{ Part of tyControls.AdvanceChart (included, not a unit): the brush components, the
  selection they make, the toolbox's brush feature, and the parallel axes' area select and
  expansion. Moved out of the unit only to keep it readable; what the control is and why
  it is built the way it is, see the unit header. }

{ _onBrush: every cartesian of the panel's grid that the feature targets,
  its range in data (pointToData clamped, or the affine inverse), restricted
  to the hosting dataZoom's value spans, rounded to the precision the
  grid's pixels allow; pushed to the history; dispatched }
procedure TTyAdvanceChart.TbBrushEnd;
var
  snap: TTyTbSnapshot;
  keys: TTyStringArray;
  pa, pb: TTyDoubleArray;
  g, c, i, k, n: Integer;
  cart: TTyCartesian2D;
  ax: TTyAxis;
  dim: Integer;
  m: TTyMat2D;
  pt: TTyPointF;
  d0, d1: TTyDoubleArray;
  mm: array[0..1] of Double;
  t: Double;
  key: string;
  zoom: TTyAxisZoom;
  win: TTyDzWindow;
  host: Integer;
  s, px: Double;
  ext: TTyRange;
  prec: Double;
  r: TTyXYWH;

  function DevX(V: Double): Double;
  begin
    Result := FBuild.Viewport.Left + V * s;
  end;

  function DevY(V: Double): Double;
  begin
    Result := FBuild.Viewport.Top + V * s;
  end;

  procedure SetBatch(ADim: Integer; AAxis: TTyAxis; A, B: Double);
  var j: Integer;
  begin
    if AAxis = nil then Exit;
    if ADim = 0 then key := 'x' else key := 'y';
    key := key + IntToStr(AAxis.ComponentIndex);
    if TbSelIndexOf(key) < 0 then Exit;
    ext := AAxis.Scale.GetExtent;
    if ADim = 0 then px := r.W else px := r.H;
    prec := TyAcceptableTickPrecision(ext.Start, ext.Stop, px, 0.5);
    if not IsNan(prec) and not IsInfinite(prec) then
    begin
      A := TyTbRound(A, prec);
      B := TyTbRound(B, prec);
    end;
    for j := 0 to High(snap) do
      if snap[j].Key = key then
      begin
        snap[j].IsValue := True;
        snap[j].A := A;
        snap[j].B := B;
        Exit;
      end;
    j := Length(snap);
    SetLength(snap, j + 1);
    snap[j].Key := key;
    snap[j].IsValue := True;
    snap[j].A := A;
    snap[j].B := B;
  end;

begin
  snap := nil;
  g := FTbBrushGrid;
  if (FBuild = nil) or (g < 0) or (g >= FBuild.GridCount) then Exit;
  s := TbScale;
  r := DzGridRect(g);
  for c := 0 to FBuild.Grid(g).CartesianCount - 1 do
  begin
    cart := FBuild.Grid(g).CartesianByIndex(c);
    if cart = nil then Continue;
    { a cartesian whose x or y axis the feature targets }
    if (cart.AxisByDim('x') = nil) or (cart.AxisByDim('y') = nil) then Continue;
    if (TbSelIndexOf('x' + IntToStr(cart.AxisByDim('x').ComponentIndex)) < 0)
      and (TbSelIndexOf('y' + IntToStr(cart.AxisByDim('y').ComponentIndex)) < 0) then Continue;
    case FTbBrushType of
      tbbRect:
        begin
          if cart.InvTransform(m) then
          begin
            cart.PointToData(TyPointF(DevX(FTbRange[0]), DevY(FTbRange[2])), d0);
            cart.PointToData(TyPointF(DevX(FTbRange[1]), DevY(FTbRange[3])), d1);
          end
          else
          begin
            SetLength(d0, 2);
            SetLength(d1, 2);
            d0[0] := cart.AxisByDim('x').CoordToData(DevX(FTbRange[0]), True);
            d0[1] := cart.AxisByDim('y').CoordToData(DevY(FTbRange[2]), True);
            d1[0] := cart.AxisByDim('x').CoordToData(DevX(FTbRange[1]), True);
            d1[1] := cart.AxisByDim('y').CoordToData(DevY(FTbRange[3]), True);
          end;
          for dim := 0 to 1 do
          begin
            mm[0] := d0[dim];
            mm[1] := d1[dim];
            if mm[0] > mm[1] then
            begin
              t := mm[0];
              mm[0] := mm[1];
              mm[1] := t;
            end;
            if dim = 0 then SetBatch(0, cart.AxisByDim('x'), mm[0], mm[1])
            else SetBatch(1, cart.AxisByDim('y'), mm[0], mm[1]);
          end;
        end;
      tbbLineX, tbbLineY:
        begin
          if FTbBrushType = tbbLineX then
          begin
            ax := cart.AxisByDim('x');
            mm[0] := ax.CoordToData(DevX(FTbRange[0]), True);
            mm[1] := ax.CoordToData(DevX(FTbRange[1]), True);
            dim := 0;
          end
          else
          begin
            ax := cart.AxisByDim('y');
            mm[0] := ax.CoordToData(DevY(FTbRange[2]), True);
            mm[1] := ax.CoordToData(DevY(FTbRange[3]), True);
            dim := 1;
          end;
          if mm[0] > mm[1] then
          begin
            t := mm[0];
            mm[0] := mm[1];
            mm[1] := t;
          end;
          SetBatch(dim, ax, mm[0], mm[1]);
        end;
    end;
  end;
  if Length(snap) = 0 then Exit;
  { the windows before the first brush: each select dataZoom's percent range }
  n := Length(snap);
  SetLength(keys, n);
  SetLength(pa, n);
  SetLength(pb, n);
  for i := 0 to n - 1 do
  begin
    keys[i] := snap[i].Key;
    pa[i] := 0;
    pb[i] := 100;
    k := StrToIntDef(Copy(snap[i].Key, 2, MaxInt), 0);
    if Copy(snap[i].Key, 1, 1) = 'x' then
    begin
      if AxisZoom('xAxis', k, zoom, win, host) then
      begin
        pa[i] := win.Percent[0];
        pb[i] := win.Percent[1];
      end;
    end
    else if AxisZoom('yAxis', k, zoom, win, host) then
    begin
      pa[i] := win.Percent[0];
      pb[i] := win.Percent[1];
    end;
  end;
  TyTbHistoryPush(FTbHistory, snap, keys, pa, pb);
  { the dispatch's update renders the toolbox again (back's status) }
  TbDispatchZoom(snap);
end;

{ ==================== the brush components [Batch 126] ====================

  BrushModel / BrushView / the `brush` action over the pure
  tyControls.AdvChart.Brush. The model's areas and painting option live
  here by component index (a merge keeps them; a notMerge, and restore,
  make new models and views); each component's view is a
  TTyBrushController. A full update (Relayout) runs the visual stage's
  layoutCovers and every view's render; the `brush` action runs the same
  update synchronously, every view but the dispatching one ($from) laying
  its covers again; takeGlobalCursor sets the painting option. The
  pointer: zrender's Draggable on a cover's piece (MouseDown / MouseMove /
  MouseUp), the controllers' own handlers after the dataZoom's, the
  cursor in TbApplyCursor. brushSelect's dispatch goes through the
  throttle the first component asks for; what it carries (the selected
  data) is the next batch's, so it is only logged here. }

function TTyAdvanceChart.BrushViewOf: TTyBrushView;
begin
  Result.S := DzScale;
  if FBuild <> nil then
  begin
    Result.OX := FBuild.Viewport.Left;
    Result.OY := FBuild.Viewport.Top;
  end
  else
  begin
    Result.OX := FLastRect.Left;
    Result.OY := FLastRect.Top;
  end;
end;

procedure TTyAdvanceChart.BrushCss(AX, AY: Double; out X, Y: Double);
var v: TTyBrushView;
begin
  v := BrushViewOf;
  X := (AX - v.OX) / v.S;
  Y := (AY - v.OY) / v.S;
end;

{ the components the option has: each one's model from its option; the
  areas, the painting option and the view kept by index }
procedure TTyAdvanceChart.BrushSync;
var n, i, old: Integer;
begin
  n := FOption.ComponentCount('brush');
  old := Length(FBrushCtls);
  for i := n to old - 1 do BrushFreeCtl(FBrushCtls[i]);
  SetLength(FBrushCtls, n);
  for i := old to n - 1 do FBrushCtls[i] := nil;
  SetLength(FBrushSpecs, n);
  SetLength(FBrushAreas, n);
  SetLength(FBrushPaint, n);
  SetLength(FBrushHasPaint, n);
  for i := 0 to n - 1 do
  begin
    FBrushSpecs[i] := TyBrushSpecOf(FOption.ComponentAt('brush', i));
    if FBrushCtls[i] = nil then
    begin
      FBrushCtls[i] := TTyBrushController.Create;
      { isTargetByCursor's onIrrelevantElement [Batch 127] }
      FBrushCtls[i].IsIrrelevant := @BrushIrrelevant;
    end;
  end;
end;

procedure TTyAdvanceChart.BrushReset;
var i: Integer;
begin
  { a view disposed: its controller off (globalPan released) [Batch 127] }
  for i := 0 to High(FBrushCtls) do BrushFreeCtl(FBrushCtls[i]);
  FBrushCtls := nil;
  FBrushSpecs := nil;
  FBrushAreas := nil;
  FBrushPaint := nil;
  FBrushHasPaint := nil;
  FBrushDragOn := False;
  FBrushCursor := '';
end;

{ BrushTargetManager's grid targets: the grids of the x axes, then of the y
  axes, then the grids the finder names, each once; on each the cartesians
  whose x or y axis the finder names. A grid none of whose cartesians is
  named has no representative one -- upstream throws on its panel; here
  it is no target. }
function TTyAdvanceChart.BrushTargets(ABrush: Integer): TTyBrushTargetArray;
var
  fd: TJSONData;
  pf: TTyParsedFinder;
  xs, ys, gs, order, geos: TTyIntegerArray;
  r: TTyXYWH;
  s: Double;
  i, k, gb, c, n: Integer;
  ax: TTyAxis;
  cart: TTyCartesian2D;
  t: TTyBrushTarget;

  procedure AddGrid(AComp: Integer);
  var q: Integer;
  begin
    if AComp < 0 then Exit;
    for q := 0 to High(order) do
      if order[q] = AComp then Exit;
    SetLength(order, Length(order) + 1);
    order[High(order)] := AComp;
  end;

  function Has(const A: TTyIntegerArray; V: Integer): Boolean;
  var q: Integer;
  begin
    for q := 0 to High(A) do
      if A[q] = V then Exit(True);
    Result := False;
  end;

begin
  Result := nil;
  if (FBuild = nil) or (ABrush < 0) or (ABrush > High(FBrushSpecs)) then Exit;
  if FBrushSpecs[ABrush].Finder = '' then Exit;
  fd := GetJSON(FBrushSpecs[ABrush].Finder);
  try
    pf := TyParseFinder(fd, FOption.Keys);
  finally
    fd.Free;
  end;
  xs := TyFinderModels(pf, 'xAxis');
  ys := TyFinderModels(pf, 'yAxis');
  gs := TyFinderModels(pf, 'grid');
  geos := TyFinderModels(pf, 'geo');
  order := nil;
  for i := 0 to High(xs) do
  begin
    ax := DzAxis('x', xs[i]);
    if ax <> nil then AddGrid(ax.GridIndex);
  end;
  for i := 0 to High(ys) do
  begin
    ax := DzAxis('y', ys[i]);
    if ax <> nil then AddGrid(ax.GridIndex);
  end;
  for i := 0 to High(gs) do AddGrid(gs[i]);
  for k := 0 to High(order) do
  begin
    gb := -1;
    for i := 0 to FBuild.GridCount - 1 do
      if FBuild.Grid(i).ComponentIndex = order[k] then
      begin
        gb := i;
        Break;
      end;
    if gb < 0 then Continue;
    t := Default(TTyBrushTarget);
    for c := 0 to FBuild.Grid(gb).CartesianCount - 1 do
    begin
      cart := FBuild.Grid(gb).CartesianByIndex(c);
      if cart = nil then Continue;
      if ((cart.AxisByDim('x') <> nil) and Has(xs, cart.AxisByDim('x').ComponentIndex))
        or ((cart.AxisByDim('y') <> nil) and Has(ys, cart.AxisByDim('y').ComponentIndex)) then
      begin
        n := Length(t.Carts);
        SetLength(t.Carts, n + 1);
        t.Carts[n] := cart;
      end;
    end;
    if Length(t.Carts) = 0 then Continue;
    t.PanelId := 'grid--' + ComponentModelId('grid', order[k]);
    t.GridComponent := order[k];
    t.Grid := gb;
    t.GeoComponent := -1;
    t.Rect := DzGridRect(gb);
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n] := t;
  end;
  { THE GEOS the finder names [Batch 152]: the panel the data rect through
    the overall matrix, in the brush's CSS px }
  s := DzScale;
  for k := 0 to High(geos) do
  begin
    if (geos[k] < 0) or (geos[k] > High(FGeos)) or (FGeos[geos[k]] = nil)
      or not FGeos[geos[k]].Valid then Continue;
    t := Default(TTyBrushTarget);
    t.PanelId := 'geo--' + ComponentModelId('geo', geos[k]);
    t.GridComponent := -1;
    t.Grid := -1;
    t.GeoComponent := geos[k];
    t.Geo := FGeos[geos[k]];
    r := FGeos[geos[k]].OverallRect;
    t.Rect.X := (r.X - BrushViewOf.OX) / s;
    t.Rect.Y := (r.Y - BrushViewOf.OY) / s;
    t.Rect.W := r.W / s;
    t.Rect.H := r.H / s;
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n] := t;
  end;
end;

{ findTargetInfo: by the area's panelId when it has one, else by the grid
  its finder reaches (its grid, its x axis' grid, its y axis'); -1 is
  `true`, the global panel }
function TTyAdvanceChart.BrushFindTarget(const ATargets: TTyBrushTargetArray;
  const AArea: TTyBrushArea): Integer;
var
  i, gm, x: Integer;
  fd: TJSONData;
  pf: TTyParsedFinder;
  ax: TTyAxis;
begin
  Result := -1;
  if AArea.Opt.HasPanel and (AArea.Opt.PanelId <> '') then
  begin
    for i := 0 to High(ATargets) do
      if ATargets[i].PanelId = AArea.Opt.PanelId then Exit(i);
    Exit;
  end;
  if AArea.Finder = '' then Exit;
  fd := GetJSON(AArea.Finder);
  try
    pf := TyParseFinder(fd, FOption.Keys);
  finally
    fd.Free;
  end;
  { targetInfoMatchers' geo: the area's geo }
  x := TyFinderModel(pf, 'geo');
  if x >= 0 then
  begin
    for i := 0 to High(ATargets) do
      if ATargets[i].GeoComponent = x then Exit(i);
  end;
  gm := TyFinderModel(pf, 'grid');
  if gm < 0 then
  begin
    x := TyFinderModel(pf, 'xAxis');
    if x >= 0 then
    begin
      ax := DzAxis('x', x);
      if ax <> nil then gm := ax.GridIndex;
    end;
  end;
  if gm < 0 then
  begin
    x := TyFinderModel(pf, 'yAxis');
    if x >= 0 then
    begin
      ax := DzAxis('y', x);
      if ax <> nil then gm := ax.GridIndex;
    end;
  end;
  if gm < 0 then Exit;
  for i := 0 to High(ATargets) do
    if (ATargets[i].GridComponent = gm) and (ATargets[i].Geo = nil) then Exit(i);
end;

{ setInputRanges: every area bound to a target takes its panel, and its
  range from its coordRange -- back through dataToPoint, less the offset
  of the round trip at the size ratio }
{ coordConvert on a target: a grid's cartesian AIndex, or [Batch 152] a
  geo's dataToPoint / pointToData -- a rect by its two corners, a polygon
  by its points (a geo has no axis: no lineX, no lineY) }
function TTyAdvanceChart.BrushConvertOn(const ATarget: TTyBrushTarget; AIndex: Integer;
  AType: TTyBrushType; AToData: Boolean; const AView: TTyBrushView;
  const ARange: TTyBrushRange; AClamp: Boolean; out AValues, AXYMinMax: TTyBrushRange): Boolean;
var
  geo: TTyGeo;
  i: Integer;
  a, b: TTyBrushPair;
  mask: TFPUExceptionMask;

  function Conv(AX, AY: Double): TTyBrushPair;
  var p: TTyPointF; d: TTyGeoPt;
  begin
    Result[0] := NaN;
    Result[1] := NaN;
    if AToData then
    begin
      if geo.DataOf(AView.OX + AX * AView.S, AView.OY + AY * AView.S, d) then
      begin
        Result[0] := d.X;
        Result[1] := d.Y;
      end;
    end
    else if geo.PointOf(AX, AY, p) then
    begin
      Result[0] := (p.X - AView.OX) / AView.S;
      Result[1] := (p.Y - AView.OY) / AView.S;
    end;
  end;

  function Mm(A, B: Double): TTyBrushPair;
  begin
    if A > B then
    begin
      Result[0] := B;
      Result[1] := A;
    end
    else
    begin
      Result[0] := A;
      Result[1] := B;
    end;
  end;

begin
  AValues := nil;
  AXYMinMax := nil;
  if ATarget.Geo = nil then
  begin
    Result := (AIndex >= 0) and (AIndex <= High(ATarget.Carts))
      and TyBrushConvert(AType, AToData, ATarget.Carts[AIndex], AView, ARange, AClamp,
        AValues, AXYMinMax);
    Exit;
  end;
  Result := False;
  geo := TTyGeo(ATarget.Geo);
  mask := GeoMaskFpu;
  try
    case AType of
      btRect:
        begin
          if Length(ARange) < 2 then Exit;
          a := Conv(ARange[0][0], ARange[1][0]);
          b := Conv(ARange[0][1], ARange[1][1]);
          SetLength(AValues, 2);
          AValues[0] := Mm(a[0], b[0]);
          AValues[1] := Mm(a[1], b[1]);
          AXYMinMax := Copy(AValues);
          Result := True;
        end;
      btPolygon:
        begin
          SetLength(AValues, Length(ARange));
          SetLength(AXYMinMax, 2);
          AXYMinMax[0][0] := Infinity;
          AXYMinMax[0][1] := NegInfinity;
          AXYMinMax[1][0] := Infinity;
          AXYMinMax[1][1] := NegInfinity;
          for i := 0 to High(ARange) do
          begin
            a := Conv(ARange[i][0], ARange[i][1]);
            AXYMinMax[0][0] := Math.Min(AXYMinMax[0][0], a[0]);
            AXYMinMax[1][0] := Math.Min(AXYMinMax[1][0], a[1]);
            AXYMinMax[0][1] := Math.Max(AXYMinMax[0][1], a[0]);
            AXYMinMax[1][1] := Math.Max(AXYMinMax[1][1], a[1]);
            AValues[i] := a;
          end;
          Result := True;
        end;
    end;
  finally
    GeoUnmaskFpu(mask);
  end;
end;

procedure TTyAdvanceChart.BrushLayout(ABrush: Integer);
var
  tg: TTyBrushTargetArray;
  i, t: Integer;
  vals, xy: TTyBrushRange;
  sx, sy: Double;
  a: TTyBrushArea;
  v: TTyBrushView;
begin
  if (ABrush < 0) or (ABrush > High(FBrushAreas)) then Exit;
  tg := BrushTargets(ABrush);
  v := BrushViewOf;
  for i := 0 to High(FBrushAreas[ABrush]) do
  begin
    a := FBrushAreas[ABrush][i];
    t := BrushFindTarget(tg, a);
    if not a.Opt.HasRange then
    begin
      a.Opt.HasRange := True;
      a.Opt.Range := nil;
    end;
    if t >= 0 then
    begin
      a.Opt.HasPanel := True;
      a.Opt.PanelId := tg[t].PanelId;
      if a.HasCoordRange and BrushConvertOn(tg[t], 0, a.Opt.BrushType, False, v,
        a.CoordRange, False, vals, xy) then
      begin
        if a.HasOffset then
        begin
          TyBrushScales(xy, a.OffsetXY, sx, sy);
          a.Opt.Range := TyBrushDiff(a.Opt.BrushType, vals, a.Offset, sx, sy);
        end
        else
          a.Opt.Range := vals;
      end;
    end;
    FBrushAreas[ABrush][i] := a;
  end;
end;

{ BrushView._updateController: the panels, the painting option, the covers
  from the model's areas }
procedure TTyAdvanceChart.BrushRender(ABrush: Integer; ARepaint: Boolean);
var
  tg: TTyBrushTargetArray;
  pn: array of TTyBrushPanel;
  i: Integer;
  ctl: TTyBrushController;
  cfg: TTyBrushOptArray;
  off: TTyBrushOpt;
  s: Double;
begin
  if (ABrush < 0) or (ABrush > High(FBrushCtls)) or (FBrushCtls[ABrush] = nil) then Exit;
  ctl := FBrushCtls[ABrush];
  s := DzScale;
  ctl.CanvasW := (FLastRect.Right - FLastRect.Left) / s;
  ctl.CanvasH := (FLastRect.Bottom - FLastRect.Top) / s;
  tg := BrushTargets(ABrush);
  SetLength(pn, Length(tg));
  for i := 0 to High(tg) do
  begin
    pn[i].Id := tg[i].PanelId;
    pn[i].Rect := tg[i].Rect;
    pn[i].DefaultType := btRect;
    pn[i].GridComponent := tg[i].GridComponent;
  end;
  ctl.SetPanels(pn, Length(pn) > 0);
  { through the globalPan mutex [Batch 127] }
  if FBrushHasPaint[ABrush] then BrushEnableCtl(ctl, FBrushPaint[ABrush], False)
  else
  begin
    { a model's brushOption starts empty: no type, drawing off }
    off := TyBrushDefaultOpt;
    off.BrushType := btNone;
    BrushEnableCtl(ctl, off, False);
  end;
  SetLength(cfg, Length(FBrushAreas[ABrush]));
  for i := 0 to High(cfg) do cfg[i] := FBrushAreas[ABrush][i].Opt;
  ctl.UpdateCovers(cfg);
  { inside a paint's layout the list is built next anyway }
  if ARepaint then BrushChanged;
end;

procedure TTyAdvanceChart.BrushPass;
var b: Integer;
begin
  BrushSync;
  for b := 0 to High(FBrushSpecs) do BrushLayout(b);
  for b := 0 to High(FBrushSpecs) do BrushRender(b, False);
end;

{ setOutputRanges: an area on a target gets coordRanges (one per cartesian
  of the target), coordRange the first of them, and __rangeOffset -- the
  first's way back to pixels less the range }
function TTyAdvanceChart.BrushOutput(ABrush: Integer;
  const AAreas: TTyBrushAreaArray): TTyBrushAreaArray;
var
  tg: TTyBrushTargetArray;
  i, t, c, n: Integer;
  vals, xy, back, bxy: TTyBrushRange;
  v: TTyBrushView;
begin
  Result := Copy(AAreas);
  tg := BrushTargets(ABrush);
  v := BrushViewOf;
  for i := 0 to High(Result) do
  begin
    t := BrushFindTarget(tg, Result[i]);
    if t < 0 then Continue;
    for c := 0 to Max(High(tg[t].Carts), Ord(tg[t].Geo <> nil) - 1) do
    begin
      if not BrushConvertOn(tg[t], c, Result[i].Opt.BrushType, True, v,
        Result[i].Opt.Range, True, vals, xy) then Continue;
      Result[i].HasCoordRanges := True;
      n := Length(Result[i].CoordRanges);
      SetLength(Result[i].CoordRanges, n + 1);
      Result[i].CoordRanges[n] := vals;
      if not Result[i].HasCoordRange then
      begin
        Result[i].HasCoordRange := True;
        Result[i].CoordRange := vals;
        if BrushConvertOn(tg[t], c, Result[i].Opt.BrushType, False, v, vals,
          False, back, bxy) then
        begin
          Result[i].HasOffset := True;
          Result[i].Offset := TyBrushDiff(Result[i].Opt.BrushType, back,
            Result[i].Opt.Range, 1, 1);
          Result[i].OffsetXY := bxy;
        end;
      end;
    end;
  end;
end;

{ BrushView._onBrush: the areas in data too; the `brush` action unless it
  is a drag's end (a removeOnClick clearing is dispatched), then brushEnd
  at an end }
procedure TTyAdvanceChart.BrushOnTrigger(ABrush: Integer; const ATrig: TTyBrushTrigger);
var
  areas: TTyBrushAreaArray;
  id, js: string;
begin
  if not ATrig.Fired then Exit;
  if (ABrush < 0) or (ABrush > High(FBrushSpecs)) then Exit;
  areas := BrushOutput(ABrush, ATrig.Areas);
  if not ATrig.IsEnd or ATrig.RemoveOnClick then BrushApplyOwn(ABrush, areas);
  if ATrig.IsEnd then
  begin
    id := ComponentModelId('brush', ABrush);
    { update 'none': the event alone }
    js := '{"type":"brushend","brushId":' + TyBrushJsonStr(id) + ',"areas":'
      + TyBrushAreasJson(areas) + ',"$from":' + TyBrushJsonStr(id) + '}';
    BrushLogEvent('brushend', ABrush, True, areas, js);
    EmitPayloadEvent('brushend', js);
  end;
  BrushChanged;
end;

{ the `brush` action from a brush's own view: setAreas on it, the update
  (updateVisual: layoutCovers, every other view's covers), the event }
procedure TTyAdvanceChart.BrushApplyOwn(ABrush: Integer; const AAreas: TTyBrushAreaArray);
var
  i, b: Integer;
  id, js: string;
begin
  SetLength(FBrushAreas[ABrush], Length(AAreas));
  for i := 0 to High(AAreas) do
    FBrushAreas[ABrush][i] := TyBrushAreaOfOutput(FBrushSpecs[ABrush], AAreas[i]);
  Inc(FBrushActDepth);
  try
    if FBuild <> nil then
    begin
      for b := 0 to High(FBrushSpecs) do BrushLayout(b);
      for b := 0 to High(FBrushSpecs) do
        if b <> ABrush then BrushRender(b);
    end;
    { the visual stage: the selection, its visuals, brushSelect [Batch 127] }
    BrushSelectRun(True);
    id := ComponentModelId('brush', ABrush);
    js := '{"type":"brush","brushId":' + TyBrushJsonStr(id) + ',"areas":'
      + TyBrushAreasJson(AAreas) + ',"$from":' + TyBrushJsonStr(id) + '}';
    BrushLogEvent('brush', ABrush, True, AAreas, js);
    EmitPayloadEvent('brush', js);
  finally
    Dec(FBrushActDepth);
  end;
  if FBrushActDepth = 0 then BrushFlush;
  EmitUpdated;
end;

{ the brush components an action's payload names (brushIndex, else
  brushId, else brushName); none named: all of them }
function TTyAdvanceChart.BrushQuery(APayload: TJSONObject): TTyIntegerArray;
var
  d: TJSONData;
  i, k, n: Integer;
  s: string;
  hit: Boolean;

  procedure Add(AIndex: Integer);
  var q: Integer;
  begin
    if (AIndex < 0) or (AIndex > High(FBrushSpecs)) then Exit;
    for q := 0 to High(Result) do
      if Result[q] = AIndex then Exit;
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n] := AIndex;
  end;

  function Matches(AData: TJSONData; const AText: string): Boolean;
  var q: Integer;
  begin
    Result := False;
    if AData is TJSONArray then
    begin
      for q := 0 to AData.Count - 1 do
        if (AData.Items[q].JSONType = jtString) and (AData.Items[q].AsString = AText) then
          Exit(True);
    end
    else if AData.JSONType = jtString then Result := AData.AsString = AText
    else if AData.JSONType = jtNumber then Result := TyJsNumberToString(AData.AsFloat) = AText;
  end;

begin
  Result := nil;
  d := APayload.Find('brushIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    if d is TJSONArray then
    begin
      for i := 0 to d.Count - 1 do
        if d.Items[i].JSONType = jtNumber then Add(Trunc(d.Items[i].AsFloat));
    end
    else if d.JSONType = jtNumber then Add(Trunc(d.AsFloat));
    Exit;
  end;
  d := APayload.Find('brushId');
  if (d = nil) or (d.JSONType = jtNull) then d := nil;
  if d <> nil then
  begin
    for k := 0 to High(FBrushSpecs) do
      if Matches(d, ComponentModelId('brush', k)) then Add(k);
    Exit;
  end;
  d := APayload.Find('brushName');
  if (d <> nil) and (d.JSONType <> jtNull) then
  begin
    for k := 0 to High(FBrushSpecs) do
    begin
      s := ComponentModelName('brush', k);
      hit := Matches(d, s);
      if hit then Add(k);
    end;
    Exit;
  end;
  for k := 0 to High(FBrushSpecs) do Add(k);
end;

{ the `brush` action from the API: setAreas on the components it names
  (areas absent: the areas stay), the update, the event with the payload }
procedure TTyAdvanceChart.BrushDoAction(APayload: TJSONObject);
var
  sel: TTyIntegerArray;
  node, fromN: TJSONData;
  parsed, logged: TTyBrushAreaArray;
  b, i, n: Integer;
  a: TTyBrushArea;
  hasFrom: Boolean;
  from, js: string;
begin
  BrushSync;
  sel := BrushQuery(APayload);
  node := APayload.Find('areas');
  logged := nil;
  if node is TJSONArray then
    for b := 0 to High(sel) do
    begin
      parsed := nil;
      for i := 0 to node.Count - 1 do
        if (node.Items[i] is TJSONObject)
          and TyBrushAreaOfJson(FBrushSpecs[sel[b]], TJSONObject(node.Items[i]), a) then
        begin
          n := Length(parsed);
          SetLength(parsed, n + 1);
          parsed[n] := a;
        end;
      FBrushAreas[sel[b]] := parsed;
      if b = 0 then logged := Copy(parsed);
    end;
  fromN := APayload.Find('$from');
  hasFrom := (fromN <> nil) and (fromN.JSONType = jtString);
  if hasFrom then from := fromN.AsString else from := '';
  if FBuild <> nil then
  begin
    for b := 0 to High(FBrushSpecs) do BrushLayout(b);
    { a view the action came from keeps its covers }
    for b := 0 to High(FBrushSpecs) do
      if not (hasFrom and (from = ComponentModelId('brush', b))) then BrushRender(b);
  end;
  { the visual stage: the selection, its visuals, brushSelect [Batch 127] }
  BrushSelectRun(True);
  js := TbEventJson(APayload, 'brush');
  BrushLogEvent('brush', -1, False, logged, js);
  EmitPayloadEvent('brush', js);
  BrushChanged;
end;

procedure TTyAdvanceChart.BrushDoEnd(APayload: TJSONObject);
var js: string;
begin
  js := TbEventJson(APayload, 'brushend');
  BrushLogEvent('brushend', -1, False, nil, js);
  EmitPayloadEvent('brushend', js);
end;

{ brushVisual's setBrushOption on takeGlobalCursor: the payload's
  brushOption for the key 'brush', brushType false for any other; then the
  update renders every view }
procedure TTyAdvanceChart.BrushTakeCursor(APayload: TJSONObject);
var
  d, bo: TJSONData;
  isBrush: Boolean;
  b: Integer;
  off: TTyBrushOpt;
begin
  BrushSync;
  if Length(FBrushSpecs) = 0 then Exit;
  d := APayload.Find('key');
  isBrush := (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'brush');
  bo := APayload.Find('brushOption');
  for b := 0 to High(FBrushSpecs) do
  begin
    if isBrush then
    begin
      { no brushOption: upstream's generateBrushOption answers undefined
        and the update throws; the painting option stays }
      if not (bo is TJSONObject) then Continue;
      FBrushPaint[b] := TyBrushPaintOpt(FBrushSpecs[b], bo);
    end
    else
    begin
      off := TyBrushPaintOpt(FBrushSpecs[b], nil);
      off.BrushType := btNone;
      FBrushPaint[b] := off;
    end;
    FBrushHasPaint[b] := True;
  end;
  if FBuild <> nil then
  begin
    for b := 0 to High(FBrushSpecs) do BrushLayout(b);
    for b := 0 to High(FBrushSpecs) do BrushRender(b);
  end;
  { brushSelect: TbDoTakeCursor's, with or without a brush [Batch 127] }
end;

procedure TTyAdvanceChart.BrushLogEvent(const AType: string; ABrush: Integer;
  AFromSelf: Boolean; const AAreas: TTyBrushAreaArray; const APayload: string);
var n: Integer;
begin
  n := Length(FBrushEvLog);
  SetLength(FBrushEvLog, n + 1);
  FBrushEvLog[n].EventType := AType;
  FBrushEvLog[n].Brush := ABrush;
  FBrushEvLog[n].FromSelf := AFromSelf;
  FBrushEvLog[n].Areas := Copy(AAreas);
  FBrushEvLog[n].Payload := APayload;
end;

function TTyAdvanceChart.BrushClock: Double;
begin
  if IsNan(FBrushNow) then Result := GetTickCount64 else Result := FBrushNow;
end;

{ brushVisual's dispatch of brushSelect: through the throttle the first
  component asks for (createOrUpdate), with every component's areas. Not
  during a brushSelect of its own. }
procedure TTyAdvanceChart.BrushVisual(const ABatch: TTyBrushSelectBatch);
var
  batch: TTyBrushSelectBatch;
  n: Integer;
  now_, due: Double;
  execNow, thr: Boolean;
begin
  if FBrushInSelect then Exit;
  batch := ABatch;
  now_ := BrushClock;
  { only the first component's throttle; none without a brush (an empty
    batch, dispatched at once) [Batch 127] }
  if Length(FBrushSpecs) > 0 then
    thr := TyBrushThrottleConfigure(FBrushThr, FBrushSpecs[0].ThrottleKind,
      FBrushSpecs[0].ThrottleType, FBrushSpecs[0].ThrottleDelay)
  else
    thr := TyBrushThrottleConfigure(FBrushThr, btkNone, '', NaN);
  if not thr then
  begin
    BrushExecSelect(batch, now_);
    Exit;
  end;
  { the call's clearTimeout }
  BrushDropPending(FBrushThr.Timer);
  FBrushThr.Timer := 0;
  TyBrushThrottleCall(FBrushThr, now_, execNow, due);
  if execNow then
  begin
    FBrushThr.LastExec := now_;
    BrushExecSelect(batch, now_);
    Exit;
  end;
  Inc(FBrushPendSeq);
  n := Length(FBrushPend);
  SetLength(FBrushPend, n + 1);
  FBrushPend[n].Id := FBrushPendSeq;
  FBrushPend[n].Due := due;
  FBrushPend[n].Gen := FBrushThr.Gen;
  FBrushPend[n].Batch := batch;
  FBrushThr.Timer := FBrushPendSeq;
  BrushArmTimer;
end;

procedure TTyAdvanceChart.BrushExecSelect(const ABatch: TTyBrushSelectBatch; ATime: Double);
var n: Integer;
begin
  FBrushInSelect := True;
  try
    n := Length(FBrushSelLog);
    SetLength(FBrushSelLog, n + 1);
    FBrushSelLog[n].Time := ATime;
    FBrushSelLog[n].Batch := ABatch;
    { the brushSelect action: its brushselected event, after the event of
      the action whose update dispatched it [Batch 127] -- [F4b] inside an
      action, in the one queue of what that action dispatched, in order }
    if FBatchDefer > 0 then
    begin
      { a batch's items: the update runs once, so does its brushSelect --
        the last state's }
      FBatchBrushJson := BrushSelectedJson(ABatch);
      FBatchBrushHas := True;
    end
    else if FActCycle > 0 then
    begin
      n := Length(FActPending);
      SetLength(FActPending, n + 1);
      FActPending[n] := Default(TTyTipAct);
      FActPending[n].EventJson := BrushSelectedJson(ABatch);
      FBatchBrushQueued := True;
    end
    else
    begin
      n := Length(FBrushEmitQ);
      SetLength(FBrushEmitQ, n + 1);
      FBrushEmitQ[n] := BrushSelectedJson(ABatch);
    end;
  finally
    FBrushInSelect := False;
  end;
end;

procedure TTyAdvanceChart.BrushDropPending(AId: Integer);
var i, k: Integer;
begin
  if AId = 0 then Exit;
  for i := 0 to High(FBrushPend) do
    if FBrushPend[i].Id = AId then
    begin
      for k := i to High(FBrushPend) - 1 do FBrushPend[k] := FBrushPend[k + 1];
      SetLength(FBrushPend, Length(FBrushPend) - 1);
      Exit;
    end;
end;

procedure TTyAdvanceChart.BrushTick(ANow: Double);
var
  best, i, k: Integer;
  t: Double;
  p: TTyBrushPending;
begin
  repeat
    best := -1;
    for i := 0 to High(FBrushPend) do
      if (FBrushPend[i].Due <= ANow) and ((best < 0)
        or (FBrushPend[i].Due < FBrushPend[best].Due)
        or ((FBrushPend[i].Due = FBrushPend[best].Due) and (FBrushPend[i].Id < FBrushPend[best].Id))) then
        best := i;
    if best < 0 then Break;
    p := FBrushPend[best];
    for k := best to High(FBrushPend) - 1 do FBrushPend[k] := FBrushPend[k + 1];
    SetLength(FBrushPend, Length(FBrushPend) - 1);
    { the clock is the timer's due, unless it is behind the last tick }
    t := p.Due;
    if not IsNan(FBrushTickPrev) and (FBrushTickPrev > t) then t := FBrushTickPrev;
    if p.Gen = FBrushThr.Gen then
    begin
      FBrushThr.LastExec := t;
      FBrushThr.Timer := 0;
    end;
    BrushExecSelect(p.Batch, t);
  until False;
  FBrushTickPrev := ANow;
  BrushArmTimer;
  { a timer's brushSelect is an action of its own [Batch 127] }
  if FBrushActDepth = 0 then BrushFlush;
end;

procedure TTyAdvanceChart.BrushArmTimer;
var
  i: Integer;
  due: Double;
begin
  { a test drives the clock itself }
  if not IsNan(FBrushNow) then Exit;
  if Length(FBrushPend) = 0 then
  begin
    if FBrushTimer <> nil then FBrushTimer.Enabled := False;
    Exit;
  end;
  due := FBrushPend[0].Due;
  for i := 1 to High(FBrushPend) do due := Math.Min(due, FBrushPend[i].Due);
  if FBrushTimer = nil then
  begin
    FBrushTimer := TTimer.Create(nil);
    FBrushTimer.OnTimer := @BrushTimerFired;
  end;
  FBrushTimer.Enabled := False;
  FBrushTimer.Interval := Math.Max(1, Ceil(due - BrushClock));
  FBrushTimer.Enabled := True;
end;

procedure TTyAdvanceChart.BrushTimerFired(Sender: TObject);
begin
  FBrushTimer.Enabled := False;
  BrushTick(BrushClock);
end;

{ the topmost cover piece the pointer finds (device px): the brush views'
  groups in component order, the later over the earlier; nothing outside
  the canvas }
function TTyAdvanceChart.BrushPieceAt(AX, AY: Integer; out ABrush, AIndex: Integer;
  out APiece: TTyBrushPiece): Boolean;
var
  b: Integer;
  x, y, s: Double;
begin
  Result := False;
  ABrush := -1;
  AIndex := -1;
  APiece := bpMain;
  if (csDesigning in ComponentState)
    or ((Length(FBrushCtls) = 0) and (Length(FParBrushCtls) = 0)) then Exit;
  BrushCss(AX, AY, x, y);
  s := DzScale;
  if (x < 0) or (y < 0) or (x > (FLastRect.Right - FLastRect.Left) / s)
    or (y > (FLastRect.Bottom - FLastRect.Top) / s) then Exit;
  for b := High(FBrushCtls) downto 0 do
    if (FBrushCtls[b] <> nil) and FBrushCtls[b].PieceAt(x, y, AIndex, APiece) then
    begin
      ABrush := b;
      Exit(True);
    end;
  { the parallel axes' groups, under the brush views' [Batch 130] }
  for b := High(FParBrushCtls) downto 0 do
    if (FParBrushCtls[b] <> nil) and FParBrushCtls[b].PieceAt(x, y, AIndex, APiece) then
    begin
      ABrush := TyParallelBrushBase + b;
      Exit(True);
    end;
end;

{ zrender's Draggable takes a press on a piece (dragstart); the
  controllers' own mousedown still runs -- on a draggable target it only
  ends a track a lost release left }
function TTyAdvanceChart.BrushDragStart(AX, AY: Integer): Boolean;
var
  b, i: Integer;
  pc: TTyBrushPiece;
  x, y: Double;
begin
  Result := BrushPieceAt(AX, AY, b, i, pc);
  if not Result then Exit;
  BrushCss(AX, AY, x, y);
  FBrushDragOn := True;
  FBrushDragBrush := b;
  FBrushDragSerial := BrushCtlOf(b).Covers[i].Serial;
  FBrushDragPiece := pc;
  FBrushDragX := x;
  FBrushDragY := y;
  BrushCtlDown(AX, AY, True);
end;

procedure TTyAdvanceChart.BrushCtlDown(AX, AY: Integer; ADraggable: Boolean);
var
  b: Integer;
  x, y: Double;
begin
  BrushCss(AX, AY, x, y);
  for b := 0 to High(FBrushCtls) do
    if FBrushCtls[b] <> nil then
      BrushOnTrigger(b, FBrushCtls[b].MouseDown(x, y, ADraggable));
  { the parallel axes' controllers [Batch 130] }
  for b := 0 to High(FParBrushCtls) do
    if FParBrushCtls[b] <> nil then
      ParBrushOnTrigger(b, FParBrushCtls[b].MouseDown(x, y, ADraggable));
end;

procedure TTyAdvanceChart.BrushPointerMove(AX, AY: Integer);
var
  b: Integer;
  x, y: Double;
  t: TTyBrushTrigger;
begin
  if (Length(FBrushCtls) = 0) and (Length(FParBrushCtls) = 0) then Exit;
  BrushCss(AX, AY, x, y);
  { Draggable's drag: the delta from the last pointer event }
  if FBrushDragOn and (BrushCtlOf(FBrushDragBrush) <> nil) then
  begin
    t := BrushCtlOf(FBrushDragBrush).Drift(FBrushDragSerial, FBrushDragPiece,
      x - FBrushDragX, y - FBrushDragY);
    FBrushDragX := x;
    FBrushDragY := y;
    BrushTriggerTo(FBrushDragBrush, t);
    BrushChanged;
  end;
  for b := 0 to High(FBrushCtls) do
    if FBrushCtls[b] <> nil then
    begin
      t := FBrushCtls[b].MouseMove(x, y);
      if t.Fired then
      begin
        BrushOnTrigger(b, t);
        BrushChanged;
      end
      else if FBrushCtls[b].Dragging then BrushChanged;
    end;
  { the parallel axes' controllers [Batch 130] }
  for b := 0 to High(FParBrushCtls) do
    if FParBrushCtls[b] <> nil then
    begin
      t := FParBrushCtls[b].MouseMove(x, y);
      if t.Fired then ParBrushOnTrigger(b, t)
      else if FParBrushCtls[b].Dragging then BrushChanged;
    end;
end;

{ Draggable's dragend: the cover's ondragend triggers with isEnd }
procedure TTyAdvanceChart.BrushDragEnd;
var b: Integer;
begin
  if not FBrushDragOn then Exit;
  FBrushDragOn := False;
  b := FBrushDragBrush;
  if BrushCtlOf(b) = nil then Exit;
  BrushTriggerTo(b, BrushCtlOf(b).DragEnd(FBrushDragSerial));
end;

procedure TTyAdvanceChart.BrushCtlUp(AX, AY: Integer);
var
  b: Integer;
  x, y: Double;
  was: Boolean;
begin
  if (Length(FBrushCtls) = 0) and (Length(FParBrushCtls) = 0) then Exit;
  BrushCss(AX, AY, x, y);
  for b := 0 to High(FBrushCtls) do
    if FBrushCtls[b] <> nil then
    begin
      was := FBrushCtls[b].Dragging;
      BrushOnTrigger(b, FBrushCtls[b].MouseUp(x, y));
      if was then BrushChanged;
    end;
  { the parallel axes' controllers [Batch 130] }
  for b := 0 to High(FParBrushCtls) do
    if FParBrushCtls[b] <> nil then
    begin
      was := FParBrushCtls[b].Dragging;
      ParBrushOnTrigger(b, FParBrushCtls[b].MouseUp(x, y));
      if was then BrushChanged;
    end;
end;

function TTyAdvanceChart.BrushCrosshair(AX, AY: Integer): Boolean;
var
  b: Integer;
  x, y: Double;
begin
  Result := False;
  if (Length(FBrushCtls) = 0) and (Length(FParBrushCtls) = 0) then Exit;
  BrushCss(AX, AY, x, y);
  for b := 0 to High(FBrushCtls) do
    if (FBrushCtls[b] <> nil) and FBrushCtls[b].Crosshair(x, y) then Result := True;
  { the parallel axes' controllers [Batch 130] }
  for b := 0 to High(FParBrushCtls) do
    if (FParBrushCtls[b] <> nil) and FParBrushCtls[b].Crosshair(x, y) then Result := True;
end;

procedure TTyAdvanceChart.BrushChanged;
begin
  DropStatic;
  FZrDirty := True;
  inherited Invalidate;
end;

{ the covers: each brush view's group in component order, a group's covers
  in the order they were added; the main shape filled and stroked in the
  cover's style (the skin's where it wrote none), the handles invisible }
function TTyAdvanceChart.BuildBrushes(AList: TTyPaintList): Integer;
var
  b, q, i: Integer;
  ord_: TTyIntegerArray;
  ctl: TTyBrushController;
  cv: TTyBrushCover;
  el: TTyChartElement;
  v: TTyBrushView;
  pts: array of TTyPointF;
  st: TTyStyleSet;
  inkFill, inkStroke, c: TTyChartColor;
  lw: Double;
begin
  Result := 0;
  if Length(FBrushCtls) = 0 then Exit;
  v := BrushViewOf;
  st := ActiveController.Model.ResolveStyle('TyAdvChartBrush', '', []);
  inkFill := TTyChartColor(st.Background.Color);
  inkStroke := TTyChartColor(st.BorderColor);
  for b := 0 to High(FBrushCtls) do
  begin
    ctl := FBrushCtls[b];
    if ctl = nil then Continue;
    ord_ := ctl.GroupOrder;
    for q := 0 to High(ord_) do
    begin
      cv := ctl.Covers[ord_[q]];
      el := Default(TTyChartElement);
      el.Silent := True;
      el.Datum := TyChartDatum(-1, -1);
      el.Z := TyBrushCoverZ;
      el.Style.Alpha := 1;
      if cv.Opt.BrushType = btPolygon then
      begin
        if Length(cv.Points) < 2 then Continue;
        SetLength(pts, Length(cv.Points));
        for i := 0 to High(pts) do
          pts[i] := TyPointF(v.OX + cv.Points[i].X * v.S, v.OY + cv.Points[i].Y * v.S);
        if cv.Closed then el.Shape := TyShapePolygon(pts)
        else el.Shape := TyShapePolyline(pts);
      end
      else
      begin
        if IsNan(cv.Main.X) or IsNan(cv.Main.Y) or IsNan(cv.Main.W) or IsNan(cv.Main.H) then
          Continue;
        el.Shape := TyShapeRect(TyRectF(v.OX + cv.Main.X * v.S, v.OY + cv.Main.Y * v.S,
          v.OX + (cv.Main.X + cv.Main.W) * v.S, v.OY + (cv.Main.Y + cv.Main.H) * v.S));
      end;
      if not (cv.Opt.Style.Fill.Written and (cv.Opt.Style.Fill.Text = 'none')) then
      begin
        c := inkFill;
        if cv.Opt.Style.Fill.Written and not TyTryParseChartColor(cv.Opt.Style.Fill.Text, c) then
          c := inkFill;
        el.Style.HasFill := True;
        el.Style.FillColor := c;
      end;
      lw := cv.Opt.Style.LineWidth;
      if IsNan(lw) then lw := 1;
      if (lw > 0) and not (cv.Opt.Style.Stroke.Written and (cv.Opt.Style.Stroke.Text = 'none')) then
      begin
        c := inkStroke;
        if cv.Opt.Style.Stroke.Written and not TyTryParseChartColor(cv.Opt.Style.Stroke.Text, c) then
          c := inkStroke;
        el.Style.StrokeColor := c;
        el.Style.StrokeWidthLogical := lw;
      end;
      if not IsNan(cv.Opt.Style.Opacity) then
        el.Style.Alpha := Max(0, Min(1, cv.Opt.Style.Opacity));
      AList.Add(el);
      Inc(Result);
    end;
  end;
end;

{ ==================== the selection [Batch 127] ====================

  visualEncoding.ts's brushVisual, the overall visual stage, over the pure
  tyControls.AdvChart.Brush: every brush component in order -- its areas
  with their bounding rects, each series it controls (a brushSelector:
  scatter, effectScatter, bar, candlestick; seriesIndex; controlSeries: the
  area's target grid holds the series' cartesian, or the area is global)
  checked item by item against the item's layout, brushLink spreading a
  selection by data index -- and the inBrush / outOfBrush visuals written
  over the rows the visual stages before it left (FVisualRows, restored from
  FBrushVisBase first: the stage runs again from the same input). A later
  brush writes over an earlier one. An update with a payload (an action's,
  not a setOption's) then dispatches brushSelect through the throttle; its
  brushselected event waits for the action's own event (BrushFlush).

  THE globalPan MUTEX (interactionMutex.ts): one holder, the controller
  that enabled last; a disable releases it only when it holds it. While it
  is held no roam pans (MouseDown). onIrrelevantElement: the topmost
  element under the pointer, a silent one too, belongs to a series on
  another coordinate system above the panel's grid -- its zlevel, then its
  z, higher. }

procedure TTyAdvanceChart.BrushEnableCtl(ACtl: TTyBrushController; const AOpt: TTyBrushOpt;
  AAuto: Boolean);
var was: Boolean;
begin
  if ACtl = nil then Exit;
  was := ACtl.Enabled;
  if AAuto then ACtl.EnableAuto(AOpt) else ACtl.EnableBrush(AOpt);
  { _doDisableBrush releases globalPan when this one holds it, then
    _doEnableBrush takes it }
  if was and (FPanHolder = ACtl.Uid) then FPanHolder := 0;
  if ACtl.Enabled then FPanHolder := ACtl.Uid;
end;

procedure TTyAdvanceChart.BrushFreeCtl(var ACtl: TTyBrushController);
begin
  if ACtl = nil then Exit;
  { dispose: enableBrush(false) }
  if ACtl.Enabled and (FPanHolder = ACtl.Uid) then FPanHolder := 0;
  FreeAndNil(ACtl);
end;

function TTyAdvanceChart.PanTaken: Boolean;
begin
  Result := FPanHolder <> 0;
end;

function TTyAdvanceChart.BrushGlobalPanTaken: Boolean;
begin
  Result := PanTaken;
end;

function TTyAdvanceChart.BrushIrrelevant(const APanel: TTyBrushPanel; AX, AY: Double): Boolean;
var
  v: TTyBrushView;
  idx, slot, si, sz, szl: Integer;
  el: TTyChartElement;
  node, d: TJSONData;
  gz, gzl, diff: Double;
  hasCoord: Boolean;
begin
  Result := False;
  if (APanel.GridComponent < 0) or (FPaintList = nil) or not FPaintListValid then Exit;
  v := BrushViewOf;
  idx := FPaintList.TopElementAt(v.OX + AX * v.S, v.OY + AY * v.S, FPaintListPPI);
  if idx < 0 then Exit;
  el := FPaintList.Element(idx);
  { getComponentByElement: a series' element. A marker's, a legend's, the
    toolbox's, a brush cover -- nothing with a coordinate system -- is not
    irrelevant }
  if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex < 0) then Exit;
  si := el.Datum.SeriesIndex;
  slot := SlotOfSeries(si);
  if (slot < 0) or (slot > High(FBindings)) then Exit;
  { its coordinate system's model: the panel's own grid is relevant; a
    series with none (a pie, a funnel) is too }
  if FBindings[slot].Cart <> nil then
  begin
    if (FBindings[slot].XAxis <> nil)
      and (FBindings[slot].XAxis.GridIndex = APanel.GridComponent) then Exit;
    hasCoord := True;
  end
  else
    hasCoord := (FBindings[slot].Polar <> nil) or (FBindings[slot].CalendarIndex >= 0)
      or (FBindings[slot].SeriesType = TyGraphSeriesTypeName)
      or (FBindings[slot].SeriesType = TyTreeSeriesTypeName)
      or (FBindings[slot].SeriesType = 'radar');
  if not hasCoord then Exit;
  { retrieveZInfo: zlevel first, then z; equal is relevant }
  gz := 0;
  gzl := 0;
  node := FOption.ComponentAt('grid', APanel.GridComponent);
  if node is TJSONObject then
  begin
    d := TJSONObject(node).Find('z');
    if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat) then gz := d.AsFloat;
    d := TJSONObject(node).Find('zlevel');
    if (d <> nil) and (d.JSONType = jtNumber) and not IsNan(d.AsFloat) then gzl := d.AsFloat;
  end;
  if FBindings[slot].SeriesType = 'line' then sz := SeriesIntIn(si, 'z', 3)
  else sz := SeriesIntIn(si, 'z', 2);
  szl := SeriesIntIn(si, 'zlevel', 0);
  diff := szl - gzl;
  if diff = 0 then diff := sz - gz;
  Result := diff > 0;
end;

procedure TTyAdvanceChart.BrushVisCapture;
var i: Integer;
begin
  FBrushVisBase := nil;
  FBrushVisBaseOk := Length(FBrushSpecs) > 0;
  if not FBrushVisBaseOk then Exit;
  SetLength(FBrushVisBase, Length(FVisualRows));
  for i := 0 to High(FVisualRows) do FBrushVisBase[i] := Copy(FVisualRows[i]);
end;

function TTyAdvanceChart.BrushSelectCompute: TTyBrushSelectBatch;
var
  b, i, k, r, raw, n, si, t: Integer;
  reach: TTyBrushReach;
  vis: TTyBrushVisual;
  sel: TTyBrushSelAreaArray;
  tg: TTyBrushTargetArray;
  lays: array of TTyBrushItemLayoutArray;
  layDone: array of Boolean;
  lists: array of TTyIntegerArray;
  linkSel: array of Boolean;
  hasBrush, linked, inB, applies, ctrl: Boolean;
  v: TTyBrushView;
  sv: TTySeriesVisual;
  outColor, baseColor: TTyVisualColor;
  st: TTyDataStore;
  offKey: Integer;
  ov: TTyDataValue;
  item: TTyBrushSelSeries;

  function Live(ASlot: Integer): Boolean;
  begin
    Result := not FBindings[ASlot].Hidden;
  end;

  function HasSelector(ASlot: Integer): Boolean;
  var s: string;
  begin
    s := FBindings[ASlot].SeriesType;
    Result := (s = 'scatter') or (s = 'effectScatter') or (s = 'bar') or (s = 'candlestick');
  end;

  procedure EnsureLayout(ASlot: Integer);
  var q: Integer;
  begin
    if layDone[ASlot] then Exit;
    layDone[ASlot] := True;
    lays[ASlot] := nil;
    if (ASlot > High(FStores)) or (FStores[ASlot] = nil) then Exit;
    sv := TySeriesVisual(0);
    if ASlot <= High(FBarCols) then sv.Bar := FBarCols[ASlot];
    if ASlot <= High(FWhiskers) then sv.Whisker := FWhiskers[ASlot];
    sv.Large := LargeKindOf(ASlot);
    { a series on a geo: the points layout (dataToPoint, unclipped)
      [Batch 152] }
    if (FBindings[ASlot].GeoIndex >= 0) and (GeoOfSlot(ASlot) <> nil) then
      lays[ASlot] := GeoBrushLayouts(ASlot)
    else
      lays[ASlot] := TyBrushItemLayouts(FBindings[ASlot], FStores[ASlot], StackFor(ASlot), sv);
    { the cartesian's device px -> the brush's CSS px }
    for q := 0 to High(lays[ASlot]) do
    begin
      lays[ASlot][q].X := (lays[ASlot][q].X - v.OX) / v.S;
      lays[ASlot][q].Y := (lays[ASlot][q].Y - v.OY) / v.S;
      lays[ASlot][q].W := lays[ASlot][q].W / v.S;
      lays[ASlot][q].H := lays[ASlot][q].H / v.S;
    end;
  end;

  function CheckIn(ASlot, ARow: Integer): Boolean;
  var q: Integer;
  begin
    Result := False;
    if (ASlot > High(lays)) or (ARow > High(lays[ASlot])) then Exit;
    for q := 0 to High(lists[ASlot]) do
      if TyBrushSelects(sel[lists[ASlot][q]], lays[ASlot][ARow]) then Exit(True);
  end;

begin
  Result := nil;
  if Length(FBrushSpecs) = 0 then Exit;
  SetLength(Result, Length(FBrushSpecs));
  for b := 0 to High(FBrushSpecs) do
  begin
    Result[b].BrushIndex := b;
    Result[b].BrushId := ComponentModelId('brush', b);
    Result[b].BrushName := ComponentModelName('brush', b);
    if b <= High(FBrushAreas) then Result[b].Areas := Copy(FBrushAreas[b]);
  end;
  if (FBuild = nil) or (FOption = nil) then Exit;
  { the stage runs again from the rows the stages before it left }
  if FBrushVisBaseOk then
  begin
    SetLength(FVisualRows, Length(FBrushVisBase));
    for i := 0 to High(FBrushVisBase) do FVisualRows[i] := Copy(FBrushVisBase[i]);
  end;
  v := BrushViewOf;
  SetLength(lays, Length(FBindings));
  SetLength(layDone, Length(FBindings));
  for i := 0 to High(layDone) do layDone[i] := False;
  outColor := TyVisualFromChart(TTyChartColor(
    ActiveController.Model.ResolveStyle('TyAdvChartBrushOut', '', []).TextColor));
  offKey := TyOverrideKey('visualMap');
  for b := 0 to High(FBrushSpecs) do
  begin
    reach := TyBrushReachOf(FOption.ComponentAt('brush', b));
    vis := TyBrushVisualOf(FOption.ComponentAt('brush', b));
    SetLength(sel, Length(Result[b].Areas));
    for k := 0 to High(sel) do sel[k] := TyBrushSelAreaOf(Result[b].Areas[k]);
    tg := BrushTargets(b);
    lists := nil;
    SetLength(lists, Length(FBindings));
    linkSel := nil;
    hasBrush := False;
    { step A: each series' areas, and the data indices a linked one selects }
    for i := 0 to High(FBindings) do
    begin
      if not Live(i) or not HasSelector(i) then Continue;
      if not TyBrushControls(reach, FBindings[i].SeriesIndex) then Continue;
      for k := 0 to High(sel) do
      begin
        { controlSeries: a global area, or the target's cartesians hold the
          series' }
        t := BrushFindTarget(tg, Result[b].Areas[k]);
        ctrl := t < 0;
        if not ctrl then
          for r := 0 to High(tg[t].Carts) do
            if tg[t].Carts[r] = FBindings[i].Cart then ctrl := True;
        { a series on the target's geo [Batch 152] }
        if not ctrl and (tg[t].Geo <> nil) and (GeoOfSlot(i) = tg[t].Geo) then ctrl := True;
        if ctrl then
        begin
          n := Length(lists[i]);
          SetLength(lists[i], n + 1);
          lists[i][n] := k;
        end;
        hasBrush := hasBrush or (Length(lists[i]) > 0);
      end;
      if TyBrushLinks(reach, FBindings[i].SeriesIndex) and (Length(lists[i]) > 0)
        and (i <= High(FStores)) and (FStores[i] <> nil) then
      begin
        EnsureLayout(i);
        if Length(linkSel) < FStores[i].Count then
        begin
          n := Length(linkSel);
          SetLength(linkSel, FStores[i].Count);
          for r := n to High(linkSel) do linkSel[r] := False;
        end;
        for r := 0 to FStores[i].Count - 1 do
          if CheckIn(i, r) then linkSel[r] := True;
      end;
    end;
    { step B: every series in the batch; the visuals where the brush applies }
    for i := 0 to High(FBindings) do
    begin
      if not Live(i) then Continue;
      si := FBindings[i].SeriesIndex;
      item := Default(TTyBrushSelSeries);
      item.SeriesIndex := si;
      item.SeriesId := ComponentModelId('series', si);
      item.SeriesName := SeriesModelName(si);
      st := nil;
      if i <= High(FStores) then st := FStores[i];
      if st <> nil then
      begin
        linked := TyBrushLinks(reach, si);
        if linked then applies := hasBrush else applies := Length(lists[i]) > 0;
        if not linked and (Length(lists[i]) > 0) then EnsureLayout(i);
        if applies then
        begin
          if Length(FVisualRows) < Length(FBindings) then
          begin
            SetLength(FVisualRows, Length(FBindings));
            SetLength(FVisualMetas, Length(FBindings));
            SetLength(FVisualLines, Length(FBindings));
          end;
          if FVisualRows[i] = nil then
          begin
            baseColor := TyVisualFromChart(TTyChartColor(SeriesColor(si)));
            SetLength(FVisualRows[i], st.RawCount);
            for r := 0 to High(FVisualRows[i]) do
            begin
              FVisualRows[i][r] := Default(TTyVisualRow);
              FVisualRows[i][r].Color := baseColor;
              FVisualRows[i][r].Opacity := NaN;
            end;
          end;
        end;
        for r := 0 to st.Count - 1 do
        begin
          raw := st.GetRawIndex(r);
          if linked then inB := (r <= High(linkSel)) and linkSel[r]
          else inB := CheckIn(i, r);
          if inB then
          begin
            n := Length(item.DataIndex);
            SetLength(item.DataIndex, n + 1);
            item.DataIndex[n] := raw;
          end;
          if not applies or (raw < 0) or (raw > High(FVisualRows[i])) then Continue;
          { `visualMap: false` on the item opts it out }
          if st.HasOverrideByRaw(raw, offKey) then
          begin
            ov := st.GetOverrideByRaw(raw, offKey);
            if (ov.Kind = dvkBool) and (ov.Num = 0) then Continue;
          end;
          TyBrushApplyVisual(vis.States[inB], vis.OutIsSkin and not inB, outColor,
            FVisualRows[i][raw]);
        end;
      end;
      n := Length(Result[b].Selected);
      SetLength(Result[b].Selected, n + 1);
      Result[b].Selected[n] := item;
    end;
  end;
end;

procedure TTyAdvanceChart.BrushSelectRun(ADispatch: Boolean; ARepaint: Boolean);
var batch: TTyBrushSelectBatch;
begin
  if ADispatch then FBrushPayload := False;
  batch := BrushSelectCompute;
  { the series' visuals changed: the list again (inside a layout it is
    built next anyway) }
  if ARepaint and (Length(FBrushSpecs) > 0) then BrushChanged;
  if ADispatch then BrushVisual(batch);
end;

procedure TTyAdvanceChart.BrushFlush;
var
  q: TTyStringArray;
  i: Integer;
begin
  while Length(FBrushEmitQ) > 0 do
  begin
    q := FBrushEmitQ;
    FBrushEmitQ := nil;
    for i := 0 to High(q) do EmitPayloadEvent('brushselected', q[i]);
  end;
end;

{ the brushSelect action's event: the batch, each item as the action
  handled it (its type the event's, its batch null) }
function TTyAdvanceChart.BrushSelectedJson(const ABatch: TTyBrushSelectBatch): string;
var
  b, s, k: Integer;
  st: TTyStyleSet;
  defFill, defStroke: string;
begin
  { the model's areas whole: the brush's default colours are the skin's
    [milestone D5-D8] }
  st := ActiveController.Model.ResolveStyle('TyAdvChartBrush', '', []);
  defFill := TyBrushColorText(Cardinal(st.Background.Color));
  defStroke := TyBrushColorText(Cardinal(st.BorderColor));
  Result := '{"type":"brushselected","batch":[';
  for b := 0 to High(ABatch) do
  begin
    if b > 0 then Result := Result + ',';
    Result := Result + '{"brushId":' + TyBrushJsonStr(ABatch[b].BrushId)
      + ',"brushIndex":' + IntToStr(ABatch[b].BrushIndex)
      + ',"brushName":' + TyBrushJsonStr(ABatch[b].BrushName)
      + ',"areas":' + TyBrushModelAreasJson(ABatch[b].Areas, defFill, defStroke) + ',"selected":[';
    for s := 0 to High(ABatch[b].Selected) do
    begin
      if s > 0 then Result := Result + ',';
      Result := Result + '{"seriesId":' + TyBrushJsonStr(ABatch[b].Selected[s].SeriesId)
        + ',"seriesIndex":' + IntToStr(ABatch[b].Selected[s].SeriesIndex)
        + ',"seriesName":' + TyBrushJsonStr(ABatch[b].Selected[s].SeriesName)
        + ',"dataIndex":[';
      for k := 0 to High(ABatch[b].Selected[s].DataIndex) do
      begin
        if k > 0 then Result := Result + ',';
        Result := Result + IntToStr(ABatch[b].Selected[s].DataIndex[k]);
      end;
      Result := Result + ']}';
    end;
    Result := Result + '],"type":"brushselected","batch":null}';
  end;
  Result := Result + ']}';
end;

{ axisAreaSelect: the queried parallelAxis models take the intervals and
  the chart updates (parallelVisual's opacities) [Batch 128]; the update's
  visual stage (brushSelect), the toolbox's render and the event }
procedure TTyAdvanceChart.BrushDoAxisAreaSelect(APayload: TJSONObject);
var
  hit: Boolean;
  first: Integer;
begin
  { THE AXES THE QUERY NAMES take the intervals, and the update renders
    them (parallelVisual's opacities) [Batch 128] -- every parallelAxis
    view but the first the query finds (fromAxisAreaSelect), which keeps
    the covers it has [Batch 130] }
  hit := ParallelAreaSelect(APayload, first);
  FParBrushSkip := first;
  if hit or (Length(FParallels) > 0) then
  begin
    FParBrushInAas := True;
    try
      FullUpdate;
    finally
      FParBrushInAas := False;
    end;
  end;
  BrushSync;
  BrushSelectRun(True);
  TbBrushSnap;
  FDirty := True;
  Invalidate;
  EmitPayloadEvent('axisareaselected', TbEventJson(APayload, 'axisareaselected'));
end;

{ ---- the toolbox's brush feature (feature/Brush.ts) ---- }

{ what BrushFeature.render reads off the brush models: the last one's
  brushType and brushOption.brushMode (|| 'single'), and whether any keeps
  an area }
procedure TTyAdvanceChart.TbBrushModelState(out AHas, AMulti, ABrushed: Boolean;
  out AType: TTyBrushType);
var b: Integer;
begin
  AHas := False;
  AMulti := False;
  ABrushed := False;
  AType := btNone;
  for b := 0 to High(FBrushSpecs) do
  begin
    AHas := (b <= High(FBrushHasPaint)) and FBrushHasPaint[b];
    if AHas then
    begin
      AType := FBrushPaint[b].BrushType;
      AMulti := FBrushPaint[b].Multiple;
    end
    else
    begin
      AType := btNone;
      AMulti := False;
    end;
    if (b <= High(FBrushAreas)) and (Length(FBrushAreas[b]) > 0) then ABrushed := True;
  end;
end;

{ an update the port renders later: the feature renders with what the
  models hold now }
procedure TTyAdvanceChart.TbBrushSnap;
begin
  TbBrushModelState(FTbBfSnapHas, FTbBfSnapMulti, FTbBfSnapBrushed, FTbBfSnapType);
  FTbBfSnap := True;
end;

{ BrushFeature.render: every listed type's status -- keep by the mode,
  clear by any area, a type by the brush type -- and the type and mode its
  clicks read }
procedure TTyAdvanceChart.TbBrushRender(ATb: Integer);
var
  fm: TJSONObject;
  d: TJSONData;
  k: Integer;
  has, multi, brushed, on_: Boolean;
  typ: TTyBrushType;
  nm: string;
begin
  if FTbBfSnap then
  begin
    has := FTbBfSnapHas;
    multi := FTbBfSnapMulti;
    brushed := FTbBfSnapBrushed;
    typ := FTbBfSnapType;
  end
  else
    TbBrushModelState(has, multi, brushed, typ);
  FTbBfHas := has;
  FTbBfMulti := multi;
  FTbBfType := typ;
  fm := TyToolboxFeatureModel(FOption, ATb, 'brush', TbTitles);
  if fm = nil then Exit;
  try
    d := fm.Find('type');
    if not (d is TJSONArray) then Exit;
    for k := 0 to d.Count - 1 do
    begin
      if d.Items[k].JSONType <> jtString then Continue;
      nm := d.Items[k].AsString;
      if nm = 'keep' then on_ := multi
      else if nm = 'clear' then on_ := brushed
      else on_ := has and (typ <> btNone) and (TyBrushTypeName(typ) = nm);
      if on_ then TbSetStatus(ATb, 'brush', nm, 'emphasis')
      else TbSetStatus(ATb, 'brush', nm, 'normal');
    end;
  finally
    fm.Free;
  end;
end;

{ BrushFeature.onclick: clear dispatches axisAreaSelect, then the brush
  action with no areas; any other takes the global cursor -- keep flips the
  mode and keeps the type, a type flips itself on or off }
procedure TTyAdvanceChart.TbBrushClick(const AIcon: string);
var bt, bm: string;
begin
  if AIcon = 'clear' then
  begin
    DispatchAction('{"type":"axisAreaSelect","intervals":[]}');
    DispatchAction('{"type":"brush","command":"clear","areas":[]}');
    Exit;
  end;
  if AIcon = 'keep' then
  begin
    if FTbBfHas and (FTbBfType <> btNone) then bt := '"' + TyBrushTypeName(FTbBfType) + '"'
    else if FTbBfHas then bt := 'false'
    else bt := 'null';
    if FTbBfMulti then bm := 'single' else bm := 'multiple';
  end
  else
  begin
    if FTbBfHas and (FTbBfType <> btNone) and (TyBrushTypeName(FTbBfType) = AIcon) then
      bt := 'false'
    else
      bt := TyBrushJsonStr(AIcon);
    if FTbBfMulti then bm := 'multiple' else bm := 'single';
  end;
  DispatchAction('{"type":"takeGlobalCursor","key":"brush","brushOption":{"brushType":'
    + bt + ',"brushMode":"' + bm + '"}}');
end;

{ ---- what the tests read ---- }

function TTyAdvanceChart.BrushCount: Integer;
begin
  Result := Length(FBrushCtls);
end;

function TTyAdvanceChart.BrushControllerOf(AIndex: Integer): TTyBrushController;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FBrushCtls)) then Result := FBrushCtls[AIndex];
end;

function TTyAdvanceChart.BrushModelAreas(AIndex: Integer): TTyBrushAreaArray;
begin
  Result := nil;
  if (AIndex >= 0) and (AIndex <= High(FBrushAreas)) then Result := Copy(FBrushAreas[AIndex]);
end;

function TTyAdvanceChart.BrushHitTest(AX, AY: Integer; out ABrush, AIndex: Integer;
  out APiece: TTyBrushPiece): Boolean;
begin
  Result := BrushPieceAt(AX, AY, ABrush, AIndex, APiece);
end;

function TTyAdvanceChart.BrushSelectCount: Integer;
begin
  Result := Length(FBrushSelLog);
end;

function TTyAdvanceChart.BrushSelectAt(AIndex: Integer): TTyBrushSelectRec;
begin
  Result := Default(TTyBrushSelectRec);
  if (AIndex >= 0) and (AIndex <= High(FBrushSelLog)) then Result := FBrushSelLog[AIndex];
end;

function TTyAdvanceChart.BrushEventCount: Integer;
begin
  Result := Length(FBrushEvLog);
end;

function TTyAdvanceChart.BrushEventAt(AIndex: Integer): TTyBrushEventRec;
begin
  Result := Default(TTyBrushEventRec);
  if (AIndex >= 0) and (AIndex <= High(FBrushEvLog)) then Result := FBrushEvLog[AIndex];
end;

procedure TTyAdvanceChart.BrushClearLogs;
begin
  FBrushSelLog := nil;
  FBrushEvLog := nil;
end;

{ ==================== the parallel axes' area select [Batch 130] ====================

  ParallelAxisView: every parallelAxis view a BrushController of its own,
  mounted on the axis' place and turned by its rotation, its one panel the
  band along the axis, drawing lineX in that frame with the
  areaSelectStyle and removeOnClick; never holding globalPan
  (enableGlobalPan). A render lays the covers again from the axis model's
  active intervals (getCoverInfoList) -- except the render of the update an
  axisAreaSelect causes, for the first axis its query finds. A cover's
  `brush` event turns the covers' ranges into intervals (coordToData,
  clamped) and dispatches axisAreaSelect for the axis: while a drag moves
  when the axis is realtime, at its end when it is not, and always for the
  tiny drag that clears. }

function TTyAdvanceChart.BrushCtlOf(AIndex: Integer): TTyBrushController;
var k: Integer;
begin
  Result := nil;
  if AIndex < 0 then Exit;
  if AIndex < TyParallelBrushBase then
  begin
    if AIndex <= High(FBrushCtls) then Result := FBrushCtls[AIndex];
    Exit;
  end;
  k := AIndex - TyParallelBrushBase;
  if k <= High(FParBrushCtls) then Result := FParBrushCtls[k];
end;

procedure TTyAdvanceChart.BrushTriggerTo(AIndex: Integer; const ATrig: TTyBrushTrigger);
begin
  if AIndex < TyParallelBrushBase then BrushOnTrigger(AIndex, ATrig)
  else ParBrushOnTrigger(AIndex - TyParallelBrushBase, ATrig);
end;

procedure TTyAdvanceChart.ParBrushFree;
var k: Integer;
begin
  for k := 0 to High(FParBrushCtls) do FreeAndNil(FParBrushCtls[k]);
  FParBrushCtls := nil;
  FParBrushSkip := -1;
  { a drag on a cover that is gone ends with it }
  if FBrushDragOn and (FBrushDragBrush >= TyParallelBrushBase) then FBrushDragOn := False;
end;

{ _refreshBrushController of every axis view that renders: mount on the
  axis' layout, the panel, enableBrush, updateCovers from the intervals.
  CSS px: the axis' own coordinates over the view's scale. A view not
  shown (`show: false`) returns before it -- its controller stays as it
  was. }
procedure TTyAdvanceChart.ParBrushPass;
var
  n, old, k, p, a, i: Integer;
  par: TTyParallel;
  ctl: TTyBrushController;
  ss: TTyParallelSelectStyle;
  v: TTyBrushView;
  e0, e1: Double;
  pn: array of TTyBrushPanel;
  cfg: TTyBrushOptArray;
  iv: TTyParallelIntervalArray;
  ax: TTyAxis;
  mask: TFPUExceptionMask;
begin
  if FOption = nil then n := 0 else n := FOption.ComponentCount('parallelAxis');
  old := Length(FParBrushCtls);
  for k := n to old - 1 do FreeAndNil(FParBrushCtls[k]);
  SetLength(FParBrushCtls, n);
  for k := old to n - 1 do FParBrushCtls[k] := nil;
  if n = 0 then Exit;
  v := BrushViewOf;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    for k := 0 to n - 1 do
    begin
      { fromAxisAreaSelect }
      if k = FParBrushSkip then Continue;
      p := ParallelOfAxis(k);
      if p < 0 then Continue;
      par := FParallels[p];
      a := par.AxisOfComponent(k);
      if (a < 0) or (a > High(par.Views)) or (a > High(par.Layouts)) then Continue;
      if not par.Views[a].Shown then Continue;
      ss := TyParallelSelectStyleOf(FOption.ComponentAt('parallelAxis', k));
      ctl := FParBrushCtls[k];
      if ctl = nil then
      begin
        ctl := TTyBrushController.Create;
        FParBrushCtls[k] := ctl;
      end;
      ctl.Mount((par.Layouts[a].PosX - v.OX) / v.S, (par.Layouts[a].PosY - v.OY) / v.S,
        par.Layouts[a].Rotation);
      ax := par.Axis(a);
      ax.LocalExtent(e0, e1);
      SetLength(pn, 1);
      pn[0] := Default(TTyBrushPanel);
      pn[0].Id := 'pl';
      pn[0].Rect := TyParallelBrushPanelRect(e0 / v.S, e1 / v.S, ss.Width);
      pn[0].DefaultType := btLineX;
      pn[0].GridComponent := -1;
      ctl.CanvasW := (FLastRect.Right - FLastRect.Left) / v.S;
      ctl.CanvasH := (FLastRect.Bottom - FLastRect.Top) / v.S;
      ctl.SetPanels(pn, True);
      { enableGlobalPan: the mutex is never this controller's }
      ctl.EnableBrush(TyParallelBrushOpt(ss));
      { getCoverInfoList }
      iv := nil;
      if k <= High(FParIntervals) then iv := FParIntervals[k];
      SetLength(cfg, Length(iv));
      for i := 0 to High(iv) do
      begin
        { brushType, panelId and range, over DEFAULT_BRUSH_OPT }
        cfg[i] := TyBrushDefaultOpt;
        cfg[i].BrushType := btLineX;
        cfg[i].HasId := False;
        cfg[i].Id := '';
        cfg[i].HasPanel := True;
        cfg[i].PanelId := 'pl';
        cfg[i].HasRange := True;
        SetLength(cfg[i].Range, 1);
        cfg[i].Range[0][0] := ax.DataToCoord(iv[i][0], True) / v.S;
        cfg[i].Range[0][1] := ax.DataToCoord(iv[i][1], True) / v.S;
      end;
      ctl.UpdateCovers(cfg);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

{ ParallelAxisView._onBrush }
procedure TTyAdvanceChart.ParBrushOnTrigger(AAxis: Integer; const ATrig: TTyBrushTrigger);
var
  p, a, i: Integer;
  ax: TTyAxis;
  node, d: TJSONData;
  rt: Boolean;
  pay: TJSONObject;
  ivs, pair: TJSONArray;
  act: TTyParallelBrushAction;
  s: Double;
  mask: TFPUExceptionMask;
begin
  if not ATrig.Fired then Exit;
  BrushChanged;
  p := ParallelOfAxis(AAxis);
  if p < 0 then Exit;
  a := FParallels[p].AxisOfComponent(AAxis);
  if a < 0 then Exit;
  ax := FParallels[p].Axis(a);
  s := DzScale;
  act := Default(TTyParallelBrushAction);
  act.Axis := AAxis;
  act.AxisId := ComponentModelId('parallelAxis', AAxis);
  SetLength(act.Intervals, Length(ATrig.Areas));
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    for i := 0 to High(ATrig.Areas) do
    begin
      act.Intervals[i][0] := NaN;
      act.Intervals[i][1] := NaN;
      if Length(ATrig.Areas[i].Opt.Range) < 1 then Continue;
      act.Intervals[i][0] := ax.CoordToData(ATrig.Areas[i].Opt.Range[0][0] * s, True);
      act.Intervals[i][1] := ax.CoordToData(ATrig.Areas[i].Opt.Range[0][1] * s, True);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
  { realtime: during the drag, not at its end (the end carries what the
    last move did); not realtime: at the end. A clearing click always. }
  node := FOption.ComponentAt('parallelAxis', AAxis);
  d := nil;
  if node is TJSONObject then d := TJSONObject(node).Find('realtime');
  if d = nil then rt := True else rt := JsTruthy(d);
  if not (((not rt) = ATrig.IsEnd) or ATrig.RemoveOnClick) then Exit;
  SetLength(FParBrushLog, Length(FParBrushLog) + 1);
  FParBrushLog[High(FParBrushLog)] := act;
  pay := TJSONObject.Create;
  pay.Add('type', 'axisAreaSelect');
  pay.Add('parallelAxisId', act.AxisId);
  ivs := TJSONArray.Create;
  for i := 0 to High(act.Intervals) do
  begin
    pair := TJSONArray.Create;
    pair.Add(TJSONFloat(act.Intervals[i][0]));
    pair.Add(TJSONFloat(act.Intervals[i][1]));
    ivs.Add(pair);
  end;
  pay.Add('intervals', ivs);
  DispatchActionObject(pay);
end;

{ the covers of every parallel axis' controller, in the axes' order and a
  group's in the order they were added: the main shape through the group's
  transform, filled and stroked in its style (the skin's colours where the
  areaSelectStyle wrote none; a cover laid from the intervals has the
  brush's default style, and the brush's skin colours) }
function TTyAdvanceChart.BuildParallelBrushes(AList: TTyPaintList): Integer;
var
  k, q, i: Integer;
  ord_: TTyIntegerArray;
  ctl: TTyBrushController;
  cv: TTyBrushCover;
  el: TTyChartElement;
  v: TTyBrushView;
  pts: array of TTyPointF;
  st, stB: TTyStyleSet;
  inkFill, inkStroke, brFill, brStroke, c: TTyChartColor;
  lw, lx, ly: Double;
  corner: array[0..3, 0..1] of Double;
begin
  Result := 0;
  if (csDesigning in ComponentState) or (Length(FParBrushCtls) = 0) then Exit;
  v := BrushViewOf;
  st := ActiveController.Model.ResolveStyle(TyParallelSelectSkin, '', []);
  inkFill := TTyChartColor(st.Background.Color);
  inkStroke := TTyChartColor(st.BorderColor);
  stB := ActiveController.Model.ResolveStyle('TyAdvChartBrush', '', []);
  brFill := TTyChartColor(stB.Background.Color);
  brStroke := TTyChartColor(stB.BorderColor);
  for k := 0 to High(FParBrushCtls) do
  begin
    ctl := FParBrushCtls[k];
    if ctl = nil then Continue;
    ord_ := ctl.GroupOrder;
    for q := 0 to High(ord_) do
    begin
      cv := ctl.Covers[ord_[q]];
      if IsNan(cv.Main.X) or IsNan(cv.Main.Y) or IsNan(cv.Main.W) or IsNan(cv.Main.H)
        or IsInfinite(cv.Main.X) or IsInfinite(cv.Main.Y)
        or IsInfinite(cv.Main.W) or IsInfinite(cv.Main.H) then Continue;
      el := Default(TTyChartElement);
      el.Silent := True;
      el.Datum := TyChartDatum(-1, -1);
      el.Z := TyBrushCoverZ;
      el.Style.Alpha := 1;
      corner[0, 0] := cv.Main.X;
      corner[0, 1] := cv.Main.Y;
      corner[1, 0] := cv.Main.X + cv.Main.W;
      corner[1, 1] := cv.Main.Y;
      corner[2, 0] := cv.Main.X + cv.Main.W;
      corner[2, 1] := cv.Main.Y + cv.Main.H;
      corner[3, 0] := cv.Main.X;
      corner[3, 1] := cv.Main.Y + cv.Main.H;
      SetLength(pts, 4);
      for i := 0 to 3 do
      begin
        lx := ctl.Xf[0] * corner[i, 0] + ctl.Xf[2] * corner[i, 1] + ctl.Xf[4];
        ly := ctl.Xf[1] * corner[i, 0] + ctl.Xf[3] * corner[i, 1] + ctl.Xf[5];
        pts[i] := TyPointF(v.OX + lx * v.S, v.OY + ly * v.S);
      end;
      el.Shape := TyShapePolygon(pts);
      if not (cv.Opt.Style.Fill.Written and (cv.Opt.Style.Fill.Text = 'none')) then
      begin
        if cv.Opt.Style.Fill.Skin <> '' then c := inkFill else c := brFill;
        if cv.Opt.Style.Fill.Written and not TyTryParseChartColor(cv.Opt.Style.Fill.Text, c) then
          c := inkFill;
        el.Style.HasFill := True;
        el.Style.FillColor := c;
      end;
      lw := cv.Opt.Style.LineWidth;
      if IsNan(lw) then lw := 1;
      if (lw > 0) and not (cv.Opt.Style.Stroke.Written and (cv.Opt.Style.Stroke.Text = 'none')) then
      begin
        if cv.Opt.Style.Stroke.Skin <> '' then c := inkStroke else c := brStroke;
        if cv.Opt.Style.Stroke.Written and not TyTryParseChartColor(cv.Opt.Style.Stroke.Text, c) then
          c := inkStroke;
        el.Style.StrokeColor := c;
        el.Style.StrokeWidthLogical := lw;
      end;
      if not IsNan(cv.Opt.Style.Opacity) then
        el.Style.Alpha := Max(0, Min(1, cv.Opt.Style.Opacity));
      AList.Add(el);
      Inc(Result);
    end;
  end;
end;

function TTyAdvanceChart.ParallelBrushOf(AAxis: Integer): TTyBrushController;
begin
  Result := nil;
  if (AAxis >= 0) and (AAxis <= High(FParBrushCtls)) then Result := FParBrushCtls[AAxis];
end;

function TTyAdvanceChart.ParallelBrushActionCount: Integer;
begin
  Result := Length(FParBrushLog);
end;

function TTyAdvanceChart.ParallelBrushActionAt(AIndex: Integer): TTyParallelBrushAction;
begin
  Result := Default(TTyParallelBrushAction);
  if (AIndex >= 0) and (AIndex <= High(FParBrushLog)) then Result := FParBrushLog[AIndex];
end;

procedure TTyAdvanceChart.ParallelBrushClearLog;
begin
  FParBrushLog := nil;
end;

{ ==================== the parallel axis expansion [Batch 140] ====================

  ParallelView, one per parallel component, listens on zrender's mousedown,
  mouseup and mousemove whatever the button: with axisExpandable written
  and axisExpandTriggerOn 'click' a press and a release within sqrt(5) px
  ask getSlidedAxisExpandWindow where the window goes; with 'mousemove'
  every move asks it, through a fixRate throttle of axisExpandRate ms whose
  next call a jump debounces by axisExpandDebounce, a 'none' call
  cancelling what waits. What the view dispatches carries no query: every
  parallel takes the window. }

{ parallelAxisExpand: findComponents of the parallel main type by the query --
  parallelIndex (a number, a numeric string, a list), else parallelId, else
  parallelName, else every parallel -- and setAxisExpand: each of the five
  keys the payload owns written into the model's option (the window array
  shared). The update renders (_makeLayoutInfo rewrites that array), its
  visual stage dispatches brushSelect, and the event carries the payload,
  its window as the layout left it. }
procedure TTyAdvanceChart.DoParallelAxisExpand(APayload: TJSONObject);
const
  cKeys: array[0..4] of string = ('axisExpandable', 'axisExpandCenter',
    'axisExpandCount', 'axisExpandWidth', 'axisExpandWindow');
var
  n, k, j, q, last: Integer;
  hit: array of Boolean;
  d: TJSONData;
  node: TJSONObject;
  ev: TJSONObject;
  t: string;

  procedure MarkIndex(AData: TJSONData);
  var i2: Integer; v: Double;
  begin
    if AData is TJSONArray then
    begin
      for i2 := 0 to AData.Count - 1 do MarkIndex(TJSONArray(AData).Items[i2]);
      Exit;
    end;
    if AData.JSONType = jtNumber then v := AData.AsFloat
    else if (AData.JSONType = jtString) and (AData.AsString <> '')
      and (IntToStr(StrToIntDef(AData.AsString, -1)) = AData.AsString) then
      v := StrToInt(AData.AsString)
    else Exit;
    if IsNan(v) or (Frac(v) <> 0) or (v < 0) or (v >= n) then Exit;
    hit[Trunc(v)] := True;
  end;

  procedure MarkText(AData: TJSONData; AById, AInList: Boolean);
  var i2: Integer; s: string;
  begin
    if AData is TJSONArray then
    begin
      if AInList then Exit;
      for i2 := 0 to AData.Count - 1 do MarkText(TJSONArray(AData).Items[i2], AById, True);
      Exit;
    end;
    if AData.JSONType = jtString then s := AData.AsString
    else if (AData.JSONType = jtNumber) and not AInList then
      s := TyJsNumberToString(AData.AsFloat)
    else Exit;
    for i2 := 0 to n - 1 do
      if AById and (ComponentModelId('parallel', i2) = s) then hit[i2] := True
      else if (not AById) and (ComponentModelName('parallel', i2) = s) then hit[i2] := True;
  end;

begin
  if (FOption = nil) or (APayload = nil) then Exit;
  n := FOption.ComponentCount('parallel');
  SetLength(hit, n);
  for k := 0 to n - 1 do hit[k] := False;
  d := APayload.Find('parallelIndex');
  if (d <> nil) and (d.JSONType <> jtNull) then MarkIndex(d)
  else
  begin
    d := APayload.Find('parallelId');
    if (d <> nil) and (d.JSONType <> jtNull) then MarkText(d, True, False)
    else
    begin
      d := APayload.Find('parallelName');
      if (d <> nil) and (d.JSONType <> jtNull) then MarkText(d, False, False)
      else
        for k := 0 to n - 1 do hit[k] := True;
    end;
  end;
  last := -1;
  for k := 0 to n - 1 do
  begin
    if not hit[k] then Continue;
    if not (FOption.ComponentAt('parallel', k) is TJSONObject) then Continue;
    node := TJSONObject(FOption.ComponentAt('parallel', k));
    { `opt.hasOwnProperty(name)`: a key the payload holds, null included }
    for j := 0 to High(cKeys) do
    begin
      q := APayload.IndexOfName(cKeys[j]);
      if q < 0 then Continue;
      if node.IndexOfName(cKeys[j]) >= 0 then node.Delete(cKeys[j]);
      node.Add(cKeys[j], APayload.Items[q].Clone);
    end;
    last := k;
  end;
  if (last >= 0) or (Length(FParallels) > 0) then FullUpdate;
  BrushSync;
  BrushSelectRun(True);
  TbBrushSnap;
  FDirty := True;
  Invalidate;
  { the event: a shallow copy of the payload, whose window IS the model's
    array -- rewritten by the layout -- when a model took it }
  ev := TJSONObject.Create;
  try
    ev.Add('type', 'parallelaxisexpand');
    for j := 0 to APayload.Count - 1 do
    begin
      t := APayload.Names[j];
      if t = 'type' then Continue;
      d := APayload.Items[j];
      if (t = 'axisExpandWindow') and (d is TJSONArray) and (last >= 0)
        and (FOption.ComponentAt('parallel', last) is TJSONObject)
        and (TJSONObject(FOption.ComponentAt('parallel', last)).Find('axisExpandWindow') is TJSONArray) then
        d := TJSONObject(FOption.ComponentAt('parallel', last)).Find('axisExpandWindow');
      ev.Add(t, d.Clone);
    end;
    EmitPayloadEvent('parallelaxisexpand', TyTbJson(ev));
  finally
    ev.Free;
  end;
end;

procedure TTyAdvanceChart.ParExpEnsure;
var k, n, was: Integer;
begin
  n := Length(FParallels);
  was := Length(FParExp);
  if was >= n then Exit;
  SetLength(FParExp, n);
  for k := was to n - 1 do
  begin
    FParExp[k] := Default(TTyParallelExpandView);
    FParExp[k].DebounceNext := NaN;
    FParExp[k].ThrRate := NaN;
  end;
end;

{ createOrUpdate(this, '_throttledDispatchExpand', axisExpandRate, 'fixRate'):
  a new throttle -- its clock from the epoch -- when the rate changes; the
  function itself when the rate is null }
procedure TTyAdvanceChart.ParExpConfigure(AIndex: Integer);
var rate: Double; rateMoved: Boolean;
begin
  if (AIndex < 0) or (AIndex > High(FParallels)) or (FParallels[AIndex] = nil) then Exit;
  ParExpEnsure;
  rate := FParallels[AIndex].ExpandRate;
  if FParExp[AIndex].ThrActive then
    rateMoved := IsNan(rate) or (rate <> FParExp[AIndex].ThrRate)
  else
    rateMoved := True;
  if not rateMoved then Exit;
  if IsNan(rate) then
  begin
    FParExp[AIndex].ThrActive := False;
    FParExp[AIndex].ThrRate := NaN;
    Exit;
  end;
  FParExp[AIndex].ThrActive := True;
  FParExp[AIndex].ThrRate := rate;
  FParExp[AIndex].LastCall := 0;
  FParExp[AIndex].LastExec := 0;
  FParExp[AIndex].DebounceNext := NaN;
  Inc(FParExp[AIndex].Gen);
  FParExp[AIndex].TimerId := 0;
end;

{ getSlidedAxisExpandWindow: _makeLayoutInfo (the option's window
  rewritten), its window copied, containPoint's own _makeLayoutInfo (the
  window rewritten again), then the slide }
function TTyAdvanceChart.ParExpSlideAt(AIndex: Integer; AX, AY: Double;
  out AW0, AW1: Double): TTyParallelSlide;
var
  par: TTyParallel;
  node: TJSONObject;
begin
  AW0 := NaN;
  AW1 := NaN;
  Result := pslNone;
  if (AIndex < 0) or (AIndex > High(FParallels)) then Exit;
  par := FParallels[AIndex];
  if par = nil then Exit;
  node := nil;
  if FOption.ComponentAt('parallel', AIndex) is TJSONObject then
    node := TJSONObject(FOption.ComponentAt('parallel', AIndex));
  TyParallelRelayoutInfo(par, node);
  AW0 := par.ExpandWindow0;
  AW1 := par.ExpandWindow1;
  TyParallelRelayoutInfo(par, node);
  Result := TyParallelSlide(par, AX, AY, AW0, AW1);
end;

procedure TTyAdvanceChart.ParExpDown(AX, AY: Integer);
var i: Integer; par: TTyParallel;
begin
  ParExpEnsure;
  for i := 0 to High(FParallels) do
  begin
    par := FParallels[i];
    if (par = nil) or (i > High(FParExp)) then Continue;
    if par.ExpandOpt and par.TriggerClick then
    begin
      FParExp[i].HasDown := True;
      FParExp[i].DownX := AX;
      FParExp[i].DownY := AY;
    end;
  end;
end;

procedure TTyAdvanceChart.ParExpUp(AX, AY: Integer);
var
  i: Integer;
  par: TTyParallel;
  dist, w0, w1: Double;
begin
  ParExpEnsure;
  i := 0;
  while i <= High(FParallels) do
  begin
    par := FParallels[i];
    if (par <> nil) and (i <= High(FParExp)) then
    begin
      if par.ExpandOpt and par.TriggerClick and FParExp[i].HasDown then
      begin
        dist := Sqr(FParExp[i].DownX - AX) + Sqr(FParExp[i].DownY - AY);
        { CLICK_THRESHOLD: the handler returns -- the press stays }
        if dist > 5 then
        begin
          Inc(i);
          Continue;
        end;
        if ParExpSlideAt(i, AX, AY, w0, w1) <> pslNone then
          ParExpDispatch(i, w0, w1, 0, ParExpClock);
      end;
      if i <= High(FParExp) then FParExp[i].HasDown := False;
    end;
    Inc(i);
  end;
end;

procedure TTyAdvanceChart.ParExpMove(AX, AY: Integer);
var
  i: Integer;
  par: TTyParallel;
  w0, w1: Double;
  slide: TTyParallelSlide;
begin
  ParExpEnsure;
  i := 0;
  while i <= High(FParallels) do
  begin
    par := FParallels[i];
    { nothing while a click trigger's press is down }
    if (par <> nil) and (i <= High(FParExp)) and not FParExp[i].HasDown
      and par.ExpandOpt and par.TriggerMove then
    begin
      slide := ParExpSlideAt(i, AX, AY, w0, w1);
      ParExpConfigure(i);
      par := FParallels[i];
      if (slide = pslJump) and FParExp[i].ThrActive then
        FParExp[i].DebounceNext := par.ExpandDebounce;
      ParExpCall(i, slide <> pslNone, w0, w1, slide = pslJump);
    end;
    Inc(i);
  end;
end;

{ the throttled function's call (util/throttle.ts cb) }
procedure TTyAdvanceChart.ParExpCall(AIndex: Integer; AHasArgs: Boolean;
  AW0, AW1: Double; AJump: Boolean);
var
  now_, delay, base, diff, deb: Double;
  debounce: Boolean;
  anim: Integer;
begin
  if AJump then anim := 1 else anim := 2;
  now_ := ParExpClock;
  if not FParExp[AIndex].ThrActive then
  begin
    if AHasArgs then ParExpDispatch(AIndex, AW0, AW1, anim, now_);
    Exit;
  end;
  deb := FParExp[AIndex].DebounceNext;
  { `debounceNextCall || delay`, `debounceNextCall || debounce` }
  debounce := (not IsNan(deb)) and (deb <> 0);
  if debounce then delay := deb else delay := FParExp[AIndex].ThrRate;
  FParExp[AIndex].DebounceNext := NaN;
  if debounce then base := FParExp[AIndex].LastCall
  else base := FParExp[AIndex].LastExec;
  diff := now_ - base - delay;
  { clearTimeout(timer) }
  ParExpDropPending(FParExp[AIndex].TimerId);
  FParExp[AIndex].TimerId := 0;
  if debounce then
    ParExpSchedule(AIndex, now_ + delay, AHasArgs, AW0, AW1, AJump)
  else if diff >= 0 then
  begin
    FParExp[AIndex].LastExec := now_;
    if AHasArgs then ParExpDispatch(AIndex, AW0, AW1, anim, now_);
  end
  else
    ParExpSchedule(AIndex, now_ + -diff, AHasArgs, AW0, AW1, AJump);
  if AIndex <= High(FParExp) then FParExp[AIndex].LastCall := now_;
end;

{ _dispatchExpand: parallelAxisExpand with the window -- and the animation
  a move adds: null for a jump, a duration of nought for a slide (AAnim 1,
  2; 0 none) }
procedure TTyAdvanceChart.ParExpDispatch(AIndex: Integer; AW0, AW1: Double;
  AAnim: Integer; ATime: Double);
var
  p: TJSONObject;
  n: Integer;
begin
  n := Length(FParExpLog);
  SetLength(FParExpLog, n + 1);
  FParExpLog[n].Time := ATime;
  FParExpLog[n].Par := AIndex;
  FParExpLog[n].W0 := AW0;
  FParExpLog[n].W1 := AW1;
  case AAnim of
    1: FParExpLog[n].Animation := 'null';
    2: FParExpLog[n].Animation := '{"duration":0}';
  else
    FParExpLog[n].Animation := 'absent';
  end;
  p := TJSONObject.Create;
  p.Add('type', 'parallelAxisExpand');
  p.Add('axisExpandWindow', TJSONArray.Create([AW0, AW1]));
  if AAnim = 1 then p.Add('animation', TJSONNull.Create)
  else if AAnim = 2 then p.Add('animation', TJSONObject.Create(['duration', 0]));
  { the dispatch frees it }
  DispatchActionObject(p);
end;

procedure TTyAdvanceChart.ParExpSchedule(AIndex: Integer; ADue: Double;
  AHasArgs: Boolean; AW0, AW1: Double; AJump: Boolean);
var n: Integer;
begin
  Inc(FParExpSeq);
  n := Length(FParExpPend);
  SetLength(FParExpPend, n + 1);
  FParExpPend[n].Id := FParExpSeq;
  FParExpPend[n].Par := AIndex;
  FParExpPend[n].Gen := FParExp[AIndex].Gen;
  FParExpPend[n].Due := ADue;
  FParExpPend[n].HasArgs := AHasArgs;
  FParExpPend[n].W0 := AW0;
  FParExpPend[n].W1 := AW1;
  FParExpPend[n].Jump := AJump;
  FParExp[AIndex].TimerId := FParExpSeq;
  ParExpArmTimer;
end;

procedure TTyAdvanceChart.ParExpDropPending(AId: Integer);
var i, k: Integer;
begin
  if AId = 0 then Exit;
  for i := 0 to High(FParExpPend) do
    if FParExpPend[i].Id = AId then
    begin
      for k := i to High(FParExpPend) - 1 do FParExpPend[k] := FParExpPend[k + 1];
      SetLength(FParExpPend, Length(FParExpPend) - 1);
      Exit;
    end;
end;

function TTyAdvanceChart.ParExpClock: Double;
begin
  if IsNan(FParExpNow) then Result := GetTickCount64 else Result := FParExpNow;
end;

procedure TTyAdvanceChart.ParallelExpandTick(ANow: Double);
var
  best, i, k: Integer;
  p: TTyParallelExpandPending;
  anim: Integer;
begin
  repeat
    best := -1;
    for i := 0 to High(FParExpPend) do
      if (FParExpPend[i].Due <= ANow) and ((best < 0)
        or (FParExpPend[i].Due < FParExpPend[best].Due)
        or ((FParExpPend[i].Due = FParExpPend[best].Due)
          and (FParExpPend[i].Id < FParExpPend[best].Id))) then
        best := i;
    if best < 0 then Break;
    p := FParExpPend[best];
    for k := best to High(FParExpPend) - 1 do FParExpPend[k] := FParExpPend[k + 1];
    SetLength(FParExpPend, Length(FParExpPend) - 1);
    { exec: its throttle's lastExec is now (a newer throttle's is not) }
    if (p.Par <= High(FParExp)) and (p.Gen = FParExp[p.Par].Gen) then
    begin
      FParExp[p.Par].LastExec := p.Due;
      FParExp[p.Par].TimerId := 0;
    end;
    if p.HasArgs then
    begin
      if p.Jump then anim := 1 else anim := 2;
      ParExpDispatch(p.Par, p.W0, p.W1, anim, p.Due);
    end;
  until False;
  ParExpArmTimer;
end;

procedure TTyAdvanceChart.ParExpArmTimer;
var
  i: Integer;
  due: Double;
begin
  { a test drives the clock itself }
  if not IsNan(FParExpNow) then Exit;
  if Length(FParExpPend) = 0 then
  begin
    if FParExpTimer <> nil then FParExpTimer.Enabled := False;
    Exit;
  end;
  due := FParExpPend[0].Due;
  for i := 1 to High(FParExpPend) do due := Math.Min(due, FParExpPend[i].Due);
  if FParExpTimer = nil then
  begin
    FParExpTimer := TTimer.Create(nil);
    FParExpTimer.OnTimer := @ParExpTimerFired;
  end;
  FParExpTimer.Enabled := False;
  FParExpTimer.Interval := Math.Max(1, Ceil(due - ParExpClock));
  FParExpTimer.Enabled := True;
end;

procedure TTyAdvanceChart.ParExpTimerFired(Sender: TObject);
begin
  FParExpTimer.Enabled := False;
  ParallelExpandTick(ParExpClock);
end;

function TTyAdvanceChart.ParallelExpandActionCount: Integer;
begin
  Result := Length(FParExpLog);
end;

function TTyAdvanceChart.ParallelExpandActionAt(AIndex: Integer): TTyParallelExpandAction;
begin
  Result := Default(TTyParallelExpandAction);
  if (AIndex >= 0) and (AIndex <= High(FParExpLog)) then Result := FParExpLog[AIndex];
end;

procedure TTyAdvanceChart.ParallelExpandClearLog;
begin
  FParExpLog := nil;
end;
