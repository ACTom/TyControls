# 工具窗口工作台 真机验收表（D 期 + E 期合并）

> 2026-09-28。D 期计划末尾的 43 项和 E 期计划末尾的补充项合成这一张，从 1 连续编号；「备注」一列是原来的编号（原 D-7 = D 期表第 7 项，原 E-48 = E 期补充表第 48 项）。D 期第 38 项已由 E 期的 38′ 替换。
> 两张原表留在 `2026-09-24-toolwindow-phase-d.md`、`2026-09-27-toolwindow-phase-e.md` 末尾，只作记录，按这一张验。

## 开始之前

- **一、IDE 组**：在 Lazarus 里安装 `D:/Projects/ty-3.1/tycontrols_dt.lpk` 并重建 IDE（这会把这台机器的包注册切到 ty-3.1 这棵树）。然后打开 `examples/toolwindows/toolwindows_example.lpi`，在设计器里打开 `umain.lfm` 做。这一组会改 `umain.lfm`，验完用 `git checkout -- examples/toolwindows` 还原。
- **二、运行时组**：直接跑 `examples/toolwindows/lib/x86_64-win64/toolwindows_example.exe`（主控已经编好）。
  - 菜单栏在标题栏左端（File / View / Layout / Diagnostics）；主题下拉框和 Dark 开关在标题栏右端。
  - Diagnostics 里的 Disable Output Page、Disable Search Window 是开关，打勾 = 禁用着；每项验完把它关回来。
  - 布局弄乱了用 Layout › Reset Layout 回到 .lfm 的样子。程序关掉时会把布局存到 `GetAppConfigDir(False)` 下的 `toolwindows.layout`（Windows 上一般在 `%LOCALAPPDATA%\toolwindows_example\`），下次启动读回来。
- 「平台」一列写的是**必须**在哪验；空着的在手头的 Win32 上验一遍就行。

## 一、Lazarus IDE（设计器）

| # | 验什么 | 平台 | 怎么操作 | 期望 | 备注 |
|---|---|---|---|---|---|
| 1 | 面板图标 | | 看「TyControls Containers」页；系统缩放 100% / 150% / 200% 各看一眼 | 栏和 manager 两个按钮有图标、不糊 | 原 D-1 |
| 2 | 放下栏的尺寸 | | 从面板点一下放一条栏到空白窗体上（150% 缩放下再放一次） | 左侧一条带图标条的栏，写着「添加工具窗口」；对象查看器里 `ExpandedSize` 正好 240（不是 239 / 241 / 380）、不加粗。拖一个矩形放下也一样：拖出的宽被忽略，栏按 240 推导（已知） | 原 D-2 |
| 3 | 改 `Placement` | | 对象查看器里改成 `twpRight` / `twpBottom` | `Align` 跟着变，栏挪到父控件那一侧的最外边 | 原 D-3 |
| 4 | 新建工具窗口 + 撤销 | | 栏右键「新建工具窗口」（`New Tool Window`）；再 `Ctrl+Z` | 新窗口成为当前页、名字和标题一样、窗体标题出现「*」；撤销后窗口没了 | 原 D-4 |
| 5 | 设计期点图标 / 标签切页 | | 左栏点另一个图标；底栏点另一个标签 | 松开时切页，对象查看器的 `ActiveIndex` 跟着变 | 原 D-5 |
| 6 | 设计期能点选禁用窗口 | | 选中 SearchWin，对象查看器把 `Enabled` 改成 False；点 Explorer 图标，再点 Search 图标。底栏把 OutputWin 的 `Enabled` 改成 False，点别的标签，再点 Output 标签。验完两个都改回 True | 禁用的图标 / 标签画灰，但点了照样切页、`ActiveIndex` 跟着变；设计期底栏不让出标签行，Output 的筛选框和清除按钮照旧在标签行右端 | 新增（审查指出） |
| 7 | 标签行让位给栏 | | 底栏：点标签行后面的空白处 | 选中的是栏，不是当前页窗口 | 原 D-6 |
| 8 | 「显示窗口 ▸」 | | 栏右键「显示窗口 ▸」（`Show Window ▸`）→ 挑一个窗口 | 切过去并选中它；子菜单每项是「名字 "标题"」 | 原 D-7 |
| 9 | 移到另一侧栏 + 撤销 | | 左栏窗口（比如 SearchWin）右键「移到另一侧栏」（`Move to Other Side Bar`）；再 `Ctrl+Z`；底栏窗口右键看同一项 | 窗口到了右栏、成为当前页、窗体标题出现「*」；撤销后回到左栏，排在**末尾**、成为当前页（原来的序号不还原，已知）；底栏窗口上这一项是灰的 | 原 D-8 |
| 10 | 设计期右栏删光了照旧显示 | | 选中 OutlineWin（右栏唯一的窗口），右键「移到另一侧栏」；看右栏；再 `Ctrl+Z` | 右栏照旧在、原来的宽，内容区写着「添加工具窗口」（`Add a tool window`），不会缩成 0 消失（`HideWhenEmpty` 只管运行时）；撤销后 Outline 回到右栏 | 新增（审查指出） |
| 11 | 添加操作区 | | 窗口右键「添加操作区」（`Add Actions Area`），往里拖一个按钮；再右键看同一项 | 操作区出现在标题行右端，按钮在里面；第二次这一项是灰的 | 原 D-9 |
| 12 | Placement 冲突提示 | | 把右栏的 `Placement` 改成 `twpLeft`；再改回来 | 两条栏底部立刻出现「与另一条栏的 Placement 相同」（`Same Placement as another bar`），不用点一下才刷新；改回来立刻消失 | 原 D-10 |
| 13 | 撤销删除 → 孤儿 | | 选中一个窗口按 Delete，再 `Ctrl+Z` | 窗口出现在窗体上、顶上一行「不在工具窗口栏里，运行时隐藏」（`Not in a tool window bar: hidden at run time`）；右键「移回栏里 ▸」（`Move Back into Bar ▸`）挑原来的栏，回去并成为当前页（排在末尾）；再 `Ctrl+Z`，又成孤儿 | 原 D-11 |
| 14 | 粘贴 | | 复制一个窗口；点侧栏图标条（选中栏）再粘贴；再选中当前页窗口的正文粘贴一次 | 第一次进了栏；第二次落在窗口里，显示成孤儿提示 | 原 D-12 |
| 15 | 继承窗体 | | 新建一个继承自 `umain` 的窗体，在继承来的窗口上右键 | 「移到另一侧栏」灰；往继承来的栏里「新建工具窗口」可以 | 原 D-13 |
| 16 | frame 实例 | | 新建一个 frame 放一条栏和两个窗口，再把 frame 放到窗体上，右键 frame 里的栏和窗口 | 新建 / 添加 / 移动三类菜单项都是灰的 | 原 D-14 |
| 17 | `Controller` 隐藏 | | 选中窗口、选中操作区看对象查看器 | 没有 `Controller`；栏上有 | 原 D-15 |
| 18 | 设计期角标 | | 选中 OutlineWin，对象查看器改 `ShowBadge`、`BadgeValue`、`BadgeDot` | 设计器里右栏图标右上角立刻出现 / 变化（数字胶囊或圆点）；保存再打开还在 | 原 E-50 |
| 19 | 保存再打开 | | 调过顺序、换过当前页、有一个孤儿的窗体保存、关掉、再打开 | 顺序、当前页、孤儿都还在 | 原 D-16 |
| 20 | 组件树里选中藏着的窗口 | | 在对象查看器的组件树里点一个非当前页的窗口 | 不会切过去（LCL 设计器不调 `ShowControl`，文档写了；**据 Lazarus 源码推断，以真机为准**）；记下实际表现 | 原 D-17 |
| 21 | 中文 IDE | | Lazarus 切到中文重启，右键栏和窗口 | 菜单项是中文 | 原 D-18 |

## 二、运行时（`examples/toolwindows`）

| # | 验什么 | 平台 | 怎么操作 | 期望 | 备注 |
|---|---|---|---|---|---|
| 22 | 启动事件 | | 看 Output 页 | 第一行 `Ready`；启动时没有 `active =` 之类的切页日志 | 原 D-19 |
| 23 | 跨侧拖动 | | 按住 Search 图标拖到右栏图标条、再拖到右栏内容区上、再拖到编辑区上 | 右栏条上出现插入线；在内容区上线停在最后一个图标后面；编辑区上是禁止光标、没有线；在右栏松开就过去了，日志一行 `moved SearchWin from LeftBar (#…)` | 原 D-20 |
| 24 | 拖动光标 | Win32、GTK3、Qt、Cocoa | 同上，看光标 | 拖动中一直是拖动光标 / 禁止光标，松开后恢复 | 原 D-21 |
| 25 | Esc 取消 | Win32、GTK3 | 拖到一半按 Esc | 什么都没变；松开不算点击 | 原 D-22 |
| 26 | 拖出源栏后的坐标 | GTK3（X11 / Wayland） | 从左栏拖到右栏 | 右栏的插入线跟着指针走，位置对 | 原 D-23 |
| 27 | 从双击起拖 | Qt | 双击一个图标，第二次按下不松、直接拖 | 能拖起来 | 原 D-24 |
| 28 | Alt+Tab 中途 | 各 widgetset | 拖到一半 Alt+Tab 切走 | 拖动取消，回来后栏状态正常 | 原 D-25 |
| 29 | 拖动中弹模态框 | 各 widgetset | Diagnostics › Show a Dialog in 3 s，马上去拖一个图标别松手 | 对话框弹出时拖动取消；关掉对话框后没有残留的插入线或光标 | 原 D-26 |
| 30 | 拖动中弹菜单 | 各 widgetset | Diagnostics › Pop Up a Menu in 3 s，同上 | 同上 | 原 D-27 |
| 31 | 捕获期间离开 | Win32 | 按住图标（不超过阈值）移出栏再移回来松开 | 按阈值内松开算点击，图标悬停状态不乱 | 原 D-28 |
| 32 | 窗口里的按钮移动自己 | Win32 优先 | 点 Outline 操作区的双向箭头按钮（提示 `Move to the other side`）；到了左边再点一次 | Outline 到了左栏，程序不崩；右栏空了整条隐藏、编辑区变宽；日志先是 `MoveWindow returned True; Outline is in RightBar right now`（返回 True、还在旧栏），再是 `moved OutlineWin from RightBar (#0)`。再点一次回到右栏，右栏重新出现 | 原 D-29 |
| 33 | 窗口里的按钮恢复布局 | Win32 优先 | 先把布局弄乱，再点 Explorer 操作区的逆时针箭头按钮（提示 `Reset layout`） | 恢复到启动时的样子，程序不崩 | 原 D-30 |
| 34 | 布局存取 | | 拖乱、收起一侧、调宽、换当前页 → Layout › Save Layout → 再弄乱 → Layout › Load Layout；再 Layout › Reset Layout；再关掉程序重开 | Load 回到存的样子；Reset 回到 .lfm 的样子；重开回到关之前的样子 | 原 D-31 |
| 35 | 底栏最大化 / 收起 | | 标签行的最大化按钮、收起按钮；标签右键菜单（Maximize / Restore、Hide Panel）；View › Bottom Panel（Ctrl+J） | 最大化压掉编辑区、还原回原高；收起后界面上没有底栏，Ctrl+J 叫回来 | 原 D-32 |
| 36 | 拉宽与吸附 | | 拖侧栏和底栏的边；拖到很窄再松手；拖回来 | 实时变宽；拖到内容下限一半以下松手 = 收起；拖回来不收起 | 原 D-33 |
| 37 | 右键菜单 | | 侧栏图标上右键「Move to Other Side」；图标条空白处右键 | 图标上弹菜单、能移；空白处不弹栏的菜单 | 原 D-34 |
| 38 | 溢出 | | 把窗体缩矮、缩窄到图标 / 标签放不下 | 出现溢出按钮；左栏菜单往右开、右栏往左开、底栏往下开 | 原 D-35 |
| 39 | 溢出菜单位置 | GTK3 / Qt Wayland | 同上 | 菜单贴着溢出按钮，不跑到屏幕角上 | 原 D-36 |
| 40 | 提示 | | 指针停在图标上、标签上、最大化按钮上 | 图标显示 StripHint（比如 `Explorer (files)`），标签显示 StripHint（比如 `Problems (no actions area)`），按钮显示 `Maximize`；中文界面下是中文 | 原 D-37 |
| 41 | 禁用当前页后标签行的提示 | | 底栏切到 Output，Diagnostics › Disable Output Page；指针停在 Problems 标签上、最大化按钮上、收起按钮上，再停在标签后面的空白处 | Problems 标签提示 `Problems (no actions area)`，按钮提示 `Maximize` / `Hide`（中文界面「最大化」/「收起」）；空白处没有提示 | 新增（让出行的提示跟栏的 `ShowHint`，示例底栏开着） |
| 42 | 禁用当前页（底栏） | 各 widgetset | 底栏切到 Output，Diagnostics › Disable Output Page。Output 还是当前页时：点最大化、再点还原；点收起，再 Ctrl+J 叫回来；把窗体缩窄到有标签收进溢出，点溢出按钮。然后点 Problems 标签；再点 Output 标签；最后再点一次菜单启用 | Output 正文灰、操作区（筛选框、清除）看不见，标签行不变淡；最大化 / 还原 / 收起 / 溢出照常；点 Problems 能切过去；Output 标签灰、没有悬停、点了不切；启用后操作区回来、Output 标签能点。**不再**有「点什么都没反应、切不走」 | 原 E-38′（替换原 D-38） |
| 43 | 禁用当前页（底栏）点正文 | Win32、GTK3、Qt、Cocoa | Output 禁用、还是当前页时，在它的正文上点几下、双击几下 | 没有任何反应，程序不崩（Win32 上栏的 `OnMouseDown` 会触发，示例里看不出来，不算问题） | 原 E-46 |
| 44 | 禁用非当前页（侧栏） | | 左栏当前页是 Explorer 时，Diagnostics › Disable Search Window；指针停在 Search 图标上、点它、按住拖它；右键它选 Move to Other Side | 图标灰、没有悬停、点了不切、拖不起来；提示照常；右键菜单能把它移过去 | 原 E-44 |
| 45 | 禁用当前页（侧栏） | | Layout › Reset Layout，确认 Search 启用着（Disable Search Window 没打勾）；切到 Search，再 Diagnostics › Disable Search Window；点 Search 图标两次；点 Explorer 图标 | 第一次收起、第二次展开；点 Explorer 切过去 | 原 E-45 |
| 46 | 换父后的 IME / 光标 | Win32、Linux | Search 框里用中文输入法打到一半（不上屏），拖 Search 到右栏 | 组字被丢掉（文档写的），程序不崩；再点进去能正常输入 | 原 D-39 |
| 47 | 侧栏角标 | | 看 Search 图标；点左栏当前页的图标收起左栏，再看；展开后右键 Search › Move to Other Side，再看 | 图标右上角一个数字胶囊 `3`，不压住指示条；收起后还在；移到右栏后跟着过去 | 原 E-47 |
| 48 | 底栏角标、99+、溢出 | | 看 Problems 标签；Diagnostics › Add 45 Problems 点三次（必要时把窗体缩窄）；有溢出按钮就点开 | 开始时标题后面一个胶囊 `2`；点三次后 Problems 显示 `99+`，后面的标签右移或收进溢出菜单；溢出菜单里写 `Terminal (1)`（Output 也收进去、又亮着圆点时写 `Output •`） | 原 E-48（期望改过） |
| 49 | Output 圆点 | | 先切到 Output；切到 Problems；收起再展开底栏（收起按钮，再 Ctrl+J）；拖一个侧栏图标换个位置，或点 Diagnostics 里的某一项（比如 Add 45 Problems）；再切回 Output | 切到 Problems：圆点不亮；收起再展开：仍不亮；拖图标或点 Diagnostics 之后：Output 标签后面亮一个圆点；切回 Output：圆点灭 | 原 E-49（期望改过，删了「换个主题」） |
| 50 | 一侧空了隐藏 + 放置预览 | | 把 Outline 拖到左栏；再从左栏按住一个图标往右拖，指针进右侧那块、出来、再进去、松手 | 右栏整条消失、编辑区变宽；拖动一开始右侧编辑区边缘就出现一块「放到右侧栏」（英文 `Drop here to show the right side bar`），宽同右栏原来展开的宽；指针进去高亮、出来恢复；松手右栏出现、窗口成为当前页并展开 | 原 E-51 |
| 51 | 预览的平台行为 | GTK3（X11 / Wayland）、Qt、Cocoa | 同 50 | 预览出现在编辑区右边缘、盖在编辑区上（不被编辑区或底栏挡住）；拖动不因预览出现而中断；松手或 Esc 后预览消失、不留残影 | 原 E-52 |
| 52 | 预览中取消 | 各 widgetset | 同 50，拖到一半按 Esc；再试一次：先点 Diagnostics › Show a Dialog in 3 s，马上开始拖，等对话框弹出 | 预览消失，右栏仍隐藏，窗口没动 | 原 E-53 |
| 53 | 隐藏的一侧用菜单移过去 | | 右栏隐藏时，右键左栏的一个图标 › Move to Other Side | 右栏出现，窗口过去了 | 原 E-54 |
| 54 | 布局存取与隐藏 | | 右栏隐藏时 Layout › Save Layout；Layout › Reset Layout；再 Layout › Load Layout；关掉程序重开 | Reset 后右栏回来（Outline 在右边）；Load 后右栏又隐藏；重开是关之前的样子 | 原 E-55 |
| 55 | 同侧有别的对齐控件时，空侧栏回到原位 | | 需在自己的窗体里摆（示例里侧栏没有同侧的对齐兄弟）：左侧再放一个 alLeft 面板，紧挨在左栏里侧（左栏和编辑区之间）；右栏外侧（窗体最右边）再放一个 alRight 面板；放一个 manager，两条栏都指向它，各放一两个窗口。运行：把左栏的窗口全拖到右栏，再拖一个回来；把右栏的窗口全拖到左栏，再拖一个回来。把窗体缩窄一些，再来一遍 | 左栏隐藏时面板贴到窗体左边；左栏回来时出现在面板**外侧**（窗体最左），面板仍紧挨在它右边、中间没有缝。右栏回来时在右侧面板**里侧**，右侧面板仍贴着窗体右边 | 新增（`ApplyAxisSize` 的新规则） |
| 56 | 换肤 | | 标题栏右端的主题下拉框 17 个主题逐个切，Dark 开关亮 / 暗都切 | 标题行、标签下划线、图标着色、边缘线都对；拖动时插入线看得见（高对比度皮肤重点看） | 原 D-40 |
| 57 | 换肤看角标和预览 | | 同上，每个主题看一眼角标、按 50 拖一次看预览 | 角标数字看得清（高对比度皮肤重点看）；预览底色和边框看得见、文字看得清 | 原 E-56 |
| 58 | 换密度 | | View › Density › Modern / Classic 来回切 | 图标条、标题行、标签跟着变，操作区按钮不被裁 | 原 D-41 |
| 59 | 字形清晰 | Linux、macOS | 看图标条、溢出、最大化、收起按钮，还有角标的小字 | 不糊 | 原 D-42 |
| 60 | 中文界面 | | 系统语言中文（或 `--lang zh_CN`）启动 | 菜单、窗口标题、日志是中文；布局照常存取（按 Name 认窗口） | 原 D-43 |

共 60 项：IDE 21 项，运行时 39 项。

## 发现问题怎么报

报编号 + 现象即可，比如「42：点收起没反应」。平台相关的写上在哪个平台。
