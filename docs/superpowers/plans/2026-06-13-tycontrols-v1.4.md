# TyControls v1.4 — TTyTabControl 成熟化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 给 `TTyTabControl` 加 `RemoveTab` + Notification 悬空保护 + 可关闭页签(× / OnTabClose),并把页签几何改为单遍布局消除每帧 O(n²)。

**Architecture:** 增删/外部释放统一走私有 `RemovePageInternal(idx, AFree)`;`Notification(opRemove)` 在 `FDestroying` 标志保护下剔除被释放的页面板。可关闭页签靠 `TabsClosable`/`OnTabClose`/`TyTabCloseRect`;页签头几何改由 `RebuildLayout(APPI)` 一次性填 `FHeaderRects`/`FCloseRects`,渲染与鼠标读数组。

**Tech Stack:** Free Pascal / Lazarus / LCL / BGRABitmap;FPCUnit。

**约束(记忆):** 几何/像素测试钉 `Font.PixelsPerInch := 96`;测试构建 `lazbuild tests/tytests.lpi` 后跑 `./tests/tytests`;新测试单元加进 `tytests.lpr` uses(本阶段不新增测试单元,沿用 `tests/test.tabcontrol.pas`);子代理派发以 "DIRECT task. Do NOT invoke any brainstorming/planning skill, do NOT create plan files." 开头。

**现状关键事实(已核对 source/tyControls.TabControl.pas):**
- 并行结构 `FCaptions: TStringList` + `FPages: array of TTyPanel`;`FTabIndex/FTabHeight/FHoverTab/FOnChange`。
- 页面板由 `AddTab` 创建,`Owner=Self`、`Parent=Self`、`Align=alClient`、`Visible` 切换。
- 现有几何 `TyTabHeaderRect(i)`:`pad=MulDiv(12,PPI,96)` 每侧、`MinW=MulDiv(48,PPI,96)`、宽 `=textW+2*pad` 夹到 MinW、X 累加;`TabHPx=MulDiv(FTabHeight,PPI,96)`(>=1)。**非 closable 时新布局必须复刻这一几何。**
- `RenderTo`/`MouseDown`/`MouseMove` 当前在循环里每页调 `TyTabHeaderRect`(O(n²) 来源)。
- 现有测试见 `tests/test.tabcontrol.pas`(`TestHeaderRectsLayout` 断言 width>=48、rect(1).Left=rect(0).Right、Bottom=28;`TestMouseDownSelectsTab` 点 header 中点选中)。**这些必须保持通过。**

---

## Task 1: RemoveTab + Notification 悬空保护

**Files:**
- Modify: `source/tyControls.TabControl.pas`
- Modify: `tests/test.tabcontrol.pas`

- [ ] **Step 1: 写失败测试 — 追加到 tests/test.tabcontrol.pas**

