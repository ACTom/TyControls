unit tyControls.AdvanceChart.DataZoomView;
{$mode objfpc}{$H+}
{ A slider dataZoom's own picture -- SliderZoomView as the first render
  leaves it: where the slider sits (_resetLocation over the box-layout merge,
  the 'ph' placeholders filled from the grid), the window's two ends along
  it, the background, the data shadow of the first series it can take one
  from, the filler, the frame, the two handles, the move bar with its icon,
  and the two labels. [Batch 61.]

  THE PLACE IS ZRENDER'S BOUNDING-RECT ARITHMETIC, not a picture of it.
  _positionGroup reads the slider group's rect BEFORE _updateView has put
  anything at the window: the handles still unscaled at nought, the filler
  and the move bar of no width, the move icon at nought -- and it is that
  rect, flipped and turned, that the view group is moved by. So the group
  sits where the half-built slider says, and the finished one is drawn
  there. The data shadow's polyline, which has no fill, grows that rect by
  two and a half pixels each side (strokeContainThreshold), which is why a
  default slider starts 2.8 px right of the grid.

  THE DATA SHADOW IS THE RAW DATA, unfiltered and unsampled, as upstream
  reads getRawData(): the caller hands the two columns over.

  THE VIEW'S OWN STATE COMES IN FROM THE CHART [batch 62]: after its own
  action a slider keeps the ends it was dragged to (descending after a
  cross), the labels a hover or a drag showed, the handle and move-bar
  emphasis, and the brush rect. Without it the ends are the window's.

  NOT HERE: a mirrored custom handle icon is drawn turned, not mirrored.

  PURE: the option and the chart's answers in, geometry out, and marks from
  the geometry. }
interface
uses SysUtils, Math, fpjson,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Option,
     tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Shape,
     tyControls.AdvanceChart.Layout, tyControls.AdvanceChart.ZrPath,
     tyControls.AdvanceChart.RichStyle, tyControls.AdvanceChart.Color;

