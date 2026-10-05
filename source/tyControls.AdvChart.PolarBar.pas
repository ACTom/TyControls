unit tyControls.AdvChart.PolarBar;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- the bars on a polar. [Batch 113, C4]

  UPSTREAM'S layout/barPolar.ts (calcRadialBar, layoutPerAxisPerSeries), the
  polar half of chart/bar/BarView.ts (the clip, the element creator, the
  corners of updateStyle, the background, isZeroOnPolar), zrender's
  roundSector buildPath and util/shape/sausage.ts, and label/sectorLabel.ts,
  transcribed.

  A RADIAL BAR stands on a category (or value) ANGLE axis and grows along the
  radius; a TANGENTIAL bar stands on the radius axis and sweeps the angle.
  The layout is upstream's record: the centre, r0 and r in px, and the two
  angles in radians CLOCKWISE on the screen (the degrees negated), with
  `clockwise` saying which way round the sector is drawn -- the end angle
  decides the direction, as a cartesian bar's end decides its own.

  NOT THE GRID'S SOLVER. calcRadialBar is its own: the band at least 1, a
  category gap of 20% and a bar gap of 30% by default (the grid's are a
  computed gap and 10%), the last series' gaps win, no barMinWidth. The
  stack is its own too: lastStackCoords keyed by the base VALUE, per sign,
  holding the end coordinate the last bar reached -- barMinHeight included,
  which is why upstream does not read the stack's result column here.

  THE PATHS ARE ZRENDER'S, number for number: a label at a built-in position
  ('inside', 'top' ...) hangs off the path's bounding rect, and that rect is
  the arcs' as PathProxy.getBoundingRect takes them. The painter draws the
  shape record's sector (AdvChart.Shape), which covers the same pixels.

  PURE: SysUtils, Math, fpjson and the AdvChart units. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
  tyControls.AdvChart.Data, tyControls.AdvChart.Series,
  tyControls.AdvChart.Polar, tyControls.AdvChart.ZrPath,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Shape;

