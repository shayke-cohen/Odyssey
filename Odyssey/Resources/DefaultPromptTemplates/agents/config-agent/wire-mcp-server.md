---
name: "Wire up an MCP server"
sortOrder: 3
---

Before wiring, confirm the transport type (stdio / SSE / HTTP), whether auth is token-based or OAuth, and which agent(s) will consume this server — ask if any are unknown.
Cover four steps in order: transport config (command or URL + args), auth setup (env var name, token scope), permission grants in settings.json (tool-level, not wildcard), and a smoke-test command to verify the connection.
Check that the server's tool names don't collide with existing MCP tools already registered before finalizing the config.
Output: ready-to-paste settings.json block, then the exact smoke-test command with expected output.

Server:
