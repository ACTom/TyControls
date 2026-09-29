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
  end;

{ the paint-list elements of a series' markLines: segment, symbols, label.
  Silent all: markers carry no tooltip yet, and a hover on one must not
  report the series under it. }
function TyBuildMarkLines(const APics: TTyMkLinePicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList): Integer;

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

initialization
  {$IFDEF WINDOWS}
  GTextDefaults := TJSONObject(GetJSON('{"fontSize":12,"fontStyle":"normal",'
    + '"fontWeight":"normal","fontFamily":"Microsoft YaHei"}'));
  {$ELSE}
  GTextDefaults := TJSONObject(GetJSON('{"fontSize":12,"fontStyle":"normal",'
    + '"fontWeight":"normal","fontFamily":"sans-serif"}'));
  {$ENDIF}

finalization
  GTextDefaults.Free;
end.
