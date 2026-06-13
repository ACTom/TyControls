# TyControls v1.5.1 — 修复用户实测的 4 个缺陷(v1.6 前置)

> 执行:superpowers:subagent-driven-development,**串行**派发 implementer(v1.5 并行撞车教训)。约束:几何/像素测试钉 PPI=96;`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests`;现有 317 测试保持全绿、不改既有测试;`examples/demo/mainform.lfm`+`demo.lpi` 有用户未提交改动——除非任务明确要改 mainform.pas,否则勿碰;子代理派发以 "DIRECT task. Do NOT invoke any brainstorming/planning skill." 开头。

## 诊断(根因已定位)

**Bug 1 — Edit 光标/文本位置偏移,越长越偏。** `MeasureCodepointWidths` 用 LCL `TBitmap.Canvas`、`Font.Height := -FontHeight`(**负**=字符高,不含行距)测宽;但 `TTyPainter.DrawText` 用 **BGRABitmap** `FontHeight := Scale(Round(size*96/72))`(**正**=含行距的单元高)绘制。两种引擎 + 正负高语义不同 ⇒ 每字宽有恒定比例差,累积 ⇒ 光标右漂、文本看着被压缩/截断。**修:用与 painter 完全一致的 BGRA 引擎 + 同一字体设置来测宽。**

**Bug 2 — ScrollBar 拖不动。** `TTyScrollBar` **根本没有 MouseDown/MouseMove/MouseUp 重写**——只有公开的 `BeginThumbDrag/DragThumbTo/EndThumbDrag`,没有任何代码把鼠标事件接到它们上。所以鼠标完全无法拖动滑块(测试/示例都是直接调公开方法,从未测鼠标)。内嵌在 ListBox 里的滚动条同理不动。**修:加鼠标重写(点滑块→拖动;点轨道空白→翻页)+ MouseCapture + Enabled 守卫。** ListBox 已有 `TopIndex↔FScrollBar.Position` 双向同步(带 FSyncingScroll 防重入),滚动条能拖后内嵌场景自动好。

**Bug 3 — FormChrome.Active=True 窗口跑到屏幕外(多显示器,负 Top)。** `InstallChrome` 设 `BorderStyle:=bsNone` ⇒ 句柄重建、widgetset 重新摆放窗口;在带负坐标的多屏虚拟桌面上落到屏幕外。**修:改 BorderStyle 前存 `BoundsRect`,`HandleNeeded` 后恢复,保持窗口原位。**

**Bug 4 — 切主题时窗口(表单)背景不变。** 表单是普通 `TForm`,不是受样式控制的 TyControl,主题碰不到它。**修:给三套主题加 `TyForm` 窗口背景令牌 + 一个 `TyColorToLCL(TTyColor):TColor` 辅助函数;demo 在 ApplyTheme 里据此设 `Self.Color`(及 chrome 窗体)。** 给买家一个文档化的"窗体跟随主题"配方。

---

## Task 1: Edit 文本测量与 painter 绘制一致(Bug 1)

**Files:** Modify `source/tyControls.Painter.pas`, `source/tyControls.Edit.pas`; test `tests/test.edit.pas`.

- [ ] **Step 1 失败测试**(test.edit.pas,用已暴露的 `CaretPixelXAt` + 渲染探针):
  渲染一段较长文本(如 `'abcdefghijklmnopqrstuvwxyz0123456789'`)到位图 @96,断言:文本最后一个字形的右边缘像素位置 ≈ `CaretPixelXAt(Len, 96)`(末位光标 x)。当前两者发散(测量>绘制)。具体做法:渲染后从右往左扫描找最右非背景(文本色)像素列 `RightmostInk`;断言 `Abs(RightmostInk - (CaretPixelXAt(Len,96) ... ))` 在小容差内(几 px)。或更稳:断言"在 caret x 左侧若干 px 内存在文本墨迹,且 caret x 右侧无文本墨迹"——即光标紧贴文本末尾。设计成当前失败(光标远在墨迹右侧)、修后通过。参考 test.edit.pas 既有渲染/reread 模式。
