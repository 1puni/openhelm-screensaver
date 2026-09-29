#!/usr/bin/env python3
"""Render the Tynningö saver plate + visibility mask from open data only.

Runs build-open-enc.py (OSM + EMODnet -> S-57-shaped GeoPackage), then renders with the same
portrayal and first-land occlusion as build-noaa-scene.py. The light comes from NGA Pub. 116.
Requires uv (for shapely), GDAL, Pillow, Node.js and the macOS Arial fonts.
"""
import json
import math
import re
from pathlib import Path
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

SAVER = Path(__file__).resolve().parents[1]
ROOT = SAVER.parent
DATA = SAVER / 'Provenance/tynningo-open'
GPKG = SAVER / 'build/tynningo-open-enc.gpkg'
SIZE = (3456, 2234)
LAYERS = ('LNDARE', 'COALNE', 'DEPCNT', 'DEPARE', 'BOYLAT', 'BCNLAT', 'BOYCAR', 'BOYSPP', 'BCNSPP',
          'BOYISD', 'BCNSAW', 'LIGHTS', 'BRIDGE', 'LNDRGN', 'SEAARE', 'BUAARE')
FONT = '/System/Library/Fonts/Supplemental/Arial.ttf'

NGA = json.loads((DATA / 'oxdjupet-lights.json').read_text())
COLOUR_NAME = {'W': 'white', 'R': 'red', 'G': 'green'}
INK = {'white': '#d9dcda', 'red': '#eb5757', 'green': '#46cd66'}


def nga_position(record):
    parts = re.findall(r"(\d+)°(\d+)'([\d.]+)\"([NSEW])", record['position'])
    lat, lon = (int(d) + int(m) / 60 + float(sec) / 3600 for d, m, sec, _ in parts)
    return (round(lon, 7), round(lat, 7))


def nga_sectors(record):
    """Light-list sectors are bearings from seaward; return bearings from the light."""
    sectors, previous = [], None
    for token in record['remarks'].replace('\n', ' ').rstrip(' .').split(', '):
        m = re.match(r"([WRG])\.(?:\(unintensified\))?\s*(?:(\d+)°(?:(\d+)`)?)?-(\d+)°(?:(\d+)`)?", token.strip())
        if not m:
            continue
        colour, sd, sm, ed, em = m.groups()
        start = int(sd) + int(sm or 0) / 60 if sd else previous
        end = int(ed) + int(em or 0) / 60
        sectors.append((COLOUR_NAME[colour], round((start + 180) % 360, 1), round((end + 180) % 360, 1)))
        previous = end
    return sectors


def nga_ranges(record):
    return {COLOUR_NAME[c]: float(v) for c, v in re.findall(r'([WRG])\. (\d+(?:\.\d+)?)', record['range'])}


def nga_character(record):
    m = re.match(r'([A-Za-z]+)\.(\(\d+\))?([WRG.]+)\s*period (\d+(?:\.\d+)?)s', record['characteristic'].replace('\n', ' '))
    kind, group, colours, period = m.groups()
    return f"{kind}{group or ''} {colours.replace('.', '')} {period}s"


def nga_name(record):
    return record['name'].strip('-. ').split(',')[0].replace('Varmdo', 'Värmdö').replace('Tynningo', 'Tynningö').replace('Lagnogrundet', 'Lagnögrundet').replace('Sodernas', 'Södernäs')


TYNNINGO = next(r for r in NGA if 'C6570' in r['featureNumber'])
LIGHT = nga_position(TYNNINGO)
CENTER = LIGHT
ZOOM = 13.35
SCALE = 2
assert LIGHT == (18.3891389, 59.3714444), LIGHT


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


subprocess.run(['uv', 'run', '--quiet', str(SAVER / 'scripts/build-open-enc.py')], check=True)
features = {}
with tempfile.TemporaryDirectory(prefix='open-enc-render-') as tmp:
    for layer in LAYERS:
        out = Path(tmp) / f'{layer}.geojson'
        r = subprocess.run(['ogr2ogr', '-f', 'GeoJSON', str(out), str(GPKG), layer], capture_output=True, text=True)
        features[layer] = json.loads(out.read_text())['features'] if r.returncode == 0 else []

ranges = nga_ranges(TYNNINGO)
sectors = [dict(startBearing=a, endBearing=b, colour=c, rangeNauticalMiles=ranges[c]) for c, a, b in nga_sectors(TYNNINGO)]
anchor = project(LIGHT)
scene = dict(id='tynningo-open-preview', title='Tynningö — Stockholm archipelago', chart=dict(
    center=list(CENTER), zoom=ZOOM, logicalWidth=SIZE[0] // SCALE, logicalHeight=SIZE[1] // SCALE, deviceScaleFactor=SCALE,
    asset='tynningo-open-preview@2x.png', lightVisibilityAsset='tynningo-open-preview-light-visibility@2x.png'), light=dict(
    name='Tynningö', coordinate=list(LIGHT), character=nga_character(TYNNINGO), periodSeconds=6.0,
    pulses=[dict(start=0.0, end=0.48), dict(start=0.96, end=1.44)],
    anchor=dict(x=anchor[0] / SIZE[0], y=anchor[1] / SIZE[1]), sectors=sectors))
