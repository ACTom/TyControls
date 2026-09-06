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

  TTyChartElementStyle = record
    HasFill: Boolean;
    FillColor: TTyChartColor;
    { <= 0 means no stroke at all, the same rule TTyPainter.StrokePath follows:
      a theme that set a width of 0 meant "off", not "hairline". }
    StrokeWidthLogical: Double;
    StrokeColor: TTyChartColor;
    FillEvenOdd: Boolean;
    DashLogical: TTyDoubleArray;
    Alpha: Double;                    // 0..1; 1 = opaque
  end;

  { Which datum an element belongs to. Both -1 together means "none" -- one
    place decides that, so the two can never disagree. }
  TTyChartDatumRef = record
    SeriesIndex: Integer;
    DataIndex: Integer;
  end;

  TTyChartElement = record
    Shape: TTyChartShape;
    Style: TTyChartElementStyle;
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
function TyChartDatum(ASeries, AData: Integer): TTyChartDatumRef;
function TyChartDatumValid(const ADatum: TTyChartDatumRef): Boolean;
{ A style with nothing switched on: no fill, no stroke, fully opaque. Callers
  turn on what they want rather than remembering to turn off what they do not. }
function TyChartStyle: TTyChartElementStyle;
{ An element carrying a shape, silent and datum-less until the caller says
  otherwise -- so a decoration that forgets to set Silent is at worst inert,
  never a thing that steals hovers from the data. }
function TyChartElement(const AShape: TTyChartShape): TTyChartElement;

implementation

function TyChartNoDatum: TTyChartDatumRef;
begin
  Result.SeriesIndex := -1;
  Result.DataIndex := -1;
end;

function TyChartDatum(ASeries, AData: Integer): TTyChartDatumRef;
begin
  Result.SeriesIndex := ASeries;
  Result.DataIndex := AData;
end;

function TyChartDatumValid(const ADatum: TTyChartDatumRef): Boolean;
begin
  { Both or neither, decided in ONE place. A half-valid datum is the defect
    TyChartHitValid exists to prevent in the old chart. }
  Result := (ADatum.SeriesIndex >= 0) and (ADatum.DataIndex >= 0);
end;

function TyChartStyle: TTyChartElementStyle;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.HasFill := False;
  Result.StrokeWidthLogical := 0;
  Result.FillEvenOdd := False;
  Result.DashLogical := nil;
  Result.Alpha := 1;
end;

function TyChartElement(const AShape: TTyChartShape): TTyChartElement;
begin
  FillChar(Result, SizeOf(Result), 0);
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

end.
