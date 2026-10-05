# 主题编辑器 1 期：编辑与预览 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行方式（项目约定，优先于子技能的默认做法）**：整期**连续写完**——每个任务只写代码 + 测试并单独提交，任务之间**不编译、不跑测试**（例外只有 Task 0：基线编译、全量、生成两份金样本，这些产出要进 git）；Task 1–11 写完后在 Task 12 **一次编译**、跑本期 suite 和全量、集中修红、按 spec 逐条核代码、集中变异、期末审查、写回 spec、签收。中途不汇报、不问要不要提交。**三期做完用户一次性真机验收**：本期的真机项写在本计划末尾，Task 13 新建验收文档 `docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md`，2、3 期往里追加。
>
> **谁来做**：标 **【主控执行】** 的步骤实现 agent **不做**、直接跳过：问用户、编 `tycontrols.lpk` / `tycontrols_dt.lpk`、编 `tools/themebuilder` 以外的示例、截图、启动 GUI 冒烟。实现 agent 不编任何 `.lpk`（可以改 `.lpk` 的文件清单）。**`tools/themebuilder/themebuilder.lpi` 实现 agent 可以编**（Task 12，编法见「跑测试的固定套路」），它不依赖 `tycontrols` 包，不碰机器级包注册。
>
> **共享文件**：`source/tyControls.Base.pas`、`Painter.pas`、`StyleModel.pas`、`TextMenu.pas` 本期**不改**；`StrConsts.pas` 也不改（本期库里没有新的用户可见文字）。本期只改 spec §4 列的三处（见「需要改共享文件的地方」）。执行中发现非改不可，停下交主控，主控先问用户。

**Goal:** `tools/themebuilder/` 下能用的第一版主题编辑器：左边 SynEdit 写 `.tycss`（CSS 高亮、目录补全），右边按控件家族分页的预览立刻换上这套主题（独立控制器，明 / 暗、密度、全部禁用），问题列表带行号可跳转，新建（复制内置主题 / 极简模板）、打开、保存、最近文件、外部修改提醒，编辑器配色跟随工具自己的皮肤，中英双语。

**Architecture:** 库里只动三处：设计期 StyleOverride 对话框里「配好高亮与补全的 SynEdit」拆成不依赖 IDE 的 `TTyCssEditKit`（设计期对话框与工具共用）；`ETyCssError` 带上行列号；`ThemeLint` 加带位置、严重度、种类的 `TyLintCssEx`（位置靠在解析成功后用同一个词法器按语法走一遍记下来，解析器的数据结构不动），旧 `TyLintCss` 改为调它再只取文字、输出逐字不变。工具的每个单元以 `tb` 开头（避开测试工程搜索路径里终端示例的 `umain`）：文档模型管文件名、换行符、BOM、外部修改；问题收集把 lint 结果转成列表（丢掉底层已定义的「未定义变量」）；预览是一个 frame，控件从 `.lfm` 流进来后逐个挂上它自己的控制器，文本经一个内存主题源（带文档目录，`url()` / `@import` 按它解析）叠加在底层之上加载，失败保留上一版，加载成功后再对全部 typeKey 试解析一遍，防住「某个模式下缺变量、画的时候才抛」；主窗体是侧栏工作台（本期只有「问题」一页）+ 编辑区 + 预览区，停顿 300 ms 刷新。

**Tech Stack:** FPC 3.2.2 / Lazarus 4.4 LCL、SynEdit（Lazarus 自带包）、BGRABitmap、fpcunit（`tests/tytests.lpi`）；Python 3（`scripts/example-rsj2po.py` 等）。

**设计依据:** `docs/superpowers/specs/2026-10-01-theme-builder-design.md`（下称 spec）§9 第 1 条，细节在 §4、§5、§6、§8。

**不在本期**：种子面板、Ctrl+点击、覆盖检查、导出主题包、代码片段小窗（2 期）；AI 的一切（3 期）；侧栏的「种子」「AI」两页（2、3 期再往 `.lfm` 里加，本期不放占位）；工具的使用文档与 README（3 期末一起写）；CHANGELOG（发版时写）；合 `main`。

---

## 总目录

| 部分 | 任务 | 这一批做完能看到什么（执行时不单独验收） |
|---|---|---|
| 基线 | Task 0 | 起点、全量条数；测试工程能带上 SynEdit；lint 输出与解析错误消息的两份金样本 |
| 库里的三处 | Task 1–3 | `ETyCssError.Line / Col`；`TyLintCssEx`（旧输出逐字不变）；`TTyCssEditKit` 拆出、设计期对话框改用它 |
| 工具的底子 | Task 4–6 | 工程骨架、文档模型（换行符 / BOM / 外部修改）、设置与最近文件、新建模板、问题收集 |
| 预览 | Task 7–8 | 八页预览、独立控制器、加载与试解析、明暗 / 密度 / 全部禁用、对话框 / 菜单 / 通知 / 真窗体 |
| 主窗体 | Task 9–10 | 侧栏工作台 + 编辑区 + 预览区、新建 / 打开 / 保存 / 最近文件、问题列表与跳转、行标记、外部修改提醒、编辑器外观 |
| 双语与脚本 | Task 11 | 中英 `.po`、检查脚本认 `tools/` |
| 收尾 | Task 12 | 一次编译、全量、按 spec 逐条核、集中变异、主控编包冒烟、审查、写回 spec、签收 |
| 验收文档 | Task 13 | 新建三期共用的验收文档，写入 1 期各项 |

---

## 核实记录（写计划时读源码，2026-10-01，`feat/theme-builder` @ `39203dc7`）

**1. 设计期 CSS 编辑框（`designtime/tyControls.Design.Css.Editor.pas`，351 行）**

1. 唯一的 IDE 依赖是 interface 里的 `PropEdits`（`:14`），只为 `TTyStyleOverrideProperty = class(TStringPropertyEditor)`（`:19-23`、`:315-349`）。implementation 的 uses（`:27-32`）全是 LCL / SynEdit / 本库：`Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Graphics, Dialogs, TypInfo, SynEdit, SynEditTypes, SynCompletion, SynHighlighterCss, tyControls.*`（含 `tyControls.Dialogs` 的 `TyMessageDlg`）。
2. 「配好的 SynEdit」分散在四段：建编辑框与补全（`:126-147`：`Gutter.Visible`、`OnChange`、`OnStatusChange`、`OnKeyPress`、去掉 `eoScrollPastEol`、`TSynCssSyn`、`TSynCompletion`（`ShortCut = 16416` 即 Ctrl+Space、`EndOfTokenChr`））；离开一行时格式化该行（`EditStatusChange`，`:218-239`，用 `TyCssFormatLine`，`FFormatting` 防重入）；键入标识符字符时记下要弹补全（`EditKeyPress`，`:241-246`）；`EditChange` 后半段（`:275-292`）弹补全，`CompletionExecute`（`:295-303`）用 `TyCssCompletionItems` 填单——**它传的是整篇文本**（注释「good enough」），不是光标前的文本。`EditChange` 前半段（`:269-273`）刷新「未知属性」警告条，属对话框自己。
3. 对话框其余部分（`TTreeView` 参考列表、警告 `TLabel`、按钮、`DefaultValueFor`、`ListDblClick`、`Validate` / `Format`）留在设计期，照旧是原生 LCL 控件（设计期 IDE 内 UI，不受「自绘 UI 内不用裸 LCL」约束）。
4. 引用它的只有 `tyControls.Design.PropEditors.pas:23`（uses）与 `:713-717`（注册）；`tyControls.Design.pas:10` 注释提到它。
5. `tycontrols_dt.lpk`：`<Files>` 逐个列单元（`:18-45`），`RequiredPkgs` 已有 `SynEdit`（`:60-62`）与 `IDEIntf`；搜索路径是整个 `designtime`（`:10`）。发版守卫 `tests/test.release.pas:525` 的 `CheckDir('designtime', 'tycontrols_dt.lpk', bad)` 要求 `designtime/*.pas` 全在清单里——新单元漏了会红。
6. SynEdit（`C:\lazarus\components\synedit\`，Lazarus 4.4）提供多路钩子：`RegisterStatusChangedHandler`（`synedit.pp:1091`）、`RegisterBeforeKeyPressHandler`（`:1104`，`KeyPress` 里调，`:3278-3284`）；`OnChange` 只有一个。`TSynCssSyn` 的配色属性：`CommentAttri`、`IdentifierAttri`、`KeyAttri`、`NumberAttri`、`SpaceAttri`、`StringAttri`、`SymbolAttri`、`MeasurementUnitAttri`、`SelectorAttri`（`synhighlightercss.pas:296-311`）。行标记：`TSynEditMark`（`syneditmarks.pp:84-108`：`Line`、`ImageList`、`ImageIndex`、`Visible`）、`Editor.Marks`（`synedit.pp:995`）；整行底色：`OnSpecialLineMarkup`（`synedit.pp:1236`，`TSpecialLineMarkupEvent`）。已编好的 SynEdit 单元在 `components/synedit/units/x86_64-win64/win32`。

**2. 解析器与 `ETyCssError`（`source/tyControls.Css.Parser.pas`，568 行）**

7. `ETyCssError = class(Exception)`（`:50`），解析器里**只有一个抛出点** `TTyCssParser.Error`（`:146-150`）：`CreateFmt(rsCssErrorFrame, [AMsg, ATok.Line, ATok.Col, ATok.Text])`；所有语法错误（`Expect` `:152-157`、未知伪类 `:176`、未闭合块 `:311` / `:362` / `:442`、`@import` 位置 `:388` 与路径 `:404` / `:408`、`@mode` `:427` / `:449` / `:453`、未知 at 规则 `:475` / `:477`、`:root` `:503`、顶层 `:509`）都经它。
8. 行列号由词法器给（`Css.Lexer.pas:62-85` `Advance`）：LF 换行；单独的 CR 换行；CR 后跟 LF 时 CR 只加一列、LF 换行。列按**字节**数（UTF-8 汉字占 3 列），制表符算 1 列——和 SynEdit 的 `LogicalCaretXY` 同一种列。未闭合块的错误落在 EOF 记号上（最后一个非空白字符之后）。
9. `rsCssErrorFrame = '%s at line %d, col %d (got "%s")'`（`StrConsts.pas:47`）。
10. 别处抛 `ETyCssError` 而**没有位置**的：`StyleModel.pas:1390` / `:1395` / `:1403` / `:1406`（`@import` 太深、空路径、找不到、循环）与 `:1616`（nil 主题源）。`StyleModel` 不改，这几处的 `Line / Col` 保持 0。值错误（`rsSmInvalidPadding` 等，`StyleModel.pas:363-711`）抛的是普通 `Exception`，也没有位置。
11. 捕获 `ETyCssError` 的地方都只看类型、不看消息文字：`tests/test.Css.Parser.pas:174-322`、`:396`，`tests/test.StyleModel.pas:369`、`:671`、`:712`；`ThemeLint.pas:480-484` 把 `E.Message` 包进 `rsLintParseError`——消息必须逐字不变（Task 0 的金样本守着）。

**3. 主题检查（`source/tyControls.ThemeLint.pas`，532 行）**

12. 检查项与输出顺序（单元头 `:10-29`）：未知属性 → 未定义变量 → 缺资源 → 低对比度；`@import` 的问题（太深、空路径、找不到、循环、读不了、解析错）在展开时报（`CollectImports`，`:266-356`）；入口文本解析失败时只报一条 `parse error: <E.Message>`（`:473-490`）。消息文字全是 `rsLint*`（`StrConsts.pas:34-44`）。
13. 解析器**不保留**规则 / 声明的位置（`TTyCssRule`、`TTyCssDeclaration`，`Css.Parser.pas:19-27`）；`:root` 与 `@mode` 的变量存进 `TStringList.Values[]`（`:319`），同名后写的覆盖前写的、占原来的下标。所以行号只能另算：解析成功后用同一个 `TTyCssLexer`（公开 `Next` / `Peek`，`Css.Lexer.pas:25-27`）按语法走一遍，按出现顺序记下规则的首个选择器、每条声明的属性名、每个变量**最后一次**定义、每个 `@import` 的位置——与 lint 遍历解析结果的顺序一一对应。缺资源、未定义变量落在所在声明那一行；导入文件里的问题落在把它引进来的顶层 `@import` 那一行。
14. 「未定义变量」只认文档（及其导入）自己定义的变量（`CollectSheetVars` `:246-257`），**不认底层**：文档里 `var(--surface-hover)` 而自己没定义，lint 报未定义，而引擎运行时能从底层解析——对工具是误报（见开工前问题一第 3 条）。
15. 未知属性的判断（`:431-438`）：`TyApplyDeclaration` 抛异常当「属性已知」、不报；值写错（如 `border-radius: 1px 2px 3px`）因此 lint 看不见，只在加载时 `ValidateRules` 抛（无位置）。
16. 调用点：只有 `tests/test.themelint.pas`（`TThemeLintTest`，21 条，含 `TestLightThemeLintsClean`）。

**4. 侧栏工作台（`source/tyControls.ToolWindows.pas`，已在 main）**

17. 用法照 `examples/toolwindows/umain.lfm`：`TTyToolWindowBar`（`Placement`、`ExpandedSize`、`Collapsed`、`ActiveIndex`、`Images`、`Manager` 可空，`ToolWindows.pas:1351-1376`）里放 `TTyToolWindow`（`Caption`、`ImageName`、`StripHint`、`ShowBadge`、`BadgeValue`），窗口里 `Align = alClient` 放内容；`ActivateWindow` / `ActiveWindow` / `WindowCount` / `Windows[]`（`:1293-1303`）。图标用 `TTyLucideImageList`（`Names.Strings` 列 Lucide 名字，`circle-alert`、`circle-x`、`triangle-alert` 都在 `assets/lucide/codepoints.json` 里）。
18. **本期只建「问题」一页**（理由见开工前问题一第 1 条）；种子、AI 两页在 2、3 期往 `.lfm` 里加（种子在最前，AI 在最后）。

**5. 独立样式控制器（`source/tyControls.Controller.pas`、`Base.pas`）**

19. `TTyStyleController.Create(AOwner)`（`Controller.pas:205-237`）自带一个 `TTyStyleModel`，模型构造时装好底层（默认主题）。控件的 `Controller` 属性（`Base.pas:327`、`:509`）**不从父控件继承**：`ActiveController` 是「自己的 `FController`，否则 `TyDefaultController`」（`Base.pas:835-841`、`:2016-2022`）。所以预览要把 `Root` 下每个 Ty 控件逐个设 `Controller`（照 `TTyDialog.ApplyControllerToChildren`，`Dialogs.pas:472-495`：`TTyCustomControl` 与 `TTyGraphicControl` 分开判断、窗口化的递归）。组合控件自己往内部子控件推（`SetController` 覆写：ComboBox、PageControl、ListView、TabStrip 等 16 个单元）。
20. 加载 API：`LoadThemeCss(text)`（`Controller.pas:597-603`）= `Model.LoadFromCss`（REPLACE 用户层、叠在底层上）+ 密度包 + `StyleOverride` + `Changed`；但它不带目录（`GThemeBaseDir = ''`，`url()` 相对路径解析不到）。带目录的办法是实现一个内存 `ITyThemeSource`（`ThemeBundle.pas:52-60`：`RootCss`、`AssetBaseDir` 等六个方法）交给 `Model.LoadFromSource`（`StyleModel.pas:1611-1629`，设 `GThemeBaseDir` 再 `LoadFromCss`），再自己补密度包（`TyDensityModernCss`，`DensityPack.pas:17`）与 `Changed`。
21. 失败时保持原主题：`LoadInto`（`StyleModel.pas:1440-1547`）先解析、展开 `@import`、`ValidateRules` 试算每条声明，全过才提交；任何一步抛异常，旧的用户层原封不动。**但** `ValidateRules` 用的变量集是「底层 + 文档 `:root` + 所有 `@mode` 的并集」（`:1485-1496`）——只在暗色块里定义、亮色下被规则引用的变量，加载通过，亮色下 `ResolveStyle` 画的时候才抛。控件的 `Paint` 抛异常会弹错误框、重画、再弹，所以预览加载成功后要自己试解析一遍（Task 7 的 `TbProbeResolve`）。
22. 明暗：`Controller.Mode`（`:326-331`）→ `Model.SetMode`；用户层没有 `@mode` 块时 `Model.ModeNames` 为空（`StyleModel.pas:1046-1054` 只看用户层），切换无意义。`Changed`（`:665-687`）会 `SeedModeIfDual`（没选模式的双模式主题选它的默认模式）。
23. 密度：`Controller.Density`（`:403-410`）→ `ReloadThemeLayer`（`:359-401`），它按 `ThemeFile` / `ThemeName` 重装，两者都空时 `LoadFromCss('')`——**预览用内存源加载的文本会被冲掉**，所以换密度之后要把上一版能用的文本重新加载一次。控件的默认高度在构造时读一次密度（`TyDensityHeight`，`:174-180`），`.lfm` 里又写死了 `Height`，所以预览换密度只换令牌（字号、内距），不换控件高度（开工前问题一第 2 条）。
24. 弹出物：`TTyPopupMenu.Controller`（`Menu.pas:545`，普通字段）直接设；`TTyMenuBar` 的下拉用它自己的 `ActiveController`（`:2464`）；`TTyForm.Controller`（`Form.pas:499`，`SetController` `:2726-2742` 调 `ApplyChromeTheme` 只管窗体背景与标题栏，不管子控件）；`TTyNotification.Controller`（`Notification.pas:361`）。消息对话框 `TyBuildMessageDialog`（`Dialogs.pas:777`）用 `Application` 当 Owner，`DoShow` 里 `ApplyOwnerController`（`:497-528`）取「Owner 是有 Controller 的 `TTyForm` 就用它，否则主窗体的」——会变成工具自己的皮肤。办法：建好之后把它从 `Application` 挪到一个 `Controller` = 预览控制器的隐藏 `TTyForm` 名下（`Application.RemoveComponent(d); FDialogOwner.InsertComponent(d)`），`ApplyControllerNow`（`:530-533`）是现成的测试缝。
25. 全局串扰（改不了，记下）：每个控制器的 `Changed` 都会写全局 `TyFallbackFontSize`（`:674`）并清全局文字测量缓存。预览主题的 `--font-size-base` 会影响工具界面「字号被抑制时」的回落字号——只在皮肤自定 typeKey 规则丢了字号时才看得出（真机验收看一眼）。

**6. 预览要摆的控件**

26. 类名都在 `source/` 里核过：`TTyButton`（变体 `primary` / `danger` / `ghost`，主题里 `TyButton.*`）、`TTySpeedButton`、`TTyDropDownButton`、`TTyLabel`、`TTyLinkLabel`、`TTyCheckBox`、`TTyRadioButton`、`TTyToggleSwitch`、`TTyTag`（`accent` / `danger`）、`TTyBadge`、`TTyDivider`、`TTyEdit`、`TTyMemo`、`TTyComboBox`、`TTySpinEdit`、`TTyDateTimePicker`、`TTyTrackBar`、`TTyRating`、`TTyListBox`、`TTyCheckListBox`、`TTyTreeView`、`TTyListView`、`TTyStringGrid`、`TTyValueListEditor`、`TTyPanel`、`TTyGroupBox`、`TTyCard`、`TTyExPanel`、`TTyPageControl` / `TTyTabSheet`、`TTyTabSet`、`TTyScrollBox`、`TTySplitter`、`TTyMenuBar`（配 `TMainMenu`）、`TTyToolBar` / `TTyToolButton` / `TTyToolSeparator`、`TTyStatusBar`、`TTyBreadcrumb`、`TTyPopupMenu`、`TTyScrollBar`、`TTyProgressBar`（`AnimationsEnabled`）、`TTyCircularProgress`、`TTyActivityIndicator`、`TTyAlert`（`AlertType = atInfo/atSuccess/atWarning/atError`，写法见 `examples/antdesign/umain.lfm:924-960`）、`TTyEmpty`、`TTyNotification`（组件）。主题里带变体的 typeKey 清单：`grep -ohE "Ty[A-Za-z]+\.[a-z0-9-]+" themes/*.tycss themes/builtin/*.tycss`（按钮家族 `primary` / `danger` / `ghost`、`TyEdit.embedded`、`TyTag.accent` / `.danger`、`TyAlert.*`、`TyNotification.*`、`on-titlebar` 一族）。
27. 摆法参考：`examples/antdesign/umain.lfm`（`TTyPageControl` + `TTyTabSheet`、`TTyAlert`）、`examples/toolwindows/umain.lfm`（`TTyTreeView.Items` 写在 `.lfm`、`TTyListBox.Items.Strings`）、`examples/button`（按钮变体）。「全部禁用」：遍历 `Pages` 下每个 Ty 控件设 `Enabled := False`，记下原值，取消时还原（`.lfm` 里本来就禁用的样例还原后仍禁用）。

**7. 编辑器外观**

28. 工具界面用 `TyDefaultController`（示例惯例：`examples/toolwindows/umain.pas:204-215` 的 `ThemeName := ...` + `ApplyChromeTheme`），预览用自己的控制器。SynEdit 的颜色从 `TyDefaultController` 取：`Model.ResolveOverride('color: var(--x);')`（`StyleModel.pas:153`，按当前合并变量求值、坏值容忍、没定义时 `tpTextColor` 不在 `Present` 里）逐个取令牌。所有皮肤都有的令牌：`--input-bg`、`--on-surface`、`--selection`（带 alpha）、`--muted`（带 alpha）、`--surface-chrome`、`--accent`、`--success`、`--warning`、`--info`、`--danger`（`Css.Catalog.pas:21-277`）。字体：`--terminal-font-family`（`RawVar`，值为 `monospace` 时换平台等宽字体，照 `Terminal.pas:1625-1634` 的三平台取法）、字号 `--font-size-base`（`ResolveMetric`）。
29. 换肤通知：`TyDefaultController.AddChangeListener(@...)`（`Controller.pas:689-697`）；**窗体销毁时必须 `RemoveChangeListener`**——默认控制器活到进程结束，留下的方法指针在后面的测试里一换肤就 AV。

**8. 新建模板**

30. 内置主题全文：`TyBuiltinThemeCss(AName)`（`BuiltinThemes.pas:38-43`，`default` = `themes/auto.tycss`、`system`、各结构皮肤）与 `TyBuiltinThemeNames`（`:27-36`），数据编译在 `BuiltinThemeData.pas` 里（生成物，与 `themes/` 文件逐字节同步由 `test.builtinthemes` 守着）。工具不读 `themes/` 目录，发布后也能新建。`themes/palettes/*.tycss` 不是编译进去的，不在「从内置主题新建」里（用户可以直接打开文件）。
31. 极简模板的种子值取 `themes/auto.tycss:507-511`（亮）与 `:562-570`（暗）：亮 `--accent #3B82F6; --surface #FFFFFF; --on-surface #1F2937; --border #D1D5DB; --danger #EF4444; --radius 6px`；暗 `--accent #60A5FA; --surface #1E1E1E; --on-surface #E5E7EB; --border #3F3F46; --danger #F87171; --radius 6px`。

**9. 外部修改提醒**

32. `TTyStyleController.HotReload` / `PollThemeFile`（`Controller.pas:532-581`）发现改动就直接重载进模型，不问、也不管编辑器文本——不合用。工具自己轮询：打开 / 保存时记下 `FileAge` 与大小，1 秒一次比较，变了先更新快照再提示（同一次改动只问一次，照 `PollThemeFile` 的「先记戳」）；文件暂时不存在时跳过不提示。

**10. 中英 `.po`**

33. `scripts/example-rsj2po.py <dir> <project> <json>`（`:1-20`）读 `<dir>/lib/*/*.rsj`，跳过 `tycontrols.*` 单元，往 `<dir>/languages/<project>.zh_CN.po` 追加代码里的 resourcestring——**目录是参数，`tools/themebuilder` 直接能用**。`.lfm` 的文字条目（`#: <小写根类名>.<小写组件名>.caption`）不由脚本生成，照示例手写在 `.po` 前半段（`examples/terminal/languages/terminal_example.zh_CN.po:12-`）。程序加载两份目录：`<exe名>.zh_CN.po`（`SetDefaultLang('', LangDir)`）与 `tycontrols.zh_CN.po`（`TranslateUnitResourceStringsEx(..., 'tycontrols', 'tyControls.StrConsts')`），见 `examples/toolwindows/toolwindows_example.lpr`。库目录的最新一份是 `languages/tycontrols.strconsts.zh_CN.po`。
34. `scripts/check-example-po.py` 只扫 `examples/*/languages/*.po`（`:52`）、`scripts/check-lfm-props.py` 只扫 `examples/*/*.lfm`（`:57`）——都要加上 `tools/*/`。`tests/test.i18n.pas` 的 `TestNoCatalogueEntryIsWhollyEmpty`（`:88-`）扫全仓 `.po`，已经覆盖 `tools/`。

