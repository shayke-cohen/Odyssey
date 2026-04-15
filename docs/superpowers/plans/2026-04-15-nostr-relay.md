# Nostr Internet P2P Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Nostr-protocol relay as Tier 3 P2P transport so any two Odyssey instances can exchange encrypted agent messages over the internet with zero server infrastructure.

**Architecture:** Each Odyssey instance owns a secp256k1 keypair stored in Keychain; the privkey is injected into the sidecar via environment variable at startup. After two users exchange invite codes (extended with Nostr pubkey + relay list), the sidecar uses `nostr-tools` to publish NIP-44 encrypted Nostr DMs to free public relays. Incoming messages are decrypted and dispatched into the existing peer messaging pipeline.

**Tech Stack:** `nostr-tools` (Bun/TypeScript), `GigaBitcoin/secp256k1.swift` (SPM, for Swift key generation), `nostr-tools` SimplePool for multi-relay WebSocket management.

---

## File Map

**New sidecar files:**
- `sidecar/src/relay/nostr-crypto.ts` — key generation, NIP-44 encrypt/decrypt, event sign/verify (thin wrappers around nostr-tools)
- `sidecar/src/relay/nostr-transport.ts` — peer management, relay pool, send/receive routing

**Modified sidecar files:**
- `sidecar/src/types.ts` — add `nostr.addPeer`, `nostr.removePeer` commands; `nostr.status` event; `OdysseyP2PEnvelope` type
- `sidecar/src/tools/tool-context.ts` — add `nostrTransport: NostrTransport` field
- `sidecar/src/ws-server.ts` — handle `nostr.addPeer`, `nostr.removePeer` commands
- `sidecar/src/tools/messaging-tools.ts` — route `peer_delegate_task` to Nostr peers
- `sidecar/src/index.ts` — init NostrTransport, add to toolContext

**New test files:**
- `sidecar/test/nostr-crypto.test.ts`
- `sidecar/test/nostr-transport.test.ts`

**Modified Swift files:**
- `project.yml` — add `GigaBitcoin/secp256k1.swift` SPM package
- `Odyssey/Services/IdentityManager.swift` — secp256k1 keypair gen + Keychain storage + `hexString` extension
- `Odyssey/Services/SidecarManager.swift` — inject `ODYSSEY_NOSTR_PRIVKEY_HEX`, `ODYSSEY_NOSTR_PUBKEY_HEX`, `ODYSSEY_NOSTR_RELAYS` env vars
- `Odyssey/Services/SidecarProtocol.swift` — `nostrAddPeer`, `nostrRemovePeer` commands; `nostrStatus` event
- `Odyssey/App/AppState.swift` — `nostrPublicKeyHex` stored state, handle `nostr.status` event, `addNostrPeer()` helper
- `Odyssey/Services/InviteCodeGenerator.swift` — add `nostrPubkey` + `nostrRelays` optional fields to `InvitePayload`
- `Packages/OdysseyCore/Sources/OdysseyCore/Networking/InviteTypes.swift` — add `nostrPubkey` + `nostrRelays` optional fields to `InvitePayload`
- `Odyssey/Views/MainWindow/PeerNetworkView.swift` — Nostr relay status badge

---

## Task 1: Install nostr-tools

**Files:**
- Modify: `sidecar/package.json`

- [ ] **Step 1: Install dependency**

```bash
cd /Users/shayco/Odyssey/sidecar && bun add nostr-tools
```

Expected output: `bun add v1.x.x [...] + nostr-tools@2.x.x`

- [ ] **Step 2: Verify import works**

```bash
cd /Users/shayco/Odyssey/sidecar && bun -e "import { generateSecretKey, getPublicKey, nip44, finalizeEvent, verifyEvent, SimplePool } from 'nostr-tools'; console.log('ok')"
```

Expected: `ok`

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar && git add package.json bun.lockb && git commit -m "chore(sidecar): add nostr-tools dependency"
```

---

## Task 2: nostr-crypto.ts — key utilities and NIP-44 encryption

**Files:**
- Create: `sidecar/src/relay/nostr-crypto.ts`
- Create: `sidecar/test/nostr-crypto.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `sidecar/test/nostr-crypto.test.ts`:

