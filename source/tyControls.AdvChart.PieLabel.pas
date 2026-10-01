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

  WHAT IS NOT HERE: the overlap solver. Upstream can shift outer labels up and
  down a side, re-solve their x on an ellipse, borrow room from a neighbour and
  truncate a label to fit the view rect. None of that is needed to put ONE
  label in the right place, all of it is needed to keep several from landing on
  each other, and it is its own piece of work. Until it lands, a crowded pie
  draws its outer labels overlapping where ECharts would have moved them apart.
  Said here rather than left for a reader to discover.

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
  end;

  { One placed label, DEVICE px. AnchorV is always the middle -- upstream forces
    it unconditionally after everything else has been decided. }
  TTyPieLabelPlacement = record
    Valid: Boolean;
    X, Y: Double;
    AnchorH: TTyTextAnchorH;
    AnchorV: TTyTextAnchorV;
    RotationRad: Double;
    { The guide line, three points and so two segments. The SECOND one is
      horizontal by construction -- y3 is copied from y2 rather than computed --
      which is what makes a column of outer labels line up. }
    HasLine: Boolean;
    P1, P2, P3: TTyPointF;
  end;

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

uses tyControls.AdvChart.RichStyle;

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
begin
  Result := ABase;
  if AOption = nil then Exit;
  series := ObjOf(AOption.ComponentAt('series', ASlot));
  if series = nil then Exit;

  Result.MinShowLabelDeg := NumIn(series, 'minShowLabelAngle',
    Result.MinShowLabelDeg);

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
    else if s = 'none' then Result.Overflow := tloNone;
  end;

  line := ObjOf(series.Find('labelLine'));
  if line <> nil then
  begin
    d := line.Find('show');
    if (d <> nil) and (d.JSONType = jtBoolean) then
      Result.ShowLine := d.AsBoolean;
    Result.LineLength := LengthIn(line, 'length', Result.LineLength);
    Result.LineLength2 := LengthIn(line, 'length2', Result.LineLength2);
  end;
end;

{ ==================== the placement ==================== }

function TyPlacePieLabel(const ASpec: TTyPieLabelSpec;
  const ALayout: TTyPieLayout; const ASector: TTyPieSector;
  APPI: Integer): TTyPieLabelPlacement;
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

  mid := (ASector.StartRad + ASector.EndRad) / 2;
  nx := Cos(mid);
  ny := Sin(mid);

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
    rad := ArcTan2(nx, ny);
    if rad < 0 then rad := 2 * Pi + rad;
    if (ny > 0) and (ASpec.Rotate <> tprTangentialNoFlip) then rad := Pi + rad;
    Result.RotationRad := rad - Pi;
  end;

  { OFFSET LAST, after everything else has placed the words. Upstream applies
    it INSIDE the rotation -- it moves the rotation origin too, so a rotated
    label's offset runs along the rotated axes. This applies it in screen
    axes, because the painter rotates about the anchor and has no separate
    origin to move. The two agree whenever the label is not rotated, which is
    the default. }
  if APPI > 0 then
  begin
    Result.X := Result.X + ASpec.OffsetXLogical * scale;
    Result.Y := Result.Y + ASpec.OffsetYLogical * scale;
  end;

  Result.Valid := True;
end;

{ ==================== the marks ==================== }

function TyBuildPieLabels(const ABinding: TTySeriesBinding;
  const ALayout: TTyPieLayout; const ASpec: TTyPieLabelSpec;
  const AInk: TTyPieLabelInk; const AFills: array of TTyChartColor;
  AStore: TTyDataStore; const ASeriesName: string; AValueDim,
  APercentPrecision: Integer; const AMeasurer: ITyTextMeasurer;
  APPI: Integer; AList: TTyPaintList): Integer;
var
  i, row: Integer;
  percents: TTyDoubleArray;
  place: TTyPieLabelPlacement;
  words: string;
  w, h: Double;
  box: TTyRectF;
  el: TTyChartElement;
  fill: TTyChartColor;
  lbl: TTyLabelSpec;
  ink, stroke: TTyChartColor;
  strokeW: Double;
  pts: array[0..2] of TTyPointF;
