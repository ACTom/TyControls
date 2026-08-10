# -*- coding: utf-8 -*-
"""Regenerate source/tyControls.Icons.Lucide.pas from assets/lucide/.

    python scripts/gen-lucide.py            # regenerate
    python scripts/gen-lucide.py --check    # fail if the unit is out of date (no write)

WHY PYTHON AND NOT POWERSHELL. The other generators here are .ps1 because they move text
around. This one has to base64 a 850KB binary, parse JSON into a Pascal identifier table and
emit a 1.5MB unit; PowerShell 5.1's ConvertFrom-Json hands back PSCustomObject and its string
building is quadratic at this size. scripts/ already carries Python for the non-trivial tools
(check-lfm-props.py, example-rsj2po.py, check-example-po.py).

WHAT MAKES THE OUTPUT AN OPTIONAL UNIT. The font's bytes live in a const array IN THE UNIT,
not in an .lrs: an LCL resource is linked whole-file whether or not anything reads it, so a
font in one could never be dropped. A unit is dropped by smart linking when nothing `uses` it
-- which is the whole point, because 850KB in every application that never asked for icons is
not a rounding error. That only holds while NO core unit references this one; the dependency
runs one way, from the application inwards.

THE DRIFT GUARD. The unit carries TyLucideAssetDigest, a SHA-1 over the exact asset bytes it
was generated from. tests/test.lucide.pas recomputes it from assets/lucide/ and fails if they
disagree, so editing the .ttf or the codepoint map without re-running this script is caught by
the suite rather than by a user seeing the wrong glyph.
"""
import base64
import hashlib
import io
import json
import os
import re
import sys
import zlib

# Spelled as constants so the self-digest below cannot be broken by an editor, a heredoc or a
# nested-escaping accident -- which is exactly how it was broken once already.
CRLF = b'\x0d\x0a'
LF = b'\x0a'

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, 'assets', 'lucide')
OUT = os.path.join(ROOT, 'source', 'tyControls.Icons.Lucide.pas')

TTF = os.path.join(ASSETS, 'lucide.ttf')
CPS = os.path.join(ASSETS, 'codepoints.json')
VER = os.path.join(ASSETS, 'VERSION')

B64_CHUNK = 960          # chars per array element; array of N strings, not an N-deep concat
FAMILY = 'lucide'        # sfnt nameID 1 of the vendored file, checked below


def _plain(n):
    """'a-arrow-down' -> 'TyIconAArrowDown'. Dashes vanish; capitals mark the seams."""
    return 'TyIcon' + ''.join(s[:1].upper() + s[1:] for s in n.split('-'))


def _spelled(n):
    """'arrow-down-a-z' -> 'TyIconArrow_Down_A_Z'. Every seam kept, for names the plain form
    cannot tell apart."""
    return 'TyIcon' + '_'.join(s[:1].upper() + s[1:] for s in n.split('-'))


def constant_names(names):
    """name -> Pascal constant, for the whole set at once.

    Two passes, because collisions cannot be seen one name at a time. Dropping the dashes loses
    where they were, so 'arrow-down-0-1' and 'arrow-down-01' both fold to TyIconArrowDown01 --
    and PASCAL IDENTIFIERS ARE CASE-INSENSITIVE, which is the part that is easy to miss:
    'arrow-down-a-z' (…AZ) and 'arrow-down-az' (…Az) are a duplicate to the compiler even
    though Python would call them distinct. So the collision test folds case.

    When a group collides, EVERY member of it gets the fully-spelled form -- not just the
    later ones. Handing the clean name to whichever sorted first would make the result depend
    on the order of the input file, and the next upstream icon that sorts in front would
    silently rename an existing constant.
    """
    plain = {}
    for n in names:
        plain.setdefault(_plain(n).lower(), []).append(n)
    out = {}
    for n in names:
        out[n] = _plain(n) if len(plain[_plain(n).lower()]) == 1 else _spelled(n)
    taken = {}
    for n, k in out.items():
        if k.lower() in taken:
            raise SystemExit('constant %s still collides after spelling it out: %r and %r'
                             % (k, taken[k.lower()], n))
        taken[k.lower()] = n
    return out


