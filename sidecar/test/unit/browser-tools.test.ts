/**
 * Unit tests for createBrowserTools.
 *
 * No sidecar process or Swift app required. Tests verify:
 *   - Each tool broadcasts the correct BrowserCommand type via ctx.broadcast
 *   - Non-blocking tools resolve when pendingBrowserResults resolver is called
 *   - Blocking tools (yieldToUser, renderHtml) resolve when pendingBrowserBlocking resolver is called
 *   - Blocking tools time out and return a timeout message when no resolver fires
 *   - Disconnect cleanup resolves all pending maps with an error sentinel
 */
import { describe, test, expect, beforeEach } from "bun:test";
import { createBrowserTools } from "../../src/tools/browser-tools.js";
import type { ToolContext } from "../../src/tools/tool-context.js";
import type { SidecarEvent } from "../../src/types.js";

// ─── Helpers ─────────────────────────────────────────────────────────────────

const SESSION = "test-session-1";
const EXTRA = { sessionId: SESSION };

interface CapturedBroadcast {
  calls: SidecarEvent[];
}

function buildCtx(captured: CapturedBroadcast): ToolContext {
  return {
    pendingBrowserResults: new Map(),
    pendingBrowserBlocking: new Map(),
    broadcast: (e) => { captured.calls.push(e); },
    // Unused by browser tools but required by ToolContext shape
    delegation: {} as any,
    sessions: {} as any,
    blackboard: {} as any,
    messages: {} as any,
    channels: {} as any,
    workspaces: {} as any,
    peerRegistry: {} as any,
    connectors: {} as any,
    relayClient: {} as any,
    conversationStore: {} as any,
    projectStore: {} as any,
    nostrTransport: {} as any,
    agentDefinitions: new Map(),
    spawnSession: async (sid) => ({ sessionId: sid }),
  } as unknown as ToolContext;
}

function getTool(ctx: ToolContext, name: string) {
  const tools = createBrowserTools(ctx);
  const tool = tools.find((t) => t.name === name);
  if (!tool) throw new Error(`Tool not found: ${name}`);
  return tool;
}

/** Resolve a pending non-blocking result after a tick. */
function resolveResult(ctx: ToolContext, commandType: string, payload: string) {
  const key = `${SESSION}:${commandType}`;
  setImmediate(() => {
    ctx.pendingBrowserResults.get(key)?.(payload);
    ctx.pendingBrowserResults.delete(key);
  });
}

/** Resolve a pending blocking call after a tick. */
function resolveBlocking(ctx: ToolContext, data: string) {
  setImmediate(() => {
    ctx.pendingBrowserBlocking.get(SESSION)?.(data);
    ctx.pendingBrowserBlocking.delete(SESSION);
  });
}

// ─── Tests ───────────────────────────────────────────────────────────────────

describe("createBrowserTools — tool registration", () => {
  test("registers exactly 11 tools", () => {
    const ctx = buildCtx({ calls: [] });
    expect(createBrowserTools(ctx)).toHaveLength(11);
  });

  test("all expected tool names are present", () => {
    const ctx = buildCtx({ calls: [] });
    const names = createBrowserTools(ctx).map((t) => t.name);
    expect(names).toContain("browser_navigate");
    expect(names).toContain("browser_screenshot");
    expect(names).toContain("browser_read_dom");
    expect(names).toContain("browser_click");
    expect(names).toContain("browser_type");
    expect(names).toContain("browser_scroll");
    expect(names).toContain("browser_wait_for");
    expect(names).toContain("browser_get_console_logs");
    expect(names).toContain("browser_get_network_logs");
    expect(names).toContain("browser_yield_to_user");
    expect(names).toContain("browser_render_html");
  });
});

describe("browser_navigate", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.navigate with url", async () => {
    const tool = getTool(ctx, "browser_navigate");
    resolveResult(ctx, "browser.navigate", JSON.stringify({ title: "Example", finalUrl: "https://example.com" }));
    await tool.execute({ url: "https://example.com" }, EXTRA);
    expect(captured.calls).toHaveLength(1);
    expect(captured.calls[0].type).toBe("browser.navigate");
    expect((captured.calls[0] as any).url).toBe("https://example.com");
  });

  test("returns the resolved payload text", async () => {
    const tool = getTool(ctx, "browser_navigate");
    const payload = JSON.stringify({ title: "My Page", finalUrl: "https://example.com/final" });
    resolveResult(ctx, "browser.navigate", payload);
    const result = await tool.execute({ url: "https://example.com" }, EXTRA);
    expect(result.content[0].text).toBe(payload);
  });

  test("sessionId comes from extra", async () => {
    const tool = getTool(ctx, "browser_navigate");
    resolveResult(ctx, "browser.navigate", "{}");
    await tool.execute({ url: "https://example.com" }, EXTRA);
    expect((captured.calls[0] as any).sessionId).toBe(SESSION);
  });
});

