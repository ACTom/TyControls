# TyControls 主题系统 v2 · 阶段1「分层令牌 + 重构内置主题」设计/实现

- **日期:** 2026-06-18 · 承总纲 `2026-06-17-tycontrols-theme-system-v2-design.md`,依赖 Phase 0(merge-then-resolve)已落地。
- **来源:** 一次 4-lens 审计 workflow（derivations / on-accent / DefaultTheme-drift / structure）+ 综合。
- **关键发现(改变范围判断):** 三套主题**重度手调** —— 同一视觉角色的派生**幅度与方向都因主题而异**(如 `--surface-1` = light darken4% / dark lighten8% / showcase darken4%;`--surface-2` = 6/4/4)。所以**跨主题统一(`elevate()`+共享步长)无法保真** —— `elevate` 留 **P3**(双模式,配每模式 step 令牌)。**P1 不引入 `elevate()`**,MAP 层保留各主题**显式 `darken`/`lighten`**。
- **重要:** Phase 0 的 merge-then-resolve 已让「改 SEED → 内联派生自动重派生」生效。所以 MAP 层的价值是 **DRY + 可读**(一次定义),**不是**新增「换肤」能力(那已经有了)。

---

## §0. 已核验地基

- **求值模型**(`StyleModel.pas`):`:root` 变量存原始串,每个属性在 `ResolveStyle` 期对 `FMergedVars` 求值。**任何 `var(--x)`,只要 `--x` 的值正是当前内联的表达式,就逐字节解析相同** —— 这就是「分层=等价替换=零像素」的依据。
- **`on()` 语义**(`Css.Values.pas`):Rec.601 luma,阈值 `> 0.5`。1 参 → 纯黑/白;3 参 `on(bg, inkOnLight, inkOnDark)` → 返回你传的字面。
- **各填充 seed 的 luma**(已算):light accent #3B82F6=0.478→白;light danger #EF4444=0.467→白;showcase accent #7C3AED=0.385→白;showcase danger #DB2777=0.400→白;**dark accent #60A5FA=0.604→1参给#000000**;dark danger #F87171=0.601→#000000。
- **后果(关键):** 1 参 `on()` 对 light+showcase 零像素;但 dark 会把**本就正确**的 `#0B1120` 站点挪成纯 `#000000`(非零变化)。**dark 必须用 3 参** `on(var(--accent), #0B1120, #FFFFFF)` —— 既修 bug 又保正确站点逐字节不变。light/showcase 用 1 参。
  - **⚠ 参序(实现核验,纠正初稿):** `inkOnLight` 是 **bg 偏亮(luma>0.5)时** 取的墨,故应传**深墨** `#0B1120`;`inkOnDark` 传 `#FFFFFF`。dark accent `#60A5FA` luma 0.604>0.5 → 取 `inkOnLight=#0B1120`。**初稿把两参写反了**(`#FFFFFF, #0B1120`),会得白墨;已改为 `#0B1120, #FFFFFF`。
- 无 `.gitattributes`;`tycontrols.lpk` 仅 `OtherUnitFiles=source`。`{$INCLUDESTR}` 在 FPC 3.2.2 **不支持**(已验证)→ DefaultTheme 用生成器 `gen-defaulttheme.ps1`(Commit 0,已落地)。

---

## §1. `light.tycss` 的 `:root`(SEED / MAP / ALIAS / COMPONENT)

下面每个 MAP/ALIAS/COMPONENT 值都**等于其消费点当前内联的表达式**,故替换零像素。