def sfnt_family(data):
    """Family name (nameID 1) straight out of the file, so the generated constant cannot drift
    from the bytes it names."""
    import struct
    numTables = struct.unpack_from('>H', data, 4)[0]
    tables = {}
    for i in range(numTables):
        tag, _chk, o, l = struct.unpack_from('>4sIII', data, 12 + 16 * i)
        tables[tag.decode('ascii')] = (o, l)
    o, _l = tables['name']
    _fmt, count, strOff = struct.unpack_from('>HHH', data, o)
    for i in range(count):
        pid, _eid, _lid, nid, ln, no = struct.unpack_from('>HHHHHH', data, o + 6 + 12 * i)
        if nid != 1:
            continue
        raw = data[o + strOff + no: o + strOff + no + ln]
        return raw.decode('utf-16-be') if pid == 3 else raw.decode('latin-1')
    return ''


def empty_codepoints(data, wanted):
    """The subset of `wanted` whose glyph has NO OUTLINE in this font.

    Upstream keeps a codepoint in codepoints.json forever once allocated -- that is the
    property that makes generated constants survive a font upgrade -- so the map still lists
    every icon Lucide has ever had, including the ~18 brand logos v1.0 removed. Their entries
    resolve to a glyph id whose glyf record is zero bytes long, and rendering one produces a
    blank square. Shipping those names would mean HasGlyph('github') answering True and the
    user getting nothing, which is a worse failure than not having the name at all.
    """
    import struct
    numTables = struct.unpack_from('>H', data, 4)[0]
    tab = {}
    for i in range(numTables):
        tag, _chk, o, l = struct.unpack_from('>4sIII', data, 12 + 16 * i)
        tab[tag.decode('ascii')] = (o, l)

    head_o = tab['head'][0]
    long_loca = struct.unpack_from('>h', data, head_o + 50)[0] == 1
    num_glyphs = struct.unpack_from('>H', data, tab['maxp'][0] + 4)[0]

    loca_o = tab['loca'][0]
    if long_loca:
        loca = list(struct.unpack_from('>%dI' % (num_glyphs + 1), data, loca_o))
    else:
        loca = [v * 2 for v in struct.unpack_from('>%dH' % (num_glyphs + 1), data, loca_o)]

    # cmap: prefer a format-4 windows-unicode subtable, which is what an icon font ships
    cmap_o = tab['cmap'][0]
    n = struct.unpack_from('>H', data, cmap_o + 2)[0]
    best = None
    for i in range(n):
        pid, eid, off = struct.unpack_from('>HHI', data, cmap_o + 4 + 8 * i)
        if (pid, eid) in ((3, 1), (3, 10), (0, 3), (0, 4)):
            best = cmap_o + off
            break
    if best is None:
        raise SystemExit('no usable cmap subtable in the vendored font')
    fmt = struct.unpack_from('>H', data, best)[0]
    gid = {}
    if fmt == 4:
        segX2 = struct.unpack_from('>H', data, best + 6)[0]
        seg = segX2 // 2
        ends = struct.unpack_from('>%dH' % seg, data, best + 14)
        starts = struct.unpack_from('>%dH' % seg, data, best + 16 + segX2)
        deltas = struct.unpack_from('>%dh' % seg, data, best + 16 + 2 * segX2)
        ro_base = best + 16 + 3 * segX2
        ranges = struct.unpack_from('>%dH' % seg, data, ro_base)
        for i in range(seg):
            for cp in range(starts[i], min(ends[i], 0xFFFF) + 1):
                if ranges[i] == 0:
                    g = (cp + deltas[i]) & 0xFFFF
                else:
                    addr = ro_base + 2 * i + ranges[i] + 2 * (cp - starts[i])
                    g = struct.unpack_from('>H', data, addr)[0]
                    if g:
                        g = (g + deltas[i]) & 0xFFFF
                if g:
                    gid[cp] = g
    else:
        raise SystemExit('cmap format %d not handled; the vendored font used to be format 4' % fmt)

    empty = set()
    for cp in wanted:
        g = gid.get(cp)
        if g is None or g + 1 >= len(loca) or loca[g + 1] <= loca[g]:
            empty.add(cp)
    return empty