在 `TTyTabControlAccess` 不需要改。在 `TTyTabControlTest` 的 `published` 区追加:
```pascal
    procedure TestRemoveTabCompactsAndAdjustsIndex;
    procedure TestRemoveActiveTabSelectsNeighborFiresOnChange;
    procedure TestRemoveTabBeforeActiveKeepsActivePageNoOnChange;
    procedure TestRemoveTabOutOfRangeNoOp;
    procedure TestExternalFreePageHardensArrays;
```
implementation 区追加(注意:`RemoveTab` 是 public):
```pascal
procedure TTyTabControlTest.TestRemoveTabCompactsAndAdjustsIndex;
begin
  FTab.AddTab('A');
  FTab.AddTab('B');
  FTab.AddTab('C');
  AssertEquals('3 tabs', 3, FTab.TabCount);
  FTab.RemoveTab(1);                 // remove middle 'B'
  AssertEquals('2 tabs after remove', 2, FTab.TabCount);
  AssertEquals('caption[0] still A', 'A', FTab.TabCaption(0));
  AssertEquals('caption[1] now C', 'C', FTab.TabCaption(1));
end;

procedure TTyTabControlTest.TestRemoveActiveTabSelectsNeighborFiresOnChange;
var
  Probe: TTabChangeProbe;
begin
  FTab.AddTab('A');
  FTab.AddTab('B');
  FTab.AddTab('C');
  FTab.TabIndex := 2;                 // active = last 'C'
  Probe := TTabChangeProbe.Create;
  try
    FTab.OnChange := @Probe.Handle;
    FTab.RemoveTab(2);                // remove active last -> neighbor (idx 1)
    AssertEquals('TabIndex falls back to new last (1)', 1, FTab.TabIndex);
    AssertTrue('new active page visible', FTab.Pages[1].Visible);
    AssertEquals('OnChange fired once (active page changed)', 1, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyTabControlTest.TestRemoveTabBeforeActiveKeepsActivePageNoOnChange;
var
  Probe: TTabChangeProbe;
  ActivePageBefore: TTyPanel;
begin
  FTab.AddTab('A');
  FTab.AddTab('B');
  FTab.AddTab('C');
  FTab.TabIndex := 2;                 // active 'C'
  ActivePageBefore := FTab.Pages[2];
  Probe := TTabChangeProbe.Create;
  try
    FTab.OnChange := @Probe.Handle;
    FTab.RemoveTab(0);                // remove 'A' (before active)
    AssertEquals('index shifts 2 -> 1', 1, FTab.TabIndex);
    AssertSame('same page object still active', ActivePageBefore, FTab.Pages[1]);
    AssertTrue('still visible', FTab.Pages[1].Visible);
    AssertEquals('OnChange NOT fired (same page active)', 0, Probe.Count);
  finally
    Probe.Free;
  end;
end;

procedure TTyTabControlTest.TestRemoveTabOutOfRangeNoOp;
begin
  FTab.AddTab('A');
  FTab.RemoveTab(5);
  FTab.RemoveTab(-1);
  AssertEquals('still 1 tab', 1, FTab.TabCount);
end;

procedure TTyTabControlTest.TestExternalFreePageHardensArrays;
{ Freeing a page panel directly (not via RemoveTab) must update the parallel
  arrays via Notification, not leave a dangling pointer. }
var
  PageB: TTyPanel;
begin
  FTab.AddTab('A');
  PageB := FTab.AddTab('B');
  FTab.AddTab('C');
  AssertEquals('3 tabs', 3, FTab.TabCount);
  PageB.Free;                         // external free of middle page
  AssertEquals('2 tabs after external free', 2, FTab.TabCount);
  AssertEquals('caption[0] A', 'A', FTab.TabCaption(0));
  AssertEquals('caption[1] C (B detached)', 'C', FTab.TabCaption(1));
  { Re-render must not crash with a dangling page }
  FTab.Invalidate;
end;
```

- [ ] **Step 2: 运行,确认失败/不编译**

Run: `cd /Users/tom/Projects/TyControls && lazbuild tests/tytests.lpi 2>&1 | tail -5`
Expected: 编译失败(`RemoveTab` 未声明)。这就是失败信号。

- [ ] **Step 3: 实现 — 改 source/tyControls.TabControl.pas**

3a. `private` 区新增字段与方法声明(在 `FOnChange` 后):
```pascal
    FDestroying: Boolean;
```
并在 private 方法区加:
```pascal
    function  IndexOfPage(APage: TTyPanel): Integer;
    procedure RemovePageInternal(AIndex: Integer; AFree: Boolean);
```

3b. `public` 区(在 `AddTab` 后)加:
```pascal
    procedure RemoveTab(AIndex: Integer);
```

3c. `protected` 区加 Notification 覆盖声明:
```pascal
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
```

3d. 改 `Destroy`(先置 FDestroying):
```pascal
destructor TTyTabControl.Destroy;
begin
  FDestroying := True;
  FCaptions.Free;
  { Pages are owned components (Owner=Self) so freed by TComponent.Destroy }
  inherited Destroy;
end;
```

