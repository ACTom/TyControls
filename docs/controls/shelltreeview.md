# TTyShellTreeView

## 概述

`TTyShellTreeView` 是一个**文件系统后备**的 `TTyTreeView` —— 一棵目录树。
根节点默认是 `tyControls.FileSystem` 的 `TyFsRoots`(Windows 各盘符;Unix 的 `/` + 主目录 + 挂载卷),
也可以用 `Root` 把整棵树**收窄到某一个目录**;每个目录的子节点在**展开时**才用
`TyFsReadDirectory(path, '*', ObjectTypes)` 枚举 —— 懒加载,深目录树不会一次读满整块盘。
默认只枚举文件夹,`ObjectTypes` 里加上 `fotFiles` 就是经典资源管理器左窗格(文件作为叶子出现)。

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
Tree.OnPathChange := @DirChosen;    // 焦点目录变化(自行接线时用)
```

两控件文件浏览器**不用写胶水** —— 在对象查看器里连上就行(或代码里一行):

```pascal
Tree.ShellListView := List;   // 树里选中文件夹 → 列表加载它
List.ShellTreeView := Tree;   // 列表里进入文件夹 → 树跟着走(两个方向可同时接,不会递归)
```

## 属性 / 方法

| 成员 | 说明 |
|---|---|
| `Directory: string` | 读 = 当前焦点目录(`SelectedPath`,**不带**尾分隔符);写 = 展开定位并聚焦到该路径。**写不到时抛 `ETyShellInvalidPath`**(设计期/流式化时不抛),见下节。 |
| `Path: string` | **public(非 published)**,LCL 那个名字与那套语义(`shellctrls.pas:142`):读回目录时**带**尾分隔符,写时接受绝对路径**或**相对于 `GetRootPath` 的路径。以前只认"以某个根为前缀的绝对路径",相对写法静默什么也不做。不 published:同一份选中状态挂两个 published 名字会在每个 `.lfm` 里写两遍。 |
| `Root: string` | 把整棵树收窄到这一个目录;`''`(默认)= `TyFsRoots` 那套全机器"位置"。写它重建整棵树;目录不存在则抛 `ETyShellInvalidPath`(设计期/流式化不抛,同 LCL `shellctrls.pas:625`)。以前根本没有 —— 想做一棵限定在项目目录里的选择器只能派生。 |
| `ObjectTypes: TTyFsObjectTypes` | 枚举哪几类条目。默认 `[fotFolders]`(同 LCL)。加 `fotFiles` 则文件作为**叶子**出现(没有展开箭头、不会去读盘)。**写入即刷新**。 |
| `ShowHidden: Boolean` | 是否枚举隐藏项 —— 就是 `ObjectTypes` 里 `fotHidden` 那一位的另一个名字,两边**双向同步**。默认 `False`。**写入即刷新**。 |
| `FileSortType: TTyFsFileSortType` | 子节点顺序:`fstNone`(默认,同 LCL —— 原始 `FindFirst` 顺序)/ `fstAlphabet` / `fstFoldersFirst` / `fstCustom`(交给 `OnSortCompare`)。以前没有任何排序,`TyFsSortEntries` 一直躺在模型单元里没人调。 |
| `ExpandCollapseMode` | `ecmRefreshedExpanding`(默认,同 LCL:每次展开都重读)/ `ecmKeepChildren`(沿用已建好的子节点)。见下节 —— 本控件以前**写死**成比 `ecmKeepChildren` 还严的行为。 |
| `UseBuiltinIcons: Boolean` | 是否用自带的文件夹/驱动器/文件图标。默认 `True`;关掉则 `Images := nil`。以前唯一的办法是构造完再覆盖 `Images`,而且没法要"完全不要图标"。 |
| `OnPathChange` | 焦点目录变化时触发,`SelectedPath` 是新路径。 |
| `OnAddItem` | **逐条否决**:`(Sender, ABasePath, AEntry, var ACanAdd)`,置 `False` 丢掉这一条。此前唯一的过滤就是隐藏属性那一个粗粒度开关 —— 想藏掉 `.git`、系统联接点、符号链接环都做不到。 |
| `OnSortCompare` | 对两条**原始记录**的比较器;赋值即把 `FileSortType` 切成 `fstCustom` 并重读(同 LCL `shellctrls.pas:693`),清空则退回 `fstNone`。祖先的 `OnCompareNodes` 比的是**节点**(渲染出来的文字),按扩展名/日期/自然数排序需要的是文件记录。 |
| `ShellListView` | 设计期可赋值的**伴随文件列表**:树里选中一个文件夹,列表就加载它。以前必须手写 `OnPathChange → Directory` 的胶水,在对象查看器里根本连不起来。 |
| `PopulateRoots` | 清空并重铺根节点(`Root` 为 `''` 时按 `TyFsRoots`,否则一个 `Root` 节点)。整棵树重来,焦点也丢。 |
| `UpdateView(AStartDir = '')` | 按当前磁盘状态与当前设置**重新枚举已展开的节点**,保留展开状态与焦点路径。`AStartDir` 把刷新**限定在该节点的子树**内(同 LCL `shellctrls.pas:134`);该路径没有对应的**已实体化**节点时什么也不做 —— 屏幕上没有它,就没有东西需要更新。 |
| `Refresh(ANode)` | 只重读**一个节点**的子节点,其余不动;`nil` = 整棵树重铺(同 LCL `shellctrls.pas:133`)。应用自己刚建/删了一个文件夹时,这是最省的一条路。 |
| `GetPathFromNode(ANode): string` | **public** 的节点 → 绝对路径映射;目录会带尾分隔符(LCL 契约,`shellctrls.pas:1195-1207`),`nil` 返回 `''`。以前只有 `protected NodePath`,类外只能拿到**焦点**那一个路径 —— 多选取路径、绘制回调里查路径、拖拽源路径全都做不到。 |
| `GetBasePath` / `GetRootPath` | 平台基路径(Windows `''`、Unix `'/'`)与**当前生效**的根(有 `Root` 就是它,带尾分隔符)。对应 `shellctrls.pas:125-126`。 |
| `GetFilesInDir(...)` | **class function** 目录枚举器,给别的类复用(对应 `shellctrls.pas:127-129`)。返回本族统一的 `TTyFsEntryArray` 而不是填调用方的 `TStrings` —— 记录里带着 `Size` / `Modified` / `Attr` / `TypeName`,字符串列表装不下。 |
| `SelectedPath: string` | 当前焦点目录,无则 `''`。 |
| `SelectPath(path): Boolean` | 从含该路径的根逐级展开、聚焦到目标节点。**返回是否真的落到目标**;失败原因见 `LastPathError`。**不抛异常**。 |
| `LastPathError: TTyShellPathError` | 上一次路径赋值的结果:`speNone` / `speEmptyPath` / `speNoSuchPath` / `speNoRoot` / `speUnreachable`。 |

## `ExpandCollapseMode`:少一个枚举值,是**故意**的

LCL 的 `TExpandCollapseMode`(`shellctrls.pas:48-52`)有三个值,本控件只有前两个。
第三个 `ecmCollapseAndClear`(**折叠时**丢掉子节点)在这里**没有实现,而不是实现成空的**:
`TTyTreeView` 没有折叠方向的 protected 接缝 —— `SetExpanded` 是非虚的私有 setter,折叠时唯一的钩子是
published 的 `OnCollapsing` / `OnCollapsed`,而那两个槽位是**应用的**。提供一个赋了值却什么都不发生的枚举项,
正是这个控件这一轮刚刚清理掉的那类缺陷。要补齐它,需要在 `tyControls.TreeView` 里加一个 `DoCollapsed` 虚方法。

原来的行为**比 `ecmKeepChildren` 还严**:`ChildCount = 0` 才枚举,而且没有任何地方会清空子节点 —— 一个目录在控件的
整个生命周期里只被读**一次**,之后新建或删除的东西永远不出现,连折叠再展开都救不了。现在默认与 LCL 一致
(每次展开都重读),旧行为保留为 `ecmKeepChildren`。

> 顺带的一处正确性:`ecmRefreshedExpanding` 重建子节点时,焦点如果正落在被释放的那批节点里,
> `DeleteNode` 会把 `FocusedNode` 置空,但没人重新推导 `FSelectedPath` —— 于是树会继续**报告**一个它已经不站在
> 上面的目录。`DoExpanding` 现在会把焦点按路径找回来,找不到就把选中清空并触发 `OnPathChange`。

## 路径赋值失败是**可观测**的(不再静默)

以前 `SelectPath` 找不到路径就直接返回,`Directory` 还读回**旧**路径 —— 调用方分不清「路径写错了」和
「路径没错、这棵树就是显示不出来」。现在两条通道各司其职:

| 通道 | 失败时的行为 | 为什么 |
|---|---|---|
| `SelectPath(path): Boolean` | 返回 `False`,`LastPathError` 说明原因 | 方法**有返回值**,有返回值就不必用异常;文件对话框解析用户输入的路径是常态,不是异常 |
| `Directory := path` | 抛 `ETyShellInvalidPath` | 属性写**没有返回通道**,静默 = 不可恢复 |

```pascal
if not Tree.SelectPath(P) then
  case Tree.LastPathError of
    speNoSuchPath:  ShowMessage('目录不存在');
    speUnreachable: ShowMessage('目录存在,但当前设置下不可见(试试 ShowHidden := True)');
    speNoRoot:      ShowMessage('该路径不在任何一个已铺的根之下');
  end;
