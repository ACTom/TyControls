# 控件拆出 TTyCustomXxx 验收

这是 issue #8「控件拆出 `TTyCustomXxx` 父类」五期做完后的**一次性验收**入口：一张表列出 0–4 期签收里留给「手点」与真机的全部项，后面是等你拍板的决定和发现问题怎么报。每项看完在「结果」列写 过 / 不过 / 现象。

## 这是什么，做了什么

每个控件 `TTyXxx` 拆成两层：`TTyCustomXxx` 放全部实现、属性照 LCL 的可见性放在 public / protected，`TTyXxx` 只有一段 `published`。第三方（issue #8 的 PascalSCADA）从 `TTyCustomXxx` 派生，只发布自己想露的属性。继承链照 LCL：`TTyGlyphButton` 挂在 `TTyCustomButton` 一系下，不再是 `TTyButton` 的后代。两个基类 `TTyCustomControl` / `TTyGraphicControl` 和 `TTyComponent` 不再发布任何东西。

- **0 期**：拆分前给每个注册类拍了一份 RTTI + 主题键快照（迁移期守卫，4 期末撤掉），加了常驻的结构守卫；基类不再发布，每个控件按 3.0 的 RTTI 顺序自己发布那 40–50 个通用属性。
- **1 期**：输入与显示，59 个类（按钮、标签、编辑框、选择、组合框、进度、滑块）。
- **2 期**：容器、列表、表格，42 个类；TreeView / HeaderControl 的事件 Sender 改写 Custom 类。
- **3 期**：其余可视控件，35 个类（工具条、Ribbon、窗体镶边、图像、取色、终端、工具窗口）。
- **4 期**：非可视组件 20 个（控制器、图标字体与图像列表、提示与通知、8 个对话框），`IconFont` 与图像集合的引用属性写 Custom 类（`Controller` 暂不改，见决定 F1）；文档 `docs/subclassing.md`（含「从 3.0 升级」）。

一共拆了 156 个类；不拆的 17 个（菜单 3、`TCommonDialog` 一系的对话框 11、`TTyForm` / `TTyDialog`、`TTyToolWindowManager`）各有理由写在 `tests/test.customclasses.pas` 的 `CNotSplit`；`TTyAdvanceChart`、`TTyCalendar`、`TTyDateTimePicker` 等 AdvChart 分支合进来后再拆。

**用户能感到的**：`.lfm` 一个字不用改，主题不用改，每个控件的属性名、默认值、写出顺序、默认尺寸、主题键都跟 3.0 一样。要改的是代码里 `X is TTyButton` 这类判断、TreeView 等事件处理过程的签名、几个属性与返回值的类型——全部列在 `docs/subclassing.md` 的「从 3.0 升级」。这是 4.0 的不兼容变化，3.0 作为 LTS 不受影响。

## 准备

- **装包**：用本分支的 `tycontrols.lpk`、`tycontrols_dt.lpk` 重建 IDE（第 1–4、20–25 项要在 IDE 里看）。验收完记得装回 main 的包。
- **示例**：`lazbuild -B examples/<名字>/*.lpi`。要手点的是 `controls`、`toolbar`、`grid`、`containers`、`tabcontrol`、`treeview`、`shell`、`inputs`、`ribbon`、`toolwindows`、`terminal`、`rtl`、`icons`、`dialogs`。
- **对照**：第 2、4 项要和 main 比，另开一个装着 main 包的 Lazarus（或验完一项换一次包）。
- **顺序建议**：先 IDE 里的项（1–4、20–25），再示例（5–19），最后读文档（26–27）。除注明的外都在 Windows（Win32）上做；拆分不碰平台代码，Linux / macOS 只做第 28 项抽查。

## 验收表

「期（出处）」是这一项出自哪一期、签收或计划里的编号。

