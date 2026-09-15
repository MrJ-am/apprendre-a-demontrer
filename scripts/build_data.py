#!/usr/bin/env python3
"""Compile le sous-ensemble Org documenté en données de parcours."""
import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'cours' / 'parcours.org'
OUTPUT = ROOT / 'data' / 'course.json'


def compile_course(text):
    tracks = []
    current = None
    track = lesson = None
    ids = set()
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        heading = re.fullmatch(r'(\*{1,3}) (.+)', line)
        if heading:
            level, title = len(heading[1]), heading[2]
            current = {'title': title}
            if level == 1:
                track = current
                track['lessons'] = []
                tracks.append(track)
                lesson = None
            elif level == 2:
                if track is None:
                    raise ValueError('Leçon sans parcours')
                lesson = current
                lesson['steps'] = []
                track['lessons'].append(lesson)
            else:
                if lesson is None:
                    raise ValueError('Exercice sans leçon')
                current.update(kind='choice', answers=[], choices=[], scene='', formula='', source='', rule='')
                lesson['steps'].append(current)
        elif line == ':PROPERTIES:':
            if current is None:
                raise ValueError('Propriétés sans titre')
            i += 1
            while i < len(lines) and lines[i] != ':END:':
                prop = re.fullmatch(r':([A-Z_]+):\s*(.*)', lines[i])
                if not prop:
                    raise ValueError(f'Propriété invalide, ligne {i + 1}')
                key, value = prop.groups()
                mapping = {'CUSTOM_ID':'id','TYPE':'kind','ANSWERS':'answers','SCENE':'scene','FORMULA':'formula','SOURCE':'source','RULE':'rule','SHORT':'shortTitle','SYMBOL':'symbol','VIDEO_PROVIDER':'videoProvider','VIDEO_ID':'videoId','VIDEO_DURATION':'videoDuration','VIDEO_START':'videoStart','VIDEO_POSTER':'videoPoster','VIDEO_WATCH_URL':'videoWatchUrl'}
                if key not in mapping:
                    raise ValueError(f'Propriété inconnue : {key}')
                current[mapping[key]] = [v.strip() for v in value.split(';;')] if key == 'ANSWERS' else value
                i += 1
            if i == len(lines):
                raise ValueError('Tiroir de propriétés non fermé')
        elif line.startswith('#+begin_'):
            key = line.removeprefix('#+begin_').strip()
            if key not in {'description','intro','context','question','hint','success','takeaway','video','video_focus'}:
                raise ValueError(f'Bloc Org non pris en charge : {key}')
            if current is None:
                raise ValueError('Bloc sans titre')
            i += 1
            block = []
            while i < len(lines) and lines[i] != '#+end_' + key:
                block.append(lines[i])
                i += 1
            if i == len(lines):
                raise ValueError(f'Bloc {key} non fermé')
            current[key] = '\n'.join(block).strip()
        elif line.startswith('|'):
            if current is None or 'choices' not in current:
                raise ValueError('Tableau en dehors d’un exercice')
            if re.fullmatch(r'[|+\-\s]+', line):
                i += 1
                continue
            cells = [s.strip().replace('\\vert{}', '|') for s in line.strip('|').split('|')]
            if cells[0] != 'ID':
                if len(cells) != 3:
                    raise ValueError(f'Trois colonnes attendues, ligne {i + 1}')
                current['choices'].append(dict(zip(['id','label','feedback'],cells)))
        elif line.strip() and not line.startswith('#+'):
            raise ValueError(f'Texte hors bloc, ligne {i + 1} : {line[:80]}')
        i += 1

    def identify(item):
        identity = item.get('id', '')
        if not re.fullmatch(r'[a-z][a-z0-9-]*', identity) or identity in ids:
            raise ValueError(f'Identifiant absent, invalide ou dupliqué : {identity}')
        ids.add(identity)

    for t in tracks:
        identify(t)
        for field in ['description','shortTitle','symbol']:
            if not t.get(field): raise ValueError(f'{t["id"]} : {field} manquant')
        if not t['lessons']: raise ValueError('Parcours vide')
        for l in t['lessons']:
            identify(l)
            if not l.get('intro') or not l['steps']: raise ValueError(f'Leçon incomplète : {l["id"]}')
            provider = l.pop('videoProvider', 'placeholder')
            video_id = l.pop('videoId', '')
            if provider not in ['placeholder','youtube','vimeo']: raise ValueError('Fournisseur vidéo inconnu')
            if provider == 'youtube' and not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id): raise ValueError('Identifiant YouTube invalide')
            if provider == 'vimeo' and not re.fullmatch(r'[0-9]+(?:/[A-Za-z0-9]+)?', video_id): raise ValueError('Identifiant Vimeo invalide')
            if provider == 'placeholder' and video_id: raise ValueError('Vidéo provisoire avec identifiant')
            def seconds(property_name):
                value = l.pop(property_name, '0')
                if not re.fullmatch(r'[0-9]+', value): raise ValueError('Durée ou repère vidéo invalide')
                return int(value)
            duration, start = seconds('videoDuration'), seconds('videoStart')
            if start and (not duration or start >= duration): raise ValueError('Repère vidéo hors durée')
            poster = l.pop('videoPoster', '')
            watch_url = l.pop('videoWatchUrl', '')
            for url, hosts in [(poster, ['i.vimeocdn.com']), (watch_url, ['vimeo.com', 'www.vimeo.com', 'www.youtube.com', 'youtu.be'])]:
                if url:
                    parsed = urlsplit(url)
                    if parsed.scheme != 'https' or parsed.hostname not in hosts or parsed.username or parsed.password or parsed.port:
                        raise ValueError('Lien vidéo non autorisé')
            if provider == 'placeholder' and (duration or start or poster or watch_url): raise ValueError('Vidéo provisoire avec métadonnées de lecture')
            l['video'] = {'provider':provider,'id':video_id,'title':l.get('video', l['title']), 'duration':duration,'start':start,'poster':poster,'watchUrl':watch_url,'focus':l.pop('video_focus','')}
            for s in l['steps']:
                identify(s)
                for field in ['context','question','hint','success','takeaway']:
                    if not s.get(field): raise ValueError(f'{s["id"]} : {field} manquant')
                if s['kind'] not in ['choice','fill','rewrite']: raise ValueError('Type d’exercice inconnu')
                if not s['answers']: raise ValueError('Réponse manquante')
                if s['kind'] == 'choice':
                    options = [c['id'] for c in s['choices']]
                    if len(options) < 2 or len(set(options)) != len(options) or any(a not in options for a in s['answers']):
                        raise ValueError(f'Choix incohérents : {s["id"]}')
                elif s['choices']: raise ValueError('Choix dans un exercice à saisir')
                if s['kind'] == 'rewrite' and (not s['source'] or s['rule'] not in ['nnf','no-implies','equivalent','structure']):
                    raise ValueError('Exercice de formalisation incomplet')
    if not tracks: raise ValueError('Aucun parcours')
    return {'version':1, 'tracks':tracks}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    course = compile_course(SOURCE.read_text())
    rendered = json.dumps(course, ensure_ascii=False, indent=2) + '\n'
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != rendered:
            raise SystemExit('Les données ne correspondent pas à la source Org. Exécuter npm run build:data.')
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(rendered)
    lessons = [l for t in course['tracks'] for l in t['lessons']]
    print(f'{len(course["tracks"])} parcours, {len(lessons)} leçons, {sum(len(l["steps"]) for l in lessons)} exercices — source Org vérifiée.')
