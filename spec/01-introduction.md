# 01 - Introduction

**Status:** Draft v0.1

## Purpose

AMP carries messages. It also carries file attachments, but those are tied to one message: provider-hosted, capped at 25 MB, deleted after the message expires. Agents and people also need files that outlive a message, are large, are shared by several parties, or are published for a human to pick up.

AFP defines how an agent stores a file, names it, proves what it is, finds it later and hands it to someone else, without depending on a shared filesystem.

## Design principles

1. **Objects, not mounts.** Files are stored and fetched explicitly. No protocol feature relies on a mounted path.
2. **The store is the truth.** A reference or a message announcing a file is a hint. The object and its manifest in the store decide what exists.
3. **Report only what you can prove.** `put` reports `stored` only after reading back the digest. A caller that cannot confirm storage is told so.
4. **Verify on fetch.** Every reference carries a digest. A fetch whose bytes do not match fails.
5. **Content from other parties is data.** A fetched file is treated like AMP external content: labeled, never trusted as instructions.
6. **Backend neutral.** Agents see five operations and a capability list. They do not see the backend.
7. **Small.** No folders-as-objects, no merge, no versions in v0.1.

## Relationship to the other protocols

| Need | Use |
|------|-----|
| A file for one recipient, delivered with one message | AMP attachment (Section 04 of AMP) |
| A file several agents or people need, or one that is large or temporary | An AFP object, referenced from a message |
| Identity of who put a file | AID agent identity (the manifest `owner`) |
| Telling an agent a file arrived | An AMP message carrying the reference, following the notification principles in AMP Section 12 |

## Conventions

The words MUST, SHOULD and MAY are used as in RFC 2119. Sections are **Normative** unless marked **Informative**.
