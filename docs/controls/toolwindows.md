# 工具窗口：TTyToolWindowBar / TTyToolWindowManager

## 1. 概述

IDE 式的侧栏和底栏。侧栏一侧只显示一个工具窗口，靠图标条切换；底栏是一排文字标签，标签右边放当前页自己的操作区（筛选框、清除、新建终端之类）。左右侧栏之间可以互相拖动工具窗口，底栏只能在栏内调顺序。

四个类：

| 类 | 作用 | 设计器里 |
|---|---|---|
| `TTyToolWindowBar` | 贴一条边的栏：侧栏有图标条，底栏有标签行；切页、收起、拉宽、调顺序 | 组件面板「TyControls Containers」页 |
| `TTyToolWindow` | 一页工具窗口：上面标题行，下面正文 | 没有面板按钮，用栏的右键「新建工具窗口」 |
| `TTyToolWindowActions` | 窗口的操作区，排在标题行右端（底栏排在标签行右端） | 没有面板按钮，用窗口的右键「添加操作区」 |
| `TTyToolWindowManager` | 不可见组件，可以不放：跨侧拖动、`MoveWindow`、布局保存 | 组件面板「TyControls Containers」页 |

单元：栏、窗口、操作区在 `tyControls.ToolWindows`，manager 在 `tyControls.ToolWindows.Manager`。

### 摆法

栏就是普通的 `Align` 控件：`Placement` 选左、右、底，`Align` 跟着变。底栏横跨整个窗口还是只在编辑区下面，由布局决定：把编辑区和底栏一起放进一个 `alClient` 的容器，底栏就只在编辑区下面（VS Code 默认的样子）。

```
object LeftBar: TTyToolWindowBar          { Placement 默认 twpLeft }
  Manager = ToolMgr
  object ExplorerWin: TTyToolWindow
    Caption = 'Explorer'
    ImageName = 'files'
  end
end
object EditorHost: TTyPanel
  Align = alClient
  object BottomBar: TTyToolWindowBar
    Placement = twpBottom
    Align = alBottom
    Manager = ToolMgr
    object OutputWin: TTyToolWindow
      Caption = 'Output'
    end
  end
  object EditorMemo: TTyMemo
    Align = alClient
  end
end
object ToolMgr: TTyToolWindowManager
end
```

## 2. typeKey 与 token

| typeKey | 用途 |
|---|---|
| `TyToolWindowBar` | 栏底色 |
| `TyToolWindowStrip` | 图标条底色，靠内容区一侧的界线（border-color / border-width） |
| `TyToolWindowStripItem` | 图标格；`:hover` `:selected` `:active` `:disabled` |
| `TyToolWindowStripIndicator` | 当前图标旁的指示条 |
| `TyToolWindowEdge` | 拉宽边，也是贴着编辑区的分隔线；`:hover` `:active` |
| `TyToolWindow` | 窗口正文底色 |
| `TyToolWindowHeader` | 侧栏标题行：底色、标题墨色和字体、可选底线（border-color + border-width） |
| `TyToolWindowActions` | 操作区底色 |
| `TyToolWindowTabRow` | 底栏标签行底色 |
| `TyToolWindowTab` | 底栏标签；`:hover` `:selected` `:disabled` |
| `TyToolWindowTabIndicator` | 当前标签的下划线 |
| `TyToolWindowOverflow` | 溢出按钮（图标条和标签行共用） |
| `TyToolWindowButton` | 底栏的最大化 / 还原、收起按钮 |
| `TyToolWindowSeparator` | 底栏标题行里固定按钮前的竖线（border-color + border-width） |
| `TyToolWindowDropIndicator` | 拖放插入线 |
| `TyToolWindowNote` | 设计期提示（孤儿窗口、没有窗口、Placement 冲突、多余操作区、非窗口子控件） |

颜色 token（light.tycss 里的默认值）：

