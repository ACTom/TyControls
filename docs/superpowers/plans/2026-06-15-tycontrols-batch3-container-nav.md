# TyControls 批③ 容器/导航 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Panel/GroupBox 加 `Alignment`;TabControl 加 Ctrl+Tab/Ctrl+PgUp-Dn/Home/End;ScrollBar 加端部箭头按钮 + `SmallChange` + 键盘;TrackBar 加 `Orientation`(竖向)+ `Frequency` 刻度 + `LineSize`/`PageSize` + 键盘。

**Architecture:** 纯叠加、向后兼容。几何抽成可单测纯函数:`TyScrollButtonSize`/`TyScrollTrackRect`(滚动条轨道内缩),`TyTrackThumbOffset`/`TyTrackPosFromOffset`(轨道条双向几何 + 反算)。横向 TrackBar / 现有 ScrollBar 几何走纯函数的非镜像分支,逐像素回归。

**Tech Stack:** Free Pascal / Lazarus LCL;FPCUnit;PPI=96;无头键盘/鼠标注入。

**约定:** 运行测试 `lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain`。基线 **0 failures + 15 个无头 win32(error 1407)环境错误(忽略)**。新增测试加在已注册单元里。提交 `feat(tycontrols): …`。`examples/demo/*` 是用户测试台——只 stage 本任务的源/测试文件,不动 demo。

---

## File Structure
- `source/tyControls.Panel.pas` — `FAlignment` + published `Alignment`(默认 taCenter);RenderTo 用之。
- `source/tyControls.GroupBox.pas` — `FAlignment` + published `Alignment`(默认 taLeftJustify);RenderTo 标题 + 擦除带按 Alignment 定位。
- `source/tyControls.TabControl.pas` — `KeyDown` 扩展 Ctrl+Tab/Ctrl+Shift+Tab(循环)/Ctrl+PgDn-Up(夹紧)/Home/End。
- `source/tyControls.ScrollBar.pas` — `FSmallChange` + published `SmallChange`;纯函数 `TyScrollButtonSize`/`TyScrollTrackRect`;轨道内缩 + 箭头按钮渲染/命中 + `KeyDown`。
- `source/tyControls.TrackBar.pas` — `TTyTrackOrientation` + `FOrientation`/`FFrequency`/`FLineSize`/`FPageSize` + published;纯函数 `TyTrackThumbOffset`/`TyTrackPosFromOffset`;双向 ThumbRect/DragTo/RenderTo + 刻度 + `KeyDown`。
- Tests:`tests/test.controls.panel.pas`、`test.groupbox.pas`、`test.tabcontrol.pas`、`test.controls.scrollbar.pas`(有 `TScrollAccess`)、`test.trackbar.pas`(有 `TTyTrackBarProbe` 暴露 RenderTo/SimulateKeyDown(var Key)/SimulateMouseDown)。
- Docs:`docs/controls/panel.md`、`groupbox.md`、`tabcontrol.md`、`scrollbar.md`、`trackbar.md`。

---

## Task 1: TTyPanel.Alignment

**Files:** Modify `source/tyControls.Panel.pas`;Test `tests/test.controls.panel.pas`.

- [ ] **Step 1: 失败测试**(渲染对齐:左/右对齐时标题墨迹的水平重心不同。加到 panel 测试单元;若无 access 子类暴露 RenderTo,加 `TPanelAccess = class(TTyPanel) public procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer); begin RenderTo(ACanvas, ARect, APPI); end; end;`):
```pascal
procedure TestAlignmentMovesCaptionInk;
  function InkCentroidX(A: TAlignment): Double;
  var P: TPanelAccess; bmp: TBitmap; reread: TBGRABitmap; x,y,n: Integer; sx: Double; px: TBGRAPixel;
  begin
    P := TPanelAccess.Create(nil);
    bmp := TBitmap.Create;
    try
      P.Caption := 'Hi'; P.Alignment := A; P.Font.PixelsPerInch := 96;
      bmp.PixelFormat := pf32bit; bmp.SetSize(200, 30);
      bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0,0,200,30);
      P.DoRenderTo(bmp.Canvas, Rect(0,0,200,30), 96);
      reread := TBGRABitmap.Create(bmp);
      try
        sx := 0; n := 0;
        for x := 0 to 199 do for y := 4 to 26 do
        begin px := reread.GetPixel(x,y);
          if (px.red<160) and (px.green<160) then begin sx := sx + x; Inc(n); end; end;
        if n = 0 then Result := -1 else Result := sx / n;
      finally reread.Free; end;
    finally bmp.Free; P.Free; end;
  end;
var cl, cr: Double;
begin
  cl := InkCentroidX(taLeftJustify);
  cr := InkCentroidX(taRightJustify);
  AssertTrue('left caption has ink', cl > 0);
  AssertTrue('right-aligned caption ink is further right than left-aligned', cr > cl + 20);
end;
```
Register it. (`TBitmap`/`TBGRABitmap`/`clWhite` need `Graphics, BGRABitmap, BGRABitmapTypes` in uses — add if missing.)

- [ ] **Step 2: 确认失败/不编译**(`Alignment` 未声明)。`lazbuild tests/tytests.lpi`。
- [ ] **Step 3: 实现**(`source/tyControls.Panel.pas`):
  - `uses` 确认含 `Graphics`(`TAlignment`)——是。private `FAlignment: TAlignment;`(`Create` 加 `FAlignment := taCenter;`)+ setter `SetAlignment`(`if FAlignment=AValue then Exit; FAlignment:=AValue; Invalidate;`)。published `property Alignment: TAlignment read FAlignment write SetAlignment default taCenter;`
  - RenderTo:把 `P.DrawText(ContentRect, FCaption, ..., taLeftJustify, tlCenter, True)` 的 `taLeftJustify` 改为 `FAlignment`。
