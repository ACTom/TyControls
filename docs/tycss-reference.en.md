# TyControls `.tycss` Style Language Reference

> 中文版见 [tycss-reference.md](tycss-reference.md)。

This document is the authoritative syntax reference for the TyControls v1 style language (`.tycss`), written for theme authors and control developers.
Every rule stated here has been checked against the engine implementation (`source/tyControls.Css.Lexer.pas`, `Css.Parser.pas`,
`Css.Values.pas`, `StyleModel.pas`, `Painter.pas`). Where other documents disagree, this one wins.

Loading entry points: `TTyStyleModel.LoadFromFile(filename)` / `LoadFromCss(source string)`.
Syntax errors raise `ETyCssError` (with line/column numbers); invalid property values (such as an unparseable color) raise at load time;
**unknown property names are silently ignored** and never reported.

## Built-in Default Skin and Override Semantics

The library ships a built-in default skin (identical to `themes/light.tycss`) that is always present as the base layer. `ResolveStyle`
behaves as follows: a typeKey falls back to the built-in defaults **if and only if** the loaded theme has no rules at all for that
typeKey. As soon as the theme writes any rule for a typeKey, the built-in layer is disabled for that key entirely; the theme alone
decides everything, and properties the theme leaves blank do not leak through from the built-in layer. A complete theme therefore
renders exactly as it did before this feature existed, while a partial theme never leaves uncovered controls invisible.

> **Upgrading an existing theme? Read §8.1 first.** v3 split the 51 controls that borrowed another control's typeKey into keys of
> their own. Because override semantics are **all-or-nothing per typeKey**, any new key your theme never mentions falls back to the
> built-in light values **as a whole key**.

---

## 1. Overview and a Complete Example

`.tycss` is a deliberately small CSS dialect:

- The top level has exactly two constructs: `:root` variable blocks and style rules;
- Selectors have one shape only: `type [.variant] [:state]`, with comma-separated lists allowed;
- Descendant, child, wildcard, and every other combinator selector are **not supported**;
- Variables are evaluated lazily at their use sites; both `var(--x)` and bare `--x` work;
- Colors support the `rgb` / `rgba` constructors plus the `lighten` / `darken` / `alpha` / `mix` adjustment functions, nested to any depth.

Here is a minimal but complete theme, usable as-is:

```css
/* my-theme.tycss - a minimal working theme */
:root {
  --accent:     #3B82F6;
  --surface:    #FFFFFF;
  --on-surface: #1F2937;
  --border:     #D1D5DB;
  --danger:     #EF4444;
  --radius:     6px;
  --focus-ring: var(--accent);   /* focus ring color; overridable on its own */
}

TyButton {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 6px;
  font-size: 10px;
  font-weight: 400;
}
TyButton:hover    { background: darken(--surface, 4%); }
TyButton:focus    { border-color: var(--accent); outline: 2px var(--focus-ring); }
TyButton:active   { background: darken(--surface, 10%); }
TyButton:disabled { opacity: 0.5; }

TyButton.primary        { background: var(--accent); color: #FFFFFF; border-color: var(--accent); }
TyButton.primary:hover  { background: lighten(--accent, 8%); }
TyButton.primary:active { background: darken(--accent, 8%); }

TyLabel {
  background: alpha(#FFFFFF, 0);   /* fully transparent */
  color: var(--on-surface);
  font-size: 10px;
}

TyEdit, TyComboBox {
  background: var(--surface);
  color: var(--on-surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 4px;
  font-size: 10px;
}
TyEdit:focus, TyComboBox:focus { border-color: var(--accent); outline: 2px var(--focus-ring); }

TyPanel {
  background: var(--surface);
  border-color: var(--border);
  border-width: 1px;
  border-radius: var(--radius);
  padding: 8px;
}
```

For fuller examples see the bundled themes: `themes/light.tycss`, `themes/dark.tycss`, `themes/builtin/showcase.tycss`.

---

## 2. File Structure and Lexical Rules

### 2.1 Top-level structure

A `.tycss` file is a sequence of `:root` blocks and style rules, in any order, freely interleaved:

```css
:root { --a: #fff; }
TyButton { background: var(--a); }
:root { --a: #000; }   /* multiple :root blocks are allowed; the later definition of a name wins */
```

### 2.2 Comments

Only block comments `/* ... */` are supported; they may span lines. `//` line comments are **not** supported.

### 2.3 Token overview

| Token | Form | Notes |
|---|---|---|
| Color literal | `#rgb` `#rrggbb` `#rrggbbaa` | After `#` only hex characters are consumed; the length must be 3, 6, or 8, anything else raises at evaluation time |
| Number | `10` `0.45` `.5` | Unsigned; decimals allowed. **Lexically a number carries no minus sign** (see "Negative values" below) |
| Identifier | `bold` `--accent` `-2px` | First character `[a-zA-Z_-]`, later characters may include digits; `-` may lead, so `--accent` and `-2px` are each a single identifier |
| Function name | `var(` `lighten(` `url(` | An identifier **immediately followed** by `(` (no space between) opens a function call |
| String | `"Noto Sans"` `'a'` | Single or double quotes; **no escape sequences**; cannot contain its own quote character |
| Unit / symbol | `px` `%` `deg` | `px` and `deg` are ordinary identifiers, glued onto a preceding number to form `6px`, `90deg`; `%` is a standalone symbol bound to the number before it |
| Punctuation | `: ; { } . , ( )` | |

Negative values: `-2px` lexes as a single identifier token, but the length/number evaluation functions parse it correctly,
so negative offsets such as `shadow: 0px -2px 4px #0000002E;` are legal.

### 2.4 Writing declarations

- Every declaration is `property: value;` and the **semicolon is mandatory**, including after the last declaration in a block;
- A value runs to the next semicolon or `}`; commas and colons inside parentheses do not cut it short;
- Type names, variant names, pseudo-class names, property names, and function names all match **case-insensitively**
  (by convention, follow the spellings used in this document and the bundled themes);
- If the same property appears twice in one rule block, **the later one wins**.

---

## 3. `:root` Variables

### 3.1 Definition

```css
:root {
  --accent: #3B82F6;
  --radius: 6px;
  --hover-bg: lighten(--accent, 8%);   /* variables may reference other variables */
}
```

- Variable names must start with `--`; anything else is a parse error;
- A value is stored as **raw text** and evaluated only at its use site (lazy evaluation). Variables may therefore reference
  other variables forward or mutually, and may hold color functions, gradient argument fragments, or any other expression;
- Redefining a name overrides the earlier definition (across multiple `:root` blocks too);
- Referencing an undefined variable raises **when a rule that uses it is evaluated**, i.e. when the stylesheet loads.

### 3.2 References: `var(--x)` and bare `--x` both work

In color, length, and number expressions the following two spellings are **fully equivalent**:

```css
TyButton {
  background: var(--accent);            /* standard CSS spelling */
  border-color: --accent;               /* bare variable form, equally valid */
  border-radius: var(--radius);
  padding: --radius;
}
```

Both forms also work inside function arguments; the bundled themes use the bare form heavily for brevity:

```css
TyButton:hover { background: lighten(--accent, 8%); }      /* bare --x */
TyButton:focus { border-color: darken(var(--border), 10%); } /* var(--x) */
```

Note: a `var(...)` form is only usable as a whole value or a whole function argument; there is no string concatenation.

### 3.3 Built-in semantic tokens

Besides `--focus-ring` (§5.14), the built-in themes define several other **semantic tokens** in `:root` for sub-part typeKeys
and text controls to reference. They are ordinary `--` variables and theme authors may override them wholesale:

| Token | Built-in value (light) | Meaning / use |
|---|---|---|
| `--selection` | `alpha(var(--accent), 0.30)` | Text selection highlight band (accent-tinted, semi-transparent); referenced by `TyTextSelection`, so Edit/Memo selections share their look with selected list rows |
| `--muted` | `alpha(var(--on-surface), 0.5)` | De-emphasized foreground (placeholder / hint text); referenced by `TyTextHint` |
| `--overlay-hover` | `alpha(var(--on-surface), 0.12)` | Semi-transparent hover overlay (e.g. the rounded backdrop behind a tab's close ×); referenced by `TyTabClose` |

```css
:root {
  --selection:     alpha(var(--accent), 0.30);
  --muted:         alpha(var(--on-surface), 0.5);
  --overlay-hover: alpha(var(--on-surface), 0.12);
}
```

> Changing these three tokens restyles selections, placeholders, and hover overlays globally, with no per-control edits.
> Like `--accent` and `--on-surface` above they are evaluated lazily at use sites and may reference other variables.

---

## 4. Selectors and Style Resolution

### 4.1 Selector grammar

```
selector      ::= type-name [ "." variant-name ] [ ":" state-name ]
selector-list ::= selector { "," selector }
```

- **Type name**: the control's typeKey (see section 8), e.g. `TyButton`;
- **Variant name** (optional): any identifier, matching a token in the control's `StyleClass` property, e.g. `.primary`;
  **at most one** variant per selector;
- **State name** (optional): only the five names `hover`, `active`, `focus`, `disabled`, `selected` are allowed
  (`checked` is an alias of `selected` and parses to the same state); any other pseudo-class name is a parse error.
  At most one state per selector; chaining such as `:selected:disabled` is **not allowed**.

```css
TyButton { ... }                 /* base style for the type */
TyButton.primary { ... }         /* variant */
TyButton:hover { ... }           /* state */
TyButton.primary:hover { ... }   /* variant + state */
TyEdit:focus, TyComboBox:focus { ... }   /* comma list: one declaration group registered under several selectors */
```

### 4.2 Selectors that are explicitly unsupported

All of the following either fail to parse or never match; the engine has **no** combinator selectors at all:

- Descendant / child selectors: `TyPanel TyButton`, `TyPanel > TyButton`
- Wildcard: `*`
- Multiple variants: `TyButton.primary.large` (a selector allows exactly one `.variant`)
- Bare class / bare state selectors: `.primary`, `:hover` (a selector must start with a type name)
- Attribute selectors, `!important`, and `@media` are all unsupported
  (`@import` and `@mode` **are** supported at-rules, they are just not selectors; `@import` must appear **before**
  all `:root` blocks and rules)

### 4.3 Where control states come from

A control computes its current state set on every repaint:

- `disabled` (control `Enabled = False`) is **exclusive**: a disabled control has only the disabled state;
  hover / focus / active are all ignored;
- `hover`: the mouse is over the control;
- `active`: the left mouse button is held down (for CheckBox and the like this still means "pressed", not "checked");
- `focus`: the control has keyboard focus. Controls based on `TTyGraphicControl` (the `TTyLabel` family,
  `TTyProgressBar`, the gauge family, and so on) have **no** focus state; every windowed control that can take focus supports it;
- `selected`: a **selectable part** (item / cell / tab) is in its selected state. It is supplied by the sub-part's resolve site
  (e.g. `TyListViewItem`, `TyCalendarCell`, `TyGridCell`, `TySegmentedItem`), not by the control's own momentary state.

Several states can hold at once (hovering over a focused button = hover + focus).
Which states a key supports depends on **what its resolve site passes**. Section 8 lists the pseudo-classes the built-in theme
actually writes for each key, and calls out keys whose resolve sites pass an **empty state set**, making their pseudo-class
selectors dead (e.g. `TyLinkLabelLink`).

### 4.4 Resolution and merge order (ResolveStyle)

A control's final style merges several `TTyStyleSet` layers in a **fixed order**; a later layer overrides only the properties
it **explicitly declares**:

1. **Type base layer**: `Type { }`;
2. **Variant layer**: each whitespace-separated token in the control's `StyleClass`, applying `Type.variant { }` in the order
   the tokens appear in the `StyleClass` string (`StyleClass` may hold several variants, e.g. `"primary large"`);
3. **State layer**: for each state currently in effect, processed in the fixed order
   **selected → hover → focus → active → disabled**;
   within each state, `Type:state { }` applies first, then `Type.variant:state { }` in variant order.
   Putting `selected` first is deliberate: it is a **static resident layer**, so hover/active can override its conflicting
   properties one by one, while properties only selected declares (say, a `border-color` no one else sets) still survive.

It follows that **a rule with a state always applies later than (beats) a rule without one, and a variant state rule always
applies later than the plain type rule of the same state**.

#### Why the hover for `.primary` must be written `TyButton.primary:hover`

```css
TyButton          { background: #FFFFFF; }
TyButton:hover    { background: #F0F0F0; }              /* state layer */
TyButton.primary  { background: var(--accent); }        /* variant layer */
```

Hovering over a button whose `StyleClass = primary`, the merge order is
`TyButton` → `TyButton.primary` → `TyButton:hover`.
The state layer comes **after** the variant layer, so the `#F0F0F0` from `TyButton:hover` overrides the accent from `.primary`,
and the primary button washes out on hover. The fix is a matching state rule for the variant, which applies after
`TyButton:hover`:

```css
TyButton.primary:hover { background: lighten(--accent, 8%); }
```

#### Duplicate selectors: last one wins (merged per property)

For each `(type, variant, state)` combination the engine applies **all** matching rules in source order, each overriding the
previous per property, exactly like browser CSS. This is also what lets `@import` / appended loads layer per property:

```css
TyButton { background: #FF0000; color: #111111; }
TyButton { background: #00FF00; }   /* overrides background only; color is still #111111 */
```

`TestDuplicateRuleLastWins` in `tests/test.StyleModel.pas` guards this behavior.
Even so, avoid defining the same selector twice **in one file**; when you need parallel declarations, put them in one rule
block so readers do not have to scan the whole file for overrides.

---

## 5. Property Reference

The engine recognizes 23 properties (plus `background-color` as an alias of `background`); every other property name is
silently ignored. This section covers the 16 general-purpose ones. The other 7 are window-chrome / material properties this
manual does not yet cover individually (`render-style` is covered in §9 item 17; for the rest,
`background-size`, `background-blur`, `glass-blur`, `glass-tint`, and
`background-under-titlebar`, the source `TyApplyDeclaration` is currently the reference).
All lengths are **logical pixels** (96 DPI baseline), scaled to the control's actual DPI when drawing.
A length may be written `6px` or bare `6` (the `px` suffix is optional), or as `var(--x)` / bare `--x`.

### 5.1 `background` — background fill

```
background: <color-expression> ;
background: linear-gradient(<angle>deg, <stop1>, <stop2>[, …]) ;
```

- Solid: any color expression (`#hex`, `var()`, bare `--x`, color functions; see section 6);
- Gradient: see section 7; **the angle must be the first argument**, and the value parses as a gradient only when it starts with `linear-gradient(`; 2 or more stops are supported (with optional positions).

```css
TyPanel  { background: var(--surface); }
TyButton { background: linear-gradient(90deg, lighten(--accent, 10%), var(--accent)); }
```

`background-color` is an **alias** of `background` (solid colors only, no gradients); the two behave identically:

```css
TyEdit { background-color: rgb(255, 255, 255); }   /* same as background: rgb(255, 255, 255); */
```

### 5.2 `background-image` — nine-slice image

```
background-image: url(<path>) slice(<top> <right> <bottom> <left>) [repeat] ;
```

- `url()` and `slice()` are **both mandatory**; omitting either raises;
- The four `slice` values are integer pixels in the fixed order **top right bottom left** (the CSS four-value order),
  giving the width of the non-stretching border on each edge of the source image;
- An optional trailing `repeat` (v3) **tiles** the four edges and the center (1:1 repetition) instead of stretching them,
  for bitmap skins with patterned or textured borders; without it, they stretch (the old behavior). The four corners are
  always 1:1 either way;
- The path may be quoted or unquoted, but **must never contain spaces**: the lexer inserts spaces into unquoted paths
  (`panel.png` becomes `panel. png`) and the engine recovers by deleting all spaces unconditionally, so real spaces are
  deleted too and the path silently reads wrong. Keep directory and file names free of spaces;
- Relative paths resolve against the **process's current working directory** (there is no "relative to the theme file"
  resolution); if the file does not exist, the fill is silently skipped (no error, nothing drawn);
- `var()` is not supported.

```css
TyPanel { background-image: url(assets/panel.png) slice(8 8 8 8); }
```

### 5.3 `color` — foreground / text color

```
color: <color-expression> ;
```

Used for text and for tier-b monochrome glyphs (the CheckBox check mark, ComboBox dropdown arrow, SpinEdit/ScrollBar arrows,
tab close ×, and so on; see §8.7).

```css
TyButton.primary { color: #FFFFFF; }
```

Note: sliders, knobs, and other tier-a **colored surfaces** no longer borrow the control's `color`; their color comes from
the `background` of their own sub-part typeKey (`TyScrollThumb`, `TyToggleKnob`, and so on). See §8.2 / §8.7. Track and rail
backgrounds still come from the parent control's `background`.

### 5.4 `border-color` / `border-width` / `border-style` — borders

```
border-color: <color-expression> ;
border-width: <length> ;
border-style: none | solid | outset | inset ;
```

The three work together: no border is stroked when `border-width` is 0 (or `border-color` is undeclared).
A `solid` border is stroked along the inside of the rounded rectangle.

`border-style` values, **default `solid`**:
- `none` — **forces no border**, even when `border-width > 0`;
- `solid` — single-color stroke (along the inside of the rounded rect);
- `outset` / `inset` (v3) — **two-color 3D bevel**: top/left and bottom/right use a lighter and a darker edge color,
  `outset` raised, `inset` recessed. The light and dark colors are **derived automatically** from `border-color`
  (lighten for top/left, darken for bottom/right). Bevels are inherently **square-cornered** (the corner radius is not
  applied), suiting classic-style controls (pair with `border-radius: 0`).

`dashed`, `dotted`, `groove`, `ridge`, and other styles are not supported.

```css
TyEdit       { border-color: var(--border); border-width: 1px; }
TyEdit:focus { border-color: var(--accent); }
TyPanel      { border-style: none; }   /* explicitly no border, even with a border-width */
/* classic raised button: face color as border-color; highlight/shadow edges derived automatically */
TyButton.classic { border: 2px outset #C0C0C0; border-radius: 0; background: #C0C0C0; }
```

### 5.5 `border` — border shorthand

```
border: <width> [<style>] <color> ;
```

Sets `border-width`, `border-style`, and `border-color` in one declaration, **fully equivalent** to writing them separately.
Width comes first, color last, with an optional `solid` / `none` / `outset` / `inset` style between them (`solid` when omitted).
The color may be any color expression (`#hex`, `var(--x)`, `rgb(...)` / `rgba(...)`; see section 6):

```css
TyButton { border: 2px solid var(--accent); }   /* width=2px, style=solid, color=accent */
TyEdit   { border: 1px var(--border); }          /* style omitted, same as solid */
TyPanel  { border: 0px none var(--border); }     /* style=none → forces no border */
```

### 5.6 `border-radius` — corner radius

```
border-radius: <length> ;
border-radius: <TL> <TR> <BR> <BL> ;
```

Shapes the background fill, the border, and the focus ring alike. `0px` gives square corners.

- **1 value**: the same radius on all four corners (backward compatible with the original behavior);
- **4 values**: the CSS order **top-left, top-right, bottom-right, bottom-left** (`TL TR BR BL`), space-separated.
  Each value may be a length or `var(--x)` / bare `--x`; `0` means square.

```css
TyButton    { border-radius: var(--radius); }           /* same radius on all corners */
TyTitleBar  { border-radius: 6px 6px 0 0; }            /* round top, square bottom (title bar / tabs) */
TyTabControl { border-radius: var(--radius) var(--radius) 0 0; }
```

The built-in themes use `var(--radius) var(--radius) 0 0` on title bars (`TyTitleBar`) and tabs (`TyTab`) for the
round-top, square-bottom look.

**Not supported**: per-corner longhands (`border-top-left-radius` etc.), percentage radii, and the
elliptical two-radius form (`<a> / <b>`).

### 5.7 `padding` — inner padding

