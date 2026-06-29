# TTyForm Native Window Resize — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development — fresh subagent per task, spec-review + quality-review between tasks. Steps use `- [ ]`.

**Goal:** Make the borderless `TTyForm` edge-resizable on every platform (native where possible), content still to the edge, plus a published `Resizable` opt-out. Fix the real bug where no `TTyForm` (demo included) can be resized.

**Architecture:** Shared `TyHitTestBorder` + a per-widgetset strategy. Windows = native NC resize (`WS_THICKFRAME` + `WM_NCCALCSIZE` + `WM_NCHITTEST`); Linux = `AdjustClientRect` gutter + WM handoff; macOS = resizable `styleMask`; engine manual-drag as fallback. Spec: `docs/superpowers/specs/2026-06-29-ttyform-native-resize-design.md`.

**Reality note:** window resize CANNOT be verified headlessly (needs a real window manager). Pure logic (`TyHitTestBorder`, `Resizable` gating, gutter inset math) IS unit-tested; the Windows NC behaviour + DWM-corner interaction need **real-machine iteration with the user** (like the earlier chevron/scrollbar GUI bugs). Each Windows task ends compile-clean + pure-tests-green, then a real-machine checkpoint.

**Baseline:** `main` builds; suite ~1395 run / 0 fail / 11 pre-existing win32-1407 env errors. Every task: `lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain` → failures 0; commit ending `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`; never push.

**Invariants:** don't regress window effects (DWM corners/shadow via `ApplyWindowEffects`), the title-bar drag, maximize, multi-monitor DPI, or the title-bar streaming path; every new message handler chains `inherited`; all changes `{$IFDEF}`-guarded per widgetset; default behaviour with `Resizable=True` = "window is resizable" (the fix), `Resizable=False` = today's fixed behaviour.

---

## Phase A — `Resizable` property + gating + gutter scaffolding  *(pure, fully testable)*

### Task A1: `Resizable` property + engine/maximize gating
**Files:** `source/tyControls.Form.pas`; Test `tests/test.form.pas` (or the existing chrome test unit — locate it; else add `tests/test.formresize.pas` + register).

Add `FResizable: Boolean` (init `True` in `SetupChrome`) + published `property Resizable: Boolean read FResizable write SetResizable default True;`. `SetResizable(AValue)`: no-op if unchanged; store; then re-apply strategy hooks (stubs for now: `ApplyResizeStrategy` — empty per-platform, filled in B/C) + drive maximize availability: when `not Resizable`, the title-bar max button is hidden/disabled (reuse the existing `ShowMaximize`/`MaxButton` path — set `MaxButton.Enabled := AValue` if a bar is associated) and the title-bar double-click-maximize is gated. In `TTyChromeEngine.FormMouseDown` and `FormMouseMove`, **gate the resize hit on `FForm.Resizable`**: if the form isn't resizable, treat every position as `bhNone` (no resize cursor, no resize start). Add a read-accessor the engine can call (`FForm` is a `TTyForm`; expose `Resizable` or an internal `CanResize` getter).

- [ ] **Step 1: failing tests** — `TyHitTestBorder` already has coverage; add: a `TTyForm` created via `CreateNew(nil,0)` (no Show) defaults `Resizable=True`; after `Resizable:=False`, an engine `FormMouseDown` at an edge coordinate leaves `FResizing=False` and `BoundsRect` unchanged; with `Resizable=True` the same edge press sets `FResizing=True`. (If creating a `TTyForm` headless realizes a handle and fails — guard with `HandleAllocated`-free paths, or test a thin `CanResizeAt(form, pt)` pure helper extracted from the engine. Prefer extracting the gating into a pure function `TyResizeHitFor(AResizable, AClient, APt, AZone): TTyBorderHit` and test THAT.)
- [ ] **Step 2:** run → fail. **Step 3:** implement (prefer the pure `TyResizeHitFor` helper; engine calls it). **Step 4:** pass.
- [ ] **Step 5:** commit `feat(form): Resizable property + resize gating (default True; False -> fixed + no maximize)`.

