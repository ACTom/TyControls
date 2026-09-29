{ tyControls.Terminal 的一部分(被 include,不是单元):链接——按着链接键时的悬停,和改变「什么算链接」的两个属性。
  只为好读从单元里搬出来;控件是什么、参照上游哪里,见单元头。 }

{ ---- 链接 --------------------------------------------------------------------------- }

function TTyTerminalView.LinkKeyHeld(Shift: TShiftState): Boolean;
begin
  if FIsMac then
    Result := ssMeta in Shift
  else
    Result := ssCtrl in Shift;
end;

function TTyTerminalView.LinkAt(ACol, AViewRow: Integer; out ALink: TTyTermLink): Boolean;
begin
  Result := TyTermFindLinkAt(FCore.Buffer, FCore.Links, ACol, FCore.Buffer.YDisp + AViewRow, FCore.Cols,
    FDetectUrls, FAllowNonHttpLinks, ALink);
end;

procedure TTyTerminalView.DirtyLinkRows(const ALink: TTyTermLink);
var
  a, b, i: Integer;
begin
  a := Max(ALink.Range.StartY - 1 - FCore.Buffer.YDisp, 0);
  b := Min(ALink.Range.EndY - 1 - FCore.Buffer.YDisp, FCore.Rows - 1);
  if b < a then Exit;
  if FInRender then
  begin
    for i := a to Min(b, High(FDirty)) do
      FDirty[i] := True;
  end
  else
    DirtyRows(a, b);
end;

procedure TTyTerminalView.UpdateHover(X, Y: Integer; Shift: TShiftState);
var
  ins: TRect;
  cell: TPoint;
  link: TTyTermLink;
  valid: Boolean;
begin
  if csDesigning in ComponentState then Exit;
  FHoverShift := Shift;
  valid := False;
  link := Default(TTyTermLink);
  if (X >= 0) and (Y >= 0) and LinkKeyHeld(Shift) and (FRoute <> mrSelect) then
  begin
    EnsureMetrics(Font.PixelsPerInch);
    ins := ContentInsets(Font.PixelsPerInch);
    if (X >= ins.Left) and (Y >= ins.Top) and (X < ins.Left + FCore.Cols * FMetrics.CellW)
      and (Y < ins.Top + FCore.Rows * FMetrics.CellH) then
    begin
      cell := CellAt(X, Y);
      valid := LinkAt(cell.X, cell.Y, link);
    end;
  end;
  if (valid = FHoverValid) and (not valid or TyTermLinkEquals(link, FHoverLink)) then
    Exit;
  if FHoverValid then
    DirtyLinkRows(FHoverLink);
  FHoverLink := link;
  FHoverValid := valid;
  if FHoverValid then
    DirtyLinkRows(FHoverLink);
end;

procedure TTyTerminalView.SetDetectUrls(AValue: Boolean);
begin
  if FDetectUrls = AValue then Exit;
  FDetectUrls := AValue;
  if FHoverValid then
    UpdateHover(FLastMousePos.X, FLastMousePos.Y, FHoverShift);
end;

procedure TTyTerminalView.SetAllowNonHttpLinks(AValue: Boolean);
begin
  if FAllowNonHttpLinks = AValue then Exit;
  FAllowNonHttpLinks := AValue;
  if FHoverValid then
    UpdateHover(FLastMousePos.X, FLastMousePos.Y, FHoverShift);
end;
