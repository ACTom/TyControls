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
TTyFsRoot        = record Path, Display: string; Kind: TTyFsRootKind; end;
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
| `TyFsRoots` | 可移植"位置"列表(Windows 盘符 / Unix `/`+home+挂载点)。至少一个根,不崩。 |
| `TyFsParent(path)` | 父目录;根处稳定。 |
| `TyFsBreadcrumb(path)` | **累积可导航路径,根在前**:`/home/tom` → `['/','/home','/home/tom']`;`C:\Users\Tom` → `['C:\','C:\Users','C:\Users\Tom']`。盘符根保留尾分隔符,其余不带。保留输入路径自身的分隔符(主机无关)。 |
| `TyFsResolveSaveName(dir, typed, defaultExt)` | Save 名解析:裸名对 `dir` 展开;无扩展名补 `defaultExt`;已有扩展名不动。 |
| `TyFsTypeName(entry)` | 启发式种类标签(`'Folder'` / `'PNG File'` / `'File'`)。 |

## 设计取舍 / 搁置

- `TypeName` 是扩展名启发式标签,不是 OS 注册的文件类型描述(那是 Win-only)。
- 原生 shell 图标、PIDL 特殊文件夹、剩余空间、实时文件监视 —— 均非跨平台,搁置(见 Phase 7 设计稿的搁置清单)。
- `TyFsRoots` 在 Unix 是启发式扫固定挂载点(`/media/$USER`,`/run/media/$USER`,`/mnt`,`/Volumes`),挂别处的卷会漏;Windows 盘符稳。

## 消费者

`TTyShellListView`(over TTyListView)、`TTyShellTreeView`(over TTyTreeView)、过滤/路径 combo、
以及 `TTyOpenDialog`/`TTySaveDialog` 都是这个单元的薄视图。见
`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`。
