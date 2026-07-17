# examples/antdesign —— "TyControls Pro" 示例系统

> 状态:规划(2026-07-17) · 配套路线图:`docs/design/2026-07-16-antd-gap-controls.md`

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
│           │ Breadcrumb ▸ 页面标题        〔Avatar〕 │  ← 顶部条
│  Sider    ├─────────────────────────────────────────┤
│  导航     │                                         │
│           │            内容区(切页)                │
│  (可折叠) │                                         │
└───────────┴─────────────────────────────────────────┘
```

- **窗体**:`TTyForm` + `TTyTitleBar`,全部控件放在 `Surface` 里(见 formsurface 定论)
- **Sider**:左侧导航。**当前**用 `TTyTreeView`(已有);折叠交互用 `TTySplitter`
- **顶部条**:**当前**用 `TTyLabel` 占位;`TTyBreadcrumb` 落地后替换
- **内容区**:`TTyPageControl`(页签隐藏,靠 Sider 切页)—— 每页对应一个主题分组

## 3. 页面规划(**为待开发控件预留位置**)

每页列出:**现在能放的**(已有控件)/ **待替换或补入的**(批次里待开发)。

| 页面 | 现在能放 | 待补(批次) |
|---|---|---|
| **仪表盘** | `TTyCard`★ 承载各区块、`TTyBadge`★、`TTyTag`★、`TTySparkline`、`TTyChart`、`TTyCircularProgress`、`TTyMeter` | — |
| **列表 / 表格** | `TTyListView`、`TTyTag`★(状态列)、`TTyBadge`★ | `TTyPagination`(批2)、`TTyEmpty`★(空态) |
| **表单 / 录入** | `TTyEdit`、`TTyNumericEdit`、`TTyComboBox`、`TTyDateTimePicker`、`TTyToggleSwitch`、`TTyTrackBar`、`TTyRating`、`TTyCheckBox`、`TTyRadioGroup`、`TTyColorButton` | `TTyTreeSelect`、`TTyCascader`、`TTyTransfer`(批3) |
| **反馈** | `TTyMessage`(模态)、`TTyDialog`、`TTyProgressBar`、`TTyActivityIndicator` | `TTyAlert`★(内联条)、`TTyNotification`★(角落 toast)、`TTyPopover`(批3) |
| **导航** | `TTyPageControl`、`TTyTabSet`、`TTyMenuBar`、`TTyToolBar` | `TTySteps`(批2)、`TTyBreadcrumb`(批2)、`TTySegmented`★ |
| **数据展示** | `TTyCard`★、`TTyTag`★、`TTyBadge`★、`TTyTreeView`、`TTyExPanel`(≈Collapse)、`TTyImageView` | — |

★ = 批 1(Card/Tag/Badge 已写,Alert/Notification/Empty/Segmented 待做)

**预留做法**:每个待补控件的位置放一个 `TTyLabel` 占位,文案写明"此处将放 TTyXxx(批N)",并在 `umain.pas` 留 `{ TODO(批N): 用 TTyXxx 替换 LblPlaceholderXxx }`。这样规划是**可执行的**,不是纸面承诺。

## 4. 硬约束(项目铁律,别破)

- **界面全部在 `.lfm` 里设计**,不在代码里 `Create` 控件(examples-must-be-lfm-titlebar-skin)
- 控件**放进 `Surface`**;非可视组件留在窗体上
- **必须能运行时换肤**(标题栏内置皮肤下拉 + 暗色开关),默认 `antdesign`
- 视觉值**一律走主题 token**;这个 example **不许**为了好看在代码里硬编码颜色

## 5. 依赖 / 先决条件

**在主题规则落地前,新控件放进去也不会渲染**(样式键未定义 → `DrawFrame` 拿不到 background 就不画):
- `TyCard` / `TyCardHeader` / `TyCardActions` / `TyTag` / `TyTagClose` —— 当前 **0/20 覆盖**
- `TyBadge` —— 当前 **6/20**(既有 bug:14 个内置皮肤下 `TTyButton` 的徽标也不显示)

**顺序**:批1 主题规则 → 骨架 + 仪表盘/数据展示页 → 随批2/批3 逐页填充。

## 6. 目录

`examples/antdesign/`:`antdesign_pro.lpi` / `.lpr` / `umain.lfm` / `umain.pas`(必要时每页一个 frame 单元)。
