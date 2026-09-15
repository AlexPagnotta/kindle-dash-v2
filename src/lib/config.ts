const int = (value: string | undefined, fallback: number) => {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

const rotation = (value: string | undefined) => {
  const parsed = int(value, 90);
  return ([0, 90, 180, 270] as const).find((angle) => angle === parsed) ?? 90;
};

export const config = {
  /** Dashboard size, in physical pixels. The Kindle sits in landscape, so this is landscape. */
  screen: {
    width: int(process.env.SCREEN_WIDTH, 800),
    height: int(process.env.SCREEN_HEIGHT, 600),
  },
  /**
   * The panel's framebuffer stays portrait whichever way the device is placed, so the rendered PNG
   * is rotated to match. Use 270 if the dashboard comes out upside down, 0 if you rotate the
   * framebuffer on the device instead.
   */
  rotate: rotation(process.env.DASH_ROTATE),
  /** Timezone used by every date rendered on the dashboard. */
  timezone: process.env.DASH_TZ ?? process.env.TZ ?? "Europe/Rome",
  /** How long a rendered PNG stays valid, and how often the prerender job runs. */
  ttlMs: int(process.env.DASH_TTL_MS, 5 * 60 * 1000),
  /** Where rendered PNGs are cached. */
  cacheDir: process.env.DASH_CACHE_DIR ?? "/tmp/kindle-dash",
  /** The renderer screenshots the app through its own HTTP server. */
  internalUrl: process.env.DASH_INTERNAL_URL ?? `http://127.0.0.1:${process.env.PORT ?? 3000}`,
  /** Set to "1" to keep the cache warm in the background. */
  prerender: process.env.DASH_PRERENDER === "1",
};

export const isDev = process.env.NODE_ENV !== "production";

/** Rotation is a render concern: the browser preview always stays upright. */
export const renderRotation = isDev ? 0 : config.rotate;

/** Size of the image the Kindle receives, which is the dashboard turned on its side. */
export const outputSize =
  renderRotation % 180 === 0
    ? config.screen
    : { width: config.screen.height, height: config.screen.width };
