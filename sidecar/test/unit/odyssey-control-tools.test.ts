/**
 * Regression tests for the odyssey-control MCP tool catalog.
 *
 * Covers:
 * - odysseyControlToolDefinitions has the expected 23 tools with correct metadata
 * - List tools return real agents/groups/skills from ~/.odyssey/config
 * - Get tools retrieve individual entities by name
 * - Round-trip write→list→get→delete for agents and groups
 * - Error cases return gracefully (no throws) for nonexistent entities
 * - Schedule tools handle missing data file gracefully
 *
 * These tests read from and write to ~/.odyssey/config (same dir the app uses).
 * The write round-trip uses a "zzz-regression-test" name so it sorts last and
 * is obviously a test fixture. afterAll cleans it up.
 *
 * Usage: bun test test/unit/odyssey-control-tools.test.ts
 */
import { describe, test, expect, afterAll } from "bun:test";
import { existsSync, unlinkSync, rmdirSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { odysseyControlToolDefinitions } from "../../src/tools/odyssey-control-server.js";

const CONFIG_DIR = process.env.ODYSSEY_CONFIG_DIR ?? join(homedir(), ".odyssey", "config");

// Clean up test fixtures written during round-trip tests
afterAll(() => {
  const agentPath = join(CONFIG_DIR, "agents", "zzz-regression-test.json");
  const groupPath = join(CONFIG_DIR, "groups", "zzz-regression-test.json");
  const skillPath = join(CONFIG_DIR, "skills", "zzz-regression-test", "SKILL.md");
  if (existsSync(agentPath)) unlinkSync(agentPath);
  if (existsSync(groupPath)) unlinkSync(groupPath);
  if (existsSync(skillPath)) {
    unlinkSync(skillPath);
    rmdirSync(join(CONFIG_DIR, "skills", "zzz-regression-test"));
  }
});

function tool(name: string) {
  const t = odysseyControlToolDefinitions.find((t) => t.name === name);
  if (!t) throw new Error(`Tool "${name}" not found in odysseyControlToolDefinitions`);
  return t;
}

function parseResult(result: { content: { text: string }[] }) {
  return JSON.parse(result.content[0].text);
}

// ─── Tool catalog ─────────────────────────────────────────────────────────────

const EXPECTED_TOOLS = [
  "list_agents", "get_agent", "create_or_update_agent", "delete_agent",
  "list_groups", "get_group", "create_or_update_group", "delete_group",
  "list_skills", "get_skill", "update_skill",
  "open_chat", "open_group_chat",
  "list_projects", "open_project",
  "list_schedules", "get_schedule", "create_schedule", "update_schedule", "delete_schedule", "trigger_schedule",
  "get_whats_new", "get_app_status",
];

describe("odysseyControlToolDefinitions", () => {
  test("has exactly 23 tools", () => {
    expect(odysseyControlToolDefinitions.length).toBe(23);
  });

  test("contains all expected tool names", () => {
    const names = odysseyControlToolDefinitions.map((t) => t.name);
    for (const expected of EXPECTED_TOOLS) {
      expect(names).toContain(expected);
    }
  });

  test("every tool has a non-empty description", () => {
    for (const t of odysseyControlToolDefinitions) {
      expect(t.description.length).toBeGreaterThan(0);
    }
  });

  test("every tool has an execute function", () => {
    for (const t of odysseyControlToolDefinitions) {
      expect(typeof t.execute).toBe("function");
    }
  });

  test("no duplicate tool names", () => {
    const names = odysseyControlToolDefinitions.map((t) => t.name);
    expect(new Set(names).size).toBe(names.length);
  });
});

// ─── list_agents: real data ────────────────────────────────────────────────────

describe("list_agents", () => {
  test("returns real agents from config dir", async () => {
    const result = await tool("list_agents").execute({});
    const { agents } = parseResult(result);
    expect(Array.isArray(agents)).toBe(true);
    expect(agents.length).toBeGreaterThan(0);
  });

  test("includes known agents (Coder, Designer) with required fields", async () => {
    const result = await tool("list_agents").execute({});
    const { agents } = parseResult(result);
    const names = agents.map((a: any) => a.name);
    expect(names).toContain("Coder");
    expect(names).toContain("Designer");
    // Verify shape
    const coder = agents.find((a: any) => a.name === "Coder");
    expect(coder.description).toBeDefined();
    expect(typeof coder.enabled).toBe("boolean");
    expect(coder.model).toBeDefined();
  });

  test("enabled=true filter returns only enabled agents", async () => {
    const result = await tool("list_agents").execute({ enabled: true });
    const { agents } = parseResult(result);
    expect(Array.isArray(agents)).toBe(true);
    for (const a of agents) {
      expect(a.enabled).toBe(true);
    }
  });
});

// ─── get_agent: real data ─────────────────────────────────────────────────────

describe("get_agent", () => {
  test("retrieves Coder agent by name", async () => {
    const result = await tool("get_agent").execute({ name: "Coder" });
    const agent = parseResult(result);
    expect(agent.name).toBe("Coder");
    expect(agent.agentDescription).toBeDefined();
    expect(agent.enabled).toBe(true);
  });

  test("retrieves agent case-insensitively", async () => {
    const result = await tool("get_agent").execute({ name: "coder" });
    const agent = parseResult(result);
    expect(agent.name).toBe("Coder");
  });

  test("returns error object for nonexistent agent", async () => {
    const result = await tool("get_agent").execute({ name: "__nonexistent_xyz__" });
    const parsed = parseResult(result);
    expect(parsed.error).toBeDefined();
  });
});

// ─── list_groups: real data ───────────────────────────────────────────────────

describe("list_groups", () => {
  test("returns real groups from config dir", async () => {
    const result = await tool("list_groups").execute({});
    const { groups } = parseResult(result);
    expect(Array.isArray(groups)).toBe(true);
    expect(groups.length).toBeGreaterThan(0);
  });

  test("includes Dev Squad with required fields", async () => {
    const result = await tool("list_groups").execute({});
    const { groups } = parseResult(result);
    const names = groups.map((g: any) => g.name);
    expect(names).toContain("Dev Squad");
    const devSquad = groups.find((g: any) => g.name === "Dev Squad");
    expect(typeof devSquad.enabled).toBe("boolean");
  });
});

// ─── get_group: real data ─────────────────────────────────────────────────────

describe("get_group", () => {
  test("retrieves Dev Squad by name", async () => {
    const result = await tool("get_group").execute({ name: "Dev Squad" });
    const group = parseResult(result);
    expect(group.name).toBe("Dev Squad");
    expect(Array.isArray(group.agentNames)).toBe(true);
  });

  test("returns error for nonexistent group", async () => {
    const result = await tool("get_group").execute({ name: "__nonexistent_xyz__" });
    expect(parseResult(result).error).toBeDefined();
  });
});

// ─── list_skills: real data ───────────────────────────────────────────────────

describe("list_skills", () => {
  test("returns real skills from config dir", async () => {
    const result = await tool("list_skills").execute({});
    const { skills } = parseResult(result);
    expect(Array.isArray(skills)).toBe(true);
    expect(skills.length).toBeGreaterThan(0);
  });

  test("includes ulysses-knowledge skill", async () => {
    const result = await tool("list_skills").execute({});
    const { skills } = parseResult(result);
    const names = skills.map((s: any) => s.name);
    expect(names).toContain("ulysses-knowledge");
  });
});

// ─── get_skill: real data ─────────────────────────────────────────────────────

describe("get_skill", () => {
  test("retrieves ulysses-knowledge SKILL.md content", async () => {
    const result = await tool("get_skill").execute({ name: "ulysses-knowledge" });
    const content = result.content[0].text;
    expect(content).toContain("ulysses-knowledge");
    expect(content.length).toBeGreaterThan(100);
  });

  test("returns error for nonexistent skill", async () => {
    const result = await tool("get_skill").execute({ name: "__nonexistent_xyz__" });
    expect(parseResult(result).error).toBeDefined();
  });
});

// ─── Round-trip: create_or_update_agent → get_agent → delete_agent ───────────

describe("agent round-trip", () => {
  const TEST_NAME = "Zzz Regression Test";

  test("creates agent and verifies it appears in list_agents", async () => {
    const writeResult = await tool("create_or_update_agent").execute({
      name: TEST_NAME,
      fields: { agentDescription: "Temporary regression test fixture", model: "haiku", color: "gray" },
    });
    expect(parseResult(writeResult).ok).toBe(true);

    const listResult = await tool("list_agents").execute({});
    const { agents } = parseResult(listResult);
    const found = agents.find((a: any) => a.name === TEST_NAME);
    expect(found).toBeDefined();
    expect(found.description).toBe("Temporary regression test fixture");
  });

  test("get_agent retrieves the created agent", async () => {
    const result = await tool("get_agent").execute({ name: TEST_NAME });
    const agent = parseResult(result);
    expect(agent.name).toBe(TEST_NAME);
    expect(agent.model).toBe("haiku");
    expect(agent.color).toBe("gray");
  });

  test("update merges fields without overwriting unrelated ones", async () => {
    const result = await tool("create_or_update_agent").execute({
      name: TEST_NAME,
      fields: { color: "purple" },
    });
    expect(parseResult(result).ok).toBe(true);

    const getResult = await tool("get_agent").execute({ name: TEST_NAME });
    const agent = parseResult(getResult);
    expect(agent.color).toBe("purple");
    expect(agent.model).toBe("haiku"); // preserved from previous write
  });

  test("delete_agent removes the agent", async () => {
    const result = await tool("delete_agent").execute({ name: TEST_NAME });
    expect(parseResult(result).ok).toBe(true);

    const getResult = await tool("get_agent").execute({ name: TEST_NAME });
    expect(parseResult(getResult).error).toBeDefined();
  });
});

// ─── Round-trip: create_or_update_group → get_group → delete_group ───────────

describe("group round-trip", () => {
  const TEST_NAME = "Zzz Regression Test";

  test("creates group and verifies it appears in list_groups", async () => {
    const writeResult = await tool("create_or_update_group").execute({
      name: TEST_NAME,
      fields: { groupDescription: "Temporary regression test group", agentNames: ["Coder"] },
    });
    expect(parseResult(writeResult).ok).toBe(true);

    const listResult = await tool("list_groups").execute({});
    const { groups } = parseResult(listResult);
    const found = groups.find((g: any) => g.name === TEST_NAME);
    expect(found).toBeDefined();
  });

  test("get_group retrieves the created group", async () => {
    const result = await tool("get_group").execute({ name: TEST_NAME });
    const group = parseResult(result);
    expect(group.name).toBe(TEST_NAME);
    expect(group.agentNames).toContain("Coder");
  });

  test("delete_group removes the group", async () => {
    const result = await tool("delete_group").execute({ name: TEST_NAME });
    expect(parseResult(result).ok).toBe(true);

    const getResult = await tool("get_group").execute({ name: TEST_NAME });
    expect(parseResult(getResult).error).toBeDefined();
  });
});

// ─── Round-trip: update_skill → get_skill ─────────────────────────────────────

describe("skill round-trip", () => {
  const TEST_NAME = "zzz-regression-test";
  const CONTENT = `---\nname: zzz-regression-test\ndescription: Temporary test skill\n---\n\nRegression test content.\n`;

  test("writes skill and verifies it appears in list_skills", async () => {
    const writeResult = await tool("update_skill").execute({ name: TEST_NAME, content: CONTENT });
    expect(parseResult(writeResult).ok).toBe(true);

    const listResult = await tool("list_skills").execute({});
    const { skills } = parseResult(listResult);
    expect(skills.map((s: any) => s.name)).toContain(TEST_NAME);
  });

  test("get_skill returns the written content", async () => {
    const result = await tool("get_skill").execute({ name: TEST_NAME });
    expect(result.content[0].text).toContain("Regression test content.");
  });
});

// ─── Schedule read tools ──────────────────────────────────────────────────────

describe("list_schedules", () => {
  test("returns a schedules array (empty or populated)", async () => {
    const result = await tool("list_schedules").execute({});
    const { schedules } = parseResult(result);
    expect(Array.isArray(schedules)).toBe(true);
  });

  test("each schedule has required fields when populated", async () => {
    const result = await tool("list_schedules").execute({});
    const { schedules } = parseResult(result);
    for (const s of schedules) {
      expect(s.id).toBeDefined();
      expect(s.name).toBeDefined();
      expect(typeof s.isEnabled).toBe("boolean");
    }
  });
});

describe("get_schedule", () => {
  test("returns error for nonexistent schedule", async () => {
    const result = await tool("get_schedule").execute({ id_or_name: "__nonexistent_xyz__" });
    expect(parseResult(result).error).toBeDefined();
  });
});

describe("update_schedule", () => {
  test("returns error when schedule is not found", async () => {
    const result = await tool("update_schedule").execute({ id_or_name: "__nonexistent__", fields: { isEnabled: false } });
    expect(parseResult(result).error).toBeDefined();
  });
});

describe("delete_schedule", () => {
  test("returns error when schedule is not found", async () => {
    const result = await tool("delete_schedule").execute({ id_or_name: "__nonexistent__" });
    expect(parseResult(result).error).toBeDefined();
  });
});

describe("trigger_schedule", () => {
  test("returns error when schedule is not found", async () => {
    const result = await tool("trigger_schedule").execute({ id_or_name: "__nonexistent__" });
    expect(parseResult(result).error).toBeDefined();
  });
});

// ─── System tools ─────────────────────────────────────────────────────────────

describe("get_whats_new", () => {
  test("returns a defined object without throwing", async () => {
    const result = await tool("get_whats_new").execute({});
    expect(result.content.length).toBeGreaterThan(0);
    expect(parseResult(result)).toBeDefined();
  });
});
