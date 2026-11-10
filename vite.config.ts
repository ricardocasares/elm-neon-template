import elm from "vite-plugin-elm";
import css from "@tailwindcss/vite";
import { defineConfig } from "vite";
import { api } from "./api/_ts/dev.ts";

export default defineConfig({
  plugins: [css(), elm(), api()],
  // The browser app, which Vercel serves as static files (vercel.json outputDirectory).
  build: { outDir: "dist/client" },
  environments: {
    ssr: {
      build: {
        // Not under dist/client, so the server bundle is never served publicly.
        outDir: "dist/server",
        target: "esnext",
        rollupOptions: {
          input: { app: "api/_ts/app.ts" },
        },
      },
    },
  },
  builder: {
    async buildApp(builder) {
      await builder.build(builder.environments.ssr);
      await builder.build(builder.environments.client);
    },
  },
});
