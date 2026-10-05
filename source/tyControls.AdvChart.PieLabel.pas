unit tyControls.AdvChart.PieLabel;
{$mode objfpc}{$H+}
{ Where a pie slice's label goes, and the line that points at it.

  A PIE LABEL IS NOT PLACED BY THE THIRTEEN POSITIONS. PieView hands the label
  to setLabelStyle like every other series and then resets the geometry:
  pie/labelLayout.ts computes x, y and rotation itself.

  BUT ONLY SOME OF IT IS RESET, and the difference decides two options.
  PieView resets `position` and `rotation` and nothing else, and the reset
  MERGES rather than replaces -- so the `distance` and `offset` the generic
  reader already wrote both survive into zrender. `distance` is then read only
  inside the `has a position` gate, which the null position closes, so it is
  dead. `offset` is applied outside that gate, unconditionally, so it is not.
  Two options that look equally discarded and are not.

  `align` and `verticalAlign` ARE discarded -- this pass overwrites both after
  the generic reader has picked them up. Rejecting them on the option surface
  would be wrong; accepting and then ignoring them is what upstream does.

  THREE PLACEMENTS, AND ONLY ONE OF THEM CAN COLLIDE.
    center  -- at the pie's own centre. Nothing else to say.
    inside  -- on the middle of the ring, at the slice's bisector.
    outer   -- out past the rim, with a two-segment line back to the slice.
  Upstream pushes ONLY the outer ones into the list its overlap solver reads.
  Inside and centre labels are placed and finished.

  THE OVERLAP SOLVER (avoidOverlap, avoidLabelOverlap's default true) is here
  too [Batch 109, roadmap B13]: each side's outer labels sorted and shifted
  apart on y (labelLayoutHelper's shiftLayoutOnXY, the B8 transcription), their
  x solved again on an ellipse through the outermost label of each half where
  anything moved, the labelLine / edge alignments, a target width per label
  (bleedMargin, edgeDistance) that truncates it, and the line stood off the
  label again. It runs over the whole series' list before the marks are
  built, so it lives in TyBuildPieLabels; TyPlacePieLabel places ONE label
  and keeps only the last step, which is all one label sees of it.
  THE TURN LIMITS (limitTurnAngle / limitSurfaceAngle, AdvChart.LabelGuide)
  bend every line the build draws -- moved or not -- after the solver, and
  a smooth line draws two cubics [Batch 112, roadmap B14]; TyPlacePieLabel
  leaves them out.

  PORTED FROM src/chart/pie/labelLayout.ts, ECharts 6.1.0.

  PURE: SysUtils, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Labels,
  tyControls.AdvChart.Data, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Series,
  tyControls.AdvChart.LabelOpt, tyControls.AdvChart.Pie;

type
  { `inside` and `inner` are the same thing; EVERYTHING ELSE -- including a name
    nobody recognises -- falls through to outer. That is upstream's structure:
    two equality tests and an else, rather than a table. }
  TTyPieLabelPosition = (tplOuter, tplInside, tplCentre);

  { alignTo. `edge` pins the text to the view rect's own edge instead of to the
    end of its line, and flips which side of the anchor it hangs off. }
  TTyPieAlignTo = (tpaNone, tpaLabelLine, tpaEdge);

  { rotate takes a number of DEGREES or one of three words. }
  TTyPieRotate = (tprNone, tprNumber, tprRadial, tprTangential,
    tprTangentialNoFlip);

  { [top, right, bottom, left] }
  TTyPieMargin = array[0..3] of Double;

  TTyPieLabelSpec = record
    Show: Boolean;
    Position: TTyPieLabelPosition;
    AlignTo: TTyPieAlignTo;
    Rotate: TTyPieRotate;
    RotateDeg: Double;
    { distanceToLabelLine, LOGICAL px -- the gap between the end of the line and
      the words. NOT `label.distance`, which a pie never reads. }
    DistanceToLineLogical: Double;
    { Both are percentages OF THE VIEW RECT'S WIDTH, or plain numbers in
      logical px. Not of the radius and not of min(width, height): a port that
      guessed either would place edge-aligned labels at a plainly wrong x on
      any view rect that is not square. }
    LineLength, LineLength2: TTyBoxValue;
    EdgeDistance: TTyBoxValue;
    { NaN means "work it out at layout time", which is what upstream does: the
      default is commented out in its own defaultOption and computed from the
      view rect instead. }
    BleedMargin: Double;
    ShowLine: Boolean;
    { A slice narrower than this shows neither label nor line. DEGREES. }
    MinShowLabelDeg: Double;
    { LOGICAL px, and it DOES reach a pie label -- see the header. Upstream
      applies it inside the rotation, which this does not; noted where it is
      applied. }
    OffsetXLogical, OffsetYLogical: Double;
    { The ink options -- `color`, `textBorderColor`, `textBorderWidth`, a
      background -- read by the shared reader; the bands and the ground are
      the control's. }
    Ink: TTyLabelSpec;
    { A string template, the empty one included; see TTyLabelSpec. }
    Formatter: string;
    HasFormatter: Boolean;
    Overflow: TTyLabelOverflow;
    { WHAT THE OPTION SAID, kept beside the enum because two rules read the
      WORD rather than the placement: the guide line exists only for the
      literal 'outer' and 'outside', and the tangential guard tests the same
      two strings. Any other value -- 'top', say -- takes the outer placement
      and gets no line. }
    PositionWord: string;
    { `avoidLabelOverlap: false` (the series'): the default true runs
      avoidOverlap, whose last step stands the line off the label's x again
      [Batch 96] }
    NoAvoidOverlap: Boolean;
    { `label.ellipsis`, '...' unless written: what a label the solver cuts
      ends with [Batch 109] }
    Ellipsis: string;
    { labelLine.minTurnAngle / maxSurfaceAngle (degrees, as JavaScript's
      ToNumber reads them; 90 unless written, nought or not a number: no
      limit), smooth (setLabelLineState's number) and length2 as a label
      layout routing the line reads it (`length2 || 0`, logical px; a
      percentage is not a number there) [Batch 112] }
    MinTurnAngle, MaxSurfaceAngle, Smooth, RouteLength2: Double;
  end;

  { One placed label, DEVICE px. AnchorV is always the middle -- upstream forces
    it unconditionally after everything else has been decided. }
  TTyPieLabelPlacement = record
    Valid: Boolean;
    X, Y: Double;
    { label.x / y before the offset, and the offset (device px): what the
      label layout starts from [Batch 103] }
    BaseX, BaseY, OffX, OffY: Double;
    AnchorH: TTyTextAnchorH;
    AnchorV: TTyTextAnchorV;
    RotationRad: Double;
    { The guide line, three points and so two segments. The SECOND one is
      horizontal by construction -- y3 is copied from y2 rather than computed --
      which is what makes a column of outer labels line up. }
    HasLine: Boolean;
    P1, P2, P3: TTyPointF;
    { what the overlap solver reads, device px: labelLine's length and
      length2, distanceToLabelLine, edgeDistance [Batch 109] }
    LineLen, LineLen2, DistToLine, EdgeDist: Double;
    { the slice's normal (cos, sin of its middle angle): limitSurfaceAngle's
      surface [Batch 112] }
    NX, NY: Double;
  end;

{ ==== THE OVERLAP SOLVER (avoidOverlap) [Batch 109, roadmap B13] ====

  ONE LABEL IN pieLabelLayout's LIST -- every outer and centre label, in data
  order; an inside one never enters it. Device px throughout. }
type
  TTyPieAvoidItem = record
    { ---- inputs ---- }
    { position 'center': in the list, left out of everything }
    Centre: Boolean;
    { the position is literally 'outer' -- the labelLine alignment's test,
      which 'outside' and the unknown words fail }
    OuterWord: Boolean;
    { linePoints exist: every placement that is not inside or centre }
    HasLine: Boolean;
    AlignTo: TTyPieAlignTo;
    Len, Len2, LabelDistance, EdgeDistance, BleedMargin: Double;
    { an author `label.width`: never constrained }
    HasStyleWidth: Boolean;
    { the block's left + right padding, and whether it has a background
      (whose rect already counts the padding) }
    PaddingH: Double;
    HasBackground: Boolean;
    { the rect's width before any constraint }
    UnconstrainedWidth: Double;
    { ---- the state the solver moves ---- }
    LabelX, LabelY: Double;
    { computeLabelGlobalRect's rect, margins included }
    Rect: TTyXYWH;
    Line: array[0..2] of TTyPointF;
    { targetTextWidth, once set }
    HasTarget: Boolean;
    Target: Double;
    { the style width constrainTextWidth left (none: HasWidth False) }
    HasWidth: Boolean;
    Width: Double;
  end;
  TTyPieAvoidItemArray = array of TTyPieAvoidItem;

  { computeLabelGlobalRect: an item's rect for its label x / y and width as
    they stand (AIndex is its place in the list) }
  TTyPieAvoidRectFn = function(const AItem: TTyPieAvoidItem;
    AIndex: Integer): TTyXYWH of object;

{ avoidOverlap over a series' list: the sides split at ACX, the target
  widths (each constraint re-measured through ARect), adjustSingleSide on the
  right then the left (labelLine alignment to the farthest x, the shift on y
  within AView, the ellipse through r + length), and every line stood off its
  label. AR is the SERIES' radius. }
procedure TyPieAvoidOverlap(var AItems: TTyPieAvoidItemArray; ACX, ACY,
  AR: Double; const AView: TTyXYWH; const ARect: TTyPieAvoidRectFn);

{ A PLAIN LABEL UNDER A WIDTH: zrender's per-line truncation (the container
  one short of the width, the ellipsis dropped if it does not fit) when
  AHasWidth and ATruncate; the drawn text, and the widest line's width. }
function TyPiePlainFit(const AText: string; AHasWidth: Boolean; AWidth: Double;
  ATruncate: Boolean; const AEllipsis: string; const AMeasurer: ITyTextMeasurer;
  const AFontName: string; AFontSizeLogical, AWeight: Integer;
  out AContentW: Double): string;

{ The margins computeLabelGlobalRect puts round a pie label (device px):
  minMargin's top and bottom halves (its left and right forced to 0) on the
  global rect (AType 1); textMargin on the local one (2); otherwise one px
  above and below, as a textMargin. }
procedure TyPieLabelMargin(const AInk: TTyLabelSpec; AScale: Double;
  out AType: Integer; out AMargin: TTyPieMargin);

{ The global rect of a label whose own box is ARaw, hung at label.x / y with
  the offset inside the turn (zrender's origin = minus the offset). }
function TyPieLabelGlobalRect(const ARaw: TTyXYWH; ALabelX, ALabelY, AOffX,
  AOffY, ARotation: Double; AMarginType: Integer;
  const AMargin: TTyPieMargin): TTyXYWH;

function TyPieLabelSpecDefault: TTyPieLabelSpec;
function TyPieLabelSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ABase: TTyPieLabelSpec): TTyPieLabelSpec;

{ Place one slice's label. ALayout supplies the series radius and the view rect,
  both of which the arithmetic needs and neither of which is on the sector. }
function TyPlacePieLabel(const ASpec: TTyPieLabelSpec;
  const ALayout: TTyPieLayout; const ASector: TTyPieSector;
  APPI: Integer): TTyPieLabelPlacement;

{ How a pie's labels are drawn, beyond where they go. Fonts and colours arrive
  resolved, like everywhere else below AdvChart.Measure.

  ONLY TWO INKS, NOT THREE. A pie label is either over its own slice or over
  the chart's ground, and upstream decides which by the same rule it uses
  everywhere: only `inside` and `inner` count. `center` does NOT -- a centred
  donut label sits on the hole, not on the ring, so it takes the outside ink
  even though it is inside the pie's circle. }
type
  TTyPieLabelInk = record
    FontName: string;
    FontSizeLogical: Integer;
    FontWeight: Integer;
    { The three luminance bands for a label over its slice, and the theme's
      own ink for one that is not. }
    InsideColour: array[0..2] of TTyChartColor;
    OutsideColour: TTyChartColor;
    { The ground, for the halos. }
    Ground: TTyChartColor;
    GroundDark: Boolean;
    { The guide line's ink and width. Upstream draws it in the slice's own
      colour, which is why it is not a theme key. }
    LineWidthLogical: Double;
  end;

{ Append this pie's labels, and the lines that point at them, to AList.

  AFills is index-parallel to the sectors -- a pie is colorBy:data, so the
  line and an inside label's contrast both come from the slice's own colour.

  Answers how many elements were added. }
function TyBuildPieLabels(const ABinding: TTySeriesBinding;
  const ALayout: TTyPieLayout; const ASpec: TTyPieLabelSpec;
  const AInk: TTyPieLabelInk; const AFills: array of TTyChartColor;
  AStore: TTyDataStore; const ASeriesName: string; AValueDim,
  APercentPrecision: Integer; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;

{ bleedMargin's computed default: ten on a normal chart, two on a small one.

  NOT A CONSTANT, and the small case is not hypothetical -- it is exactly what a
  pie nested in a calendar or matrix cell gets. A hardcoded ten over-margins
  every one of them. }
function TyPieBleedMargin(const AViewRect: TTyRectF): Double;

implementation

uses tyControls.AdvChart.RichStyle, tyControls.AdvChart.JsMath,
  tyControls.AdvChart.LabelLayout, tyControls.AdvChart.LabelGuide;

const
  cRadian = Pi / 180;
  { The fixed nudge along the slice's own normal, applied to inside AND outer
    labels alike before anything else moves them. Upstream writes the literal 3
    twice and explains it nowhere; it is here because it is there. }
  cNormalNudge = 3.0;

function TyPieLabelSpecDefault: TTyPieLabelSpec;
begin
  { every field, so a flag added later starts False rather than wherever
    the stack left it }
  Result := Default(TTyPieLabelSpec);
  { THE INK OPTIONS START AUTOMATIC -- a zero record would be a literal
    colour of nought. }
  Result.Ink := TyLabelSpecNone;
  Result.Show := True;                        { PieSeries.ts:269 }
  Result.Position := tplOuter;                { :271-272, 'outer' not 'outside' }
  Result.AlignTo := tpaNone;
  Result.Rotate := tprNone;
  Result.RotateDeg := 0;
  Result.DistanceToLineLogical := 5;          { :282 }
  Result.LineLength := TyBoxPx(15);           { labelLine.length, :290 }
  Result.LineLength2 := TyBoxPx(30);          { :292 }
  Result.EdgeDistance := TyBoxPercent(25);    { :277 }
  Result.BleedMargin := NaN;
  Result.ShowLine := True;                    { :288 }
  Result.MinTurnAngle := 90;                  { :295 }
  Result.MaxSurfaceAngle := 90;               { :296 }
  Result.Smooth := 0;                         { :294 }
  Result.RouteLength2 := 30;
  Result.MinShowLabelDeg := 0;
  Result.OffsetXLogical := 0;
  Result.OffsetYLogical := 0;
  Result.Formatter := '';
  Result.PositionWord := 'outer';
  { PIE OVERRIDES THE SHARED DEFAULT. The generic overflow node defaults to
    none; pie's own defaultOption sets truncate, and pie is the one series type
    whose labels routinely run off the view. The option catalog in this
    repository records the generic value for both. }
  Result.Overflow := tloTruncate;
  Result.Ellipsis := '...';
end;

function TyPieBleedMargin(const AViewRect: TTyRectF): Double;
begin
  if Min(TyRectFWidth(AViewRect), TyRectFHeight(AViewRect)) > 200 then
    Result := 10
  else
    Result := 2;
end;

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then
    Result := TJSONObject(AData)
  else
    Result := nil;
end;

function ParseFloatIn(const AText: string; out AValue: Double): Boolean;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := TryStrToFloat(Trim(AText), AValue, fs);
end;

{ A length that may be a percentage of the view width. }
function LengthIn(ANode: TJSONObject; const AKey: string;
  const ADefault: TTyBoxValue): TTyBoxValue;
var
  d: TJSONData;
  s: string;
  v: Double;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  if d.JSONType = jtNumber then Exit(TyBoxPx(d.AsFloat));
  if d.JSONType <> jtString then Exit;
  s := Trim(d.AsString);
  if s = '' then Exit;
  if s[Length(s)] = '%' then
  begin
    if ParseFloatIn(Copy(s, 1, Length(s) - 1), v) then Exit(TyBoxPercent(v));
    Exit;
  end;
  if ParseFloatIn(s, v) then Result := TyBoxPx(v);
end;

function NumAt(AArr: TJSONArray; AIndex: Integer; ADefault: Double): Double;
begin
  Result := ADefault;
  if (AArr = nil) or (AIndex < 0) or (AIndex >= AArr.Count) then Exit;
  if AArr.Items[AIndex].JSONType <> jtNumber then Exit;
  Result := AArr.Items[AIndex].AsFloat;
end;

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtNumber) then Exit;
  Result := d.AsFloat;
end;

function StrIn(ANode: TJSONObject; const AKey: string): string;
var d: TJSONData;
begin
  Result := '';
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d = nil) or (d.JSONType <> jtString) then Exit;
  Result := d.AsString;
end;

function TyPieLabelSpecOf(AOption: TTyChartOption; ASlot: Integer;
  const ABase: TTyPieLabelSpec): TTyPieLabelSpec;
var
  series, node, line: TJSONObject;
  d: TJSONData;
  s: string;
  margins: TTyLabelSpec;
  k: Integer;
begin
  Result := ABase;
  if AOption = nil then Exit;
  series := ObjOf(AOption.ComponentAt('series', ASlot));
  if series = nil then Exit;

  Result.MinShowLabelDeg := NumIn(series, 'minShowLabelAngle',
    Result.MinShowLabelDeg);
  d := series.Find('avoidLabelOverlap');
  Result.NoAvoidOverlap := (d <> nil) and (d.JSONType in [jtBoolean, jtNull, jtNumber, jtString])
    and not ((d.JSONType = jtBoolean) and d.AsBoolean)
    and not ((d.JSONType = jtNumber) and (d.AsFloat <> 0) and not IsNan(d.AsFloat))
    and not ((d.JSONType = jtString) and (d.AsString <> ''));

  node := ObjOf(series.Find('label'));
  TyLabelReadInk(node, series, Result.Ink);
  { its text block [Batch 86] }
  TyLabelReadBlock(node, AOption.Root, Result.Ink);
  if node <> nil then
  begin
    d := node.Find('show');
    if (d <> nil) and (d.JSONType = jtBoolean) then Result.Show := d.AsBoolean;

    { `inside` and `inner` are the same; `center` is its own case; EVERY other
      value falls through to outer, INCLUDING one nobody recognises. Upstream
      has no table here, only two equality tests and an else. }
    s := StrIn(node, 'position');
    if s <> '' then
    begin
      Result.PositionWord := s;
      if (s = 'inside') or (s = 'inner') then Result.Position := tplInside
      else if s = 'center' then Result.Position := tplCentre
      else Result.Position := tplOuter;
    end;

    s := StrIn(node, 'alignTo');
    if s = 'labelLine' then Result.AlignTo := tpaLabelLine
    else if s = 'edge' then Result.AlignTo := tpaEdge
    else if s = 'none' then Result.AlignTo := tpaNone;

    d := node.Find('rotate');
    if d <> nil then
      case d.JSONType of
        jtNumber:
          begin
            Result.Rotate := tprNumber;
            Result.RotateDeg := d.AsFloat;
          end;
        jtBoolean:
          { `true` is radial. The catalog types this boolean|number|string and
            gives no enum for the three words, so nothing but the source says
            they exist. }
          if d.AsBoolean then Result.Rotate := tprRadial
          else Result.Rotate := tprNone;
        jtString:
          begin
            s := d.AsString;
            if s = 'radial' then Result.Rotate := tprRadial
            else if s = 'tangential' then Result.Rotate := tprTangential
            else if s = 'tangential-noflip' then
              Result.Rotate := tprTangentialNoFlip;
          end;
      end;

    Result.DistanceToLineLogical := NumIn(node, 'distanceToLabelLine',
      Result.DistanceToLineLogical);
    d := node.Find('offset');
    if (d <> nil) and (d is TJSONArray) then
    begin
      if TJSONArray(d).Count > 0 then
        Result.OffsetXLogical := NumAt(TJSONArray(d), 0,
          Result.OffsetXLogical);
      if TJSONArray(d).Count > 1 then
        Result.OffsetYLogical := NumAt(TJSONArray(d), 1,
          Result.OffsetYLogical);
    end;
    Result.EdgeDistance := LengthIn(node, 'edgeDistance', Result.EdgeDistance);
    d := node.Find('bleedMargin');
    if (d <> nil) and (d.JSONType = jtNumber) then
      Result.BleedMargin := d.AsFloat;
    d := node.Find('formatter');
    if (d <> nil) and (d.JSONType = jtString) then
    begin
      Result.Formatter := d.AsString;
      Result.HasFormatter := True;
    end
    else if (d <> nil) and (d.JSONType = jtNull) then
    begin
      Result.Formatter := '';
      Result.HasFormatter := False;
    end;
    s := StrIn(node, 'overflow');
    if s = 'truncate' then Result.Overflow := tloTruncate
    { 'break' / 'breakAll' wrap rather than cut -- the block's to do, and
      the plain label does not wrap [Batch 109] }
    else if s <> '' then Result.Overflow := tloNone;
    d := node.Find('ellipsis');
    if (d <> nil) and (d.JSONType = jtString) then Result.Ellipsis := d.AsString;
    { minMargin / textMargin: the solver's rect counts them, and so does the
      label layout after it [Batch 109] }
    margins := TyLabelSpecOfNode(node, series, TyLabelSpecNone);
    Result.Ink.MarginType := margins.MarginType;
    for k := 0 to 3 do Result.Ink.MarginLogical[k] := margins.MarginLogical[k];
  end;

  line := ObjOf(series.Find('labelLine'));
  if line <> nil then
  begin
    d := line.Find('show');
    if (d <> nil) and (d.JSONType = jtBoolean) then
      Result.ShowLine := d.AsBoolean;
    Result.LineLength := LengthIn(line, 'length', Result.LineLength);
    Result.LineLength2 := LengthIn(line, 'length2', Result.LineLength2);
    { the limits and the smooth [Batch 112] }
    Result.MinTurnAngle := TyGuideJsNumber(line.Find('minTurnAngle'), Result.MinTurnAngle);
    Result.MaxSurfaceAngle := TyGuideJsNumber(line.Find('maxSurfaceAngle'),
      Result.MaxSurfaceAngle);
    if line.Find('smooth') <> nil then
      Result.Smooth := TyLabelLineSmoothOf(line.Find('smooth'));
    Result.RouteLength2 := TyGuideLength2(line.Find('length2'), Result.RouteLength2);
  end;
end;

{ ==================== the placement ==================== }

{ OFFSET LAST, after everything else has placed the words, and INSIDE the
  rotation: zrender adds it to label.x / y and sets the origin to minus it,
  so a turned label's offset runs along the turned axes. The transform's
  translation is the point the painter hangs and turns the words at.
  [Batch 103: it was added in screen axes.] From BaseX / BaseY, so the build
  runs it again once the overlap solver has moved them [Batch 109]. }
procedure PieApplyOffset(var P: TTyPieLabelPlacement; const ASpec: TTyPieLabelSpec;
  APPI: Integer);
var
  scale: Double;
  m: TTyMat2D;
begin
  P.X := P.BaseX;
  P.Y := P.BaseY;
  P.OffX := 0;
  P.OffY := 0;
  if APPI <= 0 then Exit;
  scale := APPI / 96;
  P.OffX := ASpec.OffsetXLogical * scale;
  P.OffY := ASpec.OffsetYLogical * scale;
  if TyLabelLocalTransform(P.BaseX + P.OffX, P.BaseY + P.OffY,
    -P.OffX, -P.OffY, P.RotationRad, 1, 1, m) then
  begin
    P.X := m[4];
    P.Y := m[5];
  end
  else
  begin
    P.X := 0;
    P.Y := 0;
  end;
end;

{ THE PLACEMENT. ALastStep: stand the line off the label's x again, as
  avoidOverlap's last pass does to a label nothing moved -- what one label
  sees of the solver. The build leaves it to the solver itself. }
function PlacePie(const ASpec: TTyPieLabelSpec;
  const ALayout: TTyPieLayout; const ASector: TTyPieSector;
  APPI: Integer; ALastStep: Boolean): TTyPieLabelPlacement;
var
  mid, nx, ny, scale, sweep: Double;
  x1, y1, x2, y2, x3, y3: Double;
  lineLen, lineLen2, distToLine, edgeDist, nudge: Double;
  viewW, viewL: Double;
  rad: Double;
begin
  Result := Default(TTyPieLabelPlacement);
  Result.AnchorH := tahCentre;
  { FORCED, unconditionally and after everything else -- upstream's last word on
    a pie label is `verticalAlign: middle`. }
  Result.AnchorV := tavMiddle;
  if not ASpec.Show then Exit;
  if not ASector.Valid then Exit;
  if IsNan(ASector.StartRad) or IsNan(ASector.EndRad) then Exit;

  { A slice too narrow to label shows neither words nor line. Measured on the
    DRAWN sweep, which padAngle has already eaten into. }
  sweep := Abs(ASector.EndRad - ASector.StartRad);
  if sweep < ASpec.MinShowLabelDeg * cRadian then Exit;

  if APPI > 0 then scale := APPI / 96 else scale := 1;
  viewW := TyRectFWidth(ALayout.ViewRect);
  viewL := ALayout.ViewRect.Left;
  lineLen := TyPieResolve(ASpec.LineLength, viewW);
  lineLen2 := TyPieResolve(ASpec.LineLength2, viewW);
  { A PERCENTAGE IS ALREADY IN DEVICE px -- it was taken of a device-px view
    rect. Only a literal number is logical and needs scaling. }
  if ASpec.LineLength.Kind = buPx then lineLen := lineLen * scale;
  if ASpec.LineLength2.Kind = buPx then lineLen2 := lineLen2 * scale;
  edgeDist := TyPieResolve(ASpec.EdgeDistance, viewW);
  if ASpec.EdgeDistance.Kind = buPx then edgeDist := edgeDist * scale;
  distToLine := ASpec.DistanceToLineLogical * scale;
  nudge := cNormalNudge * scale;
  Result.LineLen := lineLen;
  Result.LineLen2 := lineLen2;
  Result.DistToLine := distToLine;
  Result.EdgeDist := edgeDist;

  mid := (ASector.StartRad + ASector.EndRad) / 2;
  { V8'S cos AND sin, as the label's place is upstream's to the bit: an
    update moves it from its old place [Batch 92] }
  nx := TyJsCos(mid);
  ny := TyJsSin(mid);
  Result.NX := nx;
  Result.NY := ny;

  if ASpec.Position = tplCentre then
  begin
    Result.X := ASector.CX;
    Result.Y := ASector.CY;
    Result.AnchorH := tahCentre;
  end
  else
  begin
    { The point on the slice the label hangs off: the middle of the RING for an
      inside label, the RIM for an outer one. }
    if ASpec.Position = tplInside then
    begin
      x1 := (ASector.R1 + ASector.R0) / 2 * nx + ASector.CX;
      y1 := (ASector.R1 + ASector.R0) / 2 * ny + ASector.CY;
    end
    else
    begin
      x1 := ASector.R1 * nx + ASector.CX;
      y1 := ASector.R1 * ny + ASector.CY;
    end;
    Result.X := x1 + nx * nudge;
    Result.Y := y1 + ny * nudge;

    if ASpec.Position = tplInside then
      Result.AnchorH := tahCentre
    else
    begin
      { THE SERIES RADIUS, NOT THE SLICE'S. `lineLen + r - sector.r` is a
        roseType compensation: every slice's line then ENDS the same distance
        from the series' own rim, so the labels form a column even though the
        slices reach different depths. Drop the two extra terms and a rose
        chart's labels follow its spikes. }
      x2 := x1 + nx * (lineLen + ALayout.R1 - ASector.R1);
      y2 := y1 + ny * (lineLen + ALayout.R1 - ASector.R1);
      if nx < 0 then x3 := x2 - lineLen2 else x3 := x2 + lineLen2;
      { HORIZONTAL BY CONSTRUCTION -- y3 is COPIED from y2 rather than computed
        along the normal. That is what makes the second segment level and the
        labels line up; computing it would fan them out. }
      y3 := y2;

      if ASpec.AlignTo = tpaEdge then
      begin
        { Pinned to the view rect's own edge rather than to the end of the
          line, and the text then hangs INWARD -- which is why the alignment
          below is the opposite way round for this case. }
        if nx < 0 then Result.X := viewL + edgeDist
        else Result.X := viewL + viewW - edgeDist;
      end
      else
      begin
        if nx < 0 then Result.X := x3 - distToLine
        else Result.X := x3 + distToLine;
        { AVOIDOVERLAP'S LAST STEP (labelLayout.ts:224-255), which runs
          whether a label moved or not -- unless a label is turned or the
          series says no: the line's end stands off the label's x again and
          its middle point keeps its distance from the end. Taken back off
          the x it was added to, the end is not always where it was, in the
          last bits [Batch 96] }
        if ALastStep and (not ASpec.NoAvoidOverlap) and ((ASpec.Rotate = tprNone)
          or ((ASpec.Rotate = tprNumber) and (ASpec.RotateDeg = 0))) then
        begin
          sweep := x2 - x3;
          if Result.X < ASector.CX then x3 := Result.X + distToLine
          else x3 := Result.X - distToLine;
          x2 := x3 + sweep;
        end;
      end;
      Result.Y := y3;

      { THE LINE IS FOR 'outer' AND 'outside' ONLY, and that is a test on the
        WORD rather than on the placement: PieView removes the guide line for
        every other value, while labelLayout still computes the outer anchor
        for it. So `position: 'top'` on a pie puts the label out past the rim
        with nothing pointing at it. }
      Result.HasLine := ASpec.ShowLine
        and ((ASpec.PositionWord = 'outer') or (ASpec.PositionWord = 'outside'));
      Result.P1 := TyPointF(x1, y1);
      Result.P2 := TyPointF(x2, y2);
      Result.P3 := TyPointF(x3, y3);

      if ASpec.AlignTo = tpaEdge then
      begin
        if nx > 0 then Result.AnchorH := tahRight else Result.AnchorH := tahLeft;
      end
      else
      begin
        if nx > 0 then Result.AnchorH := tahLeft else Result.AnchorH := tahRight;
      end;
    end;
  end;

  { ---- the rotation ---- }
  Result.RotationRad := 0;
  if ASpec.Rotate = tprNumber then
    Result.RotationRad := ASpec.RotateDeg * cRadian
  else if ASpec.Position = tplCentre then
    Result.RotationRad := 0
  else if ASpec.Rotate = tprRadial then
  begin
    if nx < 0 then Result.RotationRad := -mid + Pi
    else Result.RotationRad := -mid;
  end
  else if (ASpec.Rotate = tprTangential)
    or ((ASpec.Rotate = tprTangentialNoFlip)
        and (ASpec.PositionWord <> 'outside')
        and (ASpec.PositionWord <> 'outer')) then
  begin
    { TRANSCRIBED WITH ITS PRECEDENCE BUG. Upstream writes
        rotate === 'tangential' || rotate === 'tangential-noflip' && pos !== ...
      and && binds tighter than ||, so the position guard applies ONLY to
      `tangential-noflip`. Plain `tangential` takes this branch even on an
      outer label, where tangential rotation makes no sense -- which is almost
      certainly not what was meant. The condition above is the same shape.
      Transcribing the intent instead would draw different pies. }
    rad := TyJsAtan2(nx, ny);
    if rad < 0 then rad := 2 * Pi + rad;
    if (ny > 0) and (ASpec.Rotate <> tprTangentialNoFlip) then rad := Pi + rad;
    Result.RotationRad := rad - Pi;
  end;

  Result.BaseX := Result.X;
  Result.BaseY := Result.Y;
  PieApplyOffset(Result, ASpec, APPI);
  Result.Valid := True;
end;

function TyPlacePieLabel(const ASpec: TTyPieLabelSpec;
  const ALayout: TTyPieLayout; const ASector: TTyPieSector;
  APPI: Integer): TTyPieLabelPlacement;
begin
  Result := PlacePie(ASpec, ALayout, ASector, APPI, True);
end;

{ ==================== the overlap solver [Batch 109] ==================== }

{ Math.min / Math.max: NaN wins }
function JsMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B < A then Result := B else Result := A;
end;

function JsMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B > A then Result := B else Result := A;
end;

type
  { a side's labels, as indices into the list }
  TPieSide = array of Integer;

  { the solver's pass over one list, its arguments at hand }
  TPieSolver = record
    Items: ^TTyPieAvoidItemArray;
    CX, CY, R: Double;
    View: TTyXYWH;
    RectOf: TTyPieAvoidRectFn;
  end;

{ constrainTextWidth: the label's width set from the room it has -- the
  room itself where the text is wider than it, and, forced (the x moved
  since), released again where the room has grown past the text's own
  width -- and its rect measured again. An author's width wins. }
procedure PieConstrain(var S: TPieSolver; AIndex: Integer; AAvailable: Double;
  AForce: Boolean);
var
  oldOuter, inner, extra: Double;
begin
  if S.Items^[AIndex].HasStyleWidth then Exit;
  { a background's rect already counts the padding }
  if S.Items^[AIndex].HasBackground then extra := 0
  else extra := S.Items^[AIndex].PaddingH;
  oldOuter := S.Items^[AIndex].Rect.W + extra;
  if (AAvailable < oldOuter) or AForce then
  begin
    inner := AAvailable - S.Items^[AIndex].PaddingH;
    if AAvailable < oldOuter then
    begin
      S.Items^[AIndex].HasWidth := True;
      S.Items^[AIndex].Width := inner;
    end
    else if AForce and not (inner > S.Items^[AIndex].UnconstrainedWidth) then
    begin
      S.Items^[AIndex].HasWidth := True;
      S.Items^[AIndex].Width := inner;
    end
    else
      S.Items^[AIndex].HasWidth := False;
    S.Items^[AIndex].Rect := S.RectOf(S.Items^[AIndex], AIndex);
  end;
end;

type
  TPieSemi = record
    List: TPieSide;
    N: Integer;
    RB, MaxY: Double;
  end;

procedure PieSemiAdd(var ASemi: TPieSemi; AIndex: Integer);
begin
  if ASemi.N >= Length(ASemi.List) then SetLength(ASemi.List, ASemi.N * 2 + 4);
  ASemi.List[ASemi.N] := AIndex;
  Inc(ASemi.N);
end;

{ recalculateX's test for one label: the outermost label of a half fixes
  that half's ellipse -- the LAST of equals, as `>=` takes it }
procedure PieSemiTake(var S: TPieSolver; var ASemi: TPieSemi; AIndex,
  ADir: Integer);
var dx, dy, rA: Double;
begin
  dy := Abs(S.Items^[AIndex].LabelY - S.CY);
  if dy >= ASemi.MaxY then
  begin
    dx := S.Items^[AIndex].LabelX - S.CX - S.Items^[AIndex].Len2 * ADir;
    { the horizontal semi-axis is r + length: x has not changed }
    rA := S.R + S.Items^[AIndex].Len;
    if Abs(dx) < rA then ASemi.RB := Sqrt(dy * dy / (1 - dx * dx / rA / rA))
    else ASemi.RB := rA;
    ASemi.MaxY := dy;
  end;
  PieSemiAdd(ASemi, AIndex);
end;

{ recalculateXOnSemiToAlignOnEllipseCurve: every label of a half put on its
  ellipse, its room worked out again (forced) for the x it moves to }
procedure PieSemiAlign(var S: TPieSolver; const ASemi: TPieSemi; ADir: Integer);
var
  q, j: Integer;
  rB2, rA, rA2, dx, dy, newX, deltaX: Double;
begin
  rB2 := ASemi.RB * ASemi.RB;
  for q := 0 to ASemi.N - 1 do
  begin
    j := ASemi.List[q];
    dy := Abs(S.Items^[j].LabelY - S.CY);
    rA := S.R + S.Items^[j].Len;
    rA2 := rA * rA;
    { the ellipse's implicit function, solved for x }
    dx := Sqrt(Abs((1 - dy * dy / rB2) * rA2));
    newX := S.CX + (dx + S.Items^[j].Len2) * ADir;
    deltaX := newX - S.Items^[j].LabelX;
    PieConstrain(S, j, S.Items^[j].Target - deltaX * ADir, True);
    S.Items^[j].LabelX := newX;
  end;
end;

{ adjustSingleSide: one side's labels, ADir 1 right and -1 left }
procedure PieAdjustSide(var S: TPieSolver; var ASide: TPieSide; ADir: Integer;
  AFarthestX: Double);
var
  i, k, len: Integer;
  dx: Double;
  tmp: TTyLabelLayoutItemArray;
  order: array of Integer;
  sorted: TPieSide;
  top, bottom: TPieSemi;
begin
  len := Length(ASide);
  if len < 2 then Exit;
  { alignTo labelLine: every label to the farthest x, the line's middle point
    by the same distance -- the literal 'outer' only }
  for i := 0 to len - 1 do
  begin
    k := ASide[i];
    if S.Items^[k].OuterWord and (S.Items^[k].AlignTo = tpaLabelLine) then
    begin
      dx := S.Items^[k].LabelX - AFarthestX;
      S.Items^[k].Line[1].X := S.Items^[k].Line[1].X + dx;
      S.Items^[k].LabelX := AFarthestX;
    end;
  end;
  { shiftLayoutOnXY on y within the view -- the B8 transcription, over the
    rects and label.y. It sorts the side, and the side is read sorted. }
  SetLength(tmp, len);
  SetLength(order, len);
  for i := 0 to len - 1 do
  begin
    tmp[i] := Default(TTyLabelLayoutItem);
    tmp[i].Box.Rect := S.Items^[ASide[i]].Rect;
    tmp[i].LabelX := S.Items^[ASide[i]].LabelX;
    tmp[i].LabelY := S.Items^[ASide[i]].LabelY;
    order[i] := i;
  end;
  { nothing moved: nothing to solve again }
  if not TyShiftLabelsOnXYOrdered(tmp, order, 1, S.View.Y, S.View.Y + S.View.H) then
    Exit;
  for i := 0 to len - 1 do
  begin
    S.Items^[ASide[i]].Rect := tmp[i].Box.Rect;
    S.Items^[ASide[i]].LabelY := tmp[i].LabelY;
  end;
  SetLength(sorted, len);
  for i := 0 to len - 1 do sorted[i] := ASide[order[i]];
  ASide := sorted;
  { recalculateX: only the labels with no alignment, split at the centre }
  top := Default(TPieSemi);
  bottom := Default(TPieSemi);
  for i := 0 to len - 1 do
  begin
    k := ASide[i];
    if S.Items^[k].AlignTo <> tpaNone then Continue;
    if S.Items^[k].LabelY > S.CY then PieSemiTake(S, bottom, k, ADir)
    else PieSemiTake(S, top, k, ADir);
  end;
  PieSemiAlign(S, top, ADir);
  PieSemiAlign(S, bottom, ADir);
end;

procedure TyPieAvoidOverlap(var AItems: TTyPieAvoidItemArray; ACX, ACY,
  AR: Double; const AView: TTyXYWH; const ARect: TTyPieAvoidRectFn);
var
  S: TPieSolver;
  left, right: TPieSide;
  nl, nr, i: Integer;
  leftmostX, rightmostX, t, realW, dist: Double;
begin
  S.Items := @AItems;
  S.CX := ACX;
  S.CY := ACY;
  S.R := AR;
  S.View := AView;
  S.RectOf := ARect;
  SetLength(left, Length(AItems));
  SetLength(right, Length(AItems));
  nl := 0;
  nr := 0;
  { Number.MAX_VALUE }
  leftmostX := MaxDouble;
  rightmostX := -MaxDouble;
  for i := 0 to High(AItems) do
  begin
    if AItems[i].Centre then Continue;
    if AItems[i].LabelX < ACX then
    begin
      leftmostX := JsMin(leftmostX, AItems[i].LabelX);
      left[nl] := i;
      Inc(nl);
    end
    else
    begin
      rightmostX := JsMax(rightmostX, AItems[i].LabelX);
      right[nr] := i;
      Inc(nr);
    end;
  end;
  SetLength(left, nl);
  SetLength(right, nr);

  { the room each label has, and the first constraint }
  for i := 0 to High(AItems) do
  begin
    if AItems[i].Centre or not AItems[i].HasLine then Continue;
    if AItems[i].HasStyleWidth then Continue;
    if AItems[i].AlignTo = tpaEdge then
    begin
      if AItems[i].LabelX < ACX then
        t := AItems[i].Line[2].X - AItems[i].LabelDistance - AView.X
          - AItems[i].EdgeDistance
      else
        t := AView.X + AView.W - AItems[i].EdgeDistance - AItems[i].Line[2].X
          - AItems[i].LabelDistance;
    end
    else if AItems[i].AlignTo = tpaLabelLine then
    begin
      if AItems[i].LabelX < ACX then
        t := leftmostX - AView.X - AItems[i].BleedMargin
      else
        t := AView.X + AView.W - rightmostX - AItems[i].BleedMargin;
    end
    else
    begin
      if AItems[i].LabelX < ACX then
        t := AItems[i].LabelX - AView.X - AItems[i].BleedMargin
      else
        t := AView.X + AView.W - AItems[i].LabelX - AItems[i].BleedMargin;
    end;
    AItems[i].HasTarget := True;
    AItems[i].Target := t;
    PieConstrain(S, i, t, False);
  end;

  PieAdjustSide(S, right, 1, rightmostX);
  PieAdjustSide(S, left, -1, leftmostX);

  { every line stood off its label again: edge from the text's real width,
    the others from the label's x with the middle point keeping its
    distance; the last segment level with the label }
  for i := 0 to High(AItems) do
  begin
    if AItems[i].Centre or not AItems[i].HasLine then Continue;
    if AItems[i].HasBackground then realW := AItems[i].Rect.W
    else realW := AItems[i].Rect.W + AItems[i].PaddingH;
    dist := AItems[i].Line[1].X - AItems[i].Line[2].X;
    if AItems[i].AlignTo = tpaEdge then
    begin
      if AItems[i].LabelX < ACX then
        AItems[i].Line[2].X := AView.X + AItems[i].EdgeDistance + realW
          + AItems[i].LabelDistance
      else
        AItems[i].Line[2].X := AView.X + AView.W - AItems[i].EdgeDistance - realW
          - AItems[i].LabelDistance;
    end
    else
    begin
      if AItems[i].LabelX < ACX then
        AItems[i].Line[2].X := AItems[i].LabelX + AItems[i].LabelDistance
      else
        AItems[i].Line[2].X := AItems[i].LabelX - AItems[i].LabelDistance;
      AItems[i].Line[1].X := AItems[i].Line[2].X + dist;
    end;
    AItems[i].Line[1].Y := AItems[i].LabelY;
    AItems[i].Line[2].Y := AItems[i].LabelY;
  end;
end;

function TyPiePlainFit(const AText: string; AHasWidth: Boolean; AWidth: Double;
  ATruncate: Boolean; const AEllipsis: string; const AMeasurer: ITyTextMeasurer;
  const AFontName: string; AFontSizeLogical, AWeight: Integer;
  out AContentW: Double): string;
var
  lines: TStringArray;
  i: Integer;
  w, h: Double;
begin
  AContentW := 0;
  Result := AText;
  if (AText = '') or (AMeasurer = nil) then Exit;
  if AHasWidth and ATruncate then
  begin
    lines := TyZrPlainTextLines(AText, AWidth, MaxDouble, 0, AEllipsis,
      AMeasurer, AFontName, AFontSizeLogical, AWeight);
    Result := string.Join(#10, lines);
  end
  else
    lines := AText.Split([#10]);
  for i := 0 to High(lines) do
  begin
    if lines[i] = '' then Continue;
    AMeasurer.MeasureLine(lines[i], AFontName, AFontSizeLogical, AWeight, w, h);
    if w > AContentW then AContentW := w;
  end;
end;

procedure TyPieLabelMargin(const AInk: TTyLabelSpec; AScale: Double;
  out AType: Integer; out AMargin: TTyPieMargin);
var k: Integer;
begin
  case AInk.MarginType of
    1:
      begin
        AType := 1;
        for k := 0 to 3 do AMargin[k] := AInk.MarginLogical[k] * AScale;
        { minMarginForce [null, 0, null, 0] }
        AMargin[1] := 0;
        AMargin[3] := 0;
      end;
    2:
      begin
        AType := 2;
        for k := 0 to 3 do AMargin[k] := AInk.MarginLogical[k] * AScale;
      end;
  else
    { marginDefault [1, 0, 1, 0], as a textMargin }
    AType := 2;
    AMargin[0] := 1 * AScale;
    AMargin[1] := 0;
    AMargin[2] := 1 * AScale;
    AMargin[3] := 0;
  end;
end;

function TyPieLabelGlobalRect(const ARaw: TTyXYWH; ALabelX, ALabelY, AOffX,
  AOffY, ARotation: Double; AMarginType: Integer;
  const AMargin: TTyPieMargin): TTyXYWH;
var
  m: TTyMat2D;
  has: Boolean;
begin
  has := TyLabelLocalTransform(ALabelX + AOffX, ALabelY + AOffY, -AOffX, -AOffY,
    ARotation, 1, 1, m);
  Result := TyLabelGeometry(ARaw, m, has, AMarginType, AMargin).Rect;
end;

{ the box of a one-run text in its own frame, as the TSpan's (left, middle)
  -- the alignment the label has when the solver measures it }
function PiePlainRaw(AW, AH: Double): TTyXYWH;
var y: Double;
begin
  y := 0 - AH / 2;
  Result := TyXYWH(0, y, (0 + AW) - 0, (y + AH) - y);
end;

{ ==================== the marks ==================== }

type
  { WHAT A PIE LABEL IS MEASURED FROM, for the solver's rect and for the
    marks after it: one entry per label in the solver's list. [Batch 109] }
  TPieFit = class
  public
    Measurer: ITyTextMeasurer;
    FontName: string;
    FontSize, FontWeight: Integer;
    Scale: Double;
    { a plain label is cut under a width (overflow 'truncate', the pie's
      default), ending in Ellipsis }
    Truncate: Boolean;
    Ellipsis: string;
    { the block's spec, the fonts set; Rich: the label is a block }
    Lbl: TTyLabelSpec;
    Rich: Boolean;
    MarginType: Integer;
    Margin: TTyPieMargin;
    OffX, OffY: Double;
    Words: array of string;
    Fills: array of TTyChartColor;
    Rots: array of Double;
    LineH: array of Double;
    { the block's spec under a width the solver set }
    function SpecUnder(AHasWidth: Boolean; AWidth: Double): TTyLabelSpec;
    { the label's own box, as the solver measures it (left, middle) }
    function Raw(AIndex: Integer; AHasWidth: Boolean; AWidth: Double): TTyXYWH;
    { computeLabelGlobalRect }
    function RectOf(const AItem: TTyPieAvoidItem; AIndex: Integer): TTyXYWH;
  end;

function TPieFit.SpecUnder(AHasWidth: Boolean; AWidth: Double): TTyLabelSpec;
begin
  Result := Lbl;
  if not AHasWidth then Exit;
  Result.Rt.Style.WidthKind := rtwNumber;
  { the block's numbers are CSS px }
  Result.Rt.Style.Width := AWidth / Scale;
end;

function TPieFit.Raw(AIndex: Integer; AHasWidth: Boolean; AWidth: Double): TTyXYWH;
var
  pieces: TTyRtPieceArray;
  b: TTyXYWH;
  cw: Double;
begin
  { an empty text has no lines, and its box is the empty one at the origin }
  if Words[AIndex] = '' then Exit(TyXYWH(0, 0, 0, 0));
  if Rich then
  begin
    pieces := TyLabelBlockPieces(SpecUnder(AHasWidth, AWidth), Words[AIndex],
      Fills[AIndex], True, False, False, tahLeft, tavMiddle, Scale, Measurer);
    b := TyRtBounds(pieces);
    if Scale = 1 then Exit(b);
    Exit(TyXYWH(b.X * Scale, b.Y * Scale, b.W * Scale, b.H * Scale));
  end;
  TyPiePlainFit(Words[AIndex], AHasWidth, AWidth, Truncate, Ellipsis, Measurer,
    FontName, FontSize, FontWeight, cw);
  Result := PiePlainRaw(cw, LineH[AIndex]);
end;

function TPieFit.RectOf(const AItem: TTyPieAvoidItem; AIndex: Integer): TTyXYWH;
begin
  Result := TyPieLabelGlobalRect(Raw(AIndex, AItem.HasWidth, AItem.Width),
    AItem.LabelX, AItem.LabelY, OffX, OffY, Rots[AIndex], MarginType, Margin);
end;

function TyBuildPieLabels(const ABinding: TTySeriesBinding;
  const ALayout: TTyPieLayout; const ASpec: TTyPieLabelSpec;
  const AInk: TTyPieLabelInk; const AFills: array of TTyChartColor;
  AStore: TTyDataStore; const ASeriesName: string; AValueDim,
  APercentPrecision: Integer; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;
type
  { one placed label, before the solver }
  TPieLab = record
    Sector: Integer;
    Place: TTyPieLabelPlacement;
    Words: string;
    Fill: TTyChartColor;
    W, H: Double;
    { its place in the solver's list, -1 for an inside label }
    Avoid: Integer;
  end;
var
  i, k, a, row, nl, na: Integer;
  percents: TTyDoubleArray;
  place: TTyPieLabelPlacement;
  words, drawn: string;
  w, h, cw, scale, bleed, lastRot, lastCX, lastCY: Double;
  box: TTyRectF;
  el: TTyChartElement;
  fill: TTyChartColor;
  lbl: TTyLabelSpec;
  ink, stroke: TTyChartColor;
  strokeW: Double;
  pts: array[0..2] of TTyPointF;
  labs: array of TPieLab;
  items: TTyPieAvoidItemArray;
  fit: TPieFit;
  hasWidth, hasRotate: Boolean;
  width: Double;
begin
  Result := 0;
  if (AList = nil) or (AMeasurer = nil) then Exit;
  if not ALayout.Valid then Exit;
  if not ASpec.Show then Exit;
  if APPI > 0 then scale := APPI / 96 else scale := 1;

  { The three bands and the outside ink, packed into the shape the shared
    chooser wants. A pie has no use for the rest of a label spec -- its
    geometry came from somewhere else entirely -- so only the colour fields
    are filled in. }
  lbl := ASpec.Ink;
  lbl.InsideColour[0] := AInk.InsideColour[0];
  lbl.InsideColour[1] := AInk.InsideColour[1];
  lbl.InsideColour[2] := AInk.InsideColour[2];
  lbl.OutsideColour := AInk.OutsideColour;
  lbl.Ground := AInk.Ground;
  lbl.GroundDark := AInk.GroundDark;
  lbl.FontName := AInk.FontName;
  lbl.FontSizeLogical := AInk.FontSizeLogical;
  lbl.FontWeight := AInk.FontWeight;
  { THE PIE'S DEFAULT OVERFLOW IS 'truncate', and it is the label style's:
    a block cuts under any width -- the author's or the solver's -- unless the
    label wrote another overflow (the block reads only what was written)
    [Batch 109] }
  if lbl.Rt.Needed and (ASpec.Overflow = tloTruncate)
    and (lbl.Rt.Style.Overflow = rtoNone) then
    lbl.Rt.Style.Overflow := rtoTruncate;
  percents := TyPieSectorPercents(ALayout, APercentPrecision);

  { bleedMargin's computed default, from the view in CSS px [Batch 109] }
  if IsNan(ASpec.BleedMargin) then
    bleed := TyPieBleedMargin(TyRectF(0, 0, TyRectFWidth(ALayout.ViewRect) / scale,
      TyRectFHeight(ALayout.ViewRect) / scale)) * scale
  else
    bleed := ASpec.BleedMargin * scale;

  fit := TPieFit.Create;
  try
    fit.Measurer := AMeasurer;
    fit.FontName := AInk.FontName;
    fit.FontSize := AInk.FontSizeLogical;
    fit.FontWeight := AInk.FontWeight;
    fit.Scale := scale;
    fit.Truncate := ASpec.Overflow = tloTruncate;
    fit.Ellipsis := ASpec.Ellipsis;
    fit.Lbl := lbl;
    fit.Rich := lbl.Rt.Needed;
    TyPieLabelMargin(ASpec.Ink, scale, fit.MarginType, fit.Margin);
    if APPI > 0 then
    begin
      fit.OffX := ASpec.OffsetXLogical * scale;
      fit.OffY := ASpec.OffsetYLogical * scale;
    end;

    { ---- every label placed, and the solver's list: the outer and centre
      ones, in data order ---- }
    SetLength(labs, Length(ALayout.Sectors));
    SetLength(items, Length(ALayout.Sectors));
    nl := 0;
    na := 0;
    lastRot := 0;
    lastCX := ALayout.CX;
    lastCY := ALayout.CY;
    for i := 0 to High(ALayout.Sectors) do
    begin
      { VALID, NOT `the radius is a number`. A NaN datum keeps the ring's own
        radius on an ordinary pie and only goes NaN under roseType, so a radius
        test would label every gap on a plain pie. }
      if not ALayout.Sectors[i].Valid then Continue;
      place := PlacePie(ASpec, ALayout, ALayout.Sectors[i], APPI, False);
      if not place.Valid then Continue;
      { upstream keeps the LAST label's turn, inside ones included, and the
        last label's centre }
      lastRot := place.RotationRad;
      lastCX := ALayout.Sectors[i].CX;
      lastCY := ALayout.Sectors[i].CY;

      { A PIE SAYS ITS NAME, not its value -- getFormattedLabel falls back to
        the datum's name where a bar falls back to its number. The row asked
        is the VIEW row, the one the store's accessors answer for: with a slice
        deselected in the legend the raw index named the next slice along. `{a}`
        is the series' NAME, `{c}` its value, `{d}` its share. }
      words := TyLabelText(ASpec.Formatter, ASpec.HasFormatter, tldName, AStore,
        ALayout.Sectors[i].Index, ASeriesName, AValueDim, percents[i], True,
        ABinding.SeriesIndex, ABinding.SeriesType);
      if Length(AFills) > 0 then fill := AFills[i mod Length(AFills)]
      else fill := AInk.OutsideColour;
      w := 0;
      h := 0;
      if words <> '' then
        AMeasurer.MeasureLine(words, AInk.FontName, AInk.FontSizeLogical,
          AInk.FontWeight, w, h);

      labs[nl].Sector := i;
      labs[nl].Place := place;
      labs[nl].Words := words;
      labs[nl].Fill := fill;
      labs[nl].W := w;
      labs[nl].H := h;
      labs[nl].Avoid := -1;
      if ASpec.Position <> tplInside then
      begin
        labs[nl].Avoid := na;
        items[na] := Default(TTyPieAvoidItem);
        items[na].Centre := ASpec.Position = tplCentre;
        items[na].OuterWord := ASpec.PositionWord = 'outer';
        items[na].HasLine := ASpec.Position = tplOuter;
        items[na].AlignTo := ASpec.AlignTo;
        items[na].Len := place.LineLen;
        items[na].Len2 := place.LineLen2;
        items[na].LabelDistance := place.DistToLine;
        items[na].EdgeDistance := place.EdgeDist;
        items[na].BleedMargin := bleed;
        if fit.Rich then
        begin
          items[na].HasStyleWidth := lbl.Rt.Style.WidthKind <> rtwNone;
          if lbl.Rt.Style.HasPadding then
            items[na].PaddingH := (lbl.Rt.Style.Padding[1] + lbl.Rt.Style.Padding[3]) * scale;
          items[na].HasBackground := lbl.Rt.Style.HasBackground;
        end;
        items[na].LabelX := place.BaseX;
        items[na].LabelY := place.BaseY;
        items[na].Line[0] := place.P1;
        items[na].Line[1] := place.P2;
        items[na].Line[2] := place.P3;
        SetLength(fit.Words, na + 1);
        SetLength(fit.Fills, na + 1);
        SetLength(fit.Rots, na + 1);
        SetLength(fit.LineH, na + 1);
        fit.Words[na] := words;
        fit.Fills[na] := fill;
        fit.Rots[na] := place.RotationRad;
        fit.LineH[na] := h;
        items[na].Rect := fit.RectOf(items[na], na);
        items[na].UnconstrainedWidth := items[na].Rect.W;
        Inc(na);
      end;
      Inc(nl);
    end;
    SetLength(labs, nl);
    SetLength(items, na);

    { ---- avoidOverlap: unless the series says no, or the LAST label is
      turned (`hasLabelRotate` is overwritten label by label upstream) ---- }
    hasRotate := (lastRot <> 0) and not IsNan(lastRot);
    if (not hasRotate) and (not ASpec.NoAvoidOverlap) and (na > 0) then
      TyPieAvoidOverlap(items, lastCX, lastCY, ALayout.R1,
        TyXYWHOfRect(ALayout.ViewRect), @fit.RectOf);

    { ---- the marks ---- }
    for k := 0 to nl - 1 do
    begin
      i := labs[k].Sector;
      place := labs[k].Place;
      words := labs[k].Words;
      fill := labs[k].Fill;
      a := labs[k].Avoid;
      hasWidth := False;
      width := 0;
      if a >= 0 then
      begin
        { where the solver left it }
        place.BaseX := items[a].LabelX;
        place.BaseY := items[a].LabelY;
        place.P1 := items[a].Line[0];
        place.P2 := items[a].Line[1];
        place.P3 := items[a].Line[2];
        hasWidth := items[a].HasWidth;
        width := items[a].Width;
        PieApplyOffset(place, ASpec, APPI);
      end;
      row := ALayout.Sectors[i].RawIndex;

      { The line first, so the words sit over it where they meet. }
      if place.HasLine then
      begin
        pts[0] := place.P1;
        pts[1] := place.P2;
        pts[2] := place.P3;
        { THE LAST PASS BENDS EVERY LINE, moved or not: the turn, then the
          angle to the slice's surface (labelLayout.ts:579-583) [Batch 112] }
        TyLimitTurnAngle(pts, ASpec.MinTurnAngle);
        TyLimitSurfaceAngle(pts, place.NX, place.NY, ASpec.MaxSurfaceAngle);
        el := TyChartElement(TyShapePolyline(pts));
        el.Shape.Cmds := TyLabelLineCmds(pts, ASpec.Smooth);
        el.Caption.LgSmooth := ASpec.Smooth;
        el.Style.StrokeColor := fill;
        el.Style.StrokeWidthLogical := AInk.LineWidthLogical;
        { SILENT. A leader line is a pointer at the slice, not a target of its
          own, and a hit on it would report the datum twice over. }
        el.Silent := True;
        { but it is the slice's: its select state moves it [Batch 88] }
        el.IsGuide := True;
        el.Datum := TyChartDatum(ABinding.SeriesIndex, ALayout.Sectors[i].Index, row);
        { it draws itself in on entering (LabelManager's strokePercent) }
        el.Anim.Role := carGuide;
        el.Anim.Series := ABinding.SeriesIndex;
        el.Anim.Index := ALayout.Sectors[i].Index;
        AList.Add(el);
        Inc(Result);
      end;

      { AN EMPTY TEXT KEEPS ITS LINE: a formatter of '' is an empty label, and
        upstream still draws the line that points at it. }
      if words = '' then Continue;
      h := labs[k].H;
      { THE WORDS AS DRAWN: cut where the solver gave the label a width --
        zrender truncates under style.width and nowhere else [Batch 109] }
      if fit.Rich then
      begin
        { the block cuts itself, below }
        drawn := words;
        cw := labs[k].W;
      end
      else
      begin
        drawn := TyPiePlainFit(words, hasWidth, width, fit.Truncate, ASpec.Ellipsis,
          AMeasurer, AInk.FontName, AInk.FontSizeLogical, AInk.FontWeight, cw);
        if not hasWidth then cw := labs[k].W;
      end;
      if (cw <= 0) or (h <= 0) then Continue;
      case place.AnchorH of
        tahCentre: box.Left := place.X - cw / 2;
        tahRight: box.Left := place.X - cw;
      else
        box.Left := place.X;
      end;
      box.Right := box.Left + cw;
      { Always the middle -- upstream's last word on a pie label. }
      box.Top := place.Y - h / 2;
      box.Bottom := box.Top + h;

      el := TyChartElement(TyShapeRect(box));
      el.Caption.Text := drawn;
      if drawn <> words then el.Caption.LmText := words;
      el.Caption.FontName := AInk.FontName;
      el.Caption.FontSizeLogical := AInk.FontSizeLogical;
      el.Caption.FontWeight := AInk.FontWeight;
      TyLabelInk(lbl, fill, True, False, ASpec.Position = tplInside, ink, stroke,
        strokeW);
      TyLabelStampEmphasis(lbl, fill, True, False, ASpec.Position = tplInside,
        el.Caption);
      { THE BLOCK, where the label's style needs one: laid out about the place
        the pie gave it, 'inherit' the slice's colour [Batch 86], under the
        width the solver gave it [Batch 109] }
      if fit.Rich then
      begin
        el.Caption.RtScale := scale;
        el.Caption.RtPieces := TyLabelBlockPieces(fit.SpecUnder(hasWidth, width),
          words, fill, True, False, ASpec.Position = tplInside, place.AnchorH,
          tavMiddle, el.Caption.RtScale, AMeasurer);
        if Length(el.Caption.RtPieces) > 0 then
        begin
          el.Shape := TyShapeRect(TyRtDeviceBox(el.Caption.RtPieces, place.X,
            place.Y, place.RotationRad, el.Caption.RtScale));
          el.Caption.RtEmph := TyRtReink(el.Caption.RtPieces, el.Caption.EmphColour,
            True, el.Caption.EmphStrokeColour, el.Caption.EmphStrokeWidthLogical);
        end;
      end;
      el.Caption.Colour := ink;
      el.Caption.StrokeColour := stroke;
      el.Caption.StrokeWidthLogical := strokeW;
      el.Caption.X := place.X;
      el.Caption.Y := place.Y;
      el.Caption.AnchorH := place.AnchorH;
      el.Caption.AnchorV := place.AnchorV;
      el.Caption.RotationRad := place.RotationRad;
      { ALREADY CUT: zrender truncates only under a width, and the width is
        the solver's -- the text above is what it draws [Batch 109] }
      el.Caption.Truncate := False;
      { WHAT THE LABEL LAYOUT READS: a pie label is placed at label.x / y (its
        host's position is null) with its style's alignment; the host is found
        by the datum [Batch 103] }
      el.Caption.LmKind := 2;
      el.Caption.LmBaseX := place.BaseX;
      el.Caption.LmBaseY := place.BaseY;
      el.Caption.LmOffX := place.OffX;
      el.Caption.LmOffY := place.OffY;
      el.Caption.LmPosAH := place.AnchorH;
      el.Caption.LmPosAV := tavMiddle;
      el.Caption.LmStyleHasAH := True;
      el.Caption.LmStyleHasAV := True;
      el.Caption.LmStyleAH := place.AnchorH;
      el.Caption.LmStyleAV := tavMiddle;
      el.Caption.LmTextW := cw;
      el.Caption.LmTextH := h;
      { the label's own minMargin / textMargin, as LabelManager reads them
        [Batch 109] }
      el.Caption.LmMarginType := ASpec.Ink.MarginType;
      el.Caption.LmMargin[0] := ASpec.Ink.MarginLogical[0] * scale;
      el.Caption.LmMargin[1] := ASpec.Ink.MarginLogical[1] * scale;
      el.Caption.LmMargin[2] := ASpec.Ink.MarginLogical[2] * scale;
      el.Caption.LmMargin[3] := ASpec.Ink.MarginLogical[3] * scale;
      el.Caption.LmInkFill := fill;
      el.Caption.LmInkHasFill := True;
      el.Caption.LmInkInside := ASpec.Position = tplInside;
      el.Silent := False;
      { `row` is the RAW index -- see TyBuildPieMarks for why a pie needs both. }
      el.Datum := TyChartDatum(ABinding.SeriesIndex,
        ALayout.Sectors[i].Index, row);
      el.Z2 := 1;
      { it fades in on entering, where it stands (LabelManager) [Batch 89] }
      el.Anim.Role := carLabel;
      el.Anim.Series := ABinding.SeriesIndex;
      el.Anim.Index := ALayout.Sectors[i].Index;
      AList.Add(el);
      Inc(Result);
    end;
  finally
    fit.Free;
  end;
end;

end.