3e. 在 implementation 区新增方法实现(放在 AddTab 之后即可):
```pascal
function TTyTabControl.IndexOfPage(APage: TTyPanel): Integer;
var I: Integer;
begin
  Result := -1;
  for I := 0 to High(FPages) do
    if FPages[I] = APage then
      Exit(I);
end;

{ Shared removal for both RemoveTab (AFree=True) and Notification/external free
  (AFree=False). Compacts the parallel arrays, fixes FTabIndex, reselects, and
  fires OnChange only when the visually-active page object actually changes. }
procedure TTyTabControl.RemovePageInternal(AIndex: Integer; AFree: Boolean);
var
  OldActive, NewActive, Page: TTyPanel;
  J: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FPages)) then Exit;

  if (FTabIndex >= 0) and (FTabIndex < Length(FPages)) then
    OldActive := FPages[FTabIndex]
  else
    OldActive := nil;

  Page := FPages[AIndex];

  { Detach from parallel arrays BEFORE freeing, so a Free-triggered Notification
    cannot find the page and re-enter this routine. }
  FCaptions.Delete(AIndex);
  for J := AIndex to High(FPages) - 1 do
    FPages[J] := FPages[J + 1];
  SetLength(FPages, Length(FPages) - 1);

  { Fix selected index. }
  if Length(FPages) = 0 then
    FTabIndex := -1
  else if AIndex < FTabIndex then
    Dec(FTabIndex)
  else if AIndex = FTabIndex then
  begin
    if FTabIndex > High(FPages) then
      FTabIndex := High(FPages);
  end;
  { AIndex > FTabIndex: unchanged. }

  if AFree and (Page <> nil) then
    Page.Free;

  ShowOnlyPage(FTabIndex);
  Invalidate;

  if (FTabIndex >= 0) and (FTabIndex < Length(FPages)) then
    NewActive := FPages[FTabIndex]
  else
    NewActive := nil;

  if (NewActive <> OldActive) and Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTabControl.RemoveTab(AIndex: Integer);
begin
  RemovePageInternal(AIndex, True);
end;

procedure TTyTabControl.Notification(AComponent: TComponent; Operation: TOperation);
var
  Idx: Integer;
begin
  inherited Notification(AComponent, Operation);   // base nils FController etc.
  if FDestroying then Exit;
  if (Operation = opRemove) and (AComponent is TTyPanel) then
  begin
    Idx := IndexOfPage(TTyPanel(AComponent));
    if Idx >= 0 then
      RemovePageInternal(Idx, False);              // already being freed
  end;
end;
```

> 注意:`ShowOnlyPage` 当前实现遍历 `FPages` 设 Visible,对压缩后的数组安全。`RemovePageInternal` 不复用 `SetTabIndex`(后者有自己的 OnChange 触发),手动改 `FTabIndex` 以精确控制 OnChange 语义。

- [ ] **Step 4: 构建并运行 TabControl 套件**

Run: `cd /Users/tom/Projects/TyControls && lazbuild tests/tytests.lpi && ./tests/tytests --suite=TTyTabControlTest --format=plain`
Expected: 全部通过(原 12 + 新 5 = 17)。

- [ ] **Step 5: 全量回归**

Run: `./tests/tytests -a --format=plain 2>&1 | grep -i "number of"`
Expected: 295 + 5 = 300,0 errors,0 failures。

- [ ] **Step 6: Commit**

```bash
git add source/tyControls.TabControl.pas tests/test.tabcontrol.pas
git commit -m "feat(tycontrols): TTyTabControl RemoveTab + Notification dangling-page hardening"
```

---

## Task 2: 可关闭页签 + 单遍布局(消除 O(n²))

**Files:**
- Modify: `source/tyControls.TabControl.pas`
- Modify: `tests/test.tabcontrol.pas`

- [ ] **Step 1: 写失败测试 — 追加到 tests/test.tabcontrol.pas**

`TTyTabControlAccess` 加暴露(public):无需新增(closable 走 published 属性 + public TyTabCloseRect;关闭点击走已暴露的 `CallMouseDown`)。

