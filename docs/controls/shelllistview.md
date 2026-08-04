# TTyShellListView

## 概述

`TTyShellListView` 是一个**文件系统后备**的 `TTyListView` —— 显示某个目录的内容(文件夹 + 文件),
四列(名称 / 大小 / 类型 / 修改时间),可切五种视图、点表头排序、多选框选、F2 重命名、按类型分组折叠。

它是**纯适配器**:`TTyListView` 的 OwnerData 模式,唯一后备存储是 `tyControls.FileSystem` 的
`TTyFsEntryArray`(item index == 数组下标)。只 override 五个取值方法 + `CommitEdit`(重命名)+
`CompareItems`(原始值排序)+ `DoItemActivate`(文件夹进入 / 文件激活),其余(绘制/滚动/命中/多选/首字母/表头排序/F2 编辑器/列/分组)全部**继承不动**。
主题也一并继承:它不 override `GetStyleTypeKey`,因此解析的是 `TTyListView` 自己的那套键
(`TyListView` 外框 + `TyListViewItem` / `TyListViewHeader` / `TyListViewHeaderSection` /
`TyListViewGroupHeader` / `TyListViewCheckBox` / `TyListViewLine` / `TyListViewMarquee`,
逐项说明见 [listview.md](listview.md))。**这个"借用"是刻意的**:适配器只换数据源,一个像素都不自己画,
凭空多一个键只会多出一份必须与 `TyListView` 手工同步的规则。给文件列表换皮肤 = 改 `TyListView*` 规则;
`StyleClass` 只作用于**外框**(各部件是按空类名解析的),想单独区分文件面板与普通列表,只能靠 `StyleClass`
改外框,或给本控件加一个自己的键 —— 后者目前没有。

## 用法

```pascal
uses tyControls.ShellListView;

Shell := TTyShellListView.Create(Self);
Shell.Parent := Panel1;
Shell.LoadDirectory('C:\Users\Tom');     // 或 Shell.Directory := ...
Shell.OnFileActivate := @FileChosen;     // 双击文件 / Enter;双击文件夹自动进入
```

## 属性 / 方法

