/**
 * Unit tests for stores that lack direct coverage in stores.test.ts:
 * PeerRegistry, ConnectorStore, ConversationStore, ProjectStore.
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { PeerRegistry } from "../../src/stores/peer-registry.js";
import { ConnectorStore } from "../../src/stores/connector-store.js";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import { ProjectStore } from "../../src/stores/project-store.js";
import type { AgentConfig, ConnectorConfig } from "../../src/types.js";

// ─── PeerRegistry ───────────────────────────────────────────────────

describe("PeerRegistry", () => {
  let reg: PeerRegistry;
  const cfg: AgentConfig = {
    name: "A",
    systemPrompt: "",
    allowedTools: [],
    mcpServers: [],
    model: "claude-sonnet-4-6",
    workingDirectory: "/tmp",
    skills: [],
  };

  beforeEach(() => {
    reg = new PeerRegistry();
  });

  test("register and get peer", () => {
    reg.register("mac-1", "ws://host:9849", [{ name: "Coder", config: cfg }]);
    const peer = reg.get("mac-1");
    expect(peer).toBeDefined();
    expect(peer!.status).toBe("connected");
    expect(peer!.agents).toHaveLength(1);
    expect(peer!.endpoint).toBe("ws://host:9849");
  });

  test("remove peer", () => {
    reg.register("mac-1", "ws://host:9849", []);
    reg.remove("mac-1");
    expect(reg.get("mac-1")).toBeUndefined();
  });

  test("findAgentOwner returns connected peer owning the agent", () => {
    reg.register("mac-1", "ws://host-1:9849", [{ name: "Coder", config: cfg }]);
    reg.register("mac-2", "ws://host-2:9849", [{ name: "Reviewer", config: cfg }]);
    const owner = reg.findAgentOwner("Coder");
    expect(owner?.peer.name).toBe("mac-1");
    expect(owner?.agent.name).toBe("Coder");
  });

  test("findAgentOwner skips disconnected peers", () => {
    reg.register("mac-1", "ws://host-1:9849", [{ name: "Coder", config: cfg }]);
    // Simulate disconnect by mutating the peer
    const peer = reg.get("mac-1")!;
    peer.status = "disconnected";
    expect(reg.findAgentOwner("Coder")).toBeUndefined();
  });

  test("list + listConnected", () => {
    reg.register("mac-1", "ws://h-1", []);
    reg.register("mac-2", "ws://h-2", []);
    reg.get("mac-2")!.status = "disconnected";
    expect(reg.list()).toHaveLength(2);
    expect(reg.listConnected()).toHaveLength(1);
    expect(reg.listConnected()[0].name).toBe("mac-1");
  });

  test("register overwrites existing peer", () => {
    reg.register("mac-1", "ws://old", []);
    reg.register("mac-1", "ws://new", [{ name: "X", config: cfg }]);
    expect(reg.get("mac-1")!.endpoint).toBe("ws://new");
    expect(reg.get("mac-1")!.agents).toHaveLength(1);
  });
});

// ─── ConnectorStore ─────────────────────────────────────────────────

function buildConn(id: string, displayName = id, provider = "custom"): ConnectorConfig {
  return {
    id,
    displayName,
    provider: provider as any,
    status: "connected",
    lastCheckedAt: new Date().toISOString(),
  } as ConnectorConfig;
}

describe("ConnectorStore", () => {
  let store: ConnectorStore;

  beforeEach(() => {
    store = new ConnectorStore();
  });

  test("upsert inserts new connection", () => {
    store.upsert(buildConn("c1", "Zapier"), { kind: "oauth" } as any);
    const entry = store.get("c1");
    expect(entry?.connection.id).toBe("c1");
    expect(entry?.credentials).toBeDefined();
  });

  test("upsert without credentials preserves existing credentials", () => {
    store.upsert(buildConn("c1"), { kind: "oauth", token: "a" } as any);
    store.upsert(buildConn("c1", "Renamed"));
    const entry = store.get("c1")!;
    expect(entry.connection.displayName).toBe("Renamed");
    expect((entry.credentials as any).token).toBe("a");
  });

  test("list returns sorted by displayName", () => {
    store.upsert(buildConn("c1", "Zeta"));
    store.upsert(buildConn("c2", "Alpha"));
    const names = store.list().map((e) => e.connection.displayName);
    expect(names).toEqual(["Alpha", "Zeta"]);
  });

  test("listConfigs returns shallow copies", () => {
    store.upsert(buildConn("c1", "X"));
    const cfg = store.listConfigs()[0];
    cfg.displayName = "mutated";
    expect(store.get("c1")!.connection.displayName).toBe("X");
  });

  test("findByProvider filters", () => {
    store.upsert(buildConn("c1", "A", "github") as any);
    store.upsert(buildConn("c2", "B", "custom") as any);
    const found = store.findByProvider("github" as any);
    expect(found).toHaveLength(1);
    expect(found[0].connection.id).toBe("c1");
  });

  test("markAuthorizing sets status", () => {
    const entry = store.markAuthorizing(buildConn("c1"));
    expect(entry.connection.status).toBe("authorizing");
  });

  test("revoke clears credentials and sets status", () => {
    store.upsert(buildConn("c1"), { kind: "oauth", token: "a" } as any);
    const revoked = store.revoke("c1");
    expect(revoked?.connection.status).toBe("revoked");
    expect(revoked?.credentials).toBeUndefined();
  });

  test("revoke on missing id returns undefined", () => {
    expect(store.revoke("ghost")).toBeUndefined();
  });
});

// ─── ConversationStore ──────────────────────────────────────────────

describe("ConversationStore", () => {
  let store: ConversationStore;

  beforeEach(() => {
    store = new ConversationStore();
  });

  test("sync replaces full list", () => {
    store.sync([
      {
        id: "c1",
        topic: "Topic",
        lastMessageAt: new Date().toISOString(),
        lastMessagePreview: "",
        unread: false,
        participants: [],
        projectId: null,
        projectName: null,
        workingDirectory: null,
      },
    ]);
    expect(store.listConversations()).toHaveLength(1);
    store.sync([]);
    expect(store.listConversations()).toHaveLength(0);
  });

  test("ensureConversation creates when missing", () => {
    store.ensureConversation("c1", "Coder");
    expect(store.listConversations()).toHaveLength(1);
    expect(store.listConversations()[0].id).toBe("c1");
  });

  test("ensureConversation is idempotent", () => {
    store.ensureConversation("c1", "Coder");
    store.ensureConversation("c1", "Coder");
    expect(store.listConversations()).toHaveLength(1);
  });

  test("appendMessage stores and getMessages returns them", () => {
    store.ensureConversation("c1", "A");
    store.appendMessage("c1", {
      id: "m1",
      text: "hi",
      type: "chat",
      senderParticipantId: "user",
      timestamp: new Date().toISOString(),
      isStreaming: false,
    });
    const msgs = store.getMessages("c1");
    expect(msgs).toHaveLength(1);
    expect(msgs[0].text).toBe("hi");
  });

  test("getMessages on missing conversation returns []", () => {
    expect(store.getMessages("ghost")).toEqual([]);
  });

  test("appendMessage on unknown conversation auto-creates it", () => {
    store.appendMessage("c-auto", {
      id: "m1",
      text: "hi",
      type: "chat",
      senderParticipantId: "user",
      timestamp: new Date().toISOString(),
      isStreaming: false,
    });
    expect(store.getMessages("c-auto")).toHaveLength(1);
  });
});

// ─── ProjectStore ───────────────────────────────────────────────────

describe("ProjectStore", () => {
  let store: ProjectStore;

  beforeEach(() => {
    store = new ProjectStore();
  });

  test("sync replaces full list", () => {
    store.sync([
      {
        id: "p1",
        name: "Odyssey",
        rootPath: "/repo",
        icon: "folder",
        color: "blue",
        isPinned: true,
        pinnedAgentIds: [],
      },
    ]);
    expect(store.list()).toHaveLength(1);
    expect(store.list()[0].name).toBe("Odyssey");

    store.sync([]);
    expect(store.list()).toHaveLength(0);
  });

  test("list returns empty initially", () => {
    expect(store.list()).toEqual([]);
  });
});