```
padding: <all> ;
padding: <vertical> <horizontal> ;
padding: <top> <right> <bottom> <left> ;
```

Space-separated; exactly 1, 2, or 4 values (3 raises). Semantics match CSS.

```css
TyButton { padding: 6px; }
TyPanel  { padding: 8px 12px; }
TyEdit   { padding: 4px 8px 4px 8px; }
```

### 5.8 `font-family` — font name

```
font-family: <font-name> ;
```

The value's raw text is used directly as the font name. **Do not quote it**: quote characters are kept as part of the name
and the font is then not found. Write multi-word names bare (runs of spaces normalize to a single space):

```css
TyLabel { font-family: Noto Sans CJK SC; }   /* correct */
/* font-family: "Noto Sans CJK SC";  wrong: the quotes become part of the name */
```

### 5.9 `font-size` — font size (the number means pt)

```
font-size: <number>[px] ;
```

**The number is interpreted as points (pt)**: drawing converts it to pixels as `round(n × 96 / 72)`, then applies DPI
scaling. A `px` suffix is allowed but merely stripped; the number is still treated as pt. `font-size: 10px` is really 10pt
(about 13 pixels at 96 DPI). The built-in themes follow this spelling.

```css
TyButton { font-size: 10px; }   /* = 10pt */
```

### 5.10 `font-weight` — font weight

```
font-weight: bold | normal | <number> ;
```

- `bold` = 700, `normal` = 400; plain numbers work too (e.g. `600`);
- Rendering knows only bold and regular: **values ≥ 600 draw bold, everything else regular**; there are no intermediate weights.

```css
TyTitleBar { font-weight: 700; }
```

### 5.11 `opacity` — whole-control opacity

```
opacity: <0..1 decimal> ;
```

Applies uniformly to the **control's entire drawn output** (text included). Its usual home is the disabled state:

```css
TyButton:disabled { opacity: 0.5; }
```

Opacity takes effect through the shared framework paint path (DrawFrame). In v1.1 the render paths of `TyCheckBox` and
`TyRadioButton` were changed so `opacity` and `shadow` work there too; all typeKeys (including `TyLabel`) now support it.

### 5.12 `shadow` — drop shadow

```
shadow: <x-offset> <y-offset> <blur-radius> <color> ;
```

- Four space-separated parts in fixed order: X offset, Y offset, blur radius (all logical pixels; offsets may be negative), color;
- **The color must be a single token**: `#hex` (preferably `#rrggbbaa` with alpha), `var(--x)`, or bare `--x`.
  Because the value splits on spaces, **color functions containing commas** (`alpha(...)`, `mix(...)`, etc.) cannot be used;
  for translucency write hex-alpha directly;
- A color with alpha 0 draws no shadow;
- Shadows also go through the DrawFrame path and **have no effect on `TyCheckBox` / `TyRadioButton`**.

```css
TyButton { shadow: 0px 2px 4px #0000002E; }
TyPanel  { shadow: 0px 1px 3px var(--shadow-color); }
```

### 5.13 `outline` / `outline-offset` — focus ring

```
outline: <width> <color> ;
outline-offset: <length> ;
```

Draws a focus indicator ring inside the control. TyControls controls are fully self-drawn and their output is clipped to the
control rectangle, so the focus ring always shifts **inward** rather than expanding outward.

- `outline: <width> <color>`: width first (starts with a digit), color second (a color expression).
  Independent of `border`; affects neither layout nor `padding`. Setting this property adds `tpOutline` to the `Present` set;
- `outline-offset: <length>`: how far the ring is inset from the control's outer edge; default `0` (hugging the edge).
  `outline-offset` alone does **not** set `tpOutline`; the ring draws only when an `outline` rule is also present;
- `outline: 0` disables the ring in a specific rule (the engine handles only the `outline` shorthand and `outline-offset`; an `outline-width` property is not recognized and is silently ignored);
- The ring's corners follow the four-corner `border-radius` (each corner reduced by `outline-offset` and clamped to a minimum of 0).

Usually written inside a `:focus` rule, referencing the `--focus-ring` semantic token:

```css
TyButton:focus { outline: 2px var(--focus-ring); }
TyEdit:focus   { border-color: var(--accent); outline: 2px var(--focus-ring); outline-offset: 2px; }
```

### 5.14 `--focus-ring` — the focus ring color token

This is not a property name but a **semantic variable** the built-in themes define in `:root`:

```css
:root {
  --focus-ring: var(--accent);
}
```

Every built-in theme (`light.tycss`, `dark.tycss`, and the rest) defines `--focus-ring` in `:root` and draws the focus ring
with `outline: 2px var(--focus-ring)` in the `:focus` rules of all focusable controls.

Theme authors can customize it as follows:

| Goal | How |
|---|---|
| Change the focus ring color | `:root { --focus-ring: #FF8800; }` |
| Disable focus rings globally | write `outline: 0;` in each `:focus` rule, or omit `outline` |
| Disable the ring for one control | `TyEdit:focus { outline: 0; }` |
| Return to square focus rings | write `border-radius: 0;` on the control |

---

## 6. Color Function Reference

A color expression is `#hex` | `var(--x)` | bare `--x` | `rgb(...)` / `rgba(...)` | one of the functions below (whose color
arguments are themselves color expressions, **nested to any depth**). Function names are case-insensitive. The `%` suffix on
percentage arguments is optional (`8%` equals `8`); **the one exception is `alpha`, see below**.

Every position that accepts a color (`color`, `background` / `background-color`, `border-color`, the `border:` shorthand,
color function arguments, and so on) accepts all of these forms.

### 6.1 `lighten(<color>, <percentage 0..100>)`

Lightens toward white: per channel `ch + (255 − ch) × p/100`; **alpha is unchanged**.

```css
TyButton.primary:hover { background: lighten(--accent, 8%); }
```

### 6.2 `darken(<color>, <percentage 0..100>)`

Darkens toward black: per channel `ch × (1 − p/100)`; **alpha is unchanged**.

```css
TyButton:active { background: darken(--surface, 10%); }
```

### 6.3 `alpha(<color>, <opacity 0..1>)`

**Replaces** the color's alpha with the given value (RGB unchanged); `0` fully transparent, `1` opaque.

> **Trap**: the second argument is a 0..1 decimal, **not a percentage**. The engine strips a `%` suffix but
> **does not divide by 100**: `alpha(#fff, 50%)` equals `alpha(#fff, 50)`, which clamps to fully opaque.
> Always write a decimal: `alpha(#FFFFFF, 0.18)`.

```css
TyCaptionButton:hover { background: alpha(#FFFFFF, 0.18); }
TyLabel { background: alpha(#FFFFFF, 0); }   /* transparent background */
```

### 6.4 `mix(<color1>, <color2>, <percentage 0..100>)`

Linear blend; the percentage is the **share of the second color**: `result = color1 × (1−p/100) + color2 × p/100`.
All four channels (RGB and alpha) participate.

```css
:root { --tint: mix(--surface, --accent, 20%); }   /* 80% surface + 20% accent */
```

### 6.5 `rgb(<r>, <g>, <b>)` / `rgba(<r>, <g>, <b>, <a>)`

Builds a color from RGB components. `r` / `g` / `b` are integers 0..255; the fourth `rgba` argument `a` is the opacity,
written either as a 0..1 decimal or as a percentage with `%` (`0.6` equals `60%`).
`rgb(...)` equals `rgba(...)` with alpha 1. Usable anywhere a color is accepted (including `border:` and `background`).

```css
TyEdit  { background-color: rgb(255, 255, 255); }
TyLabel { color: rgba(0, 0, 0, 0.6); }          /* 60% opaque black */
TyButton { border: 2px solid rgb(59, 130, 246); }
```

### 6.6 Nesting and variables

```css
TyButton:hover {
  background: lighten(mix(--surface, var(--accent), 15%), 4%);
}
```

---

## 7. Linear Gradients

```
background: linear-gradient(<angle>deg, <stop1>, <stop2>[, …<stopN>]) ;
```

- **The angle must be the first argument** (angle-first); the `deg` suffix is optional and the angle may have decimals;
- It is followed by **2 or more color stops** (multi-stop since v3, for gloss effects and the like); fewer than 2 raises;
- Each stop is `color [position]`: the color is a full color expression (functions and variables allowed; internal commas
  do not mis-split), the position an optional percentage or 0..1 number (e.g. `#fff 0%`, `var(--accent) 50%`);
- Positions normalize by the CSS rules: a missing first position becomes `0`, a missing last becomes `1`, missing middles
  interpolate **evenly** between the neighboring positioned stops, and positions are forced **non-decreasing**
  (a smaller position is clamped up to its predecessor);
- Keyword directions such as `to right` are not supported (direction comes from the angle alone; see 7.1).

A multi-stop example (classic glass gloss: bright top band):

```css
TyButton.primary {
  background: linear-gradient(90deg, #FFFFFF 0%, #EAEAEA 48%, #DADADA 52%, #EDEDED 100%);
}
```

### 7.1 Angle direction (differs from CSS!)

The gradient axis passes through the control's center. Direction is a mathematical angle in **screen coordinates**
(x right, y down): `dx = cos θ, dy = sin θ`, with the start color at the endpoint opposite the angle:

| Angle | Direction (start color → end color) |
|---|---|
| `0deg` | left → right |
| `90deg` | **top → bottom** |
| `180deg` | right → left |
| `270deg` | bottom → top |

This **disagrees** with the browser CSS convention (`0deg` up, `90deg` right).
The `linear-gradient(90deg, …)` seen throughout the built-in showcase theme is a **top-to-bottom** gradient:

```css
TyButton.primary {
  background: linear-gradient(90deg, lighten(--accent, 10%), var(--accent));
  /* lighter at the top, accent at the bottom */
}
```

Gradient endpoints sit where the gradient axis crosses the control's bounding box; the gradient fills the whole control rectangle.

---

## 8. typeKeys and the Built-in Variant List

The type name in a selector is the typeKey returned by the control's `GetStyleTypeKey` (sub-part typeKeys included).

