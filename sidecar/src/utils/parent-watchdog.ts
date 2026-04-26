/**
 * Parent-process watchdog.
 *
 * If the Swift app crashes or is force-quit, the sidecar would otherwise stay
 * running and hold its WebSocket port. This poller detects parent death by
 * sending signal 0 (alive check) to the parent PID — `process.kill(pid, 0)`
 * throws ESRCH when the process no longer exists.
 */

import { logger } from "../logger.js";

export interface ParentWatchdogOptions {
  parentPid: number;
  intervalMs?: number;
  /** Defaults to logging + process.exit(0). Tests inject a custom callback. */
  onParentDead?: () => void;
  /** Default: real `process.kill`. Tests inject a stub. */
  isAlive?: (pid: number) => boolean;
}

const DEFAULT_INTERVAL_MS = 2000;

export function startParentWatchdog(opts: ParentWatchdogOptions): { stop: () => void } {
  const interval = opts.intervalMs ?? DEFAULT_INTERVAL_MS;
  const isAlive = opts.isAlive ?? defaultIsAlive;
  const onDead = opts.onParentDead ?? (() => {
    logger.warn("sidecar", `Parent process ${opts.parentPid} no longer exists; shutting down`);
    process.exit(0);
  });

  const timer = setInterval(() => {
    if (!isAlive(opts.parentPid)) {
      clearInterval(timer);
      onDead();
    }
  }, interval);

  // Don't keep the event loop alive solely for this watchdog.
  if (typeof timer.unref === "function") timer.unref();

  return {
    stop: () => clearInterval(timer),
  };
}

function defaultIsAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}
