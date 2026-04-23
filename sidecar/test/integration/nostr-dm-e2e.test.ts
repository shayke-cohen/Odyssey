/**
 * End-to-end integration test: nostr.dm.send → relay → nostr.dm.received
 *
 * Full stack path:
 *   WS client A
 *     → WsServer A (nostr.dm.send command)
 *     → NostrTransport A (sendDM, kind-4 encrypted publish)
 *     → LocalNostrRelay
 *     → NostrTransport B (kind-4 subscription, decrypt, dispatch)
 *     → WsServer B (broadcast nostr.dm.received)
 *     → WS client B  ✓
 *
 * Also covers multi-peer fan-out: one sender, two receivers.
 *
 * Run: bun test test/integration/nostr-dm-e2e.test.ts
 */

import { describe, test, expect, beforeAll, afterAll } from 'bun:test'
import { WsServer } from '../../src/ws-server.js'
import { NostrTransport } from '../../src/relay/nostr-transport.js'
import { generateNostrKeypair } from '../../src/relay/nostr-crypto.js'
import { LocalNostrRelay } from './local-nostr-relay.js'
import { SessionRegistry } from '../../src/stores/session-registry.js'
import { BlackboardStore } from '../../src/stores/blackboard-store.js'
import { MessageStore } from '../../src/stores/message-store.js'
import { ChatChannelStore } from '../../src/stores/chat-channel-store.js'
import { WorkspaceStore } from '../../src/stores/workspace-store.js'
import { PeerRegistry } from '../../src/stores/peer-registry.js'
import { ConnectorStore } from '../../src/stores/connector-store.js'
import { ConversationStore } from '../../src/stores/conversation-store.js'
import { ProjectStore } from '../../src/stores/project-store.js'
import { DelegationStore } from '../../src/stores/delegation-store.js'
import { TaskBoardStore } from '../../src/stores/task-board-store.js'
import type { SidecarEvent } from '../../src/types.js'
import { wsConnectDirect } from '../helpers.js'

// ── Ports (randomised to avoid collisions with other test suites) ─────────────
const BASE_PORT = 29900 + Math.floor(Math.random() * 200)
const RELAY_PORT = BASE_PORT
const WS_PORT_A   = BASE_PORT + 1
const WS_PORT_B   = BASE_PORT + 2
const WS_PORT_C   = BASE_PORT + 3   // third participant for multi-peer test

let relay: LocalNostrRelay
let serverA: WsServer
let serverB: WsServer
let serverC: WsServer

const kpA = generateNostrKeypair()
const kpB = generateNostrKeypair()
const kpC = generateNostrKeypair()

