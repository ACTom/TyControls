# 补齐现代 UI 基础件 —— 对标 Ant Design 的缺口

> 状态:路线图已批准(2026-07-16) · 基线:main `7031da4`(144 个已注册组件)

## 1. 由来

拿 [Ant Design 5.x 的组件总览](https://ant.design/components/overview)逐项比对我们已注册的 144 个组件,找出**在原生桌面语境下站得住、且我们确实没有替代品**的缺口。AntD 是 Web/React 库,不能照搬——判断标准是"这个 **UI 概念**我们缺不缺",不是"这个组件名我们有没有"。

## 2. 范围(14 个控件,分 3 批)

### 批次 1 —— 现代 UI 基础件(7 个)
小、独立、高频,互不牵扯,能立刻用上。

| 控件 | 缺口理由(为什么现有的顶不上) |
|---|---|
| `TTyCard` | 卡片容器(标题 + 内容 + 操作区)。`TTyGroupBox` 是"带边框标题的分组",`TTyPanel` 是裸容器——都不是卡片 |
| `TTyAlert` | **内联**警告条,常驻界面内。我们所有提示都是**模态弹窗**,这个语义完全没有 |
| `TTyNotification` | 角落浮出、自动消失的 toast。`TTyMessage` 是**模态对话框**,是另一回事 |
| `TTyTag` | 标签/胶囊。无替代 |
| `TTyBadge` | 独立徽标。现在 badge **焊死在 `TTyButton` 内部**,挂不到别的控件上 |
| `TTyEmpty` | 空状态占位(图 + 文案 + 可选操作)。列表/树/表格标配,现在只能手拼 Label |
| `TTySegmented` | 分段控制器。`TTyTabSet` 是页签条,语义和用法都不同 |

### 批次 2 —— 导航 / 流程(3 个)

| 控件 | 缺口理由 |
|---|---|
| `TTyPagination` | 上一页/下一页 + 页码按钮组(`1 2 3 … 195`)。**不依赖 Grid**,配 ListView/ListBox/自绘列表都用得上 |
| `TTySteps` | 向导步骤条。做安装/配置向导绕不开,现在得手搓 |
| `TTyBreadcrumb` | 面包屑。Shell 那套(ShellTreeView/ShellListView)正缺路径导航 |

### 批次 3 —— 数据录入的经典缺口(4 个)
交互最重(下拉 + 树 + 多列联动),放最后。

| 控件 | 缺口理由 |
|---|---|
| `TTyTransfer` | 双列表穿梭框。**经典桌面控件**(非 Web 概念),我们竟然没有 |
| `TTyTreeSelect` | 树形下拉。有 TreeView 有 ComboBox,唯独没有二者结合 |
| `TTyCascader` | 级联选择(省/市/区) |
| `TTyPopover` | **功能性缺口**:`TTyHint`/`TTyBalloonHint` 只能显示文本,**放不了控件**;`Popconfirm` 也依赖它 |

## 3. 明确不做(理由留档,免得反复纠结)

- **Grid / Table** —— 用户明确暂缓(工作量单独一档,见 controls-expansion 路线图)
- **Statistic / Descriptions / Result / Skeleton** —— 都是 Label/Panel 的**组合套路**,不值得做成控件(Descriptions 已有 `TTyValueListEditor`)
- **Tour / Watermark / QRCode / Masonry / Mentions / Anchor / Carousel** —— Web/移动味重,桌面场景少
- **FloatButton** —— 移动端范式
- **AutoComplete** —— `TTyComboEdit` / `TTyMRUComboBox` 基本覆盖;若要补,是给它们加"下拉建议"模式,不是新控件
- **Drawer** —— 桌面通常用 Splitter+Panel / ExPanel 解决;边缘案例,暂不做
- **TimePicker** —— 真缺,但应当是给 `TTyDateTimePicker` 加**"仅时间"模式**,不是新控件
- **Flex / Space / Grid(布局) / Layout / Form / Upload / ConfigProvider / App / Affix / Util / Pro\*** —— Web/React 框架概念,LCL 用 Align/Anchors + GridPanel/RelativePanel,**范式不同,照搬是水土不服**

## 4. 每个控件的完整形态(照 `fc3c11c` 的样板,一个都不能少)

1. `source/tyControls.<Name>.pas` —— 控件本体(BGRABitmap 自绘;窗口化 vs 图形控件基类按需选)
2. **主题**:所有 `.tycss` 的样式规则 —— `themes/*.tycss`(5 个)+ `themes/builtin/*.tycss`(15 个),**双模式都要**;改完**必须重跑 `gen-builtinthemes.ps1`**,否则 `test.builtinskins` 挂
3. **面板图标**:`scripts/gen-icons.ps1` 加字形 → `designtime/icons/TTy<Name>{,_150,_200}.png` → 重生成 `designtime/tycontrols_icons.lrs`
4. `designtime/tyControls.Design.pas` —— `RegisterComponents` + 默认拖放尺寸(如需)
5. `tycontrols.lpk` —— 加单元
6. `tests/test.<name>.pas` + 注册进 `tests/tytests.lpr`
7. `docs/controls/<name>.md` + `docs/controls/README.md` 索引
8. 示例:并进相关 example 的 `.lfm`(**控件放 `Surface` 里**)
9. 收尾:i18n(若有可翻译串)、README / CHANGELOG(按"只写用户可感知影响")

## 5. 约定

- **一批一 merge**(沿用既有惯例),每批开自己的分支
- 视觉值**一律走主题 token**,不在控件代码里硬编码(项目铁律)
- 每批合并前跑完整套件(基线 **2952 / 0 fail**,12 个既有 win32 句柄环境错)+ golden 像素守卫
