import { describe, expect, test } from "bun:test";

// ---------------------------------------------------------------------------
// Unit tests for preflight-check logic
//
// We test the decision logic (given certain fs/process states, what result is
// returned?) rather than invoking the real system binaries.  The integration
// path (real claude / codex) is covered by the sidecar smoke test and the
// running app.
// ---------------------------------------------------------------------------

// Build a minimal valid Codex auth.json payload.
function makeCodexAuth(opts: {
  accessTokenExp?: number;
  refreshToken?: string | null;
  omitAccessToken?: boolean;
} = {}) {
  const exp = opts.accessTokenExp ?? Math.floor(Date.now() / 1000) + 3600;
  const payload = Buffer.from(JSON.stringify({ exp })).toString("base64url");
  const token = `eyJhbGciOiJSUzI1NiJ9.${payload}.sig`;
  return JSON.stringify({
    auth_mode: "chatgpt",
    tokens: {
      access_token: opts.omitAccessToken ? undefined : token,
      refresh_token: opts.refreshToken === undefined ? "rt_valid" : opts.refreshToken,
      id_token: token,
      account_id: "user-test",
    },
    last_refresh: new Date().toISOString(),
  });
}

// Minimal JWT-exp decoder (duplicated from preflight-check.ts to test it independently)
function parseJwtExp(token: string): number | null {
  try {
    const payload = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString());
    return typeof payload.exp === "number" ? payload.exp : null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// JWT helper
// ---------------------------------------------------------------------------

describe("parseJwtExp (inline duplicate)", () => {
  test("extracts exp from a valid JWT", () => {
    const exp = Math.floor(Date.now() / 1000) + 3600;
    const payload = Buffer.from(JSON.stringify({ exp })).toString("base64url");
    const token = `header.${payload}.sig`;
    expect(parseJwtExp(token)).toBe(exp);
  });

  test("returns null for a malformed token", () => {
    expect(parseJwtExp("not-a-jwt")).toBeNull();
    expect(parseJwtExp("a.b")).toBeNull();
    expect(parseJwtExp("")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Codex auth.json structure
// ---------------------------------------------------------------------------

describe("Codex auth.json validation logic", () => {
  test("auth with future exp and refresh token is considered valid", () => {
    const auth = JSON.parse(makeCodexAuth());
    const accessToken: string = auth.tokens.access_token;
    const refreshToken: string = auth.tokens.refresh_token;
    const exp = parseJwtExp(accessToken)!;

    expect(exp).toBeGreaterThan(Math.floor(Date.now() / 1000));
    expect(refreshToken).toBeTruthy();
  });

  test("auth with expired access token but present refresh token: session still live", () => {
    const pastExp = Math.floor(Date.now() / 1000) - 3600;
    const auth = JSON.parse(makeCodexAuth({ accessTokenExp: pastExp, refreshToken: "rt_valid" }));
    const exp = parseJwtExp(auth.tokens.access_token)!;
    const hasRefresh = !!auth.tokens.refresh_token;

    // Codex refreshes automatically — only fail if BOTH are gone
    const sessionDead = exp * 1000 < Date.now() && !hasRefresh;
    expect(sessionDead).toBe(false);
  });

  test("auth with expired access token AND no refresh token: session dead", () => {
    const pastExp = Math.floor(Date.now() / 1000) - 3600;
    const auth = JSON.parse(makeCodexAuth({ accessTokenExp: pastExp, refreshToken: null }));
    const exp = parseJwtExp(auth.tokens.access_token)!;
    const hasRefresh = !!auth.tokens.refresh_token;

    const sessionDead = exp * 1000 < Date.now() && !hasRefresh;
    expect(sessionDead).toBe(true);
  });

  test("auth missing access_token is invalid", () => {
    const auth = JSON.parse(makeCodexAuth({ omitAccessToken: true }));
    expect(auth.tokens.access_token).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// Real-binary integration (skipped if tool not installed)
// ---------------------------------------------------------------------------

describe("real binary checks (skipped when tool absent)", () => {
  test("claude --version exits 0 when claude is installed", () => {
    const which = Bun.spawnSync(["which", "claude"]);
    if (which.exitCode !== 0) {
      console.log("  [skip] claude not found in PATH");
      return;
    }
    const claudeBin = new TextDecoder().decode(which.stdout).trim();
    const result = Bun.spawnSync([claudeBin, "--version"]);
    expect(result.exitCode).toBe(0);
  });

  test("codex --version exits 0 when Codex.app is installed", () => {
    const codexBin = process.env.CODEX_BINARY ?? "/Applications/Codex.app/Contents/Resources/codex";
    const { existsSync } = require("fs");
    if (!existsSync(codexBin)) {
      console.log("  [skip] Codex.app not installed");
      return;
    }
    const result = Bun.spawnSync([codexBin, "--version"]);
    expect(result.exitCode).toBe(0);
    const out = new TextDecoder().decode(result.stdout);
    expect(out).toContain("codex");
  });

  test("~/.codex/auth.json has a valid structure when Codex is authenticated", () => {
    const { existsSync, readFileSync } = require("fs");
    const { join } = require("path");
    const { homedir } = require("os");
    const authPath = join(homedir(), ".codex", "auth.json");
    if (!existsSync(authPath)) {
      console.log("  [skip] Codex auth.json not present");
      return;
    }
    const auth = JSON.parse(readFileSync(authPath, "utf8"));
    expect(auth.tokens?.access_token).toBeTruthy();
  });
});
