# 05 - AMP integration

**Status:** Draft v0.1

AFP works with AMP without changing how AMP attachments work today. A message can carry either kind.

## Two kinds of attachment

An entry in a message's `payload.attachments` has a `storage` field.

| `storage` | Meaning |
|-----------|---------|
| `provider` (or absent) | The existing AMP behavior: the file is uploaded to the provider, scanned, signed, and expires with the message. Unchanged |
| `afp` | The attachment is an AFP reference. No bytes pass through the provider |

An attachment with no `storage` field is `provider`, so existing messages and implementations are unaffected.

## AFP attachment object

```json
{
  "storage": "afp",
  "filename": "report.pdf",
  "content_type": "application/pdf",
  "size": 1827341,
  "digest": "sha256:3b2c9f5da87e4f1c8b0a2d6e9f3c7a1b5d8e2f4a6c0b3d7e9f1a4c6d8e0b2a40",
  "ref": "afp://artifacts/2026/10/report.pdf",
  "endpoint": "https://files.example.net",
  "url": "https://files.example.net/artifacts/2026/10/report.pdf?X-Amz-Expires=3600&..."
}
```

`filename`, `content_type`, `size` and `digest` mean what they mean in AMP. `ref`, `endpoint` and `url` are as in Section 02. The attachment lives inside `payload`, so `payload_hash` covers it and the message signature binds the reference and digest. The `url` is short-lived, so a recipient that needs the file later uses `ref` and its own access to the space, or asks the sender for a new link.

An AFP attachment has no `id`, `scan_status`, `uploaded_at` or `expires_at`. The scan result and expiry live in the object's manifest, which the recipient reads from the store.

## Rules

- A sender MUST put the object (and receive `stored: true`) before routing the message.
- A recipient MUST verify the digest on fetch. A mismatch is not delivered to the model as content.
- The message's trust annotation applies. A file from a non-verified sender is data, not instructions, whatever it contains.
- AMP size limits (10 attachments, 25 MB each, 100 MB total) apply to `provider` attachments only. AFP attachments are limited by the space.
- A provider MUST NOT fetch, scan or rewrite an AFP attachment's content. It MAY validate the shape of the object.
- A recipient that has no access to the space and no `url` cannot fetch the file. It reports that, and does not guess another route.
- A provider that accepts AFP attachments advertises the capability `attachments:afp`. A sender routing to a recipient provider that does not list it receives `422 attachments_not_supported`, as AMP defines for unsupported attachments. Local delivery needs no negotiation.
- AMP does not cap an AFP attachment's `size`. `filename` follows the AMP character rules. The space decides any size limit.
- Notification follows AMP Section 12: the message is a hint. The store is the truth about whether the object exists.

## Choosing

Use a `provider` attachment for a file that belongs to one message and is under 25 MB. Use an `afp` attachment when the file is large, is shared by several parties, must outlive the message, or is published for a person to retrieve.
