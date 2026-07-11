# Phase 7 批次 1 —— `tyControls.FileSystem` 实施计划

> 设计:`docs/superpowers/specs/2026-07-11-phase7-shell-filedialogs-design.md`(已批准)
> 这是纯单元,无 UI,无新主题 token。第一次合并。

## 交付物

| # | 产物 |
|---|---|
| 1 | `source/tyControls.FileSystem.pas` —— 记录类型 + 九个纯自由函数(spec 已定签名) |
| 2 | `tests/test.filesystem.pas` —— 无头,跑在临时目录上;覆盖 spec 的 9 条边界清单 |
| 3 | `tycontrols.lpk` `<Item>`;`tests/tytests.lpr` uses |
| 4 | `docs/controls/filesystem.md` —— 单元文档(这是**非可视工具单元**,不进调色板,无需图标/注册) |

**不做:** 调色板图标(不是控件)、Design.pas 注册(不是组件)、示例(下一批 TTyShellListView 才有可看的)。

## 执行结构

同 ListView 各批:**两个 agent 互不相见地写**(一个实现、一个只按 spec 契约写测试,禁止读实现),第三个
交叉核对"实现与测试哪里不一致、哪里碰巧一致但契约没规定"。跑完由我裁决冲突、**每个修复做变异测试**、再提交。

## 契约要点(实现者遵循 spec,重点重申)

- `uses SysUtils, LazFileUtils, FileUtil, Masks, LazUTF8` —— **不 uses 任何 LCL 控件单元**。
- 每次文件系统触碰走 `*UTF8` 包装(`FindFirstUTF8`/`FindNextUTF8`/`FindCloseUTF8`/`DirectoryExistsUTF8`/
  `ExpandFileNameUTF8`)。裸 `SysUtils.FindFirst` 在 Windows 损坏非 ASCII。
- 隐藏 = `(Attr and faHidden){%H-}`,一个谓词,不手写 `Name[1]='.'`。
- 掩码走 `Masks.MatchesWindowsMaskList`(DefaultWindowsQuirks);`'*.*'`/`''` 归一为 `'*'`。
- 比较走 `CompareFilenames`(OS 大小写);目录永远排文件前,与升降序无关;升降序只翻转两个可比较值之间。
- 唯一的 `{$IFDEF MSWINDOWS}` 在 `TyFsRoots`。绝不用 `Drive: Char` API。
- FPC 坑:函数不能返回匿名 `array of T`(用具名 `TTyFsEntryArray`/`TTyFsRootArray`/`TTyFsFilterSpecArray`/
  `TStringArray`);托管类型 `Result` 先 `nil`;`{%H-}` 抑制平台属性提示。

## 测试要点

- 在**临时目录**(scratchpad 或 `GetTempDir`)建一棵可控树:2 个子目录、几个不同扩展名+大小+时间的文件、
  一个点开头/隐藏文件、一个 unicode(中文)名文件。`SetUp` 建、`TearDown` 删干净。
- 逐条钉 spec 的 9 条边界清单,过程名按**规则**命名。
- **不依赖真实系统目录的具体内容** —— `TyFsRoots` 只断言"至少一个根、不崩、含预期种类",不断言具体盘符/挂载点。
- unicode 往返:建一个中文名文件,`TyFsReadDirectory` 回来的 `Name` 与写入的一致(证明 `*UTF8` 生效)。

## 验收

- 全量测试 0 失败(基线 2714 + 新增)。
- `themes/*`、`DefaultTheme.pas`、`BuiltinThemeData.pas`、`tests/golden/*`、`tyControls.TreeView.pas`、
  `tyControls.ListView*.pas` **零改动**(这批只加新单元)。
- 单元在 Windows 编译通过;跨平台正确性靠 `{$IFDEF}` 审查 + Unix 分支的 code review(无 Linux 机器)。