**11. 构建与测试工程**

35. `tests/tytests.lpi` 的 `RequiredPackages` 是 `fpcunitconsolerunner` / `FCL` / `BGRABitmapPack` / `LCL`，源码走 `OtherUnitFiles="../source;.;../examples/terminal"`（`:50`）。工具单元要编进测试就得加 `SynEdit` 包与 `../designtime;../tools/themebuilder` 路径。**单元名冲突**：终端示例的主窗体单元叫 `umain`，已在测试路径上，spec §4 的 `umain.pas` 放进同一路径会撞名——工具单元一律 `tb` 前缀。
36. tools 下两种编法都有先例：要 `tycontrols` 包的（`tools/advchart-probe/advchart_probe.lpi`，走机器级包注册，编它就得 `--pcp` 私有配置那一套）与只走源码路径的（`tools/terminal-bench/terminalbench.lpi`：`BGRABitmapPack` + `LCL` + `OtherUnitFiles="../../source"`）。**本工具取后者**（另加 `SynEdit` 包与 `../../designtime`）：`lazbuild -B tools/themebuilder/themebuilder.lpi` 直接能编，不写包注册、不用 `--pcp`；开发者在 IDE 里打开也不用先装 `tycontrols` 包。`tools/` 不进发布包（`scripts/make-release.ps1:8`）。

---

## 开工前要定的问题

每条都给了建议，**计划正文按建议写**；改了哪条，执行时改对应任务，Task 12 写回 spec 原处。第一类由主控在 Task 0 决定问不问用户；用户没回复前按建议做（三期一起验收时仍可改，Task 13 把它们写进验收文档的「等你定的决定」）。

### 一、产品方向 / 用户可见（问用户）

> **状态（2026-10-01）**：未单独询问用户，按建议执行（用户 2026-10-01 以 /goal 指示按计划、开发、验证、修复顺序完成 spec 全部内容），一起验收时可改。第二类（实现层面）主控按建议采纳。

1. **侧栏本期只有「问题」一页。** spec 定的是「种子 / 问题 / AI」三页。**建议**本期只建「问题」，2 期加「种子」（最前）、3 期加「AI」（最后）：占位页的文字要进 `.po`、要翻译、下一期又整段换掉，而三期做完才验收，用户看不到占位的样子。另一做法：本期三页都建，种子 / AI 两页只放一行「第 2 期 / 第 3 期」。
2. **预览换密度只换令牌、不换控件高度。** 控件的默认高度在构造时读一次密度，`.lfm` 里又写死了高度（核实记录 23），切到「现代」时字号、内距变了，控件框不变高。**建议**本期先这样，真机验收时看效果再定。另一做法：换密度时把预览 frame 整个重建（控件按新密度构造）；代价是 frame 的构造约 0.2–0.5 秒、页签与滚动位置要记住再还原。
3. **问题列表里，底层已经定义的变量不算「未定义」。** lint 只认文档自己定义的变量（核实记录 14），文档写 `var(--surface-hover)` 而没自己定义时会报未定义，引擎运行时却能从底层取到。**建议**工具把这类过滤掉（库里的 lint 行为不变，过滤在工具里做）。另一做法：照 lint 原样报（对只改几个种子、其余靠底层的主题全是误报）。
4. **编辑器里不自动格式化光标离开的那一行。** 设计期对话框会把离开的行整理成 `prop: value;` 的样子（核实记录 2）。主题文件里常有对齐的写法（`auto.tycss` 暗色块 `--accent:     #60A5FA;`），光标走过一行就被改掉，而且「没编辑也变了」。**建议**工具里关掉，设计期对话框保持原样。
5. **保存时的编码与换行符。** **建议**：保持读入时的换行符（LF / CRLF / CR，以第一个换行为准）与 BOM 有无、文末有无换行；读入的文件不是合法 UTF-8 时按系统编码猜测转成 UTF-8，状态栏说一句「按 xxx 读入，将存为 UTF-8」，并算作已修改。
6. **保存哪些文件时提醒重跑生成脚本。** spec 只说 `themes/builtin/*.tycss`。**建议**再加上 `themes/auto.tycss` 与 `themes/system.tycss`（同一个 `gen-builtinthemes.ps1` 编进去的），以及 `themes/light.tycss`（提醒 `gen-defaulttheme.ps1` 与 `gen-tycss-catalog.ps1`）。判断条件：文件的上两级目录里有 `scripts/gen-builtinthemes.ps1`（即仓库检出）。
7. **编辑器的语法配色取哪些令牌。** **建议**（Task 10 的表）：底色 `--input-bg`、文字 `--on-surface`、选区 `--selection` 叠在底色上、行号栏底 `--surface-chrome`、行号与注释 `--muted`、选择器与关键字 `--accent`、字符串 `--success`、数字与单位 `--warning`、at 规则 `--info`；有问题的行：错误 `--danger`、警告 `--warning` 各以 18% 叠在底色上。某些皮肤下 `--success` / `--warning` 在底色上可能看不清，真机验收逐个皮肤看。
8. **外部程序把打开的文件删了。** **建议**不提示（和控制器热重载一样跳过），保存时照常写回。另一做法：提示「文件已被删除」。

### 二、实现层面（主控定）

1. **工具单元一律 `tb` 前缀**（核实记录 35）：`tbmain`、`tbdocument`、`tbsettings`、`tbtemplates`、`tbproblems`、`tbpreview`、`tbsamplewin`、`tbeditorlook`、`tbthemesource`。spec §4 的 `u*` 名字（`udocument`、`upreview`、`uproblems`…）照此改名，2、3 期的 `useeds` / `urules` / `udiff` / `uexport` / `ai/*` 也用 `tb` 前缀（Task 12 写回 spec §4）。
2. **工具工程只走源码路径**（核实记录 36）：`RequiredPackages` = `LCL`、`BGRABitmapPack`、`SynEdit`；`OtherUnitFiles` = `.;../../source;../../designtime`。
3. **拆出的单元**：`designtime/tyControls.Design.CssEditKit.pas`，类 `TTyCssEditKit = class(TComponent)`，挂到一个现成的 `TSynEdit` 上（`Attach`），不自己建编辑框——工具的 SynEdit 写在 `.lfm` 里。补全的上下文改为「光标之前的文本」（原来传整篇，长文件里光标在规则内时会给出选择器而不是属性）；这对设计期对话框是改进，记进 spec §4。
4. **`TyLintCssEx` 的记录**比 spec 多两样：`Kind`（种类）与 `Subject`（属性名 / 变量名 / 路径 / 选择器）——工具按种类过滤（开工前问题一第 3 条）、3 期的回喂按种类判失败；另加一种只在 `Ex` 里出现的 `tlkBadValue`（值写错，如 `border-radius` 给三个数），旧 `TyLintCss` 把它滤掉，所以旧输出逐字不变。消息文字用引擎自己的异常消息，不加新的 resourcestring。
5. **预览加载后试解析**（核实记录 21）：`TbProbeResolve` 对 `TyCatalogTypeKeys` 每个 typeKey、它在当前模型里的每个变体（`GetVariantsForType`）、六种状态组合（无、hover、active、focus、disabled、selected）各 `ResolveStyle` 一次；抛了就把上一版能用的文本重新加载、报错。切明暗后同样试一次，失败就退回原模式。Task 12 记下试解析的耗时（`default` 主题一次）；超过 50 ms 写进签收。
6. **预览是 frame、运行时建**：`TTbPreviewFrame`（`tbpreview.pas` / `.lfm`），主窗体在 `FormCreate` 里 `Create(Self)` 再放进 `PreviewHost`。不用 `.lfm` 里的 `inline`：运行时建的 frame 构造返回时自己的 `.lfm` 已经读完、`Loaded` 已跑，挂控制器的时机确定（内嵌 frame 构造返回时子控件还在 `csLoading`，见仓库记忆「FPC 流式 fixup 顺序」）。
7. **消息对话框换 Owner**（核实记录 24），隐藏的 `FDialogOwner: TTyForm`（`CreateNew(Self)`、`Controller` = 预览控制器、从不显示）。
8. **不弹框的测试缝**：主窗体的所有询问（保存？重新载入？）经一个方法 `Ask(AMsg, AButtons): TModalResult`，`class var PromptAnswerForTest: TModalResult`（非 `mrNone` 时直接返回它）；另存为经 `class var SaveAsNameForTest: string`；配置文件经 `class var SettingsFileForTest: string`。注释标「FOR THE TESTS」。测试里任何路径都不许 `ShowModal`（仓库记忆「探针程序会在用户桌面弹模态框」）。
9. **金样本**（Task 0）：改库之前用当前代码跑出 lint 输出与解析错误消息，存成 fixture；Task 1、2 之后逐字比对。

---

## 需要改共享文件的地方

**库（spec §4 的三处，别的库文件不动）：**

| 文件 | 改什么 | 任务 |
|---|---|---|
| `source/tyControls.Css.Parser.pas` | `ETyCssError` 加 `Line`、`Col`（默认 0）；`TTyCssParser.Error` 填上；消息不变 | Task 1 |
| `source/tyControls.ThemeLint.pas` | 新增 `TTyLintSeverity`、`TTyLintKind`、`TTyLintIssue`、`TTyLintIssues`、`TyLintCssEx`；`TyLintCss` 改为调 `Ex` 再取文字 | Task 2 |
| `designtime/tyControls.Design.CssEditKit.pas` | **新建**：`TTyCssEditKit`（不引 `PropEdits` 等 IDE 单元） | Task 3 |
| `designtime/tyControls.Design.Css.Editor.pas` | 对话框改用 `TTyCssEditKit`，删掉挪走的代码 | Task 3 |
| `tycontrols_dt.lpk` | `<Files>` 加新单元 | Task 3 |

`StrConsts.pas`、`tycontrols.lpk`、`.pot` / `.po`（库的）**不改**：新代码没有新的库内文字（`tlkBadValue` 的消息是「属性名: 引擎的异常消息」，拼接不翻译；新单元没有 resourcestring）。

**非库的共用文件：** `tests/tytests.lpi`（`SynEdit` 包、两个搜索路径，Task 0 / Task 4）、`tests/tytests.lpr`（uses，各任务）、`scripts/check-example-po.py`、`scripts/check-lfm-props.py`、`scripts/smoke-launch-examples.ps1`（认 `tools/`，Task 11）、`.gitignore`（Task 4）。

---

## 接口清单（全计划用这一套名字）

### `source/tyControls.Css.Parser.pas`（改）

```pascal
  { Line / Col: where the parser stopped, 1-based, the column counted in bytes (what
    SynEdit calls the logical column). 0 when the error is not the parser's -- an
    @import that failed, a nil source (raised by the style model). }
  ETyCssError = class(Exception)
  private
    FLine, FCol: Integer;
  public
    property Line: Integer read FLine write FLine;
    property Col: Integer read FCol write FCol;
  end;
```

### `source/tyControls.ThemeLint.pas`（改）

```pascal
type
  TTyLintResult = array of string;   { unchanged }

  TTyLintSeverity = (tlsError, tlsWarning);
  TTyLintKind = (tlkParseError, tlkUnknownProperty, tlkUndefinedVar, tlkMissingAsset,
    tlkLowContrast, tlkImportTooDeep, tlkEmptyImportPath, tlkMissingImport,
    tlkImportCycle, tlkUnreadableImport, tlkImportParseError,
    tlkBadValue);   { TyLintCssEx only: a value the engine rejects (not reported by TyLintCss) }

  TTyLintIssue = record
    Line, Col: Integer;          { in ASource, 1-based, byte column; 0 = no position }
    Severity: TTyLintSeverity;
    Kind: TTyLintKind;
    { the property, the variable (no leading --), the asset or import path, the selector;
      '' for a parse error or a too-deep import }
    Subject: string;
    Message: string;             { exactly the text TyLintCss gives for this issue }
  end;
  TTyLintIssues = array of TTyLintIssue;

{ unchanged signature and output: the messages of TyLintCssEx without tlkBadValue }
function TyLintCss(const ASource: string; const ABaseDir: string = ''): TTyLintResult;
{ the same checks in the same order, each with where it is (spec 5.4), how bad and what
  kind; an issue inside an @import-ed file is placed on the entry document's @import that
  brought it in. NEVER raises. }
function TyLintCssEx(const ASource: string; const ABaseDir: string = ''): TTyLintIssues;
```

严重度：`tlsError` = `tlkParseError`、`tlkUnknownProperty`、`tlkUndefinedVar`、`tlkBadValue`、全部 `tlkImport*` 与 `tlkEmptyImportPath`；`tlsWarning` = `tlkMissingAsset`、`tlkLowContrast`。

### `designtime/tyControls.Design.CssEditKit.pas`（新）

```pascal
unit tyControls.Design.CssEditKit;
{ The SynEdit setup the tycss editors share (spec 4): the CSS highlighter, completion from
  the tycss catalog (Ctrl+Space, and as an identifier is typed), the caret kept on real
  text, and optionally the line the caret leaves tidied. Used by the design-time
  StyleOverride dialog and by tools/themebuilder. No IDE units. }
interface
uses
  Classes, SysUtils, Controls, SynEdit, SynEditTypes, SynCompletion, SynHighlighterCss;

type
  TTyCssEditKit = class(TComponent)
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { configure AEdit; an OnChange it already has keeps running, after the kit's }
    procedure Attach(AEdit: TSynEdit; ASelectorMode: Boolean);
    procedure Detach;
    { the lines above the caret and the caret line up to the caret }
    function TextBeforeCaret: string;
    { what Ctrl+Space puts in Completion.ItemList }
    procedure FillCompletion;
    { the kit's own status handler (registered on the edit); public FOR THE TESTS }
    procedure HandleStatusChange(Sender: TObject; Changes: TSynStatusChanges);
    property Edit: TSynEdit read FEdit;
    property Highlighter: TSynCssSyn read FHighlighter;
    property Completion: TSynCompletion read FComplete;
    property SelectorMode: Boolean read FSelectorMode write FSelectorMode;
    property FormatOnLineLeave: Boolean read FFormatOnLineLeave write FFormatOnLineLeave default True;
    property AutoComplete: Boolean read FAutoComplete write FAutoComplete default True;
  end;
```

### 工具（`tools/themebuilder/`）

```pascal
{ tbthemesource.pas }
type
  { editor text as a theme source: url() and @import resolve from ABaseDir ('' = none) }
  TTbTextThemeSource = class(TInterfacedObject, ITyThemeSource)
  public
    constructor Create(const AText, ABaseDir: string);
    function RootCss: string;
    function ReadText(const ARelPath: string; out S: string): Boolean;
    function OpenAsset(const ARelPath: string; out Stream: TStream): Boolean;
    function Manifest: TTyThemeManifest;
    function RootName: string;
    function AssetBaseDir: string;
  end;

{ tbdocument.pas }
type
  TTbLineEnding = (tleLF, tleCRLF, tleCR);
  TTbDocument = class
  public
    procedure NewUntitled(const AText, ABasedOn: string);
    { raises on a read error; the document is unchanged then }
    procedure LoadFromFile(const AFileName: string);
    { ALines joined with the document's line ending, BOM and final line break as read }
    procedure SaveToFile(const AFileName: string; ALines: TStrings);
    function EditorText: string;
    { the file on disk changed since it was opened / saved (age or size). The stamp is
      taken again, so one change answers True once. A missing file answers False. }
    function DiskChanged: Boolean;
    { '' or the script(s) to run after saving a theme the library compiles in }
    function RegenerateHint: string;
    property FileName: string read FFileName;
    property BaseDir: string read GetBaseDir;          { '' when untitled }
    property Untitled: Boolean read GetUntitled;
    property BasedOn: string read FBasedOn;
    property LineEnding: TTbLineEnding read FLineEnding;
    property HasBom: Boolean read FHasBom;
    property TrailingEol: Boolean read FTrailingEol;
    property ConvertedFrom: string read FConvertedFrom;  { '' = it was UTF-8 }
  end;
function TbDetectLineEnding(const S: string): TTbLineEnding;  { the first break; none -> the platform's }
function TbJoinLines(ALines: TStrings; AEol: TTbLineEnding; ATrailing: Boolean): string;
function TbLineEndingName(AEol: TTbLineEnding): string;       { 'LF' / 'CRLF' / 'CR' }

{ tbsettings.pas }
const
  TbMaxRecent = 10;
type
  TTbSettings = class
  public
    constructor Create(const AIniFile: string);
    destructor Destroy; override;
    procedure Load;                    { a missing file = defaults }
    procedure Save;                    { creates the directory }
    procedure AddRecent(const AFileName: string);    { to the front; no duplicates; at most TbMaxRecent }
    procedure RemoveRecent(const AFileName: string);
    property Recent: TStrings read FRecent;
    property EditorTheme: string read FEditorTheme write FEditorTheme;   { default 'default' }
    property EditorDark: Boolean read FEditorDark write FEditorDark;
    property PreviewDark: Boolean read FPreviewDark write FPreviewDark;
    property PreviewModern: Boolean read FPreviewModern write FPreviewModern;
    property FileName: string read FFileName;
  end;
function TbDefaultSettingsFile: string;   { GetAppConfigDir(False) + 'themebuilder.ini' }

{ tbtemplates.pas }
function TbMinimalTemplate: string;
{ a header comment naming the theme, then TyBuiltinThemeCss(AName) unchanged; '' if unknown }
function TbFromBuiltin(const AName: string): string;
function TbBuiltinHeader(const AName: string): string;

{ tbproblems.pas }
type
  TTbProblemOrigin = (tpoLint, tpoLoad, tpoDocument);
  TTbProblem = record
    Line, Col: Integer;                 { 0 = no position }
    Severity: TTyLintSeverity;
    Origin: TTbProblemOrigin;
    Kind: TTyLintKind;                  { meaningful for tpoLint only }
    Text: string;
  end;
  TTbProblems = array of TTbProblem;
{ names (lower case, no --) the base layer defines, in any mode }
procedure TbBaseVarNames(ADest: TStrings);
{ lint issues (minus undefined variables the base defines) + a hint per line with url()
  when the document has no folder yet; sorted: no position first, then by line and column }
function TbCollectProblems(const AText, ABaseDir: string; AUntitled: Boolean;
  ABaseVars: TStrings): TTbProblems;
procedure TbAddProblem(var AList: TTbProblems; ALine, ACol: Integer;
  ASeverity: TTyLintSeverity; AOrigin: TTbProblemOrigin; const AText: string);
function TbHasParseError(const AList: TTbProblems): Boolean;
function TbErrorCount(const AList: TTbProblems): Integer;
function TbProblemCaption(const AProblem: TTbProblem): string;   { '12:5  text' / '—  text' }

{ tbpreview.pas }
procedure TbApplyController(ARoot: TWinControl; AController: TTyStyleController);
{ every catalog typeKey x its variants x six state sets; False and AError on the first raise }
function TbProbeResolve(AModel: TTyStyleModel; out AError: string): Boolean;
type
  TTbPreviewFrame = class(TFrame)
    { .lfm: Tools (tool theme) + Root (preview theme): see Task 7 }
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { AText over the base, as an app would load it; url() / @import from ABaseDir.
      False + AError: the preview keeps the last version that loaded (or the base) }
    function LoadDocument(const AText, ABaseDir: string; out AError: string): Boolean;
    { False + AError: the document does not resolve in that mode; the mode is unchanged }
    function SetDark(ADark: Boolean; out AError: string): Boolean;
    procedure SetModern(AModern: Boolean);
    procedure SetAllDisabled(ADisabled: Boolean);
    function HasModes: Boolean;
    function BuildSampleDialog: TTyDialog;          { built, not shown }
    function BuildSampleWindow: TTbSampleForm;      { built once, not shown }
    procedure ShowSampleWindow;
    function StyledControlCount: Integer;           { FOR THE TESTS }
    property Controller: TTyStyleController read FController;
    property ModeError: string read FModeError;     { the last rejected switch, '' after a good load }
    property AllDisabled: Boolean read FAllDisabled;
    property IsDark: Boolean read GetIsDark;
    property IsModern: Boolean read GetIsModern;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;  { a switch was used }
  end;

{ tbsamplewin.pas }
type
  TTbSampleForm = class(TTyForm)
  public
    procedure UseController(AController: TTyStyleController);
  end;

{ tbeditorlook.pas }
type
  TTbEditorColors = record
    Background, Text, Selection, Gutter, LineNumbers, Comment, Keyword, Str, Number,
    AtRule, ErrorLine, WarningLine: TColor;
    FontName: string;
    FontSize: Integer;       { points }
  end;
function TbEditorColors(AController: TTyStyleController): TTbEditorColors;
procedure TbApplyEditorColors(AEdit: TSynEdit; AHighlighter: TSynCssSyn;
  const AColors: TTbEditorColors);

{ tbmain.pas }
type
  TTbMainForm = class(TTyForm)
  public
    class var PromptAnswerForTest: TModalResult;   { FOR THE TESTS: mrNone = really ask }
    class var SaveAsNameForTest: string;           { FOR THE TESTS }
    class var SettingsFileForTest: string;         { FOR THE TESTS }
    procedure RefreshNow;                          { lint + preview + problem list, now }
    procedure NewMinimal;
    procedure NewFromBuiltin(const AName: string);
    function OpenFile(const AFileName: string): Boolean;
    function SaveTo(const AFileName: string): Boolean;
    function SaveDocument: Boolean;                { Save As when untitled }
    procedure CheckDiskNow;                        { what the watch timer does }
    procedure JumpToProblem(AIndex: Integer);
    procedure SetEditorAppearance(const ATheme: string; ADark: Boolean);
    { FOR THE TESTS: how many times Ask answered from PromptAnswerForTest, and the last
      message it was given }
    property AskCount: Integer read FAskCount;
    property LastAsk: string read FLastAsk;
    property Doc: TTbDocument read FDoc;
    property Kit: TTyCssEditKit read FKit;
    property Preview: TTbPreviewFrame read FPreview;
    property Problems: TTbProblems read FProblems;
    property Settings: TTbSettings read FSettings;
  end;
```

---

## 文件清单

