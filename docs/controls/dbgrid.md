# 数据表格（TTyDBGrid）

## 1. 概述

`TTyDBGrid` 是 `tycontrols_db` 包里的数据表格：把 `DataSource` 指向一个 `TDataSource`，每一行就是数据集的一条记录，每一列是一个字段。行为照 LCL 的 `TDBGrid`——同样的 `Options`、同样的键盘规则、同样的事件名——外观和交互（主题、勾选框、下拉、掩码、日期编辑器、列宽拖动、列拖动）沿用本库的 `TTyStringGrid`。

| 项目 | 值 |
|---|---|
| 单元 | `tyControls.DB.Grid`（`TTyCustomDBGrid` 放全部实现，`TTyDBGrid` 只发布） |
| 建在 | `TTyCustomStringGrid` |
| LCL 对应 | `TDBGrid`（`DBGrids` 单元） |
| 组件面板 | `TyControls Data Controls` 页 |
| typeKey | `TyDBGrid`，父键 `TyGrid` |

完整的演示见 [examples/dbgrid](../../examples/dbgrid/)：一千条订单的内存表，设计期定义的列（勾选框、查找下拉、备注、带格式的金额），导航条，标题点击排序，多选删除，只读开关。

数据感知控件共同的东西（包、安装、界面语言、`DataSource` 的规则）见 [dbcontrols.md](dbcontrols.md)。

---

## 2. 表格里只有一屏记录

表格从不把数据集复制一份。它和 LCL 的 `TDBGrid` 一样只看一个「窗口」：数据连接的 `BufferCount` 是正文放得下的整行数，`RowCount` 是窗口里的记录数，第 i 行就是窗口里第 i 条记录。数据集有一百万行，表格也只读屏幕上那几十行；窗口的大小随控件高度、行高、标题行和主题变化。

所以：

- **当前行跟着数据集走。** `Row` 永远是数据集的当前记录；方向键、翻页、点击别的行、代码里 `Row := 5`，都变成数据连接的 `MoveBy`，表格只在数据集滚动之后跟上。
- **整行滚动**，没有像素级的平滑滚动（和 LCL 一样）。
- **单元格文本来自字段**：`Field.DisplayText`；`NULL` 就是空。`Cells[]` 那一套存储表格不用，往里写什么都不会显示出来。

---

## 3. 选项

`Options` 的类型就是 LCL 的 `TDBGridOptions`，`OptionsExtra` 是 `TDBGridExtraOptions`，默认值也和 LCL 相同。给 `TDBGrid` 写的窗体，`Options = [...]` 那一行原样读得进来，含义相同。底层字符串表格自己的 `Options` 在这里不发布。

| LCL 选项 | 在这里 |
|---|---|
| `dgTitles`、`dgIndicator`、`dgRowLines`、`dgColLines` | 标题行、指示列、横线、竖线 |
| `dgColumnResize`、`dgColumnMove` | 拖分隔线改列宽、拖标题换列的位置 |
| `dgEditing`、`dgRowSelect`、`dgAlwaysShowSelection` | 可编辑、整行选择（同时去掉编辑，照 LCL）、失焦时选区不变淡 |
| `dgTabs` | Tab 在格之间走，见第 5 节 |
| `dgConfirmDelete`、`dgCancelOnExit`、`dgDisableDelete`、`dgDisableInsert` | 见第 6 节 |
| `dgMultiselect`、`dgPersistentMultiSelect` | 见第 8 节 |
| `dgHeaderHotTracking`、`dgHeaderPushedLook`、`dgCellHints`、`dgTruncCellHints`、`dgCellEllipsis`、`dgRowHighlight`、`dgThumbTracking`、`dgDblClickAutoSize` | 对应底层表格的同名能力 |
| `dgDisplayMemoText` | 备注字段显示内容（否则显示 `(MEMO)`），并且可以就地编辑 |
| `dgAlwaysShowEditor`、`dgAutoSizeColumns`、`dgAnyButtonCanSelect` | 照收、读回，**没有效果** |
| `dgeAutoColumns`、`dgeCheckboxColumn` | 没有设计期列时按字段自动建列；布尔字段画成勾选框 |

