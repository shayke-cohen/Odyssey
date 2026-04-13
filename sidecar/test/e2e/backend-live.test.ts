/**
 * Focused live backend regressions for ClaudeRuntime.
 *
 * These tests boot a real sidecar subprocess and exercise:
 * - native Anthropic Claude execution through the Claude Agent SDK
 * - Ollama-backed Claude execution using a real local Ollama daemon
 *
 * Usage:
 *   ODYSSEY_E2E_CLAUDE=1 \
 *   bun test sidecar/test/e2e/backend-live.test.ts
 *
 *   ODYSSEY_E2E_OLLAMA=1 \
 *   ODYSSEY_E2E_OLLAMA_MODEL=qwen3-coder:latest \
 *   bun test sidecar/test/e2e/backend-live.test.ts
 *
 * If `ODYSSEY_E2E_OLLAMA_MODEL` is omitted, the suite picks the first model
 * returned by `GET /api/tags` from the configured Ollama base URL.
 */
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { BufferedWs, makeAgentConfig, waitForHealth, wsConnect } from "../helpers.js";

const WS_PORT = 40849 + Math.floor(Math.random() * 500);
const HTTP_PORT = 40850 + Math.floor(Math.random() * 500);
const DATA_DIR = mkdtempSync(join(tmpdir(), "odyssey-backend-live-"));

const isClaudeLive = (
  process.env.ODYSSEY_E2E_CLAUDE
  ?? process.env.CLAUDESTUDIO_E2E_CLAUDE
  ?? process.env.ODYSSEY_E2E_LIVE
  ?? process.env.CLAUDESTUDIO_E2E_LIVE
) === "1";
const isOllamaLive = (
  process.env.ODYSSEY_E2E_OLLAMA
  ?? process.env.CLAUDESTUDIO_E2E_OLLAMA
) === "1";

const claudeLiveTest = isClaudeLive ? test : test.skip;
const ollamaLiveTest = isOllamaLive ? test : test.skip;

const ollamaBaseURL = (
  process.env.ODYSSEY_OLLAMA_BASE_URL
  ?? process.env.CLAUDESTUDIO_OLLAMA_BASE_URL
  ?? "http://127.0.0.1:11434"
).trim().replace(/\/+$/, "");

const requestedClaudeModel = (
  process.env.ODYSSEY_E2E_CLAUDE_MODEL
  ?? process.env.CLAUDESTUDIO_E2E_CLAUDE_MODEL
  ?? "claude-sonnet-4-6"
).trim();

const requestedOllamaModel = (
  process.env.ODYSSEY_E2E_OLLAMA_MODEL
  ?? process.env.CLAUDESTUDIO_E2E_OLLAMA_MODEL
  ?? ""
).trim();

let proc: Subprocess;

const preferredOllamaModelPrefixes = [
  "gpt-oss",
  "qwen2.5-coder",
  "qwen2.5",
  "deepseek",
  "qwen3",
];
const exactQwenRegressionModel = "qwen3-coder:30b";

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
      ODYSSEY_OLLAMA_BASE_URL: ollamaBaseURL,
      CLAUDESTUDIO_OLLAMA_BASE_URL: ollamaBaseURL,
      ODYSSEY_OLLAMA_MODELS_ENABLED: "1",
      CLAUDESTUDIO_OLLAMA_MODELS_ENABLED: "1",
    },
    stdout: "pipe",
    stderr: "pipe",
  });

  await waitForHealth(HTTP_PORT);
}, 30000);

afterAll(() => {
  proc?.kill();
});

async function runRoundTrip(config: Record<string, unknown>, text: string, timeoutMs = 90000) {
  const ws = await wsConnect(WS_PORT);
  try {
    await ws.waitFor((m) => m.type === "sidecar.ready");
    const sessionId = `backend-live-${Date.now()}-${Math.floor(Math.random() * 10_000)}`;

    ws.send({
      type: "session.create",
      conversationId: sessionId,
      agentConfig: {
        ...makeAgentConfig(),
        ...config,
      },
    });
    await new Promise((resolve) => setTimeout(resolve, 750));

    ws.send({ type: "session.message", sessionId, text });

    const events = await ws.collectUntil(
      (m) => m.sessionId === sessionId && (m.type === "session.result" || m.type === "session.error"),
      timeoutMs,
    );
    const error = events.find((m) => m.type === "session.error" && m.sessionId === sessionId);
    if (error) {
      return {
        events,
        text: "",
        error: String(error.error ?? "Unknown session error"),
      };
    }

    const tokens = events
      .filter((m) => m.type === "stream.token" && m.sessionId === sessionId)
      .map((m: any) => m.text ?? "")
      .join("");
    const result = events.find((m) => m.type === "session.result" && m.sessionId === sessionId) as any;
    if (!result) {
      return {
        events,
        text: "",
        error: `Timed out waiting for session.result after ${timeoutMs}ms`,
      };
    }
    const resultText = typeof result?.result === "string" ? result.result : "";
    const combinedText = `${tokens}${resultText}`.trim();
    expect(combinedText.length).toBeGreaterThan(0);

    return {
      events,
      streamText: tokens,
      resultText,
      text: combinedText,
      error: undefined as string | undefined,
    };
  } finally {
    ws.close();
  }
}