```typescript
import { describe, it, expect } from 'bun:test'
import {
  generateNostrKeypair,
  privkeyHexToBytes,
  pubkeyHexToBytes,
  encryptMessage,
  decryptMessage,
  signNostrEvent,
  verifyNostrEvent,
} from '../src/relay/nostr-crypto.js'

describe('generateNostrKeypair', () => {
  it('returns 64-char hex privkey and 64-char hex pubkey', () => {
    const kp = generateNostrKeypair()
    expect(kp.privkeyHex).toHaveLength(64)
    expect(kp.pubkeyHex).toHaveLength(64)
    expect(kp.privkeyHex).toMatch(/^[0-9a-f]+$/)
    expect(kp.pubkeyHex).toMatch(/^[0-9a-f]+$/)
  })

  it('generates different keypairs each call', () => {
    const a = generateNostrKeypair()
    const b = generateNostrKeypair()
    expect(a.privkeyHex).not.toBe(b.privkeyHex)
  })
})

describe('NIP-44 encrypt/decrypt round-trip', () => {
  it('decrypts to original plaintext', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()
    const plaintext = '{"type":"peer.task.delegate","payload":{"task":"Review this"}}'
    const ciphertext = encryptMessage(plaintext, privkeyHexToBytes(alice.privkeyHex), bob.pubkeyHex)
    const recovered = decryptMessage(ciphertext, privkeyHexToBytes(bob.privkeyHex), alice.pubkeyHex)
    expect(recovered).toBe(plaintext)
  })

  it('produces different ciphertext each call (random nonce)', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()
    const msg = 'hello'
    const c1 = encryptMessage(msg, privkeyHexToBytes(alice.privkeyHex), bob.pubkeyHex)
    const c2 = encryptMessage(msg, privkeyHexToBytes(alice.privkeyHex), bob.pubkeyHex)
    expect(c1).not.toBe(c2)
  })

  it('throws on tampered ciphertext', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()
    const ciphertext = encryptMessage('hello', privkeyHexToBytes(alice.privkeyHex), bob.pubkeyHex)
    const tampered = ciphertext.slice(0, -4) + 'XXXX'
    expect(() => decryptMessage(tampered, privkeyHexToBytes(bob.privkeyHex), alice.pubkeyHex)).toThrow()
  })
})

describe('signNostrEvent / verifyNostrEvent', () => {
  it('verifies a signed event', () => {
    const { privkeyHex, pubkeyHex } = generateNostrKeypair()
    const event = signNostrEvent(4, 'hello', [['p', pubkeyHex]], privkeyHexToBytes(privkeyHex))
    expect(verifyNostrEvent(event)).toBe(true)
  })

  it('rejects a tampered event', () => {
    const { privkeyHex, pubkeyHex } = generateNostrKeypair()
    const event = signNostrEvent(4, 'hello', [['p', pubkeyHex]], privkeyHexToBytes(privkeyHex))
    const tampered = { ...event, content: 'tampered' }
    expect(verifyNostrEvent(tampered)).toBe(false)
  })
})
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/nostr-crypto.test.ts 2>&1 | head -20
```

Expected: `Cannot find module '../src/relay/nostr-crypto.js'`

- [ ] **Step 3: Create src/relay/ directory and implement nostr-crypto.ts**

Create `sidecar/src/relay/nostr-crypto.ts`:

```typescript
import { generateSecretKey, getPublicKey, nip44, finalizeEvent, verifyEvent } from 'nostr-tools'
import type { Event } from 'nostr-tools'

export interface NostrKeypair {
  privkeyHex: string
  pubkeyHex: string
}

export function generateNostrKeypair(): NostrKeypair {
  const privkeyBytes = generateSecretKey()
  return {
    privkeyHex: bytesToHex(privkeyBytes),
    pubkeyHex: getPublicKey(privkeyBytes),
  }
}

export function privkeyHexToBytes(hex: string): Uint8Array {
  return hexToBytes(hex)
}

export function pubkeyHexToBytes(hex: string): Uint8Array {
  return hexToBytes(hex)
}

export function encryptMessage(
  plaintext: string,
  senderPrivBytes: Uint8Array,
  recipientPubHex: string,
): string {
  const conversationKey = nip44.getConversationKey(senderPrivBytes, recipientPubHex)
  return nip44.encrypt(plaintext, conversationKey)
}

export function decryptMessage(
  ciphertext: string,
  recipientPrivBytes: Uint8Array,
  senderPubHex: string,
): string {
  const conversationKey = nip44.getConversationKey(recipientPrivBytes, senderPubHex)
  return nip44.decrypt(ciphertext, conversationKey)
}

export function signNostrEvent(
  kind: number,
  content: string,
  tags: string[][],
  privkeyBytes: Uint8Array,
): Event {
  return finalizeEvent({ kind, created_at: Math.floor(Date.now() / 1000), tags, content }, privkeyBytes)
}

export function verifyNostrEvent(event: Event): boolean {
  return verifyEvent(event)
}

// ── helpers ──────────────────────────────────────────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16)
  }
  return bytes
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('')
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/nostr-crypto.test.ts
```

Expected: `5 pass, 0 fail`

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar && git add src/relay/nostr-crypto.ts test/nostr-crypto.test.ts && git commit -m "feat(sidecar): add NIP-44 crypto utilities for Nostr relay"
```

---

## Task 3: nostr-transport.ts — relay pool, peer management, send/receive

**Files:**
- Create: `sidecar/src/relay/nostr-transport.ts`
- Create: `sidecar/test/nostr-transport.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `sidecar/test/nostr-transport.test.ts`:

