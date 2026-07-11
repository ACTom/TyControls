# Phase 7 批次 3 —— `TTyShellTreeView` 实施计划

> 设计:`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`(已批准)
> 前置:批 1 `tyControls.FileSystem`(`099e001`)、批 2 `TTyShellListView`(`ffb9044`)已合并。
> **样板**:`source/tyControls.Dialogs.SelectPath.pas` 里的 `TTySelectPathForm` 已用 TTyTreeView
> 建过懒加载目录树 —— 本控件是把那套接线抽成可复用控件,数据源换成 `tyControls.FileSystem`。

## 交付物

| # | 产物 |
|---|---|
| 1 | `source/tyControls.ShellTreeView.pas` —— `TTyShellTreeView = class(TTyTreeView)` |
| 2 | `tests/test.shelltreeview.pas` —— 无头,临时目录;测状态机(根铺设/懒展开/路径映射/选中),不测绘制 |
| 3 | `tycontrols.lpk` `<Item>`;`tests/tytests.lpr` uses;`designtime/tyControls.Design.pas` 注册进 **TyControls Containers**;调色板图标(genicons + gen-icons.ps1 + test.paletteicons,上界 130→131)|
| 4 | `docs/controls/shelltreeview.md` + README 索引 |
| 5 | **消重**:`tyControls.Dialogs.SelectPath` 的 `TySubdirectories`/`TyDriveRoots`/`TyPathHasSubdir` 改为**委托** `tyControls.FileSystem`(见下,独立小步,靠 SelectPath 现有测试兜底)|

**零新增主题 token**:继承 `TTyTreeView` 的 `GetStyleTypeKey := 'TyTreeView'`,一切照旧。

## 契约

`TTyShellTreeView = class(TTyTreeView)` —— 目录树。只显示**文件夹**(never 文件)。懒加载:根节点先铺
`TyFsRoots`,子目录首次展开时才用 `TyFsReadDirectory(path, '*', [fotFolders])` 枚举。

### 节点 ↔ 路径

节点数据存一个 **Integer 索引**,指向控件持有的 `FPaths: array of string`(和 SelectPath 一样,节点数据是
定长块,存字符串索引最省事)。`NodeDataSize := SizeOf(Integer)`。`NodePath(node): string` 读回。
新增节点时把路径 append 进 `FPaths`,索引写进节点数据。

### 状态

```pascal
private
  FPaths:        array of string;   { 节点索引 -> 路径 }
  FShowHidden:   Boolean;           { 传给 TyFsReadDirectory 的 fotHidden 位 }
  FIcons:        TTyVirtualImageList;{ 文件夹/驱动器字形(固定调色板,同 ShellListView)}
  FSelectedPath: string;            { 当前焦点目录的缓存 }
  FOnPathChange: TNotifyEvent;
```

### 构造

- `NodeDataSize := SizeOf(Integer)`;接 `OnGetText`/`OnInitNode`/`OnExpanding`/`OnGetImageIndex`/`OnChange`
  到私有方法(照 SelectPath)。
- 建文件夹/驱动器字形图标表 → `Images`(TTyTreeView 用 `Images` 而非 Small/LargeImages)。固定调色板,理由同批 2。
- `PopulateRoots` 铺根(每个 `TyFsRoots` 一个根节点;`InitNode` 盖 has-children 箭头)。

### 接线(私有方法,照 SelectPath 的模式)

```pascal
procedure TreeGetText(Sender; Node; Column; TextType; var CellText);  { = ExtractFileName(NodePath) 或根的 Display }
procedure TreeInitNode(Sender; ParentNode, Node; var InitStates);      { 有子目录则 Include(ivsHasChildren) }
procedure TreeExpanding(Sender; Node; var Allowed);                    { ChildCount=0 时 PopulateChildren }
procedure TreeGetImageIndex(Sender; Node; Kind; Column; var Index);    { 文件夹/驱动器字形 }
procedure TreeChange(Sender; Node);                                    { 更新 FSelectedPath + 触发 OnPathChange }
```

