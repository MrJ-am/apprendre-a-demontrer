import { execFileSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  readdirSync,
  writeFileSync,
  readFileSync,
} from "node:fs";
import { join } from "node:path";

mkdirSync("dist", { recursive: true });
execFileSync(
  "node_modules/.bin/elm",
  ["make", "src/Main.elm", "--optimize", "--output=dist/app.js"],
  { stdio: "inherit" },
);
for (const name of readdirSync("public"))
  cpSync(join("public", name), join("dist", name), { recursive: true });
mkdirSync("dist/katex", { recursive: true });
for (const name of ["katex.min.js", "katex.min.css", "fonts"])
  cpSync(join("node_modules/katex/dist", name), join("dist/katex", name), {
    recursive: true,
  });
cpSync("node_modules/katex/LICENSE", "dist/katex/LICENSE");
const course = JSON.parse(readFileSync("data/course.json", "utf8"));
writeFileSync(
  "dist/course.js",
  "window.courseData = " +
    JSON.stringify(course).replaceAll("<", "\\u003c") +
    ";\n",
);
console.log(
  `Site construit : ${course.tracks.length} parcours, ${course.tracks.flatMap((t) => t.lessons).length} leçons.`,
);
