/**
 * Organic live E2E vault test — real task, autonomous reflection.
 *
 * Unlike resident-vault-live.test.ts (which scripts exact strings for the agent
 * to write), this test gives the agent a genuine bug to fix and lets it decide
 * what to write to MEMORY.md and sessions/ on its own.
 *
 * We verify:
 *  - The agent actually fixed the bug (run the patched file)
 *  - The agent autonomously created sessions/YYYY-MM-DD.md with substantive content
 *  - The agent autonomously appended at least one lesson to MEMORY.md ## Recent Lessons
 *  - The lesson is agent-authored (contains today's date + non-trivial text)
 *
 * No scripted reflection strings. The test never tells the agent what to write.
 *
 * Usage: ODYSSEY_E2E_LIVE=1 bun test test/e2e/resident-vault-organic.test.ts
 * Model: claude-sonnet-4-6 (better instruction-following for the reflection loop)
 * Cost: ~1 session, ~1–2k tokens
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { spawn, type Subprocess } from "bun";
import { mkdtempSync, writeFileSync, readFileSync, existsSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import {
  wsConnect as wsConnectHelper,
  waitForHealth as waitForHealthHelper,
} from "../helpers.js";

const WS_PORT = 33000 + Math.floor(Math.random() * 500);
const HTTP_PORT = 33500 + Math.floor(Math.random() * 500);
const DATA_DIR = mkdtempSync(join(tmpdir(), "odyssey-vault-organic-"));
const isLive = (process.env.ODYSSEY_E2E_LIVE ?? process.env.CLAUDESTUDIO_E2E_LIVE) === "1";

let proc: Subprocess;

function wsConnect(timeoutMs = 10_000) { return wsConnectHelper(WS_PORT, timeoutMs); }

// ─── Vault + broken code factory ─────────────────────────────────────

function createWorkspace(): { vaultDir: string; brokenFile: string; memoryBefore: string } {
  const dir = mkdtempSync(join(tmpdir(), "vault-organic-"));
  const today = new Date().toISOString().split("T")[0];

  // Vault seed files
  writeFileSync(join(dir, "CLAUDE.md"), `---
agent: resident-debugger
updated: ${today}
---

# resident-debugger

## Role
I am a resident debugging agent. I fix bugs and grow my knowledge over time.

## Knowledge Graph

| File | Purpose | Cap |
|------|---------|-----|
| \`INDEX.md\` | Map-of-content | — |
| \`MEMORY.md\` | Routing index + recent lessons | 200 lines hard cap |
| \`GUIDELINES.md\` | Self-written rules | — |
| \`SESSION.md\` | Current active state (volatile) | Reset each session |
| \`sessions/YYYY-MM-DD.md\` | Append-only daily session log | — |
| \`knowledge/{topic}.md\` | Semantic topic notes | — |

## Session Start

1. Read \`INDEX.md\` — understand what exists in the graph
2. Read \`MEMORY.md\` — load routing index and recent lessons
3. Read \`GUIDELINES.md\` — apply self-written rules
4. Reset \`SESSION.md\` — write current task and what NOT to forget
5. Grep \`sessions/\` or \`knowledge/\` for topics relevant to today

## Session End (Reflection Loop)

Before finishing, answer these:
1. What was the task? Did it succeed?
2. What was the earliest mistake or friction?
3. What one rule would prevent it next time?

Then write:
- A one-liner to \`MEMORY.md\` under \`## Recent Lessons\` (format: \`${today}: <lesson>\`)
- A full reflection entry to \`sessions/${today}.md\` (create the file if it doesn't exist)
- Update \`SESSION.md\` task status to completed

IMPORTANT: The reflection loop is mandatory. You must write to MEMORY.md and sessions/ before replying.
`);

  writeFileSync(join(dir, "INDEX.md"), `---
updated: ${today}
---

# resident-debugger — Knowledge Index

## Core Files
- [[CLAUDE.md]] — identity, graph conventions, and reflection loop
- [[MEMORY.md]] — routing index and recent lessons
- [[GUIDELINES.md]] — self-written rules
- [[SESSION.md]] — current active state (volatile)

## Sessions (Episodic)

## Knowledge (Semantic)
`);

  const memoryContent = `---
updated: ${today}
cap: "200 lines — keep under this cap; move detail to knowledge/"
---

# resident-debugger — Memory

## Recent Lessons

## Domain Map

## Active Goals
- Fix bugs in the workspace
`;
  writeFileSync(join(dir, "MEMORY.md"), memoryContent);

  writeFileSync(join(dir, "GUIDELINES.md"), `---
updated: ${today}
tags: [guidelines]
---

# Guidelines

<!-- Rules I've written from past experience. Format: - #tag Rule (YYYY-MM-DD) -->
`);

  writeFileSync(join(dir, "SESSION.md"), `---
updated: ${today}
volatile: true
---

# Current Session

## Task

## Active Context

## Do Not Forget
`);

  // The broken code to fix: off-by-one in a sum function + missing edge case handler
  writeFileSync(join(dir, "broken.js"), `// Task: fix the bugs in this file so all three assertions pass.

function sum(arr) {
  let total = 0;
  for (let i = 0; i <= arr.length; i++) {  // bug 1: off-by-one (should be <)
    total += arr[i];
  }
  return total;
}

function average(arr) {
  if (arr.length === 0) return 0;
  return sum(arr) / arr.length;
}

// These must all pass when you run: bun broken.js
const assert = (cond, msg) => { if (!cond) throw new Error("FAIL: " + msg); };

assert(sum([1, 2, 3]) === 6,        "sum([1,2,3]) should be 6");
assert(sum([]) === 0,               "sum([]) should be 0");
assert(average([10, 20, 30]) === 20, "average should be 20");

console.log("ALL ASSERTIONS PASSED");
`);

  return { vaultDir: dir, brokenFile: join(dir, "broken.js"), memoryBefore: memoryContent };
}

// ─── Lifecycle ───────────────────────────────────────────────────────

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
}, 30_000);

afterAll(() => { proc?.kill(); });

// ─── The organic test ─────────────────────────────────────────────────

describe("E2E Live Vault (organic): real task + autonomous reflection", () => {
  (isLive ? test : test.skip)(
    "agent fixes a bug then autonomously writes vault reflection",
    async () => {
      const { vaultDir, brokenFile, memoryBefore } = createWorkspace();
      const today = new Date().toISOString().split("T")[0];
      const ws = await wsConnect();

      try {
        await ws.waitFor((m) => m.type === "sidecar.ready");
        const sessionId = `vault-organic-${Date.now()}`;

        ws.send({
          type: "session.create",
          conversationId: sessionId,
          agentConfig: {
            name: "resident-debugger",
            systemPrompt:
              "You are a resident debugging agent. Your working directory is your persistent knowledge vault. " +
              "Always follow the instructions in CLAUDE.md — especially the Session End Reflection Loop. " +
              "The reflection is not optional.",
            allowedTools: ["Read", "Write", "Bash"],
            mcpServers: [],
            model: "claude-sonnet-4-6",
            workingDirectory: vaultDir,
            skills: [],
            maxTurns: 15,
          },
        });

        await new Promise((r) => setTimeout(r, 300));

        ws.send({
          type: "session.message",
          sessionId,
          text:
            "broken.js has bugs. Fix them so that running `bun broken.js` prints 'ALL ASSERTIONS PASSED'. " +
            "When the fix is verified, follow your Session End Reflection Loop from CLAUDE.md before replying.",
        });

        const msgs = await ws.collectUntil(
          (m) => m.sessionId === sessionId &&
            (m.type === "session.result" || m.type === "session.error"),
          240_000,
        );

        // ── No errors ────────────────────────────────────────────────
        const errors = msgs.filter((m: any) => m.type === "session.error");
        expect(errors).toHaveLength(0);

        const result = msgs.find((m: any) => m.type === "session.result" && m.sessionId === sessionId);
        expect(result).toBeDefined();

        // ── Bug is actually fixed ────────────────────────────────────
        const runResult = Bun.spawnSync(["bun", brokenFile]);
        const stdout = new TextDecoder().decode(runResult.stdout).trim();
        expect(stdout).toBe("ALL ASSERTIONS PASSED");

        // ── Agent autonomously created a session log ─────────────────
        const sessionFile = join(vaultDir, "sessions", `${today}.md`);
        expect(existsSync(sessionFile)).toBe(true);

        const sessionLog = readFileSync(sessionFile, "utf8");
        // Must be substantive — more than just a date header
        expect(sessionLog.length).toBeGreaterThan(50);
        console.log("\n── Agent-written session log ──────────────────────");
        console.log(sessionLog);

        // ── Agent autonomously added a lesson to MEMORY.md ───────────
        const memoryAfter = readFileSync(join(vaultDir, "MEMORY.md"), "utf8");
        expect(memoryAfter).not.toBe(memoryBefore); // file was changed

        // Extract the Recent Lessons section
        const lessonsMatch = memoryAfter.match(/## Recent Lessons\n([\s\S]*?)(\n##|$)/);
        const lessonsSection = lessonsMatch?.[1]?.trim() ?? "";
        expect(lessonsSection.length).toBeGreaterThan(0); // at least one lesson written

        console.log("\n── Agent-written MEMORY.md lessons ────────────────");
        console.log(lessonsSection);

        // Lesson should contain today's date (per CLAUDE.md format: YYYY-MM-DD: <lesson>)
        expect(lessonsSection).toContain(today);

        // ── SESSION.md was updated ────────────────────────────────────
        const sessionMd = readFileSync(join(vaultDir, "SESSION.md"), "utf8");
        // The agent should have written something under ## Task
        const taskMatch = sessionMd.match(/## Task\n([\s\S]*?)(\n##|$)/);
        const taskSection = taskMatch?.[1]?.trim() ?? "";
        expect(taskSection.length).toBeGreaterThan(0);

        console.log("\n── Agent-written SESSION.md task ───────────────────");
        console.log(taskSection);

      } finally {
        ws.close();
      }
    },
    300_000,
  );
});
