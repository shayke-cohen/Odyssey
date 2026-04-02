import type { RuntimeConnectorState } from "../stores/connector-store.js";
import type { ConnectorCapability, ConnectorConfig } from "../types.js";

type Fetcher = typeof fetch;

export interface ConnectorProbeResult {
  connection: ConnectorConfig;
  details: unknown;
}

export async function probeConnector(
  entry: RuntimeConnectorState,
  fetcher: Fetcher = fetch,
): Promise<ConnectorProbeResult> {
  switch (entry.connection.provider) {
    case "slack":
      return probeSlack(entry, fetcher);
    case "linkedin":
      return probeLinkedIn(entry, fetcher);
    case "x":
      return probeX(entry, fetcher);
    case "facebook":
      return probeFacebook(entry, fetcher);
    case "whatsapp":
      return probeWhatsApp(entry, fetcher);
  }
}

export async function executeConnectorCapability(
  entry: RuntimeConnectorState,
  capability: ConnectorCapability,
  args: Record<string, unknown>,
  fetcher: Fetcher = fetch,
): Promise<unknown> {
  switch (capability.toolName) {
    case "slack_list_channels":
      return slackListChannels(entry, args, fetcher);
    case "slack_post_message":
      return slackPostMessage(entry, args, fetcher);
    case "linkedin_get_profile":
      return linkedinGetProfile(entry, fetcher);
    case "linkedin_create_post":
      return linkedinCreatePost(entry, args, fetcher);
    case "x_get_profile":
      return xGetProfile(entry, fetcher);
    case "x_post_tweet":
      return xPostTweet(entry, args, fetcher);
    case "facebook_get_identity":
      return facebookGetIdentity(entry, fetcher);
    case "facebook_create_post":
      return facebookCreatePost(entry, args, fetcher);
    case "whatsapp_list_templates":
      return whatsappListTemplates(entry, args, fetcher);
    case "whatsapp_send_template":
      return whatsappSendTemplate(entry, args, fetcher);
    default:
      throw new Error(`Unsupported connector tool: ${capability.toolName}`);
  }
}

async function probeSlack(entry: RuntimeConnectorState, fetcher: Fetcher): Promise<ConnectorProbeResult> {
  const response = await slackAPICall(entry, "auth.test", undefined, fetcher);
  return {
    connection: {
      ...entry.connection,
      accountId: response.team_id ?? entry.connection.accountId,
      accountHandle: response.team ?? entry.connection.accountHandle,
      accountMetadataJSON: JSON.stringify({
        teamId: response.team_id,
        team: response.team,
        userId: response.user_id,
        user: response.user,
        url: response.url,
      }),
      status: "connected",
      statusMessage: `Connected to ${response.team ?? "Slack workspace"}.`,
      lastCheckedAt: new Date().toISOString(),
    },
    details: response,
  };
}

async function probeLinkedIn(entry: RuntimeConnectorState, fetcher: Fetcher): Promise<ConnectorProbeResult> {
  const response = await bearerJSON("https://api.linkedin.com/v2/userinfo", entry, undefined, fetcher);
  const handle = response.email ?? response.name ?? response.localizedFirstName ?? entry.connection.accountHandle;
  return {
    connection: {
      ...entry.connection,
      accountId: response.sub ?? entry.connection.accountId,
      accountHandle: handle,
      accountMetadataJSON: JSON.stringify(response),
      status: "connected",
      statusMessage: `Connected to LinkedIn as ${handle ?? "authorized member"}.`,
      lastCheckedAt: new Date().toISOString(),
    },
    details: response,
  };
}

async function probeX(entry: RuntimeConnectorState, fetcher: Fetcher): Promise<ConnectorProbeResult> {
  const response = await bearerJSON(
    "https://api.x.com/2/users/me?user.fields=id,name,username,profile_image_url",
    entry,
    undefined,
    fetcher,
  );
  const user = response.data ?? response;
  return {
    connection: {
      ...entry.connection,
      accountId: user.id ?? entry.connection.accountId,
      accountHandle: user.username ? `@${user.username}` : entry.connection.accountHandle,
      accountMetadataJSON: JSON.stringify(user),
      status: "connected",
      statusMessage: `Connected to X as ${user.username ? `@${user.username}` : "authorized account"}.`,
      lastCheckedAt: new Date().toISOString(),
    },
    details: user,
  };
}

