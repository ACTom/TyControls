# ③e TreeView Inline Cell Editing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax. Spec: `docs/superpowers/specs/2026-06-30-tycontrols-treeview-e-inline-edit-design.md`.

**Goal:** In-place cell editing via a themed `TTyEdit` overlay, opt-in `toEditable`, VTV-faithful (`EditNode`/`EndEditNode`/`CancelEdit` + `OnEditing`/`OnNewText`/`OnEditCancelled`); virtual (app writes back in `OnNewText`).

**Architecture:** One persistent hidden `TTyEdit` child created in the ctor, positioned via the ③d `GetCellRect` helper; edit state on the control (no node-record growth); triggers in `KeyDown`(F2)/`DblClick`/`MouseDown`(column); reposition/teardown hooked into the existing layout-invalidate spine.

**Tech Stack:** FPC/Lazarus, `source/tyControls.TreeView.pas` + `tyControls.Edit.pas`, headless `RenderTo` + fpcunit tests, build via `lazbuild tycontrols.lpk` then `tests/tytests.lpi`.

**Baseline:** main `6c29588`, suite 1469 / 0 fail / 11 env errors. Every phase must keep failures at 0 and `Options=[]` behavior byte-identical.

---

### Task E1: Foundations — option, editor field, state, last-column

**Files:** Modify `source/tyControls.TreeView.pas`. Test `tests/test.treeview.edit.pas` (new; add to `tytests.lpr` uses).