```css
:root {
  /* ── SEED ── 5 colors + 1 metric */
  --accent: #3B82F6; --surface: #FFFFFF; --on-surface: #1F2937;
  --border: #D1D5DB; --danger: #EF4444; --radius: 6px;

  /* ── MAP: directional darken/lighten the body inlines ── */
  --surface-hover:            darken(--surface, 4%);
  --surface-active:           darken(--surface, 10%);
  --surface-chrome:           darken(--surface, 6%);
  --surface-sunk:             darken(--surface, 8%);
  --surface-track:            darken(--surface, 10%);
  --surface-listitem-hover:   darken(--surface, 5%);
  --surface-tab-rest:         darken(--surface, 5%);
  --surface-tab-hover:        darken(--surface, 2%);
  --surface-toggle-off:       darken(--surface, 18%);
  --surface-toggle-off-hover: darken(--surface, 22%);
  --surface-caption-hover:    darken(--surface, 12%);
  --surface-caption-active:   darken(--surface, 20%);
  --border-hover:             darken(--border, 10%);
  --scroll-handle-hover:      darken(--border, 15%);
  --accent-hover:  lighten(--accent, 8%);   --accent-active: darken(--accent, 8%);
  --danger-hover:  lighten(--danger, 8%);   --danger-active: darken(--danger, 8%);
  --danger-press-close: darken(--danger, 10%);

  /* ── ALIAS: semantic ── */
  --focus-ring:       var(--accent);
  --selection:        alpha(var(--accent), 0.30);
  --muted:            alpha(var(--on-surface), 0.5);
  --overlay-hover:    alpha(var(--on-surface), 0.12);
  --disabled-opacity: 0.5;
  --form-bg:          var(--surface-hover);   /* TyForm bg */
  --titlebar-bg:      var(--surface-chrome);  /* TyTitleBar bg */
  --input-bg:         var(--surface);         /* Edit/Check/Radio/Combo/List/Spin/Memo bg */
  --scroll-handle:    var(--border);          /* resting scroll thumb/handle */
  --input-border-hover: var(--border-hover);  /* neutral inputs hover border */
  /* on-* declared here but WIRED only in the §3 bug-fix commit */
  --on-accent:        on(var(--accent));      /* light -> #FFFFFF (== current literal) */
  --on-danger:        on(var(--danger));      /* light -> #FFFFFF */

  /* ── COMPONENT: scalars ── */
  --input-border-width: 1px;
  --radius-sm: 3px; --radius-pill: 8px; --radius-round: 12px; --radius-scroll: 4px;
  --font-size-base: 9px; --font-size-title: 9px;
  --font-weight-normal: 400; --font-weight-bold: 700;
}
```

### Body 替换(机械、保值)

| 内联(light body) | 换为 |
|---|---|
| `darken(--surface, 4%)` Form bg | `var(--form-bg)`(Form) / `var(--surface-hover)`(Button:hover) |
| `darken(--surface, 10%)` Button:active | `var(--surface-active)` |
| `darken(--surface, 6%)` ScrollBar/TitleBar bg | `var(--surface-chrome)`(ScrollBar) / `var(--titlebar-bg)`(TitleBar) |
| `darken(--surface, 8%)` ProgressBar | `var(--surface-sunk)` |
| `darken(--surface, 10%)` TrackBar | `var(--surface-track)` |
| `darken(--surface, 5%)` ListItem:hover / Tab rest | `var(--surface-listitem-hover)` / `var(--surface-tab-rest)` |
| `darken(--surface, 2%)` Tab:hover | `var(--surface-tab-hover)` |
| `darken(--surface, 18/22%)` Toggle off/off:hover | `var(--surface-toggle-off)` / `var(--surface-toggle-off-hover)` |
| `darken(--surface, 12%)` caption hover/min/max | `var(--surface-caption-hover)` |
| `darken(--surface, 20%)` caption:active | `var(--surface-caption-active)` |
| `darken(--border, 10%)` 7 input hover sites | `var(--input-border-hover)` |
| `darken(--border, 15%)` ScrollBar/Thumb:hover | `var(--scroll-handle-hover)` |
| `var(--border)` ScrollBar color / ScrollThumb bg | `var(--scroll-handle)` |
| `lighten(--accent,8%)`/`darken(--accent,8%)` | `var(--accent-hover)`/`var(--accent-active)` |
| `lighten(--danger,8%)`/`darken(--danger,8%)` | `var(--danger-hover)`/`var(--danger-active)` |
| `darken(--danger,10%)` close:active | `var(--danger-press-close)` |
| `var(--surface)` on Edit/Check/Radio/Combo/List/Spin/Memo bg | `var(--input-bg)` |
| `opacity: 0.5` (14×) | `opacity: var(--disabled-opacity)` |
| `border-width: 1px` (inputs) | `var(--input-border-width)` |
| `border-radius: 3/8/12/4px` | `var(--radius-sm/pill/round/scroll)` |
| `font-size: 9px` (12×) | `var(--font-size-base)`(TitleBar→`var(--font-size-title)`) |
| `font-weight: 400/700` | `var(--font-weight-normal/bold)` |

