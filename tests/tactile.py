"""Prises tactiles hors libellé : événements natifs CDP, sans injection du modèle."""
from functools import partial
from http.server import ThreadingHTTPServer
from threading import Thread
from playwright.sync_api import sync_playwright, expect
from atelier import RACINE, Silencieux, charger, doc, cible, palette


def glisser(page, cdp, origine, arrivee):
    x,y=origine;tx,ty=arrivee
    cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':x,'y':y}]})
    for i in range(1,17):
        cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':x+(tx-x)*i/16,'y':y+(ty-y)*i/16}]})
    expect(page.locator('.atelier-fantome')).to_have_count(1)
    expect(page.locator('[data-depot-actif]')).to_have_count(1)
    cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
    expect(page.locator('.atelier-fantome')).to_have_count(0)
    # Laisser finir le geste natif avant de commencer un tap indépendant.
    page.wait_for_timeout(600)


def fond_jaune(page, piece):
    entete=piece.locator('.mrjam-bloc-entete').first
    entete.scroll_into_view_if_needed();bb=entete.bounding_box()
    x=min(bb['x']+bb['width']-10,page.viewport_size['width']-15);y=bb['y']+8
    assert page.evaluate('p=>!document.elementFromPoint(p.x,p.y).closest("[data-atelier-source]")',{'x':x,'y':y})
    return x,y


def centre(cible):
    cible.scroll_into_view_if_needed();bb=cible.bounding_box();return bb['x']+min(45,bb['width']/2),bb['y']+bb['height']/2


def main():
    serveur=ThreadingHTTPServer(('127.0.0.1',0),partial(Silencieux,directory=str(RACINE/'dist')))
    Thread(target=serveur.serve_forever,daemon=True).start()
    try:
        with sync_playwright() as p:
            navigateur=p.chromium.launch()
            for largeur in (390,768):
                contexte=navigateur.new_context(viewport={'width':largeur,'height':900},is_mobile=True,has_touch=True)
                page=contexte.new_page();erreurs=[];page.on('pageerror',lambda e:erreurs.append(str(e)))
                page.goto(f'http://127.0.0.1:{serveur.server_port}/#/atelier');page.wait_for_selector('#atelier');cdp=contexte.new_cdp_session(page)
                charger(page,'double')
                piece=page.locator('[data-atelier-piece="regle:etI"]')
                surface=page.locator('#atelier-surface').bounding_box()
                arrivee=(surface['x']+surface['width']/2,surface['y']+surface['height']*.68)
                assert page.evaluate('p=>!document.elementFromPoint(p.x,p.y).closest("[data-atelier-cible]")',{'x':arrivee[0],'y':arrivee[1]})
                glisser(page,cdp,fond_jaune(page,piece),arrivee)
                assert len(doc(page)['preuves'])==1
                nid=doc(page)['preuves'][0]['id']
                # Une pression normale conserve la sélection au toucher.
                for i in (0,1):
                    destination=cible(page,nid,i);destination.get_by_role('button').tap();palette(page,'Faits')
                    fait=page.locator('[data-atelier-piece="fait:hA"]')
                    arrivee=centre(destination)
                    glisser(page,cdp,fond_jaune(page,fait),arrivee)
                expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
                # Saisir la marge verte plutôt que la petite lettre.
                palette(page,'Propositions');atome=page.locator('[data-atelier-piece="atome:P"]')
                destination=page.get_by_role('button',name=f'Modifier param:{nid}:A',exact=True)
                arrivee=centre(destination);atome.scroll_into_view_if_needed();bb=atome.bounding_box()
                glisser(page,cdp,(bb['x']+5,bb['y']+bb['height']/2),arrivee)
                assert doc(page)['preuves'][0]['parametres']['A']=={'type':'atome','nom':'P'}
                page.get_by_role('button',name='Annuler',exact=True).tap()
                expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
                assert len(doc(page)['preuves'])==1
                assert not erreurs,erreurs
                contexte.close();print(f'Tactile {largeur} px : fond jaune, fond libre, faits, marge verte et boutons réussis.',flush=True)
            navigateur.close()
    finally: serveur.shutdown()

if __name__=='__main__':main()
