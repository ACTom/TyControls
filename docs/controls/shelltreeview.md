# TTyShellTreeView

## 概述

`TTyShellTreeView` 是一个**文件系统后备**的 `TTyTreeView` —— 一棵**只显示文件夹**的目录树。
根节点是 `tyControls.FileSystem` 的 `TyFsRoots`(Windows 各盘符;Unix 的 `/` + 主目录 + 挂载卷),
每个目录的子节点在**首次展开时**才用 `TyFsReadDirectory(path, '*', [fotFolders])` 枚举 —— 懒加载,
深目录树不会一次读满整块盘。

它把 `TTySelectPathForm` 里早已跑通的那套目录树接线抽成了**可复用控件**,数据源换成 `tyControls.FileSystem`。
**零新增主题 token**(继承 `GetStyleTypeKey = 'TyTreeView'`)。

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

- **懒加载。** `PopulateRoots` 只铺根、不读任何子目录;展开箭头由 `OnInitNode` 用轻量的
  `TyFsHasSubdir`(找到**第一个**子目录即返回,不枚举全部)盖;子目录只在 `OnExpanding`
  首次展开(`ChildCount = 0`)时用 `TyFsReadDirectory[fotFolders]` 读一次。深树不会预读每一层。
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
