"""Contrôles HTTP de l'application ; services vidéo externes simulés explicitement."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread

from playwright.sync_api import expect, sync_playwright

RACINE = Path(__file__).resolve().parents[1]
SORTIE = RACINE / "controles-interface"
TRANSPARENT = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lXcAAAAASUVORK5CYII=")
AMORCE = """
window.outilsApprentissage = {};
Object.defineProperty(document, 'modelContext', { configurable: true, value: {
  registerTool(outil) { window.outilsApprentissage[outil.name] = outil; }
}});
window.lecteursSimules = [];
window.echecVideoSimule = false;
window.Vimeo = { Player: class {
  constructor(iframe) { this.iframe = iframe; this.evenements = {}; window.lecteursSimules.push(this); }
  on(nom, action) { this.evenements[nom] = action; }
  ready() { return window.echecVideoSimule ? Promise.reject(new Error('Erreur simulée')) : Promise.resolve(); }
  destroy() { this.detruit = true; return Promise.resolve(); }
}};
"""


class Silencieux(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def outil(page, nom, arguments=None):
    return page.evaluate("([nom, arguments]) => window.outilsApprentissage[nom].execute(arguments)", [nom, arguments or {}])


def etat(page):
    return outil(page, "read_learning_state")["current"]


def ouvrir(page, parcours, lecon, etape=None):
    arguments = {"trackId": parcours["id"], "lessonId": lecon["id"]}
    if etape is not None:
        arguments["step"] = etape
    resultat = outil(page, "open_learning_lesson", arguments)
    page.wait_for_function("document.activeElement.id === 'lesson-heading'")
    return resultat


def verifier_largeur(page):
    ecart = page.evaluate("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    if ecart > 2:
        page.screenshot(path=str(SORTIE / "debordement.png"), full_page=True)
        details = page.evaluate("""() => [...document.querySelectorAll('body *')].filter(e => e.getBoundingClientRect().right > innerWidth + 2).slice(0,10).map(e=>[e.tagName,e.className,e.getBoundingClientRect().right])""")
        raise AssertionError(f"Débordement horizontal de {ecart}px : {details}")


def verifier_saisie(page, etape, valeur):
    if etape["kind"] == "choice":
        page.locator(f'input[type="radio"][value="{valeur}"]').check()
    else:
        page.get_by_label("Votre réponse", exact=True).fill(valeur)
    page.get_by_role("button", name="Vérifier", exact=True).click()
    page.wait_for_function("document.activeElement.id === 'feedback'")


def main():
    SORTIE.mkdir(exist_ok=True)
    cours = json.loads((RACINE / "data/course.json").read_text())
    bilan = {"transport": "HTTP local", "video": "SDK, affiche et iframe externes simulés", "typographieSignatureValidee": False}
    erreurs = []
    requetes_video = []
    with TemporaryDirectory(prefix="parcours-http-") as dossier:
        # Même artefact servi à la racine et sous un préfixe réel, sans base réécrite.
        racine_http = Path(dossier)
        for ressource in (RACINE / "dist").iterdir():
            (racine_http / ressource.name).symlink_to(ressource, target_is_directory=ressource.is_dir())
        (racine_http / "cours").symlink_to(RACINE / "dist", target_is_directory=True)
        serveur = ThreadingHTTPServer(("127.0.0.1", 0), partial(Silencieux, directory=dossier))
        fil = Thread(target=serveur.serve_forever, daemon=True)
        fil.start()
        try:
            with sync_playwright() as pilote:
                options = {"headless": True}
                if os.environ.get("CHROMIUM"):
                    options["executable_path"] = os.environ["CHROMIUM"]
                navigateur = pilote.chromium.launch(**options)
                contexte = navigateur.new_context(viewport={"width": 390, "height": 844}, reduced_motion="reduce")
                contexte.add_init_script(AMORCE)

                def externe(route):
                    adresse = route.request.url
                    if adresse.startswith("https://player.vimeo.com/"):
                        requetes_video.append(adresse)
                        route.fulfill(status=200, content_type="text/html", body="<!doctype html><title>Lecteur simulé</title>")
                    elif "vimeocdn.com" in adresse:
                        route.fulfill(status=200, content_type="image/png", body=TRANSPARENT)
                    else:
                        route.abort()

                contexte.route("https://**/*", externe)
                page = contexte.new_page()
                page.on("pageerror", lambda erreur: erreurs.append(str(erreur)))
                adresse = f"http://127.0.0.1:{serveur.server_port}"
                page.goto(adresse + "/cours/#/parcours")
                page.wait_for_function("Object.keys(window.outilsApprentissage).length === 3")
                assert len(outil(page, "read_learning_state")["tracks"]) == 3
                expect(page.locator(".mrjam")).to_have_text("MrJ.am")
                texte = page.locator(".mrjam").evaluate("e => {const r=document.createRange();r.selectNodeContents(e);const s=getSelection();s.removeAllRanges();s.addRange(r);return s.toString()}")
                assert texte == "MrJ.am" and ord(texte[3]) == 46
                expect(page.get_by_text("Toute utilisation du logo et de la signature est strictement réservée.", exact=False)).to_be_visible()
                logo = page.request.get(adresse + "/cours/assets/mrjam/Echologo.svg")
                assert logo.ok and hashlib.sha256(logo.body()).hexdigest() == "ce9ff8bf622122aaec0b88a22b9633d1c09ef35b32b9f93289f17889d520a0b3"
                page.screenshot(path=str(SORTIE / "catalogue-390.png"), full_page=True)

                # Vérifier réellement les 58 interfaces, pas seulement appeler le correcteur.
                controles = 0
                formules = 0
                for parcours in cours["tracks"]:
                    for lecon in parcours["lessons"]:
                        for numero, etape in enumerate(lecon["steps"], 1):
                            courant = ouvrir(page, parcours, lecon, numero)
                            assert courant["stepId"] == etape["id"] and courant["kind"] == etape["kind"]
                            expect(page.get_by_role("button", name="Vérifier", exact=True)).to_be_disabled()
                            page.get_by_role("button", name="Un indice", exact=True).click()
                            expect(page.locator("#hint-content")).to_be_visible()
                            page.get_by_role("button", name="Masquer l’indice", exact=True).click()
                            expect(page.locator("#hint-content")).to_have_count(0)
                            mauvaises = [c["id"] for c in etape.get("choices", []) if c["id"] not in etape["answers"]]
                            verifier_saisie(page, etape, mauvaises[0] if mauvaises else "???")
                            assert etat(page)["correct"] is False
                            verifier_saisie(page, etape, etape["answers"][0])
                            assert etat(page)["correct"] is True
                            assert page.locator("math-tex .katex-error").count() == 0
                            formules += page.locator("math-tex .katex").count()
                            verifier_largeur(page)
                            controles += 1
                bilan.update(exercices=controles, rendusKaTeXObserves=formules)

                # Les résultats sont conservés entre les leçons et dans les bilans.
                for parcours in cours["tracks"]:
                    for lecon in parcours["lessons"]:
                        ouvrir(page, parcours, lecon, len(lecon["steps"]))
                        page.get_by_role("button", name="Faire le point", exact=True).click()
                        expect(page.locator("#lesson-heading")).to_contain_text("Ce qu’on vient de construire.")
                        assert etat(page)["page"] == "bilan"
                        page.get_by_role("button", name="Revoir la leçon", exact=True).click()
                        expect(page.locator("#question-heading")).to_be_visible()
                bilan["bilans"] = 12

                # Ouverture, position recommandée, reprise, destruction et repli du lecteur.
                for parcours in cours["tracks"]:
                    for lecon in parcours["lessons"]:
                        courant = ouvrir(page, parcours, lecon)
                        assert courant["page"] == "video"
                        video = lecon["video"]
                        if video["provider"] == "placeholder":
                            expect(page.get_by_text("VIDÉO À VENIR", exact=False)).to_be_visible()
                        elif video["provider"] == "vimeo":
                            compteur = len(requetes_video)
                            expect(page.locator("course-video")).to_have_attribute("start", str(video["start"]))
                            assert len(requetes_video) == compteur
                            page.locator("course-video .video-play").click()
                            expect(page.locator("course-video iframe")).to_have_count(1)
                            iframe = page.locator("course-video iframe")
                            assert "dnt=1" in iframe.get_attribute("src")
                            assert f"#t={video['start']}s" in iframe.get_attribute("src")
                            page.evaluate("window.lecteursSimules.at(-1).evenements.timeupdate({seconds: 125})")
                            ouvrir(page, parcours, lecon, 1)
                            assert page.evaluate("window.lecteursSimules.at(-1).detruit") is True
                            ouvrir(page, parcours, lecon)
                            expect(page.locator("course-video .video-play")).to_have_attribute("aria-label", re.compile(r"Reprendre.*2:05"))
                            page.evaluate("window.echecVideoSimule=true")
                            page.locator("course-video .video-play").click()
                            expect(page.locator("course-video .video-fallback")).to_be_visible()
                            expect(page.locator("course-video a")).to_have_attribute("target", "_blank")
                            page.locator("course-video .quiet").click()
                            page.wait_for_function("document.activeElement.className === 'video-play'")
                            page.evaluate("window.echecVideoSimule=false")
                            page.locator("course-video .video-beginning").click()
                            expect(page.locator("course-video iframe")).to_have_attribute("src", re.compile(r"#t=0s$"))
                bilan["pagesVideo"] = 12

                # Clavier : touches d'édition, Entrée, boutons ElmUI, lien d'évitement.
                parcours, lecon = cours["tracks"][0], cours["tracks"][0]["lessons"][0]
                page.goto(adresse + "/#/parcours")
                page.wait_for_function("Object.keys(window.outilsApprentissage).length === 3")
                premier_texte = next((t, l, i, s) for t in cours["tracks"] for l in t["lessons"] for i, s in enumerate(l["steps"], 1) if s["kind"] == "rewrite")
                t, l, i, s = premier_texte
                ouvrir(page, t, l, i)
                saisie = page.get_by_label("Votre réponse", exact=True)
                saisie.fill(s["answers"][0])
                saisie.press("Enter")
                page.wait_for_function("document.activeElement.id === 'feedback'")
                assert etat(page)["correct"] is True
                symbole = page.get_by_role("button", name="¬", exact=True)
                symbole.focus()
                symbole.press("Space")
                page.wait_for_function("document.activeElement.id === 'answer-input'")
                assert saisie.input_value().endswith("¬") and etat(page)["correct"] is False
                saisie.fill("x" * 510)
                assert len(saisie.input_value()) == 500
                saisie.fill(s["answers"][0])
                validation = page.get_by_role("button", name="Vérifier", exact=True)
                validation.focus()
                validation.press("Enter")
                page.wait_for_function("document.activeElement.id === 'feedback'")
                assert etat(page)["correct"] is True
                page.get_by_role("link", name="Aller au contenu", exact=True).focus()
                page.keyboard.press("Enter")
                page.wait_for_function("document.activeElement.id === 'lesson-heading'")
                assert etat(page)["stepId"] == s["id"]
                bilan["clavier"] = ["Entrée dans le formulaire", "Entrée sur bouton ElmUI", "Espace sur symbole", "restitution du focus", "lien d’évitement", "limite de 500 caractères"]

                # Navigation par historique : aucune réinitialisation de réponse.
                ancien_hash = page.evaluate("location.hash")
                ouvrir(page, parcours, lecon, 1)
                page.go_back()
                page.wait_for_function("hash => location.hash === hash", arg=ancien_hash)
                assert etat(page)["stepId"] == s["id"] and etat(page)["correct"] is True
                page.go_forward()
                page.wait_for_function("document.getElementById('question-heading') !== null")

                # Contrats publics inchangés et échecs explicites, sans erreur JS non gérée.
                for nom, arguments in [("submit_learning_answer", {"answer": "x" * 501}), ("open_learning_lesson", {"trackId": "inconnu", "lessonId": "inconnue"})]:
                    resultat = page.evaluate("async ([nom, args]) => {try {await window.outilsApprentissage[nom].execute(args); return false;} catch {return true;}}", [nom, arguments])
                    assert resultat
                bilan["ports"] = ["reportState", "agentAction", "focusElement"]

                # Petits écrans, liens et boutons tactiles. Routes profondes sous préfixe.
                for largeur in [320, 390, 768, 1280]:
                    page.set_viewport_size({"width": largeur, "height": 900})
                    ouvrir(page, parcours, lecon, 1)
                    page.wait_for_timeout(80)
                    verifier_largeur(page)
                    for bouton in page.get_by_role("button").all():
                        if bouton.is_visible():
                            boite = bouton.bounding_box()
                            assert boite and boite["height"] >= 43.5, (bouton.inner_text(), boite)
                    page.screenshot(path=str(SORTIE / f"exercice-{largeur}.png"), full_page=True)
                bilan["largeurs"] = [320, 390, 768, 1280]
                page.goto(adresse + f"/cours/#/{parcours['id']}/{lecon['id']}/1")
                expect(page.locator("#question-heading")).to_be_visible()
                assert etat(page)["stepId"] == lecon["steps"][0]["id"]
                page.goto(adresse + "/cours/#/inconnu/inconnue/1")
                expect(page.locator("#lesson-heading")).to_contain_text("Cette leçon est introuvable.")
                assert not erreurs, erreurs
                bilan["erreursJavaScript"] = erreurs
                bilan["statut"] = "réussi"
                navigateur.close()
        finally:
            serveur.shutdown()
            serveur.server_close()
            fil.join(timeout=2)
    (SORTIE / "rapport.json").write_text(json.dumps(bilan, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(bilan, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
