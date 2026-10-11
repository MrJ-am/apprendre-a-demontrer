"""Indice réel : inversion, focus, état pédagogique et préférence de mouvement."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import threading
from playwright.sync_api import expect, sync_playwright
from navigation import AMORCE, etat, outil

RACINE = Path(__file__).resolve().parents[1]


class Silencieux(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def verifier_contenu(contenu):
    # KaTeX peut dépasser la boîte de ligne de quelques pixels sans être masqué.
    # Contrôler les ancêtres qui coupent réellement, pas scrollHeight isolé.
    coupes = contenu.evaluate("""e => {
      const r=e.getBoundingClientRect(); const bas=r.top+Math.max(r.height,e.scrollHeight);
      const coupes=[];
      for(let p=e;p;p=p.parentElement) {
        const s=getComputedStyle(p), b=p.getBoundingClientRect();
        if(['hidden','clip'].includes(s.overflowY) && (r.top < b.top-1 || bas > b.bottom+1))
          coupes.push({id:p.id,haut:b.top,bas:b.bottom,contenu:bas});
      }
      return coupes;
    }""")
    assert coupes == [], coupes


def verifier(site):
    cours = json.loads((RACINE / 'data/course.json').read_text())
    parcours = cours['tracks'][0]
    lecon = parcours['lessons'][0]
    index, etape = next((i, e) for i, e in enumerate(lecon['steps']) if e['kind'] != 'choice' and e['hint'])
    serveur = ThreadingHTTPServer(('127.0.0.1', 0), partial(Silencieux, directory=str(site)))
    threading.Thread(target=serveur.serve_forever, daemon=True).start()
    resultats = []
    try:
        with sync_playwright() as pilote:
            options = {'executable_path': os.environ['CHROMIUM']} if os.environ.get('CHROMIUM') else {}
            navigateur = pilote.chromium.launch(**options)
            try:
                for largeur in (320, 768, 1440):
                    for reduction in (False, True):
                        page = navigateur.new_page(viewport={'width': largeur, 'height': 1000}, reduced_motion='reduce' if reduction else 'no-preference')
                        page.set_default_timeout(4000)
                        erreurs = []
                        page.on('pageerror', lambda erreur: erreurs.append(str(erreur)))
                        page.add_init_script(AMORCE)
                        page.add_init_script("window.framesObservees=0;const r=window.requestAnimationFrame;window.requestAnimationFrame=f=>r.call(window,t=>{framesObservees++;f(t)});")
                        page.route('**/vimeo/player.min.js', lambda route: route.fulfill(content_type='application/javascript', body='/* SDK synthétique de la fixture */'))
                        page.route('https://**/*', lambda route: route.abort())
                        page.goto(f'http://127.0.0.1:{serveur.server_port}/#/{parcours["id"]}/{lecon["id"]}/{index+1}', wait_until='networkidle')
                        page.wait_for_function('Object.keys(outilsApprentissage).length === 3')
                        champ = page.get_by_role('textbox', name='Votre réponse', exact=True)
                        champ.fill(etape['answers'][0])
                        hint = page.get_by_role('button', name='Un indice', exact=True)
                        hint.focus()
                        hint.click()
                        fermer = page.get_by_role('button', name='Masquer l’indice', exact=True)
                        expect(fermer).to_be_focused()
                        expect(champ).to_have_value(etape['answers'][0])
                        if reduction:
                            expect(page.locator('#hint-transition')).to_have_count(0)
                            expect(page.locator('#hint-content')).to_be_visible()
                        else:
                            expect(page.locator('#hint-transition')).to_have_count(1)
                            # Le calcul pédagogique peut commencer pendant la transition.
                            assert not page.get_by_role('button', name='Vérifier', exact=True).is_disabled()
                        # Inverser deux fois, sans attendre une décoration ni perdre le focus.
                        fermer.click()
                        hint.click()
                        expect(fermer).to_be_focused()
                        expect(champ).to_have_value(etape['answers'][0])
                        expect(page.locator('#hint-content')).to_be_visible()
                        # La préférence change pendant la tâche, appliquée immédiatement.
                        page.emulate_media(reduced_motion='reduce')
                        expect(page.locator('#hint-transition')).to_have_count(0)
                        contenu = page.locator('#hint-content')
                        assert contenu.bounding_box()['height'] > 0
                        verifier_contenu(contenu)
                        fermer.click()
                        expect(page.locator('#hint-content')).to_have_count(0)
                        expect(hint).to_be_focused()
                        page.emulate_media(reduced_motion='no-preference')
                        hint.click()
                        page.get_by_role('button', name='Vérifier', exact=True).click()
                        page.wait_for_function("document.activeElement.id === 'feedback'")
                        assert etat(page)['correct'] is True and etat(page)['value'] == etape['answers'][0]
                        page.wait_for_timeout(500)
                        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), largeur
                        # Le cadre est auto à l'arrivée : pas d'indice tronqué après redimensionnement.
                        page.set_viewport_size({'width': 390 if largeur == 320 else 320, 'height': 900})
                        expect(contenu).to_be_visible()
                        verifier_contenu(contenu)
                        page.wait_for_timeout(300)
                        avant = page.evaluate('framesObservees')
                        page.wait_for_timeout(250)
                        assert page.evaluate('framesObservees') == avant, 'Horloge encore active au repos'
                        assert erreurs == [], erreurs
                        resultats.append({'largeur': largeur, 'reductionInitiale': reduction, 'inversionFocus': True, 'reductionLive': True, 'reponseConservee': True, 'ecritureSansAttente': True, 'repos': True})
                        page.close()
            finally:
                navigateur.close()
    finally:
        serveur.shutdown()
        serveur.server_close()
    return resultats


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--site', type=Path, default=RACINE / 'dist')
    print(json.dumps(verifier(parser.parse_args().site), ensure_ascii=False))
