# 参与贡献

> English: [CONTRIBUTING.en.md](CONTRIBUTING.en.md)

欢迎报告问题、提建议、提交代码。issue 统一提在 [GitHub](https://github.com/ACTom/TyControls/issues),中英文都可以。Gitee 只是镜像。

## 报告 bug

先看一眼[已知问题](docs/known-issues.md),那里可能已经写了原因和绕开的办法。

提 issue 时请写上:

- TyControls、Lazarus、FPC 的版本
- 操作系统和 widgetset(win32 / gtk2 / gtk3 / qt5 / qt6 / cocoa);Linux 请注明是 X11 还是 Wayland
- 显示缩放比例(100%、150%……)和所用主题
- 怎么复现:最好是在 `examples/` 里某个示例上改几行就能看到;做不到的话,附一个能编译的最小工程
- 看到的和期望的;界面问题附截图

## 功能建议

先看[路线图](https://github.com/ACTom/TyControls/milestones),也许已经在计划里。

说清楚你要用它做什么,比直接给出方案更有用:同一个需求往往有更合适的做法。

TyControls 是跨平台、多主题的通用控件库,内置皮肤用来验证主题系统,不打算完整复刻某一套设计系统。以下功能明确不做:

- 停靠(docking)布局。IDE 类界面请用侧栏工作台。
- 多窗口(把面板拖出成独立窗口)。

## 路线图与发版

每个版本对应一个 Milestone,描述里写这一版主要解决什么;每个大功能有一个跟踪 issue,可以订阅、在下面讨论。

版本只排先后,不定日期。Milestone 做完也不一定马上发版:修复版通常会再等一段时间,确认没有新的问题反馈再发。

## 版本与维护

版本号是 `主版本.次版本.修订号`。修订版只修 bug;次版本加新功能,但保持兼容,见下文。

**维护周期**:最新发布的次版本持续修复和发版。上一个次版本也继续收到修复和发版,直到再下一个次版本发布时,发最后一版后停止维护:比如 3.2 发布时发最后一个 3.0.x。严重问题不受此限。

**兼容承诺**:同一主版本内(比如整个 3.x),次版本保证:

- 公开 API 不删、不改签名;要淘汰的先标 `deprecated`,到下一个主版本才删。
- 窗体文件(`.lfm`)里的属性不删、不改名,默认值也不变。
- 老的 `.tycss` 照样能用:token 名和语法只增不删。
- 不提高最低要求:Lazarus 3.0、FPC 3.2.2。
- 控件的默认尺寸、内距和 `AutoSize` 的结果不变,升级不会让界面错位;内置主题的颜色可能微调。

修 bug 不算破坏兼容,哪怕有代码依赖了原来的错误行为。

所以遇到问题,升级到最新的次版本就能拿到修复。

## 提交代码

改动较大的话,先开 issue 或在已有的 issue 下说一声,免得做完发现方向不合。

**分支**:修已发布版本的 bug,基于还有这个 bug 的最新发布版本的维护分支 `主版本.次版本-fixes`(比如 3.0.x 的 bug 基于 `3.0-fixes`);维护者会把修复 cherry-pick 到其他维护分支和 `main`,维护分支不与其他分支互相 merge。新功能和其他改动基于 `main`,较大的功能在特性分支上做完再 merge 回 `main`。

**编译和测试**:

```
lazbuild tests/tytests.lpi
tests/tytests --all --format=plain
```

修 bug 请附一个修复前会失败的测试。

**几条硬规矩**:

- 颜色、尺寸、圆角等视觉值走主题 token,不写死在代码里。
- 自绘界面里不用原生 LCL 控件(`TEdit`、`TButton` 等)。
- 新单元要加进 `tycontrols.lpk`(设计期的加进 `tycontrols_dt.lpk`)。
- 用户可见的文字用 `resourcestring`,并同步更新 `languages/` 下的 zh_CN `.po`。
- 新示例用 `.lfm` 窗体,带标题栏,能在运行时换主题。
- 不用比 Lazarus 3.0 更新的 LCL API;必须用时,按 `LCL_FULLVERSION` 给旧版本留一条路。
- 其余照周围代码的写法来。

**提交信息**用英文,格式 `类型(范围): 说明`,例如 `fix(grid): header loses focus after sort`。修复某个 issue 的,正文里写 `Fixes #N`。

## 更新日志

每个版本的变化记在 [CHANGELOG.md](CHANGELOG.md)。只记用户能感受到的变化,每条都链接对应的 issue;文档、重构、测试这类改动不记。PR 里不用改 CHANGELOG,发版时统一整理。
