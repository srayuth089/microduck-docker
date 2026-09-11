# syntax=docker/dockerfile:1.7
#
# microduck-docker — the Microduck simulator, batteries included.
#
# Everything needed to watch (and train) Pollen Robotics' 25 cm bipedal robot
# is baked in: the MuJoCo physics, the MJCF robot model with its meshes, the
# pretrained ONNX policies, the PPO trainer, and a prebuilt Next.js viewer.
# First run is offline and instant — no clone, no download, no host Python.
#
# Multi-arch: linux/amd64, linux/arm64, linux/ppc64le, linux/s390x.

# ---------------------------------------------------------------------------
# Upstream sources. The refs below are what a bare `docker build` tracks; CI
# resolves each to a concrete commit first and passes it back in, so every
# published image records the exact SHAs it was built from (see the
# io.microduck.revision.* labels and the `version` command).
#
# Rebuilding therefore picks up upstream's newest code on purpose, while any
# individual published image stays reproducible from its recorded SHAs.
# ---------------------------------------------------------------------------
ARG LAB_REPO=https://github.com/jonathanhawkins/microduck-lab.git
ARG LAB_SHA=main
ARG RL_REPO=https://github.com/pollen-robotics/microduck_rl.git
ARG RL_SHA=develop
ARG POLICIES_REPO=https://github.com/IronSpiderMan/MicroDuckModels.git
ARG POLICIES_SHA=HEAD

# ===========================================================================
# Stage 1 — fetch sources (shallow, then strip .git; no VCS history shipped)
# ===========================================================================
FROM alpine/git:latest AS src
ARG LAB_REPO LAB_SHA RL_REPO RL_SHA POLICIES_REPO POLICIES_SHA
WORKDIR /src

# Fetch one commit rather than cloning history: smaller, and pinned.
RUN set -eux; \
    fetch() { \
      mkdir -p "$3"; cd "$3"; git init -q; git remote add origin "$1"; \
      git fetch -q --depth 1 origin "$2"; git checkout -q FETCH_HEAD; \
      rm -rf .git; \
    }; \
    fetch "$LAB_REPO"      "$LAB_SHA"      /src/microduck-lab; \
    fetch "$RL_REPO"       "$RL_SHA"       /src/microduck_rl; \
    fetch "$POLICIES_REPO" "$POLICIES_SHA" /src/policies-src

