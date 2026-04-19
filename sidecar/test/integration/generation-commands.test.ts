/**
 * Integration tests for WS commands generate.skill and generate.template.
 *
 * Boots a real WsServer on a random port with a mocked Claude Agent SDK.
 * No real LLM calls are made — the mock returns deterministic JSON.
 *
 * IMPORTANT: mock.module must be called before any import that pulls in
 * ws-server.ts (which top-level imports @anthropic-ai/claude-agent-sdk).
 */
import { mock, describe, test, expect, beforeAll, afterAll } from "bun:test";

// ─── Mock @anthropic-ai/claude-agent-sdk before ws-server is imported ────────

// Default returns valid GeneratedSkillSpec JSON text. Individual tests can swap this out.
let mockResponseText: string = JSON.stringify({
  name: "Security Audit",
  description: "Helps identify security vulnerabilities in code.",
  category: "Security",
  triggers: ["security", "audit", "vulnerability"],
  matchedMCPIds: [],
  content: "# Security Audit\n\nCheck for vulnerabilities.",
});

// Whether the mock should throw an error instead of returning text
let mockShouldThrow: boolean = false;

mock.module("@anthropic-ai/claude-agent-sdk", () => ({
  query: async function* (_opts: any) {
    if (mockShouldThrow) {
      throw new Error("Mock LLM error: authentication required");
    }
    yield {
      type: "assistant",
      message: {
        content: [{ type: "text", text: mockResponseText }],
      },
    };
  },
}));

// ─── Imports (after mock) ─────────────────────────────────────────────────────

import { WsServer } from "../../src/ws-server.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import { DelegationStore } from "../../src/stores/delegation-store.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig } from "../../src/types.js";
import { wsConnectDirect } from "../helpers.js";

// ─── Server setup ─────────────────────────────────────────────────────────────

const WS_PORT = 19900 + Math.floor(Math.random() * 1000);
let wsServer: WsServer;

const mockSessionManager = {
  createSession: async () => {},
  sendMessage: async () => {},
  resumeSession: async () => {},
  bulkResume: async () => {},
  updateSessionMode: () => {},
  forkSession: async () => {},
  pauseSession: async () => {},
} as any;

