# tyControls.FileSystem

> **非可视工具单元** —— 不是控件,不进组件面板,无图标/注册。Phase 7 的算法底座。

## 概述

`tyControls.FileSystem` 是一个**纯**单元:目录枚举、掩码过滤、原始值排序、可移植根、LCL 过滤串解析。
`uses SysUtils, LazFileUtils, FileUtil, Masks, LazUTF8`,**不依赖任何 LCL 控件**,所以 100% 无头可测(测试跑在临时目录上)。

它是 Phase 7 所有 shell 控件和文件对话框的**唯一真理源**:任何 shell 视图里的 item index == 它持有的
`TTyFsEntryArray` 的下标。

## 跨平台

- 每次文件系统触碰都走 `*UTF8` 包装(`FindFirstUTF8`/`DirectoryExistsUTF8`/`ExpandFileNameUTF8` …)——
  裸 `SysUtils.FindFirst` 在 Windows 损坏非 ASCII 名。
- 隐藏是一个可移植谓词 `(sr.Attr and faHidden)` —— Windows 上是真的 `FILE_ATTRIBUTE_HIDDEN`,
  Unix 上由 FPC 从"点开头"合成。不手写 `Name[1]='.'` 分支。
- 唯一的平台行为分支在 `TyFsRoots`(Windows 盘符 vs Unix `/`+home+挂载点);绝不用 `Drive: Char` API。

## 类型

```pascal
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
TTyFsSortKey     = (fskName, fskSize, fskType, fskModified);
TTyFsRootKind    = (rkDrive, rkRoot, rkHome, rkVolume, rkPlace);
TTyFsPlaceIcon   = (fpiByKind, fpiFolder, fpiDrive, fpiHome, fpiDesktop, fpiDocuments,
                    fpiDownloads, fpiPictures, fpiMusic, fpiVideos);          // 4.0
TTyFsRoot        = record Path, Display: string; Kind: TTyFsRootKind; Icon: TTyFsPlaceIcon; end;
TTyFsRootArray   = array of TTyFsRoot;
TTyFsFilterSpec  = record Caption, Patterns: string; end;
TTyFsFilterSpecArray = array of TTyFsFilterSpec;
```

## 函数

