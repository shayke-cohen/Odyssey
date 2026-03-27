/**
 * GitHub remote detection utility.
 * Extracted from session-manager for testability.
 */

export function detectGitHubRemote(workingDirectory: string): string | null {
  try {
    const result = Bun.spawnSync(
      ["git", "remote", "get-url", "origin"],
      { cwd: workingDirectory, stdout: "pipe", stderr: "pipe" }
    );
    const remoteUrl = result.stdout.toString().trim();
    if (remoteUrl.includes("github.com")) return remoteUrl;
    return null;
  } catch {
    return null;
  }
}

export function buildGitHubPromptSection(remoteUrl: string): string {
  return `\n\n## GitHub Workspace

This workspace is a GitHub repository (\`${remoteUrl}\`). You can use the \`gh\` CLI (via Bash tool) to interact with issues, PRs, reviews, and releases.

**Use GitHub for durable, visible work artifacts** (issues for tasks, PRs for code changes, reviews for quality gates). Use PeerBus for real-time agent coordination.

Before using \`gh\` commands, verify auth: \`gh auth status\`. If not authenticated, skip GitHub workflows.\n`;
}
