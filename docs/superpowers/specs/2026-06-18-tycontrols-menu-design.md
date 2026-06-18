# TyControls Menu System — Design

**Goal:** Themed application menu bar + context/popup menus for tyControls that match the
borderless custom `TTyForm` chrome and `.tycss` theming, while **reusing LCL's menu data
model** (`TMainMenu`/`TMenuItem`/`TPopupMenu`) so the IDE designer, actions, shortcuts and the
`Items` tree all keep working.

**Architecture (one sentence):** A single shared themed popup renderer drives both the menu
bar's dropdowns and right-click context menus; the menu bar and the popup menu are thin
adapters over the existing LCL data model; a form-level association handles the one genuine
cross-platform split (macOS global menu vs. in-window themed bar).

**Tech stack:** FPC/LCL custom controls, `TBGRABitmap`/`TTyPainter` rendering, `.tycss` theme
tokens via `TTyStyleController`, lazy borderless `TForm` popup windows (the existing
`TTyComboBox` dropdown pattern).

---

## 1. Motivation

- No menu units exist today. LCL's native `TMainMenu` (in-window on Win/GTK) and `TPopupMenu`
  (Win32 `TrackPopupMenu`) render with native frame/background/shadow that clash with the
  borderless chrome and ignore `.tycss`. Owner-draw can re-skin *items* but not the menu
  *window* — the well-known limitation.
- We want themed menus driven by the theme system, **without** throwing away the LCL data
  model (designer, `Action`, `ShortCut`, `Items` tree, `Images`).

## 2. Components

Three new units + one `TTyForm` association.

### 2.1 `TTyMenuPopup` (shared themed popup renderer) — the keystone
The menu bar's dropdowns, submenu cascades, and the context menu are **the same rendering
problem**; this component solves it once.

- A **lazy borderless `TForm`** popup window painted via `TTyPainter` — mirrors
  `TTyComboBox.FPopup` (borderless `TForm` host, `OnDeactivate` → close, a `~200ms` reopen-race
  guard tick). Reuse that proven pattern verbatim, not the native popup.
- **Input:** a root `TMenuItem` (the items to show are `root.Items[0..Count-1]`) + a screen
  anchor rectangle (the menu-bar cell, or the cursor point for context menus).
- **Renders each row:** `[icon] caption …………… [shortcut text] [submenu ▸]`, plus separators
  (`Caption = '-'`), checkmark / radio (`Checked` + `RadioItem`/`GroupIndex`), disabled
  (`Enabled = False`), default (bold, `Default = True`), hidden (`Visible = False` skipped),
  and vertical scrolling when the menu is taller than the work area.
- **Navigation (v1):** Up/Down move highlight, Enter/Space activate (`Item.Click`), Esc closes,
  Right opens a submenu (spawns a child `TTyMenuPopup`), Left closes the current submenu level;
  mouse hover highlights, hover-with-delay opens a submenu, click activates. Click-outside /
  focus-loss closes the whole chain.
- **Cascade:** a submenu is just another `TTyMenuPopup` anchored to its parent row; closing a
  level frees its children.
- **Result:** activating a leaf calls the standard `TMenuItem.Click` (which fires `OnClick` /
  the linked `Action`), then closes the chain.

### 2.2 `TTyMenuBar` (visual control)
- `class(TTyCustomControl)` (themeable like the other controls), typically `Align = alTop`.
- `property Menu: TMainMenu` — points at a standard LCL `TMainMenu` (a non-visual data
  container). The bar **only renders**; all menu management stays in `TMainMenu`.
- Renders the visible top-level `Menu.Items` as horizontal themed cells with hover / pressed /
  **active (open)** states. Clicking (or keyboard) opens a `TTyMenuPopup` anchored under the
  cell; Left/Right move between top items while open.
- **Independent + multi-instance:** drop it anywhere (in the `TitleBar`, below it via `alTop`,
  several at once). It is a normal control; placement is the user's choice.
- On non-macOS, **the bar designated as `TTyForm.MenuBar`** owns shortcut dispatch (§4).

### 2.3 `TTyPopupMenu` (context menu)
- `class(TPopupMenu)` — **reuses the LCL data model and the standard `control.PopupMenu`
  wiring** (LCL's `TControl.DoContextPopup` already calls the assigned `PopupMenu` on
  right-click). Assign a `TTyPopupMenu` to any control's `PopupMenu` and right-click "just
  works".
- Override the popup entry point so it shows a `TTyMenuPopup` at the cursor instead of the
  native menu. *Open question (resolve in plan): the exact overridable seam — `PopUp` vs.
  `DoPopup` vs. intercepting `DoContextPopup` — must be verified against the LCL version.*

