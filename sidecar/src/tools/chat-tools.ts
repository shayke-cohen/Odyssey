import { z } from "zod";
import { randomUUID } from "crypto";
import type { ToolContext } from "./tool-context.js";
import { createTextResult, defineSharedTool } from "./shared-tool.js";

export function createChatTools(ctx: ToolContext, callingSessionId: string) {
  return [
    defineSharedTool(
      "peer_chat_start",
      "Start a blocking conversation with another agent. Sends the first message and BLOCKS until the other agent replies. Returns the reply or {closed: true} if the conversation ends.",
      {
        to_agent: z.string().describe("Target agent name or session ID"),
        message: z.string().describe("Opening message"),
        topic: z.string().optional().describe("Conversation topic"),
      },
      async (args) => {
        const targetId = resolveAgentTarget(ctx, args.to_agent, callingSessionId);
        if (!targetId) {
          return createTextResult({ error: "agent_not_found", to: args.to_agent }, false);
        }

        const senderState = ctx.sessions.get(callingSessionId);
        const senderName = senderState?.agentName ?? callingSessionId;

        const channel = ctx.channels.create(
          callingSessionId,
          senderName,
          targetId,
          args.message,
          args.topic,
        );

        ctx.broadcast({
          type: "peer.chat",
          sessionId: callingSessionId,
          channelId: channel.id,
          from: senderName,
          message: args.message,
        });

        ctx.messages.push(targetId, {
          id: randomUUID(),
          from: callingSessionId,
          fromAgent: senderName,
          to: targetId,
          text: `[Chat Request] ${args.topic ?? "New conversation"}: ${args.message}`,
          channel: channel.id,
          priority: "urgent",
          timestamp: new Date().toISOString(),
          read: false,
        });

        const reply = await ctx.channels.waitForReply(channel.id, callingSessionId);
        if ("closed" in reply) {
          return createTextResult({ closed: true, summary: reply.summary, channel_id: channel.id });
        }

        return createTextResult({
          channel_id: channel.id,
          reply: reply.text,
          from_agent: reply.fromAgent,
        });
      },
    ),

    defineSharedTool(
      "peer_chat_reply",
      "Reply to an ongoing conversation. BLOCKS until the other participant responds or the conversation closes.",
      {
        channel_id: z.string().describe("Channel ID from peer_chat_start or peer_receive_messages"),
        message: z.string().describe("Reply message"),
      },
      async (args) => {
        const channel = ctx.channels.get(args.channel_id);
        if (!channel) {
          return createTextResult({ error: "channel_not_found", channel_id: args.channel_id }, false);
        }

        const senderState = ctx.sessions.get(callingSessionId);
        const senderName = senderState?.agentName ?? callingSessionId;

        const msg = ctx.channels.addMessage(args.channel_id, callingSessionId, senderName, args.message);
        if (!msg) {
          return createTextResult({ closed: true, channel_id: args.channel_id });
        }

        ctx.broadcast({
          type: "peer.chat",
          sessionId: callingSessionId,
          channelId: args.channel_id,
          from: senderName,
          message: args.message,
        });

        const reply = await ctx.channels.waitForReply(args.channel_id, callingSessionId);
        if ("closed" in reply) {
          return createTextResult({ closed: true, summary: reply.summary, channel_id: args.channel_id });
        }

        return createTextResult({
          channel_id: args.channel_id,
          reply: reply.text,
          from_agent: reply.fromAgent,
        });
      },
    ),

    defineSharedTool(
      "peer_chat_listen",
      "Wait for an incoming chat request from another agent. BLOCKS until a request arrives or timeout.",
      {
        timeout_ms: z.number().optional().describe("Timeout in milliseconds (default: 30000)"),
      },
      async (args) => {
        const channel = await ctx.channels.waitForIncoming(
          callingSessionId,
          args.timeout_ms ?? 30000,
        );

        if (!channel) {
          return createTextResult({ timeout: true, message: "No incoming chat requests within timeout" });
        }

        const lastMsg = channel.messages[channel.messages.length - 1];
        return createTextResult({
          channel_id: channel.id,
          from_agent: lastMsg.fromAgent,
          message: lastMsg.text,
          topic: channel.topic,
        });
      },
    ),

    defineSharedTool(
      "peer_chat_close",
      "End a conversation. All participants waiting for replies will receive {closed: true}.",
      {
        channel_id: z.string().describe("Channel ID to close"),
        summary: z.string().optional().describe("Summary of the conversation outcome"),
      },
      async (args) => {
        ctx.channels.close(args.channel_id, args.summary);

        const senderState = ctx.sessions.get(callingSessionId);
        ctx.broadcast({
          type: "peer.chat",
          sessionId: callingSessionId,
          channelId: args.channel_id,
          from: senderState?.agentName ?? callingSessionId,
          message: `[closed] ${args.summary ?? "Conversation ended"}`,
        });

        return createTextResult({ closed: true, channel_id: args.channel_id });
      },
    ),

    defineSharedTool(
      "peer_chat_invite",
      "Invite another agent into an existing conversation (group chat).",
      {
        channel_id: z.string().describe("Channel ID of the existing conversation"),
        agent: z.string().describe("Agent name or session ID to invite"),
        context: z.string().optional().describe("Context to provide to the invited agent"),
      },
      async (args) => {
        const targetId = resolveAgentTarget(ctx, args.agent, callingSessionId);
        if (!targetId) {
          return createTextResult({ error: "agent_not_found", agent: args.agent }, false);
        }

        const added = ctx.channels.addParticipant(args.channel_id, targetId);
        if (!added) {
          return createTextResult({ error: "channel_not_found_or_closed", channel_id: args.channel_id }, false);
        }

        const senderState = ctx.sessions.get(callingSessionId);
        const targetState = ctx.sessions.get(targetId);
        ctx.messages.push(targetId, {
          id: randomUUID(),
          from: callingSessionId,
          fromAgent: senderState?.agentName ?? callingSessionId,
          to: targetId,
          text: `[Chat Invite] You've been invited to channel ${args.channel_id}${args.context ? `: ${args.context}` : ""}`,
          channel: args.channel_id,
          priority: "urgent",
          timestamp: new Date().toISOString(),
          read: false,
        });

        ctx.broadcast({
          type: "agent.invited",
          sessionId: callingSessionId,
          invitedAgent: targetState?.agentName ?? args.agent,
          invitedBy: senderState?.agentName ?? callingSessionId,
          channelId: args.channel_id,
        });

        return createTextResult({ invited: true, agent: args.agent, channel_id: args.channel_id });
      },
    ),

    defineSharedTool(
      "group_invite_agent",
      "Invite an agent to join your current conversation as a group member. The invited agent will see the full chat transcript and can participate alongside you. Use peer_list_agents() first to see available agents.",
      {
        agent_name: z.string().describe("Name of the agent to invite (e.g. 'Coder', 'Reviewer')"),
      },
      async (args, extra: any) => {
        const sessionId = extra?.sessionId ?? callingSessionId;

        ctx.broadcast({
          type: "conversation.inviteAgent",
          sessionId,
          agentName: args.agent_name,
        });

        return createTextResult({
          invited: true,
          agent: args.agent_name,
          note: "The agent is being added to your conversation. They will see the transcript and can participate.",
        });
      },
    ),
  ];
}

function resolveAgentTarget(
  ctx: ToolContext,
  nameOrId: string,
  excludeSessionId: string,
): string | undefined {
  if (ctx.sessions.get(nameOrId) && nameOrId !== excludeSessionId) return nameOrId;

  const sessions = ctx.sessions.list();
  const match = sessions.find(
    (s) => s.agentName.toLowerCase() === nameOrId.toLowerCase() && s.id !== excludeSessionId,
  );
  return match?.id;
}
