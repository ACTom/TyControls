unit tyControls.AdvChart.Paint;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the paint list: what gets drawn, in what order, and which
  datum the pointer is over.

  ONE HIT-TEST PATH. Every chart element -- a bar, a line, a slice, a marker, a
  label background -- is added here, and the pointer question is answered by
  walking this list once. The old TTyChart kept paint and hit-test honest by
  having them call the same pure functions; that scales to three geometries.
  Here they share the same DATA (a TTyChartShape), so there is no second
  description that could drift, and there is exactly one place that decides what
  the pointer is over.

  ORDER. Sorted by (Z, Z2, insertion index), painted front-to-back in that order
  and hit-tested in REVERSE, so the topmost thing the eye sees is the thing the
  pointer gets. Z separates the layers a chart has (grid under series under
  markers under tooltip); Z2 orders within one of them; the insertion index makes
  the comparison TOTAL, which is what makes the sort stable without relying on
  the sort algorithm being stable.

  PURE: SysUtils, Math and the AdvChart units. Rendering lives in
  tyControls.AdvChart.Render, which is allowed to see the painter. That split is
  the point: ordering and hit-testing are where the defects are, and they are
  testable here without a graphics stack. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Shape;

type
  { $AARRGGBB, byte-identical to tyControls.Types' TTyColor. Declared again here
    rather than imported because that unit uses Graphics, and importing it would
    end this layer's independence from the LCL for the sake of a Cardinal. The
    render bridge casts. }
  TTyChartColor = type Cardinal;

  { A COLOUR THAT IS NOT ONE COLOUR.

    Upstream detects a gradient STRUCTURALLY -- by the presence of
    `colorStops` -- and never by the `type` field; `type` only chooses
    between the two shapes afterwards, and anything that is not exactly
    `'radial'`, a missing `type` included, draws LINEAR. }
  TTyChartGradKind = (cgkNone, cgkLinear, cgkRadial);

  TTyChartGradStop = record
    Offset: Double;
    Color: TTyChartColor;
  end;
  TTyChartGradStopArray = array of TTyChartGradStop;

  TTyChartGradient = record
    Kind: TTyChartGradKind;
    { LINEAR: (X,Y) to (X2,Y2), defaults 0,0 -> 1,0, which is LEFT TO RIGHT.
      Most of the gallery writes `x2: 0, y2: 1` and so never meets the
      default, which is exactly how a port comes to assume it is vertical.

      RADIAL: (X,Y) is the centre and R the radius, defaults 0.5/0.5/0.5.
      The inner radius is always nought and it is always a true circle. }
    X, Y, X2, Y2, R: Double;
    { False -- the default -- means the numbers are fractions of the
      element's OWN box. True means they are coordinates already. The field
      is spelled `global`; the `globalCoord` in the documentation is a
      constructor parameter name and does nothing in an option literal. }
    Global: Boolean;
    { In the order they were written. Upstream neither sorts, dedupes nor
      clamps them, and emits duplicate offsets itself. }
    Stops: TTyChartGradStopArray;
  end;

  TTyChartElementStyle = record
    HasFill: Boolean;
    FillColor: TTyChartColor;
    { <= 0 means no stroke at all, the same rule TTyPainter.StrokePath follows:
      a theme that set a width of 0 meant "off", not "hairline". }
    StrokeWidthLogical: Double;
    StrokeColor: TTyChartColor;
    { A GRADIENT INSTEAD OF THE FILL COLOUR, when the author wrote one.
      FillColor still holds a solid -- the gradient's first stop -- because
      a legend swatch and a tooltip dot need one colour and upstream's own
      rule for producing it is `colorStops[0].color`. }
    FillGradient: TTyChartGradient;
    StrokeGradient: TTyChartGradient;
    FillEvenOdd: Boolean;
    DashLogical: TTyDoubleArray;
    Alpha: Double;                    // 0..1; 1 = opaque
  end;

  { Which datum an element belongs to. Both -1 together means "none" -- one
    place decides that, so the two can never disagree. }
  TTyChartDatumRef = record
    SeriesIndex: Integer;
    { The row in the store's CURRENT VIEW -- the subscript Get(dim, index)
      wants, and the one a reader almost always means. }
    DataIndex: Integer;
    { The same row as it arrived, before any filter -- what SetCalculated
      addresses and what a callback reports.

      TWO FIELDS BECAUSE THERE ARE TWO ANSWERS, and one name was carrying
      both: cartesian marks put the VIEW index here and pie sectors the RAW
      one, so a reader taking DataIndex to the store was right on one series
      type and silently off by the dropped rows on the other. Nothing had
      noticed because the only row filtering in the control is the pie's.
      TTyChartCallbackParams has declared both fields since it was written. }
    RawDataIndex: Integer;
  end;

  { WORDS ON A MARK, and -- once the label pass has placed them -- everything
    needed to draw them.

    A MARK FILLS IN Text AND NOTHING ELSE. The label pass reads that, works
    out where the words go against the mark's own bounds, and emits a SECOND
    element with the rest filled in. So a caption with Text set and FontName
    empty is a REQUEST, and one with both is an ANSWER; the two are never the
    same element.

    Why the words are not a shape kind: AdvChart.Shape imports no measurer on
    purpose -- it is the pure hit-test layer and TyShapeBounds has to answer
    from the record alone. A text kind would ask it a question it cannot
    compute. The caption rides here instead, where resolved ink already is,
    and the entry the label pass emits carries a plain rect the shape layer
    understands completely. }
  TTyElementCaption = record
    Text: string;
    FontName: string;
    FontSizeLogical: Integer;
    FontWeight: Integer;
    { THE INK, and its own field rather than the style's FillColor -- a caption
      has a rectangle so the pointer can find it, and that rectangle must not
      be painted. Borrowing FillColor and leaving HasFill off would work and
      would mean two things by one name. }
    Colour: TTyChartColor;
    { DEVICE px: the point the words hang off, and WHICH OF THEIR OWN EDGES is
      pinned to it. Both are needed and they are different questions -- `top`
      puts the anchor above the mark AND pins the caption's bottom edge there,
      and that pairing is what turns a distance into a gap instead of an
      overlap. }
    X, Y: Double;
    AnchorH: TTyTextAnchorH;
    AnchorV: TTyTextAnchorV;
    RotationRad: Double;
    { A ROTATED CAPTION CANNOT BE TRUNCATED. The painter's rotated text entry
      takes an anchor rather than a rect, so it has nowhere to clip and no
      ellipsis; upstream truncates rotated labels and this does not. Stated
      here rather than left for a caller to discover. }
    Truncate: Boolean;
  end;

  TTyChartElement = record
    Shape: TTyChartShape;
    Style: TTyChartElementStyle;
    { Empty on everything that has nothing to say, which is almost every
      element in a chart. }
    Caption: TTyElementCaption;
    Z, Z2: Integer;
    { Painted, never hit. Grid lines, split areas and axis furniture are silent:
      without this a gridline drawn over a bar would swallow the hover the bar
      was meant to get. }
    Silent: Boolean;
    { How far outside the shape still counts, LOGICAL px. A 6 px scatter marker
      needs a forgiving target; a line series needs a whole ribbon. }
    HitSlopLogical: Double;
    Datum: TTyChartDatumRef;
  end;

  TTyPaintList = class
  private
    FItems: array of TTyChartElement;
    FCount: Integer;
    FOrder: array of Integer;
    FOrdered: Boolean;
    procedure EnsureOrder;
    function Less(A, B: Integer): Boolean;
    procedure MergeSortOrder;
  public
    constructor Create;
    procedure Clear;
    function Add(const AElement: TTyChartElement): Integer;
    { The element at its INSERTION index. }
    function Element(AIndex: Integer): TTyChartElement;
    { The insertion index of the AIndex-th element in PAINT order (back first). }
    function PaintOrder(AIndex: Integer): Integer;
    { Topmost non-silent element containing the point, or -1. }
    function HitTestElement(AX, AY: Double; APPI: Integer): Integer;
    { The same walk, reported as a datum. This and HitTestElement are ONE code
      path, so the element the caller highlights and the datum it reports can
      never be two different things. }
    function HitTest(AX, AY: Double; APPI: Integer): TTyChartDatumRef;
    property Count: Integer read FCount;
  end;