---

## 4. 列

`Columns` 是一个 `TTyDBGridColumns`，项是 `TTyDBGridColumn`：继承了本库表格列的全部属性（`EditorKind`、`PickList`、`ReadOnly`、`ValueChecked` 等），另加 `FieldName`、`DisplayFormat` 和只读的 `Field`。

- **自动列**：没有设计期列、`dgeAutoColumns` 开着时，数据集打开就按字段各建一列——字段的可见性、`DisplayName` 作标题、按 `DisplayWidth` 换算的宽度、对齐、只读。自动列不写进 `.lfm`，设计器里也不建；加一个设计期列，自动列就全部撤掉（LCL 同样如此）。
- **设计期列**：只显示列出的字段。标题、宽度、对齐在用户没设之前跟着字段走（字段的 `DisplayLabel` 改了，标题跟着改）；设过的才写进 `.lfm`。
- **`DisplayFormat`**：只有列自己设了，才推给数值或日期字段（照 LCL 的 `TColumn`）；没设时读出来是字段自己的。
- **勾选框**：布尔字段在 `dgeCheckboxColumn` 下画成勾选框，NULL 是灰态；别的字段把列的 `EditorKind` 设成 `gekCheckBox`，按 `ValueChecked` / `ValueUnchecked` 读写。
- **查找字段**（`fkLookup`）编辑时是下拉，列表来自 `LookupDataSet`，选中后写回键字段。
- **备注**显示 `(MEMO)`，开了 `dgDisplayMemoText` 显示内容；**其他 blob** 显示 `(blob)`，不能编辑。

---

## 5. 移动与滚动

| 操作 | 结果 |
|---|---|
| ↑ / ↓ | 上一条 / 下一条记录。↓ 越过最后一条时，在可以修改、没有 `dgDisableInsert` 时追加一条 |
| PgUp / PgDn | `MoveBy(±窗口行数)`，和 LCL 一样不留重叠行 |
| Ctrl+Home / Ctrl+End | 第一条 / 最后一条记录 |
| Home / End | 第一列 / 最后一列 |
| 滚轮 | 每格一条记录 |
| Tab / Shift+Tab | 在格之间走；过了窗口最后一行的最后一格，接着走到下一条记录的第一格（到底时追加，规则同 ↓）；Shift+Tab 反过来 |
| Enter | 提交这一格并走到下一条记录（本库表格的习惯） |
| 点击别的行 | `MoveBy(行差)` |

纵向滚动条是表格自己按记录算的：数据集能按 `RecNo` 定位（`IsSequenced` 且没有过滤）时，范围是全部记录，位置是 `RecNo - 1`，拖滑块就是设 `RecNo`；否则用 LCL 的三段式（开头、中间、结尾），点一下走一条，翻页或拖到两端走一个窗口。横向滚动是底层表格自己的。

---

## 6. 编辑、插入、删除

