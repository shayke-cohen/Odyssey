/**
 * Unit tests for createAskAgentTool.
 *
 * All agent spawning is intercepted via ctx.spawnSession mock so no real
 * Claude sessions are started. Each test builds its own isolated ctx to
 * prevent any cross-test state leakage.
 *
 * Covers:
 *   - Agent not found (agentDefinitions miss)
 *   - Delegation override (resolveTarget changes the target)
 *   - Successful delegation (broadcast routing + resolved events, returns answer)
 *   - Spawn failure (spawnSession throws → error result)
 *   - off mode passthrough (resolveTarget returns the nominated agent unchanged)
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { createAskAgentTool } from "../../src/tools/ask-agent-tool.js";
import { DelegationStore } from "../../src/stores/delegation-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { AgentConfig, SidecarEvent } from "../../src/types.js";

// ─── Helpers ─────────────────────────────────────────────────────────

const BASE_CONFIG: AgentConfig = {
  name: "TargetAgent",
  systemPrompt: "You are a helpful assistant.",
  allowedTools: [],
  mcpServers: [],
  model: "claude-sonnet-4-6",
  workingDirectory: "/tmp",
  skills: [],
};

interface CtxOverrides {
  spawnSession?: ToolContext["spawnSession"];
  delegation?: DelegationStore;
  agentDefinitions?: Map<string, AgentConfig>;
  sessions?: SessionRegistry;
  broadcast?: (e: SidecarEvent) => void;
}

function buildCtx(
  broadcastFn: (e: SidecarEvent) => void,
  overrides: CtxOverrides = {},
): ToolContext {
  const delegation = overrides.delegation ?? new DelegationStore();
  const sessions = overrides.sessions ?? new SessionRegistry();

  return {
    delegation,
    sessions,
    agentDefinitions: overrides.agentDefinitions ?? new Map(),
    broadcast: broadcastFn,
    spawnSession:
      overrides.spawnSession ??
      (async (sid) => ({ sessionId: sid, result: "default answer" })),
    // Unused by ask-agent-tool but required by ToolContext shape
    blackboard: {} as any,
    taskBoard: {} as any,
    messages: {} as any,
    channels: {} as any,
    workspaces: {} as any,
    peerRegistry: {} as any,
    connectors: {} as any,
    relayClient: {} as any,
    conversationStore: {} as any,
    projectStore: {} as any,
    nostrTransport: {} as any,
  };
}

/** Extract and call the single tool's execute function. */
async function callAskAgent(
  ctx: ToolContext,
  callingSessionId: string,
  args: { question: string; to_agent: string },
) {
  const tools = createAskAgentTool(ctx, callingSessionId);
  expect(tools).toHaveLength(1);
  return tools[0].execute(args);
}

function parseResult(result: { content: Array<{ type: string; text: string }> }) {
  return JSON.parse(result.content[0].text);
}

// ─── Tests ───────────────────────────────────────────────────────────

describe("createAskAgentTool — agent not found", () => {
  test("returns error result when agentDefinitions has no entry for resolved target", async () => {
    const events: SidecarEvent[] = [];
    const ctx = buildCtx((e) => events.push(e), {
      agentDefinitions: new Map(), // empty — target not found
    });

    const result = await callAskAgent(ctx, "session-1", {
      question: "What is the plan?",
      to_agent: "PM",
    });

    // success flag should be false
    expect(result.success).toBe(false);
    const parsed = parseResult(result);
    expect(parsed.error).toBe("agent_not_found");
    expect(parsed.agent).toBe("PM");
    expect(typeof parsed.message).toBe("string");
    // No broadcasts should have been emitted
    expect(events).toHaveLength(0);
  });

  test("error message includes the missing agent name", async () => {
    const ctx = buildCtx(() => {}, { agentDefinitions: new Map() });
    const result = await callAskAgent(ctx, "session-1", {
      question: "Hello?",
      to_agent: "Reviewer",
    });
    const parsed = parseResult(result);
    expect(parsed.message).toContain("Reviewer");
  });
});

