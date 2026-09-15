import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { watch } from "node:fs";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { resolve, extname, sep } from "node:path";
const exec = promisify(execFile);
const root = resolve("dist");
const port = Number(process.env.PORT || 4173);
const clients = new Set();
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2",
  ".woff": "font/woff",
  ".ttf": "font/ttf",
};
let building = false;
let again = false;
let timer;
async function build() {
  if (building) {
    again = true;
    return;
  }
  building = true;
  try {
    const { stdout } = await exec("npm", ["run", "build"], {
      maxBuffer: 8 * 1024 * 1024,
    });
    process.stdout.write(stdout);
    for (const client of clients) client.write("data: reload\n\n");
  } catch (error) {
    process.stderr.write(error.stdout || "");
    process.stderr.write(error.stderr || String(error));
  } finally {
    building = false;
    if (again) {
      again = false;
      void build();
    }
  }
}
await build();
const server = createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname === "/__updates") {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    res.write(": connected\n\n");
    clients.add(res);
    req.on("close", () => clients.delete(res));
    return;
  }
  try {
    const path = resolve(
      root,
      "." +
        decodeURIComponent(url.pathname === "/" ? "/index.html" : url.pathname),
    );
    if (!path.startsWith(root + sep)) {
      res.writeHead(403).end();
      return;
    }
    if (!(await stat(path)).isFile()) {
      res.writeHead(404).end();
      return;
    }
    const data = await readFile(path);
    const content =
      extname(path) === ".html"
        ? data
            .toString()
            .replace(
              "</body>",
              `<script>new EventSource('/__updates').onmessage=()=>location.reload()</script></body>`,
            )
        : data;
    res
      .writeHead(200, {
        "Content-Type": types[extname(path)] || "application/octet-stream",
        "Cache-Control": "no-store",
      })
      .end(content);
  } catch {
    res.writeHead(404).end("Introuvable");
  }
});
server.listen(port, "127.0.0.1", () =>
  console.log(`Parcours ouvert sur http://127.0.0.1:${port}`),
);
for (const dir of ["src", "cours", "public"])
  watch(dir, { recursive: true }, () => {
    clearTimeout(timer);
    timer = setTimeout(() => void build(), 180);
  });
