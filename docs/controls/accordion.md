# TTyAccordion — API 参考

## 1. 概述

`TTyAccordion` 是**堆叠容器**：把几个 [`TTyExPanel`](expanel.md) 当作一节节，从上到下排满整个宽度，就像编辑器侧栏里「文件夹」和「大纲」共用一栏那样。

- **折叠的节**只占标题栏的高度。
- **展开的节**按权重分剩下的高度。权重就是这一节的 `ExpandedHeight`，不需要另外的属性。
- **相邻两个展开的节**之间有一条拖动条，拖它把高度从一节挪给另一节。
- 每个展开的节至少留出 `MinBodyHeight` 的主体高度。连最小高度都放不下时，各节按最小高度排，超出容器底部的部分被裁掉——**这一版不滚动**。
- 不是 `TTyExPanel` 的子控件（比如一条工具栏、一条分隔线）保持自己的高度，宽度同样拉满。
- 展开状态和权重可以存成一行字符串、再恢复（第 7 节）。

容器接管各节的高度：放进来的 `TTyExPanel` 切换 `Collapsed` 时不再自己改 `Height`，而是由容器重新分配；过渡动画的时长取被切换那一节的 `AnimationDuration`。各节的 `OnExpand` / `OnCollapse` 照常触发，仍是应用自己的事件。

典型用途：资源管理器里的「文件夹 / 大纲」、调试侧栏里的「变量 / 监视 / 调用栈 / 断点」。

---

## 2. 单元与 typeKey

| 项目 | 值 |
|------|-----|
| 单元 | `tyControls.Accordion` |
| 容器 typeKey | `TyAccordion` |
| 拖动条 typeKey | `TyAccordionSplitter`（支持 `:hover`、`:active`） |
| 基类 | `TTyCustomAccordion`（继承自 `TTyCustomControl`） |
| 默认尺寸 | 200 × 300 |
| 组件面板 | TyControls Containers |

```pascal
uses tyControls.Accordion, tyControls.ExPanel;
```

| 令牌 | 默认 | 说明 |
|------|------|------|
| `--accordion-splitter-size` | `4px` | 拖动条的粗细。 |
| `--accordion-min-body-height` | `48px` | 没设 `MinBodyHeight` 时，展开的节至少留出的主体高度。 |

两个令牌都可以写在主题里，也可以写在这一个容器的 `StyleOverride` 里（`--accordion-splitter-size: 6px;`）。

---

## 3. 排布规则

1. **顺序**是子控件的创建顺序（`Controls[]` 的顺序，也就是 `.lfm` 里的先后），不看各节当前的 `Top`。运行时用 `MoveSection` 调整；设计期见第 8 节。
2. **宽度**：每个子控件都拉满容器的内宽。子控件自己的 `Align` / `Anchors` 不起作用。
3. **高度**：
   - 不是 `TTyExPanel` 的子控件：自己的 `Height`。
   - 折叠的节：标题栏高度。
   - 展开的节：容器高度减去上面两类、再减去拖动条之后，按 `ExpandedHeight` 的比例分。各节高度加起来正好等于可分的高度，不会多一像素或少一像素。权重只看比例，`100 : 300` 和 `1 : 3` 一样；小于 1 的按 1 算。
4. **最小高度**：展开的节不低于「标题栏 + `MinBodyHeight`」。按比例分到的不够，就给它最小高度，其余的节分剩下的。
5. **拖动条**只出现在**紧挨着的两个展开的节**之间。中间隔着折叠的节或别的控件时没有拖动条。
6. `Visible = False` 的子控件不参与排布，重新显示后回到原来的位置。
7. 容器有边框时（主题给 `TyAccordion` 写了 `border-width`），各节排在边框以内。

> 想让某一节占得多一点，设它的 `ExpandedHeight`，不是 `Height`——在容器里 `Height` 由容器说了算。新建的 `TTyExPanel` 的 `ExpandedHeight` 都是 140，所以默认各节等分。

---

## 4. 属性、方法、事件

### published

