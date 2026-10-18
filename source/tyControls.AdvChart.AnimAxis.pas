unit tyControls.AdvChart.AnimAxis;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- an axis' groupTransition: its elements as upstream's
  axis view builds them, keyed by anid. [Batch 96, AN5]

  A full update of the same option (a legend toggle, a dataZoom) renders a
  cartesian axis view again: the old _axisGroup is kept, a new one built,
  and every leaf of the new group whose anid an old leaf had is set to the
  old one's x / y / rotation and shape, then updateProps to its own, on the
  axis model at no data index (util/graphic.ts groupTransition). A leaf no
  old one matches appears at once; an old one nothing matches is gone. Only
  the place moves: the style is the new one's from the start.

  THE ELEMENTS AND THEIR ANIDS (component/axis/AxisBuilder.ts,
  CartesianAxisView.ts):
    line          'line'               the axis line: (extent[0], 0) and
                                       (extent[1], 0) through the axis
                                       group's matrix, subPixelOptimizeLine
    ticks         'ticks_' + value     (coord, 0) and (coord, tickDirection
                                       * length) through the same matrix --
                                       a y axis' quarter turn is not exact
                                       (cos(pi/2) is 6e-17) and moves the
                                       ends in their last bits -- then
                                       subPixelOptimizeLine
    labels        'label_' + value     the decomposed place and turn of the
                                       label (its x, y, rotation)
    split lines   'line_' + value      across the grid rect at the tick's
                                       canvas coordinate, then
                                       subPixelOptimizeLine
  The value is the tick's, as JavaScript writes the number: a category
  axis' ordinal, the band edge past the last category one more. A LABEL'S is
  getTickValueOutermost's: on a sorted category axis the RAW ordinal of the
  category it shows, so a bar race's label keeps its anid as it moves to
  another tick (a tick mark and a split line keep the tick number, and stay)
  [Batch 135].

    break areas  'break_a_' + id,      each break's zigzag polylines A and B
                 'break_b_' + id,      and the polygon between them (A, then
                 'break_c_' + id       B backwards) -- shape.points, arrays
                                       of a length the render decides, cut
                                       or padded by zrender's fillArray;
                                       id the break's identity [F4a]
    minor ticks  'minorticks_' + i      (coord, 0) and (coord, tickDirection
                 + '_' + value         * minorTick.length) through the axis
                                       group's matrix, subPixelOptimizeLine
                                       on the minor pen; i the major interval
                                       the tick subdivides [F3b]
    minor split  'minor_line_' + value across the grid rect, as a split line,
    lines                              on the minor split pen [F3b]
    split areas  'area_' + value       a Rect from the previous edge to this
                                       one (x = prev, width = coord - x,
                                       prev = x + width), the value the
                                       band's first edge's [F3b]
    the name     'name'                its decomposed x, y and rotation, after
                                       nameMoveOverlap [F3b] }
interface
uses SysUtils, Math,
  tyControls.AdvChart.Types, tyControls.AdvChart.Layout, tyControls.AdvChart.Anim;

