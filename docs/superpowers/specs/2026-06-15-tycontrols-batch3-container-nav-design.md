# TyControls 控件完善程序 · 批③ 容器/导航 设计文档 — Panel/GroupBox 标题对齐 + TabControl 键盘 + ScrollBar 箭头按钮/键盘 + TrackBar 竖向/刻度/键盘

- **日期:** 2026-06-15
- **前置:** `main`(Phase 0 + 批①② + 闪屏/字号修复 已合入,674 测试)。
- **定位:** "完善现有控件"程序的**批③**(容器/导航)。一次性补 4 个控件;实现计划按"Panel/GroupBox → TabControl → ScrollBar → TrackBar"(由小到大)推进。
- **执行约定:** 沿用项目惯例 —— 几何/像素测试钉 `PPI=96`;`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests.exe -a --format=plain`;现有测试保持全绿、不改既有测试语义;无头键盘/鼠标经 `KeyDown`/`MouseDown` 注入。基线:0 failures + 15 个无头 win32(error 1407)环境错误(非回归)。`examples/demo/*` 是用户测试台,可改可提交但**只 stage 本任务的文件**;demo 控件用 `.lfm` 摆放(不用代码生成)。

---

## 1. 动机

四个容器/导航控件缺常用能力:`TTyPanel`/`TTyGroupBox` 标题位置固定(无 `Alignment`);`TTyTabControl` 只有 `←/→` 切页(无 `Ctrl+Tab`/`Ctrl+PageUp-Dn`/`Home/End`);`TTyScrollBar` 无端部箭头按钮、无键盘、无 `SmallChange`(只有 `PageSize`);`TTyTrackBar` 仅横向、步进 ±1、无刻度/无 `Orientation`/`Frequency`/`LineSize`/`PageSize`/无 `PageUp-Dn-Home-End`。本批补齐,全部纯叠加、向后兼容。

## 2. 核心原则

新增属性默认值=旧行为(Panel 唯一例外:`Alignment` 默认 `taCenter` 对齐 LCL,会动到**有标题**的 Panel)。视觉跟随主题。几何抽成可单测的纯函数。

## 3. 范围

### 3.1 TTyPanel / TTyGroupBox — 标题对齐(`source/tyControls.Panel.pas`、`tyControls.GroupBox.pas`)

- **`TTyPanel.Alignment: TAlignment`**(published,默认 **`taCenter`**)。`RenderTo` 绘制 `FCaption` 时用 `Alignment` 取代当前写死的 `taLeftJustify`。`taCenter` 对齐 LCL `TPanel`。无标题(`FCaption=''`)时无可见变化。
- **`TTyGroupBox.Alignment: TAlignment`**(published,默认 **`taLeftJustify`**,沿用现状)。`RenderTo` 在顶部标题带内用 `Alignment` 定位 `FCaption` 的水平位置(left/center/right within the caption band)。`taLeftJustify` 即现状,默认零变化。
  - 注:GroupBox 的标题带几何(高度、擦除带)不变;仅水平定位受 `Alignment` 影响。`taCenter`/`taRightJustify` 时擦除带需覆盖标题在新位置的范围(测量宽度逻辑已有,见批② 字号修复;按 Alignment 定起点)。

### 3.2 TTyTabControl 键盘导航(`source/tyControls.TabControl.pas`)

在现有 `KeyDown`(已处理 `←/→` 切页)中新增(都消费按键 `Key:=0`;`TabCount=0` 时空操作):
- `Ctrl+Tab`:下一页,**循环**(末页→首页)。`Ctrl+Shift+Tab`:上一页,循环(首页→末页)。
- `Ctrl+PageDown`:下一页,**夹紧**(末页止)。`Ctrl+PageUp`:上一页,夹紧(首页止)。
- `Home`:首页(TabIndex:=0)。`End`:末页(TabIndex:=TabCount-1)。
- 保留 `←/→`(夹紧)。切页经现有 `SetTabIndex`/`TabIndex:=`(触发 `OnChange`、`ScrollTabIntoView`)。
- **不做:** `TabPosition`(底/左/右,大渲染改);标签集合的 Tab 焦点进入页内容(`Ctrl+Tab` 只切标签)。

