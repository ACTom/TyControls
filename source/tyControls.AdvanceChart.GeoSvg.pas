unit tyControls.AdvanceChart.GeoSvg;
{$mode objfpc}{$H+}
{ SVG MAPS [F6b]: echarts.registerMap(name, svg-object) and what GeoSVGResource
  makes of it -- zrender 6.1's tool/parseXML.ts and tool/parseSVG.ts, ported
  line for line onto FCL's DOM, and GeoSVGResource._buildGraphic of ECharts
  6.1 (coord/geo/GeoSVGResource.ts).

  WHY NOT BGRASVG. BGRABitmap carries an SVG reader, and the plan named it.
  It is a renderer's reader: it follows the specification (inline style over
  the presentation attributes, opacity not inherited, percentages, units,
  <use>, CSS classes), and that is exactly what the upstream parser does not
  do. zrender reads the attributes AFTER the inline style (so an attribute
  wins), inherits opacity like any other style key, reads a width of '50%'
  as 50, applies a viewBox with xMidYMid only, measures text through its own
  width table, ignores <use>, <style> and classes, skips any unknown tag with
  everything under it, and turns a transform into Transformable props through
  setLocalTransform (so getLocalTransform gives it back with the last bits
  moved). Every one of those decides a coordinate, a colour or whether an
  element is there at all; matching them on top of another parser's model
  would mean undoing half its work. The XML itself is FCL's (DOM, XMLRead):
  a conforming parser, as the browser's DOMParser is.

  THE GRAPHIC is a flat preorder list of nodes -- node 0 the extra root group
  _buildGraphic adds, node 1 the parsed <svg> root, then the document's
  elements -- each with its Transformable props, its own style keys as the
  parser leaves them (the inherited dictionary applied, url() fills resolved
  through the defs), its shape as zrender builds its PathProxy (a <path>'s
  data through createPathProxyFromString, so a Float32Array past eleven
  numbers), and the named items of the region-available tags.

  TEXT is measured while parsing (a <tspan> moves on by the width of the text
  before it), so the build takes a measurer; zrender's server-side fallback
  table is here as TyGsSsrWidth.

  PURE: SysUtils, Classes, Math, FCL's DOM and XMLRead, the AdvanceChart value
  units. }
interface

uses
  SysUtils, Classes, Math, DOM, XMLRead,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape, tyControls.AdvanceChart.ZrPath;

