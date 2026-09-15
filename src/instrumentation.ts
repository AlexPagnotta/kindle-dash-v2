export const register = async () => {
  if (process.env.NEXT_RUNTIME !== "nodejs") return;

  const { config } = await import("./lib/config");
  if (!config.prerender) return;

  const { getDash } = await import("./lib/cache");

  const tick = async () => {
    try {
      const { renderedAt } = await getDash({ force: true });
      console.log(`[prerender] ${config.screen.width}x${config.screen.height} at ${renderedAt.toISOString()}`);
    } catch (error) {
      console.error("[prerender] failed", error);
    }
  };

  // The HTTP server must be accepting connections before we screenshot ourselves
  setTimeout(() => {
    void tick();
    setInterval(() => void tick(), config.ttlMs);
  }, 5_000);
};
