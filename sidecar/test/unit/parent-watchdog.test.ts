import { describe, test, expect } from "bun:test";
import { startParentWatchdog } from "../../src/utils/parent-watchdog.js";

describe("startParentWatchdog", () => {
  test("calls onParentDead when parent is no longer alive", async () => {
    let deathFired = false;
    const wd = startParentWatchdog({
      parentPid: 99999,
      intervalMs: 10,
      isAlive: () => false,
      onParentDead: () => { deathFired = true; },
    });

    await new Promise((r) => setTimeout(r, 30));
    wd.stop();
    expect(deathFired).toBe(true);
  });

  test("does not fire when parent is alive", async () => {
    let deathFired = false;
    const wd = startParentWatchdog({
      parentPid: process.pid,
      intervalMs: 10,
      isAlive: () => true,
      onParentDead: () => { deathFired = true; },
    });

    await new Promise((r) => setTimeout(r, 30));
    wd.stop();
    expect(deathFired).toBe(false);
  });

  test("stop() halts the poll", async () => {
    let calls = 0;
    const wd = startParentWatchdog({
      parentPid: 99999,
      intervalMs: 10,
      isAlive: () => {
        calls++;
        return true;
      },
      onParentDead: () => {},
    });

    await new Promise((r) => setTimeout(r, 25));
    wd.stop();
    const callsAtStop = calls;

    await new Promise((r) => setTimeout(r, 25));
    expect(calls).toBe(callsAtStop);
  });

  test("real process.kill check works for current PID", async () => {
    // No stub: relies on the real defaultIsAlive helper. Current process MUST be alive.
    let deathFired = false;
    const wd = startParentWatchdog({
      parentPid: process.pid,
      intervalMs: 10,
      onParentDead: () => { deathFired = true; },
    });

    await new Promise((r) => setTimeout(r, 30));
    wd.stop();
    expect(deathFired).toBe(false);
  });
});
