# Phase 7 批次 4 —— `TTyFilterComboBox` + `TTyShellComboBox` 实施计划

> 设计:`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`(已批准)。
> 前置:批 1 `tyControls.FileSystem`、批 2 `TTyShellListView`、批 3 `TTyShellTreeView` 已合并。
> 两个都是 `TTyComboBox` 子类,用现成 `TyFsParseFilter`/`TyFsFilterPatterns`/`TyFsBreadcrumb`/`TyFsRoots`。
> **零新增主题 token**(继承 TTyComboBox 的 typeKey);两者都锁 `csDropDownList`(选择型,不可编辑)。

## 交付物

| # | 产物 |
|---|---|
| 1 | `source/tyControls.FilterComboBox.pas` —— `TTyFilterComboBox = class(TTyComboBox)` |
| 2 | `source/tyControls.ShellComboBox.pas` —— `TTyShellComboBox = class(TTyComboBox)` + 纯函数 `TyLookInPlaces` |
| 3 | `tests/test.filtercombobox.pas` + `tests/test.shellcombobox.pas` —— 无头,经 Access 子类观测,不测绘制 |
| 4 | 集成:`tycontrols.lpk` ×2、`tytests.lpr` ×2、`designtime/tyControls.Design.pas`(注册进 **TyControls Pickers**)、调色板图标 ×2(genicons + gen-icons.ps1 + test.paletteicons,上界 131→133) |
| 5 | `docs/controls/filtercombobox.md` + `docs/controls/shellcombobox.md` + README 索引 |

## 为什么锁 `csDropDownList`(两者)

可编辑(csDropDown)的下拉会**前缀过滤** `FVisibleItems`,行索引不再对得上模型数组 —— 和 ColorBox 一样的坑。
两个 combo 的每行都背着数据(过滤模式串 / 可导航路径),所以必须选择型。照 `TTyColorBox.SetStyle`:
`inherited SetStyle(csDropDownList)`。

## 防脱钩:模型索引存进 `Objects[]`

ColorBox 的教训:平行数组会在 `Sorted:=True` 或删除时脱钩。这两个 combo 本质**有序、从不排序**(过滤顺序 /
面包屑顺序有意义),但仍照教训做:填充时 `Items.AddObject(displayText, TObject(PtrInt(modelIndex)))`,读回时
用 `PtrInt(Items.Objects[ItemIndex])` 拿模型下标,再去模型数组取 Path/Patterns。即便将来被 Sort,数据映射也不错。

---

## 控件 1:`TTyFilterComboBox`

一个列出**过滤预设**的 combo:把 LCL 过滤串(`'文本 (*.txt)|*.txt|所有文件|*.*'`)解析成若干段,
每段的 Caption 作为一行;选中某段即把该段的模式串作为生效掩码,供文件列表 `List.Mask := FilterCombo.Mask`。

### 状态

```pascal
private
  FFilter: string;                 { LCL 过滤串原文 }
  FSpecs:  TTyFsFilterSpecArray;   { TyFsParseFilter(FFilter) 的结果;行 i <-> FSpecs[i] }
  FFilterIndex: Integer;           { 1-based(LCL FilterIndex 约定);生效段 }
  FUpdating: Boolean;              { SetFilter 重建 Items 时置位,挡住 DoSelect 误触发事件 }
  FOnFilterChange: TNotifyEvent;
```

### 公开 API

```pascal
public
  function  Mask: string;   { = 生效段的模式串(FSpecs[FFilterIndex-1].Patterns);无段时 '' }
published
  property Filter: string read FFilter write SetFilter;              { LCL 过滤串;写它重建下拉 }
  property FilterIndex: Integer read FFilterIndex write SetFilterIndex default 1;  { 1-based }
  property OnFilterChange: TNotifyEvent read FOnFilterChange write FOnFilterChange; { 生效掩码变了 }
```

### 行为契约

