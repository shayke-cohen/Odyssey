#!/usr/bin/env bun
// scripts/gen-test-invite.ts
//
// Generates a valid OdysseyCore InvitePayload for E2E testing.
// Outputs a base64url invite code to stdout.
//
// Usage: bun scripts/gen-test-invite.ts [instanceName]
// Default instanceName: "default"
//
// Prereqs:
//   - ~/.odyssey/instances/<instance>/tls.cert.pem exists
//   - Keychain has 'odyssey.wstoken.<instance>'
//   - Sidecar running with matching ODYSSEY_TLS_CERT/KEY/TOKEN
//
// OdysseyCore canonical JSON rules (must match Swift's JSONEncoder):
//   - All keys sorted alphabetically (recursive)
//   - nil/null optionals OMITTED (Swift uses encodeIfPresent)
//   - `signature` key excluded from canonical form

import { spawnSync } from "bun";
import { readFileSync } from "fs";
import { join } from "path";

const instanceName = process.argv[2] ?? "default";
const instanceDir = join(process.env.HOME!, ".odyssey", "instances", instanceName);
const scriptDir = new URL(".", import.meta.url).pathname;

// ── 1. TLS cert PEM → DER base64 ─────────────────────────────────────────
// PEM body (between header/footer) IS the base64-encoded DER bytes.
const pem = readFileSync(join(instanceDir, "tls.cert.pem"), "utf8");
const tlsCertDERBase64 = pem
  .replace(/-----BEGIN CERTIFICATE-----\n?/, "")
  .replace(/-----END CERTIFICATE-----\n?/, "")
  .replace(/\n/g, "");

// ── 2. WS bearer token from Keychain ─────────────────────────────────────
const tokenResult = spawnSync([
  "security", "find-generic-password",
  "-s", "com.odyssey.app",
  "-a", `odyssey.wstoken.${instanceName}`,
  "-w",
]);
if (tokenResult.exitCode !== 0) {
  process.stderr.write(
    `ERROR: Cannot read WS token from Keychain.\n` +
    `Make sure the Mac Odyssey app has been launched at least once.\n`
  );
  process.exit(1);
}
const bearerToken = new TextDecoder().decode(tokenResult.stdout).trim();

// ── 3. Ed25519 public key via Swift helper ────────────────────────────────
const helperPath = join(scriptDir, "sign-invite-helper.swift");
const pubkeyResult = spawnSync(["swift", helperPath, "--pubkey", instanceName]);
if (pubkeyResult.exitCode !== 0) {
  process.stderr.write(
    `ERROR: Swift helper --pubkey failed:\n${new TextDecoder().decode(pubkeyResult.stderr)}\n`
  );
  process.exit(1);
}
const hostPublicKeyBase64url = new TextDecoder().decode(pubkeyResult.stdout).trim();

// ── 4. Build payload (omit null/nil — matches Swift's encodeIfPresent) ────
const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
// hints: only include non-null fields
const hints: Record<string, string> = { lan: "127.0.0.1:9849" };
// turn: nil → omit entirely
const payload: Record<string, unknown> = {
  bearerToken,
  expiresAt,
  hints,
  hostDisplayName: instanceName,
  hostPublicKeyBase64url,
  tlsCertDERBase64,
};

// ── 5. Canonical JSON: deep-sort keys, omit null/undefined ────────────────
// Must exactly match what Swift's JSONSerialization produces with .sortedKeys,
// since OdysseyCore's verify() re-encodes the struct to build the canonical bytes.
function sortKeysDeep(obj: unknown): unknown {
  if (Array.isArray(obj)) return obj.map(sortKeysDeep);
  if (obj !== null && typeof obj === "object") {
    return Object.fromEntries(
      Object.entries(obj as Record<string, unknown>)
        .filter(([, v]) => v !== null && v !== undefined)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([k, v]) => [k, sortKeysDeep(v)])
    );
  }
  return obj;
}
const canonical = JSON.stringify(sortKeysDeep(payload));

// ── 6. Sign canonical JSON ────────────────────────────────────────────────
const signResult = spawnSync(
  ["swift", helperPath, "--sign", instanceName],
  { stdin: new TextEncoder().encode(canonical) }
);
if (signResult.exitCode !== 0) {
  process.stderr.write(
    `ERROR: Swift helper --sign failed:\n${new TextDecoder().decode(signResult.stderr)}\n`
  );
  process.exit(1);
}
const signature = new TextDecoder().decode(signResult.stdout).trim();

// ── 7. Full payload → base64url invite code ───────────────────────────────
// Full JSON includes signature. Field order doesn't matter here (decoder
// doesn't sort when decoding, only when re-encoding for verify()).
const fullPayload = { ...payload, signature };
const base64url = Buffer.from(JSON.stringify(fullPayload))
  .toString("base64")
  .replace(/\+/g, "-")
  .replace(/\//g, "_")
  .replace(/=/g, "");

process.stdout.write(base64url + "\n");