| # | 期（出处） | 验什么 | 平台 | 怎么操作 | 期望 | 结果 |
|---|---|---|---|---|---|---|
| 1 | 计划（用户验收 1） | 组件面板 | Win32（IDE） | 装上本分支两个包，翻一遍面板 | 组数、每组里的控件、顺序、图标与 main 一样 |  |
| 2 | 计划（用户验收 2） | 对象查看器 | Win32（IDE） | 任挑十个控件放到窗体上（含 Edit、ComboBox、PageControl、TreeView、StringGrid、ToolBar、Ribbon、GlyphButton、LucideImageList），与 main 并排看属性页 | 属性名、顺序、默认值是否加粗都一样 |  |
| 3 | 4 期（A28-2，用户验收 2） | Lucide 图标浏览器 | Win32（IDE） | 窗体上放一个 `TTyLucideIconFont`、一个 `TTyLucideImageList`，分别右键「图标浏览器…」；在列表上挑两个图标 | 都打开浏览器；字体上挑的名字进剪贴板；列表上挑的追加进 `Names` |  |
| 4 | 4 期（A28-3） | GlyphName 下拉 | Win32（IDE） | 放一个 `TTyCharImage`（或 `TTyGlyphButton`），`IconFont` 指向 `TTyLucideIconFont`，点 `GlyphName` 的下拉和「...」 | 下拉列出 Lucide 的两千多个名字；「...」打开图标浏览器，选中的名字写回 |  |
| 5 | 1 期（A2-4） | 工具条示例的按钮 | Win32 | `toolbar` 示例里点一个 GlyphButton、一个 ToolButton | 状态栏显示按钮标题，不弹异常 |  |
| 6 | 1 期（A4-2） | 网格计算列 | Win32 | `grid` 示例打开计算列的编辑器 | 编辑器里的字是红的 |  |
| 7 | 1 期（期末修复） | 新编辑框的文字 | Win32（IDE） | 往窗体上拖一个 `TTyEdit` | 文字是空的（不是控件名 `TyEdit1`） |  |
| 8 | 2 期 | 滚动框与视口 | Win32 | `containers` 示例看 ScrollBox 页 | 视口（`TTyScrollContent`，从 `.lfm` 读入）正常显示、能滚动 |  |
| 9 | 2 期（期末修复） | shell 树与列表 | Win32 | `shell` 示例：树与列表都有图标；在树里换目录 | 列表跟着树走 |  |
| 10 | 2 期 | 页控件 | Win32 | `tabcontrol` 示例关页、删页、切页 | 状态栏标题跟着变，不弹异常 |  |
| 11 | 2 期 | 虚拟树 | Win32 | `treeview` 示例看虚拟树与多列 | 文字、图标、列都正常（事件处理过程签名改过） |  |
| 12 | 2 期（期末修复） | 颜色列表 | Win32 | `inputs` 示例的颜色列表框、颜色组合框 | 色块与名称正常，初始选中正确 |  |
| 13 | 2 期（期末修复） | 网格值筛选 | Win32 | `grid` 示例打开、关上值筛选面板几次 | 不卡、不报错 |  |
| 14 | 3 期（A20-1） | 扩展工具条 | Win32 | `toolbar` 示例里点 ToolBarEx 上的工具按钮；看「自绘按钮」那条工具条 | 点击正常；自绘按钮画出来（`OnPaintButton` 签名改过） |  |
| 15 | 3 期 | Ribbon | Win32 | `ribbon` 示例：切页、上下文页、组的对话框启动器、画廊与后台选中 | 都正常 |  |
| 16 | 3 期（期末修复） | Ribbon 最小化与 File | Win32 | `ribbon` 示例最小化、展开；点 File 打开后台 | 收起展开正常；后台打开、能选命令 |  |
| 17 | 3 期 | 窗体标题栏 | Win32 | 任一示例点最小化、最大化 / 还原、关闭 | 都正常 |  |
| 18 | 3 期 | 工具窗口 | Win32 | `toolwindows` 示例：右键图标「移到另一侧」；Outline 窗口里的移动按钮；把窗口拖到另一条栏 | 都正常；日志里有 moved |  |
| 19 | 3 期（期末修复） | 下拉的初始选中 | Win32 | `terminal` 示例的四个下拉、`rtl` 示例的按钮组 | 一打开就选在 `.lfm` 写的那一项 |  |
| 20 | 3 期 | 工具窗口栏的设计期菜单 | Win32（IDE） | 设计器里右键工具窗口栏「显示窗口」 | 子菜单列出各窗口标题 |  |
| 21 | 4 期 | 控制器的属性编辑器 | Win32（IDE） | 窗体上的 `TTyStyleController`：`ThemeName` 下拉、`Mode` 下拉、`ThemeFile` 的「...」、`StyleOverride` 的「...」；工具窗口、操作区、窗体表面的 `Controller` 在对象查看器里仍然藏着 | 与 main 一样（编辑器改挂到 Custom 类） |  |
| 22 | 4 期 | 气泡框的 StyleClass | Win32（IDE） | `TTyPopover` 的 `StyleClass` 下拉 | 列出主题里 `TyPopover` 的变体 |  |
| 23 | 4 期 | 对话框预览 | Win32（IDE） | 双击窗体上的 `TTyMessage`、`TTyInputDialog`、`TTyProgressDialog`、`TTyAboutDialog` | 都弹出预览 |  |
| 24 | 计划（用户验收 4） | 第三方包装控件 | Win32（IDE） | 照 `docs/subclassing.md` 的例子写 `TMyTagEdit` 小包装进 IDE；放到窗体上、设 `Text` 和 `ReadOnly`，存盘再打开；换一个主题 | 面板上出现；对象查看器只有 `Text`、`ReadOnly`、`OnChange` 加 LCL 根的 15 个；值都在；跟着换主题 |  |
| 25 | 计划（用户验收 3） | 现有项目 | Win32（IDE） | 打开 3 个自己的项目（或示例 `controls`、`toolbar`、`grid`、`containers`），编译运行；设计器里改一个属性存盘 | 界面、主题、行为如常；`.lfm` 的 diff 只有那一行 |  |
| 26 | 计划（用户验收 3、5） | 升级说法够不够用 | — | 自己代码里找一处 `is TTyButton` 之类的判断，照「从 3.0 升级」改 | 说法够用，一次改对 |  |
| 27 | 计划（用户验收 5） | 文档 | — | 读 `docs/subclassing.md` 与 `.en.md` 的「限制」与「从 3.0 升级」 | 能直接贴给 issue #8；读着不别扭 |  |
| 28 | 抽查 | 别的平台 | GTK2、Qt6、Cocoa | 各编一个 `controls` 示例运行；IDE 里放一个 `TTyEdit` 看对象查看器 | 与 main 一样 |  |

