"""Vérifier les polices originales servies, leur géométrie et le copier-coller natif."""
from __future__ import annotations

import hashlib
import json
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread

from playwright.sync_api import expect, sync_playwright

RACINE = Path(__file__).resolve().parents[1]
SITE = RACINE / ".cache/site-complet"
SORTIE = RACINE / "controles-typographie"
POLICES = {
    "MrJamSignature.woff2": "1525a85c58cdea88dcb93e077c4da98d2af1ff70ae7e6710fdeda36e8af28604",
    "EchoPoint.woff2": "816109c8291b12a0b2a8f0f981cc260a074a55190d94df322b57196755caebda",
}


class Silencieux(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def empreintes():
    return {str(p.relative_to(SITE)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in SITE.rglob("*") if p.is_file() and p.name != "manifeste-preparation.json"}


def main():
    SORTIE.mkdir(exist_ok=True)
    manifeste_path = SITE / "manifeste-preparation.json"
    manifeste = json.loads(manifeste_path.read_text())
    # Une ancienne réussite ne doit pas survivre à une nouvelle tentative échouée.
    manifeste["typographieValidee"] = False
    manifeste_path.write_text(json.dumps(manifeste, indent=2, ensure_ascii=False) + "\n")
    (SORTIE / "bilan.json").unlink(missing_ok=True)
    assert empreintes() == manifeste["empreintes"], "Le candidat a changé"
    bilan = {"application": manifeste["application"], "style": manifeste["style"],
             "signature": manifeste["signature"], "polices": POLICES, "controles": []}
    with TemporaryDirectory(prefix="typographie-http-") as dossier:
        racine_http = Path(dossier)
        for ressource in SITE.iterdir():
            (racine_http / ressource.name).symlink_to(ressource, target_is_directory=ressource.is_dir())
        (racine_http / "cours").symlink_to(SITE, target_is_directory=True)
        serveur = ThreadingHTTPServer(("127.0.0.1", 0), partial(Silencieux, directory=dossier))
        Thread(target=serveur.serve_forever, daemon=True).start()
        try:
            with sync_playwright() as pilote:
                options = {"headless": True}
                if os.environ.get("CHROMIUM"):
                    options["executable_path"] = os.environ["CHROMIUM"]
                navigateur = pilote.chromium.launch(**options)
                contexte = navigateur.new_context(reduced_motion="reduce")
                contexte.route("https://**/*", lambda route: route.abort())
                page = contexte.new_page()
                erreurs = []
                page.on("pageerror", lambda erreur: erreurs.append(str(erreur)))
                adresse = f"http://127.0.0.1:{serveur.server_port}"
                cours = json.loads((RACINE / "data/course.json").read_text())
                parcours = cours["tracks"][0]
                lecon = parcours["lessons"][0]
                for prefixe in ("/", "/cours/"):
                    for largeur in (320, 390, 768, 1280):
                        page.set_viewport_size({"width": largeur, "height": 900})
                        page.goto(adresse + prefixe + f"#/{parcours['id']}/{lecon['id']}/1")
                        signature = page.locator(".mrjam")
                        expect(signature).to_have_text("MrJ.am")
                        expect(page.locator("#question-heading")).to_be_visible()
                        chargees = page.evaluate("""async () => {
                          const a = await document.fonts.load('28px MrJamSignature', 'MrJ.am');
                          const b = await document.fonts.load('28px EchoPoint', '.');
                          await document.fonts.ready;
                          return [a.length, b.length, a[0]?.status, b[0]?.status];
                        }""")
                        assert chargees == [1, 1, "loaded", "loaded"], chargees
                        for nom, sha in POLICES.items():
                            reponse = page.request.get(adresse + prefixe + "assets/mrjam/" + nom)
                            assert reponse.ok and hashlib.sha256(reponse.body()).hexdigest() == sha
                        mesures = signature.evaluate("""e => {
                          const s = getComputedStyle(e), r = e.getBoundingClientRect();
                          const textes=document.createTreeWalker(e,NodeFilter.SHOW_TEXT);
                          let noeuds=0; while(textes.nextNode()) noeuds++;
                          return {texte:e.textContent, noeuds,
                            police:s.fontFamily, taille:parseFloat(s.fontSize), largeur:r.width, hauteur:r.height,
                            avant:getComputedStyle(e,'::before').content, apres:getComputedStyle(e,'::after').content};
                        }""")
                        assert mesures["texte"] == "MrJ.am" and mesures["noeuds"] == 1, mesures
                        assert mesures["police"].split(",")[0].strip("\"'") == "MrJamSignature"
                        # geometry.json : largeur 3,04 em + marge de sélection 0,04 em.
                        # tools/build-web.py répartit cette somme entre les six avances.
                        assert abs(mesures["largeur"] - 3.08 * mesures["taille"]) < 0.1, mesures
                        assert abs(mesures["hauteur"] - 1.183 * mesures["taille"]) < 0.1, mesures
                        assert mesures["avant"] == mesures["apres"] == "none"
                        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth + 2")
                        signature.scroll_into_view_if_needed()
                        boite = signature.bounding_box()
                        page.mouse.move(boite["x"] - 1, boite["y"] + boite["height"] / 2)
                        page.mouse.down()
                        page.mouse.move(boite["x"] + boite["width"] + 1, boite["y"] + boite["height"] / 2, steps=20)
                        page.mouse.up()
                        assert page.evaluate("getSelection().toString()") == "MrJ.am"
                        page.keyboard.press("Control+c")
                        page.evaluate("""() => {
                          const e=document.createElement('textarea'); e.id='collage-test';
                          e.setAttribute('aria-label','Collage de contrôle');document.body.append(e);e.focus();
                        }""")
                        page.keyboard.press("Control+v")
                        expect(page.locator("#collage-test")).to_have_value("MrJ.am")
                        noeud = signature.evaluate_handle("e => document.createTreeWalker(e,NodeFilter.SHOW_TEXT).nextNode()")
                        for index, caractere in enumerate("MrJ.am"):
                            noeud.evaluate("""(n,i) => {const r=document.createRange();r.setStart(n,i);
                              r.setEnd(n,i+1);const s=getSelection();s.removeAllRanges();s.addRange(r)}""", index)
                            page.keyboard.press("Control+c")
                            page.locator("#collage-test").fill("")
                            page.keyboard.press("Control+v")
                            expect(page.locator("#collage-test")).to_have_value(caractere)
                        noeud.dispose()
                        page.locator("#collage-test").evaluate("e => e.remove()")
                        page.evaluate("getSelection().removeAllRanges()")
                        nom = f"{'racine' if prefixe == '/' else 'prefixe'}-{largeur}"
                        signature.screenshot(path=str(SORTIE / f"signature-{nom}.png"))
                        if prefixe == "/":
                            page.screenshot(path=str(SORTIE / f"page-{largeur}.png"), full_page=True)
                        bilan["controles"].append({"cas": nom, "mesures": mesures, "copierColler": "MrJ.am + 6 caractères"})
                assert not erreurs, erreurs
                navigateur.close()
        finally:
            serveur.shutdown()
            serveur.server_close()
    assert empreintes() == manifeste["empreintes"], "Le candidat a changé pendant les tests"
    manifeste["typographieValidee"] = True
    manifeste_path.write_text(json.dumps(manifeste, indent=2, ensure_ascii=False) + "\n")
    bilan.update(typographieValidee=True, hebergementConfirme=False, publicationAutorisee=False,
                 empreintes=manifeste["empreintes"])
    (SORTIE / "bilan.json").write_text(json.dumps(bilan, indent=2, ensure_ascii=False) + "\n")
    print("Typographie originale validée : 8 contextes HTTP, géométrie, sélection et copier-coller natif.")


if __name__ == "__main__":
    main()