- [ ] **Step 4: 跑;新用例 PASS;现有 panel 测试全绿。**
- [ ] **Step 5: Commit** `git add source/tyControls.Panel.pas tests/test.controls.panel.pas && git commit -m "feat(tycontrols): TTyPanel.Alignment (caption alignment, default taCenter)"`

---

## Task 2: TTyGroupBox.Alignment

**Files:** Modify `source/tyControls.GroupBox.pas`;Test `tests/test.groupbox.pas`.

- [ ] **Step 1: 失败测试**(与 Task1 同型,但 GroupBox 标题带在顶部 16px;探针 y 取 0..15;默认 left。加 `TGroupBoxAccess` 暴露 RenderTo 若无):
```pascal
procedure TestGroupBoxAlignmentMovesCaption;
  function InkCentroidX(A: TAlignment): Double;
  var G: TGroupBoxAccess; bmp: TBitmap; reread: TBGRABitmap; x,y,n: Integer; sx: Double; px: TBGRAPixel;
  begin
    G := TGroupBoxAccess.Create(nil); bmp := TBitmap.Create;
    try
      G.Caption := 'Hi'; G.Alignment := A; G.Font.PixelsPerInch := 96;
      bmp.PixelFormat := pf32bit; bmp.SetSize(200, 60);
      bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0,0,200,60);
      G.DoRenderTo(bmp.Canvas, Rect(0,0,200,60), 96);
      reread := TBGRABitmap.Create(bmp);
      try
        sx := 0; n := 0;
        for x := 0 to 199 do for y := 0 to 15 do
        begin px := reread.GetPixel(x,y);
          if (px.red<160) and (px.green<160) then begin sx := sx + x; Inc(n); end; end;
        if n = 0 then Result := -1 else Result := sx / n;
      finally reread.Free; end;
    finally bmp.Free; G.Free; end;
  end;
var cl, cr: Double;
begin
  cl := InkCentroidX(taLeftJustify);
  cr := InkCentroidX(taRightJustify);
  AssertTrue('left caption ink present', cl > 0);
  AssertTrue('right-aligned caption further right', cr > cl + 20);
end;
```
Register it.

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现**(`source/tyControls.GroupBox.pas`):
  - private `FAlignment: TAlignment;`(`Create` 加 `FAlignment := taLeftJustify;`)+ `SetAlignment`(同 Task1)。published `property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;`
  - RenderTo 的标题分支:按 `FAlignment` 定 `TextRect` 起点与擦除带 `BandRect`。当前:`BandRect := Rect(P.Scale(8), 0, P.Scale(8)+TextW+P.Scale(8), CapH); TextRect := Rect(P.Scale(12), 0, W - P.Scale(4), CapH);` DrawText 用 `taLeftJustify`。改为:
    ```pascal
    var BandLeft, TextLeft: Integer;
    case FAlignment of
      taCenter:      BandLeft := (W - (TextW + P.Scale(16))) div 2;
      taRightJustify:BandLeft := W - (TextW + P.Scale(16)) - P.Scale(4);
    else             BandLeft := P.Scale(4);   // taLeftJustify (current look: band starts ~Scale(8))
    end;
    if BandLeft < 0 then BandLeft := 0;
    BandRect := Rect(BandLeft, 0, BandLeft + TextW + P.Scale(16), CapH);
    P.EraseRect(BandRect);
    TextRect := Rect(BandLeft + P.Scale(4), 0, BandLeft + P.Scale(4) + TextW + P.Scale(8), CapH);
    P.DrawText(TextRect, FCaption, S.FontName, ResolveFontSize(S), S.FontWeight,
      S.TextColor, FAlignment, tlCenter, True);
    ```
    > 为保持 `taLeftJustify` 默认渲染与现状基本一致(标题在左、带覆盖文字),`BandLeft` 左对齐取 `Scale(4)`、文字 `taLeftJustify` 落在带内。现有 groupbox 测试若断言具体像素,按需放宽到"标题区有墨迹"(默认左对齐墨迹仍在左侧,不应破坏方向性断言)。RenderTo 顶部 var 区加 `BandLeft, TextLeft: Integer;`(TextLeft 可省)。
- [ ] **Step 4: 跑;新用例 PASS;现有 groupbox 测试全绿(若某像素断言因带位置微移而挂,确认是默认左对齐的合理范围内并更新坐标,勿弱化方向性)。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyGroupBox.Alignment (caption alignment, default left)`

---

## Task 3: TTyTabControl 键盘导航

**Files:** Modify `source/tyControls.TabControl.pas`;Test `tests/test.tabcontrol.pas`.

- [ ] **Step 1: 失败测试**(给 tab 测试加 access `DoKeyDown(var Key; Shift)` 若无;`TabCount`/`TabIndex`/`AddTab` 已公开):
```pascal
procedure TestTabKeyboardNav;
var T: TTabAccess; K: Word;
begin
  T := TTabAccess.Create(nil);
  try
    T.AddTab('A'); T.AddTab('B'); T.AddTab('C'); T.TabIndex := 0;
    K := VK_TAB; T.DoKeyDown(K, [ssCtrl]);                 // Ctrl+Tab -> next
    AssertEquals('ctrl+tab next', 1, T.TabIndex);
    K := VK_END; T.DoKeyDown(K, []);
    AssertEquals('end -> last', 2, T.TabIndex);
    K := VK_TAB; T.DoKeyDown(K, [ssCtrl]);                 // wrap last->first
    AssertEquals('ctrl+tab wraps', 0, T.TabIndex);
    K := VK_TAB; T.DoKeyDown(K, [ssCtrl, ssShift]);        // Ctrl+Shift+Tab wraps first->last
    AssertEquals('ctrl+shift+tab wraps back', 2, T.TabIndex);
    K := VK_HOME; T.DoKeyDown(K, []);
    AssertEquals('home -> first', 0, T.TabIndex);
    K := VK_NEXT; T.DoKeyDown(K, [ssCtrl]);                // Ctrl+PageDown -> next (clamp)
    AssertEquals('ctrl+pgdn next', 1, T.TabIndex);
  finally T.Free; end;
