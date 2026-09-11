# 🦆 Microduck Docker — User Manual

Everything this image can do, from "I just want to see a robot" to "I want to
train my own and put it on real hardware".

**Contents**
1. [Before you start](#1-before-you-start)
2. [Running the simulator](#2-running-the-simulator)
3. [Using the viewer](#3-using-the-viewer)
4. [Choosing which ducks appear](#4-choosing-which-ducks-appear)
5. [Saving your work](#5-saving-your-work)
6. [Training your own robot brain](#6-training-your-own-robot-brain)
7. [Command reference](#7-command-reference)
8. [Testing that it works](#8-testing-that-it-works)
9. [Troubleshooting](#9-troubleshooting)
10. [For the classroom](#10-for-the-classroom)

---

## 1. Before you start

**You need:** Docker, a browser, ~2 GB of disk.
**You do not need:** Python, a GPU, a real Microduck, any prior robotics.

Check Docker is alive:

```bash
docker --version
```

### What is actually happening?

The container runs two programs:

| Program | Port | Job |
|---|---|---|
| **duck-lab** | 8788 | simulates physics 50 times a second and runs the robot's brain |
| **duck-viewer** | 63317 | the 3D web page you look at |

Your browser talks to *both*, which is why you publish two ports. The page
draws what the physics engine reports — it is not a video, it is a live
simulation responding to you.

---

## 2. Running the simulator

```bash
docker run --rm -p 63317:63317 -p 8788:8788 srayuth089/microduck-docker
```

Then open <http://localhost:63317>.

| Flag | Why it's there |
|---|---|
| `--rm` | delete the container when you stop it (your data lives in the volume) |
| `-p 63317:63317` | the web page |
| `-p 8788:8788` | the physics/brain connection **(required)** |

Stop with `Ctrl+C`.

### Run it in the background

```bash
docker run -d --name duck -p 63317:63317 -p 8788:8788 srayuth089/microduck-docker
docker logs -f duck      # watch it
docker stop duck         # stop it
```

### Safer ports (recommended on shared networks)

Bind to your own machine only, so nobody on the same Wi-Fi can reach the lab:

```bash
docker run --rm -p 127.0.0.1:63317:63317 -p 127.0.0.1:8788:8788 \
  srayuth089/microduck-docker
```

---

## 3. Using the viewer

<!-- CAPTURE:viewer-annotated -->

### Moving a duck
Click to select, then **W/A/S/D**. You send a *velocity command*; the brain
works out the leg motion. This is the same 61-number observation and 14-number
action the real robot uses.

### Policy panel — swapping brains
Every duck runs one `.onnx` policy. Drag a policy chip onto a duck to swap it
live. Good experiments:

- `BEST_alpha_walking` vs `BEST_alpha_stand` — same body, different goal
- drop `roulade` on a walking duck mid-stride
- put the *same* brain on several ducks and push them differently

### 🎓 Teach panel — the fun one
Type a trick: `stand on one leg`, `wave`, `crouch`, `headstand`, `backflip`.

What happens:
1. keywords are matched to a **reward recipe** (no LLM involved)
2. the recipe is shown in plain English — *this* is what the robot is paid to do
3. PPO training starts; roughly every 15 s a fresh snapshot hot-loads
4. you watch it improve, and drag sliders to change the rewards

**This is the single best thing in the image for learning RL.** Reward shaping
stops being abstract when a bad reward makes your duck fall over immediately.

Hard tricks (the backflip) are staged curricula — the viewer narrates the chain.

### 🎬 Animate panel
Pose the robot by hand with a keyframe rig, then press **train this** and RL
learns to physically execute your animation. Note what happens to poses that
are physically impossible: physics does not negotiate.

### 🎥 Capture panel
📷 saves a PNG. 🎥 films a duck and writes mp4 + GIF into `/data/captures`
(mount a volume to keep them).

### ⤓ ONNX download
Any run can be downloaded as `.onnx` with the normalizer baked in — the same
format the real robot's runtime loads.

---

## 4. Choosing which ducks appear

List what's inside:

```bash
docker run --rm srayuth089/microduck-docker policies
```

```
BEST_alpha_sitstand    BEST_alpha_stand      BEST_alpha_walking
BEST_roller            BEST_roller_crouch    alpha_ground_pick
ball_kick_left         ball_kick_right       roulade
```

Pick some with `DUCKS` (names, paths, or your own runs):

```bash
docker run --rm -p 63317:63317 -p 8788:8788 \
  -e DUCKS="BEST_alpha_walking ball_kick_left ball_kick_right roulade" \
  srayuth089/microduck-docker
```

More ducks = more CPU. Start with 2–4.

---

## 5. Saving your work

By default a `--rm` container throws everything away. Mount `/data` to keep
trained brains, videos and the roster:

```bash
docker run --rm -p 63317:63317 -p 8788:8788 \
  -v microduck-data:/data srayuth089/microduck-docker
```

| Path in `/data` | Contents |
|---|---|
| `runs/` | your training runs (checkpoints, `policy.onnx`, logs) |
| `captures/` | PNG / mp4 / GIF from the Capture panel |
| `lab-state.json` | which ducks were on screen |

Use a real folder instead of a named volume if you prefer:
`-v "$PWD/microduck-data:/data"`.

---

## 6. Training your own robot brain

### The short version

```bash
# 1. train (a few minutes on a normal CPU)
docker run --rm -v microduck-data:/data srayuth089/microduck-docker \
  train --envs 32 --steps 3000000 --run-name my-first-duck

# 2. export to the robot's format
docker run --rm -v microduck-data:/data srayuth089/microduck-docker \
  export /data/runs/my-first-duck

# 3. score it
docker run --rm -v microduck-data:/data srayuth089/microduck-docker \
  eval /data/runs/my-first-duck/policy.onnx

# 4. watch it, next to the official brain
docker run --rm -p 63317:63317 -p 8788:8788 -v microduck-data:/data \
  -e DUCKS="my-first-duck BEST_alpha_walking" srayuth089/microduck-docker
```

### Tuning

Find the best worker count for *your* machine first:

```bash
docker run --rm srayuth089/microduck-docker bench
```

| Option | Meaning |
|---|---|
| `--envs N` | parallel simulations. More = faster learning, more CPU |
| `--steps N` | training length. 3M ≈ a usable gait; 10M+ ≈ better |
| `--run-name X` | where it's saved under `/data/runs` |

Give Docker Desktop more CPUs (*Settings → Resources*) before a long run.

### How good is it?

`eval` reports falls and how well it follows commands. Compare against
`BEST_alpha_walking` — beating it is genuinely hard, and that's the lesson.

### Does this work on the real robot?

The ONNX is drop-in compatible with the official runtime. But policies trained
here are for **prototyping rewards and ideas**. For real hardware (sim2real),
upstream re-runs the recipe on [`microduck_rl`](https://github.com/pollen-robotics/microduck_rl)
with a GPU, because the domain randomisation needed to survive reality costs
more compute than a CPU can provide. Invent the behaviour here; graduate it there.

---

## 7. Command reference

`docker run --rm [options] srayuth089/microduck-docker <command> [args]`

| Command | Purpose |
|---|---|
| `serve` *(default)* | run the simulator + viewer |
| `policies` | list brains in the image and in `/data/runs` |
| `version` | exact upstream commits this image was built from |
| `train …` | `train-walk` — velocity-command walking |
| `behavior …` | `train-behavior` — tricks |
| `export …` | `export-walk` — ONNX with normalizer baked in |
| `eval …` | `eval-walk` — headless scoring |
| `render …` | `render-rollout` — mp4 + captioned contact sheet |
| `bench …` | `bench-walk` — throughput tuning |
| `shell` | bash inside the container |

Anything else is executed literally, so `… srayuth089/microduck-docker python -V` works.

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `DUCKS` | walking + stand | which policies to load |
| `VIEWER_PORT` | `63317` | web page port *inside* the container |
| `LAB_PORT` | `8788` | physics server port *inside* the container |

---

## 8. Testing that it works

Use this to verify a fresh machine, or after a rebuild.

### Quick check (30 seconds)

```bash
# 1. the image runs and reports its provenance
docker run --rm srayuth089/microduck-docker version

# 2. the policies are present
docker run --rm srayuth089/microduck-docker policies
```

### Full check (2 minutes)

```bash
docker run -d --name ducktest \
  -p 127.0.0.1:63317:63317 -p 127.0.0.1:8788:8788 \
  srayuth089/microduck-docker

# wait for the built-in healthcheck to pass
until [ "$(docker inspect -f '{{.State.Health.Status}}' ducktest)" = healthy ]; do
  sleep 2; echo "waiting…"
done

# the physics engine is serving real geometry, not just an open socket
curl -fsS localhost:8788/scene | head -c 120

# the page is being served
curl -fsS -o /dev/null -w 'viewer HTTP %{http_code}\n' localhost:63317/

docker rm -f ducktest
```

**Expected:** healthy within ~60 s, `/scene` returns JSON containing `geom`,
and the viewer returns `HTTP 200`.

### Then check it by eye

Open <http://localhost:63317> and confirm:

- [ ] two ducks are visible and **standing, not sinking through the floor**
- [ ] one is stepping in place (the walker) — motion means physics is stepping
- [ ] clicking a duck selects it; **W** makes it walk forward
- [ ] the Teach panel lists tricks
- [ ] dragging a policy chip onto a duck changes its behaviour

If the ducks are frozen, the physics thread died — check `docker logs ducktest`.

<!-- CAPTURE:review -->

---

## 9. Troubleshooting

**Blank page, or "can't connect to the lab"**
You almost certainly published only one port. Both `-p 63317:63317` and
`-p 8788:8788` are required.

**I opened the "Network" URL and it broke**
Use `http://localhost:63317`. The lab deliberately accepts only `localhost`
origins because its API can delete training runs; a LAN origin is refused by
design. To reach it from another machine, tunnel instead:
`ssh -L 63317:localhost:63317 -L 8788:localhost:8788 user@host`.

**"port is already allocated"**
Remap the outside number: `-p 8080:63317` → browse `localhost:8080`.
(If you remap 8788, tell the page with `http://localhost:8080/?lab=localhost:9999`.)

**Very slow, fans loud**
Normal — this is real physics. Fewer ducks (`-e DUCKS="BEST_alpha_walking"`),
more CPUs in Docker Desktop, and close the Teach panel when not training.

**Trained runs disappeared**
No `-v microduck-data:/data`. With `--rm`, anything outside the volume is gone.

**Apple Silicon: "requested image's platform does not match"**
A native `arm64` image is published; force it with `--platform linux/arm64`.

**Nothing works and you want to look inside**
```bash
docker run --rm -it srayuth089/microduck-docker shell
```

---

## 10. For the classroom

A 45-minute lesson that needs no robotics background.

| Time | Activity | The idea landing |
|---|---|---|
| 0–5 | everyone runs the one-liner, opens the page | robots can be simulated |
| 5–15 | drive with WASD; try to make it fall | balance is *active*, not luck |
| 15–25 | swap brains with the policy panel | the body is fixed; the **brain** is the software |
| 25–40 | Teach panel: "stand on one leg", then move the reward sliders | machines learn what you **reward**, not what you mean |
| 40–45 | film the best duck, share the GIF | pride of authorship |

**Questions that work well**

- What if we reward *height* only? (it jumps, or stands on tiptoe, and falls)
- Why does the same brain behave differently on a slope?
- The robot has 14 joints and sees 61 numbers. What would *you* want it to see?
- Why is a simulated duck easier than a real one?

**Notes for the teacher**

- Fully offline after the first `docker pull` — good for locked-down networks.
- One machine can drive a projector while pairs experiment on laptops.
- The reward sliders are the lesson. Let a group deliberately design a *bad*
  reward and watch it get exploited — that is AI safety, taught in 3 minutes.

---

*Questions and problems: <https://github.com/srayuth089/microduck-docker/issues>*
