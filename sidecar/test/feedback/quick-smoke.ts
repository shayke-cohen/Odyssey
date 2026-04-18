/**
 * quick-smoke.ts — Standalone smoke test for a running sidecar instance.
 *
 * Tests via REST + WebSocket. NOT auto-discovered by `bun test`.
 * Run with: bun run sidecar/test/feedback/quick-smoke.ts
 *
 * Env vars:
 *   ODYSSEY_HTTP_PORT  — HTTP port (default 9850)
 *   ODYSSEY_WS_PORT    — WebSocket port (default 9849)
 *   USE_REAL_CLAUDE    — if set, use real Claude provider and 30s timeout
 */

import { waitForHealth, wsConnect } from "../helpers.js";

const HTTP_PORT = parseInt(process.env.ODYSSEY_HTTP_PORT ?? "9850");
const WS_PORT = parseInt(process.env.ODYSSEY_WS_PORT ?? "9849");
const USE_REAL_CLAUDE = !!process.env.USE_REAL_CLAUDE;

const POLL_TIMEOUT_MS = USE_REAL_CLAUDE ? 30_000 : 5_000;
const POLL_INTERVAL_MS = 500;

async function pollForCompletedTurn(
  sessionId: string,
  timeoutMs: number,
): Promise<{ status: string; error?: string }> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const res = await fetch(
      `http://127.0.0.1:${HTTP_PORT}/api/v1/sessions/${sessionId}/turns`,
    );
    if (res.ok) {
      const data: any = await res.json();
      const turns: any[] = data.turns ?? [];
      const terminal = turns.find(
        (t: any) => t.status === "completed" || t.status === "failed",
      );
      if (terminal) {
        return { status: terminal.status, error: terminal.error };
      }
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }
  throw new Error(`Turn did not complete within ${timeoutMs}ms`);
}

async function main(): Promise<void> {
  const startMs = Date.now();
  let sessionId: string | null = null;
  let ws: Awaited<ReturnType<typeof wsConnect>> | null = null;

  try {
    // 1. Wait for sidecar HTTP to be healthy
    await waitForHealth(HTTP_PORT);

    // 2. Connect WebSocket
    ws = await wsConnect(WS_PORT);

    // 3. Register test agent via WebSocket (before creating session)
    ws.send({
      type: "agent.register",
      agents: [
        {
          name: "smoke-test-agent",
          systemPrompt: "You are a test agent. Reply very briefly.",
          provider: USE_REAL_CLAUDE ? "claude" : "mock",
          model: "claude-haiku-4-5-20251001",
          allowedTools: [],
          mcpServers: [],
          skills: [],
          workingDirectory: "/tmp",
          maxTurns: 1,
        },
      ],
    });

    // Wait 200ms for agent.register to be processed
    await new Promise((r) => setTimeout(r, 200));

    // 4. Create session via REST
    const createRes = await fetch(
      `http://127.0.0.1:${HTTP_PORT}/api/v1/sessions`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          agentName: "smoke-test-agent",
          message: "reply with: pong",
        }),
      },
    );

    if (!createRes.ok) {
      const body = await createRes.text();
      throw new Error(
        `POST /api/v1/sessions failed (${createRes.status}): ${body}`,
      );
    }

    const session: any = await createRes.json();
    sessionId = session.id ?? session.sessionId;
    if (!sessionId) {
      throw new Error(
        `Session response missing id field: ${JSON.stringify(session)}`,
      );
    }

    // 5. Poll for a completed or failed turn
    const turn = await pollForCompletedTurn(sessionId, POLL_TIMEOUT_MS);

    // 6. Assert turn completed successfully
    if (turn.status !== "completed") {
      throw new Error(
        `Turn ended with status "${turn.status}"${turn.error ? `: ${turn.error}` : ""}`,
      );
    }
    if (turn.error) {
      throw new Error(`Turn completed but has error field: ${turn.error}`);
    }

    // 7. GET /api/v1/debug/state — verify sessions array present
    const stateRes = await fetch(
      `http://127.0.0.1:${HTTP_PORT}/api/v1/debug/state`,
    );
    if (!stateRes.ok) {
      throw new Error(`GET /api/v1/debug/state failed (${stateRes.status})`);
    }
    const state: any = await stateRes.json();
    if (!Array.isArray(state.sessions)) {
      throw new Error(
        `/api/v1/debug/state response missing sessions array: ${JSON.stringify(state)}`,
      );
    }

    // 8. Success output
    const result = {
      passed: true,
      provider: USE_REAL_CLAUDE ? "claude" : "mock",
      durationMs: Date.now() - startMs,
      turnStatus: "completed",
    };
    console.log(JSON.stringify(result));
  } finally {
    // Cleanup: delete session (ignore 404)
    if (sessionId) {
      try {
        await fetch(
          `http://127.0.0.1:${HTTP_PORT}/api/v1/sessions/${sessionId}`,
          { method: "DELETE" },
        );
      } catch {
        // ignore cleanup errors
      }
    }
    // Close WebSocket
    if (ws) {
      try {
        ws.close();
      } catch {
        // ignore
      }
    }
  }
}

main().then(() => process.exit(0)).catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});
