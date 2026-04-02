import { describe, expect, test } from "bun:test";
import { executeConnectorCapability, probeConnector } from "../../src/connectors/provider-runtime.js";
import type { RuntimeConnectorState } from "../../src/stores/connector-store.js";

function makeEntry(overrides: Partial<RuntimeConnectorState["connection"]> = {}): RuntimeConnectorState {
  return {
    connection: {
      id: "conn-1",
      provider: "x",
      installScope: "system",
      displayName: "Connector",
      grantedScopes: [],
      authMode: "pkce-native",
      writePolicy: "require-approval",
      status: "connected",
      ...overrides,
    },
    credentials: {
      accessToken: "token-123",
    },
  };
}

describe("provider runtime", () => {
  test("probeConnector populates X identity metadata", async () => {
    const entry = makeEntry({ provider: "x", displayName: "X Sandbox" });
    const result = await probeConnector(entry, async () =>
      new Response(JSON.stringify({
        data: {
          id: "user-1",
          username: "sandbox",
          name: "Sandbox User",
        },
      }), { status: 200 }));

    expect(result.connection.accountId).toBe("user-1");
    expect(result.connection.accountHandle).toBe("@sandbox");
    expect(result.connection.status).toBe("connected");
  });

  test("executeConnectorCapability posts a Slack message with channel + text", async () => {
    const entry = makeEntry({
      provider: "slack",
      displayName: "Slack",
      authMode: "brokered",
    });

    let capturedBody = "";
    const response = await executeConnectorCapability(
      entry,
      {
        toolName: "slack_post_message",
        provider: "slack",
        title: "Post Slack message",
        description: "",
        access: "write",
        requiredScopes: ["chat:write"],
      },
      { channel: "C123", text: "hello world" },
      async (_input, init) => {
        capturedBody = String(init?.body ?? "");
        return new Response(JSON.stringify({ ok: true, channel: "C123", ts: "123.45" }), { status: 200 });
      },
    );

    expect(capturedBody).toContain("\"channel\":\"C123\"");
    expect(capturedBody).toContain("\"text\":\"hello world\"");
    expect((response as any).ok).toBe(true);
  });

  test("executeConnectorCapability sends WhatsApp template using metadata phone number id", async () => {
    const entry = makeEntry({
      provider: "whatsapp",
      authMode: "brokered",
      accountId: "waba-1",
      accountMetadataJSON: JSON.stringify({ phoneNumberId: "phone-9" }),
    });

    let capturedURL = "";
    let capturedBody = "";
    await executeConnectorCapability(
      entry,
      {
        toolName: "whatsapp_send_template",
        provider: "whatsapp",
        title: "Send WhatsApp template",
        description: "",
        access: "write",
        requiredScopes: ["whatsapp_business_messaging"],
      },
      { to: "+15551234567", template: "hello_world", languageCode: "en_US" },
      async (input, init) => {
        capturedURL = input.toString();
        capturedBody = String(init?.body ?? "");
        return new Response(JSON.stringify({ messages: [{ id: "wamid.1" }] }), { status: 200 });
      },
    );

    expect(capturedURL).toContain("/phone-9/messages");
    expect(capturedBody).toContain("\"template\"");
    expect(capturedBody).toContain("\"hello_world\"");
  });

  test("probeConnector marks WhatsApp connections as needs-attention without a WABA id", async () => {
    const entry = makeEntry({
      provider: "whatsapp",
      authMode: "brokered",
      displayName: "WhatsApp",
    });

    const result = await probeConnector(entry);
    expect(result.connection.status).toBe("needs-attention");
    expect(result.connection.statusMessage).toContain("Business Account ID");
    expect(result.details).toEqual({ requires: ["wabaId"] });
  });

  test("executeConnectorCapability surfaces provider HTTP errors", async () => {
    const entry = makeEntry({ provider: "x", displayName: "X Sandbox" });

    await expect(executeConnectorCapability(
      entry,
      {
        toolName: "x_post_tweet",
        provider: "x",
        title: "Post X update",
        description: "",
        access: "write",
        requiredScopes: ["tweet.write"],
      },
      { text: "hello" },
      async () => new Response(JSON.stringify({ error: "rate limited" }), { status: 429 }),
    )).rejects.toThrow("rate limited");
  });

  test("executeConnectorCapability requires an access token for runtime calls", async () => {
    const entry = makeEntry({ provider: "slack", displayName: "Slack" });
    entry.credentials = undefined;

    await expect(executeConnectorCapability(
      entry,
      {
        toolName: "slack_list_channels",
        provider: "slack",
        title: "List Slack channels",
        description: "",
        access: "read",
        requiredScopes: ["channels:read"],
      },
      {},
    )).rejects.toThrow("Slack is missing an access token.");
  });
});
