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
deploy/             ZimaOS compose file, init.sh and update.sh
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
| `docker compose up -d --build` | Build and run the container (non-ZimaOS hosts) |
| `docker compose logs -f` | Follow logs, including each prerender |
| `docker compose down` | Stop it |
| `ssh <box> /DATA/AppData/kindle-dash/deploy/init.sh` | One-time ZimaOS setup: registry, build, publish |
| `ssh <box> /DATA/AppData/kindle-dash/deploy/update.sh` | Rebuild on the box and restart the ZimaOS app |
| `./device/install.sh <kindle-ip>` | Push the device side to the Kindle over SSH |

## Deploy

The server runs as a Docker container, built on the box itself so nothing leaves the LAN. The image
is ~2.5GB, mostly Chromium, and the build needs ~2GB of free RAM.

### Server: first install on ZimaOS

ZimaOS runs apps as containers but its UI cannot build images, and it always runs `docker compose
pull` before starting an app. So the image is built over SSH and published to a small registry on the
box, which gives the UI something to pull from. Everything below runs once.

1. **Clone the repo** somewhere persistent. `/DATA/AppData` is where ZimaOS keeps app data:

   ```sh
   ssh <box> 'git clone https://github.com/AlexPagnotta/kindle-dash-v2.git /DATA/AppData/kindle-dash'
   ```

2. **Run the init script**. It is idempotent, so it is safe to re-run:

   ```sh
   ssh <box> /DATA/AppData/kindle-dash/deploy/init.sh
   ```

   It starts the registry, then builds and publishes the image to
   `localhost:5000/kindle-dash:latest`. Check it landed with
   `curl http://<box-ip>:5000/v2/kindle-dash/tags/list`.

   Two ZimaOS quirks it handles for you. `$HOME` is `/DATA`, which is root-owned, so the Docker CLI
   cannot read its config and its plugins (`build`, `compose`) refuse to load with errors like
   `unknown shorthand flag: 't' in -t`: every command sets `DOCKER_CONFIG` to a writable directory
   instead. And Docker allows plain HTTP for `localhost`, so the registry needs no certificates.

3. **Install the app** in the ZimaOS UI: Apps -> "+" -> Install a customized app, and import
   `/DATA/AppData/kindle-dash/deploy/zimaos.compose.yml`. Settings such as the timezone, the panel
   size and `DASH_ROTATE` are inline in that file, so edit it before importing or change them in the
   UI afterwards.

4. **Verify** from another machine on the LAN:

   ```sh
   curl -o dash.png http://<box-ip>:3000/api/dash.png
   ```

   Expect a 600x800 PNG holding the landscape dashboard rotated onto its side.

Give the box a DHCP reservation. The Kindle has no mDNS resolver, so the device config needs an IP,
not a `.local` name, and plain HTTP: the Kindle's CA bundle is too old to be worth fighting.

### Server: updating

```sh
ssh <box> /DATA/AppData/kindle-dash/deploy/update.sh
```

That pulls the repo, rebuilds, publishes, and recreates the container from the compose file ZimaOS
stores for the app, so the UI stays in sync. It finds that file through the container's own labels,
because the UI names the compose project itself (something like `quizzical_eleanor`) rather than
using the name in the file. Those files are also root-only and `sudo` needs a password, so the script
reads it through a throwaway container.

The image is tagged twice, `localhost:5000/kindle-dash:latest` and `kindle-dash:local`, so the
rebuild lands whichever of the two the installed app happens to reference.

Rebuilding on its own changes nothing for the running app: the container keeps the old image until it
is recreated, so `docker restart` is not enough. That is what the `--force-recreate` in the script is
for.

The app survives reboots: `restart: unless-stopped` brings it back with the Docker daemon. Only the
cached PNG is lost, and the prerender job rebuilds it a few seconds after start.

### Server: any other Docker host

No registry and no UI needed, `docker-compose.yml` in the repo root builds and runs it directly:

```sh
git clone https://github.com/AlexPagnotta/kindle-dash-v2.git kindle-dash && cd kindle-dash
cp .env.example .env   # set DASH_TZ, SCREEN_WIDTH/HEIGHT, DASH_ROTATE, DASH_PORT
docker compose up -d --build
```

Updating: `git pull && docker compose up -d --build`.

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
