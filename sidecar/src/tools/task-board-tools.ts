import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import type { ToolContext } from "./tool-context.js";

export function createTaskBoardTools(ctx: ToolContext) {
  return [
    tool(
      "task_board_list",
      "List tasks on the task board. Optionally filter by status or assigned agent.",
      {
        status: z.enum(["backlog", "ready", "inProgress", "done", "failed", "blocked"]).optional()
          .describe("Filter by task status"),
        assigned_to: z.string().optional()
          .describe("Filter by assigned agent name"),
      },
      async (args) => {
        const tasks = ctx.taskBoard.list({
          status: args.status,
          assignedTo: args.assigned_to,
        });
        return { content: [{ type: "text" as const, text: JSON.stringify(tasks) }] };
      },
    ),

    tool(
      "task_board_create",
      "Create a new task on the task board. Tasks default to 'backlog' status. Use 'ready' status if the task should be immediately available for claiming.",
      {
        title: z.string().describe("Short title for the task"),
        description: z.string().optional().describe("Detailed description of what needs to be done"),
        priority: z.enum(["low", "medium", "high", "critical"]).optional()
          .describe("Task priority (default: medium)"),
        labels: z.array(z.string()).optional().describe("Tags for categorization"),
        parent_task_id: z.string().optional().describe("ID of parent task if this is a subtask"),
        status: z.enum(["backlog", "ready"]).optional().describe("Initial status (default: backlog)"),
      },
      async (args) => {
        const task = ctx.taskBoard.create({
          title: args.title,
          description: args.description ?? "",
          priority: args.priority ?? "medium",
          labels: args.labels ?? [],
          parentTaskId: args.parent_task_id,
          status: args.status ?? "ready",
        });

        ctx.broadcast({ type: "task.created", task });

        return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, task }) }] };
      },
    ),

    tool(
      "task_board_claim",
      "Atomically claim a ready task. Sets status to inProgress and assigns it to the calling agent. Fails if the task is already claimed or not in 'ready' status.",
      {
        task_id: z.string().describe("ID of the task to claim"),
      },
      async (args, extra: any) => {
        const sessionId = extra?.sessionId ?? "unknown";
        const state = ctx.sessions.get(sessionId);
        const agentName = state?.agentName ?? sessionId;

        const task = ctx.taskBoard.claim(args.task_id, agentName);
        if (!task) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ error: "claim_failed", task_id: args.task_id, reason: "Task not found or not in 'ready' status" }),
            }],
          };
        }

        ctx.broadcast({ type: "task.updated", task });

        return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, task }) }] };
      },
    ),

    tool(
      "task_board_update",
      "Update a task's status, result, or linked conversation. Use this to report progress or completion.",
      {
        task_id: z.string().describe("ID of the task to update"),
        status: z.enum(["backlog", "ready", "inProgress", "done", "failed", "blocked"]).optional()
          .describe("New status"),
        result: z.string().optional().describe("Result summary when completing a task"),
        conversation_id: z.string().optional().describe("Link to the conversation where work is happening"),
        assigned_agent_id: z.string().optional().describe("Agent ID to assign"),
        assigned_group_id: z.string().optional().describe("Group ID to assign"),
      },
      async (args) => {
        const updates: Record<string, any> = {};
        if (args.status) updates.status = args.status;
        if (args.result) updates.result = args.result;
        if (args.conversation_id) updates.conversationId = args.conversation_id;
        if (args.assigned_agent_id) updates.assignedAgentId = args.assigned_agent_id;
        if (args.assigned_group_id) updates.assignedGroupId = args.assigned_group_id;

        const task = ctx.taskBoard.update(args.task_id, updates);
        if (!task) {
          return {
            content: [{
              type: "text" as const,
              text: JSON.stringify({ error: "not_found", task_id: args.task_id }),
            }],
          };
        }

        ctx.broadcast({ type: "task.updated", task });

        return { content: [{ type: "text" as const, text: JSON.stringify({ success: true, task }) }] };
      },
    ),
  ];
}