| token | 默认 |
|---|---|
| `--toolwindow-bg` | `var(--surface)` |
| `--toolwindow-ink` | `var(--on-surface)` |
| `--toolwindow-header-bg`（标题行、操作区、标签行共用） | `var(--toolwindow-bg)` |
| `--toolwindow-caption-ink` | `var(--on-surface)` |
| `--toolwindow-tab-ink` / `--toolwindow-tab-ink-selected` | `var(--muted)` / `var(--on-surface)` |
| `--toolwindow-indicator-color` | `var(--accent)` |
| `--toolwindow-strip-bg` | `var(--chrome-bar-bg)` |
| `--toolwindow-strip-ink` / `--toolwindow-strip-ink-selected` | `var(--muted)` / `var(--on-surface)` |
| `--toolwindow-strip-indicator-color` | `var(--accent)` |
| `--toolwindow-edge-color` / `--toolwindow-edge-color-hover` | `var(--border)` / `var(--accent)` |
| `--toolwindow-overlay-hover` / `--toolwindow-overlay-active` | `var(--overlay-hover)` / `alpha(var(--on-surface), 0.20)` |
| `--toolwindow-drop-color` | `var(--accent)` |

长度 token（密度块，现代密度另有一套值）：`--toolwindow-header-height`、`-header-pad`、`-header-gap`、`-tab-pad`、`-tab-area-min`、`-indicator-size`、`-strip-indicator-size`（0 = 不画）、`-button-size`、`-glyph-size`、`-content-min`、`-strip-size`、`-strip-item-size`、`-edge-size`、`-drop-size`。

皮肤一般只调 token，不用重写基础规则。

## 3. 属性与方法

### TTyToolWindowBar

| 成员 | 说明 |
|---|---|
| `Placement` | `twpLeft`（默认）/ `twpRight` / `twpBottom`。改它顺带把 `Align` 设成对应值、把栏挪到父控件同侧的最外边。运行时栏里有窗口时，侧 ↔ 底的改动被忽略 |
| `ExpandedSize` | 展开时沿栏轴向的内容尺寸，**96 DPI 下的逻辑像素**，默认 240。侧栏不含图标条和拉宽边，底栏含标签行。空间不够时这一次排布会收窄，但不写回它 |
| `Collapsed` | 收起（默认 False）。只在运行时生效，设计期永远按展开显示。侧栏收起后剩图标条，底栏高度变成 0 |
| `ActiveIndex` / `ActiveWindow` | 当前页。`ActiveIndex` 跟着窗口走：调顺序后当前页还是那个窗口，序号跟着变。代码设当前页不改 `Collapsed` |
| `Manager` | 指向 `TTyToolWindowManager`（属性类型是基类 `TTyCustomToolWindowManager`） |
| `Images` | 图标列表；为空时回落到 `Manager.Images` |
| `Maximized` | 底栏最大化（public，不进 .lfm，也不进布局串） |
| `Windows[i]` / `WindowCount` / `IndexOfWindow(W)` | 窗口列表，顺序就是 `Controls` 顺序 |
| `WindowAtPos(X, Y)` / `ContextWindow` | 某点下的图标 / 标签对应的窗口；最近一次右键落在哪个窗口上（不在图标或标签上是 nil） |
| `OnChange` / `OnCollapse` / `OnExpand` | 见 §4 |

### TTyToolWindow

| 成员 | 说明 |
|---|---|
| `Caption` | 侧栏是标题行里的标题，底栏是标签文字 |
| `ImageName` / `ImageIndex` | 图标条上的图标。`ImageName` 是持久键，`ImageIndex` 是它的视图 |
| `StripHint` | 图标和标签的提示，空的时候用 `Caption`。类型是 `TTranslateString`，窗体的 .po 能翻译它 |
| `WindowIndex` | 在栏里排第几，可写（写 = 调顺序）；不进 .lfm |
| `Bar` / `IsActive` / `Actions` / `EnsureActions` | 所在的栏；是不是当前页；第一个操作区；没有就建一个 |
| `FocusFirst` | 把焦点给正文里第一个能聚焦的控件（跳过操作区） |
| `OnShow` / `OnHide` | 这一页显示 / 藏起 |

