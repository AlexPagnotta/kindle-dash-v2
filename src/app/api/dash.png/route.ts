import { getDash } from "~/lib/cache";

export const dynamic = "force-dynamic";

export const GET = async (request: Request) => {
  const force = new URL(request.url).searchParams.get("force") === "1";

  try {
    const { png, renderedAt, fresh } = await getDash({ force });

    return new Response(new Uint8Array(png), {
      headers: {
        "Content-Type": "image/png",
        "Cache-Control": "no-store",
        "X-Rendered-At": renderedAt.toISOString(),
        "X-Cache": fresh ? "fresh" : "stale",
      },
    });
  } catch (error) {
    console.error("[dash.png] render failed", error);
    return new Response("render failed", { status: 503 });
  }
};
