import { describe, expect, test } from "bun:test";
import { providerCapabilitiesForConnection, writeRequiresApproval } from "../../src/connectors/provider-catalog.js";
import type { ConnectorConfig } from "../../src/types.js";

function makeConnection(overrides: Partial<ConnectorConfig> = {}): ConnectorConfig {
  return {
    id: "conn-1",
    provider: "slack",
    installScope: "system",
    displayName: "Connector",
    grantedScopes: [],
    authMode: "brokered",
    writePolicy: "require-approval",
    status: "connected",
    ...overrides,
  };
}

describe("provider capability catalog", () => {
  test("connected connectors expose both read and write capabilities when scopes allow", () => {
    const capabilities = providerCapabilitiesForConnection(makeConnection({
      provider: "slack",
      grantedScopes: ["channels:read", "chat:write"],
      writePolicy: "autonomous",
    }));

    expect(capabilities.map((entry) => entry.toolName)).toEqual([
      "slack_list_channels",
      "slack_post_message",
    ]);
  });

  test("missing scopes hide write capabilities", () => {
    const capabilities = providerCapabilitiesForConnection(makeConnection({
      provider: "x",
      authMode: "pkce-native",
      grantedScopes: ["users.read"],
    }));

    expect(capabilities.map((entry) => entry.toolName)).toEqual(["x_get_profile"]);
  });

  test("read-only policy hides write capabilities but keeps read tools", () => {
    const capabilities = providerCapabilitiesForConnection(makeConnection({
      provider: "facebook",
      grantedScopes: ["public_profile", "pages_manage_posts"],
      writePolicy: "read-only",
    }));

    expect(capabilities.map((entry) => entry.toolName)).toEqual(["facebook_get_identity"]);
  });

  test("disconnected connectors expose no capabilities", () => {
    const capabilities = providerCapabilitiesForConnection(makeConnection({
      provider: "linkedin",
      authMode: "pkce-native",
      grantedScopes: ["openid", "w_member_social"],
      status: "revoked",
    }));

    expect(capabilities).toEqual([]);
  });

  test("write approval helper only returns true for require-approval", () => {
    expect(writeRequiresApproval("require-approval")).toBe(true);
    expect(writeRequiresApproval("autonomous")).toBe(false);
    expect(writeRequiresApproval("read-only")).toBe(false);
  });
});
