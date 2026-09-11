# 🦆 microduck-docker

**The [Microduck](https://pollen-robotics.com/microduck) robot simulator — in one command.**

<p align="center">
  <a href="https://hub.docker.com/r/srayuth089/microduck-docker"><img alt="Docker Pulls" src="https://img.shields.io/docker/pulls/srayuth089/microduck-docker?logo=docker&logoColor=white&color=2496ED"></a>
  <a href="https://hub.docker.com/r/srayuth089/microduck-docker/tags"><img alt="Image size" src="https://img.shields.io/docker/image-size/srayuth089/microduck-docker/latest?logo=docker&logoColor=white"></a>
  <a href="https://github.com/srayuth089/microduck-docker/actions/workflows/build.yml"><img alt="Build" src="https://github.com/srayuth089/microduck-docker/actions/workflows/build.yml/badge.svg"></a>
  <img alt="Architectures" src="https://img.shields.io/badge/arch-amd64%20%7C%20arm64-informational">
  <a href="https://www.buymeacoffee.com/srayuth"><img alt="Buy me a book" src="https://img.shields.io/badge/%F0%9F%93%96-buy%20me%20a%20book-FFDD00?labelColor=000000"></a>
</p>

Microduck is a 25 cm robot that walks on two legs, made by [Pollen Robotics](https://pollen-robotics.com)
and open-sourced with Hugging Face. This image lets you **watch it walk, teach it
tricks, and train your own robot brain** — in your browser, on the computer you
already have.

You do **not** need the real robot. You do **not** need to install Python, or a
GPU, or know what a neural network is. You need Docker and one line:

```bash
docker run --rm -p 63317:63317 -p 8788:8788 srayuth089/microduck-docker
```

Then open **<http://localhost:63317>** 🎉

<!-- CAPTURE:hero -->

---

## What you get

Everything is already inside the image — no downloads on first run, no setup.

| Inside the box | What it means |
|---|---|
| 🧠 **9 pretrained robot brains** | walking, standing, kicking a ball, a forward roll… press play and watch |
| 🦴 **The real robot model** | the actual 3D Microduck, with real joint limits and real physics (MuJoCo) |
| 🎓 **Teach panel** | ask for a trick in plain English — "stand on one leg" — and watch it learn |
| 🏋️ **Full training toolkit** | train a brand-new walking brain on your own laptop's CPU in minutes |
| 🎬 **Video capture** | film your robot and export mp4/GIF to share |
| 🖥️ **Runs anywhere** | Intel, AMD, Apple Silicon, Raspberry Pi, even IBM mainframes |

---

## 🚀 Start here (5 minutes, no experience needed)

### 1. Install Docker

[Docker Desktop](https://www.docker.com/products/docker-desktop/) — free, for
Windows, Mac and Linux. Install it, open it, wait for the whale icon to settle.

### 2. Run the duck

Copy this into a terminal (Mac: *Terminal*, Windows: *PowerShell*):

```bash
docker run --rm -p 63317:63317 -p 8788:8788 srayuth089/microduck-docker
```

The first time, Docker downloads the image (~1.5 GB, a few minutes). After
that it starts in seconds. When you see this, it's ready:

```
  ┌────────────────────────────────────────────────┐
  │  🦆  Microduck is running!                     │
  │                                                │
  │  Open this in your browser:                    │
  │      http://localhost:63317                    │
  └────────────────────────────────────────────────┘
```

### 3. Open your browser

Go to **<http://localhost:63317>**. You should see two ducks: one walking, one
standing.

**To stop:** press `Ctrl+C` in the terminal.

<!-- CAPTURE:viewer -->

---

## 🎮 Things to try

### Drive the duck
Click a duck to select it, then steer with **W A S D**. It balances by itself —
you only tell it where to go.

### Swap its brain mid-stride
Open the **policy panel** and drag a different brain onto a duck. It changes
behaviour without missing a step. Try dropping `roulade` on a walking duck.

### Teach it a new trick 🎓
Open the **Teach** panel and type something like:

- `stand on one leg`
- `wave`
- `crouch`

The lab starts training right there. Every ~15 seconds the duck reloads with
what it just learned, so you watch it get better in real time. Drag the reward
sliders to change *what it is rewarded for* — that is the whole idea of
reinforcement learning, and here you can feel it.

### Film it 🎥
The **Capture** panel takes a PNG, or films a clip and converts it to mp4 + GIF.

---

## 🧪 For teachers and tinkerers

### See what brains are available

```bash
docker run --rm srayuth089/microduck-docker policies
```

### Start with specific brains

```bash
docker run --rm -p 63317:63317 -p 8788:8788 \
  -e DUCKS="BEST_alpha_walking ball_kick_left roulade" \
  srayuth089/microduck-docker
```

### Keep your training between runs

Add a volume so trained brains, videos and settings survive a restart:

```bash
docker run --rm -p 63317:63317 -p 8788:8788 \
  -v microduck-data:/data \
  srayuth089/microduck-docker
```

### Train a walking brain from scratch

A few minutes on a normal laptop CPU:

```bash
docker run --rm -v microduck-data:/data srayuth089/microduck-docker \
  train --envs 32 --steps 3000000 --run-name my-first-duck

docker run --rm -v microduck-data:/data srayuth089/microduck-docker \
  export /data/runs/my-first-duck
```

Then start the viewer with the same volume and your duck appears in the roster,
ready to race against the official one.

### All the commands

| Command | Does |
|---|---|
| `serve` *(default)* | start simulator + viewer |
| `policies` | list available brains |
| `version` | show exact upstream code this image was built from |
| `train …` | train a walking policy (`train-walk`) |
| `behavior …` | train a trick (`train-behavior`) |
| `export …` | export a run to ONNX |
| `eval …` | score a policy (falls, tracking) |
| `render …` | render a rollout to mp4 |
| `bench …` | find the best worker count for your machine |
| `shell` | a shell inside the image |

Full details: **[docs/USER-MANUAL.md](docs/USER-MANUAL.md)**

---

## ❓ Troubleshooting

**The page is blank / "can't connect"**
Both ports matter. `-p 63317:63317` serves the page; `-p 8788:8788` carries the
physics. Use `http://localhost:...`, not the `127.0.0.1` shown by other tools
and not your LAN IP — the lab only trusts `localhost` origins.

**"port is already allocated"**
Something else is using the port. Move it: `-p 8080:63317` then browse to
`localhost:8080`.

**It's slow / the fan is loud**
Physics is real work. Give Docker Desktop more CPUs in *Settings → Resources*,
or run fewer ducks with `-e DUCKS="BEST_alpha_walking"`.

**Apple Silicon warning about platform**
Harmless if it appears — native `arm64` is published. Force it with
`--platform linux/arm64`.

---

## 🏗️ How this is built

This repo contains no robot code of its own. On a schedule, GitHub Actions
**pulls the newest upstream code**, builds it for every architecture, smoke-tests
that the physics really runs, and pushes to Docker Hub. So the image tracks the
official projects instead of drifting away from them.

```
microduck-lab  (trainer + viewer)  ─┐
microduck_rl   (robot model, MJCF) ─┼─► GitHub Actions ─► Docker Hub (multi-arch)
MicroDuckModels (pretrained ONNX)  ─┘
```

Every image records the exact commits it came from:

```bash
docker run --rm srayuth089/microduck-docker version
```

Architectures: `linux/amd64`, `linux/arm64` (and `ppc64le`, `s390x` on request).

Build it yourself: **[docs/BUILD.md](docs/BUILD.md)**

---

## 🙏 Credits

This is a **packaging project**. All the hard work belongs to:

- **[Pollen Robotics](https://pollen-robotics.com)** — Microduck itself, and
  [`microduck_rl`](https://github.com/pollen-robotics/microduck_rl) (Apache-2.0)
- **[Jonathan Hawkins](https://github.com/jonathanhawkins/microduck-lab)** —
  `microduck-lab`, the CPU trainer and viewer that make this run on a laptop (Apache-2.0)
- **[IronSpiderMan](https://github.com/IronSpiderMan/MicroDuckModels)** — the
  collected pretrained policies

Not affiliated with or endorsed by Pollen Robotics.

## 📄 License

Packaging (this repo): **Apache-2.0**.

The image also contains upstream material under its own terms — notably the 3D
robot meshes, which Pollen releases under **Creative Commons BY-SA-NC**
(**non-commercial**). Play with it, teach with it, learn from it. Do not sell it
or ship it in a commercial product. See [NOTICE](NOTICE).

---

<p align="center">
  <i>Made for classrooms, kitchen tables and anyone curious about robots.</i>
</p>

<p align="center">
  <a href="https://www.buymeacoffee.com/srayuth" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" height="60" width="217"></a>
</p>

<p align="center">
  <a href="https://devos.bluweo.com/projects">More projects by srayuth →</a>
</p>
