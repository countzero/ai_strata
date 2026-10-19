# ai_strata

My [Strata](https://github.com/Niko1221/Strata) setup, shared between machines: Strata pinned as a
submodule, plus one run config per hardware tier. Model files live outside the repository; each tier
file names their paths.

## Usage

Start the server:

```
pwsh -NoExit -wd <repo>\vendor\strata -c ".\.venv\Scripts\python.exe serve\server.py --engine strata --config ..\..\presets\<tier>.json --port 8083"
```

`<repo>` is where you cloned this repository. Paths inside Strata in a tier file are relative and
only resolve when the server starts from `vendor\strata`. A tier file sets `"host": "0.0.0.0"` and
no API key, so every device on the network can use the server.

## Tiers

Medians of `tools\strata_bench.py` (default suite, 3 runs each) against a running server.

| Tier file                                                  | Hardware                                                   | Strata    | Chat decode | 16K prompt   | Agent decode | Agent cache hit |
| ---------------------------------------------------------- | ---------------------------------------------------------- | --------- | ----------- | ------------ | ------------ | --------------- |
| `qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM` | RTX PRO 5000 Blackwell Laptop 24 GB, 192 GB RAM, 24 cores  | v0.1.45   | 70.5 tok/s  | 2617 tok/s   | 69.1 tok/s   | 68.7 %          |

## New machine

1. `git clone --recurse-submodules <url of this repository> <repo>`
2. In `vendor\strata`: `.\START-HERE.bat --yes --no-start --data-dir <data folder>`, the folder that holds
   `packs\` and `mtp\` in the tier file's paths.
3. Copy the nearest tier file to a new tier name and tune it.

## Take a release

1. Stop the server, then `git pull` and `git submodule update --init`.
2. Read the new versions' notices in `CHANGELOG.md` and do what they say, such as
   `.\START-HERE.bat --update --yes --no-start` in `vendor\strata`.
3. Start the server.

## Update Strata

Never run Strata's `UPDATE.bat`: it pulls `main` and leaves the pinned version.

1. Stop the server.
2. Pick the version: `git -C vendor\strata fetch --tags --force`, then
   `git -C vendor\strata tag --sort=-v:refname | Select-Object -First 5`. Read its release notes.
   Without `--force` the fetch stops at upstream's rewritten older tags and shows no new one.
3. `git -C vendor\strata checkout <tag>`
4. In `vendor\strata`: `.\START-HERE.bat --update --yes --no-start`. This updates the engine,
   the Python packages and setup's own `strata-*.json`.
5. Compare setup's config with the tier file:
   `git diff --no-index presets\<tier>.json vendor\strata\strata-unsloth-ud-iq4_xs.json`.
   Ignore the path differences (relative here, absolute there). Carry over new or changed flags,
   and `lib_dirs`: a renamed CUDA folder there fails silently, and the engine then stops
   without naming the missing DLL.
6. Start, check that the model loads, and run
   `.\.venv\Scripts\python.exe tools\strata_bench.py --url http://127.0.0.1:8083 --out $env:TEMP\strata-bench`
   in `vendor\strata`; without `--out` the results land inside the submodule. Put the numbers in *Tiers*.
7. `git add vendor/strata presets README.md` and commit as "Update Strata to <tag>".

Rollback: `git checkout <last commit> -- vendor/strata presets`, `git submodule update`, then step 4 again.
