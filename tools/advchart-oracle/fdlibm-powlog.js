'use strict';
// Math.log and Math.pow as V8 computes them, transcribed line by line from
// V8 12.4.254.21 src/base/ieee754.cc (node 22): log at :1638-1720 (fdlibm
// e_log.c unchanged) and pow at :2645-2906 (fdlibm e_pow.c with ONE line
// changed, :2894, marked below). tyControls.AdvChart.JsMath's TyJsLog and
// TyJsPow follow this file statement for statement; js-pow-log.js holds it to
// node's Math.pow / Math.log on every fixture row and on a fresh seeded draw.
//
// Pascal port notes (each also at the line it concerns):
//   - Doubles only, evaluated as written: one IEEE rounding per operation, no
//     fused multiply-add, no x87 extended intermediates (win64 SSE2 is fine;
//     on i386 build with -CfSSE2 or the results drift).
//   - Every constant by its bit pattern (the hex words beside it), never by
//     the decimal literal: FPC does not promise a correctly rounded literal.
//   - Word surgery: hi(x) = LongInt(QWord(x) shr 32), lo(x) = LongWord(QWord(x)),
//     withHi / withLo replace one half, fromWords builds a Double from two.
//   - Integers are 32-bit and wrap: {$R-}{$Q-} around the routines. C's
//     ">>" on a signed int is arithmetic; FPC's "shr" is logical, so a shift
//     whose left side can be negative is SarLongint (marked SAR below). The
//     ones not marked have a non-negative left side.
//   - Results V8 writes as signaling_NaN / infinity / huge*huge / tiny*tiny
//     are NaN, +-Infinity, +-0: return those values directly. Do not rely on
//     masked FPU traps to turn an overflowing multiply into Infinity.
//   - sqrt is IEEE-exact everywhere (FPC Sqrt = sqrtsd).
//
//   node -e "const F = require('./tools/advchart-oracle/fdlibm-powlog.js'); console.log(F.pow(10, -4))"

const dv = new DataView(new ArrayBuffer(8));
// GET_HIGH_WORD: the sign and exponent word, as a signed 32-bit integer
function hi(x) { dv.setFloat64(0, x); return dv.getInt32(0); }
// GET_LOW_WORD: the low mantissa word, as an unsigned 32-bit integer
function lo(x) { dv.setFloat64(0, x); return dv.getUint32(4); }
// INSERT_WORDS
function fromWords(h, l) { dv.setInt32(0, h | 0); dv.setUint32(4, l >>> 0); return dv.getFloat64(0); }
// SET_HIGH_WORD
function withHi(x, h) { dv.setFloat64(0, x); dv.setInt32(0, h | 0); return dv.getFloat64(0); }
// SET_LOW_WORD
function withLo(x, l) { dv.setFloat64(0, x); dv.setUint32(4, l >>> 0); return dv.getFloat64(0); }
const W = fromWords;

// ------------------------------------------------------------------ log
// ieee754.cc:1638-1650
const ln2_hi = W(0x3fe62e42, 0xfee00000);   // 6.93147180369123816490e-01
const ln2_lo = W(0x3dea39ef, 0x35793c76);   // 1.90821492927058770002e-10
const two54 = W(0x43500000, 0x00000000);    // 1.80143985094819840000e+16
const Lg1 = W(0x3FE55555, 0x55555593);      // 6.666666666666735130e-01
const Lg2 = W(0x3FD99999, 0x9997FA04);      // 3.999999999940941908e-01
const Lg3 = W(0x3FD24924, 0x94229359);      // 2.857142874366239149e-01
const Lg4 = W(0x3FCC71C5, 0x1D8E78AF);      // 2.222219843214978396e-01
const Lg5 = W(0x3FC74664, 0x96CB03DE);      // 1.818357216161805012e-01
const Lg6 = W(0x3FC39A09, 0xD078C69F);      // 1.531383769920937332e-01
const Lg7 = W(0x3FC2F112, 0xDF3E5244);      // 1.479819860511658591e-01
const third = W(0x3FD55555, 0x55555555);    // the literal 0.33333333333333333 (:1690)