| 函数 | 说明 |
|---|---|
| `TyFsReadDirectory(dir, mask, options)` | 核心枚举。`fotFolders`/`fotFiles`/`fotHidden` 控制包含谁;`mask` 只作用于文件(目录恒显),大小写不敏感。不存在/不可读的目录返回空数组,不抛。 |
| `TyFsMatchesFilter(name, patterns, caseSens)` | 掩码匹配(包 `MatchesWindowsMaskList`);`'*.*'`/`''` 等价全部;`';'` 列表。 |
| `TyFsParseFilter(filter)` | 解析 LCL `'Desc (*.ext)|*.ext;*.e2|All|*.*'` 管道格式 → `(Caption, Patterns)` 数组。畸形串不崩。 |
| `TyFsFilterPatterns(filter, index)` | 1-based `FilterIndex` → 当前 pattern 串;越界钳到首/末段。 |
| `TyFsCompareEntries(a, b, key, asc, foldersFirst)` | 比较两条目:目录永远排文件前(与升降序无关);再按 `key` 比**原始值**(Name 走 OS 大小写、Size:Int64、Modified:TDateTime、TypeName)。视图的 `OnCompare` 委托给它。 |
| `TyFsSortEntries(var entries, key, asc, foldersFirst)` | 就地稳定排序。 |
| `TyFsRoots` | 可移植"位置"列表(Windows 盘符 / Unix `/`+home+挂载点)。至少一个根,不崩。盘符的 `Path` 是 `C:\`,`Display` 是 `C:`。 |
| `TyFsRootName(root)` | 根的**显示名**:去掉末尾分隔符的根,`C:\` → `C:`;只剩一个分隔符的根就是它自己(`/`)。只是名字——C 盘的路径仍然是 `C:\`,把 `C:` 当路径用指的是那个盘上的当前目录。`TyFsRoots` 里盘符的 `Display`、目录树、路径下拉、选择文件夹对话框显示一个盘都按它(#250,3.0.5;之前实际显示成 `C:\`,和文档写的不一样)。 |
| `TyFsKnownFolders` | 用户的**常用文件夹**:桌面、文档、下载、图片、音乐、视频,固定按这个顺序,只列存在的、每个只列一次。`Kind = rkPlace`,`Display` 是库自己的翻译名(`rsFdPlace*`),和磁盘上叫什么无关。可能为空,不抛异常。3.0.5 新增。 |
| `TyFsPlaces` | `TyFsKnownFolders` 加 `TyFsRoots`:3.x 目录树顶层列的位置。4.0 文件对话框的位置表见 `tyControls.ShellPlaces`([文件对话框](filedialog.md)的「位置」)。 |
| `TyFsPlaceIconOf(place)` | 一个位置用哪个图标(`TTyFsPlaceIcon`):`TTyFsRoot.Icon` 给了就用它(常用文件夹各有各的),没给(`fpiByKind`,零值)就按 `Kind`:主目录是房子,`rkPlace` 是文件夹,其余是磁盘。4.0 新增。 |
| `TyRecentFolders: TStrings` | 文件对话框**最近去过的文件夹**,最新的在前:整个程序一张表,只在内存里。想跨启动保留,由程序自己读写(`LoadFromFile` / `SaveToFile` / `Text`)。4.0 新增。 |
| `TyNoteRecentFolder(folder)` | 把一个文件夹放到 `TyRecentFolders` 的最前面(已经在表里就挪上来),超出 `TyRecentFoldersLimit` 的从末尾丢掉。对话框确定时调它;程序自己打开了文件也可以调。 |
| `TyRecentFoldersLimit` | 变量,默认 5:这张表保留几个。0 = 不保留。 |
| `TyFsParseUserDirs(text, home)` | 纯函数:解析 XDG 的 `user-dirs.dirs`(`XDG_DESKTOP_DIR="$HOME/桌面"` 这种行)。只认六个键、带引号的 `"$HOME/…"` 或绝对路径;指回主目录本身(`"$HOME/"`)表示这个文件夹被关掉,不列。路径一律用 `/` 拼,不查磁盘。 |
| `TyFsExistingPlaces(candidates)` | 从候选里去掉不存在的文件夹和重复的,顺序不变,去掉末尾分隔符。 |
| `TyFsParent(path)` | 父目录;根处稳定。 |
| `TyFsBreadcrumb(path)` | **累积可导航路径,根在前**:`/home/tom` → `['/','/home','/home/tom']`;`C:\Users\Tom` → `['C:\','C:\Users','C:\Users\Tom']`。盘符根保留尾分隔符,其余不带。保留输入路径自身的分隔符(主机无关)。 |
| `TyFsResolveSaveName(dir, typed, defaultExt)` | Save 名解析:裸名对 `dir` 展开;无扩展名补 `defaultExt`;已有扩展名不动。 |
| `TyFsTypeName(entry)` | 启发式种类标签(`'Folder'` / `'PNG File'` / `'File'`)。三个词是资源串(`rsFdTypeFolder` / `rsFdTypeFileOf` / `rsFdTypeFile`),应用加载了库的翻译就是译文(#249,3.0.5),所以别拿返回值和英文字面量比较,判断目录用 `entry.IsDir`。 |

## 设计取舍 / 搁置

- `TypeName` 是扩展名启发式标签,不是 OS 注册的文件类型描述(那是 Win-only)。
- 原生 shell 图标、PIDL 特殊文件夹、剩余空间、实时文件监视 —— 均非跨平台,搁置(见 Phase 7 设计稿的搁置清单)。
- `TyFsRoots` 在 Unix 是启发式扫固定挂载点(`/media/$USER`,`/run/media/$USER`,`/mnt`,`/Volumes`),挂别处的卷会漏;Windows 盘符稳。
- **常用文件夹在各平台的取法**(`TyFsKnownFolders`):
  - Windows:问系统的特殊文件夹,所以被挪到别的盘或 OneDrive 里的「文档」也能在它实际的位置找到。「下载」没有旧式编号,用 Vista 起才有的已知文件夹接口(运行时查找,没有这个接口的系统上退回用户目录下的 `Downloads`)。
  - Linux / BSD:读 `$XDG_CONFIG_HOME/user-dirs.dirs`(默认 `~/.config/`),那里的文件夹名是本地化的;没有这个文件就用主目录下的常见英文名。
  - macOS:主目录下固定的 `Desktop`、`Documents`、`Downloads`、`Pictures`、`Music`、`Movies`(访达里显示的本地化名字只是显示名)。

## 消费者

`TTyShellListView`(over TTyListView)、`TTyShellTreeView`(over TTyTreeView)、过滤/路径 combo、
以及 `TTyOpenDialog`/`TTySaveDialog` 都是这个单元的薄视图。见[文件对话框](filedialog.md)。
