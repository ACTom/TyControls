unit tyControls.AdvChart.VisualMapView;
{$mode objfpc}{$H+}
{ A continuous visualMap's own picture: the bar, its two gradients, the end
  texts, the handles and their labels, the background -- ContinuousView and
  VisualMapView as they lay the component out before anyone touches it. And a
  piecewise one's: an item per piece (its symbol and label), the ends texts,
  stacked by layout.box -- PiecewiseView. [Batch 59.]

  THE ARITHMETIC IS ZRENDER'S, not a picture of it. Where the component sits
  is decided by the bounding rect of what it drew, and that rect is built the
  way zrender builds it: every child's rect through its local transform,
  unioned in insertion order -- the first one with ITSELF, which is why a
  width comes out as (x + w) - x -- a polygon's from its points, a text's
  from the measured line, a handle's from its icon fitted into a box, float32
  at every store (an SVG path's data is a Float32Array; a polygon's is not). Two moments matter and they are not the
  same: the background is sized from the bar drawn over its WHOLE length (the
  "sketch" upstream renders first), the group placed from the final one.

  THE INTERACTION'S GEOMETRY [Batch 116, C7]: _updateView on a dragged
  interval (TyVmContinuousUpdate -- the group stays where the build put it),
  the hover indicator and its label (TyVmIndicatorAt), and what the pointer
  hits: the bar's two polygons under the bar's rounded clip, a handle's pill
  with its pen, a text's rect, a piece's symbol. The control keeps the view's
  state (ContinuousView's own fields) and decides when to call them.

  NOT HERE: a rounded clip of a partial in-range bar (it is clipped to the
  bar's rectangle). The controller's symbolSize IS here: it makes the bar
  a trapezoid and scales the handles. [Batch 56: the bar was always a
  rectangle.] The 6.1.0 build this follows does not push
  overlapping handle labels apart, and neither does this.

  PURE: option in, geometry out, and marks from the geometry. }
interface
uses SysUtils, Math, fpjson,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Layout, tyControls.AdvChart.VisualMap;

type
  { What the component's own option says about how it looks. }
  TTyVmViewSpec = record
    Show: Boolean;
    Horizontal: Boolean;
    Inverse: Boolean;
    { `align`, 'auto' when absent }
    Align: string;
    ItemW, ItemH: Double;
    { CSS order: top, right, bottom, left }
    Padding: array[0..3] of Double;
    TextGap: Double;
    HasText: Boolean;
    Text: array[0..1] of string;
    Calculable: Boolean;
    Precision: Integer;
    Formatter: string;
    Box: TTyRawBox;
    { `handleSize`: a percentage of the item width or a length }
    HandleSize: TTyBoxRaw;
    { the handle icon's path body, `path://` taken off }
    HandleIcon: string;
    { [F6a] an `image://` handle icon, as written ('' none): the thumb is
      the picture, centred to its aspect in the icon box (createSymbol
      with keepAspect), hit over its rect }
    HandleImage: string;
    { handleStyle.borderWidth, doubled as upstream draws it }
    HandleLineWidth: Double;
    BorderWidth: Double;
    Z: Integer;
    { the colours an author may write over the theme's }
    HasContent, HasInactive, HasText_, HasBorder, HasBackground,
      HasHandleStroke: Boolean;
    Content, Inactive: TTyVisualColor;
    TextColour, BorderColour, BackgroundColour, HandleStroke: TTyChartColor;
    FontSize: Integer;
    { PIECEWISE: the item gap, `showLabel` as written, whether a click
      selects (not silent), and textStyle's align / verticalAlign / opacity
      ('' and HasTextOpacity False when unset) }
    Piecewise: Boolean;
    ItemGap: Double;
    HasShowLabel, ShowLabel: Boolean;
    Silent: Boolean;
    TextAlign, TextVAlign: string;
    HasTextOpacity: Boolean;
    TextOpacity: Double;
    { INTERACTION [Batch 116]: realtime, hoverLink (truthy), hoverLinkDataSize
      (0 when falsy), hoverLinkOnHandle (Has False when null or absent: then
      realtime decides), indicatorSize (a percentage of the item width or a
      length), and a click's mode -- single for 'single' and for true }
    Realtime: Boolean;
    HoverLink: Boolean;
    HoverLinkDataSize: Double;
    HasHoverLinkOnHandle, HoverLinkOnHandle: Boolean;
    IndicatorSize: TTyBoxRaw;
    SelectSingle: Boolean;
  end;

  { One text as zrender places it, in the view group's coordinates. }
  TTyVmText = record
    Text: string;
    X, Y: Double;
    AlignH: TTyTextAnchorH;
    AlignV: TTyTextAnchorV;
    W, H: Double;
    Rect: TTyXYWH;
  end;
  TTyVmTextArray = array of TTyVmText;

  TTyVmHandle = record
    { thumb local -> bar local, and thumb local -> view group }
    Local, Thumb: TTyMat2D;
    { the icon's rect in thumb coordinates, and the same grown by the pen }
    PathRect, Rect: TTyXYWH;
    Fill: TTyVisualColor;
    Label_: TTyVmText;
  end;
  TTyVmHandleArray = array of TTyVmHandle;

  { One child of a piecewise view group: an ends text, or a piece's item --
    its symbol in (0, 0, itemWidth, itemHeight) and its label. X, Y: where
    layout.box put the child; Rect: the child's own bounding rect. }
  TTyVmItem = record
    IsText: Boolean;
    PieceIndex: Integer;
    X, Y: Double;
    Rect: TTyXYWH;
    Symbol: string;
    SymbolBox, SymbolRect: TTyXYWH;
    Fill: TTyVisualColor;
    HasLabel: Boolean;
    { the label, or the ends text }
    Label_: TTyVmText;
    LabelOpacity: Double;
  end;
  TTyVmItemArray = array of TTyVmItem;

  TTyVisualMapLayout = record
    Valid: Boolean;
    Index: Integer;
    Horizontal: Boolean;
    { getItemAlign's answer: left/right, or top/bottom }
    ItemAlign: string;
    ItemW, ItemH: Double;
    { the view group's position on the canvas, device px }
    GroupX, GroupY: Double;
    { bar local -> view group }
    Bar: TTyMat2D;
    Interval: array[0..1] of Double;
    HandleEnds: array[0..1] of Double;
    { bar local, and their rects from the float32 path data }
    OutPoints, InPoints: TTyPointFArray;
    OutRect, InRect: TTyXYWH;
    OutStops, InStops: TTyVisualGradStopArray;
    Texts: TTyVmTextArray;
    Handles: TTyVmHandleArray;
    { view group coordinates }
    Background: TTyXYWH;
    BBoxBackground, BBoxPosition: TTyXYWH;
    Show: Boolean;
    { PIECEWISE: the children in drawn order, whether the items carry a
      label, and the ends text in view order }
    Piecewise: Boolean;
    Items: TTyVmItemArray;
    ShowLabel: Boolean;
    EndsText: array[0..1] of string;
    HasEnds: Boolean;
    { device px per CSS px, as the layout was made [Batch 116] }
    Scale: Double;
  end;

  { THE HOVER INDICATOR [Batch 116]: the symbol's place in the bar group
    (x, y), its colour, its box, and the label in the view group }
  TTyVmIndicator = record
    X, Y: Double;
    Fill: TTyVisualColor;
    Size: Double;
    Label_: TTyVmText;
  end;

  { WHAT THE VIEW SHOWS NOW where it is not the layout's [Batch 116]: the
    handles' fills and labels as the element states left them (a state
    restores the style it saved), the labels' opacity, and the indicator }
  TTyVmLiveDraw = record
    Has: Boolean;
    HandleFill: array[0..1] of TTyVisualColor;
    Labels: array[0..1] of TTyVmText;
    LabelOpacity: array[0..1] of Double;
    IndVisible: Boolean;
    IndX, IndY, IndSize: Double;
    IndFill: TTyChartColor;
    IndLabelVisible: Boolean;
    IndLabel: TTyVmText;
  end;

  { the data items one hover link reaches in one series: inner indices }
  TTyVmHoverBatch = record
    SeriesIndex: Integer;
    Inner: TTyIntegerArray;
  end;
  TTyVmHoverBatches = array of TTyVmHoverBatch;

  { ONE VIEW BETWEEN RENDERS [Batch 116]: ContinuousView's own fields --
    the interval and handle ends a drag moves, whether it drags, whether the
    pointer is over the bar group, the last hover link's items, whether the
    indicator has never shown -- its uid (the `from` of its own
    selectDataRange), how many times it was built, and the element states:
    a thumb's hover flag (2 emphasis) and whether the emphasis is applied,
    with the fill it shows and the fill it saved; a handle label's blur flag
    and whether it is applied, with what it shows and what it saved; the
    indicator and its label (the control reads their place and fill from
    their animation bags). Keep: the next update is this view's own
    selectDataRange, which does not rebuild it. }
  TTyVmLive = record
    Alive: Boolean;
    Gen: Integer;
    Uid: string;
    Interval, Ends: array[0..1] of Double;
    Dragging, Hovering, FirstShow, Keep: Boolean;
    HoverIdx: TTyVmHoverBatches;
    ThumbHover: array[0..1] of Integer;
    ThumbEmph: array[0..1] of Boolean;
    ThumbFill, ThumbSaved: array[0..1] of TTyVisualColor;
    LabelBlur, LabelBlurOn: array[0..1] of Boolean;
    Labels, LabelsSaved: array[0..1] of TTyVmText;
    IndVisible, IndLabelVisible: Boolean;
    IndX, IndY, IndSize: Double;
    IndFill: string;
    IndLabel: TTyVmText;
  end;

  TTyVisualMapInk = record
    Text, Border, Background, HandleStroke: TTyChartColor;
    FontName: string;
    FontSizeLogical, FontWeight: Integer;
  end;

function TyVisualMapViewSpecOf(AOption: TTyChartOption;
  AIndex: Integer): TTyVmViewSpec;

{ zrender's bounding rect of a symbol built by createSymbol in ABox: a
  circle's from its arc, a round rect's from its lines and corner arcs, a
  rect's (x + w) - x; anything else is its box }
function TyVmSymbolRect(const ASymbol: string; const ABox: TTyXYWH): TTyXYWH;

{ ContinuousView._buildView through positionGroup. AModel is the completed
  model (its controller visuals colour the bar); AContent the colour a
  controller visual starts from; ACanvasW/H the chart, device px; AScale
  device px per CSS px. }
function TyLayoutVisualMap(const AModel: TTyVisualMapSpec;
  const AView: TTyVmViewSpec; const AContent: TTyVisualColor;
  ACanvasW, ACanvasH, AScale: Double; const AMeasurer: ITyTextMeasurer;
  const AInk: TTyVisualMapInk): TTyVisualMapLayout;
{ [Batch 154] the same with positionGroup's container ARef (device px, the
  canvas' origin nought): createBoxLayoutReference's refContainer -- a
  matrix cell or a calendar day for a visualMap in one. The item align's
  'auto' still reads the canvas (helper.ts getItemAlign's ecSize). }
function TyLayoutVisualMap(const AModel: TTyVisualMapSpec;
  const AView: TTyVmViewSpec; const AContent: TTyVisualColor;
  ACanvasW, ACanvasH: Double; const ARef: TTyXYWH; AScale: Double;
  const AMeasurer: ITyTextMeasurer;
  const AInk: TTyVisualMapInk): TTyVisualMapLayout;

{ The elements, at AOriginX/Y on the canvas. SILENT: the component is not a
  datum. Answers how many were added. }
function TyBuildVisualMapMarks(const ALayout: TTyVisualMapLayout;
  const AView: TTyVmViewSpec; const AInk: TTyVisualMapInk;
  AOriginX, AOriginY: Double; AList: TTyPaintList): Integer;

{ The elements with what the view shows now (ALive) [Batch 116]. }
function TyBuildVisualMapMarks(const ALayout: TTyVisualMapLayout;
  const AView: TTyVmViewSpec; const AInk: TTyVisualMapInk;
  AOriginX, AOriginY: Double; AList: TTyPaintList;
  const ALive: TTyVmLiveDraw): Integer;

{ ---- the interaction [Batch 116] ---- }
{ ContinuousView._updateView on an interval and its handle ends (device px
  along the bar): the in-range bar, its colours and the handles; the
  out-of-range bar, the texts, the background and the group stay. }
procedure TyVmContinuousUpdate(var L: TTyVisualMapLayout;
  const AModel: TTyVisualMapSpec; const AView: TTyVmViewSpec;
  const AContent: TTyVisualColor; AScale: Double;
  const AMeasurer: ITyTextMeasurer; const AInk: TTyVisualMapInk;
  AI0, AI1, AE0, AE1: Double);
{ _showIndicator's geometry: at ACursor (a data value), the label APrefix
  and ATextValue formatted }
function TyVmIndicatorAt(const L: TTyVisualMapLayout;
  const AModel: TTyVisualMapSpec; const AView: TTyVmViewSpec;
  const AContent: TTyVisualColor; AScale: Double;
  const AMeasurer: ITyTextMeasurer; const AInk: TTyVisualMapInk;
  ACursor, ATextValue: Double; const APrefix: string): TTyVmIndicator;
{ a canvas point in the bar group's coordinates, the view group at
  (AGroupX, AGroupY): the inverse of the bar's global transform }
procedure TyVmGlobalToBar(const L: TTyVisualMapLayout; AGroupX, AGroupY, AX, AY: Double;
  out ABX, ABY: Double);
{ a view-group point in the bar group's coordinates }
procedure TyVmToBar(const L: TTyVisualMapLayout; AGX, AGY: Double;
  out ABX, ABY: Double);
{ the bar under a view-group point: 2 the in-range polygon, 1 the
  out-of-range one, 0 neither (or outside the bar's rounded clip) }
function TyVmBarPartAt(const L: TTyVisualMapLayout; AGX, AGY: Double): Integer;
{ a handle's pill and its pen (Path.contain), at a view-group point; AFill
  whether the thumb is filled }
function TyVmThumbContains(const L: TTyVisualMapLayout; const AView: TTyVmViewSpec;
  AHandle: Integer; AFill: Boolean; AGX, AGY: Double): Boolean;
{ a text's rect (BoundingRect.contain, edges in) }
function TyVmTextContains(const AText: TTyVmText; AGX, AGY: Double): Boolean;
{ a piece's symbol at a point of its item's own coordinates }
function TyVmSymbolContains(const AItem: TTyVmItem; AX, AY: Double): Boolean;

{ ---- pieces, exported for the tests ---- }
{ zrender's transformDirection }
function TyVmTransformDirection(const ADir: string; const M: TTyMat2D): string;
{ An icon's `path://` body fitted into ABox keeping its aspect (createSymbol
  with keepAspect): the path's rect afterwards. }
function TyVmIconRect(const APath: string; const ABox: TTyXYWH): TTyXYWH;
{ formatValueText for one number }
function TyVmFormatValue(AValue: Double; APrecision: Integer;
  const AFormatter: string): string;

const
  TyVmDefaultHandleIcon =
    'M-11.39,9.77h0a3.5,3.5,0,0,1-3.5,3.5h-22a3.5,3.5,0,0,1-3.5-3.5h0a3.5,3.5,' +
    '0,0,1,3.5-3.5h22A3.5,3.5,0,0,1-11.39,9.77Z';

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Data, tyControls.AdvChart.Color,
     tyControls.AdvChart.Complete, tyControls.AdvChart.Symbol,
     tyControls.AdvChart.Handlers, tyControls.AdvChart.ZrPath;

{ ==================== small things ==================== }

function Lt(A, B: Double): Boolean;
begin
  Result := not (IsNan(A) or IsNan(B)) and (A < B);
end;

function Gt(A, B: Double): Boolean;
begin
  Result := Lt(B, A);
end;

function XYWH(AX, AY, AW, AH: Double): TTyXYWH;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

function MatIdentity: TTyMat2D;
begin
  Result[0] := 1; Result[1] := 0; Result[2] := 0;
  Result[3] := 1; Result[4] := 0; Result[5] := 0;
end;

{ matrix.mul(out, a, b): a after b }
function MatMul(const A, B: TTyMat2D): TTyMat2D;
begin
  Result[0] := A[0] * B[0] + A[2] * B[1];
  Result[1] := A[1] * B[0] + A[3] * B[1];
  Result[2] := A[0] * B[2] + A[2] * B[3];
  Result[3] := A[1] * B[2] + A[3] * B[3];
  Result[4] := A[0] * B[4] + A[2] * B[5] + A[4];
  Result[5] := A[1] * B[4] + A[3] * B[5] + A[5];
end;

procedure MatApply(const M: TTyMat2D; AX, AY: Double; out OX, OY: Double);
begin
  OX := M[0] * AX + M[2] * AY + M[4];
  OY := M[1] * AX + M[3] * AY + M[5];
end;

{ Group.getBoundingRect's accumulation: the first child's rect unioned with
  itself, every later one with the running rect. }
procedure Accumulate(var ARect: TTyXYWH; var AHave: Boolean;
  const AChild: TTyXYWH; const M: TTyMat2D);
var t: TTyXYWH;
begin
  t := TyRectApplyMat(AChild, M);
  if not AHave then
  begin
    ARect := t;
    AHave := True;
  end;
  ARect := TyRectUnion(ARect, t);
end;

function ObjOf(A: TJSONData): TJSONObject;
begin
  if (A <> nil) and (A.JSONType = jtObject) then Result := TJSONObject(A)
  else Result := nil;
end;

function JsTruthyOf(A: TJSONData): Boolean;
begin
  if A = nil then Exit(False);
  case A.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := A.AsBoolean;
    jtNumber: Result := (A.AsFloat <> 0) and not IsNan(A.AsFloat);
    jtString: Result := A.AsString <> '';
  else
    Result := True;
  end;
end;

{ parseFloat of an option value: a number as is, a string's prefix }
function ParseFloatOf(A: TJSONData): Double;
begin
  Result := NaN;
  if A = nil then Exit;
  case A.JSONType of
    jtNumber: Result := A.AsFloat;
    jtString: Result := TyJsParseFloat(A.AsString);
  end;
end;

{ ==================== the spec ==================== }

function TyVisualMapViewSpecOf(AOption: TTyChartOption;
  AIndex: Integer): TTyVmViewSpec;
var
  node, ts, hs: TJSONObject;
  d: TJSONData;
  arr: TJSONArray;
  def: TTyRawBox;
  c: TTyChartColor;
  n, i: Integer;
  v: array[0..3] of Double;
begin
  Result := Default(TTyVmViewSpec);
  Result.Show := False;
  Result.Align := 'auto';
  Result.ItemW := 20;
  Result.ItemH := 140;
  for i := 0 to 3 do Result.Padding[i] := 15;
  Result.TextGap := 10;
  Result.HandleSize := TyBoxRawStr('120%');
  Result.HandleIcon := TyVmDefaultHandleIcon;
  Result.HandleLineWidth := 2;
  Result.Z := 4;
  Result.ItemGap := 10;
  Result.Realtime := True;
  Result.HoverLink := True;
  Result.IndicatorSize := TyBoxRawStr('50%');
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('visualMap', AIndex));
  if node = nil then Exit;
  { the subtype, as the model decides it }
  d := node.Find('type');
  if (d <> nil) and (d.JSONType = jtString) then
    Result.Piecewise := d.AsString = 'piecewise'
  else
    Result.Piecewise := TyOptDefaultSubType('visualMap', node) = 'piecewise';
  d := node.Find('show');
  Result.Show := not ((d <> nil) and (d.JSONType = jtBoolean) and not d.AsBoolean);
  d := node.Find('orient');
  Result.Horizontal := (d <> nil) and (d.JSONType = jtString)
    and (d.AsString = 'horizontal');
  d := node.Find('inverse');
  Result.Inverse := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
  d := node.Find('align');
  if (d <> nil) and (d.JSONType = jtString) then Result.Align := d.AsString;
  { resetItemSize: parseFloat of each, NaN falling back to the defaults --
    20 x 140 continuous, 20 x 14 piecewise }
  Result.ItemW := ParseFloatOf(node.Find('itemWidth'));
  if IsNan(Result.ItemW) then Result.ItemW := 20;
  Result.ItemH := ParseFloatOf(node.Find('itemHeight'));
  if IsNan(Result.ItemH) then
    if Result.Piecewise then Result.ItemH := 14 else Result.ItemH := 140;
  d := node.Find('itemGap');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.ItemGap := d.AsFloat;
  { showLabel read without its parent; selectedMode falsy is silent }
  d := node.Find('showLabel');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    Result.HasShowLabel := True;
    Result.ShowLabel := JsTruthyOf(d);
  end;
  d := node.Find('selectedMode');
  Result.Silent := (d <> nil) and not JsTruthyOf(d);
  { _onItemClick: 'single' or true picks one, anything else truthy toggles }
  Result.SelectSingle := (d <> nil) and (((d.JSONType = jtString) and (d.AsString = 'single'))
    or ((d.JSONType = jtBoolean) and d.AsBoolean));
  { [Batch 116] the interaction's switches }
  d := node.Find('realtime');
  if d <> nil then Result.Realtime := JsTruthyOf(d);
  d := node.Find('hoverLink');
  if d <> nil then Result.HoverLink := JsTruthyOf(d);
  d := node.Find('hoverLinkDataSize');
  if (d <> nil) and (d.JSONType = jtNumber) and JsTruthyOf(d) then
    Result.HoverLinkDataSize := d.AsFloat;
  d := node.Find('hoverLinkOnHandle');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    Result.HasHoverLinkOnHandle := True;
    Result.HoverLinkOnHandle := JsTruthyOf(d);
  end;
  d := node.Find('indicatorSize');
  if d <> nil then Result.IndicatorSize := TyBoxRawOf(d);
  { normalizeCssArray(padding || 0) }
  d := node.Find('padding');
  if d <> nil then
  begin
    if d.JSONType = jtNumber then
      for i := 0 to 3 do Result.Padding[i] := d.AsFloat
    else if d.JSONType = jtArray then
    begin
      arr := TJSONArray(d);
      n := arr.Count;
      for i := 0 to 3 do v[i] := NaN;
      for i := 0 to Min(n, 4) - 1 do
        if arr.Items[i].JSONType = jtNumber then v[i] := arr.Items[i].AsFloat;
      if n = 2 then begin v[2] := v[0]; v[3] := v[1]; end
      else if n = 3 then v[3] := v[1];
      for i := 0 to 3 do Result.Padding[i] := v[i];
    end
    else if (d.JSONType = jtNull) or ((d.JSONType = jtBoolean) and not d.AsBoolean) then
      for i := 0 to 3 do Result.Padding[i] := 0;
  end;
  d := node.Find('textGap');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.TextGap := d.AsFloat;
  d := node.Find('text');
  if (d <> nil) and (d.JSONType = jtArray) then
  begin
    Result.HasText := True;
    arr := TJSONArray(d);
    for i := 0 to 1 do
      if (i < arr.Count) and (arr.Items[i].JSONType in [jtString, jtNumber]) then
        Result.Text[i] := arr.Items[i].AsString;
  end;
  d := node.Find('calculable');
  Result.Calculable := (d <> nil) and (d.JSONType = jtBoolean) and d.AsBoolean;
  d := node.Find('precision');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Precision := Trunc(d.AsFloat);
  d := node.Find('formatter');
  if (d <> nil) and (d.JSONType = jtString) then Result.Formatter := d.AsString;
  { the box, merged the way a component laid out at init merges it:
    left 0 and bottom 0 by default }
  def := Default(TTyRawBox);
  def.Left := TyBoxRawNum(0);
  def.Right.Kind := brNull;
  def.Top.Kind := brNull;
  def.Bottom := TyBoxRawNum(0);
  Result.Box := TyMergeBoxIgnoreSize(node, def);
  d := node.Find('handleSize');
  if d <> nil then Result.HandleSize := TyBoxRawOf(d);
  d := node.Find('handleIcon');
  if (d <> nil) and (d.JSONType = jtString) and (Copy(d.AsString, 1, 7) = 'path://') then
    Result.HandleIcon := Copy(d.AsString, 8, MaxInt);
  if (d <> nil) and (d.JSONType = jtString) and (Copy(d.AsString, 1, 8) = 'image://') then
    Result.HandleImage := d.AsString;
  hs := ObjOf(node.Find('handleStyle'));
  if hs <> nil then
  begin
    d := hs.Find('borderWidth');
    if (d <> nil) and (d.JSONType = jtNumber) then
      Result.HandleLineWidth := d.AsFloat * 2;
    d := hs.Find('borderColor');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    begin
      Result.HasHandleStroke := True;
      Result.HandleStroke := c;
    end;
  end;
  d := node.Find('borderWidth');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.BorderWidth := d.AsFloat;
  d := node.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Z := Trunc(d.AsFloat);
  { THE AUTHOR'S COLOURS, where written; the theme's otherwise }
  d := node.Find('contentColor');
  if (d <> nil) and (d.JSONType = jtString) then
    Result.HasContent := TyVisualTryParse(d.AsString, Result.Content);
  d := node.Find('inactiveColor');
  if (d <> nil) and (d.JSONType = jtString) then
    Result.HasInactive := TyVisualTryParse(d.AsString, Result.Inactive);
  d := node.Find('borderColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
  begin
    Result.HasBorder := True;
    Result.BorderColour := c;
  end;
  d := node.Find('backgroundColor');
  if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
  begin
    Result.HasBackground := True;
    Result.BackgroundColour := c;
  end;
  ts := ObjOf(node.Find('textStyle'));
  if ts <> nil then
  begin
    d := ts.Find('color');
    if (d <> nil) and (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, c) then
    begin
      Result.HasText_ := True;
      Result.TextColour := c;
    end;
    d := ts.Find('fontSize');
    Result.FontSize := TyOptFontSize(d, Result.FontSize);
    d := ts.Find('align');
    if (d <> nil) and (d.JSONType = jtString) then Result.TextAlign := d.AsString;
    d := ts.Find('verticalAlign');
    if (d <> nil) and (d.JSONType = jtString) then Result.TextVAlign := d.AsString;
    d := ts.Find('opacity');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      Result.HasTextOpacity := True;
      Result.TextOpacity := d.AsFloat;
    end;
  end;
end;

{ ==================== the icon's path ==================== }

type
  TZrCmd = (zcM, zcL, zcC, zcQ, zcA, zcZ);
  TZrSeg = record
    Cmd: TZrCmd;
    V: array[0..7] of Double;
  end;
  TZrSegArray = array of TZrSeg;

procedure AddSeg(var ASegs: TZrSegArray; ACmd: TZrCmd;
  const AV: array of Double);
var n, i: Integer;
begin
  n := Length(ASegs);
  SetLength(ASegs, n + 1);
  ASegs[n].Cmd := ACmd;
  for i := 0 to 7 do ASegs[n].V[i] := 0;
  for i := 0 to High(AV) do ASegs[n].V[i] := AV[i];
end;

function SegLen(ACmd: TZrCmd): Integer;
begin
  case ACmd of
    zcM, zcL: Result := 3;
    zcC: Result := 7;
    zcQ: Result := 5;
    zcA: Result := 9;
  else
    Result := 1;
  end;
end;

function VMag(AX, AY: Double): Double;
begin
  Result := Sqrt(AX * AX + AY * AY);
end;

function VRatio(UX, UY, VX, VY: Double): Double;
begin
  Result := (UX * VX + UY * VY) / (VMag(UX, UY) * VMag(VX, VY));
end;

{ Math.acos, NaN outside [-1, 1] }
function JsAcos(AX: Double): Double;
begin
  if IsNan(AX) or (AX > 1) or (AX < -1) then Exit(NaN);
  if AX = 1 then Exit(0);
  if AX = -1 then Exit(Pi);
  if AX = 0 then Exit(1.5707963267948966);
  Result := ArcCos(AX);
end;

function VAngle(UX, UY, VX, VY: Double): Double;
var s: Double;
begin
  if UX * VY < UY * VX then s := -1 else s := 1;
  Result := s * JsAcos(VRatio(UX, UY, VX, VY));
end;

{ path.ts processArc }
procedure ProcessArc(var ASegs: TZrSegArray; X1, Y1, X2, Y2, FA, FS, RX, RY,
  PsiDeg: Double);
var
  psi, xp, yp, lambda, f, num, cxp, cyp, cx, cy, theta, dTheta, ux, uy, vx,
    vy, n: Double;
begin
  psi := PsiDeg * (Pi / 180.0);
  xp := TyJsCos(psi) * (X1 - X2) / 2.0 + TyJsSin(psi) * (Y1 - Y2) / 2.0;
  yp := -1 * TyJsSin(psi) * (X1 - X2) / 2.0 + TyJsCos(psi) * (Y1 - Y2) / 2.0;
  lambda := (xp * xp) / (RX * RX) + (yp * yp) / (RY * RY);
  if lambda > 1 then
  begin
    RX := RX * Sqrt(lambda);
    RY := RY * Sqrt(lambda);
  end;
  num := (((RX * RX) * (RY * RY)) - ((RX * RX) * (yp * yp))
    - ((RY * RY) * (xp * xp))) / ((RX * RX) * (yp * yp) + (RY * RY) * (xp * xp));
  { `Math.sqrt(...) || 0`: a NaN (a negative under the root) is nought }
  if IsNan(num) or (num < 0) then f := 0 else f := Sqrt(num);
  if FA = FS then f := -f;
  cxp := f * RX * yp / RY;
  cyp := f * -RY * xp / RX;
  cx := (X1 + X2) / 2.0 + TyJsCos(psi) * cxp - TyJsSin(psi) * cyp;
  cy := (Y1 + Y2) / 2.0 + TyJsSin(psi) * cxp + TyJsCos(psi) * cyp;
  theta := VAngle(1, 0, (xp - cxp) / RX, (yp - cyp) / RY);
  ux := (xp - cxp) / RX;
  uy := (yp - cyp) / RY;
  vx := (-1 * xp - cxp) / RX;
  vy := (-1 * yp - cyp) / RY;
  dTheta := VAngle(ux, uy, vx, vy);
  if VRatio(ux, uy, vx, vy) <= -1 then dTheta := Pi;
  if VRatio(ux, uy, vx, vy) >= 1 then dTheta := 0;
  if dTheta < 0 then
  begin
    n := TyJsRound(dTheta / Pi * 1e6) / 1e6;
    dTheta := Pi * 2 + (n - 2 * Int(n / 2)) * Pi;
  end;
  AddSeg(ASegs, zcA, [cx, cy, RX, RY, theta, dTheta, psi, FS]);
end;

{ createPathProxyFromString: the commands, then toStatic -- a Float32Array
  when the data runs past eleven numbers. AFloat32 says whether it did. }
function ParsePath(const S: string; out AFloat32: Boolean): TZrSegArray;
var
  i, n, off, total, k: Integer;
  ch, cmdStr: Char;
  body: string;
  p: array of Double;
  cpx, cpy, subX, subY, x1, y1, ctlX, ctlY, rx, ry, psi, fa, fs: Double;
  prev: TZrCmd;
  havePrev: Boolean;
  cmd: TZrCmd;

  function IsCmd(C: Char): Boolean;
  begin
    Result := Pos(LowerCase(C), 'mlvhzcqtsa') > 0;
  end;

  { numberReg: -?([0-9]*\.)?[0-9]+([eE]-?[0-9]+)? }
  procedure Numbers(const B: string);
  var j, st, m: Integer; t: string;
  begin
    p := nil;
    j := 1;
    while j <= Length(B) do
    begin
      st := j;
      if (B[j] = '-') then Inc(j);
      m := j;
      while (j <= Length(B)) and (B[j] in ['0'..'9']) do Inc(j);
      if (j <= Length(B)) and (B[j] = '.') then
      begin
        Inc(j);
        m := j;
        while (j <= Length(B)) and (B[j] in ['0'..'9']) do Inc(j);
      end;
      if j = m then
      begin
        { no digits here: not a number, move on one }
        j := st + 1;
        Continue;
      end;
      if (j <= Length(B)) and (B[j] in ['e', 'E']) then
      begin
        m := j + 1;
        if (m <= Length(B)) and (B[m] = '-') then Inc(m);
        if (m <= Length(B)) and (B[m] in ['0'..'9']) then
        begin
          j := m;
          while (j <= Length(B)) and (B[j] in ['0'..'9']) do Inc(j);
        end;
      end;
      t := Copy(B, st, j - st);
      SetLength(p, Length(p) + 1);
      p[High(p)] := TyJsParseFloat(t);
    end;
  end;

  function PV: Double;
  begin
    if off <= High(p) then Result := p[off] else Result := NaN;
    Inc(off);
  end;

begin
  Result := nil;
  AFloat32 := False;
  cpx := 0; cpy := 0; subX := 0; subY := 0;
  havePrev := False;
  prev := zcM;
  cmd := zcM;
  i := 1;
  while i <= Length(S) do
  begin
    ch := S[i];
    if not IsCmd(ch) then
    begin
      Inc(i);
      Continue;
    end;
    k := i + 1;
    while (k <= Length(S)) and not IsCmd(S[k]) do Inc(k);
    body := Copy(S, i + 1, k - i - 1);
    i := k;
    cmdStr := ch;
    Numbers(body);
    off := 0;
    while off < Length(p) do
    begin
      x1 := cpx;
      y1 := cpy;
      case cmdStr of
        'l': begin cpx := cpx + PV; cpy := cpy + PV; cmd := zcL; AddSeg(Result, zcL, [cpx, cpy]); end;
        'L': begin cpx := PV; cpy := PV; cmd := zcL; AddSeg(Result, zcL, [cpx, cpy]); end;
        'm': begin cpx := cpx + PV; cpy := cpy + PV; cmd := zcM; AddSeg(Result, zcM, [cpx, cpy]);
               subX := cpx; subY := cpy; cmdStr := 'l'; end;
        'M': begin cpx := PV; cpy := PV; cmd := zcM; AddSeg(Result, zcM, [cpx, cpy]);
               subX := cpx; subY := cpy; cmdStr := 'L'; end;
        'h': begin cpx := cpx + PV; cmd := zcL; AddSeg(Result, zcL, [cpx, cpy]); end;
        'H': begin cpx := PV; cmd := zcL; AddSeg(Result, zcL, [cpx, cpy]); end;
        'v': begin cpy := cpy + PV; cmd := zcL; AddSeg(Result, zcL, [cpx, cpy]); end;
        'V': begin cpy := PV; cmd := zcL; AddSeg(Result, zcL, [cpx, cpy]); end;
        'C':
          begin
            cmd := zcC;
            AddSeg(Result, zcC, [PV, PV, PV, PV, PV, PV]);
            cpx := Result[High(Result)].V[4];
            cpy := Result[High(Result)].V[5];
          end;
        'c':
          begin
            cmd := zcC;
            x1 := PV + cpx; y1 := PV + cpy;
            ctlX := PV + cpx; ctlY := PV + cpy;
            rx := PV; ry := PV;
            AddSeg(Result, zcC, [x1, y1, ctlX, ctlY, rx + cpx, ry + cpy]);
            cpx := cpx + rx;
            cpy := cpy + ry;
          end;
        'S', 's':
          begin
            ctlX := cpx;
            ctlY := cpy;
            if havePrev and (prev = zcC) and (Length(Result) > 0) then
            begin
              ctlX := ctlX + cpx - Result[High(Result)].V[2];
              ctlY := ctlY + cpy - Result[High(Result)].V[3];
            end;
            cmd := zcC;
            if cmdStr = 'S' then
            begin
              x1 := PV; y1 := PV; cpx := PV; cpy := PV;
            end
            else
            begin
              x1 := cpx + PV; y1 := cpy + PV;
              rx := PV; ry := PV;
              cpx := cpx + rx; cpy := cpy + ry;
            end;
            AddSeg(Result, zcC, [ctlX, ctlY, x1, y1, cpx, cpy]);
          end;
        'Q':
          begin
            x1 := PV; y1 := PV; cpx := PV; cpy := PV;
            cmd := zcQ;
            AddSeg(Result, zcQ, [x1, y1, cpx, cpy]);
          end;
        'q':
          begin
            x1 := PV + cpx; y1 := PV + cpy;
            rx := PV; ry := PV;
            cpx := cpx + rx; cpy := cpy + ry;
            cmd := zcQ;
            AddSeg(Result, zcQ, [x1, y1, cpx, cpy]);
          end;
        'T', 't':
          begin
            ctlX := cpx;
            ctlY := cpy;
            if havePrev and (prev = zcQ) and (Length(Result) > 0) then
            begin
              ctlX := ctlX + cpx - Result[High(Result)].V[0];
              ctlY := ctlY + cpy - Result[High(Result)].V[1];
            end;
            if cmdStr = 'T' then begin cpx := PV; cpy := PV; end
            else begin rx := PV; ry := PV; cpx := cpx + rx; cpy := cpy + ry; end;
            cmd := zcQ;
            AddSeg(Result, zcQ, [ctlX, ctlY, cpx, cpy]);
          end;
        'A', 'a':
          begin
            rx := PV; ry := PV; psi := PV; fa := PV; fs := PV;
            x1 := cpx; y1 := cpy;
            if cmdStr = 'A' then begin cpx := PV; cpy := PV; end
            else begin cpx := cpx + PV; cpy := cpy + PV; end;
            cmd := zcA;
            ProcessArc(Result, x1, y1, cpx, cpy, fa, fs, rx, ry, psi);
          end;
      else
        off := Length(p);
      end;
    end;
    if cmdStr in ['z', 'Z'] then
    begin
      cmd := zcZ;
      AddSeg(Result, zcZ, []);
      cpx := subX;
      cpy := subY;
    end;
    prev := cmd;
    havePrev := True;
  end;
  { toStatic }
  total := 0;
  for n := 0 to High(Result) do Inc(total, SegLen(Result[n].Cmd));
  if total > 11 then
  begin
    AFloat32 := True;
    for n := 0 to High(Result) do
      for k := 0 to 7 do Result[n].V[k] := TyJsFround(Result[n].V[k]);
  end;
end;

{ PathProxy.getBoundingRect, which is ZrPath's: a curve's box is its
  extrema (bbox.fromCubic / fromQuadratic), not its control points. This unit
  kept a copy that took the control points, so a custom icon whose curves
  bulge less than their handles was fitted into its box too small and drawn
  off-centre. [F1b: dataZoom had already moved to TyZrBBox.] }
function PathRect(const ASegs: TZrSegArray): TTyXYWH;
const
  cCmd: array[TZrCmd] of TTyZrCmd = (zrM, zrL, zrC, zrQ, zrA, zrZ);
var
  p: TTyZrPath;
  i, k: Integer;
begin
  SetLength(p, Length(ASegs));
  for i := 0 to High(ASegs) do
  begin
    p[i].Cmd := cCmd[ASegs[i].Cmd];
    for k := 0 to 7 do p[i].V[k] := ASegs[i].V[k];
  end;
  Result := TyZrBBox(p);
end;

{ transformPath, each store a float32 one when the data is }
procedure TransformSegs(var ASegs: TZrSegArray; const M: TTyMat2D;
  AFloat32: Boolean);
var
  i, k, n: Integer;
  sx, sy, angle, x, y: Double;

  function St(A: Double): Double;
  begin
    if AFloat32 then Result := TyJsFround(A) else Result := A;
  end;

begin
  for i := 0 to High(ASegs) do
    case ASegs[i].Cmd of
      zcM, zcL, zcC, zcQ:
        begin
          case ASegs[i].Cmd of
            zcC: n := 3;
            zcQ: n := 2;
          else
            n := 1;
          end;
          for k := 0 to n - 1 do
          begin
            x := ASegs[i].V[2 * k];
            y := ASegs[i].V[2 * k + 1];
            ASegs[i].V[2 * k] := St(M[0] * x + M[2] * y + M[4]);
            ASegs[i].V[2 * k + 1] := St(M[1] * x + M[3] * y + M[5]);
          end;
        end;
      zcA:
        begin
          sx := Sqrt(M[0] * M[0] + M[1] * M[1]);
          sy := Sqrt(M[2] * M[2] + M[3] * M[3]);
          angle := TyJsAtan2(-M[1] / sy, M[0] / sx);
          { `data[i] *= sx; data[i] += x`: two stores }
          ASegs[i].V[0] := St(St(ASegs[i].V[0] * sx) + M[4]);
          ASegs[i].V[1] := St(St(ASegs[i].V[1] * sy) + M[5]);
          ASegs[i].V[2] := St(ASegs[i].V[2] * sx);
          ASegs[i].V[3] := St(ASegs[i].V[3] * sy);
          ASegs[i].V[4] := St(ASegs[i].V[4] + angle);
          ASegs[i].V[5] := St(ASegs[i].V[5] + angle);
        end;
    end;
end;

function TyVmIconRect(const APath: string; const ABox: TTyXYWH): TTyXYWH;
var
  segs: TZrSegArray;
  f32: Boolean;
  r, fit: TTyXYWH;
  aspect, w, h, cx, cy, sx, sy: Double;
  m: TTyMat2D;
begin
  segs := ParsePath(APath, f32);
  r := PathRect(segs);
  { centerGraphic: the box, keeping the path's own proportions }
  aspect := r.W / r.H;
  w := ABox.H * aspect;
  if w <= ABox.W then
    h := ABox.H
  else
  begin
    w := ABox.W;
    h := w / aspect;
  end;
  cx := ABox.X + ABox.W / 2;
  cy := ABox.Y + ABox.H / 2;
  fit := XYWH(cx - w / 2, cy - h / 2, w, h);
  { BoundingRect.calculateTransform: translate, scale, translate }
  sx := fit.W / r.W;
  sy := fit.H / r.H;
  m := MatIdentity;
  m[4] := 0 + -r.X;
  m[5] := 0 + -r.Y;
  m[0] := m[0] * sx; m[1] := m[1] * sy;
  m[2] := m[2] * sx; m[3] := m[3] * sy;
  m[4] := m[4] * sx; m[5] := m[5] * sy;
  m[4] := m[4] + fit.X;
  m[5] := m[5] + fit.Y;
  TransformSegs(segs, m, f32);
  Result := PathRect(segs);
end;

function TyVmSymbolRect(const ASymbol: string; const ABox: TTyXYWH): TTyXYWH;
var
  segs: TZrSegArray;
  x, y, w, h, r, cx, cy: Double;

  procedure Seg(ACmd: TZrCmd; const AV: array of Double);
  var k, n: Integer;
  begin
    n := Length(segs);
    SetLength(segs, n + 1);
    segs[n] := Default(TZrSeg);
    segs[n].Cmd := ACmd;
    for k := 0 to High(AV) do segs[n].V[k] := AV[k];
  end;

  { PathProxy.arc: centre, radii, the start and the SWEEP, clockwise }
  procedure Arc(ACX, ACY, AR, AStart, AEnd: Double);
  begin
    Seg(zcA, [ACX, ACY, AR, AR, AStart, AEnd - AStart, 0, 1]);
  end;

begin
  x := ABox.X;
  y := ABox.Y;
  w := ABox.W;
  h := ABox.H;
  segs := nil;
  if ASymbol = 'circle' then
  begin
    { symbolShapeMakers.circle: r = min(w, h) / 2 about the box's centre;
      Circle.buildPath moves to (cx + r, cy) and arcs the whole turn }
    cx := x + w / 2;
    cy := y + h / 2;
    r := Min(w, h) / 2;
    Seg(zcM, [cx + r, cy]);
    Arc(cx, cy, r, 0, Pi * 2);
    Exit(PathRect(segs));
  end;
  if ASymbol = 'roundRect' then
  begin
    { r = min(w, h) / 4; roundRectHelper's lines and quarter arcs }
    r := Min(w, h) / 4;
    Seg(zcM, [x + r, y]);
    Seg(zcL, [x + w - r, y]);
    if r <> 0 then Arc(x + w - r, y + r, r, -Pi / 2, 0);
    Seg(zcL, [x + w, y + h - r]);
    if r <> 0 then Arc(x + w - r, y + h - r, r, 0, Pi / 2);
    Seg(zcL, [x + r, y + h]);
    if r <> 0 then Arc(x + r, y + h - r, r, Pi / 2, Pi);
    Seg(zcL, [x, y + r]);
    if r <> 0 then Arc(x + r, y + r, r, Pi, Pi * 1.5);
    Exit(PathRect(segs));
  end;
  { a rect path, and every other shape's own box }
  Result := XYWH(x, y, (x + w) - x, (y + h) - y);
end;

{ ==================== texts ==================== }

function AdjustX(AX, AW: Double; AAlign: TTyTextAnchorH): Double;
begin
  case AAlign of
    tahRight: Result := AX - AW;
    tahCentre: Result := AX - AW / 2;
  else
    Result := AX;
  end;
end;

function AdjustY(AY, AH: Double; AAlign: TTyTextAnchorV): Double;
begin
  case AAlign of
    tavMiddle: Result := AY - AH / 2;
    tavBottom: Result := AY - AH;
  else
    Result := AY;
  end;
end;

{ One line of text as zrender places it: the TSpan at the line's middle, and
  the Text's rect that span's rect unioned with itself. }
function MakeText(const AText: string; AX, AY: Double; AH: TTyTextAnchorH;
  AV: TTyTextAnchorV; const AMeasurer: ITyTextMeasurer;
  const AInk: TTyVisualMapInk): TTyVmText;
var
  w, h, ty: Double;
  r: TTyXYWH;
begin
  Result := Default(TTyVmText);
  Result.Text := AText;
  Result.X := AX;
  Result.Y := AY;
  Result.AlignH := AH;
  Result.AlignV := AV;
  w := 0;
  h := 0;
  if AMeasurer <> nil then
    AMeasurer.MeasureLine(AText, AInk.FontName, AInk.FontSizeLogical,
      AInk.FontWeight, w, h);
  Result.W := w;
  Result.H := h;
  ty := AdjustY(AY, h, AV) + h / 2;
  r := XYWH(AdjustX(AX, w, AH), ty - h / 2, w, h);
  Result.Rect := TyRectUnion(r, r);
end;

function WordH(const A: string): TTyTextAnchorH;
begin
  if A = 'right' then Result := tahRight
  else if A = 'center' then Result := tahCentre
  else Result := tahLeft;
end;

function WordV(const A: string): TTyTextAnchorV;
begin
  if A = 'bottom' then Result := tavBottom
  else if A = 'middle' then Result := tavMiddle
  else Result := tavTop;
end;

function TyVmTransformDirection(const ADir: string; const M: TTyMat2D): string;
var hBase, vBase, x, y, ox, oy: Double;
begin
  if (M[4] = 0) or (M[5] = 0) or (M[0] = 0) then hBase := 1
  else hBase := Abs(2 * M[4] / M[0]);
  if (M[4] = 0) or (M[5] = 0) or (M[2] = 0) then vBase := 1
  else vBase := Abs(2 * M[4] / M[2]);
  x := 0;
  y := 0;
  if ADir = 'left' then x := -hBase else if ADir = 'right' then x := hBase;
  if ADir = 'top' then y := -vBase else if ADir = 'bottom' then y := vBase;
  MatApply(M, x, y, ox, oy);
  if Abs(ox) > Abs(oy) then
  begin
    if ox > 0 then Result := 'right' else Result := 'left';
  end
  else if oy > 0 then Result := 'bottom'
  else Result := 'top';
end;

function TyVmFormatValue(AValue: Double; APrecision: Integer;
  const AFormatter: string): string;
var
  s: string;
  p: Integer;
  prm: TTyChartCallbackParams;
begin
  { a named handler is given the handle's value, upstream's formatter(value) }
  if TyChartIsHandlerRef(AFormatter) then
  begin
    prm := TyChartBlankParams;
    prm.ComponentType := 'visualMap';
    SetLength(prm.Values, 1);
    prm.Values[0] := AValue;
    prm.ValueText := TyChartValueText(AValue);
    Exit(TyChartRunHandler(AFormatter, TyChartOneParams(prm)));
  end;
  if IsInfinite(AValue) and (AValue < 0) then s := 'min'
  else if IsInfinite(AValue) then s := 'max'
  else s := TyJsToFixedStr(AValue, Min(APrecision, 20));
  if AFormatter = '' then Exit(s);
  Result := AFormatter;
  p := Pos('{value}', Result);
  if p > 0 then Result := Copy(Result, 1, p - 1) + s + Copy(Result, p + 7, MaxInt);
  p := Pos('{value2}', Result);
  if p > 0 then Result := Copy(Result, 1, p - 1) + s + Copy(Result, p + 8, MaxInt);
end;

{ ==================== the layout ==================== }

{ getControllerVisual(v, 'color', {forceState, convertOpacityToAlpha}) }
function ControllerColour(const AModel: TTyVisualMapSpec; AState: TTyVisualState;
  AValue: Double; const AContent: TTyVisualColor): TTyVisualColor;
var
  s: TTyVisualMapSpec;
  row: TTyVisualRow;
begin
  s := AModel;
  s.States := AModel.Controller;
  row := Default(TTyVisualRow);
  row.Color := AContent;
  TyVisualApply(s, AState, AValue, row, True);
  Result := row.Color;
end;

{ _makeColorGradient: 101 samples, MULTIPLIED from the start }
function ColourStops(const AModel: TTyVisualMapSpec; AState: TTyVisualState;
  A0, A1: Double; const AContent: TTyVisualColor): TTyVisualGradStopArray;
var
  step, v: Double;
  i, n: Integer;

  procedure Push(AV, AOffset: Double);
  begin
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n] := Default(TTyVisualGradStop);
    Result[n].Offset := AOffset;
    Result[n].Coord := AV;
    Result[n].Color := ControllerColour(AModel, AState, AV, AContent);
  end;

begin
  Result := nil;
  step := (A1 - A0) / 100;
  Push(A0, 0);
  for i := 1 to 99 do
  begin
    v := A0 + step * i;
    if Gt(v, A1) then Break;
    Push(v, i / 100);
  end;
  Push(A1, 1);
end;

{ getControllerVisual(v, 'symbolSize', {forceState}), CSS px }
function ControllerSize(const AModel: TTyVisualMapSpec; AState: TTyVisualState;
  AValue, AItemW: Double): Double;
var
  s: TTyVisualMapSpec;
  row: TTyVisualRow;
begin
  s := AModel;
  s.States := AModel.Controller;
  row := Default(TTyVisualRow);
  TyVisualApply(s, AState, AValue, row, False);
  if row.SizeSet then Result := row.Size else Result := AItemW;
end;

{ _createBarPoints: the controller's size at each end narrows the bar from
  the item's own edge }
function BarPoints(AItemW, ASize0, ASize1, AE0, AE1: Double): TTyPointFArray;
begin
  SetLength(Result, 4);
  Result[0] := TyPointF(AItemW - ASize0, AE0);
  Result[1] := TyPointF(AItemW, AE0);
  Result[2] := TyPointF(AItemW, AE1);
  Result[3] := TyPointF(AItemW - ASize1, AE1);
end;

{ a Polygon's rect: its path data stays a plain array -- only a proxy built
  from an SVG string goes through toStatic's Float32Array. [Batch 55: this
  rounded to float32, and a partial range's rect came out 68.5999984741211
  where upstream's is 68.6.] }
function PolyRect(const APoints: TTyPointFArray): TTyXYWH;
var
  i: Integer;
  x, y, mnX, mnY, mxX, mxY: Double;
begin
  mnX := MaxDouble; mnY := MaxDouble; mxX := -MaxDouble; mxY := -MaxDouble;
  for i := 0 to High(APoints) do
  begin
    x := APoints[i].X;
    y := APoints[i].Y;
    mnX := Min(mnX, x); mnY := Min(mnY, y);
    mxX := Max(mxX, x); mxY := Max(mxY, y);
  end;
  Result := XYWH(mnX, mnY, mxX - mnX, mxY - mnY);
end;

{ helper.getItemAlign: `align` as written, else left / right (top / bottom
  when horizontal) by which half of the canvas the component's centre falls
  in, the component measured as ten long and AItemW across }
function AutoItemAlign(const AView: TTyVmViewSpec; AItemW, ACanvasW,
  ACanvasH: Double; const APad: array of Double): string;
var
  b: TTyRawBox;
  rr: TTyXYWH;
  m: Double;
begin
  if (AView.Align <> '') and (AView.Align <> 'auto') then Exit(AView.Align);
  b := Default(TTyRawBox);
  if not AView.Horizontal then
  begin
    b.Top := TyBoxRawNum(0);
    b.Bottom.Kind := brNull;
    b.Height := TyBoxRawNum(10);
    b.Left := AView.Box.Left;
    b.Right := AView.Box.Right;
    b.Width := TyBoxRawNum(AItemW);
  end
  else
  begin
    b.Left := TyBoxRawNum(0);
    b.Right.Kind := brNull;
    b.Width := TyBoxRawNum(10);
    b.Top := AView.Box.Top;
    b.Bottom := AView.Box.Bottom;
    b.Height := TyBoxRawNum(AItemW);
  end;
  rr := TyGetLayoutRect(b, 0, 0, ACanvasW, ACanvasH, APad);
  if not AView.Horizontal then
  begin
    m := APad[3];
    if IsNan(m) or (m = 0) then m := 0;
    if Lt(m + rr.X + rr.W * 0.5, ACanvasW * 0.5) then Result := 'left'
    else Result := 'right';
  end
  else
  begin
    m := APad[0];
    if IsNan(m) or (m = 0) then m := 0;
    if Lt(m + rr.Y + rr.H * 0.5, ACanvasH * 0.5) then Result := 'top'
    else Result := 'bottom';
  end;
end;

{ renderBackground's Rect, as the position bbox reads it: (x + w) - x
  through fromLine, grown by the pen when the border has a width }
function BackgroundRect(const ABg: TTyXYWH; ABorder: Double): TTyXYWH;
begin
  Result := ABg;
  Result.W := (Result.X + Result.W) - Result.X;
  Result.H := (Result.Y + Result.H) - Result.Y;
  if ABorder > 0 then
  begin
    Result.W := Result.W + ABorder;
    Result.H := Result.H + ABorder;
    Result.X := Result.X - ABorder / 2;
    Result.Y := Result.Y - ABorder / 2;
  end;
end;

function Translate(AX, AY: Double): TTyMat2D;
begin
  Result := MatIdentity;
  Result[4] := AX;
  Result[5] := AY;
end;

{ PiecewiseView.doRender through positionGroup }
function LayoutPiecewise(const AModel: TTyVisualMapSpec;
  const AView: TTyVmViewSpec; const AContent: TTyVisualColor;
  ACanvasW, ACanvasH: Double; const ARef: TTyXYWH; AScale: Double;
  const AMeasurer: ITyTextMeasurer;
  const AInk: TTyVisualMapInk): TTyVisualMapLayout;
var
  L: TTyVisualMapLayout;
  i0, i1, gap, tgap, x, y, nextV, move, rv: Double;
  pad: array[0..3] of Double;
  itemAlign, text, lalign, lvalign: string;
  reverseList, have: Boolean;
  order: array of Integer;
  k, n, p: Integer;
  it: TTyVmItem;
  s: TTyVisualMapSpec;
  row: TTyVisualRow;
  st: TTyVisualState;
  bb, r: TTyXYWH;
  box: TTyRawBox;

  procedure Push(const AItem: TTyVmItem);
  begin
    n := Length(L.Items);
    SetLength(L.Items, n + 1);
    L.Items[n] := AItem;
  end;

  { _renderEndsText: nothing for an empty text }
  procedure EndsText(const AText: string);
  var e: TTyVmItem; ex: Double; ah: TTyTextAnchorH; hv: Boolean;
  begin
    if AText = '' then Exit;
    e := Default(TTyVmItem);
    e.IsText := True;
    e.PieceIndex := -1;
    if L.ShowLabel then
    begin
      if itemAlign = 'right' then ex := i0 else ex := 0;
      ah := WordH(itemAlign);
    end
    else
    begin
      ex := i0 / 2;
      ah := tahCentre;
    end;
    e.Label_ := MakeText(AText, ex, i1 / 2, ah, tavMiddle, AMeasurer, AInk);
    e.LabelOpacity := 1;
    hv := False;
    Accumulate(e.Rect, hv, e.Label_.Rect, MatIdentity);
    Push(e);
  end;

begin
  L := Default(TTyVisualMapLayout);
  L.Index := AModel.Index;
  L.Show := AView.Show;
  L.Piecewise := True;
  L.Scale := AScale;
  Result := L;
  if not AView.Show then Exit;
  L.Horizontal := AView.Horizontal;
  i0 := AView.ItemW * AScale;
  i1 := AView.ItemH * AScale;
  L.ItemW := i0;
  L.ItemH := i1;
  for k := 0 to 3 do pad[k] := AView.Padding[k] * AScale;
  gap := AView.ItemGap * AScale;
  tgap := AView.TextGap * AScale;

  { _getItemAlign: vertical asks helper.getItemAlign, horizontal is `align`
    or left }
  if not AView.Horizontal then
    itemAlign := AutoItemAlign(AView, i0, ACanvasW, ACanvasH, pad)
  else if (AView.Align = '') or (AView.Align = 'auto') then
    itemAlign := 'left'
  else
    itemAlign := AView.Align;
  L.ItemAlign := itemAlign;
  { showLabel: as written, else only when there is no text }
  if AView.HasShowLabel then L.ShowLabel := AView.ShowLabel
  else L.ShowLabel := not AView.HasText;

  { _getViewData: the list reversed when `horizontal ? inverse : !inverse`,
    the ends text reversed otherwise }
  reverseList := AView.Horizontal = AView.Inverse;
  SetLength(order, Length(AModel.Pieces));
  for k := 0 to High(order) do
    if reverseList then order[k] := High(order) - k else order[k] := k;
  L.HasEnds := AView.HasText;
  if AView.HasText then
  begin
    if reverseList then
    begin
      L.EndsText[0] := AView.Text[0];
      L.EndsText[1] := AView.Text[1];
    end
    else
    begin
      L.EndsText[0] := AView.Text[1];
      L.EndsText[1] := AView.Text[0];
    end;
  end;

  if L.HasEnds then EndsText(L.EndsText[0]);
  s := AModel;
  s.States := AModel.Controller;
  for k := 0 to High(order) do
  begin
    p := order[k];
    it := Default(TTyVmItem);
    it.PieceIndex := p;
    { the representative value -- a category's text -- and its state }
    if AModel.Pieces[p].HasValue and AModel.Pieces[p].ValueIsStr
      and AModel.IsCategory then
    begin
      rv := NaN;
      text := AModel.Pieces[p].ValueStr;
    end
    else
    begin
      rv := TyVisualRepresent(AModel.Pieces[p]);
      text := TyJsNumberToString(rv);
    end;
    st := TyVisualValueState(AModel, rv, text);
    { getControllerVisual(representValue, 'symbol' | 'color'): the
      controller visuals of the value's own state, over contentColor }
    row := Default(TTyVisualRow);
    row.Color := AContent;
    TyVisualApply(s, st, rv, text, row, False);
    if row.SymbolSet then it.Symbol := row.Symbol else it.Symbol := 'roundRect';
    it.Fill := row.Color;
    { createSymbol sets no colour it is not given: the path keeps zrender's
      default fill, black -- a category with no visual of its own [Batch 116] }
    if not it.Fill.Defined then it.Fill := TyVisualRgba(0, 0, 0, 1);
    it.SymbolBox := XYWH(0, 0, i0, i1);
    it.SymbolRect := TyVmSymbolRect(it.Symbol, it.SymbolBox);
    have := False;
    Accumulate(it.Rect, have, it.SymbolRect, MatIdentity);
    it.HasLabel := L.ShowLabel;
    if L.ShowLabel then
    begin
      if AView.TextAlign <> '' then lalign := AView.TextAlign else lalign := itemAlign;
      if AView.TextVAlign <> '' then lvalign := AView.TextVAlign else lvalign := 'middle';
      if lalign = 'right' then x := -tgap else x := i0 + tgap;
      it.Label_ := MakeText(AModel.Pieces[p].Text, x, i1 / 2, WordH(lalign),
        WordV(lvalign), AMeasurer, AInk);
      if AView.HasTextOpacity then it.LabelOpacity := AView.TextOpacity
      else if st = tvsOutOfRange then it.LabelOpacity := 0.5
      else it.LabelOpacity := 1;
      Accumulate(it.Rect, have, it.Label_.Rect, MatIdentity);
    end;
    Push(it);
  end;
  if L.HasEnds then EndsText(L.EndsText[1]);

  { layout.box: each child after the last, by its rect and the NEXT one's
    offset, a gap between }
  x := 0;
  y := 0;
  for k := 0 to High(L.Items) do
  begin
    r := L.Items[k].Rect;
    if L.Horizontal then
    begin
      move := r.W;
      if k < High(L.Items) then move := r.W + (-L.Items[k + 1].Rect.X + r.X);
      nextV := x + move;
    end
    else
    begin
      move := r.H;
      if k < High(L.Items) then move := r.H + (-L.Items[k + 1].Rect.Y + r.Y);
      nextV := y + move;
    end;
    L.Items[k].X := x;
    L.Items[k].Y := y;
    if L.Horizontal then x := nextV + gap else y := nextV + gap;
  end;

  { renderBackground: the group's rect, padded }
  have := False;
  bb := XYWH(0, 0, 0, 0);
  for k := 0 to High(L.Items) do
    Accumulate(bb, have, L.Items[k].Rect, Translate(L.Items[k].X, L.Items[k].Y));
  L.BBoxBackground := bb;
  L.Background := XYWH(bb.X - pad[3], bb.Y - pad[0], bb.W + pad[3] + pad[1],
    bb.H + pad[0] + pad[2]);
  Accumulate(bb, have, BackgroundRect(L.Background, AView.BorderWidth), MatIdentity);
  L.BBoxPosition := bb;

  { positionGroup, as the continuous view }
  box := AView.Box;
  box.Width := TyBoxRawNum(bb.W);
  box.Height := TyBoxRawNum(bb.H);
  r := TyGetLayoutRect(box, ARef.X, ARef.Y, ARef.W, ARef.H, [0, 0, 0, 0]);
  L.GroupX := 0 + (r.X - bb.X);
  L.GroupY := 0 + (r.Y - bb.Y);
  L.Valid := True;
  Result := L;
end;

{ the handles at AEnds: thumbs in the bar, labels in the view group; the
  fills from the in-range stops' two ends }
procedure PlaceHandlesOn(var L: TTyVisualMapLayout; const AModel: TTyVisualMapSpec;
  const AView: TTyVmViewSpec; AScale: Double; const AMeasurer: ITyTextMeasurer;
  const AInk: TTyVisualMapInk; const AInStops: TTyVisualGradStopArray;
  const AEnds: array of Double);
var
  h: Integer;
  th: TTyMat2D;
  i0, i1, hs, lx, ly, val, ss, lw, lineScale: Double;
  align: TTyTextAnchorH;
  dir: string;
  iconBox, r: TTyXYWH;
  ib: TTyRectF;
begin
  if not AView.Calculable then Exit;
  i0 := L.ItemW;
  i1 := L.ItemH;
  hs := TyBoxRawResolve(AView.HandleSize, i0);
  if AView.HandleSize.Kind = brNumber then hs := hs * AScale;
  iconBox := XYWH(-hs / 2, -hs / 2, hs, hs);
  SetLength(L.Handles, 2);
  for h := 0 to 1 do
  begin
    L.Handles[h] := Default(TTyVmHandle);
    { the controller's size at the value under the handle -- its own
      state, not a forced one: scaled to it, centred on the bar's edge
      side }
    val := TyVmLinearMap(AEnds[h], 0, i1, AModel.Extent0, AModel.Extent1, True);
    ss := ControllerSize(AModel, TyVisualValueState(AModel, val), val,
      AView.ItemW) * AScale;
    th := MatIdentity;
    th[0] := ss / i0;
    th[3] := ss / i0;
    th[4] := i0 - ss / 2;
    th[5] := AEnds[h];
    L.Handles[h].Local := th;
    L.Handles[h].Thumb := MatMul(L.Bar, th);
    if AView.HandleImage <> '' then
    begin
      { [F6a] the picture's own box: no path, no pen }
      ib := TyImageCenterBox(AView.HandleImage, TyRectF(iconBox.X, iconBox.Y,
        iconBox.X + iconBox.W, iconBox.Y + iconBox.H));
      L.Handles[h].PathRect := XYWH(ib.Left, ib.Top, ib.Right - ib.Left, ib.Bottom - ib.Top);
    end
    else
      L.Handles[h].PathRect := TyVmIconRect(AView.HandleIcon, iconBox);
    { Path.getBoundingRect with the pen: strokeNoScale divides by the line
      scale of the thumb's whole transform, which is 1 at scale 1 }
    lw := AView.HandleLineWidth;
    if h = 0 then L.Handles[h].Fill := AInStops[0].Color
    else L.Handles[h].Fill := AInStops[High(AInStops)].Color;
    if not L.Handles[h].Fill.Defined then lw := Max(lw, 4);
    lineScale := 1;
    if (Abs(L.Handles[h].Thumb[0] - 1) > 1e-10)
      and (Abs(L.Handles[h].Thumb[3] - 1) > 1e-10) then
      lineScale := Sqrt(Abs(L.Handles[h].Thumb[0] * L.Handles[h].Thumb[3]
        - L.Handles[h].Thumb[2] * L.Handles[h].Thumb[1]));
    r := L.Handles[h].PathRect;
    if (lw > 0) and (lineScale > 1e-10) and (AView.HandleImage = '') then
    begin
      r.W := r.W + lw / lineScale;
      r.H := r.H + lw / lineScale;
      r.X := r.X - lw / lineScale / 2;
      r.Y := r.Y - lw / lineScale / 2;
    end;
    L.Handles[h].Rect := r;
    { the label: [handleSize, 0] through the thumb }
    MatApply(L.Handles[h].Thumb, hs, 0, lx, ly);
    { a horizontal bar's labels sit off the bar by the thumb's shortfall }
    if AView.Horizontal then
    begin
      dir := TyVmTransformDirection('left', L.Bar);
      if (dir = 'left') or (dir = 'top') then ly := ly + (i0 - ss) / 2
      else ly := ly + (i0 - ss) / -2;
    end;
    if not AView.Horizontal then
      align := WordH(TyVmTransformDirection('left', L.Bar))
    else
      align := tahCentre;
    L.Handles[h].Label_ := MakeText(
      TyVmFormatValue(L.Interval[h], AView.Precision, AView.Formatter),
      lx, ly, align, tavMiddle, AMeasurer, AInk);
  end;
end;

procedure TyVmContinuousUpdate(var L: TTyVisualMapLayout;
  const AModel: TTyVisualMapSpec; const AView: TTyVmViewSpec;
  const AContent: TTyVisualColor; AScale: Double;
  const AMeasurer: ITyTextMeasurer; const AInk: TTyVisualMapInk;
  AI0, AI1, AE0, AE1: Double);
var
  inS0, inS1: Double;
  inStops: TTyVisualGradStopArray;
begin
  L.Interval[0] := AI0;
  L.Interval[1] := AI1;
  L.HandleEnds[0] := AE0;
  L.HandleEnds[1] := AE1;
  inStops := ColourStops(AModel, tvsInRange, AI0, AI1, AContent);
  L.InStops := inStops;
  inS0 := ControllerSize(AModel, tvsInRange, AI0, AView.ItemW) * AScale;
  inS1 := ControllerSize(AModel, tvsInRange, AI1, AView.ItemW) * AScale;
  L.InPoints := BarPoints(L.ItemW, inS0, inS1, AE0, AE1);
  L.InRect := PolyRect(L.InPoints);
  PlaceHandlesOn(L, AModel, AView, AScale, AMeasurer, AInk, inStops, [AE0, AE1]);
end;

function TyVmIndicatorAt(const L: TTyVisualMapLayout;
  const AModel: TTyVisualMapSpec; const AView: TTyVmViewSpec;
  const AContent: TTyVisualColor; AScale: Double;
  const AMeasurer: ITyTextMeasurer; const AInk: TTyVisualMapInk;
  ACursor, ATextValue: Double; const APrefix: string): TTyVmIndicator;
var
  st: TTyVisualState;
  ss, lpx, tx, ty, tw, th: Double;
  M: TTyMat2D;
  dir: string;
begin
  Result := Default(TTyVmIndicator);
  { getControllerVisual without a forced state: the value's own state in the
    MODEL's range; the colour carries the opacity as alpha }
  st := TyVisualValueState(AModel, ACursor);
  Result.Fill := ControllerColour(AModel, st, ACursor, AContent);
  ss := ControllerSize(AModel, st, ACursor, AView.ItemW) * AScale;
  Result.Y := TyVmLinearMap(ACursor, AModel.Extent0, AModel.Extent1, 0, L.ItemH, True);
  Result.X := L.ItemW - ss / 2;
  Result.Size := TyBoxRawResolve(AView.IndicatorSize, L.ItemW);
  if AView.IndicatorSize.Kind = brNumber then Result.Size := Result.Size * AScale;
  { indicatorLabelPoint: half the size of U+56FD off a horizontal bar,
    HOVER_LINK_OUT (6) off a vertical one, past half the item }
  if AView.Horizontal then
  begin
    tw := 0;
    th := 0;
    if AMeasurer <> nil then
      AMeasurer.MeasureLine(#$E5#$9B#$BD, AInk.FontName, AInk.FontSizeLogical,
        AInk.FontWeight, tw, th);
    lpx := Max(tw, th) / 2 + L.ItemW / 2;
  end
  else
    lpx := 6 * AScale + L.ItemW / 2;
  { getTransform(indicator, group): the bar's matrix after the indicator's
    own translation, then the point }
  M := MatMul(L.Bar, Translate(Result.X, Result.Y));
  MatApply(M, lpx, 0, tx, ty);
  dir := TyVmTransformDirection('left', L.Bar);
  if AView.Horizontal then
    Result.Label_ := MakeText(APrefix + TyVmFormatValue(ATextValue, AView.Precision,
      AView.Formatter), tx, ty, tahCentre, WordV(dir), AMeasurer, AInk)
  else
    Result.Label_ := MakeText(APrefix + TyVmFormatValue(ATextValue, AView.Precision,
      AView.Formatter), tx, ty, WordH(dir), tavMiddle, AMeasurer, AInk);
end;

procedure TyVmGlobalToBar(const L: TTyVisualMapLayout; AGroupX, AGroupY, AX, AY: Double;
  out ABX, ABY: Double);
var inv: TTyMat2D;
begin
  ABX := NaN;
  ABY := NaN;
  if not TyMatInvert(MatMul(Translate(AGroupX, AGroupY), L.Bar), inv) then Exit;
  MatApply(inv, AX, AY, ABX, ABY);
end;

procedure TyVmToBar(const L: TTyVisualMapLayout; AGX, AGY: Double;
  out ABX, ABY: Double);
var inv: TTyMat2D;
begin
  ABX := NaN;
  ABY := NaN;
  if not TyMatInvert(L.Bar, inv) then Exit;
  MatApply(inv, AGX, AGY, ABX, ABY);
end;

{ pathContain's windingLine for one edge }
function WindingLine(X0, Y0, X1, Y1, AX, AY: Double): Double;
var t, dir, x_: Double;
begin
  Result := 0;
  if ((AY > Y0) and (AY > Y1)) or ((AY < Y0) and (AY < Y1)) then Exit;
  if Y1 = Y0 then Exit;
  t := (AY - Y0) / (Y1 - Y0);
  if Y1 < Y0 then dir := 1 else dir := -1;
  if (t = 1) or (t = 0) then
    if Y1 < Y0 then dir := 0.5 else dir := -0.5;
  x_ := t * (X1 - X0) + X0;
  if x_ = AX then Exit(Infinity);
  if x_ > AX then Result := dir;
end;

{ a polygon's fill: its rect first, then the winding over its edges and the
  closing one -- any non-zero (an edge through the point is in) }
function PolyContains(const APts: TTyPointFArray; AX, AY: Double): Boolean;
var
  r: TTyXYWH;
  i, j: Integer;
  w: Double;
begin
  Result := False;
  if Length(APts) < 2 then Exit;
  r := PolyRect(APts);
  if not ((AX >= r.X) and (AX <= r.X + r.W) and (AY >= r.Y) and (AY <= r.Y + r.H)) then Exit;
  w := 0;
  for i := 0 to High(APts) do
  begin
    j := (i + 1) mod Length(APts);
    w := w + WindingLine(APts[i].X, APts[i].Y, APts[j].X, APts[j].Y, AX, AY);
  end;
  Result := w <> 0;
end;

function TyVmBarPartAt(const L: TTyVisualMapLayout; AGX, AGY: Double): Integer;
var bx, by, r, sc: Double;

  function InCorner(ACX, ACY: Double): Boolean;
  begin
    Result := Sqr(bx - ACX) + Sqr(by - ACY) <= Sqr(r);
  end;

begin
  Result := 0;
  if L.Piecewise or not L.Valid then Exit;
  TyVmToBar(L, AGX, AGY, bx, by);
  if IsNan(bx) or IsNan(by) then Exit;
  { the clip: the bar's rect with corners of 3 }
  if not ((bx >= 0) and (bx <= L.ItemW) and (by >= 0) and (by <= L.ItemH)) then Exit;
  sc := L.Scale;
  if (sc <= 0) or IsNan(sc) then sc := 1;
  r := Min(3 * sc, Min(L.ItemW, L.ItemH) / 2);
  if (bx < r) and (by < r) and not InCorner(r, r) then Exit;
  if (bx > L.ItemW - r) and (by < r) and not InCorner(L.ItemW - r, r) then Exit;
  if (bx < r) and (by > L.ItemH - r) and not InCorner(r, L.ItemH - r) then Exit;
  if (bx > L.ItemW - r) and (by > L.ItemH - r) and not InCorner(L.ItemW - r, L.ItemH - r) then Exit;
  { the in-range polygon is drawn over the other }
  if PolyContains(L.InPoints, bx, by) then Exit(2);
  if PolyContains(L.OutPoints, bx, by) then Exit(1);
end;

function TyVmThumbContains(const L: TTyVisualMapLayout; const AView: TTyVmViewSpec;
  AHandle: Integer; AFill: Boolean; AGX, AGY: Double): Boolean;
var
  inv, M: TTyMat2D;
  px, py, rad, ax0, ay0, ax1, ay1, t, dx, dy, d, lw, lineScale, half: Double;
  pr: TTyXYWH;
begin
  Result := False;
  if (AHandle < 0) or (AHandle > High(L.Handles)) then Exit;
  M := L.Handles[AHandle].Thumb;
  if not TyMatInvert(M, inv) then Exit;
  MatApply(inv, AGX, AGY, px, py);
  pr := L.Handles[AHandle].PathRect;
  { [F6a] a picture: its rect, edges in (rectContain) }
  if AView.HandleImage <> '' then
    Exit((px >= pr.X) and (px <= pr.X + pr.W) and (py >= pr.Y) and (py <= pr.Y + pr.H));
  { the pen: strokeNoScale divides by the line scale; a thumb without a fill
    is its pen alone, at least strokeContainThreshold (5) wide }
  lw := AView.HandleLineWidth;
  { no Max with an integer literal: that overload is Single's }
  if (not AFill) and (lw < 5) then lw := 5;
  lineScale := 1;
  if (Abs(M[0] - 1) > 1e-10) and (Abs(M[3] - 1) > 1e-10) then
    lineScale := Sqrt(Abs(M[0] * M[3] - M[2] * M[1]));
  if lineScale <= 1e-10 then half := 0 else half := lw / lineScale / 2;
  { THE PILL: a stadium along its longer side, ends of half its breadth --
    the default icon is exactly that }
  rad := Min(pr.W, pr.H) / 2;
  if pr.W >= pr.H then
  begin
    ax0 := pr.X + rad; ax1 := pr.X + pr.W - rad;
    ay0 := pr.Y + pr.H / 2; ay1 := ay0;
  end
  else
  begin
    ay0 := pr.Y + rad; ay1 := pr.Y + pr.H - rad;
    ax0 := pr.X + pr.W / 2; ax1 := ax0;
  end;
  dx := ax1 - ax0;
  dy := ay1 - ay0;
  if (dx = 0) and (dy = 0) then t := 0
  else
  begin
    t := ((px - ax0) * dx + (py - ay0) * dy) / (dx * dx + dy * dy);
    if t < 0 then t := 0
    else if t > 1 then t := 1;
  end;
  d := Sqrt(Sqr(px - (ax0 + t * dx)) + Sqr(py - (ay0 + t * dy))) - rad;
  if (lw > 0) and (Abs(d) <= half) then Exit(True);
  Result := AFill and (d <= 0);
end;

function TyVmTextContains(const AText: TTyVmText; AGX, AGY: Double): Boolean;
begin
  Result := (AText.Text <> '') and (AGX >= AText.Rect.X) and (AGX <= AText.Rect.X + AText.Rect.W)
    and (AGY >= AText.Rect.Y) and (AGY <= AText.Rect.Y + AText.Rect.H);
end;

function TyVmSymbolContains(const AItem: TTyVmItem; AX, AY: Double): Boolean;
var b: TTyXYWH; r, cx, cy: Double;

  function InCorner(ACX, ACY: Double): Boolean;
  begin
    Result := Sqr(AX - ACX) + Sqr(AY - ACY) <= Sqr(r);
  end;

begin
  b := AItem.SymbolBox;
  if AItem.Symbol = 'circle' then
  begin
    r := Min(b.W, b.H) / 2;
    cx := b.X + b.W / 2;
    cy := b.Y + b.H / 2;
    Exit(Sqr(AX - cx) + Sqr(AY - cy) <= Sqr(r));
  end;
  Result := (AX >= b.X) and (AX <= b.X + b.W) and (AY >= b.Y) and (AY <= b.Y + b.H);
  if not Result or (AItem.Symbol <> 'roundRect') then Exit;
  r := Min(b.W, b.H) / 4;
  if (AX < b.X + r) and (AY < b.Y + r) and not InCorner(b.X + r, b.Y + r) then Exit(False);
  if (AX > b.X + b.W - r) and (AY < b.Y + r) and not InCorner(b.X + b.W - r, b.Y + r) then Exit(False);
  if (AX < b.X + r) and (AY > b.Y + b.H - r) and not InCorner(b.X + r, b.Y + b.H - r) then Exit(False);
  if (AX > b.X + b.W - r) and (AY > b.Y + b.H - r) and not InCorner(b.X + b.W - r, b.Y + b.H - r) then Exit(False);
end;

function TyLayoutVisualMap(const AModel: TTyVisualMapSpec;
  const AView: TTyVmViewSpec; const AContent: TTyVisualColor;
  ACanvasW, ACanvasH, AScale: Double; const AMeasurer: ITyTextMeasurer;
  const AInk: TTyVisualMapInk): TTyVisualMapLayout;
begin
  Result := TyLayoutVisualMap(AModel, AView, AContent, ACanvasW, ACanvasH,
    XYWH(0, 0, ACanvasW, ACanvasH), AScale, AMeasurer, AInk);
end;

function TyLayoutVisualMap(const AModel: TTyVisualMapSpec;
  const AView: TTyVmViewSpec; const AContent: TTyVisualColor;
  ACanvasW, ACanvasH: Double; const ARef: TTyXYWH; AScale: Double;
  const AMeasurer: ITyTextMeasurer;
  const AInk: TTyVisualMapInk): TTyVisualMapLayout;
var
  L: TTyVisualMapLayout;
  i0, i1, gap, hs, t, ex, ey, lw, lineScale, outS0, outS1, inS0, inS1: Double;
  pad: array[0..3] of Double;
  box: TTyRawBox;
  r, bb, iconBox: TTyXYWH;
  props: TTyTransformProps;
  vertical, left, bottom: Boolean;
  k: Integer;
  word: string;
  inStops: TTyVisualGradStopArray;

  { Group.getBoundingRect of the view group }
  function GroupRect(AWithBackground: Boolean): TTyXYWH;
  var
    have, haveBar, haveGrad: Boolean;
    barRect, gradRect, bg: TTyXYWH;
    h: Integer;
  begin
    have := False;
    Result := XYWH(0, 0, 0, 0);
    { the handle labels were added to the group first }
    for h := 0 to High(L.Handles) do
      Accumulate(Result, have, L.Handles[h].Label_.Rect, MatIdentity);
    { then the bar group: its gradient group, then the thumbs }
    haveGrad := False;
    gradRect := XYWH(0, 0, 0, 0);
    Accumulate(gradRect, haveGrad, L.OutRect, MatIdentity);
    Accumulate(gradRect, haveGrad, L.InRect, MatIdentity);
    haveBar := False;
    barRect := XYWH(0, 0, 0, 0);
    Accumulate(barRect, haveBar, gradRect, MatIdentity);
    for h := 0 to High(L.Handles) do
      Accumulate(barRect, haveBar, L.Handles[h].Rect, L.Handles[h].Local);
    Accumulate(Result, have, barRect, L.Bar);
    for h := 0 to High(L.Texts) do
      Accumulate(Result, have, L.Texts[h].Rect, MatIdentity);
    if AWithBackground then
    begin
      { a Rect path: (x + w) - x through fromLine, and the pen when the
        border has a width }
      bg := L.Background;
      bg.W := (bg.X + bg.W) - bg.X;
      bg.H := (bg.Y + bg.H) - bg.Y;
      if AView.BorderWidth > 0 then
      begin
        bg.W := bg.W + AView.BorderWidth;
        bg.H := bg.H + AView.BorderWidth;
        bg.X := bg.X - AView.BorderWidth / 2;
        bg.Y := bg.Y - AView.BorderWidth / 2;
      end;
      Accumulate(Result, have, bg, MatIdentity);
    end;
  end;

begin
  L := Default(TTyVisualMapLayout);
  L.Index := AModel.Index;
  L.Show := AView.Show;
  L.Scale := AScale;
  Result := L;
  if AModel.SubType = 'piecewise' then
    Exit(LayoutPiecewise(AModel, AView, AContent, ACanvasW, ACanvasH, ARef,
      AScale, AMeasurer, AInk));
  if not AView.Show then Exit;
  if AModel.SubType <> 'continuous' then Exit;
  L.Horizontal := AView.Horizontal;
  i0 := AView.ItemW * AScale;
  i1 := AView.ItemH * AScale;
  L.ItemW := i0;
  L.ItemH := i1;
  for k := 0 to 3 do pad[k] := AView.Padding[k] * AScale;
  gap := AView.TextGap * AScale;
  hs := TyBoxRawResolve(AView.HandleSize, i0);
  if AView.HandleSize.Kind = brNumber then hs := hs * AScale;
  iconBox := XYWH(-hs / 2, -hs / 2, hs, hs);

  { getSelected: the range ascending, clamped into the extent }
  L.Interval[0] := AModel.Range0;
  L.Interval[1] := AModel.Range1;
  if Gt(L.Interval[0], L.Interval[1]) then
  begin
    t := L.Interval[0];
    L.Interval[0] := L.Interval[1];
    L.Interval[1] := t;
  end;
  for k := 0 to 1 do
  begin
    if Gt(L.Interval[k], AModel.Extent1) then L.Interval[k] := AModel.Extent1;
    if Lt(L.Interval[k], AModel.Extent0) then L.Interval[k] := AModel.Extent0;
  end;
  for k := 0 to 1 do
    L.HandleEnds[k] := TyVmLinearMap(L.Interval[k], AModel.Extent0,
      AModel.Extent1, 0, i1, True);

  { the bar group, one of four }
  L.ItemAlign := AutoItemAlign(AView, i0, ACanvasW, ACanvasH, pad);
  vertical := not AView.Horizontal;
  left := L.ItemAlign = 'left';
  bottom := L.ItemAlign = 'bottom';
  props := Default(TTyTransformProps);
  props.ScaleX := 1;
  props.ScaleY := 1;
  if (not vertical) and not AView.Inverse then
  begin
    if bottom then props.ScaleX := 1 else props.ScaleX := -1;
    props.Rotation := Pi / 2;
  end
  else if (not vertical) and AView.Inverse then
  begin
    if bottom then props.ScaleX := -1 else props.ScaleX := 1;
    props.Rotation := -Pi / 2;
  end
  else if vertical and not AView.Inverse then
  begin
    if left then props.ScaleX := 1 else props.ScaleX := -1;
    props.ScaleY := -1;
  end
  else
    if left then props.ScaleX := 1 else props.ScaleX := -1;
  L.Bar := TyMatRecompose(props);

  { the colours, which do not move: in-range over the interval, out over
    the extent }
  inStops := ColourStops(AModel, tvsInRange, L.Interval[0], L.Interval[1],
    AContent);
  L.InStops := inStops;
  L.OutStops := ColourStops(AModel, tvsOutOfRange, AModel.Extent0,
    AModel.Extent1, AContent);

  { the end texts }
  if AView.HasText then
  begin
    SetLength(L.Texts, 2);
    for k := 0 to 1 do
    begin
      if k = 0 then MatApply(L.Bar, i0 / 2, -gap, ex, ey)
      else MatApply(L.Bar, i0 / 2, i1 + gap, ex, ey);
      if k = 0 then word := TyVmTransformDirection('bottom', L.Bar)
      else word := TyVmTransformDirection('top', L.Bar);
      if AView.Horizontal then
        L.Texts[k] := MakeText(AView.Text[1 - k], ex, ey, WordH(word),
          tavMiddle, AMeasurer, AInk)
      else
        L.Texts[k] := MakeText(AView.Text[1 - k], ex, ey, tahCentre,
          WordV(word), AMeasurer, AInk);
    end;
  end;

  { the controller's size at the bars' ends: the out-of-range bar over the
    extent, the in-range one over the interval, each state forced }
  outS0 := ControllerSize(AModel, tvsOutOfRange, AModel.Extent0, AView.ItemW) * AScale;
  outS1 := ControllerSize(AModel, tvsOutOfRange, AModel.Extent1, AView.ItemW) * AScale;
  inS0 := ControllerSize(AModel, tvsInRange, L.Interval[0], AView.ItemW) * AScale;
  inS1 := ControllerSize(AModel, tvsInRange, L.Interval[1], AView.ItemW) * AScale;

  { THE SKETCH: the whole length, for the background }
  L.OutPoints := BarPoints(i0, outS0, outS1, 0, i1);
  L.OutRect := PolyRect(L.OutPoints);
  L.InPoints := BarPoints(i0, inS0, inS1, 0, i1);
  L.InRect := PolyRect(L.InPoints);
  PlaceHandlesOn(L, AModel, AView, AScale, AMeasurer, AInk, inStops, [0, i1]);
  bb := GroupRect(False);
  L.BBoxBackground := bb;
  L.Background := XYWH(bb.X - pad[3], bb.Y - pad[0], bb.W + pad[3] + pad[1],
    bb.H + pad[0] + pad[2]);

  { THE FINAL VIEW }
  L.InPoints := BarPoints(i0, inS0, inS1, L.HandleEnds[0], L.HandleEnds[1]);
  L.InRect := PolyRect(L.InPoints);
  PlaceHandlesOn(L, AModel, AView, AScale, AMeasurer, AInk, inStops, L.HandleEnds);
  bb := GroupRect(True);
  L.BBoxPosition := bb;

  { positionGroup: the box with the drawn size, on the canvas, no margin }
  box := AView.Box;
  box.Width := TyBoxRawNum(bb.W);
  box.Height := TyBoxRawNum(bb.H);
  r := TyGetLayoutRect(box, ARef.X, ARef.Y, ARef.W, ARef.H, [0, 0, 0, 0]);
  L.GroupX := 0 + (r.X - bb.X);
  L.GroupY := 0 + (r.Y - bb.Y);
  L.Valid := True;
  Result := L;
end;

{ ==================== the marks ==================== }

function TyBuildVisualMapMarks(const ALayout: TTyVisualMapLayout;
  const AView: TTyVmViewSpec; const AInk: TTyVisualMapInk;
  AOriginX, AOriginY: Double; AList: TTyPaintList): Integer;
var none: TTyVmLiveDraw;
begin
  none := Default(TTyVmLiveDraw);
  Result := TyBuildVisualMapMarks(ALayout, AView, AInk, AOriginX, AOriginY,
    AList, none);
end;

function TyBuildVisualMapMarks(const ALayout: TTyVisualMapLayout;
  const AView: TTyVmViewSpec; const AInk: TTyVisualMapInk;
  AOriginX, AOriginY: Double; AList: TTyPaintList;
  const ALive: TTyVmLiveDraw): Integer;
var
  G: TTyMat2D;
  el: TTyChartElement;
  h: Integer;

  function Blank: TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Z := AView.Z;
    Result.Silent := True;
    { no datum: the component is not a series' row }
    Result.Datum := TyChartDatum(-1, -1);
  end;

  function GlobalRect(const ARect: TTyXYWH; const M: TTyMat2D): TTyRectF;
  var r: TTyXYWH;
  begin
    r := TyRectApplyMat(ARect, M);
    Result := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
  end;

  { a bar: its rect, its gradient along the bar's own length }
  procedure Bar(const APoints: TTyPointFArray; const ARect: TTyXYWH;
    const AStops: TTyVisualGradStopArray; AFull: Boolean);
  var
    pts: TTyPointFArray;
    i: Integer;
    x, y: Double;
    grad: TTyChartGradient;
  begin
    el := Blank;
    if AFull then
      el.Shape := TyShapeRoundRect(GlobalRect(ARect, G), 3)
    else
    begin
      SetLength(pts, Length(APoints));
      for i := 0 to High(APoints) do
      begin
        MatApply(G, APoints[i].X, APoints[i].Y, x, y);
        pts[i] := TyPointF(x, y);
      end;
      el.Shape := TyShapePolygon(pts);
      { the round clip of a partial bar is its rectangle here }
      el.HasClip := True;
      el.ClipRect := GlobalRect(XYWH(0, 0, ALayout.ItemW, ALayout.ItemH), G);
    end;
    { LinearGradient(0, 0, 0, 1) over the element's own rect, turned with
      it: from the rect's (x, y) to (x, y + h), both through the matrix }
    grad := Default(TTyChartGradient);
    grad.Kind := cgkLinear;
    grad.Global := True;
    MatApply(G, ARect.X, ARect.Y, grad.X, grad.Y);
    MatApply(G, ARect.X, ARect.Y + ARect.H, grad.X2, grad.Y2);
    SetLength(grad.Stops, Length(AStops));
    for i := 0 to High(AStops) do
    begin
      grad.Stops[i].Offset := AStops[i].Offset;
      grad.Stops[i].Color := TyVisualToChart(AStops[i].Color);
    end;
    el.Style.HasFill := True;
    if Length(grad.Stops) > 0 then el.Style.FillColor := grad.Stops[0].Color;
    el.Style.FillGradient := grad;
    el.Style.Alpha := 1;
    AList.Add(el);
    Inc(Result);
  end;

  procedure Text(const AText: TTyVmText; AOpacity: Double = 1);
  var r: TTyXYWH;
  begin
    if AText.Text = '' then Exit;
    el := Blank;
    r := AText.Rect;
    el.Shape := TyShapeRect(TyRectF(r.X + G[4], r.Y + G[5],
      r.X + r.W + G[4], r.Y + r.H + G[5]));
    el.Caption.Text := AText.Text;
    el.Caption.FontName := AInk.FontName;
    el.Caption.FontSizeLogical := AInk.FontSizeLogical;
    el.Caption.FontWeight := AInk.FontWeight;
    el.Caption.Colour := AInk.Text;
    { an out-of-range item's label at half: the opacity on the colour }
    if AOpacity <> 1 then
      el.Caption.Colour := (AInk.Text and $00FFFFFF)
        or (Cardinal(Round((AInk.Text shr 24) * AOpacity)) shl 24);
    el.Caption.X := AText.X + G[4];
    el.Caption.Y := AText.Y + G[5];
    el.Caption.AnchorH := AText.AlignH;
    el.Caption.AnchorV := AText.AlignV;
    AList.Add(el);
    Inc(Result);
  end;

var
  T: TTyMat2D;
  bg: TTyXYWH;
  pr: TTyXYWH;
  ix, iy: array[0..3] of Double;
  cxl, cyl, cx, cy, sw, sh: Double;
  fill: TTyVisualColor;

  { a piecewise child: the symbol in its box, the label or the ends text;
    SILENT unless a click would select }
  procedure Item(const AItem: TTyVmItem);
  var
    spec: TTySymbolSpec;
    empty: Boolean;
    path: string;
    ox, oy: Double;
  begin
    ox := T[4] + AItem.X;
    oy := T[5] + AItem.Y;
    if not AItem.IsText then
    begin
      spec := Default(TTySymbolSpec);
      spec.Kind := TySymbolKindOf(AItem.Symbol, empty, path);
      spec.Empty := empty;
      spec.PathData := path;
      spec.WidthPx := AItem.SymbolBox.W;
      spec.HeightPx := AItem.SymbolBox.H;
      if (spec.Kind <> tsyNone) and AItem.Fill.Defined then
      begin
        el := Blank;
        el.Silent := AView.Silent;
        el.Shape := TyBuildSymbolInBox(spec, TyRectF(ox + AItem.SymbolBox.X,
          oy + AItem.SymbolBox.Y, ox + AItem.SymbolBox.X + AItem.SymbolBox.W,
          oy + AItem.SymbolBox.Y + AItem.SymbolBox.H));
        if empty then
        begin
          el.Style.StrokeColor := TyVisualToChart(AItem.Fill);
          el.Style.StrokeWidthLogical := 2;
          el.Style.HasFill := True;
          el.Style.FillColor := AInk.Background or $FF000000;
        end
        else
        begin
          el.Style.HasFill := True;
          el.Style.FillColor := TyVisualToChart(AItem.Fill);
        end;
        el.Style.Alpha := 1;
        AList.Add(el);
        Inc(Result);
      end;
      if not AItem.HasLabel then Exit;
    end;
    G := Translate(ox, oy);
    Text(AItem.Label_, AItem.LabelOpacity);
  end;

begin
  Result := 0;
  if not ALayout.Valid then Exit;
  T := MatIdentity;
  T[4] := ALayout.GroupX + AOriginX;
  T[5] := ALayout.GroupY + AOriginY;
  { the background, under everything }
  bg := ALayout.Background;
  if AInk.Background shr 24 <> 0 then
  begin
    el := Blank;
    el.Z2 := -1;
    el.Shape := TyShapeRect(TyRectF(bg.X + T[4], bg.Y + T[5],
      bg.X + bg.W + T[4], bg.Y + bg.H + T[5]));
    el.Style.HasFill := True;
    el.Style.FillColor := AInk.Background;
    el.Style.Alpha := 1;
    AList.Add(el);
    Inc(Result);
  end;
  if AView.BorderWidth > 0 then
  begin
    el := Blank;
    el.Z2 := -1;
    el.Shape := TyShapeRect(TyRectF(bg.X + T[4], bg.Y + T[5],
      bg.X + bg.W + T[4], bg.Y + bg.H + T[5]));
    el.Style.StrokeColor := AInk.Border;
    el.Style.StrokeWidthLogical := AView.BorderWidth;
    el.Style.Alpha := 1;
    AList.Add(el);
    Inc(Result);
  end;
  if ALayout.Piecewise then
  begin
    for h := 0 to High(ALayout.Items) do Item(ALayout.Items[h]);
    Exit;
  end;
  G := MatMul(T, ALayout.Bar);
  { A RECTANGLE over the whole length is the clip itself, rounded; anything
    else -- a partial range, a trapezoid -- is the polygon, clipped square }
  Bar(ALayout.OutPoints, ALayout.OutRect, ALayout.OutStops,
    (ALayout.OutPoints[0].X = 0) and (ALayout.OutPoints[3].X = 0));
  Bar(ALayout.InPoints, ALayout.InRect, ALayout.InStops,
    (ALayout.HandleEnds[0] <= 0) and (ALayout.HandleEnds[1] >= ALayout.ItemH)
    and (ALayout.InPoints[0].X = 0) and (ALayout.InPoints[3].X = 0));
  { the handles: the icon at its box, turned with the bar }
  for h := 0 to High(ALayout.Handles) do
  begin
    el := Blank;
    pr := ALayout.Handles[h].PathRect;
    cxl := pr.X + pr.W / 2;
    cyl := pr.Y + pr.H / 2;
    MatApply(MatMul(T, ALayout.Handles[h].Thumb), cxl, cyl, cx, cy);
    sw := pr.W;
    sh := pr.H;
    if AView.HandleImage <> '' then
    begin
      { [F6a] the picture's corners through the thumb's whole transform }
      MatApply(MatMul(T, ALayout.Handles[h].Thumb), pr.X, pr.Y, ix[0], iy[0]);
      MatApply(MatMul(T, ALayout.Handles[h].Thumb), pr.X + pr.W, pr.Y, ix[1], iy[1]);
      MatApply(MatMul(T, ALayout.Handles[h].Thumb), pr.X + pr.W, pr.Y + pr.H, ix[2], iy[2]);
      MatApply(MatMul(T, ALayout.Handles[h].Thumb), pr.X, pr.Y + pr.H, ix[3], iy[3]);
      el.Shape := TyShapePolygon([TyPointF(ix[0], iy[0]), TyPointF(ix[1], iy[1]),
        TyPointF(ix[2], iy[2]), TyPointF(ix[3], iy[3])]);
      el.Shape.Image := AView.HandleImage;
      AList.Add(el);
      Inc(Result);
      Continue;
    end;
    el.Shape := TyShapePath(AView.HandleIcon,
      TyRectF(cx - sw / 2, cy - sh / 2, cx + sw / 2, cy + sh / 2),
      -TyJsAtan2(ALayout.Handles[h].Thumb[1], ALayout.Handles[h].Thumb[0]),
      cx, cy);
    { what the thumb shows now: a state that ended put back the fill it
      saved [Batch 116] }
    if ALive.Has and (h <= 1) then fill := ALive.HandleFill[h]
    else fill := ALayout.Handles[h].Fill;
    el.Style.HasFill := fill.Defined;
    el.Style.FillColor := TyVisualToChart(fill);
    el.Style.StrokeColor := AInk.HandleStroke;
    el.Style.StrokeWidthLogical := AView.HandleLineWidth;
    el.Style.Alpha := 1;
    AList.Add(el);
    Inc(Result);
  end;
  { THE HOVER INDICATOR, in the bar group after the thumbs [Batch 116]: the
    circle of indicatorSize, the handles' pen around it }
  if ALive.Has and ALive.IndVisible then
  begin
    el := Blank;
    MatApply(G, ALive.IndX, ALive.IndY, cx, cy);
    el.Shape := TyShapeCircle(cx, cy, ALive.IndSize / 2);
    el.Style.HasFill := ALive.IndFill shr 24 <> 0;
    el.Style.FillColor := ALive.IndFill;
    el.Style.StrokeColor := AInk.HandleStroke;
    el.Style.StrokeWidthLogical := 2;
    el.Style.Alpha := 1;
    AList.Add(el);
    Inc(Result);
  end;
  G := T;
  for h := 0 to High(ALayout.Texts) do Text(ALayout.Texts[h]);
  for h := 0 to High(ALayout.Handles) do
    if ALive.Has and (h <= 1) then Text(ALive.Labels[h], ALive.LabelOpacity[h])
    else Text(ALayout.Handles[h].Label_);
  if ALive.Has and ALive.IndLabelVisible then Text(ALive.IndLabel);
end;

end.