type
  { One sector as upstream's layout holds it: radians clockwise on screen. }
  TTyPolarSector = record
    CX, CY, R0, R, SA, EA: Double;
    CW: Boolean;
  end;
  TTyPolarSectorArray = array of TTyPolarSector;

  { `itemStyle.borderRadius` (or backgroundStyle's) as written: a number, a
    string, or a list of them; each a number, or a percentage of the ring's
    radius (getSectorCornerRadius) }
  TTyPolarCornerSpec = record
    Given: Boolean;
    IsArray: Boolean;
    Count: Integer;
    Vals: array[0..3] of Double;
    Pct: array[0..3] of Boolean;
  end;
  TTyPolarCornerSpecArray = array of TTyPolarCornerSpec;

  { WHAT A BAR'S LABEL ASKS OF ITS SECTOR, per view row: the position word
    (item over series; '' unwritten, 'array' for the array form), whether
    `rotate` is a number and which }
  TTyPolarLabelAsk = record
    Word: string;
    IsArray: Boolean;
    HasRotate: Boolean;
    Rotate: Double;
  end;
  TTyPolarLabelAskArray = array of TTyPolarLabelAsk;

  { ONE POLAR BAR SERIES, solved: Rows by VIEW row (Valid False where the
    row has no element -- a value that is not a number, a layout that is not
    finite), the options the view reads, the area the clip cuts to. }
  TTyPolarBarLayout = record
    Solved: Boolean;
    { the base axis is the angle (upstream's isRadial) }
    IsRadial: Boolean;
    RoundCap: Boolean;
    Clip: Boolean;
    ShowBackground: Boolean;
    BgCorner: TTyPolarCornerSpec;
    { getArea: the radius extent, ascending }
    AreaCX, AreaCY, AreaR0, AreaR: Double;
    BandWidth, ColumnOffset, ColumnWidth: Double;
    Rows: TTyPolarSectorArray;
    Valid: TTyBoolArray;
    Corners: TTyPolarCornerSpecArray;
    Labels: TTyPolarLabelAskArray;
  end;
  TTyPolarBarLayoutArray = array of TTyPolarBarLayout;

{ barLayoutPolar over every polar axis a bar series stands on: one entry
  per binding slot, Solved only for a bar on a polar. }
function TySolvePolarBars(AOption: TTyChartOption;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  const APolars: TTyPolarArray): TTyPolarBarLayoutArray;

{ ---- the view's arithmetic ---- }

{ isValidLayout.polar: cx, cy, r and both angles finite }
function TyPolarSectorValid(const S: TTyPolarSector): Boolean;
{ clip.polar: r and r0 into the area's, in the bar's own order; True when
  nothing is left (the element is then ignored) }
function TyPolarBarClip(AAreaR0, AAreaR: Double; var S: TTyPolarSector): Boolean;
{ isZeroOnPolar: the two angles equal }
function TyPolarZero(const S: TTyPolarSector): Boolean;
{ createBackgroundShape on a polar }
function TyPolarBarBackground(const L: TTyPolarBarLayout;
  const S: TTyPolarSector): TTyPolarSector;
{ getSectorCornerRadius(itemStyle, shape, zeroIfNull): the list zrender's
  cornerRadius holds -- empty for none -- each percentage of
  `Math.abs(shape.r || 0 - shape.r0 || 0)`, which reads |r| when r is a
  number other than nought (the operators bind that way upstream) }
function TyPolarCornerList(const ASpec: TTyPolarCornerSpec;
  const S: TTyPolarSector): TTyDoubleArray;
{ the background's: backgroundStyle.borderRadius || 0, never a percentage }
function TyPolarCornerRaw(const ASpec: TTyPolarCornerSpec): TTyDoubleArray;
{ roundSector's normalizeCornerRadius: four, from one to four given }
function TyPolarCornerFour(const AList: TTyDoubleArray; out A: TTyCornerRadii): Boolean;

{ THE SHAPE RECORD of a polar sector, for the painter and the hit test:
  the sweep zrender's arc takes from SA to EA in the sector's direction
  (normalizeArcAngles), turned to run forward, the corners roundSector
  reads out of ACorners -- the start's and the end's swapped where the
  direction was turned -- and the Sausage flag }
function TyPolarSectorShape(const S: TTyPolarSector; const ACorners: TTyDoubleArray;
  ASausage: Boolean): TTyChartShape;

{ zrender's paths, PathProxy's data: Sector (roundSector.buildPath) and
  Sausage }
function TyZrSectorPath(const S: TTyPolarSector; const ACorners: TTyDoubleArray): TTyZrPath;
function TyZrSausagePath(const S: TTyPolarSector): TTyZrPath;

type
  { label/sectorLabel.ts' positions, after the bar's mapping }
  TTySectorTextPos = (stpBuiltin, stpStartArc, stpInsideStartArc, stpStartAngle,
    stpInsideStartAngle, stpMiddle, stpEndArc, stpInsideEndArc, stpEndAngle,
    stpInsideEndAngle);

{ createPolarPositionMapping and the calculator's switch: a word the sector
  positions know, or stpBuiltin (calculateTextPosition on the rect) }
function TySectorTextPosOf(const AWord: string; AIsRadial: Boolean): TTySectorTextPos;
{ BarView's labelPositionOutside on a polar: past the end the bar grows to }
function TyPolarOutsideWord(const S: TTyPolarSector; AIsRadial: Boolean): string;
{ createSectorCalculateTextPosition: the anchor and the alignment it implies }
procedure TySectorLabelAnchor(const S: TTyPolarSector; APos: TTySectorTextPos;
  ADistance: Double; AIsRoundCap: Boolean; out AX, AY: Double;
  out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);
{ setSectorTextRotation: a numeric rotate as it stands (it is NOT turned
  into radians upstream), the array form 0, else the turn the anchor angle
  gives -- a middle label flipped to read }
function TySectorLabelRotation(const S: TTyPolarSector; const AAsk: TTyPolarLabelAsk;
  AWord: string; AIsRadial: Boolean): Double;

implementation

uses tyControls.AdvChart.JsMath;

const
  cMinBand = 1.0;

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if (AData <> nil) and (AData is TJSONObject) then Result := TJSONObject(AData)
  else Result := nil;
end;

{ Math.min / Math.max of two: a not-a-number wins }
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


function FindIn(ANode: TJSONObject; const AKey: string): TJSONData;
begin
  Result := nil;
  if ANode <> nil then Result := ANode.Find(AKey);
end;

{ numberUtil.parsePercent (parsePositionOption) of an option value }
function PctOf(D: TJSONData; ABase: Double): Double;
var s: string;
begin
  if (D = nil) or (D.JSONType = jtNull) then Exit(NaN);
  case D.JSONType of
    jtNumber: Result := D.AsFloat;
    jtBoolean: if D.AsBoolean then Result := 1 else Result := 0;
    jtString:
      begin
        s := D.AsString;
        if s = 'center' then s := '50%'
        else if s = 'middle' then s := '50%'
        else if (s = 'left') or (s = 'top') then s := '0%'
        else if (s = 'right') or (s = 'bottom') then s := '100%';
        if (Length(Trim(s)) > 0) and (Trim(s)[Length(Trim(s))] = '%') then
          Result := TyJsParseFloat(s) / 100 * ABase
        else
          Result := TyJsParseFloat(s);
      end;
  else
    Result := NaN;
  end;
end;

function Truthy(V: Double): Boolean;
begin
  Result := (not IsNan(V)) and (V <> 0);
end;

{ a JS truthy option value }
function JsTruthy(D: TJSONData): Boolean;
begin
  if D = nil then Exit(False);
  case D.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := D.AsBoolean;
    jtNumber: Result := (D.AsFloat <> 0) and not IsNan(D.AsFloat);
    jtString: Result := D.AsString <> '';
  else
    Result := True;
  end;
end;

{ one corner value as written }
procedure CornerItem(D: TJSONData; var ASpec: TTyPolarCornerSpec; AK: Integer);
var s: string;
begin
  ASpec.Vals[AK] := NaN;
  ASpec.Pct[AK] := False;
  if D = nil then Exit;
  case D.JSONType of
    jtNumber: ASpec.Vals[AK] := D.AsFloat;
    jtString:
      begin
        s := D.AsString;
        { zrender's contain/text parsePercent: a '%' anywhere }
        ASpec.Pct[AK] := Pos('%', s) > 0;
        ASpec.Vals[AK] := TyJsParseFloat(s);
      end;
    jtBoolean: if D.AsBoolean then ASpec.Vals[AK] := 1 else ASpec.Vals[AK] := 0;
  end;
end;

function CornerSpecOf(D: TJSONData): TTyPolarCornerSpec;
var k: Integer;
begin
  Result := Default(TTyPolarCornerSpec);
  if (D = nil) or (D.JSONType = jtNull) then Exit;
  Result.Given := True;
  if D.JSONType = jtArray then
  begin
    Result.IsArray := True;
    Result.Count := Math.Min(4, D.Count);
    for k := 0 to Result.Count - 1 do CornerItem(D.Items[k], Result, k);
  end
  else
  begin
    Result.Count := 1;
    CornerItem(D, Result, 0);
  end;
end;

function StyleKey(ANode: TJSONObject; const ABlock, AKey: string): TJSONData;
var b: TJSONObject;
begin
  Result := nil;
  b := ObjOf(FindIn(ANode, ABlock));
  if b <> nil then Result := b.Find(AKey);
end;

{ ==================== the solve ==================== }

type
  TStackCol = record
    Id: string;
    Width, MaxWidth: Double;
  end;
  TLastCoord = record
    Base: Double;
    P, N: Double;
  end;
  TLastCoords = record
    Id: string;
    Items: array of TLastCoord;
  end;

function SeriesNode(AOption: TTyChartOption; ASlot: Integer): TJSONObject;
begin
  Result := ObjOf(AOption.ComponentAt('series', ASlot));
end;

function StackIdOf(ANode: TJSONObject; ASeriesIndex: Integer): string;
var d: TJSONData;
begin
  d := FindIn(ANode, 'stack');
  Result := '';
  if (d <> nil) and JsTruthy(d) then
  begin
    if d.JSONType in [jtString, jtNumber] then Result := d.AsString
    else Result := 'true';
  end;
  if Result = '' then Result := '__ec_stack_' + IntToStr(ASeriesIndex);
end;

{ the item's own JSON object at a raw index, nil where it has none }
function ItemOf(ANode: TJSONObject; ARaw: Integer): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  d := FindIn(ANode, 'data');
  if (d = nil) or (d.JSONType <> jtArray) then Exit;
  if (ARaw < 0) or (ARaw >= d.Count) then Exit;
  Result := ObjOf(d.Items[ARaw]);
end;

function TySolvePolarBars(AOption: TTyChartOption;
  const ABindings: TTySeriesBindingArray; const AStores: array of TTyDataStore;
  const AStacks: TTySeriesStackArray; AIndex: TTyAxisSeriesIndex;
  const APolars: TTyPolarArray): TTyPolarBarLayoutArray;
var
  key: string;
  p, a: Integer;
  answer: TTyPolarBarLayoutArray;
  mask: TFPUExceptionMask;

  procedure DoAxis(APolar: TTyPolar; AAxis: TTyAxis);
  var
    onIt: TTyIntegerArray;
    k, m, si, autoCount, n, r, rawIx, colV, colB, li, j: Integer;
    cols: array of TStackCol;
    offsets, widths: array of Double;
    slotCol: array of Integer;
    node, item: TJSONObject;
    band, pxSpan, remained, catGap, gapPct, autoWidth, mw, widthSum, offset,
      e0, e1, gap, span, bw, minH, minA, vStart, value, baseValue, baseCoord,
      sp, ang, rad, sa, ea, r0, r1: Double;
    lastW: Double;
    hasLast, stacked, clampLayout, sgnP: Boolean;
    gapOpt, catGapOpt: TJSONData;
    other: TTyAxis;
    lin: TTyRange;
    last: array of TLastCoords;
    st: TTyDataStore;
    sec: TTyPolarSector;
    d: TJSONData;

    function LastFor(const AId: string): Integer;
    var q: Integer;
    begin
      for q := 0 to High(last) do
        if last[q].Id = AId then Exit(q);
      Result := Length(last);
      SetLength(last, Result + 1);
      last[Result].Id := AId;
      last[Result].Items := nil;
    end;

    { lastStackCoords[stackId][baseValue]: a JS property, so 0 and -0 are one
      key and every NaN another one }
    function CoordFor(AStack: Integer; ABase: Double): Integer;
    var q: Integer;
    begin
      for q := 0 to High(last[AStack].Items) do
        if (last[AStack].Items[q].Base = ABase)
          or (IsNan(last[AStack].Items[q].Base) and IsNan(ABase)) then Exit(q);
      Result := -1;
    end;

  begin
    onIt := AIndex.SeriesOnAxisOfKey(AAxis, key);
    if Length(onIt) = 0 then Exit;
    other := APolar.OtherAxis(AAxis);
    { calcBandWidth(axis, {fromStat, min: 1}).w }
    APolar.AxisExtent(AAxis, e0, e1);
    pxSpan := Abs(e1 - e0);
    lin := AAxis.Scale.LinearExtent2(sekMapping);
    span := lin.Stop - lin.Start;
    if IsNan(span) or IsInfinite(span) then span := NaN;
    if AAxis.Scale is TTyOrdinalScale then
    begin
      if AAxis.OnBand then bw := span + 1 else bw := span;
      if bw = 0 then bw := 1;
      band := pxSpan / bw;
    end
    else
    begin
      gap := TyLiPosMinGap(AStores, onIt, AAxis);
      band := NaN;
      if (not IsNan(span)) and (span > 0) and (gap > 0) then
        band := pxSpan / span * gap
      else if gap = cTyMinGapSingle then
        band := pxSpan * 0.8;
    end;
    { isNullableNumberFinite(w) ? max(min, w) : min }
    if IsNan(band) or IsInfinite(band) then band := cMinBand
    else band := JMax(cMinBand, band);

    { calcRadialBar }
    remained := band;
    autoCount := 0;
    gapOpt := nil;
    catGapOpt := nil;
    cols := nil;
    SetLength(slotCol, Length(onIt));
    for k := 0 to High(onIt) do
    begin
      si := onIt[k];
      node := SeriesNode(AOption, ABindings[si].SeriesIndex);
      m := 0;
      while (m <= High(cols)) and (cols[m].Id <> StackIdOf(node, ABindings[si].SeriesIndex)) do Inc(m);
      if m > High(cols) then
      begin
        Inc(autoCount);
        SetLength(cols, m + 1);
        cols[m].Id := StackIdOf(node, ABindings[si].SeriesIndex);
        cols[m].Width := 0;
        cols[m].MaxWidth := 0;
      end;
      slotCol[k] := m;
      bw := PctOf(FindIn(node, 'barWidth'), band);
      mw := PctOf(FindIn(node, 'barMaxWidth'), band);
      if Truthy(bw) and not Truthy(cols[m].Width) then
      begin
        bw := JMin(remained, bw);
        cols[m].Width := bw;
        remained := remained - bw;
      end;
      if Truthy(mw) then cols[m].MaxWidth := mw;
      d := FindIn(node, 'barGap');
      if (d <> nil) and (d.JSONType <> jtNull) then gapOpt := d;
      d := FindIn(node, 'barCategoryGap');
      if (d <> nil) and (d.JSONType <> jtNull) then catGapOpt := d;
    end;
    if catGapOpt = nil then catGap := 0.2 * band
    else catGap := PctOf(catGapOpt, band);
    if gapOpt = nil then gapPct := 0.3
    else gapPct := PctOf(gapOpt, 1);
    autoWidth := JMax((remained - catGap) / (autoCount + (autoCount - 1) * gapPct), 0);
    for m := 0 to High(cols) do
    begin
      mw := cols[m].MaxWidth;
      if Truthy(mw) and (mw < autoWidth) then
      begin
        mw := JMin(mw, remained);
        if Truthy(cols[m].Width) then mw := JMin(mw, cols[m].Width);
        remained := remained - mw;
        cols[m].Width := mw;
        Dec(autoCount);
      end;
    end;
    autoWidth := JMax((remained - catGap) / (autoCount + (autoCount - 1) * gapPct), 0);
    widthSum := 0;
    hasLast := False;
    lastW := 0;
    for m := 0 to High(cols) do
    begin
      if not Truthy(cols[m].Width) then cols[m].Width := autoWidth;
      hasLast := True;
      lastW := cols[m].Width;
      widthSum := widthSum + cols[m].Width * (1 + gapPct);
    end;
    if hasLast then widthSum := widthSum - lastW * gapPct;
    offset := -widthSum / 2;
    SetLength(offsets, Length(cols));
    SetLength(widths, Length(cols));
    for m := 0 to High(cols) do
    begin
      offsets[m] := offset;
      widths[m] := cols[m].Width;
      offset := offset + cols[m].Width * (1 + gapPct);
    end;

    { layoutPerAxisPerSeries, the series in order }
    last := nil;
    for k := 0 to High(onIt) do
    begin
      si := onIt[k];
      if (si > High(AStores)) or (AStores[si] = nil) then Continue;
      st := AStores[si];
      node := SeriesNode(AOption, ABindings[si].SeriesIndex);
      m := slotCol[k];
      li := LastFor(cols[m].Id);
      answer[si].Solved := True;
      answer[si].IsRadial := AAxis = APolar.AngleAxis;
      answer[si].RoundCap := JsTruthy(FindIn(node, 'roundCap'));
      d := FindIn(node, 'clip');
      answer[si].Clip := (d = nil) or (d.JSONType = jtNull) or JsTruthy(d);
      answer[si].ShowBackground := JsTruthy(FindIn(node, 'showBackground'));
      { backgroundStyle.borderRadius || 0 }
      d := StyleKey(node, 'backgroundStyle', 'borderRadius');
      if JsTruthy(d) then answer[si].BgCorner := CornerSpecOf(d)
      else answer[si].BgCorner := Default(TTyPolarCornerSpec);
      answer[si].AreaCX := APolar.CX;
      answer[si].AreaCY := APolar.CY;
      APolar.AxisExtent(APolar.RadiusAxis, r0, r1);
      answer[si].AreaR0 := Math.Min(r0, r1);
      answer[si].AreaR := Math.Max(r0, r1);
      if IsNan(r0) or IsNan(r1) then
      begin
        answer[si].AreaR0 := NaN;
        answer[si].AreaR := NaN;
      end;
      answer[si].BandWidth := band;
      answer[si].ColumnOffset := offsets[m];
      answer[si].ColumnWidth := widths[m];

      { `get('barMinHeight') || 0` }
      minH := PctOf(FindIn(node, 'barMinHeight'), 0);
      if not Truthy(minH) then minH := 0;
      minA := PctOf(FindIn(node, 'barMinAngle'), 0);
      if not Truthy(minA) then minA := 0;
      colV := st.DimIndexOf(other.Dim);
      colB := st.DimIndexOf(AAxis.Dim);
      stacked := (si <= High(AStacks)) and AStacks[si].Stacked;
      clampLayout := (AAxis.Dim <> TyPolarRadiusDim) or not answer[si].RoundCap;
      vStart := other.DataToCoord(TyValueAxisStart(other));
      n := st.Count;
      SetLength(answer[si].Rows, n);
      SetLength(answer[si].Valid, n);
      SetLength(answer[si].Corners, n);
      SetLength(answer[si].Labels, n);
      for r := 0 to n - 1 do
      begin
        if colV >= 0 then value := st.Get(colV, r) else value := NaN;
        if colB >= 0 then baseValue := st.Get(colB, r) else baseValue := NaN;
        sgnP := value >= 0;
        baseCoord := vStart;
        if stacked then
        begin
          j := CoordFor(li, baseValue);
          if j < 0 then
          begin
            j := Length(last[li].Items);
            SetLength(last[li].Items, j + 1);
            last[li].Items[j].Base := baseValue;
            last[li].Items[j].P := vStart;
            last[li].Items[j].N := vStart;
          end;
          if sgnP then baseCoord := last[li].Items[j].P
          else baseCoord := last[li].Items[j].N;
        end
        else
          j := -1;
        if other.Dim = TyPolarRadiusDim then
        begin
          { radial sector }
          sp := other.DataToCoord(value) - vStart;
          ang := AAxis.DataToCoord(baseValue);
          if Abs(sp) < minH then
            if sp < 0 then sp := -1 * minH else sp := 1 * minH;
          sec.R0 := baseCoord;
          sec.R := baseCoord + sp;
          sa := ang - answer[si].ColumnOffset;
          ea := sa - answer[si].ColumnWidth;
          if stacked then
            if sgnP then last[li].Items[j].P := sec.R else last[li].Items[j].N := sec.R;
        end
        else
        begin
          { tangential sector }
          sp := other.DataToCoord(value, clampLayout) - vStart;
          rad := AAxis.DataToCoord(baseValue);
          if Abs(sp) < minA then
            if sp < 0 then sp := -1 * minA else sp := 1 * minA;
          sec.R0 := rad + answer[si].ColumnOffset;
          sec.R := sec.R0 + answer[si].ColumnWidth;
          sa := baseCoord;
          ea := baseCoord + sp;
          if stacked then
            if sgnP then last[li].Items[j].P := ea else last[li].Items[j].N := ea;
        end;
        sec.CX := APolar.CX;
        sec.CY := APolar.CY;
        sec.SA := -sa * Pi / 180;
        sec.EA := -ea * Pi / 180;
        sec.CW := sa >= ea;
        answer[si].Rows[r] := sec;
        { data.hasValue (every dimension a number) and isValidLayout }
        answer[si].Valid[r] := not (IsNan(value) or IsNan(baseValue))
          and TyPolarSectorValid(sec);
        { the item's own itemStyle.borderRadius and label over the series' }
        rawIx := st.GetRawIndex(r);
        item := ItemOf(node, rawIx);
        d := StyleKey(item, 'itemStyle', 'borderRadius');
        if (d = nil) or (d.JSONType = jtNull) then d := StyleKey(node, 'itemStyle', 'borderRadius');
        answer[si].Corners[r] := CornerSpecOf(d);
        answer[si].Labels[r] := Default(TTyPolarLabelAsk);
        d := StyleKey(item, 'label', 'position');
        if (d = nil) or (d.JSONType = jtNull) then d := StyleKey(node, 'label', 'position');
        if d <> nil then
        begin
          if d.JSONType = jtArray then
          begin
            answer[si].Labels[r].IsArray := True;
            answer[si].Labels[r].Word := 'array';
          end
          else if d.JSONType = jtString then
            answer[si].Labels[r].Word := d.AsString;
        end;
        d := StyleKey(item, 'label', 'rotate');
        if (d = nil) or (d.JSONType = jtNull) then d := StyleKey(node, 'label', 'rotate');
        if (d <> nil) and (d.JSONType = jtNumber) then
        begin
          answer[si].Labels[r].HasRotate := True;
          answer[si].Labels[r].Rotate := d.AsFloat;
        end;
      end;
    end;
  end;

begin
  SetLength(answer, Length(ABindings));
  for p := 0 to High(answer) do answer[p] := Default(TTyPolarBarLayout);
  Result := answer;
  if (AOption = nil) or (AIndex = nil) then Exit;
  key := TySeriesStatKey('bar', TyPolarCoordSysName);
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    for p := 0 to High(APolars) do
    begin
      if APolars[p] = nil then Continue;
      for a := 0 to 1 do
        if a = 0 then DoAxis(APolars[p], APolars[p].RadiusAxis)
        else DoAxis(APolars[p], APolars[p].AngleAxis);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
  Result := answer;
end;

{ ==================== the view ==================== }

function Finite(V: Double): Boolean;
begin
  Result := not (IsNan(V) or IsInfinite(V));
end;

function TyPolarSectorValid(const S: TTyPolarSector): Boolean;
begin
  Result := Finite(S.CX) and Finite(S.CY) and Finite(S.R) and Finite(S.SA)
    and Finite(S.EA);
end;

function TyPolarBarClip(AAreaR0, AAreaR: Double; var S: TTyPolarSector): Boolean;
var
  signNeg: Boolean;
  t, r, r0: Double;
begin
  { r0 <= r ? 1 : -1 -- a not-a-number is the negative sign }
  signNeg := not (S.R0 <= S.R);
  if signNeg then
  begin
    t := S.R;
    S.R := S.R0;
    S.R0 := t;
  end;
  { Math.min / Math.max: a not-a-number wins }
  if IsNan(S.R) or IsNan(AAreaR) then r := NaN else r := Math.Min(S.R, AAreaR);
  if IsNan(S.R0) or IsNan(AAreaR0) then r0 := NaN else r0 := Math.Max(S.R0, AAreaR0);
  S.R := r;
  S.R0 := r0;
  Result := r - r0 < 0;
  if signNeg then
  begin
    t := S.R;
    S.R := S.R0;
    S.R0 := t;
  end;
end;

function TyPolarZero(const S: TTyPolarSector): Boolean;
begin
  Result := S.SA = S.EA;
end;

function TyPolarBarBackground(const L: TTyPolarBarLayout;
  const S: TTyPolarSector): TTyPolarSector;
begin
  Result.CX := L.AreaCX;
  Result.CY := L.AreaCY;
  if L.IsRadial then
  begin
    Result.R0 := L.AreaR0;
    Result.R := L.AreaR;
    Result.SA := S.SA;
    Result.EA := S.EA;
  end
  else
  begin
    Result.R0 := S.R0;
    Result.R := S.R;
    Result.SA := 0;
    Result.EA := Pi * 2;
  end;
  { the Sector's default: clockwise }
  Result.CW := True;
end;

function TyPolarCornerList(const ASpec: TTyPolarCornerSpec;
  const S: TTyPolarSector): TTyDoubleArray;
var
  dr: Double;
  k, n: Integer;
begin
  Result := nil;
  if not ASpec.Given then
  begin
    { zeroIfNull: cornerRadius 0 }
    SetLength(Result, 1);
    Result[0] := 0;
    Exit;
  end;
  { Math.abs(shape.r || 0 - shape.r0 || 0) }
  if Truthy(S.R) then dr := Abs(S.R)
  else if Truthy(0 - S.R0) then dr := Abs(0 - S.R0)
  else dr := 0;
  if ASpec.IsArray then n := ASpec.Count else n := 4;
  SetLength(Result, n);
  for k := 0 to n - 1 do
  begin
    if ASpec.IsArray then
    begin
      if ASpec.Pct[k] then Result[k] := ASpec.Vals[k] / 100 * dr
      else Result[k] := ASpec.Vals[k];
    end
    else if ASpec.Pct[0] then Result[k] := ASpec.Vals[0] / 100 * dr
    else Result[k] := ASpec.Vals[0];
  end;
end;

function TyPolarCornerRaw(const ASpec: TTyPolarCornerSpec): TTyDoubleArray;
var k: Integer;
begin
  Result := nil;
  if not ASpec.Given then
  begin
    SetLength(Result, 1);
    Result[0] := 0;
    Exit;
  end;
  { `borderRadius || 0` handed to zrender as it stands: a string stays a
    string upstream, which roundSector's arithmetic reads as its number }
  if ASpec.IsArray then
  begin
    SetLength(Result, ASpec.Count);
    for k := 0 to ASpec.Count - 1 do Result[k] := ASpec.Vals[k];
  end
  else
  begin
    { a number: normalizeCornerRadius makes it four }
    SetLength(Result, 4);
    for k := 0 to 3 do Result[k] := ASpec.Vals[0];
  end;
end;

function TyPolarCornerFour(const AList: TTyDoubleArray; out A: TTyCornerRadii): Boolean;
var k: Integer;
begin
  for k := 0 to 3 do A[k] := 0;
  Result := False;
  case Length(AList) of
    0: Exit;
    1: begin
         { a one-element list is [v, v, 0, 0] -- a number arrives here as
           four already (getSectorCornerRadius, TyPolarCornerRaw) }
         A[0] := AList[0]; A[1] := AList[0];
       end;
    2: begin A[0] := AList[0]; A[1] := AList[0]; A[2] := AList[1]; A[3] := AList[1]; end;
    3: begin A[0] := AList[0]; A[1] := AList[1]; A[2] := AList[2]; A[3] := AList[2]; end;
  else
    for k := 0 to 3 do A[k] := AList[k];
  end;
  Result := True;
end;

function TyPolarSectorShape(const S: TTyPolarSector; const ACorners: TTyDoubleArray;
  ASausage: Boolean): TTyChartShape;
var
  st, en, t: Double;
  four: TTyCornerRadii;
  haveCorners: Boolean;
begin
  Result := TyShapeSector(S.CX, S.CY, S.R0, S.R, 0, 1);
  st := S.SA;
  en := S.EA;
  if S.CW then
  begin
    if en - st >= 2 * Pi then en := st + 2 * Pi
    else if st > en then en := st + (2 * Pi - TyJsFMod(st - en, 2 * Pi));
  end
  else
  begin
    if st - en >= 2 * Pi then en := st - 2 * Pi
    else if st < en then en := st - (2 * Pi - TyJsFMod(en - st, 2 * Pi));
    t := st;
    st := en;
    en := t;
  end;
  Result.StartRad := st;
  Result.EndRad := en;
  Result.Sausage := ASausage;
  haveCorners := (Length(ACorners) > 1)
    or ((Length(ACorners) = 1) and Truthy(ACorners[0]));
  if haveCorners and TyPolarCornerFour(ACorners, four) then
  begin
    if not S.CW then
    begin
      t := four[0]; four[0] := four[1]; four[1] := t;
      t := four[2]; four[2] := four[3]; four[3] := t;
    end;
    { roundSector clamps them itself; a negative or a not-a-number draws as
      none }
    if not (four[0] > 0) then four[0] := 0;
    if not (four[1] > 0) then four[1] := 0;
    if not (four[2] > 0) then four[2] := 0;
    if not (four[3] > 0) then four[3] := 0;
    Result.SectorRadii := four;
  end;
end;

{ ---- roundSector.ts ---- }

const
  cE = 1e-4;

function Intersect(X0, Y0, X1, Y1, X2, Y2, X3, Y3: Double;
  out AX, AY: Double): Boolean;
var dx10, dy10, dx32, dy32, t: Double;
begin
  AX := 0;
  AY := 0;
  dx10 := X1 - X0;
  dy10 := Y1 - Y0;
  dx32 := X3 - X2;
  dy32 := Y3 - Y2;
  t := dy32 * dx10 - dx32 * dy10;
  if t * t < cE then Exit(False);
  t := (dx32 * (Y0 - Y2) - dy32 * (X0 - X2)) / t;
  AX := X0 + t * dx10;
  AY := Y0 + t * dy10;
  Result := True;
end;

type
  TCornerT = record
    CX, CY, X0, Y0, X1, Y1: Double;
  end;

function CornerTangents(X0, Y0, X1, Y1, ARadius, ACr: Double;
  AClockwise: Boolean): TCornerT;
var
  x01, y01, lo, ox, oy, x11, y11, x10, y10, x00, y00, dx, dy, d2, r, s, d,
    cx0, cy0, cx1, cy1, dx0, dy0, dx1, dy1: Double;
begin
  x01 := X0 - X1;
  y01 := Y0 - Y1;
  if AClockwise then lo := ACr else lo := -ACr;
  lo := lo / Sqrt(x01 * x01 + y01 * y01);
  ox := lo * y01;
  oy := -lo * x01;
  x11 := X0 + ox;
  y11 := Y0 + oy;
  x10 := X1 + ox;
  y10 := Y1 + oy;
  x00 := (x11 + x10) / 2;
  y00 := (y11 + y10) / 2;
  dx := x10 - x11;
  dy := y10 - y11;
  d2 := dx * dx + dy * dy;
  r := ARadius - ACr;
  s := x11 * y10 - x10 * y11;
  if dy < 0 then d := -1 else d := 1;
  d := d * Sqrt(JMax(0, r * r * d2 - s * s));
  cx0 := (s * dy - dx * d) / d2;
  cy0 := (-s * dx - dy * d) / d2;
  cx1 := (s * dy + dx * d) / d2;
  cy1 := (-s * dx + dy * d) / d2;
  dx0 := cx0 - x00;
  dy0 := cy0 - y00;
  dx1 := cx1 - x00;
  dy1 := cy1 - y00;
  if dx0 * dx0 + dy0 * dy0 > dx1 * dx1 + dy1 * dy1 then
  begin
    cx0 := cx1;
    cy0 := cy1;
  end;
  Result.CX := cx0;
  Result.CY := cy0;
  Result.X0 := -ox;
  Result.Y0 := -oy;
  Result.X1 := cx0 * (ARadius / r - 1);
  Result.Y1 := cy0 * (ARadius / r - 1);
end;

function TyZrSectorPath(const S: TTyPolarSector; const ACorners: TTyDoubleArray): TTyZrPath;
var
  radius, innerRadius, t, arc, modv, cx, cy, xrs, yrs, xire, yire, xre, yre,
    xirs, yirs, halfRd, ocrs, ocre, icrs, icre, ocrMax, icrMax, limO, limI,
    ix, iy, x0, y0, x1, y1, a, b, crStart, crEnd: Double;
  icrStart, icrEnd, ocrStart, ocrEnd: Double;
  hasArc, cw, haveCorners: Boolean;
  four: TTyCornerRadii;
  ct0, ct1: TCornerT;
  path: TTyZrPath;
  mask: TFPUExceptionMask;
begin
  path := nil;
  Result := nil;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    radius := JMax(S.R, 0);
    { shape.r0 || 0 }
    if Truthy(S.R0) then innerRadius := JMax(S.R0, 0) else innerRadius := 0;
    if not (radius > 0) and not (innerRadius > 0) then Exit;
    if not (radius > 0) then
    begin
      radius := innerRadius;
      innerRadius := 0;
    end;
    if innerRadius > radius then
    begin
      t := radius;
      radius := innerRadius;
      innerRadius := t;
    end;
    if IsNan(S.SA) or IsNan(S.EA) then Exit;
    cx := S.CX;
    cy := S.CY;
    cw := S.CW;
    arc := Abs(S.EA - S.SA);
    { arc > PI2 && arc % PI2 }
    if arc > 2 * Pi then
    begin
      modv := TyJsFMod(arc, 2 * Pi);
      if modv > cE then arc := modv;
    end;
    if not (radius > cE) then
      TyZrMoveTo(path, cx, cy)
    else if arc > 2 * Pi - cE then
    begin
      TyZrMoveTo(path, cx + radius * TyJsCos(S.SA), cy + radius * TyJsSin(S.SA));
      TyZrArc(path, cx, cy, radius, S.SA, S.EA, not cw);
      if innerRadius > cE then
      begin
        TyZrMoveTo(path, cx + innerRadius * TyJsCos(S.EA), cy + innerRadius * TyJsSin(S.EA));
        TyZrArc(path, cx, cy, innerRadius, S.EA, S.SA, cw);
      end;
    end
    else
    begin
      icrStart := NaN; icrEnd := NaN; ocrStart := NaN; ocrEnd := NaN;
      ocrMax := NaN; icrMax := NaN; limO := NaN; limI := NaN;
      xre := NaN; yre := NaN; xirs := NaN; yirs := NaN;
      xrs := radius * TyJsCos(S.SA);
      yrs := radius * TyJsSin(S.SA);
      xire := innerRadius * TyJsCos(S.EA);
      yire := innerRadius * TyJsSin(S.EA);
      hasArc := arc > cE;
      if hasArc then
      begin
        { `if (cornerRadius)`: a number other than nought, or a list }
        haveCorners := (Length(ACorners) > 1)
          or ((Length(ACorners) = 1) and Truthy(ACorners[0]));
        if haveCorners and TyPolarCornerFour(ACorners, four) then
        begin
          icrStart := four[0];
          icrEnd := four[1];
          ocrStart := four[2];
          ocrEnd := four[3];
        end;
        halfRd := Abs(radius - innerRadius) / 2;
        ocrs := JMin(halfRd, ocrStart);
        ocre := JMin(halfRd, ocrEnd);
        icrs := JMin(halfRd, icrStart);
        icre := JMin(halfRd, icrEnd);
        ocrMax := JMax(ocrs, ocre);
        limO := ocrMax;
        icrMax := JMax(icrs, icre);
        limI := icrMax;
        if (ocrMax > cE) or (icrMax > cE) then
        begin
          xre := radius * TyJsCos(S.EA);
          yre := radius * TyJsSin(S.EA);
          xirs := innerRadius * TyJsCos(S.SA);
          yirs := innerRadius * TyJsSin(S.SA);
          if arc < Pi then
            if Intersect(xrs, yrs, xirs, yirs, xre, yre, xire, yire, ix, iy) then
            begin
              x0 := xrs - ix;
              y0 := yrs - iy;
              x1 := xre - ix;
              y1 := yre - iy;
              a := 1 / TyJsSin(TyJsAcos((x0 * x1 + y0 * y1)
                / (Sqrt(x0 * x0 + y0 * y0) * Sqrt(x1 * x1 + y1 * y1))) / 2);
              b := Sqrt(ix * ix + iy * iy);
              limO := JMin(ocrMax, (radius - b) / (a + 1));
              limI := JMin(icrMax, (innerRadius - b) / (a - 1));
            end;
        end;
      end;
      if not hasArc then
        TyZrMoveTo(path, cx + xrs, cy + yrs)
      else if limO > cE then
      begin
        crStart := JMin(ocrStart, limO);
        crEnd := JMin(ocrEnd, limO);
        ct0 := CornerTangents(xirs, yirs, xrs, yrs, radius, crStart, cw);
        ct1 := CornerTangents(xre, yre, xire, yire, radius, crEnd, cw);
        TyZrMoveTo(path, cx + ct0.CX + ct0.X0, cy + ct0.CY + ct0.Y0);
        if (limO < ocrMax) and (crStart = crEnd) then
          TyZrArc(path, cx + ct0.CX, cy + ct0.CY, limO, TyJsAtan2(ct0.Y0, ct0.X0),
            TyJsAtan2(ct1.Y0, ct1.X0), not cw)
        else
        begin
          if crStart > 0 then
            TyZrArc(path, cx + ct0.CX, cy + ct0.CY, crStart, TyJsAtan2(ct0.Y0, ct0.X0),
              TyJsAtan2(ct0.Y1, ct0.X1), not cw);
          TyZrArc(path, cx, cy, radius, TyJsAtan2(ct0.CY + ct0.Y1, ct0.CX + ct0.X1),
            TyJsAtan2(ct1.CY + ct1.Y1, ct1.CX + ct1.X1), not cw);
          if crEnd > 0 then
            TyZrArc(path, cx + ct1.CX, cy + ct1.CY, crEnd, TyJsAtan2(ct1.Y1, ct1.X1),
              TyJsAtan2(ct1.Y0, ct1.X0), not cw);
        end;
      end
      else
      begin
        TyZrMoveTo(path, cx + xrs, cy + yrs);
        TyZrArc(path, cx, cy, radius, S.SA, S.EA, not cw);
      end;
      if not (innerRadius > cE) or not hasArc then
        TyZrLineTo(path, cx + xire, cy + yire)
      else if limI > cE then
      begin
        crStart := JMin(icrStart, limI);
        crEnd := JMin(icrEnd, limI);
        ct0 := CornerTangents(xire, yire, xre, yre, innerRadius, -crEnd, cw);
        ct1 := CornerTangents(xrs, yrs, xirs, yirs, innerRadius, -crStart, cw);
        TyZrLineTo(path, cx + ct0.CX + ct0.X0, cy + ct0.CY + ct0.Y0);
        if (limI < icrMax) and (crStart = crEnd) then
          TyZrArc(path, cx + ct0.CX, cy + ct0.CY, limI, TyJsAtan2(ct0.Y0, ct0.X0),
            TyJsAtan2(ct1.Y0, ct1.X0), not cw)
        else
        begin
          if crEnd > 0 then
            TyZrArc(path, cx + ct0.CX, cy + ct0.CY, crEnd, TyJsAtan2(ct0.Y0, ct0.X0),
              TyJsAtan2(ct0.Y1, ct0.X1), not cw);
          TyZrArc(path, cx, cy, innerRadius, TyJsAtan2(ct0.CY + ct0.Y1, ct0.CX + ct0.X1),
            TyJsAtan2(ct1.CY + ct1.Y1, ct1.CX + ct1.X1), cw);
          if crStart > 0 then
            TyZrArc(path, cx + ct1.CX, cy + ct1.CY, crStart, TyJsAtan2(ct1.Y1, ct1.X1),
              TyJsAtan2(ct1.Y0, ct1.X0), not cw);
        end;
      end
      else
      begin
        TyZrLineTo(path, cx + xire, cy + yire);
        TyZrArc(path, cx, cy, innerRadius, S.EA, S.SA, cw);
      end;
    end;
    TyZrClose(path);
    Result := path;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

function TyZrSausagePath(const S: TTyPolarSector): TTyZrPath;
var
  r0, r, dr, rc, sa, ea, usx, usy, uex, uey: Double;
  less: Boolean;
  path: TTyZrPath;
  mask: TFPUExceptionMask;
begin
  path := nil;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    { Math.max(shape.r0 || 0, 0), Math.max(shape.r, 0) }
    if Truthy(S.R0) then r0 := JMax(S.R0, 0) else r0 := 0;
    r := JMax(S.R, 0);
    dr := (r - r0) * 0.5;
    rc := r0 + dr;
    sa := S.SA;
    ea := S.EA;
    if S.CW then less := ea - sa < Pi * 2
    else less := sa - ea < Pi * 2;
    if not less then
      if S.CW then sa := ea - Pi * 2 else sa := ea - (-Pi * 2);
    usx := TyJsCos(sa);
    usy := TyJsSin(sa);
    uex := TyJsCos(ea);
    uey := TyJsSin(ea);
    if less then
    begin
      TyZrMoveTo(path, usx * r0 + S.CX, usy * r0 + S.CY);
      TyZrArc(path, usx * rc + S.CX, usy * rc + S.CY, dr, -Pi + sa, sa, not S.CW);
    end
    else
      TyZrMoveTo(path, usx * r + S.CX, usy * r + S.CY);
    TyZrArc(path, S.CX, S.CY, r, sa, ea, not S.CW);
    TyZrArc(path, uex * rc + S.CX, uey * rc + S.CY, dr, ea - Pi * 2, ea - Pi, not S.CW);
    if r0 <> 0 then
      TyZrArc(path, S.CX, S.CY, r0, ea, sa, S.CW);
    Result := path;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ==================== the labels ==================== }

function TySectorTextPosOf(const AWord: string; AIsRadial: Boolean): TTySectorTextPos;
var w: string;
begin
  w := AWord;
  { createPolarPositionMapping }
  if (w = 'start') or (w = 'insideStart') or (w = 'end') or (w = 'insideEnd') then
    if AIsRadial then w := w + 'Arc' else w := w + 'Angle';
  if w = 'startArc' then Result := stpStartArc
  else if w = 'insideStartArc' then Result := stpInsideStartArc
  else if w = 'startAngle' then Result := stpStartAngle
  else if w = 'insideStartAngle' then Result := stpInsideStartAngle
  else if w = 'middle' then Result := stpMiddle
  else if w = 'endArc' then Result := stpEndArc
  else if w = 'insideEndArc' then Result := stpInsideEndArc
  else if w = 'endAngle' then Result := stpEndAngle
  else if w = 'insideEndAngle' then Result := stpInsideEndAngle
  else Result := stpBuiltin;
end;

function TyPolarOutsideWord(const S: TTyPolarSector; AIsRadial: Boolean): string;
begin
  if AIsRadial then
  begin
    if S.R >= S.R0 then Result := 'endArc' else Result := 'startArc';
  end
  else if S.EA >= S.SA then Result := 'endAngle'
  else Result := 'startAngle';
end;

procedure TySectorLabelAnchor(const S: TTyPolarSector; APos: TTySectorTextPos;
  ADistance: Double; AIsRoundCap: Boolean; out AX, AY: Double;
  out AH: TTyTextAnchorH; out AV: TTyTextAnchorV);
var
  mr, ma, extra, dd: Double;

  function AdjX(AAngle, ADist: Double; AIsEnd: Boolean): Double;
  begin
    if AIsEnd then Result := ADist * TyJsSin(AAngle) * -1
    else Result := ADist * TyJsSin(AAngle) * 1;
  end;

  function AdjY(AAngle, ADist: Double; AIsEnd: Boolean): Double;
  begin
    if AIsEnd then Result := ADist * TyJsCos(AAngle) * 1
    else Result := ADist * TyJsCos(AAngle) * -1;
  end;

begin
  mr := (S.R + S.R0) / 2;
  ma := (S.SA + S.EA) / 2;
  if AIsRoundCap then extra := Abs(S.R - S.R0) / 2 else extra := 0;
  { base position: top-left }
  AX := S.CX + S.R * TyJsCos(S.SA);
  AY := S.CY + S.R * TyJsSin(S.SA);
  AH := tahLeft;
  AV := tavTop;
  case APos of
    stpStartArc:
      begin
        AX := S.CX + (S.R0 - ADistance) * TyJsCos(ma);
        AY := S.CY + (S.R0 - ADistance) * TyJsSin(ma);
        AH := tahCentre;
        AV := tavTop;
      end;
    stpInsideStartArc:
      begin
        AX := S.CX + (S.R0 + ADistance) * TyJsCos(ma);
        AY := S.CY + (S.R0 + ADistance) * TyJsSin(ma);
        AH := tahCentre;
        AV := tavBottom;
      end;
    stpStartAngle:
      begin
        dd := ADistance + extra;
        AX := S.CX + mr * TyJsCos(S.SA) + AdjX(S.SA, dd, False);
        AY := S.CY + mr * TyJsSin(S.SA) + AdjY(S.SA, dd, False);
        AH := tahRight;
        AV := tavMiddle;
      end;
    stpInsideStartAngle:
      begin
        dd := -ADistance + extra;
        AX := S.CX + mr * TyJsCos(S.SA) + AdjX(S.SA, dd, False);
        AY := S.CY + mr * TyJsSin(S.SA) + AdjY(S.SA, dd, False);
        AH := tahLeft;
        AV := tavMiddle;
      end;
    stpMiddle:
      begin
        AX := S.CX + mr * TyJsCos(ma);
        AY := S.CY + mr * TyJsSin(ma);
        AH := tahCentre;
        AV := tavMiddle;
      end;
    stpEndArc:
      begin
        AX := S.CX + (S.R + ADistance) * TyJsCos(ma);
        AY := S.CY + (S.R + ADistance) * TyJsSin(ma);
        AH := tahCentre;
        AV := tavBottom;
      end;
    stpInsideEndArc:
      begin
        AX := S.CX + (S.R - ADistance) * TyJsCos(ma);
        AY := S.CY + (S.R - ADistance) * TyJsSin(ma);
        AH := tahCentre;
        AV := tavTop;
      end;
    stpEndAngle:
      begin
        dd := ADistance + extra;
        AX := S.CX + mr * TyJsCos(S.EA) + AdjX(S.EA, dd, True);
        AY := S.CY + mr * TyJsSin(S.EA) + AdjY(S.EA, dd, True);
        AH := tahLeft;
        AV := tavMiddle;
      end;
    stpInsideEndAngle:
      begin
        dd := -ADistance + extra;
        AX := S.CX + mr * TyJsCos(S.EA) + AdjX(S.EA, dd, True);
        AY := S.CY + mr * TyJsSin(S.EA) + AdjY(S.EA, dd, True);
        AH := tahRight;
        AV := tavMiddle;
      end;
  end;
end;

function TySectorLabelRotation(const S: TTyPolarSector; const AAsk: TTyPolarLabelAsk;
  AWord: string; AIsRadial: Boolean): Double;
var
  st, en, mid, anchor: Double;
  pos: TTySectorTextPos;
begin
  if AAsk.HasRotate then Exit(AAsk.Rotate);
  if AAsk.IsArray then Exit(0);
  if S.CW then
  begin
    st := S.SA;
    en := S.EA;
  end
  else
  begin
    st := S.EA;
    en := S.SA;
  end;
  mid := (st + en) / 2;
  pos := TySectorTextPosOf(AWord, AIsRadial);
  case pos of
    stpStartArc, stpInsideStartArc, stpMiddle, stpInsideEndArc, stpEndArc:
      anchor := mid;
    stpStartAngle, stpInsideStartAngle:
      anchor := st;
    stpEndAngle, stpInsideEndAngle:
      anchor := en;
  else
    Exit(0);
  end;
  Result := Pi * 1.5 - anchor;
  if (pos = stpMiddle) and (Result > Pi / 2) and (Result < Pi * 1.5) then
    Result := Result - Pi;
end;

end.
