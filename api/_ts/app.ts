import "./xhr";
import { Elm, type JsonValue } from "../src/Main.elm";

//-- RESOLVERS

type Resolve = (response: Response) => void;
const toResolver = (resolve: Resolve) => resolve as unknown as JsonValue;
const fromResolver = (resolver: JsonValue) => resolver as unknown as Resolve;

//-- INIT

const local = process.env.VERCEL ? null : "local";

const commitUrl = () => {
  const {
    VERCEL_GIT_PROVIDER,
    VERCEL_GIT_REPO_OWNER,
    VERCEL_GIT_REPO_SLUG,
    VERCEL_GIT_COMMIT_SHA,
  } = process.env;
  return VERCEL_GIT_PROVIDER === "github" &&
    VERCEL_GIT_REPO_OWNER &&
    VERCEL_GIT_REPO_SLUG &&
    VERCEL_GIT_COMMIT_SHA
    ? `https://github.com/${VERCEL_GIT_REPO_OWNER}/${VERCEL_GIT_REPO_SLUG}/commit/${VERCEL_GIT_COMMIT_SHA}`
    : null;
};

const app = Elm.Main.init({
  flags: {
    databaseUrl: process.env.DATABASE_URL ?? null,
    neonEndpoint: process.env.NEON_ENDPOINT ?? null,
    releaseId: process.env.VERCEL_GIT_COMMIT_SHA || process.env.VERCEL_DEPLOYMENT_ID || local,
    releaseUrl: commitUrl(),
    region: process.env.VERCEL_REGION || local,
  },
});

//-- PORTS:SUBSCRIBE

app.ports.interopFromElm.subscribe((msg) => {
  switch (msg.tag) {
    case "Respond":
      return fromResolver(msg.resolve)(
        new Response(msg.body, {
          status: msg.status,
          headers: msg.headers,
        }),
      );

    case "Log":
      return console[msg.level](msg.message);

    default:
      return msg satisfies never;
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
