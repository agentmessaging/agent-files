# Agent Files Protocol (AFP)

**An open protocol for agents and people to share files across hosts.** AFP defines spaces, objects, references and five operations on top of any S3-compatible store, so a file put by one agent can be found, verified and fetched by another, on any machine, with no mounted folders.

Website: **[agentfiles.org](https://agentfiles.org)**

Status: **v0.1 draft**. Companion to [AMP](https://agentmessaging.org) (messages), [AAP](https://agentactions.org) (UI actions) and [AID](https://agentids.org) (identity); see [Related](#related).

## The problem

| Today | What goes wrong |
|-------|-----------------|
| Mounted network folders (SMB, NFS) | macOS drops the mount. The agent hangs or errors on a path that vanished |
| Attach the file to a message | Fine for one recipient. Capped at 25 MB, expires with the message, nothing to browse later |
| A web file server on one host | Humans can use it. Agents on other hosts cannot |
| Per-vendor cloud storage | Each runtime invents its own way, and nothing interoperates |

## The idea

Do not share a filesystem. Share objects by reference.

```
agent A: afp put report.pdf  ->  afp://artifacts/2026/10/report.pdf  (sha256:3b2c...)
agent A: sends an AMP message that carries the reference, not the bytes
agent B: afp get afp://artifacts/2026/10/report.pdf   ->  verified against the digest
human:   opens the same file from the agent UI, or from any S3 client
```

Nothing is mounted, so nothing can drop. The store is the truth. A message that says "a file arrived" is only a hint.

## What is in v0.1

- **Spaces** (a named place with one backend and one access scope), **objects**, **references** (`afp://space/path`) and a **manifest** (digest, size, owner, expiry, scan result).
- Five operations: `put`, `get`, `ls`, `link`, `rm`, plus `capabilities`.
- A **backend contract** with an S3 profile. [Garage](https://garagehq.deuxfleurs.fr/) is the reference backend. Any S3-compatible store works: local, a VPS, or a hosted service.
- **AMP integration**: an attachment may be `storage: "afp"`, carrying a reference instead of provider-hosted bytes.

Not in v0.1: merging concurrent edits, end-to-end encryption, quotas, cross-organization federation.

## Specification

1. [Introduction](spec/01-introduction.md)
2. [Concepts](spec/02-concepts.md)
3. [Operations](spec/03-operations.md)
4. [Backends](spec/04-backends.md)
5. [AMP integration](spec/05-amp-integration.md)
6. [Security](spec/06-security.md)

## Reference implementation

The `scripts/afp-*.sh` commands are a pure-Bash reference client (bash 3.2 and later, `curl` 7.75+, `jq`, `openssl`). They are tested against Garage. Any S3-compatible store that accepts path-style requests should work. [AI Maestro](https://github.com/23blocks-OS/ai-maestro) is the first provider and ships the skill to its agents.

| Command | What it does |
|---------|--------------|
| `afp-put.sh <file>` | Store a file, read it back, verify the digest, write the manifest, print the reference |
| `afp-get.sh <ref>` | Fetch an object and verify its SHA-256 (refuses `suspicious` and `rejected`) |
| `afp-ls.sh` | List objects from their manifests |
| `afp-link.sh <ref>` | Print a reference object with a time-limited download URL |
| `afp-rm.sh <ref>` | Delete an object and its manifest |
| `afp-capabilities.sh` | Report what a space can do |
| `afp-config.sh` | Add, list and remove spaces, set the default |

Install and first use:

```bash
./install.sh                       # copies the scripts to ~/.local/bin
afp-config.sh add shared --endpoint http://host:3900 --bucket afp --region garage \
    --access-key <key> --secret-file <file> --default
afp-put.sh report.pdf              # -> afp://shared/2026/10/report.pdf
afp-get.sh afp://shared/2026/10/report.pdf
```

The Claude Code skill is in [`skills/agent-files`](skills/agent-files/SKILL.md), with setup, space examples and troubleshooting in its [`references/setup.md`](skills/agent-files/references/setup.md). The scripts print one JSON object and use the error codes from the spec.

## Tests

```bash
tests/run-tests.sh                                   # offline: validation, error mapping, config; no store needed
AFP_TEST_KEYFILE=<file> tests/run-tests.sh --live    # adds a round trip against a real S3 store
```

The offline suite needs only bash, `curl`, `jq`, `openssl` and `shasum` or `sha256sum`, and runs in CI on Ubuntu and macOS for every push and pull request. The live suite reads `GARAGE_DEFAULT_ACCESS_KEY=` and `GARAGE_DEFAULT_SECRET_KEY=` from the key file, takes `AFP_TEST_ENDPOINT`, `AFP_TEST_BUCKET` and `AFP_TEST_REGION` from the environment, and only touches objects under `skilltest/<run-id>/`, which it deletes.

## Related

| Protocol | Website | Repository |
|----------|---------|------------|
| Agent Files Protocol (AFP): files | [agentfiles.org](https://agentfiles.org) | [agentmessaging/agent-files](https://github.com/agentmessaging/agent-files) |
| Agent Messaging Protocol (AMP): messages | [agentmessaging.org](https://agentmessaging.org) | [agentmessaging/protocol](https://github.com/agentmessaging/protocol) |
| Agent Identity (AID): identity | [agentids.org](https://agentids.org) | [agentmessaging/agent-identity](https://github.com/agentmessaging/agent-identity) |
| Agent Actions Protocol (AAP): UI actions | [agentactions.org](https://agentactions.org) | [agentmessaging/agent-actions](https://github.com/agentmessaging/agent-actions) |

## License

MIT. See [LICENSE](LICENSE).
