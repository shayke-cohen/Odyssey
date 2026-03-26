/**
 * Structured JSON-line logger for the ClaudeStudio sidecar.
 *
 * Each line written to stdout is a single JSON object:
 *   {"ts":"2026-03-26T12:01:02.123Z","level":"info","category":"ws","message":"Client connected"}
 *
 * The Swift app captures stdout → sidecar.log, and the DebugLogView parses
 * these lines for display and filtering.
 */

export type SidecarLogLevel = "debug" | "info" | "warn" | "error";

const LEVEL_ORDER: Record<SidecarLogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

let currentLevel: SidecarLogLevel = "info";

/** Set the minimum log level. Messages below this level are suppressed. */
export function setLogLevel(level: SidecarLogLevel): void {
  if (level in LEVEL_ORDER) {
    currentLevel = level;
  }
}

/** Emit a structured log line to stdout/stderr. */
export function log(
  level: SidecarLogLevel,
  category: string,
  message: string,
  data?: Record<string, unknown>,
): void {
  if (LEVEL_ORDER[level] < LEVEL_ORDER[currentLevel]) return;

  const entry: Record<string, unknown> = {
    ts: new Date().toISOString(),
    level,
    category,
    message,
  };
  if (data) entry.data = data;

  const line = JSON.stringify(entry);

  // Route to the appropriate console method so Bun/Node colouring still works
  // when running interactively, while the Swift app captures everything via
  // the redirected stdout/stderr file handles.
  switch (level) {
    case "error":
      console.error(line);
      break;
    case "warn":
      console.warn(line);
      break;
    default:
      console.log(line);
      break;
  }
}

/** Convenience wrappers scoped by category. */
export const logger = {
  debug: (category: string, message: string, data?: Record<string, unknown>) =>
    log("debug", category, message, data),
  info: (category: string, message: string, data?: Record<string, unknown>) =>
    log("info", category, message, data),
  warn: (category: string, message: string, data?: Record<string, unknown>) =>
    log("warn", category, message, data),
  error: (category: string, message: string, data?: Record<string, unknown>) =>
    log("error", category, message, data),
};
