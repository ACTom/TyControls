# TyControls 控件完善程序 · 批② 选择类 设计文档 — ListBox 多选/翻页 + ComboBox 键盘选择/type-ahead + RadioButton GroupIndex

- **日期:** 2026-06-14
- **前置:** `main`(Phase 0 + 批① 已合入,660 测试)。见 [批① spec](2026-06-14-tycontrols-batch1-text-controls-design.md)。
- **定位:** "完善现有控件"程序的**批②**(选择类)。把三个选择控件补到接近 LCL 同名控件的常用能力。单一 spec;实现计划按"RadioButton → ComboBox → ListBox"顺序(由小到大)推进。
- **执行约定:** 沿用项目惯例 —— 几何/像素测试钉 `PPI=96`;`lazbuild tests/tytests.lpi` 后跑 `./tests/tytests.exe -a --format=plain`;现有测试保持全绿、不改既有测试语义;无头键盘经 `SimulateKeyDown`/`KeyDown`/`UTF8KeyPress` 注入。基线:0 failures + 15 个无头 win32(error 1407)环境错误(非回归)。`examples/demo/demo.lpi` 与 `examples/demo/mainform.lfm` 有用户未提交改动 —— **勿碰**(每个任务只 stage 自己的文件)。

---

## 1. 动机

`TTyListBox` 仅单选(`FItemIndex`),无多选、无翻页。`TTyComboBox` 是只读下拉(`csDropDownList`):关闭态**没有键盘选择**(只处理 Esc),**没有 type-ahead**(打字无反应)。`TTyRadioButton` 仅按 **Parent** 分组(`UncheckSiblings` 取消所有兄弟),无 `GroupIndex`,一个 Parent 下无法并存多个单选组。本批补齐这些常见能力,全部纯叠加、向后兼容。

## 2. 核心原则

新增属性默认值=旧行为(`MultiSelect=False`、`GroupIndex=0`、ComboBox 仍只读下拉)。视觉跟随主题(选中行复用现有 `TyListItem:active` 高亮,不引入硬编码色)。

## 3. 范围

### 3.1 TTyRadioButton.GroupIndex(`source/tyControls.CheckBox.pas`)

- **`GroupIndex: Integer`**(published,默认 0)。`UncheckSiblings` 改为只取消 **Parent 下、且 `GroupIndex` 相同** 的兄弟 `TTyRadioButton`。不同 GroupIndex 的单选组互不影响。其余行为(`Checked` 语义、`Space` 激活、点击)不变。

### 3.2 TTyComboBox 键盘选择 + type-ahead(`source/tyControls.ComboBox.pas`)

仍是**只读下拉**(不做可编辑文本输入)。在关闭态新增键盘交互:

- **`KeyDown`**(关闭态;下拉打开时维持现有 Esc 关闭):
  - `↑`:`SelectItem(FItemIndex - 1)`(夹紧到 ≥0;`FItemIndex=-1` 时选 0)。
  - `↓`:`SelectItem(FItemIndex + 1)`(夹紧到 ≤Count-1;`-1` 时选 0)。
  - `Home`:`SelectItem(0)`;`End`:`SelectItem(Count-1)`。
  - `Alt+↓` 或 `F4`:`DropDown`(打开下拉);下拉已开时 `F4` 关闭。
  - 这些键在 `Count=0` 时为空操作;消费按键(`Key:=0`)。
- **Type-ahead**(`UTF8KeyPress`):维护一个搜索缓冲 `FTypeAhead: string` 与上次击键时刻 `FTypeAheadTick: QWord`。收到可打印字符时:若距上次击键 > ~600ms 则先清空缓冲;把字符追加到缓冲;在 `Items` 中**从当前项之后**循环查找第一个**不区分大小写**以缓冲为前缀的项,`SelectItem` 之。纯前缀匹配,逻辑用一个可单测的纯函数 `TyComboTypeAheadMatch`(见 §4)。打开态时同样可用(可选;v1 仅要求关闭态)。
- 不改下拉弹层、Click 行为、渲染。

### 3.3 TTyListBox 多选 + 翻页(`source/tyControls.ListBox.pas`)

- **`MultiSelect: Boolean`**(published,默认 `False`)。`False` 时**行为与现状逐字一致**(单选 `FItemIndex`,所有现有测试不变)。
- **选择状态**:新增 `FSelected: TBits`(或等价布尔数组),长度随 `Items.Count`(在 `SetItems`/直接 mutate 兜底处重建并清空越界位)。`FItemIndex` 在多选下兼任**焦点/锚点**(anchor)行。
  - 公开:`property Selected[AIndex: Integer]: Boolean read GetSelected write SetSelected;`(写时触发重绘 + `OnChange`);`function SelCount: Integer;`;`procedure ClearSelection;`;`procedure SelectAll;`(仅 MultiSelect 有意义;单选下 `SelectAll` 为空操作或选末项——定为**空操作**)。
