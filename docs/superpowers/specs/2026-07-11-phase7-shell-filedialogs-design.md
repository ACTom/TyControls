# Phase 7 — Shell / 文件系统 + 自绘文件对话框 · 设计

> 状态:**待批准**。批准后逐批转实施计划(`docs/superpowers/plans/…`)。
> 上游:`docs/superpowers/specs/2026-07-05-controls-expansion-roadmap.md` Phase 7。
> 前置:TTyListView(SP1+SP2a+SP2b)已完工 —— 它是文件列表的底座。

## 结论(设计 workflow,3 评委一致)

三条路线(基础层优先 / 对话框优先 / shell 视图优先)经跨平台稳健性、复用+可测性、能否交付对话框
三个维度评判,**基础层优先全票胜**(9/9/8),且"第一次合并 = 纯文件系统单元"三家一致。

**架构:一个纯文件系统单元打底,所有 shell 控件和对话框都是它的薄视图。**

## 硬约束(用户既定,贯穿全 phase)

- **只跨平台。非跨平台特性一律搁置。** 每个平台相关点必须有回退或明确搁置(见"搁置清单")。
- 不用原生 LCL 控件;全自绘。
- 视觉值主题 token 驱动;**优先复用**已有 typeKey。**本 phase 目标零新增主题 token。**
- 算法逻辑放**纯自由函数**;无头测试跑在临时目录上。

## 底座 —— `tyControls.FileSystem.pas`(第一批,纯、无 UI)

`uses SysUtils, LazFileUtils, FileUtil, Masks, LazUTF8`,**不 uses 任何 LCL 控件单元** —— 所以无头
测试能覆盖它的 100%。**它是唯一真理来源:任何 shell 视图里的 item index == 它持有的 `TTyFsEntryArray`
的下标。**

### 记录类型

```pascal
type
  TTyFsEntry = record
    Name, FullPath: string;
    IsDir, IsHidden: Boolean;
    Size: Int64;
    Modified: TDateTime;
    Attr: LongInt;
    TypeName: string;        { 启发式种类标签,非 OS 注册描述 }
  end;
  TTyFsEntryArray = array of TTyFsEntry;

  TTyFsObjectType  = (fotFolders, fotFiles, fotHidden);
  TTyFsObjectTypes = set of TTyFsObjectType;

  TTyFsSortKey = (fskName, fskSize, fskType, fskModified);

  TTyFsRootKind = (rkDrive, rkRoot, rkHome, rkVolume, rkPlace);
  TTyFsRoot     = record Path, Display: string; Kind: TTyFsRootKind; end;
  TTyFsRootArray = array of TTyFsRoot;

  TTyFsFilterSpec = record Caption, Patterns: string; end;
  TTyFsFilterSpecArray = array of TTyFsFilterSpec;
```

### 纯自由函数

```pascal
{ 核心枚举。FindFirstUTF8/FindNextUTF8 over AppendPathDelim(ADir)+'*',faAnyFile,
  跳过 '.'/'..';IsDir=(Attr and faDirectory),IsHidden=(Attr and faHidden){%H-};
  非 fotHidden 丢隐藏;非 fotFolders 丢目录;非 fotFiles 丢文件;AMask 只作用于文件(目录恒显)。
  这就是 OwnerData 的后备存储。 }
function TyFsReadDirectory(const ADir, AMask: string; AOptions: TTyFsObjectTypes): TTyFsEntryArray;

{ 掩码匹配。包 Masks.MatchesWindowsMaskList(带 DefaultWindowsQuirks,使 '*.*'/'foo.*' 按文件对话框
  惯例);'*.*'/'' 归一为 AllFilesMask '*';原生处理 ';' 列表。 }
function TyFsMatchesFilter(const AName, APatterns: string; ACaseSens: Boolean): Boolean;

{ 解析 LCL 过滤串 'Desc (*.ext)|*.ext;*.e2|All|*.*' 的管道格式 → (Caption, Patterns) 对。
  纯字符串拆分;仓库里唯一真正新增的解析器。 }
function TyFsParseFilter(const AFilter: string): TTyFsFilterSpecArray;

{ FilterIndex(1-based,LCL 惯例)→ 当前 pattern 串,越界钳位。 }
function TyFsFilterPatterns(const AFilter: string; AIndex: Integer): string;

{ 比较两个条目:目录优先,再按 Name(CompareFilenames,OS 大小写规则)/ Size:Int64 /
  Modified:TDateTime / TypeName;稳定。视图的 OnCompare 委托给它 —— 比的是**原始值**,不是显示串。 }
function TyFsCompareEntries(const A, B: TTyFsEntry; AKey: TTyFsSortKey;
  AAscending, AFoldersFirst: Boolean): Integer;

{ 就地排序,给 FileListBox / 树这类扁平场景用(ListView 走 FOrder+OnCompare,不改数组)。 }
procedure TyFsSortEntries(var AEntries: TTyFsEntryArray; AKey: TTyFsSortKey;
  AAscending, AFoldersFirst: Boolean);

{ 可移植"位置"列表。{$IFDEF MSWINDOWS} GetLogicalDriveStrings → 每个盘符一个 rkDrive;
  {$ELSE} '/'(rkRoot) + GetUserDir(rkHome) + 启发式扫 /media/$USER,/run/media/$USER,/mnt,/Volumes
  (rkVolume)。这是单元里**唯一**的 {$IFDEF MSWINDOWS}。绝不用 'Drive: Char' API。 }
function TyFsRoots: TTyFsRootArray;

{ 父目录、面包屑、Save 名解析。都走 LazFileUtils 的可移植调用。 }
function TyFsParent(const APath: string): string;
function TyFsBreadcrumb(const APath: string): TStringArray;
function TyFsResolveSaveName(const ADir, ATyped, ADefaultExt: string): string;
function TyFsTypeName(const AEntry: TTyFsEntry): string;
```