在 `TTyTabControlTest` published 区追加:
```pascal
    procedure TestNonClosableGeometryUnchanged;
    procedure TestClosableWidensHeaderAndCloseRectInside;
    procedure TestClickCloseFiresEventAndRemoves;
    procedure TestClickCloseCanceledKeepsTab;
    procedure TestClickHeaderBodyStillSelectsWhenClosable;
```
implementation 区追加(用一个本地 close 探针):
```pascal
type
  TTabCloseProbe = class
  public
    LastIndex: Integer;
    Count: Integer;
    Cancel: Boolean;
    constructor Create;
    procedure Handle(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
  end;

constructor TTabCloseProbe.Create;
begin
  inherited Create;
  LastIndex := -99;
  Count := 0;
  Cancel := False;
end;

procedure TTabCloseProbe.Handle(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
begin
  Inc(Count);
  LastIndex := AIndex;
  if Cancel then AllowClose := False;
end;

procedure TTyTabControlTest.TestNonClosableGeometryUnchanged;
{ Default TabsClosable=False: header geometry identical to pre-v1.4 + empty close rect. }
var R0, R1, C0: TRect;
begin
  FTab.AddTab('AB');
  FTab.AddTab('CD');
  AssertFalse('default not closable', FTab.TabsClosable);
  R0 := FTab.TyTabHeaderRect(0);
  R1 := FTab.TyTabHeaderRect(1);
  AssertEquals('rect(0).Left=0', 0, R0.Left);
  AssertEquals('rect(0).Bottom=28', 28, R0.Bottom);
  AssertEquals('rect(1).Left = rect(0).Right', R0.Right, R1.Left);
  AssertTrue('width >= 48', (R0.Right - R0.Left) >= 48);
  C0 := FTab.TyTabCloseRect(0);
  AssertTrue('close rect empty when not closable',
    (C0.Right - C0.Left) = 0);
end;

procedure TTyTabControlTest.TestClosableWidensHeaderAndCloseRectInside;
var WNarrow, WClosable: Integer; R0, C0: TRect;
begin
  FTab.AddTab('AB');
  WNarrow := FTab.TyTabHeaderRect(0).Right - FTab.TyTabHeaderRect(0).Left;
  FTab.TabsClosable := True;
  R0 := FTab.TyTabHeaderRect(0);
  WClosable := R0.Right - R0.Left;
  AssertTrue('closable header wider than non-closable', WClosable > WNarrow);
  C0 := FTab.TyTabCloseRect(0);
  AssertTrue('close rect non-empty when closable', (C0.Right - C0.Left) > 0);
  AssertTrue('close rect inside header (left>=R0.Left)', C0.Left >= R0.Left);
  AssertTrue('close rect inside header (right<=R0.Right)', C0.Right <= R0.Right);
  AssertTrue('close rect within header vertically', (C0.Top >= R0.Top) and (C0.Bottom <= R0.Bottom));
end;

procedure TTyTabControlTest.TestClickCloseFiresEventAndRemoves;
var
  Acc: TTyTabControlAccess;
  Probe: TTabCloseProbe;
  C1: TRect;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  Acc.SetBounds(0, 0, 300, 200);
  Probe := TTabCloseProbe.Create;
  try
    Acc.TabsClosable := True;
    Acc.OnTabClose := @Probe.Handle;
    Acc.AddTab('A');
    Acc.AddTab('B');
    Acc.AddTab('C');
    C1 := Acc.TyTabCloseRect(1);
    Acc.CallMouseDown(mbLeft, (C1.Left + C1.Right) div 2, (C1.Top + C1.Bottom) div 2);
    AssertEquals('OnTabClose fired once', 1, Probe.Count);
    AssertEquals('event index = 1', 1, Probe.LastIndex);
    AssertEquals('tab removed -> 2 tabs', 2, Acc.TabCount);
    AssertEquals('caption[1] now C', 'C', Acc.TabCaption(1));
  finally
    Probe.Free;
    Acc.Free;
  end;
end;

procedure TTyTabControlTest.TestClickCloseCanceledKeepsTab;
var
  Acc: TTyTabControlAccess;
  Probe: TTabCloseProbe;
  C0: TRect;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  Acc.SetBounds(0, 0, 300, 200);
  Probe := TTabCloseProbe.Create;
  try
    Acc.TabsClosable := True;
    Probe.Cancel := True;             // handler vetoes close
    Acc.OnTabClose := @Probe.Handle;
    Acc.AddTab('A');
    Acc.AddTab('B');
    C0 := Acc.TyTabCloseRect(0);
    Acc.CallMouseDown(mbLeft, (C0.Left + C0.Right) div 2, (C0.Top + C0.Bottom) div 2);
    AssertEquals('event fired', 1, Probe.Count);
    AssertEquals('canceled -> still 2 tabs', 2, Acc.TabCount);
  finally
    Probe.Free;
    Acc.Free;
  end;
end;

procedure TTyTabControlTest.TestClickHeaderBodyStillSelectsWhenClosable;
{ Clicking the header body (NOT the close glyph) still selects, even when closable. }
var
  Acc: TTyTabControlAccess;
  R1, C1: TRect;
  BodyX: Integer;
begin
  Acc := TTyTabControlAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  Acc.SetBounds(0, 0, 300, 200);
  try
    Acc.TabsClosable := True;
    Acc.AddTab('Alpha');
    Acc.AddTab('Beta');
    R1 := Acc.TyTabHeaderRect(1);
    C1 := Acc.TyTabCloseRect(1);
    BodyX := R1.Left + 4;             // left edge of header, away from close glyph
    AssertTrue('body x left of close rect', BodyX < C1.Left);
    Acc.CallMouseDown(mbLeft, BodyX, (R1.Top + R1.Bottom) div 2);
    AssertEquals('header body click selects tab 1', 1, Acc.TabIndex);
    AssertEquals('no tab removed', 2, Acc.TabCount);
  finally
    Acc.Free;
  end;
end;
```
(把 `TTabCloseProbe` 的 type 声明放在 implementation 区顶部、第一个用到它的方法之前即可。)

