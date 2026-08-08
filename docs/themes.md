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

### 结构皮肤的深色契约(整窗一致)

结构皮肤(`themes/builtin/*.tycss`:aero / classic / xp / win11 / …)只重写**自己声明的 typeKey**,其余控件回落到 base 层,而 base 层的三个种子(`--surface` / `--on-surface` / `--border`,见 `TyBuiltinBaseModeCss`)**始终随 Mode 切换**。因此皮肤的 `@mode dark` 只有两种合法写法:

1. **真深色调色板**——皮肤自己的键随之变深,与 base 回落面共同构成一整扇深色窗口(aero 现在如此:Win7 深色 colorization 的蓝黑玻璃);
2. **整窗 no-op**——皮肤没有深色概念时(classic / Win95),必须在 `@mode dark` 里**把 base 的三个种子钉回浅色值**,让回落控件也保持浅色。只复制自己的浅色调色板是不够的:那会渲染出"自家键浅、回落面黑"的**半黑窗口**(即已修复的 aero/classic 混窗 bug)。

守卫:`tests/test.modecoherence.pas` 对每套内置主题 × 两种模式解析代表性表面(TyForm / TyListBox / TyPanel / TyStatusBar / TyMemo / TyGroupBox / TyToolBar / TyScrollBar / TyCoolBar / TyControlBar / TyTab / TyScrollContent),断言亮度同类(全亮或全暗)、且窗口正文 ink 在每个表面上可读(Rec.601 luma 差 ≥ 60)。新皮肤两条路都不走时,这个测试会点名失败。

> **no-op 必须是整窗的,包括 `--border`。** 上面第 2 条写着「把 base 的三个种子钉回浅色值」,而 xp 只钉了两个:`--surface` 与 `--on-surface` 在 `@mode dark` 里复制成了 Luna 的浅色,`--border` 漏了,于是深色模式下每一条发丝线、每一圈回落边框、以及滚动条滑块都解析成 base 的深色 `#3F3F46`(luma 64),画在 xp 自己没变的米色 chrome(luma 218)上——**浅色条上一条近黑的线**,浅色模式那边只有 6 的差。上面那道亮度守卫看不见它:它分类的是**背景**,而 xp 的背景在两个模式下确实都是浅色;边框不是表面,从来没被量过。
>
> 现在由 `TestNoOpDarkThemesAreModeInvariant` 兜住,而且**不需要任何阈值**——这正是它值得存在的原因:一套主题的深色表面如果解析出来是浅的,它就已经声明了 dark 是 no-op,那 no-op 就必须是彻底的。于是逐键比较两个模式的解析结果,**背景 + 边框 + 文字色**三样(种子喂的正是这三样)全部要求相等。真去深色的主题根本走不到这个比较;声明什么都不做的主题也就没什么可解释的。今天走到这个分支的是 classic / showcase / xp 三套。

> **"只画底色"的键必须有值。** 上面那套断言默认对**透明**表面宽容——透明是合法样式(如 base 的 TyGroupBox),跳过即可。但有一类控件**除了自己解析出来的底色什么都不画**(`TTyScrollContent` 就是:`Paint` 只做一次 `FillBackground`,还包在 `if tpBackground in S.Present` 里)。对这类键,"解析不到"不是"透明样式",而是**屏幕上留着宿主未主题化的擦除色**——而 `TTyForm.ApplyChromeTheme` 只为**纯色**窗体底重新播种那个擦除色,所以渐变底皮肤(aero)会把一块陈旧的浅灰留在那儿:暗色模式下就是一圈**亮斑**。这类键登记在 `cMustPaintKeys` 里,改用**不透明下限**而不是宽容跳过。`TyScrollContent` 正是因此加入的——它此前在**任何一层都没有规则**,于是滚动井的视口一个像素都不画。新增"只画底色"的控件时,记得把它的键一并登进这张表。

另一道守卫管**借来的 typeKey**:几十个从别的控件拆分出来的键(TyCoolBar/TyControlBar→TyPanel、TyListView→TyTreeView 等)被 `tests/test.themes.pas` 钉死为在每套出厂主题里与其 donor 逐字节同解析,防止皮肤**无意间**分叉它们。想让某个键**有意**走自己的样式,唯一通路是在该文件的 `ALIAS_EXEMPTIONS` 表登记(主题, 键, 理由)——理由必填,守卫失败时会连表带扩展方法一起打印;aero 的 rebar(TyCoolBar/TyControlBar 改走 `--chrome-bar-bg` 命令带)是首个案例。

### 守卫管的是亮度**类**,不是色相**家族**——为什么没有再加一道