| 成员 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `MinBodyHeight` | `Integer` | 跟随主题（48） | 展开的节至少留出的主体高度，逻辑像素。设了就存进 `.lfm`；设成负数表示交还给主题令牌。 |
| `OnLayoutChanged` | `TNotifyEvent` | `nil` | 布局变了：某一节折叠或展开、用户拖完一条边界、`LoadLayoutFromString` 应用了一份布局。拖动过程中不触发，松开时触发一次。适合在这里保存布局。 |
| `Align` / `Anchors` / `BorderSpacing` / `BorderWidth` / `Constraints` / `Enabled` / `Visible` / `StyleClass` / `StyleOverride` / `Controller` … | | | 通用成员。`TabStop` 默认 `False`：容器自己不拿焦点。 |

### public

| 方法 | 说明 |
|------|------|
| `SectionCount` / `Section(AIndex)` | 各节（`TTyExPanel` 子控件），按堆叠顺序，包括隐藏的。 |
| `FindSection(AName)` | 按组件名找一节；没有或有重名时返回 `nil`。 |
| `NeighbourSection(ASection, AForward)` | 堆叠里下一个（或上一个）可见且可用的节。 |
| `MoveSection(AChild, AIndex)` | 把子控件挪到 `Controls[]` 的第 `AIndex` 个并重新排布。 |
| `SplitterCount` / `SplitterRect(AIndex)` / `SplitterAt(X, Y)` / `Splitters` | 此刻的拖动条：数量、矩形（客户区坐标）、某一点落在哪一条上（没有是 -1）。 |
| `MoveSplitter(AIndex, ADelta)` | 把第 `AIndex` 条边界移动 `ADelta` 像素（向下为正），效果和用户拖动一样：受最小高度限制，两节的权重都更新。可以用它做键盘调整。 |
| `LayoutSections` | 立即重新排布。一般不用调：LCL 在容器或子控件变化时会请它。 |
| `StackRect` | 排布用的区域（客户区去掉边框）。 |
| `Animating` | 是否正在过渡到新的分配。 |
| `SaveLayoutToString` / `LoadLayoutFromString` | 见第 7 节。 |

### protected（给派生类）

| 方法 | 说明 |
|------|------|
| `SectionMinHeight(ASection)` | 一节展开时的最小高度（设备像素）。覆盖它可以给不同的节不同的下限；分配和拖动问的是同一处。 |
| `FocusSection(ASection)` | ↑ / ↓ 把焦点送到哪里。 |
| `DoLayoutChanged` | 触发 `OnLayoutChanged`。 |
| `CanAnimate` | 是否做过渡动画（没有窗口句柄时、设计期不做）。 |

---

## 5. 拖动边界

鼠标移到拖动条上，光标变成上下调整的样式，拖动条按 `TyAccordionSplitter:hover` 绘制；按住拖动时按 `:active` 绘制。

- 拖动只改这条边界两侧的两节，别的节不动。
- 两节都不会被拖到最小高度以下。
- 拖动开始时，所有展开的节的 `ExpandedHeight` 会换成它们此刻的像素高度（折叠的节按同一比例换算），之后拖多少像素权重就变多少。所以拖完以后看到的高度就是存下来的权重，容器变高变矮时各节按这个比例一起伸缩。
- 松开鼠标时触发一次 `OnLayoutChanged`。

---

## 6. 键盘

容器自己不是 Tab 停靠点。把各节的 `TabStop` 设为 `True` 后：

- Tab 依次走到各节的标题栏（以及节里的控件）。
- 焦点在某一节的标题栏上时，↑ / ↓ 移到上一节 / 下一节的标题栏，跳过隐藏和禁用的节；到头了焦点留在原地。
- 空格、回车、← / → 由标题栏自己处理（见 [TTyExPanel](expanel.md) 第 7 节）。

---

## 7. 保存和恢复布局

```pascal
// 保存
Settings.WriteString('Explorer', 'Sections', Accordion1.SaveLayoutToString);

// 恢复（窗体建好之后）
Accordion1.LoadLayoutFromString(Settings.ReadString('Explorer', 'Sections', ''));
```

保存出来是一行文字：

```
TYACCORDION/1|Folders=240,0|Outline=120,1|end
```

每一节一段：`组件名=权重,是否折叠`。开头是格式名和版本号，结尾是 `end`。