### 3.3 TTyScrollBar 端部箭头按钮 + SmallChange + 键盘(`source/tyControls.ScrollBar.pas`)

- **`SmallChange: Integer`**(published,默认 1):行步进(箭头按钮与方向键),区别于 `PageSize`(翻页)。`<1` 夹到 1。
- **几何**:新增纯函数 `TyScrollButtonSize(const AClient: TRect; AKind): Integer`(=横向尺寸:竖向取宽、横向取高;下限 1),与 `TyScrollTrackRect(const AClient: TRect; AKind; AButtonSize): TRect`(client 在主轴两端各内缩 `AButtonSize`;若内缩后轨道 ≤0 则退化为整 client、无按钮)。`TyScrollThumbRect` 接收**轨道矩形**(已是参数,无需改签名),传入 `TyScrollTrackRect(...)` 而非整 client。
- **箭头按钮**:两端各一方形按钮(竖向 top/bottom、横向 left/right)。渲染:在按钮矩形内画字形(竖向 `tgArrowUp`/`tgArrowDown`,横向 `tgArrowLeft`/`tgArrowRight`),颜色用 `S.TextColor`,背景沿用滚动条本体(本批**不做**箭头按钮独立的 hover/pressed 高亮——留后续)。
- **鼠标**:`MouseDown` 先命中两个按钮矩形——命中"减少端"(top/left)→ `Position := Position - SmallChange`;命中"增加端"(bottom/right)→ `+ SmallChange`。否则在**轨道矩形**内做原有 thumb 命中/拖拽/翻页(命中/位置计算全部改用 `TyScrollTrackRect` 而非整 client,使 thumb 不再压到按钮区)。`BeginThumbDrag`/`DragThumbTo`/`TrackLength` 也以轨道矩形为基准。
- **键盘**(`KeyDown`;点击已 `SetFocus`):竖向 `↑↓`(横向 `←→`)±SmallChange;`PageUp/PageDown` ±PageSize;`Home`→Min、`End`→Max;消费按键。`TabStop` 维持现状(默认 False,内嵌场景由父控件处理键盘;独立场景点击聚焦后可用方向键)。
- **不做:** 按住箭头的自动连发(auto-repeat,需 TTimer)——单击一步,留后续。

### 3.4 TTyTrackBar Orientation + Frequency 刻度 + LineSize/PageSize + 键盘(`source/tyControls.TrackBar.pas`)

- **`Orientation: TTyTrackOrientation = (toHorizontal, toVertical)`**(published,默认 **`toHorizontal`**,现状不变)。
  - 把现有横向几何(`ThumbWAtPPI`/`TravelAtPPI`/`ThumbRect`/`DragTo`/`RenderTo` 的 thumb 计算)推广为**按主轴**:横向主轴=宽/X,竖向主轴=高/Y。抽纯函数 `TyTrackThumbOffset(AMainLen, AThumbLen, AMin, AMax, APos: Integer; AInvert: Boolean): Integer`(返回 thumb 沿主轴的起点偏移)与 `TyTrackPosFromOffset(...)`(逆运算,拖拽用),可单测。
  - **竖向约定:top=Max、bottom=Min(值向上递增**)。即竖向 `AInvert=True`:offset = travel × (Max−Pos)/(Max−Min);拖到顶=Max、拖到底=Min。横向 `AInvert=False`(left=Min,right=Max,现状)。
  - thumb 厚度仍 12 逻辑 px(沿交叉轴铺满)。hover/drag 命中改用主轴坐标。
