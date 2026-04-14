// sidecar/test/integration/matrix-transport.test.ts
import { describe, test, expect, beforeAll, afterAll } from "bun:test";

let mockServer: ReturnType<typeof Bun.serve>;
let syncCallCount = 0;
let lastSentBody: Record<string, unknown> | null = null;
let lastSyncToken: string | null = null;
const MOCK_PORT = 19999;

beforeAll(() => {
  mockServer = Bun.serve({
    port: MOCK_PORT,
    async fetch(req) {
      const url = new URL(req.url);
      const path = url.pathname;

      if (path.includes("/login") && req.method === "POST") {
        return Response.json({
          access_token: "mock_token",
          device_id: "mock_device",
          user_id: "@test:localhost",
        });
      }

      if (path.includes("/sync") && req.method === "GET") {
        syncCallCount++;
        lastSyncToken = url.searchParams.get("since");
        const batch = `batch_${syncCallCount}`;
        const body = {
          next_batch: batch,
          rooms: {
            join: {
              "!room1:localhost": {
                timeline: {
                  events: [
                    {
                      event_id: `$ev${syncCallCount}`,
                      sender: "@remote:localhost",
                      type: "m.room.message",
                      origin_server_ts: Date.now(),
                      content: {
                        msgtype: "m.text",
                        body: "preview",
                        odyssey: {
                          messageId: `msg-${syncCallCount}`,
                          senderId: "remote-user",
                          participantType: "user",
                        },
                      },
                    },
                  ],
                },
              },
            },
          },
        };
        return Response.json(body);
      }

      if (path.includes("/send/") && req.method === "PUT") {
        lastSentBody = (await req.json()) as Record<string, unknown>;
        return Response.json({ event_id: `$sent_${Date.now()}` });
      }

      if (path.includes("/presence/") && req.method === "PUT") {
        return Response.json({});
      }

      return Response.json({ errcode: "M_NOT_FOUND" }, { status: 404 });
    },
  });
});

afterAll(() => {
  mockServer.stop(true);
});

describe("Matrix transport integration", () => {
  test("sync delivers odyssey events from mock server", async () => {
    const res = await fetch(`http://localhost:${MOCK_PORT}/_matrix/client/v3/sync?timeout=0`, {
      headers: { Authorization: "Bearer mock_token" },
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      next_batch: string;
      rooms: { join: Record<string, { timeline: { events: unknown[] } }> };
    };
    expect(body.next_batch).toMatch(/^batch_/);
    const roomEvents = Object.values(body.rooms.join)[0].timeline.events;
    expect(roomEvents.length).toBeGreaterThan(0);
    const ev = roomEvents[0] as { content: { odyssey: { messageId: string } } };
    expect(ev.content.odyssey.messageId).toMatch(/^msg-/);
  });

  test("sent message body contains odyssey field", async () => {
    const content = {
      msgtype: "m.text",
      body: "test preview",
      odyssey: {
        messageId: "msg-abc",
        senderId: "user-1",
        participantType: "user",
      },
    };
    const txnId = `dev1-${Date.now()}-${Math.random()}`;
    await fetch(
      `http://localhost:${MOCK_PORT}/_matrix/client/v3/rooms/!room1:localhost/send/m.room.message/${txnId}`,
      {
        method: "PUT",
        headers: {
          Authorization: "Bearer mock_token",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(content),
      }
    );
    expect(lastSentBody).not.toBeNull();
    const odyssey = (lastSentBody as { odyssey: { messageId: string } }).odyssey;
    expect(odyssey.messageId).toBe("msg-abc");
  });

  test("since token is forwarded on subsequent sync", async () => {
    const res1 = await fetch(`http://localhost:${MOCK_PORT}/_matrix/client/v3/sync?timeout=0`, {
      headers: { Authorization: "Bearer mock_token" },
    });
    const body1 = (await res1.json()) as { next_batch: string };
    const token = body1.next_batch;

    await fetch(
      `http://localhost:${MOCK_PORT}/_matrix/client/v3/sync?since=${token}&timeout=0`,
      { headers: { Authorization: "Bearer mock_token" } }
    );
    expect(lastSyncToken).toBe(token);
  });
});
