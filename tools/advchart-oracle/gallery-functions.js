/*
[R2-J2] The gallery as the oracles before R2-J2 read it.

Since R2-J2 the harvest writes every function of a page as a name
('@<id>.<key>', '@<id>.<key>#2': tools/advchart-gallery/harvest.js); before,
only a renderItem and a projection were named and every other function was
dropped. The oracles that feed a gallery file to upstream as it stands
(markers-point, matrix, series-calendar, sunburst, treemap, datazoom-slider)
recorded what upstream draws WITHOUT those functions -- and a '@name' handed
to upstream is a string (a formatter template that prints itself), not the
function. withoutFunctions takes the names back out, so the file is the one
those fixtures were made from; the port's tests do the same
(tests/test.advchart.gallerytext.pas). What the functions do is
gallery-callbacks.js' to say.

A renderItem's name ('@<id>', '@<id>#2') and a projection's
('@<id>.project' / '.unproject') stay: they were named before too.
*/
'use strict';

const FN_REF = /^@[A-Za-z0-9_-]+\.[A-Za-z]+(#[0-9]+)?$/;

function isFunctionRef(key, value) {
  return typeof value === 'string' && FN_REF.test(value)
    && key !== 'project' && key !== 'unproject';
}

function withoutFunctions(v) {
  if (Array.isArray(v)) return v.map(withoutFunctions);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) {
      if (isFunctionRef(k, v[k])) continue;
      o[k] = withoutFunctions(v[k]);
    }
    return o;
  }
  return v;
}

module.exports = { withoutFunctions, isFunctionRef };