`c23e45c` 修 aero 的 chrome 家族时留了一句已知边界:守卫只分「亮/暗」两类,**一套浅色发冷、深色转中性的皮肤照样能过**,只有人眼看截图才能发现。这条边界是真的,下面是**为什么不打算用色相守卫去堵它**——决定基于把全部 17 套内置 × 两个模式的 `TyForm` 与各 chrome 面的色相/饱和度全量量过一遍,不是凭感觉。

任何「chrome 必须与自家窗体底色同色相家族」的规则都要两个阈值:一个**饱和度门槛**(低于它色相无意义,规则跳过),一个**色相容差**。实测数据把这两个阈值都逼进了调色板本身的噪声带里:

| 现象 | 数据 | 后果 |
|------|------|------|
| 饱和度门槛无处可放 | aero 浅色窗体饱和度只有 **0.063**;antdesign 浅色窗体 **0.020**(`#F0F2F5`,微冷)而它的 chrome 是**纯白**(饱和度 0,`--chrome-bar-bg: var(--surface)`) | 门槛必须落在 0.020~0.063 之间,即**前后各约 4 级 RGB 色偏**。而 antdesign 那套「冷调窗体 + 纯白工具条」是 Ant 的正经设计,也是 Web 应用最常见的做法之一——它就该过 |
| 近中性色的色相是量化噪声 | office 浅色:窗体 `#F3F2F1` 色相 30°,工具条 `#E4E3E3` 色相 0°,**相差 30°**,而两者饱和度只有 0.008 / 0.004(逐通道差 1~2 级) | 色相容差必须 **> 30°** 才不会被纯噪声误伤,可那个容差已经宽到放行真正的跨家族漂移了 |
| 规则大面积落空 | 17 套里 11 套浅色模式窗体是纯中性(饱和度 0.000),规则直接跳过 | 实际管住的只有 aero(两个模式)+ bootstrap/breeze/material3 的深色侧 + showcase/xp,**真正防的是 aero 一套** |
| 标题栏必须排除 | classic 0.521、xp 与窗体差 **167°**、office 差 **174°** | 灰窗体 + 蓝标题栏是 Win32 的经典正解,`TestOnTitleBarInkReadsOnTheBar` 已按「对比度而非同色」立过契约 |

> 顺带更正一处旧判断:原先记的陷阱是「过严的色相规则会误伤 classic / xp 这类中性皮肤」。**xp 并不中性**——它是暖的(`#ECE9D8`,色相 51°,饱和度 0.085),而且自家 chrome 同色相,任何合理规则它都过。真正会被误伤的是 **antdesign 浅色**(冷窗体 + 纯白 chrome)和 **office 浅色**(两块近灰之间的色相噪声)。

另一层理由是这个缺陷已经被**结构性**挡住了大半:chrome 家族统一由 `--chrome-bar-bg` / `--surface-chrome` 两个令牌喂,皮肤要在某一个模式下转中性,得**特意**写一个中性值进去——那是设计决策,不是手滑。而误报会砸在一个完全正当的设计上,再拿豁免表买回来的话,豁免行数会比规则真正守住的主题数还多。

所以这一格的预算花在了**不需要任何阈值**的那道守卫上:上面的「no-op 必须是整窗的」。它抓到了一个真在仓库里的缺陷(xp 深色的近黑发丝线),而色相规则抓的是假想情形。色相家族仍然属于**看截图**的范畴,这是有意为之。

真要重开这个话题,需要先具备的条件是:内置皮肤里出现**第二套明确有彩度的**(饱和度 ≥ 0.15 量级,像 aero 深色的 0.471,而不是浅色的 0.063)。届时门槛两侧才会有真实余量,规则也才管得住不止一套皮肤。

### 但**皮肤内部**的色相一致性可以守——因为参照物是它自己

上一节拒绝的是**跨皮肤**的色相规则,那个拒绝依然成立。但用户后来报的 aero 深色缺陷是另一个问题,它只需要拿皮肤**跟自己**比,于是不需要任何绝对阈值。

现象:aero 深色下 `examples/containers` 同屏出现两种底色——窗体 / 分组框 / 卡片 / 折叠面板是 aero 自己的冷蓝黑,而斜面(TyBevel)、绘图面板、网格面板格子、滚动视口、工具条所在的宿主面板是**中性近黑**。实测:aero 自家窗体渐变解析为 luma 29.8、彩度 14.7,而每一个回落面都是 `#1E1E1E` —— luma **30.0**、彩度 **0.0**。亮度一模一样,色相相反:眼睛拿到一条没有明暗差可解释的颜色边界,这就是「两种底色」的样子。上一节那道亮度守卫两个都判为「暗」,顺利放行。

根因和 `c23e45c` 修的 chrome 家族是同一个,只是更大一号:aero 的 `@mode dark` 自建了一整套调色板(`--form-1/-2`、`--chrome-bar-bg`、`--surface-chrome`、`--border` …)却**没有钉 `--surface` / `--on-surface`**,于是所有它没重写的键继续吃 base 的中性种子。

