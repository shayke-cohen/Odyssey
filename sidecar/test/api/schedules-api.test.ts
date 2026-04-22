/**
 * Regression tests for schedule HTTP endpoints in api-router.ts.
 *
 * Covers: GET/POST /api/v1/schedules, PATCH/DELETE/trigger per :id.
 * Uses handleApiRequest directly — no live server needed.
 *
 * Note: GET schedule list reads from SCHEDULES_DATA_PATH which is a module-level
 * constant resolved at load time. Tests use the no-file fallback (empty array)
 * which is the safe default for any machine.
 *
 * Usage: bun test test/api/schedules-api.test.ts
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { handleApiRequest } from "../../src/api-router.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import { DelegationStore } from "../../src/stores/delegation-store.js";
import { NostrTransport } from "../../src/relay/nostr-transport.js";
import { SseManager } from "../../src/sse-manager.js";
import { WebhookManager } from "../../src/webhook-manager.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { ApiContext, AgentConfig, SidecarEvent } from "../../src/types.js";

const BASE = "http://test/api/v1";

let broadcasts: SidecarEvent[] = [];
let ctx: ApiContext;

function buildCtx(): ApiContext {
  broadcasts = [];
  const toolCtx: ToolContext = {
    blackboard: new BlackboardStore(`sched-test-${Date.now()}`),
    sessions: new SessionRegistry(),
    messages: new MessageStore(),
    channels: new ChatChannelStore(),
    workspaces: new WorkspaceStore(),
    peerRegistry: new PeerRegistry(),
    connectors: new ConnectorStore(),
    conversationStore: new ConversationStore(),
    projectStore: new ProjectStore(),
    delegation: new DelegationStore(),
    nostrTransport: new NostrTransport(() => {}),
    relayClient: { isConnected: () => false, connect: async () => {}, sendCommand: async () => ({}) } as any,
    broadcast: (event: SidecarEvent) => { broadcasts.push(event); },
    spawnSession: async (sid: string) => ({ sessionId: sid }),
    agentDefinitions: new Map<string, AgentConfig>(),
    pendingBrowserBlocking: new Map(),
    pendingBrowserResults: new Map(),
  };
  return {
    toolCtx,
    sessionManager: { listSessions: () => [], sendMessage: async () => {}, pauseSession: async () => {}, resumeSession: async () => {}, forkSession: async () => {}, spawnAutonomous: async (id: string) => ({ sessionId: id }), updateSessionMode: () => {}, answerQuestion: async () => false, answerConfirmation: async () => false, buildQueryOptionsForTesting: () => ({}), updateSessionCwd: () => {}, bulkResume: async () => {} } as any,
    sseManager: new SseManager(),
    webhookManager: new WebhookManager(),
  };
}

async function req(method: string, path: string, body?: unknown): Promise<{ status: number; body: any }> {
  const res = await handleApiRequest(
    new Request(`${BASE}${path}`, {
      method,
      headers: body ? { "Content-Type": "application/json" } : {},
      body: body ? JSON.stringify(body) : undefined,
    }),
    ctx,
  );
  if (!res) return { status: 0, body: null };
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

beforeEach(() => {
  ctx = buildCtx();
});

// ─── GET /api/v1/schedules ────────────────────────────────────────────────────

describe("GET /api/v1/schedules", () => {
  test("returns empty array when schedules file does not exist", async () => {
    const r = await req("GET", "/schedules");
    expect(r.status).toBe(200);
    expect(Array.isArray(r.body.schedules)).toBe(true);
  });

  test("accepts enabled query param without crashing", async () => {
    const r = await req("GET", "/schedules?enabled=true");
    expect(r.status).toBe(200);
    expect(Array.isArray(r.body.schedules)).toBe(true);
  });

  test("accepts enabled=false without crashing", async () => {
    const r = await req("GET", "/schedules?enabled=false");
    expect(r.status).toBe(200);
    expect(Array.isArray(r.body.schedules)).toBe(true);
  });
});

// ─── POST /api/v1/schedules ───────────────────────────────────────────────────

describe("POST /api/v1/schedules", () => {
  const validBody = {
    name: "Daily Standup",
    targetKind: "agent",
    targetName: "Coder",
    cadenceKind: "dailyTime",
    localHour: 9,
    localMinute: 0,
    promptTemplate: "Run daily standup for {{now}}",
    projectDirectory: "",
    usesAutonomousMode: true,
    runMode: "freshConversation",
  };

  test("returns ok and broadcasts schedule.create", async () => {
    const r = await req("POST", "/schedules", validBody);
    expect(r.status).toBe(200);
    expect(r.body.ok).toBe(true);
    expect(broadcasts.length).toBe(1);
    expect(broadcasts[0].type).toBe("schedule.create");
  });

  test("broadcast payload contains the submitted fields", async () => {
    await req("POST", "/schedules", validBody);
    const event = broadcasts[0] as { type: string; payload: string };
    const payload = JSON.parse(event.payload);
    expect(payload.name).toBe("Daily Standup");
    expect(payload.targetKind).toBe("agent");
    expect(payload.targetName).toBe("Coder");
    expect(payload.promptTemplate).toBe("Run daily standup for {{now}}");
  });

  test("returns 400 when name is missing", async () => {
    const { name: _, ...noName } = validBody;
    const r = await req("POST", "/schedules", noName);
    expect(r.status).toBe(400);
    expect(broadcasts.length).toBe(0);
  });

  test("returns 400 when targetKind is missing", async () => {
    const { targetKind: _, ...noKind } = validBody;
    const r = await req("POST", "/schedules", noKind);
    expect(r.status).toBe(400);
    expect(broadcasts.length).toBe(0);
  });

  test("returns 400 when targetName is missing", async () => {
    const { targetName: _, ...noTarget } = validBody;
    const r = await req("POST", "/schedules", noTarget);
    expect(r.status).toBe(400);
    expect(broadcasts.length).toBe(0);
  });

  test("returns 400 when promptTemplate is missing", async () => {
    const { promptTemplate: _, ...noPrompt } = validBody;
    const r = await req("POST", "/schedules", noPrompt);
    expect(r.status).toBe(400);
    expect(broadcasts.length).toBe(0);
  });
});

// ─── PATCH /api/v1/schedules/:id ─────────────────────────────────────────────

describe("PATCH /api/v1/schedules/:id", () => {
  const SCHEDULE_ID = "f47ac10b-58cc-4372-a567-0e02b2c3d479";

  test("returns ok and broadcasts schedule.update", async () => {
    const r = await req("PATCH", `/schedules/${SCHEDULE_ID}`, { isEnabled: false });
    expect(r.status).toBe(200);
    expect(r.body.ok).toBe(true);
    expect(broadcasts.length).toBe(1);
    expect(broadcasts[0].type).toBe("schedule.update");
  });

  test("broadcast carries the correct scheduleId", async () => {
    await req("PATCH", `/schedules/${SCHEDULE_ID}`, { isEnabled: false });
    const event = broadcasts[0] as { type: string; scheduleId: string; payload: string };
    expect(event.scheduleId).toBe(SCHEDULE_ID);
  });

  test("broadcast payload contains the updated fields", async () => {
    await req("PATCH", `/schedules/${SCHEDULE_ID}`, { isEnabled: false, localHour: 10 });
    const event = broadcasts[0] as { type: string; scheduleId: string; payload: string };
    const payload = JSON.parse(event.payload);
    expect(payload.isEnabled).toBe(false);
    expect(payload.localHour).toBe(10);
  });
});

// ─── DELETE /api/v1/schedules/:id ────────────────────────────────────────────

describe("DELETE /api/v1/schedules/:id", () => {
  const SCHEDULE_ID = "f47ac10b-58cc-4372-a567-0e02b2c3d479";

  test("returns ok and broadcasts schedule.delete", async () => {
    const r = await req("DELETE", `/schedules/${SCHEDULE_ID}`);
    expect(r.status).toBe(200);
    expect(r.body.ok).toBe(true);
    expect(broadcasts.length).toBe(1);
    expect(broadcasts[0].type).toBe("schedule.delete");
  });

  test("broadcast carries the correct scheduleId", async () => {
    await req("DELETE", `/schedules/${SCHEDULE_ID}`);
    const event = broadcasts[0] as { type: string; scheduleId: string };
    expect(event.scheduleId).toBe(SCHEDULE_ID);
  });
});

// ─── POST /api/v1/schedules/:id/trigger ──────────────────────────────────────

describe("POST /api/v1/schedules/:id/trigger", () => {
  const SCHEDULE_ID = "f47ac10b-58cc-4372-a567-0e02b2c3d479";

  test("returns ok and broadcasts schedule.trigger", async () => {
    const r = await req("POST", `/schedules/${SCHEDULE_ID}/trigger`);
    expect(r.status).toBe(200);
    expect(r.body.ok).toBe(true);
    expect(broadcasts.length).toBe(1);
    expect(broadcasts[0].type).toBe("schedule.trigger");
  });

  test("broadcast carries the correct scheduleId", async () => {
    await req("POST", `/schedules/${SCHEDULE_ID}/trigger`);
    const event = broadcasts[0] as { type: string; scheduleId: string };
    expect(event.scheduleId).toBe(SCHEDULE_ID);
  });
});
