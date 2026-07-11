# TTyShellComboBox

## 概述

`TTyShellComboBox` 是一个"查找范围"下拉框(`TTyComboBox` 子类,look-in combo)。展开后显示**当前目录的
面包屑祖先链**(根 → 当前,按深度缩进)加上**其它根**(盘符 / places),用户点任一行即跳到该目录。
字段里显示当前目录的干净标签(叶名 / 根 Display)。

锁 `csDropDownList`。**零新增主题 token**(继承 `TTyComboBox`)。**无图标**(缩进 + 文本表达层级;文件对话框
需要文件夹/盘符图标时再单独加)。

## 用法

```pascal
uses tyControls.ShellComboBox;

LookIn := TTyShellComboBox.Create(Self);
LookIn.Parent := Panel1;
LookIn.Directory := 'C:\Users\Tom\Documents';   // 重建下拉,选中当前目录行;不触发事件
LookIn.OnSelectPath := @PlacePicked;             // 用户点了某个 place

procedure TForm1.PlacePicked(Sender: TObject);
begin
  List.LoadDirectory(LookIn.SelectedPath);   // 跳到用户选的目录
end;
```

## 属性 / 方法 / 事件

| 成员 | 说明 |
|---|---|
| `Directory: string` | 当前目录。写它=重建下拉并选中当前目录行;**不触发** `OnSelectPath`。同一路径(含/不含尾分隔符)early-exit,防重入循环。 |
| `SelectedPath: string` | 当前选中行的可导航路径(经 `Objects[]` 取模型),否则 `Directory`。 |
| `OnSelectPath` | 用户点了某个 place(祖先目录或其它盘符)时触发;宿主据此 `List.LoadDirectory(SelectedPath)`。 |

## 纯函数 `TyLookInPlaces`

```pascal
type
  TTyLookInPlace = record Path, Display: string; Depth: Integer; end;
  TTyLookInPlaceArray = array of TTyLookInPlace;
function TyLookInPlaces(const ADir: string): TTyLookInPlaceArray;
```

给定 `ADir`:先 `TyFsBreadcrumb(ADir)` 的每个累积路径(`Depth = 0..N`,`Display` = 匹配的根 Display 否则叶名),
再追加每个 `TyFsRoots` 里 Path 不等于链首的根(`Depth 0`,不重复当前盘符)。`ADir=''` → 只有根。无头可测。

## 关键设计

- **锁 `csDropDownList`** + **每行模型索引存 `Objects[]`**(同 [[filtercombobox]] / ColorBox);读侧 `SelectedPath`/`DoSelect`
  与写侧的当前行匹配都经它,Sort-safe。
- **`SetDirectory` 同路径 early-exit**:用户点行 → `OnSelectPath` → 宿主导航 → 宿主回写 `Directory :=` 同一路径 →
  early-exit,不二次触发,循环终止。
- **`FUpdating` 守护重建**:重建 Items + 设 `ItemIndex` 期间 `DoSelect` 被挡,不误触发 `OnSelectPath`。
- 字段用 `PaintFieldContent` 画不带缩进的干净标签(下拉行才缩进)。

## 消费者

Phase 7 文件对话框顶部的"查找范围"下拉,和目录树 / 文件列表双向联动。见
`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`。
