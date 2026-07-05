# 控件 API 文档

TyControls 全部控件的逐控件说明（属性 / 事件 / 状态 / 主题变体 / 示例）。所有控件由 BGRABitmap
全自绘、由 `.tycss` 文本主题统一着色。样式语言参考见 [../tycss-reference.md](../tycss-reference.md)，
通用事件基线见 [../events.md](../events.md)。

## 窗口与镶边

| 控件 | 说明 |
|------|------|
| [TTyForm](ttyform.md) | 自绘无边框窗体基类，`BorderIcons` 驱动 caption 按钮 |
| [TTyTitleBar](titlebar.md) | 可关联的标题栏（`Form.TitleBar` 模式） |
| [caption 按钮](captionbutton.md) | 标题栏的最小化 / 最大化 / 关闭按钮 |
| [窗口镶边总览](formchrome.md) | 窗口镶边整体机制与配置 |

## 按钮与选择

| 控件 | 说明 |
|------|------|
| [TTyButton](button.md) | 按钮：primary / danger / ghost 变体、`:selected`、数字徽标 |
| [TTyCheckBox](checkbox.md) | 复选框，支持三态（`State` / `AllowGrayed`） |
| [TTyRadioButton](radiobutton.md) | 单选按钮（同容器互斥） |
| [TTyToggleSwitch](toggleswitch.md) | 开关（ON/OFF 滑块） |

## 文本输入

| 控件 | 说明 |
|------|------|
| [TTyEdit](edit.md) | 单行文本框：选区、剪贴板、词级导航、IME |
| [TTyMemo](memo.md) | 多行编辑器：2D 导航、内嵌滚动条 |
| [TTySpinEdit](spinedit.md) | 数值微调框（箭头 / 方向键 / 滚轮，Min/Max/Increment） |
| [TTyComboBox](combobox.md) | 下拉框：只读选择 + 可编辑 `csDropDown` + 前缀自动补全 |

## 列表与数据

| 控件 | 说明 |
|------|------|
| [TTyListBox](listbox.md) | 列表框：键盘导航、内嵌自动滚动条 |
| [TTyTreeView](treeview.md) | 虚拟树（VirtualTreeView 级）：百万节点、多列 + 排序、复选 + 三态 + 单选、多选 + 整行、内联编辑、节点拖放、逐单元格自绘 |

## 容器与布局

| 控件 | 说明 |
|------|------|
| [TTyPanel](panel.md) | 通用容器面板 |
| [TTyGroupBox](groupbox.md) | 带标题的分组框 |
| [TTyPageControl](pagecontrol.md) | 多页签容器（含 `TTyTabSheet`） |
| [TTyTabSet](tabset.md) | 纯标签条（非页容器） |
| [TTySplitter](splitter.md) | 面板间可拖拽分隔条 |
| [TTyToolBar](toolbar.md) | 工具条 + `TTyToolSeparator` 分隔符 |
| [TTyStatusBar](statusbar.md) | 底部多分区状态栏 |

## 日期与时间

| 控件 | 说明 |
|------|------|
| [TTyCalendar](calendar.md) | 日历：日 / 月 / 年下钻、Min/MaxDate |
| [TTyDateTimePicker](datetimepicker.md) | 日期时间选择器：下拉日历 + 时间分段微调 |

## 范围与进度

| 控件 | 说明 |
|------|------|
| [TTyTrackBar](trackbar.md) | 滑块（连续取值） |
| [TTyScrollBar](scrollbar.md) | 滚动条 |
| [TTyProgressBar](progressbar.md) | 进度条 |

## 图形与仪表

| 控件 | 说明 |
|------|------|
| [TTyGauge](gauge.md) | 数值仪表：线性 / 弧形 / 环形，缓动值动画 |
| [TTyCircularProgress](circularprogress.md) | 环形进度指示器（ProgressBar 的环形版，复用仪表主题） |
| [TTyActivityIndicator](activityindicator.md) | 不确定态忙碌指示器（旋转弧 spinner） |
| [TTyMeter](meter.md) | 模拟指针仪表（表盘 + 刻度 + 指针） |
| [TTyLevelMeter](levelmeter.md) | 电平条 / VU 表（连续或分段点亮 + 峰值保持，水平 / 垂直） |
| [TTyDial](dial.md) | 可交互旋钮（拖动 / 滚轮 / 方向键改值） |
| [TTyAnalogClock](analogclock.md) | 模拟时钟表盘（时 / 分 / 秒针，可自动走时） |
| [TTySparkline](sparkline.md) | 内联迷你趋势图（折线 / 柱，无轴） |
| [TTyRating](rating.md) | 星级评分（悬停预览 / 点击 / 半星） |
| [TTyGearDial](geardial.md) | 齿轮旋钮（可拖动 / 滚轮的旋钮变体） |

## 文字

| 控件 | 说明 |
|------|------|
| [TTyLabel](label.md) | 文本标签（支持助记符下划线） |
| [TTyLinkLabel](linklabel.md) | 超链接标签（accent + 下划线，点击打开 URL） |
| [TTyShadowLabel](shadowlabel.md) | 带投影的文字标签 |
| [TTyGlowLabel](glowlabel.md) | 带发光光晕的文字标签 |

## 提示

| 控件 | 说明 |
|------|------|
| [TTyHint](hint.md) | 主题化气泡提示（替换原生 LCL tooltip，全应用生效） |
| [TTyBalloonHint](balloonhint.md) | 带指针的气泡标注（标题 + 正文 + 可选图标） |

## 图标与图像

| 控件 | 说明 |
|------|------|
| [TTyIconFont](iconfont.md) | 图标字体源（注册 .ttf、name→codepoint、渲染字形） |
| [TTyCharImage](charimage.md) | 单个图标字体字形作为图像控件 |
| [TTyGlyphImageList](glyphimagelist.md) | 图标字体字形图像列表（供 Ty 控件消费） |
| [TTyImage](image.md) | 主题化位图图像控件（拉伸/等比/居中） |
| [TTyImageCollection](imagecollection.md) | DPI 感知的命名位图集合 |
| [TTyVirtualImageList](imagecollection.md) | 从集合按目标 DPI 绘制的虚拟图像列表 |

## 菜单

| 控件 | 说明 |
|------|------|
| [菜单](menu.md) | `TTyMenuBar`（菜单栏）+ `TTyPopupMenu`（右键弹出菜单） |

## 对话框

| 控件 | 说明 |
|------|------|
| [对话框](dialogs.md) | 全部 11 个自绘对话框组件 + 全局函数（消息 / 输入 / 密码 / 文本 / 选值 / 选路径 / 颜色 / 字体 / 查找 / 替换 / 进度） |

## 主题与集成

| 控件 | 说明 |
|------|------|
| [TTyStyleController](stylecontroller.md) | 样式控制器：加载 / 切换 `.tycss` 主题 |
| [TTyNativeStyler](nativestyler.md) | 非可视组件：把原生 / 第三方 LCL 控件按主题着色 |