- `SetFilter(s)`:`FUpdating:=True`;`FSpecs := TyFsParseFilter(s)`;清空 `Items`,按 `FSpecs[i].Caption`
  逐行 `AddObject(Caption, TObject(PtrInt(i)))`;把 `FFilterIndex` 夹到 `[1..Max(1,Length(FSpecs))]`;
  `ItemIndex := FFilterIndex-1`(有段时);`FUpdating:=False`。**不触发** `OnFilterChange`(初始化用,宿主随后直接读 `Mask`)。
  畸形 / 空串:`TyFsParseFilter` 已保证不崩(空 → 空数组 → 无行,`Mask=''`)。
- `SetFilterIndex(n)`:夹到 `[1..Max(1,Length(FSpecs))]`;若变了则 `ItemIndex := n-1` 并**触发** `OnFilterChange`。
- 用户从下拉选一行(`DoSelect` override,`not FUpdating` 时):`FFilterIndex := PtrInt(Objects[ItemIndex])+1`;
  若变了触发 `OnFilterChange`。
- `Mask`:`if (FFilterIndex>=1) and (FFilterIndex<=Length(FSpecs)) then FSpecs[FFilterIndex-1].Patterns else ''`。
  等价于 `TyFsFilterPatterns(FFilter, FFilterIndex)`(可交叉验证)。

---

## 控件 2:`TTyShellComboBox`(look-in 下拉)

一个"查找范围"下拉:显示**当前目录的面包屑祖先链**(根→当前,按深度缩进)加上**其它根**(盘符 / places),
用户点任一行即跳到该目录。字段显示当前目录的干净标签(叶名 / 根 Display)。

### 纯函数(本单元导出,直接无头测)

```pascal
type
  TTyLookInPlace = record Path, Display: string; Depth: Integer; end;
  TTyLookInPlaceArray = array of TTyLookInPlace;

{ 当前目录 ADir 的 look-in 行模型:先面包屑链(根->当前,Depth=0..N),再其它根(Depth=0)。 }
function TyLookInPlaces(const ADir: string): TTyLookInPlaceArray;
```