```typescript
import { describe, it, expect, beforeEach } from 'bun:test'
import { NostrTransport } from '../src/relay/nostr-transport.js'
import { generateNostrKeypair, privkeyHexToBytes } from '../src/relay/nostr-crypto.js'

describe('NostrTransport peer management', () => {
  let transport: NostrTransport

  beforeEach(() => {
    transport = new NostrTransport((event) => {})
  })

  it('reports hasPeer false before addPeer', () => {
    expect(transport.hasPeer('bob')).toBe(false)
  })

  it('reports hasPeer true after addPeer', () => {
    const { pubkeyHex } = generateNostrKeypair()
    transport.addPeer('bob', pubkeyHex, [])
    expect(transport.hasPeer('bob')).toBe(true)
  })

  it('reports hasPeer false after removePeer', () => {
    const { pubkeyHex } = generateNostrKeypair()
    transport.addPeer('bob', pubkeyHex, [])
    transport.removePeer('bob')
    expect(transport.hasPeer('bob')).toBe(false)
  })

  it('throws sendMessage when identity not set', async () => {
    const { pubkeyHex } = generateNostrKeypair()
    transport.addPeer('bob', pubkeyHex, [])
    await expect(transport.sendMessage('bob', {
      id: '1', type: 'peer.message',
      from: { peer: 'alice' }, to: { peer: 'bob' },
      payload: {}, timestamp: new Date().toISOString(),
    })).rejects.toThrow('identity not set')
  })

  it('throws sendMessage for unknown peer', async () => {
    const kp = generateNostrKeypair()
    transport.setIdentity(kp.privkeyHex, kp.pubkeyHex, [])
    await expect(transport.sendMessage('nobody', {
      id: '2', type: 'peer.message',
      from: { peer: 'alice' }, to: { peer: 'nobody' },
      payload: {}, timestamp: new Date().toISOString(),
    })).rejects.toThrow('unknown peer nobody')
  })
})

describe('NostrTransport round-trip (two instances, no relay)', () => {
  it('delivers a message from alice to bob via direct relay mock', async () => {
    // We test encrypt→decrypt directly since we can't connect to live relays in tests.
    // This validates the crypto pipeline end-to-end.
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()

    const received: any[] = []
    const bobTransport = new NostrTransport((event) => received.push(event))
    bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, [])
    bobTransport.addPeer('alice', alice.pubkeyHex, [])

    const aliceTransport = new NostrTransport((event) => {})
    aliceTransport.setIdentity(alice.privkeyHex, alice.pubkeyHex, [])
    aliceTransport.addPeer('bob', bob.pubkeyHex, [])

    // Simulate: alice builds and encrypts an event, bob decrypts and dispatches it
    const envelope = {
      id: 'test-1', type: 'peer.message' as const,
      from: { peer: 'alice' }, to: { peer: 'bob' },
      payload: { text: 'hello from alice' },
      timestamp: new Date().toISOString(),
    }

    const event = aliceTransport.buildEvent('bob', envelope)
    bobTransport.simulateIncomingEvent(event)

    expect(received).toHaveLength(1)
    expect((received[0] as any).type).toBe('peer.chat')
  })
})
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/nostr-transport.test.ts 2>&1 | head -10
```

Expected: `Cannot find module '../src/relay/nostr-transport.js'`

- [ ] **Step 3: Implement nostr-transport.ts**

Create `sidecar/src/relay/nostr-transport.ts`:

```typescript
import { SimplePool } from 'nostr-tools'
import type { Event } from 'nostr-tools'
import {
  encryptMessage,
  decryptMessage,
  signNostrEvent,
  verifyNostrEvent,
  privkeyHexToBytes,
} from './nostr-crypto.js'
import type { SidecarEvent } from '../types.js'

export interface OdysseyP2PEnvelope {
  id: string
  type: 'peer.task.delegate' | 'peer.task.result' | 'peer.task.error' | 'peer.presence' | 'peer.message'
  from: { peer: string; agent?: string }
  to: { peer: string; agent?: string }
  payload: unknown
  replyTo?: string
  timestamp: string
}

const DEFAULT_RELAYS = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.nostr.band',
]

interface PeerEntry {
  pubkeyHex: string
  relays: string[]
}

export class NostrTransport {
  private pool = new SimplePool()
  private privkeyBytes: Uint8Array | null = null
  private privkeyHex: string | null = null
  private pubkeyHex: string | null = null
  private relays: string[] = DEFAULT_RELAYS
  private peers = new Map<string, PeerEntry>()
  private broadcast: (event: SidecarEvent) => void
  private sub: { close: () => void } | null = null
  private seenEventIds = new Set<string>()

  constructor(broadcast: (event: SidecarEvent) => void) {
    this.broadcast = broadcast
  }

  setIdentity(privkeyHex: string, pubkeyHex: string, relays?: string[]) {
    this.privkeyHex = privkeyHex
    this.privkeyBytes = privkeyHexToBytes(privkeyHex)
    this.pubkeyHex = pubkeyHex
    if (relays && relays.length > 0) this.relays = relays
    this.startSubscription()
    this.emitStatus()
  }

  addPeer(name: string, pubkeyHex: string, relays: string[]) {
    this.peers.set(name, { pubkeyHex, relays })
  }

  removePeer(name: string) {
    this.peers.delete(name)
  }

  hasPeer(name: string): boolean {
    return this.peers.has(name)
  }

  /** Build a signed+encrypted Nostr event (exposed for testing). */
  buildEvent(peerName: string, envelope: OdysseyP2PEnvelope): Event {
    if (!this.privkeyBytes || !this.pubkeyHex) throw new Error('NostrTransport: identity not set')
    const peer = this.peers.get(peerName)
    if (!peer) throw new Error(`NostrTransport: unknown peer ${peerName}`)
    const content = encryptMessage(JSON.stringify(envelope), this.privkeyBytes, peer.pubkeyHex)
    return signNostrEvent(4, content, [['p', peer.pubkeyHex]], this.privkeyBytes)
  }

  /** Simulate an incoming event (exposed for testing without live relays). */
  simulateIncomingEvent(event: Event) {
    this.handleIncomingEvent(event)
  }

  async sendMessage(peerName: string, envelope: OdysseyP2PEnvelope): Promise<void> {
    if (!this.privkeyBytes) throw new Error('NostrTransport: identity not set')
    const peer = this.peers.get(peerName)
    if (!peer) throw new Error(`NostrTransport: unknown peer ${peerName}`)
    const event = this.buildEvent(peerName, envelope)
    const allRelays = [...new Set([...this.relays, ...peer.relays])]
    await this.pool.publish(allRelays, event)
  }

  destroy() {
    this.sub?.close()
    this.pool.destroy()
  }

  // ── private ──────────────────────────────────────────────────────────────

  private startSubscription() {
    if (!this.pubkeyHex) return
    this.sub?.close()
    this.sub = this.pool.subscribeMany(
      this.relays,
      [{ kinds: [4], '#p': [this.pubkeyHex] }],
      { onevent: (event: Event) => this.handleIncomingEvent(event) },
    )
  }

  private handleIncomingEvent(event: Event) {
    if (!this.privkeyBytes) return
    // Dedup
    if (this.seenEventIds.has(event.id)) return
    this.seenEventIds.add(event.id)
    // Signature check
    if (!verifyNostrEvent(event)) return
    // Find the peer by pubkey
    const peerEntry = [...this.peers.entries()].find(([, p]) => p.pubkeyHex === event.pubkey)
    if (!peerEntry) return
    const [peerName, peer] = peerEntry
    let envelope: OdysseyP2PEnvelope
    try {
      const plaintext = decryptMessage(event.content, this.privkeyBytes, peer.pubkeyHex)
      envelope = JSON.parse(plaintext)
    } catch {
      return // malformed or wrong key — ignore
    }
    this.dispatchEnvelope(peerName, envelope)
  }

  private dispatchEnvelope(peerName: string, envelope: OdysseyP2PEnvelope) {
    switch (envelope.type) {
      case 'peer.message':
        this.broadcast({
          type: 'peer.chat',
          channelId: `nostr:${peerName}`,
          from: envelope.from.peer,
          message: typeof envelope.payload === 'string'
            ? envelope.payload
            : JSON.stringify(envelope.payload),
        })
        break
      case 'peer.task.delegate':
        this.broadcast({
          type: 'peer.delegate',
          from: envelope.from.peer,
          to: envelope.to.agent ?? 'default',
          task: (envelope.payload as any).task ?? '',
        })
        break
      // peer.task.result and peer.task.error are handled by pending promise resolution
      // (future: add a pending map keyed by envelope.replyTo)
      default:
        break
    }
  }

  private emitStatus() {
    // Relay connectivity status — approximate from pool connection state
    // SimplePool doesn't expose a connected count directly; emit after a short delay
    setTimeout(() => {
      this.broadcast({
        type: 'nostr.status',
        connectedRelays: this.relays.length, // optimistic; refine if pool exposes it
        totalRelays: this.relays.length,
      } as any)
    }, 2000)
  }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test test/nostr-transport.test.ts
```

Expected: `6 pass, 0 fail`

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar && git add src/relay/nostr-transport.ts test/nostr-transport.test.ts && git commit -m "feat(sidecar): add NostrTransport relay layer"
```

---

## Task 4: Update types.ts and tool-context.ts

**Files:**
- Modify: `sidecar/src/types.ts`
- Modify: `sidecar/src/tools/tool-context.ts`

- [ ] **Step 1: Add new wire types to types.ts**

In `sidecar/src/types.ts`, add these three lines to the `SidecarCommand` union (after `| { type: "peer.remove"; ... }`):

```typescript
  | { type: "nostr.addPeer"; name: string; pubkeyHex: string; relays: string[] }
  | { type: "nostr.removePeer"; name: string }
```

Add this line to the `SidecarEvent` union (after `| { type: "ios.pushRegistered"; ... }`):

```typescript
  | { type: "nostr.status"; connectedRelays: number; totalRelays: number }
```

- [ ] **Step 2: Add OdysseyP2PEnvelope export to types.ts**

Add at the end of `sidecar/src/types.ts`:

```typescript
export type { OdysseyP2PEnvelope } from './relay/nostr-transport.js'
```

- [ ] **Step 3: Add nostrTransport to ToolContext**

In `sidecar/src/tools/tool-context.ts`, add the import and field:

```typescript
// Add import at top:
import type { NostrTransport } from '../relay/nostr-transport.js'

// Add field to ToolContext interface:
  nostrTransport: NostrTransport;
```

- [ ] **Step 4: Verify TypeScript compiles**

```bash
cd /Users/shayco/Odyssey/sidecar && bun build src/index.ts --target bun --outdir /tmp/nostr-build-test 2>&1 | grep -E "error:|warning:" | head -20
```

Expected: no errors

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar && git add src/types.ts src/tools/tool-context.ts && git commit -m "feat(sidecar): add Nostr wire types and tool context field"
```

---

## Task 5: Wire up NostrTransport in index.ts and ws-server.ts

**Files:**
- Modify: `sidecar/src/index.ts`
- Modify: `sidecar/src/ws-server.ts`