### TTyToolWindowActions

只有 `Controller`（不进 .lfm，对象查看器里藏着）和通常的外观属性。位置和尺寸由窗口排，`Align` 钉死在 `alCustom`，子控件由它自己从左往右排成一排、垂直居中。

### TTyToolWindowManager

| 成员 | 说明 |
|---|---|
| `MoveWindow(W, 目标栏, 序号 = -1)` | 把窗口挪到另一条栏（或同一条栏里调顺序）。-1 = 末尾。答 False 表示什么都没改 |
| `CanMoveWindow(W, 目标栏)` | 结构检查 + `OnCanMoveWindow`，没有副作用 |
| `UsableBar(Placement)` | 此刻这一侧的可用栏；没有答 nil。「移到另一侧」就问它要目标 |
| `IsBarUsable(栏)` | 这条栏可不可用（见 §9 Placement 冲突） |
| `CancelDrag` / `IsDragging` | 取消此刻的图标拖动；有没有在拖 |
| `SaveLayoutToString` / `LoadLayoutFromString` / `ResetLayout` / `CaptureDefaultLayout` | 见 §6 |
| `Images` | 两侧共用的图标列表 |
| `OnCanMoveWindow` / `OnWindowMoved` / `OnLayoutApplied` | 见 §4 |

## 4. 事件

| 事件 | 什么时候发 | 不发 |
|---|---|---|
| 栏 `OnChange` | 运行时当前页换了窗口（点击、代码、`MoveWindow`、直接改 Parent、当前页离开本栏） | 设计期；加载中和 `Loaded`；布局应用；只是调顺序 |
| 栏 `OnCollapse` / `OnExpand` | 运行时 `Collapsed` 真的变了 | 设计期；加载中；布局应用 |
| 窗口 `OnShow` / `OnHide` | 运行时显示 / 藏起（切页、收起、展开）；普通的布局读取里照发 | 设计期；启动时栏在 `Loaded` 里显示的那一页；加载结束时应用挂起布局的那一批（见下） |
| manager `OnCanMoveWindow` | 跨栏：拖到某条栏上、松开、调 `MoveWindow`、排队的移动执行前 | 同栏调顺序；直接改 Parent；布局应用；设计期 |
| manager `OnWindowMoved` | 运行时窗口的栏或序号真的变了：手势、`MoveWindow`、`WindowIndex`、同一 manager 下直接改 Parent | 加载中；设计期；读布局 / 恢复默认 |
| manager `OnLayoutApplied` | `LoadLayoutFromString` / `ResetLayout` 应用完一次；挂起布局在加载结束时应用的，推迟到加载结束之后（排进消息队列）再发 | — |

**挂起的布局**：还在加载中（frame 刚建出来、继承窗体、某个 `Loaded` 里）就调 `LoadLayoutFromString` / `ResetLayout`，布局先存着，等 manager 和所有栏都加载完再应用。这时窗体的 `OnCreate` 还没跑，所以这一批当作流式加载的一部分：窗口的 `OnShow` / `OnHide` 一个都不发，`OnLayoutApplied` 推到加载结束之后才发。处理器里就能放心用 FormCreate 里才建的对象。

`MoveWindow` 的发送顺序：源栏 `OnChange`（窗口原来是当前页时）→ 目标栏 `OnExpand`（原来收起时）→ 目标栏 `OnChange` → `OnWindowMoved`。都在窗口挪好、焦点还回去之后发。

## 5. 跨侧拖动与 MoveWindow

