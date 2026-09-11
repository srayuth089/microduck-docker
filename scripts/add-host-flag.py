"""Teach duck-lab a --host flag so it can bind inside a container.

Upstream (microduck-lab) hardcodes ``host="127.0.0.1"`` in viz_server.main().
That is a deliberate security boundary, not an oversight: the lab's API exposes
``DELETE /runs`` and Hugging Face token routes, and loopback is the whole
surface it trusts.

The boundary is preserved here rather than widened:

  * the flag DEFAULTS to 127.0.0.1, so behaviour outside Docker is unchanged;
  * the container passes 0.0.0.0, which is loopback-equivalent because a
    container's network namespace is its own machine;
  * the documented `docker run` publishes to HOST loopback only, so the port
    is never reachable from the LAN; and
  * the browser origin stays http://localhost:PORT, leaving LOCAL_ORIGIN_RE
    and the /ws + POST /captures origin checks untouched.

This edits the copy pip installed into the venv — the file Python actually
imports. Editing the source tree instead would patch a file nothing loads, and
the server would quietly keep binding 127.0.0.1 and be unreachable.

Every assumption is asserted, so an upstream refactor fails the build loudly
instead of shipping a broken (or silently unbound) server.
"""

import pathlib

import microduck_local.viz_server as vs

ANCHOR = 'ap.add_argument("--port", type=int, default=8788)'
BIND = 'host="127.0.0.1", port=args.port'
ADDITION = (
    '\n    ap.add_argument("--host", default="127.0.0.1",\n'
    '                    help="bind address (default loopback; the container "\n'
    '                         "image passes 0.0.0.0 and publishes to host "\n'
    '                         "loopback only)")'
)

path = pathlib.Path(vs.__file__)
src = path.read_text()

if "host=args.host" in src:
    print(f"already patched: {path}")
    raise SystemExit(0)

if ANCHOR not in src:
    raise SystemExit(f"PATCH TARGET GONE: --port argument not found in {path}")
if BIND not in src:
    raise SystemExit(f"PATCH TARGET GONE: uvicorn bind not found in {path}")

src = src.replace(ANCHOR, ANCHOR + ADDITION, 1)
src = src.replace(BIND, "host=args.host, port=args.port", 1)
path.write_text(src)

compile(src, str(path), "exec")  # syntax must survive the edit
print(f"patched: {path}")
