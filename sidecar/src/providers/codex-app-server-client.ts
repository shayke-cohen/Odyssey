import { spawn, type ChildProcessWithoutNullStreams } from "child_process";
import { logger } from "../logger.js";

type JsonRpcResponse = {
  id: number | string;
  result?: any;
  error?: {
    code?: number;
    message?: string;
    data?: unknown;
  };
};

type JsonRpcRequest = {
  id: number | string;
  method: string;
  params?: any;
};

type JsonRpcNotification = {
  method: string;
  params?: any;
};

export interface CodexClientHandlers {
  onNotification?: (notification: JsonRpcNotification) => void;
  onRequest?: (request: JsonRpcRequest) => Promise<any>;
}

export interface CodexAppServerClientOptions {
  codexPath?: string;
  configOverrides?: string[];
  envOverrides?: Record<string, string>;
}

export class CodexAppServerClient {
  private process: ChildProcessWithoutNullStreams | null = null;
  private startPromise: Promise<void> | null = null;
  private nextId = 1;
  private pending = new Map<number | string, {
    resolve: (value: any) => void;
    reject: (error: Error) => void;
  }>();
  private stdoutBuffer = "";
  private stderrBuffer = "";
  private handlers: CodexClientHandlers = {};
  private readonly codexPath: string;
  private readonly configOverrides: string[];
  private readonly envOverrides: Record<string, string>;

  constructor(options: CodexAppServerClientOptions = {}) {
    this.codexPath = options.codexPath || process.env.CODEX_BINARY || "/Applications/Codex.app/Contents/Resources/codex";
    this.configOverrides = options.configOverrides ?? [];
    this.envOverrides = options.envOverrides ?? {};
  }

  setHandlers(handlers: CodexClientHandlers) {
    this.handlers = handlers;
  }

  async start(): Promise<void> {
    if (this.startPromise) {
      return this.startPromise;
    }

    this.startPromise = this.startInternal();
    try {
      await this.startPromise;
    } catch (error) {
      this.startPromise = null;
      throw error;
    }
  }

  async call(method: string, params?: any): Promise<any> {
    await this.start();
    return this.sendRequest(method, params);
  }

  async notify(method: string, params?: any): Promise<void> {
    await this.start();
    this.write({ method, ...(params !== undefined ? { params } : {}) });
  }

  async stop(): Promise<void> {
    if (!this.process) {
      return;
    }

    this.process.kill();
    this.process = null;
    this.startPromise = null;
  }

  private async startInternal(): Promise<void> {
    const env = {
      ...process.env,
      ...this.envOverrides,
    };
    env.PATH = env.PATH?.trim() || "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";

    logger.info("codex", `Starting codex app-server with ${this.codexPath}`, {
      codexHome: env.CODEX_HOME ?? null,
      configOverrideCount: this.configOverrides.length,
    });

    const args = ["app-server"];
    for (const override of this.configOverrides) {
      args.push("-c", override);
    }
    args.push("--listen", "stdio://");

    const child = spawn(this.codexPath, args, {
      stdio: ["pipe", "pipe", "pipe"],
      env,
    });

    this.process = child;

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => {
      this.stdoutBuffer += chunk;
      this.flushStdout();
    });

    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk: string) => {
      this.stderrBuffer += chunk;
      const lines = this.stderrBuffer.split("\n");
      this.stderrBuffer = lines.pop() ?? "";
      for (const line of lines) {
        if (line.trim().length > 0) {
          logger.warn("codex", line.trim());
        }
      }
    });

    child.on("exit", (code, signal) => {
      const error = new Error(`codex app-server exited (code=${code ?? "null"}, signal=${signal ?? "null"})`);
      for (const pending of this.pending.values()) {
        pending.reject(error);
      }
      this.pending.clear();
      this.process = null;
      this.startPromise = null;
    });

    await this.sendRequest("initialize", {
      clientInfo: {
        name: "claudestudio-sidecar",
        version: "0.1.0",
      },
      capabilities: {
        experimentalApi: true,
      },
    });
    this.write({ method: "initialized" });
  }

  private sendRequest(method: string, params?: any): Promise<any> {
    const id = this.nextId++;
    const payload = { id, method, ...(params !== undefined ? { params } : {}) };
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.write(payload);
    });
  }

  private flushStdout() {
    const lines = this.stdoutBuffer.split("\n");
    this.stdoutBuffer = lines.pop() ?? "";

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) {
        continue;
      }

      try {
        const parsed = JSON.parse(line);
        this.handleIncoming(parsed);
      } catch (error: any) {
        logger.error("codex", `Failed to parse app-server message: ${error?.message ?? error}`, { line });
      }
    }
  }

  private handleIncoming(payload: JsonRpcResponse | JsonRpcRequest | JsonRpcNotification) {
    if ("id" in payload && !("method" in payload)) {
      const pending = this.pending.get(payload.id);
      if (!pending) {
        return;
      }

      this.pending.delete(payload.id);
      if (payload.error) {
        pending.reject(new Error(payload.error.message ?? "Unknown JSON-RPC error"));
      } else {
        pending.resolve(payload.result);
      }
      return;
    }

    if ("id" in payload && "method" in payload) {
      this.handleServerRequest(payload as JsonRpcRequest).catch((error: any) => {
        this.write({
          id: payload.id,
          error: {
            code: -32000,
            message: error?.message ?? "Unhandled server request error",
          },
        });
      });
      return;
    }

    this.handlers.onNotification?.(payload as JsonRpcNotification);
  }

  private async handleServerRequest(request: JsonRpcRequest): Promise<void> {
    if (!this.handlers.onRequest) {
      this.write({
        id: request.id,
        error: {
          code: -32601,
          message: `No handler registered for ${request.method}`,
        },
      });
      return;
    }

    const result = await this.handlers.onRequest(request);
    this.write({ id: request.id, result });
  }

  private write(payload: unknown) {
    if (!this.process?.stdin.writable) {
      throw new Error("codex app-server stdin is not writable");
    }

    this.process.stdin.write(`${JSON.stringify(payload)}\n`);
  }
}
