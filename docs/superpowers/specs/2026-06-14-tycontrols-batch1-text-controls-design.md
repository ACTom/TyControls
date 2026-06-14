# TyControls 控件完善程序 · 批① 文本类 设计文档 — Edit/Memo 属性补全 + SpinEdit 内联编辑 + 光标闪烁

- **日期:** 2026-06-14
- **前置:** `main`(Phase 0 横切基线已合入,~634 测试);见 [Phase 0 spec](2026-06-14-tycontrols-phase0-baseline-design.md)。
- **定位:** "完善现有控件"程序的**批①**(文本类)。把三个文本控件补到接近 LCL 同名控件的常用能力。本文是批①的单一 spec;实现计划按"Edit 属性 → Memo 属性 → SpinEdit 编辑 → 光标闪烁"顺序推进。
- **执行约定:** 沿用项目惯例 —— 几何/像素测试钉 `PPI=96`;`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests.exe -a --format=plain`;现有测试保持全绿、不改既有测试语义;无头剪贴板经虚方法 `ReadClipboardText`/`WriteClipboardText` 覆写;`examples/demo/demo.lpi` 有用户未提交改动**勿碰**。基线:0 failures + 15 个无头 win32(error 1407)环境错误(非回归)。

---

## 1. 动机

`TTyEdit` 已是完整单行编辑器(光标/选区/剪贴板/撤销/词导航/水平滚动),但缺 `ReadOnly`/`MaxLength`/`PasswordChar`/`TextHint` 这些标准 `TEdit` 属性。`TTyMemo` 缺 `ReadOnly`/`MaxLength`。`TTySpinEdit` 目前**只读显示**(只画 `IntToStr(Value)`,无光标、不能键入数值)。`TTyEdit`/`TTyMemo` 的光标是**静态** 1px 竖条(v1 为像素测试确定性而有意为之),无闪烁。本批补齐这些常见能力,且 100% 向后兼容、不破坏现有测试。

## 2. 核心原则

新增属性纯叠加。视觉值跟随主题、不写死(见 [Phase 0 §2 / 主题可定制原则]):占位符颜色由当前 `TextColor` 派生,不引入硬编码颜色。光标闪烁为**运行期**行为且无头环境静止,确定性测试不受影响。

## 3. 范围

### 3.1 TTyEdit 属性(`source/tyControls.Edit.pas`)

- **`ReadOnly: Boolean`**(published,默认 `False`)。为 `True` 时拦截所有**用户**编辑入口:`InjectKey`、`InjectBackspace`、`InjectDelete`、`DeleteWordBackward`、`DeleteWordForward`、`PasteFromClipboard`。保留光标移动、选区扩展、`CopyToClipboard`、`SelectAll`、撤销/重做的导航部分。**程序化 `Text:=`(`SetText`)仍可写**(对齐 LCL ReadOnly 语义)。`CutToClipboard` 在 ReadOnly 下退化为 `Copy`(复制选区、不删除)。
- **`MaxLength: Integer`**(published,默认 `0`=无限)。按**码点**(非字节)封顶最终文本长度。`InjectKey`:删除选区后,若 `UTF8Length(FText) >= MaxLength` 则不插入。`InjectStringAt`/`PasteFromClipboard`:把待插入串截断到 `MaxLength - 当前长度`(≤0 则不插入)。
- **`PasswordChar: string`**(published,默认 `''`=关)。约定为单个 UTF-8 码点(如 `'●'`/`'*'`)。非空时:
  - **渲染**用掩码串(`FText` 每码点替换为 `PasswordChar`),`MeasureCodepointWidths` 也基于掩码串测量(掩码每码点宽度一致,码点数不变 → 光标/滚动/命中测试索引 1:1 对齐)。
  - **安全**:掩码激活时 `CopyToClipboard`/`CutToClipboard` 为空操作(防止明文外泄)。
  - 〔比 LCL 的 `Char` 更灵活以支持 unicode 圆点;约定只取第一个码点,多码点输入按首码点用。〕
- **`TextHint: string`**(published,默认 `''`,占位符)。`FText = ''` 时绘制提示文字(taLeftJustify/tlCenter,与正文同位置);颜色 = 当前 `TextColor` 派生为 **~50% alpha**(`TyRGBA(r,g,b,$80)`),跟随主题。聚焦时光标仍画在其上。`FText` 非空时不绘制。

### 3.2 TTyMemo 属性(`source/tyControls.Memo.pas`)

- **`ReadOnly: Boolean`**(published,默认 `False`):拦截编辑入口(可打印字符插入、`Enter` 拆行、`Backspace`/`Delete`/跨行合并、词级删除、`Paste`、`Cut`→退化为 `Copy`),保留导航/选区/复制/滚动。程序化 `Lines :=` 仍可写。
- **`MaxLength: Integer`**(published,默认 `0`=无限):按**全模型总码点数**(各逻辑行内容码点之和;换行符不计入)封顶。规则(明确,无歧义):**仅限制"新增内容"的输入路径**——可打印字符插入与粘贴;当内容总码点数 `>= MaxLength` 时拒绝插入新的可打印字符,粘贴则把插入内容截断到余量(`MaxLength - 当前总码点数`,≤0 则不插)。`Enter`(拆行,不增加内容码点)、`Backspace`/`Delete`、跨行合并均**不受 MaxLength 限制**。

### 3.3 TTySpinEdit 轻量内联编辑(`source/tyControls.SpinEdit.pas`)

把"只读显示"升级为可编辑数值框,新增一个**自包含的轻量编辑层**(不复用 `TTyEdit` 实例,避免组合控件复杂度):

