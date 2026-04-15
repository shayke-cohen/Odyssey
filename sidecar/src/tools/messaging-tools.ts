import { z } from "zod";
import { randomUUID } from "crypto";
import type { ToolContext } from "./tool-context.js";
import { createTextResult, defineSharedTool } from "./shared-tool.js";
import type { OdysseyP2PEnvelope } from '../types.js';

export function createMessagingTools(ctx: ToolContext, callingSessionId: string) {
  return [
    defineSharedTool(
      "peer_send_message",
      "Send a direct async message to another agent. Returns immediately without waiting for a reply. The target agent will see this in their inbox when they call peer_receive_messages.",
      {
        to_agent: z.string().describe("Target agent session ID or agent name"),
        message: z.string().describe("Message text to send"),
        priority: z.enum(["normal", "urgent"]).optional().describe("Message priority (default: normal)"),
      },
      async (args) => {
        const targetId = resolveAgentId(ctx, args.to_agent);
        if (!targetId) {
          return createTextResult({ error: "agent_not_found", to: args.to_agent }, false);
        }

        const senderState = ctx.sessions.get(callingSessionId);
        const msg = {
          id: randomUUID(),
          from: callingSessionId,
          fromAgent: senderState?.agentName ?? callingSessionId,
          to: targetId,
          text: args.message,
          priority: args.priority ?? "normal" as const,
          timestamp: new Date().toISOString(),
          read: false,
        };
        ctx.messages.push(targetId, msg);

        ctx.broadcast({
          type: "peer.chat",
          sessionId: callingSessionId,
          channelId: `dm-${callingSessionId}-${targetId}`,
          from: senderState?.agentName ?? callingSessionId,
          message: args.message,
        });

        return createTextResult({ sent: true, to: args.to_agent });
      },
    ),

    defineSharedTool(
      "peer_broadcast",
      "Broadcast a message to all active agents on a named channel. All agents will receive this in their inbox.",
      {
        channel: z.string().describe("Channel name (e.g. 'status', 'findings')"),
        message: z.string().describe("Message to broadcast"),
      },
      async (args) => {
        const senderState = ctx.sessions.get(callingSessionId);
        const activeIds = ctx.sessions.listActive().map((s) => s.id);
        const msg = {
          id: randomUUID(),
          from: callingSessionId,
          fromAgent: senderState?.agentName ?? callingSessionId,
          text: args.message,
          channel: args.channel,
          priority: "normal" as const,
          timestamp: new Date().toISOString(),
          read: false,
        };
        ctx.messages.pushToAll(msg, activeIds);

        ctx.broadcast({
          type: "peer.chat",
          sessionId: callingSessionId,
          channelId: `broadcast-${args.channel}`,
          from: senderState?.agentName ?? callingSessionId,
          message: args.message,
        });

        return createTextResult({ broadcast: true, channel: args.channel, recipients: activeIds.length - 1 });
      },
    ),

    defineSharedTool(
      "peer_receive_messages",
      "Check your inbox for async messages and chat requests from other agents. Returns unread messages.",
      {
        since: z.string().optional().describe("ISO timestamp - only return messages after this time"),
      },
      async (args) => {
        const messages = ctx.messages.drain(callingSessionId, args.since);
        return createTextResult({ messages, count: messages.length });
      },
    ),

    defineSharedTool(
      "peer_list_agents",
      "List all running and available agent sessions. Returns each agent's name, status, and session ID.",
      {},
      async () => {
        const sessions = ctx.sessions.list();
        const agents = sessions.map((s) => ({
          sessionId: s.id,
          name: s.agentName,
          status: s.status,
          isSelf: s.id === callingSessionId,
        }));

        const registered = Array.from(ctx.agentDefinitions.entries()).map(([name]) => ({
          name,
          type: "registered_definition",
          location: "local",
        }));

        const remoteAgents = ctx.peerRegistry.listConnected().flatMap((peer) =>
          peer.agents.map((a) => ({
            name: a.name,
            type: "remote_agent",
            location: "remote",
            peer: peer.name,
          }))
        );

        return createTextResult({ activeSessions: agents, registeredAgents: registered, remoteAgents });
      },
    ),

    defineSharedTool(
      "peer_delegate_task",
      "Delegate a task to another agent. Spawns a new session for the delegate. If wait_for_result is true, blocks until the delegate finishes and returns the result.",
      {
        to_agent: z.string().describe("Agent definition name to delegate to (e.g. 'Coder', 'Reviewer')"),
        task: z.string().describe("Task description - what the agent should do"),
        context: z.string().optional().describe("Relevant context data to pass along"),
        wait_for_result: z.boolean().optional().describe("If true, block until the delegate finishes (default: false)"),
      },
      async (args) => {
        const config = ctx.agentDefinitions.get(args.to_agent);
        if (!config) {
          const existingSession = resolveAgentId(ctx, args.to_agent);
          if (existingSession) {
            const senderState = ctx.sessions.get(callingSessionId);
            ctx.messages.push(existingSession, {
              id: randomUUID(),
              from: callingSessionId,
              fromAgent: senderState?.agentName ?? callingSessionId,
              to: existingSession,
              text: `[Delegated Task] ${args.task}${args.context ? `\n\nContext: ${args.context}` : ""}`,
              priority: "urgent",
              timestamp: new Date().toISOString(),
              read: false,
            });
            return {
              ...createTextResult({ delegated: true, method: "inbox", sessionId: existingSession }),
            };
          }
          // Check remote peers before giving up
          const remotePeer = ctx.peerRegistry.findAgentOwner(args.to_agent);
          if (remotePeer) {
            try {
              if (!ctx.relayClient.isConnected(remotePeer.peer.name)) {
                await ctx.relayClient.connect(remotePeer.peer.name, remotePeer.peer.endpoint);
              }
              const result = await ctx.relayClient.sendCommand(remotePeer.peer.name, {
                type: "delegate.task",
                sessionId: callingSessionId,
                toAgent: args.to_agent,
                task: args.task,
                context: args.context,
                waitForResult: args.wait_for_result ?? false,
              });
              return {
                ...createTextResult({ delegated: true, method: "remote_relay", peer: remotePeer.peer.name, result }),
              };
            } catch (err: any) {
              return {
                ...createTextResult({ error: "remote_relay_failed", peer: remotePeer.peer.name, message: err.message }, false),
              };
            }
          }
          // Nostr fallback: if not a LAN peer but is a Nostr peer, route via Nostr
          const peerName = args.to_agent.includes('@') ? args.to_agent.split('@')[1] : null
          if (peerName && ctx.nostrTransport.hasPeer(peerName)) {
            const envelope: OdysseyP2PEnvelope = {
              id: crypto.randomUUID(),
              type: 'peer.task.delegate',
              from: { peer: process.env.ODYSSEY_INSTANCE ?? 'local' },
              to: { peer: peerName, agent: args.to_agent.split('@')[0] },
              payload: { task: args.task, agentName: args.to_agent.split('@')[0] },
              timestamp: new Date().toISOString(),
            }
            await ctx.nostrTransport.sendMessage(peerName, envelope)
            return createTextResult({ delegated: true, method: "nostr", peer: peerName })
          }
          return createTextResult({ error: "agent_not_found", agent: args.to_agent, hint: "Use peer_list_agents to see available agents" }, false);
        }

        // Inherit the calling session's working directory so delegated agents
        // work in the same place as the group (e.g. shared workspace).
        const sourceConfig = ctx.sessions.getConfig(callingSessionId);
        const effectiveConfig = sourceConfig?.workingDirectory
          ? { ...config, workingDirectory: sourceConfig.workingDirectory }
          : config;

        const senderState = ctx.sessions.get(callingSessionId);
        const waitForResult = args.wait_for_result ?? false;

        ctx.broadcast({
          type: "peer.delegate",
          sessionId: callingSessionId,
          from: senderState?.agentName ?? callingSessionId,
          to: args.to_agent,
          task: args.task,
        });

        // Instance policy routing: singleton reuses existing session, pool routes when at capacity
        const existingSessions = ctx.sessions.findByAgentName(config.name);

        if (config.instancePolicy === "singleton" && existingSessions.length > 0) {
          const target = existingSessions[0];
          ctx.messages.push(target.id, {
            id: randomUUID(),
            from: callingSessionId,
            fromAgent: senderState?.agentName ?? callingSessionId,
            to: target.id,
            text: `[Delegated Task] ${args.task}${args.context ? `\n\nContext: ${args.context}` : ""}`,
            priority: "urgent",
            timestamp: new Date().toISOString(),
            read: false,
          });
          return {
            ...createTextResult({ delegated: true, method: "reused_singleton", sessionId: target.id }),
          };
        }

        if (config.instancePolicy === "pool") {
          const poolMax = config.instancePolicyPoolMax ?? 1;
          if (existingSessions.length >= poolMax) {
            let leastBusy = existingSessions[0];
            for (const s of existingSessions) {
              if (ctx.messages.peek(s.id) < ctx.messages.peek(leastBusy.id)) {
                leastBusy = s;
              }
            }
            ctx.messages.push(leastBusy.id, {
              id: randomUUID(),
              from: callingSessionId,
              fromAgent: senderState?.agentName ?? callingSessionId,
              to: leastBusy.id,
              text: `[Delegated Task] ${args.task}${args.context ? `\n\nContext: ${args.context}` : ""}`,
              priority: "urgent",
              timestamp: new Date().toISOString(),
              read: false,
            });
            return createTextResult({ delegated: true, method: "pool_routed", sessionId: leastBusy.id });
          }
        }

        const prompt = args.context
          ? `${args.task}\n\n## Context\n${args.context}`
          : args.task;

        const delegateSessionId = randomUUID();
        try {
          const result = await ctx.spawnSession(
            delegateSessionId,
            effectiveConfig,
            prompt,
            waitForResult,
          );
          return createTextResult({
            delegated: true,
            method: "spawned",
            sessionId: result.sessionId,
            waitedForResult: waitForResult,
            result: result.result,
          });
        } catch (err: any) {
          return createTextResult({ error: "delegation_failed", message: err.message }, false);
        }
      },
    ),
  ];
}

function resolveAgentId(ctx: ToolContext, nameOrId: string): string | undefined {
  if (ctx.sessions.get(nameOrId)) return nameOrId;

  const sessions = ctx.sessions.list();
  const match = sessions.find(
    (s) => s.agentName.toLowerCase() === nameOrId.toLowerCase(),
  );
  return match?.id;
}
