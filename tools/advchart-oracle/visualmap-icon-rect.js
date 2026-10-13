// Upstream's box for a custom visualMap icon (F1b): graphic.makePath(path, {},
// box, 'center') -- what createSymbol does for a 'path://' icon that keeps its
// aspect -- then getBoundingRect() of the result, which is PathProxy's: a
// curve's box is its extrema (bbox.fromCubic / fromQuadratic), not its control
// points.
//
//   node tools/advchart-oracle/visualmap-icon-rect.js
//
// prints one line per icon: the four numbers as IEEE-754 hex, and as text.
const DIST = process.env.ECHARTS_DIST || 'D:/Projects/echarts/dist/echarts.js';
const echarts = require(DIST);

const bits = new DataView(new ArrayBuffer(8));
function hex(v) {
  bits.setFloat64(0, v);
  return bits.getUint32(0).toString(16).padStart(8, '0') + bits.getUint32(4).toString(16).padStart(8, '0');
}

const ICONS = [
  // two cubics whose handles reach well past the curve
  'M0,0 C10,-20 30,-20 40,0 C30,20 10,20 0,0 Z',
  // two quadratics, the same
  'M0,0 Q20,-30 40,0 Q20,30 0,0 Z',
];
try {
  for (const icon of ICONS) {
    const box = new echarts.graphic.BoundingRect(-12, -12, 24, 24);
    const p = echarts.graphic.makePath(icon, {}, box, 'center');
    const r = p.getBoundingRect();
    console.log(JSON.stringify(icon) + ' ' + [r.x, r.y, r.width, r.height].map(hex).join(' ')
      + ' | ' + [r.x, r.y, r.width, r.height].join(' '));
  }
} catch (e) {
  console.log(e.stack);
  process.exit(1);
}
process.exit(0);
