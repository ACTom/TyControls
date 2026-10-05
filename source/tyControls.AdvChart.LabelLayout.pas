unit tyControls.AdvChart.LabelLayout;
{$mode objfpc}{$H+}
{ SERIES LABEL LAYOUT -- upstream's LabelManager over the labels of every
  series that writes a `labelLayout`. [Batch 103, roadmap B8]

  WHAT UPSTREAM DOES, in the order it does it (label/LabelManager.ts with
  label/labelLayoutHelper.ts, ECharts 6.1.0):

  1. ADD. Every label of a series whose `labelLayout` is a function or an
     object with at least one key is listed, series in series order, each
     series' labels in its view's traverse order. It keeps what the label was:
     its transform decomposed (x, y, rotation normalised to [0, 2 Pi), the
     scale -- which after a turn is 0.9999999999999999, not one), whether it
     was ignored, the host's rect through the host's transform and the
     priority, which is that rect's area.
  2. CONFIGURE. The layout (the object, or the function's answer for this
     label) is applied: x or y given drops the host's position and puts the
     label at parsePercent(x, chart width) / (y, height), the other one where
     it was; dx / dy REPLACE the host's textConfig.offset (an author's
     `label.offset` is gone on an attached label) and, through the origin
     zrender sets to minus the offset, run along the TURNED axes; rotate (in
     degrees) replaces the turn; align / verticalAlign / fontSize go onto the
     label's style.
  3. LAY OUT, over the labels not ignored at rest: moveOverlap 'shiftX' /
     'shiftY' sorts its labels by their rects and moves label.x / y and the
     rects apart, squeezing into the chart and, when there is no room, letting
     them overlap (shiftLayoutOnXY); then hideOverlap restores every one's
     ignore, sorts them by priority (stable) and hides each label that meets
     one already kept -- rects first, oriented boxes when either is turned,
     both shrunk by a 0.05 touch threshold -- and its label line with it, and
     gives a label it hides an emphasis state that shows it again unless the
     author said otherwise.

  TWO THINGS THAT READ LIKE BUGS AND ARE TRANSCRIBED AS SUCH:
    - a label still ATTACHED to its host (no x, no y) is drawn where its host
      puts it: the host's textConfig position is recomputed on every
      transform, so moving label.x / y moves nothing. A shift on such labels
      is invisible;
    - hideOverlap computes every label's geometry AGAIN from the label as it
      stands (the oriented-box dirty bit is left set and the all-bits mask
      counts it), so it never sees an attached label's shifted rect -- only
      a free label's, through its shifted x / y.

  PURE: SysUtils, Math, fpjson and the AdvChart units. The caller places and
  measures; this unit decides. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Handlers,
  tyControls.AdvChart.AxisLabels;