function buildCtx(): ToolContext {
  return {
    blackboard: new BlackboardStore(`gen-int-${Date.now()}-${Math.random()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    nostrTransport: new NostrTransport(() => {}),
    relayClient: {
      isConnected: () => false,
      connect: async () => {},
      sendCommand: async () => ({}),
    } as any,
    broadcast: () => {},
    delegation: new DelegationStore(),
    pendingBrowserBlocking: new Map(),
    pendingBrowserResults: new Map(),
    spawnSession: async (sid: string) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
  };
}

beforeAll(() => {
  const ctx = buildCtx();
  wsServer = new WsServer(WS_PORT, mockSessionManager, ctx);
});

afterAll(() => {
  wsServer.close();
});

// ─── generate.skill ───────────────────────────────────────────────────────────

describe("generate.skill WS command", () => {
  test("valid prompt returns generate.skill.result with expected fields", async () => {
    mockShouldThrow = false;
    mockResponseText = JSON.stringify({
      name: "Security Audit",
      description: "Identifies security vulnerabilities in code.",
      category: "Security",
      triggers: ["security", "audit", "vulnerability"],
      matchedMCPIds: [],
      content: "# Security Audit\n\nCheck for vulnerabilities.",
    });

    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "generate.skill",
        requestId: "r-skill-1",
        prompt: "security auditing",
        availableCategories: ["Security", "Code Review"],
        availableMCPs: [],
      });
      const result = await ws.waitFor(
        (m) => m.type === "generate.skill.result" && m.requestId === "r-skill-1",
      );
      expect(result.type).toBe("generate.skill.result");
      expect(result.requestId).toBe("r-skill-1");
      expect(result.spec.name).toBeDefined();
      expect(result.spec.content).toBeDefined();
      expect(result.spec.category).toBeDefined();
      expect(result.spec.triggers).toBeDefined();
      expect(Array.isArray(result.spec.triggers)).toBe(true);
    } finally {
      ws.close();
    }
  });

  test("returns spec with correct values from mock", async () => {
    mockShouldThrow = false;
    mockResponseText = JSON.stringify({
      name: "Security Audit",
      description: "Identifies security vulnerabilities.",
      category: "Security",
      triggers: ["security", "audit"],
      matchedMCPIds: [],
      content: "# Security Audit\n\nCheck for vulnerabilities.",
    });

    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "generate.skill",
        requestId: "r-skill-2",
        prompt: "security auditing",
        availableCategories: ["Security"],
        availableMCPs: [],
      });
      const result = await ws.waitFor(
        (m) => m.type === "generate.skill.result" && m.requestId === "r-skill-2",
      );
      expect(result.spec.name).toBe("Security Audit");
      expect(result.spec.category).toBe("Security");
      expect(result.spec.triggers).toContain("security");
    } finally {
      ws.close();
    }
  });

  test("returns generate.skill.error when Claude returns missing required fields", async () => {
    mockShouldThrow = false;
    // Missing 'content' field — handler throws "missing required fields"
    mockResponseText = JSON.stringify({
      name: "Incomplete Skill",
      description: "Missing content.",
      category: "General",
      triggers: [],
      matchedMCPIds: [],
      // content intentionally absent
    });

    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "generate.skill",
        requestId: "r-skill-err",
        prompt: "broken skill",
        availableCategories: ["General"],
        availableMCPs: [],
      });
      const result = await ws.waitFor(
        (m) => m.type === "generate.skill.error" && m.requestId === "r-skill-err",
      );
      expect(result.type).toBe("generate.skill.error");
      expect(result.requestId).toBe("r-skill-err");
      expect(result.error).toBeDefined();
    } finally {
      ws.close();
    }
  });

  test("returns generate.skill.error when Claude returns non-JSON", async () => {
    mockShouldThrow = false;
    mockResponseText = "I cannot create that skill right now.";

    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "generate.skill",
        requestId: "r-skill-json-err",
        prompt: "bad json skill",
        availableCategories: ["General"],
        availableMCPs: [],
      });
      const result = await ws.waitFor(
        (m) => m.type === "generate.skill.error" && m.requestId === "r-skill-json-err",
      );
      expect(result.type).toBe("generate.skill.error");
      expect(result.error).toBeDefined();
    } finally {
      ws.close();
    }
  });
});

// ─── generate.template ────────────────────────────────────────────────────────

describe("generate.template WS command", () => {
  test("valid intent returns generate.template.result with name and prompt fields", async () => {
    mockShouldThrow = false;
    mockResponseText = JSON.stringify({
      name: "Review PR",
      prompt: "Review this PR for security issues and code quality.",
    });

    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "generate.template",
        requestId: "r-tmpl-1",
        intent: "review pull request",
        agentName: "Code Reviewer",
        agentSystemPrompt: "You are a code review expert.",
      });
      const result = await ws.waitFor(
        (m) => m.type === "generate.template.result" && m.requestId === "r-tmpl-1",
      );
      expect(result.type).toBe("generate.template.result");
      expect(result.requestId).toBe("r-tmpl-1");
      expect(result.spec.name).toBeDefined();
      expect(result.spec.prompt).toBeDefined();
    } finally {
      ws.close();
    }
  });

  test("returns spec with correct values from mock", async () => {
    mockShouldThrow = false;
    mockResponseText = JSON.stringify({
      name: "Review PR",
      prompt: "Review this PR for security issues and code quality.",
    });

    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "generate.template",
        requestId: "r-tmpl-2",
        intent: "review pull request",
        agentName: "Code Reviewer",
        agentSystemPrompt: "",
      });
      const result = await ws.waitFor(
        (m) => m.type === "generate.template.result" && m.requestId === "r-tmpl-2",
      );
      expect(result.spec.name).toBe("Review PR");
      expect(result.spec.prompt).toBe("Review this PR for security issues and code quality.");
    } finally {
      ws.close();
    }
  });

  test("returns generate.template.error when Claude returns invalid JSON", async () => {
    mockShouldThrow = false;
    mockResponseText = "Sorry, I cannot generate a template for that.";

    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "generate.template",
        requestId: "r-tmpl-json-err",
        intent: "something broken",
        agentName: "My Agent",
        agentSystemPrompt: "",
      });
      const result = await ws.waitFor(
        (m) => m.type === "generate.template.error" && m.requestId === "r-tmpl-json-err",
      );
      expect(result.type).toBe("generate.template.error");
      expect(result.error).toBeDefined();
    } finally {
      ws.close();
    }
  });

  test("returns generate.template.error when spec is missing required fields", async () => {
    mockShouldThrow = false;
    // Missing 'prompt' field
    mockResponseText = JSON.stringify({ name: "Incomplete Template" });

    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");
      ws.send({
        type: "generate.template",
        requestId: "r-tmpl-missing",
        intent: "missing prompt field",
        agentName: "My Agent",
        agentSystemPrompt: "",
      });
      const result = await ws.waitFor(
        (m) => m.type === "generate.template.error" && m.requestId === "r-tmpl-missing",
      );
      expect(result.type).toBe("generate.template.error");
      expect(result.error).toContain("missing required fields");
    } finally {
      ws.close();
    }
  });

  test("each test is independent — concurrent requestIds are matched correctly", async () => {
    mockShouldThrow = false;
    mockResponseText = JSON.stringify({
      name: "Debug Session",
      prompt: "Help me debug {{issue}} in {{component}}.",
    });

    const ws = await wsConnectDirect(WS_PORT);
    try {
      await ws.waitFor((m) => m.type === "sidecar.ready");

      const reqId = `r-tmpl-iso-${Date.now()}`;
      ws.send({
        type: "generate.template",
        requestId: reqId,
        intent: "debugging workflow",
        agentName: "Debugger",
        agentSystemPrompt: "",
      });
      const result = await ws.waitFor(
        (m) => m.type === "generate.template.result" && m.requestId === reqId,
      );
      expect(result.requestId).toBe(reqId);
      expect(result.spec.name).toBeDefined();
    } finally {
      ws.close();
    }
  });
});
