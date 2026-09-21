"""Verrou exact, contrats immuables et refus d'un cache commun altéré."""
import hashlib
import json
import subprocess
import unittest
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]


class StyleCommun(unittest.TestCase):
    def test_revision_exacte(self):
        verrou = json.loads((RACINE / "style-mrjam.json").read_text())
        self.assertEqual(verrou["revision"], "52ad33f881b50feef91d60915d17bae90abfc592")
        self.assertEqual(verrou["elm-ui"], "1.1.8")

    def test_contrats_preserves(self):
        contrats = json.loads((RACINE / "tests/contrats-reference.json").read_text())
        for chemin, attendu in contrats["fichiers"].items():
            with self.subTest(chemin=chemin):
                contenu = (RACINE / chemin).read_bytes()
                obtenu = hashlib.sha1(b"blob " + str(len(contenu)).encode() + b"\0" + contenu).hexdigest()
                self.assertEqual(obtenu, attendu)

    def test_pas_de_theme_local(self):
        self.assertNotIn("import MrJam.Theme", (RACINE / "src/Main.elm").read_text())
        css = (RACINE / "public/style.css").read_text()
        for selecteur in [".topbar", ".catalog-track", ".lesson-content", ".site-footer"]:
            self.assertNotIn(selecteur, css)

    def controle_cache(self):
        return subprocess.run(["node", "--input-type=module", "-e", "import { preparerStyle } from './scripts/preparer-style.mjs'; preparerStyle();"], cwd=RACINE, capture_output=True, text=True)

    def test_cache_modifie_refuse(self):
        fichier = RACINE / ".cache/style-mrjam/src/MrJam.elm"
        original = fichier.read_bytes()
        try:
            fichier.write_bytes(original + b"\n-- modification interdite\n")
            resultat = self.controle_cache()
            self.assertNotEqual(resultat.returncode, 0)
            self.assertIn("Source commune modifiée", resultat.stderr)
        finally:
            fichier.write_bytes(original)
        self.assertEqual(self.controle_cache().returncode, 0)

    def test_module_supplementaire_refuse(self):
        fichier = RACINE / ".cache/style-mrjam/src/Intrus.elm"
        self.assertFalse(fichier.exists())
        try:
            fichier.write_text("module Intrus exposing (valeur)\nvaleur = 1\n")
            resultat = self.controle_cache()
            self.assertNotEqual(resultat.returncode, 0)
            self.assertIn("modules communs non verrouillés", resultat.stderr)
        finally:
            fichier.unlink()
        self.assertEqual(self.controle_cache().returncode, 0)