This section is the theme author's **authoritative key table**. Every entry is taken from `themes/light.tycss`, the single
source of truth; `source/tyControls.DefaultTheme.pas` (the built-in base layer compiled into the library) is generated from
it and kept in byte-for-byte sync.

Current scale:

| | Count |
|---|---|
| typeKeys defined in `light.tycss` | **183** |
| Keys controls resolve but the base layer **deliberately leaves undefined** (§8.4) | 8 |
| Dead keys defined in themes but **resolved by no code at all** (§8.6) | 3 |

> **The big change in v3.** Previously 51 controls resolved **another control's** typeKey, leaving them unreachable from the
> theme layer (commits `b824a49`, `d58eada`). Each of these controls now has its own key, added as a **parallel selector** to
> the original donor's rule block, so under the built-in themes not a pixel moves, yet each one is now an independently
> skinnable hook. **Existing third-party `.tycss` files must add the new selectors**; the next subsection explains why.

### 8.1 The rule that matters most: the base layer is whole-key replacement, not a per-property cascade

The default `ResolveStyle` behavior (with `PropertyCascade` off) is **all-or-nothing per typeKey**:

- The theme has **no rule whatsoever** for a typeKey → the whole key falls back to the built-in light base layer;
- The theme has **any single rule** for that typeKey (base, variant, or state, any one is enough) → the built-in layer is
  disabled for the key **entirely**; properties the theme did not write do **not** leak through.

The test is `TTyStyleModel.UserHasTypeKey`, which looks only at the **key name**, never at which properties you covered.

This rule is the top upgrade trap and the single most important thing this section has to say:

> **Splitting keys means your theme now has keys it never wrote.**
> One rule, `TyGauge { background: url(...) }`, used to govern fourteen gauge controls at once. Now `TTyMeter` resolves
> `TyMeter`, a name your theme never mentions, so `TyMeter` falls back to the built-in light values **as a whole key**.
> On an image skin that shows up as an opaque gray box in the middle of the photo.
> **If you ever skinned `TyGauge`, you must now name `TyMeter`, `TyRating`, `TyDial`, and the rest alongside it.**

The built-in themes handle this with **parallel selectors**; third-party themes should copy the pattern:

```css
/* one rule, eighteen separately overridable names */
TyGauge, TyMeter, TyLevelMeter, TyDial, TyGearDial, TyAnalogClock, TyCircularProgress,
TyActivityIndicator, TyActivityBar, TyGearActivityIndicator, TySparkline, TyRating,
TyLColorPicker, TyHSColorPicker, TyMeterTick, TyAnalogClockHand, TyGearDialTeeth, TyColorArea {
  background: var(--surface-sunk);
  border-color: var(--border);
}
```

To audit: the alias guard in `tests/test.themes.pas` compares each new key against the donor key it was split from, entry by
entry, and covers every stylesheet under `themes/` and `examples/theming/`. Home-grown themes can run the same self-check.

### 8.2 How to read the tables

- **What it paints** — which pixels the key owns on the control. "Text ink" means only `color` is read from the key,
  "`background`" means only the background is read; no such note means the whole box-model property set applies.
- **Resolved by** — the control class that resolves the key. One key may be resolved by several controls
  (sharing is intentional; see §8.5).
- **States / variants** — the pseudo-classes and `.variants` **the built-in light theme actually writes**.
  Absence does not mean the control never reports the state: any key can take `:hover`/`:active`/`:focus`/`:disabled`/`:selected`,
  and the rule matches whenever the control reports that state on repaint (§4.3). Conversely, a few keys resolve with an
  **empty state set** (e.g. `TyLinkLabelLink`), making their pseudo-class selectors **dead**; the tables call these out.

#### 8.2.1 Forms and window chrome

| typeKey | What it paints | Resolved by | States / variants |
|---|---|---|---|
| `TyForm` | Form background; written into the form's `Color` via `ApplyChromeTheme`. Built-in `background: var(--form-bg)`, slightly darker than content surfaces | `TTyForm` | — |
| `TyFormSurface` | **Deliberately undefined** (§8.4) | `TTyFormSurface` | — |
| `TyTitleBar` | The self-drawn title bar strip (shares one rule block with `TyRibbonQuickAccess`) | `TTyTitleBar` | — |
| `TyCaptionButton` | Title bar system buttons | `TTyCaptionButton` | `:hover` `:active`; variants `.close` (`:hover`/`:active`), `.min` (`:hover`), `.max` (`:hover`) |

#### 8.2.2 The button family

The following six keys **share one rule block** with byte-identical values, each overridable separately:

| typeKey | What it paints | Resolved by |
|---|---|---|
| `TyButton` | Regular button frame + text | `TTyButton` (and descendants that do not override the key: `TTyGlyphButton`, `TTyColorButton`, `TTyDropDownButton`, `TTyMenuButton`, `TTyTransferArrowButton`) |
| `TySpeedButton` | Toolbar speed buttons | `TTySpeedButton` |
| `TyGlyphContainerButton` | Buttons with a glyph container | `TTyGlyphContainerButton` |
| `TyRibbonAppMenu` | The application menu button at the ribbon's top-left | `TTyRibbonAppMenu` |
| `TyButtonGroup` | The outer frame of a segmented button group | `TTyButtonGroup` |
| `TyUpDown` | Up-down spinner frame, center seam, and arrow ink | `TTyUpDown` |

States: `:hover` `:focus` `:active` `:disabled`.
Variants: `.primary` (`:hover`/`:active`), `.danger` (`:hover`/`:active`),
`.ghost` (transparent at rest; full set of `:hover`/`:active`/`:selected`/`:focus`/`:disabled`).

One more family member sits in a block of its own:

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyBadge` | The numeric badge capsule at a button's top-right | `TTyBadge`, `TTyButton` | none |

#### 8.2.3 Text and static labels

The following seven keys share one rule block (transparent background + `--on-surface` ink + base font size):

| typeKey | What it paints | Resolved by |
|---|---|---|
| `TyLabel` | Static caption text | `TTyLabel` |
| `TyHtmlLabel` | Rich text block (drawn run by run, underline/strikethrough bands) | `TTyHtmlLabel` |
| `TyLinkLabel` | The link label's **box** (font/content, not the link ink) | `TTyLinkLabel` |
| `TyShadowLabel` | Text with a drop shadow | `TTyShadowLabel` |
| `TyGlowLabel` | Text with a glow | `TTyGlowLabel` |
| `TyDivider` | Divider line and its embedded caption | `TTyDivider` |
| `TyCharImage` | Glyph / icon character block | `TTyCharImage` |

States: `:disabled` only (`opacity`).

| typeKey | What it paints | Resolved by | Note |
|---|---|---|---|
| `TyLinkLabelLink` | Link ink, reads `color` only | `TTyLinkLabel` | Resolves with an **empty state set**; `TyLinkLabelLink:hover` / `:disabled` are **dead selectors**; the hover color is synthesized in code via `TyLighten(col, 15)` |

> The `<a>` ink inside `TTyHtmlLabel` goes through **no typeKey at all**: `RenderTo` calls
> `ResolveOverride('color: var(--accent);')` directly, pinning it to `--accent`. The only way to change it is to change
> `--accent`. `TyHtmlLabelLink` is a deferred item and **does not exist** (§8.4).

#### 8.2.4 Input fields

| typeKey | What it paints | Resolved by | States / variants |
|---|---|---|---|
| `TyEdit` | Single-line input | `TTyEdit` and descendants that do not override the key (`TTyMaskEdit`/`TTyCurrencyEdit`/`TTyURLEdit`/`TTyNumericEdit`/`TTyCalcEdit`/`TTyValueEdit`/`TTyComboEdit`/`TTyTrackEdit`); the display strip of `TTyCalculator` also resolves it explicitly | `:hover` `:focus` `:disabled` |
| `TySpinEdit` | Numeric spinner input | `TTySpinEdit` | `:hover` `:focus` `:disabled` |
| `TyMemo` | Multi-line text box | `TTyMemo` | `:hover` `:focus` `:disabled` |
| `TyComboBox` | Dropdown field (the dropdown arrow uses `color`) | `TTyComboBox` and its 11 descendants; `TTyTreeSelect` shares it deliberately (§8.5) | `:hover` `:focus` `:disabled` |
| `TyCascader` | Cascading select field | `TTyCascader` | `:hover` `:focus` `:disabled` |
| `TyDateTimePicker` | Date-time field | `TTyDateTimePicker` | `:hover` `:focus` `:disabled` |
| `TyTextSelection` | Text selection highlight band, reads `background` only | `TTyEdit` / `TTyMemo` / `TTyDateTimePicker` | none |
| `TyTextHint` | Placeholder / hint text, reads `color` only | `TTyEdit` / `TTyTreeSelect` | none |

#### 8.2.5 Checks, switches, sliders, progress

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyCheckBox` | The check box square (the control itself is transparent) | `TTyCheckBox`, `TTyCheckListBox`, `TTyDateTimePicker` | `:hover` `:active` `:focus` `:disabled` |
| `TyRadioButton` | The radio circle | `TTyRadioButton` | `:hover` `:active` `:focus` `:disabled` |
| `TyToggleSwitch` | The switch track (`:active` is added while `Checked=True`) | `TTyToggleSwitch` | `:hover` `:active` `:focus` `:disabled` |
| `TyToggleKnob` | The switch knob (a tier-a colored surface) | `TTyToggleSwitch` | none |
| `TyTrackBar` | Slider track | `TTyTrackBar` | `:focus` `:disabled` |
| `TyTrackThumb` | Slider thumb (tier-a) | `TTyTrackBar`, `TTyTrackEdit` | `:hover` `:active` |
| `TyProgressBar` | Progress bar track | `TTyProgressBar` | `:disabled` |
| `TyProgressFill` | Progress fill segment (tier-a); only the leading corners are rounded while partially filled | `TTyProgressBar` | none |

#### 8.2.6 Containers and panels

The following seventeen keys **share one rule block** (surface color + 1px border + `--radius` + `--pad-container`).
Every one of them except `TyPanel` used to be reachable only by editing `TyPanel`, which meant touching every container
in the application:

| typeKey | What it paints | Resolved by |
|---|---|---|
| `TyPanel` | General-purpose container panel | `TTyPanel`; `TTyRelativePanel` / `TTyPaintPanel` share it deliberately (§8.5) |
| `TyScrollBox` | The scroll **well** (by convention sunk below panels) | `TTyScrollBox`; `TTyScrollPanel` inherits |
| `TyScrollContent` | The scroll container's **viewport** (the windowed child that clips the content). **Paints `background` only, no border** (the frame belongs to the outer scroll box). This key **must have a value and must be opaque**: the control paints nothing but this fill, and an unresolvable key exposes the host's unthemed erase color (on gradient skins such as aero in dark mode, a **bright patch**) | `TTyScrollContent` (the viewport of `TTyScrollBox` / `TTyScrollPanel`) |
| `TyExPanel` | The collapsible card's frame (its `padding.right` also sets the header's right inset) | `TTyExPanel` |
| `TyChart` | Chart frame, title, legend, tick labels, both axes, and grid lines | `TTyChart` |
| `TyCalculator` | Calculator backplate (the display strip resolves `TyEdit`; the keys are real `TTyButton`s) | `TTyCalculator` |
| `TyBevel` | Raised/sunken decorative line (draws only the highlight and shadow tracks, no face) | `TTyBevel` |
| `TySizeBox` | The resize grip in the bottom-right corner | `TTySizeBox` |
| `TyControlBar` | Dockable toolbar container and its decorative grippers | `TTyControlBar` |
| `TyCoolBar` | Draggable banded toolbar (grippers are interactive) | `TTyCoolBar` |
| `TyColorGrid` | Color swatch matrix and selection ring | `TTyColorGrid` |
| `TyShape` | Vector primitives (ellipse/rectangle/triangle/line) | `TTyShape` |
| `TyStarShape` | Star primitive | `TTyStarShape` |
| `TyArrow` | Arrow primitive | `TTyArrow` |
| `TyImageView` | The **letterbox backing** behind a zoomed/panned image | `TTyImageView` |
| `TyImage` | Image box (framed only when `Transparent=False`) | `TTyImage` |
| `TyPreviewBox` | The file dialog's preview well + empty-state hint text | `TTyPreviewBox` |
| `TyListGroupPanel` | The navigation accordion's **sidebar backing** | `TTyListGroupPanel` |

This block has **no state rules**. To fade a disabled image you must write
`TyImage:disabled { opacity: 0.5; }` yourself; the built-in theme declares no state rules for this family.

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyExPanelHeader` | The collapsible panel's header band: arrow + caption ink and font; `background` **is optional** (declared: fills the band; undeclared: the panel surface shows through) | `TTyExPanel` | `:hover` (hover within the band; not in the built-in theme, works as soon as you write it) |
| `TyGroupBox` | Group box (**must declare `background`**, used to mask the border line behind the caption) | `TTyGroupBox`, `TTyRadioGroup`, `TTyCheckGroup`; the group caption bands of `TTyOfficeListBox`/`TTyOfficeComboBox` also resolve it | — |
| `TyToolGroupPanel` | Ribbon-style command cluster (shares a block with `TyGroupBox`) | `TTyToolGroupPanel` | — |
| `TyGridPanel` | **Deliberately undefined** (§8.4) | `TTyGridPanel` | — |

#### 8.2.7 Scroll bars, splitters, status bar, toolbars

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyScrollBar` | Scroll bar track background; end arrow ink uses `color` (tier-b) | `TTyScrollBar` | `:hover` `:active` `:focus` `:disabled` |
| `TyScrollThumb` | The thumb's own fill and radius (tier-a) | `TTyScrollBar` | `:hover` `:active` |
| `TySplitter` | Splitter bar (built-in `background: none`, gripper ink only) | `TTySplitter` | `:hover` |
| `TyStatusBar` | Status bar strip | `TTyStatusBar` | — |
| `TyToolBar` | Toolbar strip | `TTyToolBar`, `TTyToolBarEx` | — |
| `TyToolSeparator` | Toolbar separator: `border-color` draws the line, `background` blends it into the strip (shares a block with `TyToolBar`) | `TTyToolSeparator` | — |

#### 8.2.8 The list box family

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyListBox` | List frame | `TTyListBox` and 14 descendants that do not override the key; the dropdown bodies of `TTyComboBox`/`TTyValueListEditor`, `TTyPopupSurface`, and `TTyGalleryGrid` (the gallery popup grid) also resolve it | `:hover` `:focus` `:disabled` |
| `TyValueListEditor` | Property grid frame (shares a block with `TyListBox`) | `TTyValueListEditor` | `:hover` `:focus` `:disabled` |
| `TyRibbonGallery` | The ribbon gallery's in-ribbon row frame (shares a block with `TyListBox`) | `TTyRibbonGallery` | `:hover` `:focus` `:disabled` |
| `TyListItem` | A single row: `background` sets the row fill, `color` the text | `TTyListBox`; the tiles of `TTyRibbonGallery` still resolve it too | `:hover` `:active` (= the selected row) |
| `TyValueListEditorRow` | One property grid row (shares a block with `TyListItem`) | `TTyValueListEditor` | `:hover` `:active` |

`TyValueListEditorKey` / `-Value` / `-Divider` / `-Expander` are resolved by code but **deliberately undefined** in the base layer; see §8.4.

#### 8.2.9 Trees, list views, column headers

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyTreeView` | Tree frame (shares a block with `TyListView`) | `TTyTreeView`; `TTyShellTreeView` and the dropdown tree of `TTyTreeSelect` inherit | — |
| `TyListView` | List view frame | `TTyListView`; `TTyShellListView` inherits | — |
| `TyTreeNode` | One tree node row | `TTyTreeView` | `:hover` `:selected` `:disabled` |
| `TyListViewItem` | One list view item (shares a block with `TyTreeNode`) | `TTyListView` | `:hover` `:selected` `:disabled` |
| `TyTreeHeader` | The tree's column header **band** (drawn inside its own frame, no border) | `TTyTreeView` | — |
| `TyListViewHeader` | The list view's column header band | `TTyListView` | — |
| `TyListViewGroupHeader` | The list view's **group** band (previously shared the header band's key and could not be styled apart) | `TTyListView` | — |
| `TyHeaderControl` | Standalone header strip: it **is** the frame, so `border-radius`/`shadow` are meaningful here (shares a block with the three above) | `TTyHeaderControl` | — |
| `TyTreeHeaderSection` | One column header cell | `TTyTreeView`; `TTyHeaderControl` **still shares it** (its own section key is deferred) | `:hover` `:selected` |
| `TyListViewHeaderSection` | The list view's column header cell (shares a block with the above) | `TTyListView` | `:hover` `:selected` |
| `TyTreeCheckBox` | Tree node check box | `TTyTreeView` | `:active` `:selected` `:disabled` |
| `TyListViewCheckBox` | List view check box (shares a block with the above) | `TTyListView` | `:active` `:selected` `:disabled` |

`TyListViewLine` / `TyListViewMarquee` are resolved by code but **deliberately undefined** in the base layer; see §8.4.

#### 8.2.10 The data grid `TTyGrid`

The grid has a complete key set of its own and **borrows nothing from the tree/list keys**. The base layer defines the full
set, so a new skin renders correctly without a single grid rule. `TTyDrawGrid` / `TTyStringGrid` deliberately share `TyGrid`
(§8.5). Every grid resolve carries the control's `StyleClass`, so `.variants` work **on the sub-part keys too**;
ListView / ValueListEditor do not do this.

