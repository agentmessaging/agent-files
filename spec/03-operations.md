# 03 - Operations

**Status:** Draft v0.1

An implementation exposes these operations. Each takes arguments and returns a JSON object. A failure returns `{ "ok": false, "error": { "code": "...", "message": "..." } }`. A command-line implementation exits non-zero on failure. All output is JSON on stdout.

## put

Store a file.

| Argument | Required | Description |
|----------|----------|-------------|
| `file` | Yes | Local path to read |
| `space` | No | Target space. Default is the host's default space |
| `path` | No | Object path. Default is `<yyyy>/<mm>/<filename>` |
| `ttl` | No | Lifetime, for example `7d`. Sets `expires` |
| `content_type` | No | Otherwise detected |

Steps: compute the SHA-256, upload, read back the digest from the store, write the manifest. Result:

```json
{ "ok": true, "ref": "afp://artifacts/2026/10/report.pdf", "digest": "sha256:...", "size": 1827341, "stored": true }
```

`stored: true` MUST be returned only after the digest was verified in the store. If the backend cannot confirm, the result is an error. An implementation MUST NOT fall back silently to a local copy.

An existing path is not overwritten unless `force` is set. Without it the error code is `exists`.

## get

Fetch a file.

| Argument | Required | Description |
|----------|----------|-------------|
| `ref` | Yes | The reference, or the full reference object |
| `digest` | No | Expected digest. Defaults to the one in the reference object, or the manifest |
| `dest` | No | Directory or file path. Default is a per-agent download folder |

The implementation downloads, computes the SHA-256 and compares. On mismatch it deletes the partial file and returns code `digest_mismatch`. A `suspicious` or `rejected` scan result blocks the fetch and returns `scan_blocked`. A person decides what to do with a `suspicious` file, as in AMP.

If the reference object has a `url` and the host has no credentials for the space, `get` MAY use the URL. Whether it uses the URL or its own credentials, the digest check applies.

## ls

List objects.

| Argument | Description |
|----------|-------------|
| `space` | Space to list |
| `prefix` | Optional path prefix |
| `limit` | Default 100 |

Result: an array of `{ ref, size, owner, created, expires }` read from manifests, plus `truncated: true` when more objects matched than `limit` returned.

## link

Mint a time-limited download link. Requires capability `link`.

| Argument | Description |
|----------|-------------|
| `ref` | The reference |
| `ttl` | Link lifetime. Default 1 hour, maximum 7 days |

Result: the full reference object including `url`. A backend without `link` returns code `unsupported`. The object's manifest is required, because the reference object carries its digest; without one the code is `not_found`.

## rm

Delete an object and its manifest. By default only the `owner` or a host administrator may delete. Returns `{ "ok": true }` when the store confirms the deletion, otherwise an error.

## capabilities

Return the capability list for a space, so an agent does not promise a link on a backend that cannot make one.

```json
{ "ok": true, "space": "artifacts", "backend": "s3", "capabilities": ["link", "expire", "ui"] }
```

## Error codes

`exists`, `not_found`, `digest_mismatch`, `scan_blocked`, `unsupported`, `unreachable`, `invalid_path`, `invalid_space`, `forbidden`, `too_large`, `usage`.

`usage` means the caller passed missing or malformed arguments. A `get` of a reference that has neither a digest nor a manifest cannot be verified and returns `digest_mismatch`.

`unreachable` means the backend could not be contacted. It is returned as an error, never hidden.