- **`Frequency: Integer`**(published,默认 **0**=无刻度)。`>0` 时沿轨道(交叉轴的一侧,如横向底边/竖向右边)每 `Frequency` 个值画一根刻度短线(用 `S.TextColor`/`TyTrackThumb` 描边色)。`0` 默认零变化。刻度位置 = 对每个 `v in Min..Max step Frequency` 用 `TyTrackThumbOffset` 求主轴位置画线。
- **`LineSize: Integer`**(published,默认 1)+ **`PageSize: Integer`**(published,默认 10)。
- **键盘**(`KeyDown`,扩展现有 `←/→`):
  - 横向:`←` −LineSize、`→` +LineSize;竖向:`↓` −LineSize、`↑` +LineSize(向上加值,与 top=Max 一致)。
  - `PageUp` +PageSize、`PageDown` −PageSize(两向一致:PageUp 加值);`Home`→Min、`End`→Max。消费按键。
- **不做:** 刻度标签文字;`TickMarks`(both/top/bottom 位置选择)——固定单侧。

## 4. 关键纯函数(可单测)

- `TyScrollButtonSize(AClient, AKind): Integer`、`TyScrollTrackRect(AClient, AKind, AButtonSize): TRect`(ScrollBar 轨道内缩)。
- `TyTrackThumbOffset(AMainLen, AThumbLen, AMin, AMax, APos, AInvert): Integer` 与 `TyTrackPosFromOffset(AMainLen, AThumbLen, AMin, AMax, AOffset, AInvert): Integer`(TrackBar 双向几何 + 反算)。
- 这些无控件依赖,直接单测(横向=现有行为回归、竖向=镜像、刻度=偏移序列)。

## 5. 不做(批③显式排除)

- TabControl `TabPosition`(底/左/右)、多行标签、`Ctrl+Tab` 进入页内容。
- ScrollBar 箭头自动连发(auto-repeat)、独立 `LargeChange`(用 `PageSize`)。
- TrackBar 刻度数字标签、`TickMarks` 位置选项、`SelStart/SelEnd` 选区。
- Panel `BevelInner/Outer`、GroupBox checkbox 变体。

## 6. 验收

- 现有测试保持全绿(尤其 TrackBar 横向、ScrollBar 拖拽/翻页、Tab `←/→`、Panel/GroupBox smoke —— 默认值=现状,Panel 有标题的渲染对齐变化由新测试覆盖)。新增测试:
  - **Panel/GroupBox**:`Alignment` 三态渲染(标题墨迹水平位置随对齐变化的像素探针;Panel 默认 center、GroupBox 默认 left)。
  - **TabControl**:`Ctrl+Tab` 循环(末页→首页)、`Ctrl+Shift+Tab` 循环、`Ctrl+PageDown/Up` 夹紧、`Home/End`;`TabCount=0` 空操作;切页触发 `OnChange`。
  - **ScrollBar**:纯函数 `TyScrollButtonSize`/`TyScrollTrackRect`(轨道内缩正确);点上/下箭头 ±SmallChange、点轨道空白翻页(命中基于内缩轨道)、thumb 拖拽落在轨道内;键盘 ↑↓/PageUp-Dn/Home/End;`SmallChange` 默认 1、`<1` 夹 1。
  - **TrackBar**:纯函数 `TyTrackThumbOffset`/`TyTrackPosFromOffset`(横向回归 + 竖向镜像 top=Max + 反算往返一致);竖向 `ThumbRect`/拖拽;`Frequency>0` 刻度线像素;键盘横/竖 LineSize、PageUp/Dn PageSize、Home/End;`Orientation` 默认 horizontal 现状不变。
- 无头键盘/鼠标经 `KeyDown`/`MouseDown`(access 子类暴露);PPI=96 钉死。
- 构建矩阵全绿;heaptrc 0;终审通过;`docs/controls/panel.md`/`groupbox.md`/`tabcontrol.md`/`scrollbar.md`/`trackbar.md` 同步新属性。

## 7. 兼容性

加属性/方法是叠加。`Orientation=toHorizontal`、`Frequency=0`、ScrollBar 默认无键盘热路径改变(箭头按钮使轨道缩短——这是预期视觉变化,内嵌 ListBox/Memo 的滚动条也会显示箭头并相应缩短轨道,属正常)。Panel `Alignment=taCenter` 是唯一默认行为变化(有标题的 Panel 居中);若买家依赖旧的左对齐,显式设 `Alignment := taLeftJustify`。
