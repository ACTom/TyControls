# Contributing

> 中文: [CONTRIBUTING.md](CONTRIBUTING.md)

Bug reports, suggestions and pull requests are all welcome. Please file issues on [GitHub](https://github.com/ACTom/TyControls/issues), in English or Chinese. The Gitee repository is a mirror.

## Reporting a bug

Check the [known issues](docs/known-issues.en.md) first; the cause and a workaround may already be listed there.

Please include:

- TyControls, Lazarus and FPC versions
- Operating system and widgetset (win32 / gtk2 / gtk3 / qt5 / qt6 / cocoa); on Linux, whether it's X11 or Wayland
- Display scaling (100%, 150%, …) and the theme in use
- How to reproduce it: ideally a few lines changed in one of the `examples/`; otherwise a minimal project that compiles
- What you see and what you expected; a screenshot for anything visual

## Suggesting a feature

Have a look at the [roadmap](https://github.com/ACTom/TyControls/milestones) first; it may already be planned.

Tell us what you want to do with it rather than only the solution you have in mind. There is often a better fit for the same need.

TyControls is a general-purpose, cross-platform, multi-theme control library. The built-in skins exist to prove the theme system, not to replicate any one design system in full. These are out of scope:

- Docking layouts. For IDE-style UIs, use the tool-window workbench.
- Multiple windows (tearing panels off into separate windows).

## Roadmap and releases

Each version has a Milestone whose description says what the release is mainly about. Each major feature has a tracking issue you can subscribe to and discuss.

Versions are ordered, not dated. A finished Milestone doesn't mean an immediate release: a bug-fix release usually waits a while longer, until no new problem reports come in.

## Versions and support

Versions are `major.minor.patch`. Patch releases only fix bugs; minor releases add features but stay compatible, as described below.

**Support window**: the latest minor version gets fixes and releases. The one before it keeps getting fixes and releases too, until the next minor version after that ships; then it gets one last release and support ends. For example, the last 4.0.x comes out together with 4.2. Severe problems are exempt from this.

**Long-term support**: 3.0 is a long-term support release. It keeps getting fixes and releases until 2027-09-30, one year after 3.0.0, while new work goes into 4.x.

**Compatibility**: within a major version (all of 3.x, say), a minor release guarantees that:

- Public API is neither removed nor changed in signature. Anything on its way out is marked `deprecated` first and only removed in the next major version.
- Properties stored in form files (`.lfm`) are neither removed nor renamed, and their default values don't change.
- Existing `.tycss` files keep working: token names and syntax are only ever added to.
- The minimum requirements don't go up: Lazarus 3.0, FPC 3.2.2.
- Controls keep their default sizes, padding and `AutoSize` results, so upgrading doesn't shift your layout. Colors in the built-in themes may be fine-tuned.

Fixing a bug doesn't count as breaking compatibility, even if some code relied on the old, wrong behavior.

So when you hit a problem, upgrading to the latest minor version gets you the fix.

## Pull requests

For anything sizeable, open an issue or comment on an existing one first, so the work doesn't end up going in a different direction.

**Branches**: a fix for a released version goes on the maintenance branch, `major.minor-fixes`, of the newest release that still has the bug (a 3.0.x bug goes on `3.0-fixes`). The maintainer cherry-picks fixes to the other maintenance branches and to `main`; maintenance branches are never merged with any other branch. Features and everything else go on `main`; larger features are built on a feature branch and merged back into `main`.

**Build and test**:

```
lazbuild tests/tytests.lpi
tests/tytests --all --format=plain
```

Bug fixes should come with a test that fails without the fix.

**Ground rules**:

- Visual values (colors, sizes, radii) come from theme tokens, never hard-coded.
- No native LCL controls (`TEdit`, `TButton`, …) inside owner-drawn UI.
- Add new units to `tycontrols.lpk` (design-time ones to `tycontrols_dt.lpk`).
- A new control is split from the start: `TTyCustomXxx` holds the implementation, `TTyXxx` is just a `published` section (see [docs/subclassing.en.md](docs/subclassing.en.md)). A control that is not split goes in `CNotSplit` in `tests/test.customclasses.pas` with its reason, or the tests fail.
- User-visible text goes in a `resourcestring`, with the zh_CN `.po` under `languages/` updated to match.
- New examples use `.lfm` forms, have a title bar and can switch themes at runtime.
- Don't use LCL API newer than Lazarus 3.0; where you must, keep a path for older versions behind `LCL_FULLVERSION`.
- Otherwise, follow the code around you.

**Commit messages** are in English, as `type(scope): summary`, e.g. `fix(grid): header loses focus after sort`. If it fixes an issue, put `Fixes #N` in the body.

## Changelog

Each release's changes go in [CHANGELOG.en.md](CHANGELOG.en.md). It only records changes users can notice, each linked to its issue; docs, refactoring and tests are left out. Don't edit the changelog in a PR; it's written up at release time.
