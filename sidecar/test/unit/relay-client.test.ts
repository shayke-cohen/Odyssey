/**
 * Unit tests for RelayClient.
 * Runs a minimal local WebSocket server and exercises the relay client
 * against it. Covers: connect, command correlation by id, timeout,
 * event forwarding, sendCommand on unconnected peer, disconnect/isConnected.
 */
import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { RelayClient } from "../../src/relay-client.js";
import type { SidecarCommand, SidecarEvent } from "../../src/types.js";

function startRelayEcho(port: number): Promise<{ close: () => void }> {
  let handler: ((msg: any) => any) | null = null;
  const server = Bun.serve({
    port,
    fetch(req, server) {
      if (server.upgrade(req)) return undefined as any;
      return new Response("no", { status: 404 });
    },
    websocket: {
      open() {},
      message(ws, data) {
        try {
          const msg = JSON.parse(typeof data === "string" ? data : "{}");
          if (msg.type === "relay.handshake") return;
          if (msg.commandId) {
            // Echo back a synthetic session.result with the same commandId
            ws.send(
              JSON.stringify({
                commandId: msg.commandId,
                event: {
                  type: "session.result",
                  sessionId: "echo",
                  result: `ack:${msg.command?.type ?? "unknown"}`,
                  cost: 0,
                  inputTokens: 0,
                  outputTokens: 0,
                  numTurns: 0,
                  toolCallCount: 0,
                },
              }),
            );
          }
        } catch {
          // ignore
        }
      },
    },
  });
  return Promise.resolve({ close: () => server.stop(true) });
}

function startRelayStreaming(port: number): Promise<{ close: () => void }> {
  const server = Bun.serve({
    port,
    fetch(req, s) {
      if (s.upgrade(req)) return undefined as any;
      return new Response("no", { status: 404 });
    },
    websocket: {
      open(ws) {
        setTimeout(() => {
          ws.send(
            JSON.stringify({
              type: "stream.token",
              sessionId: "remote",
              token: "hello",
            }),
          );
        }, 50);
      },
      message() {},
    },
  });
  return Promise.resolve({ close: () => server.stop(true) });
}

describe("RelayClient", () => {
  let port: number;
  let server: { close: () => void } | null = null;

  beforeEach(() => {
    port = 30000 + Math.floor(Math.random() * 5000);
  });

  afterEach(() => {
    if (server) {
      server.close();
      server = null;
    }
  });

  test("sendCommand throws when not connected", async () => {
    const client = new RelayClient(() => {});
    await expect(client.sendCommand("ghost", { type: "session.pause", sessionId: "x" } as SidecarCommand)).rejects.toThrow(
      /No relay connection/,
    );
  });

  test("isConnected is false before connect", () => {
    const client = new RelayClient(() => {});
    expect(client.isConnected("peer-a")).toBe(false);
  });

  test("connect + sendCommand correlates response by commandId", async () => {
    server = await startRelayEcho(port);
    const client = new RelayClient(() => {});
    await client.connect("peer-a", `ws://localhost:${port}`);
    expect(client.isConnected("peer-a")).toBe(true);

    const response = await client.sendCommand(
      "peer-a",
      { type: "session.pause", sessionId: "s1" } as SidecarCommand,
      2000,
    );
    expect(response.type).toBe("session.result");
    expect((response as any).result).toBe("ack:session.pause");
    client.disconnectAll();
  });

  test("connect is idempotent for same peer", async () => {
    server = await startRelayEcho(port);
    const client = new RelayClient(() => {});
    await client.connect("peer-a", `ws://localhost:${port}`);
    await client.connect("peer-a", `ws://localhost:${port}`);
    expect(client.isConnected("peer-a")).toBe(true);
    client.disconnectAll();
  });

  test("forwards non-correlated events to onEvent", async () => {
    server = await startRelayStreaming(port);
    const events: SidecarEvent[] = [];
    const client = new RelayClient((e) => events.push(e));
    await client.connect("peer-stream", `ws://localhost:${port}`);

    // Wait briefly for stream.token to arrive
    await new Promise((r) => setTimeout(r, 250));
    expect(events.some((e) => e.type === "stream.token")).toBe(true);
    client.disconnectAll();
  });

  test("sendCommand rejects on timeout", async () => {
    // Server that ignores messages — connect succeeds, echo never comes
    const silent = Bun.serve({
      port,
      fetch(req, s) {
        if (s.upgrade(req)) return undefined as any;
        return new Response();
      },
      websocket: { open() {}, message() {} },
    });
    server = { close: () => silent.stop(true) };
    const client = new RelayClient(() => {});
    await client.connect("peer-slow", `ws://localhost:${port}`);

    await expect(
      client.sendCommand(
        "peer-slow",
        { type: "session.pause", sessionId: "s1" } as SidecarCommand,
        80,
      ),
    ).rejects.toThrow(/timed out/);

    client.disconnectAll();
  });

  test("disconnect removes connection", async () => {
    server = await startRelayEcho(port);
    const client = new RelayClient(() => {});
    await client.connect("peer-a", `ws://localhost:${port}`);
    expect(client.isConnected("peer-a")).toBe(true);
    client.disconnect("peer-a");
    // Wait for close event to propagate
    await new Promise((r) => setTimeout(r, 50));
    expect(client.isConnected("peer-a")).toBe(false);
  });

  test("connect rejects on bad URL", async () => {
    const client = new RelayClient(() => {});
    // Use a port that nothing listens on
    await expect(client.connect("peer-x", `ws://127.0.0.1:1`)).rejects.toThrow();
  });
});