function TyChartNoDatum: TTyChartDatumRef;
function TyChartDatum(ASeries, AData: Integer): TTyChartDatumRef; overload;
{ When the two spaces disagree -- a pie, whose sectors skip the rows a
  negative value removed and whose layout therefore counts in neither. }
function TyChartDatum(ASeries, AData, ARaw: Integer): TTyChartDatumRef; overload;
function TyChartDatumValid(const ADatum: TTyChartDatumRef): Boolean;
{ A style with nothing switched on: no fill, no stroke, fully opaque. Callers
  turn on what they want rather than remembering to turn off what they do not. }
function TyChartStyle: TTyChartElementStyle;
{ An element carrying a shape, silent and datum-less until the caller says
  otherwise -- so a decoration that forgets to set Silent is at worst inert,
  never a thing that steals hovers from the data. }
function TyChartElement(const AShape: TTyChartShape): TTyChartElement;

{ The one colour a gradient degrades to where only one will do -- a legend
  swatch, a tooltip marker. Upstream's own rule: the FIRST stop, not an
  average and not a midpoint; transparent when it has no stops. }
function TyGradientSolid(const AGrad: TTyChartGradient): TTyChartColor;

{ The gradient's geometry in real coordinates, against the element's box.

  WHICH BOX: the ELEMENT's own, and nothing larger. Not the plot, not the
  series -- upstream takes `el.getBoundingRect()`, so every bar in a series
  ramps over its own rectangle and a two-stop gradient reads the same on all
  of them. A stacked segment likewise restarts per segment. }
