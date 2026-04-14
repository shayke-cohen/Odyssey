export interface ProjectSummaryWire {
  id: string;
  name: string;
  rootPath: string;
  icon: string;
  color: string;
  isPinned: boolean;
  pinnedAgentIds: string[];
}

export class ProjectStore {
  private projects = new Map<string, ProjectSummaryWire>();

  sync(projects: ProjectSummaryWire[]): void {
    this.projects.clear();
    for (const p of projects) {
      this.projects.set(p.id, p);
    }
  }

  list(): ProjectSummaryWire[] {
    return Array.from(this.projects.values())
      .sort((a, b) => (b.isPinned ? 1 : 0) - (a.isPinned ? 1 : 0) || a.name.localeCompare(b.name));
  }

  get(id: string): ProjectSummaryWire | undefined {
    return this.projects.get(id);
  }
}
