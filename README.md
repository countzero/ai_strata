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
only resolve when the server starts from `vendor\strata`. A tier file sets `"host": "0.0.0.0"`, so
every device on the network can use the server. A tier file also sets `"api_key": "insecure"`: a
fixed value, not a secret. Clients send it as `Authorization: Bearer insecure` or
`x-api-key: insecure`.

## Tiers

Medians of `tools\strata_bench.py` (default suite, 3 runs each) against a running server.

| Tier file                                                      | Hardware                                                                     | Strata    | Chat decode | 16K prompt   | Agent decode | Agent cache hit |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------- | --------- | ----------- | ------------ | ------------ | --------------- |
| `qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM`     | RTX PRO 5000 Blackwell Laptop 24 GB, 192 GB RAM, 24 cores                    | v0.2.2    | 73.5 tok/s  | 2701 tok/s   | 57.0 tok/s   | 69.6 %          |
| `qwen3.8-flash-next.unsloth-ud-iq4_xs.16GB_8GB_VRAM_128GB_RAM` | RTX 4070 Ti SUPER 16 GB + RTX 2060 SUPER 8 GB (vision), 128 GB RAM, 16 cores | v0.2.1    | 52.5 tok/s  | 2930 tok/s   | 55.3 tok/s   | 69.4 %          |

The 24 GB row was measured on a free card. v0.2.1.3 in the same session gave 68.7 tok/s chat
decode, 2627 tok/s 16K prompt and 56.8 tok/s agent decode.

## New machine

1. `git clone --recurse-submodules <url of this repository> <repo>`
2. In `vendor\strata`:
   `.\START-HERE.bat --yes --no-start --family unsloth --model <quant> --context <tokens> --gpu <n> --port 8083 --gguf-dir <GGUF folder> --data-dir <data folder>`.
   The data folder holds `packs\` and `mtp\` in the tier file's paths. Name the model: with `--no-start`
   setup takes its own recommended answers, which can be another model and a new download. Add
   `--move-data` to move the files of an earlier Strata install into the data folder; without it they stay.
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
4. In `vendor\strata`: `.\START-HERE.bat --update --yes --no-start`. This updates the Python
   packages and setup's own `strata-*.json`, not the engine: setup replaces only one older than
   its minimum, and then compiles it on Windows, which fails.
5. Install the engine by hand, in `vendor\strata`. A point release (v0.2.1.3) has no release page;
   its engine is on the base release's (v0.2.1):
   `gh release download <release> -R Niko1221/Strata -p "strata-engine-*-windows-x86_64-cuda-cuda13.tar.gz" -p SHA256SUMS.txt -D <temp folder>`.
   Check the package's SHA-256 against `SHA256SUMS.txt`, move the files of `engine\` into
   `engine\.previous\` (emptied first), unpack the package into `engine\`, and check
   `engine\strata.exe --version`.
6. Compare setup's config with the tier file:
   `git diff --no-index presets\<tier>.json vendor\strata\strata-unsloth-ud-iq4_xs.json`.
   Ignore the path differences (relative here, absolute there). Carry over new or changed flags,
   and `lib_dirs`: a renamed CUDA folder there fails silently, and the engine then stops
   without naming the missing DLL.
7. Start, check that the model loads, and run
   `.\.venv\Scripts\python.exe tools\strata_bench.py --url http://127.0.0.1:8083 --api-key insecure --out $env:TEMP\strata-bench`
   in `vendor\strata`; without `--out` the results land inside the submodule. VRAM taken by other
   programs lowers the numbers: when they differ from the old row, run the old version in the same
   session before calling it a regression. Put the numbers in *Tiers*.
8. `git add vendor/strata presets README.md` and commit as "Update Strata to <tag>".

Rollback: `git checkout <last commit> -- vendor/strata presets`, `git submodule update`, then copy
`engine\.previous\` back into `engine\`.
