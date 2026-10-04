# Agent Files Protocol (AFP)

**An open protocol for agents and people to share files across hosts.** AFP defines spaces, objects, references and five operations on top of any S3-compatible store, so a file put by one agent can be found, verified and fetched by another, on any machine, with no mounted folders.

Status: **v0.1 draft**. Companion to [AMP](https://github.com/agentmessaging/protocol) (messages), [AAP](https://github.com/agentmessaging/agent-actions) (UI actions) and [AID](https://github.com/agentmessaging/agent-identity) (identity).

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

[AI Maestro](https://github.com/23blocks-OS/ai-maestro) is the first provider. The `agent-files` skill and scripts follow in `skills/` once the spec settles.

## License

MIT. See [LICENSE](LICENSE).
