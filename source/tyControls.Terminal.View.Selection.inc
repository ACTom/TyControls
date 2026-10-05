{ tyControls.Terminal 的一部分(被 include,不是单元):控件与选区服务之间的胶水——追 trim、按下 / 拖动 / 松开、自动滚计时器、公开方法。
  只为好读从单元里搬出来;控件是什么、参照上游哪里,见单元头。 }

{ ---- 选区 --------------------------------------------------------------------------- }

procedure TTyCustomTerminalView.SelectionChanged(Sender: TObject);
begin
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

{ 选区此刻落在哪几个视口行(钳在视口里);False = 没有,或不在视口里 }
function TTyCustomTerminalView.SelectionViewRows(out AFirst, ALast: Integer): Boolean;
var
  s, e: TTyTermSelPoint;
  yd: Integer;
begin
  AFirst := -1;
  ALast := -1;
  if not FSelection.FinalStart(s) or not FSelection.FinalEnd(e) then
    Exit(False);
  yd := FCore.Buffer.YDisp;
  AFirst := Max(Min(s.Row, e.Row) - yd, 0);
  ALast := Min(Max(s.Row, e.Row) - yd, FCore.Rows - 1);
  Result := AFirst <= ALast;
  if not Result then
  begin
    AFirst := -1;
    ALast := -1;
  end;
end;

{ 上游 refresh():只重画涉及的行——上次画过的选区行段与现在的并集。在绘制里(追 trim)只标
  脏不失效:这一帧就画掉 }
procedure TTyCustomTerminalView.SelectionRedraw(Sender: TObject);
var
  a, b, i: Integer;
begin
  if FSelDrawnFirst >= 0 then
  begin
    a := FSelDrawnFirst;
    b := FSelDrawnLast;
  end
  else
  begin
    a := MaxInt;
    b := -1;
  end;
  if SelectionViewRows(FSelDrawnFirst, FSelDrawnLast) then
  begin
    a := Min(a, FSelDrawnFirst);
    b := Max(b, FSelDrawnLast);
  end;
  { 画的时候会重记;这里先记下现在的,下一次失效就从它算 }
  if (b < a) or (a = MaxInt) then Exit;
  a := Max(a, 0);
  b := Min(b, High(FDirty));
  if b < a then Exit;
  if FInRender then
  begin
    for i := a to b do
      FDirty[i] := True;
  end
  else
    DirtyRows(a, b);
end;

procedure TTyCustomTerminalView.SyncSelectionTrim;
var
  d: Int64;
begin
  if FSelection = nil then Exit;
  d := FCore.Buffer.TrimmedLines - FSelTrimBase;
  FSelTrimBase := FCore.Buffer.TrimmedLines;
  if d > 0 then
  begin
    if d > MaxInt then d := MaxInt;
    FSelection.HandleTrim(Integer(d));
  end;
end;

function TTyCustomTerminalView.SelPointAt(X, Y: Integer): TTyTermSelPoint;
var
  ins: TRect;
  p: TPoint;
begin
  EnsureMetrics(Font.PixelsPerInch);
  ins := ContentInsets(Font.PixelsPerInch);
  p := TyTermSelectionPointAt(X - ins.Left, Y - ins.Top, FMetrics.CellW, FMetrics.CellH,
    FCore.Cols, FCore.Rows);
  Result.Col := p.X;
  Result.Row := p.Y + FCore.Buffer.YDisp;
end;

procedure TTyCustomTerminalView.SelectionPress(Shift: TShiftState; X, Y: Integer);
var
  clicks: Integer;
  cell: TPoint;
  link: TTyTermLink;
  lp: PTyTermLinkRange;
begin
  clicks := TyMultiClickCount(ssDouble in Shift, X, Y, FLastClickX, FLastClickY, FLastClickTick,
    FClickCount, Font.PixelsPerInch);
  { 双击时指针下有链接就选整条(上游 _selectWordAtCursor 先看 linkifier.currentLink);
    不要求链接键,受 DetectUrls / AllowNonHttpLinks 管 }
  lp := nil;
  if clicks = 2 then
  begin
    cell := CellAt(X, Y);
    if LinkAt(cell.X, cell.Y, link) then
      lp := @link.Range;
  end;
  { Shift 扩展只在程序没接管鼠标时(上游 _enabled && shiftKey);程序接管时 Shift 是覆盖键 }
  FSelection.Press(SelPointAt(X, Y), clicks, not Reporting and (ssShift in Shift), ColumnWanted(Shift), lp);
  if FSelection.Dragging then
    StartDragTimer;
