#!/usr/bin/env python3
"""Render one decorative ENC scene from pinned NOAA downloads; no app tiles/sprites."""
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
import zipfile

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SAVER = ROOT / 'screensaver'
DATA = SAVER / 'Provenance/noaa'
SIZE = (3456, 2234)
CENTER = (-122.446, 37.830)
ZOOM = 13.0
SCALE = 2
CELLS = ('US5OAKEF', 'US5OAKEG', 'US5OAKEH', 'US5OAKFF', 'US5OAKFG', 'US5OAKFH')
LAYERS = ('LNDARE', 'COALNE', 'DEPCNT', 'SOUNDG', 'BUYLAT', 'BCNLAT', 'LIGHTS', 'BRIDGE', 'SEAARE')
FONT = '/System/Library/Fonts/Supplemental/Arial.ttf'


def mercator(c):
    return (c[0] / 360 + .5, (1 - math.asinh(math.tan(math.radians(c[1]))) / math.pi) / 2)


def project(c):
    x, y = mercator(c)
    cx, cy = mercator(CENTER)
    world = 512 * 2 ** ZOOM * SCALE
    return ((x - cx) * world + SIZE[0] / 2, (y - cy) * world + SIZE[1] / 2)


def polygons(g):
    return [g['coordinates']] if g['type'] == 'Polygon' else g['coordinates'] if g['type'] == 'MultiPolygon' else []


def lines(g):
    return [g['coordinates']] if g['type'] == 'LineString' else g['coordinates'] if g['type'] == 'MultiLineString' else []


def points(g):
    return [g['coordinates']] if g['type'] == 'Point' else g['coordinates'] if g['type'] == 'MultiPoint' else []


def visible(p, margin=30):
    return -margin <= p[0] < SIZE[0] + margin and -margin <= p[1] < SIZE[1] + margin


features = {layer: [] for layer in LAYERS}
sources = json.loads((DATA / 'source-manifest.json').read_text())
with tempfile.TemporaryDirectory(prefix='openhelm-noaa-') as temporary:
    for cell in CELLS:
        archive = DATA / (cell + '.zip')
        if hashlib.sha256(archive.read_bytes()).hexdigest() != sources['sources'][cell]['sha256']:
            raise ValueError(f'{cell}: downloaded archive differs from reviewed source manifest')
        cell_root = Path(temporary) / cell
        with zipfile.ZipFile(archive) as zipped:
            for member in zipped.namelist():
                if Path(member).is_absolute() or '..' in Path(member).parts:
                    raise ValueError(f'{cell}: unexpected archive path')
            zipped.extractall(cell_root)
        source = cell_root / 'ENC_ROOT' / cell / (cell + '.000')
        for layer in LAYERS:
            output = Path(temporary) / (cell + '-' + layer + '.json')
            result = subprocess.run(['ogr2ogr', '-f', 'GeoJSON', str(output), str(source), layer], capture_output=True, text=True)
            if result.returncode:
                if result.stderr.strip() == f"ERROR 1: Couldn't fetch requested layer '{layer}'!":
                    continue
                raise RuntimeError(result.stderr)
            for feature in json.loads(output.read_text())['features']:
                feature['sourceCell'] = cell
                features[layer].append(feature)

light = next(f for f in features['LIGHTS'] if f['sourceCell'] == 'US5OAKFG' and f['properties']['LNAM'] == '0226014E0B1B0032')
assert light['properties']['SIGSEQ'] == '00.5+(04.5)'
assert light['properties']['COLOUR'] == ['1'] and light['properties']['VALNMR'] == 20
anchor = project(light['geometry']['coordinates'])
scene = dict(id='alcatraz-noaa-preview', title='Alcatraz — San Francisco Bay · NOAA data preview', chart=dict(
    center=CENTER, zoom=ZOOM, logicalWidth=1728, logicalHeight=1117, deviceScaleFactor=SCALE,
    asset='alcatraz-noaa-preview@2x.png', lightVisibilityAsset='alcatraz-noaa-preview-light-visibility@2x.png'), light=dict(
    name='Alcatraz Light', coordinate=light['geometry']['coordinates'], character='Fl W 5s', periodSeconds=5,
    pulses=[dict(start=0, end=.5)], anchor=dict(x=anchor[0]/SIZE[0], y=anchor[1]/SIZE[1]),
    sectors=[dict(startBearing=0, endBearing=360, colour='white', rangeNauticalMiles=20)]))