type
  { a series' labelLayout: none, an object, or a named handler }
  TTyLabelLayoutKind = (tlkNone, tlkObject, tlkHandler);
  TTyLabelLayoutSpec = record
    Kind: TTyLabelLayoutKind;
    Obj: TTyChartLabelLayout;
    Handler: string;
  end;

  { moveOverlap, read }
  TTyLabelMove = (tlmNone, tlmShiftX, tlmShiftY);

  { ONE LABEL IN THE MANAGER'S LIST, as the layout pass weighs it. The
    caller fills the inputs; TyLayoutLabels fills the answers. }
  TTyLabelLayoutItem = record
    { ---- inputs ---- }
    Priority: Double;
    { ignored at rest (a label only a state shows): kept out of the layout }
    DefIgnore: Boolean;
    HasGuide, DefGuideIgnore: Boolean;
    Move: TTyLabelMove;
    HideOverlap: Boolean;
    { POSITION NULL: the label is drawn where label.x / y put it -- a pie's,
      or one given an x or a y. False: its host places it. }
    Free: Boolean;
    { the label's own box before any margin, in its frame }
    RawLocal: TTyXYWH;
    { 0 none, 1 minMargin (grows the global rect), 2 textMargin (grows the
      local one); [top, right, bottom, left] }
    MarginType: Integer;
    Margin: array[0..3] of Double;
    { THE INNER TRANSFORMABLE as the host left it: the point (label.x + the
      offset, or the position's anchor + the offset), the origin (minus the
      offset), the turn and the scale }
    InnerX, InnerY, OriginX, OriginY, Rotation, ScaleX, ScaleY: Double;
    { the offset, for a free label's inner point after a shift }
    OffX, OffY: Double;
    { label.x / label.y: what a shift moves }
    LabelX, LabelY: Double;
    { an emphasis state that already says ignore one way or the other (the
      author's `emphasis.label.show` against the normal one): hideOverlap
      leaves it as it is }
    EmphDeclared, GuideEmphDeclared: Boolean;
    { ---- answers ---- }
    { the geometry at the layout's start, and as hideOverlap saw it }
    Box: TTyLabelBox;
    Ignore, GuideIgnore: Boolean;
    { hideOverlap hid it and gave its emphasis state `ignore: false` }
    EmphShow, GuideEmphShow: Boolean;
  end;
  TTyLabelLayoutItemArray = array of TTyLabelLayoutItem;

{ ---- reading ---- }

{ The series' `labelLayout` node as seriesModel.get reads it: a string
  '@Name' is a handler; an object with at least one key, a non-empty
  string or array is a layout (keys(...).length -- a string that names no
  handler or an array lays out with every field absent); null, a boolean,
  a number or {} is none. APieDefault merges a pie's default
  `{hideOverlap: true}` under the node (and stands alone where the series
  wrote no `labelLayout` at all: AHasKey False). }
function TyLabelLayoutSpecOf(ANode: TJSONData; AHasKey, APieDefault: Boolean): TTyLabelLayoutSpec;

{ One layout object read: x / y (numbers and strings, a boolean as +b),
  dx / dy, rotate and fontSize (numbers), align / verticalAlign (strings),
  width / height, moveOverlap, hideOverlap and draggable (JavaScript
  truthiness), labelLinePoints (an array of [x, y]). }
function TyLabelLayoutOfObject(AObj: TJSONObject): TTyChartLabelLayout;

{ moveOverlap as the layout pass compares it: exactly 'shiftX' / 'shiftY'. }
function TyLabelMoveOf(const ALayout: TTyChartLabelLayout): TTyLabelMove;

{ parsePercent(value, all): a number as it is; a text through the position
  words ('center' / 'middle' 50%, 'left' / 'top' 0%, 'right' / 'bottom'
  100%), then 'N%' of AAll, else parseFloat; absent NaN. }
function TyLabelLayoutPos(const AValue: TTyChartPosValue; AAll: Double): Double;

{ degrees to radians as LabelManager multiplies: deg * (Math.PI / 180) }
function TyLabelLayoutRad(ADeg: Double): Double;

{ ---- geometry ---- }

{ Transformable.getLocalTransform with no skew and no anchor, its order of
  operations exactly; False (and the identity) when needLocalTransform says
  there is none -- every term within 5e-5 of rest. }
function TyLabelLocalTransform(AX, AY, AOriginX, AOriginY, ARotation,
  AScaleX, AScaleY: Double; out AM: TTyMat2D): Boolean;

{ computeLabelGeometry: the raw local rect, a textMargin round it, through
  the transform (none: AHasM False), a minMargin round the result. }
function TyLabelGeometry(const ARawLocal: TTyXYWH; const AM: TTyMat2D;
  AHasM: Boolean; AMarginType: Integer; const AMargin: array of Double): TTyLabelBox;

{ An item's geometry from its inner transformable }
function TyLabelItemBox(const AItem: TTyLabelLayoutItem): TTyLabelBox;

{ setLocalTransform on a decomposition: x, y, the turn normalised into
  [0, 2 Pi) (normalizeRadian), the scale. AHasM False is the identity. }
procedure TyLabelDecompose(const AM: TTyMat2D; AHasM: Boolean;
  out AX, AY, ARotation, AScaleX, AScaleY: Double);

{ normalizeRadian }
function TyNormalizeRadian(AAngle: Double): Double;

{ A PLAIN SECTOR'S PATH RECT -- zrender's roundSector buildPath without
  corners (move to the outer start, the outer arc, a line to the inner end
  and the inner arc back, or to the centre), measured by
  PathProxy.getBoundingRect: the arc's ends and the quarter turns it passes,
  in V8's cos / sin. What a pie slice's label takes as its host's rect. }
function TySectorPathRect(ACX, ACY, AR0, AR, AStart, AEnd: Double;
  AClockwise: Boolean): TTyXYWH;

{ ---- the layout ---- }

{ shiftLayoutOnXY over the items AIdx names, ADim 0 for x and 1 for y, the
  bounds [AMin, AMax]: sorted (stable) by their rects, then moved apart, the
  ends squeezed in (80 % at most of the gaps first), the other end's gap
  borrowed, and a bail-out that lets them overlap when there is no room.
  Moves Box.Rect and LabelX / LabelY. }
procedure TyShiftLabelsOnXY(var AItems: TTyLabelLayoutItemArray;
  const AIdx: array of Integer; ADim: Integer; AMin, AMax: Double);

{ restoreIgnore and hideOverlap over the items AIdx names. }
procedure TyHideOverlapLabels(var AItems: TTyLabelLayoutItemArray;
  const AIdx: array of Integer);

{ LabelManager.layout, whole, on the chart's rect (device px; upstream's is
  [0, width] x [0, height]): every item's Box from its inner transformable,
  the shifts, then hideOverlap. Items ignored at rest take no part. }
procedure TyLayoutLabels(var AItems: TTyLabelLayoutItemArray; ALeft, ATop,
  ARight, ABottom: Double);

implementation

uses
  tyControls.AdvChart.Layout, tyControls.AdvChart.JsMath,
  tyControls.AdvChart.Data, tyControls.AdvChart.ZrPath;

{ ==================== reading ==================== }

function Truthy(D: TJSONData): Boolean;
begin
  if (D = nil) or (D.JSONType = jtNull) then Exit(False);
  case D.JSONType of
    jtBoolean: Result := D.AsBoolean;
    jtNumber: Result := (not IsNan(D.AsFloat)) and (D.AsFloat <> 0);
    jtString: Result := D.AsString <> '';
  else
    Result := True;
  end;
end;

function PosOf(D: TJSONData): TTyChartPosValue;
begin
  Result := TyChartPosAbsent;
  if (D = nil) or (D.JSONType = jtNull) then Exit;
  case D.JSONType of
    jtNumber: Result := TyChartPosNum(D.AsFloat);
    jtString: Result := TyChartPosText(D.AsString);
    jtBoolean: if D.AsBoolean then Result := TyChartPosNum(1) else Result := TyChartPosNum(0);
  else
    { +[] and +{} are not numbers a chart can use }
    Result := TyChartPosNum(NaN);
  end;
end;

function TyLabelLayoutOfObject(AObj: TJSONObject): TTyChartLabelLayout;
var
  d: TJSONData;
  arr, pt: TJSONArray;
  i: Integer;
begin
  Result := Default(TTyChartLabelLayout);
  if AObj = nil then Exit;
  Result.X := PosOf(AObj.Find('x'));
  Result.Y := PosOf(AObj.Find('y'));
  d := AObj.Find('dx');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.HasDx := True;
    Result.Dx := d.AsFloat;
  end;
  d := AObj.Find('dy');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.HasDy := True;
    Result.Dy := d.AsFloat;
  end;
  d := AObj.Find('rotate');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.HasRotate := True;
    Result.Rotate := d.AsFloat;
  end;
  d := AObj.Find('align');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.HasAlign := True;
    Result.Align := d.AsString;
  end;
  d := AObj.Find('verticalAlign');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.HasVerticalAlign := True;
    Result.VerticalAlign := d.AsString;
  end;
  d := AObj.Find('fontSize');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.HasFontSize := True;
    Result.FontSize := d.AsFloat;
  end;
  d := AObj.Find('width');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.HasWidth := True;
    Result.Width := d.AsFloat;
  end;
  d := AObj.Find('height');
  if (d <> nil) and (d.JSONType = jtNumber) then
  begin
    Result.HasHeight := True;
    Result.Height := d.AsFloat;
  end;
  d := AObj.Find('moveOverlap');
  if (d <> nil) and (d.JSONType = jtString) then Result.MoveOverlap := d.AsString;
  Result.HideOverlap := Truthy(AObj.Find('hideOverlap'));
  Result.Draggable := Truthy(AObj.Find('draggable'));
  d := AObj.Find('labelLinePoints');
  if (d <> nil) and (d is TJSONArray) and (TJSONArray(d).Count > 0) then
  begin
    arr := TJSONArray(d);
    Result.HasLabelLinePoints := True;
    SetLength(Result.LabelLinePoints, arr.Count);
    for i := 0 to arr.Count - 1 do
    begin
      Result.LabelLinePoints[i].X := NaN;
      Result.LabelLinePoints[i].Y := NaN;
      if not (arr.Items[i] is TJSONArray) then Continue;
      pt := TJSONArray(arr.Items[i]);
      if (pt.Count > 0) and (pt.Items[0].JSONType = jtNumber) then
        Result.LabelLinePoints[i].X := pt.Items[0].AsFloat;
      if (pt.Count > 1) and (pt.Items[1].JSONType = jtNumber) then
        Result.LabelLinePoints[i].Y := pt.Items[1].AsFloat;
    end;
  end;
end;

function TyLabelLayoutSpecOf(ANode: TJSONData; AHasKey, APieDefault: Boolean): TTyLabelLayoutSpec;
var
  obj: TJSONObject;
  s: string;
begin
  Result := Default(TTyLabelLayoutSpec);
  Result.Kind := tlkNone;
  { NOT WRITTEN AT ALL: the series' default, which only a pie has }
  if not AHasKey then
  begin
    if APieDefault then
    begin
      Result.Kind := tlkObject;
      Result.Obj.HideOverlap := True;
    end;
    Exit;
  end;
  { null stays null: merge() does not overwrite a key the option holds }
  if (ANode = nil) or (ANode.JSONType = jtNull) then Exit;
  case ANode.JSONType of
    jtString:
      begin
        s := ANode.AsString;
        if TyChartIsHandlerRef(s) then
        begin
          Result.Kind := tlkHandler;
          Result.Handler := s;
        end
        { keys('abc') is ['0', '1', '2']: an empty layout, laid out }
        else if s <> '' then Result.Kind := tlkObject;
      end;
    jtArray:
      if TJSONArray(ANode).Count > 0 then Result.Kind := tlkObject;
    jtObject:
      begin
        obj := TJSONObject(ANode);
        { the default merged under: a key the author wrote is kept }
        if (obj.Count = 0) and not APieDefault then Exit;
        Result.Kind := tlkObject;
        Result.Obj := TyLabelLayoutOfObject(obj);
        if APieDefault and (obj.IndexOfName('hideOverlap') < 0) then
          Result.Obj.HideOverlap := True;
      end;
  end;
end;

function TyLabelMoveOf(const ALayout: TTyChartLabelLayout): TTyLabelMove;
begin
  if ALayout.MoveOverlap = 'shiftX' then Result := tlmShiftX
  else if ALayout.MoveOverlap = 'shiftY' then Result := tlmShiftY
  else Result := tlmNone;
end;

function TyLabelLayoutPos(const AValue: TTyChartPosValue; AAll: Double): Double;
var s, t: string;
begin
  case AValue.Kind of
    cpvNumber: Result := AValue.Num;
    cpvText:
      begin
        s := AValue.Text;
        if (s = 'center') or (s = 'middle') then s := '50%'
        else if (s = 'left') or (s = 'top') then s := '0%'
        else if (s = 'right') or (s = 'bottom') then s := '100%';
        t := TyJsTrim(s);
        if (t <> '') and (t[Length(t)] = '%') then
          Result := TyJsParseFloat(s) / 100 * AAll
        else
          Result := TyJsParseFloat(s);
      end;
  else
    Result := NaN;
  end;
end;

function TyLabelLayoutRad(ADeg: Double): Double;
var k: Double;
begin
  { const degreeToRadian = Math.PI / 180, then rotate * degreeToRadian }
  k := Pi / 180;
  Result := ADeg * k;
end;

{ ==================== geometry ==================== }

function NotAroundZero(A: Double): Boolean;
begin
  Result := (A > 5e-5) or (A < -5e-5);
end;

function TyLabelLocalTransform(AX, AY, AOriginX, AOriginY, ARotation,
  AScaleX, AScaleY: Double; out AM: TTyMat2D): Boolean;
var
  aa, ac, atx, ab, ad, aty, st, ct: Double;
begin
  AM[0] := 1; AM[1] := 0; AM[2] := 0; AM[3] := 1; AM[4] := 0; AM[5] := 0;
  { needLocalTransform; the NaN in a scale reads as a change, as `NaN - 1`
    is truthy-and-not-around-zero upstream }
  Result := NotAroundZero(ARotation) or NotAroundZero(AX) or NotAroundZero(AY)
    or NotAroundZero(AScaleX - 1) or NotAroundZero(AScaleY - 1)
    or IsNan(AScaleX) or IsNan(AScaleY);
  if not Result then Exit;
  { the origin }
  if (AOriginX <> 0) or (AOriginY <> 0) then
  begin
    AM[4] := -AOriginX * AScaleX - 0 * AOriginY * AScaleY;
    AM[5] := -AOriginY * AScaleY - 0 * AOriginX * AScaleX;
  end
  else
  begin
    AM[4] := 0;
    AM[5] := 0;
  end;
  AM[0] := AScaleX;
  AM[3] := AScaleY;
  AM[1] := 0 * AScaleX;
  AM[2] := 0 * AScaleY;
  if ARotation <> 0 then
  begin
    { matrix.rotate about [0, 0] }
    aa := AM[0]; ac := AM[2]; atx := AM[4];
    ab := AM[1]; ad := AM[3]; aty := AM[5];
    st := TyJsSin(ARotation);
    ct := TyJsCos(ARotation);
    AM[0] := aa * ct + ab * st;
    AM[1] := -aa * st + ab * ct;
    AM[2] := ac * ct + ad * st;
    AM[3] := -ac * st + ct * ad;
    AM[4] := ct * (atx - 0) + st * (aty - 0) + 0;
    AM[5] := ct * (aty - 0) - st * (atx - 0) + 0;
  end;
  AM[4] := AM[4] + (AOriginX + AX);
  AM[5] := AM[5] + (AOriginY + AY);
end;

function TyLabelGeometry(const ARawLocal: TTyXYWH; const AM: TTyMat2D;
  AHasM: Boolean; AMarginType: Integer; const AMargin: array of Double): TTyLabelBox;
var m: array[0..3] of Double; i: Integer;
begin
  for i := 0 to 3 do
    if i <= High(AMargin) then m[i] := AMargin[i] else m[i] := 0;
  Result.LocalRect := ARawLocal;
  if AMarginType = 2 then
    Result.LocalRect := TyRectExpand(Result.LocalRect, m[0], m[1], m[2], m[3]);
  if AHasM then
  begin
    Result.M := AM;
    Result.Rect := TyRectApplyMat(Result.LocalRect, AM);
  end
  else
  begin
    Result.M := TyMatIdentity;
    Result.Rect := Result.LocalRect;
  end;
  if AMarginType = 1 then
    Result.Rect := TyRectExpand(Result.Rect, m[0], m[1], m[2], m[3]);
  Result.AxisAligned := (not AHasM) or TyMatAxisAligned(AM);
end;

function TyLabelItemBox(const AItem: TTyLabelLayoutItem): TTyLabelBox;
var
  m: TTyMat2D;
  has: Boolean;
begin
  has := TyLabelLocalTransform(AItem.InnerX, AItem.InnerY, AItem.OriginX,
    AItem.OriginY, AItem.Rotation, AItem.ScaleX, AItem.ScaleY, m);
  Result := TyLabelGeometry(AItem.RawLocal, m, has, AItem.MarginType, AItem.Margin);
end;

function TyNormalizeRadian(AAngle: Double): Double;
begin
  Result := TyJsFMod(AAngle, Pi * 2);
  if Result < 0 then Result := Result + Pi * 2;
end;

procedure TyLabelDecompose(const AM: TTyMat2D; AHasM: Boolean;
  out AX, AY, ARotation, AScaleX, AScaleY: Double);
var p: TTyTransformProps;
begin
  if not AHasM then
  begin
    AX := 0; AY := 0; ARotation := 0; AScaleX := 1; AScaleY := 1;
    Exit;
  end;
  p := TyMatDecompose(AM);
  AX := p.X;
  AY := p.Y;
  ARotation := TyNormalizeRadian(p.Rotation);
  AScaleX := p.ScaleX;
  AScaleY := p.ScaleY;
end;

{ ==================== a sector's path rect ==================== }

function TySectorPathRect(ACX, ACY, AR0, AR, AStart, AEnd: Double;
  AClockwise: Boolean): TTyXYWH;
const
  e = 1e-4;
var
  path: TTyZrPath;
  radius, inner, tmp, arc, md, xrs, yrs, xire, yire: Double;
  hasArc: Boolean;
begin
  path := nil;
  Result := TyXYWH(0, 0, -1, -1);
  radius := Max(AR, Double(0));
  if IsNan(AR0) then inner := 0 else inner := Max(AR0, Double(0));
  if not ((radius > 0) or (inner > 0)) then Exit;
  if not (radius > 0) then
  begin
    radius := inner;
    inner := 0;
  end;
  if inner > radius then
  begin
    tmp := radius;
    radius := inner;
    inner := tmp;
  end;
  if IsNan(AStart) or IsNan(AEnd) then Exit;
  arc := Abs(AEnd - AStart);
  if arc > Pi * 2 then
  begin
    md := TyJsFMod(arc, Pi * 2);
    if md > e then arc := md;
  end;
  if not (radius > e) then
    TyZrMoveTo(path, ACX, ACY)
  else if arc > Pi * 2 - e then
  begin
    TyZrMoveTo(path, ACX + radius * TyJsCos(AStart), ACY + radius * TyJsSin(AStart));
    TyZrArc(path, ACX, ACY, radius, AStart, AEnd, not AClockwise);
    if inner > e then
    begin
      TyZrMoveTo(path, ACX + inner * TyJsCos(AEnd), ACY + inner * TyJsSin(AEnd));
      TyZrArc(path, ACX, ACY, inner, AEnd, AStart, AClockwise);
    end;
  end
  else
  begin
    xrs := radius * TyJsCos(AStart);
    yrs := radius * TyJsSin(AStart);
    xire := inner * TyJsCos(AEnd);
    yire := inner * TyJsSin(AEnd);
    hasArc := arc > e;
    TyZrMoveTo(path, ACX + xrs, ACY + yrs);
    if hasArc then TyZrArc(path, ACX, ACY, radius, AStart, AEnd, not AClockwise);
    TyZrLineTo(path, ACX + xire, ACY + yire);
    if (inner > e) and hasArc then
      TyZrArc(path, ACX, ACY, inner, AEnd, AStart, AClockwise);
  end;
  TyZrClose(path);
  Result := TyZrBBox(path);
end;

{ ==================== the layout ==================== }

function RectPos(const AR: TTyXYWH; ADim: Integer): Double; inline;
begin
  if ADim = 0 then Result := AR.X else Result := AR.Y;
end;

function RectSize(const AR: TTyXYWH; ADim: Integer): Double; inline;
begin
  if ADim = 0 then Result := AR.W else Result := AR.H;
end;

procedure TyShiftLabelsOnXY(var AItems: TTyLabelLayoutItemArray;
  const AIdx: array of Integer; ADim: Integer; AMin, AMax: Double);
var
  list: array of Integer;
  len, i, j, k: Integer;
  lastPos, delta, minGap, maxGap: Double;

  procedure Move1(AK: Integer; AD: Double);
  begin
    if ADim = 0 then
    begin
      AItems[AK].Box.Rect.X := AItems[AK].Box.Rect.X + AD;
      AItems[AK].LabelX := AItems[AK].LabelX + AD;
    end
    else
    begin
      AItems[AK].Box.Rect.Y := AItems[AK].Box.Rect.Y + AD;
      AItems[AK].LabelY := AItems[AK].LabelY + AD;
    end;
  end;

  procedure UpdateMinMaxGap;
  var f, l: Integer;
  begin
    f := list[0];
    l := list[len - 1];
    minGap := RectPos(AItems[f].Box.Rect, ADim) - AMin;
    maxGap := AMax - RectPos(AItems[l].Box.Rect, ADim) - RectSize(AItems[l].Box.Rect, ADim);
  end;

  procedure ShiftList(AD: Double; AStart, AEnd: Integer);
  var q: Integer;
  begin
    for q := AStart to AEnd - 1 do Move1(list[q], AD);
  end;

  procedure SqueezeGaps(AD, AMaxPct: Double);
  var
    gaps: array of Double;
    q: Integer;
    total, gap, pct, prevEnd: Double;
  begin
    SetLength(gaps, len - 1);
    total := 0;
    for q := 1 to len - 1 do
    begin
      prevEnd := RectPos(AItems[list[q - 1]].Box.Rect, ADim);
      gap := Max(RectPos(AItems[list[q]].Box.Rect, ADim) - prevEnd
        - RectSize(AItems[list[q - 1]].Box.Rect, ADim), Double(0));
      gaps[q - 1] := gap;
      total := total + gap;
    end;
    if total = 0 then Exit;
    pct := Min(Abs(AD) / total, AMaxPct);
    if AD > 0 then
    begin
      for q := 0 to len - 2 do ShiftList(gaps[q] * pct, 0, q + 1);
    end
    else
    begin
      for q := len - 1 downto 1 do ShiftList(-gaps[q - 1] * pct, q, len);
    end;
  end;

  procedure TakeBoundsGap(AThis, AOther: Double; ADir: Integer);
  var moveFromMaxGap, remained: Double;
  begin
    if AThis < 0 then
    begin
      moveFromMaxGap := Min(AOther, -AThis);
      if moveFromMaxGap > 0 then
      begin
        ShiftList(moveFromMaxGap * ADir, 0, len);
        remained := moveFromMaxGap + AThis;
        if remained < 0 then SqueezeGaps(-remained * ADir, 1);
      end
      else
        SqueezeGaps(-AThis * ADir, 1);
    end;
  end;

  procedure SqueezeWhenBailout(AD: Double);
  var
    dir, q: Integer;
    each: Double;
  begin
    if AD < 0 then dir := -1 else dir := 1;
    AD := Abs(AD);
    each := Ceil(AD / (len - 1));
    for q := 0 to len - 2 do
    begin
      if dir > 0 then ShiftList(each, 0, q + 1)
      else ShiftList(-each, len - q - 1, len);
      AD := AD - each;
      if AD <= 0 then Exit;
    end;
  end;

begin
  len := Length(AIdx);
  if len < 2 then Exit;
  SetLength(list, len);
  for i := 0 to len - 1 do list[i] := AIdx[i];
  { a stable sort by the rect's start, as V8's is }
  for i := 1 to len - 1 do
  begin
    k := list[i];
    j := i - 1;
    while (j >= 0) and (RectPos(AItems[k].Box.Rect, ADim)
      < RectPos(AItems[list[j]].Box.Rect, ADim)) do
    begin
      list[j + 1] := list[j];
      Dec(j);
    end;
    list[j + 1] := k;
  end;
  lastPos := 0;
  for i := 0 to len - 1 do
  begin
    k := list[i];
    delta := RectPos(AItems[k].Box.Rect, ADim) - lastPos;
    if delta < 0 then Move1(k, -delta);
    lastPos := RectPos(AItems[k].Box.Rect, ADim) + RectSize(AItems[k].Box.Rect, ADim);
  end;
  UpdateMinMaxGap;
  if minGap < 0 then SqueezeGaps(-minGap, 0.8);
  if maxGap < 0 then SqueezeGaps(maxGap, 0.8);
  UpdateMinMaxGap;
  TakeBoundsGap(minGap, maxGap, 1);
  TakeBoundsGap(maxGap, minGap, -1);
  UpdateMinMaxGap;
  if minGap < 0 then SqueezeWhenBailout(-minGap);
  if maxGap < 0 then SqueezeWhenBailout(maxGap);
end;

procedure TyHideOverlapLabels(var AItems: TTyLabelLayoutItemArray;
  const AIdx: array of Integer);
const
  cTouch = 0.05;
var
  order, shown: array of Integer;
  i, j, k, n, ns: Integer;
  hit: Boolean;
begin
  n := Length(AIdx);
  { restoreIgnore }
  for i := 0 to n - 1 do
  begin
    AItems[AIdx[i]].Ignore := AItems[AIdx[i]].DefIgnore;
    if AItems[AIdx[i]].HasGuide then
      AItems[AIdx[i]].GuideIgnore := AItems[AIdx[i]].DefGuideIgnore;
  end;
  SetLength(order, n);
  for i := 0 to n - 1 do order[i] := AIdx[i];
  { by priority, the higher first, stable }
  for i := 1 to n - 1 do
  begin
    k := order[i];
    j := i - 1;
    while (j >= 0) and (AItems[k].Priority > AItems[order[j]].Priority) do
    begin
      order[j + 1] := order[j];
      Dec(j);
    end;
    order[j + 1] := k;
  end;
  SetLength(shown, n);
  ns := 0;
  for i := 0 to n - 1 do
  begin
    k := order[i];
    { THE GEOMETRY AGAIN, from the label as it stands: a free label where its
      shifted x / y put it, an attached one where its host does }
    if AItems[k].Free then
    begin
      AItems[k].InnerX := AItems[k].LabelX + AItems[k].OffX;
      AItems[k].InnerY := AItems[k].LabelY + AItems[k].OffY;
    end;
    AItems[k].Box := TyLabelItemBox(AItems[k]);
    if AItems[k].Ignore then Continue;
    hit := False;
    for j := 0 to ns - 1 do
      if TyLabelBoxesIntersect(AItems[k].Box, AItems[shown[j]].Box, cTouch) then
      begin
        hit := True;
        Break;
      end;
    if hit then
    begin
      { hideEl: a label not yet hidden is shown again under emphasis, unless
        that state already says }
      if not AItems[k].EmphDeclared then AItems[k].EmphShow := True;
      AItems[k].Ignore := True;
      if AItems[k].HasGuide then
      begin
        if (not AItems[k].GuideIgnore) and not AItems[k].GuideEmphDeclared then
          AItems[k].GuideEmphShow := True;
        AItems[k].GuideIgnore := True;
      end;
    end
    else
    begin
      shown[ns] := k;
      Inc(ns);
    end;
  end;
end;

procedure TyLayoutLabels(var AItems: TTyLabelLayoutItemArray; ALeft, ATop,
  ARight, ABottom: Double);
var
  i, nx, ny, nh: Integer;
  xs, ys, hs: array of Integer;
begin
  SetLength(xs, Length(AItems));
  SetLength(ys, Length(AItems));
  SetLength(hs, Length(AItems));
  nx := 0;
  ny := 0;
  nh := 0;
  for i := 0 to High(AItems) do
  begin
    AItems[i].Ignore := AItems[i].DefIgnore;
    AItems[i].GuideIgnore := AItems[i].DefGuideIgnore;
    AItems[i].EmphShow := False;
    AItems[i].GuideEmphShow := False;
    AItems[i].Box := TyLabelItemBox(AItems[i]);
    if AItems[i].DefIgnore then Continue;
    case AItems[i].Move of
      tlmShiftX: begin xs[nx] := i; Inc(nx); end;
      tlmShiftY: begin ys[ny] := i; Inc(ny); end;
    end;
    if AItems[i].HideOverlap then
    begin
      hs[nh] := i;
      Inc(nh);
    end;
  end;
  SetLength(xs, nx);
  SetLength(ys, ny);
  SetLength(hs, nh);
  TyShiftLabelsOnXY(AItems, xs, 0, ALeft, ARight);
  TyShiftLabelsOnXY(AItems, ys, 1, ATop, ABottom);
  TyHideOverlapLabels(AItems, hs);
end;

end.