- 在当前记录上打开编辑器——直接打字、F2、双击——数据集就进入编辑（`DataLink.Edit`）；数据集不肯（比如数据源的 `AutoEdit` 关着），这一格就当只读，按键被吞掉。
- 编辑器的初值是 `Field.Text`（`dgDisplayMemoText` 下备注是内容），掩码是字段的 `EditMask`，`OnFieldEditMask` 可以改。字符串字段最多输入字段的 `Size` 个字符。
- 掩码没填满的值不会写进字段：Enter、方向键、点别的格都会停在原地并给出掩码的提示，只能补全或按 Esc 放弃。数据集 `Post`（导航条的「保存」或代码里调用）也一样会被拦下，抛出掩码的错误，记录保持编辑状态，不会把其他字段先存进去。
- 离开这一格时写进字段（`Field.Text`），离开这条记录时由数据集自己 `Post`；导航条上点保存时，开着的编辑器里的文字也会先写进去。
- Esc：编辑器里按，撤销这一格；没有编辑器时按，取消整条记录。
- Insert 键插入；Ctrl+Del 删除，`dgConfirmDelete` 时先问（主题化的消息框，经 protected virtual `ConfirmDeleteRecord`，子类可以换掉）。
- 一条插入之后谁也没动过的新记录，上移、下移、点别的行、焦点离开（`dgCancelOnExit`）时自动取消。
- 字段或数据集拒收（`OnValidate`、`BeforePost` 抛异常）时，异常照常交给应用程序，编辑器留在原格，里面是用户刚才输入的内容。
- 不能编辑的情况：表格 `ReadOnly`、没有 `dgEditing`、数据连接只读、数据集或字段不能修改、列 `ReadOnly`、计算字段、自增字段、键字段不能改的查找字段、没开 `dgDisplayMemoText` 的备注。勾选框在这些情况下点了也不翻转，也不触发 `OnCheckBoxChange`。

---

## 7. 指示列

指示列（`dgIndicator`）在当前记录那一行画状态：

| 状态 | 标记 | 主题令牌 |
|---|---|---|
| 浏览 | 指向记录的三角 | `--glyph-dbgrid-browse` |
| 编辑（`dsEdit`） | I 形竖线 | `--glyph-dbgrid-edit` |
| 插入（`dsInsert`） | I 形竖线，用插入色 | `--glyph-dbgrid-insert` |
| 多选中的其他行 | 圆点 | `--glyph-dbgrid-selected` |

主题给了令牌就用那个图标字体字形，没给就由表格自己画。颜色取指示列（`TyGridIndicator`）的文字色；插入色取主题给选中单元格的底色（`TyGridCell:selected`，通常是主题的强调色）。从右往左的布局里指示列在右边，三角指向左边。

---

## 8. 多选

打开 `dgMultiselect` 后（规则照 LCL）：

- 普通点击：只选中点到的那条；
- Ctrl+点击、Ctrl+小键盘 `*`：切换这一条的选中状态；
- Shift+↑ / Shift+↓：把选区延伸到移到的那一条；往回走则收缩；
- 其他移动（不按 Shift 的方向键、翻页、Ctrl+Home / End）：只选中移到的那条；
- `dgPersistentMultiSelect`：上面这些都不清空选区，只有 Ctrl+点击改它。

选中的行画成选中单元格的样子，指示列里有一个圆点。数据集关闭、换了数据源、去掉 `dgMultiselect` 时选区清空。

`SelectedRows`（`TTyBookmarkList`，对应 LCL 的 `TBookmarkList`）：

| 成员 | 说明 |
|---|---|
| `Count`、`Items[i]` | 选中的记录数、第 i 条的书签 |
| `CurrentRowSelected` | 当前记录选中没有；赋值就选中或取消 |
| `IndexOf(书签)` | 这条记录在不在里面（-1 = 不在）；比较用数据集的 `CompareBookmarks` |
| `Clear` | 清空选区 |
| `Delete` | 把选中的记录从数据集里删掉，然后清空 |
| `Refresh` | 去掉数据集已经不认的书签（`BookmarkValid`），有去掉的返回 True |

书签由数据集生成、比较和释放。删除选中的记录：

```pascal
if Grid.SelectedRows.Count > 0 then
  Grid.SelectedRows.Delete;
```

逐条处理：

```pascal
for i := 0 to Grid.SelectedRows.Count - 1 do
begin
  Orders.GotoBookmark(Grid.SelectedRows[i]);
  Total := Total + Orders.FieldByName('Amount').AsFloat;
end;
```

---

## 9. 排序与筛选

