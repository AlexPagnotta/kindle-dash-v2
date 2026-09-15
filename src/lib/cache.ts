import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";

import { config } from "./config";
import { renderDash } from "./render";

type Cached = { png: Buffer; renderedAt: Date; fresh: boolean };

const file = path.join(config.cacheDir, "dash.png");

let inFlight: Promise<Cached> | null = null;

const readCache = async (): Promise<Cached | null> => {
  try {
    const [png, meta] = await Promise.all([readFile(file), stat(file)]);
    return { png, renderedAt: meta.mtime, fresh: Date.now() - meta.mtimeMs < config.ttlMs };
  } catch {
    return null;
  }
};

const render = async (): Promise<Cached> => {
  const png = await renderDash();

  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, png);

  return { png, renderedAt: new Date(), fresh: true };
};

/**
 * Returns the cached PNG when it is still fresh, otherwise renders a new one.
 * Concurrent callers share a single render.
 */
export const getDash = async ({ force = false } = {}): Promise<Cached> => {
  if (!force) {
    const cached = await readCache();
    if (cached?.fresh) return cached;
  }

  if (inFlight) return inFlight;

  const job = render().finally(() => {
    inFlight = null;
  });
  inFlight = job;

  try {
    return await job;
  } catch (error) {
    // A stale image on the Kindle beats a blank screen
    const stale = await readCache();
    if (stale) return stale;
    throw error;
  }
};
