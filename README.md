# OpenHelm Alcatraz Preview

An offline native Mac screen saver: NOAA's San Francisco Bay geography, a
monochrome chart, and a rotating white sweep from Alcatraz Light.

**Apple Silicon · macOS 14 or newer.** The minimum OS comes from the build target;
not every supported macOS version has been tested. This decorative preview is
not for navigation and is not an official NOAA product.

The original renderer is MIT-licensed OpenHelm code. This standalone source has
no private repository history, Swedish chart resources, app data, downloaded
sprites or dependency on the full OpenHelm application. NOAA data retains its
own terms: read [the source and data provenance](screensaver/Scenes/alcatraz-noaa-preview.md)
and [NOAA's agreement](screensaver/Provenance/noaa/ENC_Agreement.html).

## Build locally

Apple Command Line Tools (Swift 6+) and Node.js are enough to build from the
included PNGs. Recreating those PNGs also requires Python with Pillow 12.2.0,
GDAL 3.13.3 (`ogr2ogr`) and macOS Arial. No credentials or online service is used.

```sh
make test
make build
make visual-check
make preview
```

The zip appears at
`screensaver/build/OpenHelm-Alcatraz-Preview-macOS-arm64.zip`.
`make assets` regenerates the plate and visibility mask from the pinned NOAA
archives. Chart and mask hashes repeat with the recorded tools.

## Download status

This binary is **ad-hoc signed, not Developer ID signed or notarized**. A Mac may
block downloaded software from an unidentified developer. The local bundle-load
check does not reproduce Gatekeeper's downloaded-file path, and installation in
the macOS screen saver host has not been tested. No command here disables
Gatekeeper or removes quarantine. See [Apple's explanation](https://support.apple.com/en-gb/102445).

The native preview can be built and inspected locally. A signed, notarized build
and a normal screen saver installation check are still needed for a frictionless
public binary release. No installer runs as part of any command above.

## Source scope

Extracted from the original OpenHelm source at
`59600977bfba0d89599452fc671279d8ae729e4e`, with the NOAA preview change on
`handoff/noaa-alcatraz-screensaver-preview`. Renderer/core source is preserved;
the preview's default scene, build entry points and test fixtures are adapted
for this standalone export. Geometry in Swift tests is explicitly synthetic.

Original code: [MIT](LICENSE), copyright 2026 OpenHelm contributors, with
existing authorship retained. This licence does not relicense NOAA data or
system fonts; fonts are used locally for rendering and are not distributed.