- [ ] **Step 1: Init NostrTransport in index.ts**

In `sidecar/src/index.ts`, add the import and instantiation:

```typescript
// Add to existing imports:
import { NostrTransport } from './relay/nostr-transport.js'

// After line `const relayClient = new RelayClient(...)`:
const NOSTR_PRIVKEY_HEX = process.env.ODYSSEY_NOSTR_PRIVKEY_HEX ?? ''
const NOSTR_PUBKEY_HEX = process.env.ODYSSEY_NOSTR_PUBKEY_HEX ?? ''
const NOSTR_RELAYS = (process.env.ODYSSEY_NOSTR_RELAYS ?? '').split(',').filter(Boolean)
const nostrTransport = new NostrTransport((event) => broadcastFn(event))
if (NOSTR_PRIVKEY_HEX && NOSTR_PUBKEY_HEX) {
  nostrTransport.setIdentity(NOSTR_PRIVKEY_HEX, NOSTR_PUBKEY_HEX, NOSTR_RELAYS)
}
```

Add `nostrTransport` to the `toolContext` object (after `relayClient`):

```typescript
  nostrTransport,
```

- [ ] **Step 2: Handle nostr.addPeer and nostr.removePeer in ws-server.ts**

In `sidecar/src/ws-server.ts`, add these cases to the command switch (after the `case "peer.remove":` block):

```typescript
      case "nostr.addPeer":
        this.ctx.nostrTransport.addPeer(command.name, command.pubkeyHex, command.relays)
        logger.info("nostr", `Added Nostr peer "${command.name}" (${command.pubkeyHex.slice(0, 8)}…)`)
        break
      case "nostr.removePeer":
        this.ctx.nostrTransport.removePeer(command.name)
        logger.info("nostr", `Removed Nostr peer "${command.name}"`)
        break
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/shayco/Odyssey/sidecar && bun build src/index.ts --target bun --outdir /tmp/nostr-build-test2 2>&1 | grep -E "error:" | head -10
```

Expected: no errors

- [ ] **Step 4: Route outgoing peer_delegate_task to Nostr peers in messaging-tools.ts**

In `sidecar/src/tools/messaging-tools.ts`, find the `peer_delegate_task` tool handler. It currently checks `ctx.peerRegistry.findAgentOwner(args.to_agent)` to find a LAN peer. Add a Nostr fallback after that check:

```typescript
// After existing peerRegistry lookup, add:
// If the peer was not found in LAN registry but is a Nostr peer, route via Nostr
const peerName = args.to_agent.includes('@') ? args.to_agent.split('@')[1] : null
if (!remotePeer && peerName && ctx.nostrTransport.hasPeer(peerName)) {
  const envelope: OdysseyP2PEnvelope = {
    id: crypto.randomUUID(),
    type: 'peer.task.delegate',
    from: { peer: process.env.ODYSSEY_INSTANCE ?? 'local' },
    to: { peer: peerName, agent: args.to_agent.split('@')[0] },
    payload: { task: args.task, agentName: args.to_agent.split('@')[0] },
    timestamp: new Date().toISOString(),
  }
  await ctx.nostrTransport.sendMessage(peerName, envelope)
  return { success: true, routed: 'nostr', peer: peerName }
}
```

Add the import at the top of `messaging-tools.ts`:

```typescript
import type { OdysseyP2PEnvelope } from '../relay/nostr-transport.js'
```

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey/sidecar && git add src/index.ts src/ws-server.ts src/tools/messaging-tools.ts && git commit -m "feat(sidecar): wire NostrTransport into sidecar startup, commands, and outgoing task routing"
```

---

## Task 6: Add secp256k1.swift SPM package and Keychain keypair

**Files:**
- Modify: `project.yml`
- Modify: `Odyssey/Services/IdentityManager.swift`

- [ ] **Step 1: Add secp256k1.swift to project.yml**

In `project.yml`, add to the `packages:` block (after `OdysseyCore:`):

```yaml
  secp256k1:
    url: https://github.com/GigaBitcoin/secp256k1.swift
    from: "0.15.0"
```

Add to the `Odyssey` target's `dependencies:` list (after `- package: OdysseyCore`):

```yaml
      - package: secp256k1
        product: secp256k1
```

- [ ] **Step 2: Regenerate Xcode project**

```bash
cd /Users/shayco/Odyssey && xcodegen generate
```

Expected: `Generating project...` without errors. Xcode will resolve the package on next open.

- [ ] **Step 3: Add nostr keypair to IdentityManager.swift**

In `Odyssey/Services/IdentityManager.swift`, add the import and the two new methods.

Add at the top after existing imports:

```swift
import secp256k1
```

Add a private `hexString` extension right after the imports (before the class declaration):

```swift
private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
```

Add these two methods to the `IdentityManager` class (after the existing `wsToken(for:)` method):

```swift
/// Returns the secp256k1 keypair for Nostr relay, generating and storing it in Keychain on first call.
/// The key is stored under `"odyssey.nostr.<instanceName>"`.
func nostrKeypair(for instanceName: String) throws -> (privkeyHex: String, pubkeyHex: String) {
    let keychainKey = "odyssey.nostr.\(instanceName)"
    // Try to load existing 32-byte raw private key
    if let rawBytes = try? loadKeychainData(forKey: keychainKey), rawBytes.count == 32 {
        let privkey = try secp256k1.Signing.PrivateKey(rawRepresentation: rawBytes)
        let pubkeyHex = Data(privkey.publicKey.dataRepresentation.dropFirst()).hexString
        return (rawBytes.hexString, pubkeyHex)
    }
    // Generate new keypair
    let privkey = try secp256k1.Signing.PrivateKey()
    let rawBytes = Data(privkey.rawRepresentation)
    try saveKeychainData(rawBytes, forKey: keychainKey)
    let pubkeyHex = Data(privkey.publicKey.dataRepresentation.dropFirst()).hexString
    return (rawBytes.hexString, pubkeyHex)
}

