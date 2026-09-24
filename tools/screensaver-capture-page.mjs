// First-land occlusion, extracted unchanged from the OpenHelm renderer.
export function computeLineOfSightAlpha({
  land,
  width,
  height,
  anchorX,
  anchorY,
  clearancePixels,
  angleBins,
}) {
  if (!(land instanceof Uint8Array) || land.length !== width * height) {
    throw new Error("line-of-sight land raster has the wrong dimensions");
  }
  const cornerRadii = [
    Math.hypot(anchorX, anchorY),
    Math.hypot(width - 1 - anchorX, anchorY),
    Math.hypot(anchorX, height - 1 - anchorY),
    Math.hypot(width - 1 - anchorX, height - 1 - anchorY),
  ];
  const maximumRadius = Math.ceil(Math.max(...cornerRadii));
  const binCount = angleBins ?? Math.max(4096, Math.ceil(2 * Math.PI * maximumRadius));
  const firstLand = new Float32Array(binCount);
  firstLand.fill(maximumRadius + 1);

  for (let bin = 0; bin < binCount; bin += 1) {
    const angle = (bin + 0.5) / binCount * Math.PI * 2;
    const dx = Math.cos(angle);
    const dy = Math.sin(angle);
    for (let radius = clearancePixels; radius <= maximumRadius; radius += 0.5) {
      const x = Math.round(anchorX + dx * radius);
      const y = Math.round(anchorY + dy * radius);
      if (x < 0 || x >= width || y < 0 || y >= height) break;
      if (land[y * width + x]) {
        firstLand[bin] = radius;
        break;
      }
    }
  }

  const alpha = new Uint8ClampedArray(width * height);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const index = y * width + x;
      if (land[index]) continue;
      const dx = x - anchorX;
      const dy = y - anchorY;
      const radius = Math.hypot(dx, dy);
      const normalizedAngle = (Math.atan2(dy, dx) + Math.PI * 2) % (Math.PI * 2);
      const bin = Math.min(binCount - 1, Math.floor(normalizedAngle / (Math.PI * 2) * binCount));
      if (radius < firstLand[bin]) alpha[index] = 255;
    }
  }
  return alpha;
}

