import { describe, it, expect, beforeEach } from 'bun:test'
import { NostrTransport } from '../src/relay/nostr-transport.js'
import {
  generateNostrKeypair,
  privkeyHexToBytes,
  encryptMessage,
  signNostrEvent,
} from '../src/relay/nostr-crypto.js'

describe('NostrTransport peer management', () => {
  let transport: NostrTransport

  beforeEach(() => {
    transport = new NostrTransport((event) => {})
  })

  it('reports hasPeer false before addPeer', () => {
    expect(transport.hasPeer('bob')).toBe(false)
  })

  it('reports hasPeer true after addPeer', () => {
    const { pubkeyHex } = generateNostrKeypair()
    transport.addPeer('bob', pubkeyHex, [])
    expect(transport.hasPeer('bob')).toBe(true)
  })

  it('reports hasPeer false after removePeer', () => {
    const { pubkeyHex } = generateNostrKeypair()
    transport.addPeer('bob', pubkeyHex, [])
    transport.removePeer('bob')
    expect(transport.hasPeer('bob')).toBe(false)
  })

  it('throws sendMessage when identity not set', async () => {
    const { pubkeyHex } = generateNostrKeypair()
    transport.addPeer('bob', pubkeyHex, [])
    await expect(transport.sendMessage('bob', {
      id: '1', type: 'peer.message',
      from: { peer: 'alice' }, to: { peer: 'bob' },
      payload: {}, timestamp: new Date().toISOString(),
    })).rejects.toThrow('identity not set')
  })

  it('throws sendMessage for unknown peer', async () => {
    const kp = generateNostrKeypair()
    transport.setIdentity(kp.privkeyHex, kp.pubkeyHex, [])
    await expect(transport.sendMessage('nobody', {
      id: '2', type: 'peer.message',
      from: { peer: 'alice' }, to: { peer: 'nobody' },
      payload: {}, timestamp: new Date().toISOString(),
    })).rejects.toThrow('unknown peer nobody')
  })
})

describe('NostrTransport round-trip (two instances, no relay)', () => {
  it('delivers a message from alice to bob via direct relay mock', async () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()

    const received: any[] = []
    const bobTransport = new NostrTransport((event) => received.push(event))
    bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, [])
    bobTransport.addPeer('alice', alice.pubkeyHex, [])

    const aliceTransport = new NostrTransport((event) => {})
    aliceTransport.setIdentity(alice.privkeyHex, alice.pubkeyHex, [])
    aliceTransport.addPeer('bob', bob.pubkeyHex, [])

    const envelope = {
      id: 'test-1', type: 'peer.message' as const,
      from: { peer: 'alice' }, to: { peer: 'bob' },
      payload: { text: 'hello from alice' },
      timestamp: new Date().toISOString(),
    }

    const event = aliceTransport.buildEvent('bob', envelope)
    bobTransport.simulateIncomingEvent(event)

    expect(received).toHaveLength(1)
    expect((received[0] as any).type).toBe('peer.chat')
  })
})

