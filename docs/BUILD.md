# Building microduck-docker

The published images are built by GitHub Actions, not on a laptop. This
document explains how that works and how to reproduce or modify it.

## Design

This repo contains **no robot code**. It contains a Dockerfile that fetches
upstream code at build time. Consequences worth knowing:

- **Rebuilding tracks upstream.** A build today picks up whatever
  `microduck-lab@main`, `microduck_rl@develop` and the policies repo currently
  hold. That is deliberate: the image should follow the official projects.
- **A published image is still reproducible.** CI resolves each ref to a commit
  *before* building and passes the SHAs in as build args, so the image records
  exactly what it contains:

  ```bash
  docker run --rm srayuth089/microduck-docker version
  docker inspect srayuth089/microduck-docker | grep io.microduck.revision
  ```

- Rebuilding with those SHAs reproduces that image.

## CI: `.github/workflows/build.yml`

```
resolve ──► test ──► publish
```

| Job | Runs on | Does |
|---|---|---|
| **resolve** | every trigger | `git ls-remote` each upstream → SHAs; derives the version; skips the run if a scheduled build finds nothing changed |
| **test** | every trigger | builds native amd64 and **smoke-tests it**: healthcheck, `/scene` returns real geometry, viewer answers, `policies` lists the walker |
| **publish** | not on PRs | builds multi-arch, pushes to Docker Hub with provenance + SBOM, syncs the Hub README, cuts a GitHub release |

**Triggers**

| Trigger | When |
|---|---|
| `schedule` | Mondays 04:17 UTC — picks up upstream changes unattended |
| `push` | changes to `Dockerfile`, `entrypoint.sh`, or the workflow |
| `pull_request` | build + test only, never publishes |
| `workflow_dispatch` | manual, with an "all architectures" checkbox |

The scheduled run exits early when the upstream fingerprint already has a
published tag, so quiet weeks cost almost no CI minutes.

### Versioning

```
2026.09.11-a1b2c3d
└─ build date  └─ sha256(lab+rl+policies)[:7]
```

Chronologically sortable, and identical upstream code always yields the same
tag. `latest` follows the newest successful publish.

## One-time setup

The workflow needs one secret:

| Name | Where |
|---|---|
| `DOCKERHUB_TOKEN` | Docker Hub → *Account Settings → Personal access tokens* → **Read & Write** |

Add it under *Settings → Secrets and variables → Actions → New repository secret*.

Optionally set the repository **variable** `DOCKERHUB_USERNAME` if your Hub
account is not `srayuth089`.

Then: *Actions → build & publish → Run workflow*.

## Architectures

Always built: `linux/amd64`, `linux/arm64`.
On request (the `all_arches` checkbox): `linux/ppc64le`, `linux/s390x`.

The exotic pair is opt-in because they build under QEMU emulation and there are
no manylinux wheels for numba/onnxruntime there, so those compile from source —
expect a long run. `build-essential` and `cmake` are in the builder stage for
exactly this reason.

## Building locally

You do not need to, but:

```bash
# native arch
docker build -t microduck-docker:dev .

# pin upstream explicitly
docker build -t microduck-docker:pinned \
  --build-arg LAB_SHA=38624537030bcfdb0d48c7df68d8ced8d7061837 \
  --build-arg RL_SHA=29e887ecfbf5d37144759e5a9f8a176dfb83d547 \
  --build-arg VERSION=local .

# multi-arch (needs buildx + QEMU)
docker buildx build --platform linux/amd64,linux/arm64 -t you/microduck-docker:dev --push .
```

Then run the checks in
[USER-MANUAL §8](USER-MANUAL.md#8-testing-that-it-works).

## Image layout

| Path | Contents |
|---|---|
| `/opt/venv` | Python 3.12 + CPU torch, MuJoCo, SB3, onnxruntime |
| `/app/microduck_local` | the lab: trainer, evaluator, `duck-lab` server |
| `/app/microduck_rl` | MJCF robot model + meshes (`MICRODUCK_RL_DIR`) |
| `/app/policies` | pretrained `.onnx` policies |
| `/app/viewer` | prebuilt Next.js standalone server |
| `/data` | **volume** — runs, captures, roster |

Size notes: CPU-only torch is installed from the PyTorch CPU index, which
avoids ~2.5 GB of CUDA wheels the image could never use. The viewer is built
with `output: "standalone"`, so no `node_modules` ships.

## The one upstream modification

`duck-lab` hardcodes `host="127.0.0.1"`, which inside a container means
"unreachable from outside". The Dockerfile adds a `--host` flag by `sed`,
and **fails the build** if the target line is not found — so an upstream
refactor produces a loud error instead of a silently unbound server.

Upstream's loopback restriction is a real security boundary (the API exposes
`DELETE /runs` and Hugging Face token routes), and it is preserved:

- the default is still `127.0.0.1`;
- `0.0.0.0` inside a container namespace is that container's own loopback;
- the documented `docker run` publishes to host loopback;
- the browser origin stays `http://localhost:…`, so the origin checks on
  `/ws` and `POST /captures` are untouched.

## Maintenance

**Upstream renamed a branch** → update `resolve` in the workflow and the
`ARG *_SHA` defaults.

**Upstream moved the MJCF** → `COPY` in the `src` stage fails loudly; fix the path.

**The patch step fails** → upstream changed `viz_server.py`'s argument parser.
Re-read `main()` and adjust the `sed`. Do not remove the `grep` guards.