| 文件 | 本期做什么 |
|---|---|
| `tests/tytests.lpi` | `SynEdit` 包、`../designtime`（Task 0）；`../tools/themebuilder`（Task 4） |
| `tests/test.themebuilder.golden.pas`、`tests/fixtures/themebuilder/lint-golden.txt`、`parse-golden.txt` | **新建**（Task 0） |
| `source/tyControls.Css.Parser.pas` | 改（Task 1） |
| `tests/test.themebuilder.parser.pas` | **新建**（Task 1） |
| `source/tyControls.ThemeLint.pas` | 改（Task 2） |
| `tests/test.themebuilder.lint.pas`、`tests/fixtures/themebuilder/import-child.tycss` | **新建**（Task 2） |
| `designtime/tyControls.Design.CssEditKit.pas` | **新建**（Task 3） |
| `designtime/tyControls.Design.Css.Editor.pas`、`tycontrols_dt.lpk` | 改（Task 3） |
| `tests/test.themebuilder.editkit.pas` | **新建**（Task 3） |
| `tools/themebuilder/themebuilder.lpi`、`themebuilder.lpr`、`tbdocument.pas`、`tbsettings.pas`、`tbthemesource.pas` | **新建**（Task 4） |
| `tests/test.themebuilder.doc.pas`、`.gitignore` | 新建 / 改（Task 4） |
| `tools/themebuilder/tbtemplates.pas` | **新建**（Task 5；测试并进 `test.themebuilder.doc.pas`） |
| `tools/themebuilder/tbproblems.pas`、`tests/test.themebuilder.problems.pas` | **新建**（Task 6） |
| `tools/themebuilder/tbpreview.pas`、`tbpreview.lfm` | **新建**（Task 7），改（Task 8） |
| `tools/themebuilder/tbsamplewin.pas`、`tbsamplewin.lfm` | **新建**（Task 8） |
| `tests/test.themebuilder.preview.pas` | **新建**（Task 7），改（Task 8） |
| `tools/themebuilder/tbmain.pas`、`tbmain.lfm` | **新建**（Task 9），改（Task 10） |
| `tools/themebuilder/tbeditorlook.pas` | **新建**（Task 10） |
| `tests/test.themebuilder.main.pas` | **新建**（Task 9），改（Task 10、11） |
| `tools/themebuilder/languages/themebuilder.zh_CN.po`、`themebuilder.zh_CN.json`、`tycontrols.zh_CN.po` | **新建**（Task 11；代码条目由 Task 12 跑脚本补） |
| `scripts/check-example-po.py`、`scripts/check-lfm-props.py`、`scripts/smoke-launch-examples.ps1` | 改（Task 11） |
| `tests/tytests.lpr` | uses 随各任务加 |
| `docs/superpowers/specs/2026-10-01-theme-builder-design.md` | 只在 Task 12 写回 |
| `docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md` | **新建**（Task 13） |

**不碰**：四个共享文件、`StrConsts.pas`、`Controller.pas`、`Dialogs.pas`、`ThemeBundle.pas`、`tycontrols.lpk`、`themes/`、`README*`、`CHANGELOG*`。

---

## 实现期的地雷（每个任务开工前看一眼）

1. **不 amend、不 rebase、不 reset、不 stash**；一个任务一个提交，修复另起提交。
2. **不用 `sed -i`**（Git Bash 的 sed 会把 CRLF 吃成 LF，仓库记忆「Git Bash sed -i 吃 CRLF」）；改 `.pas` / `.lfm` / `.lpk` / `.po` 用 Edit / Write。含反斜杠或 `\x` 转义的测试数据、脚本用 Write 落文件，不用 heredoc。
3. **只按 PID 结束进程，绝不 `taskkill -im`**（全机器按镜像名杀，会杀掉别的 agent 的测试）。
4. **FPC 的 `{ }` 注释会嵌套**：注释里写 CSS 例子时 `{` 会吞掉后面的代码（线索是第一条「Comment level 2」警告）——注释里的 CSS 花括号写成 `( )` 或用 `//`（照 `Css.Parser.pas:29` 的写法）。字符串里的 `{` 不受影响。
5. **`.lfm` 规矩**（仓库记忆「示例必须 .lfm + 标题栏 + 换肤」）：主窗体与示例窗体都是 `TTyForm`，`.lfm` 里写 `TitleBar = Bar`（不写标题栏拖不动）；标题栏有真文字；界面换肤走「视图 → 编辑器外观」。`.lfm` 里 `Checked = True` / `ItemIndex` 会在流式加载时触发 `OnChange`、碰到还没读进来的兄弟控件——初值在代码里设。`ModalResult` 在 `.lfm` 里写整数。
6. **自绘 UI 里不用裸 LCL 控件**：唯一例外是 SynEdit（spec §6）。容器用 `TTyPanel`，文字用 `TTyLabel`，列表用 `TTyListBox`……非可视的 `TMainMenu`、`TTimer` 照示例的先例可以用。
7. **视觉值走主题令牌**：编辑器颜色、字体、问题行的底色全从控制器取（Task 10 的表），不写死颜色；预览区的背景来自预览主题。
8. **published 属性的 default 必须等于构造值**（`TTyCssEditKit.FormatOnLineLeave` / `AutoComplete` 默认 True，构造里就设 True）。
9. **聚焦用 `CanSetFocus`**：`if Editor.CanSetFocus then Editor.SetFocus`。测试里窗体不显示，直接 `SetFocus` 会抛。
10. **默认控制器的监听要摘**：`TyDefaultController.AddChangeListener` 配 `FormDestroy` 里的 `RemoveChangeListener`；预览控制器归 frame 所有，frame 析构前先把样例窗体、对话框 Owner 释放。测试 `TearDown` 要还原 `TyDefaultController` 的 `ThemeName` / `Mode` / `Density`（`SetUp` 里记下）。
11. **测试不弹任何窗**：询问全走 `PromptAnswerForTest`，另存为走 `SaveAsNameForTest`，配置走 `SettingsFileForTest`（指到临时目录，**绝不**写用户真实的配置目录）；样例对话框、样例窗体、通知只建不显示。
12. **新单元进清单**：`designtime/*.pas` 进 `tycontrols_dt.lpk`（发版守卫会红）；工具单元进 `themebuilder.lpi` 的 `<Units>`（Task 9 的守卫测试查）。本期不往 `tycontrols.lpk` 加单元。
13. **注释与代码风格**：库里的新代码照所在单元的英文注释惯例；工具单元也用英文注释（`examples/` 的惯例）；用户可见文字全部 resourcestring 或 `.lfm`。
14. **`ETyCssError` 的消息一个字都不能变**（金样本、`ThemeLint` 的 `rsLintParseError` 包着它）；`TyLintCss` 的输出顺序与文字一个字都不能变（金样本）。
15. **预览不许让 `Paint` 抛异常**：任何能改预览模型的路径（加载、换明暗、换密度）之后都要 `TbProbeResolve`，失败就退回上一版（核实记录 21）。
16. **`Changed` 之后才读解析结果**：`LoadFromSource` 不调控制器的 `Changed`，漏了的症状是控件不重画、`SeedModeIfDual` 没跑（双模式主题没选模式，`@mode` 里才有的变量未定义、试解析失败）。
17. **SynEdit 的列是字节列**：跳转用 `Editor.LogicalCaretXY := Point(Col, Line)`，不用 `CaretXY`（汉字所在行会偏）。
18. **单跑绿 / 全量红** 先 `lazbuild -B` 重编（仓库记忆「变异后必须重编再全量」），再查进程级状态（`TyDefaultController` 被前面的 suite 换过皮肤、`Screen` 字体回落）；期末变异先 `git diff --stat` 确认改到了（CRLF 上的替换可能根本没命中）。
19. **编译探针别把 `.ppu` 写进 `source/`**：任何手编都带 `-FU`，编完 `git status` 看 `source/`、`designtime/`、`tools/themebuilder/` 下没有游离的 `.ppu` / `.o`。

---

## 跑测试的固定套路（只在 Task 0 与 Task 12 跑）

改了 `source/` 或 `designtime/` 之后**必须** `lazbuild -B`。exe 用唯一名 `tytests-tb.exe`。

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/tb-build.txt 2>&1 || { tail -30 /tmp/tb-build.txt; false; } && cd tests && cp tytests.exe tytests-tb.exe && for s in $SUITES; do ./tytests-tb.exe --suite=$s --format=plain > /tmp/tb-$s.txt 2>&1; printf '%s: ' $s; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/tb-$s.txt | tr '\n' ' '; echo; done
```

`SUITES` = `TThemeLintGoldenTests TTbParserPosTests TTbLintExTests TTbCssEditKitTests TTbDocumentTests TTbSettingsTests TTbTemplatesTests TTbProblemsTests TTbPreviewTests TTbMainFormTests TThemeLintTest TTestCssParser TTestStyleLoad TTestStyleImport TControllerTest TCssCatalogTest TI18NTest TReleaseManifestTest TTyTerminalExampleTests`

**判据是每个 suite 那一行都有 `Number of run tests`、errors / failures 为 0**，不是 exit code。某一行为空 = 跑丢了，重跑，别读成通过。

全量（输出必须重定向到文件）：

```bash
cd /d/Projects/ty-3.1/tests && ./tytests-tb.exe --all --format=plain > /tmp/tb-all.txt 2>&1; grep -E "Number of (run tests|errors|failures|ignored)" /tmp/tb-all.txt
```

**编工具**（实现 agent 可以做，只在 Task 12）：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tools/themebuilder/themebuilder.lpi > /tmp/tb-tool.txt 2>&1; tail -3 /tmp/tb-tool.txt; grep -ci "components.synedit.*Compiling\|Compiling.*synedit" /tmp/tb-tool.txt
```

Expected：0 错，程序在 `tools/themebuilder/lib/x86_64-win64/themebuilder.exe`；最后一个数是 0（lazbuild 没有去重编 Lazarus 目录里的 SynEdit 包——若不为 0，停下交主控，别让它写 `C:\lazarus`）。不需要 `--pcp`：这个工程不要求 `tycontrols` 包，不碰机器级包注册（核实记录 36）。

---

## 关于判据和变异

- 纯函数给**输入 / 期望表**；控件、窗体、预览写**判据**（比什么、怎么数、失败打印什么），测试代码执行时现写（仓库记忆「plan 里写判据别写测试代码」）。
- 每条判据写明「**在哪个变异下必须红**」；变异期末集中做（Task 12 Step 6）：改一行 → `git diff --stat` 确认改到了 → `lazbuild -B` → 跑相关 suite → **必须红** → 改回 → 重编重跑 → 绿。没红的先查改没改对地方、再查是不是「这条路走不到」；确实没红，当场补测试，签收记录写一句。
- 接线类变异（监听没挂、控制器没推、换 Owner 没做、刷新没接、钩子没注册）每类至少一条（仓库记忆「建好没接线是本项目的默认故障」）。
- 断言里那个量要真的变过（仓库记忆「断言里那个量从没变过」）：「坏主题不影响工具界面」之前先证明同一个预览**会**被好主题改掉；「换密度后文档还在」之前先证明文档的值和底层不同；「编辑器颜色跟着换肤」之前先证明两套皮肤的 `--input-bg` 不同。
- 标「—」的不做变异（结构性检查或纯文档），理由写在表里。

---

### Task 0: 基线、测试工程带上 SynEdit、两份金样本

**Files:**
- Modify: `tests/tytests.lpi`
- Create: `tests/test.themebuilder.golden.pas`（suite `TThemeLintGoldenTests`）、`tests/fixtures/themebuilder/lint-golden.txt`、`tests/fixtures/themebuilder/parse-golden.txt`
- Modify: `tests/tytests.lpr`（uses 加 `test.themebuilder.golden`）

- [ ] **Step 1: 【主控执行】开工前问题一的八条**：主控决定问不问用户；问了就把答复写进「开工前要定的问题 · 一」开头（新加一个「状态」引用块，格式照终端 7 期计划）；没问或没回复就按建议做，一起验收时可改。第 1 条选「三页都建」：Task 9 的 `.lfm` 多两个 `TTyToolWindow`（`SeedsWin`、`AiWin`，各一个 `TTyLabel` 写「第 2 期」「第 3 期」），Task 11 的 `.po` 多四条。第 2 条选「重建」：Task 8 的 `SetModern` 改成重建 frame（先记页签与滚动位置）。第 3 条选「照原样报」：Task 6 去掉过滤。

- [ ] **Step 2: 确认起点**

```bash
cd /d/Projects/ty-3.1 && git status --short && git branch --show-current && git log --oneline -1 && git log --oneline feat/theme-builder..main | wc -l
```

Expected：工作区干净，分支 `feat/theme-builder`，HEAD 是本计划的提交或其后；`main` 没有新提交（有的话停下交主控：要不要先合）。

- [ ] **Step 3: 测试工程带上 SynEdit 与 `designtime`**：`tests/tytests.lpi` 的 `RequiredPackages` 末尾加

```xml
      <Item>
        <PackageName Value="SynEdit"/>
      </Item>
```

`OtherUnitFiles` 改为 `../source;.;../examples/terminal;../designtime`（`../tools/themebuilder` 等 Task 4 目录建好再加）。

- [ ] **Step 4: 金样本单元** `tests/test.themebuilder.golden.pas`（单元头注释：为什么有它——Task 1、2 改了解析器与 lint，旧输出与消息必须逐字不变；样本在改之前由当时的代码生成）。一个 suite `TThemeLintGoldenTests`，两条测试：
  - `TestTheLintOutputIsUnchanged`：语料 = `themes/` 下全部 `*.tycss`（递归，按相对路径排序，各以自己所在目录为 `ABaseDir`）+ 单元里的常量数组 `GoldenSnippets`（下面列的片段，`ABaseDir` 为空）。输出格式：每个语料一行 `== <相对路径或 snippet:N>`，接着 `TyLintCss` 的每条一行。
  - `TestTheParseErrorsReadTheSame`：对 `GoldenSnippets` 里每个会解析失败的片段，`TTyCssParser.Create(s).Parse` 抛出的 `E.ClassName + ': ' + E.Message` 一行；另加 `TTyStyleModel.LoadFromCss('@import "definitely_missing.tycss";')` 的一行（StyleModel 抛的、无位置的那种）。
  - 两条都是：环境变量 `TY_WRITE_GOLDEN=1` 时把输出写进 fixture（LF、UTF-8、无 BOM）后通过；否则读 fixture，**把两边的 CRLF 都换成 LF 再比**，不同时失败信息打印第一处不同的行号与两边那一行。
  - `GoldenSnippets`（Pascal 字符串，`#10` / `#13#10` / `#13` 显式写出，含中文的那条用 UTF-8 字面量）：`'TyButton {'#10'  color red;'#10'}'`、同一句用 `#13#10`、同一句用 `#13`、`'TyButton:hover2 { }'`、`':root { --a: 1px;'`、`'TyButton { color: red;'`、`'@mode dark {'#10'  :root { --x: 1px; }'`、`'TyButton { }'#10'@import "a.tycss";'`、`'@media x { }'`、`'@ x'`、`'@mode dark { TyButton { } }'`、`'@mode dark { :rot { } }'`、`'@import url(1);'`、`'@import 5;'`、`':nope { }'`、`'5px { }'`、`'/* 中 */ TyButton:x {}'`、`'/* a'#10'b */ TyButton {'#10' color red; }'`、`'TyButton { frobnicate: var(--nope); }'`、`'TyButton { color: var(--ghost); background: darken(--missing, 4%); }'`、`':root { --c: #112233; }'#10'TyButton { background: #111111; color: #131313; }'`、`'TyButton { border-radius: 1px 2px 3px; }'`、`'TyPanel { background-image: url(nope.png) slice(4 4 4 4); }'`、`'@import "definitely_not_here.tycss";'`、`''`。
  - 注册：`tests/tytests.lpr` 的 uses 加 `test.themebuilder.golden`。

- [ ] **Step 5: 基线编译、生成样本、跑全量**（本任务的例外，实现 agent 做）：

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tests/tytests.lpi > /tmp/tb-build.txt 2>&1 || { tail -30 /tmp/tb-build.txt; false; }; grep -ci "Compiling.*components.synedit" /tmp/tb-build.txt; cd tests && cp tytests.exe tytests-tb.exe && mkdir -p fixtures/themebuilder && TY_WRITE_GOLDEN=1 ./tytests-tb.exe --suite=TThemeLintGoldenTests --format=plain > /tmp/tb-gold-w.txt 2>&1; ./tytests-tb.exe --suite=TThemeLintGoldenTests --format=plain > /tmp/tb-gold.txt 2>&1; grep -E "Number of (run tests|errors|failures)" /tmp/tb-gold.txt; wc -l fixtures/themebuilder/*.txt
```

Expected：编译 0 错；SynEdit 那个计数是 0（lazbuild 用的是已编好的 SynEdit，没去重编——不为 0 就停下交主控）；样本两份都非空（`lint-golden.txt` 约 200–400 行，其中 `themes/light.tycss` 那一段没有警告行）；第二次跑 2 条全过。然后跑全量（「跑测试的固定套路」），条数与红名单记进草稿，Task 12 签收时写进本计划末尾。**除已知偶发失败外有别的红就停。**

- [ ] **Step 6: 提交**

```bash
cd /d/Projects/ty-3.1 && git add tests/tytests.lpi tests/tytests.lpr tests/test.themebuilder.golden.pas tests/fixtures/themebuilder && git commit -m "test(themebuilder): golden lint output and parse messages before the parser and lint change

The theme builder needs positions from the parser and the linter.
These two fixtures hold what both say today, over every theme in
themes/ and a set of broken snippets, so the change can prove the
old output did not move. The test project also takes the SynEdit
package and designtime/ from here on.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: `ETyCssError` 带上行列号

**Files:**
- Modify: `source/tyControls.Css.Parser.pas`（`:50` 的声明、`:146-150` 的 `Error`）
- Create: `tests/test.themebuilder.parser.pas`（suite `TTbParserPosTests`）
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 声明**：照接口清单替换 `:50` 的一行（注释写英文，说明 0 的意思）。

- [ ] **Step 2: 抛出点**：

```pascal
procedure TTyCssParser.Error(const AMsg: string; const ATok: TTyCssToken);
var
  e: ETyCssError;
begin
  e := ETyCssError.CreateFmt(rsCssErrorFrame,
    [AMsg, ATok.Line, ATok.Col, ATok.Text]);
  e.Line := ATok.Line;
  e.Col := ATok.Col;
  raise e;
end;
```

- [ ] **Step 3: 判据测试**（`TTbParserPosTests`，每行一条：输入 → 期望的 `Line`、`Col`；另断言 `E.Message` 里含 `' at line <L>, col <C> '`——证明字段与消息同源）：

| # | 输入（Pascal 字面量） | Line | Col | 在哪个变异下必须红 |
|---|---|---|---|---|
| P1 | `'TyButton {'#10'  color red;'#10'}'` | 2 | 9 | `e.Line := ATok.Line` 删掉（恒 0） |
| P2 | 同上换 `#13#10` | 2 | 9 | —（词法器的既有行为，守 CRLF） |
| P3 | 同上换 `#13` | 2 | 9 | — |
| P4 | `'TyButton:hover2 { }'`（未知伪类） | 1 | 10 | `e.Col := ATok.Col` 删掉 |
| P5 | `':root { --a: 1px;'`（EOF） | 1 | 18 | — |
| P6 | `'TyButton { }'#10'@import "a.tycss";'` | 2 | 1 | — |
| P7 | `'@mode dark { TyButton { } }'` | 1 | 14 | — |
| P8 | `'/* 中 */ TyButton:x {}'`（字节列） | 1 | 20 | — |
| P9 | `'/* a'#10'b */ TyButton {'#10' color red; }'` | 3 | 8 | — |
| P10 | `TTyStyleModel.LoadFromCss('@import "definitely_missing.tycss";')` 抛的 `ETyCssError` | 0 | 0 | —（守「StyleModel 抛的没有位置」这条约定，不是变异目标） |

  另一条 `TestTheMessagesDidNotChange` 不需要：`TThemeLintGoldenTests.TestTheParseErrorsReadTheSame` 就是它；变异 **G1**（`rsCssErrorFrame` 的实参顺序换成 `[AMsg, ATok.Col, ATok.Line, ATok.Text]`）必须让那条红。

- [ ] **Step 4: 注册与提交**：uses 加 `test.themebuilder.parser`。`feat(css): a parse error says where it stopped as numbers, not only in its message` + Co-Authored-By。

---

### Task 2: `TyLintCssEx`——带位置、严重度、种类

**Files:**
- Modify: `source/tyControls.ThemeLint.pas`
- Create: `tests/test.themebuilder.lint.pas`（suite `TTbLintExTests`）、`tests/fixtures/themebuilder/import-child.tycss`
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 类型与声明**：接口清单里的类型与 `TyLintCssEx` 加进 interface；单元头注释补一段：`TyLintCssEx` 是什么、位置怎么来（解析成功后按语法走一遍词法器，解析器的数据结构不动）、`tlkBadValue` 只在 `Ex` 里。

- [ ] **Step 2: 位置表**（implementation 私有）：

```pascal
type
  TLintPos = record
    Line, Col: Integer;
  end;
  { Where each piece of the entry document starts, recorded by walking the lexer the way
    the parser walks it -- only ever after the parser accepted the text, so the grammar is
    known to hold. Order matches the parsed sheet: Rules[i] <-> Rules[i], a rule's
    Declarations[j] <-> Decls[i][j], ModeBlocks[m] <-> Modes[m], Imports[k] <-> Imports[k].
    A variable maps to its LAST definition: :root and @mode keep the last value of a name
    in the first name's slot (Css.Parser.pas ParseRootInto). }
  TLintPositions = class
  public
    Rules: array of TLintPos;               { the rule's first selector token }
    Decls: array of array of TLintPos;      { the property name token }
    RootVars: TStringList;                  { lower name (no --) -> Objects = index into VarPos }
    Modes: array of TStringList;            { the same, one list per @mode block }
    VarPos: array of TLintPos;
    Imports: array of TLintPos;             { the '@' of each @import }
    constructor Create;
    destructor Destroy; override;
    function RootVar(const AName: string): TLintPos;           { (0,0) when unknown }
    function ModeVar(AMode: Integer; const AName: string): TLintPos;
  end;

function BuildPositions(const ASource: string): TLintPositions;
```

  `BuildPositions` 的走法（用 `TTyCssLexer.Next`，整个函数 `try … except` 包住，出错就返回已记下的部分、其余位置为 0——lint 永不抛）：顶层循环取记号直到 `ctkEOF`：
  - `ctkAtKeyword`：`import` → 记进 `Imports`，然后一直取到 `ctkSemicolon`；`mode` → 新建一个 `Modes` 表，取模式名、取 `{`，内层循环：`}` 结束；`:` → 取 `root`，调 `ReadVarBlock(Modes[最后])`。
  - `ctkColon`：取 `root`，`ReadVarBlock(RootVars)`。
  - `ctkIdent`：新的一条规则，记它的位置进 `Rules`；一直取到 `ctkLBrace`（选择器列表）；`ReadDeclBlock(规则序号)`。
  - `ReadDeclBlock`：循环取记号，`ctkRBrace` 结束；否则这个记号就是属性名，记位置；然后一直取到 `ctkSemicolon`（解析器的 `ReadRawValue` 遇 `;` 就停、不看括号深度，`Css.Parser.pas:233`）。
  - `ReadVarBlock(AList)`：同上，属性名是 `--name`：`LowerCase(Copy(name, 3, MaxInt))`，已在表里就**改写**它的位置（最后一次定义），否则新增。

