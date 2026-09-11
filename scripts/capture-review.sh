#!/usr/bin/env bash
# Capture review screenshots of the running simulator for the docs.
#
# Runs the image exactly as a user would, waits for it to be genuinely healthy,
# then drives a headless browser to photograph the viewer. The point is that
# the pictures in the README are of the SHIPPED IMAGE, not of a dev checkout.
#
#   ./scripts/capture-review.sh [image] [outdir]
set -euo pipefail

IMAGE="${1:-microduck-docker:test}"
OUT="${2:-docs/media}"
NAME=microduck-capture
VIEWER=63317
LAB=8788

mkdir -p "$OUT"
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "▶ starting $IMAGE"
docker run -d --name "$NAME" \
  -p "127.0.0.1:${VIEWER}:63317" -p "127.0.0.1:${LAB}:8788" \
  "$IMAGE" >/dev/null

echo "▶ waiting for health"
for i in $(seq 1 120); do
  s=$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo none)
  [ "$s" = healthy ] && break
  if [ "$s" = unhealthy ] || ! docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
    docker logs "$NAME"; echo "✗ container failed"; exit 1
  fi
  sleep 2
done
[ "$s" = healthy ] || { docker logs "$NAME"; echo "✗ never healthy"; exit 1; }

# Let the ducks actually take a few steps: a screenshot of frame 0 is a photo
# of a T-pose, which tells a reader nothing about whether the sim works.
echo "▶ letting the physics settle"
sleep 12

echo "▶ evidence from the API"
curl -fsS "localhost:${LAB}/scene"    -o "$OUT/scene.json"
curl -fsS "localhost:${LAB}/policies" -o "$OUT/policies.json"
docker run --rm "$IMAGE" version | tee "$OUT/version.txt"

# Screenshot via Playwright in a throwaway container — nothing to install here.
# --network host so it can reach the published loopback ports.
echo "▶ screenshotting the viewer"
docker run --rm --network host -v "$PWD/$OUT:/out" \
  mcr.microsoft.com/playwright:v1.50.0-noble \
  bash -c '
    npm i -s playwright@1.50.0 >/dev/null 2>&1 || true
    node -e "
      const {chromium} = require(\"playwright\");
      (async () => {
        const b = await chromium.launch();
        const p = await b.newPage({viewport:{width:1600,height:1000}, deviceScaleFactor:2});
        await p.goto(\"http://localhost:'"$VIEWER"'\", {waitUntil:\"networkidle\", timeout:60000});
        await p.waitForTimeout(10000);          // let ducks walk into frame
        await p.screenshot({path:\"/out/viewer.png\"});
        await p.waitForTimeout(4000);
        await p.screenshot({path:\"/out/viewer-2.png\"});
        await b.close();
      })().catch(e => { console.error(e); process.exit(1); });
    "
  ' || echo "⚠ screenshot step failed — API evidence above is still valid"

echo "▶ container log"
docker logs "$NAME" 2>&1 | tail -20 | tee "$OUT/run.log"

echo
echo "✓ captured into $OUT:"
ls -la "$OUT"