### Task A2: Linux resize gutter via `AdjustClientRect` (scaffold + test the math)
**Files:** `source/tyControls.Form.pas`; Test as above.

Add `TTyForm.AdjustClientRect(var ARect: TRect); override;` guarded `{$IF DEFINED(LCLGtk2) or DEFINED(LCLQt5) or DEFINED(LCLQt6)}` — when `Resizable` and not maximized, inset `ARect` by `FBorderZone` on each side (so `alClient` children stop short of the form edge → the edge strip receives the mouse). On Windows/Cocoa the override is a no-op (`inherited` only). Factor the inset into a pure helper `TyResizeGutterRect(const AClient: TRect; AZone: Integer; AResizable, AMaximized, ANeedsGutter: Boolean): TRect` so it's testable on any platform.

- [ ] **Step 1: failing tests** — `TyResizeGutterRect` insets by `AZone` when `ANeedsGutter and AResizable and not AMaximized`; returns `AClient` unchanged otherwise (not resizable / maximized / no-gutter platform). Edge: zero/tiny client.
- [ ] **Step 2:** fail. **Step 3:** implement helper + the guarded override. **Step 4:** pass.
- [ ] **Step 5:** commit `feat(form): resize gutter math (AdjustClientRect inset on GTK/Qt; pure TyResizeGutterRect)`.

---

## Phase B — Windows native NC resize  *(R&D + real-machine; the core)*

### Task B1: spike — how to intercept `WM_NCCALCSIZE`/`WM_NCHITTEST` in LCL-Win32
**Files:** investigation only (notes appended to the plan or a scratch comment).

Determine the clean interception point: does LCL-Win32 deliver `WM_NCCALCSIZE`/`WM_NCHITTEST` to `TWinControl.WndProc` (overridable), or must we subclass via `SetWindowLongPtr(Handle, GWLP_WNDPROC, …)` after handle creation? Read LCL `win32/win32callback.inc` / `win32proc` for how these are handled today, and whether `bsNone` already removes `WS_THICKFRAME`. Confirm where to re-add `WS_THICKFRAME` (`CreateWnd`/`InitializeWnd` override + `SetWindowPos SWP_FRAMECHANGED`). Output: the exact mechanism + hook point for B2.

- [ ] **Step 1:** read LCL win32 widgetset message dispatch + `TCustomForm` style handling. **Step 2:** write the findings (mechanism, hook point, any LCL message the form already gets) into a short note in this plan file under B1. **Step 3:** commit `docs(form): B1 spike — LCL-Win32 NC message interception findings`.

#### B1 findings (2026-06-29 — read `C:\lazarus\lcl\interfaces\win32\win32callback.inc`)

**Mechanism chosen: subclass the HWND via `SetWindowLongPtr(Handle, GWLP_WNDPROC, …)` after handle creation, chaining the saved LCL window proc with `CallWindowProc`.** Overriding `TTyForm.WndProc` does NOT work for either message — proven from the source:

- **Dispatch path:** every window message enters `WindowProc → TWindowProcHelper.DoWindowProc` (`win32callback.inc`), which inits `LMessage := Default; PLMsg := @LMessage; WinProcess := True`, optionally `DeliverMessage`s to the LCL control, then — unless the message is in a small "respect the LCL result" allow-list (keys / erasebkgnd / setcursor / IME / syscommand …) — **overwrites the result with `CallDefaultWindowProc` whenever `WinProcess` is still True** (line ~2679-2689).
- **`WM_NCHITTEST`** (line 2358): `SetLMessageAndParams(LM_NCHITTEST)` — sets the LCL msg but leaves `WinProcess = True`, and `LM_NCHITTEST` is NOT in the result-respecting allow-list. So even if a `WndProc` override set `Message.Result`, the LCL callback discards it and returns `DefWindowProc`'s value. An override is futile.
- **`WM_NCCALCSIZE`:** NOT present anywhere in `DoWindowProc`'s `case Msg of`. It falls through with `PLMsg^.Msg = LM_NULL` (so it is never `DeliverMessage`d — guard at line ~2620), `WinProcess` stays True, and `CallDefaultWindowProc` returns. So `WM_NCCALCSIZE` is **never delivered to an LCL `WndProc` at all** — an override can't see it.
- **`WS_THICKFRAME` / `bsNone`:** a `bsNone` form is created with no resize border. The robust place to (re)assert the style is **after the handle exists** (`DoShow` / on `Resizable` change), via `GetWindowLong/SetWindowLong(Handle, GWL_STYLE, …)` + `SetWindowPos(…, SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE)`.