type
  TTyAxisAnimKind = (aakLine, aakTick, aakLabel, aakSplitLine,
    { [F4a] a break area's polyline A, B and its polygon; [F3b] the minor
      ticks, minor split lines, split areas and the name }
    aakBreakA, aakBreakB, aakBreakC, aakMinorTick, aakMinorSplit, aakSplitArea, aakName);

  { one leaf of an axis group: a Text (X, Y, Rotation) or a Line (X1 .. Y2),
    and where it came from in the spec }
  TTyAxisAnimEl = record
    Anid: string;
    Kind: TTyAxisAnimKind;
    { the mark's index (ticks, split lines) or the placement's (labels) }
    Index: Integer;
    X, Y, Rotation: Double;
    X1, Y1, X2, Y2: Double;
    { a break leaf's points, x and y in turn [F4a] }
    Pts: TTyDoubleArray;
  end;
  TTyAxisAnimElArray = array of TTyAxisAnimEl;

  { a minor tick as Axis.getMinorTicksCoords gives it: its value, its place
    in the axis' own frame (coord) and on the canvas (toGlobalCoord), and
    the major interval it subdivides [F3b] }
  TTyAxisMinorTick = record
    Value: Double;
    Local: Double;
    Global: Double;
    Interval: Integer;
  end;
  TTyAxisMinorTickArray = array of TTyAxisMinorTick;

  { what the spec does not carry: which parts the axis builds, the tick's
    length and the three pens' widths in device px, and the grid's rect as
    upstream's gridRect }
  TTyAxisAnimInput = record
    ShowLine, ShowTicks, ShowLabels, ShowSplitLine, TickInside: Boolean;
    TickLength: Double;
    LineWidth, TickWidth, SplitWidth: Double;
    Horizontal: Boolean;
    Plot: TTyXYWH;
    { a sorted category axis' ordinals by tick (getRawOrdinalNumber); empty
      for none [Batch 135] }
    ByTick: TTyIntegerArray;
    { [F3b] the minor ticks and minor split lines (their ticks, the minor
      tick's length and the two pens' widths, device px), the split areas,
      the name }
    ShowMinorTicks, ShowMinorSplitLine, ShowSplitArea, ShowName: Boolean;
    MinorTickLength, MinorTickWidth, MinorSplitWidth: Double;
    MinorTicks: TTyAxisMinorTickArray;
  end;

{ zrender's subPixelOptimize: a position put on the half pixel (an odd
  width) or the whole pixel (an even one); Math.round, not banker's }
function TySubPixelOptimize(APos, ALineWidth: Double; APositive: Boolean): Double;
{ ... and subPixelOptimizeLine: a line along x or along y (its ends within
  half a pixel of each other) on that grid; a width of nought leaves it }
procedure TySubPixelOptimizeLine(var AX1, AY1, AX2, AY2: Double; ALineWidth: Double);
{ every leaf of the axis group an anid names, as upstream's builder makes it
  from this spec }
function TyAxisAnimElements(const ASpec: TTyAxisLayoutSpec;
  const AIn: TTyAxisAnimInput): TTyAxisAnimElArray;
{ the props groupTransition moves: x / y / rotation of a Text, the four
  ends of a Line, a break leaf's points, a Rect's x, y, width and height }
function TyAxisAnimProps(const AEl: TTyAxisAnimEl): TTyAnimProps;
{ a proxy key: the axis' ('xAxis0') and the anid }
function TyAxisAnimKey(const AAxisKey, AAnid: string): string;
{ a label's anid: 'label_' + its tick value through ABySort (a sorted
  category axis' ordinals by tick) [Batch 135] }
function TyAxisLabelAnid(ATickValue: Double; const AByTick: TTyIntegerArray): string;

implementation

uses tyControls.AdvChart.Scale;

function TySubPixelOptimize(APos, ALineWidth: Double; APositive: Boolean): Double;
var doubled, v: Double;
begin
  { `!lineWidth`: nought and not-a-number leave it }
  if IsNan(ALineWidth) or (ALineWidth = 0) then Exit(APos);
  doubled := TyJsRound(APos * 2);
  v := doubled + TyJsRound(ALineWidth);
  { (d + w) % 2 === 0: an even integer (a negative odd one leaves -1) }
  if Frac(v / 2) = 0 then Result := doubled / 2
  else if APositive then Result := (doubled + 1) / 2
  else Result := (doubled + -1) / 2;
end;

procedure TySubPixelOptimizeLine(var AX1, AY1, AX2, AY2: Double; ALineWidth: Double);
begin
  if IsNan(ALineWidth) or (ALineWidth = 0) then Exit;
  if TyJsRound(AX1 * 2) = TyJsRound(AX2 * 2) then
  begin
    AX1 := TySubPixelOptimize(AX1, ALineWidth, True);
    AX2 := AX1;
  end;
  if TyJsRound(AY1 * 2) = TyJsRound(AY2 * 2) then
  begin
    AY1 := TySubPixelOptimize(AY1, ALineWidth, True);
    AY2 := AY1;
  end;
end;

{ v2ApplyTransform, operation for operation }
procedure Apply(const M: TTyMat2D; AX, AY: Double; out AOX, AOY: Double);
begin
  AOX := M[0] * AX + M[2] * AY + M[4];
  AOY := M[1] * AX + M[3] * AY + M[5];
end;

{ a polyline's points flattened, or a polygon's: A, then B backwards }
function FlatPoints(const AA, AB: TTyBreakPointArray): TTyDoubleArray;
var i, n: Integer;
begin
  SetLength(Result, 2 * (Length(AA) + Length(AB)));
  n := 0;
  for i := 0 to High(AA) do
  begin
    Result[n] := AA[i].X;
    Result[n + 1] := AA[i].Y;
    Inc(n, 2);
  end;
  for i := High(AB) downto 0 do
  begin
    Result[n] := AB[i].X;
    Result[n + 1] := AB[i].Y;
    Inc(n, 2);
  end;
end;

function TyAxisAnimElements(const ASpec: TTyAxisLayoutSpec;
  const AIn: TTyAxisAnimInput): TTyAxisAnimElArray;
var
  n, i: Integer;
  g: TTyMat2D;
  fr: TTyAxisNameFrame;
  tickEnd: Double;
  els: TTyAxisAnimElArray;

  { a new leaf at the end of els; its index }
  function Push(AKind: TTyAxisAnimKind; const AAnid: string; AIndex: Integer): Integer;
  begin
    if n >= Length(els) then SetLength(els, n * 2 + 8);
    els[n] := Default(TTyAxisAnimEl);
    els[n].Kind := AKind;
    els[n].Anid := AAnid;
    els[n].Index := AIndex;
    Inc(n);
    Push := n - 1;
  end;

var
  k: Integer;
  minorEnd, prev: Double;
begin
  Result := nil;
  els := nil;
  n := 0;
  if not ASpec.HasNameFrame then Exit;
  fr := ASpec.NameFrame;
  g := TyMatLocal(fr.PosX, fr.PosY, fr.Rotation);
  { the axis line: the axis' own extent, through the group's matrix -- or
    cut at the breaks, each segment its own leaf [Batch 132] }
  if AIn.ShowLine and ASpec.HasBreakLine then
    for i := 0 to High(ASpec.BreakLineSegs) do
    begin
      k := Push(aakLine, ASpec.BreakLineSegs[i].Anid, -1);
      els[k].X1 := ASpec.BreakLineSegs[i].X1;
      els[k].Y1 := ASpec.BreakLineSegs[i].Y1;
      els[k].X2 := ASpec.BreakLineSegs[i].X2;
      els[k].Y2 := ASpec.BreakLineSegs[i].Y2;
    end
  else if AIn.ShowLine then
  begin
    k := Push(aakLine, 'line', -1);
    Apply(g, fr.Ext0, 0, els[k].X1, els[k].Y1);
    Apply(g, fr.Ext1, 0, els[k].X2, els[k].Y2);
    TySubPixelOptimizeLine(els[k].X1, els[k].Y1, els[k].X2, els[k].Y2,
      AIn.LineWidth);
  end;
  { the major ticks: every one built, a hidden label's too (it is ignored,
    not dropped) }
  if AIn.ShowTicks then
  begin
    tickEnd := fr.NameDirection * AIn.TickLength;
    if AIn.TickInside then tickEnd := -tickEnd;
    for i := 0 to High(ASpec.TickMarks) do
    begin
      k := Push(aakTick, 'ticks_' + TyJsNumberToString(ASpec.TickMarks[i].Value), i);
      Apply(g, ASpec.TickMarks[i].Local, 0, els[k].X1, els[k].Y1);
      Apply(g, ASpec.TickMarks[i].Local, tickEnd, els[k].X2, els[k].Y2);
      TySubPixelOptimizeLine(els[k].X1, els[k].Y1, els[k].X2, els[k].Y2,
        AIn.TickWidth);
    end;
  end;
  { the labels upstream builds, an overlapped one too }
  if AIn.ShowLabels then
    for i := 0 to High(ASpec.Placements) do
    begin
      if not ASpec.Placements[i].Built then Continue;
      if i > High(ASpec.TickValues) then Continue;
      k := Push(aakLabel, TyAxisLabelAnid(ASpec.TickValues[i], AIn.ByTick), i);
      els[k].X := ASpec.Placements[i].X;
      els[k].Y := ASpec.Placements[i].Y;
      if ASpec.Placements[i].HasM then els[k].Rotation := ASpec.Placements[i].DecRotation
      else els[k].Rotation := ASpec.RotationRad;
    end;
  { the split lines the view builds (a denied end is not built) }
  if AIn.ShowSplitLine then
    for i := 0 to High(ASpec.SplitLineMarks) do
    begin
      if not ASpec.SplitLineMarks[i].Drawn then Continue;
      k := Push(aakSplitLine, 'line_' + TyJsNumberToString(ASpec.SplitLineMarks[i].Value), i);
      if AIn.Horizontal then
      begin
        els[k].X1 := ASpec.SplitLineMarks[i].Coord;
        els[k].Y1 := AIn.Plot.Y;
        els[k].X2 := ASpec.SplitLineMarks[i].Coord;
        els[k].Y2 := AIn.Plot.Y + AIn.Plot.H;
      end
      else
      begin
        els[k].X1 := AIn.Plot.X;
        els[k].Y1 := ASpec.SplitLineMarks[i].Coord;
        els[k].X2 := AIn.Plot.X + AIn.Plot.W;
        els[k].Y2 := ASpec.SplitLineMarks[i].Coord;
      end;
      TySubPixelOptimizeLine(els[k].X1, els[k].Y1, els[k].X2, els[k].Y2,
        AIn.SplitWidth);
    end;
  { the break areas: rectCoordBuildBreakAxis adds them to the axis group
    [F4a] }
  for i := 0 to High(ASpec.BreakAreas) do
  begin
    k := Push(aakBreakA, 'break_a_' + ASpec.BreakAreas[i].Id, i);
    els[k].Pts := FlatPoints(ASpec.BreakAreas[i].A, nil);
    if not ASpec.BreakAreas[i].HasB then Continue;
    k := Push(aakBreakB, 'break_b_' + ASpec.BreakAreas[i].Id, i);
    els[k].Pts := FlatPoints(ASpec.BreakAreas[i].B, nil);
    k := Push(aakBreakC, 'break_c_' + ASpec.BreakAreas[i].Id, i);
    els[k].Pts := FlatPoints(ASpec.BreakAreas[i].A, ASpec.BreakAreas[i].B);
  end;
  { [F3b] the minor ticks: createTicks with the minor length, on the minor
    pen }
  if AIn.ShowMinorTicks then
  begin
    minorEnd := fr.NameDirection * AIn.MinorTickLength;
    if AIn.TickInside then minorEnd := -minorEnd;
    for i := 0 to High(AIn.MinorTicks) do
    begin
      k := Push(aakMinorTick, 'minorticks_' + IntToStr(AIn.MinorTicks[i].Interval) + '_'
        + TyJsNumberToString(AIn.MinorTicks[i].Value), i);
      Apply(g, AIn.MinorTicks[i].Local, 0, els[k].X1, els[k].Y1);
      Apply(g, AIn.MinorTicks[i].Local, minorEnd, els[k].X2, els[k].Y2);
      TySubPixelOptimizeLine(els[k].X1, els[k].Y1, els[k].X2, els[k].Y2,
        AIn.MinorTickWidth);
    end;
  end;
  { [F3b] the minor split lines across the grid rect }
  if AIn.ShowMinorSplitLine then
    for i := 0 to High(AIn.MinorTicks) do
    begin
      k := Push(aakMinorSplit, 'minor_line_' + TyJsNumberToString(AIn.MinorTicks[i].Value), i);
      if AIn.Horizontal then
      begin
        els[k].X1 := AIn.MinorTicks[i].Global;
        els[k].Y1 := AIn.Plot.Y;
        els[k].X2 := AIn.MinorTicks[i].Global;
        els[k].Y2 := AIn.Plot.Y + AIn.Plot.H;
      end
      else
      begin
        els[k].X1 := AIn.Plot.X;
        els[k].Y1 := AIn.MinorTicks[i].Global;
        els[k].X2 := AIn.Plot.X + AIn.Plot.W;
        els[k].Y2 := AIn.MinorTicks[i].Global;
      end;
      TySubPixelOptimizeLine(els[k].X1, els[k].Y1, els[k].X2, els[k].Y2,
        AIn.MinorSplitWidth);
    end;
  { [F3b] the split areas: rectCoordAxisBuildSplitArea's rects, every band
    whatever its colour; the edge carried as x + width }
  if AIn.ShowSplitArea and (Length(ASpec.SplitAreaMarks) > 0) then
  begin
    prev := ASpec.SplitAreaMarks[0].Coord;
    for i := 1 to High(ASpec.SplitAreaMarks) do
    begin
      k := Push(aakSplitArea, 'area_' + TyJsNumberToString(ASpec.SplitAreaMarks[i - 1].Value), i - 1);
      if AIn.Horizontal then
      begin
        els[k].X1 := prev;
        els[k].Y1 := AIn.Plot.Y;
        els[k].X2 := ASpec.SplitAreaMarks[i].Coord - els[k].X1;
        els[k].Y2 := AIn.Plot.H;
        prev := els[k].X1 + els[k].X2;
      end
      else
      begin
        els[k].X1 := AIn.Plot.X;
        els[k].Y1 := prev;
        els[k].X2 := AIn.Plot.W;
        els[k].Y2 := ASpec.SplitAreaMarks[i].Coord - els[k].Y1;
        prev := els[k].Y1 + els[k].Y2;
      end;
    end;
  end;
  { [F3b] the name: a Text on the axis group, decomposed }
  if AIn.ShowName and ASpec.NamePlacement.Shown then
  begin
    k := Push(aakName, 'name', -1);
    els[k].X := ASpec.NamePlacement.X;
    els[k].Y := ASpec.NamePlacement.Y;
    els[k].Rotation := ASpec.NamePlacement.RotationRad;
  end;
  SetLength(els, n);
  Result := els;
end;

function TyAxisLabelAnid(ATickValue: Double; const AByTick: TTyIntegerArray): string;
var v: Double;
begin
  v := ATickValue;
  { getRawOrdinalNumber: the map inside it, the number itself outside }
  if (Length(AByTick) > 0) and not IsNan(v) and (v >= 0) and (v < Length(AByTick))
    and (Frac(v) = 0) then
    v := AByTick[Trunc(v)];
  Result := 'label_' + TyJsNumberToString(v);
end;

function TyAxisAnimProps(const AEl: TTyAxisAnimEl): TTyAnimProps;
begin
  if AEl.Kind in [aakBreakA, aakBreakB, aakBreakC] then
    Result := TyAnimProps([TyAnimProp('shape.points', TyAnimArr(AEl.Pts, 2))])
  { a split area's Rect: x, y, width, height in X1 .. Y2 [F3b] }
  else if AEl.Kind = aakSplitArea then
    Result := TyAnimProps([TyAnimProp('shape.x', TyAnimNum(AEl.X1)),
      TyAnimProp('shape.y', TyAnimNum(AEl.Y1)), TyAnimProp('shape.width', TyAnimNum(AEl.X2)),
      TyAnimProp('shape.height', TyAnimNum(AEl.Y2))])
  else if AEl.Kind in [aakLabel, aakName] then
    Result := TyAnimProps([TyAnimProp('x', TyAnimNum(AEl.X)),
      TyAnimProp('y', TyAnimNum(AEl.Y)), TyAnimProp('rotation', TyAnimNum(AEl.Rotation))])
  else
    Result := TyAnimProps([TyAnimProp('shape.x1', TyAnimNum(AEl.X1)),
      TyAnimProp('shape.y1', TyAnimNum(AEl.Y1)), TyAnimProp('shape.x2', TyAnimNum(AEl.X2)),
      TyAnimProp('shape.y2', TyAnimNum(AEl.Y2))]);
end;

function TyAxisAnimKey(const AAxisKey, AAnid: string): string;
begin
  Result := AAxisKey + '/' + AAnid;
end;

end.