(SAVER / 'Scenes/tynningo-open-preview.json').write_text(json.dumps(scene, indent=2, ensure_ascii=False) + '\n')

image = Image.new('RGB', SIZE, '#090c0e')
draw = ImageDraw.Draw(image)
land = Image.new('L', SIZE)
land_draw = ImageDraw.Draw(land)
for feature in features['LNDARE']:
    for polygon in polygons(feature['geometry']):
        for index, ring in enumerate(polygon):
            land_draw.polygon([project(c) for c in ring], fill=0 if index else 255)

# EMODnet-derived contours (~115 m source grid): generalised, decorative.
# Shallow-water stipple, same rule as the OpenHelm gray theme (app/src/theme.ts):
# 4x4 physical-pixel dots, 24 px pitch for 0-3 m, 32 px pitch for 3-6 m, none deeper.
STIPPLE = ((0, 24, 0x80), (3, 32, 0x60))
for drval1, pitch, ink in STIPPLE:
    band = Image.new('L', SIZE)
    band_draw = ImageDraw.Draw(band)
    for feature in features['DEPARE']:
        if feature['properties']['DRVAL1'] != drval1:
            continue
        for polygon in polygons(feature['geometry']):
            for index, ring in enumerate(polygon):
                band_draw.polygon([project(c) for c in ring], fill=0 if index else 255)
    dots = Image.new('RGB', SIZE, (ink, ink, ink))
    grid = Image.new('L', SIZE)
    grid_draw = ImageDraw.Draw(grid)
    for y in range(0, SIZE[1], pitch):
        for x in range(0, SIZE[0], pitch):
            grid_draw.rectangle((x, y, x + 3, y + 3), fill=255)
    from PIL import ImageChops
    image.paste(dots, (0, 0), ImageChops.multiply(band, grid))
draw = ImageDraw.Draw(image)

for feature in features['DEPCNT']:
    if feature['properties']['VALDCO'] < 6:
        continue  # the 3 m isoline is mostly EMODnet grid noise at this scale
    for line in lines(feature['geometry']):
        draw.line([project(c) for c in line], fill='#30383d', width=2)

