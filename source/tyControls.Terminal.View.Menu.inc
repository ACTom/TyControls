{ tyControls.Terminal 的一部分(被 include,不是单元):右键菜单——内置四项、什么时候弹、什么时候不弹。
  只为好读从单元里搬出来;控件是什么、参照上游哪里,见单元头。 }

{ ---- 右键菜单 ----------------------------------------------------------------------- }

procedure TTyTerminalView.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var
  keyboard: Boolean;
  cur: TRect;
  buf: TTyTerminalBuffer;
  cell: TPoint;
  link: TTyTermLink;
begin
  inherited DoContextPopup(MousePos, Handled);
  if Handled or (csDesigning in ComponentState) then Exit;
  keyboard := (MousePos.X = -1) and (MousePos.Y = -1);
  if not keyboard then
  begin
    { 这次右键按下报给了程序:不弹(Win32 在抬起后才发 WM_CONTEXTMENU) }
    if FRightReported then
    begin
      FRightReported := False;
      Handled := True;
      Exit;
    end;
    if FRightLocal then
      FRightLocal := False
    else if Reporting and not OverrideHeld(CurrentShiftState) then
    begin
      { 菜单先于按下到(有的 widgetset 按下时就发):按下会报给程序,这里不弹 }
      Handled := True;
      Exit;
    end;
  end;
  if not keyboard and FIsMac then
  begin
    { macOS 惯例(上游 rightClickSelectsWord: isMac):右键在选区外先选中那个词(指针下有链接
      就选整条)——宿主的 PopupMenu 也是(上游选词在弹哪个菜单之前,Clipboard.ts:83-96) }
    SyncSelectionTrim;
    cell := CellAt(MousePos.X, MousePos.Y);
    if LinkAt(cell.X, cell.Y, link) then
      FSelection.RightClickSelect(SelPointAt(MousePos.X, MousePos.Y), @link.Range)
    else
      FSelection.RightClickSelect(SelPointAt(MousePos.X, MousePos.Y));
  end;
  if PopupMenu <> nil then Exit;
  if keyboard then
  begin
    ApplyPendingGrid;                      { the cell counted in the grid it is shown in }
    buf := FCore.Buffer;
    cur := CellRect(Min(buf.X, FCore.Cols - 1), EnsureRange(CursorViewRow, 0, FCore.Rows - 1));
    MousePos := Point(cur.Left, cur.Bottom);
  end;
  ShowContextMenu(MousePos);
  Handled := True;
end;

procedure TTyTerminalView.UpdateContextMenu;

  function Add(const ACaption: string; AOnClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FMenu);
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
    FMenu.Items.Add(Result);
  end;

var
  sep: TMenuItem;
begin
  if FMenu = nil then
  begin
    FMenu := TTyPopupMenu.Create(nil);
    FMenuCopy := Add(rsTextMenuCopy, @MenuCopyClick);
    FMenuPaste := Add(rsTextMenuPaste, @MenuPasteClick);
    sep := TMenuItem.Create(FMenu);
    sep.Caption := '-';
    FMenu.Items.Add(sep);
    FMenuSelectAll := Add(rsTextMenuSelectAll, @MenuSelectAllClick);
    FMenuClear := Add(rsTerminalMenuClear, @MenuClearClick);
  end;
  FMenuCopy.Enabled := HasSelection;
  { 只问「有没有文字」,不把整段读出来(剪贴板里可能是几兆) }
  FMenuPaste.Enabled := not ReadOnly and ClipboardHasText;
  FMenuSelectAll.Enabled := True;
  FMenuClear.Enabled := True;
end;

procedure TTyTerminalView.ShowContextMenu(const AClientPos: TPoint);
var
  p: TPoint;
begin
  UpdateContextMenu;
  FMenu.Controller := ActiveController;
  FMenu.PopupComponent := Self;
  p := ClientToScreen(AClientPos);
  FMenu.PopUp(p.X, p.Y);
end;

function TTyTerminalView.CurrentShiftState: TShiftState;
begin
  Result := GetKeyShiftState;
end;

procedure TTyTerminalView.MenuCopyClick(Sender: TObject);
begin
  CopyToClipboard;
end;

procedure TTyTerminalView.MenuPasteClick(Sender: TObject);
begin
  PasteFromClipboard;
end;

procedure TTyTerminalView.MenuSelectAllClick(Sender: TObject);
begin
  SelectAll;
  FinishSelection;
end;

procedure TTyTerminalView.MenuClearClick(Sender: TObject);
begin
  Clear;
end;
