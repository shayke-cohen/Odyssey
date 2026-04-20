/**
 * E2E iOS pairing test — simulates the full iOS↔Mac communication stack.
 *
 * Architecture under test:
 *
 *   iOS emulator  ──NIP-44──►  local Nostr relay  ──►  MacRelayBridge  ──►  WsServer
 *   WsServer      ──broadcast──►  MacRelayBridge   ──NIP-44──►  relay  ──►  iOS emulator
 *
 * MacRelayBridge is the TypeScript equivalent of NostrEventRelay.swift:
 *   - Subscribes to local relay with Mac's keypair
 *   - Decrypts incoming events, injects into WsServer as nostr.injectCommand
 *   - Intercepts WsServer broadcasts, encrypts, and routes back to iOS via relay
 *
 * Tests:
 *   1. pairing.hello → trustedIosNpubs updated → pairing.confirmed roundtrip to iOS
 *   2. session.create via Nostr reaches sidecar sessionManager
 *   3. session.message via Nostr reaches sidecar; stream.token routes back to iOS
 *
 * Run: bun test test/integration/ios-pairing-e2e.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { WsServer } from "../../src/ws-server.js";
import { LocalNostrRelay } from "./local-nostr-relay.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { DelegationStore } from "../../src/stores/delegation-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig } from "../../src/types.js";
import {
  generateNostrKeypair,
  encryptMessage,
  decryptMessage,
  signNostrEvent,
  privkeyHexToBytes,
  type NostrKeypair,
} from "../../src/relay/nostr-crypto.js";

// ── Port allocation ───────────────────────────────────────────────────────────

const BASE = 27800 + Math.floor(Math.random() * 500);
const RELAY_PORT = BASE;
const WS_PORT = BASE + 600;
const LOCAL_RELAY_URL = `ws://127.0.0.1:${RELAY_PORT}`;

// ── Shared state ──────────────────────────────────────────────────────────────

let relay: LocalNostrRelay;
let wsServer: WsServer;
let macBridge: MacRelayBridge;

let sessionCreateCalls: Array<{ id: string; config: any }> = [];
let sessionMessageCalls: Array<{ id: string; text: string }> = [];

// ── MacRelayBridge ────────────────────────────────────────────────────────────
//
// TypeScript mirror of NostrEventRelay.swift:
//   - Subscribes to local relay with Mac keypair (kind-4 events tagged #p=macPubkey)
//   - Decrypts each event, injects into WsServer as nostr.injectCommand
//   - Listens to all WsServer broadcasts; routes session/pairing replies back to iOS

class MacRelayBridge {
  readonly keypair: NostrKeypair;
  private relayUrl: string;
  private wsPort: number;
  private sidecarWs: WebSocket | null = null;
  private relayWs: WebSocket | null = null;
  // sessionId/conversationId → iOS sender pubkeyHex (mirrors Swift nostrSessions)
  private nostrSessions = new Map<string, string>();
  // All sidecar messages received by the bridge (for assertions)
  received: any[] = [];

  constructor(relayUrl: string, wsPort: number) {
    this.keypair = generateNostrKeypair();
    this.relayUrl = relayUrl;
    this.wsPort = wsPort;
  }

  async start(): Promise<void> {
    await this.connectToSidecar();
    await this.subscribeToRelay();
  }

  private connectToSidecar(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const ws = new WebSocket(`ws://127.0.0.1:${this.wsPort}`);
      this.sidecarWs = ws;

      const timeout = setTimeout(
        () => reject(new Error("MacRelayBridge: sidecar connect timeout")),
        8000,
      );

      ws.onmessage = (evt: MessageEvent) => {
        const msg = JSON.parse(
          typeof evt.data === "string" ? evt.data : "{}",
        );
        this.received.push(msg);
        if (msg.type === "sidecar.ready") {
          clearTimeout(timeout);
          resolve();
        }
        this.interceptSidecarMessage(msg);
      };

      ws.onerror = () => {
        clearTimeout(timeout);
        reject(new Error("MacRelayBridge: sidecar WebSocket error"));
      };
    });
  }

  private subscribeToRelay(): Promise<void> {
    const subId = `mac-${Math.random().toString(36).slice(2)}`;
    return new Promise<void>((resolve) => {
      const ws = new WebSocket(this.relayUrl);
      this.relayWs = ws;
      ws.onopen = () => {
        ws.send(
          JSON.stringify([
            "REQ",
            subId,
            { kinds: [4], "#p": [this.keypair.pubkeyHex] },
          ]),
        );
        resolve();
      };
      ws.onmessage = (evt: MessageEvent) => {
        try {
          const arr = JSON.parse(evt.data as string);
          if (
            Array.isArray(arr) &&
            arr[0] === "EVENT" &&
            arr[1] === subId
          ) {
            this.handleIncomingNostrEvent(arr[2]);
          }
        } catch {
          /* ignore */
        }
      };
    });
  }

  // Decrypt an incoming iOS→Mac Nostr event and inject into sidecar.
  private handleIncomingNostrEvent(event: any): void {
    const privBytes = privkeyHexToBytes(this.keypair.privkeyHex);
    let plaintext: string;
    try {
      plaintext = decryptMessage(event.content, privBytes, event.pubkey);
    } catch {
      return;
    }

    let command: any;
    try {
      command = JSON.parse(plaintext);
    } catch {
      return;
    }

    const iosPubkey: string = event.pubkey;

    // Track session→iOS mapping for reply routing (mirrors Swift nostrSessions)
    if (command.type === "session.create")
      this.nostrSessions.set(command.conversationId, iosPubkey);
    if (command.type === "session.message")
      this.nostrSessions.set(command.sessionId, iosPubkey);
    if (command.type === "pairing.hello")
      this.nostrSessions.set("__pairing__", iosPubkey);

    // Forward to sidecar as nostr.injectCommand
    this.sidecarWs?.send(
      JSON.stringify({ type: "nostr.injectCommand", command }),
    );
  }

  // Forward a sidecar broadcast event back to the originating iOS device.
  private interceptSidecarMessage(msg: any): void {
    const iosPubkey =
      this.nostrSessions.get(msg.sessionId) ??
      this.nostrSessions.get(msg.conversationId) ??
      (msg.type === "pairing.confirmed"
        ? this.nostrSessions.get("__pairing__")
        : undefined);

    if (!iosPubkey) return;

    const privBytes = privkeyHexToBytes(this.keypair.privkeyHex);
    const encrypted = encryptMessage(JSON.stringify(msg), privBytes, iosPubkey);
    const nostrEvent = signNostrEvent(
      4,
      encrypted,
      [["p", iosPubkey]],
      privBytes,
    );

    const ws = new WebSocket(this.relayUrl);
    ws.onopen = () => {
      ws.send(JSON.stringify(["EVENT", nostrEvent]));
      setTimeout(() => ws.close(), 100);
    };
  }

  stop(): void {
    this.relayWs?.close();
    this.sidecarWs?.close();
  }
}

