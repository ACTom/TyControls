unit tyControls.Memo;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8, Clipbrd,
  ExtCtrls, StdCtrls,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ScrollBar, tyControls.UndoStack, tyControls.Animation, tyControls.QtWS;
type
  // Cumulative-prefix pixel widths, length = codepoints+1 (shared name with Edit).
  TTyIntArray = array of Integer;

  // A "visual row" is one painted text row. It is a half-open codepoint segment
  // [StartCol, EndCol) of one logical line (Line). When WordWrap=False each
  // logical line maps to exactly one visual row spanning the whole line
  // (StartCol=0, EndCol=LineLen). When WordWrap=True a long logical line yields
  // 1..N segments split at word boundaries (char-break for an over-long word).
  // An empty logical line emits one zero-width row (StartCol=EndCol=0).
  TTyVisualRow = record
    Line: Integer;      // logical line index
    StartCol: Integer;  // first codepoint column of this segment (inclusive)
    EndCol: Integer;    // one-past-last codepoint column (exclusive)
  end;
  TTyVisualRowArray = array of TTyVisualRow;

  TTyMemo = class(TTyCustomControl)
  protected
    // Pixel x where text begins (left padding scaled). Promoted from private so
    // the horizontal-scroll geometry is testable through the access subclass.
    function TextStartX(APPI: Integer): Integer;
  private
    // Logical text model: one TStrings line per logical line. Exposed (read-only
    // direction) via the published Lines:TStrings; writes go through SetLines.
    FLines: TStringList;
    // 2D caret. FCaretLine in 0..LineCountLogical-1; FCaretCol is a codepoint
    // index in 0..UTF8Length(line). FDesiredCol remembers the column for
    // vertical motion across short lines (used by later tasks).
    FCaretLine: Integer;
    FCaretCol: Integer;
    FDesiredCol: Integer;
    // Desired device-x for VERTICAL caret motion under WordWrap=True. Mirrors
    // FDesiredCol but in pixels: visual-row Up/Down preserve the on-screen x and
    // resolve the target row's column under it via VisualToCaret. Refreshed on
    // every horizontal move (Left/Right/Home/End/typing/click) alongside
    // FDesiredCol. Only consulted on the wrap path; the no-wrap Up/Down keeps the
    // FDesiredCol column-restore idiom so its behaviour is byte-identical to today.
    FDesiredX: Integer;
    // Set for the duration of a VERTICAL caret move (Up/Down) so the shared post-
    // move routine (AfterCaretMove) does NOT refresh FDesiredX — the desired x must
    // survive a run of Up/Down. Every other move leaves it False, so AfterCaretMove/
    // AfterEdit refresh FDesiredX from the (horizontally-moved) caret.
    FInVerticalMove: Boolean;
    // 2D selection anchor (codepoint index per line). No selection <=> anchor
    // equals the caret. Mirrors TTyEdit.FSelAnchor generalised to (line,col).
    FSelAnchorLine: Integer;
    FSelAnchorCol: Integer;
    // True while the left button is held for drag-select (set in MouseDown,
    // cleared in MouseUp). Mirrors TTyEdit.FMouseSelecting.
    FMouseSelecting: Boolean;
    // Index of the first VISUAL ROW painted (top of the visible window). Indexes
    // FVisualRows, not FLines: when WordWrap=False each logical line is exactly
    // one visual row so FTopRow == the top logical line (identity with the old
    // FTopLine); when WordWrap=True a long line spans several rows and FTopRow
    // tracks the visual row. TopLine maps it back to a logical line for callers.
    FTopRow: Integer;
    // Horizontal scroll offset in device px (>= 0). Only meaningful when
    // WordWrap=False: the whole rendered text/selection-band/caret shift left by
    // FScrollX so a long line follows the caret horizontally (mirrors
    // TTyEdit.FScrollX). When WordWrap=True the layout flows across visual rows
    // instead, so FScrollX is forced to 0 (ClampScrollX/EnsureCaretXVisible no-op).
    FScrollX: Integer;
    // Soft-wrap toggle (published WordWrap). Default False = no wrap: each logical
    // line is exactly one full-width visual row (today's behaviour; horizontal
    // scroll lands in a later task). True = soft wrap at word boundaries into
    // multiple visual rows. Affects BuildVisualRows and (later) render/nav/click.
    FWordWrap: Boolean;
    // Cached visual-row layout for the current content width + wrap mode, rebuilt
    // lazily by EnsureVisualRows. FVisualRowsValid is cleared whenever something
    // that affects layout changes (WordWrap toggle, edits, resize, Lines assign).
    // FVisualRowsWidth records the content width the cache was built at so a
    // resize/scrollbar change forces a rebuild even when FVisualRowsValid was set.
    FVisualRows: TTyVisualRowArray;
    FVisualRowsValid: Boolean;
    FVisualRowsWidth: Integer;
    // Embedded vertical scrollbar, lazily created on first overflow (owned by
    // Self via Create(Self), so freed by TComponent). nil until first needed.
    FScrollBar: TTyScrollBar;
    // Reentrancy guard: TopLine->scrollbar.Position and scrollbar OnChange->
    // SetTopLine would otherwise ping-pong.
    FSyncingScroll: Boolean;
    // Lazy measuring bitmap (freed in Destroy). Shared by all per-line measures.
    FMeasureBmp: TBGRABitmap;
    // Headless-only override of the LCL focused state. Real focus is unavailable
    // when rendering offscreen, so tests can force the caret to draw. Production
    // paint uses (Focused or FForceFocused) so this is a no-op unless set.
    FForceFocused: Boolean;
    // Fired after any mutation of the text model (insert/split/delete/merge).
    // Pure caret moves do NOT fire it.
    FOnChange: TNotifyEvent;
    // Fired whenever the caret position OR the selection range changes (arrow/click/
    // shift-select, programmatic SetCaret, and after edits that move the caret). The
    // funnel DoSelectionChange snapshots the last-reported (caret,anchor) and only
    // fires when it differs, so a no-op caret set never fires and it never spams.
    FOnSelectionChange: TNotifyEvent;
    // Last (caret,anchor) reported to FOnSelectionChange (the guard snapshot).
    FLastSelCaretLine, FLastSelCaretCol: Integer;
    FLastSelAnchorLine, FLastSelAnchorCol: Integer;
    // Snapshot-based undo/redo (one stack per control). FSuspendUndo is set
    // while a composite op (cut/paste/typing-over-selection) pushes its own
    // single step, so nested mutators do not add extra steps.
    FUndoStack: TTyUndoStack;
    FSuspendUndo: Boolean;
    // ReadOnly: when True, all USER edits (typing/Enter/Backspace/Delete/word-
    // delete/Paste) are blocked and Cut degrades to Copy; navigation, selection,
    // Copy, SelectAll and programmatic Lines := still work. Default False.
    FReadOnly: Boolean;
    // MaxLength: caps the TOTAL content codepoint count (sum of UTF8Length over
    // all logical lines; line breaks are NOT counted). 0 = unlimited. Blocks a
    // new printable char at the cap and truncates paste to the remaining room;
    // Enter/Backspace/Delete/merge are never limited. Default 0.
    FMaxLength: Integer;
    FImeHook: TObject;   // Qt-only IME commit interceptor (nil off Qt); see tyControls.QtWS
    // WantTabs: when True a Tab key inserts a literal tab char into the text;
    // when False (default) Tab is left to propagate so it navigates between
    // controls (the native TMemo default). Gated in KeyDown.
    FWantTabs: Boolean;
    // WantReturns: when True (default) Enter inserts a line break; when False
    // Enter is NOT consumed so the form's default button can handle it. Gated on
    // the VK_RETURN branch in KeyDown.
    FWantReturns: Boolean;
    // ScrollBars: which scrollbars the (vertical, optionally word-wrapping) memo
    // shows. Default ssAutoVertical = the historical behaviour (the embedded
    // vertical bar appears on overflow). ssNone hides it entirely; ssVertical
    // forces it always-visible. Horizontal variants degrade to the vertical
    // policy (this memo has no horizontal scrollbar — flagged, not implemented).
    FScrollBars: TScrollStyle;
    procedure SetReadOnly(AValue: Boolean);
    procedure SetMaxLength(AValue: Integer);
    procedure SetWantTabs(AValue: Boolean);
    procedure SetWantReturns(AValue: Boolean);
    procedure SetScrollBars(AValue: TScrollStyle);
    // --- Flat codepoint-offset <-> (line,col) mapping. The flat offset counts one
    // codepoint for the newline BETWEEN consecutive logical lines, so a document
    // of N lines has Sum(LineLen)+ (N-1) addressable offsets. Mirrors a native
    // TMemo's SelStart/SelLength/CaretPos integer addressing. ---
    function LineColToFlat(ALine, ACol: Integer): Integer;
    procedure FlatToLineCol(AOffset: Integer; out ALine, ACol: Integer);
    // Flat-offset accessors over the (line,col) selection/caret model. The
    // selected-text getter is the protected GetSelText (declared below alongside
    // the 2D selection helpers); the SelText property reads it.
    function GetSelStart: Integer;
    function GetSelLength: Integer;
    function GetCaretPos: Integer;
    procedure SetSelStart(AValue: Integer);
    procedure SetSelLength(AValue: Integer);
    procedure SetSelText(const AValue: string);
    procedure SetCaretPos(AValue: Integer);
    // Whole-string Text accessor over Lines (TStrings.Text get/set semantics).
    function GetText: string;
    procedure SetText(const AValue: string);
    // Total content codepoints across all logical lines (line breaks excluded).
    function ContentCodepointCount: Integer;
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
    function EffectiveFontSize(const S: TTyStyleSet): Integer;
    // WordWrap published setter (no-op if unchanged; repaints when toggled).
    procedure SetWordWrap(AValue: Boolean);
    // Fire OnChange (after a model mutation).
    procedure DoChange;
    // Fire OnSelectionChange iff the caret OR the selection anchor moved since the
    // last fire (self-guarded so it never spams; a no-op move is silent). Called
    // from every caret/selection funnel (AfterCaretMove/AfterEdit/SetCaret/drag/
    // SelectAll/ClearSelection).
    procedure DoSelectionChange;
    // Shared post-mutation routine: clamp caret, keep its line visible, repaint,
    // and fire OnChange. (UpdateScrollBar lands with the real scrollbar in T4.)
    procedure AfterEdit(APPI: Integer);
    // Shared post-move routine for pure caret motion: clamp, keep visible, repaint.
    // Never fires OnChange.
    procedure AfterCaretMove(APPI: Integer);
    // Scrollbar OnChange handler -> SetTopLine (guarded against ping-pong).
    procedure ScrollBarChange(Sender: TObject);
    // Insert a FULL input-method commit (Qt6 path), bypassing LCL's TUTF8Char (String[7]) truncation.
    procedure HandleImeCommit(const ACommitUtf8: string);
    // --- Model mutators (pure UTF8 splice; no key/paint dependency) ---
    procedure DoInsertText(const AStr: string);
    // Insert AStr at the caret, splitting it into logical lines on CR/LF (CRLF and
    // lone CR normalised to one break). A single segment is a plain in-line insert;
    // multiple segments split the caret line and splice the interior lines in.
    // Pure mutator: the caller routes through AfterEdit (one OnChange/undo step).
    // Shared by PasteFromClipboard and the SelText writer.
    procedure InsertTextMultiline(const AStr: string);
    procedure DoSplitLine;
    procedure DoBackspace;
    procedure DoDelete;
    // --- Word-delete mutators (pure UTF8 splice; route through AfterEdit at the
    // call site, like DoBackspace/DoDelete). At a line boundary they fall back to
    // the cross-line merge (DoBackspace / DoDelete). ---
    procedure DeleteWordBackward;
    procedure DeleteWordForward;
  protected
    // Blinking caret (Task 10). FCaretVisible defaults True; the timer is created
    // lazily and started ONLY when HandleAllocated, so headless tests never blink
    // and the static-caret pixel tests stay deterministic.
    FCaretVisible: Boolean;
    FBlinkTimer: TTimer;
    FBlinkElapsedMs: Integer;
    procedure EnsureBlinkTimer;
    procedure HandleBlink(Sender: TObject);
    procedure ResetCaretBlink;
    procedure DoEnter; override;
    procedure DoExit; override;
    function GetStyleTypeKey: string; override;
    // --- Undo/redo state serialization (protected so headless access subclasses
    // can drive them directly, mirroring TTyEdit). CaptureState serializes the
    // full editable state (caret/anchor header + raw lines) to one opaque string;
    // RestoreState parses it back and routes through AfterEdit so OnChange fires.
    function CaptureState: string;
    procedure RestoreState(const S: string);
    // Push the current state as one undo step (no-op while FSuspendUndo). New
    // pushes clear the redo stack; consecutive uskTyping pushes coalesce.
    procedure BeginUndoStep(AKind: Byte);
    // End a typing-coalesce run (caret nav / selection change / clipboard copy).
    procedure BreakCoalescing;
    // Remove the current selection (SelStart..SelEnd): single-line splice, or
    // multi-line merge of first-line head + last-line tail with middle lines
    // dropped. Caret -> SelStart; anchor collapses. Pure mutator — callers route
    // through AfterEdit (matching the Memo's mutator/AfterEdit split). Protected
    // so headless probe subclasses can exercise it directly (like HasSelection).
    procedure DeleteSelection;
    // --- Pure per-line geometry helpers (headless-testable; no paint state) ---
    // Codepoint length of a logical line index (0 for the synthetic empty line).
    function LineLen(ALineIndex: Integer): Integer;
    // Floored at 1 so vertical layout never divides by zero.
    function LineHeight(APPI: Integer): Integer;
    // Always >= 1 (an empty model is one logical, visually present line).
    function LineCountLogical: Integer;
    // Clamp the caret into the current model (line then col).
    procedure ClampCaret;
    // Refresh FDesiredX (the desired device-x for wrap Up/Down) from the caret's
    // current position. Called on every HORIZONTAL move so a later vertical move
    // tracks the on-screen x; vertical moves themselves never call it, so the x is
    // preserved across a run of Up/Down. No-op-ish for the no-wrap path (FDesiredX
    // is only consulted under WordWrap=True).
    procedure UpdateDesiredX(APPI: Integer);
    // Absolute (full-line) device-x where a visual row's segment begins (its
    // StartCol's caret x). The on-screen x of a caret within a row is its absolute
    // x minus this; FDesiredX stores that screen-relative form for wrap Up/Down.
    function RowBaseAbsX(AVisualRow, APPI: Integer): Integer;
    // WordWrap=True vertical motion: move the caret by ADelta visual rows (+1 down,
    // -1 up), preserving FDesiredX. Resolves the target row's column under the
    // desired x via VisualToCaret. Guards: at the top row Up is a no-op; at the
    // bottom row Down is a no-op (mirrors the no-wrap FCaretLine guards). Does NOT
    // refresh FDesiredX, so a run of Up/Down keeps tracking the original x.
    procedure MoveCaretByVisualRow(ADelta, APPI: Integer);
    // StartCol / EndCol of the caret's OWNING visual row (under WordWrap=True);
    // used by the wrap-mode Home/End. CaretToVisual's boundary tie-break decides
    // which row owns a caret sitting on a shared wrap-boundary column.
    function CaretRowStartCol(APPI: Integer): Integer;
    function CaretRowEndCol(APPI: Integer): Integer;
    // Cumulative prefix widths for ALine, measured on the shared BGRA bitmap so
    // measurement matches drawing (lifted from TTyEdit.MeasureCodepointWidths,
    // generalised to take the line as a parameter — no per-line cache).
    function MeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
    // Pixel x of the caret boundary before codepoint ACol on ALine.
    function ColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
    // Nearest codepoint boundary to device-x AX on ALine (midpoint rule).
    function ColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
    // --- Per-line word-boundary helpers (pure codepoint logic; no paint state).
    // Ported verbatim from TTyEdit (IsWordCodepoint identical; Next/PrevWordBoundary
    // generalised to operate on a passed line string rather than FText). Protected
    // so the headless probe can expose them. Indices are codepoint counts in
    // 0..UTF8Length(ALine). ---
    function IsWordCodepoint(const CP: string): Boolean;
    function NextWordBoundary(const ALine: string; AIdx: Integer): Integer;
    function PrevWordBoundary(const ALine: string; AIdx: Integer): Integer;
    // --- Pure visual-row model (no paint/window state; tested headless) ---
    // Build the ordered visual-row list for the whole document at the given
    // content width (pixels available for text, padding already removed) and
    // APPI. WordWrap=False: one full-width row per logical line. WordWrap=True:
    // each logical line is greedily packed into [StartCol,EndCol) segments that
    // fit AContentWidth, broken at the last word boundary at/before the fit point
    // (char-break a single over-long word/CJK run). Always emits >= 1 row per
    // logical line (an empty line emits one zero-width row). Pure: depends only
    // on FLines, FWordWrap, AContentWidth, APPI and the (pure) measurement.
    function BuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
    // Pixel width available for text on a row: client width minus left+right
    // padding and the (visible) scrollbar width, all scaled to APPI. This is the
    // width fed to BuildVisualRows so the wrap layout matches the render clip.
    function ContentWidthFor(APPI: Integer): Integer;
    // Rebuild FVisualRows from the current model/wrap mode at the current content
    // width if the cache is stale (invalid or built at a different width). Cheap
    // no-op when already valid for this width. Drives the render loop and the
    // caret/selection-band visual-row resolution.
    procedure EnsureVisualRows(APPI: Integer);
    // Mark the visual-row cache stale (next EnsureVisualRows rebuilds it).
    procedure InvalidateVisualRows;
    // Map a logical caret (ALine,ACol) to the visual row index that owns it plus
    // the device-x of the caret on that row. At a soft-wrap boundary column the
    // caret binds to the EARLIER (line-end) row (tie-break), so a caret typed at
    // end-of-row stays visually at the end of that row rather than jumping to the
    // start of the next. AX is the same TextStartX-relative pixel x that
    // ColPixelXAt would give for (line,col) — visual rows do not change the
    // horizontal origin (horizontal scroll is applied later by the renderer).
    procedure CaretToVisual(ALine, ACol, AContentWidth, APPI: Integer;
      out AVisualRow, AX: Integer);
    // Inverse of CaretToVisual: given a visual row index and a device-x, return
    // the logical (line,col) under that x, clamped to the row's [StartCol,EndCol]
    // segment so a click never escapes the row it landed on.
    procedure VisualToCaret(AVisualRow, AX, AContentWidth, APPI: Integer;
      out ALine, ACol: Integer);
    // Caret read/write for tests and later tasks.
    function CaretLine: Integer;
    function CaretCol: Integer;
    procedure SetCaret(ALine, ACol: Integer);
    // Direct write of the selection anchor (tests / later tasks). Does NOT move
    // the caret, so it can establish a non-empty selection.
    procedure SetSelAnchor(ALine, ACol: Integer);
    // --- 2D selection read helpers (pure; no paint state) ---
    // A selection exists when the anchor differs from the caret.
    function HasSelection: Boolean;
    // Order the anchor/caret endpoints lexicographically: (L1,C1) < (L2,C2) iff
    // (L1<L2) or (L1=L2 and C1<C2). Returns the smaller endpoint as start.
    procedure GetOrderedSel(out SL, SC, EL, EC: Integer);
    function SelStartLine: Integer;
    function SelStartCol: Integer;
    function SelEndLine: Integer;
    function SelEndCol: Integer;
    // Selected text: single line -> the spanned slice; multi-line -> first-line
    // tail + whole interior lines + last-line head, joined by LineEnding. Renamed
    // from SelText so the published flat property SelText can read it.
    function GetSelText: string;
    // Select the whole document (anchor->(0,0), caret->end of last line).
    procedure SelectAll;
    // Collapse the selection onto the caret (anchor := caret).
    procedure ClearSelection;
    // Clipboard virtual hooks (override in tests to avoid the real OS clipboard;
    // verbatim from TTyEdit). SelText is already LineEnding-joined, so the same
    // copy/cut bodies as Edit work unchanged for the multi-line model.
    function ReadClipboardText: string; virtual;
    procedure WriteClipboardText(const S: string); virtual;
    // Headless focus override (see FForceFocused). Triggers a repaint.
    procedure SetForceFocused(AValue: Boolean);
    // Visible-line count for the current bounds at APPI (>= 1).
    function VisibleLineCount(APPI: Integer): Integer;
    // Whole visible rows = Height div LineHeight(Font.PixelsPerInch), floored 1.
    // Uses Height (not ClientHeight) per the headless ListBox note — for this
    // borderless control Height = ClientHeight at runtime, but ClientHeight can
    // lag SetBounds in headless tests without a native handle.
    function VisibleRows: Integer;
    // Total painted visual rows for the current model/wrap mode/content width
    // (rebuilds the cache if stale). WordWrap=False: == LineCountLogical (one row
    // per logical line). WordWrap=True: the sum of each line's wrap-segment count.
    function TotalVisualRows(APPI: Integer): Integer;
    // Highest valid FTopRow = TotalVisualRows - VisibleRows, floored 0. For
    // WordWrap=False this equals LineCountLogical - VisibleRows (the old value).
    function MaxTopLine: Integer;
    // Raw FTopRow visual-row index (tests). TopLine maps it back to a logical line.
    function TopRow: Integer;
    // Logical line of the top visual row: FVisualRows[FTopRow].Line. For
    // WordWrap=False FTopRow == the top logical line, so this is identity.
    function TopLine: Integer;
    // The visual row index that currently owns the caret (via CaretToVisual).
    function CaretVisualRow(APPI: Integer): Integer;
    // Top-of-window setter with clamp + guarded scrollbar sync + repaint. AValue
    // is a VISUAL-ROW index (so the scrollbar's Position feeds straight in).
    procedure SetTopLine(AValue: Integer);
    // Create/update/hide the embedded vertical scrollbar. Range/position are over
    // VISUAL ROWS now (TotalVisualRows, not LineCountLogical), so a wrapped single
    // line can overflow and show the bar.
    procedure UpdateScrollBar;
    // True iff the embedded vertical scrollbar currently exists AND is visible.
    // Protected so headless probes can assert the ScrollBars policy without
    // reaching the private FScrollBar field.
    function ScrollBarVisible: Boolean;
    // Scroll FTopRow so the caret's VISUAL ROW sits inside the visible window.
    procedure EnsureCaretLineVisible(APPI: Integer);
    // --- Horizontal scroll (WordWrap=False only; mirrors TTyEdit.ClampScrollX /
    // EnsureCaretVisible generalised to the multi-line model). ---
    // Widest logical line width in px (drives MaxScroll so any line can scroll
    // fully into view). 0 for an empty document.
    function WidestLineWidth(APPI: Integer): Integer;
    // Clamp FScrollX into [0, widestLineWidth - ViewWidth]. When WordWrap=True the
    // max is forced to 0 (no horizontal scroll in wrap mode).
    procedure ClampScrollX(APPI: Integer);
    // Scroll FScrollX so the CARET-LINE caret x stays inside the content viewport
    // [StartX+Margin, ViewRight-Margin]. No-op (clamped to 0) when WordWrap=True or
    // when the caret already fits (so fitting text never leaves ScrollX = 0).
    procedure EnsureCaretXVisible(APPI: Integer);
    // Paint into ACanvas at ARect (RenderTo convention: draw local Rect(0,0,W,H),
    // EndPaint blits at ARect origin). APPI scales padding/line metrics.
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    // Input handlers. Both early-Exit when not Enabled (v1.5 policy); when
    // disabled, KeyDown does NOT consume Key so navigation falls through.
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    // Qt6: own input-method commit interceptor (custom controls otherwise get the String[7]-truncated
    // commit). No-op off Qt.
    procedure InitializeWnd; override;
    procedure DestroyWnd; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    // Left-click caret hit-test: Y -> logical line, X -> codepoint column. Early
    // Exit when not Enabled (v1.5 policy). try/except SetFocus like Edit/ListBox.
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    // Drag-select while the left button is held: re-hit-test (line,col) under the
    // pointer using the SAME math as MouseDown, moving the caret while leaving the
    // anchor fixed. Mirrors TTyEdit.MouseMove. Early Exit when not Enabled.
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    // End the drag on left-button release (no Enabled guard, matching TTyEdit).
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    // Wheel scrolls +/-3 logical lines via SetTopLine (after the user's handler).
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    // Keep the scrollbar in sync when the control is resized.
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Headless input helpers (mirror TTyEdit.Inject*). InjectChar simulates a
    // printable keypress; InjectKey simulates a VK_* KeyDown.
    procedure InjectChar(const AChar: TUTF8Char);
    procedure InjectKey(AKey: Word; AShift: TShiftState);
    procedure InjectBackspace;
    procedure InjectDelete;
    // Clipboard API. Copy/Cut require a selection; Cut and Paste route through
    // AfterEdit so OnChange fires. Paste splits the clipboard text on CR/LF and
    // inserts it as one-or-more logical lines (the multi-line generalisation of
    // TTyEdit.PasteFromClipboard, which strips newlines for its single line).
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard;
    // Undo/redo API. Both honor the Enabled guard. Undo restores the previous
    // snapshot (and moves the current state onto the redo stack); Redo re-applies.
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    // Horizontal scroll offset in device px (>= 0; WordWrap=False only). Mirrors
    // TTyEdit.ScrollX. Read-only: it is driven by EnsureCaretXVisible/ClampScrollX.
    property ScrollX: Integer read FScrollX;
    // Flat codepoint-offset selection/caret accessors (runtime; mirror native
    // TCustomMemo's public SelStart/SelLength/SelText/CaretPos integer addressing).
    // The flat offset counts one codepoint for the newline between consecutive
    // lines. SelStart = flat(ordered selection start); SelLength = |flat(caret) -
    // flat(anchor)|; SelText = the selected text (spans newlines as LineEnding);
    // CaretPos = flat(caret). Writing SelStart collapses the selection there;
    // writing SelLength extends the caret from SelStart; writing SelText replaces
    // the selection (single OnChange); writing CaretPos places the caret (collapse).
    property SelStart: Integer read GetSelStart write SetSelStart;
    property SelLength: Integer read GetSelLength write SetSelLength;
    property SelText: string read GetSelText write SetSelText;
    property CaretPos: Integer read GetCaretPos write SetCaretPos;
  published
    property Lines: TStrings read GetLines write SetLines;
    // Whole-document text as one string with platform line breaks (TStrings.Text
    // get/set). Writing replaces all lines, collapses the caret to the origin and
    // fires OnChange.
    property Text: string read GetText write SetText;
    // When True, a Tab key inserts a literal tab char into the text; when False
    // (default) Tab navigates between controls (native TMemo default).
    property WantTabs: Boolean read FWantTabs write SetWantTabs default False;
    // When True (default), Enter inserts a line break; when False, Enter is not
    // consumed so the form's default button can handle it.
    property WantReturns: Boolean read FWantReturns write SetWantReturns default True;
    // Which scrollbars show. Default ssAutoVertical = the historical behaviour (the
    // embedded vertical bar appears on overflow). ssNone hides it entirely;
    // ssVertical/ssBoth force it always-visible. This memo has no HORIZONTAL
    // scrollbar, so the horizontal variants (ssHorizontal/ssBoth/ssAutoHorizontal/
    // ssAutoBoth) honour only their vertical half (horizontal scrolling is a
    // flagged, unimplemented feature).
    property ScrollBars: TScrollStyle read FScrollBars write SetScrollBars
      default ssAutoVertical;
    // Soft word-wrap toggle. Default False (no wrap; long lines later gain
    // horizontal scrolling). True wraps long logical lines into multiple visual
    // rows at word boundaries.
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    // When True, the memo ignores all user edits but still allows caret/selection
    // navigation, Copy and SelectAll; programmatic Lines := still mutates. Cut
    // acts as Copy. Default False.
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    // Caps total content codepoints (typing blocked at the cap; paste truncated
    // to the remaining room). 0 = unlimited. Default 0.
    property MaxLength: Integer read FMaxLength write SetMaxLength default 0;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // Fired when the caret position or selection range changes without a text
    // mutation (arrow keys, click, shift-select, programmatic SetCaret) and after
    // edits that move the caret. Self-guarded: a no-op move never fires.
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
  end;