- 状态:`FEditText: string`(编辑缓冲,初值 `IntToStr(FValue)`)、`FCaret: Integer`(码点索引)。`FEditText` 在 `Value`/`Min`/`Max` 改变或控件获焦初次进入时与 `IntToStr(FValue)` 同步。
- 键入:数字 `0..9` 与**前导** `-`(仅在首位、且文本不含 `-` 时接受)插入到 `FCaret`;`Backspace`/`Delete` 行内删除;`←/→/Home/End` 移光标。光标 X 用与 Edit 同源的 `TyConfigureTextFont` 在 BGRA 位图上测量码点宽度(短数值串,正确性优先)。
- **提交**:`Enter` 或失焦(`DoExit`)→ `StrToIntDef(FEditText, FValue)` → 夹紧 `[FMinValue, FMaxValue]` → 写 `Value`(触发 `OnChange`)→ 回填 `FEditText := IntToStr(FValue)`、光标夹紧。`Esc` → 放弃缓冲,`FEditText := IntToStr(FValue)`、光标归位。
- 上/下箭头键、滚轮、上下按钮:仍步进 `Value`,并回填 `FEditText`。
- 渲染:文本区画 `FEditText`(聚焦/编辑时)或 `IntToStr(FValue)`;聚焦时画 1px 光标(与 Edit 同款)。右侧上下箭头按钮区不变。
- **不做**:选区、剪贴板、词导航(轻量层范围外)。

### 3.4 光标闪烁(Edit / Memo / SpinEdit 共享)

- 纯函数(放 `tyControls.Animation` 或各控件复用的一个小单元):
  ```pascal
  function TyCaretVisible(AElapsedMs, AHalfPeriodMs: Integer): Boolean;
  // Result := (AElapsedMs div AHalfPeriodMs) mod 2 = 0;  // 半周期 ~530ms
  ```
  可单测(0→可见、半周期→隐、整周期→可见)。
- 每控件:`FCaretVisible: Boolean`(默认 `True`)、惰性 `FBlinkTimer: TTimer`(**仅当 `HandleAllocated` 时启动**,间隔 ~530ms)。Timer 翻转 `FCaretVisible` 并 `Invalidate`。**任何编辑或光标移动复位 `FCaretVisible := True`**(活动后光标实心)。失焦停 timer。
- 光标绘制条件追加 `and FCaretVisible`。
- **确定性保证**:`FCaretVisible` 默认 `True`,无头测试从不创建/启动 `FBlinkTimer`(无窗口句柄),故 `FCaretVisible` 恒 `True` → 现有静态光标像素测试**逐像素不变、全部保持绿**。
- 内部机制,**不发布** `CaretBlink` 属性(系统级行为)。可提供 protected 可步进种子(如 `procedure SetCaretVisibleForTest(AValue: Boolean)` 或暴露纯函数)供测试。

## 4. 不做(批①显式排除)

- SpinEdit 的选区/剪贴板/词导航/浮点/千分位(SpinEdit 仍是整数)。
- Memo 的 `TextHint`/`PasswordChar`(语义弱或无意义)。
- 发布 `CaretBlink` 开关属性(运行期内部行为)。
- 安全粘贴/输入过滤策略(MaxLength 之外);Edit 的 `NumbersOnly`/掩码校验。
- 右键上下文菜单、双击选词(沿用现状,后续批次)。

## 5. 验收

- 现有测试保持全绿(尤其 **Edit/Memo 静态光标像素测试不变**——闪烁默认 True、无头不启 timer)。新增测试覆盖:
  - **Edit ReadOnly**:`ReadOnly=True` 时 `InjectKey`/退格/删除/词删/粘贴为空操作、文本不变;`Copy` 仍取到选区;`Cut` 仅复制不删;光标/选区仍可动;`Text:=` 仍生效。
  - **Edit MaxLength**:满则不插;粘贴超长截断到余量;`0` 不限。
  - **Edit PasswordChar**:渲染像素=掩码字形而非明文(探针验证一个本应是某字母的位置现在是掩码字符的墨迹/对齐);光标 x 与掩码测量一致;掩码时 `Copy`/`Cut` 为空。
  - **Edit TextHint**:`FText=''` 渲染出提示墨迹且其颜色 alpha≈$80(派生);`FText` 非空时无提示;聚焦空文本仍画光标。
  - **Memo ReadOnly/MaxLength**:编辑被拦、导航/复制可用、`Lines:=` 生效;总码点封顶。
  - **SpinEdit**:键入数字进缓冲并渲染;`←/→` 移光标(像素 x 合理);`Enter` 提交并夹紧到 `[Min,Max]`、`Value`/`OnChange` 正确;`Esc` 还原;失焦提交;上/下箭头步进并回填缓冲;非法输入(空/纯`-`)提交退回原 `Value`。
  - **Blink 纯函数**:`TyCaretVisible` 三点(0/半周期/整周期);复位逻辑(编辑后 `FCaretVisible=True`,经 protected 种子驱动验证翻转)。
- 无头剪贴板经 `ReadClipboardText`/`WriteClipboardText` 覆写;PPI=96 钉死。
- 构建矩阵 `bash scripts/build-matrix.sh` 全绿;heaptrc 0(新增 `FBlinkTimer`/`FMeasureBmp` 在 Destroy 释放);终审通过;`docs/controls/edit.md`/`memo.md`/`spinedit.md` 同步新属性。

## 6. 兼容性

加属性是叠加;默认值(`ReadOnly=False`、`MaxLength=0`、`PasswordChar=''`、`TextHint=''`)保持旧行为。光标闪烁运行期生效、无头静止,现有像素测试零变化。SpinEdit 升级为可编辑后,旧用法(只设 `Value`/箭头/滚轮)行为不变;新增的键入是叠加路径。
