# Theme-system v3 · Phase A — accent 主题色轴 (design)

**Goal:** Let any theme's accent/primary colour be changed at runtime (independent of light/dark), so one theme can be recoloured on the fly instead of shipping N colour-variant themes.

**Branch:** `feat/theme-skin-engine` (phase-4 program; see memory `theme-system-v3-skin-engine`). First of A→B→C→D→E, one phase per merge.

## Why this is small

The engine is already 80% there. `--accent` is the single seed the whole interactive palette derives from, *lazily*, at resolve time:

```
--accent-hover:  lighten(--accent, 8%);   --accent-active: darken(--accent, 8%);
--focus-ring:    var(--accent);            --selection:     alpha(var(--accent), 0.30);
--on-accent:     on(var(--accent));        /* auto-contrast ink */
```

Because `FMergedVars` stores raw expressions and `ResolveStyle`→`TyEvalColor` resolves them recursively, **overriding only `--accent` re-derives hover/active/focus-ring/selection/on-accent automatically** — no per-token work. The OS `system-accent` follow (`SystemTheme.pas` + `Controller.RefreshFromSystem`) is a working proof of "inject one colour → recolour the whole UI".

What's missing is a var layer that outranks `@mode`. The additive `:root` path can't be used: on the dual-mode built-ins `--accent` lives inside `@mode { :root { … } }`, and `RebuildMergedVars` applies `@mode` *after* the user `:root`, so an additive `:root{--accent:…}` is overwritten and has no effect (`StyleModel.pas:791-796`).

## Locked design decisions

- **D1 — accent pick vs OS `system-accent` follow:** explicit pick WINS and sticks (applied as the top layer, after `ApplySystemTokens`); OS light/dark mode-follow is unaffected and keeps working.
- **D2 — on theme switch (REPLACE load):** the accent override RESETS to the new theme's own accent (a theme is a curated whole). Additive loads keep it; mode switches keep it.

## Engine — `TTyStyleModel` (`source/tyControls.StyleModel.pas`)

- New field `FVarOverrides: TStringList` (name=value, **no leading `--`**, matching `FVars`). Create in ctor, free in dtor.
- `RebuildMergedVars` (`:781-801`): after `ApplySystemTokens(FMergedVars)`, overlay `FVarOverrides` as the **final/top layer** (`FMergedVars.Values[name] := value`). This is the load-bearing change (D1: beats OS accent; survives `@mode`).
- Public API:
  - `procedure SetVarOverride(const AName, AValue: string);` — normalise `AName` (trim, strip a leading `--`); **fail-fast validate** the value (`TyEvalColor(AValue, FMergedVars)` trial-resolve) so a bad value RAISES here with the prior state intact, instead of committing a value that then crashes every subsequent paint (the main resolve path is unguarded, unlike `ResolveOverride`); an **empty value folds into `ClearVarOverride`** (making the `TStringList` delete-on-empty quirk explicit); then store; `RebuildMergedVars`; `Inc(FVersion)`.
  - `procedure ClearVarOverride(const AName: string);` — remove one; re-merge; bump.
  - `procedure ClearVarOverrides;` — remove all; re-merge; bump.
  - `function VarOverride(const AName: string): string;` — current value or `''` (for UI state + tests).
- D2 reset points: clear `FVarOverrides` in `Clear` and in `LoadInto`'s `if AReplace then` commit branch. NOT in the additive branch, NOT in `SetMode`, NOT in `RefreshSystemTokens`.
- **Hot-reload is the one exception:** `TTyStyleController.PollThemeFile` reloads the SAME theme file through the REPLACE path, but that is an EDIT, not a switch — so it snapshots the accent override before the reload and re-applies it after (D2 must not fire for a hot-reload). It is the only replace that carries "this is a reload, not a switch" knowledge.
- Validation (`LoadInto` `tmpMerged`) is unchanged: overrides are colour-validated at the `SetVarOverride` seam instead, and on a REPLACE they're cleared anyway.

## Controller — `TTyStyleController` (`source/tyControls.Controller.pas`)

- `procedure SetAccent(const AHex: string);` → `FModel.SetVarOverride('accent', AHex); Changed;`
- `procedure ResetAccent;` → `FModel.ClearVarOverride('accent'); Changed;`
- `function AccentOverride: string;` → `FModel.VarOverride('accent')` (empty = using the theme's own accent; drives the demo's "reset" enabled-state).
- `Changed` already repaints every registered control and fires change-listeners (TTyForm re-resolves its own chrome), so the whole UI — including form chrome — recolours.
- No published persistent `Accent` property in Phase A: a streamed design-time value conflicts with D2's reset-on-switch. Deferred (revisit if a declarative brand-accent is wanted).

## App / demo

- Wire the existing `TTyColorDialog` → `SetAccent`; a "reset to theme default" → `ResetAccent` (enabled only when `AccentOverride <> ''`).
- Home: `examples/theming` (the theming showcase) gets the picker. The MAIN demo's theme controls are the user's design surface — confirm with the user before adding UI there.
- Persistence of the chosen hex is app-side, out of engine scope.

## Tests (`tests/test.accent.pas`, TDD first — 12 cases)

1. Override beats `@mode` (dual-mode, resolve in dark → the picked accent).
2. Override beats `system-accent` (stubbed accent hook; leading `--` normalised).
3. Derived recolour — EXACT: `border-color: lighten(var(--accent),20%)` and `:selected` `alpha(var(--accent),0.30)` resolve to `TyEvalColor('lighten(#…,20%)')` / `alpha(#…,0.30)` on the picked colour (covers `lighten` AND `alpha`, exact-value not `<>`).
4. `on(var(--accent))` contrast re-derives: a dark seed → light ink; a picked light accent flips the ink dark, and equals `on(picked)` exactly (the "invisible text" guard).
5. Mode-varying non-accent token still flips while the accent stays pinned (D1: override doesn't freeze other per-mode tokens).
6. `RefreshSystemTokens` (live OS-accent change) with an override set keeps the pick (D1 live path).
7. `ClearVarOverride` restores the theme accent; `VarOverride` → `''`.
8. Every mutator bumps `ThemeVersion` (each isolated).
9. D2: REPLACE `LoadFromCss` clears; additive load + `SetMode` KEEP (checked by resolve, not just the stored string).
10. Bad value (`'#12'`) raises at the call site, `ThemeVersion` unchanged, prior pick intact, resolve still works; empty value folds into a clear.
11. Controller `SetAccent`/`ResetAccent`/`AccentOverride` + `Changed` fires.
12. Hot-reload (`PollThemeFile`, temp file) preserves the pick across a same-file edit.

Golden byte-identical (default accent untouched). Mutation-verified: disabling the overlay reds 5 apply-path cases; disabling the D2 clear reds the replace case; disabling the value-validation reds the bad-value case; disabling the hot-reload re-apply reds the hot-reload case.

## Out of scope (later phases)

Painter primitives (B), geometry tokens (C), style-family dispatch (D), skins (E). Phase A ships colour-only accent runtime override.