// ── iOS emulator helpers ──────────────────────────────────────────────────────

/** Subscribe to relay events addressed to `pubkey`; returns a close() handle. */
function iosSubscribe(
  pubkey: string,
  onEvent: (event: any) => void,
): { close: () => void } {
  const ws = new WebSocket(LOCAL_RELAY_URL);
  const subId = `ios-${Math.random().toString(36).slice(2)}`;
  ws.onopen = () =>
    ws.send(JSON.stringify(["REQ", subId, { kinds: [4], "#p": [pubkey] }]));
  ws.onmessage = (evt: MessageEvent) => {
    try {
      const arr = JSON.parse(evt.data as string);
      if (Array.isArray(arr) && arr[0] === "EVENT" && arr[1] === subId)
        onEvent(arr[2]);
    } catch {
      /* ignore */
    }
  };
  return { close: () => ws.close() };
}

/** Send an NIP-44 encrypted signed kind-4 event from iOS to Mac via the relay. */
async function iosSend(
  plaintext: string,
  iosPrivHex: string,
  macPubHex: string,
): Promise<void> {
  const privBytes = privkeyHexToBytes(iosPrivHex);
  const encrypted = encryptMessage(plaintext, privBytes, macPubHex);
  const event = signNostrEvent(4, encrypted, [["p", macPubHex]], privBytes);
  const ws = new WebSocket(LOCAL_RELAY_URL);
  await new Promise<void>((r) => {
    ws.onopen = () => r();
  });
  ws.send(JSON.stringify(["EVENT", event]));
  await new Promise((r) => setTimeout(r, 60));
  ws.close();
}

/** Decrypt an iOS-received relay event; returns the parsed SidecarEvent. */
function iosDecrypt(event: any, iosPrivHex: string): any {
  const privBytes = privkeyHexToBytes(iosPrivHex);
  return JSON.parse(decryptMessage(event.content, privBytes, event.pubkey));
}

/** Wait up to `ms` ms until `pred` is true. */
async function waitUntil(
  pred: () => boolean,
  ms = 3000,
  tick = 50,
): Promise<void> {
  const deadline = Date.now() + ms;
  while (!pred() && Date.now() < deadline)
    await new Promise((r) => setTimeout(r, tick));
}

// ── Test setup ────────────────────────────────────────────────────────────────

