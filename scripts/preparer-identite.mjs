import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { preparerStyle } from "./preparer-style.mjs";

// Atelier complet, volontairement exclu des archives de préparation.
const destination = resolve(".cache/site-complet");
const cache = resolve(".cache/signature");
const { verrou, identite } = preparerStyle();
if (identite.depot !== "MrJ-am/Signature" || !/^[a-f0-9]{40}$/.test(identite.revision))
  throw new Error("La signature exige son dépôt autorisé et une révision exacte.");
const sources = ["web/EchoPoint.woff2", "web/MrJamSignature.woff2"];
if (JSON.stringify(Object.keys(identite.ressources_externes).sort()) !== JSON.stringify(sources))
  throw new Error("La liste des polices autorisées a changé.");
if (!existsSync(join(cache, "web"))) {
  mkdirSync(cache, { recursive: true });
  const git = (...argumentsGit) => execFileSync("git", ["-C", cache, ...argumentsGit], { stdio: "pipe" });
  git("init");
  git("fetch", "--depth=1", `https://github.com/${identite.depot}.git`, identite.revision);
  if (git("rev-parse", "FETCH_HEAD").toString().trim() !== identite.revision)
    throw new Error("La révision de Signature diffère du verrou.");
  git("checkout", "--detach", "FETCH_HEAD");
}
const polices = sources.map((source) => {
  const contenu = readFileSync(join(cache, source));
  const empreinte = createHash("sha1").update(`blob ${contenu.length}\0`).update(contenu).digest("hex");
  if (empreinte !== identite.ressources_externes[source])
    throw new Error(`Police originale modifiée : ${source}`);
  return { nom: source.slice(4), contenu };
});
// Licence des fontes dérivées, issue de la même révision de Signature.
const licence = readFileSync(join(cache, "fonts/Parisienne-OFL.txt"));
if (createHash("sha1").update(`blob ${licence.length}\0`).update(licence).digest("hex") !==
    "6f4c72d06b5ff3cb1ad98b0f4b5147e90d638c5f")
  throw new Error("La licence originale des fontes a changé.");

function empreintes(racine, repertoire = racine) {
  return Object.fromEntries(readdirSync(repertoire, { withFileTypes: true }).flatMap((entree) => {
    const chemin = join(repertoire, entree.name);
    if (entree.isSymbolicLink()) throw new Error(`Lien interdit : ${chemin}`);
    if (entree.isDirectory()) return Object.entries(empreintes(racine, chemin));
    return [[relative(racine, chemin), createHash("sha256").update(readFileSync(chemin)).digest("hex")]];
  }));
}
const manifeste = JSON.parse(readFileSync("dist/manifeste-preparation.json", "utf8"));
if (manifeste.style !== verrou.revision || manifeste.signature !== identite.revision || !manifeste.portageComplet)
  throw new Error("Le site construit ne correspond pas aux sources verrouillées.");
const actuelles = empreintes("dist");
delete actuelles["manifeste-preparation.json"];
if (Object.keys(actuelles).length !== Object.keys(manifeste.empreintes).length ||
    Object.entries(actuelles).some(([nom, empreinte]) => manifeste.empreintes[nom] !== empreinte))
  throw new Error("L'artefact de préparation a changé depuis sa construction.");
for (const [nom, source] of Object.entries(identite.fichiers)) {
  if (actuelles[`assets/mrjam/${nom}`] !== source.sha256)
    throw new Error(`Ressource d'identité inattendue : ${nom}`);
}
rmSync(destination, { recursive: true, force: true });
cpSync("dist", destination, { recursive: true });
for (const { nom, contenu } of polices) writeFileSync(join(destination, "assets/mrjam", nom), contenu);
writeFileSync(join(destination, "assets/mrjam/Parisienne-OFL.txt"), licence);
rmSync(join(destination, "manifeste-preparation.json"));
writeFileSync(join(destination, "manifeste-preparation.json"), JSON.stringify({
  ...manifeste,
  typographieValidee: false,
  hebergementConfirme: false,
  publicationAutorisee: false,
  empreintes: empreintes(destination),
}, null, 2) + "\n");
console.log("Site complet préparé dans .cache/site-complet ; validation navigateur encore requise.");
