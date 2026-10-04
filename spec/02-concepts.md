# 02 - Concepts

**Status:** Draft v0.1

## Space

A **space** is a named place with one backend and one access scope, for example `shared` or `artifacts`. A host configures its spaces. A space name matches `^[a-z0-9][a-z0-9-]{0,62}$`.

A space has:

| Field | Description |
|-------|-------------|
| `name` | The name above, unique on a host |
| `backend` | The backend profile in use (v0.1 defines `s3`) |
| `endpoint` | Where the backend is reached (a URL) |
| `capabilities` | What the backend can do (see below) |
| `default_ttl` | Optional default expiry for objects put without one |

The same space name on two hosts MAY point at the same store. A reference (below) carries the endpoint hint so a recipient can find it.

## Object

An **object** is one file in a space at a path. Paths use `/` separators and the character set `[a-zA-Z0-9._/-]`. A path MUST NOT contain `..`, a leading `/`, empty segments, control characters or null bytes. Maximum path length is 512 characters. Objects are immutable by convention: to change a file, put a new path.

## Reference

A **reference** names an object and pins its content:

```
afp://<space>/<path>
```

In a message or a manifest a reference is accompanied by the digest, so the form that travels is an object:

```json
{
  "ref": "afp://artifacts/2026/10/report.pdf",
  "digest": "sha256:3b2c9f5da87e4f1c8b0a2d6e9f3c7a1b5d8e2f4a6c0b3d7e9f1a4c6d8e0b2a4",
  "size": 1827341,
  "endpoint": "https://files.example.net",
  "url": "https://files.example.net/artifacts/2026/10/report.pdf?X-Amz-Expires=3600&..."
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `ref` | Yes | The reference |
| `digest` | Yes | `sha256:<hex>` of the content. Same format as AMP attachment digests |
| `size` | Yes | Size in bytes |
| `endpoint` | No | A hint where the space's store lives, for a recipient that has no configuration for the space |
| `url` | No | A time-limited download link from `link`. Lets a recipient without credentials fetch the file. Short-lived and not part of the object's identity |

The identity of an object is the pair `ref` plus `digest`. `endpoint` and `url` are conveniences.

## Manifest

Every object has a **manifest**, a small JSON document stored next to it at `<path>.afp.json`:

```json
{
  "afp": "0.1",
  "path": "2026/10/report.pdf",
  "digest": "sha256:3b2c...",
  "size": 1827341,
  "content_type": "application/pdf",
  "owner": "backend-architect@acme.aimaestro.local",
  "created": "2026-10-04T09:58:00Z",
  "expires": "2026-11-03T09:58:00Z",
  "scan": "unscanned"
}
```

| Field | Description |
|-------|-------------|
| `owner` | The AMP address (or AID identity) of the agent or person that put the object |
| `expires` | Optional. After this time a backend MAY delete the object and manifest |
| `scan` | `clean`, `basic_clean`, `unscanned`, `suspicious` or `rejected`, the same vocabulary as AMP attachments |

The manifest is written after the object. An object without a manifest is treated as `unscanned` with an unknown owner, and clients SHOULD warn.

## Capabilities

A backend declares what it can do. Callers MUST check before relying on a feature.

| Capability | Meaning |
|------------|---------|
| `link` | Can mint a time-limited download link |
| `expire` | Deletes objects after their `expires` time |
| `versions` | Keeps prior versions of an overwritten object |
| `offline` | A host keeps working with no connection to the store |
| `ui` | A human can browse the space with a standard tool |

The S3 profile with Garage declares `link`, `expire` and `ui` (through any S3 client), and does not declare `versions` or `offline`.