**注意:** `--surface-active` 与 `--surface-track` 在 light 都 = `darken10%` 但**角色不同**(按钮按下 vs 滑轨槽),dark 里分别 = darken6%/darken4% —— **按角色分两个 MAP 变量,勿按值合并**。`--on-accent/--on-danger` 本提交**只声明、不接线**(接线在 §3)。

---

## §2. `dark.tycss` / `showcase.tycss` 的 `:root` deltas

同名变量、按主题取值;body 用**相同的 `var(--…)` 名替换**(各主题内联值已等于这些定义)。

### dark.tycss
```css
  --accent:#60A5FA; --surface:#1E1E1E; --on-surface:#E5E7EB; --border:#3F3F46; --danger:#F87171; --radius:6px;
  --surface-hover: lighten(--surface, 8%);    --surface-active: darken(--surface, 6%);
  --surface-chrome: darken(--surface, 4%);     --surface-sunk: darken(--surface, 4%);
  --surface-track: darken(--surface, 4%);
  --surface-listitem-hover: lighten(--surface, 10%);
  --surface-tab-rest: lighten(--surface, 12%); --surface-tab-hover: lighten(--surface, 18%);
  --surface-toggle-off: lighten(--surface, 20%); --surface-toggle-off-hover: lighten(--surface, 24%);
  --surface-caption-hover: lighten(--surface, 16%); --surface-caption-active: lighten(--surface, 24%);
  --border-hover: lighten(--border, 12%);      --scroll-handle-hover: lighten(--border, 25%);
  --accent-hover: lighten(--accent, 8%); --accent-active: darken(--accent, 8%);
  --danger-hover: lighten(--danger, 8%); --danger-active: darken(--danger, 8%);
  --danger-press-close: darken(--danger, 10%);
  --overlay-hover: alpha(#FFFFFF, 0.14);
  --disabled-opacity: 0.5;
  --form-bg:     var(--surface);              /* dark Form = raw surface (no darken) */
  --titlebar-bg: lighten(--surface, 4%);      /* dark TitleBar lifts */
  --input-bg:    lighten(--surface, 4%);      /* dark raised input bg */
  --scroll-handle: lighten(--border, 10%);
  --input-border-hover: var(--border-hover);
  --on-accent: on(var(--accent), #0B1120, #FFFFFF);   /* light-blue accent -> inkOnLight = #0B1120 */
  --on-danger: on(var(--danger), #0B1120, #FFFFFF);
  /* COMPONENT identical to light: 1px / 3,8,12,4 / 9px / 400,700 */
```

### showcase.tycss
```css
  --accent:#7C3AED; --surface:#F5F3FF; --on-surface:#2E1065; --border:#C4B5FD; --danger:#DB2777; --radius:10px;
  --surface-hover: darken(--surface, 4%);     --surface-active: darken(--surface, 10%);
  --surface-chrome: darken(--surface, 4%);     --surface-sunk: darken(--surface, 6%);
  --surface-track: darken(--surface, 8%);
  --surface-listitem-hover: lighten(--surface, 2%);
  --surface-tab-rest: darken(--surface, 6%);   --surface-tab-hover: darken(--surface, 3%);
  --surface-toggle-off: darken(--surface, 14%); --surface-toggle-off-hover: darken(--surface, 18%);
  --surface-caption-hover: alpha(#FFFFFF, 0.18); --surface-caption-active: alpha(#FFFFFF, 0.30);
  --accent-hover: lighten(--accent, 10%); --accent-active: darken(--accent, 10%);
  --danger-hover: lighten(--danger, 10%); --danger-active: darken(--danger, 10%);
  --danger-press-close: darken(--danger, 10%);
  --overlay-hover: alpha(#FFFFFF, 0.18);
  --disabled-opacity: 0.45;
  --input-bg: #FFFFFF;
  --scroll-handle: var(--border);
  --input-border-hover: lighten(--accent, 10%);   /* showcase tints hover border from ACCENT */
  --scroll-handle-hover: var(--accent);
  --on-accent: on(var(--accent)); --on-danger: on(var(--danger));
  --form-bg: var(--surface-hover);
  --titlebar-bg: linear-gradient(90deg, lighten(--accent, 8%), var(--accent));
  --input-border-width: 2px;
  --radius-sm: 4px; --radius-pill: 9px; --radius-round: 12px; --radius-scroll: 6px;
  --font-size-base: 9px; --font-size-title: 11px;
  --font-weight-normal: 400; --font-weight-bold: 700;
```

