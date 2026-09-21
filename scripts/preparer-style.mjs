import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync } from "node:fs";
import { resolve, join } from "node:path";

export const dossierStyle = resolve(".cache/style-mrjam");

// Tous les modules compilables sont contrôlés, y compris dans un atelier sans Git.
// Le cache n'est ni une copie éditable ni une branche mobile de la bibliothèque.
export function preparerStyle() {
  const verrou = JSON.parse(readFileSync("style-mrjam.json", "utf8"));
  if (
    verrou.depot !== "MrJ-am/style-mrjam" ||
    !/^[a-f0-9]{40}$/.test(verrou.revision)
  )
    throw new Error(
      "Le style exige son dépôt autorisé et une révision Git complète.",
    );
  if (!existsSync(join(dossierStyle, "src"))) {
    mkdirSync(dossierStyle, { recursive: true });
    const git = (...argumentsGit) =>
      execFileSync("git", ["-C", dossierStyle, ...argumentsGit], {
        stdio: "pipe",
      });
    git("init");
    git(
      "fetch",
      "--depth=1",
      `https://github.com/${verrou.depot}.git`,
      verrou.revision,
    );
    if (git("rev-parse", "FETCH_HEAD").toString().trim() !== verrou.revision)
      throw new Error("La révision récupérée ne correspond pas au verrou.");
    git("checkout", "--detach", "FETCH_HEAD");
  }
  for (const [chemin, attendu] of Object.entries(verrou.fichiers)) {
    const contenu = readFileSync(join(dossierStyle, chemin));
    const empreinte = createHash("sha1")
      .update(`blob ${contenu.length}\0`)
      .update(contenu)
      .digest("hex");
    if (empreinte !== attendu)
      throw new Error(`Source commune modifiée : ${chemin}`);
  }
  const modules = (repertoire) =>
    readdirSync(join(dossierStyle, repertoire), { withFileTypes: true })
      .flatMap((entree) =>
        entree.isDirectory()
          ? modules(`${repertoire}/${entree.name}`)
          : [`${repertoire}/${entree.name}`],
      )
      .filter((chemin) => chemin.endsWith(".elm"));
  if (
    JSON.stringify(modules("src").sort()) !==
    JSON.stringify(
      Object.keys(verrou.fichiers)
        .filter((chemin) => chemin.endsWith(".elm"))
        .sort(),
    )
  )
    throw new Error(
      "Des modules communs non verrouillés ont été ajoutés au cache.",
    );
  const elm = JSON.parse(readFileSync("elm.json", "utf8"));
  if (elm.dependencies.direct["mdgriffith/elm-ui"] !== verrou["elm-ui"])
    throw new Error("La version ElmUI diffère du verrou commun.");
  const identite = JSON.parse(
    readFileSync(join(dossierStyle, "identite.json"), "utf8"),
  );
  for (const [nom, source] of Object.entries(identite.fichiers)) {
    const empreinte = createHash("sha256")
      .update(readFileSync(join(dossierStyle, "public/assets/mrjam", nom)))
      .digest("hex");
    if (empreinte !== source.sha256)
      throw new Error(`Ressource d’identité modifiée : ${nom}`);
  }
  return { verrou, identite };
}
