import type { SessionState, AgentConfig } from "../types.js";

export class SessionRegistry {
  private sessions = new Map<string, SessionState>();
  private configs = new Map<string, AgentConfig>();

  create(id: string, config: AgentConfig): SessionState {
    const state: SessionState = {
      id,
      agentName: config.name,
      provider: config.provider ?? "claude",
      status: "active",
      tokenCount: 0,
      cost: 0,
      toolCallCount: 0,
      startedAt: new Date().toISOString(),
    };
    this.sessions.set(id, state);
    this.configs.set(id, config);
    return state;
  }

  get(id: string): SessionState | undefined {
    return this.sessions.get(id);
  }

  getConfig(id: string): AgentConfig | undefined {
    return this.configs.get(id);
  }

  update(id: string, updates: Partial<SessionState>): void {
    const session = this.sessions.get(id);
    if (session) {
      Object.assign(session, updates);
    }
  }

  updateConfig(id: string, updates: Partial<AgentConfig>): void {
    const config = this.configs.get(id);
    if (config) {
      Object.assign(config, updates);
    }
  }

  remove(id: string): void {
    this.sessions.delete(id);
    this.configs.delete(id);
  }

  list(): SessionState[] {
    return Array.from(this.sessions.values());
  }

  listActive(): SessionState[] {
    return this.list().filter((s) => s.status === "active");
  }

  findByAgentName(name: string): SessionState[] {
    return this.listActive().filter(
      (s) => s.agentName.toLowerCase() === name.toLowerCase(),
    );
  }
}
