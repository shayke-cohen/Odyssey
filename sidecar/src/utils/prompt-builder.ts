/**
 * System prompt building utilities.
 * Extracted from session-manager for testability.
 */

export function buildSkillsSection(skills: Array<{ name: string; description?: string; content: string }>): string {
  if (!skills || skills.length === 0) return "";
  let section = "\n\n## Skills\n\n";
  for (const skill of skills) {
    section += `### ${skill.name}\n`;
    if (skill.description) {
      section += `> ${skill.description}\n\n`;
    }
    section += `${skill.content}\n\n`;
  }
  return section;
}
