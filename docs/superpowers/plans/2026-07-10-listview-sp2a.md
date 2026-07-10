# TTyListView SP2a 契约 —— 行首复选框 + 行内重命名

> 设计:`docs/superpowers/specs/2026-07-10-listview-design.md`(SP2 段)
> 前置:SP1 已合并(`7c39709`)。SP2b(分组视图)另做,它要改纯布局层。
>
> **零新增主题 token。** 复选框解析已有的 `'TyTreeCheckBox'`;编辑器是一个 `TTyEdit` 子控件。

## 为什么拆开

分组视图会把组头插进流式布局,`TyListVisibleRange` 的 O(1) 闭式解要换成按组前缀和 + 二分。
那是纯函数层的地基改动。复选框和重命名只动控件层。混在一批里,布局回归和交互回归会纠缠。

---

## 一、行首复选框

### 纯函数(加进 `tyControls.ListView.Layout`)

```pascal
{ 一个单元格里复选框的位置(设备像素,客户区坐标)。
  - 调用方传的 ACell:报表模式是**主列的子矩形**,其余模式是整个单元格。
    (布局单元不知道列模型,所以列几何由控件算好再传进来。)
  - lvsIcon:靠**左上角**,内缩 APad。
  - 其余:靠左、**垂直居中**,内缩 APad。
  - ACheckPx <= 0,或单元格装不下(宽或高不足 ACheckPx + APad)→ 返回 Rect(0,0,0,0)。
  绘制与命中都必须调它;和 TyListItemRect 一样,是唯一几何来源。 }
function TyListCheckRect(const ACell: TRect; AStyle: TTyListViewStyle;
  ACheckPx, APad: Integer): TRect;
```

### 控件 API

```pascal
published
  property Checkboxes: Boolean default False;
  property OnItemChecked: TTyListItemEvent;   { 收 item index }
public
  property Checked[AIndex: Integer]: Boolean read GetChecked write SetChecked;   { item index }
protected
  { 集合模式:写 Items[AIndex].States 的 lisChecked。
    OwnerData:什么都不做 —— 控件不缓存状态,由 app 在 OnItemChecked 里改自己的存储。
    读一律走 GetItemState,所以两种模式只有一条读路径。 }
  procedure SetItemChecked(AIndex: Integer; AValue: Boolean); virtual;
```

`Checked[i]` 读 = `lisChecked in GetItemState(i)`。**控件不持有勾选状态**,和数据模型的其余部分一致。

`SetChecked` 越界索引静默忽略(不抛)。改变后触发 `OnItemChecked(Self, itemIndex)`,并 `Invalidate`。

### 交互

- **点击复选框**(`GetHitPart = lhpCheck`)→ 切换勾选,**不改变选中和焦点**,直接 `Exit`,不进选择逻辑。
- **`Space`**:`Checkboxes = True` 时切换焦点项的勾选;`Ctrl+Space` 仍切换**选中**(多选模式)。
  `Checkboxes = False` 时 `Space` 维持原状(切换选中)。
- 复选框**不参与框选**(marquee 只改选中集)。

### 绘制

- 样式 `ActiveController.Model.ResolveStyle('TyTreeCheckBox', '', S)`,勾选时 `S = [tysActive]`。
- 报表模式:复选框占主列左侧,**图标与文字整体右移** `CheckPx + Pad`。
- 流式模式:复选框叠在单元格左上(`lvsIcon`)或左中(其余),**不改变单元格尺寸**。
- 逻辑像素常量 `TyLvCheckPx = 14`。

---

## 二、行内重命名

### 契约

