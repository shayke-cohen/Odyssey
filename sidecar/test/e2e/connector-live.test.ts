/**
 * Live connector smoke tests.
 *
 * These tests hit real third-party provider APIs and are skipped unless
 * CLAUDESTUDIO_CONNECTOR_LIVE=1 is set.
 *
 * WhatsApp read-only smoke:
 *   CLAUDESTUDIO_CONNECTOR_LIVE=1 \
 *   WHATSAPP_ACCESS_TOKEN=... \
 *   WHATSAPP_WABA_ID=... \
 *   bun test sidecar/test/e2e/connector-live.test.ts
 *
 * Optional WhatsApp write smoke:
 *   CLAUDESTUDIO_CONNECTOR_LIVE=1 \
 *   CLAUDESTUDIO_CONNECTOR_LIVE_WRITE=1 \
 *   WHATSAPP_ACCESS_TOKEN=... \
 *   WHATSAPP_WABA_ID=... \
 *   WHATSAPP_PHONE_NUMBER_ID=... \
 *   WHATSAPP_TEMPLATE_NAME=... \
 *   WHATSAPP_TO=... \
 *   bun test sidecar/test/e2e/connector-live.test.ts
 */
import { describe, expect, test } from "bun:test";
import { executeConnectorCapability, probeConnector } from "../../src/connectors/provider-runtime.js";
import type { RuntimeConnectorState } from "../../src/stores/connector-store.js";

const isLive = process.env.CLAUDESTUDIO_CONNECTOR_LIVE === "1";
const isWriteLive = isLive && process.env.CLAUDESTUDIO_CONNECTOR_LIVE_WRITE === "1";
const liveTest = isLive ? test : test.skip;

const hasWhatsAppReadEnv = Boolean(
  process.env.WHATSAPP_ACCESS_TOKEN && process.env.WHATSAPP_WABA_ID,
);
const hasWhatsAppWriteEnv = Boolean(
  hasWhatsAppReadEnv &&
  process.env.WHATSAPP_PHONE_NUMBER_ID &&
  process.env.WHATSAPP_TEMPLATE_NAME &&
  process.env.WHATSAPP_TO,
);

const whatsappReadTest = isLive && hasWhatsAppReadEnv ? test : test.skip;
const whatsappWriteTest = isWriteLive && hasWhatsAppWriteEnv ? test : test.skip;

function makeWhatsAppEntry(): RuntimeConnectorState {
  return {
    connection: {
      id: "live-whatsapp",
      provider: "whatsapp",
      installScope: "system",
      displayName: "WhatsApp Live Sandbox",
      grantedScopes: ["whatsapp_business_management", "whatsapp_business_messaging"],
      authMode: "brokered",
      writePolicy: "require-approval",
      status: "connected",
      accountId: process.env.WHATSAPP_WABA_ID,
      accountMetadataJSON: JSON.stringify({
        wabaId: process.env.WHATSAPP_WABA_ID,
        phoneNumberId: process.env.WHATSAPP_PHONE_NUMBER_ID,
      }),
    },
    credentials: {
      accessToken: process.env.WHATSAPP_ACCESS_TOKEN,
    },
  };
}

describe("Live connector smoke", () => {
  liveTest("documents missing env when live connector mode is enabled without provider setup", () => {
    if (hasWhatsAppReadEnv) {
      expect(true).toBe(true);
      return;
    }

    const missing: string[] = [];
    if (!process.env.WHATSAPP_ACCESS_TOKEN) missing.push("WHATSAPP_ACCESS_TOKEN");
    if (!process.env.WHATSAPP_WABA_ID) missing.push("WHATSAPP_WABA_ID");
    expect(missing.length).toBeGreaterThan(0);
  });

  whatsappReadTest("WhatsApp probeConnector validates the business account", async () => {
    const entry = makeWhatsAppEntry();
    const result = await probeConnector(entry);

    expect(result.connection.status).toBe("connected");
    expect(result.connection.accountId).toBeTruthy();
    expect(result.connection.statusMessage).toContain("WhatsApp Business");
  }, 30000);

  whatsappReadTest("WhatsApp list templates returns a provider response", async () => {
    const entry = makeWhatsAppEntry();
    const result = await executeConnectorCapability(
      entry,
      {
        toolName: "whatsapp_list_templates",
        provider: "whatsapp",
        title: "List WhatsApp templates",
        description: "",
        access: "read",
        requiredScopes: ["whatsapp_business_management"],
      },
      { limit: 10 },
    ) as any;

    expect(result).toBeDefined();
    expect(typeof result).toBe("object");
  }, 30000);

  whatsappWriteTest("WhatsApp send template succeeds when explicit live write mode is enabled", async () => {
    const entry = makeWhatsAppEntry();
    const result = await executeConnectorCapability(
      entry,
      {
        toolName: "whatsapp_send_template",
        provider: "whatsapp",
        title: "Send WhatsApp template",
        description: "",
        access: "write",
        requiredScopes: ["whatsapp_business_messaging"],
      },
      {
        to: process.env.WHATSAPP_TO!,
        template: process.env.WHATSAPP_TEMPLATE_NAME!,
        languageCode: process.env.WHATSAPP_LANGUAGE_CODE ?? "en_US",
      },
    ) as any;

    expect(result).toBeDefined();
    expect(typeof result).toBe("object");
  }, 30000);
});
