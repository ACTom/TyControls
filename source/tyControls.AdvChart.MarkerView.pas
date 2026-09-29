unit tyControls.AdvChart.MarkerView;
{$mode objfpc}{$H+}
{ WHAT A MARKER DRAWS. The Marker unit decides which items survive and where
  their ends land; this one turns a surviving markLine into upstream's
  picture -- the segment (chart/helper/Line.ts createLine, zrender's Line
  with its sub-pixel step), the two end symbols (createSymbol at full size,
  turned along the line), and the label (Line.beforeUpdate's placement
  table, labelStyle's text style, zrender's updateInnerText and its outside
  ink) -- as numbers, then as paint-list elements.

  THE MERGED ITEM. A line reads its lineStyle, label and z2 from the line
  item upstream builds by merging the start item and then the end item into
  {type, valueIndex, value}, a key already there staying: so a lineStyle or
  a label on the END reaches the line when the start has none, and two
  objects under one key merge key by key. The master markLine is its own
  option merged over the defaults the same way. A view here is that list of
  objects, first one holding a key winning.

  PURE: option and layout in, numbers and elements out. [Batch 65] }
interface

uses SysUtils, Math, fpjson,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape, tyControls.AdvChart.Paint,
     tyControls.AdvChart.ZrPath, tyControls.AdvChart.Marker;