**showcase 渐变/例外(不折成标量 MAP —— 保持内联,P1 不动):**
- `TyButton` rest/hover 用 `linear-gradient(...)`(含 `darken(--surface,6/4%)`/`lighten(--surface,3%)`)—— **保持内联**(渐变串非单色令牌)。
- `TyButton.primary`/`TyProgressFill`/`TyTrackThumb` rest=`linear-gradient(90deg, lighten(--accent,10%), var(--accent))`,hover=`linear-gradient(90deg, lighten(--accent,16%), lighten(--accent,4%))` —— **保持内联**。danger 渐变同理。
- **showcase ScrollBar:active 不一致(必须逐字节保留):** `TyScrollBar:active`/`TyScrollThumb:active` 用 `darken(--accent, 8%)`(8%,**非** showcase 的 10%)。**勿指向 `--accent-active`**(showcase 是 10%)→ **保持 `darken(--accent, 8%)` 内联**。

---

## §3. on-accent 修正(唯一有意像素变化,独立提交,在分层之后)

dark 同一 accent `#60A5FA` 上两种墨:`#0B1120`(button/list) 与 `#FFFFFF`(checkbox/radio,**bug**)。`on()` 统一。

站点(`color:` 墨在填充上):light/showcase 用 `var(--on-accent)`/`var(--on-danger)`(零像素,= 现 #FFFFFF);dark 同样换名,3 参 `on()` → button/list 保 `#0B1120` 不变、**checkbox/radio 由 #FFFFFF 改 #0B1120(修复)**。`TyToggleSwitch.color` 含在内(旋钮 `TyToggleKnob`=#FFFFFF 不动)。`TyCaptionButton.close` 墨 → `var(--on-danger)`。

**像素变化总结:** light/showcase 零;dark 仅 `TyCheckBox:active`/`TyRadioButton:active`(及 toggle.color)墨 #FFFFFF→#0B1120。**金标准 diff 必须正好只有这些 dark 站点。** 修正提交中**更新 dark 金标准**。

**测试:** 现有无 shipped-theme 墨值断言(控件测试用内联 CSS),故无既有测试因此变红。新增一条:载 dark.tycss,resolve `TyCheckBox` `[tysActive]`,断言 `TextColor` = `#0B1120`(锁定修复,TDD red→green)。

---

## §4. DefaultTheme.pas 去重 —— 已落地(Commit 0)

`gen-defaulttheme.ps1` 从 light.tycss 生成 DefaultTheme.pas;`TestBuiltinMatchesLightTheme` 守新鲜度。每次改完 light.tycss **重跑生成器**。

---

## §5. 提交顺序(每步金标准零 diff)

- **Commit 0(已完成):** DefaultTheme 生成器。
- **Commit 1(分层):** 三套主题加 SEED/MAP/ALIAS/COMPONENT 层 + body 等价替换(on-* 只声明不接线)。**重跑生成器**(light 变了)。金标准**零 diff**(纯替换)。
- **Commit 2(on-accent 修正):** 接线 `color:` 站点 + dark 新断言。light/showcase 零像素;dark 仅 checkbox/radio(/toggle)墨变 —— **更新 dark 金标准**为这唯一有意变化。

每步:`lazbuild tests/tytests.lpi` → `tytests.exe`,现有全绿 + 金标准守恒。