async function probeFacebook(entry: RuntimeConnectorState, fetcher: Fetcher): Promise<ConnectorProbeResult> {
  const response = await bearerJSON(
    "https://graph.facebook.com/v22.0/me?fields=id,name",
    entry,
    undefined,
    fetcher,
  );
  return {
    connection: {
      ...entry.connection,
      accountId: response.id ?? entry.connection.accountId,
      accountHandle: response.name ?? entry.connection.accountHandle,
      accountMetadataJSON: JSON.stringify(response),
      status: "connected",
      statusMessage: `Connected to Facebook as ${response.name ?? "authorized identity"}.`,
      lastCheckedAt: new Date().toISOString(),
    },
    details: response,
  };
}

async function probeWhatsApp(entry: RuntimeConnectorState, fetcher: Fetcher): Promise<ConnectorProbeResult> {
  const metadata = parseMetadata(entry.connection);
  const wabaId = metadata.wabaId ?? entry.connection.accountId;
  if (!wabaId) {
    return {
      connection: {
        ...entry.connection,
        status: "needs-attention",
        statusMessage: "Connected token is present, but WhatsApp Business Account ID is still required.",
        lastCheckedAt: new Date().toISOString(),
      },
      details: { requires: ["wabaId"] },
    };
  }

  const response = await bearerJSON(
    `https://graph.facebook.com/v22.0/${encodeURIComponent(wabaId)}?fields=id,name`,
    entry,
    undefined,
    fetcher,
  );
  return {
    connection: {
      ...entry.connection,
      accountId: response.id ?? wabaId,
      accountHandle: response.name ?? entry.connection.accountHandle,
      accountMetadataJSON: JSON.stringify({ ...metadata, ...response, wabaId }),
      status: "connected",
      statusMessage: `Connected to WhatsApp Business ${response.name ?? response.id ?? wabaId}.`,
      lastCheckedAt: new Date().toISOString(),
    },
    details: response,
  };
}

async function slackListChannels(entry: RuntimeConnectorState, args: Record<string, unknown>, fetcher: Fetcher) {
  const limit = typeof args.limit === "number" ? Math.max(1, Math.min(200, Math.trunc(args.limit))) : 100;
  return slackAPICall(
    entry,
    `conversations.list?exclude_archived=true&limit=${limit}&types=public_channel,private_channel`,
    undefined,
    fetcher,
  );
}

async function slackPostMessage(entry: RuntimeConnectorState, args: Record<string, unknown>, fetcher: Fetcher) {
  const channel = asRequiredString(args.channel, "channel");
  const text = asRequiredString(args.text, "text");
  return slackAPICall(entry, "chat.postMessage", { channel, text }, fetcher);
}

async function linkedinGetProfile(entry: RuntimeConnectorState, fetcher: Fetcher) {
  return bearerJSON("https://api.linkedin.com/v2/userinfo", entry, undefined, fetcher);
}

async function linkedinCreatePost(entry: RuntimeConnectorState, args: Record<string, unknown>, fetcher: Fetcher) {
  const text = asRequiredString(args.text, "text");
  const personId = entry.connection.accountId ?? parseMetadata(entry.connection).personId;
  if (!personId) {
    throw new Error("LinkedIn post requires an authenticated member id. Run connector test first.");
  }

  return bearerJSON(
    "https://api.linkedin.com/v2/ugcPosts",
    entry,
    {
      method: "POST",
      headers: {
        "X-Restli-Protocol-Version": "2.0.0",
      },
      body: JSON.stringify({
        author: `urn:li:person:${personId}`,
        lifecycleState: "PUBLISHED",
        specificContent: {
          "com.linkedin.ugc.ShareContent": {
            shareCommentary: { text },
            shareMediaCategory: "NONE",
          },
        },
        visibility: {
          "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC",
        },
      }),
    },
    fetcher,
  );
}

async function xGetProfile(entry: RuntimeConnectorState, fetcher: Fetcher) {
  return bearerJSON(
    "https://api.x.com/2/users/me?user.fields=id,name,username,profile_image_url",
    entry,
    undefined,
    fetcher,
  );
}

