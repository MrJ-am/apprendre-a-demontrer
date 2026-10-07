import { execFileSync } from "node:child_process";
import { mkdtempSync, cpSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";
import { preparerStyle, dossierStyle } from "./preparer-style.mjs";
preparerStyle();
const temp = mkdtempSync(join(tmpdir(), "atelier-tests-"));
try {
  cpSync("elm.json", join(temp, "elm.json"));
  cpSync("src", join(temp, "src"), { recursive: true });
  cpSync(join(dossierStyle, "src"), join(temp, ".cache/style-mrjam/src"), {
    recursive: true,
  });
  cpSync("tests/AtelierCheck.elm", join(temp, "src/AtelierCheck.elm"));
  cpSync("tests/AtelierRegles.elm", join(temp, "src/AtelierRegles.elm"));
  execFileSync(
    resolve("node_modules/.bin/elm"),
    ["make", "src/AtelierCheck.elm", "--output=check.js"],
    { cwd: temp, stdio: "inherit" },
  );
  const sandbox = { setTimeout, clearTimeout, console };
  vm.createContext(sandbox);
  vm.runInContext(readFileSync(join(temp, "check.js"), "utf8"), sandbox);
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("Tests Elm sans réponse.")),
      10000,
    );
    sandbox.Elm.AtelierCheck.init({ flags: null }).ports.finished.subscribe(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
    );
  });
  const echecs = result.filter((t) => !t.passe);
  assert.equal(echecs.length, 0, JSON.stringify(echecs, null, 2));
  console.log(`${result.length} contrôles du noyau et des théorèmes réussis.`);
} finally {
  rmSync(temp, { recursive: true, force: true });
}
