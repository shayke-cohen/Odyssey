import { readFileSync, writeFileSync, mkdirSync, existsSync, renameSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import type { BlackboardEntry } from "../types.js";
import { logger } from "../logger.js";

type ChangeListener = (entry: BlackboardEntry) => void;

const PERSIST_DEBOUNCE_MS = 50;

export class BlackboardStore {
  private entries = new Map<string, BlackboardEntry>();
  private listeners: { pattern: string; callback: ChangeListener }[] = [];
  private persistPath: string;
  private persistTimer: ReturnType<typeof setTimeout> | null = null;
  private persistCalls = 0;

  constructor(scope?: string) {
    const baseDir = process.env.ODYSSEY_DATA_DIR ?? process.env.CLAUDESTUDIO_DATA_DIR ?? join(homedir(), ".odyssey");
    const dir = join(baseDir, "blackboard");
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    this.persistPath = join(dir, `${scope ?? "global"}.json`);
    this.loadFromDisk();
  }

  write(key: string, value: string, writtenBy: string, workspaceId?: string): BlackboardEntry {
    const now = new Date().toISOString();
    const existing = this.entries.get(key);
    const entry: BlackboardEntry = {
      key,
      value,
      writtenBy,
      workspaceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    };
    this.entries.set(key, entry);
    this.schedulePersist();
    this.notifyListeners(entry);
    return entry;
  }

  read(key: string): BlackboardEntry | undefined {
    return this.entries.get(key);
  }

  query(pattern: string): BlackboardEntry[] {
    const regex = new RegExp("^" + pattern.replace(/\./g, "\\.").replace(/\*/g, ".*") + "$");
    const results: BlackboardEntry[] = [];
    for (const [key, entry] of this.entries) {
      if (regex.test(key)) results.push(entry);
    }
    return results;
  }

  keys(scope?: string): string[] {
    const allKeys = Array.from(this.entries.keys());
    if (!scope) return allKeys;
    return allKeys.filter((k) => {
      const entry = this.entries.get(k);
      return entry?.workspaceId === scope;
    });
  }

  subscribe(pattern: string, callback: ChangeListener): () => void {
    const listener = { pattern, callback };
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== listener);
    };
  }

  /** Force any pending debounced persist to flush immediately. Call on shutdown. */
  flushSync(): void {
    if (this.persistTimer !== null) {
      clearTimeout(this.persistTimer);
      this.persistTimer = null;
      this.persistNow();
    }
  }

  /** For tests: count of actual disk-write attempts (debounced or flushed). */
  get _persistCallCount(): number {
    return this.persistCalls;
  }

  private notifyListeners(entry: BlackboardEntry): void {
    for (const listener of this.listeners) {
      const regex = new RegExp(
        "^" + listener.pattern.replace(/\./g, "\\.").replace(/\*/g, ".*") + "$"
      );
      if (regex.test(entry.key)) {
        listener.callback(entry);
      }
    }
  }

  private loadFromDisk(): void {
    if (!existsSync(this.persistPath)) return;
    let raw: string;
    try {
      raw = readFileSync(this.persistPath, "utf-8");
    } catch (err) {
      logger.error("blackboard", `Failed to read ${this.persistPath}: ${err}`);
      return;
    }
    try {
      const data = JSON.parse(raw) as Record<string, BlackboardEntry>;
      for (const [key, entry] of Object.entries(data)) {
        this.entries.set(key, entry);
      }
    } catch (err) {
      // Corrupt JSON. Quarantine the file and continue empty so the operator
      // can recover (instead of silently losing state on every restart).
      const corruptPath = `${this.persistPath}.corrupt.${Date.now()}`;
      try {
        renameSync(this.persistPath, corruptPath);
        logger.error(
          "blackboard",
          `Corrupt blackboard at ${this.persistPath}: ${err}. Quarantined to ${corruptPath}; starting empty.`,
        );
      } catch (renameErr) {
        logger.error(
          "blackboard",
          `Corrupt blackboard at ${this.persistPath}: ${err}. Failed to quarantine: ${renameErr}`,
        );
      }
    }
  }

  private schedulePersist(): void {
    if (this.persistTimer !== null) return;
    this.persistTimer = setTimeout(() => {
      this.persistTimer = null;
      this.persistNow();
    }, PERSIST_DEBOUNCE_MS);
  }

  private persistNow(): void {
    this.persistCalls++;
    try {
      const obj: Record<string, BlackboardEntry> = {};
      for (const [key, entry] of this.entries) {
        obj[key] = entry;
      }
      writeFileSync(this.persistPath, JSON.stringify(obj, null, 2));
    } catch (err) {
      logger.error("blackboard", `Failed to persist ${this.persistPath}: ${err}`);
    }
  }
}
