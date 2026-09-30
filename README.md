# OpenHelm Lighthouses

An offline native Mac screen saver: a quiet nautical chart and a lighthouse sweeping its real
sectors, stopping at the first land it meets. Two charts, chosen under **Options…** in
System Settings → Screen Saver, where each chart's data credits are also shown:

- **Tynningö — Stockholm archipelago** (default): Fl(2) WRG 6s over Oxdjupet, built only from
  open data — OpenStreetMap (ODbL), EMODnet Bathymetry (CC BY 4.0) and NGA's List of Lights
  (public domain). See [its provenance](screensaver/Provenance/tynningo-open/README.md).
- **Alcatraz — San Francisco Bay**: Fl W 5s from NOAA Electronic Navigational Charts under
  [NOAA's agreement](screensaver/Provenance/noaa/ENC_Agreement.html). See
  [its provenance](screensaver/Scenes/alcatraz-noaa-preview.md).

**macOS 14 or newer, Apple Silicon and Intel.** Decorative light studies, **not for
navigation**; neither chart is an official product of any hydrographic office. The chart
plates carry no text; credits travel beside them, in the saver and in the release zip.

## Build locally

Apple Command Line Tools (Swift 6+) and Node.js build everything from the included PNGs:

```sh
make test
make build        # → screensaver/build/lighthouses-release/OpenHelm-Lighthouses-macOS.zip
make preview
```

`make build` compiles a universal saver carrying both scenes, loads the built bundle through
its principal class the way the screen saver host does, renders a preview clip per chart,
zips it with README, credits and licences, then re-verifies the unzipped bundle. It never
installs anything. `make alcatraz` still builds the original single-scene Alcatraz preview.

`make assets` regenerates all chart plates and visibility masks from the pinned sources.
That additionally needs Python with Pillow 12.2.0, GDAL 3.13.3 (`ogr2ogr`, `gdalwarp`,
`gdal_contour`), [uv](https://docs.astral.sh/uv/) (for shapely) and macOS Arial. Both
builds refuse inputs that differ from their recorded hashes; the plates repeat byte for byte.

## Download status

The release binary is **ad-hoc signed, not Developer ID signed or notarised**, so macOS
may say it cannot verify the developer. After a first double-click, use **System Settings →
Privacy & Security → Open Anyway**, then double-click the saver again. See
[Apple's explanation](https://support.apple.com/en-gb/102445). No command here disables
Gatekeeper or removes quarantine.

## Source scope

A standalone export of the screen saver from the original OpenHelm source (private history
not included). Renderer/core source is preserved; the preview's default scene, build entry
points and test fixtures are adapted for this export, and geometry in Swift tests is
explicitly synthetic. `SOURCE_MANIFEST.json` lists every file with its SHA-256.

Original code: [MIT](LICENSE), copyright 2026 OpenHelm contributors, with existing
authorship retained. This licence does not relicense chart data (each source keeps its own
terms above) or system fonts, which are used locally for rendering and not distributed.

## 1puni island edition

[1puni — Tynningö](docs/1puni-tynningo.md) is an additional native saver with the
original unicorn emblem and `1puni.com` set into the island. `make brand` builds
its separate bundle; `make install-brand` installs it for the current user.