- `PopulateChildren(node)`:`TyFsReadDirectory(NodePath(node), '*', [fotFolders] + hidden)` → 每个子目录
  `AddChild` + `InitNode`。has-children 箭头由 `OnInitNode` 按"该子目录还有没有下级目录"盖。
- **懒加载不碰盘直到展开**:`OnInitNode` 判 has-children 用一个轻量 `TyFsHasSubdir(path)`(见消重),
  只查有没有一个子目录,不枚举全部。

### 公开 API

```pascal
public
  procedure PopulateRoots;                     { 清空重铺根 }
  function  SelectedPath: string;              { = FSelectedPath }
  procedure SelectPath(const APath: string);   { 展开并聚焦到某路径(逐级 PopulateChildren + FocusedNode)}
published
  property Directory: string read SelectedPath write SelectPath;
  property ShowHidden: Boolean read FShowHidden write SetShowHidden default False;
  property OnPathChange: TNotifyEvent read FOnPathChange write FOnPathChange;  { 焦点目录变化 }
```

`SelectPath(path)`:把 path 拆成祖先链(可用 `TyFsBreadcrumb`),从根逐级找/展开/聚焦到目标节点。
找不到静默返回。这是对话框"在路径框敲目录 → 树里定位"要用的。

`OnPathChange` 是对话框把**树选中 → 列表 `LoadDirectory`** 的接线点。

## 消重(交付物 5,独立小步)

`tyControls.Dialogs.SelectPath` 现有三个私有/单元级助手 `TySubdirectories`/`TyDriveRoots`/`TyPathHasSubdir`,
和 `tyControls.FileSystem` 的 `TyFsReadDirectory[fotFolders]`/`TyFsRoots` 是重复逻辑。改为**委托**:

- `TySubdirectories(p)` → 用 `TyFsReadDirectory(p,'*',[fotFolders])` 取名,返回 `TStringArray`(保持签名)。
- `TyDriveRoots` → 用 `TyFsRoots` 的 Path,返回 `TStringArray`(保持签名)。
- `TyPathHasSubdir(p)` → 新增 `tyControls.FileSystem.TyFsHasSubdir(p): Boolean`(找到第一个子目录即 True,
  不枚举全部,快),SelectPath 委托它。

**保持 SelectPath 的公开签名不变**,`TTySelectPathForm` 的现有测试是兜底 —— 它们必须原样通过,证明委托等价。
`TyFsHasSubdir` 加进 FileSystem 单元(**这会动批 1 已合并的单元**,但只是新增一个函数 + 一个测试,不改现有函数)。

## 无头测试要点

- 临时目录建可控树(进程唯一名,吸取批 2 教训):嵌套目录 `a/`、`a/b/`、`a/c/`、`d/`,几个文件(应被过滤掉)。
- 测:
  - `PopulateRoots` 后有根节点;根含预期的盘符/根类型。
  - `SelectPath(临时根)` 后 `SelectedPath` = 该路径;`Directory` 读回一致。
  - 展开一个目录后,子节点**只有目录、没有文件**(用 `TTyShellTreeViewAccess` 暴露节点遍历 + `NodePath`)。
  - `TyFsHasSubdir`:有子目录的目录返回 True,叶子目录返回 False,不存在的返回 False。
  - `ShowHidden` 切换隐藏目录。
  - `OnPathChange` 在焦点目录变化时触发,`SelectedPath` 是新路径。
- 不测绘制;懒展开的"首次展开才枚举"可通过"展开前子节点数=0、展开后>0"间接验。
- **SelectPath 消重的验证 = SelectPath 现有测试原样通过**(委托等价)。

## 验收

- 全量测试 0 失败(基线 2783 + 新增)。
- `themes/*`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、`tyControls.TreeView.pas`、
  `tyControls.ListView*.pas`、`tyControls.ShellListView.pas` **零改动**。
- `tyControls.FileSystem.pas` 只**新增** `TyFsHasSubdir`(+ 其测试),现有函数零改动 —— golden 无关(非主题)。
- `tyControls.Dialogs.SelectPath.pas` 只把三个助手改为委托,公开签名不变,其现有测试原样通过。
- 调色板漂移守卫通过。
