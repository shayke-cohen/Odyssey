/**
 * Tests for TaskBoardStore — focuses on debounced persistence (no per-mutation
 * synchronous disk writes) and durable flush on shutdown.
 *
 * Usage: ODYSSEY_DATA_DIR=/tmp/odyssey-test-$(date +%s) bun test test/unit/task-board-store.test.ts
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { TaskBoardStore } from "../../src/stores/task-board-store.js";

describe("TaskBoardStore — debounced persistence", () => {
  let board: TaskBoardStore;

  beforeEach(() => {
    board = new TaskBoardStore(`tb-test-${Date.now()}-${Math.random()}`);
  });

  test("rapid create+update calls coalesce into a small number of disk persists", async () => {
    const tasks = [];
    for (let i = 0; i < 50; i++) {
      tasks.push(board.create({ title: `task ${i}` }));
    }
    for (const t of tasks) {
      board.update(t.id, { status: "ready" });
    }
    board.flushSync();

    expect(board._persistCallCount).toBeLessThanOrEqual(3);
    expect(board.list()).toHaveLength(50);
  });

  test("flushSync writes latest state to disk", () => {
    const scope = `tb-flush-${Date.now()}-${Math.random()}`;
    const a = new TaskBoardStore(scope);
    a.create({ id: "task-x", title: "from-a" });
    a.flushSync();

    const b = new TaskBoardStore(scope);
    expect(b.get("task-x")?.title).toBe("from-a");
  });
});