| 成员 | 说明 |
|---|---|
| `Directory: string` | 设置即读盘。写它 = `LoadDirectory`。 |
| `Root: string` | **public(非 published)**,与 `Directory` 同一份存储 —— LCL 给"被列出的目录"起的名字(`shellctrls.pas:300`),让 `List.Root := Dir` 这样的移植代码能编译。不 published:同一份状态挂两个 published 名字会在每个 `.lfm` 里把同一个路径写两遍,对象查看器里也会出现两行互相覆盖。 |
| `Mask: string` | 文件过滤(`';'` 分隔,如 `'*.txt;*.md'`);目录恒显;改后自动重读。默认 `'*'`。 |
| `MaskCaseSensitivity` | `Mask` 的大小写规则:`mcsPlatformDefault` / `mcsCaseInsensitive` / `mcsCaseSensitive`。**默认 `mcsCaseInsensitive`,与 LCL 的 `mcsPlatformDefault` 不同**(见下节)。 |
| `ObjectTypes: TTyFsObjectTypes` | 枚举哪几类条目。默认 `[fotFolders, fotFiles]`(**与 LCL 的 `[otNonFolders]` 不同**,见下节);以前是构造函数里写死的私有字段,"只文件"或"只文件夹"面板根本配不出来。 |
| `ShowHidden: Boolean` | 是否枚举隐藏项 —— 就是 `ObjectTypes` 里 `fotHidden` 那一位的另一个名字,两边**双向同步**。默认 `False`。 |
| `FoldersFirst: Boolean` | 文件夹是否在两个方向都排在文件前。默认 `True`。 |
| `GroupByKind: Boolean` | 按**类型**(即类型列的值)分成可折叠的组;文件夹一组、各文件类型一组。默认 `False`。 |
| `AutoSizeColumns: Boolean` | 每次 `Resize` 按**列被写死时的比例**重新分配客户区宽度,末列吃掉除法余数。默认 `True`(同 LCL)。关掉则一个像素都不动。以前四列恒为 220/90/120/140:窗口一宽右边就是一片死区,一窄就把"修改时间"切掉。 |
| `UseBuiltInIcons: Boolean` | 是否用控件自带的种类图标。默认 `True`。关掉会**同时**卸下内置 `SmallImages`/`LargeImages` **并**让 `GetItemImageIndex` 返回 `-1` —— 只卸列表不够,行仍会给图标留槽。 |
| `OnFileActivate` | 双击文件 / Enter 触发(双击文件夹改为进入)。 |
| `OnAddItem` | **逐条否决**:每枚举出一条就触发一次 `(Sender, ABasePath, AEntry, var ACanAdd)`,置 `ACanAdd := False` 丢掉这一条。此前的过滤只有 `Mask`(仅文件、仅按名)/ `ShowHidden` / `ObjectTypes`,而 `Entries` 是只读的唯一存储 —— 按大小、日期、属性或应用黑名单过滤**完全没有接缝**。 |
| `ShellTreeView` | 设计期可赋值的**伴随目录树**:在列表里进入某个文件夹,树跟着走。类型是抽象接缝 `TTyShellTreeLink` 而不是 `TTyShellTreeView`,原因见下节。 |
| `LoadDirectory(path)` / `UpdateView` | 读盘 / 重读当前目录。**破坏性改名:** `UpdateView` 原名 `Refresh`(用 `reintroduce` 遮蔽 `TControl.Refresh`)。`Refresh` 在 LCL 和本库其它每一个控件上都是"立刻重绘"(`Invalidate` + `Update`),于是这里成了唯一一个例行重绘调用会去读盘的控件,而真想重绘的调用者反倒没处说。`UpdateView` 是 LCL 自己给"重新枚举"起的名字,`Refresh` 从此与别处同义。 |
| `SelectedFile: string` | 焦点项的 FullPath,无则 `''`。 |
| `FileAt(i): string` | item index → FullPath,越界 `''`。 |
| `Entries: TTyFsEntryArray` | 只读后备数组,给对话框拿选中集。 |

## `UpdateView` 按**路径**恢复选中,不按行号

以前重读之后选中集是钉在**行索引**上的(`ItemsChanged` 只负责把选中数组改长度)。于是在选中行**上方**新增
或删除一个文件,高亮就悄悄挪到了另一个文件上 —— 文件对话框据此返回一个用户从来没点过的名字。

现在 `UpdateView` 先把选中集与焦点记成 **FullPath**,重读后按路径重新落位;焦点文件如果已经不在了,
就是**没有焦点**(`ItemIndex := -1`),而不是滑到某个幸存者身上。LCL 做同一件事(存 `Selected.Caption`、
用 `FindCaption` 找回,`shellctrls.pas:1996-1999`),按路径比按标题多覆盖一种情况:重命名。

> `CommitEdit`(F2 重命名)也走 `UpdateView`。它一度还写着 `Refresh` —— 而 `Refresh` 改回"重绘"之后,
> 这行就悄悄变成了空操作:文件在磁盘上改名了,行里还显示旧名字。原来的重命名测试看不见,因为它自己
> 又调了一次重读。

## 两处**故意**与 LCL 不同的默认值

| 属性 | LCL 默认 | 本控件默认 | 为什么 |
|---|---|---|---|
| `ObjectTypes` | `[otNonFolders]`(只文件) | `[fotFolders, fotFiles]` | 本控件一直是文件夹 + 文件都显示;跟 LCL 对齐会让每个现有宿主的文件夹凭空消失。缺的是**能配**,不是换默认。 |
| `MaskCaseSensitivity` | `mcsPlatformDefault`(Linux 上区分大小写) | `mcsCaseInsensitive` | 本库一直是全平台不区分大小写(`tyControls.FileSystem` 里写明的文件对话框惯例);跟 LCL 对齐会悄悄改掉每一台 Unix 宿主的过滤结果。缺的同样是**能配**。 |

## 关键设计

