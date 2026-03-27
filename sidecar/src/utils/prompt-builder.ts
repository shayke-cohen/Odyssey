/**
 * System prompt building utilities.
 * Extracted from session-manager for testability.
 */

export function buildSkillsSection(skills: Array<{ name: string; content: string }>): string {
  if (!skills || skills.length === 0) return "";
  let section = "\n\n## Skills\n\n";
  for (const skill of skills) {
    section += `### ${skill.name}\n${skill.content}\n\n`;
  }
  return section;
}