end;
```
Register it. (Add a `TTabAccess = class(TTyTabControl) public procedure DoKeyDown(var Key: Word; Shift: TShiftState); begin KeyDown(Key, Shift); end; end;` if the file lacks a keydown access; `VK_TAB`/`VK_NEXT`/`VK_PRIOR`/`VK_HOME`/`VK_END` from LCLType.)

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现** —— 扩展 `TTyTabControl.KeyDown`。在现有 `case Key of VK_RIGHT/VK_LEFT` 之前(或之内),先处理 Ctrl 组合与 Home/End。把方法体改为:
```pascal
procedure TTyTabControl.KeyDown(var Key: Word; Shift: TShiftState);
var NewIndex, Cnt: Integer;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  Cnt := FCaptions.Count;
  if Cnt = 0 then Exit;
  // Ctrl+Tab / Ctrl+Shift+Tab: cycle with wrap.
  if (Key = VK_TAB) and (ssCtrl in Shift) then
  begin
    if ssShift in Shift then NewIndex := FTabIndex - 1 else NewIndex := FTabIndex + 1;
    if NewIndex < 0 then NewIndex := Cnt - 1;
    if NewIndex > Cnt - 1 then NewIndex := 0;
    TabIndex := NewIndex; Key := 0; Exit;
  end;
  // Ctrl+PageDown / Ctrl+PageUp: next/prev, clamp.
  if (Key = VK_NEXT) and (ssCtrl in Shift) then
  begin
    if FTabIndex < Cnt - 1 then TabIndex := FTabIndex + 1; Key := 0; Exit;
  end;
  if (Key = VK_PRIOR) and (ssCtrl in Shift) then
  begin
    if FTabIndex > 0 then TabIndex := FTabIndex - 1; Key := 0; Exit;
  end;
  case Key of
    VK_HOME:  begin TabIndex := 0; Key := 0; end;
    VK_END:   begin TabIndex := Cnt - 1; Key := 0; end;
    VK_RIGHT:
      begin
        NewIndex := FTabIndex + 1;
        if NewIndex > Cnt - 1 then NewIndex := Cnt - 1;
        TabIndex := NewIndex; Key := 0;
      end;
    VK_LEFT:
      begin
        NewIndex := FTabIndex - 1;
        if NewIndex < 0 then NewIndex := 0;
        TabIndex := NewIndex; Key := 0;
      end;
  end;
end;
```
  （`TabIndex :=` 经 `SetTabIndex` 夹紧/`ShowOnlyPage`/`ScrollTabIntoView`/`OnChange`;若 `FTabIndex=-1`(无选中),`+1`→0、`-1`→-1 夹到 0/由 setter 处理。确认 `VK_TAB`/`VK_NEXT`/`VK_PRIOR` 已在 `uses LCLType`——是。)
- [ ] **Step 4: 跑;新用例 PASS;现有 tab `←/→` 测试全绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyTabControl keyboard nav (Ctrl+Tab cycle, Ctrl+PgUp/Dn, Home/End)`

---

## Task 4: TTyScrollBar 轨道内缩 + SmallChange(几何地基)

**Files:** Modify `source/tyControls.ScrollBar.pas`;Test `tests/test.controls.scrollbar.pas`.

> 本任务把 thumb/拖拽/翻页的几何基准从整 client 改为"内缩后的轨道",并加 `SmallChange`。箭头按钮的渲染与命中在 Task 5。**注意:这会改变控件鼠标几何**——现有 `TTyScrollBarDragTest`/`TTyScrollBarMouseTest` 的点击坐标可能需按新轨道更新(预期变化,非弱化)。

- [ ] **Step 1: 失败测试**(纯函数):
```pascal
procedure TestScrollTrackInsetGeometry;
begin
  AssertEquals('vertical button size = width', 16, TyScrollButtonSize(Rect(0,0,16,160), sbVertical));
  AssertEquals('horizontal button size = height', 12, TyScrollButtonSize(Rect(0,0,200,12), sbHorizontal));
  // vertical: track insets top+bottom by button size
  AssertEquals('v track top', 16, TyScrollTrackRect(Rect(0,0,16,160), sbVertical, 16).Top);
  AssertEquals('v track bottom', 144, TyScrollTrackRect(Rect(0,0,16,160), sbVertical, 16).Bottom);
  // degenerate: too short -> whole client (no buttons)
  AssertEquals('degenerate keeps full', 0, TyScrollTrackRect(Rect(0,0,16,20), sbVertical, 16).Top);
  AssertEquals('degenerate keeps full2', 20, TyScrollTrackRect(Rect(0,0,16,20), sbVertical, 16).Bottom);
end;
```
Register it (in `TTyScrollGeometryTest`).

