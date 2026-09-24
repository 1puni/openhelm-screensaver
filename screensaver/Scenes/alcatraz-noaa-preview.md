# OpenHelm Alcatraz Preview

A native, offline Mac screen saver: a quiet chart of San Francisco Bay and a
white sweep from Alcatraz Light. Apple Silicon; macOS 14 or newer.

This separately named preview uses NOAA data acquired on 24 September 2026.
It contains no Swedish chart imagery or copied nautical sprites. It is a
decorative light study, **not for navigation** and not an official NOAA product.
The chart omits features and uses an original, simplified portrayal.

## Data and light

Office of Coast Survey. (2001). *NOAA Electronic Navigational Charts (ENC)*
[Dataset]. National Oceanic and Atmospheric Administration. Accessed
2026-09-24. https://doi.org/10.25923/jyyk-j845

Direct source: https://charts.noaa.gov/ENCs/ENCs.shtml

The six downloaded cells are US5OAKEF, US5OAKEG, US5OAKEH, US5OAKFF,
US5OAKFG and US5OAKFH. The source archive hashes are retained in
`source-manifest.json`; base cells and their supplied updates are read by GDAL.
Coastlines, land polygons, depth contours, soundings, bridges and coloured
navigation marks are rendered from these cells. Depth values are in metres.
The original glyphs are simple circles/triangles, not certified chart symbols.

The selected light is US5OAKFG LIGHTS record LNAM `0226014E0B1B0032` at
[-122.4221417, 37.8262289]. Its actual attributes are white, flashing,
period 5 seconds, signal sequence `00.5+(04.5)`, nominal range 20 nautical miles.
The record is retained in `build-receipt.json`. The name/characteristic is also
corroborated by the US Coast Guard 2025 Light List, volume VI, number 4315:
https://navcen.uscg.gov/sites/default/files/pdf/lightLists/LightList_V6_2025.pdf

The original OpenHelm native renderer is unchanged. Its rotating white sweep is
an artistic interpretation of the light's period; it does not reproduce the
physical optic, brightness, observer-specific flashes or atmosphere. NOAA gives
no angular sector limits for this light. The preview uses a full-circle white
range, with the existing first-land visibility mask cutting the beam at the
shoreline. The original 24-point lighthouse-footprint clearance is retained.
This is a two-dimensional chart mask, not a three-dimensional visibility model.

## Reuse terms

Read the included `NOAA-ENC-USER-AGREEMENT.html` before using this data-derived
preview. The originating NOAA agreement permits download, use and redistribution,
with the origin and agreement carried onward. Derived and redistributed products
are not official NOAA ENCs. NOAA's logos are not used and NOAA does not endorse
this preview.

Agreement: https://charts.noaa.gov/ENCs/ENC_Agreement.shtml

Data licensing: https://nauticalcharts.noaa.gov/data/data-licensing.html

The data licensing page states that Coast Survey acquired data is dedicated
under CC0-1.0 and explains externally supplied data. The ENC-specific agreement
above governs these downloaded chart products; the release carries it rather
than assuming that every chart input has an identical source licence.

## Build and verify

From this standalone source directory:

```sh
make assets
make test
make build
make visual-check
```

Generation requires GDAL's `ogr2ogr`, Pillow, Node.js and the macOS Arial font.
Reviewed tool versions: GDAL 3.13.3, Pillow 12.2.0. The generator refuses changed
source archive hashes and extracts each archive into a disposable directory.
It uses no live tile service, proprietary local data or app dependencies.
The standard native build requires Swift/macOS Command Line Tools.

Visual phases deliberately compare a fully land-occluded northwest bearing
(315 degrees) against east and south bearings. Full-circle light records cannot
use the older sector-count heuristic to choose an unlit frame.

## Release status

This is a review candidate. Its bundle is ad-hoc signed, not Developer ID signed
or notarized. It has not been installed or verified in the macOS screen saver
host. The native preview renderer, bundle structure, signature and generated
frames have been checked; the release coordinator must resolve distribution
signing and the final screen saver host check before describing installation as
seamless. Original OpenHelm code is MIT-licensed; see the root LICENSE. NOAA data retains its own terms.

The bundle display name and identifier are separate from the original screen
saver. No installer or automatic installation command is included in the zip.