## 按平台的项号

- **Win32（IDE）**：1、2、3、4、7、20、21、22、23、24、25
- **Win32（示例）**：5、6、8、9、10、11、12、13、14、15、16、17、18、19
- **GTK2、Qt6、Cocoa**：28
- **不分平台（读）**：26、27

## 等你定的决定

| 编号 | 问题 | 选项 | 现在的做法 | 相关项 |
|---|---|---|---|---|
| F1 | `Controller` 属性的类型（D11）：第三方从 `TTyCustomStyleController` 派生的控制器能不能挂到控件上 | （a）改成 `TTyCustomStyleController`（照 LCL）：`ActiveController` 跟着返回 Custom 类，要放开 `TextMenu.pas` 一行（`TeController` 的返回类型）和排除单元 `Calendar.pas` 两行（`TyCalendarSizeFor` 的参数），后者单独提交给 AdvChart 会话摘取；试验 diff 在主控 scratchpad `p4/d11proto.diff`，135 行类型名替换，测试编过；（b）只改属性，`ActiveController` 里硬转回 `TTyStyleController`（对第三方控制器说类型假话，计划不允许）；（c）保持 `TTyStyleController`，文档写进限制 | （c）：4.0 首版第三方控制器挂不上 `Controller`，`docs/subclassing.md` 第 5 节写明；选（a）的话需要你批准改 `TextMenu.pas` | 21、24 |
| F2 | `TTyColorComboBox` 的下拉不读宿主的色块几何（`ColorRectWidth` / `ColorRectOffset`） | （a）当 bug 修；（b）保持（3.0 起如此） | 未改（1 期计划外发现） | 12 |
| F3 | `TTyColorListBox` / `TTyColorBox` 的 `Items` 是 published 的：IDE 存窗体时把色板名字写进 `.lfm`、颜色不存，`Style` 没写的窗体读回来色块全黑 | （a）`Loaded` 无条件按 `Style` 重建（会丢手填的 `Items`）；（b）不再发布 `Items`（改 `.lfm` 兼容，4.0 才能做）；（c）保持 | 未改（2 期计划外发现，3.0 也有） | 12 |
| F4 | Ribbon 收起时存盘，读回后展开高度只能退回主题的 Ribbon 高度 | （a）保持；（b）另存一个展开高度（改 `.lfm` 格式） | （a）（3 期期末修复） | 16 |
| F5 | `TTyLucideImageList` / `TTyLucideIconFont` 继续发布、再用 Hidden 编辑器藏掉不该改的父类属性 | （a）保持（`.lfm` 兼容）；（b）4.x 里改成不发布 | （a） | 2、3 |
| F6 | 组件编辑器留在最终类上，第三方子类没有「加页」等动作（D2） | （a）保持，文档给出自己注册的写法；（b）把实现改成认 Custom 类再注册到 Custom 类上 | （a）；图标浏览器例外，认任何 Custom 字体 / 列表 | 24 |