- [ ] **Step 2: 确认失败/不编译。**
- [ ] **Step 3: 实现**(`source/tyControls.ScrollBar.pas`):
  - interface 段导出:
    ```pascal
    function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
    function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind; AButtonSize: Integer): TRect;
    ```
    implementation:
    ```pascal
    function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
    begin
      if AKind = sbVertical then Result := AClient.Right - AClient.Left
      else Result := AClient.Bottom - AClient.Top;
      if Result < 1 then Result := 1;
    end;
    function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind; AButtonSize: Integer): TRect;
    var mainLen: Integer;
    begin
      Result := AClient;
      if AKind = sbVertical then mainLen := AClient.Bottom - AClient.Top
      else mainLen := AClient.Right - AClient.Left;
      if mainLen <= 2 * AButtonSize then Exit;   // too short for two buttons -> whole client, no buttons
      if AKind = sbVertical then
        Result := Rect(AClient.Left, AClient.Top + AButtonSize, AClient.Right, AClient.Bottom - AButtonSize)
      else
        Result := Rect(AClient.Left + AButtonSize, AClient.Top, AClient.Right - AButtonSize, AClient.Bottom);
    end;
    ```
  - private `FSmallChange: Integer;`(`Create` 加 `FSmallChange := 1;`)+ `SetSmallChange`(`if AValue<1 then FSmallChange:=1 else FSmallChange:=AValue;`)。published `property SmallChange: Integer read FSmallChange write SetSmallChange default 1;`
  - private helper `function TrackRect: TRect; begin Result := TyScrollTrackRect(ClientRect, FKind, TyScrollButtonSize(ClientRect, FKind)); end;`(声明 private)。
  - 把所有用 `ClientRect`/`TyScrollThumbRect(ClientRect, ...)`/`TrackLength`(基于 ClientRect)的地方改用 `TrackRect`:
    - `RenderTo`:`ThumbR := TyScrollThumbRect(R, ...)` → 先 `Track := TyScrollTrackRect(R, FKind, TyScrollButtonSize(R, FKind)); ThumbR := TyScrollThumbRect(Track, ...)`(R 是 (0,0)-local client)。
    - `BeginThumbDrag`/`DragThumbTo`:`TyScrollThumbRect(ClientRect, ...)` → `TyScrollThumbRect(TrackRect, ...)`。
    - `TrackLength`:返回 `TrackRect` 的主轴长度(不是 ClientRect):`if FKind=sbVertical then Result := TrackRect.Bottom - TrackRect.Top else Result := TrackRect.Right - TrackRect.Left;`
    - `MouseDown`:`ThumbR := TyScrollThumbRect(TrackRect, ...)`(thumb 命中);轨道翻页判断用 ThumbR(已在内缩轨道内)。`DragThumbTo` 里 `NewTop` 是相对 TrackRect 起点的偏移——注意 `PosAlong(X,Y)` 返回的是 client 坐标,而 thumb 在内缩轨道内,`BeginThumbDrag` 存的 `ThumbStart` 也是 client 坐标(TrackRect 在 client 坐标系),`DragThumbTo` 的 `NewTop := APosAlongTrack - FDragGrabOffset` 仍在 client 坐标,但 `FreeSpace := TrackLength - ThumbLen` 现在是轨道长——需把 `NewTop` 夹到 `[TrackStart, TrackStart+FreeSpace]` 而非 `[0, FreeSpace]`。**为简化**:`DragThumbTo` 改为以轨道起点为基:`TrackStart := (FKind=sbVertical ? TrackRect.Top : TrackRect.Left); NewTop := APosAlongTrack - FDragGrabOffset; if NewTop < TrackStart then NewTop := TrackStart; if NewTop > TrackStart + FreeSpace then NewTop := TrackStart + FreeSpace; NewPos := FMin + ((NewTop - TrackStart) * Travel) div FreeSpace;`(把现有 `DragThumbTo` 按此改;`BeginThumbDrag` 的 `FDragGrabOffset := AGrabPosAlongTrack - ThumbStart` 不变,ThumbStart 用内缩轨道的 thumb)。
  - **现有鼠标/拖拽测试**:`TTyScrollBarDragTest`/`TTyScrollBarMouseTest` 用 client 坐标点击。轨道现在内缩了 buttonSize(竖向默认 16px ⇒ 轨道 [16,144))。更新这些测试的点击 Y 坐标到新轨道内(例如"点 thumb 下方翻页"的 Y 要落在内缩轨道里),并把"拖到底"等断言按新 FreeSpace 调整。**这是加箭头按钮的预期几何变化,不是弱化**——保留断言的方向性(拖动→Position 变化、翻页→±PageSize),只更新坐标。逐一跑挂的用例并修正坐标。
- [ ] **Step 4: 跑;纯函数用例 PASS;更新后的现有鼠标/拖拽测试全绿;0 failures。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyScrollBar inset track for end buttons + SmallChange (geometry)`

---

## Task 5: TTyScrollBar 箭头按钮(渲染 + 命中)

**Files:** Modify `source/tyControls.ScrollBar.pas`;Test `tests/test.controls.scrollbar.pas`.

- [ ] **Step 1: 失败测试**(用 `TScrollAccess` 暴露 `DoMouseDown(Shift, X, Y)` 若无;点上箭头区减、下箭头区加):
```pascal
procedure TestArrowButtonsStepSmallChange;
var SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(FForm); SA.Parent := FForm;
  SA.Kind := sbVertical; SA.SetBounds(0,0,16,160);
  SA.Min := 0; SA.Max := 100; SA.PageSize := 10; SA.SmallChange := 5; SA.Position := 50;
  SA.DoMouseDown([], 8, 4);          // top arrow button (y in [0,16))
  AssertEquals('top arrow -SmallChange', 45, SA.Position);
  SA.DoMouseDown([], 8, 156);        // bottom arrow button (y in [144,160))
  AssertEquals('bottom arrow +SmallChange', 50, SA.Position);