| typeKey | What it paints | States |
|---|---|---|
| `TyGrid` | Grid frame | — |
| `TyGridCell` | Body cell (built-in `background: none`, letting the surface show through) | `:hover` `:selected` |
| `TyGridCellSelectedInactive` | The selection while unfocused (`HideSelectionWhenInactive`) | — |
| `TyGridActiveCell` | The focused cell (marks the cursor cell in whole-row selection mode) | — |
| `TyGridCellMarked` | The translucent layer when the selection covers a **user-colored** cell | — |
| `TyGridSelectionFrame` | Selection frame + bottom-right fill handle (`color` = the handle's stroke) | — |
| `TyGridCellAlt` | Zebra-stripe alternate row fill | — |
| `TyGridFixed` | Frozen rows/columns area | — |
| `TyGridIndicator` | Row header slot | — |
| `TyGridHeader` | Column header band | — |
| `TyGridHeaderSection` | One column header cell | `:hover` `:selected` `:active` |
| `TyGridHeaderGroup` | Grouped header band (an upper caption spanning several columns) | — |
| `TyGridFilterRow` | The inline filter row (fill follows the surface, border follows inputs, signaling "you can type here") | — |
| `TyGridGroupRow` | Group band. The built-in `background: none` **is the intended current look**; declare a chrome fill yourself if you want one | — |
| `TyGridSummaryRow` | Summary/footer band. **Deliberately has no `border-color`**: `RenderFooter` never reads it, so writing one is a dead property | — |
| `TyGridLine` | Grid lines, reads `background` only; set it transparent to remove the lines | — |
| `TyGridCheckBox` | Check box cell | `:selected` |
| `TyGridHyperlink` | Hyperlink cell ink | — |
| `TyGridCommentMark` | Comment corner mark ink | — |
| `TyGridProgress` | Progress cell track | — |
| `TyGridProgressFill` | Progress cell fill | — |
| `TyGridRating` | The rating cell's filled star | — |
| `TyGridRatingEmpty` | The rating cell's hollow star | — |
| `TyGridButton` | Button cell (its own key, so styling grid buttons does not ripple into every button in the library) | `:hover` `:active` |

> **Name collision warning: two unrelated things claim `TyGridCell`.**
> Besides the data grid's body cell, the layout cell `TTyGridCell` of `TTyGridPanel` also returns `'TyGridCell'` from
> `GetStyleTypeKey`. The latter's `Paint` **draws nothing**, so there is no visible conflict today; but it is not an
> independently addressable hook, and a `TyGridCell` rule written for the data grid nominally covers it too.

#### 8.2.11 The tab family

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyPageControl` | The multi-page control's page container frame | `TTyPageControl` | `:hover` `:focus` `:disabled` |
| `TyTabSheet` | The page body: an opaque surface fill only, **no border**, so the OS form background cannot show through | `TTyTabSheet` | — |
| `TyTabSet` | A tab strip with **no page body** | `TTyTabSet` | `:hover` `:focus` `:disabled` |
| `TyTab` | A single tab header (`:active` here means **selected**, not pressed) | The tab strip engine (`TTyPageControl` / `TTyTabSet`); ribbon tab headers resolve it too | `:hover` `:active` |
| `TyTabClose` | The rounded backdrop behind a hovered close × (the × stroke itself uses `TyTab`'s `color`, tier-b) | The tab strip engine | none |

> Because `HasPageBody = False`, `TyTabSet` **skips `DrawFrame`** and draws only a baseline rail, so it actually consumes
> just `border-color` and `border-width`; writing `background` / `border-radius` / `shadow` draws nothing.
> A dedicated `TyTabSetRail` is deferred and does not exist (§8.4).

#### 8.2.12 Menus

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyMenuBar` | The application menu bar at the top | `TTyMenuBar` | — |
| `TyMenuView` | The dropdown/context popup body | `TTyMenuView` | — |
| `TyMenuPopup` | The popup host (a mirror key holding the same values as `TyMenuView`) | `TTyMenuView` | — |
| `TyMenuItem` | One menu row / menu bar cell; the base-state `border-color` is the separator ink | `TTyMenuBar` / `TTyMenuView` | `:hover` `:active` `:disabled` |

#### 8.2.13 Calendar and dates

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyCalendar` | Calendar frame | `TTyCalendar`, the dropdown calendar of `TTyDateTimePicker` | — |
| `TyCalendarTitle` | The month/year title at the top (bold) | `TTyCalendar` | `:hover` |
| `TyCalendarWeekday` | The weekday header row (muted ink) | `TTyCalendar` | — |
| `TyCalendarCell` | One date cell | `TTyCalendar` | `:hover` `:selected` `:disabled` |
| `TyDateTimePicker` | See §8.2.4 | `TTyDateTimePicker` | `:hover` `:focus` `:disabled` |

#### 8.2.14 The ribbon family

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyRibbon` | The command ribbon surface | `TTyRibbon`; `TTyRibbonPage` shares it deliberately (§8.5); it is also the default `StyleKey` of `TTyPopupSurface` | — |
| `TyRibbonGroup` | The captioned command group box | `TTyRibbonGroup` | — |
| `TyRibbonBackstage` | The backstage view's **content pane** (shares a block with `TyRibbon`) | `TTyRibbonBackstage` | — |
| `TyRibbonQuickAccess` | The quick access strip (shares a block with `TyTitleBar`) | `TTyRibbonQuickAccess` | — |
| `TyRibbonAppMenu` | See §8.2.2 | `TTyRibbonAppMenu` | same as the button family |
| `TyRibbonGallery` | See §8.2.8 | `TTyRibbonGallery` | `:hover` `:focus` `:disabled` |

> **Two places still borrow; that is deferral, not design.** The backstage view's **sidebar and command rows** resolve
> `ResolveStyle('TyButton', 'primary')` (with `:hover`/`:active`), so the sidebar can only be the primary button color;
> the gallery's **tiles** still resolve `TyListItem`, and its popup grid still resolves `TyListBox`.
> `TyRibbonBackstageSidebar` / `-Item` / `-Back` / `-Separator`, `TyRibbonGalleryItem` /
> `TyRibbonGalleryPopup` all **do not exist** (§8.4).
>
> Also: the name `TyRibbonTab` **has never been used**; ribbon tab headers resolve `TyTab`.
> Earlier documentation listed it as "reserved"; that reservation is gone. Do not write rules for it.

#### 8.2.15 Gauges and indicators

Previously **fourteen** unrelated controls all hard-returned `TyGauge` and all resolved the same `TyGaugeFill`, so a star
rating, an analog clock's second hand, and a progress ring were the same color **by construction**. Each now has its own
key; they share one rule block.

**Faces / backing** (one block with `TyGauge`: sunken fill + border):

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TyGauge` | Gauge face (this family's **definer**, not a borrower) | `TTyGauge` | `:disabled` |
| `TyMeter` | Meter reading area and text | `TTyMeter` | `:disabled` |
| `TyLevelMeter` | Level meter track | `TTyLevelMeter` | `:disabled` |
| `TyDial` | Dial face | `TTyDial` | `:disabled` |
| `TyGearDial` | Gear dial face | `TTyGearDial` | `:disabled` |
| `TyAnalogClock` | Clock face and ticks (`color`) | `TTyAnalogClock` | `:disabled` |
| `TyCircularProgress` | The circular progress track ring | `TTyCircularProgress` | `:disabled` |
| `TyActivityIndicator` | The busy indicator's track ring | `TTyActivityIndicator` | `:disabled` |
| `TyActivityBar` | The marquee progress bar's track frame | `TTyActivityBar` | `:disabled` |
| `TyGearActivityIndicator` | The gear busy indicator's **punched hole** (role reversed from the gauges: this paints the hole, not the track) | `TTyGearActivityIndicator` | `:disabled` |
| `TySparkline` | Sparkline backing | `TTySparkline` | `:disabled` |
| `TyRating` | Rating control backing | `TTyRating` | `:disabled` |
| `TyLColorPicker` | The lightness bar's frame and cursor (the bar body is HSV-generated pixels, no sub-part key) | `TTyLColorPicker` | `:disabled` |
| `TyHSColorPicker` | The hue/saturation square's frame and crosshair cursor | `TTyHSColorPicker` | `:disabled` |
| `TyMeterTick` | Meter ticks, reads `color` only | `TTyMeter` | empty state set |
| `TyAnalogClockHand` | Hour + minute hands, reads `color` only | `TTyAnalogClock` | empty state set |
| `TyGearDialTeeth` | Gear teeth, reads `background` only | `TTyGearDial` | empty state set |
| `TyColorArea` | The color dialog's HSV square / hue bar frame and cursor | `TTyHSVSquare` / `TTyHueBar` | empty state set |

**Lit parts** (one block with `TyGaugeFill`: `background: var(--accent)`):

| typeKey | What it paints | Resolved by |
|---|---|---|
| `TyGaugeFill` | Gauge fill. **The only sub-part key resolved with a hard-coded literal** (`ResolveStyle('TyGaugeFill', …)`); all the others are `GetStyleTypeKey + 'suffix'` | `TTyGauge` |
| `TyMeterNeedle` | Meter needle | `TTyMeter` |
| `TyLevelMeterFill` | The level bar | `TTyLevelMeter` |
| `TyLevelMeterPeak` | The peak marker line. **Give it a contrasting color**; it used to be the same color as the bar it marks | `TTyLevelMeter` |
| `TyDialPointer` | Dial pointer | `TTyDial` |
| `TyGearDialPointer` | Gear dial pointer | `TTyGearDial` |
| `TyAnalogClockSecondHand` | Second hand + center hub | `TTyAnalogClock` |
| `TyCircularProgressFill` | The circular progress arc | `TTyCircularProgress` |
| `TyActivityIndicatorFill` | The spinning arc | `TTyActivityIndicator` |
| `TyActivityBarFill` | The traveling block | `TTyActivityBar` |
| `TyGearActivityIndicatorFill` | Teeth and disc body | `TTyGearActivityIndicator` |
| `TySparklineFill` | The polyline | `TTySparkline` |
| `TySparklineDot` | The polyline endpoints | `TTySparkline` |
| `TyRatingStar` | The star shape | `TTyRating` |

> `TyRatingStar` is the family's only key with a **new state axis**: during preview hover it resolves **with `:hover`**
> (`Rating.pas`), and the built-in theme **deliberately omits** `TyRatingStar:hover` so pixels stay put;
> a skin adds that one rule to color the preview.
>
> `:disabled { opacity }` is a **no-op on most of this family**: `Opacity` is applied only inside `DrawFrame`, and of this
> family only ActivityBar, LevelMeter, Sparkline, and the **linear** style of `TTyGauge` go through `DrawFrame`. The tables
> above faithfully list the `:disabled` rules the theme writes, but most of them render no effect today.

#### 8.2.16 Cards, tags, alerts, overlays

| typeKey | What it paints | Resolved by | States / variants |
|---|---|---|---|
| `TyCard` | Card surface (header/footer are bands painted on it) | `TTyCard` | `:hover` `:disabled` |
| `TyCardHeader` | Header band: separator line and caption ink only, **no background**, so the card's own surface shows through | `TTyCard` | — |
| `TyCardActions` | The bottom action band's separator line | `TTyCard` | — |
| `TyTag` | Tag capsule | `TTyTag` | `:disabled`; variants `.accent` `.danger` |
| `TyTagClose` | The tag's close × | `TTyTag` | `:hover` |
| `TyAlert` | Inline alert strip | `TTyAlert` | `:disabled`; variants `.info` `.success` `.warning` `.error` (**hard contract**: `AlertType` maps directly onto these four names) |
| `TyAlertClose` | The alert's close × | `TTyAlert` | `:hover` |
| `TyNotification` | Corner overlay notification | `TTyNotification` | `:hover`; variants `.info` `.success` `.warning` `.error` (the variant's `color` is the **icon ink**) |
| `TyNotificationClose` | The notification's close × | `TTyNotification` | `:hover` |
| `TyEmpty` | Empty-state placeholder (transparent, resting on the empty list's own surface) | `TTyEmpty` | `:disabled` |
| `TyEmptyImage` | The empty-state illustration's ink (fainter than body text, hence its own key) | `TTyEmpty` | — |
| `TyHint` | The themed tooltip surface (replacing the native LCL hint) | `TTyHintWindow`, `TTyBalloonHint` | — |
| `TyPopover` | An overlay surface that **hosts controls** (the arrow is cut from the same surface, so it needs no key of its own) | `TTyPopover` | — |
| `TyPopoverTitle` | Popover title | `TTyPopover` | — |
| `TyChartTooltip` | The in-chart hover tooltip. The chart **does not draw this box** unless this key supplies a background | `TTyChart` | — |

#### 8.2.17 Navigation and data entry

| typeKey | What it paints | Resolved by | States |
|---|---|---|---|
| `TySegmented` | The segmented control's trough | `TTySegmented` | `:focus` `:disabled` |
| `TySegmentedItem` | One segment (its radius is **deliberately smaller** than the trough's, reading as "a piece inside the trough") | `TTySegmented` | `:hover` `:selected` `:disabled` |
| `TyPagination` | The pagination strip (transparent; the page numbers themselves are the chrome) | `TTyPagination` | `:disabled` |
| `TyPaginationItem` | One page number cell | `TTyPagination` | `:hover` `:selected` `:disabled` |
| `TySteps` | The steps bar | `TTySteps` | `:disabled` |
| `TyStepsItem` | A step marker. **State is semantics**: completed = no pseudo-class, current = `:selected`, not yet reached = `:disabled`, so the base rule paints the **completed** look | `TTySteps` | `:hover` `:selected` `:disabled` |
| `TyStepsConnector` | The line between steps, reads `background` only (**deliberately declares no `color`**); takes the state of the step it **leads to** | `TTySteps` | `:selected` `:disabled` |
| `TyBreadcrumb` | The breadcrumb strip (separators use the strip's own ink) | `TTyBreadcrumb` | `:disabled` |
| `TyBreadcrumbItem` | One breadcrumb segment; `:selected` = the last segment (the current location, read as plain ink rather than a link) | `TTyBreadcrumb` | `:hover` `:selected` `:disabled` |
| `TyTransfer` | The transfer box frame (the two list faces and the move buttons reuse `TyListBox` / `TyButton`) | `TTyTransfer` | `:disabled` |
| `TyTransferTitle` | The title band on each side of the transfer box | `TTyTransfer` | — |
| `TyCascaderPanel` | The cascading multi-column panel | `TTyCascaderPanel` | — |
| `TyCascaderItem` | One row in the cascader panel | `TTyCascaderPanel` | `:hover` `:selected` `:disabled` |
| `TyListGroupHeader` | The navigation accordion's group row (**no fill**, just muted ink + a right-side arrow; `:selected` = the group is expanded) | `TTyListGroupPanel` | `:hover` `:selected` |
| `TyListGroupItem` | A navigation item; `:active` = selected, drawn as a soft inset rounded pill | `TTyListGroupPanel` | `:hover` `:active` `:disabled` |

> `TTyTreeSelect` has **no key of its own**, and should not: it resolves `TyComboBox` (it is a combo box with a dropdown
> tree), and its popup body is a real `TTyTreeView` colored by `TyTreeView`. Writing `TyTreeSelect { … }` is **dead CSS
> that never matches**.

### 8.3 Variants are not a closed set

Any identifier can be a variant; it matches as soon as the control's `StyleClass` property contains the corresponding token
(space-separated, several allowed). The "variants" columns above list only what **the built-in theme actually defines**:

- The button family's `.primary` / `.danger` / `.ghost`;
- `TyCaptionButton`'s `.close` / `.min` / `.max` (assigned to the three title bar buttons automatically by the form chrome);
- `TyTag`'s `.accent` / `.danger`;
- The `.info` / `.success` / `.warning` / `.error` of `TyAlert` / `TyNotification`:
  these four are a **hard contract**; the control's `AlertType` / `NotificationType` maps directly onto the four names
  and picks the icon accordingly.

Remember §4.4: the variant layer applies **before** the state layer, so a variant's hover must be written `Ty….variant:hover`.

### 8.4 Deliberately undefined keys

Code resolves the following keys, but the base layer **deliberately leaves them undefined**. They are not omissions but
**optional hooks**: each has a well-defined fallback on the paint side, and the fallback is **state-dependent**, so
hard-coding a value here would **move pixels** rather than preserve them. Skins may declare them freely; the base layer
stays silent so the fallbacks keep working.

| typeKey | Resolved by | Why undefined / the fallback |
|---|---|---|
| `TyGridPanel` | `TTyGridPanel` | **A grid layout host is not a slab.** With no themed background, `DrawFrame` takes `TyFillParentBg`, so the gaps between cells take the parent container's color instead of punching a white panel into whatever hosts it. `tests/test.gridpanel.pas` asserts that **no built-in theme** gives this key a background. For a visible grid face, write `TyGridPanel { background: …; border: … }` yourself |
| `TyFormSurface` | `TTyFormSurface` | **It has no CSS of its own.** The surface renders the host form's `form` background (see its `Paint`) and hosts children that resolve their own styles. The point of the neutral key: keep `TyForm`'s padding / border from accidentally applying to the surface's own layout |
| `TyListViewLine` | `TTyListView` | `background` → otherwise the list view frame's `border-color` |
| `TyListViewMarquee` | `TTyListView` | `background` → otherwise the `TyListViewItem:selected` background (hue follows the theme, alpha is a constant) |
| `TyValueListEditorKey` | `TTyValueListEditor` | `color` → otherwise the row color **for the row's current state** |
| `TyValueListEditorValue` | `TTyValueListEditor` | Same as above |
| `TyValueListEditorExpander` | `TTyValueListEditor` | Same as above |
| `TyValueListEditorDivider` | `TTyValueListEditor` | `background` → otherwise the row color at alpha `0x28` |

> **The last four are sharp edges**: the fallback ink on a selected row is `--on-accent`, so a flat
> `color: var(--on-surface)` here makes the key names on selected rows **unreadable**. If you declare them, declare the
> `:active` / `:hover` variants too.

#### Deferred sub-part keys that therefore do not exist

`b824a49` / `d58eada` covered **box keys only**. A batch of **sub-part keys** proposed by the same audit was
**deliberately deferred**: they are an **extension** of skinnability rather than coverage gaps, and several of them
**would move pixels** (the code currently invents a color where the key ought to supply one). Per-key rationale:
[superpowers/plans/2026-07-23-typekey-explicit-borrowers.md](superpowers/plans/2026-07-23-typekey-explicit-borrowers.md).

**Do not write rules for the following names; they match nothing today:**

`TyHtmlLabelLink`, `TyButtonGroupItem`, `TyUpDownButton`,
`TyChartTitle` / `TyChartLegend` / `TyChartAxis` / `TyChartGrid` / `TyChartLabel` / `TyChartSeries1..8`,
`TyCalculatorDisplay` / `TyCalculatorExpression`, `TyBevelHighlight` / `TyBevelShadow`,
`TySizeBoxDot`, `TyControlBarGripper`, `TyCoolBarGripper`, `TyColorGridCell`,
`TyRibbonBackstageSidebar` / `-Item` / `-Back` / `-Separator`,
`TyRibbonGalleryItem` / `TyRibbonGalleryPopup`, `TyTabSetRail`,
`TyHeaderControlSection` / `-SortMark` / `-Divider`.

The corresponding parts of these controls **cannot currently be skinned separately**; they either borrow keys already in
the tables above, or their colors and geometry are Pascal constants.

### 8.5 Deliberately shared keys: borrowing by design, not oversight

About forty controls still share another control's typeKey, and **every case was audited and documented**
(rationale in the plan document above and the two commit messages). The criterion: *should a skin ever be able to treat
them differently?* Do not "fix" them.

| Sharer | Key used | Why sharing is right |
|---|---|---|
| `TTyMaskEdit`, `TTyCurrencyEdit`, `TTyURLEdit`, `TTyNumericEdit`, `TTyCalcEdit`, `TTyCalcCurrencyEdit`, `TTyValueEdit`, `TTyComboEdit` | `TyEdit` | An input with a mask or a calculator dropdown **is** an input. Box, border, padding, and states are all `TyEdit`'s; the differences are input filtering and trailing-button behavior. The shared key is exactly why they sit seamlessly in one form row, and why `TyEdit.small` dresses them all at once |
| `TTyFontComboBox`, `TTyFontSizeComboBox`, `TTyMRUComboBox`, `TTyColorComboBox`, `TTyCheckComboBox`, `TTyComboBoxEx`, 11 in all | `TyComboBox` | Same reasoning; they are all combo box fields |
| `TTyTreeSelect` | `TyComboBox` | The three marks it paints are identical to `TTyComboBox`'s, one for one; the dropdown body is a real `TTyTreeView` colored by `TyTreeView` |
| `TTyRadioGroup`, `TTyCheckGroup` | `TyGroupBox` | A group box is "a captioned frame"; inside it are real controls with keys of their own |
| `TTyShellTreeView` | `TyTreeView` (whole family) | The shell adapter paints not a single pixel itself; a directory tree **is** a tree |
| `TTyShellListView` | `TyListView` (whole family) | Same as above |
| `TTyDrawGrid`, `TTyStringGrid` | `TyGrid` (whole family) | In the three-layer hierarchy only `TTyCustomGrid` paints pixels |
| `TTyRibbonPage` | `TyRibbon` | The page paints a **strict subset** of the ribbon box and deliberately no border; a different color here would expose a 1px ring of ribbon color around every page |
| `TTyRelativePanel` | `TyPanel` | It paints **not one pixel** (no `Paint`, no `RenderTo`); everything comes from `TTyPanel.RenderTo`. It is only a **layout policy**, and a layout policy is not a visual identity a skin needs to distinguish |
| `TTyPaintPanel` | `TyPanel` | Byte-for-byte compatible with a plain panel; it **is** a panel |
| `TTyScrollPanel` | `TyScrollBox` (inherited) | What it adds is **gestures**, not surface; it draws nothing extra, so sharing the scroll well's key is the correct outcome. Note it is **no longer** `TyPanel`; the base class moved |
| `TTyGlyphButton` | `TyButton` | It is a push button with a partitioned content area |
| `TTyGalleryGrid` (the gallery popup grid) | `TyListBox` | See the deferral note in §8.2.14 |
| The **column header cells** of `TTyHeaderControl` | `TyTreeHeaderSection` | See §8.2.9; not yet split, so this one is *not* "by design" |

### 8.6 Dead keys: defined in themes, resolved by no code

The following names are defined in some bundled stylesheets, but `source/` contains **no resolve site** for them.
Rules written for them have no effect. (Coverage is uneven: `TyGridSelection` appears only in `light.tycss`, while
`TyTabControl` and `TyDateTimeButton` each appear in 6 files, so "every theme has them" would be false.)

| typeKey | Situation |
|---|---|
| `TyTabControl` | The class `TTyTabControl` **has been deleted** (commit `d201419`); the key survives only as a parallel selector alongside `TyTabSet` |
| `TyDateTimeButton` | The dropdown button of `TTyDateTimePicker` never resolves it |
| `TyGridSelection` | The grid actually uses `TyGridSelectionFrame` |
| `TyTreeSelect` | `TTyTreeSelect` returns `'TyComboBox'` (intentional sharing, §8.5). Its rule block was removed from `light.tycss` in 3.0, so it is no longer even "defined"; a purely dead name |

### 8.7 The two-tier sub-part coloring convention (tier-a / tier-b)

Small parts inside a control that are not the "control body frame" get their colors by one of two routes, according to
whether the part is an **independent colored surface**. This is the **official convention**, not a legacy gap:

- **tier-a — colored surfaces:** thumbs, knobs, fills, pointers, needles: each is a solid face that needs its own color.
  Each has a **dedicated sub-part typeKey** (`TyScrollThumb`, `TyToggleKnob`,
  `TyTrackThumb`, `TyProgressFill`, plus the fourteen `…Fill` / pointer keys of §8.2.15).
  Color comes from that typeKey's `background`, radius from its `border-radius`,
  independent of the parent control's `background`/`color`. Theme authors can color them (and their `:hover`/`:active`) separately.

- **tier-b — monochrome glyphs:** the check mark / radio dot, ComboBox dropdown arrow,
  SpinEdit up/down arrows, ScrollBar end arrows, tab close ×, and the like are a single **stroke of ink** with no face of
  their own. They **borrow the `color` (`TextColor`) of the owning control's (or sub-part's) style as their ink**. This is
  the official convention, not "each should have had a typeKey and one was forgotten". To recolor such a glyph, set `color`
  on the owning typeKey (e.g. `TyScrollBar { color: … }` recolors the end arrows, `TyTab { color: … }` recolors the close ×).

> An occasional tier-a part carries a tier-b glyph on top: the **backdrop** of a tab's close × is tier-a (`TyTabClose`'s
> `background`), while the **× stroke** on it is tier-b (`TyTab`'s `color`).

---

## 9. Limitations Summary (v1)

Engine-level limitations (each expanded in the sections above):

1. **No combinator selectors**: descendant / child / wildcard / multi-variant / bare-class / bare-state selectors are all unsupported (§4.2).
2. **Duplicate selectors: last one wins**, merged **per property** (§4.4), same as browsers.
   The genuinely counter-intuitive part is the base layer's **all-or-nothing** rule: once a theme mentions a typeKey at all,
   the built-in default layer goes dark for that key **entirely** (§8.1), so newly split keys must each be named.
3. **`url()` paths cannot contain spaces**: spaces are deleted unconditionally when the file name is reassembled (§5.2);
   paths resolve against the process working directory, and missing files are skipped silently.
4. **`shadow` colors must be a single token**: `#hex` / `var(--x)` / bare `--x`; comma-bearing
   color functions are unusable; for translucency use `#rrggbbaa` (§5.12).
5. **`opacity` and `shadow` work on all controls (v1.1)**: v1.1 fixed the render paths of `TyCheckBox` and
   `TyRadioButton` so they too support `opacity` and `shadow`; all typeKeys are covered.
6. **The second `alpha()` argument is a 0..1 decimal**; writing a percent sign does not trigger percentage conversion (§6.3).
7. **Gradient angle directions differ from CSS**: `0deg` left→right, `90deg` top→bottom (§7.1);
   only two-stop linear gradients are supported.
8. **`font-size` numbers are interpreted as pt**; the `px` suffix is decoration (§5.9). `font-weight`
   renders in just two steps: ≥600 bold, everything else regular (§5.10).
9. **Do not quote `font-family`**; the quotes are kept as part of the name (§5.8).
10. **Sub-part coloring splits into tier-a / tier-b (Batch ④)**: colored surfaces such as thumbs / knobs / fills are colored by the `background` of a dedicated sub-part typeKey (`TyScrollThumb`, `TyToggleKnob`, `TyTrackThumb`, `TyProgressFill`); monochrome glyphs such as check marks / arrows / close × borrow the owning control's `color` (`TextColor`) as their ink. Both are official conventions (§8.7). The defaults of `TyScrollThumb` / `TyToggleKnob` are **identical, value for value**, to the earlier `color`-borrowing rendering.
11. **Tab overflow scrolls horizontally (v1.10)**: when the combined width of all tab headers exceeds the control width, the tab strip enters overflow mode and can scroll horizontally: `tgArrowLeft` / `tgArrowRight` arrow buttons render at the strip's two ends, the mouse wheel scrolls over the strip, and switching the selected tab auto-scrolls it into view. While drawing, tab headers are clipped to the visible band between the two arrows (the arrows always draw on top). This strip engine is shared by `TTyPageControl` and `TTyTabSet`; details in [controls/pagecontrol.md](controls/pagecontrol.md).
    (An earlier revision named `TyTabControl` here; that control class has been deleted and the typeKey is now dead, see §8.6.)
12. `@media`, `!important`, escaped strings, and `//` line comments are unsupported.
    `@import` (which must precede all `:root` blocks and rules) and `@mode` **are** supported.
13. **Border / box-model trade-offs (v1.6; 3D bevels added in v3)**: `border-style` supports `none` / `solid` /
    `outset` / `inset` (the latter two are two-color 3D bevels, see 5.4), with **no** `dashed`, `dotted`, `groove`, or
    `ridge`; **there is no `margin` property** (use container layout for outer spacing). The `border` shorthand merely
    combines `border-width` / `border-style` / `border-color` and adds no extra capability.
14. **Unsupported `border-radius` forms**: per-corner longhands (`border-top-left-radius` etc.),
    percentage radii, and the elliptical two-radius syntax (`<a> / <b>`) are all unsupported (§5.6). `outline-offset`
    declared alone does not activate the focus ring; an `outline` declaration must accompany it (§5.13).
15. **Metric tokens (v3)**: themes still **cannot** do general layout (no `width`/`height`/
    `margin`/`gap` properties; control size and placement belong to `.lfm`/LCL), but the **intrinsic geometry** of some
    controls can be tuned with named length tokens in `:root`. Controls read them by name and fall back to built-in
    constants when unset (so goldens do not change):
    - `--checkbox-size` / `--checkbox-gap` — check box indicator side length / gap to the caption (defaults 16 / 6);
    - `--radio-size` / `--radio-gap` — the same for radio buttons (the dot scales proportionally with the box);
    - `--groupbox-caption-height` — the GroupBox top caption band height (default 16).
    - `--line-height` — the line box height (logical px) of **multi-line** captions. **No built-in constant**: when unset,
      the font's own line box is used, so nothing moves until you add the token; once set, the text block is
      `line count × value`, with the extra height split evenly above and below each line. The control's derived
      **minimum height** (text block height + vertical padding) follows along:
      shrink `font-size` and `--line-height` together and the minimum drops with them.
    Values may be `16`, `16px`, or `var()`. (Later versions will promote more hard-coded geometry to metric tokens.)
16. **Glyph override tokens (v3)**: built-in vector glyphs (check marks, radio dots, and so on) can be replaced with icon
    font code points. In `:root` write `--glyph-<slot>: "font family" "\<codepoint>";` where the family must be a font
    **installed on the system or registered by the application** (loading a bundled `.ttf` via `url()` is a future
    extension) and the code point is hexadecimal (the leading `\` is optional). Slots currently supported:
    - `--glyph-check` / `--glyph-check-indeterminate` — check box check mark / indeterminate state;
    - `--glyph-radio` — radio button dot;
    - `--glyph-close` / `--glyph-minimize` / `--glyph-maximize` / `--glyph-restore` — title bar button icons;
    - `--glyph-arrow-up` / `--glyph-arrow-down` / `--glyph-arrow-left` / `--glyph-arrow-right` — SpinEdit / scroll bar arrows;
    - `--glyph-chevron-down` / `--glyph-chevron-right` / `--glyph-chevron-left` — expand/collapse chevrons.
      `-left` is the **mirror partner** of `-right`: in an RTL grid the collapse chevron points along the reading
      direction and takes this slot (see `docs/controls/grid.md`);
    - `--glyph-dropdown` — the ComboBox dropdown indicator arrow.

    Token names follow the `--glyph-<kind>` convention, and internal glyph drawing funnels through one overridable entry
    point, so the remaining glyph slots (menus / ribbon / tree / list / calendar and so on) can each be wired up with one
    line if ever needed; nobody skins those internal glyphs in practice, so they are not wired yet.
    Example: `--glyph-check: "Segoe MDL2 Assets" "\e73e";`. Unset slots use the built-in vector glyphs. **Note**: once a
    valid override is set, the glyph always renders through the icon font (even if that font/code point renders blank);
    only an unset or malformed token falls back to the vector glyph.
17. **`render-style` family presets (v3)**: the per-control property `render-style: flat | bevel3d | inset3d;`.
    With `bevel3d`/`inset3d`, `DrawFrame` automatically applies the raised/recessed two-color 3D bevel + square corners +
    the default border width (2) + a border color derived from the (solid) background when unset, so you do not repeat
    `border-style`/`border-width`/`border-color`/`border-radius` on every control. `flat` (the default) is the original
    behavior. Applies only to control frames drawn through `DrawFrame` (buttons / inputs / panels / progress tracks /
    forms and so on); separately drawn sub-parts such as the check box indicator are unaffected.
    For an example skin see `examples/theming/classic.tycss` (classic 3D style).