implementation

constructor TTyMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  Cursor := crIBeam;
  FLines := TStringList.Create;
  FCaretLine := 0;
  FCaretCol := 0;
  FDesiredCol := 0;
  FDesiredX := 0;
  FInVerticalMove := False;
  FSelAnchorLine := 0;
  FSelAnchorCol := 0;
  // Seed the OnSelectionChange guard at the initial caret/anchor so the first real
  // move reports a change (and an initial no-op set stays silent).
  FLastSelCaretLine := 0;
  FLastSelCaretCol := 0;
  FLastSelAnchorLine := 0;
  FLastSelAnchorCol := 0;
  FMouseSelecting := False;
  FTopRow := 0;
  FScrollX := 0;
  FWordWrap := False;
  FVisualRows := nil;
  FVisualRowsValid := False;
  FVisualRowsWidth := -1;
  FScrollBar := nil;
  FSyncingScroll := False;
  FMeasureBmp := nil;
  FForceFocused := False;
  FUndoStack := TTyUndoStack.Create;
  FSuspendUndo := False;
  FReadOnly := False;
  FMaxLength := 0;
  FWantTabs := False;          // Tab navigates by default (native TMemo default)
  FWantReturns := True;        // Enter inserts a line break by default
  FScrollBars := ssAutoVertical;  // historical behaviour: bar on overflow
  FCaretVisible := True;       // solid caret until a real timer toggles it
  FBlinkTimer := nil;          // lazy: created only when HandleAllocated
  FBlinkElapsedMs := 0;
  Width := 200;
  Height := 120;
end;

destructor TTyMemo.Destroy;
begin
  // Free the timer first so its OnTimer callback can never fire mid-teardown.
  FreeAndNil(FBlinkTimer);
  TyQtUninstallIme(FImeHook);   // in case DestroyWnd never ran (Qt-only; no-op elsewhere)
  FUndoStack.Free;
  FMeasureBmp.Free;
  FLines.Free;
  inherited Destroy;
end;

// ---- Blinking caret (Task 10) ----

procedure TTyMemo.EnsureBlinkTimer;
begin
  if FBlinkTimer = nil then
  begin
    FBlinkTimer := TTimer.Create(Self);
    FBlinkTimer.Enabled := False;
    FBlinkTimer.Interval := 530;
    FBlinkTimer.OnTimer := @HandleBlink;
  end;
end;

procedure TTyMemo.HandleBlink(Sender: TObject);
begin
  Inc(FBlinkElapsedMs, FBlinkTimer.Interval);
  FCaretVisible := TyCaretVisible(FBlinkElapsedMs, FBlinkTimer.Interval);
  Invalidate;
end;

procedure TTyMemo.ResetCaretBlink;
begin
  FCaretVisible := True;
  FBlinkElapsedMs := 0;
