/**
 * Unit tests for SessionManager memory cleanup.
 * Verifies that turnHistory accumulates completed turns (up to 50) and is
 * fully cleared when pauseSession is called.
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { SessionManager } from "../../src/session-manager.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { DelegationStore } from "../../src/stores/delegation-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

const MOCK_CONFIG: AgentConfig = {
  name: "TestAgent",
  systemPrompt: "",
  allowedTools: [],
  mcpServers: [],
  model: "claude-sonnet-4-6",
  workingDirectory: "/tmp",
  skills: [],
  provider: "mock",
};

function buildCtx(broadcast: (e: SidecarEvent) => void = () => {}): ToolContext {
  const suffix = `${Date.now()}-${Math.random()}`;
  return {
    blackboard: new BlackboardStore(`cleanup-test-${suffix}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    nostrTransport: new NostrTransport(() => {}),
    delegation: new DelegationStore(),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast,
    spawnSession: async (sid, config, prompt) => {
      return { sessionId: sid };
    },
    agentDefinitions: new Map<string, AgentConfig>(),
    pendingBrowserBlocking: new Map(),
    pendingBrowserResults: new Map(),
  };
}

describe("SessionManager turnHistory cleanup", () => {
  let registry: SessionRegistry;
  let sm: SessionManager;

  beforeEach(() => {
    registry = new SessionRegistry();
    const ctx = { ...buildCtx(), sessions: registry };
    sm = new SessionManager(() => {}, registry, ctx);
  });

  test("records one completed turn after sendMessage", async () => {
    await sm.createSession("s1", MOCK_CONFIG);
    await sm.sendMessage("s1", "hello");
    expect(sm.getTurnHistory("s1")).toHaveLength(1);
    expect(sm.getTurnHistory("s1")[0].status).toBe("completed");
  });

  test("accumulates turns across multiple sends on same session", async () => {
    await sm.createSession("s1", MOCK_CONFIG);
    await sm.sendMessage("s1", "first");
    await sm.sendMessage("s1", "second");
    expect(sm.getTurnHistory("s1")).toHaveLength(2);
  });

  test("clears turnHistory after pauseSession", async () => {
    await sm.createSession("s1", MOCK_CONFIG);
    await sm.sendMessage("s1", "working");
    await sm.pauseSession("s1");
    expect(sm.getTurnHistory("s1")).toHaveLength(0);
  });

  test("pauseSession on session with no sends leaves history empty", async () => {
    await sm.createSession("s1", MOCK_CONFIG);
    await sm.pauseSession("s1");
    expect(sm.getTurnHistory("s1")).toHaveLength(0);
  });

  test("caps history at 50 turns to prevent memory leaks", async () => {
    await sm.createSession("s1", MOCK_CONFIG);
    for (let i = 0; i < 55; i++) {
      await sm.sendMessage("s1", `msg-${i}`);
    }
    expect(sm.getTurnHistory("s1").length).toBeLessThanOrEqual(50);
  });
});
