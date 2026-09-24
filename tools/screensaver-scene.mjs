import { readFile } from "node:fs/promises";

const fail = (path, message) => { throw new Error(`${path}: ${message}`); };
const finite = (value, path) => {
  if (typeof value !== "number" || !Number.isFinite(value)) fail(path, "must be finite");
  return value;
};
const positiveInteger = (value, path) => {
  finite(value, path);
  if (!Number.isSafeInteger(value) || value <= 0) fail(path, "must be a positive safe integer");
  return value;
};
const coordinate = (value, path) => {
  if (!Array.isArray(value) || value.length !== 2) fail(path, "must be [longitude, latitude]");
  const longitude = finite(value[0], `${path}[0]`);
  const latitude = finite(value[1], `${path}[1]`);
  if (longitude < -180 || longitude > 180) fail(`${path}[0]`, "outside [-180,180]");
  if (latitude < -90 || latitude > 90) fail(`${path}[1]`, "outside [-90,90]");
  return [longitude, latitude];
};

export function validateSaverScene(value) {
  if (!value || typeof value !== "object") fail("scene", "must be an object");
  if (typeof value.id !== "string" || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value.id)) fail("id", "must be lower-case kebab-case");
  if (typeof value.title !== "string" || !value.title.trim()) fail("title", "must be non-empty");
  const chart = value.chart;
  if (!chart || typeof chart !== "object") fail("chart", "must be an object");
  chart.center = coordinate(chart.center, "chart.center");
  finite(chart.zoom, "chart.zoom");
  chart.logicalWidth = positiveInteger(chart.logicalWidth, "chart.logicalWidth");
  chart.logicalHeight = positiveInteger(chart.logicalHeight, "chart.logicalHeight");
  chart.deviceScaleFactor = positiveInteger(chart.deviceScaleFactor, "chart.deviceScaleFactor");
  if (!Number.isSafeInteger(chart.logicalWidth * chart.deviceScaleFactor) ||
      !Number.isSafeInteger(chart.logicalHeight * chart.deviceScaleFactor)) {
    fail("chart.dimensions", "physical dimensions exceed safe integer range");
  }
  if (typeof chart.asset !== "string" || !/^[A-Za-z0-9@._-]+\.png$/.test(chart.asset)) fail("chart.asset", "must be a basename ending in .png");
  if (typeof chart.lightVisibilityAsset !== "string" ||
      !/^[A-Za-z0-9@._-]+\.png$/.test(chart.lightVisibilityAsset) ||
      chart.lightVisibilityAsset === chart.asset) {
    fail("chart.lightVisibilityAsset", "must be a distinct basename ending in .png");
  }
  const light = value.light;
  if (!light || typeof light !== "object") fail("light", "must be an object");
  if (typeof light.name !== "string" || !light.name.trim()) fail("light.name", "must be non-empty");
  light.coordinate = coordinate(light.coordinate, "light.coordinate");
  if (typeof light.character !== "string" || !light.character.trim()) fail("light.character", "must be non-empty");
  finite(light.periodSeconds, "light.periodSeconds");
  if (light.periodSeconds <= 0) fail("light.periodSeconds", "must be positive");
  if (!light.anchor || typeof light.anchor !== "object") fail("light.anchor", "must be an object");
  for (const axis of ["x", "y"]) {
    finite(light.anchor[axis], `light.anchor.${axis}`);
    if (light.anchor[axis] < 0 || light.anchor[axis] > 1) fail(`light.anchor.${axis}`, "outside [0,1]");
  }
  if (!Array.isArray(light.pulses) || light.pulses.length === 0) fail("light.pulses", "must be a non-empty array");
  let previousEnd = -Infinity;
  let hasDarkGap = light.pulses[0]?.start > 0;
  light.pulses.forEach((pulse, index) => {
    const path = `light.pulses[${index}]`;
    if (!pulse || typeof pulse !== "object") fail(path, "must be an object");
    finite(pulse.start, `${path}.start`);
    finite(pulse.end, `${path}.end`);
    if (pulse.start < 0 || pulse.end <= pulse.start || pulse.end > light.periodSeconds) fail("light.pulses", "pulse outside period or non-positive");
    if (pulse.start < previousEnd) fail("light.pulses", "pulses overlap or are unordered");
    if (previousEnd >= 0 && pulse.start > previousEnd) hasDarkGap = true;
    previousEnd = pulse.end;
  });
  if (previousEnd < light.periodSeconds) hasDarkGap = true;
  if (!hasDarkGap) fail("light.pulses", "must leave a dark interval");
  if (!Array.isArray(light.sectors) || light.sectors.length === 0) {
    fail("light.sectors", "must be a non-empty array");
  }
  let previousSectorEnd = -Infinity;
  light.sectors.forEach((sector, index) => {
    const path = `light.sectors[${index}]`;
    if (!sector || typeof sector !== "object") fail(path, "must be an object");
    finite(sector.startBearing, `${path}.startBearing`);
    finite(sector.endBearing, `${path}.endBearing`);
    finite(sector.rangeNauticalMiles, `${path}.rangeNauticalMiles`);
    if (sector.startBearing < 0 || sector.startBearing >= 360) {
      fail(`${path}.startBearing`, "outside [0,360)");
    }
    if (sector.endBearing <= 0 || sector.endBearing > 360) {
      fail(`${path}.endBearing`, "outside (0,360]");
    }
    if (sector.endBearing <= sector.startBearing) fail(path, "must have positive angular width");
    if (!new Set(["white", "red", "green"]).has(sector.colour)) {
      fail(`${path}.colour`, "must be white, red, or green");
    }
    if (sector.rangeNauticalMiles <= 0) {
      fail(`${path}.rangeNauticalMiles`, "must be positive");
    }
    if (sector.startBearing < previousSectorEnd) {
      fail("light.sectors", "sectors overlap or are unordered");
    }
    previousSectorEnd = sector.endBearing;
  });
  return value;
}

export async function readSaverScene(path) {
  return validateSaverScene(JSON.parse(await readFile(path, "utf8")));
}

