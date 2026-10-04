# 04 - Backends

**Status:** Draft v0.1

## Contract

A backend implements the operations in Section 03 for one space. v0.1 defines one profile, `s3`. A future profile (for example a synced-folder profile) must declare its capabilities and pass the same behavior tests.

## S3 profile

The `s3` profile uses the S3 API with these operations: PutObject (including multipart), GetObject, HeadObject, ListObjectsV2, DeleteObject and presigned GET URLs.

| AFP | S3 |
|-----|----|
| space | one bucket, or one key prefix in a shared bucket |
| object | one object at the path as its key |
| manifest | a second object at `<path>.afp.json` |
| `link` | a presigned GET URL |
| `expires` | a lifecycle rule on the bucket or prefix, and the manifest field |
| access scope | an access key with permissions scoped to the bucket or prefix |

The profile does not need S3 ACLs, bucket policies, or versioning. A store that lacks them, such as Garage, conforms.

## Reference backend: Garage

[Garage](https://garagehq.deuxfleurs.fr/) is a lightweight, self-hosted, S3-compatible store: a single binary that runs on small hardware, with a single-node mode and optional replication. It supports presigned URLs, multipart upload, CORS and lifecycle expiry (expiration and abort-incomplete-multipart actions only). It does not support object versioning, S3 ACLs, bucket policies or quotas. It uses per-key, per-bucket permissions.

Garage is the reference because it is small enough to run on any host. Nothing in AFP requires it.

## Deployment topologies (Informative)

The `endpoint` of a space can be any of the following. The protocol is the same in each.

| Topology | Typical use | Trade-offs |
|----------|-------------|------------|
| **Local only.** Garage on one host, reached over a LAN or a private mesh such as Tailscale | A team's fleet on its own network | No cost, no data leaves the network. One host is a single point of failure until replicated |
| **Self-hosted in the cloud.** Garage on a VPS or cloud instance, behind a TLS reverse proxy | Agents and people in several places, links that must work from outside | You run and patch it. Reachable from anywhere, so the network is no longer the trust boundary and access keys matter more |
| **Hosted S3-compatible service.** Any provider that speaks the S3 API | No server to run | Data leaves your network. Provider terms, egress and pricing apply. Capabilities vary and MUST be declared |
| **Multi-node Garage.** Several hosts with replication | Surviving a host failure | More to operate. Needs a replication factor above 1 |

A host MAY configure several spaces on different topologies, for example `shared` on a local store and `public` on a cloud store.

## Backend conformance (Informative)

A backend passes if: a put followed by a get returns identical bytes with a matching digest; a get of an altered object fails with `digest_mismatch`; `capabilities` reports exactly what the backend does; an unreachable store returns `unreachable`; and invalid paths are rejected before any request is made.
