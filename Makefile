SHELL := /bin/sh
SCENE := $(CURDIR)/screensaver/Scenes/alcatraz-noaa-preview.json
RESOURCES := $(CURDIR)/screensaver/Resources
BIN = $(shell swift build --disable-sandbox --package-path screensaver --show-bin-path)
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/screensaver/.build/module-cache
export CLANG_MODULE_CACHE_PATH := $(CURDIR)/screensaver/.build/clang-cache
.PHONY: test assets build alcatraz visual-check preview

test:
	node --test tests/scene.test.mjs
	swift test --disable-sandbox --package-path screensaver

assets:
	python3 screensaver/scripts/build-noaa-scene.py
	python3 screensaver/scripts/build-tynningo-scene.py

# OpenHelm Lighthouses: one universal saver, Tynningö + Alcatraz, chosen under Options….
build:
	screensaver/scripts/package-lighthouses.sh

# The original single-scene Alcatraz preview zip.
alcatraz:
	screensaver/scripts/package-noaa-preview.sh

preview:
	swift build --disable-sandbox --package-path screensaver --product OpenHelmChartSaverPreview
	'$(BIN)/OpenHelmChartSaverPreview' --scene '$(SCENE)' --resources '$(RESOURCES)'

visual-check:
	swift build --disable-sandbox --package-path screensaver --product OpenHelmChartSaverPreview
	mkdir -p screensaver/.visual-check
	'$(BIN)/OpenHelmChartSaverPreview' --scene '$(SCENE)' --resources '$(RESOURCES)' --snapshot '$(CURDIR)/screensaver/.visual-check/inactive.png' --phase 4.625 --width 1728 --height 1117 --scale 2
	'$(BIN)/OpenHelmChartSaverPreview' --scene '$(SCENE)' --resources '$(RESOURCES)' --snapshot '$(CURDIR)/screensaver/.visual-check/active-a.png' --phase 1.5 --width 1728 --height 1117 --scale 2
	'$(BIN)/OpenHelmChartSaverPreview' --scene '$(SCENE)' --resources '$(RESOURCES)' --snapshot '$(CURDIR)/screensaver/.visual-check/active-b.png' --phase 2.75 --width 1728 --height 1117 --scale 2
	swift screensaver/scripts/verify-frame-diff.swift screensaver/.visual-check/inactive.png screensaver/.visual-check/active-a.png screensaver/.visual-check/active-b.png '$(RESOURCES)/alcatraz-noaa-preview-light-visibility@2x.png' 2284 1228