本库表格自带的客户端排序、筛选和分组，在数据表格里是关掉的：它们按表格自己的存储工作，而这里屏幕上只有一个窗口，把窗口里的几十行排一下序没有意义。标题上也没有筛选按钮。

排序交给数据集。点标题触发 `OnTitleClick(Column)`，在里面让数据集排序：

```pascal
procedure TMainForm.GridTitleClick(Column: TTyDBGridColumn);
begin
  if (Column.Field <> nil) and (Column.Field.FieldKind = fkData)
    and not Column.Field.IsBlob then
    Orders.IndexFieldNames := Column.FieldName;   // TBufDataset；SQL 查询就改 ORDER BY
end;
```

筛选同理，用数据集的 `Filter` / `Filtered`，或者改查询语句。

---

## 10. 事件

事件名和 LCL 一样；凡是 LCL 传 `TColumn` 的地方，这里传 `TTyDBGridColumn`。单元格的事件在执行期间，数据连接的当前记录就是那一格所在的行，所以 `Column.Field.AsString` 读到的是那一行的值，数据集的当前记录不会因此移动。

| 事件 | 什么时候 | 和 LCL 的差别 |
|---|---|---|
| `OnCellClick(Column)` | 在正文格上点左键，记录已经移过去之后 | LCL 在松开时触发，这里在按下时 |
| `OnTitleClick(Column)` | 在标题上按下、在同一个标题上松开、中间没拖走 | 拖分隔线或拖列不算 |
| `OnColExit` / `OnColEnter` | 当前列要变时（还在旧列上）/ 变了之后 | — |
| `OnColumnMoved(Sender, FromIndex, ToIndex)` | 用户拖标题把一列换了位置之后 | 两个数是显示位置（列的 `Position`） |
| `OnColumnSized` | 用户松开列分隔线时 | — |
| `OnDrawColumnCell` | 画一格时，底色已铺好、文字还没画 | 多两个参数：画家 `APainter`、`var AHandled`（置 True 表格就不画自己的文字）；表格是用画家画的，没有 `Canvas` 可画 |
| `OnDrawColumnTitle` | 画完一个标题之后 | 多一个画家参数 |
| `OnPrepareCanvas` | 画一格之前 | **签名不同**：最后一个参数是 `var AStyle: TTyGridCellAppearance`（底色、文字色、字体、对齐），改它就改这一格的样子；LCL 是让你改 `Canvas` 的画笔和字体。标题不经过它，标题用 `OnGetHeaderStyle` |
| `OnFieldEditMask` | 编辑器要掩码时 | — |
| `OnGetCellHint(Sender, Column, var AText)` | 鼠标移到一格上（要开 `dgCellHints`） | — |
| `OnSelectEditor(Sender, Column, var Editor)` | 编辑器要打开时 | `Editor` 进来是 nil（表的编辑器是内部的，换不出来）；放一个自己的控件进去，它就盖在这一格上当编辑器：拿到字段文字，离开这一格时读回来。按键归那个控件自己管 |
| `OnUserCheckboxState(Sender, Column, var AState)` | 勾选框要画（或要读）它的状态时 | — |
| `OnEditButtonClick` | 点了 `gekEllipsis` 列的「…」按钮 | — |

