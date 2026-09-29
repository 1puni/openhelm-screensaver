# /// script
# requires-python = ">=3.11"
# dependencies = ["shapely>=2.0"]
# ///
"""Assemble an S-57-shaped GeoPackage from open inputs only.

Inputs (pinned in Provenance/tynningo-open/, see its README.md): OSM seamarks + coastline + names (ODbL),
EMODnet mean DTM (CC BY 4.0). Output layers use S-57 object/attribute acronyms
so the existing ENC-reading renderer can consume them unchanged in spirit.
Not a certified ENC; not for navigation.
"""
import gzip
import hashlib
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path

from shapely import STRtree
from shapely.geometry import LineString, Point, box, mapping, shape
from shapely.ops import linemerge, polygonize, unary_union

SAVER = Path(__file__).resolve().parents[1]
SRC = SAVER / 'Provenance/tynningo-open'
OUT = SAVER / 'build' / 'tynningo-open-enc.gpkg'
BBOX = (18.2, 59.30, 18.6, 59.45)
CONTOURS = (3, 6, 10, 20, 30, 50)  # metres below chart datum (EMODnet ~ MSL)
BANDS = (0, 3, 6, 10, 20, 30, 50, 500)

# S-57 COLOUR codes.
COLOUR = {'white': '1', 'black': '2', 'red': '3', 'green': '4', 'blue': '5', 'yellow': '6',
          'grey': '7', 'brown': '8', 'amber': '9', 'violet': '10', 'orange': '11', 'magenta': '12'}
LITCHR = {'F': 1, 'Fl': 2, 'LFl': 3, 'Q': 4, 'VQ': 5, 'UQ': 6, 'Iso': 7, 'Oc': 8, 'IQ': 9,
          'Mo': 12, 'FFl': 13, 'Al': 25}
SEAMARK_LAYER = {
    'buoy_lateral': 'BOYLAT', 'beacon_lateral': 'BCNLAT', 'buoy_cardinal': 'BOYCAR',
    'beacon_cardinal': 'BCNCAR', 'buoy_special_purpose': 'BOYSPP',
    'beacon_special_purpose': 'BCNSPP', 'buoy_isolated_danger': 'BOYISD',
    'beacon_isolated_danger': 'BCNISD', 'buoy_safe_water': 'BOYSAW',
    'beacon_safe_water': 'BCNSAW', 'wreck': 'WRECKS', 'rock': 'UWTROC',
    'obstruction': 'OBSTRN', 'recommended_track': 'RECTRC', 'fairway': 'FAIRWY',
    'cable_submarine': 'CBLSUB', 'pipeline_submarine': 'PIPSOL', 'bridge': 'BRIDGE',
    'pile': 'PILPNT', 'landmark': 'LNDMRK', 'mooring': 'MORFAC',
}


def colours(value):
    return ','.join(COLOUR[c] for c in (value or '').split(';') if c in COLOUR)


def way_geometry(element):
    coords = [(p['lon'], p['lat']) for p in element.get('geometry', []) if p]
    if len(coords) >= 4 and coords[0] == coords[-1] and element['tags'].get('natural') != 'coastline':
        from shapely.geometry import Polygon
        return Polygon(coords)
    return LineString(coords) if len(coords) >= 2 else None


def element_geometry(element):
    if element['type'] == 'node':
        return Point(element['lon'], element['lat'])
    if element['type'] == 'way':
        return way_geometry(element)
    centre = element.get('center')
    return Point(centre['lon'], centre['lat']) if centre else None


def land_polygons(coastlines, frame):
    """OSM coastline convention: land on the left of the way direction."""
    merged = linemerge(coastlines, directed=True)
    parts = list(getattr(merged, 'geoms', [merged]))
    noded = unary_union([frame.boundary, *[p.intersection(frame) for p in parts]])
    faces = list(polygonize(noded))
    tree = STRtree(faces)
    votes = [0] * len(faces)
    eps = 2e-6
    for line in parts:
        c = list(line.coords)
        for (x1, y1), (x2, y2) in zip(c, c[1:]):
            dx, dy = x2 - x1, (y2 - y1)
            n = math.hypot(dx, dy)
            if not n:
                continue
            mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            for sign in (1, -1):  # +1 = left = land
                p = Point(mx - dy / n * eps * sign, my + dx / n * eps * sign)
                for i in tree.query(p, predicate='within'):
                    votes[i] += sign
    return [f for f, v in zip(faces, votes) if v > 0], sum(1 for v in votes if v == 0)


def light_records(element, geometry):
    tags = element['tags']
    keys = sorted({k.split(':')[2] for k in tags if k.startswith('seamark:light:') and k.split(':')[2].isdigit()}, key=int)
    prefixes = [f'seamark:light:{k}:' for k in keys] or (['seamark:light:'] if any(k.startswith('seamark:light:') for k in tags) else [])
    records = []
    for prefix in prefixes:
        get = lambda k: tags.get(prefix + k) or tags.get('seamark:light:' + k)
        char = get('character') or ''
        prop = {
            'OBJNAM': tags.get('seamark:name') or tags.get('name'),
            'COLOUR': colours(get('colour')),
            'LITCHR': LITCHR.get(char),
            'SIGGRP': f'({get("group")})' if get('group') else None,
            'SIGPER': float(get('period')) if get('period') else None,
            'VALNMR': float(get('range')) if get('range') else None,
            'HEIGHT': float(get('height')) if get('height') else None,
            'SECTR1': float(get('sector_start')) if get('sector_start') else None,
            'SECTR2': float(get('sector_end')) if get('sector_end') else None,
            'OSM_REF': tags.get('seamark:light:reference'),
            'OSM_ID': f'{element["type"]}/{element["id"]}',
        }
        records.append((geometry, prop))
    return records


