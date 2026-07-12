# Mega Chamomile

A multiplayer hide-and-seek game where hiders paint their own bodies to blend
into the world, inspired by MECCHA CHAMELEON. Built with Godot 4.7
(Compatibility renderer).

- **Hiders** start pure white. Eyedrop colors from the world (RMB), paint
  yourself (LMB), and use the Ragdoll button or R key to settle into a natural
  lying pose. Ragdoll enables a fly camera; entering paint mode returns to a
  center-of-mass orbit around the body. Running and turning momentum carries
  into every released body segment. Bonus points for staying inside a seeker's
  line of sight without being noticed.
- Pick a **Human, Cat, or Dog** in the lobby. The choice is replicated, and all
  three bodies support the same painting, movement, shooting, and ragdoll loop.
- **Seekers** wait blindfolded during the paint phase, then hunt with limited
  ammo before the timer runs out.

## Run

Open in Godot 4.7 and press F5. For a local 2-player test, run two instances:
one hosts, one joins `127.0.0.1`.

For family computers, download the launcher for that operating system from the
latest GitHub Release once and double-click it. The launcher checks for the
latest release, downloads and verifies the matching game package when needed,
then starts the game. It keeps the previous working version available when an
update fails or the computer is offline. See `launcher/README.md` for platform
paths and implementation details.

CLI helpers (after `--`): `--name X`, `--host`, `--join <ip>`,
`--autostart <n>` (host starts when n players present), `--fast-phases`,
`--quit-after <s>`.

Headless E2E smoke:

```sh
godot --headless -- --host --name Host --autostart 2 --fast-phases --quit-after 30 &
godot --headless -- --join 127.0.0.1 --name Guest --quit-after 30
```

## Tests

```sh
godot --headless -s tests/run_tests.gd
```

## Docs

- `docs/DESIGN.md` — mechanics, scoring, architecture decisions
- `docs/PROGRESS.md` — current build state, pick-up-here notes

## Credits

Art & audio from [Kenney](https://kenney.nl) (CC0). Thanks Kenney!

"[The Hallwyl Museum 1st Floor Combined](https://sketchfab.com/3d-models/the-hallwyl-museum-1st-floor-combined-f74eefe9f1cd4a2795a689451e723ee9)"
by [Thomas Flynn](https://sketchfab.com/nebulousflynn), based on original museum
models by [Erik Lernestål](https://www.eriklernestal.com/), is used under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). It was converted to
a Godot game map and supplied with generated concave collision meshes.