- **鼠标**(MultiSelect=True;单选时维持现状):
  - 普通左键点击行 R:清空所有选择,选中 R,`FItemIndex := R`,锚点 := R。
  - `Ctrl+` 左键:切换 R 的选中态,`FItemIndex := R`,锚点 := R。
  - `Shift+` 左键:选中锚点(若锚点无效则用 R)到 R 的闭区间(先清空再设区间),`FItemIndex := R`,锚点不变。
- **键盘**(MultiSelect 与单选都支持翻页/Home/End;扩展选择仅 MultiSelect):
  - 单选(MultiSelect=False):`↑/↓` 现状;新增 `PageUp`=`SelectItem(FItemIndex - VisibleRows)`、`PageDown`=`SelectItem(FItemIndex + VisibleRows)`(夹紧);`Home/End` 现状。
  - 多选:`↑/↓/PageUp/PageDown/Home/End` 移动 `FItemIndex`(焦点);若 `Shift` 按下,则把锚点到新焦点的闭区间设为选中(替换式,基于一个 `BaseSelection` 快照——简化:Shift+移动时清空并选 [anchor..focus] 闭区间);否则(无 Shift)清空并只选新焦点行、锚点 := 新焦点。`Space`:切换焦点行选中态(锚点 := 焦点)。可选 `Ctrl+A`:`SelectAll`。
  - 所有移动后 `EnsureFocusVisible`(复用/推广现有 `EnsureSelectionVisible`,以 `FItemIndex` 为准)。
- **渲染**:行状态判定改为——多选下,`FSelected[i]` 为真的行取 `tysActive`;否则 hover 取 `tysHover`;否则 `tysNormal`。单选下维持"`i=FItemIndex` → active"。(焦点行与选中行的额外视觉区分留作后续;本批选中行高亮即可。)
- **`OnChange`**:任何选择集合变化触发(单选维持现状:`FItemIndex` 变化触发)。

## 4. 关键纯函数(可单测)

- `function TyComboTypeAheadMatch(AItems: TStrings; AStart: Integer; const APrefix: string): Integer;` — 从 `AStart+1` 起循环(wrap)查找第一个不区分大小写以 `APrefix` 为前缀的项的索引;无匹配返回 -1。无控件依赖,直接单测。
- ListBox 区间选择可抽一个纯 helper `procedure TySetRange(ABits: TBits; ALo, AHi, ACount: Integer);`(清空后置 [Lo..Hi]),便于测试;或在控件内实现 + 通过 `Selected[]`/`SelCount` 断言。

## 5. 不做(批②显式排除)

- ComboBox **可编辑文本输入**(`csDropDown`:嵌入 Edit 引擎)——独立后续 spec。
- ListBox owner-draw / checkbox-items / 横向滚动 / 拖拽多选的自动滚动。
- ComboBox 自动完成下拉过滤(type-ahead 只跳选,不过滤列表)。
- RadioButton 跨 Parent 的 GroupIndex 分组(仍限同 Parent 内按 GroupIndex 细分)。

## 6. 验收

- 现有测试保持全绿(尤其 ListBox 单选、ComboBox 现有下拉/选择测试 —— MultiSelect 默认 False、ComboBox 仍只读)。新增测试覆盖:
  - **RadioButton GroupIndex**:同 Parent、同 GroupIndex 的两个 radio 互斥;不同 GroupIndex 的两个 radio **不**互斥(各自可 Checked)。
  - **ComboBox**:`↑/↓` 改 ItemIndex(关闭态、不打开)、`Home/End`、`Alt+↓`/`F4` 打开下拉;type-ahead 纯函数 `TyComboTypeAheadMatch`(前缀命中 / wrap / 无匹配 / 大小写无关);经 `UTF8KeyPress` 打 'b' 选中以 b 开头的项;超时(模拟 tick 跳变)后缓冲重置。
  - **ListBox**:单选回归(MultiSelect=False 行为不变)+ PageUp/PageDown(单选);多选 click(清其余)、Ctrl+click(切换)、Shift+click(区间)、`Space` 切换、Shift+↓ 扩展、`Selected[]` 读写、`SelCount`、`ClearSelection`/`SelectAll`、`OnChange` 触发。
- 无头键盘经 `SimulateKeyDown`/`KeyDown`/`UTF8KeyPress`;PPI=96 钉死。
- 构建矩阵 `bash scripts/build-matrix.sh` 全绿;heaptrc 0(`FSelected: TBits` 在 Destroy 释放);终审通过;`docs/controls/listbox.md`/`combobox.md`/`radiobutton.md` 同步新属性。

## 7. 兼容性

加属性/方法是叠加。`MultiSelect=False`、`GroupIndex=0` 保持旧行为。ComboBox 仍只读下拉,新增键盘/type-ahead 是叠加路径(原 Click/Esc/下拉不变)。`Selected[]`/`SelCount` 在单选下仍可读(单选=至多 `FItemIndex` 一项为真),便于统一消费。
