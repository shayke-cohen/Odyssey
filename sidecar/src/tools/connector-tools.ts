import { z } from "zod";
import type { ToolContext } from "./tool-context.js";
import { createTextResult, defineSharedTool, type SharedToolDefinition } from "./shared-tool.js";
import { requestConfirmation } from "./rich-display-tools.js";
import {
  providerCapabilitiesForConnection,
  writeRequiresApproval,
} from "../connectors/provider-catalog.js";
import type { ConnectorCapability } from "../types.js";
import { executeConnectorCapability } from "../connectors/provider-runtime.js";

export function createConnectorTools(ctx: ToolContext, callingSessionId: string): SharedToolDefinition[] {
  const definitions: SharedToolDefinition[] = [
    defineSharedTool(
      "connector_list_connections",
      "List all configured system-wide connectors currently visible to this session.",
      {},
      async () => {
        const connections = ctx.connectors.listConfigs().map((connection) => ({
          id: connection.id,
          provider: connection.provider,
          displayName: connection.displayName,
          status: connection.status,
          writePolicy: connection.writePolicy,
          grantedScopes: connection.grantedScopes,
        }));
        return createTextResult({ connections });
      },
    ),
  ];

  for (const entry of ctx.connectors.list()) {
    if (!entry.credentials?.accessToken) {
      continue;
    }
    for (const capability of providerCapabilitiesForConnection(entry.connection)) {
      definitions.push(buildCapabilityTool(ctx, callingSessionId, entry.connection.id, capability));
    }
  }

  return definitions;
}

function buildCapabilityTool(
  ctx: ToolContext,
  callingSessionId: string,
  connectionId: string,
  capability: ConnectorCapability,
): SharedToolDefinition {
  const inputSchema = toolInputSchema(capability);

  return defineSharedTool(
    capability.toolName,
    capability.description,
    inputSchema,
    async (args) => {
      const entry = ctx.connectors.get(connectionId);
      if (!entry) {
        return createTextResult({ error: "connector_not_found", connectionId }, false);
      }
      const connection = entry.connection;

      if (capability.access === "write" && connection.writePolicy === "read-only") {
        ctx.broadcast({
          type: "connector.audit",
          sessionId: callingSessionId,
          connectionId: connection.id,
          provider: connection.provider,
          action: capability.toolName,
          outcome: "blocked",
          summary: "Write blocked by read-only policy.",
        });
        return createTextResult({ error: "read_only_policy", provider: connection.provider }, false);
      }

      if (capability.access === "write" && writeRequiresApproval(connection.writePolicy)) {
        const confirmation = await requestConfirmation(ctx, callingSessionId, {
          action: capability.toolName,
          reason: `The ${connection.displayName} connector requires approval before mutating actions.`,
          riskLevel: "medium",
          details: confirmationDetails(capability.toolName, args),
        });
        if (!confirmation.approved) {
          ctx.broadcast({
            type: "connector.audit",
            sessionId: callingSessionId,
            connectionId: connection.id,
            provider: connection.provider,
            action: capability.toolName,
            outcome: "denied",
            summary: "User denied connector write approval.",
          });
          return createTextResult({ approved: false, provider: connection.provider }, false);
        }
      }

      try {
        const response = await executeConnectorCapability(entry, capability, args ?? {});

        ctx.broadcast({
          type: "connector.audit",
          sessionId: callingSessionId,
          connectionId: connection.id,
          provider: connection.provider,
          action: capability.toolName,
          outcome: "allowed",
          summary: capability.access === "write"
            ? "Write action completed successfully."
            : "Read action completed successfully.",
        });

        return createTextResult(response);
      } catch (error) {
        const message = error instanceof Error ? error.message : "Connector action failed.";
        ctx.broadcast({
          type: "connector.audit",
          sessionId: callingSessionId,
          connectionId: connection.id,
          provider: connection.provider,
          action: capability.toolName,
          outcome: "failed",
          summary: message,
        });
        return createTextResult({ error: message, provider: connection.provider, action: capability.toolName }, false);
      }
    },
  );
}

function toolInputSchema(capability: ConnectorCapability): Record<string, z.ZodTypeAny> {
  switch (capability.toolName) {
    case "slack_list_channels":
    case "whatsapp_list_templates":
      return {
        limit: z.number().int().min(1).max(200).optional().describe("Optional max results to return."),
      };
    case "slack_post_message":
      return {
        channel: z.string().describe("Slack channel ID or name."),
        text: z.string().describe("Message text to post."),
      };
    case "linkedin_get_profile":
    case "x_get_profile":
    case "facebook_get_identity":
      return {};
    case "linkedin_create_post":
    case "x_post_tweet":
      return {
        text: z.string().describe("Post body."),
      };
    case "facebook_create_post":
      return {
        target: z.string().optional().describe("Optional page or profile id. Defaults to 'me'."),
        text: z.string().describe("Post body."),
      };
    case "whatsapp_send_template":
      return {
        to: z.string().describe("Destination phone number in international format."),
        template: z.string().describe("Approved WhatsApp template name."),
        languageCode: z.string().optional().describe("Template language code. Defaults to en_US."),
      };
    default:
      return {};
  }
}

function confirmationDetails(toolName: string, args: Record<string, unknown> | undefined): string | undefined {
  switch (toolName) {
    case "slack_post_message":
      return typeof args?.channel === "string" ? `Channel: ${args.channel}` : undefined;
    case "facebook_create_post":
      return typeof args?.target === "string" ? `Target: ${args.target}` : undefined;
    case "whatsapp_send_template":
      return typeof args?.to === "string" ? `Recipient: ${args.to}` : undefined;
    default:
      return undefined;
  }
}
