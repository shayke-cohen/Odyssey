export interface PeerMessage {
  id: string;
  from: string;
  fromAgent: string;
  to: string;
  text: string;
  channel?: string;
  priority: "normal" | "urgent";
  timestamp: string;
  read: boolean;
}

export class MessageStore {
  private inboxes = new Map<string, PeerMessage[]>();

  push(to: string, message: PeerMessage): void {
    const inbox = this.inboxes.get(to) ?? [];
    inbox.push(message);
    this.inboxes.set(to, inbox);
  }

  pushToAll(message: Omit<PeerMessage, "to">, sessionIds: string[]): void {
    for (const sid of sessionIds) {
      if (sid === message.from) continue;
      this.push(sid, { ...message, to: sid });
    }
  }

  drain(sessionId: string, since?: string): PeerMessage[] {
    const inbox = this.inboxes.get(sessionId);
    if (!inbox || inbox.length === 0) return [];

    let messages: PeerMessage[];
    if (!since) {
      messages = inbox.filter((m) => !m.read);
    } else {
      const sinceTime = new Date(since).getTime();
      messages = inbox.filter(
        (m) => !m.read && new Date(m.timestamp).getTime() > sinceTime,
      );
    }
    for (const m of messages) m.read = true;

    // Compact: drop everything that's now read. Without this the inbox grew
    // unboundedly across long autonomous sessions and every drain/peek
    // walked the full history (O(n²) over a session). Unread messages that
    // were skipped by the `since` filter stay so a later unfiltered drain
    // can still pick them up.
    const remaining = inbox.filter((m) => !m.read);
    if (remaining.length === 0) {
      this.inboxes.delete(sessionId);
    } else {
      this.inboxes.set(sessionId, remaining);
    }
    return messages;
  }

  peek(sessionId: string): number {
    const inbox = this.inboxes.get(sessionId) ?? [];
    return inbox.filter((m) => !m.read).length;
  }
}
