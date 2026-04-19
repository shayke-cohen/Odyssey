/**
 * Minimal in-process Nostr relay for integration tests.
 *
 * Implements just enough of NIP-01 to allow local roundtrip tests:
 *   ["REQ", subId, { kinds: [...], "#p": [...] }]
 *   ["EVENT", event]
 *   ["CLOSE", subId]
 */
import type { ServerWebSocket } from 'bun'
import { createServer as createHttpServer } from 'http'
import type { Server } from 'http'

interface Subscription {
  kinds: number[]
  pTags: string[]
}

interface StoredEvent {
  id: string
  kind: number
  pubkey: string
  tags: string[][]
  content: string
  created_at: number
  sig: string
}

export class LocalNostrRelay {
  private server: ReturnType<typeof Bun.serve> | null = null
  private clients = new Set<ServerWebSocket<{ subs: Map<string, Subscription> }>>()
  private events: StoredEvent[] = []
  readonly port: number

  constructor(port: number) {
    this.port = port
  }

  start() {
    // eslint-disable-next-line @typescript-eslint/no-this-alias
    const relay = this
    this.server = Bun.serve<{ subs: Map<string, Subscription> }>({
      port: this.port,
      websocket: {
        open(ws) {
          ws.data = { subs: new Map() }
          relay.clients.add(ws)
        },
        close(ws) {
          relay.clients.delete(ws)
        },
        message(ws, raw) {
          const text = typeof raw === 'string' ? raw : Buffer.from(raw).toString()
          let msg: any
          try { msg = JSON.parse(text) } catch { return }
          if (!Array.isArray(msg) || msg.length < 2) return

          const verb = msg[0]
          if (verb === 'REQ') {
            const subId = msg[1] as string
            const filter = msg[2] ?? {}
            ws.data.subs.set(subId, {
              kinds: filter.kinds ?? [],
              pTags: filter['#p'] ?? [],
            })
            // Send back stored matching events
            for (const ev of relay.events) {
              if (relay.matchesSub(ev, ws.data.subs.get(subId)!)) {
                ws.send(JSON.stringify(['EVENT', subId, ev]))
              }
            }
            ws.send(JSON.stringify(['EOSE', subId]))

          } else if (verb === 'EVENT') {
            const event = msg[1] as StoredEvent
            if (!event?.id) return
            relay.events.push(event)
            // Fan out to all subscribers
            for (const client of relay.clients) {
              for (const [subId, sub] of client.data.subs) {
                if (relay.matchesSub(event, sub)) {
                  client.send(JSON.stringify(['EVENT', subId, event]))
                }
              }
            }
            ws.send(JSON.stringify(['OK', event.id, true, '']))

          } else if (verb === 'CLOSE') {
            const subId = msg[1] as string
            ws.data.subs.delete(subId)
          }
        },
      },
      fetch(req, server) {
        if (server.upgrade(req)) return undefined as any
        return new Response('Nostr relay', { status: 200 })
      },
    })
  }

  stop() {
    this.server?.stop(true)
    this.server = null
    this.clients.clear()
    this.events = []
  }

  private matchesSub(event: StoredEvent, sub: Subscription): boolean {
    if (sub.kinds.length > 0 && !sub.kinds.includes(event.kind)) return false
    if (sub.pTags.length > 0) {
      const eventPTags = event.tags.filter(t => t[0] === 'p').map(t => t[1])
      if (!sub.pTags.some(p => eventPTags.includes(p))) return false
    }
    return true
  }
}