function log(x) {
  let hfsq, f, s, z, R, w, t1, t2, dk;
  let k, hx, i, j;                              // int32_t
  let lx;                                       // uint32_t

  hx = hi(x); lx = lo(x);                       // EXTRACT_WORDS(hx, lx, x)

  k = 0;
  if (hx < 0x00100000) {                        // x < 2**-1022
    if (((hx & 0x7fffffff) | lx) === 0)
      return -Infinity;                         // log(+-0) = -inf
    if (hx < 0)
      return NaN;                               // log(-#) = NaN (V8: signaling_NaN)
    k -= 54;
    x *= two54;                                 // subnormal number, scale up x
    hx = hi(x);                                 // GET_HIGH_WORD(hx, x)
  }
  if (hx >= 0x7ff00000) return x + x;           // +inf or NaN
  k += (hx >> 20) - 1023;                       // hx > 0 here: shr is fine
  hx &= 0x000fffff;
  i = (hx + 0x95f64) & 0x100000;
  x = withHi(x, hx | (i ^ 0x3ff00000));         // SET_HIGH_WORD: normalize x or x/2
  k += (i >> 20);
  f = x - 1.0;
  if ((0x000fffff & (2 + hx)) < 3) {            // -2**-20 <= f < 2**-20
    if (f === 0.0) {
      if (k === 0) return 0.0;
      dk = k;                                   // static_cast<double>(k)
      return dk * ln2_hi + dk * ln2_lo;
    }
    R = f * f * (0.5 - third * f);
    if (k === 0) return f - R;
    dk = k;
    return dk * ln2_hi - ((R - dk * ln2_lo) - f);
  }
  s = f / (2.0 + f);
  dk = k;
  z = s * s;
  i = (hx - 0x6147a) | 0;
  w = z * z;
  j = (0x6b851 - hx) | 0;
  t1 = w * (Lg2 + w * (Lg4 + w * Lg6));
  t2 = z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)));
  i |= j;
  R = t2 + t1;
  if (i > 0) {
    hfsq = 0.5 * f * f;
    if (k === 0) return f - (hfsq - s * (hfsq + R));
    return dk * ln2_hi - ((hfsq - (s * (hfsq + R) + dk * ln2_lo)) - f);
  }
  if (k === 0) return f - s * (f - R);
  return dk * ln2_hi - ((s * (f - R) - dk * ln2_lo) - f);
}

// ------------------------------------------------------------------ pow
// ieee754.cc:2646-2676
const bp = [1.0, 1.5];
const dp_h = [0.0, W(0x3FE2B803, 0x40000000)];  // 5.84962487220764160156e-01
const dp_l = [0.0, W(0x3E4CFDEB, 0x43CFD006)];  // 1.35003920212974897128e-08
const two53 = W(0x43400000, 0x00000000);        // 9007199254740992.0
const huge = W(0x7E37E43C, 0x8800759C);         // 1.0e300
const tiny = W(0x01A56E1F, 0xC2F8F359);         // 1.0e-300
const L1 = W(0x3FE33333, 0x33333303);           // 5.99999999999994648725e-01
const L2 = W(0x3FDB6DB6, 0xDB6FABFF);           // 4.28571428578550184252e-01
const L3 = W(0x3FD55555, 0x518F264D);           // 3.33333329818377432918e-01
const L4 = W(0x3FD17460, 0xA91D4101);           // 2.72728123808534006489e-01
const L5 = W(0x3FCD864A, 0x93C9DB65);           // 2.30660745775561754067e-01
const L6 = W(0x3FCA7E28, 0x4A454EEF);           // 2.06975017800338417784e-01
const P1 = W(0x3FC55555, 0x5555553E);           // 1.66666666666666019037e-01
const P2 = W(0xBF66C16C, 0x16BEBD93);           // -2.77777777770155933842e-03
const P3 = W(0x3F11566A, 0xAF25DE2C);           // 6.61375632143793436117e-05
const P4 = W(0xBEBBBD41, 0xC5D26BF1);           // -1.65339022054652515390e-06
const P5 = W(0x3E663769, 0x72BEA4D0);           // 4.13813679705723846039e-08
const lg2 = W(0x3FE62E42, 0xFEFA39EF);          // 6.93147180559945286227e-01
const lg2_h = W(0x3FE62E43, 0x00000000);        // 6.93147182464599609375e-01
const lg2_l = W(0xBE205C61, 0x0CA86C39);        // -1.90465429995776804525e-09
const ovt = W(0x3C971547, 0x652B82FE);          // 8.0085662595372944372e-17
const cp = W(0x3FEEC709, 0xDC3A03FD);           // 9.61796693925975554329e-01 = 2/(3 ln2)
const cp_h = W(0x3FEEC709, 0xE0000000);         // 9.61796700954437255859e-01
const cp_l = W(0xBE3E2FE0, 0x145B01F5);         // -7.02846165095275826516e-09
const ivln2 = W(0x3FF71547, 0x652B82FE);        // 1.44269504088896338700e+00 = 1/ln2
const ivln2_h = W(0x3FF71547, 0x60000000);      // 1.44269502162933349609e+00
const ivln2_l = W(0x3E54AE0B, 0xF85DDF44);      // 1.92596299112661746887e-08
// the literal 0.3333333333333333333333 (:2771)
// (third above, W(0x3FD55555, 0x55555555), is the same Double)

