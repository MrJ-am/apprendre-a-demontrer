import { execFileSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  readdirSync,
  writeFileSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { preparerStyle, dossierStyle } from "./preparer-style.mjs";

const { verrou, identite } = preparerStyle();
// Éviter qu'une ressource ancienne survive à la reconstruction d'un artefact.
rmSync("dist", { recursive: true, force: true });

mkdirSync("dist", { recursive: true });
execFileSync(
  "node_modules/.bin/elm",
  ["make", "src/Main.elm", "--optimize", "--output=dist/app.js"],
  { stdio: "inherit" },
);
for (const name of readdirSync("public"))
  cpSync(join("public", name), join("dist", name), { recursive: true });
cpSync(join(dossierStyle, "public/assets/mrjam"), "dist/assets/mrjam", {
  recursive: true,
});
mkdirSync("dist/katex", { recursive: true });
for (const name of ["katex.min.js", "katex.min.css", "fonts"])
  cpSync(join("node_modules/katex/dist", name), join("dist/katex", name), {
    recursive: true,
  });
cpSync("node_modules/katex/LICENSE", "dist/katex/LICENSE");
mkdirSync("dist/vimeo", { recursive: true });
cpSync(
  "node_modules/@vimeo/player/dist/player.min.js",
  "dist/vimeo/player.min.js",
);
cpSync("node_modules/@vimeo/player/LICENSE.md", "dist/vimeo/LICENSE.md");
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

const empreintes = (repertoire) =>
  Object.fromEntries(
    readdirSync(repertoire, { withFileTypes: true }).flatMap((entree) => {
      const chemin = join(repertoire, entree.name);
      return entree.isDirectory()
        ? Object.entries(empreintes(chemin))
        : [
            [
              chemin.slice(5),
              createHash("sha256").update(readFileSync(chemin)).digest("hex"),
            ],
          ];
    }),
  );
writeFileSync(
  "dist/manifeste-preparation.json",
  JSON.stringify(
    {
      application: process.env.GITHUB_SHA ?? null,
      style: verrou.revision,
      signature: identite.revision,
      portageComplet: true,
      typographieValidee: false,
      hebergementConfirme: false,
      publicationAutorisee: false,
      empreintes: empreintes("dist"),
    },
    null,
    2,
  ) + "\n",
);