语义(**在测试里逐条钉死**):
1. `crumbs := TyFsBreadcrumb(ADir)`;每个 crumb i → `Depth=i`,`Display=` 友好标签:
   若某个 `TyFsRoots.Path` 与该 crumb `SameFileName` → 用那个根的 `Display`;否则
   `ExtractFileName(ExcludeTrailingPathDelimiter(crumb))`;仍为空则回退成 crumb 原文(根盘符 `C:\` 的情况)。
2. 然后追加每个 `TyFsRoots` 里 **Path 不等于 crumbs[0]** 的根(避免和当前链的根重复),`Depth=0`,`Display=` 根 Display。
3. `ADir=''` → crumbs 空 → 只有全部根,`Depth=0`。
4. 顺序稳定:面包屑在前,其它根在后。返回数组非空当且仅当 `ADir<>''` 或 `TyFsRoots` 非空(后者恒真)。

### 状态

```pascal
private
  FDirectory:  string;              { 当前目录(无尾分隔符规范化) }
  FPlaces:     TTyLookInPlaceArray; { 当前 Items 背后的模型;行 <-> Objects[]=PtrInt(下标) }
  FUpdating:   Boolean;             { SetDirectory 重建时置位,挡住 DoSelect 误触发 }
  FOnSelectPath: TNotifyEvent;
```

### 公开 API

```pascal
public
  function SelectedPath: string;   { 当前选中行的 Path(经 Objects[] 取 FPlaces),否则 FDirectory }
published
  property Directory: string read FDirectory write SetDirectory;                   { 设它=重建下拉+选中当前目录行;不触发事件 }
  property OnSelectPath: TNotifyEvent read FOnSelectPath write FOnSelectPath;       { 用户点了某个 place }
```

### 行为契约

- `SetDirectory(p)`:`p2 := ExcludeTrailingPathDelimiter(Trim(p))`;若 `SameFileName(p2, FDirectory)` 直接返回
  (防重入循环);`FDirectory := p2`;`FUpdating:=True`;`FPlaces := TyLookInPlaces(p2)`;清空 `Items`,
  逐行 `AddObject(StringOfChar(' ', 2*Depth) + Display, TObject(PtrInt(i)))`;把 `ItemIndex` 设到
  **Path 与 FDirectory `SameFileName` 的那一行**(= 面包屑最后一项;找不到则 -1);`FUpdating:=False`。**不触发** `OnSelectPath`。
- 用户点一行(`DoSelect` override,`not FUpdating` 时):`picked := FPlaces[PtrInt(Objects[ItemIndex])].Path`;
  若 `not SameFileName(picked, FDirectory)` → `SetDirectory(picked)`(重建,内部 early-exit 不会二次触发)后
  **触发** `OnSelectPath`(宿主据此 `List.LoadDirectory(SelectedPath)`)。
- `PaintFieldContent` override:画 `FDirectory` 的干净标签(与 `TyLookInPlaces` 同一 label 逻辑:根 Display 或叶名),
  **不带缩进空格**(下拉行才缩进)。默认字段会画选中项的带缩进文本,所以这个 override 是为了字段整洁。
- **无图标**(刻意简化):look-in 行用缩进 + 文本表达层级,不铺文件夹/盘符字形。文件对话框需要图标时再单独加(记进文档)。

## 无头测试要点

**FilterComboBox**(经 `TTyFilterComboBoxAccess` 暴露 `DoSelect` / ItemIndex 驱动):
- `Filter := '文本 (*.txt)|*.txt|所有|*.*'` → 2 行;`Items[0]`='文本 (*.txt)';`FilterIndex=1` 默认;`Mask='*.txt'`。
- `FilterIndex := 2` → `Mask='*.*'`;且 `OnFilterChange` 触发一次。
- 模拟用户选第 1 行(设 ItemIndex 后走 DoSelect)→ `FilterIndex=1`、`Mask='*.txt'`、事件触发。
- `SetFilter` 本身**不**触发 `OnFilterChange`(用计数器断言 0)。
- 空 / 畸形串不崩:`Filter:=''` → 无行、`Mask=''`;`Filter:='只有标题没有管道'` → 1 段 `Patterns=''`(与 `TyFsParseFilter` 一致)。
- `Mask` 与 `TyFsFilterPatterns(Filter, FilterIndex)` 一致(交叉验证)。

**ShellComboBox** + `TyLookInPlaces`(纯函数直接测 + `TTyShellComboBoxAccess`):
- `TyLookInPlaces('/a/b')`(Unix 形)/ `TyLookInPlaces('C:\a\b')`(Win 形)→ 面包屑深度 0/1/2,Display 是各段叶名/根 Display;
  末项 Path 等于输入(规范化后)。
- `TyLookInPlaces('')` → 只有根,全 Depth 0。
- 其它根不含当前链的根(crumbs[0] 不重复出现)。
- `Directory := 某临时子目录` → `ItemIndex` 落在 Path==Directory 的行;`SelectedPath = Directory`。
- 模拟用户点面包屑上一层(设 ItemIndex 到某祖先行后走 DoSelect)→ `OnSelectPath` 触发、`SelectedPath` = 该祖先。
- `SetDirectory` 设同一路径(带/不带尾分隔符)→ early-exit,`OnSelectPath` **不**触发(计数器 0);证明防重入。
- `Directory := ''` → 无选中行(ItemIndex=-1),不崩。

测试环境注意([[controls-expansion-program]] 记过):控制台测试跑器 `TFont.PixelsPerInch=72`,任何断言绝对设备坐标的要在 SetUp 里
`Control.Font.PixelsPerInch := 96`;但本批只测状态/模型/事件,不测像素,一般用不到。临时目录用**进程唯一名**(批 2 教训)。

## 验收

- 全量测试 0 失败(基线 2791 + 新增)。
- **零新增主题 token**;`themes/*`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、
  `tyControls.ComboBox.pas`、`tyControls.FileSystem.pas`、批 2/3 的 shell 单元**零改动**。
- 调色板漂移守卫通过(133 类)。
- 每批过 [[pre-merge-checklist]] 的 i18n / README 检查(这两个 combo 运行时无用户可见文案,i18n 无新增;README 中英索引各加两行)。