- [ ] **Step 3: 发出问题**：内部的 `Emit(var AResult: TTyLintResult; AMsg)` 换成

```pascal
procedure EmitIssue(var AIssues: TTyLintIssues; const APos: TLintPos; AKind: TTyLintKind;
  const ASubject, AMsg: string);
```

  严重度由 `AKind` 查表得出（接口清单那段）。原来每一处 `Emit` 原样改成 `EmitIssue`，**顺序与消息文字不动**；位置这样给：
  - 入口文本解析失败：`Line / Col` 取自 `ETyCssError`（别的异常类为 0），`tlkParseError`，`Subject = ''`。
  - `ScanSheet` 多两个参数 `APos: TLintPositions`（入口文本给表，导入的文件给 `nil`）与 `AFallback: TLintPos`（导入的文件 = 把它引进来的顶层 `@import` 的位置；入口文本给 (0,0)）。`:root` 第 `vi` 个变量 → `APos.RootVar(名)`；第 `mi` 个 `@mode` 块的变量 → `APos.ModeVar(mi, 名)`；第 `ri` 条规则第 `di` 条声明 → `APos.Decls[ri][di]`；低对比度 → `APos.Rules[ri]`。`APos = nil` 时一律 `AFallback`。
  - `ScanValueForUndefinedVars` / `ScanValueForMissingAssets` 多一个 `APos` 参数，`Subject` = 变量名（不带 `--`，保持原大小写）/ 路径。抽出一个不发问题的 `CollectUndefinedVars(ARaw, ADefined, AOut: TStrings)`，两处共用（发问题的那个改为「收集后逐个发」，顺序不变）。
  - `CollectImports` 多参数 `ATop: TLintPos`：深度 0 时每个 `ii` 用 `APos.Imports[ii]`（`APos` 为 nil 或下标越界时 (0,0)），往下递归原样传；每个导入的 sheet 在加进 `ASheets` 时，同时把 `ATop` 记进一个并行数组，扫描时作 `AFallback`。
  - **坏值**：`ScanSheet` 的属性那一遍里：

```pascal
      known := True;
      bad := '';
      try
        known := TyApplyDeclaration(dummy, prop, raw, AEvalVars);
      except
        on E: Exception do
        begin
          known := True;
          bad := E.Message;
        end;
      end;
      if not known then
        EmitIssue(AIssues, P, tlkUnknownProperty, prop, Format(rsLintUnknownProperty, [prop]))
      else if (bad <> '') and not HasUndefinedVar(raw, ADefined) then
        EmitIssue(AIssues, P, tlkBadValue, prop, prop + ': ' + bad);
```

  （`HasUndefinedVar` = `CollectUndefinedVars` 收到了东西。值里有未定义变量时那条会在第二遍报，坏值不重复报。）

- [ ] **Step 4: 两个入口**：`TyLintCssEx` = 原 `TyLintCss` 的函数体（改用 `EmitIssue`，解析成功后 `BuildPositions`，`finally` 里释放）；`TyLintCss` 改为：

```pascal
function TyLintCss(const ASource: string; const ABaseDir: string): TTyLintResult;
var
  ex: TTyLintIssues;
  i: Integer;
begin
  Result := nil;
  ex := TyLintCssEx(ASource, ABaseDir);
  for i := 0 to High(ex) do
    if ex[i].Kind <> tlkBadValue then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := ex[i].Message;
    end;
end;
```

- [ ] **Step 5: fixture** `tests/fixtures/themebuilder/import-child.tycss`（两行：`/* imported by the lint position test */` 与 `TyButton { frobnicate: 1px; }`）。

- [ ] **Step 6: 判据测试**（`TTbLintExTests`；多行输入用 `#10` 拼；每条断言 `Line`、`Col`、`Kind`、`Severity`、`Subject`）：

| # | 输入 | 期望 | 在哪个变异下必须红 |
|---|---|---|---|
| L1 | `'TyButton {'`、`'  frobnicate: 1px;'`、`'  color: var(--ghost);'`、`'}'` | 两条：(2,3) `tlkUnknownProperty` error `frobnicate`；(3,3) `tlkUndefinedVar` error `ghost` | `ReadDeclBlock` 不记属性名（全是 0） |
| L2 | `':root {'`、`'  --a: #111;'`、`'  --a: var(--nope);'`、`'}'` | (3,3) `tlkUndefinedVar` `nope` | `ReadVarBlock` 已有的名字不改写（得到第 2 行） |
| L3 | `'@mode dark {'`、`'  :root {'`、`'    --x: var(--missing);'`、`'  }'`、`'}'` | (3,5) `missing` | `ModeVar` 查成 `RootVars` |
| L4 | `'/* c */'`、`'TyButton.primary:hover { background: #111111; color: #131313; }'` | (2,1) `tlkLowContrast` **warning** `TyButton.primary:hover` | 低对比度用 `Decls` 的位置（得到 (2,26)） |
| L5 | `'TyPanel {'`、`'  background-image: url(nope.png) slice(4 4 4 4);'`、`'}'`，`ABaseDir` = 临时目录 | (2,3) `tlkMissingAsset` warning `nope.png` | — |
| L6 | `'/* x */'`、`'@import "nope.tycss";'` | (2,1) `tlkMissingImport` error `nope.tycss` | 深度 0 不用 `Imports[ii]` |
| L7 | `'/* x */'`、`'@import "import-child.tycss";'`，`ABaseDir` = fixture 目录 | (2,1) `tlkUnknownProperty` `frobnicate`（导入文件里的问题落在 `@import` 那行） | 导入的 sheet 扫描时 `AFallback` 给 (0,0) |
| L8 | `'TyButton {'#10'  color red;'#10'}'` | 一条 (2,9) `tlkParseError` error，`Message` = `'parse error: '` + P1 的 `E.Message` | 解析失败时不从异常取位置 |
| L9 | `'TyButton {'`、`'  border-radius: 1px 2px 3px;'`、`'}'` | `Ex`：(2,3) `tlkBadValue` error `border-radius`，消息以 `'border-radius: '` 开头；`TyLintCss` 同一输入**为空** | ① `TyLintCss` 不滤 `tlkBadValue`；② `Ex` 不报坏值 |
| L10 | `'TyButton { padding: var(--undefined-pad); }'` | 只有一条 `tlkUndefinedVar`，没有 `tlkBadValue` | 去掉 `not HasUndefinedVar` 条件 |
| L11 | `'TyButton { color: var(--g); }'#10'TyEdit { color: var(--g); }'` | 两条 `tlkUndefinedVar`，行 1、行 2 | — |
| L12 | 金样本语料里每一份：`TyLintCss(x)` = `TyLintCssEx(x)` 中 `Kind <> tlkBadValue` 的 `Message` 按原顺序 | 逐条相等 | `TyLintCss` 改成先按行排序 |
| L13 | `themes/auto.tycss`（以 `themes/` 为 `ABaseDir`）：`Ex` 里每条 `Line` 都在 1..文件行数之间；**没有**位置为 0 的（它没有 `@import`） | — | `BuildPositions` 在第一个 `@mode` 之后就停（后面的规则位置全 0） |

  变异 **G2**：`EmitIssue` 里对 `tlkLowContrast` 改用 `rsLintUndefinedVar` → `TThemeLintGoldenTests.TestTheLintOutputIsUnchanged` 必须红。

- [ ] **Step 7: 注册与提交**：uses 加 `test.themebuilder.lint`。`feat(lint): TyLintCssEx says where each problem is, how bad and what kind` + Co-Authored-By（正文一句：旧 `TyLintCss` 的输出逐字不变，金样本守着）。

---

### Task 3: 拆出 `TTyCssEditKit`，设计期对话框改用它

**Files:**
- Create: `designtime/tyControls.Design.CssEditKit.pas`
- Modify: `designtime/tyControls.Design.Css.Editor.pas`、`tycontrols_dt.lpk`
- Create: `tests/test.themebuilder.editkit.pas`（suite `TTbCssEditKitTests`）
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: 新单元**：接口清单那一段 + 私有字段（`FEdit`、`FComplete`、`FHighlighter`、`FSelectorMode`、`FFormatOnLineLeave`、`FAutoComplete`、`FFormatting`、`FWantComplete`、`FLastLine`、`FPrevOnChange: TNotifyEvent`）。implementation 的 uses：`LCLType, tyControls.Css.Complete`。**不引** `PropEdits`、`IDEIntf` 的任何单元、`tyControls.Dialogs`。实现从 `Css.Editor.pas` 挪过来：

```pascal
constructor TTyCssEditKit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFormatOnLineLeave := True;
  FAutoComplete := True;
  FLastLine := 1;
end;

procedure TTyCssEditKit.Attach(AEdit: TSynEdit; ASelectorMode: Boolean);
begin
  Detach;
  FEdit := AEdit;
  FSelectorMode := ASelectorMode;
  FEdit.FreeNotification(Self);
  { Clamp the caret to real text: clicking past a line's end puts it AT the last
    character, not in virtual space past it. }
  FEdit.Options := FEdit.Options - [eoScrollPastEol];
  { tycss is a CSS dialect: the stock CSS highlighter colours comments, selectors,
    properties, values, braces and hex well enough; --tokens and darken() fall back to
    its identifier / function colouring. }
  FHighlighter := TSynCssSyn.Create(Self);
  FEdit.Highlighter := FHighlighter;
  FComplete := TSynCompletion.Create(Self);
  FComplete.Editor := FEdit;
  FComplete.OnExecute := @CompletionExecute;
  FComplete.ShortCut := 16416;   { Ctrl+Space }
  FComplete.EndOfTokenChr := '{}()[]:;,+*/\ ''"=<>!%';
  FPrevOnChange := FEdit.OnChange;
  FEdit.OnChange := @EditChange;
  FEdit.RegisterStatusChangedHandler(@HandleStatusChange, [scCaretY]);
  FEdit.RegisterBeforeKeyPressHandler(@BeforeKeyPress);
  FLastLine := FEdit.CaretY;
end;
```

  - `Detach`：`FEdit = nil` 就返回；`UnregisterStatusChangedHandler` / `UnregisterBeforeKeyPressHandler`；`FEdit.OnChange := FPrevOnChange`；编辑框的 `Highlighter` 还是我们的就置 `nil`；释放补全与高亮；`RemoveFreeNotification`；`FEdit := nil`。`Notification(opRemove)` 收到编辑框被释放时只把 `FEdit` 置 `nil`（不再碰它）。析构调 `Detach`。
  - `HandleStatusChange`：照原 `EditStatusChange`（`:218-239`），多一个开头 `if not FFormatOnLineLeave then begin FLastLine := FEdit.CaretY; Exit; end;`。
  - `BeforeKeyPress`：照原 `EditKeyPress`，加 `FAutoComplete` 条件。
  - `EditChange`：照原 `:278-292`（弹补全那段），然后 `if Assigned(FPrevOnChange) then FPrevOnChange(Sender)`。
  - `TextBeforeCaret`：`Lines[0..CaretY-2]` 用 `LineEnding` 连起来，再加 `Copy(LineText, 1, LogicalCaretXY.X - 1)`。
  - `FillCompletion` / `CompletionExecute`：`FComplete.ItemList.Clear; TyCssCompletionItems(TextBeforeCaret, FSelectorMode, FComplete.ItemList)`。

- [ ] **Step 2: 对话框改用它**（`Css.Editor.pas`）：字段 `FComplete`、`FLastLine`、`FFormatting`、`FWantComplete` 与方法 `EditStatusChange`、`EditKeyPress`、`CompletionExecute` 删掉，加 `FKit: TTyCssEditKit`；构造里 `FEdit` 建好、设完 `OnChange := @EditChange` 之后 `FKit := TTyCssEditKit.Create(Self); FKit.Attach(FEdit, ASelectorMode);`（`:130-147` 里被 kit 接管的几行删掉，`Gutter.Visible` 与 `Align` 留下）；`EditChange` 只剩警告条那段（`:269-273`）。implementation 的 uses 去掉 `SynEditTypes, SynCompletion, SynHighlighterCss`（若编译器提示还要就留），加 `tyControls.Design.CssEditKit`。`TTyStyleOverrideProperty` 与 `PropEdits` 原样。
- [ ] **Step 3: `.lpk`**：`tycontrols_dt.lpk` 的 `<Files>` 在 `Css.Editor` 那一项之前加

```xml
      <Item>
        <Filename Value="designtime/tyControls.Design.CssEditKit.pas"/>
        <UnitName Value="tyControls.Design.CssEditKit"/>
      </Item>
```

- [ ] **Step 4: 判据测试**（`TTbCssEditKitTests`；`TSynEdit.Create(nil)` 不设 Parent，kit 的 Owner 为 nil，测试自己释放）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| K1 | `Attach` 后：`Edit.Highlighter is TSynCssSyn`；`Completion.Editor = Edit`；`Completion.ShortCut = 16416`；`eoScrollPastEol` 不在 `Edit.Options` | `Attach` 不设高亮 |
| K2 | 选择器模式、文本 `'TyButton {'#10'  bac'`、光标在第 2 行末：`FillCompletion` 后 `ItemList` 含 `background`、**不含** `TyButton` | `TextBeforeCaret` 改回整篇文本（再在第 3 行加 `'}'#10'TyE'` 让整篇与光标前的上下文不同） |
| K3 | 同上文本，光标移到第 1 行第 1 列（`'T'` 前）：`ItemList` 含 `TyButton` | — |
| K4 | `OnChange` 串接：`Attach` 前给编辑框挂一个计数的 `OnChange`；`Attach` 后 `Edit.Lines.Add('x')` 触发（或直接调 `Edit.OnChange(Edit)`）→ 计数 1；`Detach` 后 `Edit.OnChange` 又是原来那个 | `Attach` 不存 `FPrevOnChange` |
| K5 | 离开行格式化：文本 `'TyButton{color:red}'#10'x'`，`CaretY := 1` 后 `CaretY := 2`，调 `HandleStatusChange(Edit, [scCaretY])` → 第 1 行 = `TyCssFormatLine('TyButton{color:red}')`，且与原文不同（先断言这一点）；`FormatOnLineLeave := False` 时同样操作第 1 行不变 | ① `HandleStatusChange` 不看 `FFormatOnLineLeave`；② `RegisterStatusChangedHandler` 没调（改为调 `Edit.OnStatusChange` 看 `Edit` 的状态钩子数——判据：`Attach` 后改 `CaretY` 触发了 kit 的处理，用 `FFormatOnLineLeave=True` 时第 1 行被改来证明；若无句柄的 SynEdit 不发状态变化，这条只留直接调用那半，签收里写一句） |
| K6 | `Edit.Free` 之后 kit 不崩：`kit.Edit = nil`，再 `kit.Free` 不 AV | `Notification` 不置 nil |
| K7 | 单元依赖：读 `designtime/tyControls.Design.CssEditKit.pas` 的文本，uses 里没有 `PropEdits`、`ComponentEditors`、`LazIDEIntf`、`IDEIntf`、`FormEditingIntf`、`tyControls.Dialogs` | 在 uses 里加 `PropEdits`（这条变异会让 tytests 编译失败——也算红） |
| K8 | `tycontrols_dt.lpk` 列了 `tyControls.Design.CssEditKit`（读 `.lpk` 文本）；`Css.Editor.pas` 里有 `TTyCssEditKit.Create` 与 `.Attach(`，没有 `TSynCompletion.Create`、`TSynCssSyn.Create` | 对话框恢复自建补全（`TSynCompletion.Create` 又出现） |

- [ ] **Step 5: 注册与提交**：uses 加 `test.themebuilder.editkit`。`refactor(designtime): the tycss SynEdit setup moves to TTyCssEditKit, shared with the theme builder` + Co-Authored-By（正文：补全现在看光标之前的文本；对话框的样子与按键不变；新单元不依赖 IDE）。

---

### Task 4: 工具工程骨架、文档模型、设置

**Files:**
- Create: `tools/themebuilder/themebuilder.lpi`、`themebuilder.lpr`、`tbdocument.pas`、`tbsettings.pas`、`tbthemesource.pas`
- Modify: `tests/tytests.lpi`（`OtherUnitFiles` 加 `../tools/themebuilder`）、`.gitignore`
- Create: `tests/test.themebuilder.doc.pas`（suites `TTbDocumentTests`、`TTbSettingsTests`；Task 5 再加 `TTbTemplatesTests`）
- Modify: `tests/tytests.lpr`

- [ ] **Step 1: `themebuilder.lpi`**（照 `examples/toolwindows/toolwindows_example.lpi` 的写法，改动：`Title` = `Theme Builder`；`RequiredPackages` = `LCL`、`BGRABitmapPack`、`SynEdit`（**不要** `tycontrols`）；`<Units>` 先列 `themebuilder.lpr`、`tbdocument.pas`、`tbsettings.pas`、`tbthemesource.pas`，后面任务逐个加（每个 `<UnitN>` 带 `<IsPartOfProject Value="True"/>` 与 `<UnitName>`，有窗体的再加 `<ComponentName>` 与 `<ResourceBaseClass Value="Form"/>` 或 `Frame`）；`OtherUnitFiles` = `.;../../source;../../designtime`；`<Target><Filename Value="themebuilder"/></Target>`；`i18n` 开、`OutDir` = `languages`；`Scaled`、`UseXPManifest`、`DpiAware = True/PM_V2`、`GraphicApplication = True`；没有 `<Icon>`）。
- [ ] **Step 2: `themebuilder.lpr`**：照 `examples/toolwindows/toolwindows_example.lpr`（`cthreads`、`Interfaces`、`{$R *.res}`、`LangDir`、`SetDefaultLang('', LangDir)`、`TranslateUnitResourceStringsEx('', LangDir, 'tycontrols', 'tyControls.StrConsts')`），`Application.CreateForm(TTbMainForm, TbMainForm)`——`tbmain` 在 Task 9 才有，本任务先写上（任务之间不编译）。
- [ ] **Step 3: `.gitignore`**：加一行 `/tools/themebuilder/themebuilder`（Linux / macOS 的可执行文件；`lib/`、`*.exe`、`*.res`、`*.rsj` 已被忽略）。
- [ ] **Step 4: `tbthemesource.pas`**：`TTbTextThemeSource`——`RootCss` = 文本；`AssetBaseDir` = `ABaseDir`（空串原样）；`ReadText` / `OpenAsset`：`ABaseDir` 为空返回 False，否则读 `ABaseDir + ARelPath`（文件不在返回 False）；`Manifest` = `Default(TTyThemeManifest)` 且 `Entry := 'theme.tycss'`；`RootName` = `'editor'`。
- [ ] **Step 5: `tbdocument.pas`**：
  - 读：`TFileStream` 读全部字节；以 `#$EF#$BB#$BF` 开头 → `FHasBom := True` 并去掉；`FindInvalidUTF8Codepoint(PChar(s), Length(s)) >= 0`（`LazUTF8`）→ `enc := GuessEncoding(s)`，`s := ConvertEncoding(s, enc, EncodingUTF8)`（`LConvEncoding`），`FConvertedFrom := enc`；`FLineEnding := TbDetectLineEnding(s)`；`FTrailingEol` = 最后一个字节是 `#10` 或 `#13`；`FText := s`；`FBasedOn := ''`；记 `FileAge` 与大小（`CaptureStamp`）。读失败抛异常，字段不变（先读进局部变量，全成功再赋值）。
  - `EditorText` = `FText`（SynEdit 自己认三种换行）。
  - 存：`s := TbJoinLines(ALines, FLineEnding, FTrailingEol)`；`FHasBom` 时前面加 BOM；写进 `AFileName`（`TFileStream` `fmCreate`）；成功后 `FFileName := ExpandFileName(AFileName)`、`FConvertedFrom := ''`、`CaptureStamp`。
  - `TbDetectLineEnding`：扫到第一个 `#13` 或 `#10`：`#13#10` → CRLF，单 `#13` → CR，`#10` → LF；没有换行时 `{$IFDEF MSWINDOWS}tleCRLF{$ELSE}tleLF{$ENDIF}`。
  - `TbJoinLines`：各行之间放换行符；`ATrailing` 且至少一行时末尾再放一个。
  - `DiskChanged`：`Untitled` 或文件不存在 → False；`FileAge` 或大小与快照不同 → 先 `CaptureStamp` 再返回 True。
  - `RegenerateHint`（开工前问题一第 6 条）：`dir := ExtractFileDir(FFileName)`；`root` = 往上两级；`FileExists(root + 'scripts' + PathDelim + 'gen-builtinthemes.ps1')` 不成立 → `''`；`ExtractFileName(dir) = 'builtin'` 且上级是 `themes`，或文件名是 `auto.tycss` / `system.tycss` 且所在目录名是 `themes` → `'gen-builtinthemes.ps1'`；文件名是 `light.tycss` 且目录名是 `themes` → `'gen-defaulttheme.ps1, gen-tycss-catalog.ps1'`；其余 `''`。（`root` 对 `themes/builtin/x` 是上两级，对 `themes/x` 是上一级——分别判断，写清楚。）
- [ ] **Step 6: `tbsettings.pas`**：`TIniFile`（`IniFiles`）；节 `[Editor]` `Theme`、`Dark`；`[Preview]` `Dark`、`Modern`；`[Recent]` `File0`..`File9`。`AddRecent`：先删掉已有的同名项（`{$IFDEF MSWINDOWS}SameText{$ELSE}=`），插到最前，超过 `TbMaxRecent` 截掉尾巴。`Save` 前 `ForceDirectories(ExtractFileDir(FFileName))`。`TbDefaultSettingsFile` = `IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'themebuilder.ini'`。
- [ ] **Step 7: 测试工程路径**：`tests/tytests.lpi` 的 `OtherUnitFiles` 改为 `../source;.;../examples/terminal;../designtime;../tools/themebuilder`。
- [ ] **Step 8: 判据测试**（文件都建在测试自己的临时目录，`TearDown` 删掉；字节用 `TFileStream` 读回比较）：

  `TTbDocumentTests`：

| # | 输入字节 | 期望 | 在哪个变异下必须红 |
|---|---|---|---|
| D1 | `'a {}'#10'b {}'#10` | `LineEnding = tleLF`、`TrailingEol`、无 BOM；装进一个 `TSynEdit.Lines`（`Lines.Text := EditorText`）再 `SaveToFile` 到另一个文件 → 字节与原文件相同 | `TbJoinLines` 固定用 `LineEnding` 常量 |
| D2 | `'a {}'#13#10'b {}'#13#10` | 同上，CRLF | — |
| D3 | `'a {}'#13#10'b {}'`（文末无换行） | 往返字节相同 | 存时不看 `FTrailingEol` |
| D4 | `#$EF#$BB#$BF'a {}'#10` | `HasBom`；`EditorText` 不以 BOM 开头；往返字节相同 | 存时不写 BOM |
| D5 | `'a {}'#13'b {}'#13` | `tleCR`，往返相同 | — |
| D6 | `'/* '#$E9' */'#10`（Latin-1 的 é，非法 UTF-8） | `ConvertedFrom <> ''`；`EditorText` 是合法 UTF-8 且含 `é` 的 UTF-8 两字节 | 不检查 UTF-8 |
| D7 | 仓库 `themes/builtin/win11.tycss` 的工作区字节复制到临时目录 | 往返字节相同（这份在 Windows 检出是 CRLF） | — |
| D8 | `DiskChanged`：打开后立刻问 → False；往文件末尾追加一个字节 → True；再问 → False；删掉文件 → False；`SaveToFile` 后立刻问 → False | 先记戳再返回的那句挪到返回之后（第二问仍 True） |
| D9 | 读失败（不存在的文件）：抛异常，`FileName`、`EditorText` 保持原来那份 | 先赋字段再读 |
| D10 | `RegenerateHint`：临时目录里造 `root/scripts/gen-builtinthemes.ps1`（空文件）与 `root/themes/builtin/x.tycss`、`root/themes/auto.tycss`、`root/themes/light.tycss`、`root/themes/palettes/p.tycss`；另一个没有 `scripts/` 的 `other/themes/builtin/x.tycss` | 分别 `'gen-builtinthemes.ps1'`、`'gen-builtinthemes.ps1'`、含 `gen-defaulttheme.ps1`、`''`、`''` | 不查 `scripts/`（`other/` 那份也提醒） |

  `TTbSettingsTests`：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| S1 | 空文件 `Load` → `EditorTheme = 'default'`，其余 False，`Recent.Count = 0` | — |