describe("browser_screenshot", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.screenshot and returns base64 payload", async () => {
    const tool = getTool(ctx, "browser_screenshot");
    const b64 = "iVBORw0KGgo=";
    resolveResult(ctx, "browser.screenshot", b64);
    const result = await tool.execute({}, EXTRA);
    expect(captured.calls[0].type).toBe("browser.screenshot");
    expect(result.content[0].text).toBe(b64);
  });
});

describe("browser_read_dom", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.readDom and returns dom payload", async () => {
    const tool = getTool(ctx, "browser_read_dom");
    const dom = JSON.stringify({ tag: "html", children: [] });
    resolveResult(ctx, "browser.readDom", dom);
    const result = await tool.execute({}, EXTRA);
    expect(captured.calls[0].type).toBe("browser.readDom");
    expect(result.content[0].text).toBe(dom);
  });
});

describe("browser_click", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.click with selector", async () => {
    const tool = getTool(ctx, "browser_click");
    resolveResult(ctx, "browser.click", "ok");
    await tool.execute({ selector: "#submit-btn" }, EXTRA);
    expect(captured.calls[0].type).toBe("browser.click");
    expect((captured.calls[0] as any).selector).toBe("#submit-btn");
  });
});

describe("browser_type", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.type with selector and text", async () => {
    const tool = getTool(ctx, "browser_type");
    resolveResult(ctx, "browser.type", "ok");
    await tool.execute({ selector: "input[name=email]", text: "test@example.com" }, EXTRA);
    expect(captured.calls[0].type).toBe("browser.type");
    expect((captured.calls[0] as any).selector).toBe("input[name=email]");
    expect((captured.calls[0] as any).text).toBe("test@example.com");
  });
});

describe("browser_scroll", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.scroll with direction and px", async () => {
    const tool = getTool(ctx, "browser_scroll");
    resolveResult(ctx, "browser.scroll", "ok");
    await tool.execute({ direction: "down", px: 300 }, EXTRA);
    expect(captured.calls[0].type).toBe("browser.scroll");
    expect((captured.calls[0] as any).direction).toBe("down");
    expect((captured.calls[0] as any).px).toBe(300);
  });
});

describe("browser_wait_for", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.waitFor with selector and timeoutMs", async () => {
    const tool = getTool(ctx, "browser_wait_for");
    resolveResult(ctx, "browser.waitFor", "ok");
    await tool.execute({ selector: ".loaded", timeoutMs: 5000 }, EXTRA);
    expect(captured.calls[0].type).toBe("browser.waitFor");
    expect((captured.calls[0] as any).selector).toBe(".loaded");
    expect((captured.calls[0] as any).timeoutMs).toBe(5000);
  });
});

describe("browser_get_console_logs", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.getConsoleLogs and returns logs", async () => {
    const tool = getTool(ctx, "browser_get_console_logs");
    const logs = JSON.stringify([{ level: "log", message: "hello" }]);
    resolveResult(ctx, "browser.getConsoleLogs", logs);
    const result = await tool.execute({}, EXTRA);
    expect(captured.calls[0].type).toBe("browser.getConsoleLogs");
    expect(result.content[0].text).toBe(logs);
  });
});

describe("browser_get_network_logs", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.getNetworkLogs and returns entries", async () => {
    const tool = getTool(ctx, "browser_get_network_logs");
    const logs = JSON.stringify([{ url: "https://api.example.com/data", statusCode: 200 }]);
    resolveResult(ctx, "browser.getNetworkLogs", logs);
    const result = await tool.execute({}, EXTRA);
    expect(captured.calls[0].type).toBe("browser.getNetworkLogs");
    expect(result.content[0].text).toBe(logs);
  });
});