- [ ] **Step 2: 运行,确认失败/不编译**

Run: `cd /Users/tom/Projects/TyControls && lazbuild tests/tytests.lpi 2>&1 | tail -5`
Expected: 编译失败(`TabsClosable`/`OnTabClose`/`TyTabCloseRect` 未声明)。

- [ ] **Step 3: 实现 — 改 source/tyControls.TabControl.pas**

3a. 在 interface 的 `type` 区(`TTyTabControl` 声明之前)加事件类型:
```pascal
  TTyTabCloseEvent = procedure(Sender: TObject; AIndex: Integer;
    var AllowClose: Boolean) of object;
```

3b. `private` 区加字段:
```pascal
    FTabsClosable: Boolean;
    FOnTabClose: TTyTabCloseEvent;
    FHeaderRects: array of TRect;   // device px, (0,0)-local, rebuilt per layout
    FCloseRects:  array of TRect;   // device px; empty rect when not closable
```
private 方法区加:
```pascal
    procedure SetTabsClosable(AValue: Boolean);
    procedure RebuildLayout(APPI: Integer);
    procedure DoCloseTab(AIndex: Integer);
```

3c. `public` 区加:
```pascal
    function TyTabCloseRect(AIndex: Integer): TRect;
```

3d. `published` 区加:
```pascal
    property TabsClosable: Boolean read FTabsClosable write SetTabsClosable default False;
    property OnTabClose: TTyTabCloseEvent read FOnTabClose write FOnTabClose;
```

3e. `Create` 末尾(在设 Width/Height 前后均可)加初始化(布尔默认 False 已由对象清零保证,显式更清晰):
```pascal
  FTabsClosable := False;
```

3f. 新增 `SetTabsClosable`:
```pascal
procedure TTyTabControl.SetTabsClosable(AValue: Boolean);
begin
  if FTabsClosable = AValue then Exit;
  FTabsClosable := AValue;
  Invalidate;
end;
```

3g. 新增 `RebuildLayout` —— 单遍 O(n) 计算所有页签头/关闭区。**非 closable 时几何与旧 `TyTabHeaderRect` 完全一致。**
```pascal
procedure TTyTabControl.RebuildLayout(APPI: Integer);
var
  TabH, Pad, MinW, CloseSize, Gap, CloseSlot, Margin: Integer;
  TabStyle: TTyStyleSet;
  I, X, TW, HW, Cy: Integer;
begin
  SetLength(FHeaderRects, FCaptions.Count);
  SetLength(FCloseRects, FCaptions.Count);

  TabH      := TabHPx(APPI);
  Pad       := MulDiv(12, APPI, 96);
  MinW      := MulDiv(48, APPI, 96);
  CloseSize := MulDiv(14, APPI, 96);
  Gap       := MulDiv(6,  APPI, 96);
  Margin    := MulDiv(6,  APPI, 96);
  CloseSlot := CloseSize + Gap;

  TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', [tysNormal]);

  X := 0;
  for I := 0 to FCaptions.Count - 1 do
  begin
    TW := TabCaptionWidth(FCaptions[I], TabStyle, APPI) + 2 * Pad;
    if FTabsClosable then
    begin
      Inc(TW, CloseSlot);
      if TW < (MinW + CloseSlot) then TW := MinW + CloseSlot;
    end
    else
      if TW < MinW then TW := MinW;

    HW := TW;
    FHeaderRects[I] := Rect(X, 0, X + HW, TabH);

    if FTabsClosable then
    begin
      Cy := (TabH - CloseSize) div 2;
      FCloseRects[I] := Rect(X + HW - Margin - CloseSize, Cy,
                             X + HW - Margin, Cy + CloseSize);
    end
    else
      FCloseRects[I] := Rect(0, 0, 0, 0);

    Inc(X, HW);
  end;
end;
```

