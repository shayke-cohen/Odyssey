// Commands from Swift -> Sidecar
export type SidecarCommand =
  | { type: "session.create"; conversationId: string; agentConfig: AgentConfig }
  | { type: "session.message"; sessionId: string; text: string; attachments?: FileAttachment[] }
  | { type: "session.resume"; sessionId: string; claudeSessionId: string }
  | { type: "session.fork"; sessionId: string; childSessionId: string }
  | { type: "session.pause"; sessionId: string }
  | { type: "agent.register"; agents: AgentDefinition[] }
  | { type: "delegate.task"; sessionId: string; toAgent: string; task: string; context?: string; waitForResult: boolean };

export interface AgentDefinition {
  name: string;
  config: AgentConfig;
  instancePolicy: "spawn" | "singleton" | { pool: number };
}

export interface AgentConfig {
  name: string;
  systemPrompt: string;
  allowedTools: string[];
  mcpServers: MCPServerConfig[];
  model: string;
  maxTurns?: number;
  maxBudget?: number;
  maxThinkingTokens?: number;
  workingDirectory: string;
  skills: SkillContent[];
  instancePolicy?: "spawn" | "singleton" | "pool";
  instancePolicyPoolMax?: number;
}

export interface MCPServerConfig {
  name: string;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  url?: string;
}

export interface SkillContent {
  name: string;
  content: string;
}

export interface FileAttachment {
  data: string;
  mediaType: string;
  fileName?: string;
}

// Events from Sidecar -> Swift
export type SidecarEvent =
  | { type: "stream.token"; sessionId: string; text: string }
  | { type: "stream.thinking"; sessionId: string; text: string }
  | { type: "stream.toolCall"; sessionId: string; tool: string; input: string }
  | { type: "stream.toolResult"; sessionId: string; tool: string; output: string }
  | { type: "session.result"; sessionId: string; result: string; cost: number }
  | { type: "session.error"; sessionId: string; error: string }
  | { type: "session.forked"; parentSessionId: string; childSessionId: string }
  | { type: "peer.chat"; channelId: string; from: string; message: string }
  | { type: "peer.delegate"; from: string; to: string; task: string }
  | { type: "blackboard.update"; key: string; value: string; writtenBy: string }
  | { type: "stream.image"; sessionId: string; imageData: string; mediaType: string; fileName?: string }
  | { type: "stream.fileCard"; sessionId: string; filePath: string; fileType: "html" | "pdf"; fileName: string }
  | { type: "sidecar.ready"; port: number; version: string };

// Session state
export interface SessionState {
  id: string;
  agentName: string;
  status: "active" | "paused" | "completed" | "failed";
  claudeSessionId?: string;
  tokenCount: number;
  cost: number;
  startedAt: string;
}

// Blackboard entry
export interface BlackboardEntry {
  key: string;
  value: string;
  writtenBy: string;
  workspaceId?: string;
  createdAt: string;
  updatedAt: string;
}