end;

procedure TTyMemo.DoEnter;
begin
  inherited DoEnter;
  ResetCaretBlink;
  if HandleAllocated then
  begin
    EnsureBlinkTimer;
    FBlinkTimer.Enabled := True;
  end;
end;

procedure TTyMemo.DoExit;
begin
  inherited DoExit;
  if FBlinkTimer <> nil then FBlinkTimer.Enabled := False;
  FCaretVisible := True;
  Invalidate;
end;

function TTyMemo.GetStyleTypeKey: string;
begin
  Result := 'TyMemo';
end;

// ---- Undo/redo machinery ----

function TTyMemo.CaptureState: string;
// Header line: 'caretLine,caretCol,anchorLine,anchorCol,lineCount'#10, then the
// raw FLines joined by #10. We serialize Count (not FLines.Text) so a document
// ending in an empty logical line round-trips exactly: RestoreState rebuilds the
// list line by line and never relies on TStrings.Text dropping trailing breaks.
var
  i: Integer;
begin
  Result := IntToStr(FCaretLine) + ',' + IntToStr(FCaretCol) + ','
    + IntToStr(FSelAnchorLine) + ',' + IntToStr(FSelAnchorCol) + ','
    + IntToStr(FLines.Count) + #10;
  for i := 0 to FLines.Count - 1 do
  begin
    if i > 0 then
      Result := Result + #10;
    Result := Result + FLines[i];
  end;
end;

procedure TTyMemo.RestoreState(const S: string);
var
  NL, FieldStart, i, LineCount: Integer;
  Header, Body: string;
  Fields: array[0..4] of Integer;
  fi, cp: Integer;
  Num: string;