```

`speUnreachable` 时焦点**仍然移动** —— 落在能走到的**最深祖先**上,不会把用户丢在原地或空处。

**LCL 对照:** `TCustomShellTreeView` 抛 `EInvalidPath`(`shellctrls.pas:428` 声明;`SetRoot` 在 `:625`、
`SetPath` 在 `:1549 / :1561 / :1580 / :1604` 抛),并且**设计期不抛**(`:621-624` 注释:「Delphi 会抛,但别把
IDE 搞崩」)。本控件照抄了这个豁免:`csLoading` / `csDesigning` 下只记 `LastPathError`,不抛 —— 否则 `.lfm`
里一个过期路径就能让窗体流式化失败。赋 `''` 也不抛:那是「没选」,不是「选失败」。

## 关键设计

- **懒加载。** `PopulateRoots` 只铺根、不读任何子目录;展开箭头由 `DoInitNode` 用轻量的
  `TyFsHasEntry(path, ObjectTypes)`(找到**第一条**符合当前设置的条目即返回,不枚举全部)盖;
  子目录在 `DoExpanding` 里按 `ExpandCollapseMode` 读。深树不会预读每一层。
  (探针从 `TyFsHasSubdir` 换成了 `TyFsHasEntry`:前者不认 `fotHidden`,于是一个只含隐藏子目录的文件夹
  会显示一个展开后什么都没有的箭头;而且它也表达不了"树里也显示文件"。)
- **published 事件槽位归应用,不归控件。** 节点文字 / 初始化 / 展开 / 图标 / 焦点变化这五件事现在是**覆写基类虚方法**
  (`DoGetText` / `DoInitNode` / `DoExpanding` / `DoGetImageIndex` / `DoTreeChange`),不再是构造函数里接到 published
  `OnGetText` / `OnInitNode` / `OnExpanding` / `OnGetImageIndex` / `OnChange` 上的 handler。以前控件占着这五个槽位,
  应用一赋 `OnGetText` 目录树就不显示文件名了,而且没有任何迹象说明为什么 —— shell 与应用在抢同一个槽。
  现在五个事件全归应用(与 LCL 的 `TShellTreeView` 同构),**每个覆写都调 `inherited`,而且放在最后**:
  应用的 handler 在 shell 把答案填好之后才跑,因此看得到、也改得动 shell 的决定(`DoExpanding` 里应用仍可否决展开)。
  `DoGetText` 的根节点分支尤其要注意这条 —— 它以前在根节点上直接 `Exit`,于是恰恰在一棵 shell 树**最先**显示的那批行
  (盘符与"位置")上,应用的 `OnGetText` 永远到不了;修一半比不修更难查:事件在一部分行上灵、另一部分不灵。
- **节点 ↔ 路径。** 节点数据是一个 Integer 索引,指向控件持有的 `FNodes` 表(`NodeDataSize := SizeOf(Integer)`),
  每行是 `(Path, IsDir)`。`IsDir` 是**存下来的**而不是每次现探:图标、展开箭头、`GetPathFromNode` 的尾分隔符
  三处都要它,而这三处都跑在每帧绘制里 —— 那里每个节点一次 `DirectoryExists` 就是一次读盘。
  类内所有比较走 `protected NodePath`(原始、不带尾分隔符),对外是 `public GetPathFromNode`(LCL 契约)。
- **`ShowHidden` 写入即刷新。** 以前是「只置标志」:新值要等到某个节点碰巧被重新展开才生效,看上去就是这个属性
  坏了。当时的两条顾虑都是真的 —— ①属性写不该释放消费者(或懒 `SelectPath` 遍历)正持有的节点句柄;
  ②在"当前目录位于隐藏祖先之下"的宿主上,重建会把当前路径弄丢。现在这两条是**被处理掉**而不是被绕开:
  `UpdateView` 在遍历进行中时**自动推迟**到遍历结束再跑(不会在遍历脚下抽走节点),并且**按路径**恢复焦点 ——
  目标不可见时退到**能走到的最深祖先**,而不是把焦点丢在已释放的节点上。同一族的 `TTyShellListView.ShowHidden`
  一直都是写入即重读,树没有理由例外。LCL 也是写入即刷新(`SetObjectTypes` → `UpdateView`,`shellctrls.pas:687`)。
- **刷新的代价说清楚:`UpdateView` 会重建根节点以下的所有节点。** 这是刷新的定义决定的(子目录集合本来就可能变了),
  所以它是一个**你主动调用**的方法,不是背地里发生的事;根节点句柄保持不变,折叠中的节点本来就没枚举过、无需刷新。
  **跨 `UpdateView` / `ShowHidden` 写入持有节点指针 = 悬垂指针**,重新走一次 `SelectPath` 拿新指针。
- **文件夹/驱动器图标用固定调色板**(内容图标),128px master 降采样。不从主题取色 —— 构造时主题可能还没解析。

## 消费者

它是 Phase 7 文件对话框(`TTyOpenDialog`/`TTySaveDialog`)左侧的目录树面板;`OnPathChange` 是"树选中 → 右侧
`TTyShellListView.LoadDirectory`"的接线点。见 `docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`。

## 与 `TTySelectPathForm` 的关系

`tyControls.Dialogs.SelectPath` 里的 `TySubdirectories` / `TyPathHasSubdir` 已委托到本控件同源的
`tyControls.FileSystem`(`TyFsReadDirectory` / `TyFsHasSubdir`),消除了两处目录枚举逻辑的漂移。
`TyDriveRoots` 保持独立 —— 该选择器的根集是**仅驱动器**(Unix 只有 `/`),与 `TyFsRoots` 的更丰富根集
(含主目录 + 挂载卷)语义不同,合并会改对话框的根列表。