- [ ] **Step 2 确认失败。**
- [ ] **Step 3 实现:**
  (a) `Painter.pas`:抽出共享字体设置,导出:
  ```pascal
  procedure TyConfigureTextFont(ABmp: TBGRABitmap; const AFontName: string;
    AFontSizeLogical, AWeight, APPI: Integer);
  begin
    ABmp.FontName := AFontName;
    ABmp.FontHeight := MulDiv(Round(AFontSizeLogical * 96 / 72), APPI, 96);
    ABmp.FontQuality := fqFineAntialiasing;
    if AWeight >= 600 then ABmp.FontStyle := [fsBold] else ABmp.FontStyle := [];
  end;
  ```
  在 interface 声明并导出。重构 `TTyPainter.DrawText`:把内部 `FBmp.FontName/fh/FontQuality/FontStyle` 设置替换为 `TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);`(FPPI 是 painter 在 BeginPaint 存的当前 PPI 字段——确认其名,若不同则用之)。绘制其余不变。
  (b) `Edit.pas`:`uses` 增加 `BGRABitmap, BGRABitmapTypes`;`FMeasureBmp` 类型由 `TBitmap` 改 `TBGRABitmap`。`MeasureCodepointWidths` 重写测量段:lazy 建 `TBGRABitmap.Create(1,1)`;`TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI)`;累积宽用**前缀**测量保证与整串绘制一致:`FWidthCache[i] := FMeasureBmp.TextSize(UTF8Copy(FText,1,i)).cx`(i=1..Len;FWidthCache[0]=0)。(前缀测量 O(n²) 但 edit 文本短且有缓存,正确性优先——光标位置=绘制前缀末端。)删掉旧的 `Font.Height:=-FontHeight` / 逐字节指针那套。`FMeasureBmp.Free` 在 Destroy 仍可(TBGRABitmap 有 Free)。
- [ ] **Step 4 跑 test.edit;Step 5 全量回归 + heaptrc(FMeasureBmp 改 BGRA 无泄漏);Step 6 commit** `fix(tycontrols): measure Edit text with painter-consistent BGRA font (caret alignment)`。

---

## Task 2: ScrollBar 鼠标拖动(Bug 2)

**Files:** Modify `source/tyControls.ScrollBar.pas`; tests `tests/test.controls.scrollbar.pas` + `tests/test.listbox.pas`.

- [ ] **Step 1 失败测试**(scrollbar:用 access 子类暴露 MouseDown/MouseMove/MouseUp):
  - 垂直滚动条,SetBounds(0,0,16,160),Min0 Max100 PageSize10,Position0。模拟在滑块上 MouseDown,再 MouseMove 到轨道中部,断言 Position 增大(约中间);MouseUp 结束。当前失败(无鼠标处理 ⇒ Position 不变)。
  - 轨道空白点击翻页:Position0,在滑块**下方**轨道 MouseDown,断言 Position 增加约 PageSize。
  - 禁用守卫:Enabled:=False 时 MouseDown 在滑块,Position 不变。
  - listbox(test.listbox.pas):内嵌滚动条可见时,通过 listbox 的滚动条(或直接驱动 scrollbar 的鼠标后)断言 ListBox.TopIndex 随之变化——验证内嵌联动。(可用 access 暴露 FScrollBar 或观察渲染。)
- [ ] **Step 2 确认失败。**
- [ ] **Step 3 实现** —— 给 `TTyScrollBar` 加 protected 重写:
  ```pascal
  procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  ```
  - `PosAlong(X,Y) := Y if vertical else X`。
  - MouseDown(mbLeft): `if not Enabled then Exit; inherited;` 计算 `ThumbR := TyScrollThumbRect(ClientRect,...)`;若点在 thumb 内 → `BeginThumbDrag(PosAlong)` 并 `MouseCapture := True`;否则(点轨道) → 翻页:点在 thumb 之前 `Position := Position - PageSize` 否则 `+ PageSize`。尝试 `if CanFocus then SetFocus`(try/except 包住,headless 安全)。
  - MouseMove: `if not Enabled then Exit; inherited; if FDragging then DragThumbTo(PosAlong);`
  - MouseUp(mbLeft): `inherited; EndThumbDrag; MouseCapture := False;`
  - 注意:`FDragging` 已存在私有字段;`MouseCapture` 是 TControl 属性。命中判断用 `PtInRect(ThumbR, Point(X,Y))` 或按 PosAlong 落在 [ThumbStart, ThumbEnd)。