describe("createAskAgentTool — delegation override", () => {
  test("resolveTarget substitutes a different agent than to_agent", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "specific_agent", targetAgentName: "PM" });

    const definitions = new Map<string, AgentConfig>([
      ["PM", { ...BASE_CONFIG, name: "PM" }],
    ]);

    let spawnedConfig: AgentConfig | undefined;
    const spawnSession: ToolContext["spawnSession"] = async (sid, config, prompt, wait) => {
      spawnedConfig = config;
      return { sessionId: sid, result: "PM says: go ahead" };
    };

    const ctx = buildCtx((e) => events.push(e), {
      delegation,
      agentDefinitions: definitions,
      spawnSession,
    });

    const result = await callAskAgent(ctx, "session-1", {
      question: "Are we on track?",
      to_agent: "Reviewer", // will be overridden to "PM"
    });

    // Spawn should have used the overridden "PM" config
    expect(spawnedConfig?.name).toBe("PM");

    // routing event should name "PM" as the target
    const routingEvent = events.find((e) => e.type === "agent.question.routing");
    expect(routingEvent).toBeDefined();
    if (routingEvent?.type === "agent.question.routing") {
      expect(routingEvent.targetAgentName).toBe("PM");
    }

    const parsed = parseResult(result);
    expect(parsed.answer).toBe("PM says: go ahead");
  });

  test("when resolveTarget returns undefined, falls back to to_agent", async () => {
    // by_agents mode + no targetAgentName → resolveTarget returns the nominated agent
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "by_agents" });

    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);

    let spawnedConfig: AgentConfig | undefined;
    const spawnSession: ToolContext["spawnSession"] = async (sid, config) => {
      spawnedConfig = config;
      return { sessionId: sid, result: "LGTM" };
    };

    const ctx = buildCtx(() => {}, { delegation, agentDefinitions: definitions, spawnSession });
    await callAskAgent(ctx, "session-1", {
      question: "Is the code good?",
      to_agent: "Reviewer",
    });

    expect(spawnedConfig?.name).toBe("Reviewer");
  });
});

describe("createAskAgentTool — successful delegation", () => {
  test("broadcasts routing and resolved events, returns agent answer", async () => {
    const events: SidecarEvent[] = [];
    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);
    const spawnSession: ToolContext["spawnSession"] = async (sid) => ({
      sessionId: sid,
      result: "Looks good to me!",
    });

    const ctx = buildCtx((e) => events.push(e), { agentDefinitions: definitions, spawnSession });
    const result = await callAskAgent(ctx, "caller-session", {
      question: "Please review this PR.",
      to_agent: "Reviewer",
    });

    // Should have emitted exactly 2 broadcast events
    expect(events).toHaveLength(2);

    const routingEvent = events[0];
    expect(routingEvent.type).toBe("agent.question.routing");
    if (routingEvent.type === "agent.question.routing") {
      expect(routingEvent.sessionId).toBe("caller-session");
      expect(routingEvent.targetAgentName).toBe("Reviewer");
      expect(typeof routingEvent.questionId).toBe("string");
    }

    const resolvedEvent = events[1];
    expect(resolvedEvent.type).toBe("agent.question.resolved");
    if (resolvedEvent.type === "agent.question.resolved") {
      expect(resolvedEvent.sessionId).toBe("caller-session");
      expect(resolvedEvent.answeredBy).toBe("Reviewer");
      expect(resolvedEvent.isFallback).toBe(false);
      expect(resolvedEvent.answer).toBe("Looks good to me!");
    }

    // routing questionId should match resolved questionId
    const routingQId =
      routingEvent.type === "agent.question.routing" ? routingEvent.questionId : null;
    const resolvedQId =
      resolvedEvent.type === "agent.question.resolved" ? resolvedEvent.questionId : null;
    expect(routingQId).toBe(resolvedQId);

    expect(result.success).toBe(true);
    const parsed = parseResult(result);
    expect(parsed.answer).toBe("Looks good to me!");
  });

  test("prompt sent to spawned agent includes caller name and question", async () => {
    const sessions = new SessionRegistry();
    sessions.create("caller-session", { ...BASE_CONFIG, name: "Coder" });

    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);

    let capturedPrompt = "";
    const spawnSession: ToolContext["spawnSession"] = async (sid, config, prompt) => {
      capturedPrompt = prompt;
      return { sessionId: sid, result: "OK" };
    };

    const ctx = buildCtx(() => {}, { agentDefinitions: definitions, spawnSession, sessions });
    await callAskAgent(ctx, "caller-session", {
      question: "Is this the right approach?",
      to_agent: "Reviewer",
    });

    expect(capturedPrompt).toContain("Coder");
    expect(capturedPrompt).toContain("Is this the right approach?");
  });

  test("uses 'another agent' as caller name when session is not registered", async () => {
    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);

    let capturedPrompt = "";
    const spawnSession: ToolContext["spawnSession"] = async (sid, config, prompt) => {
      capturedPrompt = prompt;
      return { sessionId: sid, result: "OK" };
    };

    const ctx = buildCtx(() => {}, { agentDefinitions: definitions, spawnSession });
    await callAskAgent(ctx, "unknown-session", {
      question: "Any thoughts?",
      to_agent: "Reviewer",
    });

    expect(capturedPrompt).toContain("another agent");
  });

  test("returns fallback answer when spawnSession returns no result", async () => {
    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);
    const spawnSession: ToolContext["spawnSession"] = async (sid) => ({
      sessionId: sid,
      result: undefined, // agent produced no output
    });

    const ctx = buildCtx(() => {}, { agentDefinitions: definitions, spawnSession });
    const result = await callAskAgent(ctx, "caller", {
      question: "Hello?",
      to_agent: "Reviewer",
    });

    const parsed = parseResult(result);
    expect(parsed.answer).toBe("[Agent provided no answer.]");
  });
});