- [ ] **Step 1 — failing test:** `tests/test.treeview.edit.pas` `TestEditableOptionDefaultsOff`: a fresh `TTyTreeView` has `toEditable` NOT in `Options`; `IsEditing` is False; `EditNode(nil, 0)` returns False. Register the test unit in the runner.
- [ ] **Step 2 — run, expect FAIL** (members don't exist). `lazbuild tests/tytests.lpi`.
- [ ] **Step 3 — implement:**
  - Add `toEditable` to the `TTyTreeOption` enum (after the ③d options).
  - Fields: `FEditor: TTyEdit; FEditing: Boolean; FEditNode: PVirtualNode; FEditColumn: Integer; FEditOriginalText: String; FEndingEdit: Boolean; FLastMouseColumn: Integer;`
  - `property IsEditing: Boolean read FEditing;` + read-only `EditedNode`/`EditedColumn`.
  - Constructor: create `FEditor := TTyEdit.Create(Self)`, `FEditor.Parent := Self`, `Visible := False`, `TabStop := False`, `FEditColumn := NoColumn`, `FLastMouseColumn := NoColumn`. (Add `tyControls.Edit` to the `uses`.)
  - Stub `function EditNode(Node: PVirtualNode; Column: Integer): Boolean;` returning False; `procedure EndEditNode;` / `procedure CancelEdit;` empty for now.
- [ ] **Step 4 — run, expect PASS.** Full suite: 1469→1470ish, 0 fail.
- [ ] **Step 5 — commit:** `feat(treeview): ③e E1 — toEditable option + editor field + edit state scaffolding`.

---

### Task E2: Core edit lifecycle — open / commit / cancel + events

**Files:** Modify `source/tyControls.TreeView.pas`. Test `tests/test.treeview.edit.pas`.

- [ ] **Step 1 — failing tests (headless, no real focus — drive logic directly):**
  - `TestEditNodeOpensAndSeedsText`: 1-col tree, `OnGetText` returns "row0"; `Options:=[toEditable]`; `EditNode(first,0)` returns True; `IsEditing` True; `FEditor.Visible` True; `FEditor.Text='row0'`; `FEditor.BoundsRect` equals `GetCellRect(first,0)` after `EditorBoundsFromCell` inset (assert non-empty + within client).
  - `TestEditNodeVetoedByOnEditing`: `OnEditing` sets `Allowed:=False`; `EditNode` returns False; not editing.
  - `TestEndEditNodeFiresOnNewTextOnChange`: open, set `FEditor.Text:='changed'`, `EndEditNode`; `OnNewText` fired once with (node,0,'changed'); `IsEditing` False.
  - `TestEndEditNodeNoEventWhenUnchanged`: open, leave text, `EndEditNode`; `OnNewText` NOT fired.
  - `TestCancelEditFiresCancelledNoNewText`: open, set text, `CancelEdit`; `OnEditCancelled` fired; `OnNewText` not; `IsEditing` False.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:**
  - Events: `FOnEditing: TTyTreeEditingEvent` (`Sender;Node;Column;var Allowed:Boolean`), `FOnNewText: TTyTreeNewTextEvent` (`Sender;Node;Column;const NewText:String`), `FOnEditCancelled: TTyTreeColumnNodeEvent` (`Sender;Node;Column`). Declare the event types near the other tree event types; publish the 3 properties.
  - `EditorBoundsFromCell(const r: TRect): TRect` — inset to match the cell text padding used in paint (reuse the same horizontal text pad constant the painter uses; vertically center to the editor's preferred height or fill the row).
  - `function CurrentCellText(Node; Column): String` — read via the painter's text path (`OnGetTextWithType`/`OnGetText`, Column-aware) — factor out the existing RenderTo text lookup if not already shared.
  - `EditNode`: guards (`toEditable` in Options, `Node<>nil`, not already editing the same cell); fire `OnEditing` (Allowed default True) → bail False if vetoed; `r:=GetCellRect(Node,Column)`; if `IsRectEmpty(r)` bail False; seed `FEditOriginalText`/`FEditor.Text`; `FEditor.BoundsRect:=EditorBoundsFromCell(r)`; `FEditor.Visible:=True`; `if FEditor.CanFocus then FEditor.SetFocus`; `FEditor.SelectAll`; set state; `Result:=True`.
  - `EndEditNode`: guard `FEndingEdit`; set it; if `FEditing` and `FEditor.Text<>FEditOriginalText` fire `OnNewText`; `FinishEdit` (hide editor, `FEditing:=False`, null FEditNode, invalidate the row); clear `FEndingEdit`.
  - `CancelEdit`: guard `FEndingEdit`; if `FEditing` fire `OnEditCancelled`; `FinishEdit`.
- [ ] **Step 4 — run, expect PASS** + full suite 0 fail.
- [ ] **Step 5 — commit:** `feat(treeview): ③e E2 — EditNode/EndEditNode/CancelEdit + OnEditing/OnNewText/OnEditCancelled`.

---

### Task E3: Triggers — F2, double-click, MouseDown column

**Files:** Modify `source/tyControls.TreeView.pas`. Test `tests/test.treeview.edit.pas`.

- [ ] **Step 1 — failing tests:**
  - `TestMouseDownRecordsColumn`: multi-col tree; simulate `MouseDown` over column 1's x-range; `FLastMouseColumn` (expose via a test helper or a read-only prop) = 1.
  - `TestDoubleClickEditsEditableCell`: `Options:=[toEditable]`; arrange last-mouse hit on an editable label; call `DblClick`; `IsEditing` True; the node did NOT toggle expand (collapsed stays collapsed).
  - `TestDoubleClickTogglesWhenNotEditable`: `Options:=[]`, `ToggleOnDblClick:=True`; `DblClick` on an expandable node toggles (existing behavior intact).
  - `TestF2EditsFocusedNode`: `Options:=[toEditable]`; set focused node; KeyDown(VK_F2); `IsEditing` True, `EditedColumn` = `FLastMouseColumn` (or MainColumn fallback).
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:**
  - `MouseDown`: after the existing hit-test, set `FLastMouseColumn := <hit column>` (`NoColumn` if none).
  - `DblClick`: at the top, `if (toEditable in Options) and not FEditing` then compute the hit from the last mouse position (reuse the stored hit part / re-hit-test); if the part is an editable cell region (`hpOnLabel`/`hpOnNormalCell`, not button/checkbox) and `EditNode(node, FLastMouseColumn-or-main)` returns True ⇒ `Exit` (skip the toggle). Else fall through to the existing toggle/`OnNodeDblClick` body.
  - `KeyDown`: add `VK_F2` case — `if (toEditable in Options) and (FocusedNode<>nil) and not FEditing then begin EditNode(FocusedNode, EffCol); Key:=0; end;` where `EffCol := FLastMouseColumn` if `>=0` and `<ColumnCount` else `MainColumn` (else 0).
- [ ] **Step 4 — run, expect PASS** + full suite 0 fail (esp. the existing DblClick/toggle tests).
- [ ] **Step 5 — commit:** `feat(treeview): ③e E3 — F2 + double-click-to-edit triggers + MouseDown column tracking`.

---

### Task E4: Robustness — reposition on scroll/layout, teardown on delete/clear/option-off, focus-loss commit

**Files:** Modify `source/tyControls.TreeView.pas`. Test `tests/test.treeview.edit.pas`.

- [ ] **Step 1 — failing tests:**
  - `TestScrollRepositionsEditor`: open edit on a visible node; scroll down a little (node still visible); `FEditor.BoundsRect` moved up by the scroll delta (≈).
  - `TestScrollOutCommits`: open edit; scroll so the node leaves the viewport; `IsEditing` False (committed/closed).
  - `TestDeleteEditedNodeCancels`: open edit; `DeleteNode(FEditNode)`; `IsEditing` False; `OnNewText` NOT fired; subsequent paint/`GetNodeAt` does not touch a freed pointer (no crash; `EditedNode=nil`).
  - `TestClearDuringEditCancels`: open; `Clear`; `IsEditing` False, `EditedNode=nil`.
  - `TestRemovingEditableOptionCloses`: open; `Options:=Options-[toEditable]`; `IsEditing` False.
  - `TestFocusLossCommits`: open, change text, invoke the editor's `OnExit` handler; `OnNewText` fired; `IsEditing` False.
- [ ] **Step 2 — run, expect FAIL.**
- [ ] **Step 3 — implement:**
  - `RepositionEditor`: `if not FEditing then Exit; r:=GetCellRect(FEditNode,FEditColumn); if IsRectEmpty(r) or not <intersects content rect> then EndEditNode else FEditor.BoundsRect:=EditorBoundsFromCell(r);` Guard `FEndingEdit`.
  - Call `RepositionEditor` from: the V/H scroll-offset setters, expand/collapse, `InvalidateTreeLayout`, column resize/reorder apply, node-height change, `Resize`/`DoOnResize`. (Add the call where each already invalidates layout — find via the existing `InvalidateTreeLayout`/offset paths.)
  - `DeleteNode`/`Clear`: before freeing, `if FEditing and (FEditNode is being removed / always for Clear) then CancelEdit;` then null `FEditNode` (add to the existing cached-pointer nulling alongside `FLastMouseNode`/`FHotNode`/`FRangeAnchor`).
  - `SetOptions`: `if FEditing and not (toEditable in AValue) then EndEditNode;` (apply before/after assignment consistently).
  - Editor handlers (attach in ctor): `FEditor.OnKeyDown` (Return→EndEditNode+Key:=0; Escape→CancelEdit+Key:=0); `FEditor.OnExit` (`if FEditing and not FEndingEdit then EndEditNode`).
- [ ] **Step 4 — run, expect PASS** + full suite 0 fail. Add the PPI=144 variant of `TestEditNodeOpensAndSeedsText` (bounds still match `GetCellRect` at 144).
- [ ] **Step 5 — commit:** `feat(treeview): ③e E4 — reposition/teardown (scroll, delete/clear, option-off, focus-loss)`.

---

### Task E5: Events-RTTI guard + theme/demo/showcase + final review + finish

**Files:** `tests/test.treeview*.pas`, `examples/treeview/showcasemain.pas`, `examples/demo/` (if the Tree tab is touched).

- [ ] **Step 1 — events RTTI guard:** extend the published-events guard test to include `OnEditing`/`OnNewText`/`OnEditCancelled` (bump the expected count). Run → fix the count to PASS.
- [ ] **Step 2 — theme verify:** add a headless assertion that `FEditor` (the child) resolves a themed style from the tree's Controller (e.g. its resolved background ≠ default when a controller with a non-default theme is attached). No new typeKey expected.
- [ ] **Step 3 — showcase demo:** in `examples/treeview/showcasemain.pas` columns tab, set `Options` to include `toEditable`, wire `OnNewText` to write the new string into the node blob (via `GetNodeData`), and re-read it in `OnGetText`. Rebuild the showcase (`lazbuild -B examples/treeview/treeviewshowcase.lpi`, exit 0).
- [ ] **Step 4 — full verify:** `lazbuild tycontrols.lpk` (exit 0) + suite (0 fail) + `lazbuild -B examples/demo/demo.lpi` (exit 0).
- [ ] **Step 5 — adversarial review:** dispatch 2 read-only opus reviewers (one correctness/UAF/reentrancy lens, one VTV-parity/HiDPI/coords lens) over the ③e diff; triage findings; fix real ones; re-verify.
- [ ] **Step 6 — finish branch:** superpowers:finishing-a-development-branch → present options → (user merges to main).

---

## Self-review notes
- **Type consistency:** `EditNode`/`EndEditNode`/`CancelEdit`/`IsEditing`/`EditedNode`/`EditedColumn`/`RepositionEditor`/`EditorBoundsFromCell`/`CurrentCellText`/`FLastMouseColumn` used consistently across E1–E5.
- **No node-record growth** (edit state on the control) — confirmed.
- **`GetCellRect` coord contract** (client device-px incl. scroll) is the single assumption E2/E4 rest on — the E2 subagent must verify it against the ③d implementation before assigning `FEditor.BoundsRect`, and adjust `EditorBoundsFromCell` if `GetCellRect` excludes the offset.
- **Reentrancy:** `FEndingEdit` guards commit/cancel/focus-loss/reposition — every path that can re-enter checks it.
- **`Options=[]` invariant:** every trigger gates on `toEditable in Options`; existing DblClick-toggle test must stay green.
