import { describe, test, expect, beforeEach } from "bun:test";
import { ProjectStore } from "../../src/stores/project-store.js";
import type { ProjectSummaryWire } from "../../src/stores/project-store.js";

const makeProject = (id: string, name: string): ProjectSummaryWire => ({
  id, name, rootPath: `/Users/test/${name}`,
  icon: "folder", color: "blue", isPinned: false, pinnedAgentIds: [],
});

describe("ProjectStore", () => {
  let store: ProjectStore;
  beforeEach(() => { store = new ProjectStore(); });

  test("sync populates list()", () => {
    store.sync([makeProject("p1", "Alpha"), makeProject("p2", "Beta")]);
    expect(store.list()).toHaveLength(2);
  });

  test("sync replaces previous projects", () => {
    store.sync([makeProject("old", "Old")]);
    store.sync([makeProject("new", "New")]);
    expect(store.list().map(p => p.id)).toEqual(["new"]);
  });

  test("get returns project by id", () => {
    store.sync([makeProject("p1", "Alpha")]);
    expect(store.get("p1")?.name).toBe("Alpha");
    expect(store.get("missing")).toBeUndefined();
  });
});
