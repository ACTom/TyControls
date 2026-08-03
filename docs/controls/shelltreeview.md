# TTyShellTreeView

## 概述

`TTyShellTreeView` 是一个**文件系统后备**的 `TTyTreeView` —— 一棵**只显示文件夹**的目录树。
根节点是 `tyControls.FileSystem` 的 `TyFsRoots`(Windows 各盘符;Unix 的 `/` + 主目录 + 挂载卷),
每个目录的子节点在**首次展开时**才用 `TyFsReadDirectory(path, '*', [fotFolders])` 枚举 —— 懒加载,
深目录树不会一次读满整块盘。

它把 `TTySelectPathForm` 里早已跑通的那套目录树接线抽成了**可复用控件**,数据源换成 `tyControls.FileSystem`。

主题完全继承:它不 override `GetStyleTypeKey`,解析的就是树自己那套键 —— `TyTreeView`(外框)、
`TyTreeNode`(节点行,含 `:hover` / `:selected` / `:disabled`)、`TyTreeHeader` / `TyTreeHeaderSection`
(列头带与列头格)、`TyTreeCheckBox`(节点复选框)。**这一次"借用"是刻意保留的**:适配器只换数据源,
自己不画任何一个像素,一棵目录树在视觉上就是一棵树。给它换皮肤 = 改 `TyTreeView*` 规则。

> 注意区分:同一批审计里 `TTyListView` **不再**借树的键了(它画的图标流式格、分组带、橡皮筋树没有),
> 见 [listview.md](listview.md);而 `TTyShellTreeView` 属于"借得对"的那一类。

## 用法

```pascal
uses tyControls.ShellTreeView;

Tree := TTyShellTreeView.Create(Self);
Tree.Parent := Panel1;
Tree.PopulateRoots;                 // 铺根(构造时已铺一次,重置时再调)
Tree.Directory := 'C:\Users\Tom';   // 展开定位到某目录并聚焦
Tree.OnPathChange := @DirChosen;    // 焦点目录变化(对话框据此刷新右侧文件列表)
```

## 属性 / 方法

| 成员 | 说明 |
|---|---|
| `Directory: string` | 读 = 当前焦点目录(`SelectedPath`);写 = 展开定位并聚焦到该路径(`SelectPath`)。 |
| `ShowHidden: Boolean` | 是否枚举隐藏目录。默认 `False`。**只置标志**:新值在下次(重)展开时生效;要立即刷新调 `PopulateRoots`。 |
| `OnPathChange` | 焦点目录变化时触发,`SelectedPath` 是新路径。 |
| `PopulateRoots` | 清空并按 `TyFsRoots` 重铺根节点。 |
| `SelectedPath: string` | 当前焦点目录,无则 `''`。 |
| `SelectPath(path)` | 从含该路径的根逐级展开、聚焦到目标节点;无根为其前缀或某段不可达时静默返回。 |

## 关键设计

- **懒加载。** `PopulateRoots` 只铺根、不读任何子目录;展开箭头由 `DoInitNode` 用轻量的
  `TyFsHasSubdir`(找到**第一个**子目录即返回,不枚举全部)盖;子目录只在 `DoExpanding`
  首次展开(`ChildCount = 0`)时用 `TyFsReadDirectory[fotFolders]` 读一次。深树不会预读每一层。
- **published 事件槽位归应用,不归控件。** 节点文字 / 初始化 / 展开 / 图标 / 焦点变化这五件事现在是**覆写基类虚方法**
  (`DoGetText` / `DoInitNode` / `DoExpanding` / `DoGetImageIndex` / `DoTreeChange`),不再是构造函数里接到 published
  `OnGetText` / `OnInitNode` / `OnExpanding` / `OnGetImageIndex` / `OnChange` 上的 handler。以前控件占着这五个槽位,
  应用一赋 `OnGetText` 目录树就不显示文件名了,而且没有任何迹象说明为什么 —— shell 与应用在抢同一个槽。
  现在五个事件全归应用(与 LCL 的 `TShellTreeView` 同构),**每个覆写都调 `inherited`,而且放在最后**:
  应用的 handler 在 shell 把答案填好之后才跑,因此看得到、也改得动 shell 的决定(`DoExpanding` 里应用仍可否决展开)。
  `DoGetText` 的根节点分支尤其要注意这条 —— 它以前在根节点上直接 `Exit`,于是恰恰在一棵 shell 树**最先**显示的那批行
  (盘符与"位置")上,应用的 `OnGetText` 永远到不了;修一半比不修更难查:事件在一部分行上灵、另一部分不灵。
- **只文件夹,永不文件。** 枚举恒用 `[fotFolders]`(加 `[fotHidden]` 当 `ShowHidden`),从不 `[fotFiles]`。
- **节点 ↔ 路径。** 节点数据是一个 Integer 索引,指向控件持有的 `FPaths` 路径数组(`NodeDataSize := SizeOf(Integer)`),
  `NodePath(node)` 读回。这是 `TTyTreeView` 数据-按需模式的标准用法。
- **`ShowHidden` 只置标志、不重建树。** 属性写操作绝不释放消费者(或懒 `SelectPath` 遍历)正持有的节点句柄;
  且在"唯一可写目录位于隐藏祖先之下"的宿主上,重建会连当前路径一起弄丢。要立即可见刷新,消费者显式调 `PopulateRoots`。
- **文件夹/驱动器图标用固定调色板**(内容图标),128px master 降采样。不从主题取色 —— 构造时主题可能还没解析。

## 消费者

它是 Phase 7 文件对话框(`TTyOpenDialog`/`TTySaveDialog`)左侧的目录树面板;`OnPathChange` 是"树选中 → 右侧
`TTyShellListView.LoadDirectory`"的接线点。见 `docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`。

## 与 `TTySelectPathForm` 的关系

`tyControls.Dialogs.SelectPath` 里的 `TySubdirectories` / `TyPathHasSubdir` 已委托到本控件同源的
`tyControls.FileSystem`(`TyFsReadDirectory` / `TyFsHasSubdir`),消除了两处目录枚举逻辑的漂移。
`TyDriveRoots` 保持独立 —— 该选择器的根集是**仅驱动器**(Unix 只有 `/`),与 `TyFsRoots` 的更丰富根集
(含主目录 + 挂载卷)语义不同,合并会改对话框的根列表。