- 侧栏图标可以拖到同一个 manager、同一个窗体上的另一侧栏；底栏标签只能在底栏里调顺序。侧栏和底栏之间不能互拖。
- 拖到目标栏的图标条上，插入线停在指针处；拖到目标栏别的地方，插入线停在最后一个图标后面。别处是禁止光标，松开就是取消。拖动中按 Esc 也取消。
- `OnCanMoveWindow` 里把 `AAllow` 设成 False 就能否决：拖到那条栏上时不画插入线，显示禁止光标。
- 没有 manager 的栏只能栏内调顺序。

**排队**：窗体已经显示时，跨栏的 `MoveWindow` 不当场做，而是排到消息循环里（返回 True 表示「已接受」）。这是为了让操作区里的按钮能移动自己所在的窗口：同步换父会在按钮自己的点击处理里销毁它的句柄。所以**排队时 `MoveWindow` 返回之后 `W.Bar` 还是旧栏**，挪好了会发 `OnWindowMoved`。FormCreate 里调、设计期调、同栏调顺序都是同步的；只有一个例外：这个窗口还有排着的移动时，同栏调顺序也排进队列，按调用的先后执行。

## 6. 布局保存

| 方法 | 说明 |
|---|---|
| `SaveLayoutToString` | 每一侧的尺寸、是否收起、窗口顺序、当前页，存成一行字符串 |
| `LoadLayoutFromString(S)` | 读回来。答 False 就是什么都没改，不抛异常：格式不对；设计期；manager 上还没有注册任何栏；在 manager 的事件处理器里（`OnCanMoveWindow`、`OnWindowMoved`、`OnLayoutApplied`，以及跨栏移动时发的栏事件和窗口 `OnShow` / `OnHide`）；在应用布局的那一批里（某一页的 `OnShow` / `OnHide`） |
| `ResetLayout` | 回到默认布局（从 .lfm 加载的，就是 .lfm 里的样子）。答 False 的情形同上，只是没有格式这一条 |
| `CaptureDefaultLayout` | 把此刻的样子记成默认布局 |

**在 FormCreate 里读**用户上次的布局，在 FormClose（或 OnDestroy 之前）存：

```pascal
procedure TMainForm.FormCreate(Sender: TObject);
var
  sl: TStringList;
begin
  if not FileExists(LayoutFile) then Exit;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(LayoutFile);
    // TStringList.Text 末尾多出来的换行 LoadLayoutFromString 自己会去掉
    ToolMgr.LoadLayoutFromString(sl.Text);
  finally
    sl.Free;
  end;
end;
```

布局串长这样：

```
TYTOOLLAYOUT/1|left=240,0|leftWins=Explorer,Search|leftActive=Explorer|right=300,1|rightWins=Outline|rightActive=Outline|bottom=200,0|bottomWins=Problems,Output|bottomActive=Output|end
```

窗口按 `Name` 认，不分大小写。程序改版以后读旧布局：

- 布局里有、程序里没有的窗口：丢掉。
- 程序里有、布局里没有的新窗口：留在设计时那一侧，排在后面。
- 改了名的窗口当成新窗口，原来的位置丢了。翻译 `Caption` 不影响布局。
- 名字记在另一类栏下（侧栏的窗口出现在 bottom 组里）：当成新窗口。

不保存的：底栏最大化；窗口里的内容（筛选框文字、终端会话、滚动位置）。

## 7. 设计器里使用

- 从「TyControls Containers」页放一条栏和一个 manager 到窗体上，栏的 `Manager` 指向它。在对象查看器里改 `Placement`，栏自己挪到那一边。
- **栏的右键菜单**
  - 「新建工具窗口」：建一个窗口放进栏里，成为当前页，名字和标题一样。`Ctrl+Z` 能撤掉。
  - 「显示窗口 ▸」：列出所有窗口，挑一个切过去并选中它。