This matches the existing memory note that LCL-Win32 swallows messages in its own callback (the `WM_SETTINGCHANGE` precedent) and the modern custom-frame technique (Chrome / VS Code / WinUI). The subclass intercepts `WM_NCCALCSIZE` (collapse NC so the client fills the window) + `WM_NCHITTEST` (return `TyNcHitTest`) before the LCL proc, and chains `CallWindowProc(savedProc, …)` for everything else. **Hook point:** install the subclass once per handle in `DoShow` (handle guaranteed allocated, `csDesigning` excluded); store the prior proc to restore on handle destroy / re-install idempotently.

### Task B2: WS_THICKFRAME + WM_NCCALCSIZE + WM_NCHITTEST
**Files:** `source/tyControls.Form.pas` (Windows `{$IFDEF}` block); Test `tests/...`.

Per B1's mechanism: on Windows, after the handle exists (and on `Resizable` change), ensure `WS_THICKFRAME` is set when `Resizable` (else cleared) + `SetWindowPos(…, SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE)`. Handle `WM_NCCALCSIZE` to collapse the NC area so the client fills the window (keep the sizing border hit-testable). Handle `WM_NCHITTEST`: map the cursor (screen→window coords) through a pure `TyNcHitTest(const AWinRect; APt; AZone; AResizable; ACaptionH): LRESULT-ish code` returning the `HT*` constant — edges `HTLEFT…HTBOTTOMRIGHT`, the title-bar band `HTCAPTION`, else `HTCLIENT`; never edges when `not Resizable`. Disable the engine's manual resize on Windows (native owns it; keep the engine for non-Windows). Always chain `inherited` for unhandled messages.

- [ ] **Step 1: failing tests** — pure `TyNcHitTest`: corners/edges within `AZone` → the right `HT*`; the title band (`y < ACaptionH`, not on an edge) → `HTCAPTION`; interior → `HTCLIENT`; `not Resizable` → no edge codes (caption/client only). PPI-independent (coords are device).
- [ ] **Step 2:** fail. **Step 3:** implement the message handlers + style toggle + the pure mapper. **Step 4:** pure tests pass; `lazbuild tycontrols.lpk` + tests green. **(Cannot test the live resize headlessly.)**
- [ ] **Step 5:** commit `feat(form): Windows native NC resize (WS_THICKFRAME + WM_NCCALCSIZE + WM_NCHITTEST)`.
- [ ] **Step 6 — REAL-MACHINE CHECKPOINT (user):** rebuild demo + showcase; verify resize from every edge/corner with native cursors, content to the edge, title-bar drag still works, `Resizable=False` → no resize. Report; iterate on findings.

### Task B3: reconcile maximize + DWM corners/shadow
**Files:** `source/tyControls.Form.pas`, `tyControls.WindowEffects` (read).

Make native maximize coexist with the engine's `FMaximized` bookkeeping (prefer native: `HTCAPTION` double-click + the max button → `ShowWindow(SW_MAXIMIZE/SW_RESTORE)`; sync the max/restore glyph from the real window state, e.g. `GetWindowPlacement`). Tune `WM_NCCALCSIZE` so the DWM rounded corners + shadow from `ApplyWindowEffects` still render without a 1px top-line artifact (real-machine iteration — try full-collapse vs keep-1px vs the DWM extend-frame trick).