procedure TyResolveGradient(const AGrad: TTyChartGradient;
  const ABox: TTyRectF; out AX1, AY1, AX2, AY2, AR: Double);

implementation

function TyChartNoDatum: TTyChartDatumRef;
begin
  Result.SeriesIndex := -1;
  Result.DataIndex := -1;
  Result.RawDataIndex := -1;
end;

function TyChartDatum(ASeries, AData: Integer): TTyChartDatumRef;
begin
  Result.SeriesIndex := ASeries;
  Result.DataIndex := AData;
  { THE SAME ROW IN BOTH SPACES, which is the truth for every builder that
    walks a store's view without the store having been filtered -- every
    cartesian series in the control. A builder whose two answers differ says
    so with the three-argument form; one that used this while they differed
    would be making a claim it had not checked. }
  Result.RawDataIndex := AData;
end;

function TyChartDatum(ASeries, AData, ARaw: Integer): TTyChartDatumRef;
begin
  Result.SeriesIndex := ASeries;
  Result.DataIndex := AData;
  Result.RawDataIndex := ARaw;
end;

function TyChartDatumValid(const ADatum: TTyChartDatumRef): Boolean;
begin
  { Both or neither, decided in ONE place. A half-valid datum is the defect
    TyChartHitValid exists to prevent in the old chart. }
  Result := (ADatum.SeriesIndex >= 0) and (ADatum.DataIndex >= 0);
end;

function TyChartStyle: TTyChartElementStyle;
begin
  Result := Default(TTyChartElementStyle);
  Result.HasFill := False;
  Result.StrokeWidthLogical := 0;
  Result.FillEvenOdd := False;
  Result.DashLogical := nil;
  Result.Alpha := 1;
end;