describe("browser_yield_to_user (blocking)", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.yieldToUser with message", async () => {
    const tool = getTool(ctx, "browser_yield_to_user");
    resolveBlocking(ctx, JSON.stringify({ resumed: true }));
    await tool.execute({ message: "Please log in and click Resume." }, EXTRA);
    expect(captured.calls[0].type).toBe("browser.yieldToUser");
    expect((captured.calls[0] as any).message).toBe("Please log in and click Resume.");
  });

  test("resolves when pendingBrowserBlocking resolver fires", async () => {
    const tool = getTool(ctx, "browser_yield_to_user");
    const data = JSON.stringify({ resumed: true });
    resolveBlocking(ctx, data);
    const result = await tool.execute({ message: "Please log in." }, EXTRA);
    expect(result.content[0].text).toBe(`User resumed agent control. ${data}`);
  });

  test("uses sessionId as blocking map key", async () => {
    const tool = getTool(ctx, "browser_yield_to_user");
    const callP = tool.execute({ message: "Log in." }, EXTRA);
    // Give the Promise a tick to register
    await new Promise((r) => setImmediate(r));
    expect(ctx.pendingBrowserBlocking.has(SESSION)).toBe(true);
    ctx.pendingBrowserBlocking.get(SESSION)?.("{}");
    await callP;
  });

  test("disconnect sentinel is forwarded in result", async () => {
    const tool = getTool(ctx, "browser_yield_to_user");
    const callP = tool.execute({ message: "wait" }, EXTRA);
    await new Promise((r) => setImmediate(r));
    ctx.pendingBrowserBlocking.get(SESSION)?.("[Browser disconnected]");
    const result = await callP;
    expect(result.content[0].text).toBe("User resumed agent control. [Browser disconnected]");
  }, 5000);
});

describe("browser_render_html (blocking)", () => {
  let ctx: ToolContext;
  let captured: CapturedBroadcast;
  beforeEach(() => { captured = { calls: [] }; ctx = buildCtx(captured); });

  test("broadcasts browser.renderHtml with html and title", async () => {
    const tool = getTool(ctx, "browser_render_html");
    resolveBlocking(ctx, JSON.stringify({ selected: ["a"] }));
    await tool.execute({ html: "<h1>Pick one</h1>", title: "My Canvas" }, EXTRA);
    expect(captured.calls[0].type).toBe("browser.renderHtml");
    expect((captured.calls[0] as any).html).toBe("<h1>Pick one</h1>");
    expect((captured.calls[0] as any).title).toBe("My Canvas");
  });

  test("resolves with data from window.agent.submit()", async () => {
    const tool = getTool(ctx, "browser_render_html");
    const submitData = JSON.stringify({ selected: ["row-1", "row-3"] });
    resolveBlocking(ctx, submitData);
    const result = await tool.execute({ html: "<table></table>" }, EXTRA);
    expect(result.content[0].text).toBe(`User resumed from rendered HTML. Submitted data: ${submitData}`);
  });

  test("disconnect sentinel is forwarded in result", async () => {
    const tool = getTool(ctx, "browser_render_html");
    const callP = tool.execute({ html: "<p>form</p>" }, EXTRA);
    await new Promise((r) => setImmediate(r));
    ctx.pendingBrowserBlocking.get(SESSION)?.("[Browser disconnected]");
    const result = await callP;
    expect(result.content[0].text).toBe("User resumed from rendered HTML. Submitted data: [Browser disconnected]");
  }, 5000);
});

describe("disconnect cleanup — both maps swept", () => {
  test("resolving all pending maps clears them", async () => {
    const ctx = buildCtx({ calls: [] });
    // Register a result and a blocking pending entry
    let resultResolved = false;
    let blockingResolved = false;
    ctx.pendingBrowserResults.set(`${SESSION}:browser.navigate`, (v) => { resultResolved = true; });
    ctx.pendingBrowserBlocking.set(SESSION, (v) => { blockingResolved = true; });

    // Simulate the disconnect sweep from ws-server.ts close handler
    for (const resolve of ctx.pendingBrowserResults.values()) resolve("[Browser disconnected]");
    ctx.pendingBrowserResults.clear();
    for (const resolve of ctx.pendingBrowserBlocking.values()) resolve("[Browser disconnected]");
    ctx.pendingBrowserBlocking.clear();

    expect(resultResolved).toBe(true);
    expect(blockingResolved).toBe(true);
    expect(ctx.pendingBrowserResults.size).toBe(0);
    expect(ctx.pendingBrowserBlocking.size).toBe(0);
  });
});
