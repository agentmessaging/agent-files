# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

The **Agent Files Protocol (AFP)** specification (`spec/`) and its pure-Bash reference client. It is distributed three ways:

1. **Standalone CLI.** `install.sh` copies `scripts/afp-*.sh` to `~/.local/bin`.
2. **Claude Code plugin and skill.** `.claude-plugin/plugin.json` and `skills/agent-files/SKILL.md`. The AI Maestro plugin builder pulls `skills/agent-files` and `scripts/*.sh` from this repo at `ref: main`, so fix scripts here and merge, or the next build reverts the fix.
3. **Remote install.** `install.sh` falls back to `raw.githubusercontent.com/agentmessaging/agent-files/main/scripts/` when piped from curl.

## Commands

```bash
tests/run-tests.sh                                   # offline: validation, error mapping, config
AFP_TEST_KEYFILE=<file> tests/run-tests.sh --live    # round trip against a real S3 store
./install.sh /tmp/afp-bin                            # install somewhere harmless to try it
```

## Rules for the scripts

- Bash 3.2 compatible (macOS): no associative arrays, no `${var,,}`, no `mapfile`. Run them with `/bin/bash`.
- One JSON object on stdout, `{"ok":false,"error":{"code","message"}}` and exit 1 on failure, codes from `spec/03-operations.md`. No `set -e`: every failure path prints its JSON first.
- Validate space names and paths (`afp_require_space_name`, `afp_require_path`) before any request. Build commands with argument arrays, never shell strings. Never print secrets or put them on a command line (`afp_curl` passes them through a config file on a pipe).
- Use `od -An -v` (not plain `od`), which otherwise collapses repeated lines and corrupts binary-to-hex conversions.
- Live tests use object paths under `skilltest/<run-id>/` only and delete what they create.
- Spec changes that touch AMP go to `agentmessaging/protocol`, not here.