```pascal
type
  TTyListEditingEvent = procedure(Sender: TObject; AIndex: Integer;
                                  var AAllow: Boolean) of object;
  TTyListEditedEvent  = procedure(Sender: TObject; AIndex: Integer;
                                  var AText: string) of object;

published
  { 默认只读 —— 和 TTyTreeView 的 toEditable 一样是 opt-in。文件对话框的文件面板
    不该因为误按 F2 就进入改名。这与 LCL TListView.ReadOnly=False 相反,是有意的。 }
  property ReadOnly: Boolean default True;
  property OnEditing: TTyListEditingEvent;   { AAllow := False 可否决 }
  property OnEdited:  TTyListEditedEvent;    { var AText:app 可改写;置 '' 视为放弃 }
public
  function  Editing: Boolean;
  procedure BeginEdit(AIndex: Integer);                                { item index }
  procedure EndEdit(ACommit: Boolean; ARestoreFocus: Boolean = False);
protected
  property  InlineEditor: TTyEdit read FEditor;
  { 集合模式:Items[AIndex].Caption := AText。OwnerData:什么都不做 ——
    控件不拥有数据,改存储是 app 在 OnEdited 里的事。 }
  procedure CommitEdit(AIndex: Integer; const AText: string); virtual;
```

- 触发:焦点项上按 **F2**。**不做"慢速双击改名"** —— 它会和 `OnItemActivate` 的双击打架。
- 编辑器 bounds = 该项的**标签矩形**:报表模式是主列的文字矩形,流式模式是单元格里的标签矩形。
  两者都从 `TyListItemRect` 派生,不另算几何。
- `ReadOnly = True` 或 `OnEditing` 否决 → `BeginEdit` 静默返回。
- `Enter` 提交并**把焦点还给列表**;`Esc` 取消并还焦点;**失焦提交但不还焦点**。

### 编辑器生命周期 —— 抄 `TTyValueListEditor` 那 8 条,一条都不许漏

1. `EditorExit` 开头 `if csDestroying in ComponentState then Exit;` —— 否则父窗体销毁时提交进已释放的 Items(UAF)。
2. **每一条碰编辑器的路径都要 `if FEditor = nil then Exit;`** —— 基类构造函数会先 `Resize`,那时子类构造函数还没建出 `FEditor`。
3. `SetController` override:把 Controller 下传给编辑器,否则单实例主题的列表里蹦出一个全局默认皮肤的编辑框。
4. **滚动 / `Resize` / 切 `ViewStyle` / `Sort` 之前先 `EndEdit(True)`** —— 单元格会跑,编辑框不能悬空。
5. `ItemsChanged` / `Items.Clear` / 缩短 `ItemCount` 导致被编辑行消失 → `EndEdit(False)`(取消,不提交)。
6. **按 item index 提交**,而不是 display 位置或"当前第几行";任何异步/模态边界之后要重新确认该行仍存在。
7. 键盘提交/取消把焦点还给列表;失焦提交不还(焦点已经去别处了)。
8. 编辑器 `ControlStyle + [csNoDesignVisible]`,且**在设 `Visible` 之前设**(见 `designer-internal-subcontrol-leak`)。

补一条 SP1 特有的:

9. **排序会移动行,但 item index 不变。** 编辑期间若发生排序,`EndEdit(True)` 之后再排;
   `FEditItem` 存的是 item index,所以即便中途重排也提交到对的那一项。

---

## 交付物

| # | 产物 |
|---|---|
| 1 | `tyControls.ListView.Layout`:`TyListCheckRect` + 测试 |
| 2 | `tyControls.ListView`:`Checkboxes` / `Checked[]` / `SetItemChecked` / 复选框绘制与命中 |
| 3 | `tyControls.ListView`:`ReadOnly` / `BeginEdit` / `EndEdit` / `CommitEdit` / `OnEditing` / `OnEdited` |
| 4 | `tests/test.listview.pas`:复选框状态机、编辑器生命周期(上面 9 条逐条钉) |
| 5 | `examples/listview`:左侧列表打开复选框 + F2 改名 |
| 6 | `docs/controls/listview.md` |

## 验收

- 全量测试 0 失败(基线 2583 + 新增)
- `themes/*.tycss`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、`tyControls.TreeView.pas` **零改动**
- 每条编辑器生命周期规则**都有一个以它命名的测试**,并且**变异测试**过(撤掉守卫,该测试必须挂)