3h. 重写公开 `TyTabHeaderRect` 用布局数组(保持签名/语义):
```pascal
function TTyTabControl.TyTabHeaderRect(AIndex: Integer): TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FHeaderRects)) then
    Result := Rect(0, 0, 0, 0)
  else
    Result := FHeaderRects[AIndex];
end;
```

3i. 新增公开 `TyTabCloseRect`:
```pascal
function TTyTabControl.TyTabCloseRect(AIndex: Integer): TRect;
begin
  if not FTabsClosable then
    Exit(Rect(0, 0, 0, 0));
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FCloseRects)) then
    Result := Rect(0, 0, 0, 0)
  else
    Result := FCloseRects[AIndex];
end;
```

3j. 新增 `DoCloseTab`:
```pascal
procedure TTyTabControl.DoCloseTab(AIndex: Integer);
var
  AllowClose: Boolean;
begin
  if (AIndex < 0) or (AIndex >= FCaptions.Count) then Exit;
  AllowClose := True;
  if Assigned(FOnTabClose) then
    FOnTabClose(Self, AIndex, AllowClose);
  if AllowClose then
    RemoveTab(AIndex);
end;
```

3k. 改 `RenderTo`:在 `BeginPaint` 后、画 header 前调一次 `RebuildLayout(APPI)`;header 循环改为读 `FHeaderRects[I]`;closable 时文本绘制区右边界缩到 `FCloseRects[I].Left`,并画 × 字形。替换 header 绘制循环为:
```pascal
    RebuildLayout(APPI);

    { Draw each tab header }
    for I := 0 to FCaptions.Count - 1 do
    begin
      HdrRect := FHeaderRects[I];

      TabStates := [];
      if I = FTabIndex then
        Include(TabStates, tysActive)
      else if I = FHoverTab then
        Include(TabStates, tysHover)
      else
        Include(TabStates, tysNormal);

      TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', TabStates);

      if tpBackground in TabStyle.Present then
        P.FillBackground(HdrRect, TabStyle.Background, 0);

      { Caption: when closable, keep clear of the close glyph slot. }
      TextRect := HdrRect;
      if FTabsClosable then
        TextRect.Right := FCloseRects[I].Left;
      P.DrawText(TextRect,
        FCaptions[I],
        TabStyle.FontName, TabStyle.FontSize, TabStyle.FontWeight,
        TabStyle.TextColor,
        taCenter, tlCenter, True);

      if FTabsClosable then
        P.DrawGlyph(FCloseRects[I], tgClose, TabStyle.TextColor, 1);
    end;
```
并在 `RenderTo` 的 `var` 区补一个 `TextRect: TRect;`(`HdrRect` 已有)。

3l. 改 `MouseDown`:在命中循环里先用布局数组,先判关闭区再判选中:
```pascal
procedure TTyTabControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  PPI, TabH, I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    PPI  := Font.PixelsPerInch;
    TabH := TabHPx(PPI);
    if Y < TabH then
    begin
      RebuildLayout(PPI);
      for I := 0 to FCaptions.Count - 1 do
      begin
        if (X >= FHeaderRects[I].Left) and (X < FHeaderRects[I].Right) then
        begin
          if FTabsClosable and
             (X >= FCloseRects[I].Left) and (X < FCloseRects[I].Right) and
             (Y >= FCloseRects[I].Top) and (Y < FCloseRects[I].Bottom) then
            DoCloseTab(I)
          else
            TabIndex := I;
          Break;
        end;
      end;
    end;
    try
      if CanFocus then SetFocus;
    except
      { Ignore focus errors in headless/test environments }
    end;
  end;
end;
```

3m. 改 `MouseMove` 用布局数组(仅去掉 per-iter `TyTabHeaderRect` 调用,行为不变):
```pascal
procedure TTyTabControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  PPI, TabH, NewHover, I: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  PPI  := Font.PixelsPerInch;
  TabH := TabHPx(PPI);
  NewHover := -1;
  if Y < TabH then
  begin
    RebuildLayout(PPI);
    for I := 0 to FCaptions.Count - 1 do
      if (X >= FHeaderRects[I].Left) and (X < FHeaderRects[I].Right) then
      begin
        NewHover := I;
        Break;
      end;
  end;
  if NewHover <> FHoverTab then
  begin
    FHoverTab := NewHover;
    Invalidate;
  end;
end;
```