type
  TTyMkSymbolPic = record
    Present: Boolean;
    { the visual type, and the shape drawn: 'empty' taken off, an unknown
      name drawn as a rect }
    Symbol, ShapeType: string;
    Empty: Boolean;
    { createSymbol's box, centred on the end and moved by symbolOffset }
    Box: TTyXYWH;
    X, Y, Rotation: Double;
    HasTransform: Boolean;
    Transform: TTyMat2D;
    { in the symbol's own coordinates }
    Path: TTyZrPath;
    { '' for none }
    Fill, Stroke: string;
    LineWidth: Double;
    { NaN: the style holds no opacity (painted as 1) }
    Opacity: Double;
    Z2: Double;
  end;

  TTyMkLabelPic = record
    Present: Boolean;
    Text: string;
    { the text element's own props (Line.beforeUpdate) }
    X, Y, Rotation, OriginX, OriginY: Double;
    { after label.rotate / label.offset (updateInnerText) }
    InnerX, InnerY, InnerRotation, InnerOriginX, InnerOriginY: Double;
    HasTransform: Boolean;
    Transform: TTyMat2D;
    { '' for unset (the text then lays out left / top) }
    Align, VAlign: string;
    Font: string;
    FontSize, FontWeight, FontStyle, FontFamily: TJSONData;
    { the style's own: '' / NaN for not in the style }
    StyleFill, StyleStroke: string;
    StyleLineWidth, StyleOpacity: Double;
    { updateInnerText's outside ink }
    DefFill, DefStroke: string;
    { what is painted; HasInk False when the text is empty }
    HasInk: Boolean;
    InkFill, InkStroke: string;
    InkLineWidth, InkOpacity: Double;
    Z2: Double;
    Silent: Boolean;
  end;

  TTyMkLinePic = record
    { the line's index in the block's Lines }
    Item: Integer;
    { False when an end point holds NaN: nothing is drawn }
    Drawn: Boolean;
    X1, Y1, X2, Y2: Double;
    { after the sub-pixel step }
    Path: TTyZrPath;
    Stroke: string;
    LineWidth: Double;
    DashType: TJSONData;
    Dash: TTyDoubleArray;
    DashOffset, Opacity: Double;
    LineCap, LineJoin: string;
    Z2: Double;
    FromSym, ToSym: TTyMkSymbolPic;
    Lbl: TTyMkLabelPic;
  end;
  TTyMkLinePicArray = array of TTyMkLinePic;

  { what the pictures need besides the block }
  TTyMkPicInput = record
    { the series' style colour, a css string: every colour falls back to it }
    SeriesColor: string;
    { {a}; undefined when the series has no name }
    SeriesName: TTyMkVal;
    { ecModel.option.textStyle: the option's own, nil for none }
    TextStyle: TJSONObject;
    { the chart's ground: a css string, and whether it counts as dark }
    Background: string;
    IsDark: Boolean;
    { device px per css px }
    Scale: Double;
  end;

{ the global text style's defaults (globalDefault.ts): 12 px, normal, and
  'Microsoft YaHei' on Windows, else 'sans-serif' }
function TyMkDefaultTextStyle: TJSONObject;
{ Element.getOutsideStroke: the ground over white (or black when dark) }
function TyMkOutsideStroke(const ABackground: string; AIsDark: Boolean): string;
{ zrender's isDarkMode for a css ground }
function TyMkGroundIsDark(const ABackground: string): Boolean;

{ every surviving markLine of the block, in the block's data order }
function TyMkLinePictures(const ABlock: TTyMkBlock;
  const AIn: TTyMkPicInput): TTyMkLinePicArray;

type
  { the theme's side of a marker label: where the author set no font or
    colour the skin decides, as every other label in the chart }
  TTyMkInk = record
    FontName: string;
    FontSizeLogical, FontWeight: Integer;
    { the outside ink, and the halo round it (the ground) }
    Text, Halo: TTyChartColor;
    { the inside ink over a light, a mid and a dark fill }
    Inside: array[0..2] of TTyChartColor;
  end;

{ the paint-list elements of a series' markLines: segment, symbols, label.
  Silent all: markers carry no tooltip yet, and a hover on one must not
  report the series under it. }
function TyBuildMarkLines(const APics: TTyMkLinePicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList): Integer;

type
  { a markPoint's label (Symbol.ts's setLabelStyle on the symbol path) }
  TTyMkPtLabelPic = record
    Present: Boolean;
    { HasText False: getDefaultLabel answered nothing (no value, or no label
      dimension) }
    HasText: Boolean;
    Text: string;
    { rich text is not drawn: the words are kept, no ink }
    Rich: Boolean;
    Lines: Integer;
    Position: TJSONData;
    Distance: Double;
    { the symbol path's bounding rect, grown by its stroke, in global px }
    Rect: TTyXYWH;
    InnerX, InnerY, InnerRotation, InnerOriginX, InnerOriginY: Double;
    HasTransform: Boolean;
    Transform: TTyMat2D;
    { as laid out; the author's; calculateTextPosition's }
    Align, VAlign, AuthorAlign, AuthorVAlign, DefAlign, DefVAlign: string;
    Inside: Boolean;
    Font: string;
    FontSize, FontWeight, FontStyle, FontFamily: TJSONData;
    StyleFill, StyleStroke: string;
    StyleLineWidth, StyleOpacity: Double;
    StyleBackground: TJSONData;
    DefFill, DefStroke: string;
    HasInk: Boolean;
    InkFill, InkStroke: string;
    InkLineWidth, InkOpacity: Double;
    Z2: Double;
    Silent: Boolean;
  end;

  TTyMkPointPic = record
    Item: Integer;
    { the fill after the series colour fallback }
    Fill: string;
    { False: the point holds NaN or the symbol is 'none' }
    Drawn: Boolean;
    Symbol, ShapeType: string;
    Empty: Boolean;
    { the Symbol group at the point }
    GroupX, GroupY: Double;
    HasGroupTransform: Boolean;
    GroupTransform: TTyMat2D;
    { the path inside it: offset, turn, size / 2 over the unit box }
    X, Y, Rotation, ScaleX, ScaleY: Double;
    HasLocal, HasGlobal: Boolean;
    Local, Global: TTyMat2D;
    { the unit box's path, and its rect }
    Path: TTyZrPath;
    BBox: TTyXYWH;
    LineScale: Double;
    StyleFill, StyleStroke: string;
    StyleLineWidth, StyleOpacity, StyleDashOffset: Double;
    StyleDash: TJSONData;
    { what the painter strokes: width and dash in the path's own units }
    PaintStroke: Boolean;
    PaintWidth: Double;
    HasPaintDash: Boolean;
    PaintDash: TTyDoubleArray;
    Z2: Double;
    Lbl: TTyMkPtLabelPic;
  end;
  TTyMkPointPicArray = array of TTyMkPointPic;

{ every surviving markPoint of the block, in data order. AXType / AYType:
  the coordinate dims' types, which say which dim the default text reads. }
function TyMkPointPictures(const ABlock: TTyMkBlock; const AIn: TTyMkPicInput;
  AXIsLabel, AYIsLabel: Boolean): TTyMkPointPicArray;
{ the paint-list elements of a series' markPoints }
function TyBuildMarkPoints(const APics: TTyMkPointPicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList): Integer;
{ zrender's lum(color, background): 0 for what does not parse }
function TyMkLum(const AColour: string; ABackground: Double): Double;

{ zrender's PathProxy commands through a matrix, arcs as cubics, into a
  polygon shape carrying them }
function TyMkZrShape(const APath: TTyZrPath; const M: TTyMat2D;
  AHasMatrix: Boolean): TTyChartShape;

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Data, tyControls.AdvChart.Color, tyControls.AdvChart.Labels;

type
  TMkView = array of TJSONObject;
  TMkLevels = array of TMkView;

var
  GTextDefaults: TJSONObject;
  { 'outside' as createTextConfig rewrites it }
  GTopWord: TJSONString;

function JNull(A: TJSONData): Boolean; inline;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

function Truthy(A: TJSONData): Boolean;
begin
  if JNull(A) then Exit(False);
  case A.JSONType of
    jtBoolean: Result := A.AsBoolean;
    jtNumber: Result := (not IsNan(A.AsFloat)) and (A.AsFloat <> 0);
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

function NumOf(A: TJSONData): Double;
begin
  Result := TyMkJsNumber(TyMkOf(A));
end;

function StrOf(A: TJSONData): string;
begin
  if (A <> nil) and (A.JSONType = jtString) then Result := A.AsString
  else Result := '';
end;

{ String(v) of an option value }
function JsStringOf(A: TJSONData): string;
begin
  if A = nil then Exit('undefined');
  case A.JSONType of
    jtNull: Result := 'null';
    jtString: Result := A.AsString;
    jtNumber: Result := TyJsNumberToString(A.AsFloat);
    jtBoolean: if A.AsBoolean then Result := 'true' else Result := 'false';
  else
    Result := '';
  end;
end;

function ValString(const V: TTyMkVal): string;
begin
  case V.Kind of
    mvkUndef: Result := 'undefined';
    mvkNull: Result := 'null';
    mvkNum: Result := TyJsNumberToString(V.Num);
    mvkStr: Result := V.Str;
  else
    if V.Num = 1 then Result := 'true'
    else if V.Num = 0 then Result := 'false'
    else Result := '';
  end;
end;

{ ---- views: objects merged key by key, the first holding a key winning ---- }

function VGet(const V: TMkView; const AKey: string): TJSONData;
var i: Integer;
begin
  for i := 0 to High(V) do
    if (V[i] <> nil) and (V[i].IndexOfName(AKey) >= 0) then Exit(V[i].Find(AKey));
  Result := nil;
end;

function VSub(const V: TMkView; const AKey: string): TMkView;
var
  i, n: Integer;
  d: TJSONData;
  started: Boolean;
begin
  Result := nil;
  n := 0;
  started := False;
  for i := 0 to High(V) do
  begin
    if (V[i] = nil) or (V[i].IndexOfName(AKey) < 0) then Continue;
    d := V[i].Find(AKey);
    if not started then
    begin
      { a value that is not an object won the key outright }
      if d.JSONType <> jtObject then Exit(nil);
      started := True;
    end;
    if d.JSONType = jtObject then
    begin
      SetLength(Result, n + 1);
      Result[n] := TJSONObject(d);
      Inc(n);
    end;
  end;
end;

function View1(A: TJSONObject): TMkView;
begin
  SetLength(Result, 1);
  Result[0] := A;
end;

function View2(A, B: TJSONObject): TMkView;
begin
  SetLength(Result, 2);
  Result[0] := A;
  Result[1] := B;
end;

{ Model.get / getShallow over the levels: the first that is not null }
function Chain(const L: TMkLevels; const AKey: string; AOwnOnly: Boolean = False): TJSONData;
var i: Integer;
begin
  Result := nil;
  for i := 0 to High(L) do
  begin
    Result := VGet(L[i], AKey);
    if AOwnOnly or not JNull(Result) then Break;
  end;
  if JNull(Result) then Result := nil;
end;

function Sub(const L: TMkLevels; const AKey: string): TMkLevels;
var i: Integer;
begin
  SetLength(Result, Length(L));
  for i := 0 to High(L) do Result[i] := VSub(L[i], AKey);
end;

function Levels3(const A, B, C: TMkView): TMkLevels;
begin
  SetLength(Result, 3);
  Result[0] := A;
  Result[1] := B;
  Result[2] := C;
end;

{ ---- ground ---- }

function TyMkDefaultTextStyle: TJSONObject;
begin
  Result := GTextDefaults;
end;

function TyMkGroundIsDark(const ABackground: string): Boolean;
var r, g, b, a, l: Double;
begin
  if ABackground = '' then Exit(False);
  { lum(color, 1): what shows through counts as white }
  if TyTryParseCssRgba(ABackground, r, g, b, a) then
    l := (0.299 * r + 0.587 * g + 0.114 * b) * a / 255 + (1 - a) * 1
  else
    l := 0;
  Result := l < 0.4;
end;

function TyMkOutsideStroke(const ABackground: string; AIsDark: Boolean): string;
var
  c: array[0..3] of Double;
  a, under: Double;
  i: Integer;
begin
  if not TyTryParseCssRgba(ABackground, c[0], c[1], c[2], c[3]) then
  begin
    c[0] := 255;
    c[1] := 255;
    c[2] := 255;
    c[3] := 1;
  end;
  a := c[3];
  if AIsDark then under := 0 else under := 255;
  for i := 0 to 2 do c[i] := c[i] * a + under * (1 - a);
  Result := 'rgba(' + TyJsNumberToString(c[0]) + ',' + TyJsNumberToString(c[1])
    + ',' + TyJsNumberToString(c[2]) + ',1)';
end;

{ ---- zrender pieces ---- }

{ subPixelOptimize.ts }
function SubPixel(APosition, ALineWidth: Double): Double;
var doubled: Double;
begin
  if (ALineWidth = 0) or IsNan(ALineWidth) then Exit(APosition);
  doubled := TyJsRound(APosition * 2);
  if IsNan(doubled) then Exit(NaN);
  if Frac((doubled + TyJsRound(ALineWidth)) / 2) = 0 then
    Result := doubled / 2
  else
    Result := (doubled + 1) / 2;
end;

function LinePath(AX1, AY1, AX2, AY2, ALineWidth: Double): TTyZrPath;
begin
  Result := nil;
  if (ALineWidth <> 0) and not IsNan(ALineWidth) then
  begin
    if TyJsRound(AX1 * 2) = TyJsRound(AX2 * 2) then
    begin
      AX1 := SubPixel(AX1, ALineWidth);
      AX2 := AX1;
    end;
    if TyJsRound(AY1 * 2) = TyJsRound(AY2 * 2) then
    begin
      AY1 := SubPixel(AY1, ALineWidth);
      AY2 := AY1;
    end;
  end;
  TyZrMoveTo(Result, AX1, AY1);
  TyZrLineTo(Result, AX2, AY2);
end;

{ canvas/dashStyle normalizeLineDash + getLineDash, no line scale }
function ResolveDash(AType: TJSONData; ALineWidth: Double): TTyDoubleArray;
var
  i: Integer;
  s: string;
begin
  Result := nil;
  if not (Truthy(AType) and (ALineWidth > 0)) then Exit;
  case AType.JSONType of
    jtString:
      begin
        s := AType.AsString;
        if s = 'dashed' then
        begin
          SetLength(Result, 2);
          Result[0] := 4 * ALineWidth;
          Result[1] := 2 * ALineWidth;
        end
        else if s = 'dotted' then
        begin
          SetLength(Result, 1);
          Result[0] := ALineWidth;
        end;
      end;
    jtNumber:
      begin
        SetLength(Result, 1);
        Result[0] := AType.AsFloat;
      end;
    jtArray:
      begin
        SetLength(Result, AType.Count);
        for i := 0 to AType.Count - 1 do Result[i] := NumOf(AType.Items[i]);
      end;
  end;
end;

function NotAroundZero(A: Double): Boolean; inline;
begin
  Result := (A > 5e-5) or (A < -5e-5);
end;

{ Transformable.getLocalTransform with an origin, scale 1 }
function LocalTransform(AX, AY, ARotation, AOriginX, AOriginY: Double;
  out M: TTyMat2D): Boolean;
var aa, ac, atx, ab, ad, aty, st, ct: Double;
begin
  Result := NotAroundZero(ARotation) or NotAroundZero(AX) or NotAroundZero(AY);
  if not Result then Exit;
  if (AOriginX <> 0) or (AOriginY <> 0) then
  begin
    M[4] := -AOriginX * 1 - 0 * AOriginY * 1;
    M[5] := -AOriginY * 1 - 0 * AOriginX * 1;
  end
  else
  begin
    M[4] := 0;
    M[5] := 0;
  end;
  M[0] := 1;
  M[3] := 1;
  M[1] := 0;
  M[2] := 0;
  if ARotation <> 0 then
  begin
    aa := M[0]; ac := M[2]; atx := M[4];
    ab := M[1]; ad := M[3]; aty := M[5];
    st := TyJsSin(ARotation);
    ct := TyJsCos(ARotation);
    M[0] := aa * ct + ab * st;
    M[1] := -aa * st + ab * ct;
    M[2] := ac * ct + ad * st;
    M[3] := -ac * st + ct * ad;
    M[4] := ct * (atx - 0) + st * (aty - 0) + 0;
    M[5] := ct * (aty - 0) - st * (atx - 0) + 0;
  end;
  M[4] := M[4] + (AOriginX + AX);
  M[5] := M[5] + (AOriginY + AY);
end;

{ ---- text ---- }

function ParseFontSize(A: TJSONData): string;
var n: Double;
begin
  if (A <> nil) and (A.JSONType = jtString) and ((Pos('px', A.AsString) > 0)
    or (Pos('rem', A.AsString) > 0) or (Pos('em', A.AsString) > 0)) then
    Exit(A.AsString);
  n := TyMkJsNumber(TyMkOf(A));
  if not IsNan(n) then Exit(JsStringOf(A) + 'px');
  Result := '12px';
end;

function MakeFont(AStyle, AWeight, ASize, AFamily: TJSONData): string;
var fam: string;
  function Part(A: TJSONData): string;
  begin
    if JNull(A) then Result := '' else Result := JsStringOf(A);
  end;
begin
  Result := '';
  if (not JNull(ASize)) or Truthy(AFamily) or Truthy(AWeight) then
  begin
    if Truthy(AFamily) then fam := JsStringOf(AFamily) else fam := 'sans-serif';
    Result := Trim(Part(AStyle) + ' ' + Part(AWeight) + ' ' + ParseFontSize(ASize)
      + ' ' + fam);
  end;
end;

function NormAlign(const A: string): string;
begin
  Result := A;
  if Result = 'middle' then Result := 'center';
  if (Result <> '') and (Result <> 'left') and (Result <> 'right')
    and (Result <> 'center') then Result := 'left';
end;

function NormVAlign(const A: string): string;
begin
  Result := A;
  if Result = 'center' then Result := 'middle';
  if (Result <> '') and (Result <> 'top') and (Result <> 'bottom')
    and (Result <> 'middle') then Result := 'top';
end;

{ formatTpl: {a} {b} {c}, each replaced at its FIRST occurrence only }
function FormatTpl(const ATpl: string; const AValues: array of string): string;
const cAlias: array[0..2] of Char = ('a', 'b', 'c');
var
  k, p: Integer;
  from: string;
begin
  Result := ATpl;
  for k := 0 to 2 do
  begin
    from := '{' + cAlias[k] + '}';
    p := Pos(from, Result);
    if p > 0 then
      Result := Copy(Result, 1, p - 1) + '{' + cAlias[k] + '0}'
        + Copy(Result, p + Length(from), MaxInt);
  end;
  for k := 0 to 2 do
  begin
    from := '{' + cAlias[k] + '0}';
    p := Pos(from, Result);
    if p > 0 then
      Result := Copy(Result, 1, p - 1) + AValues[k]
        + Copy(Result, p + Length(from), MaxInt);
  end;
end;

{ ---- the pictures ---- }

function TyMkLinePictures(const ABlock: TTyMkBlock;
  const AIn: TTyMkPicInput): TTyMkLinePicArray;
var
  own, master, gts: TMkView;
  ML: TMkLevels;
  i, n: Integer;
  maxZ2: Double;
  L: TTyMkLine;
  pic: TTyMkLinePic;
  s: Double;

  procedure RunZ2(A: Double);
  begin
    { Math.max(z2 || 0, maxZ2) }
    if IsNan(A) then A := 0;
    if A > maxZ2 then maxZ2 := A;
  end;

  function EndFill(const AEnd: TTyMkEnd): string;
  var d: TJSONData;
  begin
    d := Chain(Sub(Levels3(View1(AEnd.Src), own, master), 'itemStyle'), 'color');
    if d <> nil then Result := StrOf(d) else Result := AIn.SeriesColor;
  end;

  procedure Symbol(const AEnd: TTyMkEnd; AIsTo: Boolean; const AStroke: string;
    ALsOpacity: Double; ATx, ATy: Double; out P: TTyMkSymbolPic);
  var
    t, st: TJSONData;
    typ: string;
    w, h, ox, oy, rot: Double;
    sz, off: TJSONData;
    o0, o1: TJSONData;
  begin
    P := Default(TTyMkSymbolPic);
    t := TyMkLineVisual(ABlock, L.Index, not AIsTo, 'symbol');
    typ := StrOf(t);
    if (typ = '') or (typ = 'none') then Exit;
    P.Present := True;
    P.Symbol := typ;
    P.Empty := Copy(typ, 1, 5) = 'empty';
    if P.Empty then P.ShapeType := LowerCase(Copy(typ, 6, 1)) + Copy(typ, 7, MaxInt)
    else P.ShapeType := typ;
    { normalizeSymbolSize }
    sz := TyMkLineVisual(ABlock, L.Index, not AIsTo, 'symbolSize');
    if (sz <> nil) and (sz.JSONType = jtArray) then
    begin
      if sz.Count > 0 then w := NumOf(sz.Items[0]) else w := NaN;
      if sz.Count > 1 then h := NumOf(sz.Items[1]) else h := NaN;
    end
    else
    begin
      w := NumOf(sz);
      if sz = nil then w := NaN;
      h := w;
    end;
    if IsNan(w) then w := 0;
    if IsNan(h) then h := 0;
    { normalizeSymbolOffset(offset || 0, size) }
    off := TyMkLineVisual(ABlock, L.Index, not AIsTo, 'symbolOffset');
    ox := 0;
    oy := 0;
    if Truthy(off) then
    begin
      if off.JSONType = jtArray then
      begin
        o0 := nil;
        o1 := nil;
        if off.Count > 0 then o0 := off.Items[0];
        if off.Count > 1 then o1 := off.Items[1];
        if JNull(o1) then o1 := o0;
      end
      else
      begin
        o0 := off;
        o1 := off;
      end;
      ox := TyMkParsePercent(o0, w);
      oy := TyMkParsePercent(o1, h);
      if IsNan(ox) then ox := 0;
      if IsNan(oy) then oy := 0;
    end;
    P.Box.X := (-w / 2 + ox) * s;
    P.Box.Y := (-h / 2 + oy) * s;
    P.Box.W := w * s;
    P.Box.H := h * s;
    { symbolRotate: a number turns it, and turns the tangent off }
    st := TyMkLineVisual(ABlock, L.Index, not AIsTo, 'symbolRotate');
    rot := NaN;
    if st <> nil then
    begin
      rot := NumOf(st);
      if not IsNan(rot) then
      begin
        rot := rot * Pi / 180;
        if IsNan(rot) then rot := 0;
      end;
    end;
    if IsNan(rot) then
    begin
      if AIsTo then rot := -1 * Pi / 2 - TyJsAtan2(ATy, ATx)
      else rot := 1 * Pi / 2 - TyJsAtan2(ATy, ATx);
    end;
    P.Rotation := rot;
    if AIsTo then
    begin
      P.X := L.To_.Point.X;
      P.Y := L.To_.Point.Y;
    end
    else
    begin
      P.X := L.From.Point.X;
      P.Y := L.From.Point.Y;
    end;
    P.HasTransform := LocalTransform(P.X, P.Y, P.Rotation, 0, 0, P.Transform);
    P.Path := TyZrSymbol(P.ShapeType, P.Box.X, P.Box.Y, P.Box.W, P.Box.H);
    { setColor: the line's stroke }
    P.Fill := '#000';
    P.Stroke := '';
    P.LineWidth := 1;
    if P.Empty then
    begin
      P.Stroke := AStroke;
      P.Fill := '#fff';
      P.LineWidth := 2;
    end
    else if P.ShapeType = 'line' then
      P.Stroke := AStroke
    else
      P.Fill := AStroke;
    P.Opacity := ALsOpacity;
    P.Z2 := 0;
    RunZ2(0);
  end;

  procedure Picture(var P: TTyMkLinePic);
  var
    lineV: TMkView;
    itemLv, LS, LB: TMkLevels;
    d, lineType: TJSONData;
    fromFill, stroke, name, str, pos, rawA, rawV, textAlign, textVAlign,
      defFill, fc, sc: string;
    lsOpacity, tx, ty, len, dx, dy_, distX, distY, dirv, cpx, cpy, dy,
      lrot, v, rv: Double;
    rawVal: TTyMkVal;
    hasFc, hasSc, useDefault, rotSet: Boolean;
    offA: TJSONData;
    inkStroke: string;
    dlw: Double;
    label_: TTyMkLabelPic;
  begin
    lineV := View2(L.From.Src, L.To_.Src);
    itemLv := Levels3(lineV, own, master);
    fromFill := EndFill(L.From);
    { the line: lineStyle through the merged item, the stroke falling back
      to the start end's fill }
    LS := Sub(itemLv, 'lineStyle');
    d := Chain(LS, 'color');
    if d <> nil then stroke := StrOf(d) else stroke := fromFill;
    d := Chain(LS, 'width');
    if d <> nil then P.LineWidth := NumOf(d) else P.LineWidth := 1;
    d := Chain(LS, 'opacity');
    if d <> nil then lsOpacity := NumOf(d) else lsOpacity := NaN;
    lineType := Chain(LS, 'type');
    P.DashType := lineType;
    P.Dash := ResolveDash(lineType, P.LineWidth);
    d := Chain(LS, 'dashOffset');
    if d <> nil then P.DashOffset := NumOf(d) else P.DashOffset := 0;
    if IsNan(lsOpacity) then P.Opacity := 1 else P.Opacity := lsOpacity;
    d := Chain(LS, 'cap');
    if d <> nil then P.LineCap := JsStringOf(d) else P.LineCap := 'butt';
    d := Chain(LS, 'join');
    if d <> nil then P.LineJoin := JsStringOf(d) else P.LineJoin := '';
    P.Stroke := stroke;
    d := Chain(itemLv, 'z2');
    if d <> nil then P.Z2 := NumOf(d) else P.Z2 := 0;
    P.X1 := L.From.Point.X;
    P.Y1 := L.From.Point.Y;
    P.X2 := L.To_.Point.X;
    P.Y2 := L.To_.Point.Y;
    P.Path := LinePath(P.X1, P.Y1, P.X2, P.Y2, P.LineWidth * s);
    RunZ2(P.Z2);
    { the tangent: LinePath.tangentAt, the un-snapped shape }
    tx := P.X2 - P.X1;
    ty := P.Y2 - P.Y1;
    len := Sqrt(tx * tx + ty * ty);
    if len = 0 then
    begin
      tx := 0;
      ty := 0;
    end
    else
    begin
      tx := tx / len;
      ty := ty / len;
    end;
    Symbol(L.From, False, stroke, lsOpacity, tx, ty, P.FromSym);
    Symbol(L.To_, True, stroke, lsOpacity, tx, ty, P.ToSym);

    { ---- the label ---- }
    label_ := Default(TTyMkLabelPic);
    LB := Sub(itemLv, 'label');
    if not Truthy(Chain(LB, 'show')) then
    begin
      P.Lbl := label_;
      Exit;
    end;
    label_.Present := True;
    { the default text: the value rounded to ten places, else the name }
    rawVal := L.LineValue;
    case L.LineName.Kind of
      mvkStr: name := L.LineName.Str;
      mvkNum: name := TyJsNumberToString(L.LineName.Num);
    else
      name := '';
    end;
    d := Chain(LB, 'formatter');
    if (d <> nil) and (d.JSONType = jtString) then
    begin
      if AIn.SeriesName.Kind = mvkUndef then
        str := FormatTpl(d.AsString, ['undefined', name, ValString(rawVal)])
      else
        str := FormatTpl(d.AsString, [ValString(AIn.SeriesName), name, ValString(rawVal)]);
    end
    else if rawVal.Kind in [mvkUndef, mvkNull] then
      str := name
    else
    begin
      v := TyMkJsNumber(rawVal);
      if (not IsNan(v)) and (not IsInfinite(v)) then
        str := TyJsNumberToString(TyJsToFixed(v, 10))
      else
        str := ValString(rawVal);
    end;
    label_.Text := str;
    { createTextStyle, attached }
    fc := '';
    sc := '';
    d := Chain(LB, 'color');
    hasFc := d <> nil;
    if hasFc then
    begin
      fc := StrOf(d);
      if (fc = 'inherit') or (fc = 'auto') then
      begin
        fc := stroke;
        if fc = '' then fc := '#000';
      end;
    end;
    d := Chain(LB, 'textBorderColor');
    hasSc := d <> nil;
    if hasSc then
    begin
      sc := StrOf(d);
      if (sc = 'inherit') or (sc = 'auto') then
      begin
        sc := stroke;
        if sc = '' then sc := '#000';
      end;
    end;
    if hasFc then label_.StyleFill := fc;
    if hasSc then label_.StyleStroke := sc;
    d := Chain(LB, 'textBorderWidth');
    if d = nil then d := VGet(gts, 'textBorderWidth');
    if JNull(d) then label_.StyleLineWidth := NaN else label_.StyleLineWidth := NumOf(d);
    d := Chain(LB, 'opacity');
    if d = nil then d := VGet(gts, 'opacity');
    if JNull(d) then label_.StyleOpacity := lsOpacity else label_.StyleOpacity := NumOf(d);
    label_.FontStyle := Chain(LB, 'fontStyle');
    if label_.FontStyle = nil then label_.FontStyle := VGet(gts, 'fontStyle');
    label_.FontWeight := Chain(LB, 'fontWeight');
    if label_.FontWeight = nil then label_.FontWeight := VGet(gts, 'fontWeight');
    label_.FontSize := Chain(LB, 'fontSize');
    if label_.FontSize = nil then label_.FontSize := VGet(gts, 'fontSize');
    label_.FontFamily := Chain(LB, 'fontFamily');
    if label_.FontFamily = nil then label_.FontFamily := VGet(gts, 'fontFamily');
    if JNull(label_.FontStyle) then label_.FontStyle := nil;
    if JNull(label_.FontWeight) then label_.FontWeight := nil;
    if JNull(label_.FontSize) then label_.FontSize := nil;
    if JNull(label_.FontFamily) then label_.FontFamily := nil;
    label_.Font := MakeFont(label_.FontStyle, label_.FontWeight, label_.FontSize,
      label_.FontFamily);
    rawA := '';
    d := Chain(LB, 'align');
    if Truthy(d) then rawA := JsStringOf(d);
    rawV := '';
    d := Chain(LB, 'verticalAlign');
    if d = nil then d := Chain(LB, 'baseline');
    if Truthy(d) then rawV := JsStringOf(d);

    { ---- Line.beforeUpdate's placement ---- }
    d := Chain(LB, 'distance');
    if (d <> nil) and (d.JSONType = jtArray) then
    begin
      if d.Count > 0 then distX := NumOf(d.Items[0]) else distX := NaN;
      if d.Count > 1 then distY := NumOf(d.Items[1]) else distY := NaN;
    end
    else
    begin
      if d = nil then distX := NaN else distX := NumOf(d);
      distY := distX;
    end;
    distX := distX * s;
    distY := distY * s;
    { d: from the start to the end, normalised }
    dx := P.X2 - P.X1;
    dy_ := P.Y2 - P.Y1;
    len := Sqrt(dx * dx + dy_ * dy_);
    if len = 0 then
    begin
      dx := 0;
      dy_ := 0;
    end
    else
    begin
      dx := dx / len;
      dy_ := dy_ / len;
    end;
    cpx := P.X1 * (1 - 0.5) + P.X2 * 0.5;
    cpy := P.Y1 * (1 - 0.5) + P.Y2 * 0.5;
    if tx < 0 then dirv := -1 else dirv := 1;
    d := Chain(LB, 'position');
    if Truthy(d) then pos := JsStringOf(d) else pos := 'middle';
    if (d <> nil) and Truthy(d) and (d.JSONType <> jtString) then pos := #0;
    label_.X := 0;
    label_.Y := 0;
    label_.Rotation := 0;
    label_.OriginX := 0;
    label_.OriginY := 0;
    if (pos <> 'start') and (pos <> 'end') then
    begin
      label_.Rotation := -TyJsAtan2(ty, tx);
      if P.X2 < P.X1 then label_.Rotation := Pi + label_.Rotation;
    end;
    if (pos = 'insideStartTop') or (pos = 'insideMiddleTop') or (pos = 'insideEndTop')
      or (pos = 'middle') then
    begin
      dy := -distY;
      textVAlign := 'bottom';
    end
    else if (pos = 'insideStartBottom') or (pos = 'insideMiddleBottom')
      or (pos = 'insideEndBottom') then
    begin
      dy := distY;
      textVAlign := 'top';
    end
    else
    begin
      dy := 0;
      textVAlign := 'middle';
    end;
    textAlign := '';
    if pos = 'end' then
    begin
      label_.X := dx * distX + P.X2;
      label_.Y := dy_ * distY + P.Y2;
      if dx > 0.8 then textAlign := 'left'
      else if dx < -0.8 then textAlign := 'right'
      else textAlign := 'center';
      if dy_ > 0.8 then textVAlign := 'top'
      else if dy_ < -0.8 then textVAlign := 'bottom'
      else textVAlign := 'middle';
    end
    else if pos = 'start' then
    begin
      label_.X := -dx * distX + P.X1;
      label_.Y := -dy_ * distY + P.Y1;
      if dx > 0.8 then textAlign := 'right'
      else if dx < -0.8 then textAlign := 'left'
      else textAlign := 'center';
      if dy_ > 0.8 then textVAlign := 'bottom'
      else if dy_ < -0.8 then textVAlign := 'top'
      else textVAlign := 'middle';
    end
    else if (pos = 'insideStartTop') or (pos = 'insideStart')
      or (pos = 'insideStartBottom') then
    begin
      label_.X := distX * dirv + P.X1;
      label_.Y := P.Y1 + dy;
      if tx < 0 then textAlign := 'right' else textAlign := 'left';
      label_.OriginX := -distX * dirv;
      label_.OriginY := -dy;
    end
    else if (pos = 'insideMiddleTop') or (pos = 'insideMiddle')
      or (pos = 'insideMiddleBottom') or (pos = 'middle') then
    begin
      label_.X := cpx;
      label_.Y := cpy + dy;
      textAlign := 'center';
      label_.OriginY := -dy;
    end
    else if (pos = 'insideEndTop') or (pos = 'insideEnd')
      or (pos = 'insideEndBottom') then
    begin
      label_.X := -distX * dirv + P.X2;
      label_.Y := P.Y2 + dy;
      if tx >= 0 then textAlign := 'right' else textAlign := 'left';
      label_.OriginX := distX * dirv;
      label_.OriginY := -dy;
    end;
    if rawA <> '' then label_.Align := NormAlign(rawA)
    else label_.Align := NormAlign(textAlign);
    if rawV <> '' then label_.VAlign := NormVAlign(rawV)
    else label_.VAlign := NormVAlign(textVAlign);

    { updateInnerText: label.rotate replaces the turn, label.offset moves it
      and the pivot }
    label_.InnerX := label_.X;
    label_.InnerY := label_.Y;
    label_.InnerRotation := label_.Rotation;
    label_.InnerOriginX := label_.OriginX;
    label_.InnerOriginY := label_.OriginY;
    d := Chain(LB, 'rotate');
    rotSet := d <> nil;
    if rotSet then
    begin
      lrot := NumOf(d);
      label_.InnerRotation := lrot * Pi / 180;
    end;
    offA := Chain(LB, 'offset');
    if Truthy(offA) and (offA.JSONType = jtArray) and (offA.Count >= 2) then
    begin
      rv := NumOf(offA.Items[0]) * s;
      v := NumOf(offA.Items[1]) * s;
      label_.InnerX := label_.InnerX + rv;
      label_.InnerY := label_.InnerY + v;
      label_.InnerOriginX := -rv;
      label_.InnerOriginY := -v;
    end;
    label_.HasTransform := LocalTransform(label_.InnerX, label_.InnerY,
      label_.InnerRotation, label_.InnerOriginX, label_.InnerOriginY,
      label_.Transform);

    { the outside ink }
    d := Chain(LB, 'color');
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'inherit') then
    begin
      defFill := stroke;
      if defFill = '' then defFill := '#000';
    end
    else if AIn.IsDark then defFill := '#ccc'
    else defFill := '#333';
    label_.DefFill := defFill;
    label_.DefStroke := TyMkOutsideStroke(AIn.Background, AIn.IsDark);
    label_.HasInk := str <> '';
    if label_.HasInk then
    begin
      useDefault := not hasFc;
      if useDefault then label_.InkFill := defFill else label_.InkFill := fc;
      if label_.InkFill = 'none' then label_.InkFill := '';
      dlw := 0;
      inkStroke := '';
      if hasSc then inkStroke := sc
      else if (not Truthy(Chain(LB, 'backgroundColor'))) and useDefault then
      begin
        dlw := 2;
        inkStroke := label_.DefStroke;
      end;
      if (inkStroke = 'transparent') or (inkStroke = 'none') then inkStroke := '';
      label_.InkStroke := inkStroke;
      label_.InkLineWidth := NaN;
      if inkStroke <> '' then
      begin
        if (not IsNan(label_.StyleLineWidth)) and (label_.StyleLineWidth <> 0) then
          label_.InkLineWidth := label_.StyleLineWidth
        else
          label_.InkLineWidth := dlw;
      end;
      if IsNan(label_.StyleOpacity) then label_.InkOpacity := 1
      else label_.InkOpacity := label_.StyleOpacity;
    end;
    if IsInfinite(maxZ2) then label_.Z2 := 0 else label_.Z2 := maxZ2 + 2;
    label_.Silent := Truthy(Chain(LB, 'silent'));
    P.Lbl := label_;
  end;

begin
  Result := nil;
  if (not ABlock.Present) or (ABlock.Kind <> mkLine) then Exit;
  s := AIn.Scale;
  if (s <= 0) or IsNan(s) then s := 1;
  own := View1(ABlock.Own);
  master := View2(ABlock.Top, TyMkDefaults(mkLine));
  SetLength(ML, 2);
  ML[0] := own;
  ML[1] := master;
  gts := View2(AIn.TextStyle, GTextDefaults);
  maxZ2 := NegInfinity;
  n := 0;
  SetLength(Result, ABlock.Count);
  for i := 0 to High(ABlock.Lines) do
  begin
    L := ABlock.Lines[i];
    if not L.Survived then Continue;
    pic := Default(TTyMkLinePic);
    pic.Item := i;
    pic.Drawn := not (IsNan(L.From.Point.X) or IsNan(L.From.Point.Y)
      or IsNan(L.To_.Point.X) or IsNan(L.To_.Point.Y));
    if pic.Drawn then Picture(pic);
    if n < Length(Result) then
    begin
      Result[n] := pic;
      Inc(n);
    end;
  end;
  SetLength(Result, n);
end;

{ ---- into shapes ---- }

function TyMkZrShape(const APath: TTyZrPath; const M: TTyMat2D;
  AHasMatrix: Boolean): TTyChartShape;
var
  cmds: TTyPathCmdArray;
  pts: TTyPointFArray;
  nc, np, i, k, parts: Integer;
  closed: Boolean;
  x, y, cx, cy, r, a0, sweep, step, a, b, kk, c0, s0, c1, s1, px0, py0: Double;

  procedure Pt(AX, AY: Double; out OX, OY: Double);
  begin
    if AHasMatrix then TyZrApply(M, AX, AY, OX, OY)
    else
    begin
      OX := AX;
      OY := AY;
    end;
  end;

  procedure Add(AKind: TTyPathCmdKind; AX1, AY1, AX2, AY2, AX, AY: Double);
  begin
    if nc >= Length(cmds) then SetLength(cmds, nc * 2 + 8);
    cmds[nc].Kind := AKind;
    Pt(AX1, AY1, cmds[nc].X1, cmds[nc].Y1);
    Pt(AX2, AY2, cmds[nc].X2, cmds[nc].Y2);
    Pt(AX, AY, cmds[nc].X, cmds[nc].Y);
    Inc(nc);
    if AKind <> pckClose then
    begin
      if np >= Length(pts) then SetLength(pts, np * 2 + 8);
      pts[np] := TyPointF(cmds[nc - 1].X, cmds[nc - 1].Y);
      Inc(np);
    end;
  end;

begin
  cmds := nil;
  pts := nil;
  nc := 0;
  np := 0;
  closed := False;
  x := 0;
  y := 0;
  for i := 0 to High(APath) do
    case APath[i].Cmd of
      zrM:
        begin
          x := APath[i].V[0];
          y := APath[i].V[1];
          Add(pckMove, 0, 0, 0, 0, x, y);
        end;
      zrL:
        begin
          x := APath[i].V[0];
          y := APath[i].V[1];
          Add(pckLine, 0, 0, 0, 0, x, y);
        end;
      zrC:
        begin
          x := APath[i].V[4];
          y := APath[i].V[5];
          Add(pckCurve, APath[i].V[0], APath[i].V[1], APath[i].V[2], APath[i].V[3], x, y);
        end;
      zrQ:
        begin
          { a quadratic as the cubic that draws it }
          Add(pckCurve, x + 2 / 3 * (APath[i].V[0] - x), y + 2 / 3 * (APath[i].V[1] - y),
            APath[i].V[2] + 2 / 3 * (APath[i].V[0] - APath[i].V[2]),
            APath[i].V[3] + 2 / 3 * (APath[i].V[1] - APath[i].V[3]),
            APath[i].V[2], APath[i].V[3]);
          x := APath[i].V[2];
          y := APath[i].V[3];
        end;
      zrA:
        begin
          { the arc as cubics of a quarter turn at most, a line to its start
            first as the canvas does }
          cx := APath[i].V[0];
          cy := APath[i].V[1];
          r := APath[i].V[2];
          a0 := APath[i].V[4];
          sweep := APath[i].V[5];
          px0 := cx + r * Cos(a0);
          py0 := cy + r * Sin(a0);
          if nc = 0 then Add(pckMove, 0, 0, 0, 0, px0, py0)
          else Add(pckLine, 0, 0, 0, 0, px0, py0);
          parts := Ceil(Abs(sweep) / (Pi / 2) - 1e-9);
          if parts < 1 then parts := 1;
          step := sweep / parts;
          kk := 4 / 3 * Tan(step / 4);
          for k := 0 to parts - 1 do
          begin
            a := a0 + step * k;
            b := a + step;
            c0 := Cos(a); s0 := Sin(a);
            c1 := Cos(b); s1 := Sin(b);
            Add(pckCurve, cx + r * (c0 - kk * s0), cy + r * (s0 + kk * c0),
              cx + r * (c1 + kk * s1), cy + r * (s1 - kk * c1),
              cx + r * c1, cy + r * s1);
          end;
          x := cx + r * Cos(a0 + sweep);
          y := cy + r * Sin(a0 + sweep);
        end;
      zrR:
        begin
          Add(pckMove, 0, 0, 0, 0, APath[i].V[0], APath[i].V[1]);
          Add(pckLine, 0, 0, 0, 0, APath[i].V[0] + APath[i].V[2], APath[i].V[1]);
          Add(pckLine, 0, 0, 0, 0, APath[i].V[0] + APath[i].V[2],
            APath[i].V[1] + APath[i].V[3]);
          Add(pckLine, 0, 0, 0, 0, APath[i].V[0], APath[i].V[1] + APath[i].V[3]);
          Add(pckClose, 0, 0, 0, 0, 0, 0);
          closed := True;
          x := APath[i].V[0];
          y := APath[i].V[1];
        end;
      zrZ:
        begin
          Add(pckClose, 0, 0, 0, 0, 0, 0);
          closed := True;
        end;
    end;
  SetLength(cmds, nc);
  SetLength(pts, np);
  { a polygon whether or not it closes: zrender fills an open path too (a
    circle is a move and an arc) }
  Result := TyShapePolygon(pts);
  if closed then ;
  Result.Cmds := cmds;
end;

function TyBuildMarkLines(const APics: TTyMkLinePicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList): Integer;
var
  i: Integer;
  el: TTyChartElement;
  c: TTyChartColor;
  pts: TTyPointFArray;

  function Colour(const S: string; out AC: TTyChartColor): Boolean;
  begin
    Result := (S <> '') and TyTryParseChartColor(S, AC);
  end;

  function Faded(AC: TTyChartColor; AOpacity: Double): TTyChartColor;
  begin
    if IsNan(AOpacity) or (AOpacity >= 1) then Exit(AC);
    if AOpacity <= 0 then Exit(AC and $00FFFFFF);
    Result := (AC and $00FFFFFF) or (Cardinal(Round((AC shr 24) * AOpacity)) shl 24);
  end;

  function Blank(AZ2: Double): TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Z := Trunc(ABlock.Z);
    Result.Z2 := Round(AZ2);
    Result.Silent := True;
    Result.Datum := TyChartDatum(-1, -1);
    Result.Style.Alpha := 1;
  end;

  procedure Symbol(const S: TTyMkSymbolPic);
  begin
    if not S.Present then Exit;
    el := Blank(S.Z2);
    el.Shape := TyMkZrShape(S.Path, S.Transform, S.HasTransform);
    if Colour(S.Fill, c) then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := c;
    end;
    if Colour(S.Stroke, c) then
    begin
      el.Style.StrokeColor := c;
      el.Style.StrokeWidthLogical := S.LineWidth;
    end;
    if not IsNan(S.Opacity) then el.Style.Alpha := Max(0.0, Min(1.0, S.Opacity));
    AList.Add(el);
    Inc(Result);
  end;

  procedure Lbl(const B: TTyMkLabelPic);
  var
    x, y, w, h: Double;
    ah: TTyTextAnchorH;
    av: TTyTextAnchorV;
    fs: Integer;
  begin
    if (not B.Present) or (not B.HasInk) or (B.Text = '') then Exit;
    if B.HasTransform then
    begin
      x := B.Transform[4];
      y := B.Transform[5];
    end
    else
    begin
      x := 0;
      y := 0;
    end;
    if B.Align = 'center' then ah := tahCentre
    else if B.Align = 'right' then ah := tahRight
    else ah := tahLeft;
    if B.VAlign = 'middle' then av := tavMiddle
    else if B.VAlign = 'bottom' then av := tavBottom
    else av := tavTop;
    { the author's size where they gave one; the skin's otherwise }
    fs := AInk.FontSizeLogical;
    if (B.FontSize <> nil) and (B.FontSize <> GTextDefaults.Find('fontSize'))
      and (B.FontSize.JSONType = jtNumber) and (B.FontSize.AsFloat > 0) then
      fs := Round(B.FontSize.AsFloat);
    w := 0;
    h := 0;
    if AMeasurer <> nil then
      AMeasurer.MeasureLine(B.Text, AInk.FontName, fs, AInk.FontWeight, w, h);
    el := Blank(B.Z2);
    el.Shape := TyShapeRect(TyAnchorBox(x, y, w, h, ah, av));
    el.Caption.Text := B.Text;
    el.Caption.FontName := AInk.FontName;
    el.Caption.FontSizeLogical := fs;
    el.Caption.FontWeight := AInk.FontWeight;
    if (B.FontWeight <> nil) and (B.FontWeight <> GTextDefaults.Find('fontWeight')) then
    begin
      if (B.FontWeight.JSONType = jtString) and ((B.FontWeight.AsString = 'bold')
        or (B.FontWeight.AsString = 'bolder')) then el.Caption.FontWeight := 700
      else if B.FontWeight.JSONType = jtNumber then
        el.Caption.FontWeight := Round(B.FontWeight.AsFloat);
    end;
    { the author's colours as written; upstream's default ink is the skin's }
    if (B.StyleFill <> '') and Colour(B.InkFill, c) then el.Caption.Colour := c
    else el.Caption.Colour := AInk.Text;
    el.Caption.Colour := Faded(el.Caption.Colour, B.InkOpacity);
    if B.InkStroke <> '' then
    begin
      if (B.StyleStroke <> '') and Colour(B.InkStroke, c) then el.Caption.StrokeColour := c
      else el.Caption.StrokeColour := AInk.Halo;
      el.Caption.StrokeColour := Faded(el.Caption.StrokeColour, B.InkOpacity);
      if not IsNan(B.InkLineWidth) then el.Caption.StrokeWidthLogical := B.InkLineWidth;
    end;
    el.Caption.X := x;
    el.Caption.Y := y;
    el.Caption.AnchorH := ah;
    el.Caption.AnchorV := av;
    el.Caption.RotationRad := B.InnerRotation;
    if not B.HasTransform then el.Caption.RotationRad := 0;
    AList.Add(el);
    Inc(Result);
  end;

begin
  Result := 0;
  if AList = nil then Exit;
  for i := 0 to High(APics) do
  begin
    if not APics[i].Drawn then Continue;
    { the segment: zrender draws no stroke of no width }
    if (APics[i].LineWidth > 0) and (Length(APics[i].Path) = 2) then
    begin
      el := Blank(APics[i].Z2);
      SetLength(pts, 2);
      pts[0] := TyPointF(APics[i].Path[0].V[0], APics[i].Path[0].V[1]);
      pts[1] := TyPointF(APics[i].Path[1].V[0], APics[i].Path[1].V[1]);
      el.Shape := TyShapePolyline(pts);
      if not Colour(APics[i].Stroke, c) then c := $FF000000;
      el.Style.StrokeColor := c;
      el.Style.StrokeWidthLogical := APics[i].LineWidth;
      el.Style.DashLogical := Copy(APics[i].Dash);
      el.Style.Alpha := Max(0.0, Min(1.0, APics[i].Opacity));
      AList.Add(el);
      Inc(Result);
    end;
    Symbol(APics[i].FromSym);
    Symbol(APics[i].ToSym);
    Lbl(APics[i].Lbl);
  end;
end;

{ ============================ markPoint ============================ }

function TyMkLum(const AColour: string; ABackground: Double): Double;
var r, g, b, a: Double;
begin
  if not TyTryParseCssRgba(AColour, r, g, b, a) then Exit(0);
  Result := (0.299 * r + 0.587 * g + 0.114 * b) * a / 255 + (1 - a) * ABackground;
end;

{ Transformable.getLocalTransform with a scale; False when it needs none }
function LocalTransformS(AX, AY, ARotation, ASX, ASY: Double; out M: TTyMat2D): Boolean;
var aa, ac, atx, ab, ad, aty, st, ct: Double;
begin
  Result := NotAroundZero(ARotation) or NotAroundZero(AX) or NotAroundZero(AY)
    or NotAroundZero(ASX - 1) or NotAroundZero(ASY - 1);
  if not Result then Exit;
  M[4] := 0;
  M[5] := 0;
  M[0] := ASX;
  M[3] := ASY;
  M[1] := 0 * ASX;
  M[2] := 0 * ASY;
  if ARotation <> 0 then
  begin
    aa := M[0]; ac := M[2]; atx := M[4];
    ab := M[1]; ad := M[3]; aty := M[5];
    st := TyJsSin(ARotation);
    ct := TyJsCos(ARotation);
    M[0] := aa * ct + ab * st;
    M[1] := -aa * st + ab * ct;
    M[2] := ac * ct + ad * st;
    M[3] := -ac * st + ct * ad;
    M[4] := ct * (atx - 0) + st * (aty - 0) + 0;
    M[5] := ct * (aty - 0) - st * (atx - 0) + 0;
  end;
  M[4] := M[4] + (0 + AX);
  M[5] := M[5] + (0 + AY);
end;

function MatMul(const A, B: TTyMat2D): TTyMat2D;
begin
  Result[0] := A[0] * B[0] + A[2] * B[1];
  Result[1] := A[1] * B[0] + A[3] * B[1];
  Result[2] := A[0] * B[2] + A[2] * B[3];
  Result[3] := A[1] * B[2] + A[3] * B[3];
  Result[4] := A[0] * B[4] + A[2] * B[5] + A[4];
  Result[5] := A[1] * B[4] + A[3] * B[5] + A[5];
end;

{ BoundingRect.applyTransform }
function RectThrough(const S: TTyXYWH; AHas: Boolean; const M: TTyMat2D): TTyXYWH;
var
  px, py: array[0..3] of Double;
  i: Integer;
  mnx, mny, mxx, mxy: Double;
begin
  if not AHas then Exit(S);
  if (M[1] < 1e-5) and (M[1] > -1e-5) and (M[2] < 1e-5) and (M[2] > -1e-5) then
  begin
    Result.X := S.X * M[0] + M[4];
    Result.Y := S.Y * M[3] + M[5];
    Result.W := S.W * M[0];
    Result.H := S.H * M[3];
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
  { the four corners: lt, rt, rb, lb; min / max in upstream's order lt, rb,
    lb, rt }
  px[0] := M[0] * S.X + M[2] * S.Y + M[4];
  py[0] := M[1] * S.X + M[3] * S.Y + M[5];
  px[1] := M[0] * (S.X + S.W) + M[2] * S.Y + M[4];
  py[1] := M[1] * (S.X + S.W) + M[3] * S.Y + M[5];
  px[2] := M[0] * (S.X + S.W) + M[2] * (S.Y + S.H) + M[4];
  py[2] := M[1] * (S.X + S.W) + M[3] * (S.Y + S.H) + M[5];
  px[3] := M[0] * S.X + M[2] * (S.Y + S.H) + M[4];
  py[3] := M[1] * S.X + M[3] * (S.Y + S.H) + M[5];
  mnx := px[0]; mny := py[0]; mxx := px[0]; mxy := py[0];
  for i in [2, 3, 1] do
  begin
    if px[i] < mnx then mnx := px[i];
    if py[i] < mny then mny := py[i];
    if px[i] > mxx then mxx := px[i];
    if py[i] > mxy then mxy := py[i];
  end;
  Result.X := mnx;
  Result.Y := mny;
  Result.W := mxx - mnx;
  Result.H := mxy - mny;
end;

{ zrender contain/text.ts parsePercent: a string's percent of AMax, else
  the number }
function ZrPercent(A: TJSONData; AMax: Double): Double;
var s: string;
begin
  if (A <> nil) and (A.JSONType = jtString) then
  begin
    s := A.AsString;
    if Pos('%', s) > 0 then Exit(TyJsParseFloat(s) / 100 * AMax);
    Exit(TyJsParseFloat(s));
  end;
  Result := NumOf(A);
  if A = nil then Result := NaN;
  if (A <> nil) and (A.JSONType = jtNull) then Result := 0;
end;

function TyMkPointPictures(const ABlock: TTyMkBlock; const AIn: TTyMkPicInput;
  AXIsLabel, AYIsLabel: Boolean): TTyMkPointPicArray;
var
  own, master, gts: TMkView;
  MP: TMkLevels;
  i, n: Integer;
  maxZ2, s: Double;
  E: TTyMkEnd;

  procedure Picture(var P: TTyMkPointPic);
  var
    lv, IS_, LB: TMkLevels;
    d, sz, off, o0, o1, fmt, v, posd, offA: TJSONData;
    fill, typ, str, posS, rawA, rawV, fc, sc, sv: string;
    w, h, ox, oy, rot, lw, ls, gw, dist, lrot, rx, ry, op: Double;
    hasStroke, hasFill, hasFc, hasSc, useDefault, bgDrawn, lblDim, rich: Boolean;
    rectLocal, rect: TTyXYWH;
    lp: TTyMkPtLabelPic;
    calcX, calcY: Double;
    calcA, calcV: string;
    dimIdx, k: Integer;
    dl: TTyDoubleArray;
  begin
    lv := nil;
    SetLength(lv, 3);
    lv[0] := View1(E.Src);
    lv[1] := own;
    lv[2] := master;
    { itemStyle through the chain; the fill falls back to the series' }
    IS_ := Sub(lv, 'itemStyle');
    d := Chain(IS_, 'color');
    if (d <> nil) and Truthy(d) then fill := StrOf(d) else fill := AIn.SeriesColor;
    P.Fill := fill;
    d := Chain(lv, 'z2');
    if d <> nil then P.Z2 := NumOf(d) else P.Z2 := 0;
    d := Chain(lv, 'symbol');
    P.Drawn := not (IsNan(E.Point.X) or IsNan(E.Point.Y));
    if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'none') then P.Drawn := False;
    if not P.Drawn then Exit;
    { a falsy name other than 'none' is a circle }
    if Truthy(d) then typ := JsStringOf(d) else typ := 'circle';
    if d = nil then P.Symbol := '' else P.Symbol := JsStringOf(d);
    P.Empty := Copy(typ, 1, 5) = 'empty';
    if P.Empty then P.ShapeType := LowerCase(Copy(typ, 6, 1)) + Copy(typ, 7, MaxInt)
    else P.ShapeType := typ;
    { normalizeSymbolSize }
    sz := Chain(lv, 'symbolSize');
    if (sz <> nil) and (sz.JSONType = jtArray) then
    begin
      if sz.Count > 0 then w := NumOf(sz.Items[0]) else w := NaN;
      if sz.Count > 1 then h := NumOf(sz.Items[1]) else h := NaN;
    end
    else
    begin
      if sz = nil then w := NaN else w := NumOf(sz);
      h := w;
    end;
    if IsNan(w) then w := 0;
    if IsNan(h) then h := 0;
    w := w * s;
    h := h * s;
    { the unit box, scaled by size / 2; the turn (r || 0) * PI / 180 || 0 }
    P.ScaleX := w / 2;
    P.ScaleY := h / 2;
    d := Chain(lv, 'symbolRotate');
    if Truthy(d) then rot := NumOf(d) * Pi / 180 else rot := 0;
    if IsNan(rot) then rot := 0;
    P.Rotation := rot;
    { normalizeSymbolOffset: percent of the size, y falling back to x }
    P.X := 0;
    P.Y := 0;
    off := Chain(lv, 'symbolOffset');
    if off <> nil then
    begin
      if off.JSONType = jtArray then
      begin
        o0 := nil;
        o1 := nil;
        if off.Count > 0 then o0 := off.Items[0];
        if off.Count > 1 then o1 := off.Items[1];
        if JNull(o1) then o1 := o0;
      end
      else
      begin
        o0 := off;
        o1 := off;
      end;
      ox := TyMkParsePercent(o0, w / s) * s;
      oy := TyMkParsePercent(o1, h / s) * s;
      if IsNan(ox) then ox := 0;
      if IsNan(oy) then oy := 0;
      P.X := ox;
      P.Y := oy;
    end;
    { useStyle over zrender's defaults -- the fill already the series' when
      the item named none -- then setColor }
    P.StyleFill := fill;
    P.StyleStroke := '';
    P.StyleLineWidth := 1;
    P.StyleOpacity := 1;
    P.StyleDashOffset := 0;
    P.StyleDash := nil;
    d := Chain(IS_, 'borderColor');
    if d <> nil then P.StyleStroke := StrOf(d);
    d := Chain(IS_, 'borderWidth');
    if d <> nil then P.StyleLineWidth := NumOf(d);
    d := Chain(IS_, 'opacity');
    if d <> nil then P.StyleOpacity := NumOf(d);
    P.StyleDash := Chain(IS_, 'borderType');
    d := Chain(IS_, 'borderDashOffset');
    if d <> nil then P.StyleDashOffset := NumOf(d);
    if P.Empty then
    begin
      P.StyleStroke := fill;
      P.StyleFill := '#fff';
      P.StyleLineWidth := 2;
    end
    else if P.ShapeType = 'line' then
      P.StyleStroke := fill
    else
      P.StyleFill := fill;
    { the group at the point, the path inside it }
    P.GroupX := E.Point.X;
    P.GroupY := E.Point.Y;
    P.HasGroupTransform := LocalTransformS(P.GroupX, P.GroupY, 0, 1, 1, P.GroupTransform);
    P.HasLocal := LocalTransformS(P.X, P.Y, P.Rotation, P.ScaleX, P.ScaleY, P.Local);
    P.HasGlobal := P.HasLocal or P.HasGroupTransform;
    if P.HasGroupTransform and P.HasLocal then P.Global := MatMul(P.GroupTransform, P.Local)
    else if P.HasLocal then P.Global := P.Local
    else if P.HasGroupTransform then P.Global := P.GroupTransform;
    P.Path := TyZrSymbol(P.ShapeType, -1, -1, 2, 2);
    P.BBox := TyZrBBox(P.Path);
    if P.HasGlobal and (Abs(P.Global[0] - 1) > 1e-10) and (Abs(P.Global[3] - 1) > 1e-10) then
      P.LineScale := Sqrt(Abs(P.Global[0] * P.Global[3] - P.Global[2] * P.Global[1]))
    else
      P.LineScale := 1;
    hasStroke := (P.StyleStroke <> '') and (P.StyleStroke <> 'none')
      and (P.StyleLineWidth > 0);
    hasFill := (P.StyleFill <> '') and (P.StyleFill <> 'none');
    rectLocal := TyZrStrokeRect(P.BBox, Length(P.Path), hasStroke, hasFill,
      P.StyleLineWidth, P.LineScale);
    { the painted stroke, in the path's own units }
    P.PaintStroke := (P.StyleStroke <> '') and (P.StyleStroke <> 'none');
    P.PaintWidth := NaN;
    P.HasPaintDash := False;
    P.PaintDash := nil;
    if P.PaintStroke then
    begin
      lw := P.StyleLineWidth;
      if IsNan(lw) then lw := 0;
      if P.LineScale <> 0 then P.PaintWidth := lw / P.LineScale else P.PaintWidth := 0;
      if Truthy(P.StyleDash) and (P.StyleLineWidth > 0) then
      begin
        dl := ResolveDash(P.StyleDash, P.StyleLineWidth);
        if Length(dl) > 0 then
        begin
          if (P.LineScale <> 0) and (P.LineScale <> 1) then
            for k := 0 to High(dl) do dl[k] := dl[k] / P.LineScale;
          P.HasPaintDash := True;
          P.PaintDash := dl;
        end;
      end;
    end;
    { Math.max(z2 || 0, maxZ2) }
    if IsNan(P.Z2) then op := 0 else op := P.Z2;
    if op > maxZ2 then maxZ2 := op;

    { ---- the label ---- }
    lp := Default(TTyMkPtLabelPic);
    LB := Sub(lv, 'label');
    if not Truthy(Chain(LB, 'show')) then
    begin
      P.Lbl := lp;
      Exit;
    end;
    lp.Present := True;
    fmt := Chain(LB, 'formatter');
    { the value as {c} prints it: an array joins }
    v := nil;
    if E.Src <> nil then v := E.Src.Find('value');
    if (v <> nil) and (v.JSONType = jtArray) and (E.Value.Kind = mvkOther) then
    begin
      sv := '';
      for k := 0 to v.Count - 1 do
      begin
        if k > 0 then sv := sv + ',';
        if not JNull(v.Items[k]) then sv := sv + JsStringOf(v.Items[k]);
      end;
    end
    else
      sv := ValString(E.Value);
    if (fmt <> nil) and (fmt.JSONType = jtString) then
    begin
      case E.Name.Kind of
        mvkStr: str := E.Name.Str;
        mvkNum: str := TyJsNumberToString(E.Name.Num);
      else
        str := '';
      end;
      if AIn.SeriesName.Kind = mvkUndef then
        str := FormatTpl(fmt.AsString, ['undefined', str, sv])
      else
        str := FormatTpl(fmt.AsString, [ValString(AIn.SeriesName), str, sv]);
      lp.HasText := True;
    end
    else
    begin
      { getDefaultLabel: the value at the last dim that may label }
      lblDim := AXIsLabel or AYIsLabel;
      if AYIsLabel then dimIdx := 1 else dimIdx := 0;
      str := '';
      if lblDim then
      begin
        if (v <> nil) and (v.JSONType = jtArray) and (E.Value.Kind = mvkOther) then
        begin
          if (dimIdx < v.Count) and not JNull(v.Items[dimIdx]) then
          begin
            str := JsStringOf(v.Items[dimIdx]);
            lp.HasText := True;
          end;
        end
        else if not (E.Value.Kind in [mvkUndef, mvkNull]) then
        begin
          str := ValString(E.Value);
          lp.HasText := True;
        end;
      end;
    end;
    lp.Text := str;
    { the text style, attached }
    fc := '';
    sc := '';
    d := Chain(LB, 'color');
    hasFc := d <> nil;
    if hasFc then
    begin
      fc := StrOf(d);
      if (fc = 'inherit') or (fc = 'auto') then fc := fill;
      hasFc := fc <> '';
    end;
    d := Chain(LB, 'textBorderColor');
    hasSc := d <> nil;
    if hasSc then
    begin
      sc := StrOf(d);
      if (sc = 'inherit') or (sc = 'auto') then sc := fill;
      hasSc := sc <> '';
    end;
    if hasFc then lp.StyleFill := fc;
    if hasSc then lp.StyleStroke := sc;
    d := Chain(LB, 'textBorderWidth');
    if d = nil then d := VGet(gts, 'textBorderWidth');
    if JNull(d) then lp.StyleLineWidth := NaN else lp.StyleLineWidth := NumOf(d);
    d := Chain(LB, 'opacity');
    if d = nil then d := VGet(gts, 'opacity');
    if not JNull(d) then lp.StyleOpacity := NumOf(d)
    else
    begin
      { defaultOpacity: the symbol style's }
      d := Chain(IS_, 'opacity');
      if d <> nil then lp.StyleOpacity := NumOf(d) else lp.StyleOpacity := NaN;
    end;
    lp.FontStyle := Chain(LB, 'fontStyle');
    if lp.FontStyle = nil then lp.FontStyle := VGet(gts, 'fontStyle');
    lp.FontWeight := Chain(LB, 'fontWeight');
    if lp.FontWeight = nil then lp.FontWeight := VGet(gts, 'fontWeight');
    lp.FontSize := Chain(LB, 'fontSize');
    if lp.FontSize = nil then lp.FontSize := VGet(gts, 'fontSize');
    lp.FontFamily := Chain(LB, 'fontFamily');
    if lp.FontFamily = nil then lp.FontFamily := VGet(gts, 'fontFamily');
    if JNull(lp.FontStyle) then lp.FontStyle := nil;
    if JNull(lp.FontWeight) then lp.FontWeight := nil;
    if JNull(lp.FontSize) then lp.FontSize := nil;
    if JNull(lp.FontFamily) then lp.FontFamily := nil;
    lp.Font := MakeFont(lp.FontStyle, lp.FontWeight, lp.FontSize, lp.FontFamily);
    lp.StyleBackground := Chain(LB, 'backgroundColor');
    rich := False;
    for k := 0 to High(LB) do
      if Truthy(VGet(LB[k], 'rich')) then rich := True;
    lp.Rich := rich;
    rawA := '';
    d := Chain(LB, 'align');
    if d <> nil then rawA := NormAlign(JsStringOf(d));
    d := Chain(LB, 'verticalAlign');
    if d = nil then d := Chain(LB, 'baseline');
    rawV := '';
    if d <> nil then rawV := NormVAlign(JsStringOf(d));
    lp.AuthorAlign := rawA;
    lp.AuthorVAlign := rawV;
    { createTextConfig: 'outside' is 'top' }
    posd := Chain(LB, 'position');
    lp.Position := posd;
    if Truthy(posd) then posS := JsStringOf(posd) else posS := 'inside';
    if (posd <> nil) and (posd.JSONType = jtArray) then posS := #1;
    if posS = 'outside' then
    begin
      posS := 'top';
      lp.Position := GTopWord;
    end;
    d := Chain(LB, 'distance');
    if d <> nil then dist := NumOf(d) else dist := 5;
    lp.Distance := dist;
    dist := dist * s;
    { the rect: the symbol path's own, grown by its stroke, through its global
      transform }
    rect := RectThrough(rectLocal, P.HasGlobal, P.Global);
    lp.Rect := rect;
    { calculateTextPosition }
    calcX := rect.X;
    calcY := rect.Y;
    calcA := 'left';
    calcV := 'top';
    if posS = #1 then
    begin
      calcX := calcX + ZrPercent(posd.Items[0], rect.W);
      calcY := calcY + ZrPercent(posd.Items[1], rect.H);
      calcA := '';
      calcV := '';
    end
    else if posS = 'left' then
    begin
      calcX := calcX - dist; calcY := calcY + rect.H / 2; calcA := 'right'; calcV := 'middle';
    end
    else if posS = 'right' then
    begin
      calcX := calcX + dist + rect.W; calcY := calcY + rect.H / 2; calcV := 'middle';
    end
    else if posS = 'top' then
    begin
      calcX := calcX + rect.W / 2; calcY := calcY - dist; calcA := 'center'; calcV := 'bottom';
    end
    else if posS = 'bottom' then
    begin
      calcX := calcX + rect.W / 2; calcY := calcY + rect.H + dist; calcA := 'center';
    end
    else if posS = 'inside' then
    begin
      calcX := calcX + rect.W / 2; calcY := calcY + rect.H / 2; calcA := 'center'; calcV := 'middle';
    end
    else if posS = 'insideLeft' then
    begin
      calcX := calcX + dist; calcY := calcY + rect.H / 2; calcV := 'middle';
    end
    else if posS = 'insideRight' then
    begin
      calcX := calcX + rect.W - dist; calcY := calcY + rect.H / 2; calcA := 'right'; calcV := 'middle';
    end
    else if posS = 'insideTop' then
    begin
      calcX := calcX + rect.W / 2; calcY := calcY + dist; calcA := 'center';
    end
    else if posS = 'insideBottom' then
    begin
      calcX := calcX + rect.W / 2; calcY := calcY + rect.H - dist; calcA := 'center'; calcV := 'bottom';
    end
    else if posS = 'insideTopLeft' then
    begin
      calcX := calcX + dist; calcY := calcY + dist;
    end
    else if posS = 'insideTopRight' then
    begin
      calcX := calcX + rect.W - dist; calcY := calcY + dist; calcA := 'right';
    end
    else if posS = 'insideBottomLeft' then
    begin
      calcX := calcX + dist; calcY := calcY + rect.H - dist; calcV := 'bottom';
    end
    else if posS = 'insideBottomRight' then
    begin
      calcX := calcX + rect.W - dist; calcY := calcY + rect.H - dist; calcA := 'right';
      calcV := 'bottom';
    end;
    { the pin's label sits at 0.4 of its rect }
    if (P.ShapeType = 'pin') and (posS = 'inside') then calcY := rect.Y + rect.H * 0.4;
    lp.DefAlign := calcA;
    lp.DefVAlign := calcV;
    if rawA <> '' then lp.Align := rawA else if calcA <> '' then lp.Align := calcA
    else lp.Align := 'left';
    if rawV <> '' then lp.VAlign := rawV else if calcV <> '' then lp.VAlign := calcV
    else lp.VAlign := 'top';
    lp.InnerX := calcX;
    lp.InnerY := calcY;
    lp.InnerRotation := 0;
    lp.InnerOriginX := 0;
    lp.InnerOriginY := 0;
    d := Chain(LB, 'rotate');
    if d <> nil then
    begin
      lrot := NumOf(d) * Pi / 180;
      lp.InnerRotation := lrot;
    end;
    offA := Chain(LB, 'offset');
    if Truthy(offA) and (offA.JSONType = jtArray) and (offA.Count >= 2) then
    begin
      rx := NumOf(offA.Items[0]) * s;
      ry := NumOf(offA.Items[1]) * s;
      lp.InnerX := lp.InnerX + rx;
      lp.InnerY := lp.InnerY + ry;
      lp.InnerOriginX := -rx;
      lp.InnerOriginY := -ry;
    end;
    lp.HasTransform := LocalTransform(lp.InnerX, lp.InnerY, lp.InnerRotation,
      lp.InnerOriginX, lp.InnerOriginY, lp.Transform);
    { the ink: inside against the symbol's fill, else outside }
    lp.Inside := (posS <> #1) and (Pos('inside', posS) > 0) and hasFill;
    if lp.Inside then
    begin
      if P.StyleFill = 'none' then lp.DefFill := '#333'
      else
      begin
        ls := TyMkLum(P.StyleFill, 0);
        if ls > 0.5 then lp.DefFill := '#333'
        else if ls > 0.2 then lp.DefFill := '#eee'
        else lp.DefFill := '#ccc';
      end;
      lp.DefStroke := '';
      if AIn.IsDark = (TyMkLum(lp.DefFill, 0) < 0.4) then lp.DefStroke := P.StyleFill;
    end
    else
    begin
      d := Chain(LB, 'color');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'inherit') then
        lp.DefFill := fill
      else if AIn.IsDark then lp.DefFill := '#ccc'
      else lp.DefFill := '#333';
      if lp.DefFill = '' then lp.DefFill := '#000';
      lp.DefStroke := TyMkOutsideStroke(AIn.Background, AIn.IsDark);
    end;
    if rich then lp.Lines := -1
    else if lp.Text = '' then lp.Lines := 0
    else
    begin
      lp.Lines := 1;
      for k := 1 to Length(lp.Text) do
        if lp.Text[k] = #10 then Inc(lp.Lines);
    end;
    lp.HasInk := (not rich) and (lp.Text <> '');
    if lp.HasInk then
    begin
      useDefault := not hasFc;
      if useDefault then lp.InkFill := lp.DefFill else lp.InkFill := fc;
      if lp.InkFill = 'none' then lp.InkFill := '';
      bgDrawn := Truthy(lp.StyleBackground);
      gw := 0;
      lp.InkStroke := '';
      if hasSc then lp.InkStroke := sc
      else if (not bgDrawn) and useDefault then
      begin
        gw := 2;
        lp.InkStroke := lp.DefStroke;
      end;
      if (lp.InkStroke = 'transparent') or (lp.InkStroke = 'none') then lp.InkStroke := '';
      lp.InkLineWidth := NaN;
      if lp.InkStroke <> '' then
      begin
        if (not IsNan(lp.StyleLineWidth)) and (lp.StyleLineWidth <> 0) then
          lp.InkLineWidth := lp.StyleLineWidth
        else
          lp.InkLineWidth := gw;
      end;
      if IsNan(lp.StyleOpacity) then op := 1 else op := lp.StyleOpacity;
      lp.InkOpacity := op;
    end;
    if IsInfinite(maxZ2) then lp.Z2 := 0 else lp.Z2 := maxZ2 + 2;
    lp.Silent := Truthy(Chain(LB, 'silent'));
    P.Lbl := lp;
  end;

begin
  Result := nil;
  if (not ABlock.Present) or (ABlock.Kind <> mkPoint) then Exit;
  s := AIn.Scale;
  if (s <= 0) or IsNan(s) then s := 1;
  own := View1(ABlock.Own);
  master := View2(ABlock.Top, TyMkDefaults(mkPoint));
  SetLength(MP, 2);
  MP[0] := own;
  MP[1] := master;
  gts := View2(AIn.TextStyle, GTextDefaults);
  maxZ2 := NegInfinity;
  n := 0;
  SetLength(Result, ABlock.Count);
  for i := 0 to High(ABlock.Points) do
  begin
    if not ABlock.Points[i].Survived then Continue;
    E := ABlock.Points[i].E;
    Result[n] := Default(TTyMkPointPic);
    Result[n].Item := i;
    Picture(Result[n]);
    Inc(n);
    if n >= Length(Result) then Break;
  end;
  SetLength(Result, n);
end;

function TyBuildMarkPoints(const APics: TTyMkPointPicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList): Integer;
var
  i, fs: Integer;
  el: TTyChartElement;
  c: TTyChartColor;
  B: TTyMkPtLabelPic;
  x, y, w, h: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;

  function Colour(const S: string; out AC: TTyChartColor): Boolean;
  begin
    Result := (S <> '') and TyTryParseChartColor(S, AC);
  end;

  function Faded(AC: TTyChartColor; AOpacity: Double): TTyChartColor;
  begin
    if IsNan(AOpacity) or (AOpacity >= 1) then Exit(AC);
    if AOpacity <= 0 then Exit(AC and $00FFFFFF);
    Result := (AC and $00FFFFFF) or (Cardinal(Round((AC shr 24) * AOpacity)) shl 24);
  end;

  function Blank(AZ2: Double): TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Z := Trunc(ABlock.Z);
    Result.Z2 := Round(AZ2);
    Result.Silent := True;
    Result.Datum := TyChartDatum(-1, -1);
    Result.Style.Alpha := 1;
  end;

begin
  Result := 0;
  if AList = nil then Exit;
  for i := 0 to High(APics) do
  begin
    if not APics[i].Drawn then Continue;
    el := Blank(APics[i].Z2);
    el.Shape := TyMkZrShape(APics[i].Path, APics[i].Global, APics[i].HasGlobal);
    if (APics[i].StyleFill <> 'none') and Colour(APics[i].StyleFill, c) then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := c;
    end;
    if APics[i].PaintStroke and Colour(APics[i].StyleStroke, c)
      and (APics[i].StyleLineWidth > 0) and (APics[i].LineScale <> 0) then
    begin
      el.Style.StrokeColor := c;
      el.Style.StrokeWidthLogical := APics[i].StyleLineWidth;
      el.Style.DashLogical := ResolveDash(APics[i].StyleDash, APics[i].StyleLineWidth);
    end;
    if not IsNan(APics[i].StyleOpacity) then
      el.Style.Alpha := Max(0.0, Min(1.0, APics[i].StyleOpacity));
    if (APics[i].ScaleX <> 0) and (APics[i].ScaleY <> 0) then
    begin
      AList.Add(el);
      Inc(Result);
    end;
    { the label }
    B := APics[i].Lbl;
    if (not B.Present) or (not B.HasInk) or (B.Text = '') then Continue;
    if B.HasTransform then
    begin
      x := B.Transform[4];
      y := B.Transform[5];
    end
    else
    begin
      x := 0;
      y := 0;
    end;
    if B.Align = 'center' then ah := tahCentre
    else if B.Align = 'right' then ah := tahRight
    else ah := tahLeft;
    if B.VAlign = 'middle' then av := tavMiddle
    else if B.VAlign = 'bottom' then av := tavBottom
    else av := tavTop;
    fs := AInk.FontSizeLogical;
    if (B.FontSize <> nil) and (B.FontSize <> GTextDefaults.Find('fontSize'))
      and (B.FontSize.JSONType = jtNumber) and (B.FontSize.AsFloat > 0) then
      fs := Round(B.FontSize.AsFloat);
    w := 0;
    h := 0;
    if AMeasurer <> nil then
      AMeasurer.MeasureLine(B.Text, AInk.FontName, fs, AInk.FontWeight, w, h);
    el := Blank(B.Z2);
    el.Shape := TyShapeRect(TyAnchorBox(x, y, w, h, ah, av));
    el.Caption.Text := B.Text;
    el.Caption.FontName := AInk.FontName;
    el.Caption.FontSizeLogical := fs;
    el.Caption.FontWeight := AInk.FontWeight;
    if (B.FontWeight <> nil) and (B.FontWeight <> GTextDefaults.Find('fontWeight')) then
    begin
      if (B.FontWeight.JSONType = jtString) and ((B.FontWeight.AsString = 'bold')
        or (B.FontWeight.AsString = 'bolder')) then el.Caption.FontWeight := 700
      else if B.FontWeight.JSONType = jtNumber then
        el.Caption.FontWeight := Round(B.FontWeight.AsFloat);
    end;
    { the author's colour as written; upstream's default ink is the skin's --
      the three inside bands by the same luminance cut, the outside colour
      and the ground's halo otherwise }
    if (B.StyleFill <> '') and Colour(B.InkFill, c) then el.Caption.Colour := c
    else if B.Inside then
    begin
      if B.DefFill = '#333' then el.Caption.Colour := AInk.Inside[0]
      else if B.DefFill = '#eee' then el.Caption.Colour := AInk.Inside[1]
      else el.Caption.Colour := AInk.Inside[2];
    end
    else el.Caption.Colour := AInk.Text;
    el.Caption.Colour := Faded(el.Caption.Colour, B.InkOpacity);
    if B.InkStroke <> '' then
    begin
      if ((B.StyleStroke <> '') or B.Inside) and Colour(B.InkStroke, c) then
        el.Caption.StrokeColour := c
      else
        el.Caption.StrokeColour := AInk.Halo;
      el.Caption.StrokeColour := Faded(el.Caption.StrokeColour, B.InkOpacity);
      if not IsNan(B.InkLineWidth) then el.Caption.StrokeWidthLogical := B.InkLineWidth;
    end;
    el.Caption.X := x;
    el.Caption.Y := y;
    el.Caption.AnchorH := ah;
    el.Caption.AnchorV := av;
    if B.HasTransform then el.Caption.RotationRad := B.InnerRotation;
    AList.Add(el);
    Inc(Result);
  end;
end;

initialization
  {$IFDEF WINDOWS}
  GTextDefaults := TJSONObject(GetJSON('{"fontSize":12,"fontStyle":"normal",'
    + '"fontWeight":"normal","fontFamily":"Microsoft YaHei"}'));
  {$ELSE}
  GTextDefaults := TJSONObject(GetJSON('{"fontSize":12,"fontStyle":"normal",'
    + '"fontWeight":"normal","fontFamily":"sans-serif"}'));
  {$ENDIF}

  GTopWord := TJSONString.Create('top');

finalization
  GTopWord.Free;
  GTextDefaults.Free;
end.