### 跨平台要点

- **每次文件系统触碰都走 LazFileUtils 的 `*UTF8` 包装**(`FindFirstUTF8`/`DirectoryExistsUTF8`/
  `RenameFileUTF8`/`CreateDirUTF8`/`ExpandFileNameUTF8`)—— 裸 `SysUtils.FindFirst` 在 Windows 上损坏非 ASCII 名。
- **隐藏是一个可移植谓词**:`(Attr and faHidden){%H-}` —— Windows 上是真的 `FILE_ATTRIBUTE_HIDDEN`,
  Unix 上由 FPC 的 `LinuxToWinAttr` 从"点开头"合成(`rtl/unix/sysutils.pp`)。**不手写 `Name[1]='.'` 分支。**
- 大小写规则走 `CompareFilenames`(OS 感知)。平台属性提示用 `{%H-}` 抑制,和 LCL 一样。
- 全部算法函数无 widget 依赖 → `tests/test.filesystem.pas` 在临时目录建一棵树(目录、文件、一个点开头/隐藏
  文件、混合大小+时间、一个 unicode 名),断言枚举/过滤/隐藏/排序/解析 —— **完全无头**。这正是本路线胜出的原因。
- **顺带修**:现有 `tyControls.Dialogs.SelectPath` 的 `TySubdirectories`/`TyDriveRoots` 是 folders-only、
  Win-drive-only 的窄助手,且评委发现它走了**非 UTF8** 路径(真实 bug)。第一批**不强制**重构它们,但 Merge 3 要把它们指向新单元消重。

### 第一批边界清单(测试必覆盖)

1. 空目录 / 不存在的目录 → 空数组,不崩。
2. `fotFolders` 单开 → 只有目录;`fotFiles` 单开 → 只有文件;都开 → 全部;`fotHidden` 关 → 丢隐藏。
3. 点开头文件在 `fotHidden` 关时被丢、开时保留(Unix 隐藏语义)。
4. 掩码 `*.txt;*.md` 只作用于文件,目录恒显;`*.*` 和 `''` 等价于全部。
5. `TyFsParseFilter` 解析多段管道格式;段数、Caption、Patterns 正确;畸形串不崩。
6. `TyFsCompareEntries`:目录永远排在文件前(与升降序无关);Size 按 Int64、Modified 按 TDateTime、
   Name 按 OS 大小写规则;升/降序只翻转"可比较值之间"(同 ListView 的 NULLS-LAST 教训)。
7. `TyFsResolveSaveName`:裸名对 ADir 展开;无扩展名时补 ADefaultExt;已有扩展名不动。
8. `TyFsRoots` 至少返回一个根(Windows ≥1 盘符,Unix 含 '/' 和 home);不崩。
9. UTF-8 文件名往返正确(建一个中文名文件,枚举回来名字一致)。

## 后续批次(框架;每批落地前补完整契约)

