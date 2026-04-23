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
  private directorySub: { close: () => void } | null = null
  private seenEventIds = new Map<string, true>()
  private statusInterval: ReturnType<typeof setInterval> | null = null
  private lastConnectedCount = -1
  private directoryEnabled = false
  private agentNames: string[] = []

  constructor(broadcast: (event: SidecarEvent) => void) {
    this.broadcast = broadcast
  }

  /** Call before setIdentity() to enable directory publish + subscribe. */
  configureDirectory(enabled: boolean, agentNames: string[]) {
    this.directoryEnabled = enabled
    this.agentNames = agentNames
  }

  setIdentity(privkeyHex: string, pubkeyHex: string, relays?: string[]) {
    this.privkeyHex = privkeyHex
    this.privkeyBytes = privkeyHexToBytes(privkeyHex)
    this.pubkeyHex = pubkeyHex
    if (relays && relays.length > 0) this.relays = relays
    this.startSubscription()
    if (this.directoryEnabled) {
      this.startDirectorySubscription()
      // Publish profile async — non-fatal if relays are not yet connected
      this.publishProfile(pubkeyHex.slice(0, 12)).catch(() => {})
    }
    // Emit initial status after a short delay to allow relay connections to establish
    setTimeout(() => this.emitRelayStatus(), 1000)
    // Clear any existing polling interval before starting a new one
    if (this.statusInterval !== null) clearInterval(this.statusInterval)
    this.statusInterval = setInterval(() => this.emitRelayStatus(), 15_000)
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

  /** Force-emit a relay status snapshot (exposed for testing). */
  flushRelayStatus() {
    // Reset last count so the emit always fires in tests
    this.lastConnectedCount = -1
    this.emitRelayStatus()
  }

  async sendMessage(peerName: string, envelope: OdysseyP2PEnvelope): Promise<void> {
    if (!this.privkeyBytes) throw new Error('NostrTransport: identity not set')
    const peer = this.peers.get(peerName)
    if (!peer) throw new Error(`NostrTransport: unknown peer ${peerName}`)
    const event = this.buildEvent(peerName, envelope)
    const allRelays = [...new Set([...this.relays, ...peer.relays])]
    await Promise.all(this.pool.publish(allRelays, event))
  }

  /** Send a DM to a specific pubkey+relays without requiring a named peer registry entry. */
  async sendDM(recipientPubkeyHex: string, recipientRelays: string[], envelope: OdysseyP2PEnvelope): Promise<void> {
    if (!this.privkeyBytes || !this.pubkeyHex) throw new Error('NostrTransport: identity not set')
    const content = encryptMessage(JSON.stringify(envelope), this.privkeyBytes, recipientPubkeyHex)
    const event = signNostrEvent(4, content, [['p', recipientPubkeyHex]], this.privkeyBytes)
    const allRelays = [...new Set([...this.relays, ...recipientRelays])]
    await Promise.all(this.pool.publish(allRelays, event))
  }

  /** Publish or re-publish this instance's kind-0 profile to the directory. */
  async publishProfile(displayName: string, agentNames?: string[]): Promise<void> {
    if (!this.privkeyBytes || !this.pubkeyHex) return
    const names = agentNames ?? this.agentNames
    const content = JSON.stringify({
      name: displayName,
      about: 'Odyssey',
      odyssey: { v: 1, agents: names, relays: this.relays },
    })
    const event = signNostrEvent(0, content, [['t', 'odyssey']], this.privkeyBytes)
    await Promise.all(this.pool.publish(this.relays, event))
  }

  destroy() {
    if (this.statusInterval !== null) {
      clearInterval(this.statusInterval)
      this.statusInterval = null
    }
    this.sub?.close()
    this.directorySub?.close()
    this.broadcast({ type: 'nostr.status', connectedRelays: 0, totalRelays: this.relays.length })
    this.pool.destroy()
  }

  // ── private ──────────────────────────────────────────────────────────────

  /** Exposed for testing via the public alias `emitRelayStatus`. */
  private emitRelayStatus() {
    const statusMap = this.pool.listConnectionStatus()
    let connected = 0
    for (const isConnected of statusMap.values()) {
      if (isConnected) connected++
    }
    const total = this.relays.length
    // Only broadcast when the count changes to avoid redundant events
    if (connected !== this.lastConnectedCount) {
      this.lastConnectedCount = connected
      this.broadcast({ type: 'nostr.status', connectedRelays: connected, totalRelays: total })
    }
  }

  private startSubscription() {
    if (!this.pubkeyHex) return
    this.sub?.close()
    this.sub = this.pool.subscribeMany(
      this.relays,
      { kinds: [4], '#p': [this.pubkeyHex] },
      { onevent: (event: Event) => this.handleIncomingEvent(event) },
    )
  }

  private startDirectorySubscription() {
    this.directorySub?.close()
    this.directorySub = this.pool.subscribeMany(
      this.relays,
      { kinds: [0], '#t': ['odyssey'] },
      { onevent: (event: Event) => this.handleDirectoryEvent(event) },
    )
  }

  private handleDirectoryEvent(event: Event) {
    // Skip self
    if (event.pubkey === this.pubkeyHex) return
    if (!verifyNostrEvent(event)) return
    let profile: { name?: string; odyssey?: { v?: number; agents?: string[]; relays?: string[] } }
    try {
      profile = JSON.parse(event.content)
    } catch {
      return
    }
    // Only process events that identify as Odyssey instances
    if (!profile.odyssey) return
    const displayName = profile.name ?? event.pubkey.slice(0, 16)
    const agents: string[] = profile.odyssey.agents ?? []
    const relays: string[] = profile.odyssey.relays ?? this.relays
    this.broadcast({
      type: 'nostr.directory.peer',
      pubkeyHex: event.pubkey,
      displayName,
      relays,
      agents,
      seenAt: new Date().toISOString(),
    })
  }

  private handleIncomingEvent(event: Event) {
    if (!this.privkeyBytes) return
    // Dedup — bounded LRU-ish cap at 10,000 entries
    if (this.seenEventIds.has(event.id)) return
    if (this.seenEventIds.size >= 10_000) {
      for (const k of this.seenEventIds.keys()) { this.seenEventIds.delete(k); break }
    }
    this.seenEventIds.set(event.id, true)
    // Signature check
    if (!verifyNostrEvent(event)) return
    // Decrypt regardless of whether the sender is a registered peer
    let envelope: OdysseyP2PEnvelope
    try {
      const plaintext = decryptMessage(event.content, this.privkeyBytes, event.pubkey)
      envelope = JSON.parse(plaintext)
    } catch {
      return // malformed or wrong key — ignore
    }
    // Named peer lookup (for agent delegation channels)
    const peerEntry = [...this.peers.entries()].find(([, p]) => p.pubkeyHex === event.pubkey)
    const peerName = peerEntry?.[0] ?? null
    this.dispatchEnvelope(event.pubkey, peerName, envelope)
  }

  private dispatchEnvelope(senderPubkeyHex: string, peerName: string | null, envelope: OdysseyP2PEnvelope) {
    switch (envelope.type) {
      case 'peer.message': {
        const rawPayload = envelope.payload
        const payload = (typeof rawPayload === 'object' && rawPayload !== null)
          ? rawPayload as Record<string, unknown>
          : null
        const conversationId = typeof payload?.conversationId === 'string' ? payload.conversationId : null
        const text = typeof rawPayload === 'string'
          ? rawPayload
          : (typeof payload?.text === 'string' ? payload.text : JSON.stringify(rawPayload))
        const senderName = typeof payload?.senderName === 'string' ? payload.senderName : undefined
        if (conversationId) {
          // User-to-user DM: route to a specific conversation
          this.broadcast({
            type: 'nostr.dm.received',
            senderPubkeyHex,
            conversationId,
            text,
            senderName,
          })
        } else if (peerName) {
          // Legacy agent channel message
          this.broadcast({
            type: 'peer.chat',
            channelId: `nostr:${peerName}`,
            from: envelope.from.peer,
            message: text,
          })
        }
        break
      }
      case 'peer.task.delegate':
        if (peerName) {
          this.broadcast({
            type: 'peer.delegate',
            from: envelope.from.peer,
            to: envelope.to.agent ?? 'default',
            task: (envelope.payload as any).task ?? '',
          })
        }
        break
      default:
        break
    }
  }

}
