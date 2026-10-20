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
    { THE TEXT BLOCK, when the label's style needs one: its styles over the
      label levels, the inherit colour, and device px per css px [Batch 86] }
    Rt: TTyRtBlockStyle;
    RtHasInherit: Boolean;
    RtInherit: TTyChartColor;
    RtScale: Double;
    { Line.beforeUpdate's inputs, kept for its other percents [Batch 92]:
      the position as a code (0 end, 1 start, 2 insideStart*, 3
      insideMiddle* / middle, 4 insideEnd*, 5 none of them), the distances,
      dy, the tangent's x sign, and whether the author wrote the alignments }
    PosCode: Integer;
    DistX, DistY, Dy, Dir: Double;
    AuthorAlign, AuthorVAlign: Boolean;
    { [R2-I1] built for a state only (needsCreateText): ignored at rest }
    Hidden: Boolean;
    { [R2-I3] see TTyMkPtLabelPic.Hold }
    Hold: IInterface;
    { [R2-I5] see TTyMkPtLabelPic.KeepEmpty }
    KeepEmpty: Boolean;
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
    { [R2-I3] the label as the hover lays it out (Present False: as at
      rest) -- the emphasis label's text style over the normal one, and
      where the emphasis textConfig writes a position, calculateTextPosition
      over the Line group's own box instead of Line.beforeUpdate's place }
    EmphLbl: TTyMkLabelPic;
    { [R2-I5] the label as blur (1) and select (2) lay it out -- their own
      text style and words (Present False: as at rest) }
    StateLbl: array[1..2] of TTyMkLabelPic;
    { [R2-I5] the dash written as a word (TTyChartStyle.DashWord) }
    DashWord: Byte;
  end;
  TTyMkLinePicArray = array of TTyMkLinePic;

  { what the pictures need besides the block }
  TTyMkPicInput = record
    { the series' style colour, a css string: every colour falls back to it;
      SeriesColorData when the author's is not a string (a gradient) }
    SeriesColor: string;
    SeriesColorData: TJSONData;
    { {a}; undefined when the series has no name }
    SeriesName: TTyMkVal;
    { the host series, for what a named label handler is given }
    SeriesIndex: Integer;
    SeriesType: string;
    { ecModel.option.textStyle: the option's own, nil for none }
    TextStyle: TJSONObject;
    { the chart's ground: a css string, and whether it counts as dark }
    Background: string;
    IsDark: Boolean;
    { device px per css px }
    Scale: Double;
    { the root's side of a text block [Batch 86] }
    RtGlobal: TTyRtGlobal;
    { [R2-J3] the coordinate that names a marker's datum (the series'
      itemName dimension -- a category axis'): 0 x, 1 y, -1 none }
    NameDim: Integer;
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
    { the global font a rich style that does not inherit takes [Batch 86] }
    RtGlobal: TTyRtGlobal;
  end;

{ the paint-list elements of a series' markLines: segment, symbols, label.
  Silent all: markers carry no tooltip yet, and a hover on one must not
  report the series under it. }
function TyBuildMarkLines(const APics: TTyMkLinePicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList;
  AHostSeries: Integer = -1): Integer;

type
  { a markPoint's label (Symbol.ts's setLabelStyle on the symbol path) }
  TTyMkPtLabelPic = record
    Present: Boolean;
    { HasText False: getDefaultLabel answered nothing (no value, or no label
      dimension) }
    HasText: Boolean;
    Text: string;
    { rich text has no one-run ink (HasInk False, Lines -1): it is drawn as
      its block, Rt below [Batch 86: it was not drawn at all] }
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
    { THE TEXT BLOCK, when the label's style needs one: its styles over the
      label levels, the inherit colour, and device px per css px [Batch 86] }
    Rt: TTyRtBlockStyle;
    RtHasInherit: Boolean;
    RtInherit: TTyChartColor;
    RtScale: Double;
    { [R2-B] WHERE THE HOVER PUTS IT: the label laid out again on its
      symbol path scaled by the emphasis ratio (updateInnerText runs on the
      path as drawn), as a move from its rest place }
    HasEmphPlace: Boolean;
    EmphDX, EmphDY: Double;
    { [R2-I1] built for a state only (needsCreateText): ignored at rest }
    Hidden: Boolean;
    { [R2-I3] the JSON an emphasis overlay is made of, which the picture's
      references point into (nil for none) }
    Hold: IInterface;
    { [R2-I5] built though its text is empty: a state has words to show
      (setLabelStyle makes the Text whatever its normal text is) }
    KeepEmpty: Boolean;
  end;

  TTyMkPointPic = record
    Item: Integer;
    { [R2-I7] the mpData id SymbolDraw's diff pairs the symbols by }
    Id: string;
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
    { [R2-B] Symbol._updateCommon's emphasis ratio: the path's emphasis
      scale is ScaleX / ScaleY times it }
    EmphRatio: Double;
    { [R2-I1] the label as the hover lays it out: on the path at its
      emphasis scale, under the emphasis textConfig (Present False: none) }
    EmphLbl: TTyMkPtLabelPic;
    { [R2-I5] blur's (1) and select's (2), see TTyMkLinePic.StateLbl }
    StateLbl: array[1..2] of TTyMkPtLabelPic;
  end;
  TTyMkPointPicArray = array of TTyMkPointPic;

{ every surviving markPoint of the block, in data order. AXType / AYType:
  the coordinate dims' types, which say which dim the default text reads. }
function TyMkPointPictures(const ABlock: TTyMkBlock; const AIn: TTyMkPicInput;
  AXIsLabel, AYIsLabel: Boolean): TTyMkPointPicArray;
{ the paint-list elements of a series' markPoints }
function TyBuildMarkPoints(const APics: TTyMkPointPicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList;
  AHostSeries: Integer = -1): Integer;
{ zrender's lum(color, background): 0 for what does not parse }
function TyMkLum(const AColour: string; ABackground: Double): Double;

type
  TTyMkAreaPic = record
    Item: Integer;
    { the fill and stroke after the fallbacks: a css string, or the
      option's own object (a gradient) in FillData }
    Fill, Stroke: string;
    FillData, StrokeData: TJSONData;
    { False: no fill at all (a series colour that does not parse) }
    HasFill: Boolean;
    Z2: Double;
    { False when allClipped: no polygon, no label }
    Drawn: Boolean;
    Points: array[0..3] of TTyPointF;
    Path: TTyZrPath;
    BBox, Rect: TTyXYWH;
    { the box a local gradient normalises against on the device: Rect, with
      the stroke in device px [Batch 105] }
    GradBox: TTyXYWH;
    LineWidth, Opacity, DashOffset: Double;
    Dash: TJSONData;
    LineCap, LineJoin: string;
    Lbl: TTyMkPtLabelPic;
    { [R2-I1] the label under the emphasis textConfig (Present False: the
      state says no place of its own) }
    EmphLbl: TTyMkPtLabelPic;
    { [R2-I5] blur's (1) and select's (2), see TTyMkLinePic.StateLbl }
    StateLbl: array[1..2] of TTyMkPtLabelPic;
  end;
  TTyMkAreaPicArray = array of TTyMkAreaPic;

{ every surviving markArea of the block, in data order }
function TyMkAreaPictures(const ABlock: TTyMkBlock;
  const AIn: TTyMkPicInput): TTyMkAreaPicArray;
{ the paint-list elements of a series' markAreas }
function TyBuildMarkAreas(const APics: TTyMkAreaPicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList;
  AHostSeries: Integer = -1): Integer;
{ tool/color modifyAlpha: the colour at alpha A as 'rgba(r,g,b,a)'; '' for
  what does not parse }
function TyMkModifyAlpha(const AColour: string; A: Double): string;

{ zrender's PathProxy commands through a matrix, arcs as cubics, into a
  polygon shape carrying them }
function TyMkZrShape(const APath: TTyZrPath; const M: TTyMat2D;
  AHasMatrix: Boolean): TTyChartShape;

{ LINE.beforeUpdate AT ANOTHER PERCENT, for a straight line: where the end
  symbol stands (pointAt(percent)) and where the label is, with the
  alignment the position implies (-1: the author's, or none to change; 0
  left / top, 1 centre / middle, 2 right / bottom). AG is a markLine label
  element's TTyChartAnim.G: x1, y1, x2, y2, distance x, y, the position
  code, dy, the tangent's x sign. [Batch 92, AN4] }
procedure TyMkLineAt(const AG: array of Double; APercent: Double;
  out AToX, AToY, ALabelX, ALabelY: Double; out AAlignH, AAlignV: Integer);

implementation

uses Classes, tyControls.AdvChart.RichStyle, tyControls.AdvChart.JsMath, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Data, tyControls.AdvChart.Color, tyControls.AdvChart.Labels,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.Option;

type
  TMkView = array of TJSONObject;
  TMkLevels = array of TMkView;

var
  GTextDefaults: TJSONObject;
  { 'outside' as createTextConfig rewrites it }
  GTopWord, GInsideWord: TJSONString;

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

{ [R2-I1] A STATE'S label.show as setLabelStyle reads it -- getShallow down
  the item model's chain (the item, the marker option, the top-level one and
  the defaults) -- with fillLabel's copy of label.show into emphasis on the
  item and the marker option (levels 0 and 1). AHas False where none says. }
function StateLabelShow(const lv: TMkLevels; const AState: string; out AHas: Boolean): Boolean;
var
  j, i: Integer;
  st, lb, d: TJSONData;
begin
  Result := False;
  AHas := False;
  for j := 0 to High(lv) do
    for i := 0 to High(lv[j]) do
    begin
      if lv[j][i] = nil then Continue;
      d := nil;
      st := lv[j][i].Find(AState);
      if st is TJSONObject then
      begin
        lb := TJSONObject(st).Find('label');
        if lb is TJSONObject then d := TJSONObject(lb).Find('show');
      end;
      if JNull(d) and (AState = 'emphasis') and (j <= 1) then
      begin
        lb := lv[j][i].Find('label');
        if lb is TJSONObject then d := TJSONObject(lb).Find('show');
      end;
      if not JNull(d) then
      begin
        AHas := True;
        Exit(Truthy(d));
      end;
    end;
end;

{ [R2-I1] needsCreateText: some state's label.show is truthy }
function AnyStateLabelShows(const lv: TMkLevels): Boolean;
var has: Boolean;
begin
  Result := StateLabelShow(lv, 'emphasis', has) or StateLabelShow(lv, 'blur', has)
    or StateLabelShow(lv, 'select', has);
end;

{ [R2-I1] AObj as a level of its own over L }
function OverLevels(AObj: TJSONObject; const L: TMkLevels): TMkLevels;
var i: Integer;
begin
  SetLength(Result, Length(L) + 1);
  Result[0] := View1(AObj);
  for i := 0 to High(L) do Result[i + 1] := L[i];
end;

type
  { [R2-I3] the JSON an emphasis overlay is made of, alive as long as a
    picture that points into it }
  TMkHold = class(TInterfacedObject)
  public
    Objs: array of TJSONData;
    procedure Keep(A: TJSONData);
    destructor Destroy; override;
  end;

procedure TMkHold.Keep(A: TJSONData);
begin
  SetLength(Objs, Length(Objs) + 1);
  Objs[High(Objs)] := A;
end;

destructor TMkHold.Destroy;
var i: Integer;
begin
  for i := 0 to High(Objs) do Objs[i].Free;
  inherited Destroy;
end;

{ [R2-I3] THE EMPHASIS LABEL OVER THE NORMAL ONE, as setLabelStyle's
  emphasis state merges into the normal style and textConfig: every key the
  item's emphasis.label chain writes (getShallow down the chain; show and
  formatter aside, a falsy position aside, and the keys AExclude names) as
  one level over LB. A `rich` there holds only the token names the
  emphasis chain writes (getRichItemNames climbs its chain alone), each
  token's font keys falling back to the emphasis label's own; zrender's Text
  merges a state's rich INTO the normal one token by token (_mergeRich), so
  the levels below keep theirs and the overlay's tokens win key by key.
  [A first draft replaced the normal rich: the fixture says merge.] False
  where the emphasis says nothing;
  AHold owns what ALevels points into. [R2-I1's EmphTextConfig took
  position, distance, offset and rotate alone.] [R2-I5] Any special state's
  the same way (AState 'emphasis', 'blur' or 'select': setLabelStyle builds
  each one's style alike). }
function EmphLevels(const lv, LB: TMkLevels; const AState: string;
  const AExclude: array of string; out ALevels: TMkLevels;
  out AHold: IInterface): Boolean;
const
  { TEXT_PROPS_WITH_GLOBAL }
  cInherit: array[0..7] of string = ('fontStyle', 'fontWeight', 'fontSize', 'fontFamily',
    'textShadowColor', 'textShadowBlur', 'textShadowOffsetX', 'textShadowOffsetY');
var
  EL: TMkLevels;
  ov, rich, tok: TJSONObject;
  names: array of string;
  j, i, k, m, q, z: Integer;
  key: string;
  d, e: TJSONData;
  hold: TMkHold;
  skip: Boolean;
begin
  Result := False;
  ALevels := LB;
  AHold := nil;
  EL := Sub(Sub(lv, AState), 'label');
  names := nil;
  for j := 0 to High(EL) do
    for i := 0 to High(EL[j]) do
      if EL[j][i] <> nil then
        for k := 0 to EL[j][i].Count - 1 do
        begin
          skip := False;
          for z := 0 to High(names) do
            if names[z] = EL[j][i].Names[k] then skip := True;
          if not skip then
          begin
            SetLength(names, Length(names) + 1);
            names[High(names)] := EL[j][i].Names[k];
          end;
        end;
  ov := nil;
  rich := nil;
  begin
    for k := 0 to High(names) do
    begin
      key := names[k];
      if (key = 'show') or (key = 'formatter') then Continue;
      skip := False;
      for q := 0 to High(AExclude) do
        if key = AExclude[q] then skip := True;
      if skip then Continue;
      if key = 'rich' then
      begin
        { every token name down the chain, each token's keys first-wins }
        for j := 0 to High(EL) do
          for i := 0 to High(EL[j]) do
          begin
            if EL[j][i] = nil then Continue;
            d := EL[j][i].Find('rich');
            if not (d is TJSONObject) then Continue;
            if rich = nil then rich := TJSONObject.Create;
            for m := 0 to TJSONObject(d).Count - 1 do
            begin
              e := TJSONObject(d).Items[m];
              if not (e is TJSONObject) then Continue;
              if rich.IndexOfName(TJSONObject(d).Names[m]) < 0 then
                rich.Add(TJSONObject(d).Names[m], TJSONObject.Create);
              tok := TJSONObject(rich.Find(TJSONObject(d).Names[m]));
              for q := 0 to TJSONObject(e).Count - 1 do
                if (tok.IndexOfName(TJSONObject(e).Names[q]) < 0)
                  and not JNull(TJSONObject(e).Items[q]) then
                  tok.Add(TJSONObject(e).Names[q], TJSONObject(e).Items[q].Clone);
            end;
          end;
        Continue;
      end;
      d := Chain(EL, key);
      if d = nil then Continue;
      if (key = 'position') and not Truthy(d) then Continue;
      if ov = nil then ov := TJSONObject.Create;
      ov.Add(key, d.Clone);
    end;
    if rich <> nil then
    begin
      if ov = nil then ov := TJSONObject.Create;
      ov.Add('rich', rich);
    end;
  end;
  if ov = nil then Exit;
  { an emphasis token takes what it does not say of the font from the
    emphasis label itself (setTokenTextStyle: retrieve3(token, plain, the
    global -- none in a state)) }
  if rich <> nil then
    for m := 0 to rich.Count - 1 do
    begin
      tok := TJSONObject(rich.Items[m]);
      for q := 0 to High(cInherit) do
        if (tok.IndexOfName(cInherit[q]) < 0) and (ov.IndexOfName(cInherit[q]) >= 0) then
          tok.Add(cInherit[q], ov.Find(cInherit[q]).Clone);
    end;
  hold := TMkHold.Create;
  AHold := hold;
  hold.Keep(ov);
  ALevels := OverLevels(ov, LB);
  Result := True;
end;

{ THE LABEL'S TEXT BLOCK over its levels, the most specific object first,
  when any of them asks for one; AInherit (a css string) is upstream's
  inheritColor. [Batch 86] }
procedure MkRt(const LB: TMkLevels; const AIn: TTyMkPicInput;
  const AInherit: string; AScale: Double; out ART: TTyRtBlockStyle;
  out AHasInherit: Boolean; out AInherit_: TTyChartColor; out ARtScale: Double);
var
  chain: array of TJSONObject;
  i, k: Integer;
  any: Boolean;
begin
  ART := Default(TTyRtBlockStyle);
  AInherit_ := 0;
  AHasInherit := (AInherit <> '') and TyTryParseChartColor(AInherit, AInherit_);
  ARtScale := AScale;
  chain := nil;
  any := False;
  for i := 0 to High(LB) do
    for k := 0 to High(LB[i]) do
      if LB[i][k] <> nil then
      begin
        SetLength(chain, Length(chain) + 1);
        chain[High(chain)] := LB[i][k];
        if TyRtNodeWantsBlock(LB[i][k]) then any := True;
      end;
  if not any then Exit;
  ART := TyRtResolve(chain, AIn.RtGlobal, TyRtResolveOpt(True));
end;

{ THE BLOCK'S PIECES for a marker label: its styles in the font the skin
  and the author give it, the defaults the one-run caption would have been
  drawn in, hung at the label's anchor. [Batch 86] }
function MkRtPieces(const ART: TTyRtBlockStyle; const AText, AFontName: string;
  AFontSize, AWeight: Integer; const AGlobal: TTyRtGlobal; AHasInherit: Boolean;
  AInherit, ADefFill: TTyChartColor; AHasDefStroke: Boolean;
  ADefStroke: TTyChartColor; AH: TTyTextAnchorH; AV: TTyTextAnchorV;
  AScale: Double; const AMeasurer: ITyTextMeasurer): TTyRtPieceArray;
var b: TTyRtBlockStyle;
begin
  b := ART;
  TyRtFinish(b, AFontName, AFontSize, AWeight, AGlobal, AHasInherit, AInherit);
  Result := TyRtLay(AText, b, TyRtDefaultOf(True, ADefFill, AHasDefStroke,
    ADefStroke, True, AH, AV), AScale, AMeasurer);
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

{ [R2-I6] a marker label's own opacity as its element's alpha: none is 1,
  and the ink's old rule beyond [0, 1] (clamped) }
function LabelAlpha(AOpacity: Double): Double;
begin
  if IsNan(AOpacity) or (AOpacity >= 1) then Exit(1);
  if AOpacity <= 0 then Exit(0);
  Result := AOpacity;
end;

{ [R2-I5] THE WORD a dash is written as, for TTyChartStyle.DashWord: 1
  'dashed', 2 'dotted', 0 anything else (lengths, or none) -- the canvas
  normalises a word against the width it strokes at, brush by brush }
function DashWordOf(AType: TJSONData): Byte;
begin
  Result := 0;
  if (AType = nil) or (AType.JSONType <> jtString) then Exit;
  if AType.AsString = 'dashed' then Result := 1
  else if AType.AsString = 'dotted' then Result := 2;
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
{ what a named marker label handler is given: the marker's own params }
function MkHandlerText(const AHandler: string; const AIn: TTyMkPicInput;
  const AKind, AName, AValueText: string; ADataIndex: Integer;
  const AStatus: string): string;
var p: TTyChartCallbackParams;
begin
  p := TyChartBlankParams;
  p.ComponentType := AKind;
  p.SeriesIndex := AIn.SeriesIndex;
  p.SeriesType := AIn.SeriesType;
  if AIn.SeriesName.Kind = mvkStr then p.SeriesName := AIn.SeriesName.Str;
  p.Name := AName;
  p.DataIndex := ADataIndex;
  p.RawDataIndex := ADataIndex;
  p.ValueText := AValueText;
  { [R2-I4] the state it is asked for (params.status) [was: 'normal'] }
  p.Status := AStatus;
  Result := TyChartRunHandler(AHandler, TyChartOneParams(p));
end;

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

{ [R2-I4] THE EMPHASIS TEXT (labelStyle getLabelText): the state's words are
  getFormattedLabel(idx, 'emphasis', ..., the emphasis label model's
  formatter) -- down the item's chain, a string a template, a named handler
  asked with status 'emphasis'; where it answers nothing (no formatter, or
  one neither a string nor a function) the normal text stays (retrieve2).
  True where the emphasis has words of its own. [Was: the emphasis showed
  the normal text whatever its formatter said.] [R2-I5] getLabelText asks
  every special state so: AState 'emphasis', 'blur' or 'select', a handler
  asked with that status. [Was: blur and select showed the normal text.] }
function EmphText(const lv: TMkLevels; const AState: string; const AIn: TTyMkPicInput;
  const AKind, AName, AValueText: string; ADataIndex: Integer;
  out AText: string): Boolean;
var d: TJSONData;
begin
  Result := False;
  AText := '';
  d := Chain(Sub(Sub(lv, AState), 'label'), 'formatter');
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  if TyChartIsHandlerRef(d.AsString) then
    AText := MkHandlerText(d.AsString, AIn, AKind, AName, AValueText, ADataIndex,
      AState)
  else if AIn.SeriesName.Kind = mvkUndef then
    AText := FormatTpl(d.AsString, ['undefined', AName, AValueText])
  else
    AText := FormatTpl(d.AsString, [ValString(AIn.SeriesName), AName, AValueText]);
  Result := True;
end;

{ ---- the pictures ---- }

{ [R2-I3] the hover's markLine label under an emphasis position (below) }
procedure EmphLinePlace(const P: TTyMkLinePic; const AItemLv, ALB: TMkLevels;
  APos: TJSONData; AScale: Double; var ALab: TTyMkLabelPic;
  const AState: string = 'emphasis'); forward;

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
    { [R2-I3] the hover's }
    EL, LBE: TMkLevels;
    hold: IInterface;
    lab2: TTyMkLabelPic;
    emphPos: TJSONData;
    { [R2-I4] the hover's words }
    et: string;
    hasEt: Boolean;
    { [R2-I5] blur's and select's }
    sti: Integer;
    stName: string;

  { THE TEXT'S STYLE AND LINE.beforeUpdate's PLACE over the label levels
    ALB -- the rest label's, and [R2-I3] the hover's (the emphasis text
    style over them) }
  procedure LayText(const ALB: TMkLevels; var ALabel: TTyMkLabelPic);
  var LB: TMkLevels; label_: TTyMkLabelPic;
  begin
    LB := ALB;
    label_ := ALabel;
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
    { the inputs again, for the percents before 1 [Batch 92] }
    label_.DistX := distX;
    label_.DistY := distY;
    label_.Dir := dirv;
    label_.AuthorAlign := rawA <> '';
    label_.AuthorVAlign := rawV <> '';
    if pos = 'end' then label_.PosCode := 0
    else if pos = 'start' then label_.PosCode := 1
    else if (pos = 'insideStartTop') or (pos = 'insideStart')
      or (pos = 'insideStartBottom') then label_.PosCode := 2
    else if (pos = 'insideMiddleTop') or (pos = 'insideMiddle')
      or (pos = 'insideMiddleBottom') or (pos = 'middle') then label_.PosCode := 3
    else if (pos = 'insideEndTop') or (pos = 'insideEnd')
      or (pos = 'insideEndBottom') then label_.PosCode := 4
    else label_.PosCode := 5;
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
    label_.Dy := dy;
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
    { [R2-I5] the words this layout shows -- a state's own [was: the rest
      text's, so a state's words over an empty rest text had no ink] }
    label_.HasInk := label_.Text <> '';
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
    MkRt(LB, AIn, stroke, s, label_.Rt, label_.RtHasInherit, label_.RtInherit,
      label_.RtScale);
    ALabel := label_;
  end;

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
    { [R2-I5] a word, measured again against the width a state draws }
    P.DashWord := DashWordOf(lineType);
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
    { [R2-I1] built where a state shows it too (needsCreateText), ignored at
      rest [was: not built] }
    if not Truthy(Chain(LB, 'show')) and not AnyStateLabelShows(itemLv) then
    begin
      P.Lbl := label_;
      Exit;
    end;
    label_.Present := True;
    label_.Hidden := not Truthy(Chain(LB, 'show'));
    { the default text: the value rounded to ten places, else the name }
    rawVal := L.LineValue;
    case L.LineName.Kind of
      mvkStr: name := L.LineName.Str;
      mvkNum: name := TyJsNumberToString(L.LineName.Num);
    else
      name := '';
    end;
    d := Chain(LB, 'formatter');
    if (d <> nil) and (d.JSONType = jtString) and TyChartIsHandlerRef(d.AsString) then
      str := MkHandlerText(d.AsString, AIn, 'markLine', name, ValString(rawVal),
        L.DataIndex, 'normal')
    else if (d <> nil) and (d.JSONType = jtString) then
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
    LayText(LB, label_);
    { [R2-I3] AS THE HOVER LAYS IT OUT: the emphasis label's text style over
      the rest one (its place, align and distance are Line.beforeUpdate's,
      from the normal model), and where the emphasis textConfig writes a
      position, calculateTextPosition over the Line group's own box in
      place of beforeUpdate's -- updateInnerText runs after it }
    EL := Sub(Sub(itemLv, 'emphasis'), 'label');
    emphPos := Chain(EL, 'position');
    if not Truthy(emphPos) then emphPos := nil;
    hasEt := EmphText(itemLv, 'emphasis', AIn, 'markLine', name, ValString(rawVal),
      L.DataIndex, et);
    if EmphLevels(itemLv, LB, 'emphasis', ['position', 'distance', 'align', 'verticalAlign',
      'baseline'], LBE, hold) or (emphPos <> nil) or hasEt then
    begin
      lab2 := label_;
      { [R2-I4] its own words, where the emphasis formats them }
      if hasEt then lab2.Text := et;
      LayText(LBE, lab2);
      lab2.Hold := hold;
      lab2.Hidden := False;
      if emphPos <> nil then EmphLinePlace(P, itemLv, LB, emphPos, s, lab2);
      P.EmphLbl := lab2;
      if lab2.Text <> '' then label_.KeepEmpty := True;
    end;
    { [R2-I5] BLUR'S AND SELECT'S the same way: their own text style (the
      opacity aside -- the states' own), place and words }
    for sti := 1 to 2 do
    begin
      if sti = 1 then stName := 'blur' else stName := 'select';
      EL := Sub(Sub(itemLv, stName), 'label');
      emphPos := Chain(EL, 'position');
      if not Truthy(emphPos) then emphPos := nil;
      hasEt := EmphText(itemLv, stName, AIn, 'markLine', name, ValString(rawVal),
        L.DataIndex, et);
      if EmphLevels(itemLv, LB, stName, ['position', 'distance', 'align', 'verticalAlign',
        'baseline', 'opacity'], LBE, hold) or (emphPos <> nil) or hasEt then
      begin
        lab2 := label_;
        if hasEt then lab2.Text := et;
        LayText(LBE, lab2);
        lab2.Hold := hold;
        lab2.Hidden := False;
        if emphPos <> nil then EmphLinePlace(P, itemLv, LB, emphPos, s, lab2, stName);
        P.StateLbl[sti] := lab2;
        if lab2.Text <> '' then label_.KeepEmpty := True;
      end;
    end;
    { an empty rest text keeps nothing of its own to show }
    if label_.Text <> '' then label_.KeepEmpty := False;
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

procedure TyMkLineAt(const AG: array of Double; APercent: Double;
  out AToX, AToY, ALabelX, ALabelY: Double; out AAlignH, AAlignV: Integer);
var
  x1, y1, x2, y2, distX, distY, dy, dirv, fx, fy, dx, dy_, len, hp, cpx, cpy: Double;
  code: Integer;
  mask: TFPUExceptionMask;
begin
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    x1 := AG[0];
    y1 := AG[1];
    x2 := AG[2];
    y2 := AG[3];
    distX := AG[4];
    distY := AG[5];
    code := Round(AG[6]);
    dy := AG[7];
    dirv := AG[8];
    { LinePath.pointAt: [x1 * (1 - p) + x2 * p, ...] }
    fx := x1 * (1 - 0) + x2 * 0;
    fy := y1 * (1 - 0) + y2 * 0;
    AToX := x1 * (1 - APercent) + x2 * APercent;
    AToY := y1 * (1 - APercent) + y2 * APercent;
    { d = normalize(toPos - fromPos): nought for nought }
    dx := AToX - fx;
    dy_ := AToY - fy;
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
    hp := APercent / 2;
    cpx := x1 * (1 - hp) + x2 * hp;
    cpy := y1 * (1 - hp) + y2 * hp;
    AAlignH := -1;
    AAlignV := -1;
    ALabelX := 0;
    ALabelY := 0;
    case code of
      0:
        begin
          ALabelX := dx * distX + AToX;
          ALabelY := dy_ * distY + AToY;
          if dx > 0.8 then AAlignH := 0
          else if dx < -0.8 then AAlignH := 2
          else AAlignH := 1;
          if dy_ > 0.8 then AAlignV := 0
          else if dy_ < -0.8 then AAlignV := 2
          else AAlignV := 1;
        end;
      1:
        begin
          ALabelX := -dx * distX + fx;
          ALabelY := -dy_ * distY + fy;
          if dx > 0.8 then AAlignH := 2
          else if dx < -0.8 then AAlignH := 0
          else AAlignH := 1;
          if dy_ > 0.8 then AAlignV := 2
          else if dy_ < -0.8 then AAlignV := 0
          else AAlignV := 1;
        end;
      2:
        begin
          ALabelX := distX * dirv + fx;
          ALabelY := fy + dy;
        end;
      3:
        begin
          ALabelX := cpx;
          ALabelY := cpy + dy;
        end;
      4:
        begin
          ALabelX := -distX * dirv + AToX;
          ALabelY := AToY + dy;
        end;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ THE ELEMENTS ONE MARKER ADDED, from AFirst on, AS ITS HIT TARGET: its
  host series and its place in the marker's data, and silent only where the
  marker says so -- upstream's markers answer the pointer [Batch 84] }
procedure MkTarget(AList: TTyPaintList; AFirst: Integer; AKind: TTyChartTargetKind;
  AHostSeries, AIndex: Integer; ASilent: Boolean);
var
  k: Integer;
  el: TTyChartElement;
begin
  if AHostSeries < 0 then Exit;
  for k := AFirst to AList.Count - 1 do
  begin
    el := AList.Element(k);
    el.Datum := TyChartComponentDatum(AKind, AHostSeries, AIndex);
    el.Silent := ASilent;
    AList.SetElement(k, el);
  end;
end;

function TyBuildMarkLines(const APics: TTyMkLinePicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList;
  AHostSeries: Integer): Integer;
var
  first: Integer;
  i: Integer;
  el: TTyChartElement;
  c: TTyChartColor;
  pts: TTyPointFArray;

  function Colour(const S: string; out AC: TTyChartColor): Boolean;
  begin
    Result := (S <> '') and TyTryParseChartColor(S, AC);
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

  procedure Lbl(const B: TTyMkLabelPic; ATarget: TTyPaintList);
  var
    x, y, w, h: Double;
    ah: TTyTextAnchorH;
    av: TTyTextAnchorV;
    fs: Integer;
    pieces: TTyRtPieceArray;
  begin
    { [R2-I5] an empty one too where a state has words [was: nothing] }
    if (not B.Present) or ((B.Text = '') and not B.KeepEmpty) then Exit;
    if not B.HasInk and not B.Rt.Needed and not B.KeepEmpty then Exit;
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
    if (B.FontSize <> nil) and (B.FontSize <> GTextDefaults.Find('fontSize')) then
      fs := TyOptFontSize(B.FontSize, fs);  // CSS px [Batch 83]
    w := 0;
    h := 0;
    { an empty text's box is its anchor (no line to measure) }
    if (AMeasurer <> nil) and (B.Text <> '') then
      AMeasurer.MeasureLine(B.Text, AInk.FontName, fs, AInk.FontWeight, w, h);
    el := Blank(B.Z2);
    el.Ignore := B.Hidden;
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
    { [R2-I6] THE TEXT'S OWN OPACITY ON THE ELEMENT, not in its ink: a
      state's text style replaces it (zrender merges the state's style over
      the normal one) and blur's default is a tenth of it -- the states
      write the element's opacity, and with this one in the ink as well the
      two multiplied (a blur.label.opacity 0.3 over a label.opacity 0.5 drew
      at 0.15, an emphasis twin's ink carried emphasis' own once more). The
      same alpha on every colour of it, rich pieces too. }
    el.Style.Alpha := LabelAlpha(B.StyleOpacity);
    if B.InkStroke <> '' then
    begin
      if (B.StyleStroke <> '') and Colour(B.InkStroke, c) then el.Caption.StrokeColour := c
      else el.Caption.StrokeColour := AInk.Halo;
      if not IsNan(B.InkLineWidth) then el.Caption.StrokeWidthLogical := B.InkLineWidth;
    end;
    el.Caption.X := x;
    el.Caption.Y := y;
    el.Caption.AnchorH := ah;
    el.Caption.AnchorV := av;
    el.Caption.RotationRad := B.InnerRotation;
    if not B.HasTransform then el.Caption.RotationRad := 0;
    { THE BLOCK, in the skin's outside ink and halo where the style gives
      none [Batch 86] }
    if B.Rt.Needed and (B.Text <> '') then
    begin
      pieces := MkRtPieces(B.Rt, B.Text, el.Caption.FontName,
        el.Caption.FontSizeLogical, el.Caption.FontWeight, AInk.RtGlobal,
        B.RtHasInherit, B.RtInherit, AInk.Text, B.DefStroke <> '', AInk.Halo,
        ah, av, B.RtScale, AMeasurer);
      if Length(pieces) = 0 then Exit;
      el.Caption.RtPieces := pieces;
      el.Caption.RtScale := B.RtScale;
      el.Shape := TyShapeRect(TyRtDeviceBox(pieces, x, y,
        el.Caption.RotationRad, B.RtScale));
    end;
    ATarget.Add(el);
    if ATarget = AList then Inc(Result);
  end;

  { THE ANIMATION'S VIEW of what was just added: one proxy per line, its
    percent (Line.ts _createLine) [Batch 92, AN4] }
  procedure TagLast(AAt: Integer; ARole: TTyChartAnimRole; const P: TTyMkLinePic);
  var e: TTyChartElement;
  begin
    if (AHostSeries < 0) or (AList.Count <= AAt) then Exit;
    e := AList.Element(AList.Count - 1);
    e.Anim := Default(TTyChartAnim);
    e.Anim.Role := ARole;
    e.Anim.Series := AHostSeries;
    e.Anim.Index := ABlock.Lines[P.Item].DataIndex;
    e.Anim.G[0] := P.X1;
    e.Anim.G[1] := P.Y1;
    e.Anim.G[2] := P.X2;
    e.Anim.G[3] := P.Y2;
    case ARole of
      carMarkLine:
        if Length(P.Path) = 2 then
        begin
          e.Anim.G[4] := P.Path[0].V[0];
          e.Anim.G[5] := P.Path[0].V[1];
          e.Anim.G[6] := P.Path[1].V[0];
          e.Anim.G[7] := P.Path[1].V[1];
        end;
      carMarkLineLabel:
        begin
          e.Anim.G[4] := P.Lbl.DistX;
          e.Anim.G[5] := P.Lbl.DistY;
          e.Anim.G[6] := P.Lbl.PosCode;
          e.Anim.G[7] := P.Lbl.Dy;
          e.Anim.G[8] := P.Lbl.Dir;
          e.Anim.G[9] := Ord(P.Lbl.AuthorAlign) + 2 * Ord(P.Lbl.AuthorVAlign);
        end;
    end;
    AList.SetElement(AList.Count - 1, e);
  end;

var
  at, k: Integer;
  tmp: TTyPaintList;
  lel: TTyChartElement;
begin
  Result := 0;
  if AList = nil then Exit;
  for i := 0 to High(APics) do
  begin
    if not APics[i].Drawn then Continue;
    first := AList.Count;
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
      el.Style.DashWord := APics[i].DashWord;
      el.Style.DashOffsetLogical := APics[i].DashOffset;
      el.Style.Alpha := Max(0.0, Min(1.0, APics[i].Opacity));
      { THE POINTER'S RIBBON: zrender's Path.contain widens a stroke with no
        fill to its strokeContainThreshold, 5 -- a 1 px line is hit within
        2.5 px of it, not only on it }
      el.HitSlopLogical := Math.Max(APics[i].LineWidth, Double(5)) / 2;
      AList.Add(el);
      Inc(Result);
      TagLast(first, carMarkLine, APics[i]);
    end;
    at := AList.Count;
    Symbol(APics[i].FromSym);
    TagLast(at, carMarkLineFrom, APics[i]);
    at := AList.Count;
    Symbol(APics[i].ToSym);
    TagLast(at, carMarkLineTo, APics[i]);
    at := AList.Count;
    Lbl(APics[i].Lbl, AList);
    TagLast(at, carMarkLineLabel, APics[i]);
    { [R2-I3] the label as the hover lays it out, its twin }
    if APics[i].EmphLbl.Present and (AList.Count > at) then
    begin
      tmp := TTyPaintList.Create;
      try
        Lbl(APics[i].EmphLbl, tmp);
        if tmp.Count > 0 then
        begin
          lel := AList.Element(at);
          SetLength(lel.EmphTwin, 1);
          lel.EmphTwin[0].Caption := tmp.Element(0).Caption;
          lel.EmphTwin[0].Shape := tmp.Element(0).Shape;
          lel.EmphTwin[0].State := TyTwinEmphasis;
          AList.SetElement(at, lel);
        end;
      finally
        tmp.Free;
      end;
    end;
    { [R2-I5] and as blur and select lay it out }
    for k := 1 to 2 do
      if APics[i].StateLbl[k].Present and (AList.Count > at) then
      begin
        tmp := TTyPaintList.Create;
        try
          Lbl(APics[i].StateLbl[k], tmp);
          if tmp.Count > 0 then
          begin
            lel := AList.Element(at);
            SetLength(lel.EmphTwin, Length(lel.EmphTwin) + 1);
            lel.EmphTwin[High(lel.EmphTwin)].Caption := tmp.Element(0).Caption;
            lel.EmphTwin[High(lel.EmphTwin)].Shape := tmp.Element(0).Shape;
            lel.EmphTwin[High(lel.EmphTwin)].State := k;
            AList.SetElement(at, lel);
          end;
        finally
          tmp.Free;
        end;
      end;
    MkTarget(AList, first, ctkMarkLine, AHostSeries,
      ABlock.Lines[APics[i].Item].DataIndex, ABlock.Silent);
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

{ THE LABEL'S STYLE, PLACE AND INK, shared by markPoint and markArea:
  createTextStyle / createTextConfig, calculateTextPosition against ARect
  (the pin's 0.4 rule when APin), updateInnerText's rotate and offset, and
  the inside ink against the host fill (AFillStr when AFillIsString, else a
  gradient) or the outside ink. The text is the caller's. }
{ [R2-I3] zrender's BoundingRect.union: this widened to take R in }
procedure ZrUnion(var A: TTyXYWH; var AHas: Boolean; const R: TTyXYWH);
var x, y: Double;
begin
  if not AHas then
  begin
    A := R;
    AHas := True;
    Exit;
  end;
  x := Min(R.X, A.X);
  y := Min(R.Y, A.Y);
  if not IsInfinite(A.X) and not IsNan(A.X) and not IsInfinite(A.W) and not IsNan(A.W) then
    A.W := Max(R.X + R.W, A.X + A.W) - x
  else
    A.W := R.W;
  if not IsInfinite(A.Y) and not IsNan(A.Y) and not IsInfinite(A.H) and not IsNan(A.H) then
    A.H := Max(R.Y + R.H, A.Y + A.H) - y
  else
    A.H := R.H;
  A.X := x;
  A.Y := y;
end;

{ [R2-I3] zrender contain/text.ts calculateTextPosition: where the text's
  anchor goes on the rect R (its alignment the caller keeps); a word it does
  not know leaves the rect's corner }
procedure ZrCalcTextPos(APos: TJSONData; ADist: Double; const R: TTyXYWH;
  out AX, AY: Double);
var w: string;
begin
  AX := R.X;
  AY := R.Y;
  if (APos <> nil) and (APos.JSONType = jtArray) then
  begin
    if APos.Count > 0 then AX := AX + ZrPercent(APos.Items[0], R.W) else AX := NaN;
    if APos.Count > 1 then AY := AY + ZrPercent(APos.Items[1], R.H) else AY := NaN;
    Exit;
  end;
  if (APos <> nil) and (APos.JSONType = jtString) then w := APos.AsString else w := 'inside';
  if w = 'left' then
  begin
    AX := AX - ADist; AY := AY + R.H / 2;
  end
  else if w = 'right' then
  begin
    AX := AX + ADist + R.W; AY := AY + R.H / 2;
  end
  else if w = 'top' then
  begin
    AX := AX + R.W / 2; AY := AY - ADist;
  end
  else if w = 'bottom' then
  begin
    AX := AX + R.W / 2; AY := AY + R.H + ADist;
  end
  else if w = 'inside' then
  begin
    AX := AX + R.W / 2; AY := AY + R.H / 2;
  end
  else if w = 'insideLeft' then
  begin
    AX := AX + ADist; AY := AY + R.H / 2;
  end
  else if w = 'insideRight' then
  begin
    AX := AX + R.W - ADist; AY := AY + R.H / 2;
  end
  else if w = 'insideTop' then
  begin
    AX := AX + R.W / 2; AY := AY + ADist;
  end
  else if w = 'insideBottom' then
  begin
    AX := AX + R.W / 2; AY := AY + R.H - ADist;
  end
  else if w = 'insideTopLeft' then
  begin
    AX := AX + ADist; AY := AY + ADist;
  end
  else if w = 'insideTopRight' then
  begin
    AX := AX + R.W - ADist; AY := AY + ADist;
  end
  else if w = 'insideBottomLeft' then
  begin
    AX := AX + ADist; AY := AY + R.H - ADist;
  end
  else if w = 'insideBottomRight' then
  begin
    AX := AX + R.W - ADist; AY := AY + R.H - ADist;
  end;
end;

{ [R2-I3] A markLine LABEL UNDER AN EMPHASIS POSITION. The Line group's
  emphasis state carries the label's textConfig (setLabelStyle), so
  updateInnerText -- after Line.beforeUpdate placed the text -- puts it by
  calculateTextPosition on the group's own box: the line's path grown by its
  stroke at the emphasis width (max(width, 5), no fill) and each end symbol's
  path box through its transform, in the group's order; the distance the
  emphasis label's, else the normal one's (textConfig merges). The text's
  alignment stays beforeUpdate's (it sets the style's), its turn and offset
  ride along: the move is the anchor's. }
procedure EmphLinePlace(const P: TTyMkLinePic; const AItemLv, ALB: TMkLevels;
  APos: TJSONData; AScale: Double; var ALab: TTyMkLabelPic; const AState: string);
var
  box, r: TTyXYWH;
  has: Boolean;
  d: TJSONData;
  w, dist, x, y: Double;

  { [R2-I4] getBoundingRect's stroke allowance in the port's device units:
    the LOGICAL width -- max(width, 5) for a path of no fill -- and then the
    scale the path itself is drawn at. An end symbol (Line.ts createSymbol)
    has no strokeNoScale: its pen grows its box in its own coordinates,
    before its turn; the line's strokeNoScale meets a line scale of 1. [Was:
    the symbol's logical width taken as device px, and the line's floor of 5
    applied after the scale -- a corner short by both at 192 PPI.] }
  function Grown(const ABox: TTyXYWH; AHasFill: Boolean; AWidth: Double): TTyXYWH;
  var g: Double;
  begin
    Result := ABox;
    if not (AWidth > 0) then Exit;
    g := AWidth;
    if (not AHasFill) and (g < 5) then g := 5;
    Result := TyGrowByStroke(ABox, True, g * AScale);
  end;

  procedure Sym(const S: TTyMkSymbolPic);
  begin
    if not S.Present or (Length(S.Path) = 0) then Exit;
    r := TyZrBBox(S.Path);
    if (S.Stroke <> '') and (S.Stroke <> 'none') then
      r := Grown(r, (S.Fill <> '') and (S.Fill <> 'none'), S.LineWidth);
    ZrUnion(box, has, RectThrough(r, S.HasTransform, S.Transform));
  end;

begin
  has := False;
  box := Default(TTyXYWH);
  if Length(P.Path) > 0 then
  begin
    d := Chain(Sub(Sub(AItemLv, AState), 'lineStyle'), 'width');
    if d <> nil then w := NumOf(d) else w := P.LineWidth;
    r := TyZrBBox(P.Path);
    if (P.Stroke <> '') and (P.Stroke <> 'none') then
      r := Grown(r, False, w);
    ZrUnion(box, has, r);
  end;
  Sym(P.FromSym);
  Sym(P.ToSym);
  d := Chain(Sub(Sub(AItemLv, AState), 'label'), 'distance');
  if d = nil then d := Chain(ALB, 'distance');
  if d = nil then dist := 5
  else if d.JSONType = jtArray then dist := NaN
  else dist := NumOf(d);
  dist := dist * AScale;
  ZrCalcTextPos(APos, dist, box, x, y);
  ALab.InnerX := ALab.InnerX + (x - ALab.X);
  ALab.InnerY := ALab.InnerY + (y - ALab.Y);
  ALab.X := x;
  ALab.Y := y;
  ALab.HasTransform := LocalTransform(ALab.InnerX, ALab.InnerY,
    ALab.InnerRotation, ALab.InnerOriginX, ALab.InnerOriginY, ALab.Transform);
end;

procedure StyleLabel(const LB: TMkLevels; const gts: TMkView; const AIn: TTyMkPicInput;
  AScale: Double; const ARect: TTyXYWH; const AInherit: string;
  AHasFill, AFillIsString: Boolean; const AFillStr: string; ADefaultOpacity: Double;
  APin: Boolean; AMaxZ2: Double; var lp: TTyMkPtLabelPic);
var
  d, posd, offA: TJSONData;
  fc, sc, posS, rawA, rawV: string;
  hasFc, hasSc, useDefault, bgDrawn, rich: Boolean;
  dist, lrot, rx, ry, ls, gw, op, calcX, calcY: Double;
  calcA, calcV: string;
  rect: TTyXYWH;
  k: Integer;
begin
    { the text style, attached }
    fc := '';
    sc := '';
    d := Chain(LB, 'color');
    hasFc := d <> nil;
    if hasFc then
    begin
      fc := StrOf(d);
      if (fc = 'inherit') or (fc = 'auto') then fc := AInherit;
      hasFc := fc <> '';
    end;
    d := Chain(LB, 'textBorderColor');
    hasSc := d <> nil;
    if hasSc then
    begin
      sc := StrOf(d);
      if (sc = 'inherit') or (sc = 'auto') then sc := AInherit;
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
      { defaultOpacity: the host's, where it passes one }
      lp.StyleOpacity := ADefaultOpacity;
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
    if Truthy(posd) then posS := JsStringOf(posd) else
    begin
      posS := 'inside';
      lp.Position := GInsideWord;
    end;
    if (posd <> nil) and (posd.JSONType = jtArray) then posS := #1;
    if posS = 'outside' then
    begin
      posS := 'top';
      lp.Position := GTopWord;
    end;
    d := Chain(LB, 'distance');
    if d <> nil then dist := NumOf(d) else dist := 5;
    lp.Distance := dist;
    dist := dist * AScale;
    { the rect: the symbol path's own, grown by its stroke, through its global
      transform }
    rect := ARect;
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
    if APin and (posS = 'inside') then calcY := rect.Y + rect.H * 0.4;
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
      rx := NumOf(offA.Items[0]) * AScale;
      ry := NumOf(offA.Items[1]) * AScale;
      lp.InnerX := lp.InnerX + rx;
      lp.InnerY := lp.InnerY + ry;
      lp.InnerOriginX := -rx;
      lp.InnerOriginY := -ry;
    end;
    lp.HasTransform := LocalTransform(lp.InnerX, lp.InnerY, lp.InnerRotation,
      lp.InnerOriginX, lp.InnerOriginY, lp.Transform);
    { the ink: inside against the symbol's fill, else outside }
    lp.Inside := (posS <> #1) and (Pos('inside', posS) > 0) and AHasFill;
    if lp.Inside then
    begin
      { a fill that is not a string (a gradient) reads as dark }
      if not AFillIsString then lp.DefFill := '#ccc'
      else if AFillStr = 'none' then lp.DefFill := '#333'
      else
      begin
        ls := TyMkLum(AFillStr, 0);
        if ls > 0.5 then lp.DefFill := '#333'
        else if ls > 0.2 then lp.DefFill := '#eee'
        else lp.DefFill := '#ccc';
      end;
      lp.DefStroke := '';
      if AFillIsString and (AIn.IsDark = (TyMkLum(lp.DefFill, 0) < 0.4)) then
        lp.DefStroke := AFillStr;
    end
    else
    begin
      d := Chain(LB, 'color');
      if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'inherit') then
        lp.DefFill := AInherit
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
    if IsInfinite(AMaxZ2) then lp.Z2 := 0 else lp.Z2 := AMaxZ2 + 2;
    lp.Silent := Truthy(Chain(LB, 'silent'));
    MkRt(LB, AIn, AInherit, AScale, lp.Rt, lp.RtHasInherit, lp.RtInherit,
      lp.RtScale);
end;

function TyMkPointPictures(const ABlock: TTyMkBlock; const AIn: TTyMkPicInput;
  AXIsLabel, AYIsLabel: Boolean): TTyMkPointPicArray;
var
  own, master, gts: TMkView;
  MP: TMkLevels;
  i, n, k: Integer;
  maxZ2, s: Double;
  E: TTyMkEnd;
  { [R2-J3] the symbol callbacks' answers of the point being pictured }
  cbHeld: array of TJSONData;
  { [R2-I7] the names seen, for the repeats' ids }
  seen: TStringList;
  nm0: string;
  idx0: Integer;

  { mpData's name of a point: its own, else its coordinate on the name
    dimension (the series' category axis -- the max's category index, '3');
    False for none }
  function MkName(const AE: TTyMkEnd; out AName: string): Boolean;
  begin
    Result := True;
    AName := '';
    case AE.Name.Kind of
      mvkNum: AName := TyChartValueText(AE.Name.Num);
      mvkStr: AName := AE.Name.Str;
    else
      begin
        Result := False;
        if (AIn.NameDim >= 0) and (AIn.NameDim <= 1) then
          case AE.Coord[AIn.NameDim].Kind of
            mvkNum:
              begin
                AName := TyChartValueText(AE.Coord[AIn.NameDim].Num);
                Result := True;
              end;
            mvkStr:
              begin
                AName := AE.Coord[AIn.NameDim].Str;
                Result := True;
              end;
          end;
      end;
    end;
  end;

  { [R2-J3] MarkPointView: a symbol, symbolSize, symbolRotate or
    symbolOffset that is a function is called as cb(rawValue, params) --
    mpModel.getRawValue and getDataParams of the marker's datum (n: its
    place in the marker's data; no colour) -- and its answer is the value.
    Any other value as it is. }
  function Cbd(AData: TJSONData): TJSONData;
  var prm: TTyChartCallbackParams;
  begin
    Result := AData;
    if (AData = nil) or (AData.JSONType <> jtString)
      or not TyChartIsHandlerRef(AData.AsString) then Exit;
    prm := TyChartBlankParams;
    prm.ComponentType := 'markPoint';
    prm.SeriesType := AIn.SeriesType;
    prm.SeriesIndex := AIn.SeriesIndex;
    prm.SeriesName := AIn.SeriesName.Str;
    prm.DataIndex := n;
    prm.RawDataIndex := n;
    prm.Status := 'normal';
    MkName(E, prm.Name);
    case E.Value.Kind of
      mvkNum:
        begin
          SetLength(prm.Values, 1);
          prm.Values[0] := E.Value.Num;
          prm.ValueText := TyChartValueText(E.Value.Num);
        end;
      mvkStr: prm.ValueText := E.Value.Str;
    else
      prm.ValueText := 'undefined';
    end;
    Result := TyChartRunVisualHandler(AData.AsString, prm);
    if Result <> nil then
    begin
      SetLength(cbHeld, Length(cbHeld) + 1);
      cbHeld[High(cbHeld)] := Result;
    end;
  end;

  procedure Picture(var P: TTyMkPointPic);
  var
    lv, IS_, LB: TMkLevels;
    d, sz, off, o0, o1, fmt, v, posd, offA: TJSONData;
    fill, typ, str, posS, rawA, rawV, fc, sc, sv: string;
    w, h, ox, oy, rot, lw, ls, gw, dist, lrot, rx, ry, op: Double;
    hasStroke, hasFill, hasFc, hasSc, useDefault, bgDrawn, lblDim, rich: Boolean;
    rectLocal, rect: TTyXYWH;
    lp, lp2: TTyMkPtLabelPic;
    calcX, calcY: Double;
    calcA, calcV: string;
    dimIdx, k: Integer;
    dl: TTyDoubleArray;
    defOp, ls2, x1, y1, x2, y2, lw2, ratio2: Double;
    hasL2, hasG2, hasStroke2: Boolean;
    ES, LBE: TMkLevels;
    hasOv: Boolean;
    hold: IInterface;
    sc2: string;
    l2, g2: TTyMat2D;
    { [R2-I4] the name, and the hover's words }
    nm, et: string;
    hasEt: Boolean;
    { [R2-I5] blur's and select's }
    sti: Integer;
    stName: string;
    lps: TTyMkPtLabelPic;
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
    d := Cbd(Chain(lv, 'symbol'));
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
    sz := Cbd(Chain(lv, 'symbolSize'));
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
    { [R2-B] THE EMPHASIS RATIO (Symbol._updateCommon): emphasis.scale
      through the item's chain -- null, undefined or true the default
      max(1.1, 3 / _sizeY); a finite positive number (Number() of it) as it
      is; anything else no scale }
    d := Chain(Sub(lv, 'emphasis'), 'scale');
    if (d = nil) or ((d.JSONType = jtBoolean) and d.AsBoolean) then
    begin
      { a symbol of no height: 3 / 0 upstream, a scale of NaN -- none here }
      if h > 0 then P.EmphRatio := Math.Max(Double(1.1), 3 / (h / s / 2))
      else P.EmphRatio := 1;
    end
    else
    begin
      P.EmphRatio := NumOf(d);
      if IsNan(P.EmphRatio) or IsInfinite(P.EmphRatio) or not (P.EmphRatio > 0) then
        P.EmphRatio := 1;
    end;
    d := Cbd(Chain(lv, 'symbolRotate'));
    if Truthy(d) then rot := NumOf(d) * Pi / 180 else rot := 0;
    if IsNan(rot) then rot := 0;
    P.Rotation := rot;
    { normalizeSymbolOffset: percent of the size, y falling back to x }
    P.X := 0;
    P.Y := 0;
    off := Cbd(Chain(lv, 'symbolOffset'));
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
    { [R2-I1] built where a state shows it too (needsCreateText), ignored at
      rest [was: not built] }
    if not Truthy(Chain(LB, 'show')) and not AnyStateLabelShows(lv) then
    begin
      P.Lbl := lp;
      Exit;
    end;
    lp.Present := True;
    lp.Hidden := not Truthy(Chain(LB, 'show'));
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
    case E.Name.Kind of
      mvkStr: nm := E.Name.Str;
      mvkNum: nm := TyJsNumberToString(E.Name.Num);
    else
      nm := '';
    end;
    if (fmt <> nil) and (fmt.JSONType = jtString) then
    begin
      str := nm;
      if TyChartIsHandlerRef(fmt.AsString) then
        str := MkHandlerText(fmt.AsString, AIn, 'markPoint', str, sv,
          ABlock.Points[P.Item].DataIndex, 'normal')
      else if AIn.SeriesName.Kind = mvkUndef then
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
    { defaultOpacity: the symbol style's }
    d := Chain(IS_, 'opacity');
    if d <> nil then defOp := NumOf(d) else defOp := NaN;
    StyleLabel(LB, gts, AIn, s, RectThrough(rectLocal, P.HasGlobal, P.Global), fill,
      hasFill, True, P.StyleFill, defOp, P.ShapeType = 'pin', maxZ2, lp);
    { [R2-B] AND ON THE PATH THE HOVER SCALES: the same layout on the rect of
      the path at its emphasis scale (the stroke's margin by that scale's
      line scale) -- the move from the rest place; [R2-I1] under the
      emphasis textConfig too (its position, distance, offset, rotate);
      [R2-I3] under the whole emphasis label (its text style too) }
    ratio2 := P.EmphRatio;
    if IsNan(ratio2) or IsInfinite(ratio2) then ratio2 := 1;
    hasOv := EmphLevels(lv, LB, 'emphasis', [], LBE, hold);
    hasEt := EmphText(lv, 'emphasis', AIn, 'markPoint', nm, sv,
      ABlock.Points[P.Item].DataIndex, et);
    { the stroke the emphasis style draws: its own borderColor and
      borderWidth over the rest's -- the rect grows by it }
    ES := Sub(Sub(lv, 'emphasis'), 'itemStyle');
    sc2 := P.StyleStroke;
    lw2 := P.StyleLineWidth;
    d := Chain(ES, 'borderColor');
    if d <> nil then sc2 := StrOf(d);
    d := Chain(ES, 'borderWidth');
    if d <> nil then lw2 := NumOf(d);
    hasStroke2 := (sc2 <> '') and (sc2 <> 'none') and (lw2 > 0);
    { [R2-I5] and a pen that grows or shrinks the rect moves the label too
      (updateInnerText on the path as the state draws it) [was: laid out
      again only for a scale, a text style or words of its own] }
    if (ratio2 <> 1) or hasOv or hasEt or (hasStroke2 <> hasStroke)
      or (hasStroke2 and (lw2 <> P.StyleLineWidth)) then
    begin
      hasL2 := LocalTransformS(P.X, P.Y, P.Rotation, P.ScaleX * ratio2,
        P.ScaleY * ratio2, l2);
      hasG2 := hasL2 or P.HasGroupTransform;
      if P.HasGroupTransform and hasL2 then g2 := MatMul(P.GroupTransform, l2)
      else if hasL2 then g2 := l2
      else if P.HasGroupTransform then g2 := P.GroupTransform;
      if hasG2 and (Abs(g2[0] - 1) > 1e-10) and (Abs(g2[3] - 1) > 1e-10) then
        ls2 := Sqrt(Abs(g2[0] * g2[3] - g2[2] * g2[1]))
      else
        ls2 := 1;
      lp2 := lp;
      { [R2-I4] its own words, where the emphasis formats them }
      if hasEt then lp2.Text := et;
      StyleLabel(LBE, gts, AIn, s, RectThrough(TyZrStrokeRect(P.BBox, Length(P.Path), hasStroke2,
        hasFill, lw2, ls2), hasG2, g2), fill, hasFill, True, P.StyleFill, defOp,
        P.ShapeType = 'pin', maxZ2, lp2);
      { [R2-I3] what it points into lives with it }
      lp2.Hold := hold;
      lp2.Hidden := False;
      P.EmphLbl := lp2;
      x1 := 0;
      y1 := 0;
      x2 := 0;
      y2 := 0;
      if lp.HasTransform then
      begin
        x1 := lp.Transform[4];
        y1 := lp.Transform[5];
      end;
      if lp2.HasTransform then
      begin
        x2 := lp2.Transform[4];
        y2 := lp2.Transform[5];
      end;
      lp.HasEmphPlace := True;
      lp.EmphDX := x2 - x1;
      lp.EmphDY := y2 - y1;
      if lp2.Text <> '' then lp.KeepEmpty := True;
    end;
    { [R2-I5] BLUR'S AND SELECT'S LABEL: its own text style (the opacity
      aside -- the states' own) and words, on the path at rest grown by the
      stroke that state draws }
    for sti := 1 to 2 do
    begin
      if sti = 1 then stName := 'blur' else stName := 'select';
      hasEt := EmphText(lv, stName, AIn, 'markPoint', nm, sv,
        ABlock.Points[P.Item].DataIndex, et);
      ES := Sub(Sub(lv, stName), 'itemStyle');
      sc2 := P.StyleStroke;
      lw2 := P.StyleLineWidth;
      d := Chain(ES, 'borderColor');
      if d <> nil then sc2 := StrOf(d);
      d := Chain(ES, 'borderWidth');
      if d <> nil then lw2 := NumOf(d);
      hasStroke2 := (sc2 <> '') and (sc2 <> 'none') and (lw2 > 0);
      if not (EmphLevels(lv, LB, stName, ['opacity'], LBE, hold) or hasEt
        or (hasStroke2 <> hasStroke) or (hasStroke2 and (lw2 <> P.StyleLineWidth))) then
        Continue;
      lps := lp;
      lps.HasEmphPlace := False;
      if hasEt then lps.Text := et;
      StyleLabel(LBE, gts, AIn, s, RectThrough(TyZrStrokeRect(P.BBox, Length(P.Path),
        hasStroke2, hasFill, lw2, P.LineScale), P.HasGlobal, P.Global), fill, hasFill, True,
        P.StyleFill, defOp, P.ShapeType = 'pin', maxZ2, lps);
      lps.Hold := hold;
      lps.Hidden := False;
      lps.KeepEmpty := False;
      P.StateLbl[sti] := lps;
      if lps.Text <> '' then lp.KeepEmpty := True;
    end;
    { an empty rest text keeps nothing of its own to show }
    if lp.Text <> '' then lp.KeepEmpty := False;
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
  seen := TStringList.Create;
  try
    seen.Sorted := True;
    seen.Duplicates := dupIgnore;
    seen.CaseSensitive := True;
    seen.UseLocale := False;
    for i := 0 to High(ABlock.Points) do
    begin
      if not ABlock.Points[i].Survived then Continue;
      E := ABlock.Points[i].E;
      Result[n] := Default(TTyMkPointPic);
      Result[n].Item := i;
      { [R2-I7] SeriesData's makeIdFromName: the name, a repeat with its
        count; no name 'e' + two NULs + the raw index (the place in mpData) }
      if MkName(E, nm0) then
      begin
        idx0 := seen.IndexOf(nm0);
        if idx0 < 0 then
        begin
          seen.AddObject(nm0, TObject(PtrInt(1)));
          Result[n].Id := nm0;
        end
        else
        begin
          seen.Objects[idx0] := TObject(PtrInt(PtrInt(seen.Objects[idx0]) + 1));
          Result[n].Id := nm0 + '__ec__' + IntToStr(PtrInt(seen.Objects[idx0]));
        end;
      end
      else
        Result[n].Id := 'e'#0#0 + IntToStr(ABlock.Points[i].DataIndex);
      cbHeld := nil;
      try
        Picture(Result[n]);
      finally
        for k := 0 to High(cbHeld) do cbHeld[k].Free;
        cbHeld := nil;
      end;
      Inc(n);
      if n >= Length(Result) then Break;
    end;
  finally
    seen.Free;
  end;
  SetLength(Result, n);
end;

{ a markPoint's or a markArea's label as an answer caption }
function EmitLabel(const B: TTyMkPtLabelPic; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList): Integer;
var
  fs: Integer;
  el: TTyChartElement;
  c, defFill, defStroke: TTyChartColor;
  hasDefStroke: Boolean;
  pieces: TTyRtPieceArray;
  AGlobal: TTyRtGlobal;
  x, y, w, h: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;

  function Colour(const S: string; out AC: TTyChartColor): Boolean;
  begin
    Result := (S <> '') and TyTryParseChartColor(S, AC);
  end;

begin
  Result := 0;
  AGlobal := AInk.RtGlobal;
  defStroke := 0;
  { [R2-I5] an empty one too where a state has words [was: nothing] }
  if (not B.Present) or ((B.Text = '') and not B.KeepEmpty) then Exit;
  { a rich label has no one-run ink and is drawn as its block [Batch 86] }
  if not B.HasInk and not B.Rt.Needed and not B.KeepEmpty then Exit;
  if IsNan(B.InnerX) or IsNan(B.InnerY) then Exit;
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
    if (B.FontSize <> nil) and (B.FontSize <> GTextDefaults.Find('fontSize')) then
      fs := TyOptFontSize(B.FontSize, fs);  // CSS px [Batch 83]
    w := 0;
    h := 0;
    { an empty text's box is its anchor (no line to measure) }
    if (AMeasurer <> nil) and (B.Text <> '') then
      AMeasurer.MeasureLine(B.Text, AInk.FontName, fs, AInk.FontWeight, w, h);
    el := Default(TTyChartElement);
    el.Z := Trunc(ABlock.Z);
    el.Z2 := Round(B.Z2);
    el.Silent := True;
    el.Datum := TyChartDatum(-1, -1);
    el.Style.Alpha := 1;
    el.Ignore := B.Hidden;
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
    { [R2-I6] the text's own opacity on the element, as a markPoint's }
    el.Style.Alpha := LabelAlpha(B.StyleOpacity);
    if B.InkStroke <> '' then
    begin
      if ((B.StyleStroke <> '') or B.Inside) and Colour(B.InkStroke, c) then
        el.Caption.StrokeColour := c
      else
        el.Caption.StrokeColour := AInk.Halo;
      if not IsNan(B.InkLineWidth) then el.Caption.StrokeWidthLogical := B.InkLineWidth;
    end;
    el.Caption.X := x;
    el.Caption.Y := y;
    el.Caption.AnchorH := ah;
    el.Caption.AnchorV := av;
    if B.HasTransform then el.Caption.RotationRad := B.InnerRotation;
    { THE BLOCK, in the ink the one-run caption would have had where the
      style gives none: the band's inside (the host's fill as its halo),
      the skin's outside ink and halo otherwise [Batch 86] }
    if B.Rt.Needed and (B.Text <> '') then
    begin
      if B.Inside then
      begin
        if B.DefFill = '#333' then defFill := AInk.Inside[0]
        else if B.DefFill = '#eee' then defFill := AInk.Inside[1]
        else defFill := AInk.Inside[2];
        hasDefStroke := Colour(B.DefStroke, defStroke);
      end
      else
      begin
        defFill := AInk.Text;
        hasDefStroke := B.DefStroke <> '';
        defStroke := AInk.Halo;
      end;
      pieces := MkRtPieces(B.Rt, B.Text, el.Caption.FontName,
        el.Caption.FontSizeLogical, el.Caption.FontWeight, AGlobal,
        B.RtHasInherit, B.RtInherit, defFill, hasDefStroke, defStroke,
        ah, av, B.RtScale, AMeasurer);
      if Length(pieces) = 0 then Exit;
      el.Caption.RtPieces := pieces;
      el.Caption.RtScale := B.RtScale;
      el.Shape := TyShapeRect(TyRtDeviceBox(pieces, x, y,
        el.Caption.RotationRad, B.RtScale));
    end;
  AList.Add(el);
  Result := 1;
end;

{ [R2-I1] THE EMPHASIS LAYOUT ONTO THE REST LABEL AEl: the label emitted
  from AEmph -- where the hover lays it out -- read back into AEl.Anim: the
  move of its anchor G[2..3], G[4] 2 (1: the move alone, a text block), its
  alignment G[5..6], its turn G[7], its box G[8..11]; and its ink as the
  caption's emphasis ink (updateInnerText picks the inside or outside ink
  where the text now is) }
procedure StampEmphLayout(var AEl: TTyChartElement; const AEmph: TTyMkPtLabelPic;
  const ABlock: TTyMkBlock; const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer);
var
  tmp: TTyPaintList;
  e2: TTyChartElement;
  b: TTyRectF;
begin
  if not AEmph.Present then Exit;
  tmp := TTyPaintList.Create;
  try
    if (EmitLabel(AEmph, ABlock, AInk, AMeasurer, tmp) <= 0) or (tmp.Count = 0) then Exit;
    e2 := tmp.Element(0);
  finally
    tmp.Free;
  end;
  { [R2-I3] THE WHOLE LABEL as the hover lays it out -- its font, its
    block's pieces, its box -- which the states put in place of the rest
    one under emphasis }
  SetLength(AEl.EmphTwin, 1);
  AEl.EmphTwin[0].Caption := e2.Caption;
  AEl.EmphTwin[0].Shape := e2.Shape;
  AEl.EmphTwin[0].State := TyTwinEmphasis;
  AEl.Anim.G[2] := e2.Caption.X - AEl.Caption.X;
  AEl.Anim.G[3] := e2.Caption.Y - AEl.Caption.Y;
  AEl.Anim.G[4] := 1;
  if (Length(AEl.Caption.RtPieces) > 0) or (Length(e2.Caption.RtPieces) > 0) then Exit;
  AEl.Anim.G[4] := 2;
  AEl.Anim.G[5] := Ord(e2.Caption.AnchorH);
  AEl.Anim.G[6] := Ord(e2.Caption.AnchorV);
  AEl.Anim.G[7] := e2.Caption.RotationRad;
  b := e2.Shape.Bounds;
  AEl.Anim.G[8] := b.Left;
  AEl.Anim.G[9] := b.Top;
  AEl.Anim.G[10] := b.Right;
  AEl.Anim.G[11] := b.Bottom;
  AEl.Caption.HasEmph := True;
  AEl.Caption.EmphColour := e2.Caption.Colour;
  AEl.Caption.EmphStrokeColour := e2.Caption.StrokeColour;
  AEl.Caption.EmphStrokeWidthLogical := e2.Caption.StrokeWidthLogical;
end;

{ [R2-I5] BLUR'S AND SELECT'S LABEL onto the rest label AEl: each laid out
  as its state lays it out, a twin after the emphasis one }
procedure StampStateTwins(var AEl: TTyChartElement; const AStates: array of TTyMkPtLabelPic;
  const ABlock: TTyMkBlock; const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer);
var
  tmp: TTyPaintList;
  k, n: Integer;
begin
  for k := 0 to High(AStates) do
  begin
    if not AStates[k].Present then Continue;
    tmp := TTyPaintList.Create;
    try
      if (EmitLabel(AStates[k], ABlock, AInk, AMeasurer, tmp) <= 0) or (tmp.Count = 0) then
        Continue;
      n := Length(AEl.EmphTwin);
      SetLength(AEl.EmphTwin, n + 1);
      AEl.EmphTwin[n].Caption := tmp.Element(0).Caption;
      AEl.EmphTwin[n].Shape := tmp.Element(0).Shape;
      AEl.EmphTwin[n].State := k + 1;
    finally
      tmp.Free;
    end;
  end;
end;

function TyBuildMarkPoints(const APics: TTyMkPointPicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList;
  AHostSeries: Integer): Integer;
var
  first, at, k: Integer;
  i, fs: Integer;
  el, lel: TTyChartElement;
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
    first := AList.Count;
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
      { [R2-I5] a word, measured again against the width a state draws }
      el.Style.DashWord := DashWordOf(APics[i].StyleDash);
      el.Style.DashOffsetLogical := APics[i].StyleDashOffset;
    end;
    if not IsNan(APics[i].StyleOpacity) then
      el.Style.Alpha := Max(0.0, Min(1.0, APics[i].StyleOpacity));
    if (APics[i].ScaleX <> 0) and (APics[i].ScaleY <> 0) then
    begin
      { IT POPS IN: SymbolDraw's symbol, scale 0 -> size / 2 about the
        path's own origin and opacity 0 -> its own (Symbol.ts:184-200)
        [Batch 92, AN4] }
      if AHostSeries >= 0 then
      begin
        el.Anim.Role := carMarkPoint;
        el.Anim.Series := AHostSeries;
        el.Anim.Index := ABlock.Points[APics[i].Item].DataIndex;
        { [R2-I7] the diff's key }
        el.Anim.Key := APics[i].Id;
        if APics[i].HasGlobal then
          TyZrApply(APics[i].Global, 0, 0, el.Anim.G[0], el.Anim.G[1])
        else
        begin
          el.Anim.G[0] := APics[i].GroupX + APics[i].X;
          el.Anim.G[1] := APics[i].GroupY + APics[i].Y;
        end;
        el.Anim.G[2] := APics[i].ScaleX;
        el.Anim.G[3] := APics[i].ScaleY;
        if IsNan(APics[i].StyleOpacity) then el.Anim.G[4] := 1
        else el.Anim.G[4] := APics[i].StyleOpacity;
        { [R2-B] the emphasis ratio, for the states }
        el.Anim.G[5] := APics[i].EmphRatio;
      end;
      AList.Add(el);
      Inc(Result);
    end;
    at := AList.Count;
    Inc(Result, EmitLabel(APics[i].Lbl, ABlock, AInk, AMeasurer, AList));
    { THE LABEL IS THE SYMBOL PATH'S TEXT: where an update moves the symbol's
      group, it goes along (the markPoint's proxy) [Batch 99, AN6] }
    if (at > first) and (AList.Element(first).Anim.Role = carMarkPoint) then
      for k := at to AList.Count - 1 do
      begin
        lel := AList.Element(k);
        lel.Anim := Default(TTyChartAnim);
        lel.Anim.Role := carMarkPointLabel;
        lel.Anim.Series := AHostSeries;
        lel.Anim.Index := ABlock.Points[APics[i].Item].DataIndex;
        lel.Anim.G[0] := AList.Element(first).Anim.G[0];
        lel.Anim.G[1] := AList.Element(first).Anim.G[1];
        { [R2-B] where the hover puts it, as a move (G[4] says there is one);
          [R2-I1] its alignment, turn, box and ink there too }
        if APics[i].Lbl.HasEmphPlace then
        begin
          lel.Anim.G[2] := APics[i].Lbl.EmphDX;
          lel.Anim.G[3] := APics[i].Lbl.EmphDY;
          lel.Anim.G[4] := 1;
          if k = at then StampEmphLayout(lel, APics[i].EmphLbl, ABlock, AInk, AMeasurer);
        end;
        AList.SetElement(k, lel);
      end;
    { [R2-I5] and as blur and select lay it out }
    if AList.Count > at then
    begin
      lel := AList.Element(at);
      StampStateTwins(lel, APics[i].StateLbl, ABlock, AInk, AMeasurer);
      AList.SetElement(at, lel);
    end;
    MkTarget(AList, first, ctkMarkPoint, AHostSeries,
      ABlock.Points[APics[i].Item].DataIndex, ABlock.Silent);
  end;
end;

{ ============================ markArea ============================ }

function TyMkModifyAlpha(const AColour: string; A: Double): string;
var r, g, b, al: Double;
begin
  if not TyTryParseCssRgba(AColour, r, g, b, al) then Exit('');
  Result := 'rgba(' + TyJsNumberToString(r) + ',' + TyJsNumberToString(g) + ','
    + TyJsNumberToString(b) + ',' + TyJsNumberToString(A) + ')';
end;

function TyMkAreaPictures(const ABlock: TTyMkBlock;
  const AIn: TTyMkPicInput): TTyMkAreaPicArray;
var
  own, master, gts: TMkView;
  i, n, k: Integer;
  maxZ2, s, z2v: Double;
  A: TTyMkArea;
  P: TTyMkAreaPic;
  lv, IS_, LB: TMkLevels;
  d, fmt, v: TJSONData;
  hasStroke, hasFill: Boolean;
  inherit, name, str: string;
  lp, lp2: TTyMkPtLabelPic;
  LBE: TMkLevels;
  hold: IInterface;
  { [R2-I4] the hover's words }
  et: string;
  hasEt: Boolean;
  { [R2-I5] blur's and select's }
  sti: Integer;
  stName: string;
  rect2: TTyXYWH;
  penMoves: Boolean;

  { [R2-I6] Path.getBoundingRect's stroke allowance in the port's device
    units, as R2-I4's markLine Grown: the LOGICAL width -- max(width, 5)
    where the polygon has no fill -- then the scale the path is drawn at
    (the polygon has no strokeNoScale). [Was: the logical width taken as
    device px, the floor too -- half a width short at 192 PPI; the
    gradient's box floored after the scale.] }
  function AreaRect(AHasStroke, AHasFill: Boolean; AWidth: Double): TTyXYWH;
  var g: Double;
  begin
    if not (AHasStroke and (AWidth > 0) and (Length(P.Path) > 0)) then Exit(P.BBox);
    g := AWidth;
    if (not AHasFill) and (g < 5) then g := 5;
    Result := TyZrStrokeRect(P.BBox, Length(P.Path), True, True, g * s, 1);
  end;

  { [R2-I5] THE RECT A STATE LAYS THE LABEL ON: the polygon's box grown by
    the pen that state draws (its own borderColor and borderWidth over the
    rest's -- Path.getBoundingRect under the state's style); APenMoves where
    that is not the rest's [was: the rest's rect under every state] }
  function StateRect(const AState: string; out APenMoves: Boolean): TTyXYWH;
  var
    ES: TMkLevels;
    e: TJSONData;
    lw2: Double;
    has2: Boolean;
  begin
    ES := Sub(Sub(lv, AState), 'itemStyle');
    lw2 := P.LineWidth;
    e := Chain(ES, 'borderWidth');
    if e <> nil then lw2 := NumOf(e);
    has2 := ((P.Stroke <> '') or (P.StrokeData <> nil)) and (P.Stroke <> 'none');
    e := Chain(ES, 'borderColor');
    if e <> nil then has2 := not ((e.JSONType = jtString) and (e.AsString = 'none'));
    has2 := has2 and (lw2 > 0);
    APenMoves := (has2 <> hasStroke) or (has2 and (lw2 <> P.LineWidth));
    Result := AreaRect(has2, hasFill, lw2);
  end;

begin
  Result := nil;
  if (not ABlock.Present) or (ABlock.Kind <> mkArea) then Exit;
  s := AIn.Scale;
  if (s <= 0) or IsNan(s) then s := 1;
  own := View1(ABlock.Own);
  master := View2(ABlock.Top, TyMkDefaults(mkArea));
  gts := View2(AIn.TextStyle, GTextDefaults);
  maxZ2 := NegInfinity;
  n := 0;
  SetLength(Result, ABlock.Count);
  for i := 0 to High(ABlock.Areas) do
  begin
    A := ABlock.Areas[i];
    if not A.Survived then Continue;
    P := Default(TTyMkAreaPic);
    P.Item := i;
    { the merged item: the top-left corner's keys, then the bottom-right's }
    SetLength(lv, 3);
    lv[0] := View2(A.LtSrc, A.RbSrc);
    lv[1] := own;
    lv[2] := master;
    IS_ := Sub(lv, 'itemStyle');
    { the fill: the item's when it has one ('transparent' and 'none' kept),
      else the series colour at alpha 0.4 -- nothing at all when that does
      not parse }
    d := Chain(IS_, 'color');
    P.HasFill := True;
    if Truthy(d) then
    begin
      if d.JSONType = jtString then P.Fill := d.AsString else P.FillData := d;
    end
    else if AIn.SeriesColorData <> nil then
      { a gradient is used as it is }
      P.FillData := AIn.SeriesColorData
    else
    begin
      P.Fill := TyMkModifyAlpha(AIn.SeriesColor, 0.4);
      P.HasFill := P.Fill <> '';
    end;
    d := Chain(IS_, 'borderColor');
    if Truthy(d) then
    begin
      if d.JSONType = jtString then P.Stroke := d.AsString else P.StrokeData := d;
    end
    else if AIn.SeriesColorData <> nil then
      P.StrokeData := AIn.SeriesColorData
    else
      P.Stroke := AIn.SeriesColor;
    d := Chain(lv, 'z2');
    if d <> nil then P.Z2 := NumOf(d) else P.Z2 := 0;
    P.Drawn := not A.AllClipped;
    if P.Drawn then
    begin
      for k := 0 to 3 do P.Points[k] := A.Points[k];
      P.Path := nil;
      TyZrMoveTo(P.Path, A.Points[0].X, A.Points[0].Y);
      for k := 1 to 3 do TyZrLineTo(P.Path, A.Points[k].X, A.Points[k].Y);
      TyZrClose(P.Path);
      P.BBox := TyZrBBox(P.Path);
      d := Chain(IS_, 'borderWidth');
      if d <> nil then P.LineWidth := NumOf(d) else P.LineWidth := 1;
      d := Chain(IS_, 'opacity');
      if d <> nil then P.Opacity := NumOf(d) else P.Opacity := 1;
      P.Dash := Chain(IS_, 'borderType');
      d := Chain(IS_, 'borderDashOffset');
      if d <> nil then P.DashOffset := NumOf(d) else P.DashOffset := 0;
      d := Chain(IS_, 'borderCap');
      if d <> nil then P.LineCap := JsStringOf(d) else P.LineCap := 'butt';
      d := Chain(IS_, 'borderJoin');
      if d <> nil then P.LineJoin := JsStringOf(d) else P.LineJoin := '';
      hasStroke := ((P.Stroke <> '') or (P.StrokeData <> nil)) and (P.Stroke <> 'none')
        and (P.LineWidth > 0);
      hasFill := P.HasFill and (P.Fill <> 'none');
      P.Rect := AreaRect(hasStroke, hasFill, P.LineWidth);
      P.GradBox := P.Rect;
      { Math.max(z2 || 0, maxZ2) -- a clipped area does not count }
      if IsNan(P.Z2) then z2v := 0 else z2v := P.Z2;
      if z2v > maxZ2 then maxZ2 := z2v;
      { the label: the name, or the formatter }
      lp := Default(TTyMkPtLabelPic);
      LB := Sub(lv, 'label');
      { [R2-I1] built where a state shows it too (needsCreateText), ignored
        at rest [was: not built] }
      if Truthy(Chain(LB, 'show')) or AnyStateLabelShows(lv) then
      begin
        lp.Present := True;
        lp.Hidden := not Truthy(Chain(LB, 'show'));
        case A.Name.Kind of
          mvkStr: name := A.Name.Str;
          mvkNum: name := TyJsNumberToString(A.Name.Num);
        else
          name := '';
        end;
        fmt := Chain(LB, 'formatter');
        if (fmt <> nil) and (fmt.JSONType = jtString)
          and TyChartIsHandlerRef(fmt.AsString) then
          str := MkHandlerText(fmt.AsString, AIn, 'markArea', name,
            JsStringOf(VGet(lv[0], 'value')), A.DataIndex, 'normal')
        else if (fmt <> nil) and (fmt.JSONType = jtString) then
        begin
          v := VGet(lv[0], 'value');
          if AIn.SeriesName.Kind = mvkUndef then
            str := FormatTpl(fmt.AsString, ['undefined', name, JsStringOf(v)])
          else
            str := FormatTpl(fmt.AsString, [ValString(AIn.SeriesName), name, JsStringOf(v)]);
        end
        else
          str := name;
        lp.HasText := True;
        lp.Text := str;
        { inheritColor: the fill made opaque, black for a gradient }
        if P.FillData <> nil then inherit := '#000'
        else if not P.HasFill then inherit := ''
        else inherit := TyMkModifyAlpha(P.Fill, 1);
        StyleLabel(LB, gts, AIn, s, P.Rect, inherit, hasFill, P.FillData = nil, P.Fill,
          NaN, False, maxZ2, lp);
        { [R2-I1] and under the emphasis textConfig, where it says a key;
          [R2-I3] under the whole emphasis label; [R2-I4] in the words its
          formatter gives }
        hasEt := EmphText(lv, 'emphasis', AIn, 'markArea', name,
          JsStringOf(VGet(lv[0], 'value')), A.DataIndex, et);
        rect2 := StateRect('emphasis', penMoves);
        if EmphLevels(lv, LB, 'emphasis', [], LBE, hold) or hasEt or penMoves then
        begin
          lp2 := lp;
          if hasEt then lp2.Text := et;
          StyleLabel(LBE, gts, AIn, s, rect2, inherit, hasFill,
            P.FillData = nil, P.Fill, NaN, False, maxZ2, lp2);
          lp2.Hold := hold;
          lp2.Hidden := False;
          P.EmphLbl := lp2;
          if lp2.Text <> '' then lp.KeepEmpty := True;
        end;
        { [R2-I5] blur's and select's (the opacity aside -- the states'
          own) }
        for sti := 1 to 2 do
        begin
          if sti = 1 then stName := 'blur' else stName := 'select';
          hasEt := EmphText(lv, stName, AIn, 'markArea', name,
            JsStringOf(VGet(lv[0], 'value')), A.DataIndex, et);
          rect2 := StateRect(stName, penMoves);
          if not (EmphLevels(lv, LB, stName, ['opacity'], LBE, hold) or hasEt or penMoves) then
            Continue;
          lp2 := lp;
          lp2.KeepEmpty := False;
          if hasEt then lp2.Text := et;
          StyleLabel(LBE, gts, AIn, s, rect2, inherit, hasFill,
            P.FillData = nil, P.Fill, NaN, False, maxZ2, lp2);
          lp2.Hold := hold;
          lp2.Hidden := False;
          P.StateLbl[sti] := lp2;
          if lp2.Text <> '' then lp.KeepEmpty := True;
        end;
        if lp.Text <> '' then lp.KeepEmpty := False;
      end;
      P.Lbl := lp;
    end;
    Result[n] := P;
    Inc(n);
    if n >= Length(Result) then Break;
  end;
  SetLength(Result, n);
end;

function TyBuildMarkAreas(const APics: TTyMkAreaPicArray; const ABlock: TTyMkBlock;
  const AInk: TTyMkInk; const AMeasurer: ITyTextMeasurer; AList: TTyPaintList;
  AHostSeries: Integer): Integer;
var
  i, k, first, at: Integer;
  el, lel: TTyChartElement;
  c: TTyChartColor;
  pts: TTyPointFArray;
  g: TTyChartGradient;
  pat: TTyChartPattern;
begin
  Result := 0;
  if AList = nil then Exit;
  for i := 0 to High(APics) do
  begin
    if not APics[i].Drawn then Continue;
    first := AList.Count;
    if IsNan(APics[i].Points[0].X) or IsNan(APics[i].Points[0].Y)
      or IsNan(APics[i].Points[2].X) or IsNan(APics[i].Points[2].Y) then Continue;
    el := Default(TTyChartElement);
    el.Z := Trunc(ABlock.Z);
    el.Z2 := Round(APics[i].Z2);
    el.Silent := True;
    el.Datum := TyChartDatum(-1, -1);
    el.Style.Alpha := 1;
    SetLength(pts, 4);
    for k := 0 to 3 do pts[k] := APics[i].Points[k];
    el.Shape := TyShapePolygon(pts);
    if APics[i].HasFill and (APics[i].Fill <> 'none') and (APics[i].Fill <> '')
      and TyTryParseChartColor(APics[i].Fill, c) then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := c;
    end
    else if APics[i].HasFill and (APics[i].FillData <> nil) then
    begin
      { A GRADIENT OR A PATTERN -- the item's, or the series colour as it is.
        [Batch 105: an object fill drew no fill at all.] }
      if TyTryReadGradient(APics[i].FillData, g) then
      begin
        el.Style.HasFill := True;
        el.Style.FillColor := TyGradientSolid(g);
        el.Style.FillGradient := g;
      end
      else if TyTryReadPattern(APics[i].FillData, pat) then
      begin
        el.Style.HasFill := True;
        el.Style.FillColor := 0;
        el.Style.FillPattern := pat;
      end;
    end;
    if (APics[i].LineWidth > 0) and (APics[i].Stroke <> '') and (APics[i].Stroke <> 'none')
      and TyTryParseChartColor(APics[i].Stroke, c) then
    begin
      el.Style.StrokeColor := c;
      el.Style.StrokeWidthLogical := APics[i].LineWidth;
      el.Style.DashLogical := ResolveDash(APics[i].Dash, APics[i].LineWidth);
      { [R2-I5] a word, measured again against the width a state draws }
      el.Style.DashWord := DashWordOf(APics[i].Dash);
      el.Style.DashOffsetLogical := APics[i].DashOffset;
    end
    else if (APics[i].LineWidth > 0) and (APics[i].Stroke = '')
      and (APics[i].StrokeData <> nil) and TyTryReadGradient(APics[i].StrokeData, g) then
    begin
      el.Style.StrokeColor := TyGradientSolid(g);
      el.Style.StrokeGradient := g;
      el.Style.StrokeWidthLogical := APics[i].LineWidth;
      el.Style.DashLogical := ResolveDash(APics[i].Dash, APics[i].LineWidth);
      el.Style.DashWord := DashWordOf(APics[i].Dash);
      el.Style.DashOffsetLogical := APics[i].DashOffset;
    end;
    { getBoundingRect: the polygon's box grown by its stroke [Batch 105] }
    el.Style.GradBoxSet := True;
    el.Style.GradBox := APics[i].GradBox;
    if not IsNan(APics[i].Opacity) then
      el.Style.Alpha := Max(0.0, Min(1.0, APics[i].Opacity));
    AList.Add(el);
    Inc(Result);
    at := AList.Count;
    Inc(Result, EmitLabel(APics[i].Lbl, ABlock, AInk, AMeasurer, AList));
    { [R2-I1] where the emphasis textConfig puts it }
    if (AList.Count > at) and APics[i].EmphLbl.Present then
    begin
      lel := AList.Element(at);
      StampEmphLayout(lel, APics[i].EmphLbl, ABlock, AInk, AMeasurer);
      AList.SetElement(at, lel);
    end;
    { [R2-I5] and as blur and select lay it out }
    if AList.Count > at then
    begin
      lel := AList.Element(at);
      StampStateTwins(lel, APics[i].StateLbl, ABlock, AInk, AMeasurer);
      AList.SetElement(at, lel);
    end;
    MkTarget(AList, first, ctkMarkArea, AHostSeries,
      ABlock.Areas[APics[i].Item].DataIndex, ABlock.Silent);
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
  GInsideWord := TJSONString.Create('inside');

finalization
  GTopWord.Free;
  GInsideWord.Free;
  GTextDefaults.Free;
end.
