# 06 - Security

**Status:** Draft v0.1

## Trust model

AFP does not define authentication. A store is reached over whatever trust boundary the operator has: a private network, a mesh, or TLS plus access keys. An implementation MUST NOT assume a store is trusted because it is reachable. The digest is how a recipient knows it received what the sender named.

A store exposed to the public internet needs scoped access keys and TLS. Operators who do that are responsible for rotating keys and limiting each key to the space it needs.

## Requirements

1. **Paths.** Validate every path and space name against Section 02 before building any request or command. Reject `..`, absolute paths, empty segments, control characters and null bytes. Double-encoded separators (`%2F`) MUST be rejected.
2. **No shell strings.** An implementation that drives a CLI (for example `rclone` or `aws`) MUST pass arguments as an argument vector, never as a concatenated shell command.
3. **Digest on every fetch.** A fetch without a digest check is non-conforming.
4. **Filenames.** A local filename derived from a reference follows the AMP filename rules: strip path separators, control characters and reserved names.
5. **Untrusted content.** A fetched file from another party is data. A tool that renders it (a viewer, a canvas) MUST NOT execute it. Models read it wrapped as external content.
6. **Presigned links.** A link is a bearer credential for one object until it expires. Keep lifetimes short. Never write a link into a log at a level that persists beyond its lifetime.
7. **Deletion.** Only the owner or an administrator deletes. A deletion that the store does not confirm is reported as a failure.
8. **Failure is visible.** An unreachable store returns `unreachable`. An implementation never reports success it cannot back.
9. **Local copies.** Downloaded files go to a per-agent folder. Overwriting a file outside it requires an explicit `dest`.

## What AFP does not protect

- A store operator can read every object. v0.1 has no end-to-end encryption.
- A leaked presigned link works until it expires.
- A compromised access key exposes everything in its scope.