function TyChartElement(const AShape: TTyChartShape): TTyChartElement;
begin
  { Default() rather than FillChar: the record now carries five managed
    fields across three levels, and zeroing a record by bytes is only safe
    while every one of them happens to be nil already. It is, here -- FPC
    initialises a managed result before the body runs -- but the safety is
    incidental and the next field added would not know that. }
  Result := Default(TTyChartElement);
  Result.Shape := AShape;
  Result.Style := TyChartStyle;
  Result.Z := 0;
  Result.Z2 := 0;
  Result.Silent := True;
  Result.HitSlopLogical := 0;
  Result.Datum := TyChartNoDatum;
end;

{ ============================ TTyPaintList ============================ }

constructor TTyPaintList.Create;
begin
  inherited Create;
  FCount := 0;
  FOrdered := True;
end;

procedure TTyPaintList.Clear;
begin
  FItems := nil;
  FOrder := nil;
  FCount := 0;
  FOrdered := True;
end;

function TTyPaintList.Add(const AElement: TTyChartElement): Integer;
begin
  if FCount = Length(FItems) then
    SetLength(FItems, Max(16, FCount * 2));
  FItems[FCount] := AElement;
  Result := FCount;
  Inc(FCount);
  FOrdered := False;
end;

function TTyPaintList.Element(AIndex: Integer): TTyChartElement;
begin
  if (AIndex < 0) or (AIndex >= FCount) then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Datum := TyChartNoDatum;
    Exit;
  end;
  Result := FItems[AIndex];
end;

function TTyPaintList.Less(A, B: Integer): Boolean;
begin
  if FItems[A].Z <> FItems[B].Z then
    Exit(FItems[A].Z < FItems[B].Z);
  if FItems[A].Z2 <> FItems[B].Z2 then
    Exit(FItems[A].Z2 < FItems[B].Z2);
  { The insertion index makes the order TOTAL.

    Note honestly that it is REDUNDANT today: MergeSortOrder is stable (its merge
    prefers the left run on ties), so equal-z elements already keep their
    insertion order without this line. Mutation testing proved it -- replacing
    this with `False` leaves every test green, and no test could distinguish
    them, because the two produce identical output.

    It stays because the two guarantees protect different things. The sort's
    stability is a property of the sort; this is a property of the ORDER, and it
    is what keeps paint order from silently changing if the sort is ever swapped
    for a faster unstable one. What must not happen is someone reading the
    comment, believing this line is what pins the order, and deleting the merge
    sort's tie preference on that basis -- so: either alone is sufficient, both
    is deliberate, and neither is testable while the other stands. }
  Result := A < B;
end;

procedure TTyPaintList.MergeSortOrder;
var
  buf: array of Integer;

  procedure MergeRun(ALo, AMid, AHi: Integer);
  var
    i, j, k: Integer;
  begin
    i := ALo;
    j := AMid;
    for k := ALo to AHi - 1 do
    begin
      if (i < AMid) and ((j >= AHi) or (not Less(FOrder[j], FOrder[i]))) then
      begin
        buf[k] := FOrder[i];
        Inc(i);
      end
      else
      begin
        buf[k] := FOrder[j];
        Inc(j);
      end;
    end;
    for k := ALo to AHi - 1 do
      FOrder[k] := buf[k];
  end;

  procedure SortRun(ALo, AHi: Integer);
  var
    mid: Integer;
  begin
    if AHi - ALo < 2 then Exit;
    mid := (ALo + AHi) div 2;
    SortRun(ALo, mid);
    SortRun(mid, AHi);
    MergeRun(ALo, mid, AHi);
  end;

