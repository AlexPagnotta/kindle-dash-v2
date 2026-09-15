import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Keeps the runtime image small: only the server and its traced deps are copied
  output: "standalone",
  // Playwright must not be bundled, it resolves browsers from the filesystem
  serverExternalPackages: ["playwright", "playwright-core"],
};

export default nextConfig;
