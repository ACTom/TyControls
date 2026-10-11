unit tyControls.AdvChart.Large;
{$mode objfpc}{$H+}
{ LARGE MODE: one path for a whole series [Batch 117, C8].

  When a bar, scatter or candlestick series holds at least `largeThreshold`
  rows and `large` is on (a candlestick's is on by default), upstream stops
  making an element per datum. The layout writes the series into one typed
  array and the view draws it as ONE path per style: BarView's LargePath
  (a rect per row), LargeSymbolDraw's LargeSymbolPath (every symbol, or a
  fillRect per point under 4 px), CandlestickView's LargeBoxPath (one
  stroked path per sign, a line from low to high per row). This unit is the
  record of such a batch and the arithmetic upstream answers the pointer
  with; AdvChart.Marks fills it, AdvChart.Render traces it.

  THE NUMBERS ARE FLOAT32. The layouts store into createFloat32Array, so
  every point is rounded to a single before anything reads it -- the drawing,
  the bounding rect and the hit scan all see the rounded value. A bar's
  width is not: it lives on the element as a plain number.

  THE HIT TEST IS ARITHMETIC, and it is three different arithmetics:
    bar     -- zrender's own Path.contain (the bounding rect, then the
               winding over the rects; the scan below answers the same, see
               the oracle's R3) and the group's clip rect; the dataIndex is
               a FORWARD scan, the first rect containing the point, edges
               included (largePathFindDataIndex);
    symbol  -- the bounding rect of the points grown by the symbol size,
               then a TOP-DOWN scan (the last point wins) over boxes of
               max(size, 4) -- so a point inside the 4 px box but outside a
               3 px symbol's bounding rect is not hit; the soft clip that
               keeps a point from being DRAWN does not keep it from being
               hit;
    candle  -- a stroke test with no data at all: the element is hovered
               (a mouseout fires when the pointer leaves it) but carries no
               dataIndex, so no item tooltip and no chart event.
  A not-a-number anywhere in a bar's or a scatter's points makes the
  bounding rect not-a-number, and nothing in the series is ever hovered.

  PURE: SysUtils, Math, fpjson and AdvChart.Types. }
interface
uses
  SysUtils, Math, fpjson, tyControls.AdvChart.Types;

