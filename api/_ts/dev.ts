import { existsSync } from "node:fs";
import type { IncomingMessage, ServerResponse } from "node:http";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { createServerModuleRunner, type Plugin, type ViteDevServer } from "vite";
import type * as App from "./app.ts";

type Middlewares = ViteDevServer["middlewares"];

export function api(): Plugin {
  return {
    name: "app:api",
    apply: "serve",

    configureServer(vite) {
      let current = load(vite);
      current.catch(console.error);

      let debounce: ReturnType<typeof setTimeout> | undefined;
      const watched = [`${vite.config.root}/api/`, `${vite.config.root}/shared/`];

      vite.watcher.on("all", (_event, file) => {
        if (!watched.some((dir) => file.startsWith(dir))) return;
        if (!/\.(elm|ts)$/.test(file) || file.endsWith(".d.ts")) return;
        clearTimeout(debounce);
        debounce = setTimeout(() => {
          const previous = current;
          current = load(vite);
          current.then(
            () => vite.config.logger.info("Elm server restarted.", { timestamp: true }),
            (error) => vite.config.logger.error(String(error), { timestamp: true }),
          );
          previous.then(
            ({ runner }) => runner.close(),
            () => {},
          );
        }, 100);
      });

      serve(vite.middlewares, async () => (await current).app);
    },

    configurePreviewServer(preview) {
      const built = resolve(
        preview.config.root,
        preview.config.environments.ssr!.build.outDir,
        "app.js",
      );
      if (!existsSync(built)) {
        preview.config.logger.warn(`${built} is missing: run bun run build first.`);
      }
      const app = import(pathToFileURL(built).href) as Promise<typeof App>;
      app.catch(() => {});
      serve(preview.middlewares, () => app);
    },
  };
}

function serve(middlewares: Middlewares, app: () => Promise<typeof App>) {
  middlewares.use(async (req, res, next) => {
    if (!/^\/api(\/|\?|$)/.test(req.url ?? "")) return next();
    try {
      const { handle } = await app();
      await send(res, await handle(await toRequest(req)));
    } catch (error) {
      res.statusCode = 500;
      res.end(String(error));
    }
  });
}

async function load(vite: ViteDevServer) {
  const runner = createServerModuleRunner(vite.environments.ssr, { hmr: false });
  try {
    const app: typeof App = await runner.import("/api/_ts/app.ts");
    return { runner, app };
  } catch (error) {
    await runner.close();
    throw error;
  }
}

async function toRequest(req: IncomingMessage): Promise<Request> {
  const headers = new Headers();
  for (const [name, value] of Object.entries(req.headers)) {
    for (const v of [value ?? []].flat()) headers.append(name, v);
  }
  const chunks: Uint8Array[] = [];
  for await (const chunk of req) chunks.push(chunk as Uint8Array);
  const hasBody = req.method !== "GET" && req.method !== "HEAD";
  return new Request(`http://${req.headers.host ?? "localhost"}${req.url ?? "/"}`, {
    method: req.method,
    headers,
    body: hasBody ? Buffer.concat(chunks) : undefined,
  });
}

async function send(res: ServerResponse, response: Response) {
  res.statusCode = response.status;
  response.headers.forEach((value, name) => res.setHeader(name, value));
  res.end(Buffer.from(await response.arrayBuffer()));
}
