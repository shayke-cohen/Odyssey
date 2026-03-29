import { beforeEach, describe, expect, test } from "bun:test";
import { SessionManager } from "../../src/session-manager.js";
import { CodexRuntime } from "../../src/providers/codex-runtime.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { MessageStore } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import type { SidecarEvent } from "../../src/types.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import { makeAgentConfig } from "../helpers.js";

describe("Provider runtime integration", () => {
  let registry: SessionRegistry;
  let events: SidecarEvent[];
  let manager: SessionManager;
  let ctx: ToolContext;

  beforeEach(() => {
    registry = new SessionRegistry();
    events = [];

    ctx = {
      blackboard: new BlackboardStore(`provider-int-${Date.now()}`),
      taskBoard: new TaskBoardStore(`provider-int-${Date.now()}`),
      sessions: registry,
      messages: new MessageStore(),
      channels: new ChatChannelStore(),
      workspaces: new WorkspaceStore(),
      peerRegistry: new PeerRegistry(),
      relayClient: {
        isConnected: () => false,
        connect: async () => {},
        sendCommand: async () => ({}),
      } as any,
      broadcast: (event) => events.push(event),
      spawnSession: async (sessionId) => ({ sessionId }),
      agentDefinitions: new Map(),
    };

    manager = new SessionManager((event) => events.push(event), registry, ctx);
  });

  test("codex sessions route to Codex runtime test options and preserve provider in registry", async () => {
    await manager.createSession("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
      workingDirectory: "/tmp/codex-session",
      mcpServers: [
        {
          name: "filesystem",
          command: "mcp-server-filesystem",
          args: ["/tmp/codex-session"],
        },
      ],
    }));

    const state = registry.get("codex-session");
    const options = manager.buildQueryOptionsForTesting("codex-session", 1, true);

    expect(state?.provider).toBe("codex");
    expect(options.provider).toBe("codex");
    expect(options.model).toBe("gpt-5-codex");
    expect(options.cwd).toBe("/tmp/codex-session");
    expect(options.attachmentCount).toBe(1);
    expect(options.mcpServerCount).toBe(1);
    expect(options.appServerConfigOverrides).toContain("mcp_servers={}");
    expect(options.appServerConfigOverrides).toContain(`mcp_servers.session_mcp_0.command="mcp-server-filesystem"`);
  });

  test("Codex notifications normalize into existing sidecar event semantics", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
      interactive: true,
    }) as any);

    const resolved: any[] = [];
    const pendingTurn = {
      sessionId: "codex-session",
      threadId: "thr-1",
      turnId: "turn-1",
      resultText: "",
      latestPlanText: null,
      latestToolOutputs: new Map<string, string>(),
      usage: { inputTokens: 10, outputTokens: 20 },
      resolve: (value: any) => resolved.push(value),
      reject: (error: Error) => {
        throw error;
      },
    };

    (runtime as any).threadToSessionId.set("thr-1", "codex-session");
    (runtime as any).activeTurnsBySession.set("codex-session", pendingTurn);
    (runtime as any).activeTurnsByTurnId.set("turn-1", pendingTurn);

    (runtime as any).handleNotification({
      method: "item/started",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        item: {
          type: "dynamicToolCall",
          id: "item-1",
          tool: "ask_user",
          arguments: { question: "Proceed?" },
        },
      },
    });
    (runtime as any).handleNotification({
      method: "item/agentMessage/delta",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        delta: "Hello from Codex",
      },
    });
    (runtime as any).handleNotification({
      method: "item/reasoning/summaryTextDelta",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        delta: "Reasoning summary",
      },
    });
    (runtime as any).handleNotification({
      method: "item/completed",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        item: {
          type: "dynamicToolCall",
          id: "item-1",
          tool: "ask_user",
          success: true,
          contentItems: [{ type: "text", text: "{\"answer\":\"yes\"}" }],
        },
      },
    });
    (runtime as any).handleNotification({
      method: "turn/completed",
      params: {
        threadId: "thr-1",
        turn: {
          id: "turn-1",
          status: "completed",
        },
      },
    });

    expect(events).toEqual([
      {
        type: "stream.toolCall",
        sessionId: "codex-session",
        tool: "ask_user",
        input: JSON.stringify({ question: "Proceed?" }),
      },
      {
        type: "stream.token",
        sessionId: "codex-session",
        text: "Hello from Codex",
      },
      {
        type: "stream.thinking",
        sessionId: "codex-session",
        text: "Reasoning summary",
      },
      {
        type: "stream.toolResult",
        sessionId: "codex-session",
        tool: "ask_user",
        output: JSON.stringify({
          success: true,
          contentItems: [{ type: "text", text: "{\"answer\":\"yes\"}" }],
        }),
      },
    ]);
    expect(resolved).toEqual([
      {
        backendSessionId: "thr-1",
        resultText: "Hello from Codex",
        costDelta: 0,
        inputTokens: 10,
        outputTokens: 20,
        numTurns: 1,
      },
    ]);
  });

  test("Codex completion resolves even when notifications arrive before turn registration finishes", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
    }) as any);

    (runtime as any).threadToSessionId.set("thr-race", "codex-session");

    const resolved: any[] = [];
    const pendingTurn = {
      sessionId: "codex-session",
      threadId: "thr-race",
      turnId: null,
      resultText: "",
      latestPlanText: null,
      latestToolOutputs: new Map<string, string>(),
      usage: { inputTokens: 4, outputTokens: 9 },
      resolve: (value: any) => resolved.push(value),
      reject: (error: Error) => {
        throw error;
      },
    };

    (runtime as any).activeTurnsBySession.set("codex-session", pendingTurn);

    (runtime as any).handleNotification({
      method: "item/agentMessage/delta",
      params: {
        threadId: "thr-race",
        turnId: "turn-race",
        delta: "codex smoke ok",
      },
    });
    (runtime as any).handleNotification({
      method: "turn/completed",
      params: {
        threadId: "thr-race",
        turn: {
          id: "turn-race",
          status: "completed",
        },
      },
    });

    expect(events).toEqual([
      {
        type: "stream.token",
        sessionId: "codex-session",
        text: "codex smoke ok",
      },
    ]);
    expect(resolved).toEqual([
      {
        backendSessionId: "thr-race",
        resultText: "codex smoke ok",
        costDelta: 0,
        inputTokens: 4,
        outputTokens: 9,
        numTurns: 1,
      },
    ]);
    expect((runtime as any).activeTurnsBySession.has("codex-session")).toBe(false);
    expect((runtime as any).activeTurnsByTurnId.has("turn-race")).toBe(false);
  });

  test("Codex permission approval requests map into existing confirmation flow", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
    }) as any);

    (runtime as any).threadToSessionId.set("thr-1", "codex-session");

    const approvalPromise = (runtime as any).handleServerRequest("codex-session", {
      id: "perm-1",
      method: "item/permissions/requestApproval",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        itemId: "item-1",
        reason: "Need write access for this task",
        permissions: {
          network: { enabled: true },
          fileSystem: {
            read: ["/tmp/readable"],
            write: ["/tmp/writable"],
          },
        },
      },
    });

    expect(events).toEqual([
      {
        type: "agent.confirmation",
        sessionId: "codex-session",
        confirmationId: "perm-1",
        action: "Grant additional permissions",
        reason: "Need write access for this task",
        riskLevel: "high",
        details: "network: enabled\nread: /tmp/readable\nwrite: /tmp/writable",
      },
    ]);

    const answered = await runtime.answerConfirmation("codex-session", "perm-1", true);
    expect(answered).toBe(true);
    await expect(approvalPromise).resolves.toEqual({
      permissions: {
        network: { enabled: true },
        fileSystem: {
          read: ["/tmp/readable"],
          write: ["/tmp/writable"],
        },
      },
      scope: "turn",
    });
  });

  test("Codex MCP elicitation requests map into the existing question flow", async () => {
    const runtime = new CodexRuntime({
      emit: (event) => events.push(event),
      registry,
      toolCtx: ctx,
    });

    registry.create("codex-session", makeAgentConfig({
      name: "CodexBot",
      provider: "codex",
      model: "gpt-5-codex",
    }) as any);

    (runtime as any).threadToSessionId.set("thr-1", "codex-session");

    const elicitationPromise = (runtime as any).handleServerRequest("codex-session", {
      id: "elicitation-1",
      method: "mcpServer/elicitation/request",
      params: {
        threadId: "thr-1",
        turnId: "turn-1",
        serverName: "filesystem",
        mode: "form",
        _meta: { source: "mcp" },
        message: "Need a ticket id before continuing",
        requestedSchema: {
          type: "object",
          properties: {
            ticket: {
              type: "string",
              title: "Ticket",
              description: "Enter the tracking ticket",
            },
            confirm: {
              type: "boolean",
              title: "Confirm",
            },
          },
          required: ["ticket"],
        },
      },
    });

    expect(events).toEqual([
      {
        type: "agent.question",
        sessionId: "codex-session",
        questionId: "elicitation-1",
        question: "Need a ticket id before continuing",
        multiSelect: false,
        private: false,
        inputType: "form",
        inputConfig: {
          fields: [
            {
              name: "ticket",
              label: "Ticket",
              type: "text",
              placeholder: "Enter the tracking ticket",
              required: true,
            },
            {
              name: "confirm",
              label: "Confirm",
              type: "toggle",
              placeholder: undefined,
              required: false,
            },
          ],
        },
      },
    ]);

    const answered = await runtime.answerQuestion(
      "codex-session",
      "elicitation-1",
      JSON.stringify({ ticket: "ABC-123", confirm: "true" }),
    );
    expect(answered).toBe(true);
    await expect(elicitationPromise).resolves.toEqual({
      action: "accept",
      content: {
        ticket: "ABC-123",
        confirm: "true",
      },
      _meta: { source: "mcp" },
    });
  });
});
