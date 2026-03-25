---
name: peer-collaboration
description: How to communicate with other agents in ClaudPeer using PeerBus tools.
category: ClaudPeer
triggers:
  - peer_chat
  - peer_send
  - peer_delegate
  - communicate with agent
  - ask another agent
  - collaborate
---

# Peer Collaboration

You are part of a multi-agent system called ClaudPeer. Other agents are running alongside you, each with their own specialty. This skill teaches you how to communicate effectively.

## Choosing a Communication Mode

### Blocking Chat (`peer_chat_start` / `peer_chat_reply`)

Use when you need a **back-and-forth conversation** before you can proceed:

- Asking clarifying questions ("Which algorithm should I use?")
- Negotiating decisions ("I think mergesort fits -- do you agree?")
- Iterating on a design ("Here's my approach, what do you think?")

Your tool call **blocks** until the other agent replies. This is intentional -- it models a real conversation.

```
peer_chat_start(to: "Coder", message: "I found 3 candidate algorithms. Which fits our 8GB memory constraint?", topic: "Algorithm selection")
→ blocks → receives: { channel_id: "ch-1", reply: "Mergesort. It streams from disk." }

peer_chat_reply(channel_id: "ch-1", message: "Good. I'll write up the analysis.")
peer_chat_close(channel_id: "ch-1", summary: "Selected mergesort for 8GB constraint.")
```

### Async Messages (`peer_send_message` / `peer_broadcast`)

Use when you **don't need a reply** to continue your work:

- Status updates ("Implementation complete.")
- Notifications ("Build failed -- check the blackboard for details.")
- Broadcasting results ("Review approved for all components.")

```
peer_send_message(to: "Orchestrator", message: "Research phase complete. Findings on blackboard at research.sorting.*")
peer_broadcast(channel: "status", message: "All tests passing.")
```

### Delegation (`peer_delegate_task`)

Use when you want to **spawn a subtask** for another agent:

- `wait_for_result: true` -- blocks until the delegate finishes (sequential dependency)
- `wait_for_result: false` -- returns immediately with the session ID (fire-and-forget)

```
peer_delegate_task(to: "Coder", task: "Implement mergesort with external merge support", context: "Memory budget: 8GB. See blackboard research.sorting.top3 for analysis.", wait_for_result: false)
```

## Deadlock Avoidance

The PeerBus detects circular waits, but prevention is better:

- **Never wait on an agent that's waiting on you.** If you're in a blocking chat with Agent B, don't also start a blocking chat with Agent C that requires Agent B.
- **Prefer async for status updates.** If you just need to say "I'm done", use `peer_send_message`, not a blocking chat.
- **Close chats when the decision is made.** Don't leave blocking channels open -- call `peer_chat_close` with a summary.

## Group Chat Etiquette

When in a conversation with multiple agents:

- **Use @-mentions** to direct messages at specific agents when not everyone needs to respond.
- **Avoid flooding** -- consolidate your findings into one message rather than sending many small ones.
- **Summarize outcomes** -- when a decision is reached, one agent should write the summary to the blackboard.

## Checking Your Inbox

If you're running as a **worker** (singleton, long-lived), periodically check for messages:

```
peer_receive_messages(since: "2026-03-21T12:00:00Z")
```

This returns both async messages and pending chat requests. Handle chat requests by joining the conversation with `peer_chat_reply`.

## Communication Protocol

When interacting with other agents:

1. **Acknowledge receipt** -- confirm you received and understand the task or message.
2. **Report progress** -- for long tasks, write intermediate status to the blackboard.
3. **Summarize outcomes** -- when done, send a clear summary of what was accomplished.
4. **Signal errors early** -- if you're blocked or failing, notify the requesting agent immediately rather than silently retrying.
