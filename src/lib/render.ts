import { chromium, type Browser } from "playwright";

import { config, outputSize } from "./config";

let browserPromise: Promise<Browser> | null = null;

const getBrowser = async () => {
  if (!browserPromise) {
    browserPromise = chromium
      .launch({
        // Required in the container: no user namespaces, and /dev/shm is small
        args: ["--no-sandbox", "--disable-dev-shm-usage"],
      })
      .then((browser) => {
        // A crashed browser must not poison every later render
        browser.on("disconnected", () => {
          browserPromise = null;
        });
        return browser;
      })
      .catch((error: unknown) => {
        browserPromise = null;
        throw error;
      });
  }

  return browserPromise;
};

export const renderDash = async (path = "/") => {
  const browser = await getBrowser();
  const context = await browser.newContext({
    viewport: outputSize,
    deviceScaleFactor: 1,
    colorScheme: "light",
    reducedMotion: "reduce",
  });

  try {
    const page = await context.newPage();
    await page.goto(`${config.internalUrl}${path}`, { waitUntil: "networkidle", timeout: 30_000 });
    await page.emulateMedia({ media: "screen" });
    return await page.screenshot({ type: "png" });
  } finally {
    await context.close();
  }
};

export const closeBrowser = async () => {
  const browser = await browserPromise?.catch(() => null);
  browserPromise = null;
  await browser?.close();
};