end;
```
Register it (in `TTyScrollBarMouseTest`; it has `FForm`). Add `procedure DoMouseDown(Shift: TShiftState; X, Y: Integer); begin MouseDown(mbLeft, Shift, X, Y); end;` to `TScrollAccess` if absent.

- [ ] **Step 2: 确认失败**(目前点 y=4 落在 thumb 上方→翻页 −PageSize=40,非 45)。
- [ ] **Step 3: 实现:**
  - private helper `procedure ButtonRects(const AClient: TRect; out ALo, AHi: TRect);`(ALo=减少端 top/left,AHi=增加端 bottom/right):
    ```pascal
    procedure TTyScrollBar.ButtonRects(const AClient: TRect; out ALo, AHi: TRect);
    var bs, mainLen: Integer;
    begin
      bs := TyScrollButtonSize(AClient, FKind);
      if FKind = sbVertical then mainLen := AClient.Bottom - AClient.Top
      else mainLen := AClient.Right - AClient.Left;
      if mainLen <= 2 * bs then
      begin ALo := Rect(0,0,0,0); AHi := Rect(0,0,0,0); Exit; end;   // no buttons
      if FKind = sbVertical then
      begin
        ALo := Rect(AClient.Left, AClient.Top, AClient.Right, AClient.Top + bs);
        AHi := Rect(AClient.Left, AClient.Bottom - bs, AClient.Right, AClient.Bottom);
      end
      else
      begin
        ALo := Rect(AClient.Left, AClient.Top, AClient.Left + bs, AClient.Bottom);
        AHi := Rect(AClient.Right - bs, AClient.Top, AClient.Right, AClient.Bottom);
      end;
    end;
    ```
  - `MouseDown`(在 `if Button = mbLeft` 内,**最前面**,即 thumb/track 判断之前)加:
    ```pascal
    ButtonRects(ClientRect, LoR, HiR);
    if PtInRect(LoR, Point(X, Y)) then
    begin Position := Position - FSmallChange; try if CanFocus then SetFocus; except end; Exit; end;
    if PtInRect(HiR, Point(X, Y)) then
    begin Position := Position + FSmallChange; try if CanFocus then SetFocus; except end; Exit; end;
    ```
    (MouseDown var 区加 `LoR, HiR: TRect;`。)
  - `RenderTo`:画完 thumb 后,画两个箭头按钮字形:
    ```pascal
    ButtonRects(R, LoR, HiR);
    if (LoR.Right > LoR.Left) then   // buttons exist
    begin
      if FKind = sbVertical then
      begin
        P.DrawGlyph(LoR, tgArrowUp, S.TextColor, 2);
        P.DrawGlyph(HiR, tgArrowDown, S.TextColor, 2);
      end
      else
      begin
        P.DrawGlyph(LoR, tgArrowLeft, S.TextColor, 2);
        P.DrawGlyph(HiR, tgArrowRight, S.TextColor, 2);
      end;
    end;
    ```
    (RenderTo var 区加 `LoR, HiR: TRect;`。`tgArrow*` 来自 `tyControls.Painter`,已在 uses。)
- [ ] **Step 4: 跑;新用例 PASS;现有 scrollbar 测试全绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyScrollBar end arrow buttons (render + click step SmallChange)`

---

## Task 6: TTyScrollBar 键盘

**Files:** Modify `source/tyControls.ScrollBar.pas`;Test `tests/test.controls.scrollbar.pas`.

- [ ] **Step 1: 失败测试**(用 `TScrollAccess` 暴露 `DoKeyDown(Key, Shift)`):
```pascal
procedure TestScrollBarKeyboard;
var SA: TScrollAccess;
begin
  SA := TScrollAccess.Create(FForm); SA.Parent := FForm;
  SA.Kind := sbVertical; SA.Min := 0; SA.Max := 100; SA.PageSize := 10; SA.SmallChange := 1; SA.Position := 50;
  SA.DoKeyDown(VK_DOWN, []);  AssertEquals('down +small', 51, SA.Position);
  SA.DoKeyDown(VK_UP, []);    AssertEquals('up -small', 50, SA.Position);
  SA.DoKeyDown(VK_NEXT, []);  AssertEquals('pgdn +page', 60, SA.Position);
  SA.DoKeyDown(VK_PRIOR, []); AssertEquals('pgup -page', 50, SA.Position);
  SA.DoKeyDown(VK_HOME, []);  AssertEquals('home min', 0, SA.Position);
  SA.DoKeyDown(VK_END, []);   AssertEquals('end max', 100, SA.Position);
end;
```
Register it. Add `procedure DoKeyDown(Key: Word; Shift: TShiftState); begin KeyDown(Key, Shift); end;` to `TScrollAccess`.

