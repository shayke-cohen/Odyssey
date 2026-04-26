/**
 * Unit tests for all PeerBus stores.
 *
 * Tests: BlackboardStore, SessionRegistry, MessageStore, ChatChannelStore, WorkspaceStore
 * These run in-process with no network, no sidecar boot required.
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/unit/stores.test.ts
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { BlackboardStore } from "../../src/stores/blackboard-store.js";
import { SessionRegistry } from "../../src/stores/session-registry.js";
import { MessageStore, type PeerMessage } from "../../src/stores/message-store.js";
import { ChatChannelStore } from "../../src/stores/chat-channel-store.js";
import { WorkspaceStore } from "../../src/stores/workspace-store.js";

// ─── BlackboardStore ────────────────────────────────────────────────

describe("BlackboardStore", () => {
  let bb: BlackboardStore;

  beforeEach(() => {
    bb = new BlackboardStore(`test-${Date.now()}-${Math.random()}`);
  });

  test("write and read a key", () => {
    const entry = bb.write("project.name", "Odyssey", "agent-1");
    expect(entry.key).toBe("project.name");
    expect(entry.value).toBe("Odyssey");
    expect(entry.writtenBy).toBe("agent-1");
    expect(entry.createdAt).toBeTruthy();

    const read = bb.read("project.name");
    expect(read).toEqual(entry);
  });

  test("read returns undefined for missing key", () => {
    expect(bb.read("missing.key")).toBeUndefined();
  });

  test("write overwrites existing key, preserves createdAt", () => {
    const first = bb.write("counter", "1", "agent-1");
    const second = bb.write("counter", "2", "agent-2");

    expect(second.value).toBe("2");
    expect(second.writtenBy).toBe("agent-2");
    expect(second.createdAt).toBe(first.createdAt);
    expect(new Date(second.updatedAt).getTime()).toBeGreaterThanOrEqual(
      new Date(first.updatedAt).getTime(),
    );
  });

  test("query with glob pattern", () => {
    bb.write("research.sorting", "quicksort", "a");
    bb.write("research.hashing", "sha256", "a");
    bb.write("impl.status", "in-progress", "b");

    const research = bb.query("research.*");
    expect(research).toHaveLength(2);
    expect(research.map((e) => e.key).sort()).toEqual([
      "research.hashing",
      "research.sorting",
    ]);

    const all = bb.query("*");
    expect(all).toHaveLength(3);
  });

  test("query with no matches returns empty array", () => {
    bb.write("a.b", "v", "w");
    expect(bb.query("xyz.*")).toHaveLength(0);
  });

  test("keys returns all keys", () => {
    bb.write("k1", "v1", "w");
    bb.write("k2", "v2", "w");
    const keys = bb.keys();
    expect(keys).toContain("k1");
    expect(keys).toContain("k2");
  });

  test("keys filtered by workspace scope", () => {
    bb.write("scoped.a", "v", "w", "ws-1");
    bb.write("scoped.b", "v", "w", "ws-2");
    bb.write("global", "v", "w");

    expect(bb.keys("ws-1")).toEqual(["scoped.a"]);
    expect(bb.keys("ws-2")).toEqual(["scoped.b"]);
  });

  test("subscribe fires on matching writes", () => {
    const received: string[] = [];
    bb.subscribe("events.*", (entry) => received.push(entry.key));

    bb.write("events.click", "1", "w");
    bb.write("other.stuff", "2", "w");
    bb.write("events.scroll", "3", "w");

    expect(received).toEqual(["events.click", "events.scroll"]);
  });

  test("unsubscribe stops notifications", () => {
    const received: string[] = [];
    const unsub = bb.subscribe("*", (entry) => received.push(entry.key));

    bb.write("a", "1", "w");
    unsub();
    bb.write("b", "2", "w");

    expect(received).toEqual(["a"]);
  });

  // ── Debounced disk persistence ──
  // 100 rapid writes should coalesce into a small number of disk writes,
  // not one per write.
  test("rapid writes coalesce into a small number of disk persists", async () => {
    for (let i = 0; i < 100; i++) {
      bb.write(`k${i}`, `v${i}`, "agent");
    }
    bb.flushSync();

    expect(bb._persistCallCount).toBeLessThanOrEqual(3);
    expect(bb.keys()).toHaveLength(100);
  });

  test("flushSync writes the latest state to disk", async () => {
    const scope = `flush-test-${Date.now()}-${Math.random()}`;
    const bb1 = new BlackboardStore(scope);
    bb1.write("important", "value", "agent");
    bb1.flushSync();

    // A new store with the same scope should read what bb1 just wrote.
    const bb2 = new BlackboardStore(scope);
    expect(bb2.read("important")?.value).toBe("value");
  });

  // ── Corrupt-file handling ──
  test("loadFromDisk renames corrupt file and starts empty", async () => {
    const fs = await import("fs");
    const path = await import("path");
    const os = await import("os");
    const baseDir = process.env.ODYSSEY_DATA_DIR ?? path.join(os.homedir(), ".odyssey");
    const dir = path.join(baseDir, "blackboard");
    fs.mkdirSync(dir, { recursive: true });

    const scope = `corrupt-test-${Date.now()}-${Math.random()}`;
    const file = path.join(dir, `${scope}.json`);
    fs.writeFileSync(file, "{this is not valid json");

    const bb = new BlackboardStore(scope);
    expect(bb.keys()).toHaveLength(0);

    // The corrupt file should be quarantined alongside.
    const siblings = fs.readdirSync(dir).filter((f) => f.startsWith(`${scope}.json.corrupt.`));
    expect(siblings.length).toBeGreaterThanOrEqual(1);
  });
});

// ─── SessionRegistry ────────────────────────────────────────────────

describe("SessionRegistry", () => {
  let reg: SessionRegistry;
  const mockConfig = {
    name: "TestAgent",
    systemPrompt: "test",
    allowedTools: [],
    mcpServers: [],
    model: "claude-sonnet-4-6",
    workingDirectory: "/tmp",
    skills: [],
  };

  beforeEach(() => {
    reg = new SessionRegistry();
  });

  test("create and get session", () => {
    const state = reg.create("s1", mockConfig);
    expect(state.id).toBe("s1");
    expect(state.agentName).toBe("TestAgent");
    expect(state.status).toBe("active");
    expect(state.tokenCount).toBe(0);
    expect(state.cost).toBe(0);

    expect(reg.get("s1")).toEqual(state);
  });

  test("getConfig returns the agent config", () => {
    reg.create("s1", mockConfig);
    expect(reg.getConfig("s1")).toEqual(mockConfig);
  });

  test("get returns undefined for missing session", () => {
    expect(reg.get("nope")).toBeUndefined();
  });

  test("update modifies session state", () => {
    reg.create("s1", mockConfig);
    reg.update("s1", { status: "paused", cost: 0.05 });
    const state = reg.get("s1")!;
    expect(state.status).toBe("paused");
    expect(state.cost).toBe(0.05);
  });

  test("remove deletes session and config", () => {
    reg.create("s1", mockConfig);
    reg.remove("s1");
    expect(reg.get("s1")).toBeUndefined();
    expect(reg.getConfig("s1")).toBeUndefined();
  });

  test("list returns all sessions", () => {
    reg.create("s1", mockConfig);
    reg.create("s2", { ...mockConfig, name: "Agent2" });
    expect(reg.list()).toHaveLength(2);
  });

  test("listActive filters by status", () => {
    reg.create("s1", mockConfig);
    reg.create("s2", mockConfig);
    reg.update("s2", { status: "completed" });

    const active = reg.listActive();
    expect(active).toHaveLength(1);
    expect(active[0].id).toBe("s1");
  });

  test("findByAgentName returns active sessions matching name", () => {
    reg.create("s1", { ...mockConfig, name: "Coder" });
    reg.create("s2", { ...mockConfig, name: "Reviewer" });
    reg.create("s3", { ...mockConfig, name: "Coder" });

    const coders = reg.findByAgentName("Coder");
    expect(coders).toHaveLength(2);
    expect(coders.map((s) => s.id).sort()).toEqual(["s1", "s3"]);
  });

  test("findByAgentName is case-insensitive", () => {
    reg.create("s1", { ...mockConfig, name: "DevOps" });
    expect(reg.findByAgentName("devops")).toHaveLength(1);
    expect(reg.findByAgentName("DEVOPS")).toHaveLength(1);
  });

  test("findByAgentName excludes non-active sessions", () => {
    reg.create("s1", { ...mockConfig, name: "Tester" });
    reg.create("s2", { ...mockConfig, name: "Tester" });
    reg.update("s2", { status: "completed" });

    expect(reg.findByAgentName("Tester")).toHaveLength(1);
    expect(reg.findByAgentName("Tester")[0].id).toBe("s1");
  });

  test("findByAgentName returns empty for no matches", () => {
    reg.create("s1", mockConfig);
    expect(reg.findByAgentName("Ghost")).toHaveLength(0);
  });
});

// ─── MessageStore ───────────────────────────────────────────────────

describe("MessageStore", () => {
  let store: MessageStore;

  function makeMsg(overrides: Partial<PeerMessage> = {}): PeerMessage {
    return {
      id: `msg-${Math.random()}`,
      from: "sender-1",
      fromAgent: "Agent1",
      to: "receiver-1",
      text: "hello",
      priority: "normal",
      timestamp: new Date().toISOString(),
      read: false,
      ...overrides,
    };
  }

  beforeEach(() => {
    store = new MessageStore();
  });

  test("push and drain", () => {
    store.push("inbox-a", makeMsg({ to: "inbox-a", text: "msg1" }));
    store.push("inbox-a", makeMsg({ to: "inbox-a", text: "msg2" }));

    const messages = store.drain("inbox-a");
    expect(messages).toHaveLength(2);
    expect(messages[0].text).toBe("msg1");
    expect(messages[1].text).toBe("msg2");
  });

  test("drain marks messages as read", () => {
    store.push("inbox-a", makeMsg({ to: "inbox-a" }));
    store.drain("inbox-a");

    const second = store.drain("inbox-a");
    expect(second).toHaveLength(0);
  });

  test("drain with since filter", () => {
    const oldTime = new Date(Date.now() - 60_000).toISOString();
    const newTime = new Date().toISOString();

    store.push("inbox-a", makeMsg({ to: "inbox-a", text: "old", timestamp: oldTime }));
    store.push("inbox-a", makeMsg({ to: "inbox-a", text: "new", timestamp: newTime }));

    const cutoff = new Date(Date.now() - 30_000).toISOString();
    const messages = store.drain("inbox-a", cutoff);
    expect(messages).toHaveLength(1);
    expect(messages[0].text).toBe("new");
  });

  test("drain on empty inbox returns empty array", () => {
    expect(store.drain("unknown")).toHaveLength(0);
  });

  test("peek returns unread count", () => {
    store.push("inbox-a", makeMsg({ to: "inbox-a" }));
    store.push("inbox-a", makeMsg({ to: "inbox-a" }));
    expect(store.peek("inbox-a")).toBe(2);

    store.drain("inbox-a");
    expect(store.peek("inbox-a")).toBe(0);
  });

  test("pushToAll broadcasts to all except sender", () => {
    const msg = {
      id: "broadcast-1",
      from: "sender",
      fromAgent: "Sender",
      text: "broadcast",
      priority: "normal" as const,
      timestamp: new Date().toISOString(),
      read: false,
    };

    store.pushToAll(msg, ["sender", "recv-1", "recv-2"]);

    expect(store.peek("sender")).toBe(0);
    expect(store.peek("recv-1")).toBe(1);
    expect(store.peek("recv-2")).toBe(1);
  });
});

// ─── ChatChannelStore ───────────────────────────────────────────────

describe("ChatChannelStore", () => {
  let store: ChatChannelStore;

  beforeEach(() => {
    store = new ChatChannelStore();
  });

  test("create channel with participants and first message", () => {
    const ch = store.create("session-a", "AgentA", "session-b", "Hello!", "topic");
    expect(ch.id).toBeTruthy();
    expect(ch.participants).toEqual(["session-a", "session-b"]);
    expect(ch.messages).toHaveLength(1);
    expect(ch.messages[0].text).toBe("Hello!");
    expect(ch.messages[0].from).toBe("session-a");
    expect(ch.status).toBe("open");
    expect(ch.topic).toBe("topic");
  });

  test("get returns the channel", () => {
    const ch = store.create("a", "A", "b", "hi");
    expect(store.get(ch.id)).toEqual(ch);
  });

  test("get returns undefined for missing channel", () => {
    expect(store.get("nope")).toBeUndefined();
  });

  test("addParticipant adds to channel", () => {
    const ch = store.create("a", "A", "b", "hi");
    const result = store.addParticipant(ch.id, "c");
    expect(result).toBe(true);
    expect(store.get(ch.id)!.participants).toContain("c");
  });

  test("addParticipant does not duplicate", () => {
    const ch = store.create("a", "A", "b", "hi");
    store.addParticipant(ch.id, "a");
    expect(store.get(ch.id)!.participants).toEqual(["a", "b"]);
  });

  test("addParticipant returns false for closed channel", () => {
    const ch = store.create("a", "A", "b", "hi");
    store.close(ch.id);
    expect(store.addParticipant(ch.id, "c")).toBe(false);
  });

  test("addMessage appends and notifies waiters", async () => {
    const ch = store.create("a", "A", "b", "hi");

    const replyPromise = store.waitForReply(ch.id, "a", 5000);
    store.addMessage(ch.id, "b", "B", "hello back");

    const reply = await replyPromise;
    expect("text" in reply ? reply.text : null).toBe("hello back");
  });

  test("addMessage returns undefined for closed channel", () => {
    const ch = store.create("a", "A", "b", "hi");
    store.close(ch.id);
    expect(store.addMessage(ch.id, "b", "B", "late")).toBeUndefined();
  });

  test("waitForReply resolves when other participant sends", async () => {
    const ch = store.create("a", "A", "b", "hi");

    setTimeout(() => {
      store.addMessage(ch.id, "b", "B", "reply");
    }, 50);

    const result = await store.waitForReply(ch.id, "a", 5000);
    expect("text" in result).toBe(true);
    if ("text" in result) {
      expect(result.text).toBe("reply");
      expect(result.fromAgent).toBe("B");
    }
  });

  test("waitForReply returns closed for already-closed channel", async () => {
    const ch = store.create("a", "A", "b", "hi");
    store.close(ch.id, "done");

    const result = await store.waitForReply(ch.id, "a");
    expect("closed" in result).toBe(true);
    if ("closed" in result) {
      expect(result.summary).toBe("done");
    }
  });

  test("waitForReply times out", async () => {
    const ch = store.create("a", "A", "b", "hi");
    const result = await store.waitForReply(ch.id, "a", 100);
    expect("closed" in result).toBe(true);
    if ("closed" in result) {
      expect(result.summary).toBe("timeout");
    }
  });

  test("close resolves all waiters", async () => {
    const ch = store.create("a", "A", "b", "hi");

    const waiterA = store.waitForReply(ch.id, "a", 5000);
    const waiterB = store.waitForReply(ch.id, "b", 5000);

    store.close(ch.id, "finished");

    const [resultA, resultB] = await Promise.all([waiterA, waiterB]);
    expect("closed" in resultA).toBe(true);
    expect("closed" in resultB).toBe(true);
  });

  test("deadlock detection prevents circular waits", async () => {
    const ch1 = store.create("a", "A", "b", "hi from a");
    const ch2 = store.create("b", "B", "a", "hi from b");

    // a waits on ch1 (for b to reply)
    const waitA = store.waitForReply(ch1.id, "a", 5000);

    // Now b tries to wait on ch2 (for a to reply) — deadlock
    const waitB = store.waitForReply(ch2.id, "b", 5000);

    const resultB = await waitB;
    expect("closed" in resultB).toBe(true);
    if ("closed" in resultB) {
      expect(resultB.summary).toContain("deadlock");
    }

    // Clean up: close ch1 so waitA resolves
    store.close(ch1.id);
    await waitA;
  });

  test("list and listOpen", () => {
    const ch1 = store.create("a", "A", "b", "hi");
    const ch2 = store.create("c", "C", "d", "hey");
    store.close(ch1.id);

    expect(store.list()).toHaveLength(2);
    expect(store.listOpen()).toHaveLength(1);
    expect(store.listOpen()[0].id).toBe(ch2.id);
  });

  test("waitForIncoming finds channel targeted at session", async () => {
    const ch = store.create("a", "A", "b", "question?");

    const incoming = await store.waitForIncoming("b", 1000);
    expect(incoming).not.toBeNull();
    expect(incoming!.id).toBe(ch.id);
    expect(incoming!.messages[0].text).toBe("question?");
  });

  test("waitForIncoming returns null on timeout", async () => {
    const result = await store.waitForIncoming("nobody", 100);
    expect(result).toBeNull();
  });
});

// ─── WorkspaceStore ─────────────────────────────────────────────────

describe("WorkspaceStore", () => {
  let store: WorkspaceStore;

  beforeEach(() => {
    store = new WorkspaceStore();
  });

  test("create workspace with directory", () => {
    const ws = store.create("collab", "session-1");
    expect(ws.id).toBeTruthy();
    expect(ws.name).toBe("collab");
    expect(ws.participantSessionIds).toEqual(["session-1"]);
    expect(ws.path).toContain(ws.id);

    const { existsSync } = require("fs");
    expect(existsSync(ws.path)).toBe(true);
  });

  test("get returns workspace", () => {
    const ws = store.create("test", "s1");
    expect(store.get(ws.id)).toEqual(ws);
  });

  test("get returns undefined for missing workspace", () => {
    expect(store.get("nope")).toBeUndefined();
  });

  test("join adds participant", () => {
    const ws = store.create("test", "s1");
    const joined = store.join(ws.id, "s2");
    expect(joined).toBeDefined();
    expect(joined!.participantSessionIds).toContain("s2");
  });

  test("join is idempotent", () => {
    const ws = store.create("test", "s1");
    store.join(ws.id, "s1");
    expect(store.get(ws.id)!.participantSessionIds).toEqual(["s1"]);
  });

  test("join returns undefined for missing workspace", () => {
    expect(store.join("nope", "s1")).toBeUndefined();
  });

  test("list returns all workspaces", () => {
    store.create("ws1", "s1");
    store.create("ws2", "s2");
    expect(store.list()).toHaveLength(2);
  });
});