/// Deletes the stored Nostr keypair (e.g. on identity reset).
func deleteNostrKeypair(for instanceName: String) {
    deleteKeychainItem(forKey: "odyssey.nostr.\(instanceName)")
}
```

- [ ] **Step 4: Build the Swift target to verify compilation**

```bash
cd /Users/shayco/Odyssey && xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | grep -E "error:|Build succeeded|Build FAILED" | head -20
```

Expected: `Build succeeded`

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey && git add project.yml Odyssey.xcodeproj/project.pbxproj Odyssey/Services/IdentityManager.swift && git commit -m "feat(swift): add secp256k1 Nostr keypair generation to IdentityManager"
```

---

## Task 7: Inject Nostr identity into sidecar via environment variables

**Files:**
- Modify: `Odyssey/Services/SidecarManager.swift`

- [ ] **Step 1: Add env var injection in SidecarManager.swift**

In `Odyssey/Services/SidecarManager.swift`, find the block that injects `ODYSSEY_WS_TOKEN` (around line 172) and add immediately after it:

```swift
// Inject Nostr keypair for internet relay
if let nostrKP = try? IdentityManager.shared.nostrKeypair(for: config.instanceName) {
    process.environment?["ODYSSEY_NOSTR_PRIVKEY_HEX"] = nostrKP.privkeyHex
    process.environment?["ODYSSEY_NOSTR_PUBKEY_HEX"] = nostrKP.pubkeyHex
}
// Inject relay list from UserDefaults (fallback: sidecar uses hardcoded defaults)
let relays = UserDefaults.standard.stringArray(forKey: AppSettings.nostrRelaysKey) ?? []
if !relays.isEmpty {
    process.environment?["ODYSSEY_NOSTR_RELAYS"] = relays.joined(separator: ",")
}
```

- [ ] **Step 2: Add AppSettings key constant**

In whatever file defines `AppSettings` constants (grep for `AppSettings.logLevelKey`), add:

```swift
static let nostrRelaysKey = "nostrRelays"
```

- [ ] **Step 3: Store nostrPublicKeyHex in AppState for invite generation**

In `Odyssey/App/AppState.swift`, find where the `@Published` properties are declared and add:

```swift
@Published var nostrPublicKeyHex: String? = nil
```

In `AppState.init()`, find the block that calls `IdentityManager.shared` for other identity setup (search for `IdentityManager.shared` in AppState.swift). Add alongside it:

```swift
if let kp = try? IdentityManager.shared.nostrKeypair(for: InstanceConfig.name) {
    nostrPublicKeyHex = kp.pubkeyHex
}
```

If AppState.init is not `@MainActor`-isolated but the property write requires it, wrap in `Task { @MainActor in self.nostrPublicKeyHex = kp.pubkeyHex }`.

- [ ] **Step 4: Build to verify**

```bash
cd /Users/shayco/Odyssey && xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | grep -E "error:|Build succeeded|Build FAILED" | head -20
```

Expected: `Build succeeded`

- [ ] **Step 5: Commit**

```bash
cd /Users/shayco/Odyssey && git add Odyssey/Services/SidecarManager.swift Odyssey/App/AppState.swift && git commit -m "feat(swift): inject Nostr identity into sidecar environment on startup"
```

---

## Task 8: SidecarProtocol.swift — add nostr commands and event

**Files:**
- Modify: `Odyssey/Services/SidecarProtocol.swift`

- [ ] **Step 1: Add nostr command cases**

In `SidecarProtocol.swift`, find the `SidecarCommand` enum and add (after `case peerRemove`):

```swift
case nostrAddPeer(name: String, pubkeyHex: String, relays: [String])
case nostrRemovePeer(name: String)
```

- [ ] **Step 2: Add encoding for new commands**

In `SidecarCommand.encodeToJSON()`, add (after the `peerRemove` case):

```swift
case .nostrAddPeer(let name, let pubkeyHex, let relays):
    return ["type": "nostr.addPeer", "name": name, "pubkeyHex": pubkeyHex, "relays": relays]
case .nostrRemovePeer(let name):
    return ["type": "nostr.removePeer", "name": name]
```

- [ ] **Step 3: Add nostrStatus event case**

In the `SidecarEvent` enum, add (after `case iosPushRegistered`):

```swift
case nostrStatus(connectedRelays: Int, totalRelays: Int)
```

- [ ] **Step 4: Add decoding for nostrStatus in IncomingWireMessage.toEvent()**

Find `IncomingWireMessage.toEvent()` and add a case:

