import { config, isDev, renderRotation } from "~/lib/config";

// The rendered time must be the time of the render, never a build-time value
export const dynamic = "force-dynamic";

const format = (date: Date, options: Intl.DateTimeFormatOptions) =>
  new Intl.DateTimeFormat("en-GB", { timeZone: config.timezone, ...options }).format(date);

const DashboardPage = () => {
  const now = new Date();

  return (
    <div
      className={
        isDev
          ? "flex min-h-screen w-full items-center justify-center bg-gray-light"
          : "flex h-screen w-screen items-center justify-center overflow-hidden"
      }
    >
      <main
        className="flex shrink-0 flex-col items-center justify-center gap-8 bg-white text-black"
        style={{
          width: config.screen.width,
          height: config.screen.height,
          // Rotating around the centre makes the landscape box fill the portrait panel exactly
          transform: renderRotation ? `rotate(${renderRotation}deg)` : undefined,
          // Outline instead of border, so the dev preview is not 1px off the real render
          ...(isDev && { outline: "1px solid var(--color-black)" }),
        }}
      >
        <h1 className="text-4xl font-semibold tracking-tight">Hello World</h1>

        <p className="text-8xl font-semibold tabular-nums leading-none">
          {format(now, { hour: "2-digit", minute: "2-digit", hour12: false })}
        </p>

        <p className="text-2xl">
          {format(now, { weekday: "long", day: "numeric", month: "long", year: "numeric" })}
        </p>

        <p className="text-base text-gray">
          rendered at{" "}
          {format(now, { hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false })}
        </p>

        <p className="text-base text-gray">
          {config.screen.width}x{config.screen.height} &middot; {config.timezone}
        </p>
      </main>
    </div>
  );
};

export default DashboardPage;
