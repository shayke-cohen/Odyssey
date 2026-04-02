import type {
  ConnectionWritePolicy,
  ConnectorCapability,
  ConnectorConfig,
  ConnectorProvider,
} from "../types.js";

const CAPABILITIES: Record<ConnectorProvider, ConnectorCapability[]> = {
  slack: [
    {
      toolName: "slack_list_channels",
      provider: "slack",
      title: "List Slack channels",
      description: "Inspect available Slack channels for the connected workspace.",
      access: "read",
      requiredScopes: ["channels:read"],
    },
    {
      toolName: "slack_post_message",
      provider: "slack",
      title: "Post Slack message",
      description: "Post a message into a Slack channel for the connected workspace.",
      access: "write",
      requiredScopes: ["chat:write"],
    },
  ],
  linkedin: [
    {
      toolName: "linkedin_get_profile",
      provider: "linkedin",
      title: "Get LinkedIn profile",
      description: "Inspect the authorized LinkedIn member profile metadata.",
      access: "read",
      requiredScopes: ["openid"],
    },
    {
      toolName: "linkedin_create_post",
      provider: "linkedin",
      title: "Create LinkedIn post",
      description: "Create a LinkedIn post on behalf of the connected member.",
      access: "write",
      requiredScopes: ["w_member_social"],
    },
  ],
  x: [
    {
      toolName: "x_get_profile",
      provider: "x",
      title: "Get X profile",
      description: "Inspect the connected X account profile metadata.",
      access: "read",
      requiredScopes: ["users.read"],
    },
    {
      toolName: "x_post_tweet",
      provider: "x",
      title: "Post X update",
      description: "Create a post for the connected X account.",
      access: "write",
      requiredScopes: ["tweet.write"],
    },
  ],
  facebook: [
    {
      toolName: "facebook_get_identity",
      provider: "facebook",
      title: "Get Facebook identity",
      description: "Inspect the connected Facebook or Meta identity metadata.",
      access: "read",
      requiredScopes: ["public_profile"],
    },
    {
      toolName: "facebook_create_post",
      provider: "facebook",
      title: "Create Facebook post",
      description: "Create a post for the connected Facebook page or business account.",
      access: "write",
      requiredScopes: ["pages_manage_posts"],
    },
  ],
  whatsapp: [
    {
      toolName: "whatsapp_list_templates",
      provider: "whatsapp",
      title: "List WhatsApp templates",
      description: "Inspect WhatsApp business templates for the connected account.",
      access: "read",
      requiredScopes: ["whatsapp_business_management"],
    },
    {
      toolName: "whatsapp_send_template",
      provider: "whatsapp",
      title: "Send WhatsApp template",
      description: "Send a WhatsApp template message through the connected business account.",
      access: "write",
      requiredScopes: ["whatsapp_business_messaging"],
    },
  ],
};

export function providerCapabilitiesForConnection(connection: ConnectorConfig): ConnectorCapability[] {
  if (connection.status !== "connected") {
    return [];
  }

  return CAPABILITIES[connection.provider].filter((capability) => {
    if (!hasRequiredScopes(connection.grantedScopes, capability.requiredScopes)) {
      return false;
    }
    if (capability.access === "write" && connection.writePolicy === "read-only") {
      return false;
    }
    return true;
  });
}

export function writeRequiresApproval(writePolicy: ConnectionWritePolicy): boolean {
  return writePolicy === "require-approval";
}

function hasRequiredScopes(grantedScopes: string[], requiredScopes: string[]): boolean {
  const granted = new Set(grantedScopes.map((scope) => scope.trim()));
  return requiredScopes.every((scope) => granted.has(scope));
}
