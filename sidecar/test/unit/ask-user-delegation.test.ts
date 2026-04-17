/**
 * Unit tests for delegation-aware helpers in ask-user-tool.ts.
 *
 * Covers:
 *   - DEFAULT_TIMEOUT_MS values
 *   - resolveTimeout (all hint / clamp / edge cases)
 *   - leastBusyAgent (via a minimal ToolContext mock)
 */
import { describe, test, expect, beforeEach } from "bun:test";
import {
  DEFAULT_TIMEOUT_MS,
  resolveTimeout,
  leastBusyAgent,
} from "../../src/tools/ask-user-tool.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { MessageStore } from "../../src/stores/message-store.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig } from "../../src/types.js";

// ─── DEFAULT_TIMEOUT_MS ──────────────────────────────────────────────

describe("DEFAULT_TIMEOUT_MS", () => {
  test("off mode is 5 minutes", () => {
    expect(DEFAULT_TIMEOUT_MS.off).toBe(5 * 60 * 1000);
  });

  test("by_agents mode is 30 seconds", () => {
    expect(DEFAULT_TIMEOUT_MS.by_agents).toBe(30 * 1000);
  });

  test("specific_agent mode is 30 seconds", () => {
    expect(DEFAULT_TIMEOUT_MS.specific_agent).toBe(30 * 1000);
  });

  test("coordinator mode is 30 seconds", () => {
    expect(DEFAULT_TIMEOUT_MS.coordinator).toBe(30 * 1000);
  });

  test("auto modes are shorter than off mode", () => {
    expect(DEFAULT_TIMEOUT_MS.by_agents).toBeLessThan(DEFAULT_TIMEOUT_MS.off);
    expect(DEFAULT_TIMEOUT_MS.specific_agent).toBeLessThan(DEFAULT_TIMEOUT_MS.off);
    expect(DEFAULT_TIMEOUT_MS.coordinator).toBeLessThan(DEFAULT_TIMEOUT_MS.off);
  });
});

// ─── resolveTimeout ──────────────────────────────────────────────────

describe("resolveTimeout", () => {
  const modeMs = DEFAULT_TIMEOUT_MS.by_agents; // 30_000 ms

  test("no hint returns modeMs unchanged", () => {
    expect(resolveTimeout(modeMs)).toBe(modeMs);
  });

  test("undefined hint returns modeMs unchanged", () => {
    expect(resolveTimeout(modeMs, undefined)).toBe(modeMs);
  });

  test("hint shorter than mode returns hint * 1000", () => {
    // 10 seconds < 30 seconds → use the hint
    expect(resolveTimeout(modeMs, 10)).toBe(10_000);
  });

  test("hint equal to mode (in seconds) returns modeMs", () => {
    // 30 seconds hint == 30 000 ms mode → Math.min(30000, 30000) = 30000
    expect(resolveTimeout(modeMs, 30)).toBe(30_000);
  });

  test("hint longer than mode is clamped to modeMs", () => {
    // 60 seconds > 30 seconds → clamp to modeMs
    expect(resolveTimeout(modeMs, 60)).toBe(modeMs);
  });

  test("hint much longer than mode is clamped", () => {
    expect(resolveTimeout(modeMs, 9999)).toBe(modeMs);
  });

  test("works correctly with off-mode (large modeMs)", () => {
    const offMs = DEFAULT_TIMEOUT_MS.off; // 300_000
    // A 60-second hint should be respected since 60_000 < 300_000
    expect(resolveTimeout(offMs, 60)).toBe(60_000);
  });

  test("hint of 1 second works at boundary", () => {
    expect(resolveTimeout(modeMs, 1)).toBe(1_000);
  });

  test("sub-second float hint converts correctly", () => {
    // 0.5 s → 500 ms, which is < 30_000 ms
    expect(resolveTimeout(modeMs, 0.5)).toBe(500);
  });

  // The resolveTimeout function itself does no Zod validation — it just does
  // Math.min. Negative and zero values are blocked upstream by the .positive()
  // Zod schema on timeout_seconds, but the raw function still handles them:
  test("zero hint — falsy, returns modeMs (no-op path)", () => {
    // 0 is falsy in JS so the !hintSeconds guard short-circuits
    expect(resolveTimeout(modeMs, 0)).toBe(modeMs);
  });

  test("negative hint — Math.min returns negative, smaller than modeMs", () => {
    // -5 * 1000 = -5000, Math.min(-5000, 30000) = -5000
    // The schema blocks this in production; function itself returns it as-is
    expect(resolveTimeout(modeMs, -5)).toBe(-5_000);
  });
});

// ─── leastBusyAgent ──────────────────────────────────────────────────

