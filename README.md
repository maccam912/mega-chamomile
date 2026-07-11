# Mega Chamomile

A multiplayer hide-and-seek game where hiders paint their own bodies to blend
into the world, inspired by MECCHA CHAMELEON. Built with Godot 4.7
(Compatibility renderer).

- **Hiders** start pure white. Eyedrop colors from the world (RMB), paint
  yourself (LMB), find a spot, hold still. Bonus points for staying inside a
  seeker's line of sight without being noticed.
- **Seekers** wait blindfolded during the paint phase, then hunt with limited
  ammo before the timer runs out.

## Run

Open in Godot 4.7 and press F5. For a local 2-player test, run two instances:
one hosts, one joins `127.0.0.1`.

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
