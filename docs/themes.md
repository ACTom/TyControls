# 内置主题

TyControls 自带 **12 套编译进二进制的主题**(无需随程序分发 `.tycss`):11 套 curated 双模设计师调色板 + `system`(跟随 OS 强调色)。用户既可直接用内置主题,也可加载自定义主题。

## 用法

```pascal
uses tyControls.Controller, tyControls.BuiltinThemes;

TyRegisterBuiltinThemes;              // 注册 12 套到全局注册表(启动时调用一次)
Controller.ThemeName := 'dracula';   // 切换内置主题(按名)
Controller.Mode := 'dark';           // 明/暗:'light' | 'dark'
// 或跟随系统(= auto):
Controller.Follow := tfFollowSystem;
```

**明 / 暗 / 跟随系统是 controller 的轴**(`Mode` / `Follow`),与「选哪套主题」**正交**——每套内置主题都含 light + dark 两版,任意主题都能切浅色、深色或跟随 OS:

| 想要 | 设置 |
|------|------|
| 浅色 | `Follow := tfManual; Mode := 'light'` |
| 深色 | `Follow := tfManual; Mode := 'dark'` |
| 跟随系统 | `Follow := tfFollowSystem`(OS 决定浅/深;`system` 主题连强调色也跟 OS) |

切换主题时当前 `Mode` 会保留(REPLACE 加载不重置激活模式)。

## 主题清单(12)

`default`(中性蓝) · `one`(Atom One) · `dracula` · `nord` · `solarized` · `gruvbox` · `github` · `catppuccin` · `tokyonight` · `monokai` · `material` · `system`(OS 强调色)

每套主题只覆盖 5 个种子色(accent / surface / on-surface / border / danger),其余(hover/active/on-accent/focus-ring/selection/…)由引擎在解析时自动派生;`on()` 自动为每色选黑/白前景字。

调色板取自各开源项目官方色值(One/Atom、Dracula + Alucard、Nord、Solarized、Gruvbox、GitHub Primer、Catppuccin Latte/Mocha、Tokyo Night Day/Night、Monokai Pro、Material),多为 MIT;此处仅借用色值并致谢。

> 静态深色不在这 12 套里——任意主题 + `Mode := 'dark'` 即可;若只想要一套固定深色,选 `default` 并切深色。

## 自定义主题

```pascal
// 直接加载一个 .tycss 文件:
Controller.ThemeFile := 'themes/my.tycss';

// 或先按名注册再切换(便于做自己的主题下拉):
TyRegisterThemeFile('mine', 'themes/my.tycss');
Controller.ThemeName := 'mine';

// 也可注册一段内置 CSS 字符串(无文件依赖):
TyRegisterThemeCss('inline', 'TyButton { background:#1E66F5; } ...');
Controller.ThemeName := 'inline';
```

`TyThemeNames` 返回当前注册表里的全部主题名(文件源 + CSS 源),可直接用来填主题下拉。

## demo

`examples/demo` 顶部演示了完整换肤 UI:主题下拉(12 套内置 + 「自定义…」文件选择)、外观三态(浅色 / 深色 / 跟随系统)、以及「随机换肤」按钮。