- **按组件名对应**（不区分大小写）。没有名字的节、和另一节重名的节不保存。
- **恢复时**：串里有、容器里没有的名字忽略；容器里有、串里没有的节保持现状。所以以后增删了节，旧的布局串照样能用。
- **格式不对**（被截断、版本不同、数字不合法、名字重复……）时 `LoadLayoutFromString` 返回 `False`，什么都不改，也不抛异常。开头的 UTF-8 BOM 和结尾的空白、换行会被容忍，方便直接从文件或 `TStringList.Text` 里读。
- 设计期调用返回 `False`。
- 恢复时不做动画；各节的 `OnExpand` / `OnCollapse` 随状态变化触发，`OnLayoutChanged` 在最后触发一次。

`TTyToolWindowManager` 的布局串是同一套约定。

---

## 8. 设计器里使用

1. 从「TyControls Containers」页放一个 `TTyAccordion`，再往里放几个 `TTyExPanel`。
2. 各节按放进去的先后从上到下排。**调顺序**：把一节拖到另一节的位置上，松手后它就排到那里。
3. **调权重**：拉一节的下边框改它的高度，这个高度就成了它的权重（其余各节按当前高度折算），随后整栈按新的比例重排。
4. 想要「一整块表面」的外观，把各节的 `StyleClass` 设为 `embedded`。
5. 各节标题栏上的按钮：往节里放一个 `TTyExPanelActions`，再往它里面放按钮。

`.lfm` 里保存的是各节的先后顺序、各自的 `Collapsed` 和 `ExpandedHeight`（在容器里，展开的节也会存 `ExpandedHeight`）。

---

## 9. 主题

```css
/* 内置 */
TyAccordion {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 0;
  border-radius: 0;
  padding: 0;
}
TyAccordionSplitter        { background: none; }
TyAccordionSplitter:hover  { background: var(--border); }
TyAccordionSplitter:active { background: var(--accent); }
```

- `TyAccordion`：容器的底和边框。内置没有边框，因为它通常铺满一个已经有边框的侧栏。
- `TyAccordionSplitter`：拖动条。只读 `background`；静止时不画，露出容器的底色。
- 各节自己的外观是 `TyExPanel` / `TyExPanelHeader` 的事。

---

## 10. 代码示例

```pascal
uses
  tyControls.Accordion, tyControls.ExPanel, tyControls.TreeView;

procedure TMainForm.BuildExplorer;
var
  Sec: TTyExPanel;
begin
  Explorer := TTyAccordion.Create(Self);
  Explorer.Parent := SidePanel;
  Explorer.Align := alClient;
  Explorer.OnLayoutChanged := @ExplorerLayoutChanged;

  Sec := TTyExPanel.Create(Self);
  Sec.Name := 'Folders';
  Sec.Caption := '文件夹';
  Sec.StyleClass := 'embedded';
  Sec.TabStop := True;
  Sec.ExpandedHeight := 300;        // 权重：占三份
  Sec.Parent := Explorer;
  FolderTree.Parent := Sec;
  FolderTree.Align := alClient;

  Sec := TTyExPanel.Create(Self);
  Sec.Name := 'Outline';
  Sec.Caption := '大纲';
  Sec.StyleClass := 'embedded';
  Sec.TabStop := True;
  Sec.ExpandedHeight := 100;        // 占一份
  Sec.Parent := Explorer;
  OutlineTree.Parent := Sec;
  OutlineTree.Align := alClient;

  Explorer.LoadLayoutFromString(Settings.ExplorerLayout);
end;

procedure TMainForm.ExplorerLayoutChanged(Sender: TObject);
begin
  Settings.ExplorerLayout := Explorer.SaveLayoutToString;
end;
```

---

## 11. 注意事项

1. **不滚动**。各节的最小高度加起来超过容器高度时，下面的节被裁掉。需要滚动的话把内容放进各节里的 `TTyScrollBox`，或者减小 `MinBodyHeight`。
2. **节的 `Height` 归容器管**。代码里给容器里的节设 `Height` 不起作用，下一次排布就被改回去；要改比例请设 `ExpandedHeight`。
3. **顺序看创建顺序**，不看 `Top`。运行时新建的节排在最后，用 `MoveSection` 挪。
4. **过渡动画**只在有窗口句柄的运行期做；没有句柄（比如单元测试）或 `AnimationDuration = 0` 时一步到位。
5. 容器不会替各节设置 `StyleClass`、`TabStop`，这些由你决定。
6. 把一节从容器里拿出来（改 `Parent`）以后，它又变回自己管高度的普通折叠面板。