type
  TTyLargeKind = (lgkNone, lgkBar, lgkSymbol, lgkCandle);

  { One batch. Device px throughout. }
  TTyLargeGeom = record
    Kind: TTyLargeKind;
    { bar: [x, y, size] per row (size along the value axis, signed);
      symbol: [x, y] per row; candle: [sign, x, ylow, yhigh] per row, sign
      not-a-number where the row draws nothing. Float32 values. }
    Pts: TTyDoubleArray;
    { bar: largeDataIndices, the view row of each triple }
    Idx: TTyIntegerArray;
    { bar: 0 when the base axis is x (the rect's width is BarW), 1 when it
      is y; and the column's width }
    BaseDim: Integer;
    BarW: Double;
    { symbol: the series' size, its kind (Ord of the symbol unit's
      TTySymbolKind -- this unit sits under that one), the fillRect boost
      (a size under 4 px) and the hit box's floor (4 px) }
    SymW, SymH: Double;
    SymKind: Integer;
    Boost: Boolean;
    HitMin: Double;
    { symbol: the soft clip (getArea(0.1)) points outside are not drawn in }
    SoftOn: Boolean;
    Soft: TTyXYWH;
    { candle: the sign this path draws, and the width its stroke answers
      within -- max(lineWidth, strokeContainThreshold 5) }
    Sign: Integer;
    StrokeHit: Double;
    { bar, candle: the view group's clip path, which cuts the hover too }
    ClipOn: Boolean;
    Clip: TTyXYWH;
    { el.getBoundingRect(), worked out once by TyLargeSetBox }
    Box: TTyXYWH;
    { PROGRESSIVE [Batch 119]. symbol: the batch's startIndex -- the row its
      first point is (a dataIndex is the scan's index plus it) -- and the
      rows it holds so far: LargeSymbolDraw merges every chunk into the
      last batch while that holds under 2e4 numbers, so a batch grows a
      chunk at a time; 0 is every row (the zero value: a batch drawn at
      once). ChunkFirst is the chunk the batch starts with, ChunkEnds the
      rows it holds after each of its chunks. }
    Start: Integer;
    Shown: Integer;
    ChunkFirst: Integer;
    ChunkEnds: TTyIntegerArray;
  end;

{ The large series a type has: bar, scatter, candlestick; lgkNone for every
  other (a line has no large mode -- its points are always Float32, its view
  never batches). }
function TyLargeKindOfType(const AType: string): TTyLargeKind;

{ `large` and `largeThreshold` as the pipeline reads them
  (util/model.preparePipelineContext): `large` JavaScript-truthy, written or
  the type's default (a candlestick's true, a bar's and a scatter's false),
  and the count -- after the dataZoom filter -- at least the threshold
  (default 400 bar, 2000 scatter, 600 candlestick; a string threshold is
  compared as JavaScript compares it, a null is 0). }
function TyLargeIsOn(const AType: string; ALarge, AThreshold: TJSONData;
  ACount: Integer): Boolean;

{ Math.fround }
function TyLargeF32(AX: Double): Double;

{ The bounding rect zrender answers for the element, into AGeom.Box. }
procedure TyLargeSetBox(var AGeom: TTyLargeGeom);

{ largePathFindDataIndex: the first rect holding the point (its view row), or
  -1. }
function TyLargeBarScan(const AGeom: TTyLargeGeom; AX, AY: Double): Integer;
{ LargeSymbolPath.findDataIndex: the last box of max(size, 4) holding the
  point, or -1. }
function TyLargeSymbolScan(const AGeom: TTyLargeGeom; AX, AY: Double): Integer;
{ the candle path's containStroke }
function TyLargeStrokeHit(const AGeom: TTyLargeGeom; AX, AY: Double): Boolean;

{ Is the element under the point: its contain, and its clip. }
function TyLargeContains(const AGeom: TTyLargeGeom; AX, AY: Double): Boolean;
{ The view row the element's handler gives the pointer, -1 for none (a
  candle always; a bar in a gap the clip let through). }
function TyLargeIndexAt(const AGeom: TTyLargeGeom; AX, AY: Double): Integer;
{ The bounding rect as a rect (a not-a-number one is not valid). }
function TyLargeBounds(const AGeom: TTyLargeGeom): TTyRectF;
{ The rows the batch holds now: every row, or a growing symbol batch's
  Shown [Batch 119]. }
function TyLargeRows(const AGeom: TTyLargeGeom): Integer;

implementation

function TyLargeRows(const AGeom: TTyLargeGeom): Integer;
begin
  case AGeom.Kind of
    lgkBar: Result := Length(AGeom.Pts) div 3;
    lgkSymbol:
      begin
        Result := Length(AGeom.Pts) div 2;
        if (AGeom.Shown > 0) and (AGeom.Shown < Result) then Result := AGeom.Shown;
      end;
    lgkCandle: Result := Length(AGeom.Pts) div 4;
  else
    Result := 0;
  end;
end;

function TyLargeKindOfType(const AType: string): TTyLargeKind;
begin
  if AType = 'bar' then Result := lgkBar
  else if AType = 'scatter' then Result := lgkSymbol
  else if AType = 'candlestick' then Result := lgkCandle
  else Result := lgkNone;
end;

{ JavaScript's ToNumber for the few shapes a threshold takes }
function JsNum(AData: TJSONData; ADefault: Double): Double;
var s: string; v: Double; code: Integer;
begin
  if AData = nil then Exit(ADefault);
  case AData.JSONType of
    jtNull: Result := 0;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtNumber: Result := AData.AsFloat;
    jtString:
      begin
        s := Trim(AData.AsString);
        if s = '' then Exit(0);
        Val(s, v, code);
        if code = 0 then Result := v else Result := NaN;
      end;
  else
    Result := NaN;
  end;
end;

function JsTruthy(AData: TJSONData; ADefault: Boolean): Boolean;
begin
  if AData = nil then Exit(ADefault);
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (not IsNan(AData.AsFloat)) and (AData.AsFloat <> 0);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

function TyLargeIsOn(const AType: string; ALarge, AThreshold: TJSONData;
  ACount: Integer): Boolean;
var
  k: TTyLargeKind;
  th: Double;
begin
  Result := False;
  k := TyLargeKindOfType(AType);
  if k = lgkNone then Exit;
  if not JsTruthy(ALarge, k = lgkCandle) then Exit;
  case k of
    lgkBar: th := JsNum(AThreshold, 400);
    lgkSymbol: th := JsNum(AThreshold, 2000);
  else
    th := JsNum(AThreshold, 600);
  end;
  { a not-a-number threshold compares false }
  if IsNan(th) then Exit;
  Result := ACount >= th;
end;

function TyLargeF32(AX: Double): Double;
const
  { the largest single plus half a unit of its last place: the tie goes to
    the infinity }
  cOverflow: Double = 3.4028235677973366e38;
var s: Single;
begin
  if IsNan(AX) or IsInfinite(AX) then Exit(AX);
  if AX >= cOverflow then Exit(Infinity);
  if AX <= -cOverflow then Exit(NegInfinity);
  s := AX;
  Result := s;
end;

{ Math.min / Math.max: a not-a-number wins }
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

{ BoundingRect.contain: closed, false on a not-a-number }
{ JavaScript's a + b, where an infinity of each sign is NaN rather than a
  raise }
function JsAdd(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if IsInfinite(A) and IsInfinite(B) and (Sign(A) <> Sign(B)) then Exit(NaN);
  Result := A + B;
end;

function BoxHas(const ABox: TTyXYWH; AX, AY: Double): Boolean;
var r, b: Double;
begin
  if IsNan(ABox.X) or IsNan(ABox.Y) then Exit(False);
  r := JsAdd(ABox.X, ABox.W);
  b := JsAdd(ABox.Y, ABox.H);
  if IsNan(r) or IsNan(b) then Exit(False);
  Result := (AX >= ABox.X) and (AX <= r) and (AY >= ABox.Y) and (AY <= b);
end;

procedure TyLargeSetBox(var AGeom: TTyLargeGeom);
var
  i, n: Integer;
  x0, y0, x1, y1, rx, ry, w, h, a, b, c, d, lw: Double;
  any: Boolean;
begin
  AGeom.Box := Default(TTyXYWH);
  case AGeom.Kind of
    lgkBar:
      begin
        { PathProxy.getBoundingRect over the rects: from MAX_VALUE, a
          not-a-number poisoning the union }
        x0 := MaxDouble; y0 := MaxDouble; x1 := -MaxDouble; y1 := -MaxDouble;
        n := Length(AGeom.Pts) div 3;
        for i := 0 to n - 1 do
        begin
          rx := AGeom.Pts[i * 3];
          ry := AGeom.Pts[i * 3 + 1];
          if AGeom.BaseDim = 0 then
          begin
            w := AGeom.BarW;
            h := AGeom.Pts[i * 3 + 2];
          end
          else
          begin
            w := AGeom.Pts[i * 3 + 2];
            h := AGeom.BarW;
          end;
          x0 := JsMin(x0, JsMin(rx, JsAdd(rx, w)));
          y0 := JsMin(y0, JsMin(ry, JsAdd(ry, h)));
          x1 := JsMax(x1, JsMax(rx, JsAdd(rx, w)));
          y1 := JsMax(y1, JsMax(ry, JsAdd(ry, h)));
        end;
        if n = 0 then
        begin
          x0 := 0; y0 := 0; x1 := 0; y1 := 0;
        end;
        AGeom.Box.X := x0;
        AGeom.Box.Y := y0;
        AGeom.Box.W := JsAdd(x1, -x0);
        AGeom.Box.H := JsAdd(y1, -y0);
      end;
    lgkSymbol:
      begin
        { LargeSymbolPath.getBoundingRect: the points' extremes grown by the
          symbol's own size -- not the hit box's 4 px floor }
        a := Infinity; b := Infinity; c := NegInfinity; d := NegInfinity;
        n := TyLargeRows(AGeom);
        for i := 0 to n - 1 do
        begin
          a := JsMin(AGeom.Pts[i * 2], a);
          c := JsMax(AGeom.Pts[i * 2], c);
          b := JsMin(AGeom.Pts[i * 2 + 1], b);
          d := JsMax(AGeom.Pts[i * 2 + 1], d);
        end;
        AGeom.Box.X := JsAdd(a, -AGeom.SymW / 2);
        AGeom.Box.Y := JsAdd(b, -AGeom.SymH / 2);
        AGeom.Box.W := JsAdd(JsAdd(c, -a), AGeom.SymW);
        AGeom.Box.H := JsAdd(JsAdd(d, -b), AGeom.SymH);
      end;
    lgkCandle:
      begin
        { the moves and lines of this sign's rows, then grown by the stroke
          as Path.getBoundingRect grows a path without fill }
        x0 := MaxDouble; y0 := MaxDouble; x1 := -MaxDouble; y1 := -MaxDouble;
        any := False;
        n := Length(AGeom.Pts) div 4;
        for i := 0 to n - 1 do
        begin
          if IsNan(AGeom.Pts[i * 4]) or (AGeom.Pts[i * 4] <> AGeom.Sign) then Continue;
          x0 := JsMin(x0, AGeom.Pts[i * 4 + 1]);
          x1 := JsMax(x1, AGeom.Pts[i * 4 + 1]);
          y0 := JsMin(y0, JsMin(AGeom.Pts[i * 4 + 2], AGeom.Pts[i * 4 + 3]));
          y1 := JsMax(y1, JsMax(AGeom.Pts[i * 4 + 2], AGeom.Pts[i * 4 + 3]));
          any := True;
        end;
        if not any then Exit;
        lw := AGeom.StrokeHit;
        AGeom.Box.X := JsAdd(x0, -lw / 2);
        AGeom.Box.Y := JsAdd(y0, -lw / 2);
        AGeom.Box.W := JsAdd(JsAdd(x1, -x0), lw);
        AGeom.Box.H := JsAdd(JsAdd(y1, -y0), lw);
      end;
  end;
end;

function TyLargeBarScan(const AGeom: TTyLargeGeom; AX, AY: Double): Integer;
var
  i, n: Integer;
  sx, sy, w, h, v: Double;
begin
  Result := -1;
  n := Length(AGeom.Pts) div 3;
  for i := 0 to n - 1 do
  begin
    v := AGeom.Pts[i * 3 + 2];
    if AGeom.BaseDim = 0 then
    begin
      sx := AGeom.Pts[i * 3];
      w := AGeom.BarW;
      sy := AGeom.Pts[i * 3 + 1];
      h := v;
      { a negative size flips the start: comparisons with not-a-number are
        false, as JavaScript's are }
      if (not IsNan(h)) and (h < 0) then
      begin
        sy := sy + h;
        h := -h;
      end;
    end
    else
    begin
      sy := AGeom.Pts[i * 3 + 1];
      h := AGeom.BarW;
      sx := AGeom.Pts[i * 3];
      w := v;
      if (not IsNan(w)) and (w < 0) then
      begin
        sx := sx + w;
        w := -w;
      end;
    end;
    if IsNan(sx) or IsNan(sy) or IsNan(w) or IsNan(h) then Continue;
    if (AX >= sx) and (AX <= JsAdd(sx, w)) and (AY >= sy) and (AY <= JsAdd(sy, h)) then
    begin
      if i <= High(AGeom.Idx) then Exit(AGeom.Idx[i]);
      Exit(i);
    end;
  end;
end;

function TyLargeSymbolScan(const AGeom: TTyLargeGeom; AX, AY: Double): Integer;
var
  idx: Integer;
  w, h, x0, y0: Double;
begin
  Result := -1;
  w := Max(AGeom.SymW, AGeom.HitMin);
  h := Max(AGeom.SymH, AGeom.HitMin);
  for idx := TyLargeRows(AGeom) - 1 downto 0 do
  begin
    x0 := AGeom.Pts[idx * 2] - w / 2;
    y0 := AGeom.Pts[idx * 2 + 1] - h / 2;
    if IsNan(x0) or IsNan(y0) or IsInfinite(x0) or IsInfinite(y0) then Continue;
    if (AX >= x0) and (AY >= y0) and (AX <= x0 + w) and (AY <= y0 + h) then
      Exit(idx);
  end;
end;

{ zrender's line.containStroke for one segment }
function SegmentStroke(X0, Y0, X1, Y1, L, AX, AY: Double): Boolean;
var a, b, t, s: Double;
begin
  Result := False;
  if L = 0 then Exit;
  if IsNan(X0) or IsNan(Y0) or IsNan(X1) or IsNan(Y1) then Exit;
  if ((AY > Y0 + L) and (AY > Y1 + L)) or ((AY < Y0 - L) and (AY < Y1 - L))
    or ((AX > X0 + L) and (AX > X1 + L)) or ((AX < X0 - L) and (AX < X1 - L)) then
    Exit;
  if X0 = X1 then Exit(Abs(AX - X0) <= L / 2);
  a := (Y0 - Y1) / (X0 - X1);
  b := (X0 * Y1 - X1 * Y0) / (X0 - X1);
  t := a * AX - AY + b;
  s := t * t / (a * a + 1);
  Result := s <= L / 2 * L / 2;
end;

function TyLargeStrokeHit(const AGeom: TTyLargeGeom; AX, AY: Double): Boolean;
var i, n: Integer; x: Double;
begin
  Result := False;
  n := Length(AGeom.Pts) div 4;
  for i := 0 to n - 1 do
  begin
    if IsNan(AGeom.Pts[i * 4]) or (AGeom.Pts[i * 4] <> AGeom.Sign) then Continue;
    x := AGeom.Pts[i * 4 + 1];
    if SegmentStroke(x, AGeom.Pts[i * 4 + 2], x, AGeom.Pts[i * 4 + 3],
      AGeom.StrokeHit, AX, AY) then Exit(True);
  end;
end;

function TyLargeContains(const AGeom: TTyLargeGeom; AX, AY: Double): Boolean;
begin
  Result := False;
  if IsNan(AX) or IsNan(AY) then Exit;
  if not BoxHas(AGeom.Box, AX, AY) then Exit;
  case AGeom.Kind of
    lgkBar: Result := TyLargeBarScan(AGeom, AX, AY) >= 0;
    lgkSymbol: Result := TyLargeSymbolScan(AGeom, AX, AY) >= 0;
    lgkCandle: Result := TyLargeStrokeHit(AGeom, AX, AY);
  end;
  { zrender's isHover asks the clip path after the element: the view
    group's clip rect cuts the hover where it cuts the ink }
  if Result and AGeom.ClipOn then
    Result := BoxHas(AGeom.Clip, AX, AY);
end;

function TyLargeIndexAt(const AGeom: TTyLargeGeom; AX, AY: Double): Integer;
begin
  Result := -1;
  if IsNan(AX) or IsNan(AY) then Exit;
  case AGeom.Kind of
    lgkBar: Result := TyLargeBarScan(AGeom, AX, AY);
    lgkSymbol:
      if BoxHas(AGeom.Box, AX, AY) then
      begin
        Result := TyLargeSymbolScan(AGeom, AX, AY);
        { `dataIndex + (symbolEl.startIndex || 0)` [Batch 119] }
        if Result >= 0 then Result := Result + AGeom.Start;
      end;
  end;
end;

function TyLargeBounds(const AGeom: TTyLargeGeom): TTyRectF;
begin
  Result.Left := AGeom.Box.X;
  Result.Top := AGeom.Box.Y;
  Result.Right := JsAdd(AGeom.Box.X, AGeom.Box.W);
  Result.Bottom := JsAdd(AGeom.Box.Y, AGeom.Box.H);
end;

end.