| S2 | 各值设好 `Save`、另建一个 `Load` → 全部相同，`Recent` 顺序相同 | `Save` 漏写 `[Preview]` |
| S3 | `AddRecent` 12 个不同文件 → 10 个，最前是最后加的；再加第 3 个 → 它挪到最前、总数不变；Windows 上大小写不同算同一个 | 去掉去重 |
| S4 | `Save` 到不存在的子目录 → 建出来 | 去掉 `ForceDirectories` |

- [ ] **Step 9: 注册与提交**：uses 加 `test.themebuilder.doc`。`feat(themebuilder): the project, the document model and the settings` + Co-Authored-By。

---

### Task 5: 新建模板

**Files:**
- Create: `tools/themebuilder/tbtemplates.pas`
- Modify: `tools/themebuilder/themebuilder.lpi`（`<Units>` 加一项）、`tests/test.themebuilder.doc.pas`（suite `TTbTemplatesTests`）

- [ ] **Step 1: 单元**：

```pascal
resourcestring
  rsTbBasedOn = 'Based on the built-in theme "%s".';
  rsTbMinimalHeader = 'A minimal theme: the six seeds, light and dark. Everything else comes from the base theme.';

function TbBuiltinHeader(const AName: string): string;
begin
  Result := '/* ' + Format(rsTbBasedOn, [AName]) + ' */' + LineEnding + LineEnding;
end;

function TbFromBuiltin(const AName: string): string;
var
  css: string;
begin
  css := TyBuiltinThemeCss(AName);
  if css = '' then
    Exit('');
  Result := TbBuiltinHeader(AName) + css;
end;
```

  `TbMinimalTemplate`：`'/* ' + rsTbMinimalHeader + ' */'`，空一行，`@mode light` 块（`:root` 里六个种子，一行一个，值见核实记录 31），空一行，`@mode dark` 块。换行用 `LineEnding`；缩进两格 / 四格照 `themes/auto.tycss`。注释里不出现 `*/`。

- [ ] **Step 2: 判据测试**（`TTbTemplatesTests`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| T1 | 每个 `TyBuiltinThemeNames` 的名字：`TbFromBuiltin(n)` 以 `TbBuiltinHeader(n)` 开头，其余部分与 `TyBuiltinThemeCss(n)` 逐字节相同；`TbFromBuiltin('nope') = ''` | 头注释后少一个换行（其余部分对不上） |
| T2 | 极简模板在两个模式下都能用：新建 `TTyStyleController`，`Model.LoadFromCss(模板)` 不抛；`Model.ModeNames` 恰为 light、dark；`Mode := 'light'` 后 `TbProbeResolve`（Task 7 的 `tbpreview.pas`；任务之间不编译，Task 12 一起编）返回 True，`'dark'` 同样 | 暗色块整块删掉（`ModeNames` 只剩一个）；另试「暗色块漏 `--radius`」：底层有它，试解析仍过——这一变异「等价」，签收写明 |
| T3 | 模板里六个种子各出现两次（亮、暗各一），值与核实记录 31 相同（按文本 `'--accent: #3B82F6;'` 等查找） | 暗色 `--surface` 抄成亮色的值 |
| T4 | `TyLintCssEx(模板)` 没有任何问题 | — |

- [ ] **Step 3: 提交**：`feat(themebuilder): new documents from a built-in theme or a minimal template` + Co-Authored-By。

---

### Task 6: 问题收集

**Files:**
- Create: `tools/themebuilder/tbproblems.pas`、`tests/test.themebuilder.problems.pas`（suite `TTbProblemsTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: `TbBaseVarNames`**：建一个 `TTyStyleModel`（不加载任何东西 = 只有底层），对 `''`、`'light'`、`'dark'` 三个模式各 `SetMode`，对 `TyCatalogTokens` 里每个名字 `RawVar(名)` 非空就把 `LowerCase(Copy(名, 3, MaxInt))` 加进 `ADest`（`Sorted`、`Duplicates := dupIgnore`）；最后释放模型。
- [ ] **Step 2: `TbCollectProblems`**：

```pascal
function TbCollectProblems(const AText, ABaseDir: string; AUntitled: Boolean;
  ABaseVars: TStrings): TTbProblems;
var
  issues: TTyLintIssues;
  i: Integer;
