{ tyControls.Terminal 的一部分(被 include,不是单元):鼠标——横竖滚轮、上报、一次按下走哪条路(上报 / 选择 / 链接 / PRIMARY)。
  只为好读从单元里搬出来;控件是什么、参照上游哪里,见单元头。 }

{ ---- 鼠标 --------------------------------------------------------------------------- }

function TTyTerminalView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  notches, i, dir: Integer;
  ev: TTyTerminalMouseEvent;
begin
  { 宿主的 OnMouseWheel 先拿;它处理了就到此为止 }
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result or not Enabled then Exit;
  { Shift+滚轮:上游既不上报也不翻方向键(MouseService.ts:459 的 _consumeWheelEvent 对
    shiftKey 答 0 行);滚回在 Windows / Linux 上是横滚(scrollableElement.ts:394,终端没有
    横向可滚),只有 macOS 照常竖滚。不是我们的事就不吃,交给父控件。 }
  if ssShift in Shift then
  begin
    if not (FIsMac and FCore.Buffer.HasScrollback) then Exit;
    if (FWheelAccum <> 0) and ((FWheelAccum > 0) <> (WheelDelta > 0)) then
      FWheelAccum := 0;
    Inc(FWheelAccum, WheelDelta);
    notches := FWheelAccum div 120;
    FWheelAccum := FWheelAccum - notches * 120;
    Result := True;
    if notches <> 0 then
      FCore.ScrollLines(-3 * notches);
    Exit;
  end;
  { 每满 ±120 出一格,同号的余数留着,反向时清零;一格都不满也吃掉这点位移 }
  if (FWheelAccum <> 0) and ((FWheelAccum > 0) <> (WheelDelta > 0)) then
    FWheelAccum := 0;
  Inc(FWheelAccum, WheelDelta);
  notches := FWheelAccum div 120;
  FWheelAccum := FWheelAccum - notches * 120;
  Result := True;
  if notches = 0 then Exit;
  if notches > 0 then dir := 1 else dir := -1;
  for i := 1 to Abs(notches) do
  begin
    { MouseService.ts:250-292:程序要滚轮事件就上报;否则有滚回就滚 3 行;再否则
      (备用屏、AlternateScroll)发方向键 }
    if Reporting then
    begin
      if dir > 0 then
        ev := MakeMouseEvent(tmbWheel, tmaUp, MousePos.X, MousePos.Y, Shift)
      else
        ev := MakeMouseEvent(tmbWheel, tmaDown, MousePos.X, MousePos.Y, Shift);
      if FCore.TriggerMouseEvent(ev) then Continue;
    end;
    if FCore.Buffer.HasScrollback then
      FCore.ScrollLines(-3 * dir)
    else if FAlternateScroll then
    begin
      if FCore.Modes.ApplicationCursorKeys then
      begin
        if dir > 0 then FCore.Input(#27'OA', True) else FCore.Input(#27'OB', True);
      end
      else if dir > 0 then
        FCore.Input(#27'[A', True)
      else
        FCore.Input(#27'[B', True);
    end;
  end;
end;

{ 横向滚轮:LCL 的 DoMouseWheelLeft / Right 拿不到 WheelDelta(DoMouseWheelHorz 按正负分过去),
  照竖向按 ±120 累计要覆盖这一层。程序要了滚轮就报 66 / 67(左 / 右);没要就交还父控件——
  终端没有横向可滚。 }
function TTyTerminalView.DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  notches, i: Integer;
begin
  Result := inherited DoMouseWheelHorz(Shift, WheelDelta, MousePos);
  if Result or not Enabled or (csDesigning in ComponentState) then Exit;
  if not Reporting then
    Exit(False);
  if (FHorzAccum <> 0) and ((FHorzAccum > 0) <> (WheelDelta > 0)) then
    FHorzAccum := 0;
  Inc(FHorzAccum, WheelDelta);
  notches := FHorzAccum div 120;
  FHorzAccum := FHorzAccum - notches * 120;
  Result := True;
  { LCL:WheelDelta < 0 是向左(DoMouseWheelHorz 分给 DoMouseWheelLeft) }
  for i := 1 to Abs(notches) do
    if notches < 0 then
      ReportMouse(tmbWheel, tmaLeft, MousePos.X, MousePos.Y, Shift)
    else
      ReportMouse(tmbWheel, tmaRight, MousePos.X, MousePos.Y, Shift);
end;

function TyTerminalMouseButtonFor(AAction: TTyTerminalMouseAction; AButton: TMouseButton;
  AShift: TShiftState): TTyTerminalMouseButton;
begin
  if AAction = tmaMove then
  begin
    if ssLeft in AShift then Result := tmbLeft
    else if ssMiddle in AShift then Result := tmbMiddle
    else if ssRight in AShift then Result := tmbRight
    else Result := tmbNone;
    Exit;
  end;
  case AButton of
    mbLeft: Result := tmbLeft;
    mbMiddle: Result := tmbMiddle;
    mbRight: Result := tmbRight;
  else
    Result := tmbNone;
  end;
end;

function TTyTerminalView.Reporting: Boolean;
begin
  Result := FCore.Modes.MouseProtocol <> tmpNone;
end;

{ 上报用的事件:格子按 CellAt(整除再钳,上游 getCoords 的非选区取整),像素钳在网格里
  (MouseCoordsService.ts:38-39 钳到画布宽高 - 1),修饰键原样:覆盖键按着时按键不会走到
  这里,滚轮照上游带着修饰位(MouseService.ts:175-179 只在 mouseEventsRequireAlt 时剥) }
function TTyTerminalView.MakeMouseEvent(AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction;
  X, Y: Integer; Shift: TShiftState): TTyTerminalMouseEvent;
var
  cell: TPoint;
  ins: TRect;
begin
  cell := CellAt(X, Y);
  ins := ContentInsets(Font.PixelsPerInch);
  Result := Default(TTyTerminalMouseEvent);
  Result.Col := cell.X;
  Result.Row := cell.Y;
  Result.X := EnsureRange(X - ins.Left, 0, FCore.Cols * FMetrics.CellW - 1);
  Result.Y := EnsureRange(Y - ins.Top, 0, FCore.Rows * FMetrics.CellH - 1);
  Result.Button := AButton;
  Result.Action := AAction;
  Result.Shift := ssShift in Shift;
  Result.Alt := ssAlt in Shift;
  Result.Ctrl := ssCtrl in Shift;
end;

procedure TTyTerminalView.ReportMouse(AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction;
  X, Y: Integer; Shift: TShiftState);
begin
  { 第 4、5 键上游是 NONE + 按下 / 抬起,被 TriggerMouseEvent 滤掉:不报 }
  if (AButton = tmbNone) and (AAction <> tmaMove) then Exit;
  FCore.TriggerMouseEvent(MakeMouseEvent(AButton, AAction, X, Y, Shift));
end;

function TTyTerminalView.OverrideIsAlt: Boolean;
begin
  Result := (FSelectionOverrideKey = tsoAlt) or ((FSelectionOverrideKey = tsoDefault) and FIsMac);
end;

function TTyTerminalView.OverrideHeld(Shift: TShiftState): Boolean;
begin
  case FSelectionOverrideKey of
    tsoShift: Result := ssShift in Shift;
    tsoAlt: Result := ssAlt in Shift;
    tsoNone: Result := False;
  else
    if FIsMac then Result := ssAlt in Shift else Result := ssShift in Shift;
  end;
end;

function TTyTerminalView.ColumnWanted(Shift: TShiftState): Boolean;
begin
  Result := (ssAlt in Shift) and not OverrideIsAlt;
end;

{ 指针形状(xterm.css:39、:119-120、:130):程序接管鼠标(没按覆盖键)箭头;要列选择十字;
  平常 I 形,宿主设了别的 Cursor 就用宿主的。用 SetTempCursor,不写 Cursor 属性;LCL 进出
  控件时会拿 Cursor 复位,所以每次移动都重设。 }
procedure TTyTerminalView.UpdatePointer(Shift: TShiftState);
var
  c: TCursor;
begin
  if csDesigning in ComponentState then Exit;
  if FHoverValid then
    c := crHandPoint
  else if Reporting and not OverrideHeld(Shift) then
    c := crDefault
  else if ColumnWanted(Shift) then
    c := crCross
  else if Cursor <> crDefault then
    c := Cursor
  else
    c := crIBeam;
  SetTempCursor(c);
end;

{ 谁拿鼠标(4 期 4b 附录的表):路在按下那一刻定,拖动、抬起一直走它,中途松开覆盖键不换路
  (MouseService.ts:224-249,选区服务的 mousemove 监听 stopImmediatePropagation)。上报路上
  别的键按下也照报;其他路上别的键不管。 }
procedure TTyTerminalView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  cell: TPoint;
  link: TTyTermLink;
begin
  FStateChange := True;
  try
    inherited MouseDown(Button, Shift, X, Y);
  finally
    FStateChange := False;
  end;
  { 基类只在左键时取焦点;终端照终端的惯例,哪个键点下去都取(中键、右键也是在跟这个
    终端打交道)。守着 TabStop 同基类:TabStop = False 的终端(宿主拿它当只看的面板)
    点了也不抢焦点。SetFocus 可能抛(窗体还没显示、无头),同基类吞掉。 }
  if TabStop and CanFocus and not Focused then
    try
      SetFocus;
    except
    end;
  if csDesigning in ComponentState then Exit;
  FLastMousePos := Point(X, Y);
  SyncSelectionTrim;
  { Ctrl(macOS Cmd)+单击链接:链接优先,程序接管了鼠标也一样(spec §9.8);不上报、不选择 }
  if (FRoute = mrNone) and (Button = mbLeft) and LinkKeyHeld(Shift) then
  begin
    cell := CellAt(X, Y);
    if LinkAt(cell.X, cell.Y, link) then
    begin
      FRoute := mrLink;
      FRouteButton := Button;
      FDownLink := link;
      Exit;
    end;
  end;
  if FRoute = mrReport then
  begin
    Include(FReportHeld, Button);
    if Button = mbRight then FRightReported := True;
    ReportMouse(TyTerminalMouseButtonFor(tmaDown, Button, Shift), tmaDown, X, Y, Shift);
    Exit;
  end;
  if FRoute <> mrNone then Exit;
  if Button = mbRight then
  begin
    FRightReported := False;
    FRightLocal := False;
  end;
  if Reporting and not OverrideHeld(Shift) then
  begin
    FRoute := mrReport;
    FRouteButton := Button;
    FReportHeld := [Button];
    if Button = mbRight then FRightReported := True;
    ReportMouse(TyTerminalMouseButtonFor(tmaDown, Button, Shift), tmaDown, X, Y, Shift);
    Exit;
  end;
  case Button of
    mbLeft:
      begin
        FRoute := mrSelect;
        FRouteButton := Button;
        SelectionPress(Shift, X, Y);
      end;
    mbRight: FRightLocal := True;           { 菜单由 DoContextPopup 弹 }
    mbMiddle:
      { X11 惯例:中键粘贴 PRIMARY(松开时);Windows / macOS 上中键不做事 }
      if FUsesPrimary then
      begin
        FRoute := mrPrimary;
        FRouteButton := Button;
      end;
  end;
end;

procedure TTyTerminalView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if csDesigning in ComponentState then Exit;
  FLastMousePos := Point(X, Y);
  case FRoute of
    mrReport:
      ReportMouse(TyTerminalMouseButtonFor(tmaMove, mbLeft, Shift), tmaMove, X, Y, Shift);
    mrSelect:
      SelectionDrag(X, Y);
    mrNone:
      { 不带键的移动:只有 1003 放行(TriggerMouseEvent 按协议与去重决定);带着键却没有
        路(在别处按下的)上游也不报 }
      if Reporting and ([ssLeft, ssMiddle, ssRight] * Shift = []) then
        ReportMouse(tmbNone, tmaMove, X, Y, Shift);
  end;
  FMouseInside := True;
  UpdateHover(X, Y, Shift);
  UpdatePointer(Shift);
end;

procedure TTyTerminalView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  rt: TTyTerminalMouseRoute;
  cell: TPoint;
  link: TTyTermLink;
begin
  FStateChange := True;
  try
    inherited MouseUp(Button, Shift, X, Y);
  finally
    FStateChange := False;
  end;
  if csDesigning in ComponentState then Exit;
  FLastMousePos := Point(X, Y);
  if FRoute = mrReport then
  begin
    ReportMouse(TyTerminalMouseButtonFor(tmaUp, Button, Shift), tmaUp, X, Y, Shift);
    { 上游在所有键都松开时才摘掉全局监听(MouseService.ts:196-203) }
    Exclude(FReportHeld, Button);
    if FReportHeld = [] then
      FRoute := mrNone;
    Exit;
  end;
  if (FRoute <> mrNone) and (Button = FRouteButton) then
  begin
    rt := FRoute;
    FRoute := mrNone;
    case rt of
      mrSelect: SelectionRelease;
      mrPrimary: Paste(ReadPrimaryText);
      mrLink:
        begin
          { 按下和抬起在同一条链接上才算(Linkifier.ts:220-233) }
          cell := CellAt(X, Y);
          if LinkAt(cell.X, cell.Y, link) and TyTermLinkEquals(link, FDownLink)
            and Assigned(FOnLinkActivate) then
            FOnLinkActivate(Self, link.Text, link.Source = tlsOsc8);
        end;
    end;
  end;
end;