describe("createAskAgentTool — spawn failure", () => {
  test("spawnSession throwing returns delegation_failed error result", async () => {
    const events: SidecarEvent[] = [];
    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);
    const spawnSession: ToolContext["spawnSession"] = async () => {
      throw new Error("network timeout");
    };

    const ctx = buildCtx((e) => events.push(e), { agentDefinitions: definitions, spawnSession });
    const result = await callAskAgent(ctx, "caller", {
      question: "Should we ship?",
      to_agent: "Reviewer",
    });

    expect(result.success).toBe(false);
    const parsed = parseResult(result);
    expect(parsed.error).toBe("delegation_failed");
    expect(parsed.message).toBe("network timeout");
  });

  test("routing broadcast fires before spawn attempt, no resolved broadcast on failure", async () => {
    const events: SidecarEvent[] = [];
    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);
    const spawnSession: ToolContext["spawnSession"] = async () => {
      throw new Error("crash");
    };

    const ctx = buildCtx((e) => events.push(e), { agentDefinitions: definitions, spawnSession });
    await callAskAgent(ctx, "caller", {
      question: "Ready?",
      to_agent: "Reviewer",
    });

    // routing was broadcast before spawn; resolved was not because spawn threw
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe("agent.question.routing");
  });
});

describe("createAskAgentTool — off mode passthrough", () => {
  test("off mode leaves to_agent unchanged (resolveTarget returns nominated)", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "off" });

    const definitions = new Map<string, AgentConfig>([
      ["Reviewer", { ...BASE_CONFIG, name: "Reviewer" }],
    ]);

    let spawnedConfig: AgentConfig | undefined;
    const spawnSession: ToolContext["spawnSession"] = async (sid, config) => {
      spawnedConfig = config;
      return { sessionId: sid, result: "Off-mode answer" };
    };

    const ctx = buildCtx((e) => events.push(e), { delegation, agentDefinitions: definitions, spawnSession });
    const result = await callAskAgent(ctx, "session-1", {
      question: "Code review?",
      to_agent: "Reviewer",
    });

    // resolveTarget in off mode returns the nominated agent as-is
    expect(spawnedConfig?.name).toBe("Reviewer");

    const routingEvent = events.find((e) => e.type === "agent.question.routing");
    expect(routingEvent).toBeDefined();
    if (routingEvent?.type === "agent.question.routing") {
      expect(routingEvent.targetAgentName).toBe("Reviewer");
    }

    const parsed = parseResult(result);
    expect(parsed.answer).toBe("Off-mode answer");
  });

  test("coordinator mode with stored targetAgentName overrides to_agent", async () => {
    const events: SidecarEvent[] = [];
    const delegation = new DelegationStore();
    delegation.set("session-1", { mode: "coordinator", targetAgentName: "Coordinator" });

    const definitions = new Map<string, AgentConfig>([
      ["Coordinator", { ...BASE_CONFIG, name: "Coordinator" }],
    ]);

    let spawnedName = "";
    const spawnSession: ToolContext["spawnSession"] = async (sid, config) => {
      spawnedName = config.name;
      return { sessionId: sid, result: "Coordinated answer" };
    };

    const ctx = buildCtx((e) => events.push(e), { delegation, agentDefinitions: definitions, spawnSession });
    await callAskAgent(ctx, "session-1", {
      question: "Plan for today?",
      to_agent: "SomeOtherAgent", // overridden by coordinator mode
    });

    expect(spawnedName).toBe("Coordinator");
  });
});
