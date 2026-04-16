/**
 * Live E2E — agent-invoked tools end up visible in REST APIs.
 *
 * Verifies that when a live Claude agent actually calls task_board_* and
 * blackboard_* tools, the side effects land where Swift/iOS can read them:
 *  - task.created broadcast on WS
 *  - GET /api/v1/tasks returns the task
 *  - GET /blackboard/read returns the written value
 *
 * ODYSSEY_E2E_LIVE=1 required. Prompts are terse to minimize token cost.
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import {
  wsConnect as wsConnectHelper,
  waitForHealth as waitForHealthHelper,
  makeAgentConfig,
} from "../helpers.js";

const WS_PORT = 32000 + Math.floor(Math.random() * 500);
const HTTP_PORT = 32500 + Math.floor(Math.random() * 500);
const DATA_DIR = mkdtempSync(join(tmpdir(), "odyssey-tools-e2e-"));
const isLive =
  (process.env.ODYSSEY_E2E_LIVE ?? process.env.CLAUDESTUDIO_E2E_LIVE) === "1";

let proc: Subprocess;

function wsConnect(timeoutMs = 10000) {
  return wsConnectHelper(WS_PORT, timeoutMs);
}

beforeAll(async () => {
  const sidecarPath = join(import.meta.dir, "../../src/index.ts");
  proc = spawn({
    cmd: ["bun", "run", sidecarPath],
    env: {
      ...process.env,
      ODYSSEY_WS_PORT: String(WS_PORT),
      ODYSSEY_HTTP_PORT: String(HTTP_PORT),
      ODYSSEY_DATA_DIR: DATA_DIR,
      CLAUDESTUDIO_WS_PORT: String(WS_PORT),
      CLAUDESTUDIO_HTTP_PORT: String(HTTP_PORT),
      CLAUDESTUDIO_DATA_DIR: DATA_DIR,
    },
    stdout: "pipe",
    stderr: "pipe",
  });
  await waitForHealthHelper(HTTP_PORT);
}, 30000);

afterAll(() => {
  proc?.kill();
});

describe("E2E: Live tool integration", () => {
  (isLive ? test : test.skip)(
    "agent creates a task → visible via REST + task.created broadcast",
    async () => {
      const ws = await wsConnect();
      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        const sessionId = `tools-task-${Date.now()}`;

        ws.send({
          type: "session.create",
          conversationId: sessionId,
          agentConfig: makeAgentConfig({
            name: "TaskLive",
            systemPrompt:
              "You use the task_board_create tool when asked to create a task. Title must match the user's exact wording. Always use the tool; do not ask for clarification.",
            allowedTools: [
              "mcp__peerbus__task_board_create",
              "mcp__peerbus__task_board_list",
            ],
            maxTurns: 3,
          }),
        });
        await new Promise((r) => setTimeout(r, 400));

        const uniqueTitle = `e2e-task-${Date.now()}`;
        ws.send({
          type: "session.message",
          sessionId,
          text: `Create a task with exact title "${uniqueTitle}" using task_board_create.`,
        });

        const msgs = await ws.collectUntil(
          (m) =>
            m.sessionId === sessionId &&
            (m.type === "session.result" || m.type === "session.error"),
          180000,
        );

        expect(msgs.find((m: any) => m.type === "session.error")).toBeUndefined();

        // task.created event should have been broadcast
        const broadcast = msgs.find(
          (m: any) => m.type === "task.created" && m.task?.title === uniqueTitle,
        );
        expect(broadcast).toBeDefined();

        // REST reflects the task
        const res = await fetch(`http://127.0.0.1:${HTTP_PORT}/api/v1/tasks`);
        expect(res.status).toBe(200);
        const { tasks } = (await res.json()) as any;
        const found = tasks.find((t: any) => t.title === uniqueTitle);
        expect(found).toBeDefined();
        expect(["ready", "backlog"]).toContain(found.status);
      } finally {
        ws.close();
      }
    },
    240000,
  );

  (isLive ? test : test.skip)(
    "agent writes blackboard → visible via HTTP",
    async () => {
      const ws = await wsConnect();
      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        const sessionId = `tools-bb-${Date.now()}`;

        ws.send({
          type: "session.create",
          conversationId: sessionId,
          agentConfig: makeAgentConfig({
            name: "BlackboardLive",
            systemPrompt:
              "When asked, call the blackboard_write tool. Do not output any other text.",
            allowedTools: [
              "mcp__peerbus__blackboard_write",
              "mcp__peerbus__blackboard_read",
            ],
            maxTurns: 3,
          }),
        });
        await new Promise((r) => setTimeout(r, 400));

        const key = `e2e.bb.${Date.now()}`;
        const value = "hello-from-agent";
        ws.send({
          type: "session.message",
          sessionId,
          text: `Write to the blackboard with key "${key}" and value "${value}" using the blackboard_write tool.`,
        });

        await ws.collectUntil(
          (m) =>
            m.sessionId === sessionId &&
            (m.type === "session.result" || m.type === "session.error"),
          180000,
        );

        const res = await fetch(
          `http://127.0.0.1:${HTTP_PORT}/blackboard/read?key=${encodeURIComponent(key)}`,
        );
        expect(res.status).toBe(200);
        const body = (await res.json()) as any;
        expect(body.value).toBe(value);
      } finally {
        ws.close();
      }
    },
    240000,
  );
});
