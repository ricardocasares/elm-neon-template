// Bun's globals (Bun.serve, process, Buffer) for the server's TypeScript, here instead of
// "types" in tsconfig.json: Vercel type-checks api/index.ts with that tsconfig and can't
// resolve "types": ["bun"].
/// <reference types="bun" />