# Keep only what the simulator actually reads. microduck_rl is 34 MB of which
# we need the robot model; the policies repo is a whole web app of which we
# need nine .onnx files.
#
# The `test` assertions at the end are the point of this stage as much as the
# copying is: these builds track upstream HEAD, so a file moving upstream must
# fail the BUILD. Without them it would produce an image that builds green and
# then breaks in a user's hands — the worst place to find out.
RUN set -eux; \
    mkdir -p /out/microduck_rl/src/mjlab_microduck/robot /out/policies; \
    cp -r /src/microduck_rl/src/mjlab_microduck/robot/microduck \
          /out/microduck_rl/src/mjlab_microduck/robot/microduck; \
    cp /src/microduck_rl/LICENSE /out/microduck_rl/LICENSE; \
    cp /src/policies-src/public/policies/*.onnx /out/policies/; \
    cp -r /src/microduck-lab /out/microduck-lab; \
    rm -rf /out/microduck-lab/.venv /out/microduck-lab/*/node_modules \
           /out/microduck-lab/microduck_local/runs \
           /out/microduck-lab/microduck_local/lab-state.json; \
    test -f /out/microduck_rl/src/mjlab_microduck/robot/microduck/scene_walk.xml; \
    test -f /out/microduck-lab/microduck_local/pyproject.toml; \
    test -f /out/microduck-lab/duck-viewer/package.json; \
    test -f /out/policies/BEST_alpha_walking.onnx; \
    n=$(ls /out/policies/*.onnx | wc -l); echo "policies: $n"; [ "$n" -ge 5 ]

# ===========================================================================
# Stage 2 — build the viewer into a standalone production server
# ===========================================================================
FROM node:22-bookworm-slim AS viewer
WORKDIR /build
COPY --from=src /out/microduck-lab/duck-viewer/ ./

# `output: "standalone"` emits a self-contained server.js, so the runtime image
# carries neither node_modules nor the Next.js dev toolchain.
RUN printf '%s\n' \
    'import type { NextConfig } from "next";' \
    'const nextConfig: NextConfig = { output: "standalone" };' \
    'export default nextConfig;' > next.config.ts

RUN npm ci --no-audit --no-fund
RUN npm run build

# ===========================================================================
# Stage 3 — Python deps. Heaviest layer; built before app code so edits to
# the lab source do not re-resolve torch.
# ===========================================================================
FROM python:3.12-slim-bookworm AS pydeps
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1

# build-essential: numba/llvmlite and onnxruntime build from sdist on the
# architectures (ppc64le, s390x) that publish no manylinux wheels.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential cmake git patchelf; \
    rm -rf /var/lib/apt/lists/*

COPY --from=src /out/microduck-lab/microduck_local/pyproject.toml /app/microduck_local/
COPY --from=src /out/microduck-lab/microduck_local/src/ /app/microduck_local/src/

# CPU-only torch: the CUDA build pulls ~2.5 GB of nvidia wheels this image can
# never use (there is no GPU passthrough here, and the whole point of
# microduck-lab is that it trains on CPU).
RUN set -eux; \
    python -m venv /opt/venv; \
    /opt/venv/bin/pip install --upgrade pip setuptools wheel; \
    /opt/venv/bin/pip install \
        --extra-index-url https://download.pytorch.org/whl/cpu \
        /app/microduck_local

# ===========================================================================
# Stage 4 — runtime
# ===========================================================================
FROM python:3.12-slim-bookworm AS runtime

# Re-declare in this stage: ARGs do not cross FROM boundaries.
ARG LAB_REPO LAB_SHA RL_REPO RL_SHA POLICIES_REPO POLICIES_SHA
ARG VERSION=dev
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="microduck-docker" \
      org.opencontainers.image.description="Microduck bipedal robot simulator — MuJoCo physics, pretrained RL policies and a 3D browser viewer, in one container." \
      org.opencontainers.image.source="https://github.com/srayuth089/microduck-docker" \
      org.opencontainers.image.licenses="Apache-2.0 AND CC-BY-NC-SA-4.0" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      io.microduck.revision.lab="${LAB_SHA}" \
      io.microduck.revision.rl="${RL_SHA}" \
      io.microduck.revision.policies="${POLICIES_SHA}"

# libgl/libglib: MuJoCo's offscreen renderer (render-rollout) links them even
# when the sim itself runs headless. nodejs: serves the prebuilt viewer.
# ffmpeg comes from the imageio-ffmpeg wheel, so it is not installed here.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libgl1 libglib2.0-0 nodejs tini curl bash procps; \
    rm -rf /var/lib/apt/lists/*

COPY --from=pydeps /opt/venv /opt/venv
COPY --from=src /out/microduck-lab/microduck_local /app/microduck_local
COPY --from=src /out/microduck_rl /app/microduck_rl
COPY --from=src /out/policies /app/policies

# Prebuilt viewer: standalone server + the static assets it serves.
COPY --from=viewer /build/.next/standalone /app/viewer
COPY --from=viewer /build/.next/static /app/viewer/.next/static
COPY --from=viewer /build/public /app/viewer/public

ENV PATH=/opt/venv/bin:$PATH \
    MICRODUCK_RL_DIR=/app/microduck_rl \
    PYTHONUNBUFFERED=1 \
    LAB_PORT=8788 \
    VIEWER_PORT=63317 \
    DUCKS="" \
    NODE_ENV=production

# Teach duck-lab a --host flag so it can bind inside the container. The script
# carries the full rationale; in short, upstream's loopback trust boundary is
# preserved (default unchanged, host publishes to loopback, origins untouched)
# and every assumption is asserted so an upstream refactor fails the build
# instead of shipping a server that is unreachable or silently unbound.
COPY scripts/add-host-flag.py /tmp/add-host-flag.py
RUN set -eux; \
    /opt/venv/bin/python /tmp/add-host-flag.py; \
    rm /tmp/add-host-flag.py; \
    duck-lab --help | grep -q -- --host

RUN printf '%s\n' \
    "microduck-docker ${VERSION}  (built ${BUILD_DATE})" \
    "" \
    "Upstream code baked into this image:" \
    "  microduck-lab   ${LAB_SHA}" \
    "                  ${LAB_REPO}" \
    "  microduck_rl    ${RL_SHA}" \
    "                  ${RL_REPO}" \
    "  policies        ${POLICIES_SHA}" \
    "                  ${POLICIES_REPO}" \
    > /app/VERSION.txt

# Training runs and captures land here; mount a volume to keep them.
VOLUME /data
WORKDIR /app

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 63317 8788

# Non-root. /data is chowned so a fresh anonymous volume is writable.
RUN useradd -m -u 1000 duck && mkdir -p /data && chown -R duck:duck /data /app
USER duck

HEALTHCHECK --interval=15s --timeout=5s --start-period=90s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${LAB_PORT}/scene" >/dev/null \
      && curl -fsS "http://127.0.0.1:${VIEWER_PORT}/" >/dev/null || exit 1

# tini reaps the MuJoCo worker processes the trainer forks.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["serve"]
