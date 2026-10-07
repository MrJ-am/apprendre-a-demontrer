"""Parcours réels de l'atelier : souris, événements tactiles CDP, clavier et JSON.
Les observations lisent le stockage ; aucune fonction du modèle n'est appelée.
Les captures n'attestent pas un essai sur une tablette physique.
"""
from __future__ import annotations
import json
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from playwright.sync_api import sync_playwright, expect

RACINE=Path(__file__).resolve().parents[1]
SORTIE=RACINE/'controles-atelier'
CLE='mrjam.atelier-preuves.v1'

class Silencieux(SimpleHTTPRequestHandler):
    def log_message(self,*_): pass

def doc(page):
    return page.evaluate('(cle)=>JSON.parse(localStorage.getItem(cle))', CLE)

def noeuds(preuves):
    return [n for p in preuves for n in [p,*[x for es in p['entrees'] for x in noeuds(es)]]]

def id_regle(page,nom):
    return next(n['id'] for n in noeuds(doc(page)['preuves']) if n['regle'].get('nom')==nom)

def cible(page,parent='racine',indice=0,position=0):
    return page.locator(f'[data-testid="preuve:{parent}|{indice}|{position}"]')

def charger(page,nom,solution=False):
    page.get_by_label('Exemple',exact=True).select_option(nom)
    page.get_by_role('button',name='Charger la solution manipulable' if solution else 'Construire l’énoncé',exact=True).click()
    page.wait_for_timeout(70)

def palette(page,groupe):
    if not page.locator('#atelier-palette').count():
        page.get_by_role('button',name='Palette et outils',exact=True).click()
    page.locator('#atelier-palette').get_by_role('button',name=groupe,exact=True).click()

def preparer_source(page,source,destination=None):
    if source.startswith('fait:'):
        if destination is not None:
            destination.get_by_role('button').click()
        palette(page,'Faits')
    elif source.startswith('regle:'):
        palette(page,'Construire' if source.split(':')[1] in ['etI','implI','ouG','ouD'] else 'Utiliser')
    elif source.startswith('theoreme:'):
        palette(page,'Mes théorèmes')
    if source.startswith('bloc:'):
        return page.locator(f'[data-testid="{source}"]').first
    return page.locator('#atelier-palette').locator(f'[data-atelier-source="{source}"]').first

def drag(page,source,destination,tactile=False,cdp=None):
    destination.evaluate('e=>e.scrollIntoView({block:"center"})')
    page.wait_for_timeout(80)
    source.scroll_into_view_if_needed()
    a=source.bounding_box(); z=destination.bounding_box()
    sx=a['x']+min(40,a['width']/2); sy=a['y']+22
    tx=z['x']+min(45,z['width']/2); ty=z['y']+24
    if tactile:
        cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':sx,'y':sy}]})
        for i in range(1,13):
            cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':sx+(tx-sx)*i/12,'y':sy+(ty-sy)*i/12}]})
        expect(page.locator('.atelier-fantome')).to_have_count(1)
        cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
    else:
        page.mouse.move(sx,sy);page.mouse.down()
        page.mouse.move(tx,ty,steps=12)
        expect(page.locator('.atelier-fantome')).to_have_count(1)
        page.mouse.up()
    page.wait_for_timeout(100)
    expect(page.locator('.atelier-fantome')).to_have_count(0)

def placer(page,source,parent='racine',indice=0,position=0,glisser=False):
    destination=cible(page,parent,indice,position)
    origine=preparer_source(page,source,destination)
    if glisser: drag(page,origine,destination)
    else:
        origine.get_by_role('button').click()
        destination.get_by_role('button').click()
    page.wait_for_timeout(60)

def inspecter(page,id):
    page.locator(f'[data-bloc="{id}"]').get_by_role('button',name='Inspecter',exact=True).first.click()