```swift
case "nostr.status":
    guard let connected = dict["connectedRelays"] as? Int,
          let total = dict["totalRelays"] as? Int else { return nil }
    return .nostrStatus(connectedRelays: connected, totalRelays: total)
```

- [ ] **Step 5: Handle nostrStatus in AppState.handleEvent()**

In `Odyssey/App/AppState.swift`, find `handleEvent(_:)` and add:

```swift
case .nostrStatus(let connected, let total):
    // Display in PeerNetworkView via published property
    nostrRelayCount = connected
    nostrRelayTotal = total
```

Also add the two published properties near `nostrPublicKeyHex`:

```swift
@Published var nostrRelayCount: Int = 0
@Published var nostrRelayTotal: Int = 0
```

- [ ] **Step 6: Build to verify**

```bash
cd /Users/shayco/Odyssey && xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | grep -E "error:|Build succeeded|Build FAILED" | head -20
```

Expected: `Build succeeded`

- [ ] **Step 7: Commit**

```bash
cd /Users/shayco/Odyssey && git add Odyssey/Services/SidecarProtocol.swift Odyssey/App/AppState.swift && git commit -m "feat(swift): add nostr wire protocol commands and status event"
```

---

## Task 9: Extend invite payload with Nostr fields

**Files:**
- Modify: `Odyssey/Services/InviteCodeGenerator.swift`
- Modify: `Packages/OdysseyCore/Sources/OdysseyCore/Networking/InviteTypes.swift`

- [ ] **Step 1: Add optional Nostr fields to InvitePayload in InviteCodeGenerator.swift**

In `InviteCodeGenerator.swift`, the local `InvitePayload` struct (around line 19) — add two optional fields before `var sig`:

```swift
/// Nostr hex pubkey for internet relay (optional; absent in LAN-only invites).
var nostrPubkey: String?
/// Preferred Nostr relay URLs (optional).
var nostrRelays: [String]?
```

- [ ] **Step 2: Add nostrPubkey parameter to generateDevice() and populate it**

`AppState` uses `@EnvironmentObject` — there is no `AppState.shared`. Pass the value as a parameter instead.

Change the function signature of `InviteCodeGenerator.generateDevice()`:

```swift
@MainActor
static func generateDevice(
    instanceName: String,
    wsPort: Int = 9849,
    expiresIn: TimeInterval = 300,
    singleUse: Bool = true,
    nostrPubkey: String? = nil,           // ADD
    nostrRelays: [String]? = nil          // ADD
) throws -> String {
```

In the `InvitePayload` initializer inside that function (around line 120), add:

```swift
nostrPubkey: nostrPubkey,
nostrRelays: nostrRelays?.isEmpty == false ? nostrRelays : nil,
```

Update every call site that calls `InviteCodeGenerator.generateDevice(...)` to pass these — search for `generateDevice(instanceName:` in the codebase and add:

```swift
nostrPubkey: appState.nostrPublicKeyHex,
nostrRelays: UserDefaults.standard.stringArray(forKey: AppSettings.nostrRelaysKey)
```

where `appState` is the `AppState` instance available at the call site (via `@EnvironmentObject` or passed in).

- [ ] **Step 3: Add optional Nostr fields to InviteTypes.swift (OdysseyCore)**

In `Packages/OdysseyCore/Sources/OdysseyCore/Networking/InviteTypes.swift`, add to `InvitePayload` (after `singleUse`, before `sig`):

```swift
/// Nostr hex pubkey for internet relay (optional; v2+ only).
public let nostrPubkey: String?
/// Preferred Nostr relay URLs (optional; v2+ only).
public let nostrRelays: [String]?
```

Update the public `init` to include these params with defaults:

```swift
public init(
    v: Int, type: String, userPublicKey: String, displayName: String,
    tlsCertDER: String, wsToken: String, wsPort: Int, hints: InviteHints,
    exp: TimeInterval, singleUse: Bool,
    nostrPubkey: String? = nil, nostrRelays: [String]? = nil,
    sig: String
) {
    self.v = v; self.type = type; self.userPublicKey = userPublicKey
    self.displayName = displayName; self.tlsCertDER = tlsCertDER
    self.wsToken = wsToken; self.wsPort = wsPort; self.hints = hints
    self.exp = exp; self.singleUse = singleUse
    self.nostrPubkey = nostrPubkey; self.nostrRelays = nostrRelays
    self.sig = sig
}
```

- [ ] **Step 4: Wire up Nostr peer registration when accepting an invite**

In `AppState.swift`, find the place where a successfully accepted invite is processed (look for where `PeerCredentials` is stored or where `SidecarCommand.peerRegister` is sent after pairing). After that logic, add:

```swift
// If the invite includes Nostr identity, register as a Nostr peer too
if let nostrPubkey = acceptedPayload.nostrPubkey {
    let relays = acceptedPayload.nostrRelays ?? []
    Task {
        try? await sidecarManager.send(.nostrAddPeer(
            name: acceptedPayload.displayName,
            pubkeyHex: nostrPubkey,
            relays: relays
        ))
    }
}
```

- [ ] **Step 5: Build to verify**

```bash
cd /Users/shayco/Odyssey && xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | grep -E "error:|Build succeeded|Build FAILED" | head -20
```

Expected: `Build succeeded`

- [ ] **Step 6: Commit**

