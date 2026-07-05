import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseScribbles, toFeatures, textImageKey } from './scribbles.js';

const line = (id, pts = [[1, 2], [3, 4]], extra = {}) =>
  JSON.stringify({ t: 's', id, c: '#e91e63', h: 'Ada', pts, ...extra });
const erase = (id) => JSON.stringify({ t: 'e', id });

test('empty input returns an empty canvas', () => {
  assert.deepEqual(parseScribbles(''), []);
  assert.deepEqual(toFeatures([]), {
    lines: { type: 'FeatureCollection', features: [] },
    stamps: { type: 'FeatureCollection', features: [] },
  });
});

test('single line becomes a line feature', () => {
  const features = toFeatures(parseScribbles(line('a1')));
  assert.equal(features.lines.features.length, 1);
  assert.equal(features.lines.features[0].geometry.type, 'LineString');
  assert.equal(features.lines.features[0].properties.h, 'Ada');
  assert.equal(features.stamps.features.length, 0);
});

test('last write wins for the same id', () => {
  const strokes = parseScribbles(`${line('same')}\n${line('same', [[5, 6], [7, 8]], { h: 'Grace' })}`);
  assert.equal(strokes.length, 1);
  assert.deepEqual(strokes[0].pts, [[5, 6], [7, 8]]);
  assert.equal(strokes[0].h, 'Grace');
});

test('tombstone removes an existing stroke', () => {
  assert.deepEqual(parseScribbles(`${line('gone')}\n${erase('gone')}`), []);
});

test('tombstone for an unknown id is a no-op', () => {
  assert.deepEqual(parseScribbles(erase('missing')), []);
});

test('bad and half-written trailing lines are skipped', () => {
  const strokes = parseScribbles(`${line('ok')}\nnot json\n{"t":"s"`);
  assert.equal(strokes.length, 1);
  assert.equal(strokes[0].id, 'ok');
});

test('stamps are routed to point features', () => {
  const features = toFeatures(parseScribbles(line('pin', [[1, 2]], { g: '📍' })));
  assert.equal(features.lines.features.length, 0);
  assert.equal(features.stamps.features.length, 1);
  assert.equal(features.stamps.features[0].geometry.type, 'Point');
  assert.equal(features.stamps.features[0].properties.g, '📍');
});

test('text labels become point features keyed by their image id', () => {
  const features = toFeatures(parseScribbles(line('lbl', [[1, 2]], { tx: 'gap here' })));
  assert.equal(features.lines.features.length, 0);
  assert.equal(features.stamps.features.length, 1);
  assert.equal(features.stamps.features[0].geometry.type, 'Point');
  assert.equal(features.stamps.features[0].properties.g, textImageKey('#e91e63', 'gap here'));
});