beforeAll(async () => {
  sessionCreateCalls = [];
  sessionMessageCalls = [];

  relay = new LocalNostrRelay(RELAY_PORT);
  relay.start();

  const mockSessionManager = {
    createSession: async (id: string, config: any) =>
      sessionCreateCalls.push({ id, config }),
    sendMessage: async (id: string, text: string) =>
      sessionMessageCalls.push({ id, text }),
    resumeSession: async () => {},
    bulkResume: async () => {},
    updateSessionMode: () => {},
    forkSession: async () => {},
    pauseSession: async () => {},
    updateSessionCwd: () => {},
  } as any;

  const ctx: ToolContext = {
    blackboard: new BlackboardStore(`e2e-pairing-${Date.now()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    delegation: new DelegationStore(),
    taskBoard: new TaskBoardStore(`e2e-pairing-${Date.now()}`),
    nostrTransport: new NostrTransport(() => {}),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: () => {},
    spawnSession: async (sid) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
    pendingBrowserBlocking: new Map(),
    pendingBrowserResults: new Map(),
  };

  wsServer = new WsServer(WS_PORT, mockSessionManager, ctx);
  macBridge = new MacRelayBridge(LOCAL_RELAY_URL, WS_PORT);
  await macBridge.start();
});

afterAll(() => {
  macBridge.stop();
  wsServer.close();
  relay.stop();
});

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("iOS E2E pairing via local Nostr relay", () => {
  test("pairing.hello → trustedIosNpubs updated; pairing.confirmed delivered to iOS", async () => {
    const ios = generateNostrKeypair();

    // iOS subscribes to receive Mac's reply
    const iosReceived: any[] = [];
    const sub = iosSubscribe(ios.pubkeyHex, (ev) => iosReceived.push(ev));
    await new Promise((r) => setTimeout(r, 120));

    // iOS sends pairing.hello (NIP-44 encrypted to Mac's pubkey)
    await iosSend(
      JSON.stringify({
        type: "pairing.hello",
        iosNpub: ios.pubkeyHex,
        displayName: "Test iPhone 17",
      }),
      ios.privkeyHex,
      macBridge.keypair.pubkeyHex,
    );

    // Bridge should inject into sidecar; sidecar broadcasts pairing.confirmed;
    // bridge routes it back to iOS via relay.
    await waitUntil(
      () =>
        macBridge.received.some((m) => m.type === "pairing.confirmed") &&
        iosReceived.length > 0,
      4000,
    );
    sub.close();

    // 1. Sidecar received and processed pairing.hello
    const confirmed = macBridge.received.find(
      (m) => m.type === "pairing.confirmed",
    );
    expect(confirmed).toBeDefined();

    // 2. iOS received pairing.confirmed decrypted from Mac via relay
    expect(iosReceived.length).toBeGreaterThan(0);
    const decoded = iosDecrypt(iosReceived[0], ios.privkeyHex);
    expect(decoded.type).toBe("pairing.confirmed");
  });

  test("session.create via Nostr relay reaches sidecar sessionManager", async () => {
    const ios = generateNostrKeypair();
    const conversationId = `e2e-conv-${Date.now()}`;

    await iosSend(
      JSON.stringify({
        type: "session.create",
        conversationId,
        agentConfig: {
          provider: "mock",
          model: "mock",
          systemPrompt: "You are a test agent",
          name: "TestAgent",
          skills: [],
          mcpServers: [],
        },
      }),
      ios.privkeyHex,
      macBridge.keypair.pubkeyHex,
    );

    await waitUntil(
      () => sessionCreateCalls.some((c) => c.id === conversationId),
      3000,
    );

    const created = sessionCreateCalls.find((c) => c.id === conversationId);
    expect(created).toBeDefined();
    expect(created?.config.name).toBe("TestAgent");
  });

  test("session.message via Nostr relay reaches sidecar; stream.token routes back to iOS", async () => {
    const ios = generateNostrKeypair();
    const sessionId = `e2e-session-${Date.now()}`;

    // iOS subscribes for responses
    const iosReceived: any[] = [];
    const sub = iosSubscribe(ios.pubkeyHex, (ev) => iosReceived.push(ev));
    await new Promise((r) => setTimeout(r, 120));

    // First session.create to register the session→iOS mapping in MacRelayBridge
    await iosSend(
      JSON.stringify({
        type: "session.create",
        conversationId: sessionId,
        agentConfig: {
          provider: "mock",
          model: "mock",
          systemPrompt: "",
          name: "T",
          skills: [],
          mcpServers: [],
        },
      }),
      ios.privkeyHex,
      macBridge.keypair.pubkeyHex,
    );
    await new Promise((r) => setTimeout(r, 200));

    // iOS sends session.message
    await iosSend(
      JSON.stringify({
        type: "session.message",
        sessionId,
        text: "Hello from iOS via Nostr",
        attachments: [],
        planMode: false,
      }),
      ios.privkeyHex,
      macBridge.keypair.pubkeyHex,
    );

    // Wait for sidecar to process the message
    await waitUntil(
      () => sessionMessageCalls.some((c) => c.id === sessionId),
      3000,
    );

    const sent = sessionMessageCalls.find((c) => c.id === sessionId);
    expect(sent).toBeDefined();
    expect(sent?.text).toBe("Hello from iOS via Nostr");

    // Simulate sidecar broadcasting stream.token back (mirrors real Claude streaming)
    wsServer.broadcast({ type: "stream.token", sessionId, token: "hello iOS" } as any);

    // Mac bridge should intercept stream.token, encrypt, and route back to iOS via relay
    await waitUntil(() => iosReceived.length > 0, 2000);
    sub.close();

    expect(iosReceived.length).toBeGreaterThan(0);
    const decoded = iosDecrypt(iosReceived[0], ios.privkeyHex);
    expect(decoded.type).toBe("stream.token");
    expect(decoded.sessionId).toBe(sessionId);
    expect(decoded.token).toBe("hello iOS");
  });
});
