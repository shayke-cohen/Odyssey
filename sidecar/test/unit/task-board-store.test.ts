/**
 * Unit tests for TaskBoardStore.
 *
 * Tests: create, get, update, claim, list, getSubtasks, persistence, status transitions.
 * These run in-process with no network, no sidecar boot required.
 *
 * Usage: CLAUDESTUDIO_DATA_DIR=/tmp/claudestudio-test-$(date +%s) bun test test/unit/task-board-store.test.ts
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";

describe("TaskBoardStore", () => {
  let store: TaskBoardStore;

  beforeEach(() => {
    store = new TaskBoardStore(`test-${Date.now()}-${Math.random()}`);
  });

  // ─── Create ───

  test("create assigns id and defaults", () => {
    const task = store.create({ title: "Fix bug" });
    expect(task.id).toBeTruthy();
    expect(task.title).toBe("Fix bug");
    expect(task.description).toBe("");
    expect(task.status).toBe("backlog");
    expect(task.priority).toBe("medium");
    expect(task.labels).toEqual([]);
    expect(task.createdAt).toBeTruthy();
    expect(task.startedAt).toBeUndefined();
    expect(task.completedAt).toBeUndefined();
  });

  test("create respects provided fields", () => {
    const task = store.create({
      title: "Add auth",
      description: "OAuth2 flow",
      status: "ready",
      priority: "high",
      labels: ["auth", "security"],
    });
    expect(task.status).toBe("ready");
    expect(task.priority).toBe("high");
    expect(task.labels).toEqual(["auth", "security"]);
    expect(task.description).toBe("OAuth2 flow");
  });

  test("create with custom id preserves it", () => {
    const task = store.create({ id: "custom-123", title: "Test" });
    expect(task.id).toBe("custom-123");
  });

  // ─── Get ───

  test("get returns task by id", () => {
    const created = store.create({ title: "Test" });
    const found = store.get(created.id);
    expect(found).toEqual(created);
  });

  test("get returns undefined for missing id", () => {
    expect(store.get("nonexistent")).toBeUndefined();
  });

  // ─── Update ───

  test("update changes specified fields", () => {
    const task = store.create({ title: "Original" });
    const updated = store.update(task.id, { title: "Renamed", priority: "critical" });
    expect(updated?.title).toBe("Renamed");
    expect(updated?.priority).toBe("critical");
    expect(updated?.id).toBe(task.id); // id preserved
  });

  test("update returns undefined for missing task", () => {
    expect(store.update("nonexistent", { title: "x" })).toBeUndefined();
  });

  test("update to inProgress auto-sets startedAt", () => {
    const task = store.create({ title: "Test", status: "ready" });
    const updated = store.update(task.id, { status: "inProgress" });
    expect(updated?.startedAt).toBeTruthy();
  });

  test("update to done auto-sets completedAt", () => {
    const task = store.create({ title: "Test", status: "ready" });
    store.update(task.id, { status: "inProgress" });
    const updated = store.update(task.id, { status: "done" });
    expect(updated?.completedAt).toBeTruthy();
  });

  test("update to failed auto-sets completedAt", () => {
    const task = store.create({ title: "Test", status: "ready" });
    store.update(task.id, { status: "inProgress" });
    const updated = store.update(task.id, { status: "failed" });
    expect(updated?.completedAt).toBeTruthy();
  });

  test("update to ready clears timestamps and assignment", () => {
    const task = store.create({ title: "Test", status: "ready" });
    store.claim(task.id, "agent-1");
    const updated = store.update(task.id, { status: "ready" });
    expect(updated?.startedAt).toBeUndefined();
    expect(updated?.completedAt).toBeUndefined();
    expect(updated?.assignedAgentId).toBeUndefined();
    expect(updated?.assignedGroupId).toBeUndefined();
  });

  test("update to backlog clears timestamps and assignment", () => {
    const task = store.create({ title: "Test", status: "ready" });
    store.claim(task.id, "agent-1");
    const updated = store.update(task.id, { status: "backlog" });
    expect(updated?.startedAt).toBeUndefined();
    expect(updated?.assignedAgentId).toBeUndefined();
  });

  // ─── Claim ───

  test("claim sets status and assigns agent", () => {
    const task = store.create({ title: "Test", status: "ready" });
    const claimed = store.claim(task.id, "Orchestrator");
    expect(claimed?.status).toBe("inProgress");
    expect(claimed?.assignedAgentId).toBe("Orchestrator");
    expect(claimed?.startedAt).toBeTruthy();
  });

  test("claim fails for non-ready task", () => {
    const task = store.create({ title: "Test", status: "backlog" });
    expect(store.claim(task.id, "agent")).toBeUndefined();
  });

  test("claim fails for already-claimed task", () => {
    const task = store.create({ title: "Test", status: "ready" });
    store.claim(task.id, "agent-1");
    expect(store.claim(task.id, "agent-2")).toBeUndefined();
  });

  test("claim fails for missing task", () => {
    expect(store.claim("nonexistent", "agent")).toBeUndefined();
  });

  // ─── List ───

  test("list returns all tasks", () => {
    store.create({ title: "A" });
    store.create({ title: "B" });
    store.create({ title: "C" });
    expect(store.list()).toHaveLength(3);
  });

  test("list filters by status", () => {
    store.create({ title: "A", status: "ready" });
    store.create({ title: "B", status: "backlog" });
    store.create({ title: "C", status: "ready" });

    const ready = store.list({ status: "ready" });
    expect(ready).toHaveLength(2);
    expect(ready.every((t) => t.status === "ready")).toBe(true);
  });

  test("list filters by assigned agent", () => {
    const t1 = store.create({ title: "A", status: "ready" });
    store.create({ title: "B", status: "ready" });
    store.claim(t1.id, "Coder");

    const assigned = store.list({ assignedTo: "Coder" });
    expect(assigned).toHaveLength(1);
    expect(assigned[0].title).toBe("A");
  });

  test("list with no filter returns all", () => {
    store.create({ title: "A" });
    expect(store.list({})).toHaveLength(1);
  });

  // ─── Subtasks ───

  test("getSubtasks returns children", () => {
    const parent = store.create({ title: "Parent" });
    store.create({ title: "Child 1", parentTaskId: parent.id });
    store.create({ title: "Child 2", parentTaskId: parent.id });
    store.create({ title: "Unrelated" });

    const subtasks = store.getSubtasks(parent.id);
    expect(subtasks).toHaveLength(2);
    expect(subtasks.map((t) => t.title).sort()).toEqual(["Child 1", "Child 2"]);
  });

  test("getSubtasks returns empty for task without children", () => {
    const task = store.create({ title: "Lonely" });
    expect(store.getSubtasks(task.id)).toHaveLength(0);
  });

  // ─── Persistence ───

  test("tasks survive store recreation with same scope", () => {
    const scope = `persist-test-${Date.now()}-${Math.random()}`;
    const store1 = new TaskBoardStore(scope);
    store1.create({ id: "persist-1", title: "Persistent Task", status: "ready" });

    const store2 = new TaskBoardStore(scope);
    const task = store2.get("persist-1");
    expect(task).toBeTruthy();
    expect(task?.title).toBe("Persistent Task");
    expect(task?.status).toBe("ready");
  });

  // ─── Listener ───

  test("subscribe receives notifications", () => {
    const notifications: any[] = [];
    store.subscribe((task) => notifications.push(task));

    store.create({ title: "New" });
    expect(notifications).toHaveLength(1);
    expect(notifications[0].title).toBe("New");
  });

  test("unsubscribe stops notifications", () => {
    const notifications: any[] = [];
    const unsub = store.subscribe((task) => notifications.push(task));

    store.create({ title: "First" });
    unsub();
    store.create({ title: "Second" });

    expect(notifications).toHaveLength(1);
  });
});