- [ ] **Step 1:** implement maximize reconciliation + the NCCALCSIZE corner tuning. **Step 2:** compile + tests green. **Step 3:** commit `fix(form): reconcile native maximize + DWM corners with NC resize`.
- [ ] **Step 4 — REAL-MACHINE CHECKPOINT (user):** maximize/restore via button + double-click + Aero-snap; rounded corners + shadow intact; DPI change mid-session. Iterate.

---

## Phase C — Linux + macOS hooks  *(implement now, verify on those machines later)*

### Task C1: Linux WM handoff (GTK begin_resize_drag / Qt startSystemResize)
**Files:** `source/tyControls.Form.pas` (GTK/Qt `{$IFDEF}` blocks).

In the engine's edge path (or a `TTyForm` hook it calls), on an edge `FormMouseDown` when `Resizable`: GTK → `gtk_window_begin_resize_drag(GtkWindow, edge, button, rootX, rootY, time)`; Qt5/6 → `TQtWidget(Handle).Widget`'s `windowHandle.startSystemResize(Qt::Edges)` (guard Qt ≥ 5.15; else fall through to the engine manual drag). Map `TTyBorderHit` → the platform edge enum. Native handle obtained from `Handle` via the widgetset class. The gutter (A2) provides reception.

- [ ] **Step 1:** implement both, `{$IFDEF}`-guarded; map-edge pure helper tested. **Step 2:** `lazbuild` compiles on the available widgetset (Windows build must still compile — the blocks are out via IFDEF). **Step 3:** commit `feat(form): Linux edge-resize via WM handoff (GTK begin_resize_drag / Qt startSystemResize)`.

### Task C2: macOS resizable styleMask
**Files:** `source/tyControls.Form.pas` (Cocoa `{$IFDEF}` block).

When `Resizable`, set the `NSWindow` `styleMask |= NSWindowStyleMaskResizable` (clear otherwise), applied after handle creation + on `Resizable` change. `NSWindow` via the Cocoa handle.

- [ ] **Step 1:** implement (guarded). **Step 2:** compiles (Windows build unaffected). **Step 3:** commit `feat(form): macOS edge-resize via NSWindowStyleMaskResizable`.

---

## Phase D — demo wiring + finish

### Task D1: demo/showcase `Resizable` + verify
**Files:** `examples/demo/*` (a "Resizable" checkbox or just confirm the default resizes), `examples/treeview/showcasemain.pas` (already has a title bar — now resizable by default).

Confirm the demo + the TreeView showcase resize by default after Phase B (no code change needed if default works); optionally add a demo toggle exercising `Resizable`. Build both (exit 0).

- [ ] **Step 1:** build demo + showcase. **Step 2:** commit `example: confirm/添加 Resizable toggle` (if a toggle is added).
- [ ] **Step 2 — finish:** **superpowers:finishing-a-development-branch** (verify tests → options → merge per user) + an opus adversarial review of the whole resize feature (WndProc correctness, style toggling, maximize/effects regressions, IFDEF coverage, the `Resizable` gating) before merge.

---

## Self-review notes
- **Spec coverage:** Resizable (A1), gutter (A2), Windows NC (B1-B3), Linux (C1), macOS (C2), demo/finish (D1) — every spec §3 sub-section maps to a task.
- **Type consistency:** `Resizable`, `TyResizeHitFor`, `TyResizeGutterRect`, `TyNcHitTest`, `ApplyResizeStrategy`, `FBorderZone`, `FMaximized` used consistently.
- **Testability honesty:** pure helpers (`TyHitTestBorder`/`TyResizeHitFor`/`TyResizeGutterRect`/`TyNcHitTest`) carry the headless tests; live resize + DWM corners are real-machine checkpoints (B2-S6, B3-S4) with the user, explicitly called out (no false "verified").
- **No regressions:** every handler chains `inherited`; all platform code `{$IFDEF}`-guarded so the Windows build stays clean; window effects/maximize reconciled in B3.
