import type { DelegationMode } from "../types.js";

export interface DelegationConfig {
  mode: DelegationMode;
  targetAgentName?: string;
}

export class DelegationStore {
  private readonly configs = new Map<string, DelegationConfig>();

  get(sessionId: string): DelegationConfig {
    return this.configs.get(sessionId) ?? { mode: "off" };
  }

  set(sessionId: string, config: DelegationConfig): void {
    this.configs.set(sessionId, config);
  }

  delete(sessionId: string): void {
    this.configs.delete(sessionId);
  }

  resolveTarget(
    sessionId: string,
    nominatedAgent: string | undefined,
  ): string | undefined {
    const config = this.get(sessionId);
    switch (config.mode) {
      case "off":
      case "by_agents":
        return nominatedAgent;
      case "specific_agent":
      case "coordinator":
        return config.targetAgentName ?? nominatedAgent;
    }
  }
}
