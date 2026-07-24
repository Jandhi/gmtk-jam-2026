# GMTK Jam 2026

Godot 4.7 game jam project targeting a **web build on itch.io** (Compatibility renderer — keep it; Forward+ breaks web export).

## Running things

- Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot`
- Run the game headless-checked: `<godot> --path . --quit-after 2 --headless` (verifies autoloads + main scene load)
- Reimport assets after adding files outside the editor: `<godot> --headless --import --path .`
- Run sim tests: `<godot> --headless --path . --script res://scripts/tests/sim_test.gd` (also run by CI)
- Screenshot the battle scene: `<godot> --path . -- --screenshot out.png`
- Web build + zip for itch.io: `./build_web.sh` (output: `build/web.zip`)
- CI: pushing to `main` runs `.github/workflows/deploy.yml` — exports web and butler-pushes to itch.io (`jandhi/gmtk-jam-2026`, html5 channel). Needs `BUTLER_API_KEY` repo secret.

## Architecture: sim/view split

Combat is a pure, deterministic simulation (`scripts/sim/`, plain RefCounted
classes — no Nodes, no scene tree). `Sim.tick(orders)` returns an ordered list
of `SimEvent`s; the battle scene (`scenes/battle/`) only replays those events.
**Nothing outside `scripts/sim/` mutates sim state; nothing inside it
references a Node.** All randomness goes through the sim's seeded RNG.
Creature stats live in `data/creatures.csv` (edit the spreadsheet, not code;
sprite is looked up by name from `assets/art/Monsters/<Name>.PNG`).
Design details and rules interpretations: `docs/design.md`.

## Structure

- `scripts/sim/` — simulation core (see above)
- `scenes/battle/` — battle view, input, event playback
- `scenes/` — one folder per feature as the game grows (e.g. `scenes/player/`)
- `scripts/autoload/` — singletons registered in project.godot:
  - `AudioManager` — `play_sfx(stream)`, `play_music(stream)` (buses: Music, SFX)
  - `SceneChanger` — `change_to("res://scenes/x.tscn")` with fade
- `assets/art/`, `assets/audio/music/`, `assets/audio/sfx/`, `assets/fonts/`

## Conventions

- GDScript: tabs, snake_case file/function names, PascalCase node/class names, typed where easy (`:=`).
- Prefer scene composition over deep inheritance; keep scripts on scene roots.
- Web constraints: no threads (export preset is non-threaded), audio must start after a user input, avoid `OS.execute`/file dialogs.
- Jam mindset: simple > clever, cut scope early, keep the game playable at all times.
