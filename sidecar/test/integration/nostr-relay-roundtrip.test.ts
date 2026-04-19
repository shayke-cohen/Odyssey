/**
 * Integration test: iOS→Mac sidecar command flow via local Nostr relay.
 *
 * Simulates the full NIP-44 encrypted command channel between the iOS app and
 * the Mac sidecar:
 *
 *   iOS (peer A)  →  local Nostr relay  →  Mac (peer B)
 *   Mac response  →  local Nostr relay  →  iOS (peer A)
 *
 * Uses the same NIP-44 encryption and NIP-01 event format that the Swift
 * NostrSidecarBridge and NostrRelayManager use.
 *
 * Run: bun test test/integration/nostr-relay-roundtrip.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from 'bun:test'
import { LocalNostrRelay } from './local-nostr-relay.js'
import {
  generateNostrKeypair,
  encryptMessage,
  decryptMessage,
  signNostrEvent,
  privkeyHexToBytes,
} from '../../src/relay/nostr-crypto.js'

const RELAY_PORT = 29750 + Math.floor(Math.random() * 200)
const LOCAL_RELAY = `ws://127.0.0.1:${RELAY_PORT}`

let relay: LocalNostrRelay

beforeAll(() => {
  relay = new LocalNostrRelay(RELAY_PORT)
  relay.start()
})

afterAll(() => {
  relay.stop()
})

/** Subscribe to events addressed to `recipientPubkey` on the local relay. */
function subscribeToRelay(
  recipientPubkey: string,
  onEvent: (event: any) => void,
): { ws: WebSocket; close: () => void } {
  const ws = new WebSocket(LOCAL_RELAY)
  const subId = `sub-${Math.random().toString(36).slice(2)}`
  ws.onopen = () => {
    ws.send(JSON.stringify(['REQ', subId, { kinds: [4], '#p': [recipientPubkey] }]))
  }
  ws.onmessage = (msg) => {
    try {
      const arr = JSON.parse(msg.data as string)
      if (Array.isArray(arr) && arr[0] === 'EVENT' && arr[1] === subId) {
        onEvent(arr[2])
      }
    } catch { /* ignore */ }
  }
  return { ws, close: () => ws.close() }
}

/** Publish a NIP-44 encrypted kind-4 event from `senderPrivHex` to `recipientPubHex`. */
async function publishEncrypted(
  content: string,
  senderPrivHex: string,
  recipientPubHex: string,
): Promise<void> {
  const privBytes = privkeyHexToBytes(senderPrivHex)
  const encrypted = encryptMessage(content, privBytes, recipientPubHex)
  const event = signNostrEvent(4, encrypted, [['p', recipientPubHex]], privBytes)
  const ws = new WebSocket(LOCAL_RELAY)
  await new Promise<void>((resolve) => { ws.onopen = () => resolve() })
  ws.send(JSON.stringify(['EVENT', event]))
  await new Promise<void>((resolve) => setTimeout(resolve, 50))
  ws.close()
}

/** Decrypt a NIP-44 kind-4 event and return the plaintext. */
function decryptEvent(event: any, recipientPrivHex: string): string {
  const privBytes = privkeyHexToBytes(recipientPrivHex)
  return decryptMessage(event.content, privBytes, event.pubkey)
}

// ── Tests ────────────────────────────────────────────────────────────────────

describe('Local Nostr relay NIP-44 roundtrip', () => {

  test('relay delivers a kind-4 event to the correct recipient', async () => {
    const ios = generateNostrKeypair()
    const mac = generateNostrKeypair()

    const received: any[] = []
    const sub = subscribeToRelay(mac.pubkeyHex, (ev) => received.push(ev))

    // Give subscription time to register
    await new Promise((r) => setTimeout(r, 100))

    await publishEncrypted('hello from iOS', ios.privkeyHex, mac.pubkeyHex)

    const deadline = Date.now() + 3000
    while (Date.now() < deadline && received.length === 0) {
      await new Promise((r) => setTimeout(r, 50))
    }

    sub.close()
    expect(received.length).toBeGreaterThan(0)
    expect(received[0].kind).toBe(4)
    expect(received[0].pubkey).toBe(ios.pubkeyHex)
  })

  test('NIP-44 encrypted SidecarCommand survives relay roundtrip', async () => {
    const ios = generateNostrKeypair()
    const mac = generateNostrKeypair()

    const sessionId = `test-session-${Date.now()}`
    const command = {
      type: 'session.message',
      sessionId,
      text: 'ping from iOS via local relay',
    }

    const macReceived: any[] = []
    const sub = subscribeToRelay(mac.pubkeyHex, (ev) => macReceived.push(ev))
    await new Promise((r) => setTimeout(r, 100))

    await publishEncrypted(JSON.stringify(command), ios.privkeyHex, mac.pubkeyHex)

    const deadline = Date.now() + 3000
    while (Date.now() < deadline && macReceived.length === 0) {
      await new Promise((r) => setTimeout(r, 50))
    }
    sub.close()

    expect(macReceived.length).toBeGreaterThan(0)
    const plaintext = decryptEvent(macReceived[0], mac.privkeyHex)
    const decoded = JSON.parse(plaintext)
    expect(decoded.type).toBe('session.message')
    expect(decoded.sessionId).toBe(sessionId)
    expect(decoded.text).toBe('ping from iOS via local relay')
  })

  test('encrypted SidecarEvent reply routes back to iOS correctly', async () => {
    const ios = generateNostrKeypair()
    const mac = generateNostrKeypair()

    const sessionId = `reply-test-${Date.now()}`
    const responseEvent = {
      type: 'stream.token',
      sessionId,
      token: 'pong',
    }

    // iOS subscribes to receive Mac's reply
    const iosReceived: any[] = []
    const sub = subscribeToRelay(ios.pubkeyHex, (ev) => iosReceived.push(ev))
    await new Promise((r) => setTimeout(r, 100))

    // Mac publishes reply to iOS
    await publishEncrypted(JSON.stringify(responseEvent), mac.privkeyHex, ios.pubkeyHex)

    const deadline = Date.now() + 3000
    while (Date.now() < deadline && iosReceived.length === 0) {
      await new Promise((r) => setTimeout(r, 50))
    }
    sub.close()

    expect(iosReceived.length).toBeGreaterThan(0)
    const plaintext = decryptEvent(iosReceived[0], ios.privkeyHex)
    const decoded = JSON.parse(plaintext)
    expect(decoded.type).toBe('stream.token')
    expect(decoded.sessionId).toBe(sessionId)
    expect(decoded.token).toBe('pong')
  })

  test('event addressed to wrong pubkey is NOT delivered to recipient', async () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()
    const charlie = generateNostrKeypair()

    const bobReceived: any[] = []
    const sub = subscribeToRelay(bob.pubkeyHex, (ev) => bobReceived.push(ev))
    await new Promise((r) => setTimeout(r, 100))

    // Alice sends to Charlie — Bob should NOT receive it
    await publishEncrypted('not for bob', alice.privkeyHex, charlie.pubkeyHex)
    await new Promise((r) => setTimeout(r, 500))

    sub.close()
    expect(bobReceived.length).toBe(0)
  })
})
