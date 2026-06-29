# ③e TreeView Inline Cell Editing — Design

**Date:** 2026-06-30
**Status:** approved-to-build (phase-3; feature scope pre-approved 2026-06-29)
**Branch:** `feat/treeview-e` (off main `6c29588`)

## Goal

In-place editing of a tree cell's text via a themed `TTyEdit` overlay, opt-in via the
`toEditable` option. VTV-faithful surface (`EditNode`/`EndEditNode`/`CancelEdit` +
`OnEditing`/`OnNewText`/`OnEditCancelled`). The control owns NO text — it stays virtual: the
app writes the committed string back into its own node-data blob inside `OnNewText`.

## Non-goals (deferred)

- Custom per-column editors (combo / spin / date — VTV's `OnCreateEditor`). Text-only `TTyEdit`.
- Multi-line editing, validation UI, structural edits.

## Architecture

- **One persistent `TTyEdit`** (`FEditor`), created hidden in the tree constructor:
  `Parent := Self`, `Visible := False`, `TabStop := False`. Reused for every edit (positioned +
  shown on demand). Themed automatically (it reads the same `Controller` as the tree).
- **State:** `FEditing: Boolean`, `FEditNode: PVirtualNode`, `FEditColumn: Integer`,
  `FEditOriginalText: String`, `FEndingEdit: Boolean` (reentrancy guard shared by
  commit/cancel/focus-loss so they can't recurse or double-fire).
- **`FLastMouseColumn: Integer`** — set in `MouseDown` to the column under the cursor
  (`NoColumn` when 0 columns / outside any cell). F2 uses it (fallback: `MainColumn`, else 0).

## Option

Add `toEditable` to `TTyTreeOption`. `Options = []` ⇒ no editing (every prior test stays green).

## Public API (mirrors VirtualTreeView)

- `function EditNode(Node: PVirtualNode; Column: Integer): Boolean;` — start editing. Returns
  `False` when not allowed: not `toEditable`, `OnEditing` veto, `Node = nil`, or the cell has no
  visible rect. Idempotent-safe (returns False if already editing that cell).
- `procedure EndEditNode;` — commit: fire `OnNewText` iff the text changed, then hide.
- `procedure CancelEdit;` — discard: fire `OnEditCancelled`, then hide.
- `property IsEditing: Boolean read FEditing;`
- `property EditedNode: PVirtualNode read FEditNode;` / `property EditedColumn: Integer read FEditColumn;` (read-only)

## Events

- `OnEditing(Sender; Node: PVirtualNode; Column: Integer; var Allowed: Boolean)` — permit/veto
  before the editor opens (`Allowed` defaults True).
- `OnNewText(Sender; Node: PVirtualNode; Column: Integer; const NewText: String)` — commit; the
  app writes `NewText` into its node blob. Fired ONLY when the text actually changed.
- `OnEditCancelled(Sender; Node: PVirtualNode; Column: Integer)` — Esc / programmatic cancel.

## Triggers

- **F2** — in `KeyDown`, when not editing AND `toEditable` AND `FocusedNode <> nil`:
  `EditNode(FocusedNode, EffCol)`, `EffCol` = `FLastMouseColumn` if valid else `MainColumn`
  (else 0). Consume the key.
- **Double-click** — in `DblClick`: if `toEditable` AND the last `MouseDown` hit an *editable
  cell region* (`hpOnLabel` / `hpOnNormalCell` — NOT the expand button or checkbox) AND
  `EditNode` succeeds ⇒ consume (do NOT toggle expand). Otherwise fall through to the existing
  `ToggleOnDblClick` / `OnNodeDblClick` path. (Edit takes precedence on editable cells; expand
  still works via the chevron, Enter, →, and double-click on non-editable nodes.)

## Editor lifecycle

1. **`EditNode`:** guard (`toEditable`, not already editing this cell, `Node <> nil`). Fire
   `OnEditing` → if `not Allowed`, return False. `r := GetCellRect(Node, Column)` (client px,
   scroll-adjusted, ③d helper). If `r` is empty / off-view, return False. Then:
   `FEditOriginalText := <cell text>`; `FEditor.Text := FEditOriginalText`;
   `FEditor.BoundsRect := EditorBoundsFromCell(r)`; `FEditor.Visible := True`;
   `if FEditor.CanFocus then FEditor.SetFocus`; `FEditor.SelectAll`. Set the state fields,
   `FEditing := True`.
2. **Commit (`EndEditNode`):** guard `FEndingEdit`. If `FEditor.Text <> FEditOriginalText` ⇒ fire
   `OnNewText(FEditNode, FEditColumn, FEditor.Text)`. Hide editor, clear state, refocus the tree
   (`if CanFocus then SetFocus`), invalidate the edited row.
3. **Cancel (`CancelEdit`):** guard `FEndingEdit`. Fire `OnEditCancelled`. Hide, clear, refocus,
   invalidate.

The current cell text is read through the SAME path the painter uses
(`OnGetTextWithType` / `OnGetText`, Column-aware) so the editor seeds with exactly what's drawn.

## Editor input wiring (internal handlers attached to `FEditor`)

- `FEditor.OnKeyDown`: `VK_RETURN` ⇒ `EndEditNode` + `Key := 0`; `VK_ESCAPE` ⇒ `CancelEdit` +
  `Key := 0`.
- `FEditor.OnExit` (focus lost): `if FEditing and not FEndingEdit then EndEditNode` (focus-loss
  commits, Explorer-style).

## Reposition / teardown on layout change

- While editing, every layout-affecting path calls `RepositionEditor`: recompute
  `GetCellRect(FEditNode, FEditColumn)`; if the cell is visible in the content rect ⇒
  `FEditor.BoundsRect := EditorBoundsFromCell(r)`; if it scrolled out of view ⇒ `EndEditNode`
  (commit + close). Hook the existing layout spine: vertical/horizontal scroll handlers,
  expand/collapse, column resize/reorder, node-height change, `Resize`.
- `DeleteNode` / `Clear` of (or containing) `FEditNode` ⇒ `CancelEdit` then null `FEditNode`
  (same dangling-pointer hygiene as `FLastMouseNode` / `FHotNode` / `FRangeAnchor`). No commit on
  a vanishing node.
- `toEditable` removed mid-edit (`SetOptions`) ⇒ `EndEditNode`.

## Coordinates

`GetCellRect` (③d) returns the cell rect in control-client device px, already including the
scroll offsets (it is the rect `RenderTo` paints into). `FEditor` is a direct child of the tree,
so its `BoundsRect` lives in the same client space ⇒ assign directly.
`EditorBoundsFromCell(r)` applies a small inset matching the cell's text padding so the edit text
sits where the drawn text did. HiDPI: `GetCellRect` is already device-px — no extra scaling.

## Tests (headless `RenderTo` + pure; PPI=96 and one PPI=144)

1. `EditNode` returns False when not `toEditable` / `OnEditing` veto / `nil` node.
2. `EditNode` opens: `FEditing` True, `FEditor.Visible` True, `FEditor.Text` = cell text,
   `FEditor.BoundsRect` ≈ `GetCellRect`.
3. Enter commits: `OnNewText` fired with the new text, `FEditing` False; NO `OnNewText` when the
   text is unchanged.
4. Esc cancels: `OnEditCancelled` fired, no `OnNewText`, `FEditing` False.
5. Focus-loss commits (drive `FEditor.OnExit`).
6. Double-click on an editable cell edits (no expand-toggle); on a non-editable node toggles
   (existing behavior preserved).
7. F2 on the focused node edits `FLastMouseColumn`.
8. `DeleteNode` / `Clear` during edit cancels + nulls `FEditNode` (no UAF on the next paint).
9. `toEditable` removed during edit closes the editor.
10. `Options = []` ⇒ all prior tree tests green (no behavior change).

**Handle guard:** `FEditor.SetFocus` / `CanFocus` need a window handle; headless tests that drive
commit/cancel call `EndEditNode` / `CancelEdit` directly or guard `HandleAllocated`, mirroring
③b's `MouseCapture` lesson (only `RenderTo`-based tests are handle-free).

## Files

- **Modify** `source/tyControls.TreeView.pas`: `toEditable`; the edit state fields + `FEditor` +
  `FLastMouseColumn`; `EditNode` / `EndEditNode` / `CancelEdit` / `RepositionEditor` /
  `EditorBoundsFromCell`; triggers in `KeyDown` + `DblClick`; `FLastMouseColumn` in `MouseDown`;
  teardown in `DeleteNode` / `Clear` / `SetOptions`; the 3 events + events-RTTI guard test update;
  RegisterClass unaffected.
- **Reuse** `source/tyControls.Edit.pas` (`TTyEdit`) — no change expected (verify it themes as a
  child + exposes `SelectAll` / `OnKeyDown` / `OnExit`).
- **Tests** `tests/test.treeview*.pas` — new edit tests + the RTTI-guard count bump.
- **Theme:** `TTyEdit` already themed; no new typeKey (verify the child editor picks up the tree's
  Controller).
- **Demo/showcase:** make one column of the showcase "columns" tab editable; `OnNewText` writes
  into the node blob (reinforces the data-in-node pattern, [[treeview-maincolumn... data-in-node]]).

## Out-of-scope confirmations

- No new node-record growth (edit state lives on the control, not the node).
- `MoveNode` / drag (③f) is a separate spec; `FLastMouseColumn` added here is reused by ③f.