- [ ] **Step 2: 确认失败/不编译**(无 KeyDown override)。
- [ ] **Step 3: 实现** —— 加 protected `procedure KeyDown(var Key: Word; Shift: TShiftState); override;`(`uses` 加 `LCLType`):
```pascal
procedure TTyScrollBar.KeyDown(var Key: Word; Shift: TShiftState);
var Dec1, Inc1: Word;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if FKind = sbVertical then begin Dec1 := VK_UP; Inc1 := VK_DOWN; end
  else begin Dec1 := VK_LEFT; Inc1 := VK_RIGHT; end;
  if Key = Dec1 then begin Position := Position - FSmallChange; Key := 0; end
  else if Key = Inc1 then begin Position := Position + FSmallChange; Key := 0; end
  else case Key of
    VK_PRIOR: begin Position := Position - FPageSize; Key := 0; end;
    VK_NEXT:  begin Position := Position + FPageSize; Key := 0; end;
    VK_HOME:  begin Position := FMin; Key := 0; end;
    VK_END:   begin Position := FMax; Key := 0; end;
  end;
end;
```
- [ ] **Step 4: 跑;新用例 PASS;现有全绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyScrollBar keyboard (arrows/PageUp-Dn/Home/End)`

---

## Task 7: TTyTrackBar Orientation(双向几何纯函数 + 重构)

**Files:** Modify `source/tyControls.TrackBar.pas`;Test `tests/test.trackbar.pas`.

> 把横向几何推广为按主轴的纯函数,横向走非镜像分支**逐像素回归**;竖向走镜像分支(top=Max)。

- [ ] **Step 1: 失败测试**(纯函数 + 竖向 ThumbRect):
```pascal
procedure TestTrackThumbOffsetPureFns;
var off, pos: Integer;
begin
  // horizontal (invert=False): pos0 -> offset 0; posMax -> offset travel
  AssertEquals('h pos=min off=0', 0, TyTrackThumbOffset(160, 12, 0, 100, 0, False));
  AssertEquals('h pos=max off=travel', 148, TyTrackThumbOffset(160, 12, 0, 100, 100, False));
  AssertEquals('h pos=50 mid', 74, TyTrackThumbOffset(160, 12, 0, 100, 50, False));
  // vertical (invert=True): pos=max -> offset 0 (top), pos=min -> offset travel (bottom)
  AssertEquals('v pos=max off=0(top)', 0, TyTrackThumbOffset(160, 12, 0, 100, 100, True));
  AssertEquals('v pos=min off=travel(bottom)', 148, TyTrackThumbOffset(160, 12, 0, 100, 0, True));
  // round-trip
  off := TyTrackThumbOffset(160, 12, 0, 100, 37, False);
  pos := TyTrackPosFromOffset(160, 12, 0, 100, off, False);
  AssertTrue('h round-trip ~37', Abs(pos - 37) <= 1);
  off := TyTrackThumbOffset(160, 12, 0, 100, 37, True);
  pos := TyTrackPosFromOffset(160, 12, 0, 100, off, True);
  AssertTrue('v round-trip ~37', Abs(pos - 37) <= 1);
end;

procedure TestVerticalThumbRectTopIsMax;
var T: TTyTrackBarProbe; r: TRect;
begin
  T := TTyTrackBarProbe.Create(nil);
  try
    T.Orientation := toVertical; T.SetBounds(0,0,24,160); T.Font.PixelsPerInch := 96;
    T.Min := 0; T.Max := 100; T.Position := 100;     // max -> thumb at TOP
    r := T.ThumbRect;
    AssertTrue('vertical max thumb near top', r.Top <= 2);
    T.Position := 0;                                  // min -> thumb at BOTTOM
    r := T.ThumbRect;
    AssertTrue('vertical min thumb near bottom', r.Bottom >= 158);
  finally T.Free; end;
end;
```
Register both. (`TTyTrackBarProbe.ThumbRect` — `ThumbRect` is already public on TTyTrackBar.)

- [ ] **Step 2: 确认失败/不编译**(`TyTrackThumbOffset`/`Orientation`/`toVertical` 未声明)。
- [ ] **Step 3: 实现**(`source/tyControls.TrackBar.pas`):
  - interface:`type TTyTrackOrientation = (toHorizontal, toVertical);` 并导出:
    ```pascal
    function TyTrackThumbOffset(AMainLen, AThumbLen, AMin, AMax, APos: Integer; AInvert: Boolean): Integer;
    function TyTrackPosFromOffset(AMainLen, AThumbLen, AMin, AMax, AOffset: Integer; AInvert: Boolean): Integer;
    ```
    impl:
    ```pascal
    function TyTrackThumbOffset(AMainLen, AThumbLen, AMin, AMax, APos: Integer; AInvert: Boolean): Integer;
    var travel, span, eff: Integer;
    begin
      travel := AMainLen - AThumbLen;
      span := AMax - AMin;
      if (travel <= 0) or (span <= 0) then Exit(0);
      if APos < AMin then APos := AMin;
      if APos > AMax then APos := AMax;
      if AInvert then eff := AMax - APos else eff := APos - AMin;   // distance from the "0-offset" end
      Result := (travel * eff + span div 2) div span;
    end;
    function TyTrackPosFromOffset(AMainLen, AThumbLen, AMin, AMax, AOffset: Integer; AInvert: Boolean): Integer;
    var travel, span, eff: Integer;
    begin
      travel := AMainLen - AThumbLen;
      span := AMax - AMin;
      if (travel <= 0) or (span <= 0) then Exit(AMin);
      if AOffset < 0 then AOffset := 0;
      if AOffset > travel then AOffset := travel;
      eff := (AOffset * span + travel div 2) div travel;
      if AInvert then Result := AMax - eff else Result := AMin + eff;
    end;
    ```
  - private `FOrientation: TTyTrackOrientation;`(`Create` 加 `FOrientation := toHorizontal;`)+ `SetOrientation`(`if FOrientation=AValue then Exit; FOrientation:=AValue; Invalidate;`)。published `property Orientation: TTyTrackOrientation read FOrientation write SetOrientation default toHorizontal;`
  - 私有 helper `function MainLen: Integer;`(横向=ClientWidth,竖向=ClientHeight)、`function Inverted: Boolean;`(= FOrientation=toVertical)。
  - `ThumbRect`:改为按主轴:`TW := ThumbWAtPPI(PPI); off := TyTrackThumbOffset(MainLen, TW, FMin, FMax, FPosition, Inverted);` 竖向 `Result := Rect(0, off, ClientWidth, off+TW)`;横向 `Result := Rect(off, 0, off+TW, ClientHeight)`。
  - `DragTo(APos)`:`APos` 是沿主轴的坐标(横向 X、竖向 Y)。`off := APos - TW div 2; Position := TyTrackPosFromOffset(MainLen, TW, FMin, FMax, off, Inverted);`(clamp 在纯函数内)。`MouseDown`/`MouseMove` 调 `DragTo(IfThenAxis(X,Y))`——横向传 X、竖向传 Y。
  - `RenderTo` thumb 计算改用同一 `TyTrackThumbOffset`(竖向 ThumbR 沿 Y)。横向分支与旧公式等价(`TyTrackThumbOffset(..,False)` = 旧 `(Tr*(pos-min)+(max-min)div2)div(max-min)`)→ 横向像素回归。
  - **现有横向测试**(TestThumbRectPos0Left/100Right/50/DragTo*/VKLeft 等)必须全绿(横向路径等价)。MouseDown/Move 现在按 Orientation 传 X 或 Y——横向仍传 X,行为不变。
- [ ] **Step 4: 跑;两个新用例 PASS;现有横向 trackbar 测试全绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyTrackBar Orientation (vertical geometry via pure offset fns; horizontal regression)`