- **排序比原始值,不比显示串。** `TTyListView.FSortKind` 是跨列共享的单标量、还解析显示串,所以
  大小列显示 "10 KB" 会按字典序排到 "9 KB" 前面(`'1'<'9'`)。本控件覆写 `CompareItems` → `TyFsCompareEntries`
  比原始 `Size:Int64` / `Modified:TDateTime`,内部的 `ShellCompare` 按列映射 `TTyFsSortKey`。这是整个文件视图最容易踩的坑。
- **published 事件槽位归应用,不归控件。** 排序与激活现在是**覆写基类虚方法**(`CompareItems` / `DoItemActivate`),
  不再是接到 published `OnCompare` / `OnItemActivate` 上的 handler。以前控件占着那两个槽位,应用一赋值就把 shell 行为
  静默顶掉了 —— 列表不再文件夹优先,或者双击不再进目录,而且没有任何迹象表明是两处在抢同一个槽。现在:
  - `OnItemActivate` **会**触发(`DoItemActivate` 里先跑 shell 逻辑、再 `inherited`),应用照常能拿到原始激活通知;
  - `OnCompare` 的槽位是空着的,但本控件的 `CompareItems` **不调 `inherited`** —— 顺序是这个控件的身份的一部分,
    要改排序请派生并覆写 `CompareItems`。
- **排序方向不再需要预取反。** 基类只对**用户 handler** 的结果按 `sdDescending` 取反(它假设用户 handler 与方向无关);
  `TyFsCompareEntries` 自己已经吃进了方向,所以走 `OnCompare` 的年代要在这里预取反一次去抵消基类那一次。现在是覆写路径,
  没有基类的取反可抵消,预取反也一并去掉了 —— 留着会把降序双重翻转(文件夹掉到底部、文件反成升序)。
- **大小列的单位是可翻译资源串。** `'B'` / `'KB'` / `'MB'` / `'GB'` / `'TB'` 取自 `tyControls.StrConsts` 的
  `rsTyFileSize*`,不再是写死的英文 —— 否则一堆已翻译的列头中间夹着一个英文单位。格式化函数
  `TyFormatFileSize(ABytes: Int64): string` 是纯函数并**已导出**:够不着它的测试也就证不出资源串是真在用、而不只是声明了。
- **`GetItemCount` 从不碰盘** —— 它每帧每次滚动排序都被调,读 `Length(FEntries)`。读盘只在 `LoadDirectory`。
- **F2 重命名是真的重命名磁盘文件**(`RenameFileUTF8`);空名 / 同名 / 带路径分隔符的名静默放弃;
  目标已存在时重命名失败(不覆盖),视图不刷新。
- **种类图标用固定调色板**(内容图标,可用 `SmallImages`/`LargeImages` 覆盖,或 `UseBuiltInIcons := False` 全关),
  master 128px 降采样。不从主题取色 —— 构造时主题可能还没解析。
- **`TTyShellTreeLink` 为什么声明在这个单元里。** Pascal 的 interface 段不能互相 `uses`,而 LCL 是把两个类
  塞进同一个单元 + 前向声明绕过去的。`tyControls.ShellTreeView` 已经 `uses` 本单元(它的 `ShellListView`
  属性需要具体类型),所以接缝只能朝这个方向走:本单元声明抽象的 `TTyShellTreeLink = class(TTyTreeView)`,
  `TTyShellTreeView` 是它**唯一**的后代。接缝方法是 `protected` 的 —— 同单元的 `TTyShellListView` 够得着,
  应用代码则不会把它误当成树的公开 API(那是 `Directory` / `SelectPath` / `UpdateView`)。
- **双向链接靠计数器防递归。** 树选中会推给列表、列表读盘又会推回树。两侧各有一个 `FLinkLock`,推的时候
  加锁,所以级联走一步就停。LCL 用 `FLockUpdate` 守同一处(`shellctrls.pas:2003-2011`)。

## 消费者

它是 Phase 7 文件对话框(`TTyOpenDialog`/`TTySaveDialog`)的文件面板。见
`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`。