`OnDrawColumnCell`、`OnDrawColumnTitle` 交出来的画家在 macOS 的 Retina 屏上按屏幕的实际像素画：直接动 `APainter.Bitmap` 时坐标要换成图层像素，见[在 Retina 屏上直接画图层](../events.md#在-retina-屏上直接画图层)。

底层表格已有、对数据表格也有用的事件照样发布：`OnGetCellStyle`、`OnGetCellBorder`、`OnGetHeaderStyle`、`OnColumnSizing`、`OnEndColumnSize`、`OnColumnMove`、`OnClickCell`、`OnDblClickCell`、`OnRightClickCell`、`OnHeaderClick`、`OnHeaderRightClick`、`OnTopLeftChanged`，以及鼠标、键盘、滚轮事件。

---

## 11. 表尾汇总

底层表格的表尾汇总（列的 `Aggregate`）在数据表格里不自动遍历数据集——数据集可能有一百万行，每画一次都遍历一遍不现实；只汇总屏幕上的几十行又是错的数。表尾的值由 `OnColumnCalc` 给出，在数据变了的时候自己算一次：

```pascal
procedure TMainForm.RecalcTotal;
var
  bm: TBookmark;
begin
  FTotal := 0;
  bm := Orders.GetBookmark;
  Orders.DisableControls;
  try
    Orders.First;
    while not Orders.EOF do
    begin
      FTotal := FTotal + Orders.FieldByName('Amount').AsFloat;
      Orders.Next;
    end;
    Orders.GotoBookmark(bm);
  finally
    Orders.FreeBookmark(bm);
    Orders.EnableControls;
  end;
  Grid.Invalidate;
end;

{ Orders.AfterOpen、AfterPost、AfterDelete 都接到这里 }
procedure TMainForm.OrdersChanged(DataSet: TDataSet);
begin
  RecalcTotal;
end;

procedure TMainForm.GridColumnCalc(Sender: TObject; ACol: Integer; var AValue: Double;
  var AHandled: Boolean);
begin
  if Grid.Columns[ACol].FieldName = 'Amount' then
  begin
    AValue := FTotal;
    AHandled := True;
  end;
end;
```

SQL 数据库上更好的做法是 `SELECT SUM(Amount)` 单独查一次。

---

## 12. 主题

`TyDBGrid` 的父键是 `TyGrid`：主题里没写 `TyDBGrid` 规则时，数据表格和 `TTyStringGrid` 长得一模一样，17 个内置主题都没有写它。表格的各个部分用的是表格自己的键（`TyGridCell`、`TyGridHeader`、`TyGridIndicator`、`TyGridCheckBox` 等），和字符串表格相同。想只给数据表格换个样子，选择器写 `TyDBGrid`：

```css
TyDBGrid { border-color: var(--accent); }
```

指示列的四个图标令牌见第 7 节。

---

## 13. 和 LCL 的 TDBGrid 不一样的地方

- **选项**：`dgAlwaysShowEditor`、`dgAutoSizeColumns`、`dgAnyButtonCanSelect` 读得进来但不起作用。
- **滚动条显隐**：能按 `RecNo` 定位的数据集，记录放不下窗口时才显示；其他数据集窗口满了就显示（LCL 只要多于一条就显示）。`Filtered` 的数据集一律按三段式处理（LCL 只在拖动时这样算）。三段式下把滑块拖到两端也只走一个窗口，不直接跳到第一条 / 最后一条。
- **滚轮**按格数走（一次滚两格走两条）；LCL 每条消息走一条。
- **Enter** 提交并走到下一条记录（本库表格的习惯）；LCL 是打开编辑器。
- **Tab** 在窗口最后一格总会走到下一条记录（必要时追加）；LCL 在记录正在编辑或表格不能修改时把焦点交出表格。
- **何时进入编辑**：打开编辑器就进入 `dsEdit`；LCL 是第一次改值时。没改就离开的记录由数据集自己撤销，结果一样。
- **多行粘贴**只落在当前记录那一行。
- **排序与筛选**交给数据集（第 9 节）；**表尾汇总**交给 `OnColumnCalc`（第 11 节）。
- **事件**：列参数是 `TTyDBGridColumn`；画图的事件带画家参数，`OnPrepareCanvas` 改样式而不是画布，`OnSelectEditor` 的 `Editor` 进来是 nil，`OnCellClick` 在按下时触发，`OnColumnMoved` 报的是显示位置（第 10 节）。
- **多选**时当前行不画「三角加圆点」，只画它的状态；它选没选中看行的底色。
- 对象查看器里 `FieldName` 是普通文本框，没有字段名下拉。