begin
  Result := nil;
  issues := TyLintCssEx(AText, ABaseDir);
  for i := 0 to High(issues) do
  begin
    { the engine resolves a variable the base defines; lint only knows the document's }
    if (issues[i].Kind = tlkUndefinedVar) and (ABaseVars <> nil)
       and (ABaseVars.IndexOf(LowerCase(issues[i].Subject)) >= 0) then
      Continue;
    AppendLint(Result, issues[i]);
  end;
  if AUntitled then
    AddUnsavedAssetHints(Result, AText);
  SortProblems(Result);
end;
```

  - `AddUnsavedAssetHints`：逐行扫（跳过 `/* */` 注释，注释可跨行——用一个 in-comment 标志），行里有 `url(` 且括号里不是 `data:` 开头 → 一条 `tlsWarning`、`tpoDocument`、该行、`url(` 的字节列，文字 `rsTbSaveForAssets`（`'Save the file first: url() paths are read from the file''s folder.'`）。一行只报一次。
  - `SortProblems`：稳定插入排序，键 = (`Line = 0` 在前, `Line`, `Col`)。`TbAddProblem` 按同一个键把新条目插到「键相同的已有条目之后」，所以列表始终有序、不用再排。
  - `TbProblemCaption`：`Line > 0` → `Format('%d:%d  %s', [Line, Col, Text])`；否则 `'—  ' + Text`。
  - `TbHasParseError`：有 `Origin = tpoLint` 且 `Kind = tlkParseError` 的。`TbErrorCount`：`Severity = tlsError` 的条数。
- [ ] **Step 3: 判据测试**（`TTbProblemsTests`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| R1 | `TbBaseVarNames` 含 `accent`、`surface-hover`、`muted`；不含 `accent` 以外带 `--` 的写法（都去掉了前缀、小写） | 去掉 `Copy(名, 3, ...)`（全带 `--`，下一条随之红） |
| R2 | `'TyButton { background: var(--surface-hover); color: var(--nope); }'` → 一条问题，`Kind = tlkUndefinedVar`、文字含 `nope`；**先**证明不传 `ABaseVars`（nil）时是两条 | 去掉过滤 |
| R3 | 未保存 + `'TyPanel {'#10'  background-image: url(a.png) slice(1 1 1 1);'#10'}'` → 有一条 `tpoDocument` 在 (2, `url(` 的列)；同一文本 `AUntitled = False` → 没有这条；`'/* url(x) */'` 未保存 → 没有 | 不跳过注释 |
| R4 | 排序：解析失败的文本给一条 `tlkParseError`；多问题的文本按行升序；往 L1 的结果里 `TbAddProblem(…, 0, 0, …)` 两条 → 它们排在最前、彼此保持加入顺序，其余不动 | ① 排序把 `Line = 0` 放最后；② `TbAddProblem` 只追加到末尾 |
| R5 | `TbProblemCaption`：(12,5,'x') → `'12:5  x'`；(0,0,'y') → 以 `'—'` 开头 | — |
| R6 | `TbHasParseError` 对 L8 的输入为 True、对 L1 为 False；`TbErrorCount` 对 L4 的输入为 0（低对比度是警告） | `TbErrorCount` 不看严重度 |

- [ ] **Step 4: 注册与提交**：uses 加 `test.themebuilder.problems`。`feat(themebuilder): the problem list from lint, without variables the base defines` + Co-Authored-By。

---

### Task 7: 预览 frame——八页、独立控制器、加载与试解析

**Files:**
- Create: `tools/themebuilder/tbpreview.pas`、`tbpreview.lfm`
- Create: `tests/test.themebuilder.preview.pas`（suite `TTbPreviewTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/tytests.lpr`

- [ ] **Step 1: `.lfm` 结构**（`object PreviewFrame: TTbPreviewFrame`，所有 `Caption` 用英文；写法照 `examples/antdesign/umain.lfm`、`examples/toolwindows/umain.lfm`、`examples/button/umain.lfm`；尺寸用 `AutoSize` 或留足余量——换肤会撑宽，仓库记忆「换肤会撑破写死的宽度」）：
  - `Tools: TTyPanel`（`alTop`，高约 36，**工具皮肤**）：`DarkSwitch: TTyToggleSwitch`（`Caption = 'Dark'`）、`DensityCombo: TTyComboBox`（项目在代码里填）、`DisableAllCheck: TTyCheckBox`（`Caption = 'Disable all'`）、`ModeNote: TTyLabel`（初始空）。三个事件 `DarkSwitchChange`、`DensityComboChange`、`DisableAllCheckChange` 在 `.lfm` 里挂。
  - `Root: TTyPanel`（`alClient`，**预览皮肤**），里面 `Pages: TTyPageControl`（`alClient`）八个 `TTyTabSheet`，顺序与 `Caption`：`TabBasic 'Basic'`、`TabInputs 'Inputs'`、`TabLists 'Lists and trees'`、`TabGrids 'Grids'`、`TabContainers 'Containers and tabs'`、`TabMenus 'Menus and toolbars'`、`TabChrome 'Window chrome'`、`TabFeedback 'Feedback'`。每页内容：

| 页 | 控件（名字 → 类，变体 / 状态） |
|---|---|
| Basic | `BtnDefault` `TTyButton` 'Default'；`BtnPrimary` StyleClass `primary`；`BtnDanger` `danger`；`BtnGhost` `ghost`；`BtnDisabled` `Enabled = False`；`BtnPrimaryDisabled` `primary` + 禁用；`SpdGhost` `TTySpeedButton` `ghost` 带 Lucide 字形（`IconFont` 用 frame 里的 `LucideFont: TTyLucideIconFont`，`GlyphName = 'star'`）；`DdbMore` `TTyDropDownButton` 'More'；`LblNormal` `TTyLabel` 'Label'；`LblDisabled` 禁用；`LnkSample` `TTyLinkLabel` 'Link'；`ChkOn` / `ChkOff` / `ChkDisabled` `TTyCheckBox`；`RadOn` / `RadOff` `TTyRadioButton`；`TglOn` / `TglOff` `TTyToggleSwitch`；`TagPlain` / `TagAccent`（`accent`）/ `TagDanger`（`danger`）`TTyTag`；`BadgeSample` `TTyBadge`；`DivSample` `TTyDivider` |
| Inputs | `EdtText` `TTyEdit`（有文字）；`EdtHint`（`TextHint = 'Placeholder'`）；`EdtDisabled`；`EdtReadOnly`（`ReadOnly = True`）；`MemoSample` `TTyMemo`（三行）；`CmbSample` `TTyComboBox`；`SpnSample` `TTySpinEdit`；`DtpSample` `TTyDateTimePicker`；`TrkSample` `TTyTrackBar`；`RatSample` `TTyRating` |
| Lists and trees | `LstSample` `TTyListBox`（5 项）；`ClbSample` `TTyCheckListBox`（4 项）；`TreSample` `TTyTreeView`（`.lfm` 里 `Items`，两层）；`LvwSample` `TTyListView`（report 风格；列与行在代码里填） |
| Grids | `GrdSample` `TTyStringGrid`（行列与内容在代码里填，一行固定行）；`VleSample` `TTyValueListEditor`（4 对） |
| Containers and tabs | `PnlSample` `TTyPanel`；`GrpSample` `TTyGroupBox` 'Group'；`CrdSample` `TTyCard`；`ExpSample` `TTyExPanel` 'Expandable'；`TabsSample` `TTyTabSet`（标签在代码里填）；`InnerPages` `TTyPageControl` 三个 `TTyTabSheet`（'One'、'Two'、'Three'）；`SbxSample` `TTyScrollBox`（内容比它高，出滚动条）；`SplLeft` `TTyPanel` + `SplSample` `TTySplitter` + `SplRight` `TTyPanel` |
| Menus and toolbars | `MnbSample` `TTyMenuBar`（`Menu = SampleMenu`）；`TbrSample` `TTyToolBar` 放四个 `TTyToolButton`（一个 `Down`、一个禁用）与一个 `TTyToolSeparator`；`StbSample` `TTyStatusBar`（三个面板，代码里填）；`BtnPopup` `TTyButton` 'Show a popup menu'；`BrcSample` `TTyBreadcrumb`（代码里填） |
| Window chrome | `LblChromeNote` `TTyLabel`（'The title bar, its buttons and the shadow are drawn on a real window.'）；`BtnSampleWindow` `TTyButton` 'Open a sample window'；`ScbH` / `ScbV` `TTyScrollBar`（横、竖）；`ScbDisabled` 禁用 |
| Feedback | `PrgSample` `TTyProgressBar`（`Position = 60`，`AnimationsEnabled = False`）；`PrgDisabled` 禁用；`CprSample` `TTyCircularProgress`；`ActSample` `TTyActivityIndicator`；`AlrInfo` / `AlrSuccess` / `AlrWarning` / `AlrError` `TTyAlert`（`AlertType`）；`EmpSample` `TTyEmpty`；`BtnMessage` 'Message dialog'；`BtnInput` 'Input dialog'；`BtnNotify` 'Notification' |

  - 非可视：`SampleMenu: TMainMenu`（File / Edit / View；含一个带快捷键的、一个 `Checked` 的、一个禁用的、一个分隔线、一个子菜单）、`SamplePopup: TTyPopupMenu`（四项，同上几种）、`SampleNotify: TTyNotification`、`LucideFont: TTyLucideIconFont`。
  - 按钮事件（`BtnPopupClick`、`BtnSampleWindowClick`、`BtnMessageClick`、`BtnInputClick`、`BtnNotifyClick`）在 `.lfm` 里挂，本任务先写空方法，Task 8 填。
- [ ] **Step 2: `TbApplyController`**：

```pascal
procedure TbApplyController(ARoot: TWinControl; AController: TTyStyleController);

  procedure SetOne(AControl: TControl);
  begin
    { the two Ty bases share no ancestor that publishes Controller }
    if AControl is TTyCustomControl then
    begin
      if TTyCustomControl(AControl).Controller <> AController then
        TTyCustomControl(AControl).Controller := AController;
    end
    else if AControl is TTyGraphicControl then
    begin
      if TTyGraphicControl(AControl).Controller <> AController then
        TTyGraphicControl(AControl).Controller := AController;
    end;
  end;

  procedure Walk(AParent: TWinControl);
  var
    i: Integer;
  begin
    for i := 0 to AParent.ControlCount - 1 do
    begin
      SetOne(AParent.Controls[i]);
      if AParent.Controls[i] is TWinControl then
        Walk(TWinControl(AParent.Controls[i]));
    end;
  end;

begin
  if ARoot = nil then Exit;
  SetOne(ARoot);
  Walk(ARoot);
end;
```

- [ ] **Step 3: 构造与析构**：

```pascal
constructor TTbPreviewFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);          { the .lfm is read and Loaded has run }
  FController := TTyStyleController.Create(Self);
  FDialogOwner := TTyForm.CreateNew(Self);
  FDialogOwner.Controller := FController;
  FillCodeOnlyData;                  { list view rows, grid cells, tabs, status panels, crumbs, combo items }
  TbApplyController(Root, FController);
  SamplePopup.Controller := FController;
  SampleNotify.Controller := FController;
  DensityCombo.Items.Add(rsTbDensityClassic);
  DensityCombo.Items.Add(rsTbDensityModern);
  DensityCombo.ItemIndex := 0;
  UpdateModeNote;
end;
```

  析构：`FreeAndNil(FSampleWin)`、`FreeAndNil(FDialogOwner)`（都在控制器之前），`FDisabled` 表释放，然后 `inherited`（控制器归 frame 所有，随组件释放；控件对它有 `FreeNotification`）。`FillCodeOnlyData` 在 `TbApplyController` **之前**（组合控件的子项跟着拿到控制器）。

- [ ] **Step 4: 加载**：

```pascal
function TTbPreviewFrame.LoadInto(const AText, ABaseDir: string; out AError: string): Boolean;
var
  src: ITyThemeSource;
begin
  AError := '';
  src := TTbTextThemeSource.Create(AText, ABaseDir);
  try
    FController.Model.LoadFromSource(src);   { fail-fast: on a raise the old layer stays }
    if FController.Density = tdModern then
      FController.Model.LoadFromCssAdditive(TyDensityModernCss);
    FController.Changed;                     { repaint + seed the mode of a dual-mode theme }
  except
    on E: Exception do
    begin
      AError := E.Message;
      Exit(False);
    end;
  end;
  Result := TbProbeResolve(FController.Model, AError);
end;

function TTbPreviewFrame.LoadDocument(const AText, ABaseDir: string; out AError: string): Boolean;
var
  back: string;
begin
  Result := LoadInto(AText, ABaseDir, AError);
  if Result then
  begin
    FGoodText := AText;
    FGoodDir := ABaseDir;
    FModeError := '';
  end
  else
    { a load that raised left the model as it was, but one that loaded and then failed
      the probe did not: put the last good version back (or the bare base) }
    if not LoadInto(FGoodText, FGoodDir, back) then
      LoadInto('', '', back);
  UpdateModeNote;
end;
```

  `UpdateModeNote`：`HasModes`（`Length(FController.Model.ModeNames) > 0`）为 False 时 `DarkSwitch.Enabled := False`、`ModeNote.Caption := rsTbSingleMode`（'One mode only'）；否则启用、清空。

- [ ] **Step 5: 试解析**：

```pascal
function TbProbeResolve(AModel: TTyStyleModel; out AError: string): Boolean;
const
  cStates: array[0..5] of TTyStateSet = ([], [tysHover], [tysActive], [tysFocused],
    [tysDisabled], [tysSelected]);
var
  k, v, s: Integer;
  variants: TStringList;
  key, cls: string;
begin
  AError := '';
  variants := TStringList.Create;
  try
    for k := 0 to High(TyCatalogTypeKeys) do
    begin
      key := TyCatalogTypeKeys[k];
      variants.Clear;
      variants.Add('');
      AModel.GetVariantsForType(key, variants);
      for v := 0 to variants.Count - 1 do
        for s := 0 to High(cStates) do
        begin
          cls := variants[v];
          try
            AModel.ResolveStyle(key, cls, cStates[s]);
          except
            on E: Exception do
            begin
              if cls <> '' then key := key + '.' + cls;
              AError := key + ': ' + E.Message;
              Exit(False);
            end;
          end;
        end;
    end;
  finally
    variants.Free;
  end;
  Result := True;
end;
```

- [ ] **Step 6: 判据测试**（`TTbPreviewTests`；`SetUp` 记下 `TyDefaultController` 的 `ThemeName` / `Mode` / `Density`，`TearDown` 还原；frame 用 `TTbPreviewFrame.Create(nil)`，不设 Parent；文档里用一个一定和底层不同的值：`'TyButton { background: #123456; }'`，以下称「标记文档」）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| V1 | 建好后 `Pages.PageCount = 8`，标题依次是八个英文名 | — |
| V2 | `Root` 下（含）每个 Ty 控件的 `Controller = frame.Controller`，数量 `StyledControlCount >= 60`；`Tools` 里的三个控件 `Controller = nil`；`SamplePopup.Controller`、`SampleNotify.Controller` 都是预览控制器 | ① `TbApplyController` 不递归；② 构造里不给 `SamplePopup` 设 |
| V3 | 独立：加载标记文档返回 True，`BtnDefault` 经 `ActiveController.Model.ResolveStyle('TyButton','',[])` 得到的背景色 = `$123456`（先断言加载前不是）；`TyDefaultController.Model.ThemeVersion` 在加载前后不变，`TyDefaultController` 解析 `TyButton` 的背景不是 `$123456` | 把 `FController` 换成 `TyDefaultController`（接线变异） |
| V4 | 先加载标记文档，再加载坏文档（`'TyButton { color: red'`）：返回 False、`AError` 非空；预览控制器的 `ThemeVersion` 与按钮背景（`$123456`）都和坏文档之前相同 | — |
| V5 | 只在亮色定义的变量：`'@mode light { :root { --x: #ffffff; } } @mode dark { :root { --z: #000000; } } TyButton { background: var(--x); }'` 在亮色下加载 → True（切暗色在 Task 8 的 V10 测） | — |
| V6 | 亮色下缺变量：`'@mode light { :root { --z: #ffffff; } } @mode dark { :root { --x: #000000; } } TyButton { background: var(--x); }'` ：先加载标记文档，再加载它 → 返回 False（种子模式是 light，试解析抛），`AError` 含 `TyButton`；之后按钮背景仍是 `$123456`、`HasModes = False`（退回了上一版，不是停在这份双模式文档上） | ① 去掉 `TbProbeResolve` 调用；② 试解析失败后不重新加载上一版 |
| V7 | `url()` 按目录：临时目录放一个 `a.png`（任意 1×1 PNG），文档 `'TyPanel { background-image: url(a.png) slice(0 0 0 0); }'` 以该目录加载 → `ResolveStyle('TyPanel','',[]).Background.ImagePath` 等于该目录下 `a.png` 的全路径（大小写不敏感比）；同一文档以 `''` 加载 → `ImagePath` 不含该目录 | `LoadInto` 传 `''` 当目录（`TTbTextThemeSource.AssetBaseDir` 返回空） |
| V8 | 单模式文档（标记文档）加载后 `HasModes = False`、`DarkSwitch.Enabled = False`、`ModeNote.Caption <> ''`；双模式（极简模板）→ 反过来 | 不调 `UpdateModeNote` |
| V9 | 试解析真的走到了变体与状态：`'@mode light { :root { --z: #ffffff; } } @mode dark { :root { --y: #000000; } } TyButton.primary:hover { background: var(--y); }'` 亮色下加载 → 返回 False，`AError` 以 `'TyButton.primary: '` 开头 | 试解析只试 `[]` 状态（`:hover` 那条漏掉，返回 True）；只试无变体（同上） |

- [ ] **Step 7: 注册与提交**：uses 加 `test.themebuilder.preview`。`feat(themebuilder): the preview frame, its own controller and a load that never leaves it broken` + Co-Authored-By。

---

### Task 8: 预览的开关与弹出物

**Files:**
- Modify: `tools/themebuilder/tbpreview.pas`、`tbpreview.lfm`（事件已挂，只填方法）
- Create: `tools/themebuilder/tbsamplewin.pas`、`tbsamplewin.lfm`
- Modify: `tools/themebuilder/themebuilder.lpi`、`tests/test.themebuilder.preview.pas`

- [ ] **Step 1: 明暗**：

```pascal
function TTbPreviewFrame.SetDark(ADark: Boolean; out AError: string): Boolean;
var
  old, want: string;
begin
  AError := '';
  if ADark then want := 'dark' else want := 'light';
  old := FController.Mode;
  if SameText(old, want) then Exit(True);
  FController.Mode := want;
  Result := TbProbeResolve(FController.Model, AError);
  if not Result then
  begin
    FController.Mode := old;
    { the mode's display name, not its internal one: it is read in the problem list }
    if ADark then
      AError := Format(rsTbModeFailed, [rsTbModeDark, AError])    { 'In %s mode: %s' }
    else
      AError := Format(rsTbModeFailed, [rsTbModeLight, AError]);
  end;
  FModeError := AError;
end;
```

  `DarkSwitchChange`：`FUpdating` 时返回；调 `SetDark(DarkSwitch.Checked, err)`；失败就 `FUpdating := True; DarkSwitch.Checked := not DarkSwitch.Checked; FUpdating := False`；最后 `if Assigned(FOnChanged) then FOnChanged(Self)`。`IsDark` = `SameText(FController.Mode, 'dark')`。

- [ ] **Step 2: 密度**：`SetModern(AModern)`：`FController.Density := tdModern / tdClassic`（它会重装成底层，核实记录 23）；然后 `LoadInto(FGoodText, FGoodDir, err)`（失败就 `LoadInto('', '', err)`）；明暗照旧（`Mode` 不受重装影响——若测试发现被清，先记下、重装后再设回去）。`DensityComboChange` 调它再 `OnChanged`。
- [ ] **Step 3: 全部禁用**：`SetAllDisabled(True)`：遍历 `Pages` 下（含嵌套）每个 `TControl`，是 Ty 控件（两种基类）就把 `(控件, 原 Enabled)` 记进 `FDisabled`（`TFPList` 存一个小记录）并设 `Enabled := False`；`Pages` 本身不动（还能翻页）。`SetAllDisabled(False)`：按记录还原，清空记录。已经是这个状态就不重复做。`DisableAllCheckChange` 调它。
- [ ] **Step 4: 弹出物**：
  - `BuildSampleDialog`：`d := TyBuildMessageDialog(rsTbSampleMessage, mtConfirmation, [mbYes, mbNo, mbCancel]); Application.RemoveComponent(d); FDialogOwner.InsertComponent(d); Result := d;`（注释：为什么换 Owner——`ApplyOwnerController` 取 Owner 的控制器，否则取主窗体的，即工具的皮肤）。`BtnMessageClick`：`d := BuildSampleDialog; try d.ShowModal; finally d.Free; end;`。
  - `BtnInputClick`：`d := TyBuildInputDialog(rsTbSampleInputTitle, rsTbSampleInputPrompt, 'theme', edt)`（`Dialogs.pas:141`），同样换 Owner（先核实它也以 `Application` 为 Owner，`:881-`；不是的话按实际挪）再 `ShowModal`、`Free`。
  - `BtnPopupClick`：`p := BtnPopup.ClientToScreen(Point(0, BtnPopup.Height)); SamplePopup.PopUp(p.X, p.Y);`。
  - `BtnNotifyClick`：`SampleNotify.Title := rsTbSampleNotifyTitle; SampleNotify.Message := rsTbSampleNotifyText; SampleNotify.Show;`（`Notification.pas:309-336`）。
- [ ] **Step 5: 样例窗体** `tbsamplewin.lfm`：`object TbSampleForm: TTbSampleForm`，`TitleBar = Bar`，`Caption = 'Sample window'`，宽 420 高 280，`Position = poScreenCenter`；`Surface: TTyFormSurface`（`alClient`）里 `Bar: TTyTitleBar`（`alTop`，`Caption = 'Sample window'`）、`LblText: TTyLabel`（'A real window: title bar buttons, frame and shadow.'）、`EdtName: TTyEdit`、`ChkRemember: TTyCheckBox`（'Remember'）、`BtnOk: TTyButton`（'OK'，`primary`，`ModalResult` 不设）、`BtnCancel: TTyButton`（'Cancel'）；两个按钮的 `OnClick` 都是 `Close`。`UseController(ACtl)`：`Controller := ACtl; TbApplyController(Surface, ACtl); ApplyChromeTheme(ACtl);` 并 `ACtl.AddChangeListener(@ControllerChanged)`（`ControllerChanged` = `ApplyChromeTheme(Controller)`）；`FormDestroy` 里 `RemoveChangeListener`。
  - frame 的 `BuildSampleWindow`：`FSampleWin = nil` 时 `FSampleWin := TTbSampleForm.Create(Self); FSampleWin.UseController(FController);`，返回它。`ShowSampleWindow` = `BuildSampleWindow.Show`。
- [ ] **Step 6: resourcestring**（`tbpreview.pas`）：`rsTbDensityClassic = 'Classic'`、`rsTbDensityModern = 'Modern'`、`rsTbSingleMode = 'One mode only'`、`rsTbModeFailed = 'In %s mode: %s'`、`rsTbModeLight = 'light'`、`rsTbModeDark = 'dark'`、`rsTbSampleMessage = 'Save the changes to this theme?'`、`rsTbSampleInputTitle = 'Rename'`、`rsTbSampleInputPrompt = 'New name:'`、`rsTbSampleNotifyTitle = 'Saved'`、`rsTbSampleNotifyText = 'The theme was saved.'`，以及 `FillCodeOnlyData` 用到的样例文字（列表视图的列名与行、表格内容、标签页名、状态栏面板、面包屑）——全部 resourcestring，名字以 `rsTbSample` 开头。
- [ ] **Step 7: 判据测试**（接着写 `TTbPreviewTests`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| V10 | V5 的文档亮色加载后 `SetDark(True)` → False，`AError` 以 `Format(rsTbModeFailed, [rsTbModeDark, ''])` 开头且含 `TyButton`；`IsDark = False`；`ModeError` 非空；再 `SetDark(False)` → True | 失败后不退回原模式（`IsDark = True`） |
| V11 | 极简模板：`SetDark(True)` → True、`IsDark`；加载一份新文本后 `ModeError = ''` | — |
| V12 | 换密度后文档还在：标记文档加载后 `SetModern(True)` → `Controller.Density = tdModern`，按钮背景仍是 `$123456`；`SetModern(False)` 同样 | `SetModern` 不重新加载（按钮背景回到底层） |
| V13 | 全部禁用：`SetAllDisabled(True)` → `BtnDefault`、`EdtText`、`TreSample`、`InnerPages` 都 `Enabled = False`，`Pages.Enabled` 仍 True；`SetAllDisabled(False)` → 它们 True，而 `BtnDisabled`、`EdtDisabled` 仍 False | 还原时一律设 True |
| V14 | 样例对话框：`d := BuildSampleDialog; d.ApplyControllerNow` → `d.Controller = 预览控制器`、`d.Buttons[0].Controller = 预览控制器`；测试里 `Application.MainForm` 为 nil | 去掉换 Owner 那两句（`d.Controller` 为 nil） |
| V15 | 样例窗体：`BuildSampleWindow` 两次返回同一个；它的 `Controller`、`EdtName.Controller`、`BtnOk.Controller` 都是预览控制器；`TitleBar = Bar`；释放 frame 不 AV（窗体先于控制器释放） | `UseController` 不调 `TbApplyController` |
| V16 | 样例窗体跟着改：它建好后预览加载标记文档 → `BtnCancel`（默认样式的按钮）解析出的背景变成 `$123456`（先断言加载前不是） | `BuildSampleWindow` 给窗体设的是 `TyDefaultController` |

- [ ] **Step 8: 提交**：`feat(themebuilder): light and dark, density and disable-all in the preview; dialogs, menus and a real window in its theme` + Co-Authored-By。

---

### Task 9: 主窗体——布局、新建 / 打开 / 保存、问题列表

**Files:**
- Create: `tools/themebuilder/tbmain.pas`、`tbmain.lfm`
- Create: `tests/test.themebuilder.main.pas`（suite `TTbMainFormTests`）
- Modify: `tools/themebuilder/themebuilder.lpi`（`<Units>` 列全：`tbmain`、`tbpreview`、`tbsamplewin`、`tbtemplates`、`tbproblems`、`tbdocument`、`tbsettings`、`tbthemesource`、`tbeditorlook`——最后一个 Task 10 才建，本任务先列上）、`tests/tytests.lpr`

- [ ] **Step 1: `.lfm`**（`object TbMainForm: TTbMainForm`，`TitleBar = Bar`，`MenuBar = MainMenuBar`，宽 1280 高 680——别超过常见笔记本工作区，仓库记忆「窗口比工作区高就拖不动」，`Position = poScreenCenter`，`OnCreate` / `OnDestroy` / `OnCloseQuery`）：
  - `Surface: TTyFormSurface`（`alClient`）
    - `Bar: TTyTitleBar`（`alTop`，`Caption = 'Theme Builder  · TyControls'`），里面 `MainMenuBar: TTyMenuBar`（`Menu = MainMenu1`、`AutoSizeWidth = True`）
    - `Status: TTyStatusBar`（`alBottom`，三个面板：消息、`Ln, Col`、换行符与编码）
    - `SideBar: TTyToolWindowBar`（`alLeft`，`ExpandedSize = 280`，`Images = Icons`），里面 `ProblemsWin: TTyToolWindow`（`Caption = 'Problems'`、`ImageName = 'circle-alert'`、`StripHint = 'Problems'`、`ShowBadge = True`），窗口里 `ProblemsList: TTyListBox`（`alClient`，`OnDblClick = ProblemsListDblClick`）
    - `PreviewHost: TTyPanel`（`alRight`，宽 560）
    - `PreviewSplitter: TTySplitter`（`alRight`）
    - `Editor: TSynEdit`（`alClient`，`Gutter.Visible = True`，`OnChange = EditorChange`，`OnStatusChange = EditorStatusChange`，`OnSpecialLineMarkup = EditorSpecialLineMarkup`）
  - 非可视：`Icons: TTyLucideImageList`（`circle-alert`）、`GutterIcons: TTyLucideImageList`（`circle-x`、`triangle-alert`，宽高 16）、`MainMenu1: TMainMenu`、`DlgOpen: TTyOpenDialog`、`DlgSave: TTySaveDialog`、`RefreshTimer: TTimer`（`Interval = 300`，`Enabled = False`，`OnTimer = RefreshTimerTimer`）、`WatchTimer: TTimer`（`Interval = 1000`，`OnTimer = WatchTimerTimer`）。
  - 菜单：`MnuFile '&File'`：`MnuNew '&New'`（子菜单：`MnuNewMinimal 'Minimal theme'`、分隔线、内置主题在代码里加）、`MnuOpen '&Open...'`（Ctrl+O）、`MnuRecent 'Open &recent'`（代码里填）、`MnuSave '&Save'`（Ctrl+S）、`MnuSaveAs 'Save &as...'`（Ctrl+Shift+S）、分隔线、`MnuExit 'E&xit'`；`MnuView '&View'`：`MnuAppearance 'Editor &appearance'`（代码里填主题名，`RadioItem`、`GroupIndex = 1`）、`MnuEditorDark '&Dark editor'`（`AutoCheck`）、分隔线、`MnuProblems '&Problems'`（切换侧栏折叠）。
- [ ] **Step 2: `FormCreate`**（初值、列表、监听都在这里；**不写**自定义构造函数）：
  1. `TyRegisterBuiltinThemes`；`FSettings := TTbSettings.Create(IfThen(SettingsFileForTest <> '', SettingsFileForTest, TbDefaultSettingsFile)); FSettings.Load;`
  2. `FDoc := TTbDocument.Create; FBaseVars := TStringList.Create; TbBaseVarNames(FBaseVars);`
  3. `FKit := TTyCssEditKit.Create(Self); FKit.FormatOnLineLeave := False; FKit.Attach(Editor, True);`
  4. `FPreview := TTbPreviewFrame.Create(Self); FPreview.Parent := PreviewHost; FPreview.Align := alClient; FPreview.OnChanged := @PreviewChanged;`
  5. 菜单：内置主题（`TyBuiltinThemeNames`）加进 `MnuNew` 与 `MnuAppearance`；`RebuildRecentMenu`。
  6. 编辑器外观（Task 10 填 `SetEditorAppearance`；本任务先 `TyDefaultController.ThemeName := FSettings.EditorTheme; ApplyChromeTheme(TyDefaultController);`）。
  7. 预览开关按设置：`FPreview.SetModern(FSettings.PreviewModern)`（明暗在第一次加载之后设）。
  8. `NewMinimal`（第一次打开时的文档）；然后 `if FSettings.PreviewDark then FPreview.SetDark(True, err)`。
- [ ] **Step 3: 文档操作**：
  - `LoadEditor(AText)`：`Editor.Lines.Text := AText; Editor.Modified := False; Editor.ClearUndo;`（新建 / 打开是全文替换，清掉撤销）然后 `UpdateTitle; RefreshNow;`。
  - `NewMinimal` / `NewFromBuiltin(AName)`：先 `ConfirmDiscard`（有改动时问 保存 / 不保存 / 取消，经 `Ask`），再 `FDoc.NewUntitled(文本, 名字)`、`LoadEditor`。
  - `OpenFile(AFileName)`：`ConfirmDiscard`；`try FDoc.LoadFromFile … except on E do begin Ask(Format(rsTbOpenFailed, [AFileName, E.Message]), [mbOK]); FSettings.RemoveRecent(AFileName); RebuildRecentMenu; Exit(False); end;`；成功 `FSettings.AddRecent`、`RebuildRecentMenu`、`LoadEditor(FDoc.EditorText)`；`FDoc.ConvertedFrom <> ''` 时 `Editor.Modified := True` 并在状态栏说 `Format(rsTbConverted, [FDoc.ConvertedFrom])`。
  - `SaveTo(AFileName)`：`FDoc.SaveToFile(AFileName, Editor.Lines)`（异常 → `Ask(rsTbSaveFailed…)`、返回 False）；`Editor.Modified := False`；`AddRecent`；状态栏：`FDoc.RegenerateHint <> ''` 时 `Format(rsTbRegenerate, [hint])`（'Saved. This theme is compiled into the library: run scripts/%s.'），否则 `rsTbSaved`；`UpdateTitle`；`RefreshNow`（目录可能变了，`url()` 要重算）。
  - `SaveDocument`：`FDoc.Untitled` → 另存为（`SaveAsNameForTest <> ''` 时用它，否则 `DlgSave.Execute`，默认文件名 `BasedOn + '.tycss'` 或 `'theme.tycss'`）；否则 `SaveTo(FDoc.FileName)`。
  - `FormCloseQuery`：`CanClose := ConfirmDiscard`；可以关时存设置（预览的明暗 / 密度、编辑器外观）。
  - `Ask(AMsg, AButtons)`：先 `FLastAsk := AMsg`；`PromptAnswerForTest <> mrNone` 时 `Inc(FAskCount)` 并返回它；否则 `TyMessageDlg(AMsg, mtConfirmation, AButtons, 0)`。
  - `UpdateTitle`：`Bar.Caption := Format(rsTbTitle, [名字, 改动标记])`，名字 = 文件名或 `rsTbUntitled`（后面带 `BasedOn` 时 `'Untitled (win11)'`），改动标记 = `'*'` 或 `''`；`Caption` 同步。
- [ ] **Step 4: 刷新与问题列表**：
  - `EditorChange`：`UpdateTitle; RefreshTimer.Enabled := False; RefreshTimer.Enabled := True;`（重新计时）。`RefreshTimerTimer` = `RefreshNow`。
  - `RefreshNow`：

```pascal
procedure TTbMainForm.RefreshNow;
var
  text, err: string;
begin
  RefreshTimer.Enabled := False;
  text := Editor.Lines.Text;
  FProblems := TbCollectProblems(text, FDoc.BaseDir, FDoc.Untitled, FBaseVars);
  if not TbHasParseError(FProblems) then
    if not FPreview.LoadDocument(text, FDoc.BaseDir, err) then
      TbAddProblem(FProblems, 0, 0, tlsError, tpoLoad, Format(rsTbPreviewKept, [err]));
  if FPreview.ModeError <> '' then
    TbAddProblem(FProblems, 0, 0, tlsError, tpoLoad, FPreview.ModeError);
  ShowProblems;
end;
```

  （`TbAddProblem` 按序插入，见 Task 6，所以两条没有位置的会排在列表最前。）
  - `ShowProblems`：`ProblemsList.Items` 清空重填 `TbProblemCaption`；`ProblemsWin.BadgeValue := TbErrorCount(FProblems)`、`ShowBadge := BadgeValue > 0`；`Editor.Marks.Clear(True)` 后对每个 `Line > 0` 的行（同一行只一个，取最重的严重度）加一个 `TSynEditMark`（`Line`、`ImageList := GutterIcons`、`ImageIndex` 0 = 错误 / 1 = 警告、`Visible := True`），`Editor.BookMarkOptions.BookmarkImages := GutterIcons`（宽度一致，核实记录 6）；记一张「行 → 严重度」表给 `EditorSpecialLineMarkup` 用；`Editor.Invalidate`；状态栏第 0 格：没有问题时 `rsTbNoProblems`，有解析错误时 `rsTbParseKept`（'Not loaded: the preview shows the last version that worked.'）。
  - `EditorSpecialLineMarkup(Sender; Line; var Special; Markup)`：表里有这一行 → `Special := True; Markup.Background := 错误 / 警告行的颜色`（Task 10 从令牌取，本任务先用 `FLook.ErrorLine` / `WarningLine` 字段，Task 10 填）。
  - `JumpToProblem(i)` / `ProblemsListDblClick`：`Line > 0` 时 `Editor.LogicalCaretXY := Point(Max(1, Col), Line); Editor.EnsureCursorPosVisible; if Editor.CanSetFocus then Editor.SetFocus;`。
  - `EditorStatusChange`：状态栏第 1 格 `Format(rsTbLineCol, [Editor.LogicalCaretXY.Y, Editor.LogicalCaretXY.X])`；第 2 格 `TbLineEndingName(FDoc.LineEnding) + ' · UTF-8'`（有 BOM 时 `'UTF-8 BOM'`）。
- [ ] **Step 5: resourcestring**（`tbmain.pas`）：`rsTbTitle = '%s%s - Theme Builder'`、`rsTbUntitled = 'Untitled'`、`rsTbSaveChanges = 'Save the changes to %s?'`、`rsTbOpenFailed = 'Could not open %s: %s'`、`rsTbSaveFailed = 'Could not save %s: %s'`、`rsTbSaved = 'Saved.'`、`rsTbRegenerate = 'Saved. This theme is compiled into the library: run scripts/%s.'`、`rsTbConverted = 'Read as %s; it will be saved as UTF-8.'`、`rsTbPreviewKept = 'The preview kept the last version that worked: %s'`、`rsTbParseKept`、`rsTbNoProblems = 'No problems'`、`rsTbLineCol = 'Ln %d, Col %d'`、`rsTbFilter = 'Theme files (*.tycss)|*.tycss|All files|*'`（Task 10 再加外部修改那两句）。
- [ ] **Step 6: 判据测试**（`TTbMainFormTests`；`SetUp`：`SettingsFileForTest` = 临时目录里的 ini，`PromptAnswerForTest := mrNo`，记下 `TyDefaultController` 的三项；`TearDown`：还原它们、`SaveAsNameForTest := ''`、删临时目录；窗体 `TTbMainForm.Create(nil)`，不显示）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| F1 | 建好：`SideBar.WindowCount = 1`，`SideBar.Windows[0] = ProblemsWin`；`Editor.Highlighter is TSynCssSyn`（kit 接上了）且 `Kit.FormatOnLineLeave = False`；`Preview.Parent = PreviewHost`；`TitleBar = Bar`；标题含 `'Untitled'`；编辑器文本 = `TbMinimalTemplate`（两边换行统一成 LF 再比）；问题列表没有错误（`TbErrorCount = 0`） | ① `FormCreate` 不 `Attach`；② 工具里 `FormatOnLineLeave` 没关 |
| F2 | 刷新接线：`Editor.Lines.Text := 标记文档` 之后 `RefreshTimer.Enabled = True`（`OnChange` 若无句柄不触发，就直接调 `EditorChange(Editor)`）；`RefreshNow` 后 `RefreshTimer.Enabled = False`，预览按钮背景 `$123456` | `EditorChange` 不启动计时器 |
| F3 | 打开临时文件，三行：`'/* a */'`、`'TyButton {'`、`'/* 中 */ color red;'`（UTF-8）→ `Problems[0]` 是 (3,17) 的 `tlkParseError`（`中` 占 3 个字节列）；`Editor.Marks.Count = 1`、`Editor.Marks[0].Line = 3`；`ProblemsWin.BadgeValue = 1`；`JumpToProblem(0)` 后 `Editor.LogicalCaretXY = (17, 3)`；`EditorSpecialLineMarkup` 对第 3 行给 `Special = True`、对第 1 行 False | ① `ShowProblems` 不加标记；② 跳转用 `CaretXY`（物理列：`中` 按显示宽度算 2 列，光标会落到 `red` 之后一格） |
| F4 | 解析错误时预览保留：先加载标记文档，再把文本改坏 `RefreshNow` → 预览按钮背景仍 `$123456`；问题里没有 `tpoLoad` 那条（坏在解析，不重复报） | `TbHasParseError` 判断去掉（多出一条 `tpoLoad`） |
| F5 | 保存往返：打开 CRLF 无 BOM 的临时文件（D2 的字节）→ 不改 → `SaveDocument` → 字节相同；标题没有 `'*'`；`Settings.Recent[0]` = 这个文件 | `SaveTo` 不清 `Modified` |
| F6 | 未保存的新文档另存为：`SaveAsNameForTest` = 临时路径，`SaveDocument` → 文件存在、`Doc.Untitled = False`、`Doc.FileName` = 它 | — |
| F7 | 提醒生成脚本：D10 的目录结构里 `OpenFile(root/themes/builtin/x.tycss)` → `SaveDocument` → `Status.Panels[0].Text` 含 `gen-builtinthemes.ps1` | `SaveTo` 不看 `RegenerateHint` |
| F8 | 关闭询问：改动过的文档，`PromptAnswerForTest := mrCancel` → `CloseQuery` 为 False；`mrNo` → True 且文件没写；`mrYes` + 未保存 + `SaveAsNameForTest` → True 且文件写了 | `FormCloseQuery` 不问 |
| F9 | 从内置主题新建：`NewFromBuiltin('win11')` → 编辑器文本 = `TbFromBuiltin('win11')`（`Lines.Text` 与它比时两边换行统一成 LF）；标题含 `win11`；`Doc.Untitled` | — |
| F10 | 独立（spec §8）：建窗体后 `TyDefaultController` 的 `ThemeVersion` 记下；`Editor.Lines.Text := '@@@'`、`RefreshNow` → 它不变；`ProblemsList.ActiveController = TyDefaultController` | — |
| F11 | 工程清单：读 `tools/themebuilder/themebuilder.lpi`，`<Units>` 里有九个 `tb*.pas` 与 `themebuilder.lpr`；`RequiredPackages` 有 `SynEdit`、**没有** `tycontrols`；`OtherUnitFiles` 含 `../../designtime`；磁盘上 `tools/themebuilder/*.pas` 每一个都在清单里（从磁盘问清单，仓库记忆「新单元漏进 .lpk」） | —（结构性检查） |

- [ ] **Step 7: 注册与提交**：uses 加 `test.themebuilder.main`。`feat(themebuilder): the main window -- side bar, editor and preview; new, open, save and the problem list` + Co-Authored-By。

---

### Task 10: 外部修改提醒、编辑器外观、设置落地

**Files:**
- Create: `tools/themebuilder/tbeditorlook.pas`
- Modify: `tools/themebuilder/tbmain.pas`（`.lfm` 不动）、`tests/test.themebuilder.main.pas`

- [ ] **Step 1: 外部修改**：`WatchTimerTimer` = `CheckDiskNow`：

```pascal
procedure TTbMainForm.CheckDiskNow;
var
  msg: string;
begin
  if FPrompting or (Application.ModalLevel > 0) then Exit;
  if not FDoc.DiskChanged then Exit;          { takes the stamp again: asked once per change }
  msg := Format(rsTbReload, [FDoc.FileName]); { 'The file %s was changed by another program. Reload it?' }
  if Editor.Modified then
    msg := msg + LineEnding + rsTbReloadLoses; { 'Your unsaved changes will be lost.' }
  FPrompting := True;
  try
    if Ask(msg, [mbYes, mbNo]) = mrYes then
      ReloadKeepingCaret;
  finally
    FPrompting := False;
  end;
end;
```

  `ReloadKeepingCaret`：记下 `Editor.CaretY` 与 `TopLine`，`FDoc.LoadFromFile(FDoc.FileName)`（失败照 `OpenFile` 的报法）、`LoadEditor`，再把行号夹到行数以内设回去。**不经** `ConfirmDiscard`（已经问过了）。

- [ ] **Step 2: `tbeditorlook.pas`**：

| SynEdit 部位 | 取自（`TyDefaultController`） | 取不到时 |
|---|---|---|
| `Color`（底色） | `--input-bg` | `ResolveStyle('TyMemo','',[]).Background.Color` |
| `Font.Color`、`IdentifierAttri`、`SymbolAttri`、`SpaceAttri` 前景 | `--on-surface` | `TyMemo` 的 `TextColor` |
| `SelectedColor.Background` / `.Foreground` | `--selection` 按 alpha 叠在底色上 / 文字色 | `TyTextSelection` 的背景 |
| `Gutter.Color` | `--surface-chrome` | 底色 |
| 行号颜色（`Gutter.LineNumberPart.MarkupInfo.Foreground`）、`CommentAttri` | `--muted` 叠在各自底色上 | 文字色 |
| `KeyAttri`、`SelectorAttri` | `--accent` | 文字色 |
| `StringAttri` | `--success` | 文字色 |
| `NumberAttri`、`MeasurementUnitAttri` | `--warning` | 文字色 |
| at 规则（`TSynCssSyn` 里 `@` 关键字所用的属性，读 `synhighlightercss.pas` 确认是哪一个；没有单独的就跟 `KeyAttri`） | `--info` | 文字色 |
| 问题行底色（错误 / 警告） | `--danger` / `--warning` 以 18% 叠在底色上（`TyMix(bg, c, 18)`） | 同一色 |
| 字体名 | `RawVar('--terminal-font-family')`，空或 `monospace` 时平台等宽（Windows `Consolas`、macOS `Menlo`、其余 `Monospace`，照 `Terminal.pas:1625-1634`） | — |
| 字号 | `ResolveMetric('--font-size-base', 13)` 像素 → 点（`× 72 / 96`，至少 8） | — |

  取令牌：`s := AController.Model.ResolveOverride('color: var(--' + name + ');'); if tpTextColor in s.Present then c := s.TextColor`（alpha 小于 255 的先叠在对应底色上再转 `TColor`，用 `TyColorToLCL`）。`TbApplyEditorColors` 把表里每项写到 SynEdit 与高亮器上。

- [ ] **Step 3: `SetEditorAppearance(ATheme, ADark)`**：`TyDefaultController.ThemeName := ATheme`；`Mode := 'dark' / 'light'`；`ApplyChromeTheme(TyDefaultController)`；勾上对应菜单项；`FSettings.EditorTheme / EditorDark` 记下。颜色不在这里设——`FormCreate` 里 `TyDefaultController.AddChangeListener(@ToolThemeChanged)`（`ToolThemeChanged`：`FLook := TbEditorColors(TyDefaultController); TbApplyEditorColors(Editor, FKit.Highlighter, FLook); Editor.Invalidate;`），`FormCreate` 末尾再手动调一次；`FormDestroy` 里 `RemoveChangeListener`（地雷 10）。菜单点击 → `SetEditorAppearance`。`FormCreate` 第 6 步改为 `SetEditorAppearance(FSettings.EditorTheme, FSettings.EditorDark)`。
- [ ] **Step 4: 设置落地**：`FormCloseQuery` 允许关闭时：`FSettings.PreviewDark := FPreview.IsDark; FSettings.PreviewModern := FPreview.IsModern; FSettings.Save;`。`PreviewChanged`（frame 的开关用过）：`RefreshNow`（把 `ModeError` 显示出来）。`MnuProblems` 切 `SideBar.Collapsed`。
- [ ] **Step 5: resourcestring**：`rsTbReload`、`rsTbReloadLoses`。
- [ ] **Step 6: 判据测试**（接着写 `TTbMainFormTests`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| F12 | 外部修改：打开临时文件，往文件里另写一段内容（长度不同），`PromptAnswerForTest := mrYes`，`CheckDiskNow` → 编辑器文本 = 新内容；再改一次、答 `mrNo` → 编辑器不变，**再调一次** `CheckDiskNow` 时 `AskCount` 不再增加 | `DiskChanged` 不更新快照（第二次仍问） |
| F13 | 有未保存改动时 `LastAsk` 含 `rsTbReloadLoses`；没有改动时不含 | 不看 `Editor.Modified` |
| F14 | 自己保存不算外部修改：`SaveDocument` 后 `CheckDiskNow` → `AskCount` 不变 | 保存后不重新记戳（`SaveToFile` 里 `CaptureStamp` 去掉） |
| F15 | 编辑器外观跟着换：`SetEditorAppearance('default', False)` 记下 `Editor.Color`；**先证明**两套的 `--input-bg` 不同（直接用 `TbEditorColors` 各算一次）；`SetEditorAppearance('default', True)` → `Editor.Color` 变成暗色那一份，且等于 `TbEditorColors(TyDefaultController).Background` | `FormCreate` 不挂监听（`Editor.Color` 不变） |
| F16 | 监听摘掉：窗体 `Free` 之后 `TyDefaultController.Changed` 不 AV（`TearDown` 之前在测试里显式调一次） | `FormDestroy` 不 `RemoveChangeListener` |
| F17 | 设置落地：`SetEditorAppearance('xp', True)`、预览 `SetModern(True)`、`CloseQuery`（无改动）→ ini 里 `Theme=xp`、`Dark=1`、`Modern=1`；新建一个窗体（同一 ini）→ `TyDefaultController.ThemeName = 'xp'`、`Preview.IsModern` | `FormCloseQuery` 不存设置 |
| F18 | 问题行颜色来自令牌：F3 的文件打开后 `EditorSpecialLineMarkup` 给第 3 行的 `Markup.Background` = `FLook.ErrorLine`，且它不等于 `Editor.Color` | 问题行底色写死 `clRed` |

- [ ] **Step 7: 提交**：`feat(themebuilder): reload when another program changes the file; the editor takes its colours from the tool's theme` + Co-Authored-By。

---

### Task 11: 中英 `.po`、检查脚本认 `tools/`

**Files:**
- Create: `tools/themebuilder/languages/themebuilder.zh_CN.po`、`themebuilder.zh_CN.json`、`tycontrols.zh_CN.po`
- Modify: `scripts/check-example-po.py`、`scripts/check-lfm-props.py`、`scripts/smoke-launch-examples.ps1`
- Modify: `tests/test.themebuilder.main.pas`

- [ ] **Step 1: 库目录**：`tools/themebuilder/languages/tycontrols.zh_CN.po` = `languages/tycontrols.strconsts.zh_CN.po` 的逐字节副本（用 `cp`，不经编辑器）。
- [ ] **Step 2: 工具目录的 `.lfm` 部分**：`themebuilder.zh_CN.po` 头照 `examples/terminal/languages/terminal_example.zh_CN.po:1-10`（`Project-Id-Version: tycontrols-themebuilder 3.1`），接着一节 `# --- .lfm captions/text/hints (msgid=English source) ---`：三个 `.lfm` 里每个 `Caption`、`Hint`、`TextHint`、`StripHint`、`Text`、`Items.Strings` 之外的可见字符串一条，键 `<小写根类名>.<小写组件名>.<小写属性名>`（根类名：`ttbmainform`、`ttbpreviewframe`、`ttbsampleform`）。菜单项同样（`ttbmainform.mnufile.caption`）。**译文**：Theme Builder 不译；Basic 基础、Inputs 输入、Lists and trees 列表与树、Grids 表格、Containers and tabs 容器与页签、Menus and toolbars 菜单与工具栏、Window chrome 窗体外框、Feedback 反馈、Dark 暗色、Disable all 全部禁用、Problems 问题、Editor appearance 编辑器外观、Dark editor 暗色编辑器、Minimal theme 极简主题、Open recent 最近打开、Sample window 样例窗口……（样例控件的文字也译：它们本身就是在看中文字形在这套主题下的样子）。`msgstr` 一条都不能空（仓库记忆「空 .po 条目让程序起不来」）。
- [ ] **Step 3: 代码部分的译文**：`themebuilder.zh_CN.json`，键 `<小写单元名>.<小写 rs 名>`，覆盖 Task 5、7、8、9、10 的全部 resourcestring（`tbtemplates.rstbbasedon`: `"基于内置主题「%s」。"`、`tbtemplates.rstbminimalheader`: `"极简主题：只有明暗两套的六个种子，其余全部来自底层主题。"`、`tbmain.rstbtitle`: `"%s%s - 主题编辑器"`、`tbmain.rstbreload`: `"文件 %s 已被其他程序修改。重新载入吗？"`、`tbmain.rstbreloadloses`: `"未保存的改动会丢失。"`、`tbpreview.rstbmodefailed`: `"%s模式下：%s"`、`tbpreview.rstbmodelight`: `"亮色"`、`tbpreview.rstbmodedark`: `"暗色"`……）。占位符个数与顺序必须与英文一致。代码条目由 Task 12 编译后跑脚本并进 `.po`。
- [ ] **Step 4: 脚本**：
  - `check-example-po.py` 的 `glob` 改为同时扫 `examples/*/languages/*.po` 与 `tools/*/languages/*.po`（合并后排序），文件头的用法说明加一句。
  - `check-lfm-props.py` 的 `pattern` 同样加 `tools/*/*.lfm`（只查 `TTy*` 类，`TSynEdit` 不受影响）。
  - `smoke-launch-examples.ps1` 加参数 `[string[]]$Dirs = @('examples')`，`Get-ChildItem` 对每个目录各找一遍 exe；用法说明加 `-Dirs examples,tools\themebuilder`。默认行为不变。
- [ ] **Step 5: 判据测试**（`TTbMainFormTests`）：

| # | 判据 | 在哪个变异下必须红 |
|---|---|---|
| I1 | 键对得上：建主窗体、预览 frame、样例窗体，枚举每个组件的已发布字符串属性 `Caption` / `Hint` / `TextHint` / `StripHint`（非空的），拼出键；`.po` 里 `#:` 的 `.lfm` 键集合（去掉 `.json` 来的代码键——代码键的前缀是单元名，形如 `tbmain.`）与它**两个方向**都相等 | `.po` 删掉一条（少了）；多一条不存在组件的（多了） |
| I2 | `.po` 每条 `msgstr` 非空；`#, object-pascal-format` 的条目两边占位符序列相同 | — |
| I3 | `.json` 的每个键都能在工具单元的 resourcestring 里找到（读 `tools/themebuilder/*.pas` 文本，按 `rs名 =` 查）；反过来每个 resourcestring 都在 `.json` 里 | `.json` 少一个 |
| I4 | 库目录副本与 `languages/tycontrols.strconsts.zh_CN.po` 逐字节相同 | — |

- [ ] **Step 6: 提交**：`feat(themebuilder): Chinese and English; the example checks cover tools/` + Co-Authored-By。

---

### Task 12: 收尾——编译、全量、按 spec 逐条核、集中变异、主控编包冒烟、审查、写回 spec、签收

**Files:**
- Modify: 本计划（签收记录）、`docs/superpowers/specs/2026-10-01-theme-builder-design.md`（写回）、`tools/themebuilder/languages/themebuilder.zh_CN.po`（脚本补代码条目）
- 修复时按需改 Task 1–11 的文件

- [ ] **Step 1: 一次编译 + 本期 suite + 全量**：「跑测试的固定套路」。Expected：本期 suite 全 0 / 0；全量 errors / failures 与 Task 0 的基线相同（只剩基线里的已知项）、总数 = 基线 + 本期新增。红了集中修：共享改动以 spec §4 与金样本为准，预览以 spec §5.3 为准；修复提交 `fix(themebuilder): ...` / `fix(lint): ...` / `fix(css): ...`，一个问题一个提交。
- [ ] **Step 2: 编工具、补 `.po`**（实现 agent 做）：「跑测试的固定套路」里的编工具命令（0 错、没有重编 SynEdit）；然后

```bash
cd /d/Projects/ty-3.1 && python scripts/example-rsj2po.py tools/themebuilder themebuilder tools/themebuilder/languages/themebuilder.zh_CN.json && python scripts/check-example-po.py . && python scripts/check-lfm-props.py && git status --short tools/themebuilder
```

Expected：`added=` 等于工具的 resourcestring 个数、没有 `FATAL`；两个检查通过；`git status` 只有 `.po` 变了（`lib/`、exe 被忽略）。重编 tytests 再跑 `TTbMainFormTests`（I1–I3 这时才看得到代码条目）。
- [ ] **Step 3: 试解析耗时**：写一条临时测试或在 `TTbPreviewTests` 里加 `TestTheProbeIsQuick`：`default` 主题 + 极简模板各 `TbProbeResolve` 五次取中位数，打印；> 50 ms 的写进签收（不因此失败，除非 > 200 ms——那时按 typeKey 只试 `[]` 与 `[tysDisabled]`，并记为与规格不符）。
- [ ] **Step 4: 按 spec 逐条核代码，不看测试**（仓库记忆「全绿≠按 spec 做完」「建好没接线」）：§4 第 1–3 条、§5.1 前两条与末条（本期只有键入一种来源）、§5.3 除 Ctrl+点击与覆盖检查外的每一句、§5.4 每一句、§5.5、§6 的前两点与后四点（导出与代码片段除外）、§8 的共享改动 / 预览 / 工具窗体三行；逐条记「在哪一行实现 / 为什么不需要 / 挪到哪一期」。
- [ ] **Step 5: 【主控执行】编包、冒烟、看一眼**

```bash
cd /d/Projects/ty-3.1 && lazbuild -B tycontrols.lpk > /tmp/tb-pkg.txt 2>&1; tail -3 /tmp/tb-pkg.txt; lazbuild -B tycontrols_dt.lpk > /tmp/tb-dt.txt 2>&1; tail -3 /tmp/tb-dt.txt; lazbuild -B tools/themebuilder/themebuilder.lpi > /tmp/tb-tool.txt 2>&1; tail -3 /tmp/tb-tool.txt; git status --short
```

Expected：三个都编过（`tycontrols_dt.lpk` 编过 = 拆出的单元在设计期包里照常可用，spec §8）。然后：
1. `powershell -File scripts/smoke-launch-examples.ps1 -Dirs tools\themebuilder`：工具起得来、只有主窗体与应用窗口、没有 `#32770`。
2. 打开工具看一眼（不录）：新建极简 → 换暗色 → 从 `win11` 新建 → 删一个 `}` 看问题列表与行标记 → 打开 `themes/builtin/xp.tycss` 直接保存、`git diff --quiet themes/` 为真。
3. 在 IDE 里装一次 `tycontrols_dt.lpk`，打开任意控件的 `StyleOverride` 对话框：高亮、Ctrl+Space、键入弹补全、离开行格式化照旧（这一项也可留给用户真机验收的 A19）。
- [ ] **Step 6: 集中变异**（每条三拍，必须红）：G1、G2、P1、P4、L1–L4、L6–L10、L12、L13、K1、K2、K4、K5、K6、K8、D1、D3、D4、D6、D8、D9、D10、S2、S3、S4、T1、T2、T3、R1–R4、R6、V2、V3、V6、V7、V8、V9、V10、V12、V13、V14、V15、V16、F1、F2、F3、F4、F5、F7、F8、F12–F18、I1、I3。结果逐条记进签收；没红的当场补强。
- [ ] **Step 7: 期末审查（主控派两个审查 agent）**：规格核对（Step 4 的记录对着 spec 再过一遍）+ 代码质量（`git diff <Task 0 的 HEAD>..HEAD`），重点：
  - 共享改动：`ETyCssError` 消息与旧 lint 输出逐字不变（金样本）；`BuildPositions` 永不抛；拆出的单元没有 IDE 依赖，对话框行为不变。
  - 预览：每条改模型的路径之后都有试解析（地雷 15）；`LoadFromSource` 之后都有 `Changed`（地雷 16）；控制器只推给 `Root` 下、不推给 `Tools`；弹出物都挂预览控制器。
  - 主窗体：监听有挂有摘（地雷 10）；没有任何路径在测试里弹框（地雷 11）；跳转用逻辑列（地雷 17）；`.lfm` 规矩（地雷 5、6）。
  - 审出来的问题修完回到 Step 1。
- [ ] **Step 8: 写回 spec 原处，标「实现期修正（1 期）」**，原文删除线保留。至少：状态行（1 期签收）；§4 的单元名（`tb` 前缀）与新增单元、共享改动第 1 条（`TTyCssEditKit`、补全看光标前文本）、第 3 条（`Kind` / `Subject` / `tlkBadValue`）；§5.3 的试解析、密度只换令牌、弹出物怎么挂；§5.4 加载错误没有位置的那一类；§6 保存提醒的范围、BOM 与编码；开工前问题一的答复；「与规格不符之处」每一条。
- [ ] **Step 9: 签收记录写进本计划末尾，提交**：全量条数（基线 → 签收）、提交区间、本期各 suite 条数与用时、试解析耗时、变异结果（每条红 / 补强 / 等价）、spec 写回的节号、计划外发现、遗留。

```bash
cd /d/Projects/ty-3.1 && git add docs/ tools/themebuilder/languages && git commit -m "docs(themebuilder): phase 1 sign-off; corrections written back into the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: 新建三期共用的验收文档

**Files:**
- Create: `docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md`

照终端验收文档（`docs/superpowers/plans/2026-09-29-terminal-acceptance.md`）的形式与语气（仓库记忆「文档要原生语感」），一份三期共用、本期先写 1 期的部分：

- [ ] **Step 1: 开头**：一句话说这是什么（「主题编辑器三期做完后的一次性真机验收入口」）与怎么填（「结果」列写 过 / 不过 / 现象）。
- [ ] **Step 2: 「这是什么，做了什么」**：工具是什么（两三句，照 spec §1）；**1 期**：一段（编辑与预览：左边写、右边看，问题列表、新建 / 打开 / 保存、外部修改、编辑器跟着工具皮肤、中英双语；库里改了三处：设计期编辑框拆出来共用、解析错误带行列号、带位置的主题检查）；「2 期」「3 期」两行写「（待做）」。分支、1 期签收的头提交与全量条数。
- [ ] **Step 3: 「准备」**：怎么编（`lazbuild -B tools/themebuilder/themebuilder.lpi`，程序在 `tools/themebuilder/lib/<平台>/`；Linux `--ws=gtk2` / `--ws=qt6`，macOS `--ws=cocoa`）；设计期那一项要先装 `tycontrols_dt.lpk`；配置文件在哪（`GetAppConfigDir` 的实际路径，三平台各一行）、想从头来就删掉它；顺序建议（Win32 → Linux → macOS）。
- [ ] **Step 4: 「验收表」**：列 `#`、`期`、`验什么`、`平台`、`怎么操作`、`期望`、`结果`；把本计划末尾「1 期的真机验收项」A1–A22 按编号 1–22 写进去（「期」列写「1 期（A1）」……）。表头说明写「2、3 期的项接着往下编」。
- [ ] **Step 5: 「按平台的项号」**：Win32、Windows 11、Linux GTK2、Linux Qt6、macOS Cocoa 各一行。
- [ ] **Step 6: 「等你定的决定」**：「1 期开工前的问题」一张表（编号 E1 起：是什么、选项、现在的做法（按 Task 0 的实际答复）、看哪一项、改哪里），八条；「与规格不符、你可能想改的」一小节，列本计划「与规格不符之处」里用户看得见的几条（侧栏只有一页、密度只换令牌、底层变量不报、编辑器不自动格式化、加载错误有的没有行号）。
- [ ] **Step 7: 「截图」**：本期不截图；写一句「2 期起按需加」。
- [ ] **Step 8: 「发现问题怎么报」**：照终端那份（项号、平台与 widgetset、缩放、编辑器外观与预览主题、能否复现、截图放 `docs/superpowers/plans/2026-10-01-themebuilder-acceptance-shots/`、文件名带项号）；加一句「预览里看到的问题，附上当时编辑器里的主题文本（或文件）」。
- [ ] **Step 9: 「验收之后」**：结论写回 spec；不过的项一个问题一个 `fix(themebuilder): ...`；合 `main` 前查 i18n 与 README。
- [ ] **Step 10: 自查与提交**：项号连续；每一项都有「怎么操作」与「期望」；决定清单每条都有「看哪一项」。

```bash
cd /d/Projects/ty-3.1 && git add docs/superpowers/plans/2026-10-01-themebuilder-acceptance.md && git commit -m "docs(themebuilder): the acceptance sheet, with phase 1's checks

One sheet for all three phases, as with the terminal: phase 1's
checks, the questions settled before it started and what differs
from the design. Phases 2 and 3 add to it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 1 期做完能看到什么

- `tytests` 里本期十个 suite 全绿：解析错误的行列号（LF / CRLF / CR / 汉字）；`TyLintCssEx` 每种问题的位置、严重度、种类，旧 `TyLintCss` 与改之前逐字相同；拆出的编辑框在无 IDE 的测试里能挂上、补全看光标前的文本；文档往返字节不变；预览的独立控制器、坏主题不留残、只缺某个模式的变量被拦下、换密度后文档还在、弹出物都挂预览控制器；主窗体的刷新、问题跳转、行标记、保存提醒、外部修改、编辑器外观、设置、双语目录。
- 工具起得来：写主题，右边 0.3 秒后跟着变；写坏了问题列表说在哪、预览保持上一版。
- 设计期包编过，StyleOverride 对话框照旧。
- 一份三期共用的验收文档。

---

## 1 期的真机验收项（Task 13 写进验收文档，编号 1–22）

| # | 项 | 平台 | 怎么验 | 算过 |
|---|---|---|---|---|
| A1 | 启动与布局 | Win32、GTK2、Qt6、Cocoa | 启动工具；拖标题栏、改窗口大小、拖编辑区与预览之间的分隔条、折叠 / 展开左边的「问题」 | 标题栏能拖；三块区域随窗口伸缩；没有原生灰底的缝 |
| A2 | 中英界面 | Win32、GTK2 | 系统语言中文 / 英文各启动一次 | 菜单、侧栏、预览的页签与样例控件、状态栏、对话框都跟随系统语言；中文下没有英文漏网（样例控件的文字也是中文） |
| A3 | 极简模板 | 任一 | 启动（默认就是极简模板）；预览里翻八页；切「暗色」 | 八页都有内容、没有空白页；明暗两套都像默认主题 |
| A4 | 从内置主题新建 | Win32 | 「文件 → 新建」里依次选 `win11`、`xp`、`material3`、`macos`、`showcase`；每个都和 `examples/demo` 里选同一皮肤时对照 | 预览和 demo 里同皮肤的控件样子一致；文件头第一行是「基于内置主题「xxx」」 |
| A5 | 边写边看 | Win32、GTK2 | 在极简模板里改亮色的 `--accent`；再打开 `themes/auto.tycss`（600 多行）在中间连续快速打字 | 停手约 0.3 秒后预览变；大文件里打字不卡、不闪 |
| A6 | 写坏了 | 任一 | 删掉一个 `}`；再写一个不存在的属性、一个没定义的变量、一个 `border-radius: 1px 2px 3px` | 「问题」里有带行号的条目、侧栏图标上有数字；编辑器行号栏有标记、那一行有底色；双击条目光标跳到那里；删 `}` 时预览保持上一版 |
| A7 | 底层变量不报 | 任一 | 极简模板里加一条规则 `TyButton { background: var(--surface-hover); }` | 没有「未定义变量」的问题；预览的按钮变了 |
| A8 | 只缺某个模式的变量 | 任一 | 写一个只在亮色块里定义、规则里引用的变量，然后切「暗色」 | 暗色被拒绝、开关弹回，「问题」里说暗色模式下哪个控件缺什么；工具不弹错误框 |
| A9 | 预览坏不影响工具 | 任一 | 在预览加载各种坏主题、切明暗和密度的同时，看左边的问题列表、菜单、编辑器 | 工具界面的样子始终不变 |
| A10 | 密度 | Win32、Cocoa | 预览里切「现代」 | 字号、内距变大；控件框的高度不变（开工前问题一第 2 条，记下看起来是否可以接受） |
| A11 | 全部禁用 | 任一 | 勾「全部禁用」再取消 | 所有样例变成禁用样子、能翻页；取消后本来就禁用的样例仍是禁用 |
| A12 | 弹出物跟着预览主题 | Win32、GTK2、Cocoa | 预览设成与工具不同的皮肤（如工具 `default`、预览 `xp` 暗色）；依次点「消息对话框」「输入对话框」「弹出菜单」「通知」「打开样例窗口」；样例窗口开着时改主题文本 | 弹出来的都是预览的皮肤，不是工具的；样例窗口的标题栏按钮、边框、阴影对；改文本后样例窗口跟着变 |
| A13 | 带图片的主题 | Win32 | 打开 `themes/green.tycss`；再把它「另存为」到一个没有 `assets/` 的目录；再「新建」一个极简模板写一条 `url(x.png)` | 第一步预览有照片背景；第二步「问题」里有缺资源的警告；第三步有「先保存」的提示 |
| A14 | 保存不改字节 | Win32 | 打开 `themes/builtin/win11.tycss`，不改直接保存；`git diff` | 没有差异；状态栏提醒重跑 `scripts/gen-builtinthemes.ps1`；打开 `themes/light.tycss` 保存时提醒 `gen-defaulttheme.ps1` |
| A15 | 换行符与编码 | Win32、GTK2 | 分别打开 LF、CRLF、带 BOM、GBK 编码的 `.tycss` 各一个，改一个字保存 | 换行符、BOM 保持原样；GBK 那个读进来是对的、状态栏说明、存成 UTF-8；状态栏显示换行符与编码 |
| A16 | 最近文件 | 任一 | 打开几个文件后重启；把其中一个在外面删掉再从「最近打开」点它 | 列表还在、顺序对；被删的那个报错并从列表里消失 |
| A17 | 外部修改 | Win32、GTK2 | 用记事本改正在打开的文件并保存；再在工具里改一个字不保存，外面再改一次 | 第一次问要不要重新载入，选是后内容更新；第二次的提示说未保存的改动会丢失；选否后不再反复问 |
| A18 | 编辑器外观 | Win32、GTK2、Cocoa | 「视图 → 编辑器外观」逐个换皮肤、开关「暗色编辑器」 | 编辑器的底色、文字、选区、行号栏、语法颜色都跟着换；记下哪些皮肤下哪种语法颜色看不清（开工前问题一第 7 条）；滚动条和边框是系统原生的（spec §10，可接受） |
| A19 | 补全与设计期对话框 | Win32（IDE） | 工具里：规则里按 Ctrl+Space、打字母；选择器位置同样。IDE 里：任意控件 `StyleOverride` 的「…」对话框 | 规则里给属性、选择器位置给 typeKey；工具里离开一行不会被自动改写；IDE 对话框的高亮、补全、离开行整理、校验与以前一样 |
| A20 | 未保存提示 | 任一 | 改过后直接关窗口，分别选取消 / 不保存 / 保存 | 取消不关；不保存直接关；未命名的保存会弹另存为 |
| A21 | HiDPI | Win32 150%、Cocoa Retina | 看整体布局、编辑器字号、行标记图标 | 不糊、不挤、图标不被裁 |
| A22 | 输入法 | Win32、GTK2、Qt6、Cocoa | 在编辑器的注释里用中文输入法打字 | 候选框在光标旁；上屏正确（SynEdit 自己的输入法支持） |

---

## 与规格不符之处（核实中发现，Task 12 写回）

1. spec §4 的单元名 `umain` / `udocument` / … 改为 `tb` 前缀（`tbmain` / `tbdocument` / …）：测试工程的搜索路径上已有终端示例的 `umain`。另多出 `tbsettings`、`tbtemplates`、`tbthemesource`、`tbsamplewin`、`tbeditorlook` 五个单元。
2. spec §4 第 1 条：拆出的是挂到现成 `TSynEdit` 上的 `TTyCssEditKit`（不自己建编辑框）；补全改为看光标之前的文本（设计期对话框原来看整篇）。
3. spec §4 第 3 条：`TyLintCssEx` 的记录多 `Kind`、`Subject`、`Col`，另有只在 `Ex` 里出现的 `tlkBadValue`。
4. spec §5.4「解析错误用 `ETyCssError.Line / Col`」：`StyleModel` 抛的 `ETyCssError`（`@import` 失败）与值错误（普通 `Exception`）没有位置——前者 lint 会带 `@import` 那一行另报一条，后者 lint 的 `tlkBadValue` 带位置另报；加载失败本身那条显示在列表最前、没有行号。
5. spec §5.3：加了「加载后与切模式后试解析」，以防只在某个模式下缺变量时画的时候才抛；换密度只换令牌、不换控件高度（开工前问题一第 2 条）。
6. spec §5.4：「未定义变量」不报底层已定义的（开工前问题一第 3 条）。
7. spec §2 第 5 条 / §5：侧栏本期只有「问题」一页（开工前问题一第 1 条）。
8. spec §6：保存时的提醒扩到 `auto.tycss`、`system.tycss`、`light.tycss`；保持 BOM；非 UTF-8 文件按系统编码转换（开工前问题一第 5、6 条）。
9. spec 未提：工具工程只走源码路径、不依赖 `tycontrols` 包（核实记录 36）；工具里不自动格式化离开的行（开工前问题一第 4 条）。

---

## 签收

签收日期 2026-10-01。实现到 `ffe4861d`；期末两份审查（规格核对、代码质量）查出的问题由修复 + 签收 agent 处理，一个问题一个提交（`77e9d0e0`..`3e800d65`，中间的 `5bc7237c` 是 2 期计划 agent 的提交，不属本期）。「与规格不符之处」1–9 条与期末修复都已写回 spec 原处，标「实现期修正（1 期）」（状态行、§2、§4 结构与共享改动 1–4、§5.3、§5.4、§6、§10）。

### 主控已做

在 `ffe4861d` 上 `lazbuild -B` 编过 `tycontrols.lpk`、`tycontrols_dt.lpk`（0 错，拆出的 `TTyCssEditKit` 在设计期包里编得过）、`tools/themebuilder/themebuilder.lpi`（0 错）；冒烟启动只有主窗体「未命名 - 主题编辑器」与应用窗口，没有错误框。

### 期末审查的处理（提交表）

| 项 | 问题 | 提交 | 处理 |
|---|---|---|---|
| 必修 1 | 变量成环（`--a: var(--a)`、互指、`@mode` 里 `--surface: darken(var(--surface),5%)`、经 `TyEvalLength` 的裸 `--x` 环）递归到栈溢出、崩进程 | `77e9d0e0` | 修：`Css.Values` 每次查变量带当前路径上的名字，再遇到抛 `Exception`「variable --x refers back to itself」（该单元惯用普通 `Exception`，英文常量 `TyCssVarCycleMsg`，不进 `StrConsts`）；`TyLintCssEx` 新增 `ScanVarCycles`，按模式合并变量、Tarjan 强连通分量，只报环上的变量、报在定义处，类别用 **`tlkBadValue`**（不新增枚举：它本就是「引擎会拒的值」，`TyLintCss` 滤掉它，旧输出逐字不变，金样本不动）。测试：`Css.Values`、lint、模型加载、预览 `LoadDocument`、主窗体问题列表五处 |
| 必修 2 | 切暗色被拒的原因到不了问题列表；L1 解析失败时加进过期的 `ModeError` | `a481e9c4` | 修：`PreviewChanged` 只重建列表（`BuildProblems`，用上次刷新的 lint 与加载错误），不再重载；`LoadDocument` 只在文本或目录变了时清 `ModeError`；解析失败时不列 `ModeError`。V11「a good load clears it」没有钉死错误行为（它载入的是另一份文档），保留并补「同一份文本再载入不清」。新测 F19 走真实路径（拨 `DarkSwitch.Checked`，经 `OnChange`） |
| 必修 3 | 保存非原子 | `bc7cd192` | 修：写同目录临时文件 → `MoveFileExW(REPLACE_EXISTING or WRITE_THROUGH)`（其他平台 `fpRename` 并带原权限位）；失败删临时文件、文档不改名不重取时间戳（盘上的文件没变，所以也不会被当外部修改）。钩子 `TTbDocument.FailWriteForTest` 在真实 `SaveToFile` 里、写了一半之后抛 |
| 必修 4 | 试解析慢（冷 0.6–1.1 s），计时测试量的是缓存 | `275ed625` | 先修测试（每次计时前 `RefreshSystemTokens` 挪版本号丢掉缓存，所有内置主题 + 极简模板，> 100 ms 红），现状下红（aero 1062 ms）；再优化，见下表 |
| 必修 5 | 设置写不进去时关不掉窗口；L11 `AddRecent` 后顺手保存 | `0f18a69e` | 修：`SaveSettings` 尽力而为（try/except）；打开、保存把文件加进最近列表后即写设置 |
| 必修 6 | 文件末尾的解析错误行号 +1 | `38c4e59a` | 修：收集问题后钳到编辑器的行数、列钳到行长 + 1（`ClampToEditor`）；选钳位置而不是改喂给解析器的文本，lint 的其他位置与预览载入的文本都不变 |
| 必修 7 | 外部修改检测只到 2 秒 | `df8ee7dc` | 修：`TbFileStamp` 取全精度修改时间（Windows `GetFileAttributesExW` 的 `ftLastWriteTime`，Unix `fpStat` 的秒 + 纳秒）+ 大小 |
| 必修 8 | 预览控制器改全局 `TyFallbackFontSize` | —（没改） | **核实后停下交主控**：`Controller.Changed` 对任何控制器都写全局，这是库的现有契约——`test.fontcascade` 的 `TestControllerSyncsPainterFallback` 与 `test.measurecache` 的 `ThemeChangeChangesTheMeasuredFontSize` 都用 `TTyStyleController.Create(nil)`（非默认控制器）断言全局被写。改成「只有默认控制器写」会让这两条红。已写进 spec §10 与验收文档 E10 |
| 必修 9 | 最近文件：任何打开失败都移除；菜单 `&` | `c47f8450` | 修：只有文件已不存在才移除；标题里 `&` → `&&` |
| L2 | 暗色下载入单模式文档，开关与设置仍是暗 | `b069720a` | 修：载入无 `@mode` 的文档时模式置空 |
| L3 | 换密度后重载失败静默落到底层 | `45668bee` | 修：换密度同切模式一样可被拒——退回原密度、文档还在、原因写进 `ModeError`（新资源串 `rsTbDensityFailed`，已补 zh_CN） |
| L4 | 侧栏 `ShowHint` | `5f7ff49a` | 修 |
| L5 | 行标记占 SynEdit 书签图标 | `0706c217` | 修：不再把 `GutterIcons` 设成书签图标，标记自带 `ImageList` |
| L6 | `Ask` 无消息类型 | `c2d346b6` | 修：`Ask` 带 `TMsgDlgType`，打开 / 保存失败用 `mtError` |
| L7 | `DdbMore` 没挂菜单 | `ba0a9651` | 修（`.lfm`） |
| L8 | `eoTrimTrailingSpaces` | `ebef1b2d` | 修：工具里关掉 |
| L10 | 工具条换肤挤压 | `67a6dc4a` | 修：开关条的四个控件按标题 AutoSize、一个锚在前一个右边；无头测试跑不到 LCL 的锚定与自动尺寸，测试只查结构，外观写进验收第 28 项 |
| 代码审查 7 | `Css.Parser.pas` 注释 | `288b68db` | 写实：`@import` 子文件的解析错误带子文件坐标，`StyleModel` 自己抛的为 0（`StyleModel.pas` 未动） |
| 测试质量 13 | `TestTheListenerIsRemoved` 断言 `True` | `3e800d65` | 改：监听里的哨兵（`ToolThemeChangedForTest`，在碰窗体之前调用）——窗体活着时 1 次、释放后 0 次 |
| 测试质量 15 | `TestTheProbeIsQuick` 的 `err` 未初始化 | `275ed625` | 随计时测试重写一并修 |

### 试解析计时（冷，GetTickCount64，五次中位数，ms；计时粒度约 15.6 ms）

| 主题 | 修前（逐 typeKey × 变体 × 六组状态） | 中间方案（每 typeKey 一次、全部变体与状态） | 修后（快探测，`TbProbeDocument`） |
|---|---|---|---|
| default | 625 | 109 | 31 |
| system | 735 | 140 | 31 |
| adwaita | 875 | 141 | 16 |
| aero | 1062 | 156 | 31 |
| antdesign | 656 | 140 | 15 |
| bootstrap | 750 | 125 | 16 |
| breeze | 828 | 141 | 31 |
| classic | 765 | 141 | 15 |
| fluent | 781 | 125 | 16 |
| macos | 844 | 156 | 16 |
| material3 | 797 | 172 | 31 |
| office | 734 | 125 | 16 |
| showcase | 547 | 94 | 16 |
| ubuntu | 781 | 125 | 16 |
| win10 | 766 | 140 | 16 |
| win11 | 1000 | 172 | 31 |
| xp | 594 | 110 | 16 |
| 极简模板 | 625 | 110 | 16 |

中间方案只砍掉了重复：实测单是对 253 个 typeKey 各解析一次 `[]` 就要约 80 ms（底层规则按 typeKey 一遍遍求值、变量表线性查找），达不到 100 ms。最终做法（spec §5.3、验收 E9）：快探测把一次绘制可能求值的每条声明在当前模式变量下各求值一次（相同「属性 + 值」只算一次，变量按用到的名字向模型 `RawVar` 读一次、有序索引查找）；说干净就采信，抛了再走中间方案定案并指出 typeKey.变体。带 `@import` 的文档不走快探测。守护：`TestTheFastProbeAgreesWithTheResolveWalk`（V18）在全部内置主题的每个模式、极简模板与七份坏文档的两种密度上比两条路的结论（≥ 40 次比较、≥ 8 次拒收）；`TestTheProbeStillCatchesWhatAPaintWouldRaise`（V17：只在亮色定义、被变体的禁用态用到的变量；底层规则接不住的种子）与成环用例证明「画的时候会抛的主题」仍被拦下。

### 测试结果

- 基线（`ffe4861d`，`tests/tytests-tb1base.exe`）全量：8658 / 0 / 0（18 分钟）。
- 签收（`3e800d65` 重编，`tests/tytests-tb1fix.exe`）：本期 suite 与相关 suite 全绿——TThemeLintGoldenTests 2、TTbParserPosTests 10、TTbLintExTests 14、TTbCssEditKitTests 9、TTbDocumentTests 11、TTbSettingsTests 4、TTbTemplatesTests 4、TTbProblemsTests 6、TTbPreviewTests 24、TTbMainFormTests 33、TThemeLintTest 19、TTestCssParser 16、TTestCssValuesEval 10、TTestStyleLoad 9、TTestStyleImport 5、TControllerTest 9、TCssCatalogTest 14、TI18NTest 7、TReleaseManifestTest 15、TTyTerminalExampleTests 23。
- 全量：**8679 / 0 errors / 1 failure**（基线 8658 + 本批新增 21 条；17 分 46 秒）。红名单只有一条 `TTyTerminalPerfTests.TestAFloodStillPaints`（「最长无重绘 363.9 ms < 300 ms」），与本批改动无关（终端代码没动）：跑全量时另一棵树（`ty-advchart`）的全量测试同时在跑；单跑三次都绿（最长无重绘 80.5 / 58.3 / 157.1 ms）。全量里的试解析计时：15–31 ms。
- `lazbuild -B tools/themebuilder/themebuilder.lpi` 0 错（没有重编 SynEdit）；`example-rsj2po.py` added=0（`rsTbDensityFailed` 已随 `45668bee` 进 `.po`）；`check-example-po.py` 103 个文件 0 问题；`check-lfm-props.py` OK。

### 集中变异（本批修复；每条改一行 → `lazbuild -B` → 跑指定测试 → 还原原字节）

| # | 变异 | 必须红的测试 | 结果 |
|---|---|---|---|
| M1a | `EnterVar` 不抛 | `TTestCssValuesEval.TestAVariableCycleRaises`、L14、成环预览测试、主窗体成环测试 | 红（前两个失败、后两个进程段错误） |
| M1b | 去掉 `ScanVarCycles` 调用 | L14、`TestAVariableCycleIsAProblem` | 红 |
| M2a | `PreviewChanged` 改回 `RefreshNow` | F19 | **等价**：同一文本再载入不清 `ModeError`（M2b 那半修复）已让结果正确，多一次重载看不出来；两半互为保险，M2b 红 |
| M2b | `LoadDocument` 成功一律清 `ModeError` | V11「same document again keeps it」、F19「refresh keeps it」 | 红 |
| M2c | 解析失败也列 `ModeError` | F19「not listed while the text does not parse」 | 红 |
| M3 | 临时文件名改成目标本身（直写） | F20 | 红（原文件没了，`EFOpenError`） |
| M4 | 旧探测（修前代码） | `TestTheProbeIsQuick` | 红（aero 1062 ms，见计时表「修前」列） |
| M4a | 快探测不求值底层规则 | V18 | 红（`--radius: 1px 2px 3px` 快探测说干净、引擎拒）；V17 未红——`Notify` 里控件重量尺寸时抛，同样拒收，属第二道保险 |
| M4b | `cEveryState` 去掉 `tysDisabled` | V17（暗色被拒） | 红 |
| M5 | 设置保存不包 try/except | F21 | 红 |
| M6 | 去掉 `ClampToEditor` | F22 | 红（报在第 3 行） |
| M7 | 时间戳比较按 2 秒一格 | D11 | 红 |
| M9a | 打开失败一律移出最近列表 | F23 | 红 |
| M9b | 标题不转义 `&` | F24 | 红 |
| L2 | 单模式文档不清模式 | V21 | 红 |
| L3 | 换密度失败不退回 | V20 | 红 |
| L4 | `.lfm` 去掉 `ShowHint` | F25 | 红 |
| L5 | 书签图标又设成 `GutterIcons` | F26 | 红 |
| L6 | `Ask` 记录的类型恒为 `mtConfirmation` | F27 | 红 |
| L7 | `.lfm` 去掉 `DropDownMenu` | V19 | 红 |
| L8 | 不关 `eoTrimTrailingSpaces` | F28 | 红 |
| L10 | `.lfm` 去掉 `DensityCombo` 的左锚 | V22 | 红 |
| T13 | `FormDestroy` 不摘监听 | F16 | 红（释放后的监听被调用，随即访问已释放的窗体 AV） |

变异分批做，同批的变异互不影响指定测试（T13 会让之后每个主窗体测试的 `TearDown` 都 AV，单独一批重跑）。全部还原后 `git diff --quiet -- source tools tests` 为真，再 `lazbuild -B` 跑全量。

### 与规格不符之处（期末新增，已写回 spec）

1. spec §4 共享改动多一处：`Css.Values` 的变量成环防护（第 4 条）。
2. spec §5.3 试解析改为快探测 + 引擎定案两段；带 `@import` 的文档只走引擎（验收 E9）。
3. spec §5.3 换密度可被拒；单模式文档不显示为暗色。
4. spec §5.4 文末错误钳到最后一行；解析失败时不列切模式被拒。
5. spec §6 保存原子化、关掉去行尾空格、最近文件只移除已不存在的、外部修改按全精度时间戳。
6. spec §10 预览控制器会改全局回退字号（未改，交主控，验收 E10）。

### 计划外发现

- `TTyToggleSwitch.Checked` 的 setter 触发 `OnChange`——测试可以直接拨开关走真实路径。
- FPC 3.2.2 的 Windows 单元没有 `MOVEFILE_WRITE_THROUGH`（本地常量 8）；`FileAge` 把不足两秒的零头**向上**进到下一个偶数秒（D11 的夹具按这个选时间）。
- 无头测试里 LCL 不做 AutoSize 与锚定（要有句柄），工具条的布局只能查结构、真机看样子。
- 单条测试可以 `--suite=类名.测试名` 跑，变异时省时间。

### 遗留

- 必修 8（`TyFallbackFontSize`）：等主控 / 用户定（验收 E10）。
- 工具条在各皮肤下的实际样子、保存失败提示、成环不崩、刷新不卡：真机验收第 23–29 项。
- 快探测按引擎规则重走了一遍「哪些规则会被用到」，`StyleModel` 的解析规则将来变了要跟着改（V18 会红提醒）。

### 主控已做（c0cebbe1 之上）

- `lazbuild -B` 编 `tycontrols.lpk`、`tycontrols_dt.lpk`、`tools/themebuilder/themebuilder.lpi`：都 0 错。
- 冒烟：枚举工具进程的可见窗口，只有主窗体「未命名 - 主题编辑器」与应用窗口，没有 `#32770`。
- 第 8 项（E10，全局回退字号）：先按 (c) 不改——现有内置主题的 `--font-size-base` 都是 9，今天看不出差别；留给用户验收时定。
- 本批修复不另派审查：三期做完、交验收之前对整个分支做一次总审查。

### 原「主控待做」

1. 在签收头提交上 `lazbuild -B tycontrols.lpk`、`lazbuild -B tycontrols_dt.lpk`（`Css.Values.pas`、`ThemeLint.pas`、`Css.Parser.pas` 改过）、`lazbuild -B tools/themebuilder/themebuilder.lpi`，冒烟启动工具（只有主窗体与应用窗口、没有 `#32770`）。
2. 定必修 8 的做法（E10）。
3. 视情况再派一次期末审查看本批修复。