- **窗口的右键菜单**（三项固定，不适用的灰掉）
  - 「添加操作区」：给窗口建一个操作区，往里拖按钮、筛选框。已经有了就灰掉。
  - 「移到另一侧栏」：只有侧栏窗口能用，另一侧要有同一个 manager 下的可用栏。能 `Ctrl+Z`，但窗口回到原来那条栏时排在最后、成为当前页，原来的位置不还原。
  - 「移回栏里 ▸」：只有孤儿窗口（见下）能用，挑一条栏放回去。`Ctrl+Z` 把它放回原来的父控件，又成了孤儿。
- 在 frame 实例里，新建、添加、移动这几项都是灰的；另一侧那条栏在 frame 实例里（它挂在窗体的 manager 上）时，「移到另一侧栏」也是灰的；继承来的窗口不能「移到另一侧栏」，但可以往继承来的栏里新建窗口、往继承来的窗口里添加操作区。
- 设计期点图标（侧栏）或标签（底栏）就切页，对象查看器里的 `ActiveIndex` 跟着变。
- 在对象查看器的组件树里选中一个藏着的窗口，多半不会切过去：照 Lazarus 源码看，设计器选中控件时不调 `ShowControl`（以真机为准）。要切页，用栏的「显示窗口 ▸」或者点它的图标。
- **孤儿窗口**：不在栏里的窗口。删掉一个窗口再 `Ctrl+Z`，它会被建到**窗体**上（Lazarus 撤销时只找窗体的直接子控件）。设计期它铺满父控件，顶上一行写着「不在工具窗口栏里，运行时隐藏」；右键「移回栏里 ▸」放回去。运行时孤儿一直藏着。
- **Placement 冲突**：同一个 manager 下有两条栏 `Placement` 相同时，两条栏底部都会出现一行「与另一条栏的 Placement 相同」，改成不同的 `Placement` 就消失。
- **粘贴要先选中栏**：侧栏点图标条，底栏点标签行后面的空白处或拉宽边。选中的是当前页窗口的正文时，粘贴会落进窗口里。
- 窗口和操作区在对象查看器里没有 `Controller`，它们用栏的。

## 8. 流式化

```
object BottomBar: TTyToolWindowBar
  Placement = twpBottom
  Align = alBottom
  ExpandedSize = 200
  ActiveIndex = 1
  Manager = ToolMgr
  object ProblemsWin: TTyToolWindow
    Caption = 'Problems'
  end
  object OutputWin: TTyToolWindow
    Caption = 'Output'
    object OutputActions: TTyToolWindowActions
      object BtnClear: TTySpeedButton
        ...
      end
    end
    object OutputMemo: TTyMemo
      Align = alClient
    end
  end
end
```

- 窗口的 `Left`、`Top`、`Width`、`Height`、`TabOrder`、`Visible`、`Controller` 不进 .lfm；栏沿轴向的那一边（侧栏的 `Width`、底栏的 `Height`）也不进，由 `ExpandedSize` 推出来。
- 窗口顺序就是它们在 `Controls` 里的顺序，也就是 .lfm 里的先后。

## 9. 注意事项

