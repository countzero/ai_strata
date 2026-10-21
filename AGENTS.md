# AGENTS.md

Shares one Strata setup between machines: Strata as the submodule `vendor/strata`, pinned to a
release tag, and one run config per hardware tier in `presets/`. Nothing here is built or tested.
`README.md` -> *Usage* holds the start command, the other sections the steps for a new machine and
the update procedure.

## Tier files

- A tier file is a Strata run config for `serve/server.py --config`. Name it
  `<model>.<quant>.<VRAM>_VRAM_<RAM>_RAM.json`, after the hardware, never after a machine.
- Paths inside Strata (`exe`, `cwd`, `lib_dirs`, `log`, `--expert-profile`, the vision `exe`)
  stay relative: the server starts in `vendor/strata`. Model paths stay absolute.
- `"host": "0.0.0.0"` without an `api_key` is deliberate: other devices use the server, and
  Strata only warns about the missing key. Do not narrow the host, and do not add a key.
- `port` and `gpus_asked` stay out: the server reads neither. It ignores unknown keys silently, so
  check a new key against `vendor/strata/serve/server.py` before adding it.
- Change a value only with a `tools/strata_bench.py` run before and after, on the same Strata
  version. The numbers go into `README.md` -> *Tiers* and into the commit message.

## Strata

- `vendor/strata` is upstream's code: never edit it here. Its own `AGENTS.md` and `docs/`
  explain the engine and every setting.
- Never run Strata's `UPDATE.bat` or `update.sh`: they pull `main` and leave the pinned tag.
  Updates follow `README.md` -> *Update Strata*.
- The running server is the user's, and other clients depend on it: never stop or restart it
  without asking.

## Privacy

No machine names, local user names, IP addresses or paths to a home folder in any file or commit
message. Describe hardware by its parts (GPU, VRAM, RAM, cores).

## Version Control

Semantic Versioning. `CHANGELOG.md` follows Common Changelog and is written only as a step of a
release (`.opencode/skills/release/SKILL.md`).

Commit only when asked, and push only when asked; "commit" does not imply "push". The subject is
one imperative line. The body carries the measurement, the reason, and what was left undone. No
`Co-Authored-By` trailer.

## Output Formatting

Pad every cell of a markdown table so that all cells of a column share one width.
