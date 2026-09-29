# Tynningö open-data scene inputs

Pinned inputs for `scripts/build-tynningo-scene.py`; the build refuses files that differ from
`SHA256SUMS`. Area 18.2–18.6°E, 59.30–59.45°N. Acquired 2026-09-29.

| File | Source | Licence |
|---|---|---|
| `osm-seamarks.json.gz` | OpenStreetMap via Overpass: `seamark:type=*` and `natural=coastline`, osm_base 2026-09-29T09:16:34Z. Contributor user/uid/changeset metadata stripped. | ODbL 1.0, © OpenStreetMap contributors |
| `osm-names.json.gz` | OpenStreetMap via Overpass: named `place=island/islet/town/village/locality/archipelago`, `natural=strait/bay/cape/peninsula`. Metadata stripped. | ODbL 1.0, © OpenStreetMap contributors |
| `emodnet_mean_tynningo.tif` | EMODnet Bathymetry DTM, WCS coverage `emodnet__mean`, 1/16′ grid (~115 m), EPSG:4326. | CC BY 4.0, EMODnet Bathymetry Consortium |
| `oxdjupet-lights.json` | NGA Pub. 116 List of Lights records C6544, C6568, C6570, C6571, C6572 from `https://msi.nga.mil/api/publications/ngalol/lights-buoys?volume=116&output=json&includeRemovals=false`. | US Government work, public domain |

`build-open-enc.py` assembles these into an S-57-shaped GeoPackage (LNDARE, COALNE, DEPARE,
DEPCNT, LIGHTS, BOYLAT, …; not a certified ENC). `build-tynningo-scene.py` renders the plate and
first-land visibility mask from it and writes `build-receipt.json` here.

Known limits: EMODnet cannot resolve narrow channels such as Oxdjupet (~100 m), so shallow-water
stipple is patchy. OSM carries almost none of the unlit lateral buoys in this area, and NGA lists
lighted aids only, so the plate draws the five NGA lights' sectors instead of buoys.

Swedish official chart and depth data (Sjöfartsverket) is licensed, not open; none is used.