```bash
cd /Users/shayco/Odyssey && git add Odyssey/Services/InviteCodeGenerator.swift Packages/OdysseyCore/Sources/OdysseyCore/Networking/InviteTypes.swift Odyssey/App/AppState.swift && git commit -m "feat(swift): extend invite payload with Nostr pubkey and relay list"
```

---

## Task 10: PeerNetworkView — Nostr relay status indicator

**Files:**
- Modify: `Odyssey/Views/MainWindow/PeerNetworkView.swift`

- [ ] **Step 1: Add Nostr status badge to PeerNetworkView**

In `PeerNetworkView.swift`, find the view header or toolbar area and add a small relay status indicator. Locate where the view body starts (look for `var body: some View`) and add somewhere visible (e.g. top of the list or in a toolbar):

```swift
// Add this in the view where peer network header/status is shown:
if appState.nostrRelayTotal > 0 {
    HStack(spacing: 4) {
        Circle()
            .fill(appState.nostrRelayCount > 0 ? Color.green : Color.orange)
            .frame(width: 7, height: 7)
        Text(appState.nostrRelayCount > 0
             ? "\(appState.nostrRelayCount)/\(appState.nostrRelayTotal) relays"
             : "Connecting to relays…")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .accessibilityIdentifier("peerNetwork.nostrRelayStatus")
}
```

- [ ] **Step 2: Build and visually verify**

```bash
cd /Users/shayco/Odyssey && xcodebuild -scheme Odyssey -destination 'platform=macOS' build 2>&1 | grep -E "error:|Build succeeded|Build FAILED" | head -20
```

Open the app, go to Peer Network view. After sidecar starts you should see the relay status badge appear within ~2 seconds.

- [ ] **Step 3: Commit**

```bash
cd /Users/shayco/Odyssey && git add Odyssey/Views/MainWindow/PeerNetworkView.swift && git commit -m "feat(swift): add Nostr relay status indicator to PeerNetworkView"
```

---

## Task 11: End-to-end verification

- [ ] **Step 1: Run full sidecar test suite**

```bash
cd /Users/shayco/Odyssey/sidecar && bun test
```

Expected: all tests pass including the two new test files.

- [ ] **Step 2: Manual relay connectivity check**

Start the app. In a terminal:

```bash
ODYSSEY_NOSTR_PUBKEY_HEX=<your-pubkey> ODYSSEY_NOSTR_PRIVKEY_HEX=<your-privkey> \
  bun run /Users/shayco/Odyssey/sidecar/src/index.ts &
# watch logs for "nostr" category entries
tail -f ~/.odyssey/instances/default/logs/sidecar.log | grep nostr
```

Expected within 5s: log line `[nostr] NostrTransport connected to relays` or similar from the `emitStatus` call.

- [ ] **Step 3: Two-instance invite round-trip**

On Machine A: generate invite (Settings → Devices → copy invite link). Confirm invite JSON includes `nostrPubkey` field when decoded from base64.

On Machine B: accept invite. In sidecar logs: confirm `[nostr] Added Nostr peer "Machine A"`.

- [ ] **Step 4: Send a test message via Nostr relay**

From Machine B's sidecar REPL or test script:

```typescript
// sidecar/scripts/test-nostr-send.ts
import { NostrTransport } from '../src/relay/nostr-transport.js'
// ... set identity + add peer, then:
await transport.sendMessage('Machine A', {
  id: crypto.randomUUID(),
  type: 'peer.message',
  from: { peer: 'Machine B' },
  to: { peer: 'Machine A' },
  payload: { text: 'Hello over Nostr!' },
  timestamp: new Date().toISOString(),
})
console.log('sent')
```

On Machine A: confirm `peer.chat` event arrives in the sidecar log.

- [ ] **Step 5: Final commit of design doc**

```bash
cd /Users/shayco/Odyssey && git add docs/superpowers/plans/2026-04-15-nostr-relay.md docs/superpowers/specs/2026-04-15-nostr-relay-design.md 2>/dev/null; git commit -m "docs: add Nostr relay design spec and implementation plan"
```

---

## Notes for Executor

- **Swift 6 strict concurrency**: All `@MainActor` access to `AppState` must be from `@MainActor` context. Wrap `Task { @MainActor in ... }` where needed.
- **`AppState.shared`**: If no static `shared` exists, thread `nostrPublicKeyHex` through `InviteCodeGenerator.generateDevice(nostrPubkey:)` parameter instead.
- **Bun + WebSocket**: `nostr-tools` SimplePool uses the global `WebSocket`. Bun provides it natively — no polyfill needed.
- **Testing Nostr relay connectivity**: Live relay tests require internet access. Unit tests use `simulateIncomingEvent()` to avoid network dependency.
- **Relay outage handling**: If all relays are unreachable, `sendMessage` will throw. The caller should handle this gracefully (log + notify user).
- **Mac-to-Mac invite acceptance UI gap**: The current app only has an iOS pairing flow for accepting invites. A "Connect to Peer" UI (e.g. a text field in PeerNetworkView to paste an invite from another Mac) is needed to complete the flow end-to-end. This is out of scope for this plan but required before the feature is user-visible. Track as a follow-up task.
- **`OdysseyP2PEnvelope` import in messaging-tools.ts**: If the type import creates a circular dependency, export it from `types.ts` directly and import from there.