begin
  Result := 0;
  if (AList = nil) or (AMeasurer = nil) then Exit;
  if not ALayout.Valid then Exit;
  if not ASpec.Show then Exit;

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
  percents := TyPieSectorPercents(ALayout, APercentPrecision);

  for i := 0 to High(ALayout.Sectors) do
  begin
    { VALID, NOT `the radius is a number`. A NaN datum keeps the ring's own
      radius on an ordinary pie and only goes NaN under roseType, so a radius
      test would label every gap on a plain pie. }
    if not ALayout.Sectors[i].Valid then Continue;
    place := TyPlacePieLabel(ASpec, ALayout, ALayout.Sectors[i], APPI);
    if not place.Valid then Continue;

    row := ALayout.Sectors[i].RawIndex;
    { A PIE SAYS ITS NAME, not its value -- getFormattedLabel falls back to
      the datum's name where a bar falls back to its number. The row asked
      is the VIEW row, the one the store's accessors answer for: with a slice
      deselected in the legend the raw index named the next slice along. `{a}`
      is the series' NAME, `{c}` its value, `{d}` its share.
      AN EMPTY TEXT KEEPS ITS LINE: a formatter of '' is an empty label, and
      upstream still draws the line that points at it. }
    words := TyLabelText(ASpec.Formatter, ASpec.HasFormatter, tldName, AStore,
      ALayout.Sectors[i].Index, ASeriesName, AValueDim, percents[i], True,
      ABinding.SeriesIndex, ABinding.SeriesType);

    if Length(AFills) > 0 then fill := AFills[i mod Length(AFills)]
    else fill := AInk.OutsideColour;

    { The line first, so the words sit over it where they meet. }
    if place.HasLine then
    begin
      pts[0] := place.P1;
      pts[1] := place.P2;
      pts[2] := place.P3;
      el := TyChartElement(TyShapePolyline(pts));
      el.Style.StrokeColor := fill;
      el.Style.StrokeWidthLogical := AInk.LineWidthLogical;
      { SILENT. A leader line is a pointer at the slice, not a target of its
        own, and a hit on it would report the datum twice over. }
      el.Silent := True;
      { it draws itself in on entering (LabelManager's strokePercent) }
      el.Anim.Role := carGuide;
      el.Anim.Series := ABinding.SeriesIndex;
      el.Anim.Index := ALayout.Sectors[i].Index;
      AList.Add(el);
      Inc(Result);
    end;

    AMeasurer.MeasureLine(words, AInk.FontName, AInk.FontSizeLogical,
      AInk.FontWeight, w, h);
    if (w <= 0) or (h <= 0) then Continue;
    case place.AnchorH of
      tahCentre: box.Left := place.X - w / 2;
      tahRight: box.Left := place.X - w;
    else
      box.Left := place.X;
    end;
    box.Right := box.Left + w;
    { Always the middle -- upstream's last word on a pie label. }
    box.Top := place.Y - h / 2;
    box.Bottom := box.Top + h;

    el := TyChartElement(TyShapeRect(box));
    el.Caption.Text := words;
    el.Caption.FontName := AInk.FontName;
    el.Caption.FontSizeLogical := AInk.FontSizeLogical;
    el.Caption.FontWeight := AInk.FontWeight;
    TyLabelInk(lbl, fill, True, False, ASpec.Position = tplInside, ink, stroke,
      strokeW);
    TyLabelStampEmphasis(lbl, fill, True, False, ASpec.Position = tplInside,
      el.Caption);
    { THE BLOCK, where the label's style needs one: laid out about the place
      the pie gave it, 'inherit' the slice's colour [Batch 86] }
    if lbl.Rt.Needed then
    begin
      lbl.FontName := AInk.FontName;
      lbl.FontSizeLogical := AInk.FontSizeLogical;
      lbl.FontWeight := AInk.FontWeight;
      el.Caption.RtScale := APPI / 96;
      el.Caption.RtPieces := TyLabelBlockPieces(lbl, words, fill, True, False,
        ASpec.Position = tplInside, place.AnchorH, tavMiddle, el.Caption.RtScale,
        AMeasurer);
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
    el.Caption.Truncate := ASpec.Overflow = tloTruncate;
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
end;

end.
