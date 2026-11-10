import "./xhr";
import { Elm, type JsonValue } from "../src/Main.elm";

//-- RESOLVERS

type Resolve = (response: Response) => void;
const toResolver = (resolve: Resolve) => resolve as unknown as JsonValue;
const fromResolver = (resolver: JsonValue) => resolver as unknown as Resolve;

//-- INIT

const app = Elm.Main.init({
  flags: {
    databaseUrl: process.env.DATABASE_URL ?? null,
    neonEndpoint: process.env.NEON_ENDPOINT ?? null,
  },
});

//-- PORTS:SUBSCRIBE

app.ports.interopFromElm.subscribe((fromElm) => {
  switch (fromElm.tag) {
    case "Respond":
      return fromResolver(fromElm.resolve)(
        new Response(fromElm.body, {
          status: fromElm.status,
          headers: fromElm.headers,
        }),
      );

    case "Log":
      return console.error(`[elm] ${fromElm.message}`);
  }
});

//-- HANDLER

export async function handle(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const request = {
    method: req.method,
    path: url.pathname.split("/").filter(Boolean).map(decodeURIComponent),
    query: Object.fromEntries(url.searchParams),
    headers: Object.fromEntries(req.headers),
    body: await req.text(),
  };

  return new Promise<Response>((resolve) =>
    app.ports.interopToElm.send({
      tag: "Request",
      resolve: toResolver(resolve),
      request,
    }),
  );
}