type
  { One element's style as the author wrote it; each Has* False where the
    option is silent, and the theme's then. }
  TTyDzStyleSpec = record
    HasFill: Boolean;
    Fill: TTyChartColor;
    HasStroke: Boolean;
    Stroke: TTyChartColor;
    { NaN where not written }
    LineWidth: Double;
    HasOpacity: Boolean;
    Opacity: Double;
    { [R5-A] the block's shadow (getItemStyle / getLineStyle / getAreaStyle) }
    Shadow: TTyChartShadow;
    { [R7-AC] the pen beyond its colour and width (getLineStyle's type,
      dashOffset, cap, join, miterLimit; getItemStyle's border* of them):
      DashKind todNone unwritten; DashOffset NaN unwritten,
      cTyCanvasPhaseLeft where the canvas refuses it; Cap / Join -1
      unwritten, else TyCapOfWord's / TyJoinOfWord's (cTyCanvasWordLeft
      refused); Miter NaN unwritten, else TyOptMiterLimit's (-1 refused)
      [was: never read -- the options had no effect] }
    DashKind: TTyOptDash;
    Dash: TTyDoubleArray;
    DashOffset: Double;
    Cap, Join: Integer;
    Miter: Double;
  end;

  { What a slider dataZoom's option says about how it looks. }
  TTyDzSliderSpec = record
    Index: Integer;
    Show: Boolean;
    BrushSelect: Boolean;
    { showDataShadow: -1 'auto', 0 false, 1 true }
    ShowShadow: Integer;
    ShowDetail: Boolean;
    { handleLabel.show }
    LabelShow: Boolean;
    HandleIcon, MoveHandleIcon: string;
    HandleSize, MoveHandleSize: TTyBoxRaw;
    { labelPrecision: a number, or 'auto' / nothing (HasPrecision False) }
    HasPrecision: Boolean;
    Precision: Double;
    { labelFormatter, a template string }
    HasFormatter: Boolean;
    Formatter: string;
    { borderRadius: truthy (a non-zero number or any array) or not }
    HasRadius: Boolean;
    Radius: TTyDoubleArray;
    Z: Integer;
    { left / right / top / bottom / width / height as written: brAbsent
      where the option has no such key }
    Box: TTyRawBox;
    { the author's colours and widths }
    Filler, Frame, Background, Handle, MoveHandle, Brush: TTyDzStyleSpec;
    { [R5-D] emphasis.handleStyle / emphasis.moveHandleStyle: the hover
      states' styles, written over the normal ones }
    HandleEmph, MoveHandleEmph: TTyDzStyleSpec;
    { [R5-F] their shadows: emphasis' keys over the normal style's, key by
      key (the state's style merged over the normal one) }
    HandleEmphShadow, MoveHandleEmphShadow: TTyChartShadow;
    ShadowArea, ShadowLine: array[0..1] of TTyDzStyleSpec;
    HasText: Boolean;
    TextColour: TTyChartColor;
    FontSize: Integer;
    { [R5-A] textStyle.fontStyle as written (TyFontStyleCode) }
    FontStyle: Byte;
    { [R7-M] textStyle as written ('' none): the labels are createTextStyle
      of it, which the control resolves into the ink's block }
    TextStyleJson: string;
  end;

  { What the chart knows that the option does not. CSS px. }
  TTyDzSliderInput = record
    CanvasW, CanvasH: Double;
    { [Batch 154] createBoxLayoutReference's container when the slider is in
      a matrix cell or a calendar day (CSS px from the canvas' corner); the
      canvas when not HasRef }
    HasRef: Boolean;
    Ref: TTyXYWH;
    { _findCoordRect: the first target axis' grid, as laid out; without one
      the middle three fifths of the canvas }
    HasCoordRect: Boolean;
    CoordRect: TTyXYWH;
    Horizontal: Boolean;
    { the FIRST target axis' inverse }
    Inverse: Boolean;
    { the representative axis' window }
    Percent, Value: array[0..1] of Double;
    ValuePrecision: Double;
    { a category or time axis labels its ends with the scale's own label }
    LabelIsScale: Boolean;
    ScaleLabel: array[0..1] of string;
    { the data shadow: the series' raw columns along and across the axis }
    HasShadow: Boolean;
    OtherAxisInverse: Boolean;
    IsTime: Boolean;
    ThisVals, OtherVals: TTyDoubleArray;
    { THE VIEW'S STATE: the ends and range it kept (HasEnds False: from the
      window), the labels' visibility (HasLabelState False: handleLabel.show),
      the hover emphasis and the brush rect, sliderGroup-local }
    HasEnds: Boolean;
    Ends, ViewRange: array[0..1] of Double;
    HasLabelState, LabelsShown: Boolean;
    HandleHover: array[0..1] of Boolean;
    MoveHover: Boolean;
    HasBrush: Boolean;
    BrushX, BrushW: Double;
  end;

  TTyDzRole = (dzrBackground, dzrClickPanel, dzrFiller, dzrFrame, dzrHandle0,
    dzrHandle1, dzrMoveHandle, dzrMoveHandleIcon, dzrMoveZone, dzrShadow0,
    dzrShadow1, dzrShadow2, dzrShadowPolygon0, dzrShadowPolygon1,
    dzrShadowPolygon2, dzrShadowPolyline0, dzrShadowPolyline1,
    dzrShadowPolyline2, dzrLabel0, dzrLabel1);
  TTyDzRoleArray = array of TTyDzRole;

  { One element of the slider group, or one shadow group. Local: its own
    transform (a shadow polygon's and polyline's is their group's, which is
    the identity); Rect: getBoundingRect, local, the stroke included. }
  TTyDzElement = record
    Present: Boolean;
    { counted by a group's rect: not invisible }
    Included: Boolean;
    Local: TTyMat2D;
    Rect: TTyXYWH;
    { a rect's shape as set, and its `r` }
    Shape: TTyXYWH;
    HasR: Boolean;
    R: TTyDoubleArray;
    { the path the element holds, its own rect and its data's length }
    Path: TTyZrPath;
    PathRect: TTyXYWH;
    DataLen: Integer;
    { a shadow group's clip }
    Clip: TTyXYWH;
  end;
  TTyDzElements = array[TTyDzRole] of TTyDzElement;

  TTyDzLabel = record
    Text: string;
    { view group coordinates }
    X, Y: Double;
    AlignH: TTyTextAnchorH;
    AlignV: TTyTextAnchorV;
    Rect: TTyXYWH;
    Visible: Boolean;
    { [R7-M] the words as the ink's block, laid out at (X, Y) and hung
      about it, CSS px; none where the ink has no block }
    Pieces: TTyRtPieceArray;
  end;

  TTyDzSliderLayout = record
    Valid: Boolean;
    Index: Integer;
    Horizontal: Boolean;
    { _findCoordRect's answer }
    CoordRect: TTyXYWH;
    { _location, and _size as [length, thickness] }
    LocX, LocY, L, T: Double;
    Range, HandleEnds: array[0..1] of Double;
    HandleW, HandleH: Double;
    { NaN without the brush's move bar }
    MoveH: Double;
    ShadowDrawn: Boolean;
    Area, Line: TTyPointFArray;
    ThisExt, OtherExt: array[0..1] of Double;
    { the slider group's local transform; the view group's position }
    SG: TTyMat2D;
    GroupX, GroupY: Double;
    { what _positionGroup read }
    PosKids: TTyDzElements;
    PosSliderRect, PosGroupRect: TTyXYWH;
    { after _updateView }
    Kids: TTyDzElements;
    Labels: array[0..1] of TTyDzLabel;
    FinalSliderRect, FinalGroupRect: TTyXYWH;
    { the storage's display list: the painted ones, then the labels with no
      text }
    Paint: TTyDzRoleArray;
    Painted: Integer;
    { the emphasis and the brush, as the input gave them }
    HandleHover: array[0..1] of Boolean;
    MoveHover: Boolean;
    HasBrush: Boolean;
    BrushX, BrushW: Double;
  end;

  TTyDzInk = record
    Text: TTyChartColor;
    FontName: string;
    FontSizeLogical, FontWeight: Integer;
    Filler, Frame, Background, HandleFill, HandleStroke, MoveHandle,
      MoveIcon: TTyChartColor;
    { a hovered handle, a highlighted move bar, the brush }
    HandleHoverFill, HandleHoverStroke, MoveHandleHover, Brush: TTyChartColor;
    ShadowArea, ShadowLine: array[0..1] of TTyChartColor;
    { [R7-M] THE LABELS' BLOCK (HasRt): textStyle as free text, in the font
      above, over the root's side; device px per CSS px; the opacity,
      textStyle's own else the root's (HasOpacity False: neither) }
    HasRt: Boolean;
    Rt: TTyRtBlockStyle;
    RtGlobal: TTyRtGlobal;
    RtScale: Double;
    HasOpacity: Boolean;
    Opacity: Double;
  end;

function TyDzSliderSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyDzSliderSpec;

{ _resetLocation through the first _updateView. }
function TyLayoutDzSlider(const ASpec: TTyDzSliderSpec;
  const AIn: TTyDzSliderInput; const AMeasurer: ITyTextMeasurer;
  const AInk: TTyDzInk): TTyDzSliderLayout;

{ An element's transform to the canvas, CSS px. }
function TyDzGlobal(const ALayout: TTyDzSliderLayout; ARole: TTyDzRole): TTyMat2D;

{ The elements, at AOriginX/Y on the canvas, AScale device px per CSS px.
  SILENT: the component is not a datum. Answers how many were added. }
function TyBuildDzSliderMarks(const ALayout: TTyDzSliderLayout;
  const ASpec: TTyDzSliderSpec; const AInk: TTyDzInk;
  AOriginX, AOriginY, AScale: Double; AList: TTyPaintList): Integer;

{ ---- pieces, exported for the tests ---- }
{ the slider's box-layout merge: mergeLayoutParam over right / top /
  width / height 'ph' and left / bottom null }
function TyDzMergeBox(const AInput: TTyRawBox): TTyRawBox;
{ the data shadow's two point lists, sliderGroup-local }
procedure TyDzShadowPoints(const AThis, AOther: TTyDoubleArray; AL, AT: Double;
  AIsTime: Boolean; out AArea, ALine: TTyPointFArray; out AThisExt0, AThisExt1,
  AOtherExt0, AOtherExt1: Double);

const
  TyDzDefaultHandleIcon =
    'path://M-9.35,34.56V42m0-40V9.5m-2,0h4a2,2,0,0,1,2,2v21a2,2,0,0,1-2,2h-4' +
    'a2,2,0,0,1-2-2v-21A2,2,0,0,1-11.35,9.5Z';
  TyDzDefaultMoveHandleIcon =
    'path://M-320.9-50L-320.9-50c18.1,0,27.1,9,27.1,27.1V85.7c0,18.1-9,27.1-' +
    '27.1,27.1l0,0c-18.1,0-27.1-9-27.1-27.1V-22.9C-348-41-339-50-320.9-50z ' +
    'M-212.3-50L-212.3-50c18.1,0,27.1,9,27.1,27.1V85.7c0,18.1-9,27.1-27.1,' +
    '27.1l0,0c-18.1,0-27.1-9-27.1-27.1V-22.9C-239.4-41-230.4-50-212.3-50z ' +
    'M-103.7-50L-103.7-50c18.1,0,27.1,9,27.1,27.1V85.7c0,18.1-9,27.1-27.1,' +
    '27.1l0,0c-18.1,0-27.1-9-27.1-27.1V-22.9C-130.9-41-121.8-50-103.7-50z';

implementation

uses tyControls.AdvanceChart.JsMath, tyControls.AdvanceChart.Scale,
     tyControls.AdvanceChart.Data,
     tyControls.AdvanceChart.Symbol, tyControls.AdvanceChart.DataZoom,
     tyControls.AdvanceChart.Handlers, tyControls.AdvanceChart.States,
     { [R5-D] the emphasis proxy's liftColor }
     tyControls.AdvanceChart.Style;

{ ==================== small things ==================== }

const
  { a DOUBLE one: a bare real literal is a Single in FPC, and so is Math's
    Max of a double and an integer literal }
  One: Double = 1;

function JMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A < B then Result := A else Result := B;
end;

function JMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if A > B then Result := A else Result := B;
end;

function XYWH(AX, AY, AW, AH: Double): TTyXYWH;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

function Ident: TTyMat2D;
begin
  Result[0] := 1; Result[1] := 0; Result[2] := 0;
  Result[3] := 1; Result[4] := 0; Result[5] := 0;
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

function ColourOf(A: TJSONData; out AColour: TTyChartColor): Boolean;
begin
  Result := (A <> nil) and (A.JSONType = jtString)
    and TyTryParseChartColor(A.AsString, AColour);
  { [R7-AA] a string no parser reads (not '' nor 'none'): written, and the
    canvas refuses it, filling / stroking with what it had (the paint
    order settles cTyCanvasColourLeft) [was: not written, the theme's] }
  if not Result and (A <> nil) and (A.JSONType = jtString) and (A.AsString <> '')
    and (A.AsString <> 'none') then
  begin
    AColour := cTyCanvasColourLeft;
    Result := True;
  end;
end;

{ getItemStyle / getLineStyle / getAreaStyle, as far as they are read here.
  [R7-AC] AROOT: the block of the same path on the option's root -- the
  dataZoom's model's getModel climbs to the GlobalModel, so a key the block
  and its defaults (ADefaults: the keys SliderZoomModel's default block
  holds, the skin's here) leave out is the root's [was: the dataZoom's
  block alone]. APen: the pen's keys -- 'line' getLineStyle's (type,
  dashOffset, cap, join, miterLimit), 'item' getItemStyle's (border*), ''
  none }
procedure StyleOf(ANode, ARoot: TJSONObject; const AColourKey, AStrokeKey,
  AWidthKey, APen: string; const ADefaults: array of string; var AStyle: TTyDzStyleSpec);
var
  d: TJSONData;
  pre: string;
  wd: Byte;

  function Get(const AKey: string): TJSONData;
  var k: Integer;
  begin
    Result := nil;
    if ANode <> nil then Result := ANode.Find(AKey);
    if (Result <> nil) and (Result.JSONType <> jtNull) then Exit;
    Result := nil;
    if ARoot = nil then Exit;
    for k := 0 to High(ADefaults) do
      if ADefaults[k] = AKey then Exit;
    Result := ARoot.Find(AKey);
    if (Result <> nil) and (Result.JSONType = jtNull) then Result := nil;
  end;

begin
  if (ANode = nil) and (ARoot = nil) then Exit;
  if (AColourKey <> '') and ColourOf(Get(AColourKey), AStyle.Fill) then
    AStyle.HasFill := True;
  if (AStrokeKey <> '') and ColourOf(Get(AStrokeKey), AStyle.Stroke) then
    AStyle.HasStroke := True;
  if AWidthKey <> '' then
  begin
    d := Get(AWidthKey);
    if (d <> nil) and (d.JSONType = jtNumber) then AStyle.LineWidth := d.AsFloat;
  end;
  d := Get('opacity');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    AStyle.HasOpacity := True;
    AStyle.Opacity := d.AsFloat;
  end;
  { [R5-A] its shadow keys -- [R7-AC] the root's under them }
  if ARoot <> nil then TyStReadShadow([ANode, ARoot], [], [], AStyle.Shadow)
  else TyStReadShadow([ANode], [], [], AStyle.Shadow);
  if APen = '' then Exit;
  if APen = 'line' then pre := '' else pre := 'border';
  { the dash: lineStyle.type / itemStyle.borderType }
  if pre = '' then d := Get('type') else d := Get('borderType');
  if (d <> nil) and (d.JSONType = jtNumber) and (d.AsFloat <> 0) then
  begin
    AStyle.DashKind := todExplicit;
    AStyle.Dash := TTyDoubleArray.Create(d.AsFloat);
  end
  else if (d <> nil) and (d.JSONType = jtArray) then
  begin
    AStyle.Dash := TyLineDashOf(d, 1, wd);
    if Length(AStyle.Dash) = 0 then AStyle.DashKind := todSolid
    else AStyle.DashKind := todExplicit;
  end
  else if (d <> nil) and (d.JSONType = jtString) then
  begin
    if d.AsString = 'dashed' then AStyle.DashKind := todDashed
    else if d.AsString = 'dotted' then AStyle.DashKind := todDotted
    else AStyle.DashKind := todSolid;
  end;
  if pre = '' then d := Get('dashOffset') else d := Get('borderDashOffset');
  if d <> nil then AStyle.DashOffset := TyOptPenOffset(d);
  if pre = '' then d := Get('cap') else d := Get('borderCap');
  if d <> nil then AStyle.Cap := TyLineCapOf(d);
  if pre = '' then d := Get('join') else d := Get('borderJoin');
  if d <> nil then AStyle.Join := TyLineJoinOf(d);
  if pre = '' then d := Get('miterLimit') else d := Get('borderMiterLimit');
  if d <> nil then AStyle.Miter := TyOptMiterLimit(d);
end;

{ [R7-AC] the pen's own keys on an element that strokes at AW (CSS px): the
  dash (a word measured against the width), its phase, cap, join and
  miterLimit, each where written ([was: a solid butt pen]) }
procedure PenOn(var AEl: TTyChartElement; const AStyle: TTyDzStyleSpec; AW: Double);
begin
  AEl.Style.DashWord := TyDashWord(AStyle.DashKind);
  AEl.Style.DashLogical := TyDashPattern(AStyle.DashKind, AStyle.Dash, AW);
  if not IsNan(AStyle.DashOffset) then AEl.Style.DashOffsetLogical := AStyle.DashOffset;
  if AStyle.Cap >= 0 then AEl.Style.LineCap := AStyle.Cap;
  if AStyle.Join >= 0 then AEl.Style.LineJoin := AStyle.Join;
  if not IsNan(AStyle.Miter) then AEl.Style.MiterLimit := AStyle.Miter;
end;

{ [R7-AC] the hover's pen over the normal one, key by key }
function PenOver(const AEmph, ABase: TTyDzStyleSpec): TTyDzStyleSpec;
begin
  Result := ABase;
  if AEmph.DashKind <> todNone then
  begin
    Result.DashKind := AEmph.DashKind;
    Result.Dash := AEmph.Dash;
  end;
  if not IsNan(AEmph.DashOffset) then Result.DashOffset := AEmph.DashOffset;
  if AEmph.Cap >= 0 then Result.Cap := AEmph.Cap;
  if AEmph.Join >= 0 then Result.Join := AEmph.Join;
  if not IsNan(AEmph.Miter) then Result.Miter := AEmph.Miter;
end;

function BlankStyle: TTyDzStyleSpec;
begin
  Result := Default(TTyDzStyleSpec);
  Result.LineWidth := NaN;
  Result.DashOffset := NaN;
  Result.Cap := -1;
  Result.Join := -1;
  Result.Miter := NaN;
end;

{ ==================== the spec ==================== }

{ a key of a node that may be nil }
function OptFind(ANode: TJSONObject; const AKey: string): TJSONData;
begin
  if ANode = nil then Result := nil else Result := ANode.Find(AKey);
end;

function TyDzSliderSpecOf(AOption: TTyChartOption; AIndex: Integer): TTyDzSliderSpec;
var
  node, o, s, root, ro: TJSONObject;
  d: TJSONData;
  k: Integer;
  c: TTyChartColor;

  { [R7-AC] the root's block at a path ('' the root itself) }
  function RootAt(const AKey, ASub: string): TJSONObject;
  begin
    Result := nil;
    if root = nil then Exit;
    Result := ObjOf(root.Find(AKey));
    if (Result <> nil) and (ASub <> '') then Result := ObjOf(Result.Find(ASub));
  end;

begin
  Result := Default(TTyDzSliderSpec);
  Result.Index := AIndex;
  Result.Show := False;
  Result.BrushSelect := True;
  Result.ShowShadow := -1;
  Result.ShowDetail := True;
  Result.HandleIcon := TyDzDefaultHandleIcon;
  Result.MoveHandleIcon := TyDzDefaultMoveHandleIcon;
  Result.HandleSize := TyBoxRawStr('100%');
  Result.MoveHandleSize := TyBoxRawNum(7);
  Result.Z := 4;
  Result.Filler := BlankStyle;
  Result.Frame := BlankStyle;
  Result.Background := BlankStyle;
  Result.Handle := BlankStyle;
  Result.MoveHandle := BlankStyle;
  for k := 0 to 1 do
  begin
    Result.ShadowArea[k] := BlankStyle;
    Result.ShadowLine[k] := BlankStyle;
  end;
  if AOption = nil then Exit;
  node := ObjOf(AOption.ComponentAt('dataZoom', AIndex));
  if node = nil then Exit;
  root := nil;
  if AOption.Root is TJSONObject then root := TJSONObject(AOption.Root);
  d := node.Find('show');
  Result.Show := not ((d <> nil) and (d.JSONType = jtBoolean) and not d.AsBoolean);
  d := node.Find('brushSelect');
  if (d <> nil) and (d.JSONType <> jtNull) then Result.BrushSelect := JsTruthyOf(d);
  d := node.Find('showDataShadow');
  if (d <> nil) and (d.JSONType = jtBoolean) then
    if d.AsBoolean then Result.ShowShadow := 1 else Result.ShowShadow := 0;
  d := node.Find('showDetail');
  if (d <> nil) and (d.JSONType <> jtNull) then Result.ShowDetail := JsTruthyOf(d);
  o := ObjOf(node.Find('handleLabel'));
  if o <> nil then Result.LabelShow := JsTruthyOf(o.Find('show'));
  d := node.Find('handleIcon');
  if (d <> nil) and (d.JSONType = jtString) then Result.HandleIcon := d.AsString;
  d := node.Find('moveHandleIcon');
  if (d <> nil) and (d.JSONType = jtString) then Result.MoveHandleIcon := d.AsString;
  d := node.Find('handleSize');
  if (d <> nil) and (d.JSONType in [jtNumber, jtString]) then
    Result.HandleSize := TyBoxRawOf(d);
  d := node.Find('moveHandleSize');
  if (d <> nil) and (d.JSONType in [jtNumber, jtString]) then
    Result.MoveHandleSize := TyBoxRawOf(d);
  d := node.Find('labelPrecision');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.HasPrecision := True;
    Result.Precision := d.AsFloat;
  end
  else if (d <> nil) and (d.JSONType = jtString) and (d.AsString <> 'auto') then
  begin
    Result.HasPrecision := True;
    Result.Precision := TyJsToNumber(d.AsString);
  end;
  d := node.Find('labelFormatter');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.HasFormatter := True;
    Result.Formatter := d.AsString;
  end;
  d := node.Find('borderRadius');
  if d <> nil then
  begin
    Result.HasRadius := JsTruthyOf(d);
    if d.JSONType = jtNumber then
    begin
      SetLength(Result.Radius, 1);
      Result.Radius[0] := d.AsFloat;
    end
    else if d.JSONType = jtArray then
    begin
      SetLength(Result.Radius, TJSONArray(d).Count);
      for k := 0 to TJSONArray(d).Count - 1 do
        if TJSONArray(d).Items[k].JSONType = jtNumber then
          Result.Radius[k] := TJSONArray(d).Items[k].AsFloat
        else
          Result.Radius[k] := NaN;
    end;
  end;
  d := node.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Z := Trunc(d.AsFloat);
  { the box as written: an absent key stays brAbsent }
  Result.Box.Left := TyBoxRawOf(node.Find('left'));
  Result.Box.Right := TyBoxRawOf(node.Find('right'));
  Result.Box.Top := TyBoxRawOf(node.Find('top'));
  Result.Box.Bottom := TyBoxRawOf(node.Find('bottom'));
  Result.Box.Width := TyBoxRawOf(node.Find('width'));
  Result.Box.Height := TyBoxRawOf(node.Find('height'));
  { the colours }
  if ColourOf(node.Find('fillerColor'), c) then
  begin
    Result.Filler.HasFill := True;
    Result.Filler.Fill := c;
  end;
  { the frame: dataBackgroundColor (deprecated) before borderColor }
  if ColourOf(node.Find('dataBackgroundColor'), c) or ColourOf(node.Find('borderColor'), c) then
  begin
    Result.Frame.HasStroke := True;
    Result.Frame.Stroke := c;
  end;
  if ColourOf(node.Find('backgroundColor'), c) then
  begin
    Result.Background.HasFill := True;
    Result.Background.Fill := c;
  end;
  StyleOf(ObjOf(node.Find('handleStyle')), RootAt('handleStyle', ''), 'color', 'borderColor',
    'borderWidth', 'item', ['color', 'borderColor'], Result.Handle);
  { handleColor (deprecated) wins over the style's }
  if ColourOf(node.Find('handleColor'), c) then
  begin
    Result.Handle.HasFill := True;
    Result.Handle.Fill := c;
  end;
  StyleOf(ObjOf(node.Find('moveHandleStyle')), RootAt('moveHandleStyle', ''), 'color',
    'borderColor', 'borderWidth', 'item', ['color', 'opacity'], Result.MoveHandle);
  { [R5-D] the two hover states }
  Result.HandleEmph := BlankStyle;
  Result.MoveHandleEmph := BlankStyle;
  o := ObjOf(node.Find('emphasis'));
  ro := RootAt('emphasis', '');
  if (o <> nil) or (ro <> nil) then
  begin
    if ro <> nil then
    begin
      StyleOf(ObjOf(OptFind(o, 'handleStyle')), ObjOf(ro.Find('handleStyle')), 'color', 'borderColor',
        'borderWidth', 'item', ['borderColor'], Result.HandleEmph);
      StyleOf(ObjOf(OptFind(o, 'moveHandleStyle')), ObjOf(ro.Find('moveHandleStyle')), 'color',
        'borderColor', 'borderWidth', 'item', ['color'], Result.MoveHandleEmph);
    end
    else
    begin
      StyleOf(ObjOf(o.Find('handleStyle')), nil, 'color', 'borderColor', 'borderWidth', 'item', [],
        Result.HandleEmph);
      StyleOf(ObjOf(o.Find('moveHandleStyle')), nil, 'color', 'borderColor', 'borderWidth', 'item', [],
        Result.MoveHandleEmph);
    end;
  end;
  { [R5-F] the hover's shadows over the normal ones }
  if o <> nil then
  begin
    TyStReadShadow([ObjOf(o.Find('handleStyle')), ObjOf(node.Find('handleStyle'))], [], [],
      Result.HandleEmphShadow);
    TyStReadShadow([ObjOf(o.Find('moveHandleStyle')), ObjOf(node.Find('moveHandleStyle'))], [], [],
      Result.MoveHandleEmphShadow);
  end
  else
  begin
    Result.HandleEmphShadow := Result.Handle.Shadow;
    Result.MoveHandleEmphShadow := Result.MoveHandle.Shadow;
  end;
  Result.Brush := BlankStyle;
  StyleOf(ObjOf(node.Find('brushStyle')), RootAt('brushStyle', ''), 'color', 'borderColor',
    'borderWidth', 'item', ['color', 'opacity'], Result.Brush);
  o := ObjOf(node.Find('dataBackground'));
  StyleOf(ObjOf(OptFind(o, 'areaStyle')), RootAt('dataBackground', 'areaStyle'), 'color', '', '',
    '', ['color', 'opacity'], Result.ShadowArea[0]);
  StyleOf(ObjOf(OptFind(o, 'lineStyle')), RootAt('dataBackground', 'lineStyle'), '', 'color',
    'width', 'line', ['color', 'width'], Result.ShadowLine[0]);
  o := ObjOf(node.Find('selectedDataBackground'));
  StyleOf(ObjOf(OptFind(o, 'areaStyle')), RootAt('selectedDataBackground', 'areaStyle'), 'color',
    '', '', '', ['color', 'opacity'], Result.ShadowArea[1]);
  StyleOf(ObjOf(OptFind(o, 'lineStyle')), RootAt('selectedDataBackground', 'lineStyle'), '',
    'color', 'width', 'line', ['color', 'width'], Result.ShadowLine[1]);
  s := ObjOf(node.Find('textStyle'));
  if s <> nil then
  begin
    Result.TextStyleJson := s.AsJSON;
    if ColourOf(s.Find('color'), c) then
    begin
      Result.HasText := True;
      Result.TextColour := c;
    end;
    d := s.Find('fontSize');
    Result.FontSize := TyOptFontSize(d, Result.FontSize);
    Result.FontStyle := TyFontStyleCode(s.Find('fontStyle'));
  end;
end;

{ ==================== the box ==================== }

function Own(const A: TTyBoxRaw): Boolean;
begin
  Result := A.Kind <> brAbsent;
end;

{ hasValue: `!= null && !== 'auto'` }
function HasValue(const A: TTyBoxRaw): Boolean;
begin
  Result := not ((A.Kind in [brAbsent, brNull])
    or ((A.Kind = brString) and (A.Str = 'auto')));
end;

function TyDzMergeBox(const AInput: TTyRawBox): TTyRawBox;
var
  nul, ph: TTyBoxRaw;
  inp, tgt, outv: array[0..2] of TTyBoxRaw;
  k: Integer;

  { one direction: [size, start, end] }
  procedure Merge;
  var
    merged, np: array[0..2] of TTyBoxRaw;
    npOwn: array[0..2] of Boolean;
    newCount, mergedCount, i: Integer;
  begin
    newCount := 0;
    mergedCount := 0;
    for i := 0 to 2 do
    begin
      merged[i] := tgt[i];
      np[i] := Default(TTyBoxRaw);
      npOwn[i] := False;
    end;
    for i := 0 to 2 do
    begin
      if Own(inp[i]) then
      begin
        np[i] := inp[i];
        npOwn[i] := True;
        merged[i] := inp[i];
      end;
      if npOwn[i] and HasValue(np[i]) then Inc(newCount);
      if HasValue(merged[i]) then Inc(mergedCount);
    end;
    if (mergedCount = 2) or (newCount = 0) then
    begin
      for i := 0 to 2 do outv[i] := merged[i];
      Exit;
    end;
    if newCount < 2 then
      { the first of the three the author left out, from the target (every
        key is the target's own) }
      for i := 0 to 2 do
        if not npOwn[i] then
        begin
          np[i] := tgt[i];
          npOwn[i] := True;
          Break;
        end;
    for i := 0 to 2 do
      if npOwn[i] then outv[i] := np[i] else outv[i] := Default(TTyBoxRaw);
  end;

begin
  nul := Default(TTyBoxRaw);
  nul.Kind := brNull;
  ph := TyBoxRawStr('ph');
  { width, left, right }
  inp[0] := AInput.Width; inp[1] := AInput.Left; inp[2] := AInput.Right;
  for k := 0 to 2 do tgt[k] := inp[k];
  if not Own(tgt[0]) then tgt[0] := ph;
  if not Own(tgt[1]) then tgt[1] := nul;
  if not Own(tgt[2]) then tgt[2] := ph;
  Merge;
  Result.Width := outv[0]; Result.Left := outv[1]; Result.Right := outv[2];
  { height, top, bottom }
  inp[0] := AInput.Height; inp[1] := AInput.Top; inp[2] := AInput.Bottom;
  for k := 0 to 2 do tgt[k] := inp[k];
  if not Own(tgt[0]) then tgt[0] := ph;
  if not Own(tgt[1]) then tgt[1] := ph;
  if not Own(tgt[2]) then tgt[2] := nul;
  Merge;
  Result.Height := outv[0]; Result.Top := outv[1]; Result.Bottom := outv[2];
end;

{ ==================== the data shadow ==================== }

procedure TyDzShadowPoints(const AThis, AOther: TTyDoubleArray; AL, AT: Double;
  AIsTime: Boolean; out AArea, ALine: TTyPointFArray; out AThisExt0, AThisExt1,
  AOtherExt0, AOtherExt1: Double);
var
  n, index, stride: Integer;
  o0, o1, off, step, norm, coord, tv, ov, oc: Double;
  isEmpty, lastIsEmpty, haveLast: Boolean;

  procedure Push(var A: TTyPointFArray; AX, AY: Double);
  begin
    SetLength(A, Length(A) + 1);
    A[High(A)] := TyPointF(AX, AY);
  end;

  procedure Extent(const V: TTyDoubleArray; out AMin, AMax: Double);
  var i: Integer;
  begin
    AMin := Infinity;
    AMax := NegInfinity;
    for i := 0 to High(V) do
    begin
      if (not IsNan(V[i])) and (V[i] < AMin) then AMin := V[i];
      if (not IsNan(V[i])) and (V[i] > AMax) then AMax := V[i];
    end;
  end;

begin
  AArea := nil;
  ALine := nil;
  n := Length(AThis);
  Extent(AThis, AThisExt0, AThisExt1);
  Extent(AOther, AOtherExt0, AOtherExt1);
  off := (AOtherExt1 - AOtherExt0) * 0.3;
  o0 := AOtherExt0 - off;
  o1 := AOtherExt1 + off;
  Push(AArea, AL, 0);
  Push(AArea, 0, 0);
  step := AL / Math.Max(1, n - 1);
  norm := AL / (AThisExt1 - AThisExt0);
  coord := -step;
  { Math.round(count / length): every stride-th row is drawn, and the ones
    skipped still move the coordinate }
  stride := Trunc(TyJsRound(n / AL));
  lastIsEmpty := False;
  haveLast := False;
  for index := 0 to n - 1 do
  begin
    tv := AThis[index];
    if index <= High(AOther) then ov := AOther[index] else ov := NaN;
    if (stride > 0) and (index mod stride <> 0) then
    begin
      if not AIsTime then coord := coord + step;
      Continue;
    end;
    if AIsTime then coord := (tv - AThisExt0) * norm
    else coord := coord + step;
    isEmpty := IsNan(ov);
    if isEmpty then oc := 0
    else oc := TyDzLinearMap(ov, o0, o1, 0, AT, True);
    if isEmpty and not (haveLast and lastIsEmpty) and (index <> 0) then
    begin
      Push(AArea, AArea[High(AArea)].X, 0);
      if Length(ALine) > 0 then Push(ALine, ALine[High(ALine)].X, 0);
    end
    else if (not isEmpty) and haveLast and lastIsEmpty then
    begin
      Push(AArea, coord, 0);
      Push(ALine, coord, 0);
    end;
    if not isEmpty then
    begin
      Push(AArea, coord, oc);
      Push(ALine, coord, oc);
    end;
    lastIsEmpty := isEmpty;
    haveLast := True;
  end;
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

{ graphic.transformDirection }
function TransformDirection(const ADir: string; const M: TTyMat2D): string;
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
  TyZrApply(M, x, y, ox, oy);
  if Abs(ox) > Abs(oy) then
  begin
    if ox > 0 then Result := 'right' else Result := 'left';
  end
  else if oy > 0 then Result := 'bottom'
  else Result := 'top';
end;

function LabelText(const ASpec: TTyDzSliderSpec; const AIn: TTyDzSliderInput;
  AEnd: Integer): string;
var
  prm: TTyChartCallbackParams;
  p, v: Double;
  s: string;
  k: Integer;
begin
  if not ASpec.ShowDetail then Exit('');
  if ASpec.HasPrecision then p := ASpec.Precision else p := AIn.ValuePrecision;
  v := AIn.Value[AEnd];
  if IsNan(v) then s := ''
  else if AIn.LabelIsScale then s := AIn.ScaleLabel[AEnd]
  else if (not IsNan(p)) and (not IsInfinite(p)) then
    { min(max(0, p), 20) on the double: Math's overloads with an integer
      literal would take the Single one }
    s := TyJsToFixedStr(v, Trunc(JMax(JMin(p, 20.0 * One), 0.0 * One)))
  else
    s := TyJsNumberToString(v);
  if not ASpec.HasFormatter then Exit(s);
  { a named handler: upstream's labelFormatter(value, valueStr) }
  if TyChartIsHandlerRef(ASpec.Formatter) then
  begin
    prm := TyChartBlankParams;
    prm.ComponentType := 'dataZoom';
    SetLength(prm.Values, 1);
    prm.Values[0] := v;
    prm.ValueText := TyChartValueText(v);
    prm.DefaultText := s;
    Exit(TyChartRunHandler(ASpec.Formatter, TyChartOneParams(prm)));
  end;
  { String.replace with a string: the first occurrence only }
  Result := ASpec.Formatter;
  k := Pos('{value}', Result);
  if k > 0 then Result := Copy(Result, 1, k - 1) + s + Copy(Result, k + 7, MaxInt);
end;

{ ==================== the layout ==================== }

function StyleHasStroke(const AStyle: TTyDzStyleSpec; ADefault: Boolean): Boolean;
begin
  Result := ADefault or AStyle.HasStroke;
end;

function LineWidthOr(const AStyle: TTyDzStyleSpec; ADefault: Double): Double;
begin
  if IsNan(AStyle.LineWidth) then Result := ADefault else Result := AStyle.LineWidth;
end;

function LayoutSlider(const ASpec: TTyDzSliderSpec;
  const AIn: TTyDzSliderInput; const AMeasurer: ITyTextMeasurer;
  const AInk: TTyDzInk): TTyDzSliderLayout;
const
  cTrav: array[0..7] of TTyDzRole = (dzrLabel0, dzrLabel1, dzrBackground,
    dzrClickPanel, dzrFiller, dzrFrame, dzrHandle0, dzrHandle1);
  cTravMove: array[0..2] of TTyDzRole = (dzrMoveHandle, dzrMoveHandleIcon,
    dzrMoveZone);
var
  merged, params: TTyRawBox;
  cr, lr, hpRect, hRect, iconRect, ref: TTyXYWH;
  W, H, mhs, edgeGap, L, T, hh, hw, mh, iconSize, iconY, sx, sy, rot,
    offset, px, py, tw, th, ty, sc: Double;
  hi: array[0..1] of Double;
  b: TTyRtBlockStyle;
  bb: TTyXYWH;
  hp, iconP: TTyZrPath;
  handleLw: Double;
  i, k, n: Integer;
  icon, dir: string;
  have: Boolean;
  r: TTyXYWH;
  role: TTyDzRole;
  z2: array[TTyDzRole] of Integer;
  trav: TTyDzRoleArray;

  procedure Ph(var A: TTyBoxRaw; AValue: Double);
  begin
    if (A.Kind = brString) and (A.Str = 'ph') then A := TyBoxRawNum(AValue);
  end;

  { one rect element: its path, and its rect with the stroke }
  function RectKid(const AShape: TTyXYWH; AHasR: Boolean; const AR: array of Double;
    AOptimize: Boolean; AHasStroke: Boolean; ALw: Double): TTyDzElement;
  var
    s: TTyXYWH;
    r1, r2, r3, r4: Double;
    j: Integer;
  begin
    Result := Default(TTyDzElement);
    Result.Present := True;
    Result.Included := True;
    Result.Local := Ident;
    Result.Shape := AShape;
    Result.HasR := AHasR;
    SetLength(Result.R, Length(AR));
    for j := 0 to High(AR) do Result.R[j] := AR[j];
    s := AShape;
    if AOptimize then s := TyZrSubPixelOptimizeRect(AShape, ALw);
    if not AHasR then
      TyZrRect(Result.Path, s.X, s.Y, s.W, s.H)
    else
    begin
      TyZrRadii(AR, r1, r2, r3, r4);
      TyZrRoundRect(Result.Path, s.X, s.Y, s.W, s.H, r1, r2, r3, r4);
    end;
    Result.PathRect := TyZrBBox(Result.Path);
    Result.DataLen := TyZrDataLength(Result.Path);
    Result.Rect := TyZrStrokeRect(Result.PathRect, Result.DataLen, AHasStroke,
      True, ALw, 1);
  end;

  { the slider group's children at one moment }
  procedure Shapes(AFinal: Boolean; var AKids: TTyDzElements);
  var
    j: Integer;
    full, fs: TTyXYWH;
    e: TTyDzElement;
    expand: Double;
    pa, pl: TTyZrPath;
    ra, rl, g: TTyXYWH;
    haveG: Boolean;
    rr: TTyDzRole;
  begin
    for rr := Low(TTyDzRole) to High(TTyDzRole) do AKids[rr] := Default(TTyDzElement);
    full := XYWH(0, 0, L, T);
    AKids[dzrBackground] := RectKid(full, False, [], False, False, 1);
    AKids[dzrClickPanel] := RectKid(full, False, [], False, False, 1);
    if AFinal then fs := XYWH(hi[0], 0, hi[1] - hi[0], T) else fs := XYWH(0, 0, 0, 0);
    AKids[dzrFiller] := RectKid(fs, False, [], False, False, 1);
    { the frame: subPixelOptimize, a one-pixel line over a transparent fill }
    AKids[dzrFrame] := RectKid(full, ASpec.HasRadius, ASpec.Radius, True, True, 1);
    for j := 0 to 1 do
    begin
      e := Default(TTyDzElement);
      e.Present := True;
      e.Included := True;
      e.Path := hp;
      e.PathRect := hpRect;
      e.DataLen := TyZrDataLength(hp);
      e.Rect := hRect;
      if AFinal then
      begin
        { the unsorted ends, a pixel inside each }
        if j = 0 then px := Result.HandleEnds[0] + 1 else px := Result.HandleEnds[1] - 1;
        e.Local := TyZrLocal(hh / 2, hh / 2, 0, px, T / 2 - hh / 2);
      end
      else
        e.Local := Ident;
      AKids[TTyDzRole(Ord(dzrHandle0) + j)] := e;
    end;
    if ASpec.BrushSelect then
    begin
      if AFinal then fs := XYWH(hi[0], T - 0.5, hi[1] - hi[0], mh)
      else fs := XYWH(0, T - 0.5, 0, mh);
      AKids[dzrMoveHandle] := RectKid(fs, True, [0, 0, 2, 2], False,
        ASpec.MoveHandle.HasStroke, LineWidthOr(ASpec.MoveHandle, 1));
      e := Default(TTyDzElement);
      e.Present := True;
      e.Included := True;
      e.Path := iconP;
      e.PathRect := iconRect;
      e.DataLen := TyZrDataLength(iconP);
      e.Rect := iconRect;
      if AFinal then e.Local := TyZrLocal(1, 1, 0, hi[0] + (hi[1] - hi[0]) / 2, iconY)
      else e.Local := TyZrLocal(1, 1, 0, 0, iconY);
      AKids[dzrMoveHandleIcon] := e;
      expand := JMin(T / 2, JMax(mh, 10.0 * One));
      if AFinal then fs := XYWH(hi[0], T - expand, hi[1] - hi[0], mh + expand)
      else fs := XYWH(0, T - expand, 0, mh + expand);
      AKids[dzrMoveZone] := RectKid(fs, False, [], False, False, 1);
      AKids[dzrMoveZone].Included := False;
    end;
    if Result.ShadowDrawn then
      for j := 0 to 2 do
      begin
        pa := TyZrPolyPath(Result.Area, True);
        pl := TyZrPolyPath(Result.Line, False);
        { the polygon fills and does not stroke; the polyline strokes and
          does not fill, so it grows by at least five }
        ra := TyZrStrokeRect(TyZrBBox(pa), TyZrDataLength(pa), False, True, 1, 1);
        rl := TyZrStrokeRect(TyZrBBox(pl), TyZrDataLength(pl), True, False,
          LineWidthOr(ASpec.ShadowLine[Ord(j = 1)], 0.5), 1);
        haveG := False;
        g := XYWH(0, 0, 0, 0);
        TyZrAccumulate(g, haveG, ra, Ident);
        TyZrAccumulate(g, haveG, rl, Ident);
        e := Default(TTyDzElement);
        e.Present := True;
        e.Included := True;
        e.Local := Ident;
        e.Rect := g;
        AKids[TTyDzRole(Ord(dzrShadow0) + j)] := e;
        e := Default(TTyDzElement);
        e.Present := True;
        e.Included := True;
        e.Local := Ident;
        e.Path := pa;
        e.PathRect := TyZrBBox(pa);
        e.DataLen := TyZrDataLength(pa);
        e.Rect := ra;
        AKids[TTyDzRole(Ord(dzrShadowPolygon0) + j)] := e;
        e.Path := pl;
        e.PathRect := TyZrBBox(pl);
        e.DataLen := TyZrDataLength(pl);
        e.Rect := rl;
        AKids[TTyDzRole(Ord(dzrShadowPolyline0) + j)] := e;
      end;
  end;

  { Group.getBoundingRect over the slider group's included children }
  function KidsRect(const AKids: TTyDzElements): TTyXYWH;
  var rr: TTyDzRole;
  begin
    Result := XYWH(0, 0, 0, 0);
    have := False;
    for rr := dzrBackground to dzrShadow2 do
      if AKids[rr].Present and AKids[rr].Included then
        TyZrAccumulate(Result, have, AKids[rr].Rect, AKids[rr].Local);
  end;

begin
  Result := Default(TTyDzSliderLayout);
  Result.Index := ASpec.Index;
  Result.MoveH := NaN;
  if not ASpec.Show then Exit;
  Result.Horizontal := AIn.Horizontal;
  W := AIn.CanvasW;
  H := AIn.CanvasH;
  { _findCoordRect }
  if AIn.HasCoordRect then cr := AIn.CoordRect
  else cr := XYWH(W * 0.2, H * 0.2, W * 0.6, H * 0.6);
  Result.CoordRect := cr;
  { _resetLocation: the box merged over the slider's placeholders, then
    each 'ph' from where a slider goes by default -- under the grid, or
    right of it. The move bar's height here is the CONSTANT 7, not the
    option. }
  merged := TyDzMergeBox(ASpec.Box);
  if ASpec.BrushSelect then mhs := 7 else mhs := 0;
  edgeGap := 15;
  params := merged;
  { the refContainer: the canvas, or the slider's cell [Batch 154] -- the
    placeholders take its size and the grid's rect as they are, the frames
    mixed as upstream mixes them }
  if AIn.HasRef then ref := AIn.Ref
  else ref := XYWH(0, 0, W, H);
  if AIn.Horizontal then
  begin
    Ph(params.Right, ref.W - cr.X - cr.W);
    Ph(params.Top, ref.H - 30 - edgeGap - mhs);
    Ph(params.Width, cr.W);
    Ph(params.Height, 30);
  end
  else
  begin
    Ph(params.Right, edgeGap);
    Ph(params.Top, cr.Y);
    Ph(params.Width, 30);
    Ph(params.Height, cr.H);
  end;
  lr := TyGetLayoutRect(params, ref.X, ref.Y, ref.W, ref.H, []);
  Result.LocX := lr.X;
  Result.LocY := lr.Y;
  if AIn.Horizontal then
  begin
    L := lr.W;
    T := lr.H;
  end
  else
  begin
    L := lr.H;
    T := lr.W;
  end;
  Result.L := L;
  Result.T := T;
  { _resetInterval: the PERCENT window, not the inverted one -- unless the
    view kept its own ends }
  for k := 0 to 1 do
    if AIn.HasEnds then
    begin
      Result.Range[k] := AIn.ViewRange[k];
      Result.HandleEnds[k] := AIn.Ends[k];
    end
    else
    begin
      Result.Range[k] := AIn.Percent[k];
      Result.HandleEnds[k] := TyDzLinearMap(AIn.Percent[k], 0, 100, 0, L, True);
    end;
  for k := 0 to 1 do Result.HandleHover[k] := AIn.HandleHover[k];
  Result.MoveHover := AIn.MoveHover;
  Result.HasBrush := AIn.HasBrush;
  Result.BrushX := AIn.BrushX;
  Result.BrushW := AIn.BrushW;
  if Result.HandleEnds[0] > Result.HandleEnds[1] then
  begin
    hi[0] := Result.HandleEnds[1];
    hi[1] := Result.HandleEnds[0];
  end
  else
  begin
    hi[0] := Result.HandleEnds[0];
    hi[1] := Result.HandleEnds[1];
  end;
  { the handles: an icon neither built in nor a path nor an image is a
    path; fitted into (-1, 0, 2, 2) }
  icon := ASpec.HandleIcon;
  if (not TyZrIsBuiltinSymbol(icon)) and (Pos('path://', icon) = 0)
    and (Pos('image://', icon) = 0) then
    icon := 'path://' + icon;
  hp := TyZrSymbol(icon, -1, 0, 2, 2);
  hpRect := TyZrBBox(hp);
  hh := TyBoxRawResolve(ASpec.HandleSize, T);
  hw := hpRect.W / hpRect.H * hh;
  Result.HandleW := hw;
  Result.HandleH := hh;
  handleLw := LineWidthOr(ASpec.Handle, 1);
  { strokeNoScale with no global transform yet: a line scale of one }
  hRect := TyZrStrokeRect(hpRect, TyZrDataLength(hp), True, True, handleLw, 1);
  { the brush's move bar }
  mh := NaN;
  iconY := 0;
  iconP := nil;
  iconRect := XYWH(0, 0, 0, 0);
  if ASpec.BrushSelect then
  begin
    mh := TyBoxRawResolve(ASpec.MoveHandleSize, T);
    iconSize := mh * 0.8;
    iconP := TyZrSymbol(ASpec.MoveHandleIcon, -iconSize / 2, -iconSize / 2,
      iconSize, iconSize);
    iconRect := TyZrBBox(iconP);
    iconY := T + mh / 2 - 0.5;
    Result.MoveH := mh;
  end;
  { the data shadow }
  Result.ShadowDrawn := AIn.HasShadow;
  if AIn.HasShadow then
    TyDzShadowPoints(AIn.ThisVals, AIn.OtherVals, L, T, AIn.IsTime, Result.Area,
      Result.Line, Result.ThisExt[0], Result.ThisExt[1], Result.OtherExt[0],
      Result.OtherExt[1]);
  { the two moments }
  Shapes(False, Result.PosKids);
  Shapes(True, Result.Kids);
  { the slider group: flipped so the shadow grows up, turned for a vertical
    slider, mirrored for an inverse axis }
  if AIn.Horizontal then
  begin
    if AIn.OtherAxisInverse then sy := 1 else sy := -1;
    rot := 0;
  end
  else
  begin
    if AIn.OtherAxisInverse then sy := -1 else sy := 1;
    rot := Pi / 2;
  end;
  if AIn.Inverse then sx := -1 else sx := 1;
  Result.SG := TyZrLocal(sx, sy, rot, 0, 0);
  { _positionGroup }
  Result.PosSliderRect := KidsRect(Result.PosKids);
  have := False;
  r := XYWH(0, 0, 0, 0);
  TyZrAccumulate(r, have, Result.PosSliderRect, Result.SG);
  Result.PosGroupRect := r;
  if IsNan(r.X) then Result.GroupX := Result.LocX else Result.GroupX := Result.LocX - r.X;
  if IsNan(r.Y) then Result.GroupY := Result.LocY else Result.GroupY := Result.LocY - r.Y;
  { the shadow groups' clips }
  if Result.ShadowDrawn then
  begin
    Result.Kids[dzrShadow0].Clip := XYWH(0, 0, hi[0] - 0, T);
    Result.Kids[dzrShadow1].Clip := XYWH(hi[0], 0, hi[1] - hi[0], T);
    Result.Kids[dzrShadow2].Clip := XYWH(hi[1], 0, L - hi[1], T);
  end;
  { the labels, in the view group: beside each window end, out by half a
    handle and a gap }
  for k := 0 to 1 do
  begin
    if k = 0 then dir := TransformDirection('right', Result.SG)
    else dir := TransformDirection('left', Result.SG);
    offset := hw / 2 + 5;
    if k = 0 then TyZrApply(Result.SG, hi[0] - offset, T / 2, px, py)
    else TyZrApply(Result.SG, hi[1] + offset, T / 2, px, py);
    Result.Labels[k].Text := LabelText(ASpec, AIn, k);
    Result.Labels[k].X := px;
    Result.Labels[k].Y := py;
    if AIn.Horizontal then
    begin
      Result.Labels[k].AlignV := tavMiddle;
      Result.Labels[k].AlignH := WordH(dir);
    end
    else
    begin
      Result.Labels[k].AlignV := WordV(dir);
      Result.Labels[k].AlignH := tahCentre;
    end;
    if AIn.HasLabelState then Result.Labels[k].Visible := AIn.LabelsShown
    else Result.Labels[k].Visible := ASpec.LabelShow;
    if Result.Labels[k].Text = '' then
      Result.Labels[k].Rect := XYWH(0, 0, 0, 0)
    else if AInk.HasRt and (AMeasurer <> nil) then
    begin
      { [R7-M] THE BLOCK: createTextStyle(textStyleModel, {x, y, align,
        verticalAlign, fill: getTextColor()}) -- laid out at the style's
        place, its rect the union of its children }
      b := AInk.Rt;
      TyRtFinish(b, AInk.FontName, AInk.FontSizeLogical, AInk.FontWeight,
        AInk.RtGlobal, False, 0);
      b.Style.HasFill := True;
      b.Style.FillNone := False;
      if ASpec.HasText then b.Style.Fill := ASpec.TextColour
      else b.Style.Fill := AInk.Text;
      b.Style.Align := rtaNone;
      b.Style.VAlign := rtvNone;
      b.Style.HasOpacity := False;
      sc := AInk.RtScale;
      if sc <= 0 then sc := 1;
      Result.Labels[k].Pieces := TyRtLayHung(Result.Labels[k].Text, b,
        TyRtDefaultOf(False, 0, False, 0, False, Result.Labels[k].AlignH,
        Result.Labels[k].AlignV), px, py, sc, AMeasurer);
      bb := TyRtBounds(Result.Labels[k].Pieces);
      if bb.W < 0 then Result.Labels[k].Rect := XYWH(px, py, 0, 0)
      else Result.Labels[k].Rect := XYWH(px + bb.X, py + bb.Y, bb.W, bb.H);
    end
    else
    begin
      tw := 0;
      th := 0;
      if AMeasurer <> nil then
        AMeasurer.MeasureLine(Result.Labels[k].Text, AInk.FontName,
          AInk.FontSizeLogical, AInk.FontWeight, tw, th);
      ty := AdjustY(py, th, Result.Labels[k].AlignV) + th / 2;
      r := XYWH(AdjustX(px, tw, Result.Labels[k].AlignH), ty - th / 2, tw, th);
      Result.Labels[k].Rect := TyRectUnion(r, r);
    end;
  end;
  { the final rects }
  Result.FinalSliderRect := KidsRect(Result.Kids);
  have := False;
  r := XYWH(0, 0, 0, 0);
  for k := 0 to 1 do
    if Result.Labels[k].Visible then
      TyZrAccumulate(r, have, Result.Labels[k].Rect, Ident);
  TyZrAccumulate(r, have, Result.FinalSliderRect, Result.SG);
  Result.FinalGroupRect := r;
  { the paint order: the traversal, stable on z2; a label with no text
    paints nothing and goes last }
  for role := Low(TTyDzRole) to High(TTyDzRole) do z2[role] := 0;
  z2[dzrBackground] := -40;
  { a hovered handle rises by ten (the emphasis state's z2) }
  z2[dzrHandle0] := 5 + 10 * Ord(AIn.HandleHover[0]);
  z2[dzrHandle1] := 5 + 10 * Ord(AIn.HandleHover[1]);
  z2[dzrLabel0] := 10;
  z2[dzrLabel1] := 10;
  for k := 0 to 2 do
  begin
    z2[TTyDzRole(Ord(dzrShadowPolygon0) + k)] := -20;
    z2[TTyDzRole(Ord(dzrShadowPolyline0) + k)] := -19;
  end;
  trav := nil;
  n := 0;
  SetLength(trav, 20);
  for k := 0 to High(cTrav) do
  begin
    trav[n] := cTrav[k];
    Inc(n);
  end;
  if ASpec.BrushSelect then
    for k := 0 to High(cTravMove) do
    begin
      trav[n] := cTravMove[k];
      Inc(n);
    end;
  if Result.ShadowDrawn then
    for k := 0 to 2 do
    begin
      trav[n] := TTyDzRole(Ord(dzrShadowPolygon0) + k);
      trav[n + 1] := TTyDzRole(Ord(dzrShadowPolyline0) + k);
      Inc(n, 2);
    end;
  SetLength(trav, n);
  SetLength(Result.Paint, 0);
  { the painted ones, a stable insertion sort on z2 }
  for i := 0 to n - 1 do
  begin
    role := trav[i];
    if (role in [dzrLabel0, dzrLabel1])
      and (Result.Labels[Ord(role) - Ord(dzrLabel0)].Text = '') then Continue;
    k := Length(Result.Paint);
    SetLength(Result.Paint, k + 1);
    while (k > 0) and (z2[Result.Paint[k - 1]] > z2[role]) do
    begin
      Result.Paint[k] := Result.Paint[k - 1];
      Dec(k);
    end;
    Result.Paint[k] := role;
  end;
  Result.Painted := Length(Result.Paint);
  for i := 0 to n - 1 do
  begin
    role := trav[i];
    if (role in [dzrLabel0, dzrLabel1])
      and (Result.Labels[Ord(role) - Ord(dzrLabel0)].Text = '') then
    begin
      k := Length(Result.Paint);
      SetLength(Result.Paint, k + 1);
      Result.Paint[k] := role;
    end;
  end;
  Result.Valid := True;
end;

{ THE TRAPS OFF: the arithmetic is JavaScript's, and a zero span -- every
  row at one x -- divides by nought upstream and carries on with Infinity.
  The pending flags go before the old mask comes back (the SSE ones too,
  which ClearExceptions leaves standing on this CPU). }
function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

function TyLayoutDzSlider(const ASpec: TTyDzSliderSpec;
  const AIn: TTyDzSliderInput; const AMeasurer: ITyTextMeasurer;
  const AInk: TTyDzInk): TTyDzSliderLayout;
var mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    Result := LayoutSlider(ASpec, AIn, AMeasurer, AInk);
  finally
    UnmaskFP(mask);
  end;
end;

function TyDzGlobal(const ALayout: TTyDzSliderLayout; ARole: TTyDzRole): TTyMat2D;
var G: TTyMat2D;
begin
  { graphic.getTransform: each ancestor's local on the left of what is
    already there, walking up from the element }
  G := TyZrLocal(1, 1, 0, ALayout.GroupX, ALayout.GroupY);
  if ARole in [dzrLabel0, dzrLabel1] then Exit(TyMatMul(G, Ident));
  Result := TyMatMul(G, TyMatMul(ALayout.SG,
    TyMatMul(ALayout.Kids[ARole].Local, Ident)));
end;

{ ==================== the marks ==================== }

function WithOpacity(AColour: TTyChartColor; AOpacity: Double): TTyChartColor;
begin
  if AOpacity >= 1 then Exit(AColour);
  if AOpacity <= 0 then Exit(AColour and $00FFFFFF);
  Result := (AColour and $00FFFFFF)
    or (Cardinal(Round((AColour shr 24) * AOpacity)) shl 24);
end;

{ The author's colour at the author's opacity, or upstream's default
  opacity over the author's colour; the theme's colour, alpha and all,
  where the author wrote none. }
function Ink(const AStyle: TTyDzStyleSpec; AFill: Boolean; ATheme: TTyChartColor;
  ADefaultOpacity: Double): TTyChartColor;
var own: Boolean; c: TTyChartColor; op: Double;
begin
  if AFill then
  begin
    own := AStyle.HasFill;
    c := AStyle.Fill;
  end
  else
  begin
    own := AStyle.HasStroke;
    c := AStyle.Stroke;
  end;
  if AStyle.HasOpacity then op := AStyle.Opacity
  else if own then op := ADefaultOpacity
  else op := 1;
  if not own then c := ATheme;
  Result := WithOpacity(c, op);
end;

function TyBuildDzSliderMarks(const ALayout: TTyDzSliderLayout;
  const ASpec: TTyDzSliderSpec; const AInk: TTyDzInk;
  AOriginX, AOriginY, AScale: Double; AList: TTyPaintList): Integer;
var
  D: TTyMat2D;
  el: TTyChartElement;
  p: Integer;
  role: TTyDzRole;
  { [R5-D] a hovered handle's inks }
  op: Double;
  hf, hs: TTyChartColor;

  function Blank(ARole: TTyDzRole): TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Z := ASpec.Z;
    Result.Silent := True;
    Result.Datum := TyChartDatum(-1, -1);
    Result.Style.Alpha := 1;
    case ARole of
      dzrBackground: Result.Z2 := -40;
      dzrShadowPolygon0..dzrShadowPolygon2: Result.Z2 := -20;
      dzrShadowPolyline0..dzrShadowPolyline2: Result.Z2 := -19;
      dzrHandle0: Result.Z2 := 5 + 10 * Ord(ALayout.HandleHover[0]);
      dzrHandle1: Result.Z2 := 5 + 10 * Ord(ALayout.HandleHover[1]);
      dzrLabel0, dzrLabel1: Result.Z2 := 10;
    else
      Result.Z2 := 0;
    end;
  end;

  { the element's transform to the device }
  function Dev(ARole: TTyDzRole): TTyMat2D;
  begin
    Result := TyMatMul(D, TyDzGlobal(ALayout, ARole));
  end;

  function DevRect(const ARect: TTyXYWH; const M: TTyMat2D): TTyRectF;
  var r: TTyXYWH;
  begin
    r := TyRectApplyMat(ARect, M);
    Result := TyRectF(r.X, r.Y, r.X + r.W, r.Y + r.H);
  end;

  { a rect's corners carried through M: which device corner each local one
    lands on }
  function RectShape(const ARect: TTyXYWH; AHasR: Boolean;
    const AR: TTyDoubleArray; const M: TTyMat2D): TTyChartShape;
  var
    rr: array[0..3] of Double;
    out_: array[0..3] of Double;
    cx, cy, lx, ly, gx, gy, mx, my: Double;
    j, q: Integer;
    b: TTyRectF;
  begin
    b := DevRect(ARect, M);
    if not AHasR then Exit(TyShapeRect(b));
    TyZrRadii(AR, rr[0], rr[1], rr[2], rr[3]);
    for j := 0 to 3 do out_[j] := 0;
    cx := ARect.X + ARect.W / 2;
    cy := ARect.Y + ARect.H / 2;
    TyZrApply(M, cx, cy, mx, my);
    for j := 0 to 3 do
    begin
      { tl, tr, br, bl }
      if j in [0, 3] then lx := ARect.X else lx := ARect.X + ARect.W;
      if j in [0, 1] then ly := ARect.Y else ly := ARect.Y + ARect.H;
      TyZrApply(M, lx, ly, gx, gy);
      if gy <= my then
      begin
        if gx <= mx then q := 0 else q := 1;
      end
      else if gx <= mx then q := 3
      else q := 2;
      if IsNan(rr[j]) then out_[q] := 0 else out_[q] := rr[j] * AScale;
    end;
    Result := TyShapeRoundRect(b, out_);
  end;

  procedure Symbol(const AIcon: string; const AE: TTyDzElement; const M: TTyMat2D;
    AFill, AStroke: TTyChartColor; AHasStroke: Boolean; ALw: Double);
  var
    spec: TTySymbolSpec;
    empty: Boolean;
    path: string;
    cx, cy, ssx, ssy: Double;
    ib: TTyRectF;
    q: array[0..3] of TTyPointF;
  begin
    spec := Default(TTySymbolSpec);
    spec.Kind := TySymbolKindOf(AIcon, empty, path);
    if spec.Kind = tsyNone then Exit;
    spec.PathData := path;
    { [F6a] createSymbol(icon, ..., null, true): an image icon is centred
      to its own aspect in its box (makeImage 'center'), its corners through
      the element's whole matrix -- the slider group's flip included }
    if spec.Kind = tsyImage then
    begin
      ib := TyImageCenterBox(path, TyRectF(AE.PathRect.X, AE.PathRect.Y,
        AE.PathRect.X + AE.PathRect.W, AE.PathRect.Y + AE.PathRect.H));
      TyZrApply(M, ib.Left, ib.Top, q[0].X, q[0].Y);
      TyZrApply(M, ib.Right, ib.Top, q[1].X, q[1].Y);
      TyZrApply(M, ib.Right, ib.Bottom, q[2].X, q[2].Y);
      TyZrApply(M, ib.Left, ib.Bottom, q[3].X, q[3].Y);
      el.Shape := TyShapePolygon(q);
      el.Shape.Image := path;
      AList.Add(el);
      Inc(Result);
      Exit;
    end;
    ssx := Sqrt(M[0] * M[0] + M[1] * M[1]);
    ssy := Sqrt(M[2] * M[2] + M[3] * M[3]);
    spec.WidthPx := AE.PathRect.W * ssx;
    spec.HeightPx := AE.PathRect.H * ssy;
    spec.RotateDeg := RadToDeg(TyJsAtan2(M[1], M[0]));
    TyZrApply(M, AE.PathRect.X + AE.PathRect.W / 2, AE.PathRect.Y + AE.PathRect.H / 2,
      cx, cy);
    el.Shape := TyBuildSymbol(spec, cx, cy);
    { [R7-AC] the frame it is brushed in (its whole transform): its pen
      strokeNoScale, the canvas' lineWidth and lineDashOffset are in it --
      what it hands on, and a phase it takes from the canvas, are measured
      there }
    el.CanvasM := TTyDoubleArray.Create(M[0], M[1], M[2], M[3], M[4], M[5]);
    el.Style.HasFill := True;
    el.Style.FillColor := AFill;
    if AHasStroke then
    begin
      el.Style.StrokeColor := AStroke;
      el.Style.StrokeWidthLogical := ALw;
    end;
    AList.Add(el);
    Inc(Result);
  end;

  procedure Poly(ARole: TTyDzRole; const APoints: TTyPointFArray; AClose: Boolean);
  var
    pts: TTyPointFArray;
    j, gi: Integer;
    x, y: Double;
    M: TTyMat2D;
  begin
    if Length(APoints) < 2 then Exit;
    M := Dev(ARole);
    SetLength(pts, Length(APoints));
    for j := 0 to High(APoints) do
    begin
      TyZrApply(M, APoints[j].X, APoints[j].Y, x, y);
      pts[j] := TyPointF(x, y);
    end;
    el := Blank(ARole);
    if AClose then el.Shape := TyShapePolygon(pts) else el.Shape := TyShapePolyline(pts);
    gi := Ord(ARole) - Ord(dzrShadowPolygon0);
    if not AClose then gi := Ord(ARole) - Ord(dzrShadowPolyline0);
    el.HasClip := True;
    el.ClipRect := DevRect(ALayout.Kids[TTyDzRole(Ord(dzrShadow0) + gi)].Clip,
      TyMatMul(D, TyDzGlobal(ALayout, TTyDzRole(Ord(dzrShadow0) + gi))));
    if AClose then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := Ink(ASpec.ShadowArea[Ord(gi = 1)], True,
        AInk.ShadowArea[Ord(gi = 1)], 0.2 + 0.1 * Ord(gi = 1));
      TyStyleSetShadow(el.Style, ASpec.ShadowArea[Ord(gi = 1)].Shadow);
    end
    else
    begin
      el.Style.StrokeColor := Ink(ASpec.ShadowLine[Ord(gi = 1)], False,
        AInk.ShadowLine[Ord(gi = 1)], 1);
      el.Style.StrokeWidthLogical := LineWidthOr(ASpec.ShadowLine[Ord(gi = 1)], 0.5);
      TyStyleSetShadow(el.Style, ASpec.ShadowLine[Ord(gi = 1)].Shadow);
      { [R7-AC] getLineStyle's dash, phase, cap, join, miterLimit }
      PenOn(el, ASpec.ShadowLine[Ord(gi = 1)], el.Style.StrokeWidthLogical);
    end;
    AList.Add(el);
    Inc(Result);
  end;

var
  e: TTyDzElement;
  lb: TTyDzLabel;
  M: TTyMat2D;
  function Finite(A: Double): Boolean;
  begin
    Result := not (IsNan(A) or IsInfinite(A));
  end;

begin
  Result := 0;
  if not ALayout.Valid then Exit;
  { WASHED AT THE DOOR: the painter runs with the traps on, and a window
    with no number in it has nowhere to draw }
  if not (Finite(ALayout.GroupX) and Finite(ALayout.GroupY) and Finite(ALayout.L)
    and Finite(ALayout.T) and Finite(ALayout.HandleEnds[0])
    and Finite(ALayout.HandleEnds[1]) and Finite(ALayout.HandleH)) then Exit;
  D := TyZrLocal(AScale, AScale, 0, AOriginX, AOriginY);
  for p := 0 to ALayout.Painted - 1 do
  begin
    role := ALayout.Paint[p];
    e := ALayout.Kids[role];
    case role of
      dzrBackground, dzrFiller:
        begin
          el := Blank(role);
          el.Shape := RectShape(e.Shape, False, nil, Dev(role));
          el.Style.HasFill := True;
          if role = dzrBackground then
            el.Style.FillColor := Ink(ASpec.Background, True, AInk.Background, 1)
          else
            el.Style.FillColor := Ink(ASpec.Filler, True, AInk.Filler, 1);
          { [R7-AA] a fill of no alpha too: it hands the canvas its fillStyle
            (a transparent background, a filler colour the canvas refuses)
            [was: left out] }
          if e.Shape.W > 0 then
          begin
            AList.Add(el);
            Inc(Result);
          end;
        end;
      dzrFrame:
        begin
          el := Blank(role);
          el.Shape := RectShape(TyZrSubPixelOptimizeRect(e.Shape, 1), ASpec.HasRadius,
            ASpec.Radius, Dev(role));
          el.Style.StrokeColor := Ink(ASpec.Frame, False, AInk.Frame, 1);
          el.Style.StrokeWidthLogical := 1;
          { [R7-AA] the frame's Rect is filled 'rgba(0,0,0,0)': it hands the
            canvas that fill }
          el.Style.HasFill := True;
          el.Style.FillColor := 0;
          AList.Add(el);
          Inc(Result);
        end;
      dzrHandle0, dzrHandle1:
        begin
          el := Blank(role);
          { [R5-A] handleStyle's shadow on the icon; [R5-F] the hover's in the
            emphasis state }
          if ALayout.HandleHover[Ord(role) - Ord(dzrHandle0)] then
            TyStyleSetShadow(el.Style, ASpec.HandleEmphShadow)
          else
            TyStyleSetShadow(el.Style, ASpec.Handle.Shadow);
          { [R5-D] THE EMPHASIS STATE OVER THE NORMAL STYLE: emphasis.handleStyle's
            keys where written; else the default proxy's lift of the normal
            fill, and the model's default border (the theme's); the theme's
            hover ink where the author wrote no colour at all
            [Was: the theme's hover inks whatever the author wrote.] }
          { [R7-AC] getItemStyle's border dash, phase, cap, join,
            miterLimit -- the hover's over them }
          if ALayout.HandleHover[Ord(role) - Ord(dzrHandle0)] then
            PenOn(el, PenOver(ASpec.HandleEmph, ASpec.Handle),
              LineWidthOr(ASpec.HandleEmph, LineWidthOr(ASpec.Handle, 1)))
          else
            PenOn(el, ASpec.Handle, LineWidthOr(ASpec.Handle, 1));
          if ALayout.HandleHover[Ord(role) - Ord(dzrHandle0)] then
          begin
            if ASpec.HandleEmph.HasOpacity then op := ASpec.HandleEmph.Opacity
            else if ASpec.Handle.HasOpacity then op := ASpec.Handle.Opacity
            else op := 1;
            if ASpec.HandleEmph.HasFill then hf := WithOpacity(ASpec.HandleEmph.Fill, op)
            else if ASpec.Handle.HasFill then
              hf := WithOpacity(TyChartLiftColor(ASpec.Handle.Fill), op)
            else hf := WithOpacity(AInk.HandleHoverFill, op);
            if ASpec.HandleEmph.HasStroke then hs := WithOpacity(ASpec.HandleEmph.Stroke, op)
            else hs := WithOpacity(AInk.HandleHoverStroke, op);
            Symbol(ASpec.HandleIcon, e, Dev(role), hf, hs, True,
              LineWidthOr(ASpec.HandleEmph, LineWidthOr(ASpec.Handle, 1)));
          end
          else
            Symbol(ASpec.HandleIcon, e, Dev(role),
              Ink(ASpec.Handle, True, AInk.HandleFill, 1),
              Ink(ASpec.Handle, False, AInk.HandleStroke, 1), True,
              LineWidthOr(ASpec.Handle, 1));
        end;
      dzrMoveHandle:
        begin
          el := Blank(role);
          el.Shape := RectShape(e.Shape, True, e.R, Dev(role));
          el.Style.HasFill := True;
          { [R5-D] the hover: emphasis.moveHandleStyle over the normal style
            -- its colour, else the normal one, at its opacity, else the
            model's default 0.8 [was: the normal colour at 0.8, whatever the
            emphasis said] }
          if ALayout.MoveHover then
          begin
            if ASpec.MoveHandleEmph.HasOpacity then op := ASpec.MoveHandleEmph.Opacity
            else op := 0.8;
            if ASpec.MoveHandleEmph.HasFill then
              el.Style.FillColor := WithOpacity(ASpec.MoveHandleEmph.Fill, op)
            else if ASpec.MoveHandle.HasFill then
              el.Style.FillColor := WithOpacity(ASpec.MoveHandle.Fill, op)
            else if ASpec.MoveHandleEmph.HasOpacity then
              el.Style.FillColor := WithOpacity(AInk.MoveHandleHover or $FF000000, op)
            else
              el.Style.FillColor := AInk.MoveHandleHover;
          end
          else
            el.Style.FillColor := Ink(ASpec.MoveHandle, True, AInk.MoveHandle, 0.5);
          if ALayout.MoveHover and ASpec.MoveHandleEmph.HasStroke then
          begin
            el.Style.StrokeColor := WithOpacity(ASpec.MoveHandleEmph.Stroke,
              el.Style.FillColor shr 24 / 255);
            el.Style.StrokeWidthLogical := LineWidthOr(ASpec.MoveHandleEmph,
              LineWidthOr(ASpec.MoveHandle, 1));
          end
          else if ASpec.MoveHandle.HasStroke then
          begin
            el.Style.StrokeColor := WithOpacity(ASpec.MoveHandle.Stroke,
              el.Style.FillColor shr 24 / 255);
            el.Style.StrokeWidthLogical := LineWidthOr(ASpec.MoveHandle, 1);
            if ALayout.MoveHover then
              el.Style.StrokeWidthLogical := LineWidthOr(ASpec.MoveHandleEmph,
                el.Style.StrokeWidthLogical);
          end;
          if ALayout.MoveHover then
            TyStyleSetShadow(el.Style, ASpec.MoveHandleEmphShadow)
          else
            TyStyleSetShadow(el.Style, ASpec.MoveHandle.Shadow);
          { [R7-AC] its border's dash, phase, cap, join, miterLimit }
          if el.Style.StrokeWidthLogical > 0 then
          begin
            if ALayout.MoveHover then
              PenOn(el, PenOver(ASpec.MoveHandleEmph, ASpec.MoveHandle), el.Style.StrokeWidthLogical)
            else
              PenOn(el, ASpec.MoveHandle, el.Style.StrokeWidthLogical);
          end;
          if e.Shape.W > 0 then
          begin
            AList.Add(el);
            Inc(Result);
          end;
        end;
      dzrMoveHandleIcon:
        begin
          el := Blank(role);
          Symbol(ASpec.MoveHandleIcon, e, Dev(role), AInk.MoveIcon, 0, False, 0);
        end;
      dzrShadowPolygon0..dzrShadowPolygon2:
        Poly(role, ALayout.Area, True);
      dzrShadowPolyline0..dzrShadowPolyline2:
        Poly(role, ALayout.Line, False);
      dzrLabel0, dzrLabel1:
        begin
          lb := ALayout.Labels[Ord(role) - Ord(dzrLabel0)];
          if (not lb.Visible) or (lb.Text = '') then Continue;
          M := Dev(role);
          el := Blank(role);
          el.Shape := TyShapeRect(DevRect(lb.Rect, M));
          el.Caption.Text := lb.Text;
          el.Caption.FontName := AInk.FontName;
          el.Caption.FontSizeLogical := AInk.FontSizeLogical;
          el.Caption.FontWeight := AInk.FontWeight;
          if ASpec.HasText then el.Caption.Colour := ASpec.TextColour
          else el.Caption.Colour := AInk.Text;
          TyZrApply(M, lb.X, lb.Y, el.Caption.X, el.Caption.Y);
          el.Caption.AnchorH := lb.AlignH;
          el.Caption.AnchorV := lb.AlignV;
          { [R7-M] the textStyle's opacity (or the root's), and the block }
          if AInk.HasOpacity then el.Style.Alpha := Max(0, Min(1, AInk.Opacity));
          if Length(lb.Pieces) > 0 then
          begin
            el.Caption.RtPieces := Copy(lb.Pieces, 0, Length(lb.Pieces));
            el.Caption.RtScale := AScale;
          end;
          AList.Add(el);
          Inc(Result);
        end;
    end;
  end;
  { the brush rect, added to the slider group last: silent, over the body }
  if ALayout.HasBrush and (not IsNan(ALayout.BrushW)) then
  begin
    el := Blank(dzrBackground);
    el.Z2 := 0;
    el.Shape := TyShapeRect(DevRect(XYWH(ALayout.BrushX, 0, ALayout.BrushW, ALayout.T),
      Dev(dzrBackground)));
    el.Style.HasFill := True;
    el.Style.FillColor := Ink(ASpec.Brush, True, AInk.Brush, 0.3);
    TyStyleSetShadow(el.Style, ASpec.Brush.Shadow);
    { [R7-AC] brushStyle's border (getItemStyle: its stroke and pen)
      [was: none drawn] }
    if ASpec.Brush.HasStroke and (LineWidthOr(ASpec.Brush, 0) > 0) then
    begin
      el.Style.StrokeColor := Ink(ASpec.Brush, False, 0, 1);
      el.Style.StrokeWidthLogical := LineWidthOr(ASpec.Brush, 0);
      PenOn(el, ASpec.Brush, el.Style.StrokeWidthLogical);
    end;
    AList.Add(el);
    Inc(Result);
  end;
end;

end.