- [ ] **Step 4/5/6**:跑 scrollbar+listbox 测试、全量回归、commit `fix(tycontrols): TTyScrollBar mouse drag + track-paging (embedded ListBox scrollbar now works)`。

---

## Task 3: FormChrome 保持窗口位置(Bug 3)

**Files:** Modify `source/tyControls.Form.pas`; test `tests/test.form.pas`.

- [ ] **Step 1 失败/不变量测试**:CreateNew 表单,`SetBounds(120, 80, 400, 300)`,记 `B := BoundsRect`,`Chrome.Active := True`,断言 `BoundsRect` ≈ B(位置未跳)。注:headless 下 BorderStyle 变更未必移动窗口,该测试可能本就通过——仍作为"安装不改变 bounds"的不变量保留;真正的多屏负坐标无法无头复现,在测试注释里说明。
- [ ] **Step 2/3 实现**:`InstallChrome` 中,在 `FForm.BorderStyle := bsNone` **之前**存 `LocalSaved := FForm.BoundsRect;`,在 `FForm.HandleNeeded;`(及 cocoa shadow 之后)**恢复** `FForm.BoundsRect := LocalSaved;`。用局部变量,勿复用 `FSavedBounds`(那是最大化还原用)。
- [ ] **Step 4/5/6**:跑 test.form、全量回归、commit `fix(tycontrols): TTyFormChrome preserves window bounds across BorderStyle change (multi-monitor off-screen)`。

---

## Task 4: 表单背景跟随主题(Bug 4)

**Files:** Modify `source/tyControls.Types.pas`(helper)、`themes/light.tycss`/`dark.tycss`/`showcase.tycss`、`examples/demo/mainform.pas`、`examples/demo/chromeform.pas`;tests `tests/test.Types.pas` + `tests/test.themes.pas`。

- [ ] **Step 1 失败测试**:
  - test.Types.pas:`TyColorToLCL($FF112233)` 应得 `RGBToColor($11,$22,$33)`(丢 alpha)。
  - test.themes.pas:三套主题 `ResolveStyle('TyForm','',[])` 必须有 `tpBackground`(每套都定义 TyForm)。
- [ ] **Step 2 确认失败。**
- [ ] **Step 3 实现:**
  (a) `Types.pas`:加 `function TyColorToLCL(c: TTyColor): TColor;`(`uses Graphics` 取 TColor/RGBToColor;impl:`Result := RGBToColor(TyRedOf(c), TyGreenOf(c), TyBlueOf(c));`)。在 interface 声明。
  (b) 三套主题各加 `TyForm { background: <窗口底色>; }`:light 用 `darken(--surface, 4%)` 或 `--surface`(选与控件协调的浅底,如 `#F3F4F6`);dark 用 `var(--surface)`(#1E1E1E);showcase 用其门面底色。保证 `tpBackground` present。
  (c) demo `mainform.pas` 的 `ApplyTheme`:LoadTheme + Changed 后,解析 `bg := Controller.Model.ResolveStyle('TyForm','',[])`,若 `tpBackground in bg.Present` 且 `bg.Background.Kind=tfkSolid` 则 `Self.Color := TyColorToLCL(bg.Background.Color)`。(`uses` 补 Graphics/tyControls.Types/StyleModel 如缺。)
  (d) demo `chromeform.pas`:同样在其 LoadTheme 处设 `Self.Color := TyColorToLCL(...)`(若该窗体有独立 controller/LoadTheme)。
  > 勿碰 mainform.**lfm**/demo.lpi(用户改动);只改 mainform.**pas**。
- [ ] **Step 4/5/6**:跑 test.Types/test.themes、`lazbuild examples/demo/demo.lpi` 通过、全量回归、commit `feat(tycontrols): TyForm theme token + TyColorToLCL helper; demo form background follows theme`。注意只 stage 改动文件,**不** stage mainform.lfm/demo.lpi。

---

## 完成后
全套件 + 构建矩阵 + heaptrc 0 + 终审(reviewer 跑探针,尤其 Edit 光标对齐 / 滚动条拖动像素验证);本地快进合并 main + 删分支;更新记忆;然后开始 v1.6。