def parametre(page,id,nom,formule):
    inspecter(page,id)
    page.locator(f'[data-formule="param:{id}:{nom}"]').get_by_role('button').first.click()
    page.get_by_label('Saisie textuelle facultative',exact=True).fill(formule)
    page.get_by_role('button',name='Lire la saisie',exact=True).click()
    page.get_by_role('button',name='Utiliser cette proposition',exact=True).click()

def extraire(page,id,nom):
    inspecter(page,id)
    page.get_by_role('button',name='Créer un théorème',exact=True).click()
    page.get_by_label('Nom du théorème',exact=True).fill(nom)
    page.get_by_role('button',name='Enregistrer dans Mes théorèmes',exact=True).click()
    page.wait_for_timeout(80)
    defs=[d for d in doc(page)['bibliotheque'] if d['nom']==nom]
    assert len(defs)==1, page.locator('#atelier-message').inner_text()
    return defs[0]

def largeur(page):
    assert page.evaluate('document.documentElement.scrollWidth <= innerWidth + 2')
    assert not page.locator('.atelier-fantome').count()

def main():
    SORTIE.mkdir(exist_ok=True)
    serveur=ThreadingHTTPServer(('127.0.0.1',0),partial(Silencieux,directory=str(RACINE/'dist')))
    Thread(target=serveur.serve_forever,daemon=True).start()
    adresse=os.environ.get('ATELIER_URL',f'http://127.0.0.1:{serveur.server_port}/#/atelier')
    resultats=[]; erreurs=[]
    try:
        with sync_playwright() as p:
            navigateur=p.chromium.launch()
            contexte=navigateur.new_context(viewport={'width':1440,'height':1100},accept_downloads=True,reduced_motion='reduce')
            page=contexte.new_page();page.on('pageerror',lambda e:erreurs.append(str(e)))
            page.goto(adresse);page.wait_for_selector('#atelier')
            charger(page,'double')
            placer(page,'regle:etI',glisser=True)
            racine=id_regle(page,'etI')
            placer(page,'fait:hA',racine,0,glisser=True)
            placer(page,'fait:hA',racine,1,glisser=True)
            expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
            assert len(noeuds(doc(page)['preuves']))==3
            # Déplacer une construction existante avec la même référence non consommée.
            premier=doc(page)['preuves'][0]['entrees'][0][0]['id']
            origine=page.locator(f'[data-testid="bloc:{premier}"]')
            drag(page,origine,cible(page,racine,1,1))
            assert not doc(page)['preuves'][0]['entrees'][0]
            page.get_by_role('button',name='Annuler',exact=True).click()
            expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
            page.get_by_role('button',name='Rétablir',exact=True).click()
            expect(page.locator('#atelier-verification')).to_contain_text('À compléter')
            page.get_by_role('button',name='Annuler',exact=True).click()
            page.screenshot(path=str(SORTIE/'conjonction-bureau.png'),full_page=True)
            resultats.append('Souris : palette, deux cavités, contraction, déplacement imbriqué et annuler/rétablir')
            # Construire la transitivité par les actions ordinaires, sans solution chargée.
            charger(page,'transitivite')
            placer(page,'regle:implI')
            implication=id_regle(page,'implI')
            placer(page,'regle:implE',implication,0)
            finale=id_regle(page,'implE')
            parametre(page,finale,'A','B')
            placer(page,'fait:hBC',finale,0)
            placer(page,'regle:implE',finale,1)
            interieur=[n['id'] for n in noeuds(doc(page)['preuves']) if n['regle'].get('nom')=='implE' and n['id']!=finale][0]
            placer(page,'fait:hAB',interieur,0)
            placer(page,'fait:'+implication+'/h/0/0',interieur,1)
            expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
            trans=extraire(page,implication,'Transitivité testée')
            assert len(trans['entrees'])==2 and trans['parametres']==['A','B','C']
            resultats.append('Transitivité construite et extraite par l’interface : deux entrées, trois paramètres')
            # Deux applications imbriquées du nouveau théorème, puis deuxième abstraction.
            charger(page,'chaine')
            src=f'theoreme:{trans["id"]}:1'
            placer(page,src)
            seconde=doc(page)['preuves'][0]['id']
            parametre(page,seconde,'B','C')
            placer(page,src,seconde,0)
            premiere=doc(page)['preuves'][0]['entrees'][0][0]['id']
            placer(page,'fait:hAB',premiere,0)
            placer(page,'fait:hBC',premiere,1)
            placer(page,'fait:hCD',seconde,1)
            expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
            chain=extraire(page,seconde,'Chaîne de trois implications')
            assert len(chain['entrees'])==3 and chain['parametres']==['A','B','C','D']
            inspecter(page,seconde)
            page.get_by_role('button',name='Voir la démonstration',exact=True).click()
            expect(page.get_by_text('Démonstration instanciée — lecture du certificat',exact=True)).to_be_visible()
            page.get_by_role('button',name='Fermer la démonstration',exact=True).click()
            page.get_by_role('button',name='Développer cette occurrence',exact=True).click()
            expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
            page.reload();page.wait_for_selector('#atelier')
            assert len([d for d in doc(page)['bibliotheque'] if not d['id'].startswith('fourni-')])==2
            expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
            with page.expect_download() as telechargement:
                page.get_by_role('button',name='Exporter JSON',exact=True).click()
            fichier=telechargement.value; export=SORTIE/'aller-retour.json';fichier.save_as(export)
            charger(page,'vide')
            with page.expect_file_chooser() as choix:
                page.get_by_role('button',name='Importer JSON',exact=True).click()
            choix.value.set_files(export)
            expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
            resultats.append('Deuxième théorème créé, développé, restauré puis exporté/importé avec ses dépendances')
            # Instanciation composée d'un théorème personnel, sans modification de code.
            charger(page,'echange',True)
            echange=extraire(page,'echange','Échanger les termes')
            charger(page,'echange')
            page.locator('[data-formule="premisse:hAB"]').get_by_role('button').first.click()
            page.get_by_label('Saisie textuelle facultative',exact=True).fill('(P => Q) & (R | S)')
            page.get_by_role('button',name='Lire la saisie',exact=True).click()
            page.get_by_role('button',name='Utiliser cette proposition',exact=True).click()
            page.locator('[data-formule="objectif"]').get_by_role('button').first.click()
            page.get_by_label('Saisie textuelle facultative',exact=True).fill('(R | S) & (P => Q)')
            page.get_by_role('button',name='Lire la saisie',exact=True).click()
            page.get_by_role('button',name='Utiliser cette proposition',exact=True).click()
            placer(page,f'theoreme:{echange["id"]}:1')
            usage=doc(page)['preuves'][0]['id']
            placer(page,'fait:hAB',usage,0)
            expect(page.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
            assert doc(page)['preuves'][0]['parametres']['A']['type']=='implique'
            assert doc(page)['preuves'][0]['parametres']['B']['type']=='ou'
            resultats.append('Théorème personnel instancié avec deux propositions composées')
            # Composer par les trous et les connecteurs, puis par des gestes de proposition.
            charger(page,'vide')
            page.locator('[data-formule="objectif"]').get_by_role('button').first.click()
            page.locator('#atelier-palette').get_by_role('button',name='∧',exact=True).click()
            page.locator('[data-chemin="0"]').get_by_role('button').first.click()
            page.locator('#atelier-palette').get_by_role('button',name='⇒',exact=True).click()
            for chemin,atome in [('0.0','P'),('0.1','Q'),('1','R')]:
                page.locator(f'[data-atelier-source="atome:{atome}"]').get_by_role('button').click()
                page.locator(f'[data-chemin="{chemin}"]').get_by_role('button').first.click()
            page.get_by_role('button',name='Utiliser cette proposition',exact=True).click()
            assert doc(page)['objectif']['type']=='et'
            assert doc(page)['objectif']['arguments'][0]['type']=='implique'
            assert not doc(page)['preuves']
            resultats.append('Composition visuelle d’une proposition imbriquée sans saisir une formule au clavier')
            page.locator('[data-formule="objectif"]').get_by_role('button').first.click()
            page.locator('#atelier-palette').get_by_role('button',name='∨',exact=True).click()
            for chemin,atome in [('0','P'),('1','Q')]:
                page.locator(f'[data-atelier-source="atome:{atome}"]').get_by_role('button').click()
                page.locator(f'[data-chemin="{chemin}"]').get_by_role('button').first.click()
            drag(page,page.locator('[data-atelier-source="prop:brouillon"]'),page.locator('[data-formule="objectif"]'))
            assert doc(page)['objectif']['type']=='ou'
            resultats.append('Proposition composée déplacée dans un emplacement de formule par la souris')
            # Clavier : sélectionner, placer, annuler, rétablir.
            charger(page,'double')
            origine=preparer_source(page,'regle:etI')
            origine.get_by_role('button').focus();page.keyboard.press('Enter')
            expect(page.locator('#atelier-message')).to_contain_text('Objet sélectionné')
            cible(page).get_by_role('button').focus();page.keyboard.press('Enter')
            page.wait_for_function('JSON.parse(localStorage.getItem("mrjam.atelier-preuves.v1")).preuves.length === 1')
            assert len(doc(page)['preuves'])==1
            page.keyboard.press('Control+z');page.wait_for_function('JSON.parse(localStorage.getItem("mrjam.atelier-preuves.v1")).preuves.length === 0');assert not doc(page)['preuves']
            page.keyboard.press('Control+Shift+z');page.wait_for_function('JSON.parse(localStorage.getItem("mrjam.atelier-preuves.v1")).preuves.length === 1');assert len(doc(page)['preuves'])==1
            resultats.append('Clavier : sélection/placement et historique')
            # Portée : tentative de sortir une référence locale, sans perte de construction.
            charger(page,'transitivite',True)
            etat_avant=doc(page)
            origine=page.locator('[data-testid="bloc:refA"]')
            destination=cible(page,'racine',0,1)
            origine.get_by_role('button').click();destination.get_by_role('button').click()
            assert doc(page)==etat_avant
            expect(page.locator('#atelier-message')).to_contain_text('pas disponible ici')
            resultats.append('Déplacement hors de la portée refusé sans perte de descendants')
            # Captures sur plusieurs orientations, après repli pour les preuves profondes.
            charger(page,'double',True)
            for w,h in [(1440,1000),(768,1024),(1024,768),(390,844),(844,390),(320,740)]:
                page.set_viewport_size({'width':w,'height':h});page.wait_for_timeout(100)
                largeur(page)
                if w<1000:
                    if not page.locator('#atelier-palette').count():
                        page.get_by_role('button',name='Palette et outils',exact=True).click()
                    hauteur=page.locator('#atelier-palette').bounding_box()['height']
                    assert h*.45 < hauteur <= h*.56, (w,h,hauteur)
                page.screenshot(path=str(SORTIE/f'atelier-{w}x{h}.png'),full_page=True)
            resultats.append('Six formats contrôlés : ordinateur, tablette et téléphone, portrait/paysage')
            # Vrais événements tactiles reçus par Pointer Events via Chrome DevTools.
            tactile=navigateur.new_context(viewport={'width':1024,'height':900},has_touch=True,is_mobile=True,reduced_motion='reduce')
            tp=tactile.new_page();tp.goto(adresse);tp.wait_for_selector('#atelier')
            cdp=tactile.new_cdp_session(tp)
            charger(tp,'double')
            origine=preparer_source(tp,'regle:etI')
            drag(tp,origine,cible(tp),tactile=True,cdp=cdp)
            tr=id_regle(tp,'etI')
            for i in [0,1]:
                destination=cible(tp,tr,i)
                origine=preparer_source(tp,'fait:hA',destination)
                drag(tp,origine,destination,tactile=True,cdp=cdp)
            expect(tp.locator('#atelier-verification')).to_contain_text('✓ Preuve vérifiée')
            # Défilement natif hors poignée : aucun touch-action:none global.
            tp.evaluate('window.scrollTo(0,0)');tp.wait_for_timeout(80)
            cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':980,'y':760}]})
            for y in [690,590,490,390,290]:
                cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':980,'y':y}]})
            cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
            tp.wait_for_timeout(150)
            assert tp.evaluate('window.scrollY')>100
            # Annulation d'un geste interrompu conserve le document.
            avant=doc(tp);poignee=tp.locator(f'[data-testid="bloc:{tr}"]');poignee.scroll_into_view_if_needed();bb=poignee.bounding_box()
            cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':bb['x']+30,'y':bb['y']+20}]})
            cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':bb['x']+60,'y':bb['y']+45}]})
            cdp.send('Input.dispatchTouchEvent',{'type':'touchCancel','touchPoints':[]})
            expect(tp.locator('.atelier-fantome')).to_have_count(0)
            assert doc(tp)==avant
            tp.screenshot(path=str(SORTIE/'tactile-tablette.png'),full_page=True)
            resultats.append('Tactile CDP : palette, deux cavités après défilement, défilement natif et pointercancel')
            # Téléphone : atteindre une cible initialement hors écran par défilement actif.
            telephone=navigateur.new_context(viewport={'width':390,'height':844},has_touch=True,is_mobile=True,reduced_motion='reduce')
            ph=telephone.new_page();ph.goto(adresse);ph.wait_for_selector('#atelier');tcdp=telephone.new_cdp_session(ph)
            charger(ph,'double');origine=preparer_source(ph,'regle:etI');origine.scroll_into_view_if_needed();boite=origine.bounding_box()
            tcdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':boite['x']+40,'y':boite['y']+20}]})
            tcdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':375,'y':820}]})
            expect(ph.locator('.atelier-fantome')).to_have_count(1)
            for _ in range(80):
                z=cible(ph).bounding_box()
                if 100<z['y']<700:break
                ph.wait_for_timeout(50)
            assert 100<z['y']<700, z
            tcdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':375,'y':400}]})
            ph.wait_for_timeout(60)
            z=cible(ph).bounding_box()
            tcdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':z['x']+45,'y':z['y']+24}]})
            expect(ph.locator('[data-depot-actif]')).to_have_count(1)
            tcdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
            ph.wait_for_function('JSON.parse(localStorage.getItem("mrjam.atelier-preuves.v1")).preuves.length === 1')
            largeur(ph)
            ph.screenshot(path=str(SORTIE/'tactile-telephone-depot-defile.png'),full_page=True)
            resultats.append('Téléphone tactile CDP : cible hors écran atteinte par défilement pendant le geste')
            # Un stockage corrompu est conservé jusqu'à une action explicite.
            page.evaluate('(cle)=>localStorage.setItem(cle,"corrompu")',CLE)
            page.reload();page.wait_for_selector('#atelier')
            expect(page.locator('#atelier-message')).to_contain_text('Sauvegarde locale illisible')
            charger(page,'double',True)
            assert page.evaluate('(cle)=>localStorage.getItem(cle)',CLE)=='corrompu'
            resultats.append('Stockage corrompu conservé ; sauvegarde suspendue explicitement')
            largeur(page)
            assert not erreurs, erreurs
            (SORTIE/'resultats.json').write_text(json.dumps({'parcours':resultats,'erreurs':erreurs,'tablettePhysique':False},ensure_ascii=False,indent=2))
            print(json.dumps(resultats,ensure_ascii=False,indent=2))
            navigateur.close()
    finally: serveur.shutdown()

if __name__=='__main__': main()
