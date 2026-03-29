import { z } from "zod";
import type { ToolContext } from "./tool-context.js";
import { createTextResult, defineSharedTool } from "./shared-tool.js";

export function createWorkspaceTools(ctx: ToolContext, callingSessionId: string) {
  return [
    defineSharedTool(
      "workspace_create",
      "Create a new shared workspace directory that multiple agents can read/write to using their standard file tools. Returns the workspace ID and filesystem path.",
      {
        name: z.string().describe("Human-readable name for the workspace (e.g. 'sorting-collab')"),
      },
      async (args) => {
        const workspace = ctx.workspaces.create(args.name, callingSessionId);
        const senderState = ctx.sessions.get(callingSessionId);

        ctx.broadcast({
          type: "workspace.created",
          sessionId: callingSessionId,
          workspaceName: workspace.name,
          workspaceId: workspace.id,
          agentName: senderState?.agentName ?? callingSessionId,
        });

        return createTextResult({
          workspace_id: workspace.id,
          path: workspace.path,
          name: workspace.name,
        });
      },
    ),

    defineSharedTool(
      "workspace_join",
      "Join an existing shared workspace. Returns the filesystem path so you can read/write files there.",
      {
        workspace_id: z.string().describe("The workspace ID to join"),
      },
      async (args) => {
        const workspace = ctx.workspaces.join(args.workspace_id, callingSessionId);
        if (!workspace) {
          return createTextResult({ error: "workspace_not_found", workspace_id: args.workspace_id }, false);
        }

        const senderState = ctx.sessions.get(callingSessionId);
        ctx.broadcast({
          type: "workspace.joined",
          sessionId: callingSessionId,
          workspaceName: workspace.name,
          workspaceId: workspace.id,
          agentName: senderState?.agentName ?? callingSessionId,
        });

        return createTextResult({
          workspace_id: workspace.id,
          path: workspace.path,
          name: workspace.name,
          participants: workspace.participantSessionIds.length,
        });
      },
    ),

    defineSharedTool(
      "workspace_list",
      "List all available shared workspaces with their IDs, paths, and participant counts.",
      {},
      async () => {
        const workspaces = ctx.workspaces.list().map((ws) => ({
          workspace_id: ws.id,
          name: ws.name,
          path: ws.path,
          participants: ws.participantSessionIds.length,
          createdAt: ws.createdAt,
        }));
        return createTextResult({ workspaces });
      },
    ),
  ];
}