def build():
    ttf = open(TTF, 'rb').read()
    cps_raw = open(CPS, 'rb').read()
    version = io.open(VER, encoding='utf-8').read().strip()

    fam = sfnt_family(ttf)
    if fam != FAMILY:
        raise SystemExit('the vendored font calls itself %r, not %r -- update FAMILY and the '
                         'generated constant together' % (fam, FAMILY))

    cps = json.loads(cps_raw.decode('utf-8'))
    names = sorted(cps)
    for n in names:
        if not n or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in n):
            raise SystemExit('glyph name %r is not [a-z0-9-]; the constant mangler assumes it' % n)
        v = cps[n]
        if not (0 < v <= 0x10FFFF) or 0xD800 <= v <= 0xDFFF:
            raise SystemExit('codepoint for %r is out of range: %r' % (n, v))
    blank_cps = empty_codepoints(ttf, set(cps.values()))
    dropped = sorted(n for n in names if cps[n] in blank_cps)
    names = [n for n in names if cps[n] not in blank_cps]
    if not names:
        raise SystemExit('every codepoint resolved to an empty glyph -- the font is wrong')
    consts = constant_names(names)
    spelled = sorted(n for n in names if '_' in consts[n])

    digest = hashlib.sha1(ttf + cps_raw).hexdigest().upper()
    # The generator's OWN source, so editing this script without re-running it is caught too.
    # TyLucideAssetDigest guards the inputs; this guards the transformation. Without it the
    # only check on "the .pas matches the code that produced it" was `--check`, which nothing
    # ever ran: no CI, no test, no build script -- a hand-edit of the generated unit, or an
    # edit here that was never regenerated, would ship silently.
    with io.open(__file__, 'rb') as fh:
        self_src = fh.read()
    # Normalise line endings so a git checkout under a different core.autocrlf still matches.
    self_digest = hashlib.sha1(self_src.replace(CRLF, LF)).hexdigest().upper()
    # DEFLATE first. Base64 alone costs +33%, which put 1.6MB into any executable that opted
    # in; zlib takes the font to 46% and the encoded payload to 519KB, so the opt-in costs
    # roughly what the font itself weighs instead of twice that. paszlib is in the FPC RTL,
    # so this adds no dependency.
    packed = zlib.compress(ttf, 9)
    b64 = base64.b64encode(packed).decode('ascii')
    chunks = [b64[i:i + B64_CHUNK] for i in range(0, len(b64), B64_CHUNK)]

    w = []
    a = w.append
    a("unit tyControls.Icons.Lucide;")
    a("{$mode objfpc}{$H+}")
    a("")
    a("{ Lucide, bundled. GENERATED by scripts/gen-lucide.py from assets/lucide/ -- do NOT edit")
    a("  by hand; change the assets and re-run the script. Source: %s." % version)
    a("")
    a("  THIS UNIT IS OPTIONAL AND MUST STAY THAT WAY. The font is ~850KB and it lives in the")
    a("  const array below, inside the unit, precisely so that smart linking drops the whole")
    a("  thing from any application that never writes `uses tyControls.Icons.Lucide`. An .lrs")
    a("  resource would have been linked whole-file regardless. The rule that keeps this true:")
    a("  NO other unit in this library may reference this one. The dependency points inwards,")
    a("  from the application, and tests/test.lucide.pas asserts it.")
    a("")
    a("  TWO WAYS IN, and they share one registration:")
    a("")
    a("    - drop a TTyLucideIconFont on the form and point a TTyCharImage at it. Nothing to")
    a("      write; a second icon pack later is a second component beside it rather than a")
    a("      property to switch;")
    a("    - or in code, TyLucideFont -- the same component, created once and owned here.")
    a("")
    a("      CharImage1.IconFont  := TyLucideFont;")
    a("      CharImage1.GlyphName := TyIconHouse;   { or just 'house' }")
    a("")
    a("  Either way there is nothing to put in Glyphs: this unit registers a name resolver on")
    a("  startup, so any TTyIconFont whose FontFamily is 'lucide' resolves Lucide names.")
    a("")
    a("  LICENCE. ISC (Lucide) plus MIT for the Feather-derived icons; both texts are in")
    a("  assets/lucide/LICENSE and reproduced in THIRD-PARTY-NOTICES.md, which is what an")
    a("  application shipping this unit has to carry. Nothing is required of the END USER: no")
    a("  attribution on screen, no link, no notice at run time. }")
    a("")
    a("interface")
    a("")
    a("uses")
    a("  Classes, tyControls.IconFont, tyControls.ImageCollection;")
    a("")
    a("type")
    a("  { The bundled pack as a COMPONENT. TTyIconPackFont registers the embedded bytes once")
    a("    per process, so any number of these on any number of forms cost one registration. }")
    a("  TTyLucideIconFont = class(TTyIconPackFont)")
    a("  protected")
    a("    class function PackData: RawByteString; override;")
    a("    class function PackFamily: string; override;")
    a("  end;")
    a("")
    a("  { The bundled pack as a droppable IMAGE LIST -- the third way in, made possible by the")
    a("    reparent (TTyVirtualImageList IS a TCustomImageList now). Drop it and assign it straight")
    a("    to any control's Images: no font to wire, its IconFont is the shared Lucide font, set")
    a("    once here and not streamed. Names start EMPTY -- fill the icon names you use (Names.Text,")
    a("    or the icon browser) and each becomes an image, addressable by ImageIndex or ImageName.")
    a("")
    a("    Lives in THIS generated unit on purpose: a droppable list must reference TyLucideFont,")
    a("    and the optionality rule (test.lucide.NoCoreUnitReferencesTheBundledFont) forbids any")
    a("    OTHER source unit from doing so -- so the only home that keeps the font free-when-unused")
    a("    is here, inside the unit the reference cannot escape. }")
    a("  TTyLucideImageList = class(TTyVirtualImageList)")
    a("  private")
    a("    function GetLicense: string;")
    a("  public")
    a("    constructor Create(AOwner: TComponent); override;")
    a("  published")
    a("    { Always the bundled Lucide font. stored False: the constructor sets it, and a streamed")
    a("      reference to the unit-owned shared font (no owner, no name) would nil on load. }")
    a("    property IconFont stored False;")
    a("    { Attribution for the bundled icons, shown out of respect for Lucide -- though nothing is")
    a("      required of YOUR end users at run time. Read-only: the value is the summary; the")
    a("      design-time editor pops the full ISC + MIT text (TyLucideLicense) in a Ty message box. }")
    a("    property License: string read GetLicense stored False;")
    a("  end;")
    a("")
    a("const")
    a("  { The sfnt family name of the vendored file, read out of the file by the generator.")
    a("    Assign it to any TTyIconFont you want served by the resolver below. }")
    a("  TyLucideFamily = '%s';" % FAMILY)
    a("  { The exact upstream package these bytes came from. }")
    a("  TyLucideVersion = '%s';" % version)
    a("  { SHA-1 over lucide.ttf + codepoints.json as generated. tests/test.lucide.pas")
    a("    recomputes it from assets/lucide/, so editing an asset without re-running the")
    a("    generator is a red test rather than a wrong glyph in someone's application. }")
    a("  TyLucideAssetDigest = '%s';" % digest)
    a("  { SHA-1 over scripts/gen-lucide.py itself, line-endings normalised. The asset digest")
    a("    above pins the INPUTS; this pins the TRANSFORMATION, so a hand-edit of this generated")
    a("    file -- or a generator change nobody re-ran -- is a red test instead of a silent")
    a("    mismatch between the script and its output. }")
    a("  TyLucideGeneratorDigest = '%s';" % self_digest)
    a("  { Icons in the bundled font (names plus upstream aliases). }")
    a("  TyLucideGlyphCount = %d;" % len(names))
    a("  { One-liner shown in the object inspector for TTyLucideImageList.License; the '...' pops")
    a("    the full text below. }")
    a("  TyLucideLicenseSummary =")
    a("    'Lucide icons -- ISC License + MIT (Feather-derived). Click the ... for the full text.';")
    a("  { The full ISC + MIT (Feather) text, embedded verbatim from assets/lucide/LICENSE by")
    a("    scripts/gen-lucide-license.ps1; test.lucide byte-checks it against that file. }")
    a("  {$I tyControls.Icons.Lucide.License.inc}")
    if dropped:
        a("  { %d upstream names are NOT here, and that is deliberate. Lucide keeps a codepoint" % len(dropped))
        a("    forever once allocated -- the property that makes these constants survive a font")
        a("    upgrade -- so codepoints.json still lists every icon it has ever had, including the")
        a("    brand logos v1.0 removed. Their glyf records are zero bytes long: rendering one")
        a("    gives a blank square. The generator checks the outline and drops the name, so")
        a("    HasGlyph answers honestly instead of promising an icon that draws nothing:")
        for n in dropped:
            a("      %s" % n)
        a("  }")
    a("")
    a("{ The shared instance, for code that would rather not drop a component. Created on first")
    a("  use, owned by this unit, freed at finalization -- do not free it. Check Available on the")
    a("  result if you want to know whether the registration actually took. }")
    a("function TyLucideFont: TTyLucideIconFont;")
    a("")
    a("{ The codepoint for a Lucide name, or 0. Exposed because the picker and the drift guard")
    a("  both want the table without going through a component. }")
    a("function TyLucideCodepoint(const AName: string): Cardinal;")
    a("{ Name at AIndex in 0..TyLucideGlyphCount-1, sorted; '' when out of range. }")
    a("function TyLucideGlyphName(AIndex: Integer): string;")
    a("")
    a("const")
    a("  { Named glyphs. Strings, not codepoints: the name is the stable identity across a font")
    a("    upgrade, and it is what GlyphName takes. Unreferenced ones cost nothing.")
    if spelled:
        a("")
        a("    %d of them are spelled with underscores (TyIconArrow_Down_A_Z rather than" % len(spelled))
        a("    TyIconArrowDownAZ) because dropping the dashes would make them the SAME Pascal")
        a("    identifier as a sibling -- identifiers here are case-insensitive, so ...AZ and")
        a("    ...Az collide. Both members of such a pair are spelled out, so which one gets the")
        a("    short name does not depend on the order of the upstream file:")
        for n in spelled:
            a("      %-24s -> %s" % (n, consts[n]))
    a("  }")
    for n in names:
        a("  %s = '%s';" % (consts[n], n))
    a("")
    a("implementation")
    a("")
    a("uses")
    a("  SysUtils, base64, zstream;   { Classes comes from the interface uses }")
    a("")
    a("type")
    a("  TLucideEntry = record")
    a("    Name: string;")
    a("    Codepoint: Word;")
    a("  end;")
    a("")
    a("const")
    a("  { Sorted by name, so the lookup below can binary-search it. }")
    a("  LucideMap: array[0..%d] of TLucideEntry = (" % (len(names) - 1))
    rows = ["    (Name: '%s'; Codepoint: $%04X)" % (n, cps[n]) for n in names]
    a(",\r\n".join(rows))
    a("  );")
    a("")
    a("  { The font itself: DEFLATE, then base64, as an ARRAY of literals.")
    a("")
    a("    Deflate because base64 alone is +33%% and the font is already 833KB -- encoded raw it")
    a("    put 1.6MB into every executable that opted in, against 519KB compressed.")
    a("    An array rather than one concatenated expression because %d chunks joined with '+'" % len(chunks))
    a("    is an expression tree deep enough to defeat the compiler.")
    a("    Decoded and inflated once, on first use. }")
    a("  LucideB64: array[0..%d] of string = (" % (len(chunks) - 1))
    a(",\r\n".join("    '%s'" % c for c in chunks))
    a("  );")
    a("")
    a("var")
    a("  GFont: TTyLucideIconFont = nil;")
    a("  GData: RawByteString = '';")
    a("")
    a("function TyLucideCodepoint(const AName: string): Cardinal;")
    a("var lo, hi, mid, c: Integer;")
    a("begin")
    a("  lo := Low(LucideMap); hi := High(LucideMap);")
    a("  while lo <= hi do")
    a("  begin")
    a("    mid := (lo + hi) div 2;")
    a("    c := CompareText(LucideMap[mid].Name, AName);")
    a("    if c = 0 then Exit(LucideMap[mid].Codepoint);")
    a("    if c < 0 then lo := mid + 1 else hi := mid - 1;")
    a("  end;")
    a("  Result := 0;")
    a("end;")
    a("")
    a("function TyLucideGlyphName(AIndex: Integer): string;")
    a("begin")
    a("  if (AIndex < Low(LucideMap)) or (AIndex > High(LucideMap)) then Exit('');")
    a("  Result := LucideMap[AIndex].Name;")
    a("end;")
    a("")
    a("{ The resolver TTyIconFont consults when its own Glyphs map has no entry. Declining by")
    a("  family is what lets several bundled fonts coexist. }")
    a("function LucideResolver(const AFamily, AName: string; out ACodepoint: Cardinal): Boolean;")
    a("begin")
    a("  ACodepoint := 0;")
    a("  if not SameText(AFamily, TyLucideFamily) then Exit(False);")
    a("  ACodepoint := TyLucideCodepoint(AName);")
    a("  Result := ACodepoint > 0;")
    a("end;")
    a("")
    a("{ The LIST half of the same seam, and the reason a picker or the Object Inspector's")
    a("  GlyphName dropdown has anything to show for a bundled pack: this unit maps NOTHING into")
    a("  Glyphs on purpose, so anything reading Glyphs directly saw an empty font. Only this unit")
    a("  can answer it -- LucideMap is private here, and a lookup does not invert. }")
    a("function LucideLister(const AFamily: string; ANames: TStrings): Boolean;")
    a("var i: Integer;")
    a("begin")
    a("  if not SameText(AFamily, TyLucideFamily) then Exit(False);")
    a("  { Suppresses the caller's OnChange two thousand times; Add still inserts in sorted")
    a("    position, so the de-duplication against hand-mapped names is unaffected. }")
    a("  ANames.BeginUpdate;")
    a("  try")
    a("    for i := Low(LucideMap) to High(LucideMap) do")
    a("      ANames.Add(LucideMap[i].Name);")
    a("  finally")
    a("    ANames.EndUpdate;")
    a("  end;")
    a("  Result := True;")
    a("end;")
    a("")
    a("function DecodeFont: RawByteString;")
    a("var")
    a("  i, n: Integer;")
    a("  b64: RawByteString;")
    a("  src, dst: TMemoryStream;")
    a("  unz: Tdecompressionstream;")
    a("  buf: array[0..65535] of Byte;")
    a("begin")
    a("  if GData <> '' then Exit(GData);")
    a("  { Sized in one go: appending 541 chunks to a string reallocates 541 times. }")
    a("  n := 0;")
    a("  for i := Low(LucideB64) to High(LucideB64) do Inc(n, Length(LucideB64[i]));")
    a("  SetLength(b64, n);")
    a("  n := 1;")
    a("  for i := Low(LucideB64) to High(LucideB64) do")
    a("  begin")
    a("    Move(LucideB64[i][1], b64[n], Length(LucideB64[i]));")
    a("    Inc(n, Length(LucideB64[i]));")
    a("  end;")
    a("  src := TMemoryStream.Create;")
    a("  dst := TMemoryStream.Create;")
    a("  try")
    a("    b64 := DecodeStringBase64(b64);")
    a("    if b64 = '' then Exit('');")
    a("    src.WriteBuffer(b64[1], Length(b64));")
    a("    src.Position := 0;")
    a("    unz := Tdecompressionstream.Create(src);")
    a("    try")
    a("      { Read to EOF: an inflate stream cannot report its size in advance. }")
    a("      repeat")
    a("        n := unz.Read(buf, SizeOf(buf));")
    a("        if n > 0 then dst.WriteBuffer(buf, n);")
    a("      until n <= 0;")
    a("    finally")
    a("      unz.Free;")
    a("    end;")
    a("    SetLength(GData, dst.Size);")
    a("    if dst.Size > 0 then Move(dst.Memory^, GData[1], dst.Size);")
    a("  finally")
    a("    dst.Free;")
    a("    src.Free;")
    a("  end;")
    a("  Result := GData;")
    a("end;")
    a("")
    a("class function TTyLucideIconFont.PackData: RawByteString;")
    a("begin")
    a("  Result := DecodeFont;   { cached -- this is a refcount, not an 833KB copy }")
    a("end;")
    a("")
    a("class function TTyLucideIconFont.PackFamily: string;")
    a("begin")
    a("  Result := TyLucideFamily;")
    a("end;")
    a("")
    a("function TyLucideFont: TTyLucideIconFont;")
    a("begin")
    a("  { Deliberately the same class the palette offers, so the code path and the design-time")
    a("    path cannot drift -- and the pack base makes both share one registration. }")
    a("  if GFont = nil then GFont := TTyLucideIconFont.Create(nil);")
    a("  Result := GFont;")
    a("end;")
    a("")
    a("constructor TTyLucideImageList.Create(AOwner: TComponent);")
    a("begin")
    a("  inherited Create(AOwner);")
    a("  { Wire the shared bundled font (one registration per process). Names stay empty. }")
    a("  IconFont := TyLucideFont;")
    a("end;")
    a("")
    a("function TTyLucideImageList.GetLicense: string;")
    a("begin")
    a("  Result := TyLucideLicenseSummary;")
    a("end;")
    a("")
    a("initialization")
    a("  { Registered here, not in TyLucideFont, so a name resolves on a TTyIconFont the")
    a("    application created itself -- the singleton is a convenience, not the gate. }")
    a("  TyRegisterGlyphResolver(@LucideResolver);")
    a("  TyRegisterGlyphLister(@LucideLister);")
    a("")
    a("finalization")
    a("  TyUnregisterGlyphLister(@LucideLister);")
    a("  TyUnregisterGlyphResolver(@LucideResolver);")
    a("  FreeAndNil(GFont);")
    a("")
    a("end.")
    return "\r\n".join(w) + "\r\n"


def main():
    text = build()
    check = '--check' in sys.argv
    old = None
    if os.path.exists(OUT):
        old = io.open(OUT, encoding='utf-8', newline='').read()
    if check:
        if old != text:
            raise SystemExit('tyControls.Icons.Lucide.pas is OUT OF DATE -- run '
                             'python scripts/gen-lucide.py')
        print('tyControls.Icons.Lucide.pas is up to date')
        return
    io.open(OUT, 'w', encoding='utf-8', newline='').write(text)
    m = re.search(r'TyLucideGlyphCount = (\d+);', text)
    print('wrote %s (%.1f KB, %s glyphs)' % (OUT, len(text) / 1024.0,
                                             m.group(1) if m else '?'))


if __name__ == '__main__':
    main()