land_plate = Image.new('RGB', SIZE, '#313436')
land_ink = ImageDraw.Draw(land_plate)
for y in range(0, SIZE[1], 15):
    for x in range((y // 15 % 2) * 7, SIZE[0], 15):
        land_ink.rectangle((x, y, x + 1, y + 1), fill='#464a4c')
image.paste(land_plate, (0, 0), land)
draw = ImageDraw.Draw(image)
for feature in features['COALNE']:
    for line in lines(feature['geometry']):
        draw.line([project(c) for c in line], fill='#9a9e9f', width=2)
for feature in features['BRIDGE']:
    for line in lines(feature['geometry']):
        draw.line([project(c) for c in line], fill='#d2d0c8', width=5)

colours = {'1': '#d9dcda', '3': '#eb5757', '4': '#46cd66', '6': '#e4c756'}
for layer in ('BOYLAT', 'BCNLAT', 'BOYCAR', 'BOYSPP', 'BCNSPP', 'BOYISD', 'BCNSAW'):
    seen = set()
    for feature in features[layer]:
        prop = feature['properties']
        for coordinate in points(feature['geometry']):
            x, y = project(coordinate)
            key = (round(x), round(y))
            if not visible((x, y), -20) or key in seen:
                continue
            seen.add(key)
            colour = colours.get((prop.get('COLOUR') or '').split(',')[0], '#a6acab')
            radius = 5 if layer == 'LIGHTS' else 7
            if layer.startswith('BCN'):
                draw.polygon([(x, y - radius), (x + radius, y + radius), (x - radius, y + radius)], outline=colour, width=3)
            elif layer == 'BOYCAR':
                draw.polygon([(x, y - radius), (x + radius, y), (x, y + radius), (x - radius, y)], outline=colour, width=3)
            else:
                draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=colour, width=3)
            if layer != 'LIGHTS':
                draw.line((x, y + radius, x, y + radius + 7), fill=colour, width=2)

# Paper-chart style sector arcs for every NGA-listed light in view (the saver animates Tynningö).
light_font = ImageFont.truetype(FONT, 22)
taken = []


def place(box):
    if any(box[0] < b[2] and b[0] < box[2] and box[1] < b[3] and b[1] < box[3] for b in taken):
        return False
    taken.append(box)
    return True


for record in NGA:
    x, y = project(nga_position(record))
    if not visible((x, y), 60):
        continue
    radius = 70
    taken.append((x - radius - 18, y - radius - 18, x + radius + 18, y + radius + 18))
    for colour, start, end in nga_sectors(record):
        a, b = start - 90, end - 90
        if b <= a:
            b += 360
        draw.arc((x - radius, y - radius, x + radius, y + radius), a, b, fill=INK[colour], width=6)
        for bearing in (start, end):
            t = math.radians(bearing)
            draw.line((x, y, x + math.sin(t) * (radius + 18), y - math.cos(t) * (radius + 18)), fill='#59646b', width=2)
    draw.ellipse((x - 6, y - 6, x + 6, y + 6), fill='#f1e3a0')
    for dy in (radius + 34, -(radius + 58)):
        text = f'{nga_name(record)}\n{nga_character(record)}'
        box = draw.multiline_textbbox((x, y + dy), text, font=light_font, anchor='ma', align='center')
        if place(box):
            draw.multiline_text((x, y + dy), text, font=light_font, fill='#c9ccc6', anchor='ma', align='center',
                                stroke_width=2, stroke_fill='#0b0f12')
            break

# Place names from OSM, largest features first, skipping any that collide.
styles = {'town': (34, FONT, '#dcdcd6'), 'island': (32, FONT, '#c7c8c5'), 'village': (26, FONT, '#b5b8b4'),
          'islet': (22, FONT, '#a9adab'), 'strait': (26, '/System/Library/Fonts/Supplemental/Arial Italic.ttf', '#8e9ca6'),
          'bay': (22, '/System/Library/Fonts/Supplemental/Arial Italic.ttf', '#7f8c95')}
order = ['town', 'island', 'strait', 'village', 'bay', 'islet']
named = [f for layer in ('BUAARE', 'LNDRGN', 'SEAARE') for f in features[layer] if f['properties'].get('OSM_KIND') in styles]
named.sort(key=lambda f: order.index(f['properties']['OSM_KIND']))
seen_names = set()
for feature in named:
    prop = feature['properties']
    size, face, fill = styles[prop['OSM_KIND']]
    p = project(points(feature['geometry'])[0])
    if prop['OBJNAM'] in seen_names or not visible(p, -80):
        continue
    font = ImageFont.truetype(face, size)
    box = draw.textbbox(p, prop['OBJNAM'], font=font, anchor='mm')
    if place((box[0] - 8, box[1] - 6, box[2] + 8, box[3] + 6)):
        draw.text(p, prop['OBJNAM'], font=font, fill=fill, anchor='mm', stroke_width=2, stroke_fill='#161b1e')
        seen_names.add(prop['OBJNAM'])

image.save(SAVER / 'Resources' / scene['chart']['asset'])

with tempfile.TemporaryDirectory(prefix='open-enc-mask-') as tmp:
    tmp = Path(tmp)
    land_file, alpha_file = tmp / 'land.raw', tmp / 'alpha.raw'
    land_file.write_bytes(land.tobytes())
    code = '''import {readFileSync,writeFileSync} from 'node:fs';
import {computeLineOfSightAlpha} from './tools/screensaver-capture-page.mjs';
const [landFile,alphaFile,width,height,anchorX,anchorY]=process.argv.slice(1);
const alpha=computeLineOfSightAlpha({land:new Uint8Array(readFileSync(landFile)),width:+width,height:+height,anchorX:+anchorX,anchorY:+anchorY,clearancePixels:48});
writeFileSync(alphaFile,alpha);'''
    subprocess.run(['node', '--input-type=module', '-e', code, str(land_file), str(alpha_file), *map(str, SIZE), *map(str, anchor)],
                   cwd=ROOT, check=True)
    alpha = Image.frombytes('L', SIZE, alpha_file.read_bytes())
mask = Image.new('RGBA', SIZE, (255, 255, 255, 255))
mask.putalpha(alpha)
mask.save(SAVER / 'Resources' / scene['chart']['lightVisibilityAsset'])
receipt = dict(accessed='2026-09-29', gdal=subprocess.check_output(['ogr2ogr', '--version'], text=True).strip(),
               sources=(DATA / 'SHA256SUMS').read_text().splitlines(),
               features={k: len(v) for k, v in features.items()}, lightRecord=TYNNINGO,
               mask=dict(landPixels=sum(land.histogram()[1:]), visiblePixels=sum(alpha.histogram()[1:]), clearancePixels=48),
               interpretation='Decorative rotating sweep over the NGA-listed sectors and nominal ranges, clipped by first charted '
                              'land. Flash durations are a rendering choice; NGA does not list them.')
(DATA / 'build-receipt.json').write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n')
print(json.dumps(receipt, indent=2, ensure_ascii=False))
