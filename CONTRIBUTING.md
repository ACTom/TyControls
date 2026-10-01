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

## 路线图

每个版本对应一个 Milestone,描述里写这一版主要解决什么;每个大功能有一个跟踪 issue,可以订阅、在下面讨论。版本只排先后,不定日期,做完就发。

## 提交代码

改动较大的话,先开 issue 或在已有的 issue 下说一声,免得做完发现方向不合。

**分支**:修已发布版本的 bug,基于这个版本的维护分支 `主版本.次版本-fixes`(比如 3.0.x 的 bug 基于 `3.0-fixes`);新功能和其他改动基于 `main`。

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
- 其余照周围代码的写法来。

**提交信息**用英文,格式 `类型(范围): 说明`,例如 `fix(grid): header loses focus after sort`。修复某个 issue 的,正文里写 `Fixes #N`。

## 更新日志

每个版本的变化记在 [CHANGELOG.md](CHANGELOG.md)。只记用户能感受到的变化,每条都链接对应的 issue;文档、重构、测试这类改动不记。PR 里不用改 CHANGELOG,发版时统一整理。
