# Iroh transport feasibility

Research snapshot: 2026-07-16. This is an engineering recommendation, not an
implemented transport.

## Verdict

Iroh is a good architectural fit for removing port-forwarding, and the existing
MIT-licensed [`tipragot/godot-iroh`](https://github.com/tipragot/godot-iroh)
addon already implements Godot's `MultiplayerPeerExtension`. It exposes
`IrohServer.start()`, a shareable connection string, and
`IrohClient.connect()`, after which the normal high-level RPC API is available.
This avoids building the transport adapter from scratch and materially reduces
the likely migration to a small integration spike plus production hardening.

Do not tunnel ENet through iroh: that would stack ENet reliability on QUIC,
complicate peer addressing, and retain two transport state machines. Replace
`ENetMultiplayerPeer` with Godot Iroh behind a transport selection boundary so
ENet remains available during evaluation.

## Why it is promising

- Iroh 1.0.x establishes authenticated, encrypted QUIC connections by endpoint
  identity. It attempts direct paths automatically and falls back to relays
  when hole punching fails.
- Its QUIC connection exposes both streams and datagrams. Those are the raw
  ingredients needed to represent Godot's reliable and unreliable packet
  modes.
- Godot explicitly supports custom multiplayer transports through
  `MultiplayerPeerExtension`, and the godot-rust bindings expose that class.
- Godot Iroh already implements this extension point, including host-assigned
  integer peer IDs, transfer modes and channels, server/broadcast targets, and
  host relay support.
- Paint-n-Seek already uses a listen-server topology. Guests only need an iroh
  connection to the host; the authoritative rules do not need to become a
  peer-to-peer consensus system.

## What still needs validation

The addon covers the adapter work, but it should be treated as source we may
need to maintain rather than an opaque binary dependency:

1. The latest packaged release is `0.1.5` from May 2025, while the current main
   branch has continued changing without a new release. Build from a pinned
   commit rather than silently depending on the Asset Library binary.
2. Main currently pins iroh `0.96.0`; current iroh is 1.0.x, and an iroh 1.0
   update exists only as a large draft pull request. The 0.96 release also had
   NAT path-recovery regressions later addressed by iroh, so production should
   use a reviewed minimal 1.0.x update.
3. The addon reports roughly 1,024 bytes as the maximum unreliable packet size.
   Paint-n-Seek's `unreliable_ordered` ragdoll pose snapshot may exceed that and
   must be measured. If it does, compress/split the pose rather than silently
   losing it.
4. Audit target-peer behavior. The current negative-target branch appears to
   compare a positive connected peer ID with the negative selector instead of
   its absolute value, which would fail to exclude the requested peer.
5. Compile and package native libraries for every supported desktop target and
   cover reconnects, relay-to-direct path changes, packet loss, late joins, and
   host shutdown in integration tests. Upstream lists Windows, macOS, Linux,
   and Android support, but not Web.

## Product and operations changes

- Replace the manual IP field with a host ticket/room-code field. LAN discovery
  can advertise the same ticket, so local one-click joining remains possible.
- Persist the host's endpoint secret if stable host identity is desirable;
  otherwise generate an ephemeral identity per hosted session.
- Add application-level admission checks. Iroh authenticates endpoint IDs, but
  the game still decides who may enter a room and whether a ticket is current.
- Measure relayed bandwidth during ragdoll movement and painting. Iroh's public
  relays are intended for development and hobby use, are rate-limited, and have
  no SLA. A production release should budget for managed relays or operate at
  least two self-hosted relays.

## Suggested spike

Keep ENet as the default while testing one narrow vertical slice:

1. Vendor Godot Iroh from a pinned upstream commit and add an ENet/Iroh
   transport switch in `Net.gd`.
2. Replace the IP field with a connection-string field in iroh mode. Put the
   same connection string in the existing LAN advertisement.
3. Run the existing lobby registry and reliable RPCs unchanged with one host
   and one guest on separate internet connections.
4. Measure serialized movement and ragdoll RPC sizes, then validate
   `unreliable_ordered` behavior under loss and relay fallback.
5. Patch the negative-target issue if confirmed and test server broadcasts with
   three clients, including a late join and a disconnect.
6. Build pinned macOS, Windows, and Linux libraries before changing the default
   transport. Separately port the addon to a reviewed iroh 1.0.x baseline.

The go/no-go gate is a three-client internet test in which a player behind a
restrictive NAT can join via relay fallback, movement remains smooth, and a
relay-to-direct path transition does not disconnect Godot's multiplayer API.

## Primary references

- Iroh overview and repository: <https://github.com/n0-computer/iroh>
- Godot Iroh addon: <https://github.com/tipragot/godot-iroh>
- Godot Iroh Asset Library entry:
  <https://godotengine.org/asset-library/asset/3948>
- Iroh NAT traversal: <https://docs.iroh.computer/concepts/nat-traversal>
- Iroh QUIC streams/datagrams: <https://docs.iroh.computer/protocols/using-quic>
- Iroh public-relay policy: <https://docs.iroh.computer/iroh-services/relays/public>
- Iroh dedicated relay setup: <https://docs.iroh.computer/add-a-relay>
- Godot custom multiplayer peer API:
  <https://docs.godotengine.org/en/stable/classes/class_multiplayerpeerextension.html>
- Rust binding for the same extension point:
  <https://godot-rust.github.io/docs/gdext/master/godot/classes/struct.MultiplayerPeerExtension.html>