// std::scalbn(z, n) (V8 calls the C library's): x * 2**n with one rounding. It
// is reached only for a subnormal result, where every correct scalbn gives the
// same Double; this is fdlibm s_scalbn.c, which does.
const twom54 = W(0x3C900000, 0x00000000);       // 5.55111512312578270212e-17
function scalbn(x, n) {
  let k, hx, lx;
  hx = hi(x); lx = lo(x);
  k = (hx & 0x7ff00000) >> 20;                  // extract exponent (non-negative: shr)
  if (k === 0) {                                // 0 or subnormal x
    if ((lx | (hx & 0x7fffffff)) === 0) return x;   // +-0
    x *= two54;
    hx = hi(x);
    k = ((hx & 0x7ff00000) >> 20) - 54;
    if (n < -50000) return tiny * x;            // underflow
  }
  if (k === 0x7ff) return x + x;                // NaN or Inf
  k = k + n;
  if (k > 0x7fe) return x < 0 ? -Infinity : Infinity;             // overflow
  if (k > 0) return withHi(x, (hx & 0x800fffff) | (k << 20));     // normal result
  if (k <= -54) {
    if (n > 50000) return x < 0 ? -Infinity : Infinity;           // overflow
    return x < 0 ? -0 : 0;                                        // underflow
  }
  k += 54;                                      // subnormal result
  x = withHi(x, (hx & 0x800fffff) | (k << 20));
  return x * twom54;
}

