# Changelog

This changelog follows [Common Changelog](https://common-changelog.org) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.1.0]: https://github.com/countzero/ai_strata/releases/tag/v1.1.0
[1.0.0]: https://github.com/countzero/ai_strata/releases/tag/v1.0.0