(SAVER / 'Scenes/alcatraz-noaa-preview.json').write_text(json.dumps(scene, indent=2) + '\n')

image = Image.new('RGB', SIZE, '#090c0e')
draw = ImageDraw.Draw(image)
land = Image.new('L', SIZE)
land_draw = ImageDraw.Draw(land)
for feature in features['LNDARE']:
    for polygon in polygons(feature['geometry']):
        for index, ring in enumerate(polygon):
            path = [project(c) for c in ring]
            land_draw.polygon(path, fill=0 if index else 255)

# Depth contours and soundings are literal ENC geometry/values, in metres.
for feature in features['DEPCNT']:
    for line in lines(feature['geometry']):
        path = [project(c) for c in line]
        draw.line(path, fill='#30383d', width=2)
depth_font = ImageFont.truetype(FONT, 20)
occupied = set()
for feature in features['SOUNDG']:
    for coordinate in points(feature['geometry']):
        p = project(coordinate)
        if not visible(p, -40) or len(coordinate) != 3:
            continue
        cell = (round(p[0]/55), round(p[1]/38))
        if cell in occupied:
            continue
        occupied.add(cell)
        text = f'{coordinate[2]:g}'
        draw.text(p, text, font=depth_font, fill='#657178', anchor='mm')

land_plate = Image.new('RGB', SIZE, '#313436')
land_ink = ImageDraw.Draw(land_plate)
# Original deterministic stipple; no external raster or nautical sprite sources.
for y in range(0, SIZE[1], 15):
    for x in range((y//15 % 2)*7, SIZE[0], 15):
        land_ink.rectangle((x, y, x+1, y+1), fill='#464a4c')
image.paste(land_plate, (0, 0), land)
draw = ImageDraw.Draw(image)
for feature in features['COALNE']:
    for line in lines(feature['geometry']):
        draw.line([project(c) for c in line], fill='#9a9e9f', width=2)
for feature in features['BRIDGE']:
    for line in lines(feature['geometry']):
        draw.line([project(c) for c in line], fill='#d2d0c8', width=5)
    for polygon in polygons(feature['geometry']):
        draw.polygon([project(c) for c in polygon[0]], fill='#999c96', outline='#c7c9c2', width=2)

# Small original marks use the ENC's actual colour attribute. They are decorative
# renderings, not copied S-52 symbols or a certified navigation portrayal.
colours = {'1': '#d9dcda', '3': '#eb5757', '4': '#46cd66', '6': '#e4c756'}
for layer in ('BUYLAT', 'BCNLAT', 'LIGHTS'):
    seen = set()
    for feature in features[layer]:
        prop = feature['properties']
        for coordinate in points(feature['geometry']):
            x, y = project(coordinate)
            key = (round(x), round(y))
            if not visible((x,y), -20) or key in seen:
                continue
            seen.add(key)
            colour = colours.get(next(iter(prop.get('COLOUR', [])), ''), '#a6acab')
            radius = 5 if layer == 'LIGHTS' else 7
            if layer == 'BCNLAT':
                draw.polygon([(x,y-radius),(x+radius,y+radius),(x-radius,y+radius)], outline=colour, width=3)
            else:
                draw.ellipse((x-radius,y-radius,x+radius,y+radius), outline=colour, width=3)
            if layer != 'LIGHTS':
                draw.line((x,y+radius,x,y+radius+7), fill=colour, width=2)

# Geographic labels below are independently read from the included NOAA objects.
label_font = ImageFont.truetype(FONT, 30)
seen_names = set()
labels = {'ALCATRAZ ISLAND', 'ANGEL ISLAND', 'GOLDEN GATE', 'HORSESHOE BAY',
          'PRESIDIO SHOAL', 'ALCATRAZ SHOAL', 'POINT KNOX SHOAL'}
for layer in ('LNDARE', 'SEAARE'):
    for feature in features[layer]:
        name = feature['properties'].get('OBJNAM')
        if not name or name in seen_names or name.upper() not in labels:
            continue
        g = feature['geometry']
        candidates = points(g)
        if not candidates:
            rings = polygons(g)
            if not rings:
                continue
            ring = rings[0][0]
            candidates = [(sum(c[0] for c in ring)/len(ring),sum(c[1] for c in ring)/len(ring))]
        p = project(candidates[0])
        if visible(p, -150):
            draw.text(p, name.upper(), font=label_font, fill='#c7c8c5', anchor='mm', stroke_width=2, stroke_fill='#161b1e')
            seen_names.add(name)

title_font = ImageFont.truetype(FONT, 42)
small_font = ImageFont.truetype(FONT, 22)
draw.rounded_rectangle((60, SIZE[1]-215, 1250, SIZE[1]-55), radius=8, fill='#0d1216', outline='#39424a', width=2)
draw.text((90,SIZE[1]-195), 'ALCATRAZ / SAN FRANCISCO BAY', font=title_font, fill='#e1e3df')
draw.text((90,SIZE[1]-133), 'Fl W 5s · 20 M  /  native light study', font=small_font, fill='#a6b2b9')
draw.text((90,SIZE[1]-93), 'NOAA ENC data · 24 SEP 2026 · decorative preview — not for navigation', font=small_font, fill='#8e9ca6')
image.save(SAVER / 'Resources' / scene['chart']['asset'])

# Use the existing renderer's exact first-land occlusion algorithm and clearance.
with tempfile.TemporaryDirectory(prefix='openhelm-mask-') as temporary:
    temporary = Path(temporary)
    land_file, alpha_file = temporary / 'land.raw', temporary / 'alpha.raw'
    land_file.write_bytes(land.tobytes())
    code = '''import {readFileSync,writeFileSync} from 'node:fs';
import {computeLineOfSightAlpha} from './tools/screensaver-capture-page.mjs';
const [landFile,alphaFile,width,height,anchorX,anchorY]=process.argv.slice(1);
const alpha=computeLineOfSightAlpha({land:new Uint8Array(readFileSync(landFile)),width:+width,height:+height,anchorX:+anchorX,anchorY:+anchorY,clearancePixels:48});
writeFileSync(alphaFile,alpha);'''
    subprocess.run(['node','--input-type=module','-e',code,str(land_file),str(alpha_file),*map(str,SIZE),*map(str,anchor)], cwd=ROOT, check=True)
    alpha = Image.frombytes('L', SIZE, alpha_file.read_bytes())
mask = Image.new('RGBA', SIZE, (255,255,255,255))
mask.putalpha(alpha)
mask.save(SAVER / 'Resources' / scene['chart']['lightVisibilityAsset'])
land.save(DATA / 'alcatraz-land-mask.png')

receipt = dict(sourceCommit='59600977bfba0d89599452fc671279d8ae729e4e', accessed='2026-09-24',
    gdal=subprocess.check_output(['ogr2ogr','--version'],text=True).strip(),
    sources=sources['sources'],
    features={k:len(v) for k,v in features.items()},lightRecord=light,
    mask=dict(landPixels=sum(land.histogram()[1:]),visiblePixels=sum(alpha.histogram()[1:]),clearancePixels=48),
    interpretation='Decorative rotating sweep; ENC contains no sector limits for this light. Full-circle white coverage is used, clipped by first charted land. Not a claim of physical optic rotation or certified navigation portrayal.')
(DATA / 'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps(receipt,indent=2))