// textbook = true: netlib fdlibm 5.3's r line instead of V8's (for the
// generator's self-check only; the port has no such switch)
function powImpl(x, y, textbook) {
  let z, ax, z_h, z_l, p_h, p_l;
  let y1, t1, t2, r, s, t, u, v, w;
  let i, j, k, yisint, n;                       // int
  let hx, hy, ix, iy;                           // int
  let lx, ly;                                   // unsigned

  hx = hi(x); lx = lo(x);                       // EXTRACT_WORDS(hx, lx, x)
  hy = hi(y); ly = lo(y);                       // EXTRACT_WORDS(hy, ly, y)
  ix = hx & 0x7fffffff;
  iy = hy & 0x7fffffff;

  // y==zero: x**0 = 1
  if ((iy | ly) === 0) return 1.0;

  // +-NaN return x+y
  if (ix > 0x7ff00000 || ((ix === 0x7ff00000) && (lx !== 0)) || iy > 0x7ff00000 ||
      ((iy === 0x7ff00000) && (ly !== 0)))
    return x + y;                               // NaN

  // determine if y is an odd int when x < 0
  // yisint = 0 ... y is not an integer, 1 ... an odd int, 2 ... an even int
  yisint = 0;
  if (hx < 0) {
    if (iy >= 0x43400000) {
      yisint = 2;                               // even integer y
    } else if (iy >= 0x3ff00000) {
      k = (iy >> 20) - 0x3ff;                   // exponent
      if (k > 20) {
        j = ly >>> (52 - k);                    // ly is unsigned: a logical shift (shr)
        // (j << (52 - k)) == static_cast<int>(ly): compare the 32 bits
        if (((j << (52 - k)) >>> 0) === ly) yisint = 2 - (j & 1);
      } else if (ly === 0) {
        j = iy >> (20 - k);
        if ((j << (20 - k)) === iy) yisint = 2 - (j & 1);
      }
    }
  }

  // special value of y
  if (ly === 0) {
    if (iy === 0x7ff00000) {                    // y is +-inf
      if (((ix - 0x3ff00000) | lx) === 0) {
        return y - y;                           // (+-1)**+-inf is NaN
      } else if (ix >= 0x3ff00000) {            // (|x|>1)**+-inf = inf,0
        return (hy >= 0) ? y : 0.0;
      } else {                                  // (|x|<1)**-,+inf = inf,0
        return (hy < 0) ? -y : 0.0;
      }
    }
    if (iy === 0x3ff00000) {                    // y is +-1
      if (hy < 0) return 1.0 / x;               // base::Divide(one, x): IEEE x/0 = +-inf
      return x;
    }
    if (hy === 0x40000000) return x * x;        // y is 2
    if (hy === 0x3fe00000) {                    // y is 0.5
      if (hx >= 0) return Math.sqrt(x);         // x >= +0
    }
  }

  ax = Math.abs(x);                             // fabs
  // special value of x
  if (lx === 0) {
    if (ix === 0x7ff00000 || ix === 0 || ix === 0x3ff00000) {
      z = ax;                                   // x is +-0,+-inf,+-1
      if (hy < 0) z = 1.0 / z;                  // z = (1/|x|); base::Divide: 1/0 = +inf
      if (hx < 0) {
        if (((ix - 0x3ff00000) | yisint) === 0) {
          z = NaN;                              // (-1)**non-int is NaN (V8: signaling_NaN)
        } else if (yisint === 1) {
          z = -z;                               // (x<0)**odd = -(|x|**odd)
        }
      }
      return z;
    }
  }

  n = (hx >> 31) + 1;                           // SAR: SarLongint(hx, 31) + 1: 0 if x<0, else 1

  // (x<0)**(non-int) is NaN
  if ((n | yisint) === 0) return NaN;           // V8: signaling_NaN

  s = 1.0;                                      // s (sign of result -ve**odd) = -1 else = 1
  if ((n | (yisint - 1)) === 0) s = -1.0;       // (-ve)**(odd int)

  // |y| is huge
  if (iy > 0x41e00000) {                        // if |y| > 2**31
    if (iy > 0x43f00000) {                      // if |y| > 2**64, must o/uflow
      if (ix <= 0x3fefffff) return (hy < 0) ? Infinity : 0.0;       // huge*huge : tiny*tiny
      if (ix >= 0x3ff00000) return (hy > 0) ? Infinity : 0.0;
    }
    // over/underflow if x is not close to one
    if (ix < 0x3fefffff) return (hy < 0) ? s * Infinity : s * 0.0;  // s*huge*huge : s*tiny*tiny
    if (ix > 0x3ff00000) return (hy > 0) ? s * Infinity : s * 0.0;
    // now |1-x| is tiny <= 2**-20, suffice to compute
    // log(x) by x-x^2/2+x^3/3-x^4/4
    t = ax - 1.0;                               // t has 20 trailing zeros
    w = (t * t) * (0.5 - t * (third - t * 0.25));
    u = ivln2_h * t;                            // ivln2_h has 21 sig. bits
    v = t * ivln2_l - w * ivln2;
    t1 = u + v;
    t1 = withLo(t1, 0);                         // SET_LOW_WORD(t1, 0)
    t2 = v - (t1 - u);
  } else {
    let ss, s2, s_h, s_l, t_h, t_l;
    n = 0;
    // take care subnormal number
    if (ix < 0x00100000) {
      ax *= two53;
      n -= 53;
      ix = hi(ax);                              // GET_HIGH_WORD(ix, ax)
    }
    n += (ix >> 20) - 0x3ff;
    j = ix & 0x000fffff;
    // determine interval
    ix = j | 0x3ff00000;                        // normalize ix
    if (j <= 0x3988E) {
      k = 0;                                    // |x|<sqrt(3/2)
    } else if (j < 0xBB67A) {
      k = 1;                                    // |x|<sqrt(3)
    } else {
      k = 0;
      n += 1;
      ix -= 0x00100000;
    }
    ax = withHi(ax, ix);                        // SET_HIGH_WORD(ax, ix)

    // compute ss = s_h+s_l = (x-1)/(x+1) or (x-1.5)/(x+1.5)
    u = ax - bp[k];                             // bp[0]=1.0, bp[1]=1.5
    v = 1.0 / (ax + bp[k]);                     // base::Divide(one, ax + bp[k]); never 0 here
    ss = u * v;
    s_h = ss;
    s_h = withLo(s_h, 0);                       // SET_LOW_WORD(s_h, 0)
    // t_h=ax+bp[k] High
    t_h = 0.0;
    t_h = withHi(t_h, ((ix >> 1) | 0x20000000) + 0x00080000 + (k << 18));
    t_l = ax - (t_h - bp[k]);
    s_l = v * ((u - s_h * t_h) - s_h * t_l);
    // compute log(ax)
    s2 = ss * ss;
    r = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))));
    r += s_l * (s_h + ss);
    s2 = s_h * s_h;
    t_h = 3.0 + s2 + r;                         // (3.0 + s2) + r
    t_h = withLo(t_h, 0);                       // SET_LOW_WORD(t_h, 0)
    t_l = r - ((t_h - 3.0) - s2);
    // u+v = ss*(1+...)
    u = s_h * t_h;
    v = s_l * t_h + t_l * ss;
    // 2/(3log2)*(ss+...)
    p_h = u + v;
    p_h = withLo(p_h, 0);                       // SET_LOW_WORD(p_h, 0)
    p_l = v - (p_h - u);
    z_h = cp_h * p_h;                           // cp_h+cp_l = 2/(3*log2)
    z_l = cp_l * p_h + p_l * cp + dp_l[k];
    // log2(ax) = (ss+..)*2/(3*log2) = n + dp_h + z_h + z_l
    t = n;                                      // static_cast<double>(n)
    t1 = (((z_h + z_l) + dp_h[k]) + t);
    t1 = withLo(t1, 0);                         // SET_LOW_WORD(t1, 0)
    t2 = z_l - (((t1 - t) - dp_h[k]) - z_h);
  }

  // split up y into y1+y2 and compute (y1+y2)*(t1+t2)
  y1 = y;
  y1 = withLo(y1, 0);                           // SET_LOW_WORD(y1, 0)
  p_l = (y - y1) * t1 + y * t2;
  p_h = y1 * t1;
  z = p_l + p_h;
  j = hi(z); i = lo(z) | 0;                     // EXTRACT_WORDS(j, i, z): i is an int
  if (j >= 0x40900000) {                        // z >= 1024
    if (((j - 0x40900000) | i) !== 0) {         // if z > 1024
      return s * Infinity;                      // overflow: s * huge * huge
    } else {
      if (p_l + ovt > z - p_h) return s * Infinity;   // overflow
    }
  } else if ((j & 0x7fffffff) >= 0x4090cc00) {  // z <= -1075
    // C: (j - 0xc090cc00u) | i in unsigned arithmetic; only "!= 0" is read, so
    // Pascal: (LongWord(j) - LongWord($C090CC00)) or LongWord(i) <> 0
    if (((j - 0xc090cc00) | i) !== 0) {         // z < -1075
      return s * 0.0;                           // underflow: s * tiny * tiny (+-0)
    } else {
      if (p_l <= z - p_h) return s * 0.0;       // underflow
    }
  }
  // compute 2**(p_h+p_l)
  i = j & 0x7fffffff;
  k = (i >> 20) - 0x3ff;
  n = 0;
  if (i > 0x3fe00000) {                         // if |z| > 0.5, set n = [z+0.5]
    n = (j + (0x00100000 >> (k + 1))) | 0;      // k + 1 >= 0 here
    k = ((n & 0x7fffffff) >> 20) - 0x3ff;       // new k for n
    t = 0.0;
    t = withHi(t, n & ~(0x000fffff >> k));      // SET_HIGH_WORD(t, ...); k >= 0 here
    n = ((n & 0x000fffff) | 0x00100000) >> (20 - k);
    if (j < 0) n = -n;
    p_h -= t;
  }
  t = p_l + p_h;
  t = withLo(t, 0);                             // SET_LOW_WORD(t, 0)
  u = t * lg2_h;
  v = (p_l - (t - p_h)) * lg2 + t * lg2_l;
  z = u + v;
  w = v - (z - u);
  t = z * z;
  t1 = z - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
  if (textbook) {
    r = (z * t1) / (t1 - 2.0) - (w + z * w);    // fdlibm 5.3 e_pow.c
  } else {
    // V8 :2894 -- NOT fdlibm: the correction w + z*w sits inside the divisor.
    //   r = base::Divide(z * t1, (t1 - two) - (w + z * w));
    // The divisor is never 0 here (|z| <= ln2/2), so it is a plain division.
    r = (z * t1) / ((t1 - 2.0) - (w + z * w));
  }
  z = 1.0 - (r - z);
  j = hi(z);                                    // GET_HIGH_WORD(j, z)
  j = (j + (n << 20)) | 0;                      // j += int(uint32(n) << 20): wraps, {$Q-}{$R-}
  if ((j >> 20) <= 0) {                         // SAR: SarLongint(j, 20) <= 0
    z = scalbn(z, n);                           // subnormal output
  } else {
    // GET_HIGH_WORD(tmp, z); SET_HIGH_WORD(z, tmp + int(uint32(n) << 20)): the j above
    z = withHi(z, j);
  }
  return s * z;
}

function pow(x, y) { return powImpl(x, y, false); }
function powTextbook(x, y) { return powImpl(x, y, true); }

module.exports = { log, pow, powTextbook, scalbn, hi, lo, fromWords, withHi, withLo };