**为什么浅色不用一起改**:浅色下这个巧合本来就成立——aero 的 `--field-bg` 是 `#FFFFFF`,base 浅色 `--surface` 也是 `#FFFFFF`,回落的「页面纸」本来就是 aero 自己的页面纸。深色块给了 `--field-bg` 自己的冷井(`#141C27`)却把 `--surface` 落下了,巧合才断掉。所以修法就是**把种子指回皮肤已经选好的那口井**(`--surface: var(--field-bg)`),浅色一个字节都不动。另一个理由:浅色下那块白比窗体底亮 20 luma,读起来是「浅色纸盖在有色底上」的正常景深关系;深色下那块中性和窗体底**亮度相同**,只剩色相差,那才是冲突。

守卫是 `TestFallbackSurfacesStayInTheSkinsOwnHueFamily`,规则一句话,里面**没有一个可调的数**:

> 每一个回落到 base 层的窗口表面,要么是**消色轴端点**(`#FFFFFF` / `#000000`),要么彩度**不低于该皮肤自己画的最不饱和的那个表面**。

之所以不需要阈值,全靠两点:

* **参照物是皮肤自己**。整体中性的皮肤(fluent / adwaita / win11 / macos / ubuntu / win10 …)自家最低彩度就是 0,回落面 0 ≥ 0 自动通过——它们**确实**通体中性,不是被豁免;
* **轴端点豁免有物理依据**,不是拍脑袋:引擎的 `lighten()` 是逐通道向 255 混合、`darken()` 是逐通道乘,所以**任何**家族的色阶两端都收敛到消色。白和黑处的中性仍在家族内;而 `#1E1E1E` 是一个 luma 30 的中间灰,离两端都远,它的中性只能是「没来自这套调色板」。

`--surface` 是逐通道乘的种子,`darken()` 把冷色乘暗仍是冷色,所以钉一个种子就把 `--surface-hover / -active / -alt / -sunk / -track / -toggle-off / …` 整族一起拉回家族,不用逐个写。

**已量过的边界,一并记下来**:

* 17 套 × 2 模式共 34 组,0 失败;其中 32 组进入判定,2 组(default/light、system/light)本身不画任何窗口表面,跳过。42 个回落面走轴端点豁免(**全部正好是 `#FFFFFF`**),63 个进入彩度比较(全部落在自家中性的皮肤里,0 ≥ 0)。
* **ink(`--on-surface`)没有纳入守卫**,这是本节唯一的妥协,理由和上一节同源:同一条规则套到 ink 上会误伤 aero 浅色——它的回落 ink 是 base 的 `#1F2937`(彩度 17.6),自家 ink 是 `#1E2B3A`(彩度 20.3),两块冷石板差 1.4 luma、3 彩度,屏幕上分不出来;而真缺陷(aero 深色回落 ink `#E5E7EB` 彩度 4.5 对自家 16.6)要靠**比值**阈值才分得开,那就又回到量化噪声里了。所以 aero 深色的 `--on-surface` 钉子由 `aero.tycss` 里的注释和解析对拍守着,没有断言;拆掉它测试不会红。
* 皮肤若把某一个自家表面画成中性,自家最低彩度就掉到 0,该皮肤此后对本规则免疫。这是**故意**留的宽容:皮肤自己都在用中性面,回落面用中性就谈不上「不像这套皮肤」。
* 规则的牙齿由**变异测试**证明,不是靠常红:把 aero 深色的 `--surface` 钉子注释掉,守卫点名 `TyListBox` 报错。反过来,把种子钉成一个**暖色**的变异体是**故意**存活的——种子一旦被钉,那个面就归类为「皮肤自己的选择」,不再是回落面;评判皮肤自选色好不好是另一个没有自指答案的问题,不在本守卫范围内。

> **写这道守卫时踩的坑,留给下一个人**:「这个键是皮肤自己画的,还是回落的?」靠拿同一个键去解析一个**不带皮肤的参照 model** 来判定。但 `RebuildMergedVars` 里那句 `if FModeVars.Count > 0` 意味着 base 的分模式种子**只在用户主题本身是双模式时**才叠进去——一个完全不加载主题的 model,无论 `Mode` 设成什么都停在无模式的**浅色**默认值上。于是深色模式下参照物永远答白色,每个键都被判成「皮肤自己的」,整个深色半边**静默失效**:17 套全绿,而 aero 未钉种子的变异体大摇大摆走过去。修法是让参照 model 带一个**什么都不覆盖的双模式空壳**;`TestFallbackClassificationSeesTheBaseLayerInDark` 正反两面把这件事钉住了。

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
