unit tyControls.AdvChart.AxisName;
{$mode objfpc}{$H+}
{ TTyAdvanceChart -- where a cartesian axis' NAME goes.

  UPSTREAM'S AxisBuilder axisName, transcribed operation for operation. The
  name is laid out in its axis' own frame -- a group at the axis line,
  turned a quarter for a y axis -- at the end of the axis (the default), at
  its start, or in its middle beside the labels; its text is aligned by the
  side it stands on; a box padded by a margin table (or the author's) is
  put round it and taken through zrender's matrices to the screen; and it
  is then MOVED, along the way it points, until it clears what is in the
  way: for a middle name the band the labels occupy, for an end name each
  label of its own axis and then each label of the other axis.

  TWICE PER LAYOUT, as upstream does it: an estimate on the grid's raw rect,
  whose rect the grid's outer bounds are asked about, and the determination
  on the final rect, which is what is drawn. The margin level is each pass'
  own, so the two can differ.

  PURE: the measurer is the only window onto text. The move's collision is
  zrender's BoundingRect.intersect with a directional minimum translation,
  also transcribed; when either box is turned off the axes and the two
  overlap, upstream goes on to an oriented-box test this does not have, and
  the name is not moved. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.AdvChart.Layout,
  tyControls.AdvChart.JsMath;

{ upstream's remRadian: into [0, 2 pi), with JavaScript's exact remainder }
function TyRemRadian(ARadian: Double): Double;

{ zrender's BoundingRect.intersect(A, B, mtv, opt) with a direction, one
  way only, and a touch threshold: whether the two, each shrunk by the threshold,
  overlap -- and if they do, how far to move B along ADirection (radians,
  screen) to clear A. }
function TyRectIntersectDir(const A, B: TTyXYWH; ADirection,
  ATouchThreshold: Double; out AMtvX, AMtvY: Double): Boolean;

{ upstream's labelInfoList order: nearest the axis' origin first, along the
  axis, the tie kept in label order }
procedure TySortLabelGeoms(var AGeoms: TTyLabelGeomArray;
  const AFrame: TTyAxisNameFrame);

{ the name margin level of a pass: from the grid rect of THAT pass against
  the container -- an x axis' by the rect's height (0 or 1), a y axis' by
  its width (0 or 2) }
function TyAxisNameLevel(AHorizontal: Boolean; ARectW, ARectH,
  AContainerW, AContainerH: Double): Integer;

{ One axis' name on one pass. AOwn are its own shown labels and APerp the
  shown labels of every axis across it, each already sorted by its frame;
  APerpRotation is those axes' turn. }
function TyLayoutAxisName(const ASpec: TTyAxisLayoutSpec;
  const AFrame: TTyAxisNameFrame; ALevel: Integer;
  const AOwn: TTyLabelGeomArray; const APerp: array of TTyLabelGeomArray;
  APerpRotation: Double; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyAxisNamePlacement;

{ Every name of one grid on one pass, index-parallel to AAxes. Each axis'
  frame is its spec's NameFrame when the caller set one. }
function TyLayoutGridNames(const AAxes: TTyAxisLayoutSpecArray;
  const ARect: TTyRectF; AContainerW, AContainerH: Double;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): TTyAxisNamePlacementArray;

implementation

const
  cRadianEpsilon = 1e-4;
  { AxisBuilder's DEFAULT_*_NAME_MARGIN_LEVELS, [top, right, bottom, left] }
  cCenterMargins: array[0..2, 0..3] of Double =
    ((1, 2, 1, 2), (5, 3, 5, 3), (8, 3, 8, 3));
  cEndsMargins: array[0..2, 0..3] of Double =
    ((0, 1, 0, 1), (0, 3, 0, 3), (0, 3, 0, 3));

{ JavaScript's %: the exact remainder, the dividend's sign. Each subtraction
  is of a power-of-two multiple no more than twice the rest, which Sterbenz
  makes exact. }
function JsFMod(A, B: Double): Double;
var x, y: Double;
begin
  if IsNan(A) or IsNan(B) or IsInfinite(A) or (B = 0) then Exit(NaN);
  if IsInfinite(B) then Exit(A);
  B := Abs(B);
  x := Abs(A);
  if x < B then Exit(A);
  y := B;
  while y <= x / 2 do y := y * 2;
  while y >= B do
  begin
    if x >= y then x := x - y;
    y := y / 2;
  end;
  if A < 0 then Result := -x else Result := x;
end;

function TyRemRadian(ARadian: Double): Double;
var pi2: Double;
begin
  pi2 := Pi * 2;
  Result := JsFMod(JsFMod(ARadian, pi2) + pi2, pi2);
end;

function AroundZero(AValue: Double): Boolean;
begin
  Result := (AValue > -cRadianEpsilon) and (AValue < cRadianEpsilon);
end;

{ ==================== zrender's intersect ==================== }

type
  TIntersectCtx = record
    MinX, MinY: Double;
    MaxX, MaxY: Double;
    DirMinX, DirMinY: Double;
    Direction: Double;
    CheckX, CheckY: Double;
    LenMin: Double;
  end;

function NearZero(AValue: Double): Boolean;
begin
  Result := Abs(AValue) < 1e-10;
end;

procedure CalcDirMTV(var C: TIntersectCtx);
var squareMag, dirSin, dirCos, dotProd, tx, ty: Double;
begin
  squareMag := C.MinY * C.MinY + C.MinX * C.MinX;
  dirSin := TyJsSin(C.Direction);
  dirCos := TyJsCos(C.Direction);
  dotProd := dirSin * C.MinY + dirCos * C.MinX;
  if NearZero(dotProd) then
  begin
    if NearZero(C.MinX) and NearZero(C.MinY) then
    begin
      C.DirMinX := 0;
      C.DirMinY := 0;
    end;
    Exit;
  end;
  tx := squareMag * dirCos / dotProd;
  ty := squareMag * dirSin / dotProd;
  if NearZero(tx) and NearZero(ty) then
  begin
    C.DirMinX := 0;
    C.DirMinY := 0;
    Exit;
  end;
  { ONE WAY ONLY (bidirectional false): the translation must point along
    the direction, and be the shortest such }
  if (C.CheckX * tx + C.CheckY * ty > 0)
    and (Sqrt(tx * tx + ty * ty) < Sqrt(C.DirMinX * C.DirMinX + C.DirMinY * C.DirMinY)) then
  begin
    C.DirMinX := tx;
    C.DirMinY := ty;
  end;
end;

procedure IntersectOneDim(var C: TIntersectCtx; A0, A1, B0, B1: Double;
  AOnY: Boolean);
var d0, d1, dmin: Double;
begin
  d0 := Abs(A1 - B0);
  d1 := Abs(B1 - A0);
  dmin := Min(d0, d1);
  if (A1 < B0) or (B1 < A0) then
  begin
    if d0 < d1 then
    begin
      if AOnY then C.MaxY := -d0 else C.MaxX := -d0;
    end
    else if AOnY then C.MaxY := d1 else C.MaxX := d1;
  end
  else
  begin
    { with a direction every dimension is tried, both ways }
    C.LenMin := Min(dmin, C.LenMin);
    if AOnY then begin C.MinY := d0; C.MinX := 0; end
    else begin C.MinX := d0; C.MinY := 0; end;
    CalcDirMTV(C);
    if AOnY then begin C.MinY := -d1; C.MinX := 0; end
    else begin C.MinX := -d1; C.MinY := 0; end;
    CalcDirMTV(C);
  end;
end;

function TyRectIntersectDir(const A, B: TTyXYWH; ADirection,
  ATouchThreshold: Double; out AMtvX, AMtvY: Double): Boolean;
var
  C: TIntersectCtx;
  t, ax0, ax1, ay0, ay1, bx0, bx1, by0, by1: Double;
begin
  AMtvX := 0;
  AMtvY := 0;
  t := Max(Double(0), ATouchThreshold);
  C.MinX := Infinity;
  C.MinY := Infinity;
  C.MaxX := 0;
  C.MaxY := 0;
  C.DirMinX := Infinity;
  C.DirMinY := Infinity;
  C.Direction := ADirection;
  C.CheckX := TyJsCos(ADirection);
  C.CheckY := TyJsSin(ADirection);
  C.LenMin := Infinity;

  ax0 := A.X + t;
  ax1 := A.X + A.W - t;
  ay0 := A.Y + t;
  ay1 := A.Y + A.H - t;
  bx0 := B.X + t;
  bx1 := B.X + B.W - t;
  by0 := B.Y + t;
  by1 := B.Y + B.H - t;
  if (ax0 > ax1) or (ay0 > ay1) or (bx0 > bx1) or (by0 > by1) then
    Exit(False);
  Result := not ((ax1 < bx0) or (bx1 < ax0) or (ay1 < by0) or (by1 < ay0));
  IntersectOneDim(C, ax0, ax1, bx0, bx1, False);
  IntersectOneDim(C, ay0, ay1, by0, by1, True);
  if Result then
  begin
    AMtvX := C.DirMinX;
    AMtvY := C.DirMinY;
  end
  else
  begin
    AMtvX := C.MaxX;
    AMtvY := C.MaxY;
  end;
end;

{ ==================== the order of the labels ==================== }

procedure TySortLabelGeoms(var AGeoms: TTyLabelGeomArray;
  const AFrame: TTyAxisNameFrame);
var
  byX: Boolean;
  origin, ki, kj: Double;
  i, j: Integer;
  g: TTyLabelGeom;

  function Key(const AG: TTyLabelGeom): Double;
  begin
    if byX then Result := Abs(AG.X - origin) else Result := Abs(AG.Y - origin);
  end;

begin
  { dirVec = (cos -r, sin -r); sorted along whichever of x, y it runs }
  byX := Abs(TyJsCos(-AFrame.Rotation)) > 0.1;
  if byX then origin := AFrame.PosX else origin := AFrame.PosY;
  { stable, as V8's sort is }
  for i := 1 to High(AGeoms) do
  begin
    g := AGeoms[i];
    ki := Key(g);
    j := i - 1;
    while j >= 0 do
    begin
      kj := Key(AGeoms[j]);
      if kj - ki <= 0 then Break;
      AGeoms[j + 1] := AGeoms[j];
      Dec(j);
    end;
    AGeoms[j + 1] := g;
  end;
end;

function TyAxisNameLevel(AHorizontal: Boolean; ARectW, ARectH,
  AContainerW, AContainerH: Double): Integer;
begin
  if AHorizontal then
  begin
    if ARectH <= AContainerH * 0.5 then Result := 0 else Result := 1;
  end
  else if ARectW <= AContainerW * 0.5 then Result := 0
  else Result := 2;
end;

{ ==================== one name ==================== }

type
  TTextLayout = record
    Rotation: Double;
    H: TTyTextAnchorH;
    V: TTyTextAnchorV;
  end;

{ AxisBuilder.innerTextLayout -- a middle name }
function InnerTextLayout(AAxisRotation, ATextRotation: Double;
  ADirection: Integer): TTextLayout;
var diff: Double;
begin
  diff := TyRemRadian(ATextRotation - AAxisRotation);
  Result.Rotation := diff;
  if AroundZero(diff) then
  begin
    Result.H := tahCentre;
    if ADirection > 0 then Result.V := tavTop else Result.V := tavBottom;
  end
  else if AroundZero(diff - Pi) then
  begin
    Result.H := tahCentre;
    if ADirection > 0 then Result.V := tavBottom else Result.V := tavTop;
  end
  else
  begin
    Result.V := tavMiddle;
    if (diff > 0) and (diff < Pi) then
    begin
      if ADirection > 0 then Result.H := tahRight else Result.H := tahLeft;
    end
    else if ADirection > 0 then Result.H := tahLeft
    else Result.H := tahRight;
  end;
end;

{ AxisBuilder's endTextLayout -- a start or an end name }
function EndTextLayout(AAxisRotation: Double; ALocation: TTyAxisNameLocation;
  ATextRotation, AExt0, AExt1: Double): TTextLayout;
var
  diff: Double;
  inverse, onLeft: Boolean;
begin
  diff := TyRemRadian(ATextRotation - AAxisRotation);
  Result.Rotation := diff;
  inverse := AExt0 > AExt1;
  onLeft := ((ALocation = anlStart) and not inverse)
    or ((ALocation <> anlStart) and inverse);
  if AroundZero(diff - Pi / 2) then
  begin
    Result.H := tahCentre;
    if onLeft then Result.V := tavBottom else Result.V := tavTop;
  end
  else if AroundZero(diff - Pi * 1.5) then
  begin
    Result.H := tahCentre;
    if onLeft then Result.V := tavTop else Result.V := tavBottom;
  end
  else
  begin
    Result.V := tavMiddle;
    if (diff < Pi * 1.5) and (diff > Pi / 2) then
    begin
      if onLeft then Result.H := tahLeft else Result.H := tahRight;
    end
    else if onLeft then Result.H := tahRight
    else Result.H := tahLeft;
  end;
end;

{ labelLayoutApplyTranslation }
procedure Translate(var P: TTyAxisNamePlacement; ADX, ADY: Double);
begin
  P.X := P.X + ADX;
  P.Y := P.Y + ADY;
  P.M[4] := P.M[4] + ADX;
  P.M[5] := P.M[5] + ADY;
  P.Rect.X := P.Rect.X + ADX;
  P.Rect.Y := P.Rect.Y + ADY;
  P.MovedX := P.MovedX + ADX;
  P.MovedY := P.MovedY + ADY;
  Inc(P.Moves);
end;

{ moveIfOverlap: an obstacle that is turned off the axes goes to an
  oriented-box test upstream, which this does not have -- no move }
procedure MoveIfOverlap(const ARect: TTyXYWH; AAxisAligned: Boolean;
  var P: TTyAxisNamePlacement; ADirection: Double);
var mx, my: Double;
begin
  if not TyRectIntersectDir(ARect, P.Rect, ADirection, 0.05, mx, my) then Exit;
  if not (AAxisAligned and P.AxisAligned) then Exit;
  Translate(P, mx, my);
end;

{ moveIfOverlapByLinearLabels: far to near along the way the name moves }
procedure MoveByLinearLabels(const ALabels: TTyLabelGeomArray;
  ADirX, ADirY, AMoveX, AMoveY: Double; var P: TTyAxisNamePlacement;
  ADirection: Double);
var
  sameDir: Boolean;
  idx, n: Integer;
begin
  n := Length(ALabels);
  sameDir := AMoveX * ADirX + AMoveY * ADirY >= 0;
  for idx := 0 to n - 1 do
    if sameDir then
      MoveIfOverlap(ALabels[idx].Rect, ALabels[idx].AxisAligned, P, ADirection)
    else
      MoveIfOverlap(ALabels[n - 1 - idx].Rect, ALabels[n - 1 - idx].AxisAligned,
        P, ADirection);
end;

function TyLayoutAxisName(const ASpec: TTyAxisLayoutSpec;
  const AFrame: TTyAxisNameFrame; ALevel: Integer;
  const AOwn: TTyLabelGeomArray; const APerp: array of TTyLabelGeomArray;
  APerpRotation: Double; const AMeasurer: ITyTextMeasurer;
  APPI: Integer): TTyAxisNamePlacement;
var
  gap, s, px, py, mvX, mvY, nameRot, w, h, x0, y0, mm, direction: Double;
  mt, G, L, inv, lm: TTyMat2D;
  lay: TTextLayout;
  box, stOcc, lr: TTyXYWH;
  fontName: string;
  fontSize, fontWeight, i, j, k, q, lvl: Integer;
  order: array of Integer;
  haveOcc: Boolean;
begin
  Result := Default(TTyAxisNamePlacement);
  Result.Proportion := NaN;
  if (ASpec.Name = '') or (AMeasurer = nil) then Exit;
  Result.Shown := True;
  Result.Text := ASpec.Name;
  Result.Location := ASpec.NameLocation;
  lvl := ALevel;
  if lvl < 0 then lvl := 0;
  if lvl > 2 then lvl := 2;
  Result.Level := lvl;

  { THE ANCHOR in the axis' own frame, and the way a move goes }
  gap := AxisScaleF(ASpec.NameGapLogical, APPI);
  if AFrame.Inverse then s := -1 else s := 1;
  px := 0;
  py := 0;
  mvX := 0;
  mvY := 0;
  case ASpec.NameLocation of
    anlStart:
      begin
        px := AFrame.Ext0 - s * gap;
        mvX := -s;
      end;
    anlEnd:
      begin
        px := AFrame.Ext1 + s * gap;
        mvX := s;
      end;
  else
    px := (AFrame.Ext0 + AFrame.Ext1) / 2;
    py := AFrame.LabelOffset + AFrame.NameDirection * gap;
    mvY := AFrame.NameDirection;
  end;
  { rotate(identity, rotation), and Point.transform through it }
  mt := TyMatLocal(0, 0, AFrame.Rotation);
  lr.X := mt[0] * mvX + mt[2] * mvY + mt[4];
  lr.Y := mt[1] * mvX + mt[3] * mvY + mt[5];
  mvX := lr.X;
  mvY := lr.Y;

  { THE TEXT'S TURN AND ALIGNMENT }
  if ASpec.HasNameRotate then nameRot := ASpec.NameRotateRad
  else nameRot := NaN;
  if ASpec.NameLocation = anlMiddle then
  begin
    if ASpec.HasNameRotate then
      lay := InnerTextLayout(AFrame.Rotation, nameRot, AFrame.NameDirection)
    else
      lay := InnerTextLayout(AFrame.Rotation, AFrame.Rotation, AFrame.NameDirection);
  end
  else
  begin
    { `nameRotation || 0` }
    if ASpec.HasNameRotate and (not IsNan(nameRot)) and (nameRot <> 0) then
      lay := EndTextLayout(AFrame.Rotation, ASpec.NameLocation, nameRot,
        AFrame.Ext0, AFrame.Ext1)
    else
      lay := EndTextLayout(AFrame.Rotation, ASpec.NameLocation, 0,
        AFrame.Ext0, AFrame.Ext1);
  end;
  Result.AnchorH := lay.H;
  Result.AnchorV := lay.V;
  if ASpec.HasNameAlignH then Result.AnchorH := ASpec.NameAlignH;
  if ASpec.HasNameAlignV then Result.AnchorV := ASpec.NameAlignV;
  Result.LocalRotationRad := lay.Rotation;

  { THE MATRIX: the group's, then the text's inside it -- a text at its
    group's origin, unturned, takes the group's as it is }
  G := TyMatLocal(AFrame.PosX, AFrame.PosY, AFrame.Rotation);
  if (Abs(px) > 5e-5) or (Abs(py) > 5e-5) or (Abs(lay.Rotation) > 5e-5) then
  begin
    L := TyMatLocal(px, py, lay.Rotation);
    Result.M := TyMatMul(G, L);
  end
  else
    Result.M := G;

  { THE BOX, measured in the name's font }
  fontName := ASpec.NameFontName;
  fontSize := ASpec.NameFontSizeLogical;
  fontWeight := ASpec.NameFontWeight;
  if fontSize <= 0 then
  begin
    fontName := ASpec.FontName;
    fontSize := ASpec.FontSizeLogical;
    fontWeight := ASpec.FontWeight;
  end;
  AMeasurer.MeasureLine(ASpec.Name, fontName, fontSize, fontWeight, w, h);
  x0 := 0;
  case Result.AnchorH of
    tahRight: x0 := x0 - w;
    tahCentre: x0 := x0 - w / 2;
  end;
  y0 := 0;
  case Result.AnchorV of
    tavBottom: y0 := y0 - h;
    tavMiddle: y0 := y0 - h / 2;
  end;
  box := TyXYWH(x0, y0, w, h);

  { THE MARGIN: the level's, or the author's }
  case ASpec.NameMarginKind of
    nmkLevel:
      if ASpec.NameLocation = anlMiddle then
        Result.LocalRect := TyRectExpand(box, cCenterMargins[lvl][0],
          cCenterMargins[lvl][1], cCenterMargins[lvl][2], cCenterMargins[lvl][3])
      else
        Result.LocalRect := TyRectExpand(box, cEndsMargins[lvl][0],
          cEndsMargins[lvl][1], cEndsMargins[lvl][2], cEndsMargins[lvl][3]);
    nmkTextMargin:
      Result.LocalRect := TyRectExpand(box,
        AxisScaleF(ASpec.NameMargin[0], APPI), AxisScaleF(ASpec.NameMargin[1], APPI),
        AxisScaleF(ASpec.NameMargin[2], APPI), AxisScaleF(ASpec.NameMargin[3], APPI));
  else
    Result.LocalRect := box;
  end;
  Result.Rect := TyRectApplyMat(Result.LocalRect, Result.M);
  if ASpec.NameMarginKind = nmkMinMargin then
  begin
    mm := AxisScaleF(ASpec.NameMinMarginLogical, APPI) / 2;
    Result.Rect := TyRectExpand(Result.Rect, mm, mm, mm, mm);
  end;
  Result.PreRect := Result.Rect;
  Result.AxisAligned := TyMatAxisAligned(Result.M);
  Result.AnchorX := Result.M[4];
  Result.AnchorY := Result.M[5];
  Result.X := Result.M[4];
  Result.Y := Result.M[5];

  { A MIDDLE NAME'S OBSTACLE: the band the labels occupy, in the axis'
    frame, stretched to the line so the name never sits between the two --
    made whenever there is a label, moved from or not. United in the order
    the labels were LAID OUT, which upstream does before it sorts them. }
  if (ASpec.NameLocation = anlMiddle) and (Length(AOwn) > 0) then
  begin
    haveOcc := False;
    stOcc := TyXYWH(0, 0, 0, 0);
    if not TyMatInvert(G, inv) then inv := TyMatIdentity;
    SetLength(order, Length(AOwn));
    for k := 0 to High(AOwn) do
    begin
      j := k - 1;
      while (j >= 0) and (AOwn[order[j]].Index > AOwn[k].Index) do
      begin
        order[j + 1] := order[j];
        Dec(j);
      end;
      order[j + 1] := k;
    end;
    for q := 0 to High(order) do
    begin
      k := order[q];
      lm := TyMatMul(inv, AOwn[k].M);
      lr := TyRectApplyMat(AOwn[k].LocalRect, lm);
      if haveOcc then stOcc := TyRectUnion(stOcc, lr)
      else
      begin
        stOcc := lr;
        haveOcc := True;
      end;
    end;
    stOcc := TyRectUnion(stOcc, TyXYWH(Min(AFrame.Ext0, AFrame.Ext1), 0,
      Max(AFrame.Ext0, AFrame.Ext1) - Min(AFrame.Ext0, AFrame.Ext1), 1));
    Result.HasOccupied := True;
    Result.Occupied := stOcc;
  end;

  { THE MOVE }
  if not ASpec.NameNoMove then
  begin
    direction := TyJsAtan2(mvY, mvX);
    if ASpec.NameLocation = anlMiddle then
    begin
      if Result.HasOccupied then
        MoveIfOverlap(TyRectApplyMat(Result.Occupied, G), TyMatAxisAligned(G),
          Result, direction);
    end
    else
    begin
      MoveByLinearLabels(AOwn, TyJsCos(-AFrame.Rotation), TyJsSin(-AFrame.Rotation),
        mvX, mvY, Result, direction);
      for i := 0 to High(APerp) do
        MoveByLinearLabels(APerp[i], TyJsCos(-APerpRotation), TyJsSin(-APerpRotation),
          mvX, mvY, Result, direction);
    end;
  end;

  { decomposeTransform: where it is drawn and how turned }
  Result.RotationRad := -TyJsAtan2(Result.M[1], Result.M[0]);
  if ASpec.NameLocation = anlMiddle then Result.Proportion := 0.5;
end;

{ ==================== a grid's names ==================== }

function TyLayoutGridNames(const AAxes: TTyAxisLayoutSpecArray;
  const ARect: TTyRectF; AContainerW, AContainerH: Double;
  const AMeasurer: ITyTextMeasurer; APPI: Integer): TTyAxisNamePlacementArray;
var
  frames: array of TTyAxisNameFrame;
  geoms: array of TTyLabelGeomArray;
  perp: array of TTyLabelGeomArray;
  i, j, n: Integer;
  horiz: Boolean;
  perpRot: Double;
begin
  Result := nil;
  SetLength(Result, Length(AAxes));
  SetLength(frames, Length(AAxes));
  SetLength(geoms, Length(AAxes));
  { every axis' labels first, each in upstream's order }
  for i := 0 to High(AAxes) do
  begin
    if AAxes[i].HasNameFrame then frames[i] := AAxes[i].NameFrame
    else frames[i] := TyDefaultNameFrame(AAxes[i], ARect, APPI);
    geoms[i] := TyAxisLabelGeoms(AAxes[i], ARect, AMeasurer, APPI);
    TySortLabelGeoms(geoms[i], frames[i]);
  end;
  for i := 0 to High(AAxes) do
  begin
    Result[i].Proportion := NaN;
    if AAxes[i].Name = '' then Continue;
    horiz := AAxes[i].Side in [asTop, asBottom];
    { the axes across this one, in their own order }
    perp := nil;
    n := 0;
    perpRot := 0;
    for j := 0 to High(AAxes) do
      if (AAxes[j].Side in [asTop, asBottom]) <> horiz then
      begin
        SetLength(perp, n + 1);
        perp[n] := geoms[j];
        perpRot := frames[j].Rotation;
        Inc(n);
      end;
    if n = 0 then
    begin
      if horiz then perpRot := Pi / 2 else perpRot := 0;
    end;
    Result[i] := TyLayoutAxisName(AAxes[i], frames[i],
      TyAxisNameLevel(horiz, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top,
        AContainerW, AContainerH),
      geoms[i], perp, perpRot, AMeasurer, APPI);
  end;
end;

end.
