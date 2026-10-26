# Changelog

This changelog follows [Common Changelog](https://common-changelog.org) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-10-26

_After pulling: run `git submodule update` and `.\update_strata.ps1 -version v0.2.6`. It installs engine 0.1.50 and Strata's Python packages._

### Changed
- Move Strata to v0.2.6 ([`0cf1f61`](https://github.com/countzero/ai_strata/commit/0cf1f61))

### Added
- Choose the tier from a numbered list when `start.ps1` is run without `-tier` or with a name that does not exist ([`f40abe4`](https://github.com/countzero/ai_strata/commit/f40abe4))

## [1.4.0] - 2026-10-25

### Added
- Add `start.ps1`, which checks the tier file's paths and the port, then starts the server from `vendor\strata` ([`376233e`](https://github.com/countzero/ai_strata/commit/376233e))
- Add `experiment.ps1`, which measures a tier at 512K and 1M context and with two requests at once ([`b3ec8c5`](https://github.com/countzero/ai_strata/commit/b3ec8c5), [`d27a2bc`](https://github.com/countzero/ai_strata/commit/d27a2bc))

## [1.3.0] - 2026-10-24

_After pulling: stop the server and run `.\update_strata.ps1 -version v0.2.4.2` in PowerShell 7. It installs engine 0.1.48 and Strata's Python packages._

### Changed
- Move Strata to v0.2.4.2 ([`2b026ea`](https://github.com/countzero/ai_strata/commit/2b026ea))
- Set `--ple-io ram` in the 16 GB + 8 GB VRAM tier ([`9f99f14`](https://github.com/countzero/ai_strata/commit/9f99f14))

### Added
- Add `update_strata.ps1`, which moves Strata to a tag, a commit or HEAD and installs the engine of the matching release ([`4e6e8e6`](https://github.com/countzero/ai_strata/commit/4e6e8e6))
- Add `benchmark.ps1`, which measures the running server and prints the numbers for README -> Tiers ([`4e6e8e6`](https://github.com/countzero/ai_strata/commit/4e6e8e6))

## [1.2.0] - 2026-10-21

_After pulling: run `git submodule update`, then `.\START-HERE.bat --update --yes --no-start` in `vendor\strata`, and install engine 0.1.47 by hand as in README -> Update Strata, step 5. Clients on other devices no longer need an API key._

### Changed
- Move Strata to v0.2.2 ([`1a19ef5`](https://github.com/countzero/ai_strata/commit/1a19ef5))
- Serve both tiers without an API key ([`1d79902`](https://github.com/countzero/ai_strata/commit/1d79902))
- Point the 24 GB VRAM tier at the model data on `E:` ([`1e7e54a`](https://github.com/countzero/ai_strata/commit/1e7e54a))

## [1.1.0] - 2026-10-20

_After pulling: run `git submodule update`, then `.\START-HERE.bat --update --yes --no-start` in `vendor\strata`, and install engine 0.1.46 by hand as in README -> Update Strata, step 5. Clients on other devices now send `Authorization: Bearer insecure`._

### Changed
- Move Strata to v0.2.1.3 ([`b535f5e`](https://github.com/countzero/ai_strata/commit/b535f5e), [`64de764`](https://github.com/countzero/ai_strata/commit/64de764), [`d9bba38`](https://github.com/countzero/ai_strata/commit/d9bba38))
- Require the API key `insecure` from clients on the network ([`64de764`](https://github.com/countzero/ai_strata/commit/64de764))

### Added
- Add the 16 GB + 8 GB VRAM / 128 GB RAM tier for Qwen3.8-Flash-Next UD-IQ4_XS ([`4dd8fc3`](https://github.com/countzero/ai_strata/commit/4dd8fc3), [`afd221d`](https://github.com/countzero/ai_strata/commit/afd221d))

### Fixed
- Fetch Strata's tags with `--force` in the update steps ([`10e97bd`](https://github.com/countzero/ai_strata/commit/10e97bd))

## [1.0.0] - 2026-10-19

_Initial release._

### Added
- Add the 24 GB VRAM / 192 GB RAM tier for Qwen3.8-Flash-Next UD-IQ4_XS ([`532eb97`](https://github.com/countzero/ai_strata/commit/532eb97))
- Pin Strata v0.1.44.1 as the submodule `vendor/strata` ([`83cf904`](https://github.com/countzero/ai_strata/commit/83cf904))
- Add the agent rules and the plan-review and release skills ([`3b12a27`](https://github.com/countzero/ai_strata/commit/3b12a27), [`ed51fa6`](https://github.com/countzero/ai_strata/commit/ed51fa6))

[1.5.0]: https://github.com/countzero/ai_strata/releases/tag/v1.5.0
[1.4.0]: https://github.com/countzero/ai_strata/releases/tag/v1.4.0
[1.3.0]: https://github.com/countzero/ai_strata/releases/tag/v1.3.0
[1.2.0]: https://github.com/countzero/ai_strata/releases/tag/v1.2.0
[1.1.0]: https://github.com/countzero/ai_strata/releases/tag/v1.1.0
[1.0.0]: https://github.com/countzero/ai_strata/releases/tag/v1.0.0
