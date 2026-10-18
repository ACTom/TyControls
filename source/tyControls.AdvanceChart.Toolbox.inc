{ Part of tyControls.AdvanceChart (included, not a unit): the toolbox. Moved out of the
  unit only to keep it readable; what the control is and why it is built the way it is,
  see the unit header. }

{ ==================== the toolbox [Batch 125, C16] ====================

  ToolboxView's render, its icons' handlers and the features' clicks. The
  model, the layout and the texts are tyControls.AdvChart.Toolbox; this is
  the state upstream keeps between renders, and where it keeps it:
  - FTbPrev: where each toolbox's group stood -- positionElement starts
    from it, so a re-render's arithmetic is not a first render's;
  - FTbStatus: the features' iconStatus ('<toolbox>|<feature>|<icon>'),
    written into the toolbox's option upstream: a notMerge or a restore
    drops it, a merge keeps it;
  - FTbMagicTitle: magicType's titles a stack click flipped (written into
    the feature's option upstream, so the same);
  - FTbLive: each icon element's hover -- the emphasis the hover entered,
    the title shown, and whether entering applied the emphasis state's
    adjusted text. A render makes new elements, so none of it survives one,
    and an element under a still pointer is found again without a
    mouseover (zrender's Handler looks for a removed hover target where it
    was, and finds the new one: no over, no title);
  - FTbZoomActive: the dataZoom feature's _isZoomActive -- the feature
    object outlives a notMerge and a restore;
  - FTbHistory: dataZoom/history's snapshots, the GlobalModel's: a notMerge
    makes a new model, a restore keeps it (the restore BUTTON clears it
    first);
  - FTbSel: setRawRange on the select dataZooms, by axis key;
  - FTbBackup: the option a restore recreates, OptionManager's
    _optionBackup -- the last notMerge's. }

function TTyAdvanceChart.TbTitles: TTyTbTitles;
begin
  Result := Default(TTyTbTitles);
  Result.SaveAsImage := rsTyChartToolboxSaveAsImage;
  Result.Restore := rsTyChartToolboxRestore;
  Result.DataView := rsTyChartToolboxDataView;
  Result.Zoom := rsTyChartToolboxZoom;
  Result.Back := rsTyChartToolboxZoomBack;
  Result.Line := rsTyChartToolboxLine;
  Result.Bar := rsTyChartToolboxBar;
  Result.Stack := rsTyChartToolboxStack;
  Result.Tiled := rsTyChartToolboxTiled;
  Result.DataViewClose := rsMsgBtnClose;
  Result.DataViewRefresh := rsTyChartToolboxDataViewRefresh;
  { the brush feature's [Batch 127] }
  Result.BrushRect := rsTyChartToolboxBrushRect;
  Result.BrushPolygon := rsTyChartToolboxBrushPolygon;
  Result.BrushLineX := rsTyChartToolboxBrushLineX;
  Result.BrushLineY := rsTyChartToolboxBrushLineY;
  Result.BrushKeep := rsTyChartToolboxBrushKeep;
  Result.BrushClear := rsTyChartToolboxBrushClear;
end;

function TTyAdvanceChart.TbScale: Double;
begin
  if FLastPPI > 0 then Result := FLastPPI / 96 else Result := 1;
end;

function TTyAdvanceChart.TbInk: TTyTbInk;
var
  model: TTyStyleModel;
  st: TTyStyleSet;
begin
  model := ActiveController.Model;
  st := model.ResolveStyle('TyAdvChartToolbox', '', []);
  Result.Stroke := TTyChartColor(st.BorderColor);
  Result.FontName := st.FontName;
  Result.FontSizeLogical := ResolveFontSize(st);
  Result.FontWeight := st.FontWeight;
  Result.Title := TTyChartColor(st.TextColor);
  GlobalInk(Result.FontName, Result.FontSizeLogical, Result.FontWeight,
    Result.Title, [ttpSize, ttpWeight, ttpFamily]);
  Result.StrokeHover := TTyChartColor(
    model.ResolveStyle('TyAdvChartToolbox', '', [tysHover]).BorderColor);
  Result.Background := TTyChartColor(
    model.ResolveStyle('TyAdvChartToolboxBackground', '', []).Background.Color);
  Result.Border := TTyChartColor(
    model.ResolveStyle('TyAdvChartToolboxBorder', '', []).BorderColor);
  Result.Brush := TTyChartColor(
    model.ResolveStyle('TyAdvChartToolboxBrush', '', []).Background.Color);
end;

{ a written colour, the skin's where nothing was written; False: `none` }
function TbColour(const C: TTyTbColour; AFallback: TTyChartColor;
  out AColour: TTyChartColor): Boolean;
begin
  AColour := AFallback;
  case C.Kind of
    tbcNone: Exit(False);
    tbcText:
      if not TyTryParseChartColor(C.Text, AColour) then AColour := AFallback;
  end;
  Result := True;
end;

function TTyAdvanceChart.TbStatusOf(ATb: Integer): TStringList;
var
  i: Integer;
  pre, k: string;
begin
  Result := TStringList.Create;
  pre := IntToStr(ATb) + '|';
  for i := 0 to FTbStatus.Count - 1 do
  begin
    k := FTbStatus.Names[i];
    if Copy(k, 1, Length(pre)) = pre then
      Result.Values[Copy(k, Length(pre) + 1, MaxInt)] := FTbStatus.ValueFromIndex[i];
  end;
end;

procedure TTyAdvanceChart.TbSetStatus(ATb: Integer; const AFeature, AIcon,
  AState: string);
begin
  FTbStatus.Values[IntToStr(ATb) + '|' + AFeature + '|' + AIcon] := AState;
end;

function TTyAdvanceChart.TbStatusIs(ATb: Integer; const AFeature,
  AIcon: string): Boolean;
begin
  Result := FTbStatus.Values[IntToStr(ATb) + '|' + AFeature + '|' + AIcon] = 'emphasis';
end;

{ the feature exists and shows: its object lives }
function TTyAdvanceChart.TbHasFeature(ATb: Integer; const AName: string): Boolean;
var d: TJSONData;
begin
  Result := False;
  d := FOption.ComponentAt('toolbox', ATb);
  if not (d is TJSONObject) then Exit;
  d := TJSONObject(d).Find('feature');
  if not (d is TJSONObject) then Exit;
  d := TJSONObject(d).Find(AName);
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  Result := True;
  if d is TJSONObject then
  begin
    d := TJSONObject(d).Find('show');
    if (d <> nil) and (d.JSONType = jtBoolean) and not d.AsBoolean then Result := False;
  end;
end;

procedure TTyAdvanceChart.SolveToolboxes(const AMeasurer: ITyTextMeasurer;
  APPI: Integer);
var
  n, t, i: Integer;
  st: TStringList;
  s, w, h, tw, th: Double;
  ws, hs: TTyDoubleArray;
  ink: TTyTbInk;
  dzOn: Boolean;
  ref: TTyXYWH;
begin
  n := TyToolboxCount(FOption);
  { a toolbox that went takes its view (and where it stood) with it }
  i := Length(FTbPrev);
  SetLength(FTbPrev, n);
  for t := i to n - 1 do FTbPrev[t] := TyPointF(0, 0);
  SetLength(FTbSpecs, n);
  SetLength(FTbLayouts, n);
  i := Length(FTbMagicTitle);
  SetLength(FTbMagicTitle, n);
  for t := i to n - 1 do FTbMagicTitle[t] := '';
  SetLength(FTbLive, n);
  { NEW ELEMENTS: whatever was hovered is found again, not entered }
  Inc(FTbGen);
  s := TbScale;
  w := (FLastRect.Right - FLastRect.Left) / s;
  h := (FLastRect.Bottom - FLastRect.Top) / s;
  ink := TbInk;
  dzOn := False;
  for t := 0 to n - 1 do
  begin
    { the dataZoom feature's buttons, at every render: zoom by the active
      flag, back by the history }
    if TbHasFeature(t, 'dataZoom') then
    begin
      if t = 0 then dzOn := True;
      if FTbZoomActive then TbSetStatus(t, 'dataZoom', 'zoom', 'emphasis')
      else TbSetStatus(t, 'dataZoom', 'zoom', 'normal');
      if TyTbHistoryCount(FTbHistory) > 1 then TbSetStatus(t, 'dataZoom', 'back', 'emphasis')
      else TbSetStatus(t, 'dataZoom', 'back', 'normal');
    end;
    { the brush feature's buttons, at every render [Batch 127] }
    if TbHasFeature(t, 'brush') then TbBrushRender(t);
    st := TbStatusOf(t);
    try
      FTbSpecs[t] := TyToolboxSpecOf(FOption, t, TbTitles, st, FTbMagicTitle[t]);
    finally
      st.Free;
    end;
    { the titles in the default font -- 12 px, whatever the title's own is }
    SetLength(ws, Length(FTbSpecs[t].Icons));
    SetLength(hs, Length(FTbSpecs[t].Icons));
    for i := 0 to High(FTbSpecs[t].Icons) do
    begin
      ws[i] := 0;
      hs[i] := 0;
      if FTbSpecs[t].Icons[i].HasTitle and (FTbSpecs[t].Icons[i].Title <> '')
        and (AMeasurer <> nil) then
      begin
        AMeasurer.MeasureLine(FTbSpecs[t].Icons[i].Title, ink.FontName,
          Round(12 * APPI / 96), 400, tw, th);
        ws[i] := tw / s;
        hs[i] := th / s;
      end;
    end;
    { getLayoutRect and positionElement in createBoxLayoutReference's
      container: a cell or a day for one in a host [Batch 154] }
    ComponentRefCss('toolbox', t, ref);
    FTbLayouts[t] := TyToolboxLayoutOf(FTbSpecs[t], w, h, ref, FTbPrev[t].X,
      FTbPrev[t].Y, ws, hs);
    if FTbLayouts[t].Valid then
      FTbPrev[t] := TyPointF(FTbLayouts[t].GroupX, FTbLayouts[t].GroupY);
    FTbLive[t] := nil;
    SetLength(FTbLive[t], Length(FTbSpecs[t].Icons));
    { the status's emphasis is applied when the update ends -- after the
      adjustment wrote the state: the text's adjusted align comes with it }
    for i := 0 to High(FTbSpecs[t].Icons) do
      FTbLive[t][i].AdjAlign := FTbSpecs[t].Icons[i].Status;
  end;
  { a dataZoom feature that went takes its active flag with it }
  if not dzOn then FTbZoomActive := False;
  { the statuses an update took at its dispatch are spent [Batch 127] }
  FTbBfSnap := False;
  { updateZoomBtnStatus: the select brush's panels, on or off [Batch 127] }
  TbZoomCtlSync;
end;

{ zrender's composition of the group's move and the icon's: a move inside
  the epsilon is no transform at all }
function TbNotAroundZero(V: Double): Boolean;
begin
  Result := (V > 5e-5) or (V < -5e-5);
end;

procedure TTyAdvanceChart.TbIconOrigin(ATb, AIcon: Integer; out AX, AY: Double);
var gx, gy, x, y: Double;
begin
  gx := FTbLayouts[ATb].GroupX;
  gy := FTbLayouts[ATb].GroupY;
  x := FTbSpecs[ATb].Icons[AIcon].X;
  y := FTbSpecs[ATb].Icons[AIcon].Y;
  if TbNotAroundZero(x) or TbNotAroundZero(y) then
  begin
    if TbNotAroundZero(gx) or TbNotAroundZero(gy) then
    begin
      AX := x + gx;
      AY := y + gy;
    end
    else
    begin
      AX := x;
      AY := y;
    end;
  end
  else if TbNotAroundZero(gx) or TbNotAroundZero(gy) then
  begin
    AX := gx;
    AY := gy;
  end
  else
  begin
    AX := 0;
    AY := 0;
  end;
end;

function TTyAdvanceChart.TbEmphasised(ATb, AIcon: Integer): Boolean;
begin
  Result := FTbSpecs[ATb].Icons[AIcon].Status;
  if (ATb <= High(FTbLive)) and (AIcon <= High(FTbLive[ATb])) then
    Result := Result or FTbLive[ATb][AIcon].HoverEmph;
end;

function TTyAdvanceChart.BuildToolboxes(AList: TTyPaintList;
  const AMeasurer: ITyTextMeasurer): Integer;
var
  t, i: Integer;
  ink: TTyTbInk;
  s, ox, oy, tw, th, l, tp: Double;
  el: TTyChartElement;
  c: TTyChartColor;
  sty: TTyTbItemStyle;
  emph: Boolean;
  r: TTyXYWH;
  place: TTyTbTitlePlace;
  rad: array of Double;
  fs: Integer;
  pr: TTyRectF;

  function Blank: TTyChartElement;
  begin
    Result := Default(TTyChartElement);
    Result.Silent := True;
    Result.Datum := TyChartDatum(-1, -1);
    Result.Z := FTbSpecs[t].Z;
    Result.Style.Alpha := 1;
  end;

begin
  Result := 0;
  ink := TbInk;
  s := TbScale;
  for t := 0 to High(FTbLayouts) do
  begin
    if (t > High(FTbSpecs)) or not FTbLayouts[t].Valid then Continue;
    { a group a degenerate icon placed at NaN draws nothing at all }
    if IsNan(FTbLayouts[t].GroupX) or IsNan(FTbLayouts[t].GroupY) then Continue;
    { the background, under the icons }
    r := FTbLayouts[t].Background;
    el := Blank;
    el.Z2 := -1;
    if IsNan(r.X) or IsNan(r.Y) or IsNan(r.W) or IsNan(r.H) then r := Default(TTyXYWH);
    pr := TyRectF(FLastRect.Left + s * (FTbLayouts[t].GroupX + r.X),
      FLastRect.Top + s * (FTbLayouts[t].GroupY + r.Y),
      FLastRect.Left + s * (FTbLayouts[t].GroupX + r.X + r.W),
      FLastRect.Top + s * (FTbLayouts[t].GroupY + r.Y + r.H));
    SetLength(rad, Length(FTbSpecs[t].Radius));
    for i := 0 to High(rad) do rad[i] := FTbSpecs[t].Radius[i] * s;
    if Length(rad) > 0 then el.Shape := TyShapeRoundRect(pr, rad)
    else el.Shape := TyShapeRect(pr);
    if TbColour(FTbSpecs[t].Background, ink.Background, c) and ((c shr 24) <> 0) then
    begin
      el.Style.HasFill := True;
      el.Style.FillColor := c;
    end;
    if (FTbSpecs[t].BorderWidth > 0) and TbColour(FTbSpecs[t].BorderColor, ink.Border, c) then
    begin
      el.Style.StrokeColor := c;
      el.Style.StrokeWidthLogical := FTbSpecs[t].BorderWidth;
    end;
    if el.Style.HasFill or (el.Style.StrokeWidthLogical > 0) then
    begin
      AList.Add(el);
      Inc(Result);
    end;
    { the icons }
    for i := 0 to High(FTbSpecs[t].Icons) do
    begin
      { [F6a] AN IMAGE ICON: createIcon's ZRImage over the whole item box,
        with the icon style's opacity and nothing else of it }
      if FTbSpecs[t].Icons[i].IsImage then
      begin
        TbIconOrigin(t, i, ox, oy);
        if IsNan(ox) or IsNan(oy) then Continue;
        r := TyToolboxIconRect(FTbSpecs[t], FTbSpecs[t].Icons[i], False);
        el := Blank;
        el.Shape := TyShapePolygon([
          TyPointF(FLastRect.Left + s * (ox + r.X), FLastRect.Top + s * (oy + r.Y)),
          TyPointF(FLastRect.Left + s * (ox + r.X + r.W), FLastRect.Top + s * (oy + r.Y)),
          TyPointF(FLastRect.Left + s * (ox + r.X + r.W), FLastRect.Top + s * (oy + r.Y + r.H)),
          TyPointF(FLastRect.Left + s * (ox + r.X), FLastRect.Top + s * (oy + r.Y + r.H))]);
        el.Shape.Image := FTbSpecs[t].Icons[i].IconText;
        sty := TyTbStyleOf(FTbSpecs[t].Icons[i], TbEmphasised(t, i));
        if sty.HasOpacity and not IsNan(sty.Opacity) then
          el.Style.Alpha := Max(0, Min(1, sty.Opacity));
        AList.Add(el);
        Inc(Result);
        Continue;
      end;
      { a degenerate path draws nothing, NaN through and through }
      if IsNan(FTbSpecs[t].Icons[i].PathRect.X) or IsNan(FTbSpecs[t].Icons[i].PathRect.Y)
        or IsNan(FTbSpecs[t].Icons[i].PathRect.W) or IsNan(FTbSpecs[t].Icons[i].PathRect.H) then
        Continue;
      emph := TbEmphasised(t, i);
      sty := TyTbStyleOf(FTbSpecs[t].Icons[i], emph);
      TbIconOrigin(t, i, ox, oy);
      if IsNan(ox) or IsNan(oy) then Continue;
      el := Blank;
      el.Shape := TyMkZrShape(FTbSpecs[t].Icons[i].Path, TyZrLocal(s, s, 0,
        FLastRect.Left + s * ox, FLastRect.Top + s * oy), True);
      if emph then c := ink.StrokeHover else c := ink.Stroke;
      if TbColour(sty.Stroke, c, c) and (sty.LineWidth > 0) then
      begin
        el.Style.StrokeColor := c;
        el.Style.StrokeWidthLogical := sty.LineWidth;
      end;
      if sty.HasFill and TbColour(sty.Fill, 0, c) and (sty.Fill.Kind = tbcText) then
      begin
        el.Style.HasFill := True;
        el.Style.FillColor := c;
      end;
      if sty.HasOpacity and not IsNan(sty.Opacity) then
        el.Style.Alpha := Max(0, Min(1, sty.Opacity));
      AList.Add(el);
      Inc(Result);
    end;
    { the titles under the pointer }
    for i := 0 to High(FTbSpecs[t].Icons) do
    begin
      if (t > High(FTbLive)) or (i > High(FTbLive[t])) or not FTbLive[t][i].TextShown then Continue;
      if not FTbSpecs[t].Icons[i].HasTitle or (FTbSpecs[t].Icons[i].Title = '') then Continue;
      emph := TbEmphasised(t, i);
      place := TyToolboxTitlePlace(FTbSpecs[t], FTbLayouts[t], i,
        FTbLive[t][i].AdjPos, FTbLive[t][i].AdjAlign, emph);
      if IsNan(place.X) or IsNan(place.Y) then Continue;
      el := Blank;
      el.Z2 := 1;
      fs := ink.FontSizeLogical;
      if FTbSpecs[t].Icons[i].TextFontSize > 0 then fs := Round(FTbSpecs[t].Icons[i].TextFontSize);
      tw := 0;
      th := 0;
      if AMeasurer <> nil then
        AMeasurer.MeasureLine(FTbSpecs[t].Icons[i].Title, ink.FontName,
          Round(fs * s), ink.FontWeight, tw, th);
      el.Caption.Text := FTbSpecs[t].Icons[i].Title;
      el.Caption.FontName := ink.FontName;
      el.Caption.FontSizeLogical := fs;
      el.Caption.FontWeight := ink.FontWeight;
      { textFill, else the emphasis fill, else its stroke }
      sty := TyTbStyleOf(FTbSpecs[t].Icons[i], True);
      if FTbSpecs[t].Icons[i].TextFill.Kind = tbcText then
        TbColour(FTbSpecs[t].Icons[i].TextFill, ink.StrokeHover, c)
      else if FTbSpecs[t].Icons[i].Emph.HasFill
        and (FTbSpecs[t].Icons[i].Emph.Fill.Kind = tbcText) then
        TbColour(FTbSpecs[t].Icons[i].Emph.Fill, ink.StrokeHover, c)
      else
        TbColour(sty.Stroke, ink.StrokeHover, c);
      el.Caption.Colour := c;
      el.Caption.X := FLastRect.Left + s * place.X;
      el.Caption.Y := FLastRect.Top + s * place.Y;
      if place.Align = 'center' then el.Caption.AnchorH := tahCentre
      else if place.Align = 'right' then el.Caption.AnchorH := tahRight
      else el.Caption.AnchorH := tahLeft;
      if place.VAlign = 'middle' then el.Caption.AnchorV := tavMiddle
      else if place.VAlign = 'bottom' then el.Caption.AnchorV := tavBottom
      else el.Caption.AnchorV := tavTop;
      case el.Caption.AnchorH of
        tahCentre: l := el.Caption.X - tw / 2;
        tahRight: l := el.Caption.X - tw;
      else
        l := el.Caption.X;
      end;
      case el.Caption.AnchorV of
        tavMiddle: tp := el.Caption.Y - th / 2;
        tavBottom: tp := el.Caption.Y - th;
      else
        tp := el.Caption.Y;
      end;
      el.Shape := TyShapeRect(TyRectF(l, tp, l + tw, tp + th));
      AList.Add(el);
      Inc(Result);
    end;
  end;
  { the brush's cover while it is drawn (the controller's) [Batch 127] }
  if (FTbBrushCtl <> nil) and (Length(FTbBrushCtl.Covers) > 0) then
  begin
    el := Default(TTyChartElement);
    el.Silent := True;
    el.Datum := TyChartDatum(-1, -1);
    el.Z := 10000;
    el.Style.Alpha := 1;
    r := FTbBrushCtl.Covers[0].Main;
    el.Shape := TyShapeRect(TyRectF(FBuild.Viewport.Left + s * r.X,
      FBuild.Viewport.Top + s * r.Y, FBuild.Viewport.Left + s * (r.X + r.W),
      FBuild.Viewport.Top + s * (r.Y + r.H)));
    el.Style.HasFill := True;
    el.Style.FillColor := ink.Brush;
    AList.Add(el);
    Inc(Result);
  end;
end;

function TTyAdvanceChart.TbHitAt(AX, AY: Integer; out ATb, AIcon: Integer): Boolean;
var
  t, i: Integer;
  s, x, y, ox, oy: Double;
  r: TTyXYWH;
begin
  Result := False;
  ATb := -1;
  AIcon := -1;
  if csDesigning in ComponentState then Exit;
  s := TbScale;
  x := (AX - FLastRect.Left) / s;
  y := (AY - FLastRect.Top) / s;
  { zrender's Handler hit-tests nothing outside the canvas }
  if (x < 0) or (y < 0) or (x > (FLastRect.Right - FLastRect.Left) / s)
    or (y > (FLastRect.Bottom - FLastRect.Top) / s) then Exit;
  for t := High(FTbLayouts) downto 0 do
  begin
    if (t > High(FTbSpecs)) or not FTbLayouts[t].Valid then Continue;
    for i := High(FTbSpecs[t].Icons) downto 0 do
    begin
      { rectHover: the element's own rect, through its transform }
      r := TyToolboxIconRect(FTbSpecs[t], FTbSpecs[t].Icons[i], TbEmphasised(t, i));
      TbIconOrigin(t, i, ox, oy);
      { a degenerate icon's NaN rect contains nothing, as a comparison with
        NaN is false }
      if IsNan(r.X) or IsNan(r.Y) or IsNan(r.W) or IsNan(r.H) or IsNan(ox) or IsNan(oy) then
        Continue;
      if (x - ox >= r.X) and (x - ox <= r.X + r.W) and (y - oy >= r.Y)
        and (y - oy <= r.Y + r.H) then
      begin
        ATb := t;
        AIcon := i;
        Exit(True);
      end;
    end;
  end;
end;

procedure TTyAdvanceChart.TbChanged;
begin
  DropStatic;
  FZrDirty := True;
  inherited Invalidate;
end;

{ the icon's mouseover: the title shown at once (its position the
  mouseover's), the emphasis entered at the next frame -- with the state's
  adjusted text config -- unless the element is already in it }
procedure TTyAdvanceChart.TbMouseOver(const ATarget: TTyChartEventTarget);
var t, i: Integer;
begin
  if (ATarget.HdKind <> 8) or (ATarget.HdGen <> FTbGen) then Exit;
  t := ATarget.HdSeries;
  i := ATarget.HdRow;
  if (t > High(FTbLive)) or (i < 0) or (i > High(FTbLive[t])) then Exit;
  FTbLive[t][i].TextShown := FTbSpecs[t].ShowTitle;
  FTbLive[t][i].PendLeave := False;
  if not TbEmphasised(t, i) then FTbLive[t][i].PendEnter := True;
  TbChanged;
end;

{ the icon's mouseout: the emphasis left at the next frame unless the
  feature's status holds it; the title hidden at once }
procedure TTyAdvanceChart.TbMouseOut(const ATarget: TTyChartEventTarget);
var t, i: Integer;
begin
  if (ATarget.HdKind <> 8) or (ATarget.HdGen <> FTbGen) then Exit;
  t := ATarget.HdSeries;
  i := ATarget.HdRow;
  if (t > High(FTbLive)) or (i < 0) or (i > High(FTbLive[t])) then Exit;
  FTbLive[t][i].PendEnter := False;
  if not TbStatusIs(t, FTbSpecs[t].Icons[i].Feature, FTbSpecs[t].Icons[i].Name)
    and FTbLive[t][i].HoverEmph then FTbLive[t][i].PendLeave := True;
  FTbLive[t][i].TextShown := False;
  TbChanged;
end;

{ echarts' _onframe: the hover's emphasis changes applied -- entering brings
  the state's adjusted position and align, leaving takes them away }
procedure TTyAdvanceChart.TbFrame;
var
  t, i: Integer;
  any: Boolean;
begin
  any := False;
  for t := 0 to High(FTbLive) do
    for i := 0 to High(FTbLive[t]) do
    begin
      if FTbLive[t][i].PendEnter then
      begin
        FTbLive[t][i].PendEnter := False;
        FTbLive[t][i].HoverEmph := True;
        FTbLive[t][i].AdjPos := True;
        FTbLive[t][i].AdjAlign := True;
        any := True;
      end;
      if FTbLive[t][i].PendLeave then
      begin
        FTbLive[t][i].PendLeave := False;
        FTbLive[t][i].HoverEmph := False;
        FTbLive[t][i].AdjPos := False;
        FTbLive[t][i].AdjAlign := False;
        any := True;
      end;
    end;
  if any then TbChanged;
end;

procedure TTyAdvanceChart.TbClick(ATb, AIcon: Integer);
var
  f, ic, nm: string;
  h: TTyChartToolboxHandler;
begin
  if (ATb > High(FTbSpecs)) or (AIcon < 0) or (AIcon > High(FTbSpecs[ATb].Icons)) then Exit;
  f := FTbSpecs[ATb].Icons[AIcon].Feature;
  ic := FTbSpecs[ATb].Icons[AIcon].Name;
  if FTbSpecs[ATb].Icons[AIcon].IsUser then
  begin
    { onclick: '@Name' }
    nm := FTbSpecs[ATb].Icons[AIcon].OnClick;
    if TyChartIsHandlerRef(nm) and TyChartFindToolboxHandler(Copy(nm, 2, MaxInt), h) then
      h(Self, f, ic);
    Exit;
  end;
  if f = 'saveAsImage' then TbSaveAsImage(ATb)
  else if f = 'restore' then
  begin
    { history.clear, then the action }
    FTbHistory := nil;
    DispatchAction('{"type":"restore"}');
  end
  else if f = 'dataView' then TbDataView(ATb)
  else if f = 'dataZoom' then
  begin
    if ic = 'zoom' then
    begin
      if FTbZoomActive then
        DispatchAction('{"type":"takeGlobalCursor","key":"dataZoomSelect","dataZoomSelectActive":false}')
      else
        DispatchAction('{"type":"takeGlobalCursor","key":"dataZoomSelect","dataZoomSelectActive":true}');
    end
    else if ic = 'back' then TbBack;
  end
  else if f = 'magicType' then TbMagicType(ATb, ic)
  else if f = 'brush' then TbBrushClick(ic);
end;

function TTyAdvanceChart.ToolboxClick(ATb: Integer; const AFeature, AIcon: string): Boolean;
var i: Integer;
begin
  Result := False;
  if (ATb < 0) or (ATb > High(FTbSpecs)) then Exit;
  for i := 0 to High(FTbSpecs[ATb].Icons) do
    if (FTbSpecs[ATb].Icons[i].Feature = AFeature) and (FTbSpecs[ATb].Icons[i].Name = AIcon) then
    begin
      TbClick(ATb, i);
      Exit(True);
    end;
end;

procedure TTyAdvanceChart.TbDoRestore(APayload: TJSONObject);
var h: TTyTbHistory;
begin
  { resetOption('recreate'): new models from the backup -- the same
    GlobalModel, so the history stays }
  h := FTbHistory;
  ApplyNotMerge(FTbBackup);
  FTbHistory := h;
  AfterSetOption(False, True);
  EmitPayloadEvent('restore', TbEventJson(APayload, 'restore'));
end;

function TTyAdvanceChart.TbMagicSeries: TTyMagicSeriesArray;
var
  i, n, slot: Integer;
  d: TJSONData;
  b: TTySeriesBinding;
begin
  n := FOption.ComponentCount('series');
  Result := nil;
  for i := 0 to n - 1 do
  begin
    d := FOption.ComponentAt('series', i);
    if not (d is TJSONObject) then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Index := i;
    Result[High(Result)].Node := TJSONObject(d);
    Result[High(Result)].SubType := FOption.ComponentSubType('series', i);
    Result[High(Result)].Cartesian := False;
    Result[High(Result)].CatDim := '';
    Result[High(Result)].CatIndex := -1;
    slot := SlotOfSeries(i);
    if slot < 0 then Continue;
    b := FBindings[slot];
    if (b.Cart = nil) or (b.CoordSysName <> 'cartesian2d') then Continue;
    Result[High(Result)].Cartesian := True;
    { getAxesByScale('ordinal')[0]: x before y }
    if (b.XAxis <> nil) and (b.XAxis.AxisType = atCategory) then
    begin
      Result[High(Result)].CatDim := 'x';
      Result[High(Result)].CatIndex := b.XAxis.ComponentIndex;
    end
    else if (b.YAxis <> nil) and (b.YAxis.AxisType = atCategory) then
    begin
      Result[High(Result)].CatDim := 'y';
      Result[High(Result)].CatIndex := b.YAxis.ComponentIndex;
    end;
  end;
end;

procedure TTyAdvanceChart.TbMagicType(ATb: Integer; const AType: string);
var
  fm, opt, ttl, pay: TJSONObject;
  st: TStringList;
  cur: string;
  i: Integer;
begin
  fm := TyToolboxFeatureModel(FOption, ATb, 'magicType', TbTitles);
  if fm = nil then Exit;
  st := TbStatusOf(ATb);
  ttl := nil;
  opt := nil;
  try
    { the titles a stack click wrote into the feature }
    if (ATb <= High(FTbMagicTitle)) and (FTbMagicTitle[ATb] <> '') then
    begin
      if fm.IndexOfName('title') >= 0 then fm.Delete('title');
      fm.Add('title', GetJSON(FTbMagicTitle[ATb]));
    end;
    opt := TyMagicTypeOption(fm, AType, TbMagicSeries, st, cur, ttl);
    if opt = nil then Exit;
    { the statuses it set, on the feature's option }
    for i := 0 to st.Count - 1 do
      if Copy(st.Names[i], 1, 10) = 'magicType|' then
        FTbStatus.Values[IntToStr(ATb) + '|' + st.Names[i]] := st.ValueFromIndex[i];
    pay := TJSONObject.Create;
    try
      pay.Add('type', 'changeMagicType');
      pay.Add('currentType', cur);
      pay.Add('newOption', opt);
      opt := nil;
      if ttl <> nil then
      begin
        pay.Add('newTitle', ttl);
        ttl := nil;
      end;
      pay.Add('featureName', 'magicType');
      DispatchAction(TyTbJson(pay));
    finally
      pay.Free;
    end;
  finally
    opt.Free;
    ttl.Free;
    st.Free;
    fm.Free;
  end;
end;

procedure TTyAdvanceChart.TbDoMagic(APayload: TJSONObject);
var
  d, ft: TJSONData;
  t: Integer;
begin
  d := APayload.Find('newOption');
  if d is TJSONObject then
  begin
    if DoMerge(TyTbJson(d), []) then AfterSetOption(False, True);
  end;
  { the toolbox's render takes newTitle into the feature it names }
  d := APayload.Find('newTitle');
  ft := APayload.Find('featureName');
  if (d <> nil) and (d.JSONType <> jtNull) and (ft <> nil) and (ft.JSONType = jtString)
    and (ft.AsString = 'magicType') then
  begin
    SetLength(FTbMagicTitle, Max(Length(FTbMagicTitle), TyToolboxCount(FOption)));
    for t := 0 to High(FTbMagicTitle) do FTbMagicTitle[t] := TyTbJson(d);
  end;
  EmitPayloadEvent('magictypechanged', TbEventJson(APayload, 'magictypechanged'));
end;

{ getContentFromModel's two kinds of series, from the stores }
function TTyAdvanceChart.TbDataViewContent(out AMeta: TTyDvMetaArray): string;
var
  groups: TTyDvGroupArray;
  lists: TTyDvListArray;
  keys: TTyStringArray;
  i, n, slot, g, k, r, dim: Integer;
  b: TTySeriesBinding;
  st: TTyDataStore;
  key: string;
  cats: TTyOrdinalMeta;
  dims: TTyIntegerArray;
  col: TTyDoubleArray;
  isCat: Boolean;
  nm: string;
begin
  groups := nil;
  lists := nil;
  keys := nil;
  AMeta := nil;
  n := FOption.ComponentCount('series');
  for i := 0 to n - 1 do
  begin
    slot := SlotOfSeries(i);
    if (slot < 0) or (slot > High(FStores)) or (FStores[slot] = nil) then Continue;
    b := FBindings[slot];
    st := FStores[slot];
    isCat := ((b.Cart <> nil) or (b.Polar <> nil)) and (b.BaseAxis <> nil)
      and (b.BaseAxis.AxisType = atCategory) and (b.ValueAxis <> nil);
    nm := FOption.ComponentModelName('series', i);
    if isCat then
    begin
      key := b.BaseAxis.Dim + '_' + IntToStr(b.BaseAxis.ComponentIndex);
      g := -1;
      for k := 0 to High(keys) do
        if keys[k] = key then g := k;
      if g < 0 then
      begin
        g := Length(groups);
        SetLength(groups, g + 1);
        SetLength(keys, g + 1);
        keys[g] := key;
        groups[g].AxisDim := b.BaseAxis.Dim;
        groups[g].AxisIndex := b.BaseAxis.ComponentIndex;
        cats := b.BaseAxis.Categories;
        if cats <> nil then
        begin
          SetLength(groups[g].Categories, cats.Count);
          for k := 0 to cats.Count - 1 do groups[g].Categories[k] := cats.CategoryAt(k);
        end;
        SetLength(AMeta, g + 1);
        AMeta[g].AxisDim := b.BaseAxis.Dim;
        AMeta[g].AxisIndex := b.BaseAxis.ComponentIndex;
      end;
      SetLength(groups[g].Names, Length(groups[g].Names) + 1);
      groups[g].Names[High(groups[g].Names)] := nm;
      dims := st.DimsOfCoord(b.ValueAxis.Dim);
      col := nil;
      if (Length(dims) > 0) and (dims[0] >= 0) then
      begin
        SetLength(col, st.RawCount);
        for r := 0 to st.RawCount - 1 do col[r] := st.GetOriginalByRaw(dims[0], r);
      end;
      SetLength(groups[g].Columns, Length(groups[g].Columns) + 1);
      groups[g].Columns[High(groups[g].Columns)] := col;
    end
    else
    begin
      k := Length(lists);
      SetLength(lists, k + 1);
      lists[k].Name := nm;
      SetLength(lists[k].RowNames, st.RawCount);
      SetLength(lists[k].Rows, st.RawCount);
      for r := 0 to st.RawCount - 1 do
      begin
        lists[k].RowNames[r] := st.GetNameByRaw(r);
        col := nil;
        for dim := 0 to st.DimCount - 1 do
        begin
          { the stack's two columns are in the raw data upstream; no other
            column of the port's own }
          if (Copy(st.DimName(dim), 1, 5) = '__ty_')
            and (Copy(st.DimName(dim), 1, 16) <> '__ty_stackresult')
            and (Copy(st.DimName(dim), 1, 16) <> '__ty_stackedover') then Continue;
          SetLength(col, Length(col) + 1);
          if Copy(st.DimName(dim), 1, 5) = '__ty_' then col[High(col)] := st.GetByRaw(dim, r)
          else col[High(col)] := st.GetOriginalByRaw(dim, r);
        end;
        lists[k].Rows[r] := col;
      end;
    end;
  end;
  Result := TyDataViewText(groups, lists);
end;

function TTyAdvanceChart.ToolboxDataViewText: string;
var meta: TTyDvMetaArray;
begin
  Result := TbDataViewContent(meta);
end;

function TTyAdvanceChart.TbDvFind(const AName: string; out AData: TJSONData): Boolean;
var
  i: Integer;
  d: TJSONData;
begin
  Result := False;
  AData := nil;
  for i := 0 to FOption.ComponentCount('series') - 1 do
    if FOption.ComponentModelName('series', i) = AName then
    begin
      d := FOption.ComponentAt('series', i);
      if d is TJSONObject then AData := TJSONObject(d).Find('data');
      Exit(True);
    end;
end;

procedure TTyAdvanceChart.TbDataView(ATb: Integer);
var
  fm, parsed, pay: TJSONObject;
  meta: TTyDvMetaArray;
  body, title, closeC, refreshC, err: string;
  d: TJSONData;
  ro: Boolean;
begin
  FTbError := '';
  fm := TyToolboxFeatureModel(FOption, ATb, 'dataView', TbTitles);
  if fm = nil then Exit;
  try
    body := TbDataViewContent(meta);
    d := fm.Find('readOnly');
    ro := (d <> nil) and (((d.JSONType = jtBoolean) and d.AsBoolean)
      or ((d.JSONType = jtNumber) and (d.AsFloat <> 0))
      or ((d.JSONType = jtString) and (d.AsString <> '')));
    { lang[0] || title; lang[1], lang[2] the buttons }
    title := '';
    closeC := rsMsgBtnClose;
    refreshC := rsTyChartToolboxDataViewRefresh;
    d := fm.Find('lang');
    if d is TJSONArray then
    begin
      if (TJSONArray(d).Count > 0) and (TJSONArray(d).Items[0].JSONType = jtString) then
        title := TJSONArray(d).Items[0].AsString;
      if (TJSONArray(d).Count > 1) and (TJSONArray(d).Items[1].JSONType = jtString) then
        closeC := TJSONArray(d).Items[1].AsString;
      if (TJSONArray(d).Count > 2) and (TJSONArray(d).Items[2].JSONType = jtString) then
        refreshC := TJSONArray(d).Items[2].AsString;
    end;
    if title = '' then
    begin
      d := fm.Find('title');
      if (d <> nil) and (d.JSONType = jtString) then title := d.AsString;
    end;
  finally
    fm.Free;
  end;
  if not ToolboxShowDataView(title, body, ro, closeC, refreshC) then Exit;
  body := StringReplace(StringReplace(body, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
  parsed := TyDataViewParse(body, meta, err);
  if parsed = nil then
  begin
    { upstream throws 'Data view format error' after closing }
    FTbError := Format(rsTyChartToolboxDataViewBad, [err]);
    Exit;
  end;
  pay := TJSONObject.Create;
  try
    pay.Add('type', 'changeDataView');
    pay.Add('newOption', parsed);
    DispatchAction(TyTbJson(pay));
  finally
    pay.Free;
  end;
end;

procedure TTyAdvanceChart.TbDoDataView(APayload: TJSONObject);
var
  d: TJSONData;
  merged: TJSONObject;
begin
  d := APayload.Find('newOption');
  if d is TJSONObject then
  begin
    merged := TyDataViewChange(TJSONObject(d), @TbDvFind);
    try
      if DoMerge(TyTbJson(merged), []) then AfterSetOption(False, True);
    finally
      merged.Free;
    end;
  end;
  EmitPayloadEvent('dataviewchanged', TbEventJson(APayload, 'dataviewchanged'));
end;

function TTyAdvanceChart.ToolboxShowDataView(const ATitle: string;
  var AText: string; AReadOnly: Boolean; const ACloseCaption,
  ARefreshCaption: string): Boolean;
begin
  Result := TyShowDataViewDialog(ATitle, AText, AReadOnly, ACloseCaption, ARefreshCaption);
end;

function TTyAdvanceChart.ToolboxAskFileName(var AFileName: string;
  const AType: string): Boolean;
begin
  Result := TyAskImageFileName(AFileName, AType);
end;

procedure TTyAdvanceChart.TbSaveAsImage(ATb: Integer);
var
  fm: TJSONObject;
  opts, fileName, typ: string;
  handled: Boolean;
begin
  fm := TyToolboxFeatureModel(FOption, ATb, 'saveAsImage', TbTitles);
  try
    opts := TyToolboxSaveOpts(FOption, fm, fileName, typ);
  finally
    fm.Free;
  end;
  handled := False;
  if Assigned(FOnToolboxSaveAsImage) then
    FOnToolboxSaveAsImage(Self, fileName, opts, handled);
  if handled then Exit;
  if not ToolboxAskFileName(fileName, typ) then Exit;
  { getConnectedDataURL: the whole group when it is connected [Batch 141] }
  SaveConnectedToFile(fileName, opts);
end;

procedure TTyAdvanceChart.TbDoTakeCursor(APayload: TJSONObject);
var d: TJSONData;
begin
  d := APayload.Find('key');
  if (d <> nil) and (d.JSONType = jtString) and (d.AsString = 'dataZoomSelect') then
    FTbZoomActive := TyJsTruthy(APayload.Find('dataZoomSelectActive'))
  else
    FTbZoomActive := False;
  { the toolbox renders in the update: its select brush on or off at once
    [Batch 127] }
  TbZoomCtlSync;
  { the brush components' painting option, and their views [Batch 126] }
  BrushTakeCursor(APayload);
  { the visual stage's brushSelect [Batch 127], and the brush feature's
    statuses as this update renders them }
  BrushSelectRun(True);
  TbBrushSnap;
  { update: every view renders again -- the parallel axes' too [Batch 130] }
  FParBrushSkip := -1;
  FDirty := True;
  Invalidate;
  EmitPayloadEvent('globalcursortaken', TbEventJson(APayload, 'globalcursortaken'));
end;

{ the select dataZoom for an axis key ('x0'); -1 for none (findDataZoom:
  the last one) }
function TTyAdvanceChart.TbSelIndexOf(const AKey: string): Integer;
var i, k: Integer;
begin
  Result := -1;
  for i := 0 to High(FZoomSpecs) do
    if FZoomSpecs[i].SubType = 'select' then
      for k := 0 to High(FZoomSpecs[i].Targets) do
        if FZoomSpecs[i].Targets[k].Dim + IntToStr(FZoomSpecs[i].Targets[k].AxisIndex) = AKey then
          Result := i;
end;

procedure TTyAdvanceChart.TbSelPut(const AKey: string; AIsValue: Boolean; A, B: Double);
var i: Integer;
begin
  for i := 0 to High(FTbSel) do
    if FTbSel[i].Key = AKey then
    begin
      FTbSel[i].IsValue := AIsValue;
      FTbSel[i].A := A;
      FTbSel[i].B := B;
      Exit;
    end;
  i := Length(FTbSel);
  SetLength(FTbSel, i + 1);
  FTbSel[i].Key := AKey;
  FTbSel[i].IsValue := AIsValue;
  FTbSel[i].A := A;
  FTbSel[i].B := B;
end;

procedure TTyAdvanceChart.TbDispatchZoom(const ASnap: TTyTbSnapshot);
var
  a: TTyDzAction;
  i, k, n: Integer;
begin
  a := Default(TTyDzAction);
  a.Batch := True;
  a.FromToolbox := True;
  a.FromSlider := -1;
  for i := 0 to High(ASnap) do
  begin
    k := TbSelIndexOf(ASnap[i].Key);
    if k < 0 then Continue;
    n := Length(a.Items);
    SetLength(a.Items, n + 1);
    a.Items[n].DataZoomIndex := k;
    a.Items[n].IsValue := ASnap[i].IsValue;
    a.Items[n].Start := ASnap[i].A;
    a.Items[n].Stop := ASnap[i].B;
  end;
  if Length(a.Items) = 0 then Exit;
  DzDispatch(a);
end;

procedure TTyAdvanceChart.TbBack;
var snap: TTyTbSnapshot;
begin
  snap := TyTbHistoryPop(FTbHistory);
  { the dispatch's update renders the toolbox again: back's status follows
    the history -- and an empty snapshot dispatches nothing, renders
    nothing }
  TbDispatchZoom(snap);
end;

{ updateZoomBtnStatus [Batch 127]: the panels are the grids some select
  dataZoom targets an axis of (makePanelOpts), each typed lineX when only
  its x axes are declared, lineY only its y, else rect; the controller on
  with brushType 'auto' while the zoom is on and there is a panel, off
  otherwise. CSS px. }
procedure TTyAdvanceChart.TbZoomCtlSync;
var
  g, i, k, n: Integer;
  xd, yd: Boolean;
  axis: TTyAxis;
  pn: array of TTyBrushPanel;
  off: TTyBrushOpt;
  s: Double;
begin
  if (FTbBrushCtl = nil) and not FTbZoomActive then Exit;
  if FTbBrushCtl = nil then
  begin
    FTbBrushCtl := TTyBrushController.Create;
    FTbBrushCtl.IsIrrelevant := @BrushIrrelevant;
  end;
  pn := nil;
  FTbBrushGrids := nil;
  if FBuild <> nil then
    for g := 0 to FBuild.GridCount - 1 do
    begin
      xd := False;
      yd := False;
      for i := 0 to High(FZoomSpecs) do
        if FZoomSpecs[i].SubType = 'select' then
          for k := 0 to High(FZoomSpecs[i].Targets) do
          begin
            axis := DzAxis(FZoomSpecs[i].Targets[k].Dim, FZoomSpecs[i].Targets[k].AxisIndex);
            if (axis = nil) or (axis.GridIndex <> FBuild.Grid(g).ComponentIndex) then Continue;
            if FZoomSpecs[i].Targets[k].Dim = 'x' then xd := True else yd := True;
          end;
      if not (xd or yd) then Continue;
      n := Length(pn);
      SetLength(pn, n + 1);
      SetLength(FTbBrushGrids, n + 1);
      pn[n].Id := 'grid--' + ComponentModelId('grid', FBuild.Grid(g).ComponentIndex);
      pn[n].Rect := DzGridRect(g);
      pn[n].GridComponent := FBuild.Grid(g).ComponentIndex;
      if xd and not yd then pn[n].DefaultType := btLineX
      else if yd and not xd then pn[n].DefaultType := btLineY
      else pn[n].DefaultType := btRect;
      FTbBrushGrids[n] := g;
    end;
  s := TbScale;
  FTbBrushCtl.CanvasW := (FLastRect.Right - FLastRect.Left) / s;
  FTbBrushCtl.CanvasH := (FLastRect.Bottom - FLastRect.Top) / s;
  FTbBrushCtl.SetPanels(pn, Length(pn) > 0);
  if FTbZoomActive and (Length(pn) > 0) then
    BrushEnableCtl(FTbBrushCtl, TyBrushDefaultOpt, True)
  else
  begin
    off := TyBrushDefaultOpt;
    off.BrushType := btNone;
    BrushEnableCtl(FTbBrushCtl, off, False);
  end;
end;

procedure TTyAdvanceChart.TbCtlDown(AX, AY: Integer; ADraggable: Boolean);
var x, y: Double;
begin
  if FTbBrushCtl = nil then Exit;
  BrushCss(AX, AY, x, y);
  TbCtlTrigger(FTbBrushCtl.MouseDown(x, y, ADraggable));
end;

procedure TTyAdvanceChart.TbCtlMove(AX, AY: Integer);
var x, y: Double;
begin
  if (FTbBrushCtl = nil) or not FTbBrushCtl.Dragging then Exit;
  BrushCss(AX, AY, x, y);
  TbCtlTrigger(FTbBrushCtl.MouseMove(x, y));
  TbChanged;
end;

procedure TTyAdvanceChart.TbCtlUp(AX, AY: Integer);
var x, y: Double;
begin
  if (FTbBrushCtl = nil) or not FTbBrushCtl.Dragging then Exit;
  BrushCss(AX, AY, x, y);
  TbCtlTrigger(FTbBrushCtl.MouseUp(x, y));
  TbChanged;
end;

{ DataZoomFeature._onBrush: only an end with areas; the cover goes
  (updateCovers([])) and the area is the zoom }
procedure TTyAdvanceChart.TbCtlTrigger(const ATrig: TTyBrushTrigger);
var
  a: TTyBrushArea;
  i, g: Integer;
begin
  if not ATrig.Fired or not ATrig.IsEnd or (Length(ATrig.Areas) = 0) then Exit;
  FTbBrushCtl.UpdateCovers([]);
  TbChanged;
  a := ATrig.Areas[0];
  g := -1;
  for i := 0 to High(FTbBrushCtl.Panels) do
    if a.Opt.HasPanel and (FTbBrushCtl.Panels[i].Id = a.Opt.PanelId)
      and (i <= High(FTbBrushGrids)) then g := FTbBrushGrids[i];
  if (g < 0) or (Length(a.Opt.Range) = 0) then Exit;
  FTbBrushGrid := g;
  for i := 0 to 3 do FTbRange[i] := NaN;
  case a.Opt.BrushType of
    btLineX:
      begin
        FTbBrushType := tbbLineX;
        FTbRange[0] := a.Opt.Range[0][0];
        FTbRange[1] := a.Opt.Range[0][1];
      end;
    btLineY:
      begin
        FTbBrushType := tbbLineY;
        FTbRange[2] := a.Opt.Range[0][0];
        FTbRange[3] := a.Opt.Range[0][1];
      end;
  else
    if Length(a.Opt.Range) < 2 then Exit;
    FTbBrushType := tbbRect;
    FTbRange[0] := a.Opt.Range[0][0];
    FTbRange[1] := a.Opt.Range[0][1];
    FTbRange[2] := a.Opt.Range[1][0];
    FTbRange[3] := a.Opt.Range[1][1];
  end;
  TbBrushEnd;
end;

{ the pointer's cursor: an icon's own ('pointer'), and over a brush panel
  the brush's crosshair, which is set after it }
procedure TTyAdvanceChart.TbApplyCursor(AX, AY: Integer);
var
  x, y: Double;
  c, bc: string;
begin
  c := '';
  bc := '';
  { a toolbox icon (a graphic element shares the kind: its own cursor is
    TargetCursor's [F6a]) }
  if (FEvHover.HdKind = 8) and (FEvHover.Id < 0) then c := 'pointer';
  { a timeline element's cursor, zrender's default [Batch 129] }
  if (FEvHover.HdKind = 10) and (FEvHover.Id <> 0) then c := 'pointer';
  { a brush cover's piece under the pointer: its own cursor [Batch 126] }
  if (FEvHover.HdKind = 9) and (FEvHover.Id <> 0) and (FEvHover.HdGen >= 0)
    and (FEvHover.HdGen <= Ord(High(TTyBrushPiece))) then
  begin
    { through the controller's group: a parallel axis' is turned
      [Batch 130] }
    if BrushCtlOf(FEvHover.HdSeries) <> nil then
      bc := BrushCtlOf(FEvHover.HdSeries).PieceCursor(TTyBrushPiece(FEvHover.HdGen), True)
    else
      bc := TyBrushPieceCursor(TTyBrushPiece(FEvHover.HdGen), True);
    c := bc;
  end;
  { the select brush's resetCursor [Batch 127] }
  if FTbBrushCtl <> nil then
  begin
    BrushCss(AX, AY, x, y);
    if FTbBrushCtl.Crosshair(x, y) then c := 'crosshair';
  end;
  { the brush controllers' resetCursor: the crosshair in a panel off the
    covers [Batch 126] }
  if BrushCrosshair(AX, AY) then
  begin
    c := 'crosshair';
    bc := 'crosshair';
  end;
  FBrushCursor := bc;
  if c <> '' then
  begin
    FTbCursor := c;
    FDzCursor := c;
  end
  else if FTbCursor <> '' then
  begin
    FTbCursor := '';
    FDzCursor := 'default';
  end;
end;

{ ---- what the tests read ---- }

procedure TTyAdvanceChart.ToolboxFrame;
begin
  TbFrame;
end;

function TTyAdvanceChart.ToolboxCount: Integer;
begin
  Result := Length(FTbSpecs);
end;

function TTyAdvanceChart.ToolboxSpec(AIndex: Integer): TTyToolboxSpec;
begin
  Result := Default(TTyToolboxSpec);
  if (AIndex >= 0) and (AIndex <= High(FTbSpecs)) then Result := FTbSpecs[AIndex];
end;

function TTyAdvanceChart.ToolboxLayout(AIndex: Integer): TTyToolboxLayout;
begin
  Result := Default(TTyToolboxLayout);
  if (AIndex >= 0) and (AIndex <= High(FTbLayouts)) then Result := FTbLayouts[AIndex];
end;

function TTyAdvanceChart.ToolboxIconState(ATb, AIcon: Integer;
  out AEmphasised, ATitleShown, APosAdjusted, AAlignAdjusted: Boolean): Boolean;
begin
  AEmphasised := False;
  ATitleShown := False;
  APosAdjusted := False;
  AAlignAdjusted := False;
  Result := (ATb >= 0) and (ATb <= High(FTbSpecs)) and (AIcon >= 0)
    and (AIcon <= High(FTbSpecs[ATb].Icons));
  if not Result then Exit;
  AEmphasised := TbEmphasised(ATb, AIcon);
  if (ATb <= High(FTbLive)) and (AIcon <= High(FTbLive[ATb])) then
  begin
    ATitleShown := FTbLive[ATb][AIcon].TextShown;
    APosAdjusted := FTbLive[ATb][AIcon].AdjPos;
    AAlignAdjusted := FTbLive[ATb][AIcon].AdjAlign;
  end;
end;

function TTyAdvanceChart.ToolboxTitle(ATb, AIcon: Integer): TTyTbTitlePlace;
var e, shown, ap, aa: Boolean;
begin
  Result := Default(TTyTbTitlePlace);
  if not ToolboxIconState(ATb, AIcon, e, shown, ap, aa) then Exit;
  Result := TyToolboxTitlePlace(FTbSpecs[ATb], FTbLayouts[ATb], AIcon, ap, aa, e);
end;

function TTyAdvanceChart.ToolboxIconStatus(ATb: Integer; const AFeature,
  AIcon: string): string;
begin
  Result := FTbStatus.Values[IntToStr(ATb) + '|' + AFeature + '|' + AIcon];
end;

function TTyAdvanceChart.ToolboxHistoryCount: Integer;
begin
  Result := TyTbHistoryCount(FTbHistory);
end;

function TTyAdvanceChart.ToolboxCover(out ARect: TTyXYWH): Boolean;
begin
  ARect := Default(TTyXYWH);
  Result := (FTbBrushCtl <> nil) and (Length(FTbBrushCtl.Covers) > 0);
  if Result then ARect := FTbBrushCtl.Covers[0].Main;
end;
