# Iroh transport feasibility

Research snapshot: 2026-07-16. Integration baseline implemented the same day;
production hardening and external-network QA remain.

## Implementation status

Iroh is now a second transport rather than an ENet replacement. The main menu
offers **Host on LAN** / manual IP through ENet and separate **Host by Code** /
**Join Code** actions through godot-iroh. Hosts can copy the self-contained
43-character endpoint code from the lobby. Both transports feed the same Godot
high-level multiplayer API, registry, authoritative match flow, and RPCs.

The project vendors godot-iroh v0.1.5 desktop binaries with version, upstream
commit, archive checksum, and MIT license recorded under `addons/godot_iroh/`.
A local two-process iroh run completed lobby registration and a full fast match.
The three avatar ragdoll snapshots now use compact float32 position/quaternion
arrays (380–548 serialized bytes in regression tests), leaving headroom below
the addon's 1,024-byte unreliable-packet ceiling. LAN discovery remains fully
independent and has its own repeated-refresh integration smoke.

## Verdict

Iroh is a good architectural fit for removing port-forwarding, and the existing
MIT-licensed [`tipragot/godot-iroh`](https://github.com/tipragot/godot-iroh)
addon already implements Godot's `MultiplayerPeerExtension`. It exposes
`IrohServer.start()`, a shareable connection string, and
`IrohClient.connect()`, after which the normal high-level RPC API is available.
This avoids building the transport adapter from scratch and materially reduces
the likely migration to a small integration spike plus production hardening.

The implementation does not tunnel ENet through iroh, which would stack ENet
reliability on QUIC, complicate peer addressing, and retain two transport state
machines. A transport-selection boundary installs either
`ENetMultiplayerPeer` or Godot Iroh for the session, so ENet remains available.

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

1. The pinned packaged release is `0.1.5` from May 2025, while the current main
   branch has continued changing without a new release. Its exact source commit
   and archive checksum are recorded, but a reviewed iroh 1.x upgrade remains.
2. Main currently pins iroh `0.96.0`; current iroh is 1.0.x, and an iroh 1.0
   update exists only as a large draft pull request. The 0.96 release also had
   NAT path-recovery regressions later addressed by iroh, so production should
   use a reviewed minimal 1.0.x update.
3. The addon reports roughly 1,024 bytes as the maximum unreliable packet size.
   Compact ragdoll snapshots are now regression-tested below 550 bytes before
   RPC framing; packet-loss and relay-path stress still need testing.
4. Audit target-peer behavior. The current negative-target branch appears to
   compare a positive connected peer ID with the negative selector instead of
   its absolute value, which would fail to exclude the requested peer.
5. Desktop libraries are packaged for Windows x86_64, Linux x86_64, and
   universal macOS. Hardware-test those exports and cover reconnects,
   relay-to-direct path changes, packet loss, three clients, late joins, and
   host shutdown. Web remains unsupported upstream.

## Product and operations changes

- Keep the manual IP and LAN list for ENet, with the room-code field alongside
  them as a second path. This preserves offline/local play when iroh is absent.
- Persist the host's endpoint secret if stable host identity is desirable;
  otherwise generate an ephemeral identity per hosted session.
- Add application-level admission checks. Iroh authenticates endpoint IDs, but
  the game still decides who may enter a room and whether a ticket is current.
- Measure relayed bandwidth during ragdoll movement and painting. Iroh's public
  relays are intended for development and hobby use, are rate-limited, and have
  no SLA. A production release should budget for managed relays or operate at
  least two self-hosted relays.

## Completed spike and go/no-go gate

The narrow local vertical slice is complete while ENet remains the default:

1. Done: vendor pinned desktop runtimes and add the ENet/Iroh boundary.
2. Done: add code hosting/joining alongside the retained IP and LAN UI.
3. Done locally: run the existing lobby, match, and RPC flow with a host and
   guest. Separate-internet-connection testing remains.
4. Partly done: serialized ragdoll RPC payloads are budgeted; loss and relay
   fallback validation remains.
5. Patch the negative-target issue if confirmed and test server broadcasts with
   three clients, including a late join and a disconnect.
6. Packaged: pinned macOS, Windows, and Linux libraries are included. Keep ENet
   as the default and separately port to a reviewed iroh 1.x baseline.

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
