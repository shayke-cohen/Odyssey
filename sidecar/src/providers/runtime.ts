import type {
  AgentConfig,
  AgentProvider,
  FileAttachment,
  SidecarEvent,
} from "../types.js";
import type { SessionRegistry } from "../stores/session-registry.js";
import type { ToolContext } from "../tools/tool-context.js";

type EventEmitter = (event: SidecarEvent) => void;

export interface RuntimeSendArgs {
  sessionId: string;
  config: AgentConfig;
  backendSessionId?: string;
  text: string;
  attachments?: FileAttachment[];
  planMode?: boolean;
  abortController: AbortController;
}

export interface RuntimeSendResult {
  backendSessionId?: string;
  resultText: string;
  costDelta: number;
  inputTokens: number;
  outputTokens: number;
  numTurns: number;
}

export interface RuntimeDependencies {
  emit: EventEmitter;
  registry: SessionRegistry;
  toolCtx: ToolContext;
}

export interface ProviderRuntime {
  readonly provider: AgentProvider;
  createSession(sessionId: string, config: AgentConfig): Promise<void>;
  sendMessage(args: RuntimeSendArgs): Promise<RuntimeSendResult>;
  resumeSession(sessionId: string, backendSessionId: string, config?: AgentConfig): Promise<void>;
  forkSession(
    parentSessionId: string,
    childSessionId: string,
    config: AgentConfig,
    parentBackendSessionId?: string,
  ): Promise<string | undefined>;
  pauseSession(sessionId: string): Promise<void>;
  answerQuestion?(sessionId: string, questionId: string, answer: string, selectedOptions?: string[]): Promise<boolean>;
  answerConfirmation?(sessionId: string, confirmationId: string, approved: boolean, modifiedAction?: string): Promise<boolean>;
  buildTurnOptionsForTesting?(
    sessionId: string,
    config: AgentConfig,
    backendSessionId: string | undefined,
    attachmentCount: number,
    planMode?: boolean,
  ): Record<string, any>;
}