const BASE_CONFIG: AgentConfig = {
  name: "TestAgent",
  systemPrompt: "test",
  allowedTools: [],
  mcpServers: [],
  model: "claude-sonnet-4-6",
  workingDirectory: "/tmp",
  skills: [],
};

function buildMinimalCtx(
  registry: SessionRegistry,
  messages: MessageStore,
): ToolContext {
  return {
    sessions: registry,
    messages,
    // All other fields are not used by leastBusyAgent
    blackboard: {} as any,
    taskBoard: {} as any,
    channels: {} as any,
    workspaces: {} as any,
    peerRegistry: {} as any,
    connectors: {} as any,
    relayClient: {} as any,
    conversationStore: {} as any,
    projectStore: {} as any,
    nostrTransport: {} as any,
    delegation: {} as any,
    broadcast: () => {},
    spawnSession: async (sid) => ({ sessionId: sid }),
    agentDefinitions: new Map(),
  };
}

describe("leastBusyAgent", () => {
  let registry: SessionRegistry;
  let messages: MessageStore;
  let ctx: ToolContext;

  beforeEach(() => {
    registry = new SessionRegistry();
    messages = new MessageStore();
    ctx = buildMinimalCtx(registry, messages);
  });

  test("returns undefined when no sessions exist", () => {
    expect(leastBusyAgent(ctx, "caller-session")).toBeUndefined();
  });

  test("returns undefined when only the calling session is active", () => {
    registry.create("caller", BASE_CONFIG);
    expect(leastBusyAgent(ctx, "caller")).toBeUndefined();
  });

  test("returns the only other active session", () => {
    registry.create("caller", BASE_CONFIG);
    registry.create("worker", BASE_CONFIG);
    expect(leastBusyAgent(ctx, "caller")).toBe("worker");
  });

  test("excludes the calling session from candidates", () => {
    registry.create("caller", BASE_CONFIG);
    registry.create("agent-a", BASE_CONFIG);
    const result = leastBusyAgent(ctx, "caller");
    expect(result).not.toBe("caller");
    expect(result).toBe("agent-a");
  });

  test("picks the session with the fewest unread messages (least busy)", () => {
    registry.create("caller", BASE_CONFIG);
    registry.create("busy-agent", BASE_CONFIG);
    registry.create("idle-agent", BASE_CONFIG);

    // Give busy-agent 3 unread messages and idle-agent 0
    const mockMsg = (to: string) => ({
      id: `m-${Math.random()}`,
      from: "x",
      fromAgent: "X",
      to,
      text: "work",
      priority: "normal" as const,
      timestamp: new Date().toISOString(),
      read: false,
    });
    messages.push("busy-agent", mockMsg("busy-agent"));
    messages.push("busy-agent", mockMsg("busy-agent"));
    messages.push("busy-agent", mockMsg("busy-agent"));

    expect(leastBusyAgent(ctx, "caller")).toBe("idle-agent");
  });

  test("with equal message counts, returns the first in registry order", () => {
    registry.create("caller", BASE_CONFIG);
    registry.create("agent-a", BASE_CONFIG);
    registry.create("agent-b", BASE_CONFIG);
    // Both have 0 messages → sort is stable at 0, first in list wins
    const result = leastBusyAgent(ctx, "caller");
    expect(result).toBe("agent-a");
  });

  test("excludes non-active sessions", () => {
    registry.create("caller", BASE_CONFIG);
    registry.create("paused-agent", BASE_CONFIG);
    registry.update("paused-agent", { status: "paused" });
    // No active candidates remain
    expect(leastBusyAgent(ctx, "caller")).toBeUndefined();
  });

  test("prefers idle agent over two partially-busy ones", () => {
    registry.create("caller", BASE_CONFIG);
    registry.create("medium-agent", BASE_CONFIG);
    registry.create("idle-agent", BASE_CONFIG);
    registry.create("heavy-agent", BASE_CONFIG);

    const mockMsg = (to: string) => ({
      id: `m-${Math.random()}`,
      from: "x",
      fromAgent: "X",
      to,
      text: "task",
      priority: "normal" as const,
      timestamp: new Date().toISOString(),
      read: false,
    });

    messages.push("medium-agent", mockMsg("medium-agent"));
    messages.push("medium-agent", mockMsg("medium-agent"));
    messages.push("heavy-agent", mockMsg("heavy-agent"));
    messages.push("heavy-agent", mockMsg("heavy-agent"));
    messages.push("heavy-agent", mockMsg("heavy-agent"));
    messages.push("heavy-agent", mockMsg("heavy-agent"));

    expect(leastBusyAgent(ctx, "caller")).toBe("idle-agent");
  });
});
