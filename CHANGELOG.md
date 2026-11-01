# Changelog

## [0.1.0] - 2026-11-01

First release of the Agent Files Protocol (AFP) and its reference client. Website: https://agentfiles.org.

### Specification (Draft v0.1)

- `spec/01-introduction.md` to `spec/06-security.md`: spaces, objects, references (`afp://space/path`) and the manifest (digest, size, owner, expiry, scan result); the operations `put`, `get`, `ls`, `link`, `rm` and `capabilities` with their error codes; the backend contract and its S3 profile, with Garage as the reference backend; AMP integration (`storage: "afp"` attachments and the `attachments:afp` capability); security.
- Folded in findings from the reference client: the `usage` error code, the `truncated` flag on listings, and that `link` needs a manifest.

### Reference client

- `scripts/afp-put.sh`, `afp-get.sh`, `afp-ls.sh`, `afp-link.sh`, `afp-rm.sh`, `afp-capabilities.sh` and `afp-config.sh`, sharing `afp-helper.sh`. Pure Bash (3.2 and later) with `curl` 7.75+ (`--aws-sigv4`), `jq` and `openssl`. Each prints one JSON object; failures are `{"ok":false,"error":{...}}` with a non-zero exit. `get` verifies the SHA-256 and refuses `suspicious` and `rejected` scan results; `link` presigns a time-limited URL with SigV4.
- `install.sh` copies the scripts to `~/.local/bin`, or downloads them from `main` when piped from curl.

### Claude Code plugin

- `.claude-plugin/plugin.json` and the `skills/agent-files` skill, with setup, space examples and troubleshooting in `references/setup.md`.

### Tests

- `tests/run-tests.sh`: an offline suite (validation, error mapping, configuration, helper functions) and a `--live` round trip against a real S3 store.
- CI (`.github/workflows/test.yml`) runs the offline suite on Ubuntu and macOS for every push and pull request to `main`.
- The config file mode check now reads the mode with GNU `stat -c` first, so it passes on Linux as well as macOS.