---

## Task 8: TTyTrackBar Frequency 刻度

**Files:** Modify `source/tyControls.TrackBar.pas`;Test `tests/test.trackbar.pas`.

- [ ] **Step 1: 失败测试**(Frequency>0 时轨道一侧有刻度墨迹;=0 无):
```pascal
procedure TestFrequencyDrawsTicks;
  function HasTickInk(F: Integer): Boolean;
  var T: TTyTrackBarProbe; bmp: TBitmap; reread: TBGRABitmap; x,y: Integer; px: TBGRAPixel;
  begin
    Result := False;
    T := TTyTrackBarProbe.Create(nil); bmp := TBitmap.Create;
    try
      T.Orientation := toHorizontal; T.Min := 0; T.Max := 100; T.Frequency := F;
      T.Font.PixelsPerInch := 96; T.SetBounds(0,0,160,40);
      bmp.PixelFormat := pf32bit; bmp.SetSize(160,40);
      bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0,0,160,40);
      T.RenderTo(bmp.Canvas, Rect(0,0,160,40), 96);
      reread := TBGRABitmap.Create(bmp);
      try
        for x := 0 to 159 do for y := 30 to 39 do   // tick zone: bottom strip
        begin px := reread.GetPixel(x,y);
          if (px.red<200) or (px.green<200) or (px.blue<200) then Result := True; end;
      finally reread.Free; end;
    finally bmp.Free; T.Free; end;
  end;
begin
  AssertFalse('no ticks when Frequency=0', HasTickInk(0));
  AssertTrue('ticks present when Frequency=20', HasTickInk(20));
end;
```
> 注:刻度画在轨道**下方**条带(横向)。确保 Control 高度足够(40px)且刻度落在 y∈[30,40)。实现里刻度短线从轨道下缘画到控件下缘附近。若你的 thumb/track 占满高度导致无下方空间,把刻度画在 thumb 轨道交叉轴的某一侧固定带——并相应调整测试探针 y 区。Register it.

- [ ] **Step 2: 确认失败。**
- [ ] **Step 3: 实现** —— private `FFrequency: Integer;`(`Create` 加 `FFrequency := 0;`)+ `SetFrequency`(`if AValue<0 then FFrequency:=0 else FFrequency:=AValue; Invalidate;`)。published `property Frequency: Integer read FFrequency write SetFrequency default 0;`
  - `RenderTo`:画完 thumb 后,若 `FFrequency > 0` 且 `FMax > FMin`:对 `v := FMin to FMax step FFrequency`(含 FMax 端可选)算主轴位置 `off := TyTrackThumbOffset(MainLen, TW, FMin, FMax, v, Inverted)`,刻度线中心 `c := off + TW div 2`;横向画竖直短线 `x=c`,从 `y = R.Bottom - tickLen` 到 `R.Bottom`(`tickLen := P.Scale(4)`),颜色 `S.TextColor`;竖向画水平短线 `y=c`,从 `x=R.Right - tickLen` 到 `R.Right`。用 `P.StrokeBorder` 不便画线——改用 `FillBackground` 画 1px 矩形或加一个 painter 画线方法。**最简**:用 `P.FillBackground(Rect(c, R.Bottom - tickLen, c+P.Scale(1), R.Bottom), tickFill, 0)`(`tickFill.Kind:=tfkSolid; tickFill.Color:=S.TextColor`)。竖向同理。
  - 为给刻度留空间:刻度画在控件交叉轴下/右侧固定 `Scale(4)` 带,不影响 thumb(thumb 仍沿主轴铺满交叉轴)——若与 thumb 重叠也无妨(刻度在 thumb 之外的轨道区可见)。测试取 y∈[30,40) 即控件下缘带。
- [ ] **Step 4: 跑;新用例 PASS(Frequency=0 无刻度、=20 有);现有全绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyTrackBar Frequency tick marks`

---

## Task 9: TTyTrackBar LineSize/PageSize + 键盘

**Files:** Modify `source/tyControls.TrackBar.pas`;Test `tests/test.trackbar.pas`.

- [ ] **Step 1: 失败测试**(用 `TTyTrackBarProbe.SimulateKeyDown(var Key)`):
```pascal
procedure TestTrackBarKeyboardSteps;
var T: TTyTrackBarProbe; K: Word;
begin
  T := TTyTrackBarProbe.Create(nil);
  try
    T.Orientation := toHorizontal; T.Min := 0; T.Max := 100; T.LineSize := 2; T.PageSize := 20; T.Position := 50;
    K := VK_RIGHT; T.SimulateKeyDown(K); AssertEquals('right +LineSize', 52, T.Position);
    K := VK_LEFT;  T.SimulateKeyDown(K); AssertEquals('left -LineSize', 50, T.Position);
    K := VK_NEXT;  T.SimulateKeyDown(K); AssertEquals('pgdn -PageSize', 30, T.Position);
    K := VK_PRIOR; T.SimulateKeyDown(K); AssertEquals('pgup +PageSize', 50, T.Position);
    K := VK_HOME;  T.SimulateKeyDown(K); AssertEquals('home min', 0, T.Position);
    K := VK_END;   T.SimulateKeyDown(K); AssertEquals('end max', 100, T.Position);
  finally T.Free; end;
