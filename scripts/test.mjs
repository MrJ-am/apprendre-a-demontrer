import { execFileSync } from "node:child_process";
import { readFileSync, mkdtempSync, cpSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, join } from "node:path";
import vm from "node:vm";
import katex from "katex";
import assert from "node:assert/strict";

execFileSync("python3", ["scripts/build_data.py", "--check"], {
  stdio: "inherit",
});
const course = JSON.parse(readFileSync("data/course.json", "utf8"));
const steps = course.tracks.flatMap((t) => t.lessons.flatMap((l) => l.steps));
const checks = [];
for (const step of steps) {
  for (const answer of step.answers)
    checks.push({
      name: `${step.id} accepte ${answer}`,
      stepId: step.id,
      answer,
      expected: true,
    });
  checks.push({
    name: `${step.id} rejette le blanc`,
    stepId: step.id,
    answer: "",
    expected: false,
  });
  if (step.kind === "choice") {
    for (const choice of step.choices.filter(
      (c) => !step.answers.includes(c.id),
    ))
      checks.push({
        name: `${step.id} rejette ${choice.id}`,
        stepId: step.id,
        answer: choice.id,
        expected: false,
      });
  }
}
const regressions = [
  ["negation-et", "¬B ∨ ¬A", true, "commutativité"],
  ["negation-et", "non B ou non A", true, "syntaxe française"],
  ["negation-et", "!B || !A", true, "syntaxe clavier"],
  ["negation-et", "\\neg B \\lor \\neg A", true, "syntaxe LaTeX"],
  ["negation-et", "¬A ∧ ¬B", false, "confusion De Morgan"],
  ["negation-et", "¬(A ∧ B)", false, "négation non propagée"],
  ["negation-et", "A ∨ B", false, "contre-exemple booléen"],
  [
    "negation-composee",
    "C ∨ (¬B ∧ ¬A)",
    true,
    "réordonnancement des conjonctions",
  ],
  ["negation-composee", "¬A ∧ (¬B ∨ C)", false, "parenthèses significatives"],
  ["implication-ou", "B ∨ ¬A", true, "équivalence propositionnelle"],
  ["implication-ou", "¬B ∨ A", false, "réciproque incorrecte"],
  ["implication-ou", "A → B", false, "implication encore présente"],
  ["implication-nier", "¬B ∧ A", true, "négation implication"],
  ["quant-non-tous", "∃t ¬P(t)", true, "renommage lié"],
  ["quant-non-tous", "∃t ¬P(x)", false, "variable libre au lieu du témoin"],
  ["quant-non-tous", "∀x ¬P(x)", false, "mauvais quantificateur"],
  ["quant-deux", "∃a ∀b ¬P(a,b)", true, "deux renommages liés"],
  ["quant-deux", "∀y ∃x ¬P(x,y)", false, "ordre des quantificateurs"],
  ["quant-deux", "∃x ∀x ¬P(x,x)", false, "capture de variable"],
  ["nommer-frais", "k", false, "nom déjà pris"],
  ["nommer-frais", "a", false, "autre nom déjà pris"],
  ["nommer-frais", "ℓ", true, "nom mathématique"],
  ["nommer-frais", "3", false, "un nom est une lettre"],
  ["deduction-identite", "B → B", false, "tautologie hors de la dérivation"],
  ["deduction-identite", "A ⇒ A", true, "flèche alternative"],
  ["tous-contre", "0.0", true, "écriture numérique alternative"],
  ["un-temoin", "0", false, "mauvais témoin"],
  ["negation-et", "¬(A ∧)", false, "formule incomplète"],
];
for (const [stepId, answer, expected, name] of regressions)
  checks.push({ stepId, answer, expected, name });
let mathCount = 0;
function inspectMath(value) {
  if (Array.isArray(value)) {
    value.forEach(inspectMath);
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value)) {
      if (key === "formula" && item) {
        katex.renderToString(item, {
          throwOnError: true,
          strict: "error",
          trust: false,
        });
        mathCount++;
      } else inspectMath(item);
    }
  } else if (typeof value === "string") {
    const parts = value.split("$");
    assert.equal(
      parts.length % 2,
      1,
      `Délimiteur mathématique non fermé : ${value}`,
    );
    for (let i = 1; i < parts.length; i += 2) {
      katex.renderToString(parts[i], {
        throwOnError: true,
        strict: "error",
        trust: false,
      });
      mathCount++;
    }
  }
}
inspectMath(course);
const temp = mkdtempSync(join(tmpdir(), "apprendre-tests-"));
try {
  cpSync("elm.json", join(temp, "elm.json"));
  cpSync("src", join(temp, "src"), { recursive: true });
  cpSync("tests/Check.elm", join(temp, "src/Check.elm"));
  execFileSync(
    resolve("node_modules/.bin/elm"),
    ["make", "src/Check.elm", "--output=check.js"],
    { cwd: temp, stdio: "inherit" },
  );
  const sandbox = { setTimeout, clearTimeout, console };
  vm.createContext(sandbox);
  vm.runInContext(readFileSync(join(temp, "check.js"), "utf8"), sandbox);
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("Le correcteur de test ne répond pas.")),
      10000,
    );
    const app = sandbox.Elm.Check.init({ flags: { course, checks } });
    app.ports.finished.subscribe((data) => {
      clearTimeout(timer);
      resolve(data);
    });
  });
  assert.ok(Array.isArray(result), JSON.stringify(result));
  const failures = result.filter((r) => !r.passed);
  assert.equal(failures.length, 0, JSON.stringify(failures, null, 2));
  console.log(
    `${result.length} vérifications du correcteur réussies ; ${mathCount} formules KaTeX valides.`,
  );
} finally {
  rmSync(temp, { recursive: true, force: true });
}

execFileSync(
  "python3",
  ["-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
  { stdio: "inherit" },
);
execFileSync(process.execPath, ["--check", "public/bridge.js"], {
  stdio: "inherit",
});
execFileSync(process.execPath, ["--check", "public/video.js"], {
  stdio: "inherit",
});
console.log("Données, formules, correcteur et syntaxe JavaScript vérifiés.");