| # | 批次 | 内容 |
|---|---|---|
| 1 | **`tyControls.FileSystem`**(本 spec 已定) | 纯 FS 单元 + 无头测试。第一次合并。 |
| 2 | **`TTyShellListView`** | TTyListView 子类,OwnerData 适配器。override 五虚方法读 `FEntries`;`OnCompare` → `TyFsCompareEntries`(原始值);`CommitEdit` → `RenameFileUTF8`。列 Name/Size/Type/Modified。**立刻用真实消费者验证底座。** |
| 3 | **`TTyShellTreeView`** | TTyTreeView + `TyFsReadDirectory[fotFolders]` + `TyFsRoots`;把 SelectPath 的树接线泛化。**并把 `TySubdirectories`/`TyDriveRoots` 指向新单元消重。** |
| 4 | **`TTyFilterComboBox` + `TTyShellComboBox`** | TTyComboBox 子类,用 `TyFsParseFilter`/`TyFsBreadcrumb`/`TyFsRoots`。 |
| 5 | **`tyControls.Dialogs.FileDialog`** —— 交付物 | `TTyOpenDialog`/`TTySaveDialog`:TTyDialog 拼树+列表+过滤+文件名+工具栏(Up/新建文件夹);三层 API(builder / 全局函数 / 可流式组件),对齐 LCL `TOpenDialog`/`TSaveDialog`。Save 额外项:文件名框、覆盖确认(复用 `TyMessageDlg`)、默认扩展名。 |
| 6+ | SHOULD(独立) | `TTyDirectoryEdit`/`TTyFileEdit`/`TTySaveFileEdit`(克隆 TTyURLEdit 的 RightReserve 尾部钩子)、历史前进后退、文件名自动补全、跨平台 BGRA 缩略图预览窗格。 |

## 关键设计决策 —— shell 列表的排序

`TTyListView.FSortKind` 是**跨列共享的单标量**,且解析**显示串**(所以 Size 显示 "3.5 MB" 不会按数值排)。
所以 `TTyShellListView` **必须**:点表头设 `FSortColumn` 后,在 `DoCompare` 里把**列 → `TTyFsSortKey`**
映射好,委托 `TyFsCompareEntries` 比**原始值**。漏掉这个映射会静默排错。这是整个 phase 最容易踩的坑,单列一条。

## 搁置清单(非跨平台,明确不做)

- 原生 shell 图标(`SHGetFileInfo`/`NSWorkspace`/GIO)→ 回退到 `TTyVirtualImageList` 种类字形。
- `Drive: Char` + 驱动器类型(软驱/光驱/RAM 盘)的 `TTyDriveComboBox` → 无 Unix 对应;由可移植 `TyFsRoots`
  折进 `TTyShellComboBox` 取代。
- 特殊文件夹 / PIDL / shell 命名空间根(桌面、此电脑、回收站、网络、库)→ 只做文件系统路径 + places 根。
- 原生 `IContextMenu` 右键动词、`ShellExecute` 启动 → 文件对话框只返回路径;顶多以后加个自绘"新建文件夹/重命名"菜单,永久删除不做。
- `ShellChangeNotifier` / 实时文件监视(`FindFirstChangeNotification` 是 Win-only,FCL 无可移植监视器)→ 只做手动 Refresh。
- `IShellItemImageFactory` 缩略图 + 后台线程 → 跨平台 BGRA 缩略图/预览窗格作为 SHOULD 替代(Merge 6+)。
- 卷标 / 细粒度驱动器类型 / 剩余空间列 → Windows-first,首版不做。
- `TTyOpenSoundDialog` 带播放 → 无跨平台音频;声音过滤预设可搭普通 Open 对话框。
- 参考库皮肤属性(AlphaBlend / LVHeaderSkinDataName / UseShellImages)→ 已被 `.tycss` 引擎取代。

## 风险

| 风险 | 缓解 |
|---|---|
| 本路线把非视觉单元前置,可见收益(主题化对话框)要到 Merge 5 才到,底座可能过/欠拟合视图 | 顺序里 Merge 2(TTyShellListView)**立刻**用真实消费者压底座,签名不对会在树/combo/对话框叠上去之前暴露 |
| 排序接缝(单标量 `FSortKind` 解析显示串) | `DoCompare` 走 `OnCompare` → `TyFsCompareEntries` 比原始值;**列→SortKey 映射必须写对**(见上) |
| `TyFsRoots` 在 Unix 是启发式(扫固定挂载点),挂在别处的卷会漏 | Windows 盘符稳;剩余空间在 Unix 靠 fstab 不稳 → 剩余空间列 Windows-first 或首版省略 |
| `TyFsTypeName` 是扩展名启发式标签,字形是自绘,不如原生丰富 | 按跨平台规则接受;可见性略逊原生对话框 |
| 绘制/布局/交互(行渲染、F2 改名 UX、框选、对话框缩放、树↔列表↔combo 同步)无头测不了 | 只有 FS 算法真被测覆盖;其余延到真机(Win + Linux 各一台)眼验 |

## 验收(全 phase)

- 每批:全量测试 0 失败;**零新增主题 token**;`themes/*`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、
  `tests/golden/*` 零改动。
- 第一批:FS 单元纯函数无头全绿(临时目录);无 UI 可眼验。
- Merge 5 落地后:双击可跑的 `examples/filedialog`,Windows 和 Linux 各真机验一轮。
- 每批过 pre-merge 检查表([[pre-merge-checklist]]:i18n + README 中英)。
