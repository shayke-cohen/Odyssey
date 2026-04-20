import { existsSync, readFileSync } from "fs";
import { join, resolve, dirname } from "path";
import { homedir } from "os";
import { fileURLToPath } from "url";
import { spawnSync } from "child_process";

// ── helpers ────────────────────────────────────────────────────────────────

// Same resolution logic as claude-runtime.ts — must stay in sync.
function resolveClaudeCodeCliPath(): string | undefined {
  const dir = dirname(fileURLToPath(import.meta.url));
  const bundled = resolve(dir, "claude-code-cli.js");
  if (existsSync(bundled)) return bundled;
  const devPath = resolve(dir, "../../node_modules/@anthropic-ai/claude-agent-sdk/cli.js");
  if (existsSync(devPath)) return devPath;
  return undefined;
}

// Find the system `claude` binary without assuming a fixed install path.
// Claude Code can be installed to ~/.local/bin, /usr/local/bin, or anywhere in PATH.
function findClaudeBinary(): string | undefined {
  const whichResult = spawnSync("which", ["claude"], { encoding: "utf8", timeout: 3000 });
  const fromPath = whichResult.stdout?.trim();
  if (fromPath && existsSync(fromPath)) return fromPath;

  // Fallback: common macOS install locations
  const candidates = [
    join(homedir(), ".local", "bin", "claude"),
    "/usr/local/bin/claude",
    "/opt/homebrew/bin/claude",
  ];
  return candidates.find((p) => existsSync(p));
}

function binaryRuns(binary: string, args: string[]): boolean {
  const r = spawnSync(binary, args, { encoding: "utf8", timeout: 5000 });
  return r.status === 0 && !r.error;
}

function parseJwtExp(token: string): number | null {
  try {
    const payload = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
    return typeof payload.exp === "number" ? payload.exp : null;
  } catch {
    return null;
  }
}

const CODEX_BINARY =
  process.env.CODEX_BINARY ?? "/Applications/Codex.app/Contents/Resources/codex";

// ── exports ────────────────────────────────────────────────────────────────

export interface PreflightResult {
  ok: boolean;
  error?: string;
}

export function checkClaudePreflight(): PreflightResult {
  // 1. Bundled cli.js must be present (packed by build-sidecar-binary.sh)
  if (!resolveClaudeCodeCliPath()) {
    return {
      ok: false,
      error: "Claude Code CLI is missing from the Odyssey bundle. Reinstall Odyssey from the latest release.",
    };
  }

  // 2. System `claude` binary must be findable — auth lives in the OS Keychain,
  //    so file-based checks are unreliable; running the binary is the only safe signal.
  const bin = findClaudeBinary();
  if (!bin) {
    return {
      ok: false,
      error: "Claude Code is not installed. Install it from claude.ai/code and sign in, then relaunch Odyssey.",
    };
  }

  // 3. Verify the binary actually runs (catches broken installs, wrong arch, etc.)
  if (!binaryRuns(bin, ["--version"])) {
    return {
      ok: false,
      error: "Claude Code is installed but not responding. Try signing in again via the Claude Code app, then relaunch Odyssey.",
    };
  }

  return { ok: true };
}

export function checkCodexPreflight(): PreflightResult {
  // 1. Binary must exist
  if (!existsSync(CODEX_BINARY)) {
    return {
      ok: false,
      error: "Codex is not installed. Install Codex.app and sign in with your OpenAI account, then relaunch Odyssey.",
    };
  }

  // 2. Binary must run
  if (!binaryRuns(CODEX_BINARY, ["--version"])) {
    return {
      ok: false,
      error: "Codex is installed but failed to start. Try reinstalling Codex.app, then relaunch Odyssey.",
    };
  }

  // 3. Auth file must exist (written by Codex.app on first sign-in)
  const authPath = join(homedir(), ".codex", "auth.json");
  if (!existsSync(authPath)) {
    return {
      ok: false,
      error: "Codex is not signed in. Open Codex.app, sign in with your OpenAI account, then relaunch Odyssey.",
    };
  }

  // 4. Auth file must be valid — check for a non-empty access token and a live refresh token
  try {
    const auth = JSON.parse(readFileSync(authPath, "utf8"));
    const accessToken: string | undefined = auth?.tokens?.access_token;
    const refreshToken: string | undefined = auth?.tokens?.refresh_token;

    if (!accessToken) {
      return {
        ok: false,
        error: "Codex session is missing. Open Codex.app, sign in again, then relaunch Odyssey.",
      };
    }

    // If access token is expired AND there is no refresh token the session is permanently dead.
    const exp = parseJwtExp(accessToken);
    if (exp !== null && exp * 1000 < Date.now() && !refreshToken) {
      return {
        ok: false,
        error: "Codex session has expired. Open Codex.app, sign in again, then relaunch Odyssey.",
      };
    }
  } catch {
    return {
      ok: false,
      error: "Codex auth file is corrupted. Open Codex.app, sign in again, then relaunch Odyssey.",
    };
  }

  return { ok: true };
}
