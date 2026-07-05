export const STAMP_GLYPHS = ['📍', '✅', '❓', '⚠️'];

// Text scribbles render as a rasterised icon (no glyph pipeline in the style),
// so both the feature and the canvas image agree on this deterministic id.
export const textImageKey = (c, text) => `tx:${c}:${text}`;

const emptyCollection = () => ({ type: 'FeatureCollection', features: [] });

export function parseScribbles(text) {
  const strokes = new Map();
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      const msg = JSON.parse(line);
      if (!msg || typeof msg.id !== 'string') continue;
      if (msg.t === 's') strokes.set(msg.id, msg);
      if (msg.t === 'e') strokes.delete(msg.id);
    } catch {
      // A client may read while serve.py is appending; the next poll gets it.
    }
  }
  return [...strokes.values()];
}

export function toFeatures(strokes) {
  const lines = emptyCollection();
  const stamps = emptyCollection();
  for (const stroke of strokes) {
    const props = {
      id: stroke.id,
      c: stroke.c,
      h: stroke.h ?? '',
      ts: stroke.ts ?? null,
    };
    if (stroke.tx) {
      stamps.features.push({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: stroke.pts[0] },
        properties: { ...props, g: textImageKey(stroke.c, stroke.tx) },
      });
    } else if (stroke.g) {
      stamps.features.push({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: stroke.pts[0] },
        properties: { ...props, g: stroke.g },
      });
    } else {
      lines.features.push({
        type: 'Feature',
        geometry: { type: 'LineString', coordinates: stroke.pts },
        properties: props,
      });
    }
  }
  return { lines, stamps };
}
