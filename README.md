# Kindle Dash v2

Turns a jailbroken Kindle into a desk dashboard, without booting Linux on it.

A Next.js app renders the dashboard, screenshots itself with Playwright, and serves the result as a PNG.
The Kindle runs a small shell script on its stock firmware: it wakes up, downloads that PNG, draws it
straight to the e-ink panel with [FBInk](https://github.com/NiLuJe/FBInk), and goes back to sleep.
No browser and no X server on the device, so it starts in seconds and sips battery.

Everything runs on the local network. There is no auth and nothing is exposed to the internet.

```
mini PC (Docker)                          Kindle (stock firmware)
┌────────────────────────┐                ┌──────────────────────┐
│ Next.js  /             │   GET          │ dash.sh loop         │
│ Playwright screenshot  │ ◀───────────── │  wifi on             │
│ cache   /api/dash.png  │ ──── PNG ────▶ │  fbink -g file=…     │
│ prerender every 5 min  │                │  suspend             │
└────────────────────────┘                └──────────────────────┘
```

## Getting started

Requires Node 22 and npm.

```sh
npm install
npx playwright install chromium   # local dev only, the image ships its own
cp .env.example .env
npm run dev
```

- `http://localhost:3000` is the dashboard, always drawn in a box of exactly `SCREEN_WIDTH` x
  `SCREEN_HEIGHT` (`800x600`, the Kindle sits in landscape). In dev the box gets an outline and a
  grey backdrop so the panel limits are visible, and it stays upright whatever `DASH_ROTATE` says.
  Both disappear in production, which is what the Kindle gets.
- `http://localhost:3000/api/dash.png` is what the Kindle fetches: the rendered PNG, cached for
  `DASH_TTL_MS`. Add `?force=1` to bypass the cache.

Config lives in `.env` (see `.env.example`): panel size, timezone, refresh interval, port.

### Project layout

```
src/app/            dashboard page + /api/dash.png + /api/health
src/lib/config.ts   env-driven config (panel size, timezone, cache)
src/lib/render.ts   Playwright browser singleton and screenshot
src/lib/cache.ts    on-disk PNG cache, concurrent renders deduped
src/instrumentation.ts  background prerender job (DASH_PRERENDER=1)
device/             what runs on the Kindle: dash.sh, KUAL extension, installer
```

## Useful commands

| Command | What it does |
| --- | --- |
| `npm run dev` | Dev server with HMR at `localhost:3000` |
| `npm run build` | Production build (standalone output) |
| `npm start` | Run the production build locally |
| `npm run lint` | Typecheck |
| `curl -o dash.png localhost:3000/api/dash.png?force=1` | Render and save a PNG to inspect |
| `docker compose up -d --build` | Build and run the container |
| `docker compose logs -f` | Follow logs, including each prerender |
| `docker compose down` | Stop it |
| `./device/install.sh <kindle-ip>` | Push the device side to the Kindle over SSH |

## Deploy

### Server (mini PC / ZimaOS)

Built on the box, nothing leaves the LAN.

1. Clone the repo on the machine and set the env:

   ```sh
   git clone <repo> kindle-dash && cd kindle-dash
   cp .env.example .env   # set DASH_TZ, SCREEN_WIDTH/HEIGHT, DASH_ROTATE, DASH_PORT
   ```

2. Start it:

   ```sh
   docker compose up -d --build
   ```

   First build takes a few minutes and needs ~2GB of free RAM. The image is ~1.5GB, mostly Chromium.

3. Check it from another machine on the LAN: `curl -o dash.png http://<mini-pc-ip>:3000/api/dash.png`

On ZimaOS the UI cannot build images and always pulls, so the image is served by a small registry
running on the box itself. Build and publish it over SSH, then import `deploy/zimaos.compose.yml`
through Apps -> "+" -> Install a customized app.

```sh
# once: a registry on the box, so the ZimaOS UI has something to pull from
ssh <box> 'DOCKER_CONFIG=/DATA/AppData/kindle-dash/.docker docker run -d --name registry \
  --restart unless-stopped -p 5000:5000 \
  -v /DATA/AppData/registry/data:/var/lib/registry registry:2'

# every time: build, publish, restart
ssh <box> /DATA/AppData/kindle-dash/deploy/update.sh
```

The `DOCKER_CONFIG` override is needed because ZimaOS points `$HOME` at a root-owned `/DATA`, which
stops the Docker CLI plugins (`build`, `compose`) from loading. `update.sh` sets it itself.

Rebuilding alone changes nothing for the running app: the container keeps the old image until it is
recreated, which is the `--force-recreate` at the end of `update.sh`. `docker restart` is not enough.

The app survives reboots: `restart: unless-stopped` brings it back with the Docker daemon. Only the
cached PNG is lost, and the prerender job rebuilds it a few seconds after start.

### Kindle

Needs a jailbroken device with KUAL and SSH access (USBNet or Wi-Fi).

1. Download the FBInk static binary for your device from the
   [releases](https://github.com/NiLuJe/FBInk/releases) and drop it in `device/` as `fbink`.
2. `cp device/dash.conf.example device/dash.conf` and set `DASH_URL` to
   `http://<mini-pc-ip>:3000/api/dash.png`.
3. `./device/install.sh <kindle-ip>` (defaults to `192.168.15.244`, the USBNet address). It copies
   `dash.sh`, `fbink` and `dash.conf` to `/mnt/us/kindle-dash/`, and the KUAL extension to
   `/mnt/us/extensions/`.
4. On the Kindle: KUAL -> Kindle Dash -> Start dashboard.

Logs land in `/mnt/us/kindle-dash/dash.log`, capped at 512KB.

#### Device settings (`device/dash.conf`)

| Setting | Default | Notes |
| --- | --- | --- |
| `DASH_URL` | - | Full URL of the PNG endpoint, by IP |
| `INTERVAL` | `300` | Seconds between refreshes |
| `FULL_REFRESH_EVERY` | `12` | Full flashing refresh every N cycles, clears ghosting |
| `SUSPEND` | `0` | `1` suspends between refreshes via RTC wake. Big battery win, turn it on once the loop is proven |
| `STOP_FRAMEWORK` | `0` | `1` stops the Kindle UI while the dashboard runs |

### Orientation

The panel size is a server setting, not a device one. The dashboard is designed in landscape
(`SCREEN_WIDTH=800`, `SCREEN_HEIGHT=600`) because the Kindle sits on its side, but the framebuffer
stays portrait whichever way the device is placed. So the render is rotated by `DASH_ROTATE` degrees
before it is served: the PNG the Kindle gets is 600x800, and it reads upright once the device is
turned. Set `DASH_ROTATE=270` if it comes out upside down, or `0` if you rotate the framebuffer on
the device instead.

Check what your Kindle reports with `cat /sys/class/graphics/fb0/virtual_size` and make sure the two
sizes match once swapped.

## Status

Scaffold. The dashboard is a Hello World with the current date and time plus a `rendered at` stamp,
which is there to make the refresh loop verifiable at a glance. Widgets come next.