// ── Helper: build a minimal in-process WsServer ───────────────────────────────
function makeServer(port: number, keypair: { privkeyHex: string; pubkeyHex: string }, relayUrl: string): WsServer {
  let broadcastFn: (event: SidecarEvent) => void = () => {}

  const transport = new NostrTransport((event) => broadcastFn(event))
  transport.setIdentity(keypair.privkeyHex, keypair.pubkeyHex, [relayUrl])

  const ctx = {
    blackboard: new BlackboardStore(`dm-e2e-${port}-${Date.now()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    delegation: new DelegationStore(),
    taskBoard: new TaskBoardStore(`dm-e2e-${port}-${Date.now()}`),
    nostrTransport: transport,
    relayClient: { isConnected: () => false, connect: async () => {}, sendCommand: async () => ({}) } as any,
    broadcast: (event: SidecarEvent) => broadcastFn(event),
    spawnSession: async (sid: string) => ({ sessionId: sid }),
    agentDefinitions: new Map(),
    pendingBrowserBlocking: new Map(),
    pendingBrowserResults: new Map(),
  }

  const mockSessionManager = {
    createSession: async () => {},
    sendMessage: async () => {},
    resumeSession: async () => {},
    bulkResume: async () => {},
    updateSessionMode: () => {},
    forkSession: async () => {},
    pauseSession: async () => {},
    updateSessionCwd: () => {},
  } as any

  const server = new WsServer(port, mockSessionManager, ctx)

  // Wire the late-bound broadcast (mirrors index.ts pattern)
  broadcastFn = (event) => {
    server.broadcast(event)
    ctx.broadcast(event)
  }
  // Prevent double-dispatch for the ctx path
  ctx.broadcast = () => {}

  return server
}

// ── Lifecycle ─────────────────────────────────────────────────────────────────
beforeAll(async () => {
  relay = new LocalNostrRelay(RELAY_PORT)
  relay.start()
  await new Promise((r) => setTimeout(r, 100))

  const relayUrl = `ws://127.0.0.1:${RELAY_PORT}`
  serverA = makeServer(WS_PORT_A, kpA, relayUrl)
  serverB = makeServer(WS_PORT_B, kpB, relayUrl)
  serverC = makeServer(WS_PORT_C, kpC, relayUrl)

  // Allow subscriptions to register on the relay
  await new Promise((r) => setTimeout(r, 300))
})

afterAll(() => {
  serverA.close()
  serverB.close()
  serverC.close()
  relay.stop()
})

// ── Tests ─────────────────────────────────────────────────────────────────────
describe('nostr.dm.send → nostr.dm.received full stack', () => {

  test('A sends nostr.dm.send command → B receives nostr.dm.received on its WebSocket', async () => {
    const convId = `conv-${Date.now()}`

    const wsA = await wsConnectDirect(WS_PORT_A)
    const wsB = await wsConnectDirect(WS_PORT_B)

    try {
      // Drain sidecar.ready preamble
      await wsA.waitFor((m) => m.type === 'sidecar.ready', 3000)
      await wsB.waitFor((m) => m.type === 'sidecar.ready', 3000)

      // A sends a DM to B via the WebSocket command
      wsA.send({
        type: 'nostr.dm.send',
        recipientPubkeyHex: kpB.pubkeyHex,
        recipientRelays: [`ws://127.0.0.1:${RELAY_PORT}`],
        conversationId: convId,
        text: 'hello from A to B!',
        senderName: 'Sidecar-A',
      })

      // B's WebSocket client should receive nostr.dm.received
      const dm = await wsB.waitFor((m) => m.type === 'nostr.dm.received', 8000)

      expect(dm.type).toBe('nostr.dm.received')
      expect(dm.senderPubkeyHex).toBe(kpA.pubkeyHex)
      expect(dm.conversationId).toBe(convId)
      expect(dm.text).toBe('hello from A to B!')
      expect(dm.senderName).toBe('Sidecar-A')
    } finally {
      wsA.close()
      wsB.close()
    }
  }, 15_000)

  test('multi-peer fan-out: A sends to B and C simultaneously, both receive', async () => {
    const convId = `group-${Date.now()}`

    const wsA = await wsConnectDirect(WS_PORT_A)
    const wsB = await wsConnectDirect(WS_PORT_B)
    const wsC = await wsConnectDirect(WS_PORT_C)

    try {
      await Promise.all([
        wsA.waitFor((m) => m.type === 'sidecar.ready', 3000),
        wsB.waitFor((m) => m.type === 'sidecar.ready', 3000),
        wsC.waitFor((m) => m.type === 'sidecar.ready', 3000),
      ])

      const relayUrl = `ws://127.0.0.1:${RELAY_PORT}`

      // A fans out to both B and C
      wsA.send({
        type: 'nostr.dm.send',
        recipientPubkeyHex: kpB.pubkeyHex,
        recipientRelays: [relayUrl],
        conversationId: convId,
        text: 'hello group!',
        senderName: 'Sidecar-A',
      })
      wsA.send({
        type: 'nostr.dm.send',
        recipientPubkeyHex: kpC.pubkeyHex,
        recipientRelays: [relayUrl],
        conversationId: convId,
        text: 'hello group!',
        senderName: 'Sidecar-A',
      })

      // Both B and C should receive the same message
      const [dmB, dmC] = await Promise.all([
        wsB.waitFor((m) => m.type === 'nostr.dm.received' && m.conversationId === convId, 8000),
        wsC.waitFor((m) => m.type === 'nostr.dm.received' && m.conversationId === convId, 8000),
      ])

      expect(dmB.senderPubkeyHex).toBe(kpA.pubkeyHex)
      expect(dmB.conversationId).toBe(convId)
      expect(dmB.text).toBe('hello group!')

      expect(dmC.senderPubkeyHex).toBe(kpA.pubkeyHex)
      expect(dmC.conversationId).toBe(convId)
      expect(dmC.text).toBe('hello group!')
    } finally {
      wsA.close()
      wsB.close()
      wsC.close()
    }
  }, 15_000)

  test('sender does NOT receive their own DM back', async () => {
    const wsA = await wsConnectDirect(WS_PORT_A)
    try {
      await wsA.waitFor((m) => m.type === 'sidecar.ready', 3000)

      wsA.send({
        type: 'nostr.dm.send',
        recipientPubkeyHex: kpB.pubkeyHex,
        recipientRelays: [`ws://127.0.0.1:${RELAY_PORT}`],
        conversationId: `self-${Date.now()}`,
        text: 'should not echo back',
      })

      // Wait briefly; nostr.dm.received should NOT appear on A
      await new Promise((r) => setTimeout(r, 1500))
      const echo = wsA.buffer.find((m: any) => m.type === 'nostr.dm.received')
      expect(echo).toBeUndefined()
    } finally {
      wsA.close()
    }
  }, 10_000)
})
