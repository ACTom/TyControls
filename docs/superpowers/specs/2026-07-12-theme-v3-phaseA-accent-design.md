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
  - `procedure SetVarOverride(const AName, AValue: string);` — normalise `AName` (trim, strip a leading `--`); store; `RebuildMergedVars`; `Inc(FVersion)`.
  - `procedure ClearVarOverride(const AName: string);` — remove one; re-merge; bump.
  - `procedure ClearVarOverrides;` — remove all; re-merge; bump.
  - `function VarOverride(const AName: string): string;` — current value or `''` (for UI state + tests).
- D2 reset points: clear `FVarOverrides` in `Clear` (`:741`) and in `LoadInto`'s `if AReplace then` commit branch (`:1058-1067`). NOT in the additive branch, NOT in `SetMode`, NOT in `RefreshSystemTokens`.
- Validation (`LoadInto` `tmpMerged` `:1040-1054`) is unchanged: overrides are always concrete colours that can't make a valid theme unresolvable, and on a REPLACE they're about to be cleared anyway.

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

## Tests (`tests/`, TDD first)

1. Override beats `@mode`: load a dual-mode theme whose `@mode dark` sets `--accent`; `SetVarOverride('accent', X)`; resolve in dark → accent is X.
2. Override beats `system-accent`: theme with `--accent: system-accent` + a stub accent hook returning Y; `SetVarOverride('--accent', X)` (leading `--` normalised) → resolves X, not Y.
3. Derived recolour: after override, a button's `:hover`/`:active`/focus-ring/selection resolve from the new accent (spot-check `lighten`/`alpha`).
4. `ClearVarOverride('accent')` restores the theme's own accent; `VarOverride` returns `''`.
5. Version bump: `SetVarOverride`/`ClearVarOverride`/`ClearVarOverrides` each increment `ThemeVersion` (cache/switch anchor).
6. D2: a REPLACE `LoadFromCss` clears the override; an additive `LoadFromCssAdditive` and a `SetMode` do NOT.
7. Golden unchanged: default accent untouched → the pixel golden is byte-identical.

## Out of scope (later phases)

Painter primitives (B), geometry tokens (C), style-family dispatch (D), skins (E). Phase A ships colour-only accent runtime override.