describe('NostrTransport negative paths', () => {
  it('dedup: same event delivered twice results in only one broadcast', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()

    const received: any[] = []
    const bobTransport = new NostrTransport((event) => received.push(event))
    bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, [])
    bobTransport.addPeer('alice', alice.pubkeyHex, [])

    const aliceTransport = new NostrTransport((event) => {})
    aliceTransport.setIdentity(alice.privkeyHex, alice.pubkeyHex, [])
    aliceTransport.addPeer('bob', bob.pubkeyHex, [])

    const envelope = {
      id: 'dedup-1', type: 'peer.message' as const,
      from: { peer: 'alice' }, to: { peer: 'bob' },
      payload: 'hello',
      timestamp: new Date().toISOString(),
    }

    const event = aliceTransport.buildEvent('bob', envelope)
    bobTransport.simulateIncomingEvent(event)
    bobTransport.simulateIncomingEvent(event)

    expect(received.length).toBe(1)
  })

  it('tampered signature: mutated sig does not broadcast', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()

    const received: any[] = []
    const bobTransport = new NostrTransport((event) => received.push(event))
    bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, [])
    bobTransport.addPeer('alice', alice.pubkeyHex, [])

    const aliceTransport = new NostrTransport((event) => {})
    aliceTransport.setIdentity(alice.privkeyHex, alice.pubkeyHex, [])
    aliceTransport.addPeer('bob', bob.pubkeyHex, [])

    const envelope = {
      id: 'tamper-1', type: 'peer.message' as const,
      from: { peer: 'alice' }, to: { peer: 'bob' },
      payload: 'hello',
      timestamp: new Date().toISOString(),
    }

    const event = aliceTransport.buildEvent('bob', envelope)
    // Mutate the signature to make it invalid
    const tampered = { ...event, sig: 'a'.repeat(128) }
    bobTransport.simulateIncomingEvent(tampered as any)

    expect(received.length).toBe(0)
  })

  it('unknown peer pubkey: event from unknown sender does not broadcast', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()
    const stranger = generateNostrKeypair()

    const received: any[] = []
    const bobTransport = new NostrTransport((event) => received.push(event))
    bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, [])
    // Bob does NOT add alice as a peer

    // Stranger builds an event to bob
    const strangerTransport = new NostrTransport((event) => {})
    strangerTransport.setIdentity(stranger.privkeyHex, stranger.pubkeyHex, [])
    strangerTransport.addPeer('bob', bob.pubkeyHex, [])

    const envelope = {
      id: 'stranger-1', type: 'peer.message' as const,
      from: { peer: 'stranger' }, to: { peer: 'bob' },
      payload: 'hello',
      timestamp: new Date().toISOString(),
    }

    const event = strangerTransport.buildEvent('bob', envelope)
    bobTransport.simulateIncomingEvent(event)

    expect(received.length).toBe(0)
  })

  it('decrypt failure: ciphertext encrypted to wrong recipient does not broadcast', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()
    const carol = generateNostrKeypair()

    const received: any[] = []
    const bobTransport = new NostrTransport((event) => received.push(event))
    bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, [])
    bobTransport.addPeer('alice', alice.pubkeyHex, [])

    // Alice encrypts a message to carol (not bob), but signs it as from alice
    const alicePrivBytes = privkeyHexToBytes(alice.privkeyHex)
    const envelope = {
      id: 'wrongkey-1', type: 'peer.message' as const,
      from: { peer: 'alice' }, to: { peer: 'carol' },
      payload: 'hello',
      timestamp: new Date().toISOString(),
    }
    // Encrypt to carol instead of bob
    const content = encryptMessage(JSON.stringify(envelope), alicePrivBytes, carol.pubkeyHex)
    const event = signNostrEvent(4, content, [['p', bob.pubkeyHex]], alicePrivBytes)

    bobTransport.simulateIncomingEvent(event)

    expect(received.length).toBe(0)
  })

  it('malformed JSON in decrypted plaintext does not broadcast', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()

    const received: any[] = []
    const bobTransport = new NostrTransport((event) => received.push(event))
    bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, [])
    bobTransport.addPeer('alice', alice.pubkeyHex, [])

    // Alice encrypts non-JSON to bob
    const alicePrivBytes = privkeyHexToBytes(alice.privkeyHex)
    const content = encryptMessage('not json{', alicePrivBytes, bob.pubkeyHex)
    const event = signNostrEvent(4, content, [['p', bob.pubkeyHex]], alicePrivBytes)

    bobTransport.simulateIncomingEvent(event)

    expect(received.length).toBe(0)
  })

  it('peer.task.delegate dispatch: broadcasts peer.delegate event with correct fields', () => {
    const alice = generateNostrKeypair()
    const bob = generateNostrKeypair()

    const received: any[] = []
    const bobTransport = new NostrTransport((event) => received.push(event))
    bobTransport.setIdentity(bob.privkeyHex, bob.pubkeyHex, [])
    bobTransport.addPeer('alice', alice.pubkeyHex, [])

    const aliceTransport = new NostrTransport((event) => {})
    aliceTransport.setIdentity(alice.privkeyHex, alice.pubkeyHex, [])
    aliceTransport.addPeer('bob', bob.pubkeyHex, [])

    const envelope = {
      id: 'delegate-1', type: 'peer.task.delegate' as const,
      from: { peer: 'alice', agent: 'agent-a' },
      to: { peer: 'bob', agent: 'agent-b' },
      payload: { task: 'do the thing' },
      timestamp: new Date().toISOString(),
    }

    const event = aliceTransport.buildEvent('bob', envelope)
    bobTransport.simulateIncomingEvent(event)

    expect(received.length).toBe(1)
    const dispatched = received[0] as any
    expect(dispatched.type).toBe('peer.delegate')
    expect(dispatched.from).toBe('alice')
    expect(dispatched.to).toBe('agent-b')
    expect(dispatched.task).toBe('do the thing')
  })
})