type
  { the zrender element a node is }
  TTyGsKind = (gskGroup, gskRect, gskCircle, gskLine, gskEllipse, gskPolygon,
    gskPolyline, gskImage, gskTSpan, gskPath);

  { a Transformable's props (no origin, no anchor: the parser sets none) }
  TTyGsTrans = record
    X, Y, ScaleX, ScaleY, Rotation, SkewX, SkewY: Double;
  end;

  { a fill or a stroke as the style holds it: never set (the element's own
    default), set to undefined (an url() to no paint server), null ('none'),
    a colour string, a paint server }
  TTyGsPaintKind = (gpUnset, gpUndefined, gpNone, gpColour, gpGradient);
  TTyGsPaint = record
    Kind: TTyGsPaintKind;
    Colour: string;
    Grad: Integer;
  end;

  TTyGsStop = record
    Offset: Double;
    Colour: string;
  end;
  { LinearGradient / RadialGradient as parseSVG makes them: the coordinates
    through parseInt, global for gradientUnits userSpaceOnUse }
  TTyGsGradient = record
    Radial, Global: Boolean;
    X, Y, X2, Y2, R: Double;
    Stops: array of TTyGsStop;
  end;

  { a font: zrender's string (Css, '' for none: the default font) and its
    parts }
  TTyGsFont = record
    Css: string;
    SizePx: Double;
    Family, Weight, Style: string;
  end;
  { the width of a text in a font, CSS px (platformApi.measureText) }
  TTyGsMeasure = function(const AText: string; const AFont: TTyGsFont): Double of object;

  TTyGsNumKey = (gnLineWidth, gnOpacity, gnFillOpacity, gnStrokeOpacity,
    gnMiterLimit, gnFontSize);
  TTyGsStrKey = (gsLineDashOffset, gsLineCap, gsLineJoin, gsFontWeight,
    gsFontFamily, gsFontStyle, gsTextAlign, gsTextBaseline);

  { the style keys parseAttributes sets (Has: the key is the element's own) }
  TTyGsStyle = record
    Fill, Stroke: TTyGsPaint;
    NumHas: array[TTyGsNumKey] of Boolean;
    Num: array[TTyGsNumKey] of Double;
    StrHas: array[TTyGsStrKey] of Boolean;
    Str: array[TTyGsStrKey] of string;
    HasDash: Boolean;
    Dash: TTyDoubleArray;
    { a tspan's text, font (HasFont: the parser made one) and measured size:
      the width and getLineHeight }
    Text: string;
    HasFont: Boolean;
    Font: TTyGsFont;
    TextW, TextH: Double;
    { an image's source and box }
    Image: string;
    IX, IY, IW, IH: Double;
  end;

  TTyGsNode = record
    Kind: TTyGsKind;
    Parent: Integer;
    Children: TTyIntegerArray;
    T: TTyGsTrans;
    Silent, Invisible, Ignore: Boolean;
    St: TTyGsStyle;
    { the shape: the numbers the element's shape holds (rect x y w h,
      circle cx cy r, ellipse cx cy rx ry, line x1 y1 x2 y2, points), and the
      PathProxy its buildPath makes; Box that proxy's getBoundingRect }
    V: TTyDoubleArray;
    Path: TTyZrPath;
    PathF32: Boolean;
    Box: TTyXYWH;
  end;
  TTyGsNodeArray = array of TTyGsNode;

  { a named item of a region-available tag: From the named item (index in
    Named) of the <g name> it hangs under, -1 when self-named }
  TTyGsNamed = record
    Name: string;
    From: Integer;
    Tag: string;
    Node: Integer;
  end;

  TTyGsGraphic = record
    Ok: Boolean;
    Nodes: TTyGsNodeArray;
    Named: array of TTyGsNamed;
    Grads: array of TTyGsGradient;
    { the svg's width / height (NaN: none) and viewBox }
    Width, Height: Double;
    HasViewBox: Boolean;
    ViewBox: TTyXYWH;
    { the resource's boundingRect }
    Rect: TTyXYWH;
  end;

  { per node, what Path.getBoundingRect reads of the style: whether it
    strokes and fills, the line width, and the line scale (strokeNoScale:
    the global transform's, else 1) }
  TTyGsStroke = record
    HasStroke, HasFill: Boolean;
    LineWidth, LineScale: Double;
  end;
  TTyGsStrokeArray = array of TTyGsStroke;

const
  TyGsRootNode = 0;
  TyGsParsedRootNode = 1;

{ parseXML: the document and its <svg> element (the first child, or a later
  sibling, named svg case-insensitively). False when the text is not XML or
  has no svg element (upstream throws). The caller frees ADoc. }
function TyGsParseDocument(const AText: string; out ADoc: TXMLDocument;
  out ASvg: TDOMElement): Boolean;

{ GeoSVGResource._buildGraphic over parseSVG(svg, ignoreViewBox and
  ignoreRootClip): the nodes, the defs applied, the bounding rect (AHasRect:
  the resource's first one, reused), the viewBox transform on the parsed
  root, the named items of the region-available tags made non-silent. Not Ok
  where upstream throws. }
function TyGsBuild(ASvg: TDOMElement; const AMeasure: TTyGsMeasure;
  AHasRect: Boolean; const ARect: TTyXYWH): TTyGsGraphic;

{ zrender's measureText when there is no canvas: per character the default
  width table (a font with 'mono' in it: the font size each), the font size
  read off the font string }
function TyGsSsrWidth(const AText: string; const AFont: TTyGsFont): Double;

{ ---- the geometry ---- }

{ Transformable.getLocalTransform }
function TyGsLocal(const T: TTyGsTrans): TTyMat2D;
{ needLocalTransform: any prop farther than 5e-5 from the identity's }
function TyGsNeedLocal(const T: TTyGsTrans): Boolean;
{ setLocalTransform }
function TyGsDecompose(const M: TTyMat2D): TTyGsTrans;
function TyGsMatMul(const M1, M2: TTyMat2D): TTyMat2D;
function TyGsMatInvert(const A: TTyMat2D; out AOut: TTyMat2D): Boolean;
function TyGsMatIdentity: TTyMat2D;
{ BoundingRect.applyTransform }
function TyGsRectApply(const R: TTyXYWH; const M: TTyMat2D): TTyXYWH;
{ BoundingRect.union }
procedure TyGsRectUnion(var R: TTyXYWH; const O: TTyXYWH);

{ the default stroke and fill of a node's element where the style leaves
  them out: a Path and a TSpan fill '#000' (DEFAULT_TSPAN_STYLE takes
  DEFAULT_PATH_STYLE's); a Line or a Polyline strokes '#000' and does not
  fill; an Image neither }
function TyGsDefaultFill(AKind: TTyGsKind): string;
function TyGsDefaultStroke(AKind: TTyGsKind): string;
{ hasStroke / hasFill of the parser's own style (no option over it) }
function TyGsOwnStroke(const N: TTyGsNode): TTyGsStroke;

{ Element.getBoundingRect of a node, its own coordinates: a Path's proxy box
  grown by the stroke (AStroke per node), a TSpan's text rect, an Image's
  box, a Group's children through their local transforms (the ignored and
  the invisible left out) }
function TyGsNodeRect(const G: TTyGsGraphic; ANode: Integer;
  const AStroke: TTyGsStrokeArray): TTyXYWH;

{ GeoSVGRegion.calcCenter: the centre of the node's rect through the
  INVERSE of the local transforms from it up to the parsed root }
function TyGsRegionCentre(const G: TTyGsGraphic; ANode: Integer;
  const AStroke: TTyGsStrokeArray): TTyPointF;

{ the commands a canvas draws for a PathProxy's data, through AM: a
  quadratic raised to a cubic, an arc or an ellipse's arc (rotated by its
  psi) as cubics of at most a quarter turn, a rect as four lines -- an affine
  map takes each exactly. APoints: the outline sampled (the curves at 24
  points each), for the bounds. }
procedure TyGsPathCmds(const APath: TTyZrPath; const AM: TTyMat2D;
  out ACmds: TTyPathCmdArray; out APoints: TTyPointFArray);

{ is the tag one a region may be (GeoSVGResource's REGION_AVAILABLE) }
function TyGsRegionTag(const ATag: string): Boolean;
{ MapDraw's OPTION_STYLE_ENABLED_TAGS }
function TyGsStyleTag(const ATag: string): Boolean;
{ STATE_TRIGGER_TAG_MAP and LABEL_HOST_MAP: the style tags and g }
function TyGsStateTag(const ATag: string): Boolean;

implementation

uses
  tyControls.AdvanceChart.JsMath, tyControls.AdvanceChart.Data, tyControls.AdvanceChart.Scale,
  tyControls.AdvanceChart.Color;

const
  cTransEps = 5e-5;
  cJsPiOne: Double = 3.141592653589793;
  cJsPiTwo: Double = 6.283185307179586;

{ ==================== small JS pieces ==================== }

{ JavaScript's parseInt(s, 10) }
function JsParseInt(const S: string): Double;
var t: string; i, n: Integer; neg: Boolean; v: Double;
begin
  t := TyJsTrim(S + 'x');
  Delete(t, Length(t), 1);
  i := 1;
  neg := False;
  if (i <= Length(t)) and ((t[i] = '-') or (t[i] = '+')) then
  begin
    neg := t[i] = '-';
    Inc(i);
  end;
  n := 0;
  v := 0;
  while (i <= Length(t)) and (t[i] in ['0'..'9']) do
  begin
    v := v * 10 + (Ord(t[i]) - Ord('0'));
    Inc(i);
    Inc(n);
  end;
  if n = 0 then Exit(NaN);
  if neg then v := -v;
  Result := v;
end;

{ Number(x) of an attribute: null is 0 }
function JsNumberOfAttr(AHas: Boolean; const S: string): Double;
begin
  if not AHas then Exit(0);
  Result := TyJsToNumber(S);
end;

{ the regex /-?([0-9]*\.)?[0-9]+([eE]-?[0-9]+)?/g of splitNumberSequence }
function SplitNumbers(const S: string): TTyStringArray;
var
  i, n, p, e: Integer;

  function Digits(AFrom: Integer): Integer;
  begin
    Result := AFrom;
    while (Result <= n) and (S[Result] in ['0'..'9']) do Inc(Result);
  end;

  { the match starting at AAt, its end (exclusive) or 0 }
  function MatchAt(AAt: Integer): Integer;
  var k, k2, k3, start: Integer;
  begin
    Result := 0;
    start := AAt;
    if (start <= n) and (S[start] = '-') then Inc(start);
    { ([0-9]*\.)? then [0-9]+: try with the group first }
    k := Digits(start);
    if (k <= n) and (S[k] = '.') then
    begin
      k2 := Digits(k + 1);
      if k2 > k + 1 then
      begin
        Result := k2;
        { the exponent }
        if (Result <= n) and (S[Result] in ['e', 'E']) then
        begin
          k3 := Result + 1;
          if (k3 <= n) and (S[k3] = '-') then Inc(k3);
          if Digits(k3) > k3 then Result := Digits(k3);
        end;
        Exit;
      end;
    end;
    { without the group: digits }
    if k > start then
    begin
      Result := k;
      if (Result <= n) and (S[Result] in ['e', 'E']) then
      begin
        k3 := Result + 1;
        if (k3 <= n) and (S[k3] = '-') then Inc(k3);
        if Digits(k3) > k3 then Result := Digits(k3);
      end;
      Exit;
    end;
    { '-?' backs off: nothing more to try here }
  end;

begin
  Result := nil;
  n := Length(S);
  i := 1;
  while i <= n do
  begin
    e := MatchAt(i);
    if e > 0 then
    begin
      p := Length(Result);
      SetLength(Result, p + 1);
      Result[p] := Copy(S, i, e - i);
      i := e;
    end
    else
      Inc(i);
  end;
end;

{ parseFloat(arr[k]) where a missing element is undefined: NaN }
function NumAt(const A: TTyStringArray; K: Integer): Double;
begin
  if K <= High(A) then Result := TyJsParseFloat(A[K]) else Result := NaN;
end;

{ `arr[k] || def`: a missing (or empty) element takes the default }
function StrAtOr(const A: TTyStringArray; K: Integer; const ADef: string): string;
begin
  if (K <= High(A)) and (A[K] <> '') then Result := A[K] else Result := ADef;
end;

function DomStr(const S: DOMString): string;
begin
  Result := UTF8Encode(UnicodeString(S));
end;

{ getAttribute: AHas False for an absent attribute (null) }
function Attr(AEl: TDOMNode; const AName: string; out AValue: string): Boolean;
var a: TDOMNode;
begin
  AValue := '';
  Result := False;
  if not (AEl is TDOMElement) then Exit;
  a := TDOMElement(AEl).GetAttributeNode(DOMString(UTF8Decode(AName)));
  if a = nil then Exit;
  AValue := DomStr(a.NodeValue);
  Result := True;
end;

{ `getAttribute(n) || ''`-style: '' for an absent attribute }
function AttrOr(AEl: TDOMNode; const AName, ADef: string): string;
begin
  if not Attr(AEl, AName, Result) or (Result = '') then Result := ADef;
end;

{ ==================== the matrices ==================== }

function TyGsMatIdentity: TTyMat2D;
begin
  Result[0] := 1; Result[1] := 0; Result[2] := 0;
  Result[3] := 1; Result[4] := 0; Result[5] := 0;
end;

function TyGsMatMul(const M1, M2: TTyMat2D): TTyMat2D;
begin
  Result[0] := M1[0] * M2[0] + M1[2] * M2[1];
  Result[1] := M1[1] * M2[0] + M1[3] * M2[1];
  Result[2] := M1[0] * M2[2] + M1[2] * M2[3];
  Result[3] := M1[1] * M2[2] + M1[3] * M2[3];
  Result[4] := M1[0] * M2[4] + M1[2] * M2[5] + M1[4];
  Result[5] := M1[1] * M2[4] + M1[3] * M2[5] + M1[5];
end;

function TyGsMatInvert(const A: TTyMat2D; out AOut: TTyMat2D): Boolean;
var aa, ac, atx, ab, ad, aty, det: Double;
begin
  aa := A[0]; ac := A[2]; atx := A[4];
  ab := A[1]; ad := A[3]; aty := A[5];
  det := aa * ad - ab * ac;
  if IsNan(det) or (det = 0) then
  begin
    AOut := A;
    Exit(False);
  end;
  det := 1.0 / det;
  AOut[0] := ad * det;
  AOut[1] := -ab * det;
  AOut[2] := -ac * det;
  AOut[3] := aa * det;
  AOut[4] := (ac * aty - ad * atx) * det;
  AOut[5] := (ab * atx - aa * aty) * det;
  Result := True;
end;

{ matrix.rotate(out, a, rad, pivot) }
function MatRotate(const A: TTyMat2D; ARad, APX, APY: Double): TTyMat2D;
var aa, ac, atx, ab, ad, aty, st, ct: Double;
begin
  aa := A[0]; ac := A[2]; atx := A[4];
  ab := A[1]; ad := A[3]; aty := A[5];
  st := TyJsSin(ARad);
  ct := TyJsCos(ARad);
  Result[0] := aa * ct + ab * st;
  Result[1] := -aa * st + ab * ct;
  Result[2] := ac * ct + ad * st;
  Result[3] := -ac * st + ct * ad;
  Result[4] := ct * (atx - APX) + st * (aty - APY) + APX;
  Result[5] := ct * (aty - APY) - st * (atx - APX) + APY;
end;

function JsFalsy(AValue: Double): Boolean;
begin
  Result := IsNan(AValue) or (AValue = 0);
end;

function TyGsLocal(const T: TTyGsTrans): TTyMat2D;
var skx, sky: Double;
begin
  if JsFalsy(T.SkewX) then skx := 0 else skx := TyJsTan(T.SkewX);
  if JsFalsy(T.SkewY) then sky := 0 else sky := TyJsTan(-T.SkewY);
  Result[4] := 0;
  Result[5] := 0;
  Result[0] := T.ScaleX;
  Result[3] := T.ScaleY;
  Result[1] := sky * T.ScaleX;
  Result[2] := skx * T.ScaleY;
  if not JsFalsy(T.Rotation) then Result := MatRotate(Result, T.Rotation, 0, 0);
  Result[4] := Result[4] + (0 + T.X);
  Result[5] := Result[5] + (0 + T.Y);
end;

function NotAroundZero(V: Double): Boolean;
begin
  Result := (V > cTransEps) or (V < -cTransEps);
end;

function TyGsNeedLocal(const T: TTyGsTrans): Boolean;
begin
  Result := NotAroundZero(T.Rotation) or NotAroundZero(T.X) or NotAroundZero(T.Y)
    or NotAroundZero(T.ScaleX - 1) or NotAroundZero(T.ScaleY - 1)
    or NotAroundZero(T.SkewX) or NotAroundZero(T.SkewY);
end;

function TyGsDecompose(const M: TTyMat2D): TTyGsTrans;
var sx, sy, rot, shear: Double;
begin
  sx := M[0] * M[0] + M[1] * M[1];
  sy := M[2] * M[2] + M[3] * M[3];
  rot := TyJsAtan2(M[1], M[0]);
  shear := cJsPiOne / 2 + rot - TyJsAtan2(M[3], M[2]);
  sy := Sqrt(sy) * TyJsCos(shear);
  sx := Sqrt(sx);
  Result.SkewX := shear;
  Result.SkewY := 0;
  Result.Rotation := -rot;
  Result.X := M[4];
  Result.Y := M[5];
  Result.ScaleX := sx;
  Result.ScaleY := sy;
end;

function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

function JsFinite(V: Double): Boolean;
begin
  Result := not (IsNan(V) or IsInfinite(V));
end;

function TyGsRectApply(const R: TTyXYWH; const M: TTyMat2D): TTyXYWH;
var px, py: array[0..3] of Double; k: Integer; x0, y0, x1, y1: Double;
begin
  if (M[1] < 1e-5) and (M[1] > -1e-5) and (M[2] < 1e-5) and (M[2] > -1e-5) then
  begin
    Result.X := R.X * M[0] + M[4];
    Result.Y := R.Y * M[3] + M[5];
    Result.W := R.W * M[0];
    Result.H := R.H * M[3];
    if Result.W < 0 then
    begin
      Result.X := Result.X + Result.W;
      Result.W := -Result.W;
    end;
    if Result.H < 0 then
    begin
      Result.Y := Result.Y + Result.H;
      Result.H := -Result.H;
    end;
    Exit;
  end;
  { lt, rb, lb, rt: Math.min / max of four }
  px[0] := M[0] * R.X + M[2] * R.Y + M[4];
  py[0] := M[1] * R.X + M[3] * R.Y + M[5];
  px[1] := M[0] * (R.X + R.W) + M[2] * (R.Y + R.H) + M[4];
  py[1] := M[1] * (R.X + R.W) + M[3] * (R.Y + R.H) + M[5];
  px[2] := M[0] * R.X + M[2] * (R.Y + R.H) + M[4];
  py[2] := M[1] * R.X + M[3] * (R.Y + R.H) + M[5];
  px[3] := M[0] * (R.X + R.W) + M[2] * R.Y + M[4];
  py[3] := M[1] * (R.X + R.W) + M[3] * R.Y + M[5];
  x0 := px[0]; y0 := py[0]; x1 := px[0]; y1 := py[0];
  for k := 1 to 3 do
  begin
    x0 := JsMin(x0, px[k]);
    y0 := JsMin(y0, py[k]);
    x1 := JsMax(x1, px[k]);
    y1 := JsMax(y1, py[k]);
  end;
  Result.X := x0;
  Result.Y := y0;
  Result.W := x1 - x0;
  Result.H := y1 - y0;
end;

procedure TyGsRectUnion(var R: TTyXYWH; const O: TTyXYWH);
var x, y: Double;
begin
  x := JsMin(O.X, R.X);
  y := JsMin(O.Y, R.Y);
  if JsFinite(R.X) and JsFinite(R.W) then
    R.W := JsMax(O.X + O.W, R.X + R.W) - x
  else
    R.W := O.W;
  if JsFinite(R.Y) and JsFinite(R.H) then
    R.H := JsMax(O.Y + O.H, R.Y + R.H) - y
  else
    R.H := O.H;
  R.X := x;
  R.Y := y;
end;

{ ==================== the tags ==================== }

function TyGsRegionTag(const ATag: string): Boolean;
begin
  Result := (ATag = 'rect') or (ATag = 'circle') or (ATag = 'line') or (ATag = 'ellipse')
    or (ATag = 'polygon') or (ATag = 'polyline') or (ATag = 'path')
    or (ATag = 'text') or (ATag = 'tspan') or (ATag = 'g');
end;

function TyGsStyleTag(const ATag: string): Boolean;
begin
  Result := (ATag = 'rect') or (ATag = 'circle') or (ATag = 'line') or (ATag = 'ellipse')
    or (ATag = 'polygon') or (ATag = 'polyline') or (ATag = 'path');
end;

function TyGsStateTag(const ATag: string): Boolean;
begin
  Result := TyGsStyleTag(ATag) or (ATag = 'g');
end;

function TyGsDefaultFill(AKind: TTyGsKind): string;
begin
  case AKind of
    gskRect, gskCircle, gskEllipse, gskPolygon, gskPath, gskTSpan: Result := '#000';
  else
    Result := '';
  end;
end;

function TyGsDefaultStroke(AKind: TTyGsKind): string;
begin
  case AKind of
    gskLine, gskPolyline: Result := '#000';
  else
    Result := '';
  end;
end;

{ the paint the element ends with: the style's, else the element default;
  '' for none ('none' never reaches here: the parser made it null) }
function EffectivePaint(const P: TTyGsPaint; const ADefault: string): string;
begin
  case P.Kind of
    gpUnset: Result := ADefault;
    gpColour: Result := P.Colour;
    gpGradient: Result := '#gradient';
  else
    Result := '';
  end;
end;

function TyGsOwnStroke(const N: TTyGsNode): TTyGsStroke;
var s, f: string; lw: Double;
begin
  Result := Default(TTyGsStroke);
  Result.LineScale := 1;
  if N.St.NumHas[gnLineWidth] then lw := N.St.Num[gnLineWidth]
  else if N.Kind = gskImage then lw := NaN
  else lw := 1;
  Result.LineWidth := lw;
  s := EffectivePaint(N.St.Stroke, TyGsDefaultStroke(N.Kind));
  f := EffectivePaint(N.St.Fill, TyGsDefaultFill(N.Kind));
  Result.HasStroke := (s <> '') and (s <> 'none') and (lw > 0);
  Result.HasFill := (f <> '') and (f <> 'none');
end;

{ ==================== text ==================== }

function TyGsSsrWidth(const AText: string; const AFont: TTyGsFont): Double;
const
  cTable = '007LLmW''55;N0500LLLLLLLLLL00NNNLzWW\\WQb\0FWLg\bWb\WQ\WrWWQ000CL5LLFLL0LL**F*gLLLL5F0LF\FFF5.5N';
var
  font: string;
  i, j, n, k: Integer;
  size, w: Double;
  u: UnicodeString;
  code: Integer;
begin
  font := AFont.Css;
  if font = '' then font := '12px sans-serif';
  { /((?:\d+)?\.?\d*)px/: the first place it matches }
  size := NaN;
  n := Length(font);
  for i := 1 to n do
  begin
    j := i;
    while (j <= n) and (font[j] in ['0'..'9']) do Inc(j);
    if (j <= n) and (font[j] = '.') then Inc(j);
    while (j <= n) and (font[j] in ['0'..'9']) do Inc(j);
    if (j + 1 <= n) and (font[j] = 'p') and (font[j + 1] = 'x') then
    begin
      if j = i then size := 0
      else size := TyJsToNumber(Copy(font, i, j - i));
      Break;
    end;
  end;
  if JsFalsy(size) then size := 12;
  u := UTF8Decode(AText);
  w := 0;
  if Pos('mono', font) > 0 then
    Exit(size * Length(u));
  for k := 1 to Length(u) do
  begin
    code := Ord(u[k]);
    if (code >= 32) and (code - 32 < Length(cTable)) then
      w := w + (Ord(cTable[code - 32 + 1]) - 20) / 100 * size
    else
      w := w + size;
  end;
  Result := w;
end;

{ ==================== the builder ==================== }

type
  TInh = (ihFill, ihStroke, ihLineWidth, ihOpacity, ihFillOpacity, ihStrokeOpacity,
    ihLineDash, ihLineDashOffset, ihLineCap, ihLineJoin, ihMiterLimit, ihFontFamily,
    ihFontSize, ihFontStyle, ihFontWeight, ihTextAlign, ihVisibility, ihDisplay);
  TInhDict = record
    Has: array[TInh] of Boolean;
    V: array[TInh] of string;
  end;
  TSelfKey = (skTextBaseline, skStopColor);
  TSelfDict = record
    Has: array[TSelfKey] of Boolean;
    V: array[TSelfKey] of string;
  end;

const
  cInhAttr: array[TInh] of string = ('fill', 'stroke', 'stroke-width', 'opacity',
    'fill-opacity', 'stroke-opacity', 'stroke-dasharray', 'stroke-dashoffset',
    'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit', 'font-family',
    'font-size', 'font-style', 'font-weight', 'text-anchor', 'visibility', 'display');
  cSelfAttr: array[TSelfKey] of string = ('alignment-baseline', 'stop-color');

type
  TPending = record
    Node: Integer;
    IsStroke: Boolean;
    Id: string;
  end;

  TGsBuilder = class
  public
    G: TTyGsGraphic;
    Inh: array of TInhDict;
    HasInh: array of Boolean;
    SelfSt: array of TSelfDict;
    HasSelf: array of Boolean;
    Defs: array of record
      Id: string;
      Grad: Integer;
    end;
    Pending: array of TPending;
    AllNamed: array of TTyGsNamed;
    TextX, TextY: Double;
    Measure: TTyGsMeasure;
    Failed: Boolean;
    function NewNode(AKind: TTyGsKind; AParent: Integer): Integer;
    procedure AddChild(AParent, AChild: Integer);
    procedure InheritStyle(AParent, AChild: Integer);
    procedure ParseAttributes(AX: TDOMNode; AEl: Integer; AOnlyInline, AIsText: Boolean);
    procedure ParseTransform(AX: TDOMNode; AEl: Integer);
    procedure ParseNode(AX: TDOMNode; AParent, ANamedFrom: Integer; AInDefs, AInText: Boolean);
    procedure ParseText(AX: TDOMNode; AParent: Integer);
    function ParseGradient(AX: TDOMNode; ARadial: Boolean): Integer;
    procedure ApplyDefs;
    function FillStroke(AEl: Integer; AIsStroke: Boolean; const S: string;
      APendOk: Boolean): TTyGsPaint;
  end;

function TGsBuilder.NewNode(AKind: TTyGsKind; AParent: Integer): Integer;
begin
  Result := Length(G.Nodes);
  SetLength(G.Nodes, Result + 1);
  SetLength(Inh, Result + 1);
  SetLength(HasInh, Result + 1);
  SetLength(SelfSt, Result + 1);
  SetLength(HasSelf, Result + 1);
  G.Nodes[Result] := Default(TTyGsNode);
  G.Nodes[Result].Kind := AKind;
  G.Nodes[Result].Parent := AParent;
  G.Nodes[Result].T.ScaleX := 1;
  G.Nodes[Result].T.ScaleY := 1;
  Inh[Result] := Default(TInhDict);
  HasInh[Result] := False;
  SelfSt[Result] := Default(TSelfDict);
  HasSelf[Result] := False;
end;

procedure TGsBuilder.AddChild(AParent, AChild: Integer);
var n: Integer;
begin
  G.Nodes[AChild].Parent := AParent;
  n := Length(G.Nodes[AParent].Children);
  SetLength(G.Nodes[AParent].Children, n + 1);
  G.Nodes[AParent].Children[n] := AChild;
end;

{ inheritStyle: the child's own keys kept, the parent's filled in }
procedure TGsBuilder.InheritStyle(AParent, AChild: Integer);
var k: TInh;
begin
  if (AParent < 0) or not HasInh[AParent] then Exit;
  HasInh[AChild] := True;
  for k := Low(TInh) to High(TInh) do
    if Inh[AParent].Has[k] and not Inh[AChild].Has[k] then
    begin
      Inh[AChild].Has[k] := True;
      Inh[AChild].V[k] := Inh[AParent].V[k];
    end;
end;

{ /([^\s:;]+)\s*:\s*([^:;]+)/g over a style attribute }
procedure ParseInline(AX: TDOMNode; var AInh: TInhDict; var ASelf: TSelfDict);
var
  s, key, val: string;
  i, n, k0, k1, v0: Integer;
  ik: TInh;
  sk: TSelfKey;

  function IsWs(C: Char): Boolean;
  begin
    Result := C in [#9, #10, #11, #12, #13, ' '];
  end;

begin
  if not Attr(AX, 'style', s) or (s = '') then Exit;
  n := Length(s);
  i := 1;
  while i <= n do
  begin
    { the key: a run of neither space, colon nor semicolon }
    if IsWs(s[i]) or (s[i] = ':') or (s[i] = ';') then
    begin
      Inc(i);
      Continue;
    end;
    k0 := i;
    k1 := i;
    while (k1 <= n) and not (IsWs(s[k1]) or (s[k1] = ':') or (s[k1] = ';')) do Inc(k1);
    { then spaces, a colon, spaces, a value of neither colon nor semicolon;
      the key may also end inside the run (the regex backs off one character
      at a time, but a shorter key never meets a colon either) }
    v0 := k1;
    while (v0 <= n) and IsWs(s[v0]) do Inc(v0);
    if (v0 > n) or (s[v0] <> ':') then
    begin
      i := k0 + 1;
      Continue;
    end;
    Inc(v0);
    while (v0 <= n) and IsWs(s[v0]) do Inc(v0);
    if (v0 > n) or (s[v0] = ':') or (s[v0] = ';') then
    begin
      { \s* gives its last space back to the value, if it took any }
      if IsWs(s[v0 - 1]) and (s[v0 - 1] <> ':') then
        Dec(v0)
      else
      begin
        i := k0 + 1;
        Continue;
      end;
    end;
    key := Copy(s, k0, k1 - k0);
    i := v0;
    while (i <= n) and (s[i] <> ':') and (s[i] <> ';') do Inc(i);
    val := Copy(s, v0, i - v0);
    for ik := Low(TInh) to High(TInh) do
      if cInhAttr[ik] = key then
      begin
        AInh.Has[ik] := True;
        AInh.V[ik] := val;
      end;
    for sk := Low(TSelfKey) to High(TSelfKey) do
      if cSelfAttr[sk] = key then
      begin
        ASelf.Has[sk] := True;
        ASelf.V[sk] := val;
      end;
  end;
end;

procedure ParseAttrStyle(AX: TDOMNode; var AInh: TInhDict; var ASelf: TSelfDict);
var ik: TInh; sk: TSelfKey; v: string;
begin
  for ik := Low(TInh) to High(TInh) do
    if Attr(AX, cInhAttr[ik], v) then
    begin
      AInh.Has[ik] := True;
      AInh.V[ik] := v;
    end;
  for sk := Low(TSelfKey) to High(TSelfKey) do
    if Attr(AX, cSelfAttr[sk], v) then
    begin
      ASelf.Has[sk] := True;
      ASelf.V[sk] := v;
    end;
end;

{ getFillStrokeStyle: url(#id) waits for the defs (undefined till then),
  'none' is null, anything else the string }
function TGsBuilder.FillStroke(AEl: Integer; AIsStroke: Boolean; const S: string;
  APendOk: Boolean): TTyGsPaint;
var t, id: string; p, n: Integer;
begin
  Result := Default(TTyGsPaint);
  Result.Grad := -1;
  { /^url\(\s*#(.*?)\)/ }
  if Copy(S, 1, 4) = 'url(' then
  begin
    t := Copy(S, 5, MaxInt);
    p := 1;
    while (p <= Length(t)) and (t[p] in [#9, #10, #11, #12, #13, ' ']) do Inc(p);
    if (p <= Length(t)) and (t[p] = '#') then
    begin
      n := Pos(')', Copy(t, p + 1, MaxInt));
      if n > 0 then
      begin
        id := Trim(Copy(t, p + 1, n - 1));
        if not APendOk then
        begin
          { parseSVG hands the root no pending list: push throws }
          Failed := True;
          Result.Kind := gpUndefined;
          Exit;
        end;
        n := Length(Pending);
        SetLength(Pending, n + 1);
        Pending[n].Node := AEl;
        Pending[n].IsStroke := AIsStroke;
        Pending[n].Id := id;
        Result.Kind := gpUndefined;
        Exit;
      end;
    end;
  end;
  if S = 'none' then
  begin
    Result.Kind := gpNone;
    Exit;
  end;
  Result.Kind := gpColour;
  Result.Colour := S;
end;


var
  GDegToAngle: Double;

function MatOf6(A, B, C, D, E, F: Double): TTyMat2D;
begin
  Result[0] := A; Result[1] := B; Result[2] := C;
  Result[3] := D; Result[4] := E; Result[5] := F;
end;

procedure TGsBuilder.ParseTransform(AX: TDOMNode; AEl: Integer);
const
  cNames: array[0..5] of string = ('translate', 'scale', 'rotate', 'skewX', 'skewY', 'matrix');
var
  tr, typ, body: string;
  opTyp, opVal: TTyStringArray;
  i, j, k, n, p: Integer;
  mt: TTyMat2D;
  have, ok: Boolean;
  v: TTyStringArray;
  sx, sy: Double;
begin
  if not Attr(AX, 'transform', tr) or (tr = '') then Exit;
  tr := StringReplace(tr, ',', ' ', [rfReplaceAll]);
  { /(translate|scale|rotate|skewX|skewY|matrix)\(([\-\s0-9\.eE,]*)\)/g }
  opTyp := nil;
  opVal := nil;
  i := 1;
  n := Length(tr);
  while i <= n do
  begin
    ok := False;
    for k := 0 to High(cNames) do
    begin
      typ := cNames[k];
      if Copy(tr, i, Length(typ) + 1) = typ + '(' then
      begin
        j := i + Length(typ) + 1;
        p := j;
        while (p <= n) and (tr[p] in ['-', '0'..'9', '.', 'e', 'E', ',', #9, #10, #11, #12, #13, ' ']) do
          Inc(p);
        if (p <= n) and (tr[p] = ')') then
        begin
          body := Copy(tr, j, p - j);
          SetLength(opTyp, Length(opTyp) + 1);
          SetLength(opVal, Length(opVal) + 1);
          opTyp[High(opTyp)] := typ;
          opVal[High(opVal)] := body;
          i := p + 1;
          ok := True;
        end;
        Break;
      end;
    end;
    if not ok then Inc(i);
  end;
  have := False;
  mt := TyGsMatIdentity;
  for i := High(opTyp) downto 0 do
  begin
    v := SplitNumbers(opVal[i]);
    have := True;
    typ := opTyp[i];
    if typ = 'translate' then
    begin
      sx := NumAt(v, 0);
      sy := TyJsParseFloat(StrAtOr(v, 1, '0'));
      mt[4] := mt[4] + sx;
      mt[5] := mt[5] + sy;
    end
    else if typ = 'scale' then
    begin
      sx := NumAt(v, 0);
      if (1 <= High(v)) and (v[1] <> '') then sy := TyJsParseFloat(v[1])
      else sy := NumAt(v, 0);
      mt[0] := mt[0] * sx;
      mt[1] := mt[1] * sy;
      mt[2] := mt[2] * sx;
      mt[3] := mt[3] * sy;
      mt[4] := mt[4] * sx;
      mt[5] := mt[5] * sy;
    end
    else if typ = 'rotate' then
    begin
      sx := TyJsParseFloat(StrAtOr(v, 1, '0'));
      sy := TyJsParseFloat(StrAtOr(v, 2, '0'));
      mt := MatRotate(mt, -NumAt(v, 0) * GDegToAngle, sx, sy);
    end
    else if typ = 'skewX' then
    begin
      sx := TyJsTan(NumAt(v, 0) * GDegToAngle);
      mt := TyGsMatMul(MatOf6(1, 0, sx, 1, 0, 0), mt);
    end
    else if typ = 'skewY' then
    begin
      sy := TyJsTan(NumAt(v, 0) * GDegToAngle);
      mt := TyGsMatMul(MatOf6(1, sy, 0, 1, 0, 0), mt);
    end
    else if typ = 'matrix' then
    begin
      for k := 0 to 5 do mt[k] := NumAt(v, k);
    end;
  end;
  if have then G.Nodes[AEl].T := TyGsDecompose(mt);
end;

procedure TGsBuilder.ParseAttributes(AX: TDOMNode; AEl: Integer; AOnlyInline,
  AIsText: Boolean);
var
  selfD: TSelfDict;
  d: TInhDict;
  st: TTyGsStyle;
  parts: TTyStringArray;
  k: Integer;

  procedure Num(AKey: TInh; ANum: TTyGsNumKey);
  begin
    if d.Has[AKey] then
    begin
      st.NumHas[ANum] := True;
      st.Num[ANum] := TyJsParseFloat(d.V[AKey]);
    end;
  end;

  procedure Str(AKey: TInh; AStr: TTyGsStrKey);
  begin
    if d.Has[AKey] then
    begin
      st.StrHas[AStr] := True;
      st.Str[AStr] := d.V[AKey];
    end;
  end;

begin
  HasInh[AEl] := True;
  selfD := Default(TSelfDict);
  if AX.NodeType = ELEMENT_NODE then
  begin
    ParseTransform(AX, AEl);
    ParseInline(AX, Inh[AEl], selfD);
    if not AOnlyInline then ParseAttrStyle(AX, Inh[AEl], selfD);
  end;
  d := Inh[AEl];
  st := G.Nodes[AEl].St;
  if d.Has[ihFill] then
    st.Fill := FillStroke(AEl, False, d.V[ihFill], AEl <> TyGsParsedRootNode);
  if d.Has[ihStroke] then
    st.Stroke := FillStroke(AEl, True, d.V[ihStroke], AEl <> TyGsParsedRootNode);
  Num(ihLineWidth, gnLineWidth);
  Num(ihOpacity, gnOpacity);
  Num(ihFillOpacity, gnFillOpacity);
  Num(ihStrokeOpacity, gnStrokeOpacity);
  Num(ihMiterLimit, gnMiterLimit);
  Num(ihFontSize, gnFontSize);
  Str(ihLineDashOffset, gsLineDashOffset);
  Str(ihLineCap, gsLineCap);
  Str(ihLineJoin, gsLineJoin);
  Str(ihFontWeight, gsFontWeight);
  Str(ihFontFamily, gsFontFamily);
  Str(ihFontStyle, gsFontStyle);
  Str(ihTextAlign, gsTextAlign);
  if AIsText then
  begin
    SelfSt[AEl] := selfD;
    HasSelf[AEl] := True;
  end;
  if d.Has[ihLineDash] and (d.V[ihLineDash] <> '') then
  begin
    parts := SplitNumbers(d.V[ihLineDash]);
    st.HasDash := True;
    SetLength(st.Dash, Length(parts));
    for k := 0 to High(parts) do st.Dash[k] := TyJsParseFloat(parts[k]);
  end;
  G.Nodes[AEl].St := st;
  if d.Has[ihVisibility] and ((d.V[ihVisibility] = 'hidden') or (d.V[ihVisibility] = 'collapse')) then
    G.Nodes[AEl].Invisible := True;
  if d.Has[ihDisplay] and (d.V[ihDisplay] = 'none') then
    G.Nodes[AEl].Ignore := True;
end;

{ parsePoints }
function PointsOf(const S: string): TTyDoubleArray;
var list: TTyStringArray; i, n: Integer;
begin
  Result := nil;
  list := SplitNumbers(S);
  n := (Length(list) + 1) div 2;
  SetLength(Result, n * 2);
  for i := 0 to n - 1 do
  begin
    Result[2 * i] := NumAt(list, 2 * i);
    Result[2 * i + 1] := NumAt(list, 2 * i + 1);
  end;
end;

function ParseFloatAttr(AX: TDOMNode; const AName, ADef: string): Double;
begin
  Result := TyJsParseFloat(AttrOr(AX, AName, ADef));
end;

function TGsBuilder.ParseGradient(AX: TDOMNode; ARadial: Boolean): Integer;
var
  gr: TTyGsGradient;
  stop: TDOMNode;
  offStr, stopColor, stopOpacity, u: string;
  styleI: TInhDict;
  styleS: TSelfDict;
  off, cr, cg, cb, ca: Double;
  n: Integer;
begin
  gr := Default(TTyGsGradient);
  gr.Radial := ARadial;
  if ARadial then
  begin
    gr.X := JsParseInt(AttrOr(AX, 'cx', '0'));
    gr.Y := JsParseInt(AttrOr(AX, 'cy', '0'));
    gr.R := JsParseInt(AttrOr(AX, 'r', '0'));
  end
  else
  begin
    gr.X := JsParseInt(AttrOr(AX, 'x1', '0'));
    gr.Y := JsParseInt(AttrOr(AX, 'y1', '0'));
    gr.X2 := JsParseInt(AttrOr(AX, 'x2', '10'));
    gr.Y2 := JsParseInt(AttrOr(AX, 'y2', '0'));
  end;
  gr.Global := Attr(AX, 'gradientUnits', u) and (u = 'userSpaceOnUse');
  stop := AX.FirstChild;
  while stop <> nil do
  begin
    if (stop.NodeType = ELEMENT_NODE) and (LowerCase(DomStr(stop.NodeName)) = 'stop') then
    begin
      if Attr(stop, 'offset', offStr) and (offStr <> '') then
      begin
        if Pos('%', offStr) > 1 then off := JsParseInt(offStr) / 100
        else off := TyJsParseFloat(offStr);
      end
      else
        off := 0;
      styleI := Default(TInhDict);
      styleS := Default(TSelfDict);
      ParseInline(stop, styleI, styleS);
      if styleS.Has[skStopColor] and (styleS.V[skStopColor] <> '') then
        stopColor := styleS.V[skStopColor]
      else
        stopColor := AttrOr(stop, 'stop-color', '#000000');
      stopOpacity := AttrOr(stop, 'stop-opacity', '');
      if stopOpacity <> '' then
        if TyTryParseCssRgba(stopColor, cr, cg, cb, ca) and not JsFalsy(ca) then
        begin
          if stopOpacity[Length(stopOpacity)] = '%' then
            ca := ca * (TyJsParseFloat(stopOpacity) / 100)
          else
            ca := ca * TyJsParseFloat(stopOpacity);
          stopColor := 'rgba(' + TyJsNumberToString(cr) + ',' + TyJsNumberToString(cg) + ','
            + TyJsNumberToString(cb) + ',' + TyJsNumberToString(ca) + ')';
        end;
      n := Length(gr.Stops);
      SetLength(gr.Stops, n + 1);
      gr.Stops[n].Offset := off;
      gr.Stops[n].Colour := stopColor;
    end;
    stop := stop.NextSibling;
  end;
  Result := Length(G.Grads);
  SetLength(G.Grads, Result + 1);
  G.Grads[Result] := gr;
end;

procedure TGsBuilder.ParseText(AX: TDOMNode; AParent: Integer);
var
  n: Integer;
  fs, w, lw: Double;
  tb, ta: string;
  hasFs: Boolean;
  st: TTyGsStyle;
  stroke: Boolean;
begin
  n := NewNode(gskTSpan, AParent);
  if JsFalsy(TextX) then G.Nodes[n].T.X := 0 else G.Nodes[n].T.X := TextX;
  if JsFalsy(TextY) then G.Nodes[n].T.Y := 0 else G.Nodes[n].T.Y := TextY;
  G.Nodes[n].Silent := True;
  G.Nodes[n].St.Text := DomStr(AX.TextContent);
  InheritStyle(AParent, n);
  ParseAttributes(AX, n, False, False);
  { applyTextAlignment }
  if HasSelf[AParent] then
  begin
    tb := '';
    if SelfSt[AParent].Has[skTextBaseline] then tb := SelfSt[AParent].V[skTextBaseline];
    if (tb = '') or (tb = 'auto') or (tb = 'baseline') then tb := 'alphabetic'
    else if (tb = 'before-edge') or (tb = 'text-before-edge') then tb := 'top'
    else if (tb = 'after-edge') or (tb = 'text-after-edge') then tb := 'bottom'
    else if (tb = 'central') or (tb = 'mathematical') then tb := 'middle';
    G.Nodes[n].St.StrHas[gsTextBaseline] := True;
    G.Nodes[n].St.Str[gsTextBaseline] := tb;
  end;
  if HasInh[AParent] and Inh[AParent].Has[ihTextAlign] and (Inh[AParent].V[ihTextAlign] <> '') then
  begin
    ta := Inh[AParent].V[ihTextAlign];
    if ta = 'middle' then ta := 'center';
    G.Nodes[n].St.StrHas[gsTextAlign] := True;
    G.Nodes[n].St.Str[gsTextAlign] := ta;
  end;
  st := G.Nodes[n].St;
  hasFs := st.NumHas[gnFontSize];
  fs := NaN;
  if hasFs then fs := st.Num[gnFontSize];
  if hasFs and not JsFalsy(fs) and (fs < 9) then
  begin
    st.Num[gnFontSize] := 9;
    G.Nodes[n].T.ScaleX := G.Nodes[n].T.ScaleX * (fs / 9);
    G.Nodes[n].T.ScaleY := G.Nodes[n].T.ScaleY * (fs / 9);
    fs := 9;
  end;
  st.Font := Default(TTyGsFont);
  st.Font.SizePx := 12;
  st.Font.Family := 'sans-serif';
  if (hasFs and not JsFalsy(fs)) or (st.StrHas[gsFontFamily] and (st.Str[gsFontFamily] <> '')) then
  begin
    st.HasFont := True;
    if hasFs and not JsFalsy(fs) then st.Font.SizePx := fs;
    if st.StrHas[gsFontFamily] and (st.Str[gsFontFamily] <> '') then
      st.Font.Family := st.Str[gsFontFamily];
    if st.StrHas[gsFontStyle] then st.Font.Style := st.Str[gsFontStyle];
    if st.StrHas[gsFontWeight] then st.Font.Weight := st.Str[gsFontWeight];
    st.Font.Css := st.Font.Style + ' ' + st.Font.Weight + ' '
      + TyJsNumberToString(st.Font.SizePx) + 'px ' + st.Font.Family;
  end;
  { getBoundingRect: the text's width and getLineHeight ('国' wide) }
  w := 0;
  if Assigned(Measure) then
  begin
    w := Measure(st.Text, st.Font);
    st.TextH := Measure(#$E5#$9B#$BD, st.Font);
  end;
  st.TextW := w;
  G.Nodes[n].St := st;
  { tSpanHasStroke: a stroke not null nor 'none', a line width over nought
    (DEFAULT_PATH_STYLE's 1 where the style leaves it out) }
  if st.NumHas[gnLineWidth] then lw := st.Num[gnLineWidth] else lw := 1;
  stroke := (st.Stroke.Kind in [gpColour, gpGradient]) and (lw > 0);
  if not stroke then lw := 0;
  TextX := TextX + (w + lw);
  AddChild(AParent, n);
end;

procedure TGsBuilder.ParseNode(AX: TDOMNode; AParent, ANamedFrom: Integer;
  AInDefs, AInText: Boolean);
var
  nm, nameAttr, s, id: string;
  el, fromSub, k: Integer;
  kind: TTyGsKind;
  isParser: Boolean;
  child: TDOMNode;
  v: Double;
  has: Boolean;
begin
  if AX.NodeType <> ELEMENT_NODE then Exit;
  nm := LowerCase(DomStr(AX.NodeName));
  el := -1;
  fromSub := ANamedFrom;
  if nm = 'defs' then AInDefs := True;
  if nm = 'text' then AInText := True;
  if (nm = 'defs') or (nm = 'switch') then
    el := AParent
  else
  begin
    if not AInDefs then
    begin
      isParser := True;
      kind := gskGroup;
      if nm = 'g' then kind := gskGroup
      else if nm = 'rect' then kind := gskRect
      else if nm = 'circle' then kind := gskCircle
      else if nm = 'line' then kind := gskLine
      else if nm = 'ellipse' then kind := gskEllipse
      else if nm = 'polygon' then kind := gskPolygon
      else if nm = 'polyline' then kind := gskPolyline
      else if nm = 'image' then kind := gskImage
      else if (nm = 'text') or (nm = 'tspan') then kind := gskGroup
      else if nm = 'path' then kind := gskPath
      else isParser := False;
      if isParser then
      begin
        if nm = 'text' then
        begin
          TextX := TyJsParseFloat(AttrOr(AX, 'x', '0')) + TyJsParseFloat(AttrOr(AX, 'dx', '0'));
          TextY := TyJsParseFloat(AttrOr(AX, 'y', '0')) + TyJsParseFloat(AttrOr(AX, 'dy', '0'));
        end
        else if nm = 'tspan' then
        begin
          if Attr(AX, 'x', s) then TextX := TyJsParseFloat(s);
          if Attr(AX, 'y', s) then TextY := TyJsParseFloat(s);
        end;
        el := NewNode(kind, AParent);
        if (nm = 'polygon') or (nm = 'polyline') then
        begin
          if Attr(AX, 'points', s) and (s <> '') then G.Nodes[el].V := PointsOf(s);
          G.Nodes[el].Silent := True;
        end;
        InheritStyle(AParent, el);
        ParseAttributes(AX, el, False, (nm = 'text') or (nm = 'tspan'));
        if nm = 'tspan' then
        begin
          TextX := TextX + TyJsParseFloat(AttrOr(AX, 'dx', '0'));
          TextY := TextY + TyJsParseFloat(AttrOr(AX, 'dy', '0'));
        end;
        case kind of
          gskRect:
            begin
              SetLength(G.Nodes[el].V, 4);
              G.Nodes[el].V[0] := ParseFloatAttr(AX, 'x', '0');
              G.Nodes[el].V[1] := ParseFloatAttr(AX, 'y', '0');
              G.Nodes[el].V[2] := ParseFloatAttr(AX, 'width', '0');
              G.Nodes[el].V[3] := ParseFloatAttr(AX, 'height', '0');
              G.Nodes[el].Silent := True;
            end;
          gskCircle:
            begin
              SetLength(G.Nodes[el].V, 3);
              G.Nodes[el].V[0] := ParseFloatAttr(AX, 'cx', '0');
              G.Nodes[el].V[1] := ParseFloatAttr(AX, 'cy', '0');
              G.Nodes[el].V[2] := ParseFloatAttr(AX, 'r', '0');
              G.Nodes[el].Silent := True;
            end;
          gskLine:
            begin
              SetLength(G.Nodes[el].V, 4);
              G.Nodes[el].V[0] := ParseFloatAttr(AX, 'x1', '0');
              G.Nodes[el].V[1] := ParseFloatAttr(AX, 'y1', '0');
              G.Nodes[el].V[2] := ParseFloatAttr(AX, 'x2', '0');
              G.Nodes[el].V[3] := ParseFloatAttr(AX, 'y2', '0');
              G.Nodes[el].Silent := True;
            end;
          gskEllipse:
            begin
              SetLength(G.Nodes[el].V, 4);
              G.Nodes[el].V[0] := ParseFloatAttr(AX, 'cx', '0');
              G.Nodes[el].V[1] := ParseFloatAttr(AX, 'cy', '0');
              G.Nodes[el].V[2] := ParseFloatAttr(AX, 'rx', '0');
              G.Nodes[el].V[3] := ParseFloatAttr(AX, 'ry', '0');
              G.Nodes[el].Silent := True;
            end;
          gskImage:
            begin
              if not Attr(AX, 'xlink:href', s) or (s = '') then s := AttrOr(AX, 'href', '');
              G.Nodes[el].St.Image := s;
              has := Attr(AX, 'x', s);
              v := JsNumberOfAttr(has, s);
              G.Nodes[el].St.IX := v;
              has := Attr(AX, 'y', s);
              G.Nodes[el].St.IY := JsNumberOfAttr(has, s);
              has := Attr(AX, 'width', s);
              G.Nodes[el].St.IW := JsNumberOfAttr(has, s);
              has := Attr(AX, 'height', s);
              G.Nodes[el].St.IH := JsNumberOfAttr(has, s);
              G.Nodes[el].Silent := True;
            end;
          gskPath:
            begin
              G.Nodes[el].Path := TyZrParseSvg(AttrOr(AX, 'd', ''), G.Nodes[el].PathF32);
              G.Nodes[el].Silent := True;
            end;
        end;
        { the name: an empty one is none }
        if Attr(AX, 'name', nameAttr) and (nameAttr <> '') then
        begin
          k := Length(AllNamed);
          SetLength(AllNamed, k + 1);
          AllNamed[k].Name := nameAttr;
          AllNamed[k].From := -1;
          AllNamed[k].Tag := nm;
          AllNamed[k].Node := el;
          if nm = 'g' then fromSub := k;
        end
        else if ANamedFrom >= 0 then
        begin
          k := Length(AllNamed);
          SetLength(AllNamed, k + 1);
          AllNamed[k].Name := AllNamed[ANamedFrom].Name;
          AllNamed[k].From := ANamedFrom;
          AllNamed[k].Tag := nm;
          AllNamed[k].Node := el;
        end;
        AddChild(AParent, el);
      end;
    end;
    { paint servers, in defs or not }
    if (nm = 'lineargradient') or (nm = 'radialgradient') then
    begin
      k := ParseGradient(AX, nm = 'radialgradient');
      if Attr(AX, 'id', id) and (id <> '') then
      begin
        SetLength(Defs, Length(Defs) + 1);
        Defs[High(Defs)].Id := id;
        Defs[High(Defs)].Grad := k;
      end;
    end;
  end;
  if (el >= 0) and (G.Nodes[el].Kind = gskGroup) then
  begin
    child := AX.FirstChild;
    while child <> nil do
    begin
      if child.NodeType = ELEMENT_NODE then
        ParseNode(child, el, fromSub, AInDefs, AInText)
      else if (child.NodeType = TEXT_NODE) and AInText then
        ParseText(child, el);
      child := child.NextSibling;
    end;
  end;
end;

procedure TGsBuilder.ApplyDefs;
var i, j, gi: Integer; p: TTyGsPaint;
begin
  for i := 0 to High(Pending) do
  begin
    gi := -1;
    { the last definition of the id wins (this._defs[id] = def) }
    for j := 0 to High(Defs) do
      if Defs[j].Id = Pending[i].Id then gi := Defs[j].Grad;
    p := Default(TTyGsPaint);
    p.Grad := gi;
    if gi >= 0 then p.Kind := gpGradient else p.Kind := gpUndefined;
    if Pending[i].IsStroke then G.Nodes[Pending[i].Node].St.Stroke := p
    else G.Nodes[Pending[i].Node].St.Fill := p;
  end;
end;

{ ==================== the document ==================== }

function TyGsParseDocument(const AText: string; out ADoc: TXMLDocument;
  out ASvg: TDOMElement): Boolean;
var
  parser: TDOMParser;
  src: TXMLInputSource;
  st: TStringStream;
  node: TDOMNode;
begin
  Result := False;
  ADoc := nil;
  ASvg := nil;
  parser := TDOMParser.Create;
  st := TStringStream.Create(AText);
  src := nil;
  try
    parser.Options.PreserveWhitespace := True;
    parser.Options.Namespaces := False;
    parser.Options.ExpandEntities := True;
    parser.Options.Validate := False;
    src := TXMLInputSource.Create(st);
    try
      parser.Parse(src, ADoc);
    except
      FreeAndNil(ADoc);
      Exit;
    end;
  finally
    src.Free;
    st.Free;
    parser.Free;
  end;
  if ADoc = nil then Exit;
  { parseXML: the document's first child, or the first later sibling that
    is an element named svg }
  node := ADoc.FirstChild;
  while (node <> nil) and not ((node.NodeType = ELEMENT_NODE)
    and (LowerCase(DomStr(node.NodeName)) = 'svg')) do
    node := node.NextSibling;
  if node = nil then
  begin
    FreeAndNil(ADoc);
    Exit;
  end;
  ASvg := TDOMElement(node);
  Result := True;
end;

{ the PathProxy a shape's buildPath makes, and its box }
procedure BuildShapePath(var N: TTyGsNode);
var i, np: Integer; k, x, y, a, b, ox, oy: Double;
begin
  case N.Kind of
    gskRect:
      begin
        N.Path := nil;
        TyZrRect(N.Path, N.V[0], N.V[1], N.V[2], N.V[3]);
      end;
    gskCircle:
      begin
        N.Path := nil;
        TyZrMoveTo(N.Path, N.V[0] + N.V[2], N.V[1]);
        TyZrArc(N.Path, N.V[0], N.V[1], N.V[2], 0, cJsPiTwo, False);
      end;
    gskEllipse:
      begin
        N.Path := nil;
        k := 0.5522848;
        x := N.V[0];
        y := N.V[1];
        a := N.V[2];
        b := N.V[3];
        ox := a * k;
        oy := b * k;
        TyZrMoveTo(N.Path, x - a, y);
        TyZrCubic(N.Path, x - a, y - oy, x - ox, y - b, x, y - b);
        TyZrCubic(N.Path, x + ox, y - b, x + a, y - oy, x + a, y);
        TyZrCubic(N.Path, x + a, y + oy, x + ox, y + b, x, y + b);
        TyZrCubic(N.Path, x - ox, y + b, x - a, y + oy, x - a, y);
        TyZrClose(N.Path);
      end;
    gskLine:
      begin
        N.Path := nil;
        TyZrMoveTo(N.Path, N.V[0], N.V[1]);
        TyZrLineTo(N.Path, N.V[2], N.V[3]);
      end;
    gskPolygon, gskPolyline:
      begin
        N.Path := nil;
        np := Length(N.V) div 2;
        if np >= 2 then
        begin
          TyZrMoveTo(N.Path, N.V[0], N.V[1]);
          for i := 1 to np - 1 do TyZrLineTo(N.Path, N.V[2 * i], N.V[2 * i + 1]);
          if N.Kind = gskPolygon then TyZrClose(N.Path);
        end;
      end;
  end;
  if N.Kind in [gskRect, gskCircle, gskEllipse, gskLine, gskPolygon, gskPolyline, gskPath] then
    N.Box := TyZrBBox(N.Path);
end;

{ makeViewBoxTransform (xMidYMid) }
procedure ViewBoxTransform(const AVb, ARect: TTyXYWH; out AScale, AX, AY: Double);
begin
  AScale := JsMin(ARect.W / AVb.W, ARect.H / AVb.H);
  AX := -(AVb.X + AVb.W / 2) * AScale + (ARect.X + ARect.W / 2);
  AY := -(AVb.Y + AVb.H / 2) * AScale + (ARect.Y + ARect.H / 2);
end;

{ new BoundingRect: a negative size turned round }
function NewRect(AX, AY, AW, AH: Double): TTyXYWH;
begin
  if AW < 0 then
  begin
    AX := AX + AW;
    AW := -AW;
  end;
  if AH < 0 then
  begin
    AY := AY + AH;
    AH := -AH;
  end;
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

function TyGsBuild(ASvg: TDOMElement; const AMeasure: TTyGsMeasure;
  AHasRect: Boolean; const ARect: TTyXYWH): TTyGsGraphic;
var
  b: TGsBuilder;
  child: TDOMNode;
  s, vb: string;
  width, height, bx, by, bw, bh, sc, tx, ty: Double;
  hasBX, hasBY: Boolean;
  arr: TTyStringArray;
  i, k, n, root, pr: Integer;
  remap: TTyIntegerArray;
  cr: TTyXYWH;
  strokes: TTyGsStrokeArray;

  procedure UnSilent(ANode: Integer);
  var j: Integer;
  begin
    b.G.Nodes[ANode].Silent := False;
    for j := 0 to High(b.G.Nodes[ANode].Children) do UnSilent(b.G.Nodes[ANode].Children[j]);
  end;

begin
  Result := Default(TTyGsGraphic);
  if ASvg = nil then Exit;
  b := TGsBuilder.Create;
  try
    b.G := Default(TTyGsGraphic);
    b.Measure := AMeasure;
    root := b.NewNode(gskGroup, -1);
    pr := b.NewNode(gskGroup, root);
    b.AddChild(root, pr);
    if not Attr(ASvg, 'viewBox', vb) then vb := '';
    if Attr(ASvg, 'width', s) and (s <> '') then width := TyJsParseFloat(s) else width := NaN;
    if Attr(ASvg, 'height', s) and (s <> '') then height := TyJsParseFloat(s) else height := NaN;
    b.ParseAttributes(ASvg, pr, True, False);
    child := ASvg.FirstChild;
    while child <> nil do
    begin
      b.ParseNode(child, pr, -1, False, False);
      child := child.NextSibling;
    end;
    b.ApplyDefs;
    if b.Failed then Exit;
    for i := 0 to High(b.G.Nodes) do BuildShapePath(b.G.Nodes[i]);
    b.G.Width := width;
    b.G.Height := height;
    if vb <> '' then
    begin
      arr := SplitNumbers(vb);
      if Length(arr) >= 4 then
      begin
        b.G.HasViewBox := True;
        b.G.ViewBox.X := TyJsParseFloat(arr[0]);
        b.G.ViewBox.Y := TyJsParseFloat(arr[1]);
        b.G.ViewBox.W := TyJsParseFloat(arr[2]);
        b.G.ViewBox.H := TyJsParseFloat(arr[3]);
      end;
    end;
    { the bounding rect: the svg's size, else the viewBox, else the content }
    if AHasRect then
      b.G.Rect := ARect
    else
    begin
      hasBX := False;
      hasBY := False;
      bx := 0; by := 0; bw := 0; bh := 0;
      if not IsNan(width) then
      begin
        hasBX := True;
        bx := 0;
        bw := width;
      end
      else if b.G.HasViewBox then
      begin
        hasBX := True;
        bx := b.G.ViewBox.X;
        bw := b.G.ViewBox.W;
      end;
      if not IsNan(height) then
      begin
        hasBY := True;
        by := 0;
        bh := height;
      end
      else if b.G.HasViewBox then
      begin
        hasBY := True;
        by := b.G.ViewBox.Y;
        bh := b.G.ViewBox.H;
      end;
      if not (hasBX and hasBY) then
      begin
        { rootFromParse.getBoundingRect(): the parser's own styles, no
          transform yet (line scale 1) }
        SetLength(strokes, Length(b.G.Nodes));
        for i := 0 to High(b.G.Nodes) do strokes[i] := TyGsOwnStroke(b.G.Nodes[i]);
        cr := TyGsNodeRect(b.G, pr, strokes);
        if not hasBX then
        begin
          bx := cr.X;
          bw := cr.W;
        end;
        if not hasBY then
        begin
          by := cr.Y;
          bh := cr.H;
        end;
      end;
      b.G.Rect := NewRect(bx, by, bw, bh);
    end;
    if b.G.HasViewBox then
    begin
      ViewBoxTransform(b.G.ViewBox, b.G.Rect, sc, tx, ty);
      b.G.Nodes[pr].T.ScaleX := sc;
      b.G.Nodes[pr].T.ScaleY := sc;
      b.G.Nodes[pr].T.X := tx;
      b.G.Nodes[pr].T.Y := ty;
    end;
    { the named items of the region-available tags, non-silent with all
      under them }
    SetLength(remap, Length(b.AllNamed));
    for i := 0 to High(b.AllNamed) do
    begin
      remap[i] := -1;
      if not TyGsRegionTag(b.AllNamed[i].Tag) then Continue;
      n := Length(b.G.Named);
      SetLength(b.G.Named, n + 1);
      b.G.Named[n] := b.AllNamed[i];
      remap[i] := n;
      UnSilent(b.AllNamed[i].Node);
    end;
    for k := 0 to High(b.G.Named) do
      if b.G.Named[k].From >= 0 then b.G.Named[k].From := remap[b.G.Named[k].From];
    b.G.Ok := True;
    Result := b.G;
  finally
    b.Free;
  end;
end;

{ ==================== the geometry ==================== }

function TyGsNodeRect(const G: TTyGsGraphic; ANode: Integer;
  const AStroke: TTyGsStrokeArray): TTyXYWH;
var
  i, c: Integer;
  have: Boolean;
  cr, tmp: TTyXYWH;
  st: TTyGsStroke;
  n: TTyGsNode;
  x, y, w, h, lw: Double;
  ta, tb: string;
begin
  n := G.Nodes[ANode];
  case n.Kind of
    gskGroup:
      begin
        have := False;
        Result := NewRect(0, 0, 0, 0);
        for i := 0 to High(n.Children) do
        begin
          c := n.Children[i];
          if G.Nodes[c].Ignore or G.Nodes[c].Invisible then Continue;
          cr := TyGsNodeRect(G, c, AStroke);
          tmp := TyGsRectApply(cr, TyGsLocal(G.Nodes[c].T));
          if not have then
          begin
            Result := NewRect(tmp.X, tmp.Y, tmp.W, tmp.H);
            have := True;
          end;
          TyGsRectUnion(Result, tmp);
        end;
      end;
    gskTSpan:
      begin
        w := n.St.TextW;
        h := n.St.TextH;
        if n.St.StrHas[gsTextAlign] then ta := n.St.Str[gsTextAlign] else ta := 'left';
        if n.St.StrHas[gsTextBaseline] then tb := n.St.Str[gsTextBaseline] else tb := 'top';
        x := 0;
        if ta = 'right' then x := x - w
        else if ta = 'center' then x := x - w / 2;
        y := 0;
        if tb = 'middle' then y := y - h / 2
        else if tb = 'bottom' then y := y - h;
        Result := NewRect(x, y, w, h);
        if n.St.NumHas[gnLineWidth] then lw := n.St.Num[gnLineWidth] else lw := 1;
        if not ((n.St.Stroke.Kind in [gpColour, gpGradient]) and (lw > 0)) then lw := 0;
        if lw > 0 then
        begin
          Result.X := Result.X - lw / 2;
          Result.Y := Result.Y - lw / 2;
          Result.W := Result.W + lw;
          Result.H := Result.H + lw;
        end;
      end;
    gskImage:
      begin
        x := n.St.IX;
        if JsFalsy(x) then x := 0;
        y := n.St.IY;
        if JsFalsy(y) then y := 0;
        Result := NewRect(x, y, n.St.IW, n.St.IH);
      end;
  else
    begin
      if (ANode <= High(AStroke)) then st := AStroke[ANode] else st := TyGsOwnStroke(n);
      Result := TyZrStrokeRect(n.Box, TyZrDataLength(n.Path), st.HasStroke, st.HasFill,
        st.LineWidth, st.LineScale);
    end;
  end;
end;

function TyGsRegionCentre(const G: TTyGsGraphic; ANode: Integer;
  const AStroke: TTyGsStrokeArray): TTyPointF;
var
  r: TTyXYWH;
  cx, cy: Double;
  mat, inv: TTyMat2D;
  t: Integer;
begin
  r := TyGsNodeRect(G, ANode, AStroke);
  cx := r.X + r.W / 2;
  cy := r.Y + r.H / 2;
  mat := TyGsMatIdentity;
  t := ANode;
  while (t >= 0) and (t <> TyGsRootNode) do
  begin
    mat := TyGsMatMul(TyGsLocal(G.Nodes[t].T), mat);
    t := G.Nodes[t].Parent;
  end;
  if TyGsMatInvert(mat, inv) then mat := inv;
  Result.X := mat[0] * cx + mat[2] * cy + mat[4];
  Result.Y := mat[1] * cx + mat[3] * cy + mat[5];
end;

procedure TyGsPathCmds(const APath: TTyZrPath; const AM: TTyMat2D;
  out ACmds: TTyPathCmdArray; out APoints: TTyPointFArray);
var
  i, k, n, nc, np: Integer;
  lastX, lastY, x0, y0, cx, cy, rx, ry, a0, sweep, psi, th, kk, p0, p1,
    c0, s0, c1, s1, t, u, cp, sp, r, qx, qy: Double;

  procedure Pt(AX, AY: Double);
  begin
    if np >= Length(APoints) then SetLength(APoints, np * 2 + 16);
    APoints[np].X := AM[0] * AX + AM[2] * AY + AM[4];
    APoints[np].Y := AM[1] * AX + AM[3] * AY + AM[5];
    Inc(np);
  end;

  procedure Cmd(AKind: TTyPathCmdKind; AX1, AY1, AX2, AY2, AX, AY: Double);
  begin
    if nc >= Length(ACmds) then SetLength(ACmds, nc * 2 + 16);
    ACmds[nc] := Default(TTyPathCmd);
    ACmds[nc].Kind := AKind;
    ACmds[nc].X1 := AM[0] * AX1 + AM[2] * AY1 + AM[4];
    ACmds[nc].Y1 := AM[1] * AX1 + AM[3] * AY1 + AM[5];
    ACmds[nc].X2 := AM[0] * AX2 + AM[2] * AY2 + AM[4];
    ACmds[nc].Y2 := AM[1] * AX2 + AM[3] * AY2 + AM[5];
    ACmds[nc].X := AM[0] * AX + AM[2] * AY + AM[4];
    ACmds[nc].Y := AM[1] * AX + AM[3] * AY + AM[5];
    Inc(nc);
  end;

  procedure Cubic(AX1, AY1, AX2, AY2, AX, AY: Double);
  var j: Integer; tt, uu: Double;
  begin
    Cmd(pckCurve, AX1, AY1, AX2, AY2, AX, AY);
    for j := 1 to 24 do
    begin
      tt := j / 24;
      uu := 1 - tt;
      Pt(uu * uu * uu * lastX + 3 * uu * uu * tt * AX1 + 3 * uu * tt * tt * AX2 + tt * tt * tt * AX,
        uu * uu * uu * lastY + 3 * uu * uu * tt * AY1 + 3 * uu * tt * tt * AY2 + tt * tt * tt * AY);
    end;
    lastX := AX;
    lastY := AY;
  end;

  { a point of the arc's ellipse at an angle }
  procedure ArcPt(AAngle: Double; out AX, AY: Double);
  begin
    AX := cx + rx * Cos(AAngle) * cp - ry * Sin(AAngle) * sp;
    AY := cy + rx * Cos(AAngle) * sp + ry * Sin(AAngle) * cp;
  end;

  { the unit circle's point (AUX, AUY) on the ellipse }
  procedure Map(AUX, AUY: Double; out AX, AY: Double);
  begin
    AX := cx + rx * AUX * cp - ry * AUY * sp;
    AY := cy + rx * AUX * sp + ry * AUY * cp;
  end;

var
  ax1, ay1, ax2, ay2, ax, ay: Double;
begin
  ACmds := nil;
  APoints := nil;
  nc := 0;
  np := 0;
  lastX := 0;
  lastY := 0;
  x0 := 0;
  y0 := 0;
  for i := 0 to High(APath) do
    case APath[i].Cmd of
      zrM:
        begin
          Cmd(pckMove, 0, 0, 0, 0, APath[i].V[0], APath[i].V[1]);
          lastX := APath[i].V[0];
          lastY := APath[i].V[1];
          x0 := lastX;
          y0 := lastY;
          Pt(lastX, lastY);
        end;
      zrL:
        begin
          Cmd(pckLine, 0, 0, 0, 0, APath[i].V[0], APath[i].V[1]);
          lastX := APath[i].V[0];
          lastY := APath[i].V[1];
          Pt(lastX, lastY);
        end;
      zrC:
        Cubic(APath[i].V[0], APath[i].V[1], APath[i].V[2], APath[i].V[3],
          APath[i].V[4], APath[i].V[5]);
      zrQ:
        begin
          qx := APath[i].V[0];
          qy := APath[i].V[1];
          Cubic(lastX + 2 / 3 * (qx - lastX), lastY + 2 / 3 * (qy - lastY),
            APath[i].V[2] + 2 / 3 * (qx - APath[i].V[2]),
            APath[i].V[3] + 2 / 3 * (qy - APath[i].V[3]),
            APath[i].V[2], APath[i].V[3]);
        end;
      zrA:
        begin
          cx := APath[i].V[0];
          cy := APath[i].V[1];
          rx := APath[i].V[2];
          ry := APath[i].V[3];
          a0 := APath[i].V[4];
          sweep := APath[i].V[5];
          psi := APath[i].V[6];
          { canvas' arc where the radii are within 1e-3: a circle of the
            larger }
          if Abs(rx - ry) <= 1e-3 then
          begin
            r := Max(rx, ry);
            rx := r;
            ry := r;
            psi := 0;
          end;
          cp := Cos(psi);
          sp := Sin(psi);
          ArcPt(a0, ax, ay);
          if i = 0 then
          begin
            Cmd(pckMove, 0, 0, 0, 0, ax, ay);
            x0 := ax;
            y0 := ay;
          end
          else
            Cmd(pckLine, 0, 0, 0, 0, ax, ay);
          lastX := ax;
          lastY := ay;
          Pt(ax, ay);
          { [R2-F] a sixteenth of a turn a cubic at most: its distance from
            the true arc is 6.6e-8 of the radius (a quarter turn's was
            2.7e-4: a pixel at a radius of 3 700, which a map zoomed in
            reaches), under a twentieth of a device pixel for any radius to
            750 000 -- the arc a canvas draws, at any zoom }
          n := Ceil(Abs(sweep) / (Pi / 8) - 1e-9);
          if n < 1 then n := 1;
          th := sweep / n;
          kk := 4 / 3 * Tan(th / 4);
          for k := 0 to n - 1 do
          begin
            p0 := a0 + th * k;
            p1 := a0 + th * (k + 1);
            c0 := Cos(p0);
            s0 := Sin(p0);
            c1 := Cos(p1);
            s1 := Sin(p1);
            Map(c0 - kk * s0, s0 + kk * c0, ax1, ay1);
            Map(c1 + kk * s1, s1 - kk * c1, ax2, ay2);
            Map(c1, s1, ax, ay);
            Cubic(ax1, ay1, ax2, ay2, ax, ay);
          end;
        end;
      zrR:
        begin
          ax := APath[i].V[0];
          ay := APath[i].V[1];
          t := APath[i].V[2];
          u := APath[i].V[3];
          Cmd(pckMove, 0, 0, 0, 0, ax, ay);
          Cmd(pckLine, 0, 0, 0, 0, ax + t, ay);
          Cmd(pckLine, 0, 0, 0, 0, ax + t, ay + u);
          Cmd(pckLine, 0, 0, 0, 0, ax, ay + u);
          Cmd(pckClose, 0, 0, 0, 0, ax, ay);
          Pt(ax, ay);
          Pt(ax + t, ay);
          Pt(ax + t, ay + u);
          Pt(ax, ay + u);
          lastX := ax;
          lastY := ay;
          x0 := ax;
          y0 := ay;
        end;
      zrZ:
        begin
          Cmd(pckClose, 0, 0, 0, 0, x0, y0);
          lastX := x0;
          lastY := y0;
        end;
    end;
  SetLength(ACmds, nc);
  SetLength(APoints, np);
end;

initialization
  GDegToAngle := cJsPiOne / 180;
end.