### 2.4 `TTyForm.MenuBar: TTyMenuBar` (the cross-platform glue)
Designates **which** menu bar is the application's *primary* menu, and handles the one real
platform split:

- **macOS (`{$IFDEF DARWIN}`):** promote `MenuBar.Menu` to `Form.Menu` so the **global
  top-of-screen menu bar** works (the only correct place on macOS); the in-window `TTyMenuBar`
  is hidden by default (configurable).
- **Windows / Linux:** leave `Form.Menu = nil` (so LCL draws **no** native in-window menu),
  let `TTyMenuBar` render the themed bar, and let this primary bar own shortcut dispatch.

`TTyMenuBar` stays independent and multi-instance; `Form.MenuBar` merely marks the primary one
(macOS `Form.Menu` source + non-mac shortcut owner). Extra menu bars are pure themed bars.

## 3. Data model — reuse, do not reinvent

Render straight from the LCL `TMenuItem` tree; no parallel model:

| Render aspect | LCL source |
|---|---|
| label | `Caption` (`'-'` ⇒ separator) |
| accelerator text | `ShortCut` (`ShortCutToText`) |
| enabled / visible | `Enabled` / `Visible` |
| check / radio | `Checked`, `RadioItem`, `GroupIndex` |
| icon | `Bitmap` or `ImageIndex` + the menu's `Images` |
| emphasis | `Default` (bold) |
| submenu | `Count > 0` ⇒ `Items[]` |
| activation | `Click` ⇒ `OnClick` / `Action` |

## 4. Shortcut dispatch (non-macOS)

Because `Form.Menu` is left nil on Win/Linux, LCL's automatic shortcut routing does not run.
The primary bar (the `Form.MenuBar`) — or `TTyForm` on its behalf — hooks key input
(`TCustomForm.IsShortCut` override / `OnShortCut` / `KeyPreview`) and calls
`Menu.IsShortCut(Message)` to dispatch `Ctrl+S` etc. On macOS this is handled natively by
`Form.Menu`, so the hook is non-mac only.

## 5. Theming (`.tycss` tokens)

New selectors, following the existing SEED→MAP→ALIAS→COMPONENT tier convention and the existing
state model:

- `TyMenuBar` — bar background / color / font / padding; item cell states hover / active(open) /
  disabled.
- `TyMenuPopup` — popup window background / border / radius / elevation(shadow) / padding.
- `TyMenuItem` — row color, padding, hover background, disabled color, shortcut-text color,
  separator color, checkmark + submenu-arrow color.

Added to `light.tycss` / `dark.tycss` / `showcase.tycss` (and so the generated `DefaultTheme`,
`auto`, `system`). All visual values are token-driven — no hard-coded colors in the control
code (the project's hard rule).

## 6. Scope: v1 vs. v1.1

- **v1:** mouse + basic keyboard (Up/Down/Left/Right/Enter/Esc), shortcut dispatch, separators,
  check/radio, icons, submenus/cascade, full theming, the cross-platform `Form.MenuBar` glue.
- **v1.1 (deferred):** `Alt` activation of the menu bar, mnemonic underlines (`&File` → Alt+F),
  type-ahead first-letter jump. (Approved deferral — ship a usable themed version first.)

## 7. Testing

- **Headless (unit):** the `TMenuItem`-tree → render-row mapping (captions, separator /
  check / radio / disabled / shortcut-text flags, submenu detection, hidden-item skip);
  `Menu.IsShortCut` dispatch; `TTyPopupMenu` routing to `TTyMenuPopup`; popup height / scroll
  computation (separated from the window, the `TTyComboBox.ComputePopupHeight` pattern).
- **Golden:** add the new `TyMenuBar` / `TyMenuItem` / `TyMenuPopup` selectors to the resolved-
  style golden grid so their themed values are pixel-guarded.
- **Real-GUI manual:** the popup window itself, focus / click-outside close, cascade, and the
  macOS global-menu path (we are on Windows — macOS needs a real-mac check).

## 8. Risks / open items (resolved during planning)

- **macOS `Form.Menu` behavior** is verified only by inspection until a real-mac run — flag it.
- **`TPopupMenu` override seam** (`PopUp`/`DoPopup`) — verify against the installed LCL.
- **Popup focus/close semantics** — reuse the `TTyComboBox` `OnDeactivate` + 200ms reopen-guard
  exactly; the menu-bar click-while-open-reopen race is the same one ComboBox already solved.
- **Submenu open/close timing** — pick a hover delay (e.g. ~300ms) consistent with native feel.