end;

procedure TestTrackBarVerticalUpIncreases;
var T: TTyTrackBarProbe; K: Word;
begin
  T := TTyTrackBarProbe.Create(nil);
  try
    T.Orientation := toVertical; T.Min := 0; T.Max := 100; T.LineSize := 3; T.Position := 50;
    K := VK_UP;   T.SimulateKeyDown(K); AssertEquals('up +LineSize (top=max)', 53, T.Position);
    K := VK_DOWN; T.SimulateKeyDown(K); AssertEquals('down -LineSize', 50, T.Position);
  finally T.Free; end;
end;
```
Register both. (`VK_NEXT`/`VK_PRIOR`/`VK_HOME`/`VK_END`/`VK_UP`/`VK_DOWN` from LCLType.)

- [ ] **Step 2: 确认失败**(LineSize/PageSize 未声明;且 Up/Down/Page/Home/End 未处理)。
- [ ] **Step 3: 实现:**
  - private `FLineSize, FPageSize: Integer;`(`Create` 加 `FLineSize := 1; FPageSize := 10;`)+ setters(`<1` 夹 1)。published `property LineSize: Integer read FLineSize write SetLineSize default 1;`、`property PageSize: Integer read FPageSize write SetPageSize default 10;`
  - 重写 `KeyDown`(替换现有只有 VK_LEFT/RIGHT 的版本):
    ```pascal
    procedure TTyTrackBar.KeyDown(var Key: Word; Shift: TShiftState);
    var DecKey, IncKey: Word;
    begin
      if not Enabled then Exit;
      inherited KeyDown(Key, Shift);
      if FOrientation = toVertical then begin DecKey := VK_DOWN; IncKey := VK_UP; end   // up increases (top=max)
      else begin DecKey := VK_LEFT; IncKey := VK_RIGHT; end;
      if Key = IncKey then begin Position := FPosition + FLineSize; Key := 0; end
      else if Key = DecKey then begin Position := FPosition - FLineSize; Key := 0; end
      else case Key of
        VK_PRIOR: begin Position := FPosition + FPageSize; Key := 0; end;   // PageUp increases
        VK_NEXT:  begin Position := FPosition - FPageSize; Key := 0; end;
        VK_HOME:  begin Position := FMin; Key := 0; end;
        VK_END:   begin Position := FMax; Key := 0; end;
      end;
    end;
    ```
- [ ] **Step 4: 跑;两个新用例 PASS;现有 trackbar 键盘测试(`TestVKLeftDecrement` 等)——注意默认 LineSize=1 时 `←`/`→` 仍 ±1,旧测试应保持绿;若旧测试断言 `←`=−1 而现在 −LineSize(默认 1)= −1,一致。全绿。**
- [ ] **Step 5: Commit** `feat(tycontrols): TTyTrackBar LineSize/PageSize + full keyboard (arrows/PageUp-Dn/Home/End, vertical-aware)`

---

## Task 10: 文档 + 收口

**Files:** `docs/controls/panel.md`、`groupbox.md`、`tabcontrol.md`、`scrollbar.md`、`trackbar.md`;全量回归 + 矩阵。

- [ ] **Step 1: 文档** —— 各控件 md 补:Panel/GroupBox `Alignment`;TabControl 键盘(Ctrl+Tab 循环、Ctrl+PgUp/Dn、Home/End);ScrollBar 端部箭头按钮 + `SmallChange` + 键盘(↑↓/PgUp-Dn/Home/End);TrackBar `Orientation`(竖向 top=Max 向上加值)+ `Frequency` 刻度 + `LineSize`/`PageSize` + 键盘。
- [ ] **Step 2: 全量回归 + 矩阵**
  ```bash
  lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain
  bash scripts/build-matrix.sh
  ```
  Expected:0 failures(+15 env errors only);`== matrix OK ==`。
- [ ] **Step 3: Commit** `docs(tycontrols): document Panel/GroupBox Alignment, TabControl keyboard, ScrollBar arrows/keyboard, TrackBar orientation/ticks/keyboard`

---

## 完成后
全套件 + 矩阵 + heaptrc 0 + 终审(reviewer 核横向 TrackBar/现有 ScrollBar 几何回归、竖向镜像、箭头命中、各键盘);本地快进合并 main + 删分支;更新记忆(批③ 完成,批④ 起)。

## Self-Review(规划者自查,已执行)
- **Spec 覆盖**:Panel Alignment→T1;GroupBox Alignment→T2;TabControl 键盘→T3;ScrollBar 轨道内缩+SmallChange→T4、箭头→T5、键盘→T6;TrackBar Orientation→T7、Frequency→T8、LineSize/PageSize+键盘→T9;文档→T10。
- **类型/签名一致**:`Alignment`(T1/T2);`TyScrollButtonSize`/`TyScrollTrackRect`/`SmallChange`/`TrackRect`/`ButtonRects`(T4/T5/T6);`TTyTrackOrientation`/`TyTrackThumbOffset`/`TyTrackPosFromOffset`/`Orientation`/`MainLen`/`Inverted`/`Frequency`/`LineSize`/`PageSize`(T7/T8/T9)前后一致。
- **向后兼容**:Panel 唯一默认变化(taCenter);GroupBox/TabControl/ScrollBar/TrackBar 默认=现状(Orientation=horizontal 走纯函数非镜像分支逐像素回归;Frequency=0 无刻度;SmallChange=1)。**ScrollBar 轨道内缩是预期几何变化**——T4 显式要求更新现有鼠标/拖拽测试坐标(保方向性、不弱化)。
- **无占位符**:纯函数/键盘/对齐给完整代码;refactor 给精确替换;ScrollBar/TrackBar 几何重构的现有测试影响已显式标注处理方式。
