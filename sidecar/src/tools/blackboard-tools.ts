import { z } from "zod";
import type { ToolContext } from "./tool-context.js";
import { createTextResult, defineSharedTool } from "./shared-tool.js";

export function createBlackboardTools(ctx: ToolContext) {
  return [
    defineSharedTool(
      "blackboard_read",
      "Read a value from the shared blackboard. Returns the entry with key, value, writtenBy, and timestamps.",
      { key: z.string().describe("The namespaced key to read (e.g. 'research.sorting_results')") },
      async (args) => {
        const entry = ctx.blackboard.read(args.key);
        if (!entry) {
          return createTextResult({ error: "not_found", key: args.key }, false);
        }
        return createTextResult(entry);
      },
    ),

    defineSharedTool(
      "blackboard_write",
      "Write a structured value to the shared blackboard. Other agents can read it. Use namespaced keys like 'research.top3' or 'impl.status'.",
      {
        key: z.string().describe("Namespaced key (e.g. 'research.sorting_algorithms')"),
        value: z.string().describe("JSON-encoded value to store"),
        scope: z.string().optional().describe("Optional workspace_id to scope this entry"),
      },
      async (args, extra: any) => {
        const sessionId = extra?.sessionId ?? "unknown";
        const state = ctx.sessions.get(sessionId);
        const writtenBy = state?.agentName ?? sessionId;

        const entry = ctx.blackboard.write(args.key, args.value, writtenBy, args.scope);

        ctx.broadcast({
          type: "blackboard.update",
          sessionId,
          key: entry.key,
          value: entry.value,
          writtenBy: entry.writtenBy,
        });

        return createTextResult({ success: true, key: entry.key, updatedAt: entry.updatedAt });
      },
    ),

    defineSharedTool(
      "blackboard_query",
      "Query blackboard entries by glob pattern. Returns all matching entries. Use '*' to match any segment.",
      { pattern: z.string().describe("Glob pattern (e.g. 'research.*', 'impl.*.status')") },
      async (args) => {
        const entries = ctx.blackboard.query(args.pattern);
        return createTextResult(entries);
      },
    ),

    defineSharedTool(
      "blackboard_subscribe",
      "Subscribe to changes on matching blackboard keys. Returns current matching entries. Future writes to matching keys will be delivered via your inbox (use peer_receive_messages to check).",
      { pattern: z.string().describe("Glob pattern to subscribe to (e.g. 'review.*')") },
      async (args) => {
        const current = ctx.blackboard.query(args.pattern);
        return createTextResult({
          subscribed: args.pattern,
          currentEntries: current,
          note: "Use peer_receive_messages() to check for future updates matching this pattern.",
        });
      },
    ),
  ];
}
