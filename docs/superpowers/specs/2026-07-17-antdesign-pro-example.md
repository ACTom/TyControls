# examples/antdesign —— "TyControls Pro" 示例系统

> 状态:**已落地(2026-07-17)** · 配套路线图:`docs/design/2026-07-16-antd-gap-controls.md`

## 1. 定位

不是又一个"控件陈列柜",而是一个**做成产品样子的示例系统** —— 仿 [Ant Design Pro](https://pro.ant.design/) 的后台布局,主题固定以 **antdesign** 皮肤为默认。

它有三个作用:
1. **对外**:证明这套控件能拼出真实的现代后台界面,而不只是单控件 demo
2. **对内**:AntD-gap 批次程序的**集成验收面** —— 每落地一个新控件就有确定的归位,做完立刻能看见
3. **回归**:把新老控件放在同一主题下并排,风格不一致会一眼看出来

## 2. 布局(Ant Design Pro 的骨架)

```
┌─────────────────────────────────────────────────────┐
│ TTyTitleBar   TyControls Pro     [皮肤▾] [暗色开关] │  ← 自绘窗框(项目铁律)
├───────────┬─────────────────────────────────────────┤
│           │ 首页 / 工作台 / 仪表盘        〔Avatar〕│  ← 顶部条(仅面包屑)
│  Sider    ├─────────────────────────────────────────┤
│  折叠菜单 │                                         │
│           │            内容区(切页)                │
│  (可折叠) │                                         │
└───────────┴─────────────────────────────────────────┘
```

- **窗体**:`TTyForm` + `TTyTitleBar`,全部控件放在 `Surface` 里(见 formsurface 定论)
- **Sider**:左侧导航,用 **`TTyListGroupPanel`**(Outlook 式分组可展开列表 = 折叠菜单);
  整条收起走「视图」菜单,拉宽窄走 `TTySplitter`
  > **2026-07-17 修正**:原设计写的是 `TTyTreeView`,是**错的**。Ant Design Pro 的 Sider 是
  > **折叠菜单**,不是树:导航是"固定两层、点一个就去",树是"任意深度的层级数据浏览器"。
  > 用树做导航,拿到的是根节点 / 缩进 / 树线这些用不上的外观,而分组开合 + 条目即目的地
  > 的语义反而得自己拼。手风琴控件把这两层直接做成了 `AddGroup`/`AddItem` + `OnItemClick`。
- **顶部条**:`TTyBreadcrumb`(随 Sider 选中项重建)—— **不再另画页面标题**
  > 面包屑末节按契约就是"你在哪"(`docs/controls/breadcrumb.md`),它已经是页面标题了。
  > AntD Pro 之所以能同时摆一个大标题,是因为它的 PageHeader 有 ~100px 高、靠字号差
  > (12px 灰面包屑 vs 20px 粗标题)拉出层次;本例的顶部条只有 44px,塞不下这个层次,
  > 两行同号文字叠在一起只会糊成一团(用户原话:"仪表盘三个字有啥用")。故只留面包屑。
- **内容区**:`TTyPageControl`(页签隐藏,靠 Sider 切页)—— 每页对应一个主题分组

## 3. 页面规划 —— **全部落地(2026-07-17)**

原表分「现在能放 / 待补」两列,是因为立项时 14 个控件一个都还没写。**现在 14 个全部写完并已并入本示例**,所以「待补」列已全部兑现,下表保留它只为留档当初的规划。

| 页面 | 内容 | 原「待补」(现已全部落地) |
|---|---|---|
| **仪表盘** | `TTyCard`★ 承载各区块、`TTyBadge`★、`TTyTag`★、`TTySparkline`、`TTyChart`、`TTyCircularProgress`、`TTyMeter` | — |
| **列表 / 表格** | `TTyListView`、`TTyTag`★(状态列)、`TTyBadge`★ | `TTyPagination`(批2)、`TTyEmpty`★(空态) |
| **表单 / 录入** | `TTyEdit`、`TTyNumericEdit`、`TTyComboBox`、`TTyDateTimePicker`、`TTyToggleSwitch`、`TTyTrackBar`、`TTyRating`、`TTyCheckBox`、`TTyRadioGroup`、`TTyColorButton` | `TTyTreeSelect`、`TTyCascader`、`TTyTransfer`(批3) |
| **反馈** | `TTyMessage`(模态)、`TTyDialog`、`TTyProgressBar`、`TTyActivityIndicator` | `TTyAlert`★(内联条)、`TTyNotification`★(角落 toast)、`TTyPopover`(批3) |
| **导航** | `TTyPageControl`、`TTyTabSet`、`TTyMenuBar`、`TTyToolBar` | `TTySteps`(批2)、`TTyBreadcrumb`(批2)、`TTySegmented`★ |
| **数据展示** | `TTyCard`★、`TTyTag`★、`TTyBadge`★、`TTyTreeView`、`TTyExPanel`(≈Collapse)、`TTyImageView` | — |

★ = 批 1

**占位机制(已功成身退)**:每个待补控件的位置曾放一个 `TTyLabel` 占位 + `umain.pas` 里一条 `{ TODO(批N): 用 TTyXxx 替换 LblPhXxx }`。**11 个占位与 TODO 现已全部被真控件取代**,顶部条那段面包屑字符串拼接也换成了真的 `TTyBreadcrumb`。这套「可执行的规划」确实按设计兑现了:每条 TODO 都有确定的归位,做完即可替换。

> 仅剩一条 TODO(`umain.pas`,列表页状态列):`TTyListView` 的单元格里放不了 `TTyTag` —— 标签是控件,不是绘制元素。这不在 11 个占位之列,且陈述仍然成立,故保留。

## 4. 硬约束(项目铁律,别破)

- **界面全部在 `.lfm` 里设计**,不在代码里 `Create` 控件(examples-must-be-lfm-titlebar-skin)
- 控件**放进 `Surface`**;非可视组件留在窗体上
- **必须能运行时换肤**(标题栏内置皮肤下拉 + 暗色开关),默认 `antdesign`
- 视觉值**一律走主题 token**;这个 example **不许**为了好看在代码里硬编码颜色

## 5. 依赖 / 先决条件 —— **已满足(2026-07-17)**

样式键**在任何主题下都没有定义**时,控件确实不渲染(`DrawFrame` 拿不到 background 就不画)。但"某个皮肤的 `.tycss` 里没写"**不等于**不渲染:模型有两层,base 层(`tyControls.DefaultTheme`,由 `themes/light.tycss` 生成)垫在每个主题下面,皮肤没定义的 typeKey 会**继承** base 的规则,并用**该皮肤自己的 var** 求值。

本节最初的两条判断经实测后修正:

- `TyCard` / `TyCardHeader` / `TyCardActions` / `TyTag` / `TyTagClose` —— 曾是 **0 覆盖,而且连 base 都没有**,所以在**任何**主题下都不画(比"0/20"更严重)。**真正的修复是补 `light.tycss` → 重跑 `gen-defaulttheme.ps1`**;20 个主题各自的规则是在此之上的皮肤真实性打磨。**现已全部落地。**
- `TyBadge` —— 文件覆盖曾是 6/20,但**"14 个内置皮肤下 TTyButton 徽标不显示"这个 bug 并不存在**:base 层一直提供 `TyBadge`,实测 20 个主题全部能解析到 background、徽标都真画得出来。14 个皮肤后来补的显式 `TyBadge` 是**真实性打磨**(圆角强调色药丸在 classic/xp 这类皮肤上不合年代),不是 bug 修复。

守卫:`test.builtinthemes` 的 `TestAllBuiltinsDrawGapControls` —— 每个内置主题在**明暗两模式**下都必须能解析到 14 个控件中每一个**表面键**的 background(次级键如 Header/Actions/TagClose/StepsConnector 按契约可选、优雅降级,故不强制;`TTyTreeSelect` 也不在其中——它**故意没有自己的 key**,`GetStyleTypeKey` 返回 `'TyComboBox'`,因为它就是个组合框字段)。注意该守卫只在 **base 与皮肤都缺**该 key 时才红——因为 base 会兜底,用 `ResolveStyle` 断言"每个皮肤各自定义了 X"是假绿。

**顺序**:~~批1 主题规则~~(已完成)→ 骨架 + 仪表盘/数据展示页(已完成)→ 随批2/批3 逐页填充。

## 6. 目录 —— **骨架已落地(2026-07-17)**

`examples/antdesign/`:`antdesign_pro.lpi` / `.lpr` / `umain.lfm` / `umain.pas`(单窗体够用,没有拆 frame)。

6 个页面(`PgDashboard` / `PgList` / `PgForm` / `PgFeedback` / `PgNav` / `PgData`)全部就位,**14 个 Ant Design-gap 控件全部用上**(Card / Tag / Badge / Alert×4 型 / Notification / Popover / Empty / Segmented / Pagination / Steps / Breadcrumb / TreeSelect / Cascader / Transfer)。默认皮肤 `antdesign`,标题栏带皮肤下拉 + 暗色开关。

**验证状态**:`lazbuild -B` 通过;并用一次性探针确认 `umain.lfm` **能真正流式加载**(155 个组件)—— 编译通过并不能证明这点,`.lfm` 里写错属性名要到运行期流式化才报错。这个探针每次都值回票价:曾抓出 **`TTyEmpty` / `TTyPanel` 并未 published `Visible`**,`.lfm` 里写 `Visible = False` 会在流式化时 `EReadError` 炸掉(现改在 `FormCreate` 里设)。**视觉效果仍未真机过目。**

## 7. 真机反馈修正(2026-07-17,第二轮)

用户把本例与真的 Ant Design Pro 并排比对后提了 6 条,全部已改;探针实测结论记在这里,免得重犯:

| 反馈 | 真因(实测,不是猜) | 处置 |
|---|---|---|
| 顶部条压住内容、"今日访问上面有文字隐隐约约" | **不是几何重叠**(探针:TopBar 0..44、PageHost 44..619,严丝合缝)。真因是 44px 的条里塞了两个**图形控件**:`Crumb`(2..24)与 `LblPageTitle`(23..43)**互相压 1px**,且标题贴着条底、与内容区之间 0 间距——两段同号文字叠在一起,就是"隐隐约约" | 删掉冗余的 `LblPageTitle`(见 §2),面包屑垂直居中到 `Top=11` |
| 面包屑下面的"仪表盘"三个字有啥用 | 末节即当前位置,确实是把同一个词写两遍 | 同上 |
| 左侧为啥用树 | 设计之初就选错了控件(见 §2 修正) | 换 `TTyListGroupPanel`;3 组 × 2 条目,`OnItemClick` 切页,探针逐条验过 6 个去处与面包屑 |
| 数据展示的图片没显示 | `LoadSampleImage` 猜的三条相对路径(`../../`、`../`、`./`)**没有一条**指得到 `themes/assets/background.jpg`——exe 跑在 `lib/<target>/`,真实路径是 `../../../../`;`LoadFromFile` miss 时按契约静默清空,于是永远是个空画框 | 不再赌文件:`BuildSampleImage` 用 BGRA **现画**一张抽象风景,颜色全部从主题解析(accent 取 primary 按钮底色),换肤即重画。17 主题 ×明暗 = 0 异常 |
| 折叠面板内容区超出边界 | **用户是字面正确的**:`TTyExPanel.AdjustClientRect` 只扣标题栏、**不扣边框**,所以 `Align=alClient` 的子控件拿到 `(0,26)-(781,200)` = 连边框一起盖住,文字直接压在边线上 | 例子侧改用显式内缩 + `Anchors=[akTop,akLeft,akRight]`(实测 12/12/12 留白,且跟随窗宽)。**库侧的 `AdjustClientRect` 不扣边框是真实缺口,留给库去修** |
| 导航页标签切换一片空白 | `TabsDemo` **压根没接 `OnChange`**,而 `TTyTabSet` 是**纯页签条**(不承载页面,见 `docs/controls/tabset.md`),它下面那 110px 只是控件自绘的空面板 | 页签条只留页签(`Height = TabHeight + 2`,与 `examples/tabset` 同款),下配真内容面板 `TabsBody`,由宿主按 `TabIndex` 换内容;分段控制器同理配 `LblSegValue` |
