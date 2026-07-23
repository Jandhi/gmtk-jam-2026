# GMTK Jam 2026

Godot 4.7 game jam project targeting a **web build on itch.io** (Compatibility renderer — keep it; Forward+ breaks web export).

## Running things

- Godot binary: `/Applications/Godot.app/Contents/MacOS/Godot`
- Run the game headless-checked: `<godot> --path . --quit-after 2 --headless` (verifies autoloads + main scene load)
- Reimport assets after adding files outside the editor: `<godot> --headless --import --path .`
- Web build + zip for itch.io: `./build_web.sh` (output: `build/web.zip`)
- CI: pushing to `main` runs `.github/workflows/deploy.yml` — exports web and butler-pushes to itch.io (`jandhi/gmtk-jam-2026`, html5 channel). Needs `BUTLER_API_KEY` repo secret.

## Structure

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
