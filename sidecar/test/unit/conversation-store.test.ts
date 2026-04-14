import { describe, test, expect, beforeEach } from "bun:test";
import { ConversationStore } from "../../src/stores/conversation-store.js";
import type { ConversationSummaryWire, MessageWire } from "../../src/stores/conversation-store.js";

const makeConv = (id: string): ConversationSummaryWire => ({
  id, topic: "Test", lastMessageAt: "2026-04-13T10:00:00Z",
  lastMessagePreview: "Hello", unread: false, participants: [],
  projectId: null, projectName: null, workingDirectory: null,
});
const makeMsg = (id: string, text: string): MessageWire => ({
  id, text, type: "text", senderParticipantId: null,
  timestamp: "2026-04-13T10:00:00Z", isStreaming: false,
});

describe("ConversationStore", () => {
  let store: ConversationStore;
  beforeEach(() => { store = new ConversationStore(); });

  test("sync populates listConversations", () => {
    store.sync([makeConv("a"), makeConv("b")]);
    expect(store.listConversations()).toHaveLength(2);
  });

  test("appendMessage adds to getMessages", () => {
    store.sync([makeConv("c1")]);
    store.appendMessage("c1", makeMsg("m1", "hi"));
    expect(store.getMessages("c1")).toHaveLength(1);
    expect(store.getMessages("c1")[0].text).toBe("hi");
  });

  test("getMessages respects limit", () => {
    store.sync([makeConv("c2")]);
    for (let i = 0; i < 10; i++) store.appendMessage("c2", makeMsg(`m${i}`, `msg${i}`));
    expect(store.getMessages("c2", 3)).toHaveLength(3);
  });

  test("getMessages returns chronological order", () => {
    store.sync([makeConv("c3")]);
    store.appendMessage("c3", { ...makeMsg("m1", "first"), timestamp: "2026-04-13T10:00:00Z" });
    store.appendMessage("c3", { ...makeMsg("m2", "second"), timestamp: "2026-04-13T10:01:00Z" });
    const msgs = store.getMessages("c3");
    expect(msgs[0].text).toBe("first");
    expect(msgs[1].text).toBe("second");
  });

  test("sync replaces all conversations", () => {
    store.sync([makeConv("old")]);
    store.sync([makeConv("new1"), makeConv("new2")]);
    const ids = store.listConversations().map(c => c.id);
    expect(ids).not.toContain("old");
    expect(ids).toContain("new1");
  });
});