> 删除旧的 `TyTabHeaderRect` 的内联几何循环实现(被 3h 替换);`TabCaptionWidth`/`TabHPx` 保留不变。`uses` 已含 `tyControls.Painter`(`tgClose`/`TTyGlyphKind` 在该单元),无需新增。

- [ ] **Step 4: 构建并运行 TabControl 套件**

Run: `cd /Users/tom/Projects/TyControls && lazbuild tests/tytests.lpi && ./tests/tytests --suite=TTyTabControlTest --format=plain`
Expected: 全通过(17 + 5 = 22)。特别确认 `TestHeaderRectsLayout`、`TestMouseDownSelectsTab`、`TestActiveTabRendersActiveStyle`(非 closable 几何不变)仍绿。

- [ ] **Step 5: 全量回归**

Run: `./tests/tytests -a --format=plain 2>&1 | grep -i "number of"`
Expected: 300 + 5 = 305,0 errors,0 failures。

- [ ] **Step 6: Commit**

```bash
git add source/tyControls.TabControl.pas tests/test.tabcontrol.pas
git commit -m "feat(tycontrols): closable tabs (TabsClosable/OnTabClose/TyTabCloseRect) + single-pass header layout"
```

---

## Task 3: 集成(示例 + 文档)

**Files:**
- Modify: `examples/tabcontrol/` (主窗体单元,代码建 UI)
- Modify: `docs/controls/tabcontrol.md`
- Modify: `docs/KNOWN_GAPS.md`
- Modify: `README.md`

- [ ] **Step 1: 示例展示 closable** — 读 `examples/tabcontrol/` 下的主窗体单元(`grep -rl TTyTabControl examples/tabcontrol`),在创建 TabControl 后加 `TabCtrl.TabsClosable := True;` 并挂一个 `OnTabClose` 处理器(默认允许关闭即可,可加注释说明可置 `AllowClose:=False` 取消)。确保 `lazbuild examples/tabcontrol/*.lpi` 通过。

- [ ] **Step 2: 文档 docs/controls/tabcontrol.md** — 读该文件,补:`RemoveTab(AIndex)`;`TabsClosable`(默认 False);`OnTabClose(Sender; AIndex; var AllowClose)`(关闭语义、取消方法);`TyTabCloseRect`(测试/命中几何);并说明外部释放页面板已由 Notification 安全处理。

- [ ] **Step 3: docs/KNOWN_GAPS.md** — 找到 TabControl 相关条目:删除/改写"页签关闭按钮"已实现;保留"页签横向滚动溢出截断"与"拖拽重排"为仍未做。`grep -n -i "tab\|页签" docs/KNOWN_GAPS.md` 定位。

- [ ] **Step 4: README.md** — 在 TabControl 能力描述处(或控件列表)补一句:支持可关闭页签(× / OnTabClose)与运行时增删页(AddTab/RemoveTab)。`grep -n -i "tabcontrol\|页签\|标签页" README.md` 定位。

- [ ] **Step 5: 构建矩阵 + 全量测试**

Run: `cd /Users/tom/Projects/TyControls && bash scripts/build-matrix.sh 2>&1 | tail -8 && ./tests/tytests -a --format=plain 2>&1 | grep -i "number of"`
Expected: 矩阵全绿;测试 305,0/0。

- [ ] **Step 6: Commit**

```bash
git add examples/tabcontrol docs/controls/tabcontrol.md docs/KNOWN_GAPS.md README.md
git commit -m "docs(tycontrols): document closable tabs + RemoveTab; showcase in tabcontrol example"
```

---

## 完成后
- 最终全套件 + 构建矩阵 + heaptrc 0 泄漏核查(重点:反复 AddTab/RemoveTab 不漏;外部 Free 页不漏不崩)。
- 终审(reviewer 跑探针)。
- 通过后 superpowers:finishing-a-development-branch(本仓约定:本地快进合并 main + 删分支)。
- 更新项目记忆 `tycontrols-project.md`(TabControl 已补 RemoveTab/Notification/可关闭页签;backlog 去掉关闭项,保留滚动/拖拽)。