begin
  { Merge sort rather than quicksort: chart elements arrive very nearly in z
    order already, which is quicksort's quadratic case with a naive pivot. }
  SetLength(buf, FCount);
  SortRun(0, FCount);
end;

procedure TTyPaintList.EnsureOrder;
var
  i: Integer;
begin
  if FOrdered then Exit;
  SetLength(FOrder, FCount);
  for i := 0 to FCount - 1 do
    FOrder[i] := i;
  MergeSortOrder;
  FOrdered := True;
end;

function TTyPaintList.PaintOrder(AIndex: Integer): Integer;
begin
  EnsureOrder;
  if (AIndex < 0) or (AIndex >= FCount) then Exit(-1);
  Result := FOrder[AIndex];
end;

function TTyPaintList.HitTestElement(AX, AY: Double; APPI: Integer): Integer;
var
  i, idx: Integer;
  slop: Double;
begin
  Result := -1;
  EnsureOrder;
  { REVERSE paint order: the last thing drawn is the top thing seen, and it is
    what the pointer must get. Walking forwards would report whatever is under
    the pile. }
  for i := FCount - 1 downto 0 do
  begin
    idx := FOrder[i];
    if FItems[idx].Silent then Continue;
    if APPI > 0 then
      slop := FItems[idx].HitSlopLogical * APPI / 96
    else
      slop := FItems[idx].HitSlopLogical;
    if TyShapeContains(FItems[idx].Shape, AX, AY, slop) then
      Exit(idx);
  end;
end;

function TTyPaintList.HitTest(AX, AY: Double; APPI: Integer): TTyChartDatumRef;
var
  idx: Integer;
begin
  idx := HitTestElement(AX, AY, APPI);
  if idx < 0 then
    Result := TyChartNoDatum
  else
    Result := FItems[idx].Datum;
end;

function TyGradientSolid(const AGrad: TTyChartGradient): TTyChartColor;
begin
  if Length(AGrad.Stops) = 0 then Exit(0);
  Result := AGrad.Stops[0].Color;
end;

function SafeNum(AValue, ADefault: Double): Double;
begin
  if IsNan(AValue) or IsInfinite(AValue) then Exit(ADefault);
  Result := AValue;
end;

procedure TyResolveGradient(const AGrad: TTyChartGradient;
  const ABox: TTyRectF; out AX1, AY1, AX2, AY2, AR: Double);
var w, h: Double;
begin
  w := ABox.Right - ABox.Left;
  h := ABox.Bottom - ABox.Top;
  if AGrad.Kind = cgkRadial then
  begin
    AX1 := AGrad.X;
    AY1 := AGrad.Y;
    AR := AGrad.R;
    if not AGrad.Global then
    begin
      AX1 := AX1 * w + ABox.Left;
      AY1 := AY1 * h + ABox.Top;
      { THE RADIUS SCALES BY THE SMALLER SIDE, so a radial gradient is a
        circle on any box rather than an ellipse squeezed into it. }
      AR := AR * Min(w, h);
    end;
    { The sanity fallbacks run AFTER the multiply and are ABSOLUTE, so a
      degenerate box leaves a half-pixel dot rather than half a box. A
      NEGATIVE radius takes the same fallback. }
    AX1 := SafeNum(AX1, 0.5);
    AY1 := SafeNum(AY1, 0.5);
    if (AR < 0) or IsNan(AR) or IsInfinite(AR) then AR := 0.5;
    AX2 := AX1;
    AY2 := AY1;
    Exit;
  end;
  AX1 := AGrad.X;
  AY1 := AGrad.Y;
  AX2 := AGrad.X2;
  AY2 := AGrad.Y2;
  if not AGrad.Global then
  begin
    { EACH AXIS ON ITS OWN -- x by the width and y by the height. The
      anisotropy is the point: it is how `0,0 -> 0,1` is vertical whatever
      the box's shape, and Sankey exploits it deliberately. }
    AX1 := AX1 * w + ABox.Left;
    AX2 := AX2 * w + ABox.Left;
    AY1 := AY1 * h + ABox.Top;
    AY2 := AY2 * h + ABox.Top;
  end;
  AX1 := SafeNum(AX1, 0);
  AX2 := SafeNum(AX2, 1);
  AY1 := SafeNum(AY1, 0);
  AY2 := SafeNum(AY2, 0);
  AR := 0;
end;

end.