end;

procedure TTyCustomTerminalView.SelectionDrag(X, Y: Integer);
var
  ins: TRect;
begin
  SyncSelectionTrim;
  EnsureMetrics(Font.PixelsPerInch);
  ins := ContentInsets(Font.PixelsPerInch);
  { 点钳在网格里,滚速按真实的越界距离算;50 像素是逻辑像素,按 PPI 缩放 }
  FSelection.DragTo(SelPointAt(X, Y), TyTermDragScrollAmount(Y - ins.Top, FCore.Rows * FMetrics.CellH,
    MulDiv(TyTermDragScrollMaxThreshold, Font.PixelsPerInch, 96)));
end;

procedure TTyCustomTerminalView.SelectionRelease;
begin
  StopDragTimer;
  SyncSelectionTrim;
  FSelection.Release;
  FinishSelection;
end;

procedure TTyCustomTerminalView.FinishSelection;
begin
  SyncSelectionTrim;
  if not FSelection.HasSelection then Exit;
  { PRIMARY 只登记,文字等有人要时再取(一万行的选区松手时不必拼一遍);CopyOnSelect 才
    现在就要文字 }
  if FUsesPrimary then
    OfferPrimary;
  if FCopyOnSelect then
    WriteClipboardText(FSelection.Text(LineEnding));
end;

procedure TTyCustomTerminalView.StartDragTimer;
begin
  if csDesigning in ComponentState then Exit;
  if FDragTimer = nil then
  begin
    FDragTimer := TTimer.Create(nil);
    FDragTimer.Enabled := False;
    FDragTimer.Interval := TyTermDragScrollInterval;
    FDragTimer.OnTimer := @DragTimerFired;
  end;
  FDragTimer.Enabled := True;
end;

procedure TTyCustomTerminalView.StopDragTimer;
begin
  if FDragTimer <> nil then
    FDragTimer.Enabled := False;
end;

procedure TTyCustomTerminalView.DragTimerFired(Sender: TObject);
begin
  DragScrollTick;
end;

procedure TTyCustomTerminalView.DragScrollTick;
var
  n: Integer;
begin
  SyncSelectionTrim;
  n := FSelection.DragScrollAmount;
  if n <> 0 then
  begin
    FCore.ScrollLines(n);
    FSelection.AfterDragScroll;
  end;
end;

function TTyCustomTerminalView.DragTimerActive: Boolean;
begin
  Result := (FDragTimer <> nil) and FDragTimer.Enabled;
end;

procedure TTyCustomTerminalView.SelectAll;
begin
  SyncSelectionTrim;
  FSelection.SelectAll;
end;

procedure TTyCustomTerminalView.ClearSelection;
begin
  StopDragTimer;
  FSelection.Clear;
end;

{ 宿主给的数钳进缓冲:列 0..Cols、行 0..最后一行、长度 0..到缓冲末尾(上游不查;长度
  太大时「起点 + 长度」会溢出) }
procedure TTyCustomTerminalView.Select(ACol, AAbsRow, ALength: Integer);
var
  last: Integer;
  room: Int64;
begin
  SyncSelectionTrim;
  last := Max(FCore.Buffer.Lines.Length - 1, 0);
  ACol := EnsureRange(ACol, 0, FCore.Cols);
  AAbsRow := EnsureRange(AAbsRow, 0, last);
  room := Int64(last - AAbsRow + 1) * FCore.Cols - ACol;
  if ALength < 0 then
    ALength := 0
  else if ALength > room then
    ALength := Integer(room);
  FSelection.SetSelection(ACol, AAbsRow, ALength);
end;

procedure TTyCustomTerminalView.SelectLines(AFirst, ALast: Integer);
begin
  SyncSelectionTrim;
  FSelection.SelectLines(AFirst, ALast);
end;

function TTyCustomTerminalView.GetSelectionText: string;
begin
  SyncSelectionTrim;
  Result := FSelection.Text(LineEnding);
end;

function TTyCustomTerminalView.GetHasSelection: Boolean;
begin
  SyncSelectionTrim;
  Result := FSelection.HasSelection;
end;

procedure TTyCustomTerminalView.SetWordSeparators(const AValue: string);
begin
  FWordSeparators := AValue;
  FSelection.WordSeparators := UTF8Decode(AValue);
end;

function TTyCustomTerminalView.WordSeparatorsStored: Boolean;
begin
  Result := FWordSeparators <> TyTermDefaultWordSeparators;
end;
