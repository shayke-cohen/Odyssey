import { describe, test, expect } from "bun:test";
import { detectGitHubRemote, buildGitHubPromptSection } from "../../src/utils/github-detection.js";

describe("GitHub Detection", () => {
  test("detects GitHub remote in the ClaudPeer repo", () => {
    // Use the project root (parent of sidecar/) as test fixture
    const projectRoot = new URL("../../../", import.meta.url).pathname.replace(/\/$/, "");
    const remote = detectGitHubRemote(projectRoot);
    expect(remote).toContain("github.com");
  });

  test("returns null for non-git directory", () => {
    const remote = detectGitHubRemote("/tmp");
    expect(remote).toBeNull();
  });

  test("returns null for nonexistent directory", () => {
    const remote = detectGitHubRemote("/nonexistent/path/that/does/not/exist");
    expect(remote).toBeNull();
  });

  test("buildGitHubPromptSection includes key elements", () => {
    const section = buildGitHubPromptSection("git@github.com:user/repo.git");
    expect(section).toContain("GitHub Workspace");
    expect(section).toContain("gh auth status");
    expect(section).toContain("git@github.com:user/repo.git");
    expect(section).toContain("gh` CLI");
    expect(section).toContain("PeerBus");
  });

  test("buildGitHubPromptSection works with HTTPS URL", () => {
    const section = buildGitHubPromptSection("https://github.com/user/repo.git");
    expect(section).toContain("https://github.com/user/repo.git");
    expect(section).toContain("GitHub Workspace");
  });
});
