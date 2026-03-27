import { describe, test, expect } from "bun:test";
import { buildSkillsSection } from "../../src/utils/prompt-builder.js";

describe("Skill Injection", () => {
  test("empty skills returns empty string", () => {
    expect(buildSkillsSection([])).toBe("");
  });

  test("null-ish skills returns empty string", () => {
    expect(buildSkillsSection(undefined as any)).toBe("");
    expect(buildSkillsSection(null as any)).toBe("");
  });

  test("single skill formatted correctly", () => {
    const result = buildSkillsSection([
      { name: "github-workflow", content: "Use GitHub for durable artifacts." },
    ]);
    expect(result).toContain("## Skills");
    expect(result).toContain("### github-workflow");
    expect(result).toContain("Use GitHub for durable artifacts.");
  });

  test("multiple skills all included in order", () => {
    const result = buildSkillsSection([
      { name: "peer-collaboration", content: "PeerBus docs" },
      { name: "github-workflow", content: "GitHub docs" },
      { name: "blackboard-patterns", content: "Blackboard docs" },
    ]);
    expect(result).toContain("### peer-collaboration");
    expect(result).toContain("### github-workflow");
    expect(result).toContain("### blackboard-patterns");
    // Verify ordering: peer-collaboration appears before github-workflow
    const peerIdx = result.indexOf("### peer-collaboration");
    const ghIdx = result.indexOf("### github-workflow");
    const bbIdx = result.indexOf("### blackboard-patterns");
    expect(peerIdx).toBeLessThan(ghIdx);
    expect(ghIdx).toBeLessThan(bbIdx);
  });

  test("skill content with markdown preserved", () => {
    const result = buildSkillsSection([
      {
        name: "github-workflow",
        content: "## When to Activate\n\n- **Issues** for bugs\n- **PRs** for code changes",
      },
    ]);
    expect(result).toContain("## When to Activate");
    expect(result).toContain("- **Issues** for bugs");
  });
});