def main():
    frame = box(*BBOX)
    for line in (SRC / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split()
        if hashlib.sha256((SRC / name).read_bytes()).hexdigest() != digest:
            raise ValueError(f'{name}: differs from the pinned SHA256SUMS')
    seamarks = json.loads(gzip.decompress((SRC / 'osm-seamarks.json.gz').read_bytes()))['elements']
    names = json.loads(gzip.decompress((SRC / 'osm-names.json.gz').read_bytes()))['elements']
    layers = {}

    def add(layer, geometry, prop):
        if geometry is not None and not geometry.is_empty:
            layers.setdefault(layer, []).append({'type': 'Feature', 'geometry': mapping(geometry), 'properties': prop})

    coast = [way_geometry(e) for e in seamarks if e['type'] == 'way' and e['tags'].get('natural') == 'coastline']
    coast = [c for c in coast if c is not None]
    land, undecided = land_polygons(coast, frame)
    for polygon in land:
        add('LNDARE', polygon, {})
    for line in coast:
        add('COALNE', line.intersection(frame), {})
    land_union = unary_union(land)
    water = frame.difference(land_union)

    for element in seamarks:
        tags = element['tags']
        kind = tags.get('seamark:type')
        geometry = element_geometry(element)
        if kind in ('light_minor', 'light_major') or any(k.startswith('seamark:light:') for k in tags):
            for g, prop in light_records(element, geometry):
                add('LIGHTS', g, prop)
        layer = SEAMARK_LAYER.get(kind)
        if layer:
            prefix = f'seamark:{kind}:'
            add(layer, geometry, {
                'OBJNAM': tags.get('seamark:name') or tags.get('name'),
                'COLOUR': colours(tags.get(prefix + 'colour')),
                'CATLAM': tags.get(prefix + 'category'),
                'OSM_ID': f'{element["type"]}/{element["id"]}',
            })

    for element in names:
        tags = element['tags']
        kind = tags.get('place') or tags.get('natural')
        layer = {'island': 'LNDRGN', 'islet': 'LNDRGN', 'archipelago': 'LNDRGN', 'cape': 'LNDRGN',
                 'peninsula': 'LNDRGN', 'town': 'BUAARE', 'village': 'BUAARE', 'locality': 'LNDRGN',
                 'strait': 'SEAARE', 'bay': 'SEAARE'}.get(kind)
        if layer:
            add(layer, element_geometry(element), {'OBJNAM': tags['name'], 'OSM_KIND': kind,
                                                   'OSM_ID': f'{element["type"]}/{element["id"]}'})

    with tempfile.TemporaryDirectory(prefix='open-enc-') as tmp:
        tmp = Path(tmp)
        dtm = SRC / 'emodnet_mean_tynningo.tif'
        smooth = tmp / 'smooth.tif'
        subprocess.run(['gdalwarp', '-q', '-r', 'cubicspline', '-tr', str(1 / 3840), str(1 / 3840), str(dtm), str(smooth)], check=True)
        lines = tmp / 'contours.geojson'
        subprocess.run(['gdal_contour', '-q', '-a', 'ELEV', '-fl', *[str(-d) for d in reversed(CONTOURS)], str(smooth), str(lines)], check=True)
        for feature in json.loads(lines.read_text())['features']:
            g = shape(feature['geometry']).intersection(water)
            add('DEPCNT', g, {'VALDCO': -feature['properties']['ELEV']})
        bands = tmp / 'bands.geojson'
        subprocess.run(['gdal_contour', '-q', '-p', '-amin', 'AMIN', '-amax', 'AMAX', '-fl', *[str(-d) for d in reversed(BANDS)], str(smooth), str(bands)], check=True)
        for feature in json.loads(bands.read_text())['features']:
            p = feature['properties']
            if p['AMAX'] > 0:
                continue
            g = shape(feature['geometry']).buffer(0).intersection(water)
            add('DEPARE', g, {'DRVAL1': -p['AMAX'], 'DRVAL2': -p['AMIN']})

        OUT.parent.mkdir(exist_ok=True)
        OUT.unlink(missing_ok=True)
        for layer, features in sorted(layers.items()):
            path = tmp / f'{layer}.geojson'
            path.write_text(json.dumps({'type': 'FeatureCollection', 'features': features}))
            subprocess.run(['ogr2ogr', '-q', '-f', 'GPKG', '-append', '-nln', layer, '-a_srs', 'EPSG:4326', str(OUT), str(path)], check=True)

    summary = {k: len(v) for k, v in sorted(layers.items())}
    summary['_undecided_faces'] = undecided
    print(json.dumps(summary, indent=1))


if __name__ == '__main__':
    sys.exit(main())