begin
  NL := Pos(#10, S);
  if NL = 0 then Exit;  // malformed; ignore
  Header := Copy(S, 1, NL - 1);
  Body := Copy(S, NL + 1, Length(S) - NL);
  // Parse the five comma-separated header fields.
  for fi := 0 to 4 do Fields[fi] := 0;
  fi := 0;
  Num := '';
  for cp := 1 to Length(Header) do
  begin
    if Header[cp] = ',' then
    begin
      if fi <= 4 then Fields[fi] := StrToIntDef(Num, 0);
      Inc(fi);
      Num := '';
    end
    else
      Num := Num + Header[cp];
  end;
  if fi <= 4 then Fields[fi] := StrToIntDef(Num, 0);
  LineCount := Fields[4];
  // Rebuild FLines from the body by splitting on #10. We add exactly LineCount
  // lines so a document with trailing empty line(s) round-trips (do NOT use
  // FLines.Text, which drops trailing empty lines). When LineCount is 0 the body
  // is empty and FLines ends up Count=0 (the empty-document state).
  FLines.Clear;
  if LineCount > 0 then
  begin
    FieldStart := 1;
    i := 1;
    while i <= Length(Body) do
    begin
      if Body[i] = #10 then
      begin
        FLines.Add(Copy(Body, FieldStart, i - FieldStart));
        FieldStart := i + 1;
      end;
      Inc(i);
    end;
    FLines.Add(Copy(Body, FieldStart, Length(Body) - FieldStart + 1));
    // Defensive: clamp to the recorded line count (the body always has exactly
    // LineCount-1 separators, so this matches, but stay safe against malformed S).
    while FLines.Count > LineCount do
      FLines.Delete(FLines.Count - 1);
    while FLines.Count < LineCount do
      FLines.Add('');
  end;
  FCaretLine := Fields[0];
  FCaretCol := Fields[1];
  FSelAnchorLine := Fields[2];
  FSelAnchorCol := Fields[3];
  FDesiredCol := FCaretCol;
  // Clamp anchor into the restored model (caret is clamped inside AfterEdit).
  if FSelAnchorLine < 0 then FSelAnchorLine := 0;
  if FSelAnchorLine > LineCountLogical - 1 then FSelAnchorLine := LineCountLogical - 1;
  if FSelAnchorCol < 0 then FSelAnchorCol := 0;
  if FSelAnchorCol > LineLen(FSelAnchorLine) then FSelAnchorCol := LineLen(FSelAnchorLine);
  // AfterEdit clamps the caret, keeps it visible, refreshes the scrollbar,
  // repaints and fires OnChange (so undo/redo report a state change for free).
  AfterEdit(Font.PixelsPerInch);
end;

procedure TTyMemo.BeginUndoStep(AKind: Byte);
begin
  if FSuspendUndo then Exit;
  FUndoStack.Push(CaptureState, AKind);
end;

procedure TTyMemo.BreakCoalescing;
begin
  FUndoStack.BreakCoalescing;
end;

procedure TTyMemo.Undo;
begin
  if not Enabled then Exit;
  if FUndoStack.CanUndo then
    RestoreState(FUndoStack.Undo(CaptureState));
end;

procedure TTyMemo.Redo;
begin
  if not Enabled then Exit;
  if FUndoStack.CanRedo then
    RestoreState(FUndoStack.Redo(CaptureState));
end;

function TTyMemo.CanUndo: Boolean;
begin
  Result := FUndoStack.CanUndo;
end;

function TTyMemo.CanRedo: Boolean;
begin
  Result := FUndoStack.CanRedo;
end;

procedure TTyMemo.SetReadOnly(AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  Invalidate;
end;

procedure TTyMemo.SetMaxLength(AValue: Integer);
begin
  if FMaxLength = AValue then Exit;
  FMaxLength := AValue;
end;

procedure TTyMemo.SetWantTabs(AValue: Boolean);
begin
  FWantTabs := AValue;
end;

procedure TTyMemo.SetWantReturns(AValue: Boolean);
begin
  FWantReturns := AValue;
end;

procedure TTyMemo.SetScrollBars(AValue: TScrollStyle);
begin
  if FScrollBars = AValue then Exit;
  FScrollBars := AValue;
  // Re-evaluate the embedded bar's visibility under the new policy.
  UpdateScrollBar;
  Invalidate;
end;

// ---- Flat codepoint-offset <-> (line,col) mapping ----

function TTyMemo.LineColToFlat(ALine, ACol: Integer): Integer;
// Sum of (LineLen + 1 newline) for every line strictly above ALine, plus ACol.
// Clamped into the model so out-of-range inputs map to a valid offset.
var
  i, MaxLine: Integer;
begin
  MaxLine := LineCountLogical - 1;
  if ALine < 0 then ALine := 0;
  if ALine > MaxLine then ALine := MaxLine;
  if ACol < 0 then ACol := 0;
  if ACol > LineLen(ALine) then ACol := LineLen(ALine);
  Result := 0;
  for i := 0 to ALine - 1 do
    Inc(Result, LineLen(i) + 1);  // +1 for the newline between lines i and i+1
  Inc(Result, ACol);
end;

procedure TTyMemo.FlatToLineCol(AOffset: Integer; out ALine, ACol: Integer);
// Walk lines accumulating (LineLen + 1) until AOffset lands within a line's
// [0..LineLen] span (the trailing slot is the position before that line's
// newline). Clamps a negative offset to (0,0) and an over-large offset to the
// end of the last line.
var
  i, MaxLine, Remaining, Span: Integer;
begin
  ALine := 0;
  ACol := 0;
  if AOffset <= 0 then Exit;
  MaxLine := LineCountLogical - 1;
  Remaining := AOffset;
  for i := 0 to MaxLine do
  begin
    Span := LineLen(i);
    if Remaining <= Span then
    begin
      ALine := i;
      ACol := Remaining;
      Exit;
    end;
    // Consume this line plus its trailing newline and move on.
    Dec(Remaining, Span + 1);
    if Remaining < 0 then
    begin
      // AOffset fell on the newline slot itself: bind to end of this line.
      ALine := i;
      ACol := Span;
      Exit;
    end;
  end;
  // Past the end of the document: clamp to the end of the last line.
  ALine := MaxLine;
  ACol := LineLen(MaxLine);
end;

function TTyMemo.GetSelStart: Integer;
begin
  // Flat offset of the ORDERED selection start (lexicographically smaller end).
  Result := LineColToFlat(SelStartLine, SelStartCol);
end;

function TTyMemo.GetSelLength: Integer;
begin
  // |flat(caret) - flat(anchor)| = the codepoint span of the selection.
  Result := Abs(LineColToFlat(FCaretLine, FCaretCol)
    - LineColToFlat(FSelAnchorLine, FSelAnchorCol));
end;

function TTyMemo.GetCaretPos: Integer;
begin
  Result := LineColToFlat(FCaretLine, FCaretCol);
end;

procedure TTyMemo.SetSelStart(AValue: Integer);
var
  L, C: Integer;
begin
  // Native semantics: setting SelStart moves the caret there and collapses the
  // selection (a following SelLength write re-extends it).
  FlatToLineCol(AValue, L, C);
  FCaretLine := L;
  FCaretCol := C;
  ClampCaret;
  FSelAnchorLine := FCaretLine;
  FSelAnchorCol := FCaretCol;
  FDesiredCol := FCaretCol;
  BreakCoalescing;
  UpdateDesiredX(Font.PixelsPerInch);
  EnsureCaretLineVisible(Font.PixelsPerInch);
  Invalidate;
  DoSelectionChange;
end;

procedure TTyMemo.SetSelLength(AValue: Integer);
var
  SS, L, C: Integer;
begin
  // Extend the selection from the current SelStart by AValue codepoints: the
  // anchor stays at SelStart, the caret moves to flat(SelStart)+AValue (clamped).
  if AValue < 0 then AValue := 0;
  SS := GetSelStart;
  // Anchor at SelStart, caret at SelStart + length.
  FlatToLineCol(SS, L, C);
  FSelAnchorLine := L;
  FSelAnchorCol := C;
  FlatToLineCol(SS + AValue, L, C);
  FCaretLine := L;
  FCaretCol := C;
  ClampCaret;
  FDesiredCol := FCaretCol;
  BreakCoalescing;
  UpdateDesiredX(Font.PixelsPerInch);
  EnsureCaretLineVisible(Font.PixelsPerInch);
  Invalidate;
  DoSelectionChange;
end;

procedure TTyMemo.SetSelText(const AValue: string);
var
  HadChange: Boolean;
begin
  if FReadOnly then Exit;
  // Composite op: delete the current selection then insert AValue, all as one
  // undo step firing OnChange exactly once (mirrors the Edit control). Route the
  // insert through the multi-line paste splitter so a value with line breaks
  // becomes multiple lines.
  HadChange := HasSelection or (AValue <> '');
  BeginUndoStep(uskPaste);
  FSuspendUndo := True;
  try
    if HasSelection then DeleteSelection;
    if AValue <> '' then
      InsertTextMultiline(AValue);
  finally
    FSuspendUndo := False;
  end;
  // One OnChange + caret/scroll refresh for the whole replace.
  if HadChange then
    AfterEdit(Font.PixelsPerInch);
end;

procedure TTyMemo.SetCaretPos(AValue: Integer);
var
  L, C: Integer;
begin
  FlatToLineCol(AValue, L, C);
  SetCaret(L, C);  // collapses the selection onto the caret (native semantics)
end;

function TTyMemo.GetText: string;
begin
  // Whole-document string with platform line breaks (TStrings.Text semantics).
  Result := FLines.Text;
end;

procedure TTyMemo.SetText(const AValue: string);
begin
  // Replace all lines from the string (split on line breaks by TStrings.Text),
  // collapse the caret/selection to the origin, refresh layout + fire OnChange.
  BeginUndoStep(uskNone);
  FLines.Text := AValue;
  FCaretLine := 0;
  FCaretCol := 0;
  FSelAnchorLine := 0;
  FSelAnchorCol := 0;
  FDesiredCol := 0;
  AfterEdit(Font.PixelsPerInch);
end;

function TTyMemo.ContentCodepointCount: Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to FLines.Count - 1 do Inc(Result, UTF8Length(FLines[i]));
end;

function TTyMemo.GetLines: TStrings;
begin
  Result := FLines;
end;

procedure TTyMemo.SetLines(AValue: TStrings);
begin
  // Capture a fresh (non-typing) undo step only when the assignment actually
  // changes the content, so a no-op reassign does not push a spurious step and
  // TestSetLinesClampsCaret (which never touches undo) is unaffected.
  if (AValue = nil) or (AValue.Text <> FLines.Text) then
    BeginUndoStep(uskNone);
  FLines.Assign(AValue);
  ClampCaret;
  // The text model changed: any cached wrap layout is stale.
  InvalidateVisualRows;
  // Clamp the window and refresh the scrollbar in case the row count changed.
  if FTopRow > MaxTopLine then FTopRow := MaxTopLine;
  if FTopRow < 0 then FTopRow := 0;
  UpdateScrollBar;
  Invalidate;
end;

function TTyMemo.LineCountLogical: Integer;
begin
  // An empty model is still one visible line (caret can sit on line 0).
  Result := FLines.Count;
  if Result < 1 then
    Result := 1;
end;

procedure TTyMemo.ClampCaret;
var
  MaxLine, CurLen: Integer;
begin
  MaxLine := LineCountLogical - 1;
  if FCaretLine < 0 then FCaretLine := 0;
  if FCaretLine > MaxLine then FCaretLine := MaxLine;
  // Length of the caret's line in codepoints (0 for the synthetic empty line).
  CurLen := LineLen(FCaretLine);
  if FCaretCol < 0 then FCaretCol := 0;
  if FCaretCol > CurLen then FCaretCol := CurLen;
  if FDesiredCol < 0 then FDesiredCol := 0;
end;

function TTyMemo.RowBaseAbsX(AVisualRow, APPI: Integer): Integer;
// Absolute (full-line) device-x at which visual row AVisualRow's segment BEGINS,
// i.e. ColPixelXAt(line, StartCol). A continuation segment is drawn shifted left by
// this minus TextStartX so its first codepoint sits at the content left; the
// difference between a caret's absolute x and this base is the on-SCREEN x of the
// caret within the row. For a full-width row (StartCol=0) this is TextStartX.
var
  Line: string;
begin
  EnsureVisualRows(APPI);
  if (AVisualRow < 0) or (AVisualRow > High(FVisualRows)) then
    Exit(TextStartX(APPI));
  if FVisualRows[AVisualRow].Line < FLines.Count then
    Line := FLines[FVisualRows[AVisualRow].Line]
  else
    Line := '';
  Result := ColPixelXAt(Line, FVisualRows[AVisualRow].StartCol, APPI);
end;

procedure TTyMemo.UpdateDesiredX(APPI: Integer);
var
  CW, VRow, CaretAbsX: Integer;
begin
  // FDesiredX is the caret's on-SCREEN x within its visual row = the caret's
  // absolute full-line x MINUS the row's base absolute x. This screen-relative
  // form is stable across rows (the quantity a user perceives as "the column"),
  // so a wrap Up/Down can re-project it onto a different row's coordinate frame.
  CW := ContentWidthFor(APPI);
  CaretToVisual(FCaretLine, FCaretCol, CW, APPI, VRow, CaretAbsX);
  FDesiredX := CaretAbsX - RowBaseAbsX(VRow, APPI);
  if FDesiredX < 0 then FDesiredX := 0;
end;

procedure TTyMemo.MoveCaretByVisualRow(ADelta, APPI: Integer);
var
  CW, CurRow, CaretAbsX, TargetRow, MaxRow, TargetAbsX, NewLine, NewCol: Integer;
begin
  CW := ContentWidthFor(APPI);
  EnsureVisualRows(APPI);
  MaxRow := High(FVisualRows);
  if MaxRow < 0 then Exit;   // no rows (defensive)
  // Current owning visual row.
  CaretToVisual(FCaretLine, FCaretCol, CW, APPI, CurRow, CaretAbsX);
  TargetRow := CurRow + ADelta;
  // Guards mirror the no-wrap FCaretLine>0 / <MaxLine: clamp into [0, MaxRow] so a
  // top-row Up or bottom-row Down is a no-op (the caret stays put).
  if TargetRow < 0 then TargetRow := 0;
  if TargetRow > MaxRow then TargetRow := MaxRow;
  // Re-project the preserved on-SCREEN desired-x onto the TARGET row's coordinate
  // frame: target absolute x = screen x + target row base. VisualToCaret then
  // resolves the column in its (absolute-x) contract and clamps into the segment,
  // so the caret lands at the same on-screen column on the target row.
  TargetAbsX := FDesiredX + RowBaseAbsX(TargetRow, APPI);
  VisualToCaret(TargetRow, TargetAbsX, CW, APPI, NewLine, NewCol);
  FCaretLine := NewLine;
  FCaretCol := NewCol;
  // FDesiredX intentionally NOT refreshed: a run of Up/Down tracks the original x.
end;

function TTyMemo.CaretRowStartCol(APPI: Integer): Integer;
var
  CW, VRow, CaretX: Integer;
begin
  CW := ContentWidthFor(APPI);
  EnsureVisualRows(APPI);
  CaretToVisual(FCaretLine, FCaretCol, CW, APPI, VRow, CaretX);
  if (VRow >= 0) and (VRow <= High(FVisualRows)) then
    Result := FVisualRows[VRow].StartCol
  else
    Result := 0;
end;

function TTyMemo.CaretRowEndCol(APPI: Integer): Integer;
var
  CW, VRow, CaretX: Integer;
begin
  CW := ContentWidthFor(APPI);
  EnsureVisualRows(APPI);
  CaretToVisual(FCaretLine, FCaretCol, CW, APPI, VRow, CaretX);
  if (VRow >= 0) and (VRow <= High(FVisualRows)) then
    Result := FVisualRows[VRow].EndCol
  else
    Result := LineLen(FCaretLine);
end;

function TTyMemo.CaretLine: Integer;
begin
  Result := FCaretLine;
end;

function TTyMemo.CaretCol: Integer;
begin
  Result := FCaretCol;
end;

procedure TTyMemo.SetCaret(ALine, ACol: Integer);
begin
  FCaretLine := ALine;
  FCaretCol := ACol;
  ClampCaret;
  // A direct caret write collapses any selection (mirrors TTyEdit.SetCaretPos).
  FSelAnchorLine := FCaretLine;
  FSelAnchorCol := FCaretCol;
  FDesiredCol := FCaretCol;
  // A deliberate caret placement is a horizontal move: refresh the desired x so a
  // following wrap Up/Down tracks the placed caret's x (not a stale value).
  UpdateDesiredX(Font.PixelsPerInch);
  Invalidate;
  // A programmatic caret placement is a caret/selection change (self-guarded: a
  // re-set to the same caret+anchor stays silent).
  DoSelectionChange;
end;

procedure TTyMemo.SetSelAnchor(ALine, ACol: Integer);
var
  MaxLine, CurLen: Integer;
begin
  // Clamp the anchor into the model exactly like the caret (line then col).
  MaxLine := LineCountLogical - 1;
  if ALine < 0 then ALine := 0;
  if ALine > MaxLine then ALine := MaxLine;
  CurLen := LineLen(ALine);
  if ACol < 0 then ACol := 0;
  if ACol > CurLen then ACol := CurLen;
  FSelAnchorLine := ALine;
  FSelAnchorCol := ACol;
  Invalidate;
end;

// ---- 2D selection read/mutate helpers ----

function TTyMemo.HasSelection: Boolean;
begin
  Result := (FSelAnchorLine <> FCaretLine) or (FSelAnchorCol <> FCaretCol);
end;

procedure TTyMemo.GetOrderedSel(out SL, SC, EL, EC: Integer);
var
  AnchorFirst: Boolean;
begin
  // (FSelAnchorLine,FSelAnchorCol) <= (FCaretLine,FCaretCol) lexicographically?
  AnchorFirst := (FSelAnchorLine < FCaretLine)
    or ((FSelAnchorLine = FCaretLine) and (FSelAnchorCol <= FCaretCol));
  if AnchorFirst then
  begin
    SL := FSelAnchorLine; SC := FSelAnchorCol;
    EL := FCaretLine;     EC := FCaretCol;
  end
  else
  begin
    SL := FCaretLine;     SC := FCaretCol;
    EL := FSelAnchorLine; EC := FSelAnchorCol;
  end;
end;

function TTyMemo.SelStartLine: Integer;
var
  SL, SC, EL, EC: Integer;
begin
  GetOrderedSel(SL, SC, EL, EC);
  Result := SL;
end;

function TTyMemo.SelStartCol: Integer;
var
  SL, SC, EL, EC: Integer;
begin
  GetOrderedSel(SL, SC, EL, EC);
  Result := SC;
end;

function TTyMemo.SelEndLine: Integer;
var
  SL, SC, EL, EC: Integer;
begin
  GetOrderedSel(SL, SC, EL, EC);
  Result := EL;
end;

function TTyMemo.SelEndCol: Integer;
var
  SL, SC, EL, EC: Integer;
begin
  GetOrderedSel(SL, SC, EL, EC);
  Result := EC;
end;

function TTyMemo.GetSelText: string;
var
  SL, SC, EL, EC, i: Integer;
  Head, Tail: string;
begin
  Result := '';
  if not HasSelection then Exit;
  GetOrderedSel(SL, SC, EL, EC);
  if SL = EL then
  begin
    // Single line: the slice from SC..EC on that line.
    if SL < FLines.Count then
      Result := UTF8Copy(FLines[SL], SC + 1, EC - SC);
    Exit;
  end;
  // Multi-line: first-line tail + whole interior lines + last-line head.
  if SL < FLines.Count then
    Tail := UTF8Copy(FLines[SL], SC + 1, LineLen(SL) - SC)
  else
    Tail := '';
  Result := Tail;
  for i := SL + 1 to EL - 1 do
  begin
    if i < FLines.Count then
      Result := Result + LineEnding + FLines[i]
    else
      Result := Result + LineEnding;
  end;
  if EL < FLines.Count then
    Head := UTF8Copy(FLines[EL], 1, EC)
  else
    Head := '';
  Result := Result + LineEnding + Head;
end;

procedure TTyMemo.SelectAll;
var
  LastLine: Integer;
begin
  FSelAnchorLine := 0;
  FSelAnchorCol := 0;
  LastLine := LineCountLogical - 1;
  FCaretLine := LastLine;
  FCaretCol := LineLen(LastLine);
  FDesiredCol := FCaretCol;
  EnsureCaretLineVisible(Font.PixelsPerInch);
  Invalidate;
  // A selection change ends a typing-coalesce run.
  BreakCoalescing;
  // Select-all extended the selection range: report it (self-guarded).
  DoSelectionChange;
end;

procedure TTyMemo.ClearSelection;
begin
  FSelAnchorLine := FCaretLine;
  FSelAnchorCol := FCaretCol;
  Invalidate;
  // A selection change ends a typing-coalesce run.
  BreakCoalescing;
  // Collapsing the selection (anchor->caret) is a selection-range change (guarded).
  DoSelectionChange;
end;

procedure TTyMemo.SetForceFocused(AValue: Boolean);
begin
  if FForceFocused = AValue then Exit;
  FForceFocused := AValue;
  Invalidate;
end;

function TTyMemo.LineLen(ALineIndex: Integer): Integer;
begin
  if (ALineIndex >= 0) and (ALineIndex < FLines.Count) then
    Result := UTF8Length(FLines[ALineIndex])
  else
    Result := 0;  // synthetic empty line (model has zero lines)
end;

procedure TTyMemo.DoChange;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyMemo.DoSelectionChange;
begin
  // Self-guard: only fire when the caret OR the anchor actually moved since the
  // last fire. This lets every caret/selection funnel call DoSelectionChange
  // unconditionally without double-firing (a no-op set stays silent) or spamming.
  if (FCaretLine = FLastSelCaretLine) and (FCaretCol = FLastSelCaretCol)
    and (FSelAnchorLine = FLastSelAnchorLine)
    and (FSelAnchorCol = FLastSelAnchorCol) then
    Exit;
  FLastSelCaretLine := FCaretLine;
  FLastSelCaretCol := FCaretCol;
  FLastSelAnchorLine := FSelAnchorLine;
  FLastSelAnchorCol := FSelAnchorCol;
  if Assigned(FOnSelectionChange) then
    FOnSelectionChange(Self);
end;

function TTyMemo.VisibleLineCount(APPI: Integer): Integer;
var
  S: TTyStyleSet;
  ContentH, LH: Integer;
begin
  S := CurrentStyle;
  // Content height = client height minus top+bottom padding (scaled).
  ContentH := ClientHeight - MulDiv(S.Padding.Top, APPI, 96)
    - MulDiv(S.Padding.Bottom, APPI, 96);
  LH := LineHeight(APPI);
  if LH < 1 then LH := 1;
  Result := ContentH div LH;
  if Result < 1 then
    Result := 1;
end;

procedure TTyMemo.EnsureCaretLineVisible(APPI: Integer);
var
  VR, MaxTop, CaretVR: Integer;
begin
  VR := VisibleRows;
  // Resolve the caret's VISUAL ROW (WordWrap=False: == FCaretLine, identity).
  CaretVR := CaretVisualRow(APPI);
  // Scroll up so the caret row is the new top.
  if CaretVR < FTopRow then
    FTopRow := CaretVR;
  // Scroll down so the caret row is the last fully visible row: caret in
  // [FTopRow, FTopRow+VR).
  if CaretVR > FTopRow + VR - 1 then
    FTopRow := CaretVR - VR + 1;
  // Never scroll past the last valid window / below 0.
  MaxTop := MaxTopLine;
  if FTopRow > MaxTop then FTopRow := MaxTop;
  if FTopRow < 0 then FTopRow := 0;
end;

// ---- Horizontal scrolling (WordWrap=False only) ----
// TTyEdit's FScrollX idiom generalised to the multi-line model: a single
// per-memo horizontal pixel offset. MaxScroll is driven by the WIDEST logical
// line (so the longest line can scroll fully into view), while EnsureCaretXVisible
// measures the CARET'S line to keep the caret inside the viewport. With short text
// that fits, neither method ever raises FScrollX above 0, so the no-wrap render
// stays byte-identical to today (FScrollX = 0 collapses every X term).

function TTyMemo.WidestLineWidth(APPI: Integer): Integer;
var
  i, W: Integer;
  Widths: TTyIntArray;
begin
  Result := 0;
  for i := 0 to FLines.Count - 1 do
  begin
    Widths := MeasureLineWidths(FLines[i], APPI);
    W := Widths[Length(Widths) - 1];
    if W > Result then Result := W;
  end;
end;

procedure TTyMemo.ClampScrollX(APPI: Integer);
var
  ViewWidth, MaxScroll: Integer;
begin
  // Wrap mode never scrolls horizontally: pin to 0.
  if FWordWrap then
  begin
    FScrollX := 0;
    Exit;
  end;
  ViewWidth := ContentWidthFor(APPI);
  if ViewWidth < 0 then ViewWidth := 0;
  MaxScroll := WidestLineWidth(APPI) - ViewWidth;
  if MaxScroll < 0 then MaxScroll := 0;
  if FScrollX > MaxScroll then FScrollX := MaxScroll;
  if FScrollX < 0 then FScrollX := 0;
end;

procedure TTyMemo.EnsureCaretXVisible(APPI: Integer);
var
  StartX, ViewWidth, ViewRight, Margin, MaxScroll, CaretPx: Integer;
  CaretLineStr: string;
begin
  // Wrap mode never scrolls horizontally: pin to 0.
  if FWordWrap then
  begin
    FScrollX := 0;
    Exit;
  end;
  StartX := TextStartX(APPI);
  ViewWidth := ContentWidthFor(APPI);
  if ViewWidth < 0 then ViewWidth := 0;
  ViewRight := StartX + ViewWidth;
  // 2 scaled device px margin (mirrors TTyEdit.EnsureCaretVisible).
  Margin := MulDiv(2, APPI, 96);
  // Caret x on its OWN line (absolute, before the scroll shift).
  if FCaretLine < FLines.Count then
    CaretLineStr := FLines[FCaretLine]
  else
    CaretLineStr := '';
  CaretPx := ColPixelXAt(CaretLineStr, FCaretCol, APPI);
  // Scroll right when the caret is past the right edge.
  if CaretPx - FScrollX > ViewRight - Margin then
    FScrollX := CaretPx - (ViewRight - Margin);
  // Scroll left when the caret is before the left edge.
  if CaretPx - FScrollX < StartX + Margin then
    FScrollX := CaretPx - (StartX + Margin);
  // Clamp into [0, widestLineWidth - ViewWidth].
  MaxScroll := WidestLineWidth(APPI) - ViewWidth;
  if MaxScroll < 0 then MaxScroll := 0;
  if FScrollX > MaxScroll then FScrollX := MaxScroll;
  if FScrollX < 0 then FScrollX := 0;
end;

// ---- Vertical scrolling (sections 3-6 lifted from TTyListBox; FItems.Count ->
// LineCountLogical, ScaledItemHeight -> LineHeight) ----

function TTyMemo.VisibleRows: Integer;
var
  LH: Integer;
begin
  LH := LineHeight(Font.PixelsPerInch);
  if LH < 1 then LH := 1;
  // Use Height rather than ClientHeight so the result is testable headlessly
  // (in headless LCL without a native handle, ClientHeight can lag behind
  // SetBounds). For this borderless control Height = ClientHeight at runtime.
  Result := Height div LH;
  if Result < 1 then Result := 1;
end;

function TTyMemo.TotalVisualRows(APPI: Integer): Integer;
begin
  EnsureVisualRows(APPI);
  Result := Length(FVisualRows);
  if Result < 1 then Result := 1;   // a non-empty model always has >= 1 row
end;

function TTyMemo.MaxTopLine: Integer;
begin
  // Row-based: TotalVisualRows - VisibleRows. For WordWrap=False this equals the
  // old LineCountLogical - VisibleRows (one visual row per logical line).
  Result := TotalVisualRows(Font.PixelsPerInch) - VisibleRows;
  if Result < 0 then Result := 0;
end;

function TTyMemo.TopRow: Integer;
begin
  Result := FTopRow;
end;

function TTyMemo.TopLine: Integer;
begin
  // Map the top visual row back to its logical line. WordWrap=False: FTopRow is
  // the top logical line (identity). Guard against a stale/empty cache.
  EnsureVisualRows(Font.PixelsPerInch);
  if (FTopRow >= 0) and (FTopRow <= High(FVisualRows)) then
    Result := FVisualRows[FTopRow].Line
  else
    Result := 0;
end;

function TTyMemo.CaretVisualRow(APPI: Integer): Integer;
var
  CW, VRow, CaretX: Integer;
begin
  EnsureVisualRows(APPI);
  CW := ContentWidthFor(APPI);
  CaretToVisual(FCaretLine, FCaretCol, CW, APPI, VRow, CaretX);
  Result := VRow;
end;

procedure TTyMemo.SetTopLine(AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < 0 then Clamped := 0;
  if Clamped > MaxTopLine then Clamped := MaxTopLine;
  if FTopRow = Clamped then Exit;
  FTopRow := Clamped;
  // Sync scrollbar position (guard reentrancy).
  if (not FSyncingScroll) and (FScrollBar <> nil) and FScrollBar.Visible then
  begin
    FSyncingScroll := True;
    try
      FScrollBar.Position := FTopRow;
    finally
      FSyncingScroll := False;
    end;
  end;
  Invalidate;
end;

procedure TTyMemo.ScrollBarChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FSyncingScroll := True;
  try
    SetTopLine(FScrollBar.Position);
  finally
    FSyncingScroll := False;
  end;
end;

procedure TTyMemo.UpdateScrollBar;
var
  VR, MaxPos, MaxTop, Total: Integer;
  WasVisible, WantBar: Boolean;
begin
  VR := VisibleRows;
  Total := TotalVisualRows(Font.PixelsPerInch);
  // Clamp FTopRow in case Lines were mutated directly (without SetLines).
  MaxTop := Total - VR;
  if MaxTop < 0 then MaxTop := 0;
  if FTopRow > MaxTop then FTopRow := MaxTop;
  // ScrollBars policy decides whether the embedded vertical bar shows:
  //   ssNone                      -> never (hidden even under overflow);
  //   ssVertical / ssBoth / ...   -> always (force visible even when it fits);
  //   ssAutoVertical (default) and the horizontal variants we cannot honour
  //                               -> on overflow only (the historical behaviour).
  // This memo has NO horizontal scrollbar, so ssHorizontal/ssBoth/ssAutoHorizontal/
  // ssAutoBoth degrade to the vertical policy (their horizontal half is a flagged,
  // unimplemented feature). ssVertical/ssBoth force-show; the rest are auto.
  case FScrollBars of
    ssNone:
      WantBar := False;
    ssVertical, ssBoth:
      WantBar := True;
  else
    WantBar := Total > VR;   // ssAutoVertical / ssAutoBoth / horizontal-only -> auto
  end;
  if WantBar then
  begin
    // Capture the bar's prior visibility BEFORE creating/flipping it. A bar that
    // does not yet exist counts as previously-hidden: TControl.Visible defaults
    // to True, so reading FScrollBar.Visible AFTER creation would falsely report
    // the first-ever creation as "already visible" and skip the narrow rebuild
    // below — undersizing Max by the rows the stolen SBWidth pushes off-screen.
    WasVisible := (FScrollBar <> nil) and FScrollBar.Visible;
    // Ensure scrollbar created.
    if FScrollBar = nil then
    begin
      FScrollBar := TTyScrollBar.Create(Self);
      FScrollBar.Parent := Self;
      FScrollBar.Kind := sbVertical;
      FScrollBar.Align := alRight;
      FScrollBar.OnChange := @ScrollBarChange;
      // Embedded scrollbar drives content scrolling: keep it instant (no thumb
      // glide) so scrolling never lags behind the wheel/keyboard.
      FScrollBar.AnimationsEnabled := False;
    end;
    // Update DPI-dependent width and controller every call so DPI changes take effect.
    FScrollBar.Width := MulDiv(TyScrollbarSize, Font.PixelsPerInch, 96);
    FScrollBar.Controller := Self.Controller;
    // SBWidth feedback (matters when WordWrap=True): making the bar visible steals
    // SBWidth from the content width, which narrows the wrap and can yield MORE
    // visual rows than the (wider) pre-scrollbar Total we just computed. If the
    // visibility is flipping hidden->visible now, flip it FIRST, invalidate the
    // row cache (so it rebuilds at the narrowed content width) and recompute Total
    // so the range below covers EVERY settled row — otherwise the last wrapped
    // rows could never scroll into view. No-op for WordWrap=False (content width
    // is independent of the bar there, so the recomputed Total is unchanged).
    if not WasVisible then
    begin
      FScrollBar.Visible := True;
      if FWordWrap then
      begin
        InvalidateVisualRows;
        Total := TotalVisualRows(Font.PixelsPerInch);
        MaxTop := Total - VR;
        if MaxTop < 0 then MaxTop := 0;
        if FTopRow > MaxTop then FTopRow := MaxTop;
      end;
    end;
    MaxPos := Total - VR;
    if MaxPos < 0 then MaxPos := 0;
    FSyncingScroll := True;
    try
      FScrollBar.Min := 0;
      FScrollBar.Max := MaxPos;
      FScrollBar.PageSize := VR;
      FScrollBar.Position := FTopRow;
    finally
      FSyncingScroll := False;
    end;
    FScrollBar.Visible := True;
  end
  else
  begin
    if FScrollBar <> nil then
      FScrollBar.Visible := False;
  end;
end;

function TTyMemo.ScrollBarVisible: Boolean;
begin
  Result := (FScrollBar <> nil) and FScrollBar.Visible;
end;

procedure TTyMemo.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  APPI, LH, Row, CW, NewLine, NewCol: Integer;
begin
  if not Enabled then Exit;          // v1.5 policy: ignore input when disabled
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  APPI := Font.PixelsPerInch;
  LH := LineHeight(APPI);
  CW := ContentWidthFor(APPI);
  EnsureVisualRows(APPI);
  // Y -> VISUAL ROW (mirror TTyListBox row math, but over visual rows). For
  // WordWrap=False FTopRow == the top logical line and each row is a full line,
  // so this reduces to the legacy logical-line hit-test exactly. VisualToCaret
  // resolves the (line,col) under X clamped to the row's segment.
  Row := FTopRow + (Y div LH);
  VisualToCaret(Row, X, CW, APPI, NewLine, NewCol);
  FCaretLine := NewLine;
  FCaretCol := NewCol;
  FDesiredCol := FCaretCol;
  // A click is a horizontal move: refresh the desired x for a following wrap Up/Down.
  UpdateDesiredX(APPI);
  // A fresh left-click sets the anchor onto the caret (collapsing any prior
  // selection) and begins a drag (mirrors TTyEdit.MouseDown). This is additive:
  // existing click tests assert only the resolved caret position, unaffected.
  FSelAnchorLine := FCaretLine;
  FSelAnchorCol := FCaretCol;
  FMouseSelecting := True;
  // A mouse-driven caret move ends a typing-coalesce run.
  BreakCoalescing;
  try
    if CanFocus then
      SetFocus;
  except
    // Ignore focus errors in headless/test environments.
  end;
  Invalidate;
  // A click moved the caret and collapsed the selection (self-guarded no-op safe).
  DoSelectionChange;
end;

procedure TTyMemo.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  APPI, LH, Row, CW, NewLine, NewCol: Integer;
begin
  if not Enabled then Exit;          // v1.5 policy: ignore input when disabled
  inherited MouseMove(Shift, X, Y);
  if not FMouseSelecting then Exit;
  // Re-hit-test under the pointer using the SAME visual-row math as MouseDown;
  // move the caret only — the anchor stays fixed so the selection extends as we
  // drag.
  APPI := Font.PixelsPerInch;
  LH := LineHeight(APPI);
  CW := ContentWidthFor(APPI);
  EnsureVisualRows(APPI);
  Row := FTopRow + (Y div LH);
  VisualToCaret(Row, X, CW, APPI, NewLine, NewCol);
  FCaretLine := NewLine;
  FCaretCol := NewCol;
  FDesiredCol := FCaretCol;
  // A drag is a horizontal move: refresh the desired x for a following wrap Up/Down.
  UpdateDesiredX(APPI);
  Invalidate;
  // A drag extended the selection (caret moved, anchor fixed): report it (guarded).
  DoSelectionChange;
end;

procedure TTyMemo.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
    FMouseSelecting := False;
end;

function TTyMemo.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  Delta: Integer;
begin
  if not Enabled then Exit(False);
  // Let the user's OnMouseWheel handler run first; if it consumes the event, stop.
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then
  begin
    Result := True;
    Exit;
  end;
  // WheelDelta > 0 = scroll up (FTopRow decreases)
  // WheelDelta < 0 = scroll down (FTopRow increases). Scrolls +/-3 VISUAL ROWS.
  if WheelDelta > 0 then
    Delta := -3
  else
    Delta := 3;
  SetTopLine(FTopRow + Delta);
  Result := True;
end;

procedure TTyMemo.Resize;
begin
  inherited Resize;
  // A width change alters the wrap layout (EnsureVisualRows also re-checks the
  // width, but invalidate explicitly so a same-width re-layout is never skipped
  // when the scrollbar visibility flipped).
  InvalidateVisualRows;
  UpdateScrollBar;
  // A width change alters the horizontal viewport: re-clamp the scroll offset.
  ClampScrollX(Font.PixelsPerInch);
end;

procedure TTyMemo.AfterEdit(APPI: Integer);
begin
  ClampCaret;
  // The text model changed: any cached wrap layout is stale.
  InvalidateVisualRows;
  EnsureCaretLineVisible(APPI);
  // Keep the caret inside the horizontal viewport (no-op for fitting text / wrap).
  EnsureCaretXVisible(APPI);
  // An edit is a horizontal move: refresh the desired x so a later wrap Up/Down
  // tracks the new caret x (rebuild the layout first via the invalidate above).
  if not FInVerticalMove then
    UpdateDesiredX(APPI);
  UpdateScrollBar;
  ResetCaretBlink;
  Invalidate;
  DoChange;
  // An edit that moves the caret is also a selection/caret change (self-guarded).
  DoSelectionChange;
end;

procedure TTyMemo.AfterCaretMove(APPI: Integer);
begin
  ClampCaret;
  EnsureCaretLineVisible(APPI);
  // Keep the caret inside the horizontal viewport (no-op for fitting text / wrap).
  EnsureCaretXVisible(APPI);
  // Refresh the desired x for wrap Up/Down on every HORIZONTAL move; a vertical
  // move (FInVerticalMove) preserves it so a run of Up/Down tracks the original x.
  if not FInVerticalMove then
    UpdateDesiredX(APPI);
  ResetCaretBlink;
  Invalidate;
  // Pure caret motion ends any typing-coalesce run: the next typed character
  // starts a fresh undo step. AfterCaretMove is the shared post-routine for all
  // keyboard navigation branches (VK_LEFT/RIGHT/UP/DOWN/HOME/END), so breaking
  // here covers them uniformly.
  BreakCoalescing;
  // Keyboard navigation / shift-select changed the caret/selection (self-guarded).
  DoSelectionChange;
end;

// ---- Model mutators (pure UTF8 splice on FLines) ----

procedure TTyMemo.DoInsertText(const AStr: string);
// Splice AStr into the current line at FCaretCol (codepoint index); advance the
// caret past the inserted text. Mirrors TTyEdit.InjectStringAt per-line.
var
  Cur, Before, After: string;
  L: Integer;
begin
  if AStr = '' then Exit;
  // Ensure the model has a backing line for the caret.
  if FLines.Count = 0 then
    FLines.Add('');
  Cur := FLines[FCaretLine];
  L := UTF8Length(Cur);
  if FCaretCol > L then FCaretCol := L;
  Before := UTF8Copy(Cur, 1, FCaretCol);
  After  := UTF8Copy(Cur, FCaretCol + 1, L - FCaretCol);
  FLines[FCaretLine] := Before + AStr + After;
  FCaretCol := FCaretCol + UTF8Length(AStr);
end;

procedure TTyMemo.DoSplitLine;
// Split the current line at FCaretCol into two logical lines; caret moves to the
// start of the new (lower) line.
var
  Cur, Before, After: string;
  L: Integer;
begin
  if FLines.Count = 0 then
    FLines.Add('');
  Cur := FLines[FCaretLine];
  L := UTF8Length(Cur);
  if FCaretCol > L then FCaretCol := L;
  Before := UTF8Copy(Cur, 1, FCaretCol);
  After  := UTF8Copy(Cur, FCaretCol + 1, L - FCaretCol);
  FLines[FCaretLine] := Before;
  FLines.Insert(FCaretLine + 1, After);
  Inc(FCaretLine);
  FCaretCol := 0;
end;

procedure TTyMemo.DoBackspace;
// At col>0: delete the previous codepoint on the current line.
// At col 0, line>0: merge the current line onto the end of the previous line,
// caret landing at the join. At (0,0): no-op (caller checks and skips OnChange).
var
  Cur, Prev, Before, After: string;
  L, PrevLen: Integer;
begin
  if FCaretCol > 0 then
  begin
    Cur := FLines[FCaretLine];
    L := UTF8Length(Cur);
    Before := UTF8Copy(Cur, 1, FCaretCol - 1);
    After  := UTF8Copy(Cur, FCaretCol + 1, L - FCaretCol);
    FLines[FCaretLine] := Before + After;
    Dec(FCaretCol);
  end
  else
  begin
    // col = 0, must be line > 0 (caller guards the (0,0) no-op).
    Prev := FLines[FCaretLine - 1];
    Cur  := FLines[FCaretLine];
    PrevLen := UTF8Length(Prev);
    FLines[FCaretLine - 1] := Prev + Cur;
    FLines.Delete(FCaretLine);
    Dec(FCaretLine);
    FCaretCol := PrevLen;
  end;
end;

procedure TTyMemo.DoDelete;
// Before line end: delete the next codepoint on the current line.
// At line end with a following line: merge the next line up (caret stays).
// At the very end of the document: no-op (caller checks and skips OnChange).
var
  Cur, Nxt, Before, After: string;
  L: Integer;
begin
  Cur := FLines[FCaretLine];
  L := UTF8Length(Cur);
  if FCaretCol < L then
  begin
    Before := UTF8Copy(Cur, 1, FCaretCol);
    After  := UTF8Copy(Cur, FCaretCol + 2, L - FCaretCol - 1);
    FLines[FCaretLine] := Before + After;
  end
  else
  begin
    // At end of line; merge the following line up (caller guards end-of-doc).
    Nxt := FLines[FCaretLine + 1];
    FLines[FCaretLine] := Cur + Nxt;
    FLines.Delete(FCaretLine + 1);
    // caret stays at (FCaretLine, FCaretCol = L)
  end;
end;

// ---- Per-line word-boundary helpers (ported from TTyEdit) ----

function TTyMemo.IsWordCodepoint(const CP: string): Boolean;
// Verbatim from TTyEdit.IsWordCodepoint. A word codepoint is anything that is
// not whitespace and not ASCII punctuation. Whitespace: #32, #9, U+00A0. ASCII
// punctuation: ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ ` { | } ~
// All other codepoints (letters, digits, CJK, emoji, combining marks) are words.
const
  ASCII_PUNCT = '!"#$%&''()*+,-./:;<=>?@[\]^`{|}~';
  NBSP = #$C2#$A0;  // U+00A0 in UTF-8
begin
  if CP = '' then
    Exit(False);
  // Whitespace
  if (CP = #32) or (CP = #9) or (CP = NBSP) then
    Exit(False);
  // ASCII punctuation (single-byte codepoints only)
  if (Length(CP) = 1) and (Pos(CP[1], ASCII_PUNCT) > 0) then
    Exit(False);
  Result := True;
end;

function TTyMemo.NextWordBoundary(const ALine: string; AIdx: Integer): Integer;
// TTyEdit.NextWordBoundary generalised to a passed line string.
var
  i, Len: Integer;
begin
  Len := UTF8Length(ALine);
  if AIdx < 0 then AIdx := 0;
  if AIdx > Len then AIdx := Len;
  i := AIdx;
  // Skip the current word run, then skip the following non-word run.
  while (i < Len) and IsWordCodepoint(UTF8Copy(ALine, i + 1, 1)) do
    Inc(i);
  while (i < Len) and not IsWordCodepoint(UTF8Copy(ALine, i + 1, 1)) do
    Inc(i);
  Result := i;
end;

function TTyMemo.PrevWordBoundary(const ALine: string; AIdx: Integer): Integer;
// TTyEdit.PrevWordBoundary generalised to a passed line string.
var
  i, Len: Integer;
begin
  Len := UTF8Length(ALine);
  if AIdx < 0 then AIdx := 0;
  if AIdx > Len then AIdx := Len;
  i := AIdx;
  // Skip the preceding non-word run, then skip the preceding word run.
  while (i > 0) and not IsWordCodepoint(UTF8Copy(ALine, i, 1)) do
    Dec(i);
  while (i > 0) and IsWordCodepoint(UTF8Copy(ALine, i, 1)) do
    Dec(i);
  Result := i;
end;

// ---- Pure visual-row model ----

function TTyMemo.BuildVisualRows(AContentWidth, APPI: Integer): TTyVisualRowArray;
// Greedy wrap. For each logical line, when WordWrap=False emit one full-width
// row [0,LineLen). When WordWrap=True pack codepoints into the content width:
//   - measure cumulative prefix widths once per line;
//   - from a segment StartCol, find Fit = the largest col whose width relative to
//     StartCol still fits AContentWidth (at least StartCol+1 so progress is
//     guaranteed even for an over-long single glyph);
//   - prefer to break at the last WORD boundary in (StartCol, Fit] so we cut at a
//     space, not mid-word; if there is no boundary past StartCol within the fit
//     (one long word / a CJK run), char-break at Fit.
// An empty logical line (or a degenerate non-positive width) emits one row.
var
  li, n, Len, StartCol, Fit, BreakCol, Cand, BaseX: Integer;
  Line: string;
  Widths: TTyIntArray;

  procedure AddRow(ALine, ASC, AEC: Integer);
  begin
    SetLength(Result, n + 1);
    Result[n].Line := ALine;
    Result[n].StartCol := ASC;
    Result[n].EndCol := AEC;
    Inc(n);
  end;

begin
  Result := nil;
  n := 0;
  for li := 0 to LineCountLogical - 1 do
  begin
    if li < FLines.Count then
      Line := FLines[li]
    else
      Line := '';
    Len := UTF8Length(Line);

    if (not FWordWrap) or (Len = 0) or (AContentWidth <= 0) then
    begin
      // No-wrap (identity), empty line, or unusable width => one full row.
      AddRow(li, 0, Len);
      Continue;
    end;

    Widths := MeasureLineWidths(Line, APPI);
    StartCol := 0;
    while StartCol < Len do
    begin
      BaseX := Widths[StartCol];
      // Largest Fit in (StartCol, Len] with (Widths[Fit]-BaseX) <= AContentWidth.
      Fit := StartCol;
      while (Fit < Len) and (Widths[Fit + 1] - BaseX <= AContentWidth) do
        Inc(Fit);
      // Guarantee progress: at least one codepoint per row even if it overflows.
      if Fit = StartCol then
        Fit := StartCol + 1;
      if Fit >= Len then
      begin
        AddRow(li, StartCol, Len);
        StartCol := Len;
        Continue;
      end;
      // Prefer the last word boundary in (StartCol, Fit]. NextWordBoundary walks
      // forward to the end of the next word run; collect candidates up to Fit.
      BreakCol := 0;
      Cand := NextWordBoundary(Line, StartCol);
      while (Cand <= Fit) and (Cand > StartCol) do
      begin
        BreakCol := Cand;
        if Cand >= Len then Break;
        Cand := NextWordBoundary(Line, Cand);
        if Cand <= BreakCol then Break;   // no further progress (defensive)
      end;
      if (BreakCol > StartCol) and (BreakCol <= Fit) then
        AddRow(li, StartCol, BreakCol)    // break at the word boundary
      else
        AddRow(li, StartCol, Fit);        // char-break (over-long word / CJK)
      StartCol := Result[n - 1].EndCol;
    end;
  end;
  // Defensive: a non-empty FLines must always yield at least one row.
  if n = 0 then
    AddRow(0, 0, 0);
end;

function TTyMemo.ContentWidthFor(APPI: Integer): Integer;
var
  S: TTyStyleSet;
  SBWidth: Integer;
begin
  S := CurrentStyle;
  SBWidth := 0;
  if (FScrollBar <> nil) and FScrollBar.Visible then
    SBWidth := MulDiv(TyScrollbarSize, APPI, 96);
  // Use Width (not ClientWidth) to match VisibleRows' headless-safe convention:
  // for this borderless control Width = ClientWidth at runtime, but ClientWidth
  // can lag SetBounds in headless tests without a native handle.
  Result := Width - MulDiv(S.Padding.Left, APPI, 96)
    - MulDiv(S.Padding.Right, APPI, 96) - SBWidth;
  if Result < 0 then Result := 0;
end;

procedure TTyMemo.EnsureVisualRows(APPI: Integer);
var
  CW: Integer;
begin
  CW := ContentWidthFor(APPI);
  if FVisualRowsValid and (FVisualRowsWidth = CW) then Exit;
  FVisualRows := BuildVisualRows(CW, APPI);
  FVisualRowsWidth := CW;
  FVisualRowsValid := True;
end;

procedure TTyMemo.InvalidateVisualRows;
begin
  FVisualRowsValid := False;
end;

procedure TTyMemo.CaretToVisual(ALine, ACol, AContentWidth, APPI: Integer;
  out AVisualRow, AX: Integer);
var
  Rows: TTyVisualRowArray;
  i: Integer;
  Line: string;
begin
  AVisualRow := 0;
  AX := TextStartX(APPI);
  Rows := BuildVisualRows(AContentWidth, APPI);
  if Length(Rows) = 0 then Exit;
  // Find the owning row. Tie-break: a caret at a soft-wrap boundary column binds
  // to the EARLIER row (the one whose EndCol == ACol) rather than the next row
  // whose StartCol == ACol. We accept a row when ACol is within [StartCol,EndCol];
  // because we scan in order and accept the FIRST such row, the earlier row wins
  // the tie at a shared boundary column.
  AVisualRow := High(Rows);   // default: last row (handles col == final EndCol)
  for i := 0 to High(Rows) do
    if (Rows[i].Line = ALine) and (ACol >= Rows[i].StartCol)
       and (ACol <= Rows[i].EndCol) then
    begin
      AVisualRow := i;
      Break;
    end;
  // Device-x is identical to the plain per-line caret x (visual rows do not move
  // the horizontal origin; horizontal scroll is applied later by the renderer).
  if ALine < FLines.Count then
    Line := FLines[ALine]
  else
    Line := '';
  AX := ColPixelXAt(Line, ACol, APPI);
end;

procedure TTyMemo.VisualToCaret(AVisualRow, AX, AContentWidth, APPI: Integer;
  out ALine, ACol: Integer);
var
  Rows: TTyVisualRowArray;
  Line: string;
  Col: Integer;
begin
  ALine := 0;
  ACol := 0;
  Rows := BuildVisualRows(AContentWidth, APPI);
  if Length(Rows) = 0 then Exit;
  if AVisualRow < 0 then AVisualRow := 0;
  if AVisualRow > High(Rows) then AVisualRow := High(Rows);
  ALine := Rows[AVisualRow].Line;
  if ALine < FLines.Count then
    Line := FLines[ALine]
  else
    Line := '';
  // Resolve x to a codepoint on the logical line, then clamp into the row's
  // [StartCol,EndCol] segment so the result never escapes the clicked row.
  Col := ColIndexAtX(Line, AX, APPI);
  if Col < Rows[AVisualRow].StartCol then Col := Rows[AVisualRow].StartCol;
  if Col > Rows[AVisualRow].EndCol then Col := Rows[AVisualRow].EndCol;
  ACol := Col;
end;

// ---- Word-delete mutators (pure UTF8 splice on the caret line; fall back to the
// cross-line merge at the line boundary). Callers route through AfterEdit. ----

procedure TTyMemo.DeleteWordBackward;
var
  Cur, Before, After: string;
  t, L: Integer;
begin
  if FReadOnly then Exit;            // ReadOnly: block word-backward delete
  if FLines.Count = 0 then Exit;
  Cur := FLines[FCaretLine];
  t := PrevWordBoundary(Cur, FCaretCol);
  if t < FCaretCol then
  begin
    // Splice [t, FCaretCol) out of the line; caret lands at t.
    L := UTF8Length(Cur);
    Before := UTF8Copy(Cur, 1, t);
    After  := UTF8Copy(Cur, FCaretCol + 1, L - FCaretCol);
    FLines[FCaretLine] := Before + After;
    FCaretCol := t;
  end
  else
    // At col 0: fall back to the cross-line merge (caller guards (0,0) earlier).
    DoBackspace;
end;

procedure TTyMemo.DeleteWordForward;
var
  Cur, Before, After: string;
  t, L: Integer;
begin
  if FReadOnly then Exit;            // ReadOnly: block word-forward delete
  if FLines.Count = 0 then Exit;
  Cur := FLines[FCaretLine];
  t := NextWordBoundary(Cur, FCaretCol);
  if t > FCaretCol then
  begin
    // Splice [FCaretCol, t) out of the line; caret stays.
    L := UTF8Length(Cur);
    Before := UTF8Copy(Cur, 1, FCaretCol);
    After  := UTF8Copy(Cur, t + 1, L - t);
    FLines[FCaretLine] := Before + After;
  end
  else
    // At line end: fall back to the cross-line merge (caller guards end-of-doc).
    DoDelete;
end;

procedure TTyMemo.DeleteSelection;
// 2D generalisation of TTyEdit.DeleteSelection. Single line: splice within the
// line. Multi-line: keep SL's head (codepoints 1..SC) + EL's tail (codepoints
// EC+1..end), drop the interior lines. Caret -> SelStart; anchor collapses.
var
  SL, SC, EL, EC, i: Integer;
  Line, Before, After, Head, Tail: string;
begin
  if not HasSelection then Exit;
  GetOrderedSel(SL, SC, EL, EC);
  if SL = EL then
  begin
    // Splice within a single line.
    Line   := FLines[SL];
    Before := UTF8Copy(Line, 1, SC);
    After  := UTF8Copy(Line, EC + 1, UTF8Length(Line) - EC);
    FLines[SL] := Before + After;
  end
  else
  begin
    // Merge SL's head with EL's tail, then delete the interior + EL lines.
    Head := UTF8Copy(FLines[SL], 1, SC);
    Tail := UTF8Copy(FLines[EL], EC + 1, UTF8Length(FLines[EL]) - EC);
    FLines[SL] := Head + Tail;
    // Lines SL+1..EL inclusive all shift to index SL+1 as they are removed.
    for i := 1 to EL - SL do
      FLines.Delete(SL + 1);
  end;
  FCaretLine := SL;
  FCaretCol  := SC;
  // Collapse the selection onto the new caret position.
  FSelAnchorLine := FCaretLine;
  FSelAnchorCol  := FCaretCol;
end;

// ---- Clipboard implementation ----
// Virtual hooks lifted verbatim from TTyEdit so headless tests can override them
// with an in-memory string.

function TTyMemo.ReadClipboardText: string;
begin
  Result := Clipboard.AsText;
end;

procedure TTyMemo.WriteClipboardText(const S: string);
begin
  Clipboard.AsText := S;
end;

procedure TTyMemo.CopyToClipboard;
begin
  // Identical to TTyEdit.CopyToClipboard: SelText is already LineEnding-joined,
  // so the multi-line case needs no special handling here.
  if not HasSelection then Exit;
  WriteClipboardText(GetSelText);
  // Copy does not mutate, but it ends a typing-coalesce run (mirrors TTyEdit).
  BreakCoalescing;
end;

procedure TTyMemo.CutToClipboard;
begin
  // ReadOnly: a cut may not delete; degrade to a plain copy.
  if FReadOnly then begin CopyToClipboard; Exit; end;
  if not HasSelection then Exit;
  WriteClipboardText(GetSelText);
  // Capture ONE undo step (uskCut); suppress the inner DeleteSelection's own step
  // so the whole cut reverts in a single undo.
  BeginUndoStep(uskCut);
  FSuspendUndo := True;
  try
    DeleteSelection;
  finally
    FSuspendUndo := False;
  end;
  // Route through AfterEdit so OnChange fires (DeleteSelection is a pure mutator).
  AfterEdit(Font.PixelsPerInch);
end;

procedure TTyMemo.InsertTextMultiline(const AStr: string);
// Pure mutator: normalise CR/LF in AStr, split into segments, and splice them in
// at the caret. A single segment is a plain in-line insert; multiple segments
// split the caret line (head before caret / tail after) and insert the interior
// lines, leaving the caret at the end of the final segment before the tail. The
// caller routes through AfterEdit (one OnChange/undo step).
var
  Norm, Cur, Head, Tail: string;
  Segs: TStringList;
  i, InsertAt: Integer;
begin
  // Normalise CR/LF: CRLF -> LF, lone CR -> LF, so each remaining LF is one break.
  Norm := StringReplace(AStr, #13#10, #10, [rfReplaceAll]);
  Norm := StringReplace(Norm, #13, #10, [rfReplaceAll]);
  // Split into segments on LF. A single segment (no break) is a plain insert.
  // Build the segment list manually (rather than via TStringList.Text) so a
  // trailing break's empty segment is preserved: 'a'#10 -> ['a',''] (two lines),
  // matching the Enter semantics.
  Segs := TStringList.Create;
  try
    Head := '';
    for i := 1 to Length(Norm) do
    begin
      if Norm[i] = #10 then
      begin
        Segs.Add(Head);
        Head := '';
      end
      else
        Head := Head + Norm[i];
    end;
    Segs.Add(Head);

    if Segs.Count = 1 then
    begin
      // No line breaks: a plain in-line insert at the caret.
      DoInsertText(Segs[0]);
    end
    else
    begin
      // Split the caret line into head (before caret) + tail (after caret).
      if FLines.Count = 0 then
        FLines.Add('');
      Cur  := FLines[FCaretLine];
      Head := UTF8Copy(Cur, 1, FCaretCol);
      Tail := UTF8Copy(Cur, FCaretCol + 1, UTF8Length(Cur) - FCaretCol);
      // First segment joins the head on the caret line.
      FLines[FCaretLine] := Head + Segs[0];
      // Interior segments become whole new lines after the caret line.
      InsertAt := FCaretLine + 1;
      for i := 1 to Segs.Count - 2 do
      begin
        FLines.Insert(InsertAt, Segs[i]);
        Inc(InsertAt);
      end;
      // Final segment + the preserved tail becomes the last inserted line; caret
      // lands at the end of the final segment, before the preserved tail.
      FLines.Insert(InsertAt, Segs[Segs.Count - 1] + Tail);
      FCaretLine := InsertAt;
      FCaretCol  := UTF8Length(Segs[Segs.Count - 1]);
    end;
  finally
    Segs.Free;
  end;
end;

procedure TTyMemo.PasteFromClipboard;
// Multi-line paste: read the clipboard, normalise line breaks, split into
// segments and splice them into the model. A truly-empty clipboard is a full
// no-op (mirrors TTyEdit). A non-empty-but-CRLF-only clipboard (e.g. #10) still
// deletes any selection and inserts the resulting (possibly empty) segments,
// which mutates the model and fires OnChange.
var
  S: string;
  Room: Integer;
begin
  if FReadOnly then Exit;            // ReadOnly: block paste
  S := ReadClipboardText;
  if S = '' then Exit;  // truly-empty clipboard: full no-op (Edit 551)
  // MaxLength: truncate the payload to the remaining content room. When the doc
  // is already at/over the cap there is no room -> full no-op (Exit before any
  // mutation). Otherwise trim the RAW clipboard string to Room codepoints BEFORE
  // the CR/LF split. This caps inserted content at Room; any CR/LF inside the
  // trimmed prefix become line breaks (which don't count toward content), so the
  // resulting content may be slightly UNDER Room — never over. Simple and safe.
  if FMaxLength > 0 then
  begin
    Room := FMaxLength - ContentCodepointCount;
    if Room <= 0 then Exit;
    if UTF8Length(S) > Room then
      S := UTF8Copy(S, 1, Room);
  end;
  // Capture ONE undo step (uskPaste) covering the whole paste — both the
  // selection delete and the multi-line splice revert in a single undo. The
  // inner mutators are pure (no BeginUndoStep of their own), so FSuspendUndo is
  // not strictly required, but set it for symmetry with cut and to guard against
  // any future BeginUndoStep added to the inner helpers.
  BeginUndoStep(uskPaste);
  FSuspendUndo := True;
  try
    if HasSelection then DeleteSelection;
    // Normalise + split + splice the payload into one-or-more logical lines.
    InsertTextMultiline(S);
    FDesiredCol := FCaretCol;
    AfterEdit(Font.PixelsPerInch);
  finally
    FSuspendUndo := False;
  end;
end;

function TTyMemo.EffectiveFontSize(const S: TTyStyleSet): Integer;
begin
  // Verbatim from TTyEdit.EffectiveFontSize.
  if S.FontSize > 0 then
    Result := S.FontSize
  else
    Result := 12;  // fallback 12pt
end;

function TTyMemo.TextStartX(APPI: Integer): Integer;
var
  S: TTyStyleSet;
begin
  S := CurrentStyle;
  Result := MulDiv(S.Padding.Left, APPI, 96);
end;

procedure TTyMemo.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  InvalidateVisualRows;
  // Switching INTO wrap mode pins the horizontal offset to 0 (no h-scroll in wrap);
  // switching OUT re-clamps it (still 0 until the caret moves). ClampScrollX
  // handles both via its FWordWrap branch.
  ClampScrollX(Font.PixelsPerInch);
  Invalidate;
end;

function TTyMemo.LineHeight(APPI: Integer): Integer;
var
  S: TTyStyleSet;
  EffSize: Integer;
begin
  S := CurrentStyle;
  EffSize := EffectiveFontSize(S);
  if FMeasureBmp = nil then
    FMeasureBmp := TBGRABitmap.Create(1, 1);
  // Configure exactly as TTyPainter.DrawText so the measured cell height matches
  // what is drawn (same BGRA engine + height semantics as TTyEdit's fix).
  TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
  // 'Ag' spans an ascender and a descender — a stable single-line cell height.
  Result := FMeasureBmp.TextSize('Ag').cy;
  if Result < 1 then
    Result := 1;
end;

function TTyMemo.MeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
// Cumulative prefix x positions (px), length = UTF8Length(ALine)+1, measured on
// the shared lazy bitmap. Lifted from TTyEdit.MeasureCodepointWidths; takes the
// line as a parameter and does NOT cache (per-line caching is a later concern).
var
  S: TTyStyleSet;
  EffSize: Integer;
  i, Len: Integer;
begin
  Result := nil;
  S := CurrentStyle;
  EffSize := EffectiveFontSize(S);
  Len := UTF8Length(ALine);
  SetLength(Result, Len + 1);
  Result[0] := 0;
  if Len > 0 then
  begin
    if FMeasureBmp = nil then
      FMeasureBmp := TBGRABitmap.Create(1, 1);
    TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
    // PREFIX measurement captures inter-glyph kerning/hinting as drawn.
    for i := 1 to Len do
      Result[i] := FMeasureBmp.TextSize(UTF8Copy(ALine, 1, i)).cx;
  end;
end;

function TTyMemo.ColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
var
  Widths: TTyIntArray;
  Len: Integer;
begin
  Len := UTF8Length(ALine);
  if ACol < 0 then ACol := 0;
  if ACol > Len then ACol := Len;
  Result := TextStartX(APPI);
  if Len = 0 then
    Exit;
  Widths := MeasureLineWidths(ALine, APPI);
  Result := Result + Widths[ACol];
end;

function TTyMemo.ColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
// Midpoint-nearest codepoint boundary (lifted from TTyEdit.CaretIndexAtX). AX is a
// device x in control coordinates; add FScrollX so a click while horizontally
// scrolled resolves to the correct (scrolled-away) column. FScrollX is 0 when the
// text fits or WordWrap=True, so this reduces to the un-scrolled hit-test exactly.
var
  Widths: TTyIntArray;
  StartX, RelX, Len, i, MidPoint: Integer;
begin
  StartX := TextStartX(APPI);
  RelX := AX - StartX + FScrollX;
  Len := UTF8Length(ALine);
  if RelX <= 0 then
    Exit(0);
  Widths := MeasureLineWidths(ALine, APPI);
  if RelX >= Widths[Len] then
    Exit(Len);
  Result := 0;
  for i := 0 to Len - 1 do
  begin
    MidPoint := (Widths[i] + Widths[i + 1]) div 2;
    if RelX <= MidPoint then
      Exit(i);
    Result := i + 1;
  end;
end;

procedure TTyMemo.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
// Visible visual-ROW loop + static caret. Each painted row is one TTyVisualRow
// segment [StartCol,EndCol) of a logical line: when WordWrap=False the cache holds
// exactly one full-width row (StartCol=0, EndCol=LineLen) per logical line, so the
// loop reduces to the legacy per-logical-line render and is BYTE-IDENTICAL (the
// segment substring is the whole line, drawn at ContentRect.Left). When WordWrap=
// True a long line yields several rows; each continuation segment is drawn at the
// content left in its own LH-tall cell. FTopRow is the top VISUAL-ROW index.
//
// Identity note: for a row with StartCol=0 the segment substring equals the line
// and RowBaseW (= Widths[StartCol]) is 0, so every X (band + caret) collapses to
// today's per-line math. Horizontal scroll (FScrollX) is added in T3.
var
  P: TTyPainter;
  S, SelStyle: TTyStyleSet;
  R, ContentRect, LineRect, CaretRect, BandRect: TRect;
  SBWidth, LH, ContentTop, LastVisible, vr, y: Integer;
  EffSize, CaretX, CaretVRow: Integer;
  Line, Seg: string;
  RL, RS, RE, RowBaseW, bandStartCol, bandEndCol: Integer;
  // Selection-band state (resolved once before the visible-row loop).
  SL, SC, EL, EC, X1, X2: Integer;
  Widths: TTyIntArray;
  BandFill: TTyFill;
  BandColor: TTyColor;
  DrawBand: Boolean;
begin
  // Keep the scrollbar in sync (cheap; catches external Lines mutations).
  UpdateScrollBar;
  // Build/refresh the visual-row cache for the current content width + wrap mode.
  EnsureVisualRows(APPI);

  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    EffSize := EffectiveFontSize(S);
    DrawFrame(P, R, S);

    // Content area = full rect inset by the MEMO style's Padding.
    ContentRect := Rect(
      R.Left   + P.Scale(S.Padding.Left),
      R.Top    + P.Scale(S.Padding.Top),
      R.Right  - P.Scale(S.Padding.Right),
      R.Bottom - P.Scale(S.Padding.Bottom)
    );

    // Subtract scrollbar width when visible (mirrors TTyListBox.RenderTo).
    SBWidth := 0;
    if (FScrollBar <> nil) and FScrollBar.Visible then
      SBWidth := MulDiv(TyScrollbarSize, APPI, 96);

    LH := LineHeight(APPI);
    ContentTop := ContentRect.Top;

    // Resolve the selection band color ONCE before the visible-row loop (mirrors
    // TTyEdit): the TyTextSelection typeKey (accent-tinted via
    // --selection = alpha(accent,0.30)). Only needed when a selection exists; the
    // band is filled per visible row below.
    SL := 0; SC := 0; EL := 0; EC := 0;
    if HasSelection then
    begin
      SelStyle := ActiveController.Model.ResolveStyle('TyTextSelection', '', []);
      GetOrderedSel(SL, SC, EL, EC);
    end;

    // Last visible visual row: fill the content height with LH-tall cells.
    LastVisible := FTopRow + (ContentRect.Bottom - ContentTop) div LH;
    if LastVisible > High(FVisualRows) then
      LastVisible := High(FVisualRows);

    for vr := FTopRow to LastVisible do
    begin
      if (vr < 0) or (vr > High(FVisualRows)) then Continue;
      RL := FVisualRows[vr].Line;
      RS := FVisualRows[vr].StartCol;
      RE := FVisualRows[vr].EndCol;
      if RL < FLines.Count then
        Line := FLines[RL]
      else
        Line := '';
      // Segment substring for this row: codepoints [RS, RE). For a full-width row
      // (RS=0, RE=LineLen) this is the whole line (identity with the old render).
      Seg := UTF8Copy(Line, RS + 1, RE - RS);
      y := ContentTop + (vr - FTopRow) * LH;
      // Horizontal scroll: shift the row's left edge left by FScrollX so a long
      // line follows the caret; the Right edge stays clipped at the content
      // right (DrawText clips to LineRect), so glyphs never spill past it. With
      // FScrollX = 0 (fitting text or WordWrap=True) LineRect.Left is unchanged,
      // so the no-wrap render is byte-identical to today.
      LineRect := Rect(ContentRect.Left - FScrollX, y,
        ContentRect.Right - SBWidth, y + LH);

      // Selection band for this row, drawn BENEATH the text (band first so the
      // glyphs sit on top). Reuse the SAME line widths the row draws with so band
      // geometry matches the drawn text exactly. No FScrollX term (added in T3).
      // Generalised per visual row: with RS=0 it reduces to the legacy per-line
      // band exactly. RowBaseW shifts the row's columns so the segment's first
      // codepoint sits at ContentRect.Left.
      if HasSelection and (RL >= SL) and (RL <= EL) then
      begin
        Widths := MeasureLineWidths(Line, APPI);
        RowBaseW := Widths[RS];
        DrawBand := True;
        // Left edge: selection start column on this row.
        if (RL = SL) and (SC > RS) then
        begin
          // Selection begins partway through this logical line.
          if SC > RE then
            DrawBand := False         // selection starts after this row's segment
          else
            bandStartCol := SC;
        end
        else
          bandStartCol := RS;         // selection covers the row's left edge
        // Right edge: either ends within this line (clamp to RE) or extends to the
        // content right edge because the selection continues onto a later line.
        if RL = EL then
        begin
          if EC < RS then
            DrawBand := False         // selection ends before this row's segment
          else if EC < RE then
            bandEndCol := EC
          else
            bandEndCol := RE;
        end
        else
          bandEndCol := -1;           // sentinel: extend to the content right edge
        if DrawBand then
        begin
          // Shift the band left by FScrollX (same as the text). The right-edge
          // sentinel (bandEndCol < 0) already means "extend to the viewport right"
          // so it is NOT shifted. Clamp both edges into the content rect so the
          // band never paints over the padding/scrollbar when scrolled. FScrollX=0
          // leaves the band geometry byte-identical to today.
          X1 := ContentRect.Left + (Widths[bandStartCol] - RowBaseW) - FScrollX;
          if bandEndCol < 0 then
            X2 := ContentRect.Right - SBWidth
          else
            X2 := ContentRect.Left + (Widths[bandEndCol] - RowBaseW) - FScrollX;
          if X1 < ContentRect.Left then X1 := ContentRect.Left;
          if X2 > ContentRect.Right - SBWidth then X2 := ContentRect.Right - SBWidth;
          if X1 < X2 then
          begin
            BandRect := Rect(X1, y, X2, y + LH);
            // Band color from the TyTextSelection typeKey (accent-tinted; mirrors
            // TTyEdit). Theme-overridable, matching selected list rows.
            BandColor := SelStyle.Background.Color;
            BandFill := Default(TTyFill);
            BandFill.Kind := tfkSolid;
            BandFill.Color := BandColor;
            P.FillBackground(BandRect, BandFill, 0);
          end;
        end;
      end;

      P.DrawText(LineRect, Seg, S.FontName, EffSize, S.FontWeight,
        S.TextColor, taLeftJustify, tlTop, False);
    end;

    // Static caret: only when focused (or headless-forced), no active selection,
    // and the caret's VISUAL ROW is currently visible. 1px bar like TTyEdit, inset
    // 2px top/bottom in the cell. Gated on not HasSelection so the caret hides
    // while a selection band is shown (matches TTyEdit). CaretToVisual binds a
    // wrap-boundary caret to the earlier (line-end) row; X is segment-relative so
    // a full-width row (RS=0) reproduces today's caret X exactly.
    if (Focused or FForceFocused) and not HasSelection and FCaretVisible then
    begin
      CaretToVisual(FCaretLine, FCaretCol, FVisualRowsWidth, APPI, CaretVRow, CaretX);
      if (CaretVRow >= FTopRow) and (CaretVRow <= LastVisible)
        and (CaretVRow >= 0) and (CaretVRow <= High(FVisualRows)) then
      begin
        RL := FVisualRows[CaretVRow].Line;
        RS := FVisualRows[CaretVRow].StartCol;
        if RL < FLines.Count then
          Line := FLines[RL]
        else
          Line := '';
        // Segment-relative caret X: full-line ColPixelXAt minus the row's base
        // offset (= 0 when RS=0, so identical to the old caret X for no-wrap),
        // then shifted left by FScrollX so the caret tracks the scrolled text.
        // FScrollX = 0 (fitting text / WordWrap=True) leaves this byte-identical.
        CaretX := R.Left + ColPixelXAt(Line, FCaretCol, APPI)
          - (ColPixelXAt(Line, RS, APPI) - TextStartX(APPI)) - FScrollX;
        y := ContentTop + (CaretVRow - FTopRow) * LH;
        CaretRect := Rect(CaretX, y + P.Scale(2),
          CaretX + P.Scale(1), y + LH - P.Scale(2));
        P.FillBackground(CaretRect, Default(TTyFill), 0);
        P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
        // Pin the Windows IME composition window to the caret (client coords),
        // so CJK candidates appear at the caret instead of the screen origin.
        if Focused then TySetImeCaretPos(Self, CaretX, y);
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyMemo.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

// ---- Input handlers ----

procedure TTyMemo.UTF8KeyPress(var UTF8Key: TUTF8Char);
begin
  if not Enabled then Exit;          // v1.5 policy: ignore input when disabled
  if FReadOnly then Exit;            // ReadOnly: block printable typing
  inherited UTF8KeyPress(UTF8Key);
  // Printable codepoints only; control chars (Enter/Tab/etc.) are handled in
  // KeyDown or ignored here.
  if (UTF8Key = '') or (UTF8Key[1] < #32) then Exit;
  // MaxLength: block a new printable char once the total content is at the cap.
  // Guarded HERE (the typing caller) and NOT in DoInsertText, because paste also
  // routes through DoInsertText but must truncate (not be blocked wholesale).
  if (FMaxLength > 0) and (ContentCodepointCount >= FMaxLength) then Exit;
  // A selection is replaced by the typed text (delete-then-insert, like
  // TTyEdit.InjectKey 643 — NOT an early exit). Capture ONE undo step up front:
  // replacing a selection is a fresh (non-typing) step, so a later coalescing
  // typing run does not fold the deletion into it. When there is no selection it
  // is a plain typing insert (coalesces with adjacent single-char inserts).
  if HasSelection then
    BeginUndoStep(uskDelete)
  else
    BeginUndoStep(uskTyping);
  if HasSelection then DeleteSelection;
  DoInsertText(UTF8Key);
  // Collapse the selection anchor onto the new caret so consecutive typing keeps
  // inserting (rather than the stale anchor making HasSelection true and the next
  // char replacing the just-typed run). Mirrors TTyEdit.InjectStringAt, which
  // sets FSelAnchor := FCaret after every insert.
  FSelAnchorLine := FCaretLine;
  FSelAnchorCol := FCaretCol;
  FDesiredCol := FCaretCol;          // horizontal edit refreshes desired column
  AfterEdit(Font.PixelsPerInch);
end;

{ Insert a FULL input-method commit (Qt6). LCL's UTF8KeyPress caps a commit at TUTF8Char (String[7],
  ~2 CJK chars); our Qt event filter (tyControls.QtWS) calls this with the whole commitString. Mirrors
  PasteFromClipboard: MaxLength trim, one undo step, replace selection, splice via InsertTextMultiline. }
procedure TTyMemo.HandleImeCommit(const ACommitUtf8: string);
var
  S: string;
  Room: Integer;
begin
  if FReadOnly or not Enabled then Exit;
  if ACommitUtf8 = '' then Exit;
  S := ACommitUtf8;
  if FMaxLength > 0 then
  begin
    Room := FMaxLength - ContentCodepointCount;
    if Room <= 0 then Exit;
    if UTF8Length(S) > Room then S := UTF8Copy(S, 1, Room);
  end;
  BeginUndoStep(uskTyping);
  FSuspendUndo := True;
  try
    if HasSelection then DeleteSelection;
    InsertTextMultiline(S);
    FSelAnchorLine := FCaretLine;     // collapse anchor so the next input doesn't replace this run
    FSelAnchorCol := FCaretCol;
    FDesiredCol := FCaretCol;
    AfterEdit(Font.PixelsPerInch);
  finally
    FSuspendUndo := False;
  end;
end;

procedure TTyMemo.InitializeWnd;
begin
  inherited InitializeWnd;
  FImeHook := TyQtInstallImeCommit(Self, @HandleImeCommit);   // Qt6 only; nil elsewhere
end;

procedure TTyMemo.DestroyWnd;
begin
  TyQtUninstallIme(FImeHook);
  inherited DestroyWnd;
end;

procedure TTyMemo.KeyDown(var Key: Word; Shift: TShiftState);
var
  APPI, L, MaxLine, WordT: Integer;
  CtrlLike, Extending: Boolean;
  CurLine: string;
begin
  if not Enabled then Exit;          // when disabled, do NOT consume Key
  inherited KeyDown(Key, Shift);
  APPI := Font.PixelsPerInch;
  MaxLine := LineCountLogical - 1;
  // Ctrl (Win/Linux) or Meta/Cmd (macOS) modifies Home/End to document extents.
  CtrlLike := (ssCtrl in Shift) or (ssMeta in Shift);
  // Shift extends the selection: navigation moves the caret but keeps the anchor.
  // When NOT extending, each nav branch collapses the anchor onto the new caret
  // (mirrors TTyEdit; additive — existing single-caret nav never passes ssShift,
  // so the collapse path runs with anchor already glued to the caret).
  Extending := ssShift in Shift;

  // Clipboard shortcuts (Ctrl on Win/Linux, Meta/Cmd on macOS), handled BEFORE
  // the navigation case so they take precedence. Each consumes Key and Exits.
  if CtrlLike and (Key = VK_A) then
  begin
    SelectAll;
    Key := 0;
    Exit;
  end;
  if CtrlLike and (Key = VK_C) then
  begin
    CopyToClipboard;
    Key := 0;
    Exit;
  end;
  if CtrlLike and (Key = VK_X) then
  begin
    CutToClipboard;
    Key := 0;
    Exit;
  end;
  if CtrlLike and (Key = VK_V) then
  begin
    PasteFromClipboard;
    Key := 0;
    Exit;
  end;

  // Redo: Ctrl/Cmd+Shift+Z OR Ctrl/Cmd+Y. Check redo BEFORE undo so the Shift+Z
  // variant is not swallowed by the plain Ctrl+Z branch below (same idiom as
  // TTyEdit). CtrlLike already covers Ctrl (Win/Linux) and Meta/Cmd (macOS).
  if ( (Key = VK_Z) and CtrlLike and (ssShift in Shift) )
     or ( (Key = VK_Y) and CtrlLike ) then
  begin
    Redo;
    Key := 0;
    Exit;
  end;
  // Undo: Ctrl/Cmd+Z (no Shift).
  if (Key = VK_Z) and CtrlLike and not (ssShift in Shift) then
  begin
    Undo;
    Key := 0;
    Exit;
  end;

  case Key of
    VK_RETURN:
    begin
      // WantReturns=False: do NOT consume Enter — leave Key intact so it propagates
      // and the form's default button can handle it (native TMemo semantics). No
      // model change. Exit before consuming the key.
      if not FWantReturns then Exit;
      // Enter on a selection replaces it with a line break (delete-then-split).
      // Capture ONE undo step (uskNewline) covering both the selection delete and
      // the split, so the whole Enter reverts in a single undo. ReadOnly blocks the
      // mutation entirely (the key is still consumed so it never falls through).
      if not FReadOnly then
      begin
        BeginUndoStep(uskNewline);
        FSuspendUndo := True;
        try
          if HasSelection then DeleteSelection;
          DoSplitLine;
        finally
          FSuspendUndo := False;
        end;
        FDesiredCol := FCaretCol;
        AfterEdit(APPI);
      end;
      Key := 0;
    end;
    VK_TAB:
    begin
      // WantTabs=False (default): do NOT consume Tab — leave Key intact so it
      // propagates and navigates between controls (native TMemo semantics).
      if not FWantTabs then Exit;
      // WantTabs=True: insert a literal tab character into the text (replacing any
      // selection), as one undo step firing OnChange once. ReadOnly blocks the
      // mutation but still consumes the key.
      if not FReadOnly then
      begin
        if HasSelection then
          BeginUndoStep(uskDelete)
        else
          BeginUndoStep(uskTyping);
        FSuspendUndo := True;
        try
          if HasSelection then DeleteSelection;
          DoInsertText(#9);
        finally
          FSuspendUndo := False;
        end;
        // Collapse the anchor onto the new caret (mirrors typed insertion).
        FSelAnchorLine := FCaretLine;
        FSelAnchorCol := FCaretCol;
        FDesiredCol := FCaretCol;
        AfterEdit(APPI);
      end;
      Key := 0;
    end;
    VK_BACK:
    begin
      // ReadOnly: consume the key but make no model change.
      if FReadOnly then
      begin
        Key := 0;
        Exit;
      end;
      // A selection is deleted wholesale (never falls to the prev-char path),
      // checked BEFORE the (0,0) no-op guard so a selection always mutates.
      if HasSelection then
      begin
        BeginUndoStep(uskDelete);
        DeleteSelection;
        FDesiredCol := FCaretCol;
        AfterEdit(APPI);
        Key := 0;
        Exit;
      end;
      // (0,0): no model change, no OnChange, but key is consumed. No undo step
      // is captured here since nothing mutates.
      if (FCaretCol = 0) and (FCaretLine = 0) then
      begin
        Key := 0;
        Exit;
      end;
      // Ctrl/Alt+Backspace deletes the previous word (within the line; at col 0 it
      // falls back to the cross-line merge inside DeleteWordBackward). Precedence
      // selection > word > single, mirroring TTyEdit. Capture the pre-mutation
      // state as a fresh (non-typing) undo step.
      BeginUndoStep(uskBackspace);
      if (ssCtrl in Shift) or (ssAlt in Shift) then
        DeleteWordBackward
      else
        DoBackspace;
      FDesiredCol := FCaretCol;
      AfterEdit(APPI);
      Key := 0;
    end;
    VK_DELETE:
    begin
      // ReadOnly: consume the key but make no model change.
      if FReadOnly then
      begin
        Key := 0;
        Exit;
      end;
      // A selection is deleted wholesale, checked BEFORE the end-of-doc guard
      // so a selection always mutates regardless of caret position.
      if HasSelection then
      begin
        BeginUndoStep(uskDelete);
        DeleteSelection;
        FDesiredCol := FCaretCol;
        AfterEdit(APPI);
        Key := 0;
        Exit;
      end;
      L := LineLen(FCaretLine);
      // End of document (last line, last col): no change, no OnChange. No undo
      // step is captured here since nothing mutates.
      if (FCaretCol >= L) and (FCaretLine >= MaxLine) then
      begin
        Key := 0;
        Exit;
      end;
      // Ctrl/Alt+Delete deletes the next word (within the line; at line end it
      // falls back to the cross-line merge inside DeleteWordForward). Capture the
      // pre-mutation state as a fresh (non-typing) undo step.
      BeginUndoStep(uskDelete);
      if (ssCtrl in Shift) or (ssAlt in Shift) then
        DeleteWordForward
      else
        DoDelete;
      FDesiredCol := FCaretCol;
      AfterEdit(APPI);
      Key := 0;
    end;
    VK_LEFT:
    begin
      // Word-wise left: Alt+Left (macOS Option) or Ctrl+Left (Win/Linux), placed
      // ABOVE the plain-arrow logic. t < FCaretCol => move within the line to the
      // previous word boundary; else (at col 0) move to the END of the previous
      // line. Honors Extending (keep anchor) like the plain arrows. (Cmd/ssMeta
      // does NOT trigger word nav — mirrors TTyEdit.)
      if (ssAlt in Shift) or (ssCtrl in Shift) then
      begin
        if FCaretLine < FLines.Count then CurLine := FLines[FCaretLine] else CurLine := '';
        WordT := PrevWordBoundary(CurLine, FCaretCol);
        if WordT < FCaretCol then
          FCaretCol := WordT
        else if (FCaretCol = 0) and (FCaretLine > 0) then
        begin
          Dec(FCaretLine);
          FCaretCol := LineLen(FCaretLine);
        end;
      end
      else if FCaretCol > 0 then
        Dec(FCaretCol)
      else if FCaretLine > 0 then
      begin
        Dec(FCaretLine);
        FCaretCol := LineLen(FCaretLine);
      end;
      FDesiredCol := FCaretCol;
      if not Extending then
      begin
        FSelAnchorLine := FCaretLine;
        FSelAnchorCol := FCaretCol;
      end;
      AfterCaretMove(APPI);
      Key := 0;
    end;
    VK_RIGHT:
    begin
      L := LineLen(FCaretLine);
      // Word-wise right: Alt+Right or Ctrl+Right. t > FCaretCol => move within the
      // line to the next word boundary; else (at line end) move to the START of
      // the next line.
      if (ssAlt in Shift) or (ssCtrl in Shift) then
      begin
        if FCaretLine < FLines.Count then CurLine := FLines[FCaretLine] else CurLine := '';
        WordT := NextWordBoundary(CurLine, FCaretCol);
        if WordT > FCaretCol then
          FCaretCol := WordT
        else if (FCaretCol >= L) and (FCaretLine < MaxLine) then
        begin
          Inc(FCaretLine);
          FCaretCol := 0;
        end;
      end
      else if FCaretCol < L then
        Inc(FCaretCol)
      else if FCaretLine < MaxLine then
      begin
        Inc(FCaretLine);
        FCaretCol := 0;
      end;
      FDesiredCol := FCaretCol;
      if not Extending then
      begin
        FSelAnchorLine := FCaretLine;
        FSelAnchorCol := FCaretCol;
      end;
      AfterCaretMove(APPI);
      Key := 0;
    end;
    VK_UP:
    begin
      // FInVerticalMove suppresses the FDesiredX refresh in AfterCaretMove so the
      // desired x survives a run of Up/Down (wrap path). The no-wrap path uses the
      // FDesiredCol column-restore idiom and is byte-identical to today.
      FInVerticalMove := True;
      try
        if FWordWrap then
          MoveCaretByVisualRow(-1, APPI)
        else if FCaretLine > 0 then
        begin
          Dec(FCaretLine);
          // Restore desired column, clamped to the new line length.
          FCaretCol := FDesiredCol;
          if FCaretCol > LineLen(FCaretLine) then
            FCaretCol := LineLen(FCaretLine);
        end;
        // FDesiredCol / FDesiredX preserved across vertical motion.
        if not Extending then
        begin
          FSelAnchorLine := FCaretLine;
          FSelAnchorCol := FCaretCol;
        end;
        AfterCaretMove(APPI);
      finally
        FInVerticalMove := False;
      end;
      Key := 0;
    end;
    VK_DOWN:
    begin
      FInVerticalMove := True;
      try
        if FWordWrap then
          MoveCaretByVisualRow(+1, APPI)
        else if FCaretLine < MaxLine then
        begin
          Inc(FCaretLine);
          FCaretCol := FDesiredCol;
          if FCaretCol > LineLen(FCaretLine) then
            FCaretCol := LineLen(FCaretLine);
        end;
        // FDesiredCol / FDesiredX preserved across vertical motion.
        if not Extending then
        begin
          FSelAnchorLine := FCaretLine;
          FSelAnchorCol := FCaretCol;
        end;
        AfterCaretMove(APPI);
      finally
        FInVerticalMove := False;
      end;
      Key := 0;
    end;
    VK_HOME:
    begin
      if CtrlLike then
      begin
        // Document-wide, in BOTH wrap modes.
        FCaretLine := 0;
        FCaretCol := 0;
      end
      else if FWordWrap then
        // Visual-row-local: jump to the caret's visual-row START col.
        FCaretCol := CaretRowStartCol(APPI)
      else
        FCaretCol := 0;          // line-local (no-wrap; unchanged)
      FDesiredCol := FCaretCol;
      // FDesiredX is refreshed in AfterCaretMove (horizontal move).
      if not Extending then
      begin
        FSelAnchorLine := FCaretLine;
        FSelAnchorCol := FCaretCol;
      end;
      AfterCaretMove(APPI);
      Key := 0;
    end;
    VK_END:
    begin
      if CtrlLike then
      begin
        // Document-wide, in BOTH wrap modes.
        FCaretLine := MaxLine;
        FCaretCol := LineLen(FCaretLine);
      end
      else if FWordWrap then
        // Visual-row-local: jump to the caret's visual-row END col. At a soft-wrap
        // boundary CaretToVisual binds EndCol to THIS (earlier) row, so the caret
        // stays visually at the end of the current row.
        FCaretCol := CaretRowEndCol(APPI)
      else
        FCaretCol := LineLen(FCaretLine);  // line-local (no-wrap; unchanged)
      FDesiredCol := FCaretCol;
      // FDesiredX is refreshed in AfterCaretMove (horizontal move).
      if not Extending then
      begin
        FSelAnchorLine := FCaretLine;
        FSelAnchorCol := FCaretCol;
      end;
      AfterCaretMove(APPI);
      Key := 0;
    end;
  end;
end;

// ---- Headless input helpers ----

procedure TTyMemo.InjectChar(const AChar: TUTF8Char);
var
  K: TUTF8Char;
begin
  if FReadOnly then Exit;            // ReadOnly: block typed insert
  K := AChar;
  UTF8KeyPress(K);
end;

procedure TTyMemo.InjectKey(AKey: Word; AShift: TShiftState);
var
  K: Word;
begin
  K := AKey;
  KeyDown(K, AShift);
end;

procedure TTyMemo.InjectBackspace;
begin
  if FReadOnly then Exit;            // ReadOnly: block backspace edit
  InjectKey(VK_BACK, []);
end;

procedure TTyMemo.InjectDelete;
begin
  if FReadOnly then Exit;            // ReadOnly: block delete edit
  InjectKey(VK_DELETE, []);
end;

end.
