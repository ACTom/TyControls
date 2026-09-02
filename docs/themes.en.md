# Built-in themes

> 中文版见 [themes.md](themes.md)。

TyControls ships **12 themes compiled into the binary** (no `.tycss` files to distribute): 11 curated dual-mode designer palettes plus `system` (follows the OS accent color). You can use these directly or load your own themes.

## Usage

```pascal
uses tyControls.Controller, tyControls.BuiltinThemes;

TyRegisterBuiltinThemes;              // register all 12 (call once at startup)
Controller.ThemeName := 'dracula';   // switch built-in theme by name
Controller.Mode := 'dark';           // light/dark: 'light' | 'dark'
// or follow the OS (= auto):
Controller.Follow := tfFollowSystem;
```

**Light / dark / follow-system is a controller axis** (`Mode` / `Follow`), orthogonal to which theme is selected. Every built-in theme has both a light and a dark side, so any theme can be light, dark, or OS-following:

| Want | Set |
|------|------|
| Light | `Follow := tfManual; Mode := 'light'` |
| Dark | `Follow := tfManual; Mode := 'dark'` |
| Follow the OS | `Follow := tfFollowSystem` (the OS decides light/dark; the `system` theme follows the OS accent color too) |

Following the OS works on Windows, macOS and Qt5 / Qt6; GTK2 / GTK3 cannot read the desktop appearance — see [known issues](known-issues.en.md).

Switching themes keeps the current `Mode` (a REPLACE load does not reset the active mode).

## Theme list (12)

`default` (neutral blue) · `one` (Atom One) · `dracula` · `nord` · `solarized` · `gruvbox` · `github` · `catppuccin` · `tokyonight` · `monokai` · `material` · `system` (OS accent)

Each theme only sets 5 seed colors (accent / surface / on-surface / border / danger); everything else (hover / active / on-accent / focus-ring / selection / …) is derived by the engine at resolve time, and `on()` picks a black or white foreground per color automatically.

The palettes use the official color values of the respective open-source projects (One/Atom, Dracula + Alucard, Nord, Solarized, Gruvbox, GitHub Primer, Catppuccin Latte/Mocha, Tokyo Night Day/Night, Monokai Pro, Material), most of them MIT-licensed; only the color values are borrowed, with thanks.

> There is no separate static dark theme in the 12 — any theme plus `Mode := 'dark'` is one. If you just want a single fixed dark look, pick `default` and switch to dark.

### The dark-mode contract for structural skins

Structural skins (`themes/builtin/*.tycss`: aero / classic / xp / win11 / …) only override the typeKeys they declare; every other control falls back to the base layer, whose three seeds (`--surface` / `--on-surface` / `--border`) always switch with `Mode`. A skin's `@mode dark` block therefore has exactly two legal shapes:

1. **A real dark palette** — the skin's own keys go dark along with the base fallback, forming one consistently dark window (aero does this: the deep blue-black glass of Win7's dark colorization);
2. **A whole-window no-op** — a skin with no concept of dark (classic / Win95) must pin the base's three seeds back to their light values in `@mode dark`, so fallback controls stay light too. Copying only the skin's own light palette is not enough: that renders a half-dark window (light skin keys over dark fallback surfaces).

The no-op must cover the whole window, **including `--border`** — pinning only `--surface` and `--on-surface` leaves fallback borders and scrollbar thumbs resolving to the base's dark values, drawing near-black hairlines on light chrome.

These contracts are enforced by tests: `test.modecoherence.pas` resolves representative surfaces for every built-in theme in both modes and asserts consistent lightness plus readable ink (luma difference ≥ 60); `TestNoOpDarkThemesAreModeInvariant` requires a declared-no-op dark side to be byte-identical to light across background, border, and text; and `TestFallbackSurfacesStayInTheSkinsOwnHueFamily` catches a skin whose dark palette forgets to pin `--surface`, leaving neutral-gray fallback surfaces next to the skin's own tinted ones. Borrowed typeKeys (TyCoolBar/TyControlBar → TyPanel, TyListView → TyTreeView, …) are pinned to resolve identically to their donors in every stock theme; intentional divergence must be registered (with a reason) in the `ALIAS_EXEMPTIONS` table in `tests/test.themes.pas`.

## Custom themes

```pascal
// Load a .tycss file directly:
Controller.ThemeFile := 'themes/my.tycss';

// Or register by name first (handy for a theme dropdown):
TyRegisterThemeFile('mine', 'themes/my.tycss');
Controller.ThemeName := 'mine';

// A CSS string works too (no file dependency):
TyRegisterThemeCss('inline', 'TyButton { background:#1E66F5; } ...');
Controller.ThemeName := 'inline';
```

`TyThemeNames` returns every registered theme name (file-backed and CSS-backed) — ready to fill a theme dropdown.

## Demo

The top of `examples/demo` is a complete theming UI: a theme dropdown (12 built-ins plus "Custom…" file picking), a three-state appearance switch (light / dark / follow system), and a random-theme button.