async function xPostTweet(entry: RuntimeConnectorState, args: Record<string, unknown>, fetcher: Fetcher) {
  const text = asRequiredString(args.text, "text");
  return bearerJSON(
    "https://api.x.com/2/tweets",
    entry,
    {
      method: "POST",
      body: JSON.stringify({ text }),
    },
    fetcher,
  );
}

async function facebookGetIdentity(entry: RuntimeConnectorState, fetcher: Fetcher) {
  return bearerJSON("https://graph.facebook.com/v22.0/me?fields=id,name", entry, undefined, fetcher);
}

async function facebookCreatePost(entry: RuntimeConnectorState, args: Record<string, unknown>, fetcher: Fetcher) {
  const text = asRequiredString(args.text, "text");
  const target = asOptionalString(args.target) ?? "me";
  return bearerJSON(
    `https://graph.facebook.com/v22.0/${encodeURIComponent(target)}/feed`,
    entry,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ message: text }).toString(),
    },
    fetcher,
  );
}

async function whatsappListTemplates(entry: RuntimeConnectorState, args: Record<string, unknown>, fetcher: Fetcher) {
  const metadata = parseMetadata(entry.connection);
  const wabaId = metadata.wabaId ?? entry.connection.accountId;
  if (!wabaId) {
    throw new Error("WhatsApp template listing requires a WhatsApp Business Account ID.");
  }
  const limit = typeof args.limit === "number" ? Math.max(1, Math.min(200, Math.trunc(args.limit))) : 100;
  return bearerJSON(
    `https://graph.facebook.com/v22.0/${encodeURIComponent(wabaId)}/message_templates?limit=${limit}`,
    entry,
    undefined,
    fetcher,
  );
}

async function whatsappSendTemplate(entry: RuntimeConnectorState, args: Record<string, unknown>, fetcher: Fetcher) {
  const metadata = parseMetadata(entry.connection);
  const phoneNumberId = metadata.phoneNumberId ?? entry.connection.accountId;
  if (!phoneNumberId) {
    throw new Error("WhatsApp send requires a phone number ID in account metadata.");
  }

  const to = asRequiredString(args.to, "to");
  const template = asRequiredString(args.template, "template");
  const languageCode = asOptionalString(args.languageCode) ?? "en_US";

  return bearerJSON(
    `https://graph.facebook.com/v22.0/${encodeURIComponent(phoneNumberId)}/messages`,
    entry,
    {
      method: "POST",
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to,
        type: "template",
        template: {
          name: template,
          language: { code: languageCode },
        },
      }),
    },
    fetcher,
  );
}

async function slackAPICall(
  entry: RuntimeConnectorState,
  method: string,
  body: Record<string, unknown> | undefined,
  fetcher: Fetcher,
) {
  const token = requireAccessToken(entry);
  const response = await fetcher(`https://slack.com/api/${method}`, {
    method: body ? "POST" : "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      ...(body ? { "Content-Type": "application/json; charset=utf-8" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await parseJSONResponse(response);
  if (json.ok === false) {
    throw new Error(json.error ?? "Slack API call failed.");
  }
  return json;
}

async function bearerJSON(
  url: string,
  entry: RuntimeConnectorState,
  init: RequestInit | undefined,
  fetcher: Fetcher,
) {
  const token = requireAccessToken(entry);
  const response = await fetcher(url, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  return parseJSONResponse(response);
}

function requireAccessToken(entry: RuntimeConnectorState): string {
  const token = entry.credentials?.accessToken;
  if (!token) {
    throw new Error(`${entry.connection.displayName} is missing an access token.`);
  }
  return token;
}

async function parseJSONResponse(response: Response) {
  const text = await response.text();
  const json = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new Error(json.error?.message ?? json.error ?? json.message ?? `HTTP ${response.status}`);
  }
  return json;
}

function asRequiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Connector input is missing "${field}".`);
  }
  return value.trim();
}

function asOptionalString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function parseMetadata(connection: ConnectorConfig): Record<string, string> {
  if (!connection.accountMetadataJSON) {
    return {};
  }
  try {
    const parsed = JSON.parse(connection.accountMetadataJSON);
    return typeof parsed === "object" && parsed !== null ? parsed as Record<string, string> : {};
  } catch {
    return {};
  }
}