- `Controller` 由栏推给窗口、窗口再推给操作区。代码里直接赋给窗口的值会被下一次推送盖掉，要换主题请设栏的 `Controller`。
- 图标条的提示跟着栏的 `ShowHint`，底栏标签的提示跟着各窗口的 `ShowHint`。提示文字用 `StripHint`，**不要用 `Hint`**：窗口的 `Hint` 会冒到它里面所有没设 `Hint` 的控件上。
- 要禁用一页，禁用正文里的控件，**不要禁用 `TTyToolWindow` 本身**。底栏的标签行由当前页接收输入，当前页禁用后标签、溢出、最大化、收起都会失灵。
- 操作区上的 `AutoSize`、`ChildSizing`、`BorderSpacing` 不起作用。
- 启动时显示出来的当前页收不到 `OnShow`。首次填充内容请放在 FormCreate 里。
- `OnExit` 里不要把焦点设回被藏起来的窗口里的控件。
- 底栏收起后界面上没有入口（侧栏至少还有图标条），请自己给一个开关：菜单项或快捷键设 `Collapsed := False`。示例里是 View › Bottom Panel（`Ctrl+J`）。
- 事件处理器里不要释放栏、窗口或 manager，要释放请用 `Application.ReleaseComponent`。
- 只设了 `ImageIndex`、没设 `ImageName` 的窗口要在两侧之间移动，就得用 manager 上的共享列表。只在 manager 上设列表时，对象查看器里 `ImageIndex` 的下拉是空的（它只看栏自己的 `Images`），这时请设 `ImageName`。
- 拖动中按 Esc 只吃掉 KeyDown，Esc 的 KeyUp 照样会到焦点控件。
- 排队时 `MoveWindow` 返回之后 `W.Bar` 还是旧栏（§5）。
- 窗体显示之后调的 `LoadLayoutFromString` / `ResetLayout` 也会排队；排着的布局执行时会盖掉这段时间里的同步改动，也会顶掉已经排着的移动。
- 跨栏移动（`MoveWindow`、拖放、读布局、恢复默认）会重建窗口里所有控件的句柄：输入法组字、光标位置、原生子窗口的状态都不保留。
- 改了名的窗口当成新窗口（§6）；翻译 `Caption` 不影响布局。
- `Bar.Manager` 是基类类型。经它调 `MoveWindow` 或布局方法要转型成 `TTyToolWindowManager`，或者直接用窗体上的 manager 字段；用到 manager 的单元要 uses `tyControls.ToolWindows.Manager`。
- 继承窗体上读用户布局，请在 FormCreate 里调：祖先层加载中调的会被子孙层流进来的值盖掉。
- 同一个 manager 下 `Placement` 相同的栏都不可用：不参与跨栏拖动、`MoveWindow` 和布局保存，栏内调顺序照常。
- 不支持：manager 放在数据模块里、栏分布在多个窗体上。
- 删掉一个工具窗口或操作区后撤销 / 重做，它会被建到**窗体**上：窗口显示成孤儿，右键「移回栏里 ▸」；操作区用 IDE 的「改变父控件」放回窗口。

## 10. 和 VS Code / JetBrains 的差异

- 两侧都有图标条（VS Code 右侧栏用标题行里的标签切换）。
- 侧栏和底栏之间不能互拖（VS Code 三处互通）。
- 图标和标签都在松开时切换，不在按下时。
- 拖空的侧栏保留图标条（VS Code 整块藏起来）。
- 一侧只显示一个窗口，不做上下 / 左右分屏（JetBrains 可以）。
- 不做：边缘靠近弹出、图标 / 标签上的数字徽标、每个窗口各记一个尺寸、键盘操作图标条、浮动 / 独立窗口、跨窗体拖动、内置右键菜单、从标题行拖动窗口。

和库里其他控件的习惯也有两处不同：

- 图标和标签松开才切。库里单纯做切换的控件（`TTySegmented`、`TTyTabSet` 这类标签条、`TTyPagination`）是按下就切；这里按下之后可能是要拖，所以等松开。TreeView、Grid 的表头点击也改成了松开才算。
- `OnWindowMoved` 对 `MoveWindow`、改 `WindowIndex` 也发。Grid 的 `OnRowMove`、TreeView 的 `OnNodeMoved`、标签条的 `OnReorder` 只在手势里发；这里是想给程序一个「布局变了」的信号，比如拿来自动保存。

## 11. 示例

`examples/toolwindows`：一个类 IDE 窗体，左边 Explorer / Search，右边 Outline，编辑区下面 Problems / Output / Terminal。能跨侧拖、最大化和收起底栏、保存 / 读取 / 恢复布局（关掉再开回到上次的样子）、换肤、换密度；Output 页里是事件日志，Diagnostics 菜单用来在真机上试拖动中弹对话框、弹菜单、禁用当前页这几种情况。