### 与计划不符、你可能想改的

- `Controller` 属性仍是 `TTyStyleController`（F1 选了 c），计划原来建议照 LCL 改成 Custom 类。
- 组合框弹层、`ActivePage` / `Pages[]`、工具条 `Buttons[]`、工具窗口一族交出的对象等，比计划最初写的更多地改成了 Custom 类型（第 0–3 期期末修复改定 R7-4），升级时要改的赋值比最初估的多；全部列在 `docs/subclassing.md` 7.4。
- 数值编辑框、组合框、列表框等在读窗体期间先存下索引或值、`Loaded` 时再落——这是 3.0 没有的行为，只在第三方按别的顺序发布时用得上（3.0 的窗体读入路径一字不变）。
- 编辑框、多行编辑框、组合框的 `Caption` 就是 `Text`，新放上窗体的编辑框不再把控件名写进文字（照 LCL 的 `csSetCaption` 去掉了）。
- 4 期 S28-1 用 `TTyImage` 而不是计划写的 `TTyGlyphButton` 验 Lucide 图像列表（图标按钮的 `Images` 是图像集合，不接图像列表）。

## 发现问题怎么报

- 在表里「结果」列写「不过」加一句现象；能截图就截图，放 `docs/superpowers/plans/2026-10-02-custom-classes-acceptance-shots/`，文件名带项号（如 `14-win32-toolbarex.png`）。
- 说清楚：平台和 widgetset、Lazarus 版本、示例名或自己的项目、能不能复现。
- 弹了「Unknown property」或 `EInvalidCast` 的，附上窗体文件（`.lfm`）和调用栈。

## 验收之后

- 不过的项一个问题开一个 `fix(controls): ...`，修完重跑全量。
- 决定清单定下来的改计划并在原处标注；F 项要改代码的另开任务。
- 发版时 CHANGELOG「变更」写一条并关联 #8；合 `main` 前按合并前清单查 i18n 与 README。
