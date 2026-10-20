/*
Upstream's own answers for round-2 batch R2-J2: d3-geo's geoAlbersUsa, the
projection the gallery's map-usa-projection hands ECharts
(`projection: {project: p => projection(p), unproject: p =>
projection.invert(p)}` over `d3.geoAlbersUsa()`), which the demo transcribes
in examples/advchart/ualbersusa.pas.

Runs d3-geo 2.0.1 -- the version the page loads from its CDN -- from
tools/advchart-oracle/node_modules (`npm install` in that folder; D3_GEO
overrides the path). Nothing of d3 is vendored into the repository.

  node tools/advchart-oracle/gallery-projection.js

writes tests/fixtures/advchart-gallery-projection.json (ORACLE_OUT
overrides). The drawn map (a geo over the USA map through the same
projection) is geo.js' case 'albers-usa'.

Numbers are the 16 lowercase hex digits of the IEEE double (big-endian).

Top level: source, version, notes[], project[], unproject[], guards[].
  project[]    [lon, lat, x, y]: albersUsa([lon, lat]); x and y null where it
               answers null (no inset takes the point)
  unproject[]  [x, y, lon, lat]: albersUsa.invert([x, y])
Guards: points in each of the three insets and outside all of them; two
generations byte-identical; it parses back.
*/
'use strict';
const fs = require('fs');
const path = require('path');

const D3_GEO = process.env.D3_GEO || path.join(__dirname, 'node_modules', 'd3-geo');
let d3 = null;
try { d3 = require(D3_GEO); }
catch (e) {
  console.log('This needs d3-geo 2.0.1: run `npm install` in tools/advchart-oracle (or set D3_GEO).');
  process.exit(2);
}
const VERSION = JSON.parse(fs.readFileSync(path.join(path.dirname(require.resolve(D3_GEO)), '..', 'package.json'), 'utf8')).version;
const OUT = process.env.ORACLE_OUT || path.join(__dirname, '..', '..', 'tests', 'fixtures', 'advchart-gallery-projection.json');

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  if (Number.isNaN(v)) return '7ff8000000000000';
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}

function generate() {
  const projection = d3.geoAlbersUsa();
  const project = [];
  // the lower 48, Alaska (west to -180), Hawaii, Puerto Rico and beyond
  for (let lon = -180; lon <= -55; lon += 2.5) {
    for (let lat = 10; lat <= 75; lat += 2.5) {
      const p = projection([lon, lat]);
      project.push([hex(lon), hex(lat), p ? hex(p[0]) : null, p ? hex(p[1]) : null]);
    }
  }
  // some that are not on the grid: fractions, the insets' own corners
  const extra = [[-155.5828, 19.8968], [-149.9003, 61.2181], [-66.1057, 18.4655], [-77.0369, 38.9072],
    [-122.4194, 37.7749], [-70.0, 43.123456789], [-171.3, 63.8], [-160.1, 21.9], [-67.0, 44.9]];
  for (const q of extra) {
    const p = projection(q);
    project.push([hex(q[0]), hex(q[1]), p ? hex(p[0]) : null, p ? hex(p[1]) : null]);
  }
  const unproject = [];
  for (let x = -20; x <= 980; x += 20) {
    for (let y = -10; y <= 520; y += 20) {
      const p = projection.invert([x, y]);
      unproject.push([hex(x), hex(y), hex(p[0]), hex(p[1])]);
    }
  }
  // and back from points the projection gave
  for (const r of project.slice(0, 400)) {
    if (r[2] == null) continue;
    const x = Buffer.from(r[2], 'hex').readDoubleBE(0);
    const y = Buffer.from(r[3], 'hex').readDoubleBE(0);
    const p = projection.invert([x, y]);
    unproject.push([r[2], r[3], hex(p[0]), hex(p[1])]);
  }
  return {
    source: 'd3-geo ' + VERSION + ' geoAlbersUsa(), defaults (scale 1070, translate [480, 250])',
    version: VERSION,
    notes: [
      'project: albersUsa([lon, lat]) -- the lower 48, then Alaska, then Hawaii, each clipped to its inset; null where none takes the point.',
      'unproject: albersUsa.invert([x, y]) -- the inset chosen by the point\'s place relative to the lower 48\'s translate and scale.',
    ],
    project,
    unproject,
  };
}

function guards(out) {
  const g = [];
  const add = (name, ok) => g.push({ name, ok: !!ok });
  const fromHex = h => Buffer.from(h, 'hex').readDoubleBE(0);
  const at = (lon, lat) => out.project.find(r => fromHex(r[0]) === lon && fromHex(r[1]) === lat);
  add('a point of the lower 48 projects', at(-100, 40)[2] !== null);
  add('a point of Alaska projects into its inset (left, low)', (() => {
    const r = at(-150, 62.5);
    return r[2] !== null && fromHex(r[2]) < 480 - 0.214 * 1070 && fromHex(r[3]) > 250 + 0.120 * 1070;
  })());
  add('Hawaii projects into its inset', (() => {
    const r = out.project.find(q => fromHex(q[0]) === -155.5828);
    return r[2] !== null && fromHex(r[2]) > 480 - 0.214 * 1070 && fromHex(r[2]) < 480 - 0.115 * 1070;
  })());
  add('Puerto Rico is no inset\'s: null', out.project.find(q => fromHex(q[0]) === -66.1057)[2] === null);
  add('the mid-Pacific is nobody\'s', at(-170, 10)[2] === null);
  return g;
}

let json1, json2, out1;
try {
  out1 = generate();
  out1.guards = guards(out1);
  json1 = JSON.stringify(out1, null, 1) + '\n';
  const o2 = generate();
  o2.guards = guards(o2);
  json2 = JSON.stringify(o2, null, 1) + '\n';
} catch (e) {
  console.log(e.stack);
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
const bad = out1.guards.filter(q => !q.ok);
out1.guards.forEach(q => console.log('guard ' + (q.ok ? 'ok  ' : 'FAIL') + ' ' + q.name));
let parses = true;
try { JSON.parse(json1); } catch (e) { parses = false; }
console.log(out1.project.length + ' projected, ' + out1.unproject.length + ' inverted; two runs '
  + (json1 === json2 ? 'identical' : 'DIFFERENT') + '; ' + json1.length + ' bytes');
if (bad.length || json1 !== json2 || !parses) {
  console.log('FAILED: the fixture was not written');
  process.exit(1);
}
fs.writeFileSync(OUT, json1);
console.log('wrote', OUT);
process.exit(0);