async function fetchOllamaModelNames(): Promise<string[]> {
  const response = await fetch(`${ollamaBaseURL}/api/tags`);
  if (!response.ok) {
    throw new Error(`Ollama tags request failed with HTTP ${response.status} at ${ollamaBaseURL}/api/tags`);
  }

  const body = await response.json() as { models?: Array<{ name?: string }> };
  return (body.models ?? [])
    .map((model) => model.name?.trim() ?? "")
    .filter((name) => name.length > 0)
    .sort(comparePreferredOllamaModels);
}

function comparePreferredOllamaModels(left: string, right: string): number {
  const leftRank = preferredOllamaModelPrefixes.findIndex((prefix) => left.startsWith(prefix));
  const rightRank = preferredOllamaModelPrefixes.findIndex((prefix) => right.startsWith(prefix));
  const normalizedLeftRank = leftRank === -1 ? Number.MAX_SAFE_INTEGER : leftRank;
  const normalizedRightRank = rightRank === -1 ? Number.MAX_SAFE_INTEGER : rightRank;

  if (normalizedLeftRank !== normalizedRightRank) {
    return normalizedLeftRank - normalizedRightRank;
  }

  return left.localeCompare(right);
}

async function resolveOllamaModel(): Promise<string> {
  const names = await fetchOllamaModelNames();
  if (names.length === 0) {
    throw new Error(`Ollama is reachable at ${ollamaBaseURL}, but /api/tags returned no downloaded models.`);
  }

  if (requestedOllamaModel.length > 0) {
    if (!names.includes(requestedOllamaModel)) {
      throw new Error(
        `Requested ODYSSEY_E2E_OLLAMA_MODEL=${requestedOllamaModel} was not found in /api/tags. Available: ${names.join(", ")}`,
      );
    }
    return requestedOllamaModel;
  }

  for (const name of names) {
    if (name !== exactQwenRegressionModel) {
      return name;
    }
  }

  return names[0];
}

function expectBoundedOllamaOutcome(modelName: string, result: { text: string; error?: string }) {
  if (result.error) {
    expect(result.error).toMatch(
      /Timed out waiting for session.result|did not complete a Claude Code turn|stopped responding through Claude Code|did not respond to the Anthropic-compatible Messages API|rejected Claude Code's Anthropic-compatible tool probe|does not support tools/i,
    );
    return;
  }

  expect(result.text.trim().length).toBeGreaterThan(0);
}

async function runExactOllamaRegression(
  config: Record<string, unknown>,
  exactText: string,
  attempts = 3,
  timeoutMs = 180000,
) {
  const failures: string[] = [];

  for (let attempt = 1; attempt <= attempts; attempt++) {
    const result = await runRoundTrip(
      config,
      `Reply with exactly ${exactText} and nothing else.`,
      timeoutMs,
    );

    if (!result.error) {
      const candidates = [result.resultText, result.streamText, result.text]
        .map((value) => value.trim().toUpperCase())
        .filter((value) => value.length > 0);
      if (candidates.some((value) => value.includes(exactText))) {
        return { attempt, result };
      }
      failures.push(
        `attempt ${attempt}: unexpected text (result="${result.resultText}", stream="${result.streamText}")`,
      );
      continue;
    }

    failures.push(`attempt ${attempt}: ${result.error}`);
  }

  throw new Error(`Failed to get exact Ollama regression text after ${attempts} attempts.\n${failures.join("\n")}`);
}

describe("Live backend regressions", () => {
  claudeLiveTest("native Claude model still streams and completes through ClaudeRuntime", async () => {
    const { text } = await runRoundTrip(
      makeAgentConfig({
        name: "ClaudeLiveRegression",
        provider: "claude",
        model: requestedClaudeModel,
        systemPrompt: "Reply with exactly CLAUDE-BACKEND-OK and nothing else.",
        maxTurns: 1,
      }),
      "ping",
      120000,
    );

    expect(text.toUpperCase()).toContain("CLAUDE-BACKEND-OK");
  }, 150000);

  ollamaLiveTest("real Ollama tags are discoverable and a downloaded model completes or fails fast through ClaudeRuntime", async () => {
    const names = await fetchOllamaModelNames();
    const modelName = await resolveOllamaModel();

    expect(names.length).toBeGreaterThan(0);
    expect(names).toContain(modelName);

    const result = await runRoundTrip(
      makeAgentConfig({
        name: "OllamaLiveRegression",
        provider: "claude",
        model: `ollama:${modelName}`,
        systemPrompt: "Reply with exactly OLLAMA-BACKEND-OK and nothing else.",
        maxTurns: 1,
      }),
      "ping",
      180000,
    );

    expectBoundedOllamaOutcome(modelName, result);
  }, 240000);

  ollamaLiveTest("qwen3-coder:30b completes through ClaudeRuntime when used without heavy ambient MCPs", async () => {
    const names = await fetchOllamaModelNames();
    if (!names.includes(exactQwenRegressionModel)) {
      return;
    }

    const { result } = await runExactOllamaRegression(
      makeAgentConfig({
        name: "OllamaQwenRegression",
        provider: "claude",
        model: `ollama:${exactQwenRegressionModel}`,
        systemPrompt: "Reply with exactly OLLAMA-QWEN-REGRESSION and nothing else.",
        maxTurns: 1,
      }),
      "OLLAMA-QWEN-REGRESSION",
      3,
      180_000,
    );

    expect(result.error).toBeUndefined();
    expect(result.resultText.toUpperCase()).toContain("OLLAMA-QWEN-REGRESSION");
  }, 600_000);
});
