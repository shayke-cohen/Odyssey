/**
 * Live Nostr relay integration test
 *
 * This test connects to real public Nostr relays and validates the full
 * end-to-end path: keypair generation → encryption → relay delivery → decryption.
 *
 * SKIP BEHAVIOR
 * Set SKIP_LIVE_TESTS=1 to skip this file entirely (offline / CI without outbound
 * internet access). Without that variable the test runs by default.
 *
 *   SKIP_LIVE_TESTS=1 bun test test/nostr-live-relay.test.ts   # skips
 *   bun test test/nostr-live-relay.test.ts                     # runs (needs internet)
 */

import { describe, it, expect } from 'bun:test'
import { NostrTransport } from '../src/relay/nostr-transport.js'
import { generateNostrKeypair } from '../src/relay/nostr-crypto.js'

const SKIP = process.env.SKIP_LIVE_TESTS === '1'
const LIVE_RELAYS = ['wss://relay.damus.io', 'wss://nos.lol']

async function waitForEvent(received: any[], predicate: (e: any) => boolean, timeoutMs = 15_000): Promise<any | undefined> {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    const found = received.find(predicate)
    if (found) return found
    await new Promise((r) => setTimeout(r, 500))
  }
  return undefined
}

describe.skipIf(SKIP)('NostrTransport live relay round-trip', () => {
  it(
    'delivers a legacy peer.message (string payload) → peer.chat via public relays',
    async () => {
      const alice = generateNostrKeypair()
      const bob = generateNostrKeypair()

      const bobReceived: any[] = []
      const bobTransport = new NostrTransport((event) => bobReceived.push(event))
      bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, LIVE_RELAYS)
      bobTransport.addPeer('alice', alice.pubkeyHex, LIVE_RELAYS)

      const aliceTransport = new NostrTransport((_event) => {})
      aliceTransport.setIdentity(alice.privkeyHex, alice.pubkeyHex, LIVE_RELAYS)
      aliceTransport.addPeer('bob', bob.pubkeyHex, LIVE_RELAYS)

      try {
        await new Promise((resolve) => setTimeout(resolve, 3000))

        await aliceTransport.sendMessage('bob', {
          id: `live-legacy-${Date.now()}`,
          type: 'peer.message',
          from: { peer: 'alice' },
          to: { peer: 'bob' },
          payload: 'hello from alice via real relays',
          timestamp: new Date().toISOString(),
        })

        const peerChat = await waitForEvent(bobReceived, (e) => e.type === 'peer.chat')
        if (!peerChat) {
          throw new Error('Timed out waiting for peer.chat via live relays. Relays may be down.')
        }

        expect(peerChat.type).toBe('peer.chat')
        expect(peerChat.from).toBe('alice')
        expect(peerChat.message).toContain('hello from alice via real relays')
        expect(peerChat.channelId).toBe('nostr:alice')
      } finally {
        aliceTransport.destroy()
        bobTransport.destroy()
      }
    },
    30_000,
  )

  it(
    'delivers a user DM (conversationId payload) → nostr.dm.received via public relays',
    async () => {
      const alice = generateNostrKeypair()
      const bob = generateNostrKeypair()
      const convId = `test-conv-${Date.now()}`

      const bobReceived: any[] = []
      const bobTransport = new NostrTransport((event) => bobReceived.push(event))
      bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, LIVE_RELAYS)
      // Bob does NOT register alice as a named peer — simulates receiving from a new contact

      const aliceTransport = new NostrTransport((_event) => {})
      aliceTransport.setIdentity(alice.privkeyHex, alice.pubkeyHex, LIVE_RELAYS)

      try {
        await new Promise((resolve) => setTimeout(resolve, 3000))

        // Alice sends a user DM to bob via sendDM (no named peer registration needed)
        await aliceTransport.sendDM(bob.pubkeyHex, LIVE_RELAYS, {
          id: `live-dm-${Date.now()}`,
          type: 'peer.message',
          from: { peer: alice.pubkeyHex },
          to: { peer: bob.pubkeyHex },
          payload: { conversationId: convId, text: 'hello via sendDM!', senderName: 'Alice' },
          timestamp: new Date().toISOString(),
        })

        const dm = await waitForEvent(bobReceived, (e) => e.type === 'nostr.dm.received')
        if (!dm) {
          throw new Error('Timed out waiting for nostr.dm.received via live relays. Relays may be down.')
        }

        expect(dm.type).toBe('nostr.dm.received')
        expect(dm.senderPubkeyHex).toBe(alice.pubkeyHex)
        expect(dm.conversationId).toBe(convId)
        expect(dm.text).toBe('hello via sendDM!')
        expect(dm.senderName).toBe('Alice')
      } finally {
        aliceTransport.destroy()
        bobTransport.destroy()
      }
    },
    30_000,
  )

  it(
    'delivers a user DM to multiple recipients (multi-peer fan-out) via public relays',
    async () => {
      const alice = generateNostrKeypair()
      const bob = generateNostrKeypair()
      const carol = generateNostrKeypair()
      const convId = `test-group-${Date.now()}`

      const bobReceived: any[] = []
      const carolReceived: any[] = []

      const bobTransport = new NostrTransport((event) => bobReceived.push(event))
      bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, LIVE_RELAYS)

      const carolTransport = new NostrTransport((event) => carolReceived.push(event))
      carolTransport.setIdentity(carol.privkeyHex, carol.pubkeyHex, LIVE_RELAYS)

      const aliceTransport = new NostrTransport((_event) => {})
      aliceTransport.setIdentity(alice.privkeyHex, alice.pubkeyHex, LIVE_RELAYS)

      try {
        await new Promise((resolve) => setTimeout(resolve, 3000))

        // Alice sends the same message to both bob and carol (group fan-out)
        const envelope = {
          id: `live-group-${Date.now()}`,
          type: 'peer.message' as const,
          from: { peer: alice.pubkeyHex },
          to: { peer: 'group' },
          payload: { conversationId: convId, text: 'hello group!' },
          timestamp: new Date().toISOString(),
        }
        await Promise.all([
          aliceTransport.sendDM(bob.pubkeyHex, LIVE_RELAYS, { ...envelope, to: { peer: bob.pubkeyHex } }),
          aliceTransport.sendDM(carol.pubkeyHex, LIVE_RELAYS, { ...envelope, to: { peer: carol.pubkeyHex } }),
        ])

        const [bobDm, carolDm] = await Promise.all([
          waitForEvent(bobReceived, (e) => e.type === 'nostr.dm.received'),
          waitForEvent(carolReceived, (e) => e.type === 'nostr.dm.received'),
        ])

        if (!bobDm || !carolDm) {
          throw new Error('Timed out waiting for group DMs. Relays may be down.')
        }

        expect(bobDm.conversationId).toBe(convId)
        expect(bobDm.text).toBe('hello group!')
        expect(carolDm.conversationId).toBe(convId)
        expect(carolDm.text).toBe('hello group!')
      } finally {
        aliceTransport.destroy()
        bobTransport.destroy()
        carolTransport.destroy()
      }
    },
    30_000,
  )
})
