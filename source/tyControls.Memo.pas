unit tyControls.Memo;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8, LazMethodList, Clipbrd,
  Generics.Collections, ExtCtrls, StdCtrls,
  BGRABitmap, BGRABitmapTypes, BGRATextBidi,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ScrollBar, tyControls.UndoStack, tyControls.Animation,
  tyControls.PlatformWS, tyControls.Controller, tyControls.TextMenu
  {$IFDEF LCLCocoa}, LMessages, tyControls.CocoaWS{$ENDIF};
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

  { One same-direction stretch of a laid-out VISUAL ROW: a contiguous half-open range of
    codepoints [First, Last) -- counted from the ROW's first codepoint, not the logical
    line's -- that the bidirectional algorithm placed at [Left, Right) px from the row's
    left edge. A row with no right-to-left script in it never gets a table at all and this
    whole apparatus stays asleep; a row reading "ab<two hebrew letters>cd" is three runs,
    the middle one drawn right-to-left.

    The runs are in LOGICAL order (they partition 0..the row's codepoint count) while
    Left/Right are VISUAL, so run[1].Left < run[0].Left is perfectly normal and is exactly
    the case the prefix sum could not express.

    WHY A ROW AND NOT A LINE. RenderTo draws each visual row as its OWN string (the segment
    substring, at the content left edge), so TTyPainter runs the bidirectional algorithm per
    row and the reordering a caret has to agree with is the row's, not the line's. Under
    WordWrap=False a row IS the whole line and the distinction costs nothing.

    This is TTyEdit.TTyBidiRun's record with row-relative indices. It is duplicated rather
    than shared because the shared home for it would be tyControls.Painter or .Base, and
    pulling the whole of tyControls.Edit into the memo's dependency graph to borrow a
    five-field record would be the worse trade. }
  TTyMemoBidiRun = record
    First, Last: Integer;
    RTL: Boolean;
    Left, Right: Integer;   // device px, relative to the ROW's text origin
  end;
  TTyMemoBidiRunArray = array of TTyMemoBidiRun;

  { The whole bidirectional answer for ONE visual row's segment, cached by segment content.

    Lead[i] / Trail[i] are the x of caret boundary i measured inside the run that owns the
    character AFTER it and the run that owns the character BEFORE it. They differ only at a
    direction boundary -- which is the entire point, since that is where one column has two
    screen positions and BGRA's own GetCaret hands back only the second.

    Active = False records "this segment needs no reordering", which is an answer worth
    caching too: it is what keeps a mixed document from re-asking the gate per paint. }
  TTyMemoRowBidi = record
    Active: Boolean;
    Runs: TTyMemoBidiRunArray;   // logical order
    Order: TTyIntArray;          // run indices, LEFT-to-RIGHT on screen
    Lead, Trail: TTyIntArray;    // length = row codepoints + 1
  end;

  TTyMemo = class(TTyCustomControl, ITyTextEditActions, ITyImeEditable)
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
    { Which of the two glyphs beside the caret it is standing against.

      A (line, column) stops having ONE screen position the moment the row is
      bidirectional: in "ab<alef><bet>cd" the boundary at column 2 is both "after the b" and
      "before the alef", and those are the two OPPOSITE ends of the Hebrew run. True means
      the caret is drawn against the character BEFORE it (where typing and a rightward walk
      leave it), False against the character AFTER it. Both are legitimate answers and the
      Unicode algorithm does not choose; the operation that last moved the caret does, so
      that is what this remembers. Verbatim in spirit from TTyEdit.FCaretAfterPrev.

      True is the default and the value every path that does not care leaves behind, because
      it is what an insertion point means: "the text I just wrote ends here". }
    FCaretAfterPrev: Boolean;
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
    // Multi-click sequence tracking (LCL has no native triple-click): the last press's
    // client position + tick and the running count, advanced by TyAdvanceClickCount.
    // 1 = caret, 2 = word, 3 = current logical line.
    FClickCount: Integer;
    FLastClickTick: QWord;
    FLastClickX, FLastClickY: Integer;
    // The default themed right-click menu (tyControls.TextMenu). nil until a context
    // popup is first raised on this memo; freed in Destroy.
    FTextMenu: TTyTextEditMenu;
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
    FInLinesChange: Boolean;   // re-entrancy guard for the Lines change notification
    FVisualRows: TTyVisualRowArray;
    FVisualRowsValid: Boolean;
    FVisualRowsWidth: Integer;
    // Embedded vertical scrollbar, lazily created on first overflow (owned by
    // Self via Create(Self), so freed by TComponent). nil until first needed.
    FScrollBar: TTyScrollBar;
    // Embedded HORIZONTAL scrollbar (WordWrap=False only); drives FScrollX. Same
    // lazy/owned lifecycle as FScrollBar. nil until first needed.
    FHScrollBar: TTyScrollBar;
    // Reentrancy guard: TopLine->scrollbar.Position and scrollbar OnChange->
    // SetTopLine would otherwise ping-pong. Shared by both bars.
    FSyncingScroll: Boolean;
    // Lazy measuring bitmap (freed in Destroy). Shared by all per-line measures.
    FMeasureBmp: TBGRABitmap;
    // Per-line width cache (line content -> cumulative prefix widths). The hot path: a keystroke makes
    // RenderTo / caret / scrollbar code measure the caret line + every visible line repeatedly, and
    // MeasureLineWidths is O(n^2) per line; without this, an edit re-measures all of them every repaint
    // (the ~0.5s lag). Keyed by CONTENT so unchanged lines hit the cache with no index-sync across
    // insert/delete; dropped wholesale when the font signature (name/size/weight/PPI) changes, and
    // capped to bound edit-history growth.
    FLineWidthCache: specialize TDictionary<string, TTyIntArray>;
    FWidthCacheSig: string;   // font signature the cache was built for
    // Incremental hint for the line being edited: typing/erasing happens at the line END, so the new
    // content is usually a prefix-extension (append) or prefix-truncation (delete) of the last one.
    // Then we reuse the unchanged prefix widths and only measure the new tail — O(1) per keystroke,
    // and EXACT (kerning preserved, unlike summing per-char advances). Middle edits fall back to full.
    FLastMeasuredLine: string;
    FLastMeasuredWidths: TTyIntArray;
    // Cheap per-line TOTAL-width cache (line content -> full line pixel width). WidestLineWidth
    // only needs each line's TOTAL width (the LAST prefix of MeasureLineWidths), so it uses a
    // SINGLE FMeasureBmp.TextSize(line).cx per line (O(L)) instead of the O(L^2) per-character
    // prefix path. Same content key + font-signature drop discipline as FLineWidthCache; the
    // total equals MeasureLineWidths(line)[High] exactly (both are TextSize of the whole line).
    FLineTotalWidthCache: specialize TDictionary<string, Integer>;
    // Memoised widest logical-line width (px) + the font signature it was computed for. Cleared by
    // InvalidateVisualRows (every text mutation funnels through it), so a scroll/paint/scrollbar
    // pass does not re-scan all lines. FWidestWidthValid=False => recompute on next WidestLineWidth.
    FWidestWidth: Integer;
    FWidestWidthValid: Boolean;
    FWidestWidthSig: string;
    { --- Bidirectional row layout; see EnsureRowBidi for the whole argument ---
      THE GATE, memoised on the ONE line it was last asked about. TTyEdit keeps a
      document-wide flag because its document IS one line; a memo's is unbounded, and
      rescanning it per text change would put an O(document) cost on the keystroke path --
      the exact shape of the bug that once cost this control half a second per key. So the
      question asked here is "does THIS line need reordering", and the answer is kept for
      the line the caret is sitting on, which is the line every blink, every keystroke and
      every mouse move of a drag re-asks about. }
    FBidiGateLine: string;
    FBidiGateAnswer: Boolean;
    FBidiGateSeeded: Boolean;
    { Run tables per ROW SEGMENT, keyed by content -- the same discipline (and the same
      reason) as FLineWidthCache: a repaint of a bidirectional document must not rebuild a
      TBidiTextLayout per visible row per frame. Only ever reached once the gate has fired. }
    FRowBidiCache: specialize TDictionary<string, TTyMemoRowBidi>;
    FRowBidiSig: string;      // font signature the row tables were built for
    // Headless-only override of the LCL focused state. Real focus is unavailable
    // when rendering offscreen, so tests can force the caret to draw. Production
    // paint uses (Focused or FForceFocused) so this is a no-op unless set.
    FForceFocused: Boolean;
    // Fired after any mutation of the text model (insert/split/delete/merge).
    // Pure caret moves do NOT fire it.
    FOnChange: TNotifyEvent;
    { Multicast OnChange (LCL stdctrls.pp:853-855, inherited by TCustomMemo). Lazy: a memo
      nobody observes must not pay for a TMethodList. }
    FOnChangeHandlers: TMethodList;
    { Dirty flag + the by-code guard, verbatim in spirit from TTyEdit -- see there. Every
      completed mutation passes DoChange, and only a programmatic Text/Lines assignment sets
      the guard, so typing dirties the memo and `Memo.Lines := ...` cleans it. }
    FModified: Boolean;
    FTextChangeByCode: Boolean;
    { Horizontal alignment of every painted row (TMemo republishes TCustomEdit's Alignment at
      stdctrls.pp:1023). A centred multi-line block could not be produced by any other route
      here: the row renderer always started at the left content edge. }
    FAlignment: TAlignment;
    { Case folding applied to typed AND assigned text (stdctrls.pp:1028; LCL folds in
      include/customedit.inc). Reuses TTyEdit's rule so the two controls fold identically. }
    FCharCase: TEditCharCase;
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
    {$IFDEF LCLCocoa}
    // macOS IME handler (TTyCocoaImeHandler): created in Create, freed in Destroy, returned from the
    // LM_IM_COMPOSITION message so LCL-Cocoa gives us the caret-following IME view. See tyControls.CocoaWS.
    FCocoaIme: TObject;
    {$ENDIF}
    // HideSelection (default True, matches TMemo): when the control is unfocused, paint no selection
    // highlight. The selection itself is preserved; only its band is hidden.
    FHideSelection: Boolean;
    // MaxLength: caps the TOTAL content codepoint count (sum of UTF8Length over
    // all logical lines; line breaks are NOT counted). 0 = unlimited. Blocks a
    // new printable char at the cap and truncates paste to the remaining room;
    // Enter/Backspace/Delete/merge are never limited. Default 0.
    FMaxLength: Integer;
    FImeHook: TObject;   // Qt-only IME commit interceptor (nil off Qt); see tyControls.QtWS
    FImeCaretRect: TRect; // caret rect (client device px) cached each paint; fed to the Qt IME query
    // WantTabs: when True a Tab key inserts a literal tab char into the text;
    // when False (default) Tab is left to propagate so it navigates between
    // controls (the native TMemo default). Gated in KeyDown.
    FWantTabs: Boolean;
    // WantReturns: when True (default) Enter inserts a line break; when False
    // Enter is NOT consumed so the form's default button can handle it. Gated on
    // the VK_RETURN branch in KeyDown.
    FWantReturns: Boolean;
    // ScrollBars: which scrollbars the memo shows, on BOTH axes. Default ssAutoVertical
    // keeps the historical behaviour (the embedded vertical bar appears on overflow);
    // ssNone hides everything; ssVertical / ssHorizontal force one bar always-visible;
    // ssAutoVertical / ssAutoHorizontal show one on overflow; ssBoth and ssAutoBoth do
    // both. See UpdateScrollBar for the resolution, and the fuller note beside it.
    //
    // (This comment used to say the memo had no horizontal scrollbar and that the
    // horizontal styles degraded to the vertical policy. That stopped being true when the
    // horizontal bar landed -- FHScrollBar, the ssHorizontal/ssBoth arms of UpdateScrollBar
    // and a whole test unit, test.memo.hscroll -- and a comment that denies a working
    // feature costs as much as one that promises a missing one.)
    FScrollBars: TScrollStyle;
    procedure SetReadOnly(AValue: Boolean);
    procedure SetHideSelection(AValue: Boolean);
    procedure SetMaxLength(AValue: Integer);
    procedure SetWantTabs(AValue: Boolean);
    procedure SetWantReturns(AValue: Boolean);
    procedure SetScrollBars(AValue: TScrollStyle);
    procedure SetAlignment(AValue: TAlignment);
    procedure SetCharCase(AValue: TEditCharCase);
    { Fold AStr per CharCase (identical rule to TTyEdit.ApplyCharCase). '' passes through. }
    function ApplyCharCase(const AStr: string): string;
    { Re-fold every line after CharCase changes to something other than ecNormal -- LCL folds
      the EXISTING text on the setter too, so a field switched to ecUpperCase does not keep
      showing the lower-case value it already held. }
    procedure RefoldAllLines;
    { Device-px x offset added to a visual row's draw/caret/band origin under
      taCenter / taRightJustify. Zero when left-aligned, and zero whenever the row is wider
      than the viewport (scroll governs then; alignment of an overflowing row is moot -- the
      same rule TTyEdit.AlignOffset follows). }
    function RowAlignOffset(AVisualRow, AContentWidth, APPI: Integer): Integer;
    // The line separator TStrings.Text actually writes between two lines, and its
    // codepoint width. Mirrors TStrings.GetTextStr/GetLineBreakCharLBS: an explicitly
    // assigned Lines.LineBreak wins, otherwise the TextLineBreakStyle glyph (CRLF on
    // Windows). Every flat offset below is measured in these units, so if this drifts
    // from what Text emits, SelStart stops indexing Text.
    function TextLineBreak: string;
    function LineBreakCodepoints: Integer;
    // --- Flat codepoint-offset <-> (line,col) mapping. The flat offset counts the
    // FULL line separator (LineBreakCodepoints, = 2 for CRLF) for the newline BETWEEN
    // consecutive logical lines, so the offsets index the very string Text returns.
    // That is the native contract, not a convenience: TCustomEdit.GetSelText IS
    // UTF8Copy(Text, SelStart + 1, SelLength) (customedit.inc:118-121) and SelectAll
    // IS SelLength := UTF8Length(Text) (customedit.inc:222-228), while TCustomMemo.Text
    // IS Lines.Text (custommemo.inc:150-156). Charging one codepoint per newline would
    // put SelStart one behind Text per preceding line -- silently right on line 0 and
    // wrong everywhere below it, which is the worst possible failure shape. ---
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
    function GetText: TCaption;
    procedure SetText(const AValue: TCaption);
    // Total content codepoints across all logical lines (line breaks excluded).
    function ContentCodepointCount: Integer;
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
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
    // Scrollbar OnChange handlers -> SetTopLine / FScrollX (guarded against ping-pong).
    procedure ScrollBarChange(Sender: TObject);
    procedure HScrollBarChange(Sender: TObject);
    // Height (device px) the horizontal bar steals from the content when visible, else 0.
    function HScrollBarHeight: Integer;
    // Insert a FULL input-method commit (Qt6 path), bypassing LCL's TUTF8Char (String[7]) truncation.
    procedure HandleImeCommit(const ACommitUtf8: string);
    // Caret rect (client device px) for the Qt IME candidate window; empty when not focused.
    function GetImeCaretRect: TRect;
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
    // Diagnostic: number of times the O(L^2) per-character MeasureLineWidths was ENTERED (bumped at
    // function entry, incl. cache hits). The perf-regression test asserts a bulk load + widest-width
    // scroll-range scan does NOT enter it once per line (WidestLineWidth uses the cheap total path).
    FMeasureLineWidthsCalls: Integer;
    // Diagnostic: how many times the RTL gate actually SCANNED a line (memo misses only).
    // The perf guard asserts a thousand left-to-right lines cost the caret no more scans
    // than one line does -- i.e. that the gate is per line, not per document.
    FBidiGateCalls: Integer;
    { Diagnostic: how many times the ROW-LAYOUT machinery was entered (EnsureRowBidi), which
      is the work the line gate exists to avoid. It has to be counted separately from
      FBidiGateCalls and from UsesBidiCaret, because neither can see the difference:
      EnsureRowBidi has a second gate of its own (TyTextHasRTL of the segment, which is the
      question the PAINTER asks), so wedging the line gate open still produces the right
      ANSWER for left-to-right text -- it just pays a segment substring, a dictionary hash
      and a second scan per query to get there. Two mutants that forced the line gate open
      survived the whole suite until this counter existed. }
    FBidiRowLookups: Integer;
    { Diagnostic: how many TBidiTextLayout objects were actually CONSTRUCTED. Separate from
      FBidiRowLookups for the same reason that one is separate from FBidiGateCalls -- the
      output cannot tell the difference. BGRA's layout reproduces the cumulative-prefix
      caret positions EXACTLY for a string with no right-to-left codepoint in it, so
      removing the second gate (TyTextHasRTL of the segment, which is the question the
      PAINTER asks) changes not one pixel; it just lays every row out twice. A mutant that
      did exactly that survived two rounds of guards until this counter existed. }
    FBidiLayoutBuilds: Integer;
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
    // Effective point size for a resolved style (routes through the shared resolver so a
    // skin that suppresses font-size gets the theme's --font-size-base). Protected so the
    // headless probes can configure a measuring bitmap exactly as the control does.
    function EffectiveFontSize(const S: TTyStyleSet): Integer;
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
    // Cheap TOTAL width of ALine (px) = a single TextSize(ALine).cx, cached by content. Equals
    // MeasureLineWidths(ALine)[High] exactly but skips the O(L^2) per-character prefix work. Used by
    // WidestLineWidth (which only needs the total), NOT for caret/selection/render geometry.
    function MeasureLineTotalWidth(const ALine: string; APPI: Integer): Integer;
    // Pixel x of the caret boundary before codepoint ACol on ALine.
    function ColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
    { Where the caret for (ALine, ACol) is DRAWN, in control device px, BEFORE the
      horizontal scroll and the row's alignment offset are applied -- the same frame
      TTyEdit.CaretDrawXAt answers in. AAfterPrev is the caret's AFFINITY (see
      FCaretAfterPrev): which of the two glyphs beside the column it stands against. For a
      row with no right-to-left script in it the two answers are identical. }
    { Which visual row owns caret (ALine, ACol), with the soft-wrap tie-break. Reads the
      row cache directly, so callers must have ensured it. }
    function CaretOwningRow(ALine, ACol: Integer): Integer;
    function CaretDrawXAt(ALine, ACol: Integer; AAfterPrev: Boolean; APPI: Integer): Integer;
    // Where the LIVE caret is drawn: CaretDrawXAt for (FCaretLine, FCaretCol) resolved
    // with the affinity the last movement left behind.
    function CaretDrawX(APPI: Integer): Integer;
    { WHICH PATH the caret is currently coming from: the per-row bidirectional run table, or
      the prefix sum. A diagnostic, and it has to exist, because pixels cannot answer it --
      for a row with a single run the two paths produce the SAME numbers, so a gate wedged
      permanently open is invisible in the output and shows up only in the cost. }
    function UsesBidiCaret(APPI: Integer): Boolean;
    // --- Bidirectional row layout (all no-ops on a left-to-right document) ---
    { THE GATE. Does ALine carry any right-to-left script? Memoised on the last line asked
      about, so a run of caret queries on an unchanged line costs one string compare and a
      thousand left-to-right lines cost exactly what one line costs. }
    function LineHasRTL(const ALine: string): Boolean;
    // The substring RenderTo actually draws for visual row AVisualRow.
    function RowSegmentOf(AVisualRow: Integer): string;
    { Build (or fetch) the run table for a row SEGMENT. False when the segment needs no
      reordering -- which is also what the painter decides, by asking TyTextHasRTL of the
      very string it is about to draw. }
    function EnsureRowBidi(const ASeg: string; APPI: Integer;
      out ARB: TTyMemoRowBidi): Boolean;
    // Gate then table, for a visual row. False => this row is answered by the prefix sum.
    function RowBidi(AVisualRow, APPI: Integer; out ARB: TTyMemoRowBidi): Boolean;
    { The x of caret boundary AIndex measured INSIDE run ARun. Only meaningful for
      ARun.First <= AIndex <= ARun.Last. }
    function RowBidiEdgeX(const ARB: TTyMemoRowBidi; ARun, AIndex: Integer): Integer;
    // The run a caret at row-relative AIndex with affinity AAfterPrev binds to; -1 if none.
    function RowBidiCaretRun(const ARB: TTyMemoRowBidi; AIndex: Integer;
      AAfterPrev: Boolean): Integer;
    // The run immediately left (ADir<0) or right (ADir>0) of ARun on screen; -1 at the end.
    function RowBidiNeighbourRun(const ARB: TTyMemoRowBidi; ARun, ADir: Integer): Integer;
    { Device x of a caret within visual row AVisualRow, measured from the row's own left
      text edge, for the row-relative column ARowCol. The prefix sum when the row needs no
      reordering, the run table's answer when it does. }
    function RowCaretRelX(AVisualRow, ARowCol: Integer; AAfterPrev: Boolean;
      APPI: Integer): Integer;
    { The visually leftmost (ASide<0) or rightmost (ASide>0) caret column of a visual row,
      as a LOGICAL column, plus the affinity that puts the caret on that side. For a row
      with no reordering these are simply StartCol and EndCol. }
    procedure RowVisualEdge(AVisualRow, ASide, APPI: Integer;
      out ACol: Integer; out AAfterPrev: Boolean);
    { Park FCaretAfterPrev at its default -- the caret stands against the character BEFORE
      it. Called by the navigations that move the caret without choosing a glyph for it to
      stand against: a programmatic caret/selection write, a word jump, Home, End, a
      completed edit. The mouse and the Left/Right arrows DO choose, and set it themselves. }
    procedure DefaultCaretAffinity;
    { Move the caret ONE GLYPH in the direction pressed (ADir: -1 left, +1 right), crossing
      into the neighbouring visual row at the row's VISUAL edge. Returns True when this
      row's caret is governed by a run table -- whether or not the caret actually moved --
      so the caller knows to skip the logical walk. False means "no reordering here, walk
      the string exactly as before". }
    function MoveCaretVisualH(ADir, APPI: Integer): Boolean;
    { True when a vertical move must be resolved by SCREEN X rather than by the remembered
      logical column: a remembered column only names the same place on both lines when both
      read the same way. Consulted only on the no-wrap path -- the wrap path is already an
      x-preserving move. }
    function VerticalMoveNeedsX(ATargetLine: Integer): Boolean;
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
    // Select the word (or same-class run) around column ACol on line ALine -- the
    // double-click primitive. Sets anchor+caret; the per-line analogue of
    // TTyEdit.SelectWordAt.
    procedure SelectWordAtLineCol(ALine, ACol: Integer);
    // Select the whole logical line ALine (col 0 .. line end, the newline excluded) --
    // the triple-click primitive.
    procedure SelectLine(ALine: Integer);
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
    { Fired by FLines itself, so a mutation made THROUGH the published Lines is seen. }
    procedure LinesChanged(Sender: TObject);
    // Map a logical caret (ALine,ACol) to the visual row index that owns it plus
    // the device-x of the caret on that row. At a soft-wrap boundary column the
    // caret binds to the EARLIER (line-end) row (tie-break), so a caret typed at
    // end-of-row stays visually at the end of that row rather than jumping to the
    // start of the next. AX is the same TextStartX-relative pixel x that
    // ColPixelXAt would give for (line,col) — visual rows do not change the
    // horizontal origin (horizontal scroll is applied later by the renderer).
    procedure CaretToVisual(ALine, ACol, AContentWidth, APPI: Integer;
      out AVisualRow, AX: Integer);
    { The same, told which side of a direction boundary the caret is standing on. The
      two-argument form above delegates here with the DEFAULT affinity, so a caller that
      does not know about glyphs (and the headless row tests, which do not) is unchanged.

      Note the two questions the memo has to answer at once and must not confuse: the WRAP
      tie-break decides which ROW owns a column sitting on a soft-wrap boundary (the earlier
      row wins, unchanged), and the DIRECTION affinity decides which of two x positions that
      column has inside that row. }
    procedure CaretToVisualEx(ALine, ACol: Integer; AAfterPrev: Boolean;
      AContentWidth, APPI: Integer; out AVisualRow, AX: Integer);
    { The visual row list for AContentWidth: the CACHE when it matches, a fresh build when
      the caller asked about a different width (the headless row tests do). This is on the
      caret path -- every keystroke, every mouse move of a drag, every blink -- and
      rebuilding the whole document's row list per query is the shape of the bug that once
      cost this control half a second per key. }
    function RowsFor(AContentWidth, APPI: Integer): TTyVisualRowArray;
    // Inverse of CaretToVisual: given a visual row index and a device-x, return
    // the logical (line,col) under that x, clamped to the row's [StartCol,EndCol]
    // segment so a click never escapes the row it landed on.
    procedure VisualToCaret(AVisualRow, AX, AContentWidth, APPI: Integer;
      out ALine, ACol: Integer);
    { The same, also reporting which side of a direction boundary the x landed on. That half
      of the answer cannot be dropped: at a boundary the column alone is two different places
      on screen, so a hit test that returned only the column would leave the caret to guess,
      and a click on the far side of an embedded run would draw the caret on the near side. }
    procedure VisualToCaretEx(AVisualRow, AX, AContentWidth, APPI: Integer;
      out ALine, ACol: Integer; out AAfterPrev: Boolean);
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
    // Collapse the selection onto the caret (anchor := caret).
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
    // Right-click: the user's PopupMenu wins if set, otherwise show the default themed
    // text-edit menu at the click point (ITEM 1).
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
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
    { BREAKING and deliberate, mirroring TTyEdit: LCL's ClearSelection DELETES the
      selected text; ours collapsed the highlight and left it. It was also PROTECTED
      while LCL's is public, so the wrong behaviour was not even reachable to be noticed.
      CollapseSelection is the old behaviour, kept and named. }
    procedure ClearSelection;
    procedure CollapseSelection;
    { Append one line. LCL's TCustomMemo publishes this and it is what the running-log
      pattern reaches for; without it the same thing had to be spelled Lines.Add -- which
      is fine now that Lines notifies, and was silent before it did. }
    procedure Append(const AValue: string);
    { Empty the memo. }
    procedure Clear;
    // Scroll the TEXT VIEW by a device-pixel delta -- the memo meaning of ScrollBy
    // (TCustomMemo.ScrollBy -> ScrollBy_WS, custommemo.inc:45-48), NOT the inherited
    // TWinControl one, which SetBounds()es every child (wincontrol.inc:6255-6268).
    // Without this override a caller reaching for the documented memo scroll API
    // would drag this memo's own embedded scrollbars off their docked edges and
    // leave the text exactly where it was.
    //
    // Overriding is safe HERE specifically. TTyScrollBox must not do the same: its
    // ScrollByDelta calls ScrollBy(-dx,-dy) meaning the TWinControl child-mover, so
    // an override there would call itself. TTyMemo never calls ScrollBy at all (it
    // scrolls through SetTopLine / FScrollX), and no LCL code path calls ScrollBy on
    // a plain TCustomControl -- the only LCL caller is TControlScrollBar
    // (controlscrollbar.inc:79-81), which exists only on a TScrollingWinControl.
    //
    // Sign follows TWinControl: a POSITIVE delta moves the CONTENT down/right, i.e.
    // reveals earlier rows / earlier columns. Vertical motion is quantised to whole
    // visual rows (the view's unit), so a sub-row DeltaY is a no-op; callers wanting
    // row units have TopLine/SetTopLine.
    procedure ScrollBy(DeltaX, DeltaY: Integer); override;
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
    // Select the whole document (anchor->(0,0), caret->end of last line).
    procedure SelectAll;
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard;
    // Undo/redo API. Both honor the Enabled guard. Undo restores the previous
    // snapshot (and moves the current state onto the redo stack); Redo re-applies.
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    // --- ITyTextEditActions: the seam the shared default context menu drives (thin
    // delegates to the public API above; see tyControls.TextMenu). ---
    function TeControl: TControl;
    function TeController: TTyStyleController;
    procedure TeUndo;
    procedure TeRedo;
    procedure TeCut;
    procedure TeCopy;
    procedure TePaste;
    procedure TeSelectAll;
    function TeCanUndo: Boolean;
    function TeCanRedo: Boolean;
    function TeHasSelection: Boolean;
    function TeCanPaste: Boolean;
    function TeHasText: Boolean;
    function TeIsReadOnly: Boolean;
    // --- ITyImeEditable: the seam the macOS IME handler drives during CJK composition (thin
    // delegates to members below; see tyControls.CocoaWS / tyControls.TextMenu). ---
    function  ImeTargetControl: TWinControl;
    function  ImeIsReadOnly: Boolean;
    function  ImeCaretBoundClient: TRect;
    function  ImeCaretIndex: Integer;
    procedure ImeSessionBegin;
    procedure ImeSessionEnd;
    procedure ImeReplace(AStart, ALen: Integer; const AText: string);
    {$IFDEF LCLCocoa}
    // macOS: answer LCL-Cocoa's handle-creation query (LM_IM_COMPOSITION) with our IME handler so the
    // control gets the IME-capable native view whose candidate window follows the caret.
    procedure CocoaImComposition(var Message: TLMessage); message LM_IM_COMPOSITION;
    {$ENDIF}
    // Horizontal scroll offset in device px (>= 0; WordWrap=False only). Mirrors
    // TTyEdit.ScrollX. Read-only: it is driven by EnsureCaretXVisible/ClampScrollX.
    property ScrollX: Integer read FScrollX;
    // Flat codepoint-offset selection/caret accessors (runtime; mirror native
    // TCustomMemo's public SelStart/SelLength/SelText/CaretPos integer addressing).
    // The offsets index the SAME string Text returns, counting the FULL line
    // separator between lines (two codepoints for CRLF on Windows), so the native
    // idiom works verbatim:
    //   Memo.SelStart := Pos(Needle, Memo.Text) - 1;   Memo.SelLength := Length(Needle);
    // and SelText always equals UTF8Copy(Text, SelStart + 1, SelLength).
    // SelStart = flat(ordered selection start); SelLength = |flat(caret) -
    // flat(anchor)|; SelText = the selected text (line breaks as in Text);
    // CaretPos = flat(caret). Writing SelStart collapses the selection there;
    // writing SelLength extends the caret from SelStart; writing SelText replaces
    // the selection (single OnChange); writing CaretPos places the caret (collapse).
    // An offset landing inside a CRLF is clamped to the end of the preceding line.
    // NOTE: SelectAll gives SelLength = UTF8Length(Text) MINUS the trailing break
    // TStrings.Text appends after the last line -- that trailing break is not a
    // caret position. (The LCL's own TCustomEdit.SelectAll includes it.)
    property SelStart: Integer read GetSelStart write SetSelStart;
    property SelLength: Integer read GetSelLength write SetSelLength;
    property SelText: string read GetSelText write SetSelText;
    { A FLAT codepoint offset, not LCL's TPoint. LCL's TCustomMemo overrides GetCaretPos to
      return line/column (stdctrls.pp:919, custommemo.inc:176-179), and the two types share no
      assignment, so a ported `P := Memo.CaretPos` fails to COMPILE rather than misbehaving --
      the loud failure. What was genuinely unreachable was the information itself: the 2-D
      accessors were protected, so every "Ln 12, Col 4" indicator had to subclass the memo.
      They are public now (CaretLine / CaretCol / SetCaret, just below), which is the part
      that was missing; the flat form keeps its name because SelStart/SelLength/SelText are
      flat too and the four have to address the same string. }
    property CaretPos: Integer read GetCaretPos write SetCaretPos;
    { The caret's LINE and COLUMN (0-based codepoints) -- what LCL answers from CaretPos on a
      memo, and the pair a status bar, a go-to-line command or an error highlighter needs.
      These were PROTECTED, so the one piece of information a multi-line caret carries and a
      flat offset does not was reachable only by subclassing. SetCaret places both. }
    function CaretLine: Integer;
    function CaretCol: Integer;
    procedure SetCaret(ALine, ACol: Integer);
    { Dirty flag, LCL's TCustomEdit.Modified inherited by TCustomMemo (stdctrls.pp:867): True
      once the USER has changed the text, False again after a programmatic Text/Lines write.
      See TTyEdit.Modified -- the distinction is the point, and OnChange cannot supply it. }
    property Modified: Boolean read FModified write FModified;
    { Multicast OnChange (stdctrls.pp:853-855). Same reason as on TTyEdit: the single OnChange
      slot belongs to the application, and an observer must not have to take it. }
    procedure AddHandlerOnChange(const AnOnChangeEvent: TNotifyEvent; AsFirst: Boolean = False);
    procedure RemoveHandlerOnChange(const AnOnChangeEvent: TNotifyEvent);
    procedure RemoveAllHandlersOfObject(AnObject: TObject); override;
  published
    property Lines: TStrings read GetLines write SetLines;
    // Whole-document text as one string with platform line breaks (TStrings.Text
    // get/set). Writing replaces all lines, collapses the caret to the origin and
    // fires OnChange.
    property Text: TCaption read GetText write SetText;
    // When True, a Tab key inserts a literal tab char into the text; when False
    // (default) Tab navigates between controls (native TMemo default).
    property WantTabs: Boolean read FWantTabs write SetWantTabs default False;
    // When True (default), Enter inserts a line break; when False, Enter is not
    // consumed so the form's default button can handle it.
    property WantReturns: Boolean read FWantReturns write SetWantReturns default True;
    // Which scrollbars show (like TMemo). Default ssAutoVertical (vertical bar on overflow).
    //   ssNone           -> neither bar;
    //   ssVertical/ssBoth   -> force the vertical bar;  ssAutoVertical/ssAutoBoth -> vertical on overflow;
    //   ssHorizontal/ssBoth -> force the horizontal bar; ssAutoHorizontal/ssAutoBoth -> horizontal on overflow.
    // The horizontal bar only applies when WordWrap=False (wrap mode never scrolls horizontally).
    property ScrollBars: TScrollStyle read FScrollBars write SetScrollBars
      default ssAutoVertical;
    // Soft word-wrap toggle. Default False (no wrap; long lines scroll horizontally instead).
    // True wraps long logical lines into multiple visual rows at word boundaries.
    property WordWrap: Boolean read FWordWrap write SetWordWrap default False;
    // When True, the memo ignores all user edits but still allows caret/selection
    // navigation, Copy and SelectAll; programmatic Lines := still mutates. Cut
    // acts as Copy. Default False.
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property HideSelection: Boolean read FHideSelection write SetHideSelection default True;
    { Horizontal placement of EVERY painted row (TMemo republishes it at stdctrls.pp:1023).
      A centred title block or a right-aligned numeric column could not be produced by any
      route here before: the renderer always started each row at the left content edge, and
      no theme token moves text. Alignment is ignored for a row that is WIDER than the
      viewport -- there is nothing to centre, and horizontal scroll owns the origin then
      (TTyEdit.AlignOffset takes the same position). }
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    { Force typed AND assigned text to one case (stdctrls.pp:1028). Reuses TTyEdit's fold, so
      an upper-case-only note field behaves the same in both controls; setting it re-folds the
      text already held, as LCL does. }
    property CharCase: TEditCharCase read FCharCase write SetCharCase default ecNormal;
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
    // Standard control properties/events re-published to match TMemo (all inherited; the key/mouse
    // overrides call inherited so the events fire). Color/BorderStyle are intentionally NOT published:
    // this control is theme-/self-drawn. BidiMode stays out of scope -- RTL is realized by the
    // widgetset on a native EDIT handle, so there is nothing for a self-drawn control to inherit.
    // (Alignment and CharCase used to be listed here as out of scope too. Alignment was a real
    // capability gap and CharCase was one method away from the sibling Edit; both are above now.)
    property TabStop default True;
    property TabOrder;
    property Visible;
    property PopupMenu;
    property ShowHint;
    property ParentShowHint;
    property Constraints;
    property BorderSpacing;
    property DragCursor;
    property DragKind;
    property DragMode;
    property OnContextPopup;
    property OnDblClick;
    property OnDragDrop;
    property OnDragOver;
    property OnEndDrag;
    property OnStartDrag;
    property OnEditingDone;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyPress;
    property OnKeyUp;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
  end;

implementation

constructor TTyMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  Cursor := crIBeam;
  FLines := TStringList.Create;
  { The one line TTyComboBox already had and this control did not. }
  TStringList(FLines).OnChange := @LinesChanged;
  FCaretLine := 0;
  FCaretCol := 0;
  FCaretAfterPrev := True;
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
  FClickCount := 0;
  FLastClickTick := 0;
  FTextMenu := nil;            // lazily built on first right-click
  FTopRow := 0;
  FScrollX := 0;
  FWordWrap := False;
  FVisualRows := nil;
  FVisualRowsValid := False;
  FVisualRowsWidth := -1;
  FScrollBar := nil;
  FHScrollBar := nil;
  FSyncingScroll := False;
  FMeasureBmp := nil;
  FLineWidthCache := specialize TDictionary<string, TTyIntArray>.Create;
  FLineTotalWidthCache := specialize TDictionary<string, Integer>.Create;
  FWidthCacheSig := '';
  FWidestWidth := 0;
  FWidestWidthValid := False;
  FWidestWidthSig := '';
  FMeasureLineWidthsCalls := 0;
  FBidiGateCalls := 0;
  FBidiRowLookups := 0;
  FBidiLayoutBuilds := 0;
  { Both bidirectional caches are keyed by CONTENT -- the gate by the line string, the run
    tables by the row's segment string -- so neither needs an invalidation seam: a text
    change simply misses. That is the same argument FLineWidthCache is built on, and it is
    what keeps a keystroke from having to drop anything. }
  FBidiGateLine := '';
  FBidiGateAnswer := False;
  FBidiGateSeeded := False;
  FRowBidiCache := specialize TDictionary<string, TTyMemoRowBidi>.Create;
  FRowBidiSig := '';
  FForceFocused := False;
  FUndoStack := TTyUndoStack.Create;
  FSuspendUndo := False;
  FReadOnly := False;
  {$IFDEF LCLCocoa}
  // Create BEFORE the handle exists: LCL-Cocoa queries LM_IM_COMPOSITION inside CreateHandle. Self is
  // passed as ITyImeEditable; the handler holds it as a COM field whose _AddRef is a no-op (no cycle).
  FCocoaIme := TTyCocoaImeHandler.Create(Self);
  {$ENDIF}
  FHideSelection := True;      // TMemo default: hide the selection highlight when unfocused
  FMaxLength := 0;
  FWantTabs := False;          // Tab navigates by default (native TMemo default)
  FWantReturns := True;        // Enter inserts a line break by default
  FScrollBars := ssAutoVertical;  // historical behaviour: bar on overflow
  FCaretVisible := True;       // solid caret until a real timer toggles it
  FBlinkTimer := nil;          // lazy: created only when HandleAllocated
  FBlinkElapsedMs := 0;
  FAlignment := taLeftJustify;
  FCharCase := ecNormal;
  FModified := False;
  { A screen reader has no native peer to fall back on for a self-drawn control, so without
    this the memo reads as an unidentified custom control. LCL's TCustomEdit.Create says
    larTextEditorSingleline (include/customedit.inc:87); a memo is the multi-line one. }
  AccessibleRole := larTextEditorMultiline;
  Width := 200;
  Height := 120;
end;

destructor TTyMemo.Destroy;
begin
  // The default context menu holds only an interface reference back to Self (TComponent
  // interface calls do not reference-count), so freeing it here touches nothing else.
  FreeAndNil(FTextMenu);
  {$IFDEF LCLCocoa}
  FreeAndNil(FCocoaIme);   // macOS IME handler (no strong refs back to Self)
  {$ENDIF}
  // Free the timer first so its OnTimer callback can never fire mid-teardown.
  FreeAndNil(FBlinkTimer);
  TyImeUninstall(FImeHook);   // in case DestroyWnd never ran (Qt-only; no-op elsewhere)
  FUndoStack.Free;
  FMeasureBmp.Free;
  FLineWidthCache.Free;
  FLineTotalWidthCache.Free;
  FRowBidiCache.Free;
  FLines.Free;
  FreeAndNil(FOnChangeHandlers);
  inherited Destroy;
end;

// ---- Multicast OnChange (LCL customedit.inc:91-97) ----

procedure TTyMemo.AddHandlerOnChange(const AnOnChangeEvent: TNotifyEvent;
  AsFirst: Boolean = False);
begin
  if FOnChangeHandlers = nil then FOnChangeHandlers := TMethodList.Create;
  FOnChangeHandlers.Add(TMethod(AnOnChangeEvent), not AsFirst);
end;

procedure TTyMemo.RemoveHandlerOnChange(const AnOnChangeEvent: TNotifyEvent);
begin
  if FOnChangeHandlers <> nil then
    FOnChangeHandlers.Remove(TMethod(AnOnChangeEvent));
end;

procedure TTyMemo.RemoveAllHandlersOfObject(AnObject: TObject);
begin
  inherited RemoveAllHandlersOfObject(AnObject);
  if FOnChangeHandlers <> nil then
    FOnChangeHandlers.RemoveAllMethodsOfObject(AnObject);
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
  TyImeSetFocus(FImeHook, True);   // GTK2: start our IM context composing (no-op elsewhere)
  Invalidate;   // show caret + (HideSelection) the selection band immediately on focus-gain
end;

procedure TTyMemo.DoExit;
begin
  inherited DoExit;
  TyImeSetFocus(FImeHook, False);   // GTK2: stop our IM context composing (no-op elsewhere)
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

procedure TTyMemo.SetHideSelection(AValue: Boolean);
begin
  if FHideSelection = AValue then Exit;
  FHideSelection := AValue;
  if not Focused then Invalidate;   // only changes the unfocused appearance
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

function TTyMemo.TextLineBreak: string;
// Reproduce TStrings.GetTextStr's separator choice exactly (it calls the private
// GetLineBreakCharLBS): an assigned LineBreak overrides, otherwise the style glyph.
// GetText is FLines.Text, so this IS the separator sitting between two lines in Text.
begin
  if FLines.LineBreak <> sLineBreak then
    Exit(FLines.LineBreak);
  case FLines.TextLineBreakStyle of
    tlbsLF: Result := #10;
    tlbsCR: Result := #13;
  else
    Result := #13#10;   // tlbsCRLF
  end;
end;

function TTyMemo.LineBreakCodepoints: Integer;
begin
  Result := UTF8Length(TextLineBreak);
  // A zero-width separator would make two adjacent lines share offsets and break
  // FlatToLineCol's descent; Text always emits at least one char, so floor at 1.
  if Result < 1 then Result := 1;
end;

function TTyMemo.LineColToFlat(ALine, ACol: Integer): Integer;
// Sum of (LineLen + separator width) for every line strictly above ALine, plus ACol.
// Clamped into the model so out-of-range inputs map to a valid offset.
var
  i, MaxLine, NL: Integer;
begin
  MaxLine := LineCountLogical - 1;
  if ALine < 0 then ALine := 0;
  if ALine > MaxLine then ALine := MaxLine;
  if ACol < 0 then ACol := 0;
  if ACol > LineLen(ALine) then ACol := LineLen(ALine);
  NL := LineBreakCodepoints;   // hoisted: constant for the whole walk
  Result := 0;
  for i := 0 to ALine - 1 do
    Inc(Result, LineLen(i) + NL);  // + the full separator Text writes after line i
  Inc(Result, ACol);
end;

procedure TTyMemo.FlatToLineCol(AOffset: Integer; out ALine, ACol: Integer);
// Walk lines accumulating (LineLen + separator width) until AOffset lands within a
// line's [0..LineLen] span (the trailing slot is the position before that line's
// separator). Clamps a negative offset to (0,0) and an over-large offset to the end
// of the last line. Offsets landing strictly INSIDE a multi-char separator (the slot
// between CR and LF) are not caret positions; they bind to the end of the line the
// separator follows, so no caller can wedge the caret inside a line break.
var
  i, MaxLine, Remaining, Span, NL: Integer;
begin
  ALine := 0;
  ACol := 0;
  if AOffset <= 0 then Exit;
  MaxLine := LineCountLogical - 1;
  NL := LineBreakCodepoints;
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
    // Consume this line plus its trailing separator and move on.
    Dec(Remaining, Span + NL);
    if Remaining < 0 then
    begin
      // AOffset fell on (or inside) the separator: bind to end of this line.
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
  DefaultCaretAffinity;   // a flat offset names a codepoint, not a glyph; see SetCaret
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
  DefaultCaretAffinity;   // likewise
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

function TTyMemo.GetText: TCaption;
begin
  // Whole-document string with platform line breaks (TStrings.Text semantics).
  Result := FLines.Text;
end;

procedure TTyMemo.SetText(const AValue: TCaption);
begin
  // Replace all lines from the string (split on line breaks by TStrings.Text),
  // collapse the caret/selection to the origin, refresh layout + fire OnChange.
  BeginUndoStep(uskNone);
  FLines.Text := ApplyCharCase(AValue);
  FCaretLine := 0;
  FCaretCol := 0;
  FSelAnchorLine := 0;
  FSelAnchorCol := 0;
  FDesiredCol := 0;
  { A programmatic write: OnChange still fires (LCL's does too), but it must not dirty the
    field -- that difference is the whole content of Modified. }
  FTextChangeByCode := True;
  try
    AfterEdit(Font.PixelsPerInch);
  finally
    FTextChangeByCode := False;
  end;
  FModified := False;
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

procedure TTyMemo.LinesChanged(Sender: TObject);
begin
  { Lines is handed out bare, so a mutation THROUGH it -- Lines.Add, Lines.Delete, Lines[i] :=,
    Lines.Text := -- never reached the control: only the Lines SETTER invalidated. It looked
    like it worked, because the visual-row cache starts invalid and lines added while the form
    is still being built render fine; it broke on the append AFTER the first paint, which is the
    running-log pattern two of our own demos are written in.

    Reached the same way TTyComboBox reaches its own list (FItems.OnChange), which is what makes
    the omission an oversight rather than a position.

    Deliberately NOT an undo step: an undo step belongs to an edit the user made, and code
    appending to a log is not that. The SETTER keeps pushing one, as it did. }
  if FInLinesChange then Exit;   // our own Assign inside SetLines re-enters here
  ClampCaret;
  InvalidateVisualRows;
  if FTopRow > MaxTopLine then FTopRow := MaxTopLine;
  if FTopRow < 0 then FTopRow := 0;
  UpdateScrollBar;
  Invalidate;
end;

procedure TTyMemo.SetLines(AValue: TStrings);
begin
  // Capture a fresh (non-typing) undo step only when the assignment actually
  // changes the content, so a no-op reassign does not push a spurious step and
  // TestSetLinesClampsCaret (which never touches undo) is unaffected.
  if (AValue = nil) or (AValue.Text <> FLines.Text) then
    BeginUndoStep(uskNone);
  FInLinesChange := True;      // the notification would duplicate what follows
  try
    FLines.Assign(AValue);
  finally
    FInLinesChange := False;
  end;
  ClampCaret;
  // The text model changed: any cached wrap layout is stale.
  InvalidateVisualRows;
  // Clamp the window and refresh the scrollbar in case the row count changed.
  if FTopRow > MaxTopLine then FTopRow := MaxTopLine;
  if FTopRow < 0 then FTopRow := 0;
  UpdateScrollBar;
  FModified := False;   // loading content into the control is not the user editing it
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
  { The LIVE affinity, not the default: the desired x has to be where the caret is actually
    DRAWN, or a following Up/Down would re-project a position the user never saw. }
  CaretToVisualEx(FCaretLine, FCaretCol, FCaretAfterPrev, CW, APPI, VRow, CaretAbsX);
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
  CaretToVisualEx(FCaretLine, FCaretCol, FCaretAfterPrev, CW, APPI, CurRow, CaretAbsX);
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
  { The affinity comes from the hit test too. A vertical move lands the caret ON a glyph
    boundary of the target row, and on a reordered row that boundary has two sides -- the
    one the x fell on is the one the user is looking at. }
  VisualToCaretEx(TargetRow, TargetAbsX, CW, APPI, NewLine, NewCol, FCaretAfterPrev);
  FCaretLine := NewLine;
  FCaretCol := NewCol;
  // FDesiredX intentionally NOT refreshed: a run of Up/Down tracks the original x.
end;

function TTyMemo.MoveCaretVisualH(ADir, APPI: Integer): Boolean;
var
  CW, VRow, X, RS, RowCol, r, q, j, TargetRow, EdgeCol: Integer;
  RB: TTyMemoRowBidi;
  EdgeAfterPrev: Boolean;
begin
  CW := ContentWidthFor(APPI);
  EnsureVisualRows(APPI);
  CaretToVisualEx(FCaretLine, FCaretCol, FCaretAfterPrev, CW, APPI, VRow, X);
  if not RowBidi(VRow, APPI, RB) then
    Exit(False);   // nothing reordered here: the caller walks the string exactly as before

  { From here on the answer is OURS whatever happens, including "the caret did not move".
    Falling through to the logical walk at a reordered row's edge would step the caret in the
    OPPOSITE direction from the key pressed: at the visual LEFT end of a right-to-left run
    the caret sits on the run's LAST column, and Dec would walk it back to the right. }
  Result := True;
  RS := FVisualRows[VRow].StartCol;
  RowCol := FCaretCol - RS;
  r := RowBidiCaretRun(RB, RowCol, FCaretAfterPrev);
  if r < 0 then Exit;

  { Inside a right-to-left run the screen and the string run opposite ways, so a rightward
    keypress is a BACKWARD step through the codepoints. This one line is the whole of "Left
    and Right are visual movement in text". }
  if RB.Runs[r].RTL then j := RowCol - ADir else j := RowCol + ADir;
  if (j >= RB.Runs[r].First) and (j <= RB.Runs[r].Last) then
  begin
    FCaretCol := RS + j;
    FCaretAfterPrev := j > RB.Runs[r].First;
    Exit;
  end;

  { The step left the run: cross to the one that sits next to it ON SCREEN and land one
    glyph inside it, measured from the edge we arrived at. Landing ON that edge instead
    would be a keypress that did not move the caret, because a run's near edge is the same
    point as its neighbour's far edge. }
  q := RowBidiNeighbourRun(RB, r, ADir);
  if q >= 0 then
  begin
    if ADir > 0 then
    begin
      if RB.Runs[q].RTL then j := RB.Runs[q].Last - 1 else j := RB.Runs[q].First + 1;
    end
    else
      if RB.Runs[q].RTL then j := RB.Runs[q].First + 1 else j := RB.Runs[q].Last - 1;
    FCaretCol := RS + j;
    FCaretAfterPrev := j > RB.Runs[q].First;
    Exit;
  end;

  { The step left the ROW as well: cross into the neighbouring VISUAL row and land on ITS
    far visual edge -- the right edge going left, the left edge going right. This is the
    generalisation of the plain "previous line's end / next line's start", and on a
    left-to-right neighbour it produces exactly those two columns. }
  TargetRow := VRow + ADir;
  if (TargetRow < 0) or (TargetRow > High(FVisualRows)) then Exit;
  if ADir > 0 then
    RowVisualEdge(TargetRow, -1, APPI, EdgeCol, EdgeAfterPrev)
  else
    RowVisualEdge(TargetRow, +1, APPI, EdgeCol, EdgeAfterPrev);
  FCaretLine := FVisualRows[TargetRow].Line;
  FCaretCol := EdgeCol;
  FCaretAfterPrev := EdgeAfterPrev;
end;

function TTyMemo.VerticalMoveNeedsX(ATargetLine: Integer): Boolean;
var
  Cur, Tgt: string;
begin
  { A remembered COLUMN names the same place on both lines only when both read the same way.
    Asked of BOTH lines because either one being reordered breaks the correspondence: moving
    off a Hebrew line onto a Latin one is as wrong as the other way round.

    Two gate calls rather than one, and deliberately so -- the memo is one slot deep, so this
    costs two scans per Up/Down keypress on a left-to-right document. That is per KEYPRESS,
    not per query, and it is two scans of a LINE, never of the document. }
  if FCaretLine < FLines.Count then Cur := FLines[FCaretLine] else Cur := '';
  if (ATargetLine >= 0) and (ATargetLine < FLines.Count) then
    Tgt := FLines[ATargetLine]
  else
    Tgt := '';
  Result := LineHasRTL(Cur) or LineHasRTL(Tgt);
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

procedure TTyMemo.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  { Only the draw ORIGIN moves. Wrapping, measurement and the (line,col) model are all
    alignment-free, so the visual-row cache stays valid -- rebuilding it here would re-measure
    every line for a repaint that needs none. }
  Invalidate;
end;

function TTyMemo.ApplyCharCase(const AStr: string): string;
begin
  case FCharCase of
    ecUppercase: Result := UTF8UpperCase(AStr);
    ecLowerCase: Result := UTF8LowerCase(AStr);
  else
    Result := AStr;
  end;
end;

procedure TTyMemo.RefoldAllLines;
var
  i: Integer;
  folded: string;
  didFold: Boolean;
begin
  if FCharCase = ecNormal then Exit;
  didFold := False;
  FInLinesChange := True;   // one invalidation at the end, not one per line
  try
    for i := 0 to FLines.Count - 1 do
    begin
      folded := ApplyCharCase(FLines[i]);
      if folded <> FLines[i] then
      begin
        FLines[i] := folded;
        didFold := True;
      end;
    end;
  finally
    FInLinesChange := False;
  end;
  if didFold then
  begin
    InvalidateVisualRows;
    Invalidate;
  end;
end;

procedure TTyMemo.SetCharCase(AValue: TEditCharCase);
begin
  if FCharCase = AValue then Exit;
  FCharCase := AValue;
  { Re-case what is already held, as LCL and TTyEdit.SetCharCase both do: a field switched to
    ecUpperCase that goes on showing its lower-case value is the surprising half. Not an undo
    step and not a Modified change -- it is a normalisation the program asked for, not an edit
    the user made. }
  RefoldAllLines;
end;

function TTyMemo.RowAlignOffset(AVisualRow, AContentWidth, APPI: Integer): Integer;
var
  RL, RS, RE, w: Integer;
  Line: string;
  Widths: TTyIntArray;
begin
  Result := 0;
  { Left-justified is the default and the hot path: exit before measuring anything, so an
    unaligned memo pays nothing and renders byte-identically to before. }
  if FAlignment = taLeftJustify then Exit;
  if (AContentWidth <= 0) or (AVisualRow < 0) or (AVisualRow > High(FVisualRows)) then Exit;
  RL := FVisualRows[AVisualRow].Line;
  RS := FVisualRows[AVisualRow].StartCol;
  RE := FVisualRows[AVisualRow].EndCol;
  if RL < FLines.Count then Line := FLines[RL] else Line := '';
  { The per-line width cache is what makes this affordable per paint: the measure is keyed by
    line CONTENT, so after the first pass every visible row is a dictionary hit. (The selection
    band on the same row already measures the same line the same way.) }
  Widths := MeasureLineWidths(Line, APPI);
  w := Widths[RE] - Widths[RS];
  if w >= AContentWidth then Exit;   // overflowing row: scroll owns the origin
  if FAlignment = taCenter then
    Result := (AContentWidth - w) div 2
  else
    Result := AContentWidth - w;
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
  { A code-facing caret write names a (line, column) and says nothing about glyphs, so the
    caret it places has no run to stand against and must fall back to the default. Without
    this the same assignment would land in two different places depending on which side of a
    direction boundary the user last clicked. }
  DefaultCaretAffinity;
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
  Head, Tail, NL: string;
begin
  Result := '';
  if not HasSelection then Exit;
  // Join with the separator Text itself uses (not a bare LineEnding): SelStart /
  // SelLength are offsets into Text, so SelText must be the slice they name --
  // UTF8Copy(Text, SelStart + 1, SelLength) -- byte for byte.
  NL := TextLineBreak;
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
      Result := Result + NL + FLines[i]
    else
      Result := Result + NL;
  end;
  if EL < FLines.Count then
    Head := UTF8Copy(FLines[EL], 1, EC)
  else
    Head := '';
  Result := Result + NL + Head;
end;

procedure TTyMemo.Append(const AValue: string);
begin
  { Straight through Lines, so it picks up the change hook and the visual-row cache
    invalidation rather than reimplementing either. }
  FLines.Add(AValue);
end;

procedure TTyMemo.Clear;
begin
  FLines.Clear;
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
  DefaultCaretAffinity;   // the document end is a logical end; see SetCaret
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
  { Deletes, as LCL does. DeleteSelection already carries the undo step, the caret move
    and the change notification. }
  if HasSelection then
    DeleteSelection
  else
    CollapseSelection;
end;

procedure TTyMemo.CollapseSelection;
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
  { Dirty-flag bookkeeping at the one point every completed mutation passes, reading the
    by-code guard exactly as LCL's Change does (include/customedit.inc:613-616). }
  if not FTextChangeByCode then
    FModified := True;
  if Assigned(FOnChange) then
    FOnChange(Self);
  if FOnChangeHandlers <> nil then
    FOnChangeHandlers.CallNotifyEvents(Self);
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
// Widest logical line, in px. Only each line's TOTAL width is needed, so this uses the O(L) cheap
// total-width path (one TextSize per line) instead of the O(L^2) per-character MeasureLineWidths —
// loading N KB no longer re-measures every character-prefix of every line (the ~10s file-preview
// stall). The scan result is memoised and cleared by InvalidateVisualRows on any text change, so
// scroll/paint/scrollbar passes reuse it. Font-signature guarded so a theme/DPI change recomputes.
var
  i, W: Integer;
  S: TTyStyleSet;
  sig: string;
begin
  S := CurrentStyle;
  sig := S.FontName + '|' + IntToStr(EffectiveFontSize(S)) + '|'
    + IntToStr(S.FontWeight) + '|' + IntToStr(APPI);
  if FWidestWidthValid and (sig = FWidestWidthSig) then
    Exit(FWidestWidth);
  Result := 0;
  for i := 0 to FLines.Count - 1 do
  begin
    W := MeasureLineTotalWidth(FLines[i], APPI);
    if W > Result then Result := W;
  end;
  FWidestWidth := Result;
  FWidestWidthValid := True;
  FWidestWidthSig := sig;
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
  { Caret x on its OWN line (absolute, before the scroll shift). Asked of the DRAWN caret
    rather than of the prefix sum: those are the same number for a line with no right-to-left
    script in it and only the drawn one is right for the rest -- and scrolling to where the
    caret is NOT would leave the user typing off-screen.

    This branch only runs with WordWrap off, where a visual row IS a logical line and starts
    at column 0, so the row's own frame and the line's are the same and CaretDrawXAt's answer
    is directly comparable with ViewRight. }
  if FCaretLine < FLines.Count then
    CaretLineStr := FLines[FCaretLine]
  else
    CaretLineStr := '';
  if LineHasRTL(CaretLineStr) then
    CaretPx := CaretDrawXAt(FCaretLine, FCaretCol, FCaretAfterPrev, APPI)
  else
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
  // Subtract the horizontal scrollbar's strip when it's showing.
  Result := (Height - HScrollBarHeight) div LH;
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

procedure TTyMemo.HScrollBarChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FSyncingScroll := True;
  try
    FScrollX := FHScrollBar.Position;
    Invalidate;
  finally
    FSyncingScroll := False;
  end;
end;

function TTyMemo.HScrollBarHeight: Integer;
begin
  if (FHScrollBar <> nil) and FHScrollBar.Visible then
    Result := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), Font.PixelsPerInch, 96)
  else
    Result := 0;
end;

procedure TTyMemo.UpdateScrollBar;
var
  PPI, LH, VR, MaxPos, MaxTop, Total, SBW, viewW, hMax, fw: Integer;
  WasVisible, WantV, WantH: Boolean;
begin
  PPI := Font.PixelsPerInch;
  LH := LineHeight(PPI); if LH < 1 then LH := 1;
  SBW := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), PPI, 96);   // both bars' thickness
  // Frame inset: the scrollbars sit flush to the edge and would cover the border + focus ring
  // DrawFrame paints at the OUTER edge (the memo's ring looked clipped by the vbar). Pull both
  // bars in by ~the ring width so the frame stays visible around them, like a native memo.
  fw := MulDiv(2, PPI, 96); if fw < 1 then fw := 1;
  Total := TotalVisualRows(PPI);

  // ---- 1) Decide + apply the VERTICAL bar FIRST, from the full height (its overflow is row-count
  //         driven and effectively independent of the hbar). Applying it now makes ContentWidthFor
  //         reflect the real vbar, so the hbar's show-test and its scroll range below use ONE
  //         consistent width (no stale-vbar transient). ----
  VR := Height div LH; if VR < 1 then VR := 1;
  case FScrollBars of
    ssVertical, ssBoth: WantV := True;
    ssAutoVertical, ssAutoBoth: WantV := Total > VR;
  else
    WantV := False;   // ssNone / ssHorizontal / ssAutoHorizontal -> no vertical bar
  end;
  if WantV then
  begin
    // Prior visibility captured BEFORE creating/flipping: a not-yet-created bar counts as hidden
    // (TControl.Visible defaults True), else the first-ever creation skips the WordWrap rebuild below.
    WasVisible := (FScrollBar <> nil) and FScrollBar.Visible;
    if FScrollBar = nil then
    begin
      FScrollBar := TTyScrollBar.Create(Self);
      FScrollBar.Parent := Self;
      FScrollBar.Kind := sbVertical;
      FScrollBar.Align := alRight;
      // A standalone TTyScrollBar is focusable; an embedded one must not be, or dragging
      // the bar would take focus (and the caret) out of the memo it is scrolling.
      FScrollBar.TabStop := False;
      FScrollBar.OnChange := @ScrollBarChange;
      FScrollBar.AnimationsEnabled := False;   // instant: scrolling never lags the wheel/keyboard
      FScrollBar.ControlStyle := FScrollBar.ControlStyle + [csNoDesignVisible];   // internal: never a designable child
    end;
    FScrollBar.Width := SBW;
    // Inset the vertical bar inside the frame (Align=alRight honours BorderSpacing) so the
    // border + focus ring drawn at the outer edge are not covered by it.
    FScrollBar.BorderSpacing.Right  := fw;
    FScrollBar.BorderSpacing.Top    := fw;
    FScrollBar.BorderSpacing.Bottom := fw;
    FScrollBar.Controller := Self.Controller;
    FScrollBar.Visible := True;
    // WordWrap: a newly-visible vbar steals SBW from the content width -> narrower wrap -> MORE rows.
    // Rebuild at the narrowed width and recompute Total so the range covers every settled row. No-op
    // for WordWrap=False (width independent of the bar).
    if (not WasVisible) and FWordWrap then
    begin
      InvalidateVisualRows;
      Total := TotalVisualRows(PPI);
    end;
  end
  else if FScrollBar <> nil then
    FScrollBar.Visible := False;

  // ---- 2) Decide the HORIZONTAL bar from the NOW-CURRENT content width (reflects the vbar just
  //         applied). WordWrap=False only, and only with room for the bar plus a content row. ----
  WantH := False;
  if (not FWordWrap) and (Height >= 2 * SBW) then
    case FScrollBars of
      ssHorizontal, ssBoth: WantH := True;
      ssAutoHorizontal, ssAutoBoth: WantH := WidestLineWidth(PPI) > ContentWidthFor(PPI);
    end;

  // ---- 3) Final visible-row count (the hbar steals a row), clamp FTopRow, set the vbar range. ----
  VR := (Height - (Ord(WantH) * SBW)) div LH; if VR < 1 then VR := 1;
  MaxTop := Total - VR; if MaxTop < 0 then MaxTop := 0;
  if FTopRow > MaxTop then FTopRow := MaxTop;
  if FTopRow < 0 then FTopRow := 0;
  if WantV then
  begin
    MaxPos := Total - VR; if MaxPos < 0 then MaxPos := 0;
    FSyncingScroll := True;
    try
      FScrollBar.Min := 0;
      FScrollBar.Max := MaxPos;
      FScrollBar.PageSize := VR;
      FScrollBar.Position := FTopRow;
    finally
      FSyncingScroll := False;
    end;
  end;

  // ---- 4) Apply the HORIZONTAL bar (manual bottom strip, stopping before the vbar) ----
  if WantH then
  begin
    if FHScrollBar = nil then
    begin
      FHScrollBar := TTyScrollBar.Create(Self);
      FHScrollBar.Parent := Self;
      FHScrollBar.Kind := sbHorizontal;
      FHScrollBar.Align := alNone;   // manual: stops before the vbar so they don't fight for the corner
      FHScrollBar.TabStop := False;  // embedded: never take the caret off the memo (see the vbar)
      FHScrollBar.OnChange := @HScrollBarChange;
      FHScrollBar.AnimationsEnabled := False;
      FHScrollBar.ControlStyle := FHScrollBar.ControlStyle + [csNoDesignVisible];   // internal: hide in the designer
    end;
    FHScrollBar.Height := SBW;
    FHScrollBar.Controller := Self.Controller;
    FHScrollBar.Visible := True;
    // Inset like the vertical bar: left/bottom by fw, and stop before the (also-inset) vbar.
    FHScrollBar.SetBounds(fw, Height - SBW - fw, Width - 2*fw - (Ord(WantV) * SBW), SBW);
    viewW := ContentWidthFor(PPI);
    hMax := WidestLineWidth(PPI) - viewW; if hMax < 0 then hMax := 0;
    if FScrollX > hMax then FScrollX := hMax;
    if FScrollX < 0 then FScrollX := 0;
    FSyncingScroll := True;
    try
      FHScrollBar.Min := 0;
      FHScrollBar.Max := hMax;
      FHScrollBar.PageSize := viewW;
      FHScrollBar.Position := FScrollX;
    finally
      FSyncingScroll := False;
    end;
  end
  else
  begin
    if FHScrollBar <> nil then FHScrollBar.Visible := False;
    // No hbar: re-clamp a stale horizontal offset (line shrank, ScrollBars->ssNone, wrap toggled on),
    // so a previously scrolled-off line isn't left stranded with no bar to bring it back.
    ClampScrollX(PPI);
  end;
end;

function TTyMemo.ScrollBarVisible: Boolean;
begin
  Result := (FScrollBar <> nil) and FScrollBar.Visible;
end;

// ---- ITyTextEditActions (default context-menu seam; thin delegates) ----

function TTyMemo.TeControl: TControl;              begin Result := Self; end;
function TTyMemo.TeController: TTyStyleController;  begin Result := ActiveController; end;
procedure TTyMemo.TeUndo;                           begin Undo; end;
procedure TTyMemo.TeRedo;                           begin Redo; end;
procedure TTyMemo.TeCut;                            begin CutToClipboard; end;
procedure TTyMemo.TeCopy;                           begin CopyToClipboard; end;
procedure TTyMemo.TePaste;                          begin PasteFromClipboard; end;
procedure TTyMemo.TeSelectAll;                      begin SelectAll; end;
function TTyMemo.TeCanUndo: Boolean;                begin Result := CanUndo; end;
function TTyMemo.TeCanRedo: Boolean;                begin Result := CanRedo; end;
function TTyMemo.TeHasSelection: Boolean;           begin Result := HasSelection; end;
// Route through the virtual ReadClipboardText so headless tests can stub the clipboard.
function TTyMemo.TeCanPaste: Boolean;               begin Result := ReadClipboardText <> ''; end;
function TTyMemo.TeHasText: Boolean;
begin
  Result := (FLines.Count > 1) or ((FLines.Count = 1) and (FLines[0] <> ''));
end;
function TTyMemo.TeIsReadOnly: Boolean;             begin Result := FReadOnly; end;

// ---- ITyImeEditable (macOS IME composition seam; see tyControls.CocoaWS) ----

function  TTyMemo.ImeTargetControl: TWinControl;    begin Result := Self; end;
function  TTyMemo.ImeIsReadOnly: Boolean;           begin Result := FReadOnly or (not Enabled); end;
function  TTyMemo.ImeCaretBoundClient: TRect;       begin Result := GetImeCaretRect; end;
function  TTyMemo.ImeCaretIndex: Integer;           begin Result := SelStart; end;
// Bracket the WHOLE composition in one undo step (mirrors HandleImeCommit): BeginUndoStep captures the
// pre-composition text, FSuspendUndo then swallows every per-keystroke push until End fires.
procedure TTyMemo.ImeSessionBegin;                  begin BeginUndoStep(uskTyping); FSuspendUndo := True; end;
procedure TTyMemo.ImeSessionEnd;                    begin FSuspendUndo := False; DoChange; end;
procedure TTyMemo.ImeReplace(AStart, ALen: Integer; const AText: string);
begin
  // Replace [AStart, AStart+ALen) with AText, then relayout (AfterEdit), as HandleImeCommit does.
  if ALen > 0 then
  begin
    SelStart := AStart;
    SelLength := ALen;
    DeleteSelection;
  end
  else
    CaretPos := AStart;
  if AText <> '' then InsertTextMultiline(AText);
  // Collapse the anchor onto the caret. InsertTextMultiline moves the caret but NOT the anchor, so
  // without this the just-inserted run stays SELECTED -- and on commit the next keystroke overwrites
  // it. Edit's InjectStringAt collapses itself; Memo's HandleImeCommit collapses explicitly, same as here.
  FSelAnchorLine := FCaretLine;
  FSelAnchorCol := FCaretCol;
  FDesiredCol := FCaretCol;
  AfterEdit(Font.PixelsPerInch);
end;

{$IFDEF LCLCocoa}
procedure TTyMemo.CocoaImComposition(var Message: TLMessage);
begin
  // WParam 0 = IM_MESSAGE_WPARAM_GET_IME_HANDLER (LCL-Cocoa wants our ICocoaIMEControl); 1 = lookup-word (unused).
  if Message.WParam = 0 then Message.Result := PtrInt(FCocoaIme)
  else Message.Result := 0;
end;
{$ENDIF}

{ Double-click primitive: select the same-class run (a word run, or a punctuation/space run)
  around column ACol on line ALine. Mirrors TTyEdit.SelectWordAt but on one logical line. }
procedure TTyMemo.SelectWordAtLineCol(ALine, ACol: Integer);
var
  lineText: string;
  Len, p, ws, we: Integer;
  refWord: Boolean;
begin
  BreakCoalescing;
  if (ALine < 0) or (ALine >= FLines.Count) then Exit;
  lineText := FLines[ALine];
  Len := UTF8Length(lineText);
  FCaretLine := ALine;
  FSelAnchorLine := ALine;
  if Len = 0 then
  begin
    FCaretCol := 0; FSelAnchorCol := 0;
    FDesiredCol := 0; UpdateDesiredX(Font.PixelsPerInch); Invalidate; Exit;
  end;
  if ACol < 0 then ACol := 0;
  if ACol > Len then ACol := Len;
  // Classify the codepoint the click sits on: the one to the RIGHT of boundary ACol, or (at
  // line end) the one to its left. Then expand over the maximal run of the SAME class.
  if ACol >= Len then p := Len - 1 else p := ACol;
  refWord := IsWordCodepoint(UTF8Copy(lineText, p + 1, 1));
  ws := p;
  while (ws > 0) and (IsWordCodepoint(UTF8Copy(lineText, ws, 1)) = refWord) do Dec(ws);
  we := p + 1;
  while (we < Len) and (IsWordCodepoint(UTF8Copy(lineText, we + 1, 1)) = refWord) do Inc(we);
  FSelAnchorCol := ws;
  FCaretCol := we;
  FDesiredCol := FCaretCol;
  UpdateDesiredX(Font.PixelsPerInch);
  ResetCaretBlink;
  Invalidate;
end;

{ Triple-click primitive: select the whole logical line ALine (col 0 .. end of line;
  the trailing newline is NOT part of the line, matching SelectAll's boundary). }
procedure TTyMemo.SelectLine(ALine: Integer);
begin
  BreakCoalescing;
  if (ALine < 0) or (ALine >= FLines.Count) then Exit;
  FSelAnchorLine := ALine; FSelAnchorCol := 0;
  FCaretLine := ALine;     FCaretCol := UTF8Length(FLines[ALine]);
  FDesiredCol := FCaretCol;
  UpdateDesiredX(Font.PixelsPerInch);
  ResetCaretBlink;
  Invalidate;
end;

{ Right-click: the user's PopupMenu wins if set; otherwise show the default themed menu
  (tyControls.TextMenu) and consume the event. Identical to TTyEdit.DoContextPopup. }
procedure TTyMemo.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
begin
  inherited DoContextPopup(MousePos, Handled);   // fires OnContextPopup (may set Handled)
  if Handled then Exit;
  if PopupMenu <> nil then Exit;                 // LCL's WMContextMenu will show the user's
  if FTextMenu = nil then FTextMenu := TTyTextEditMenu.Create(Self);
  FTextMenu.Popup(MousePos);
  Handled := True;
end;

procedure TTyMemo.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  APPI, LH, Row, CW, NewLine, NewCol, Clicks: Integer;
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
  { Undo the row's alignment shift before resolving the column, or a click on a centred row
    lands on the character that WOULD be there if the row were left-justified. Zero under the
    default alignment, so the plain hit-test is unchanged.

    Then lift the click into the ABSOLUTE (full logical line) frame VisualToCaret answers in,
    by adding back the row's base. RowBaseAbsX is TextStartX for any row that starts at
    column 0 -- which is EVERY row when WordWrap is off -- so this term is zero for the
    unwrapped hit test and leaves it byte-identical. It is not zero for a wrapped
    CONTINUATION row, where a client x was being compared against whole-line prefix widths
    and then clamped: that resolved most of the row to its StartCol. }
  VisualToCaretEx(Row, X - RowAlignOffset(Row, CW, APPI)
      + (RowBaseAbsX(Row, APPI) - TextStartX(APPI)),
    CW, APPI, NewLine, NewCol, FCaretAfterPrev);
  FCaretLine := NewLine;
  FCaretCol := NewCol;
  FDesiredCol := FCaretCol;
  // A click is a horizontal move: refresh the desired x for a following wrap Up/Down.
  UpdateDesiredX(APPI);
  // Click sequence + shift-extend (mirrors TTyEdit.MouseDown). LCL has no native
  // triple-click and marks only the 2nd press with ssDouble, so count the sequence
  // here: 2 = word, 3 = the whole logical line, 1 (and a wrapped 4+) = plain caret.
  BreakCoalescing;   // a mouse-driven caret move ends a typing-coalesce run
  if ssShift in Shift then
  begin
    // Shift+click EXTENDS: the caret already moved to the click; keep the anchor
    // (do NOT collapse) so the selection grows from where it started.
    FMouseSelecting := True;
  end
  else
  begin
    Clicks := TyMultiClickCount(ssDouble in Shift, X, Y, FLastClickX, FLastClickY, FLastClickTick, FClickCount);
    if Clicks = 2 then
    begin
      SelectWordAtLineCol(FCaretLine, FCaretCol);   // double-click: word under the pointer
      FMouseSelecting := False;
    end
    else if Clicks = 3 then
    begin
      SelectLine(FCaretLine);                        // triple-click: the current logical line
      FMouseSelecting := False;
    end
    else
    begin
      if Clicks > 3 then FClickCount := 1;           // wrap the sequence back to a plain click
      // A fresh left-click sets the anchor onto the caret (collapsing any prior
      // selection) and begins a drag. Existing click tests assert only the caret, unaffected.
      FSelAnchorLine := FCaretLine;
      FSelAnchorCol := FCaretCol;
      FMouseSelecting := True;
    end;
  end;
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
  // Same frame lift as MouseDown -- a drag has to hit-test identically to the press that
  // began it, or the selection would not follow the pointer on a wrapped or reordered row.
  VisualToCaretEx(Row, X - RowAlignOffset(Row, CW, APPI)
      + (RowBaseAbsX(Row, APPI) - TextStartX(APPI)),
    CW, APPI, NewLine, NewCol, FCaretAfterPrev);
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

procedure TTyMemo.ScrollBy(DeltaX, DeltaY: Integer);
// Text-view scroll (see the declaration for why this must NOT be TWinControl's
// child-mover, and why overriding is safe on this class but not on TTyScrollBox).
var
  PPI, LH, NewX: Integer;
begin
  PPI := Font.PixelsPerInch;
  // Vertical: the view addresses whole visual rows, so convert the pixel delta with
  // `div` (truncates toward zero) -- a sub-row delta must scroll nothing rather than
  // jump a whole row. SetTopLine clamps to [0, MaxTopLine] and syncs the bar.
  if DeltaY <> 0 then
  begin
    LH := LineHeight(PPI);
    if LH < 1 then LH := 1;
    SetTopLine(FTopRow - (DeltaY div LH));
  end;
  // Horizontal: real device px. WordWrap=True never scrolls horizontally (FScrollX is
  // pinned to 0 there), so leave it alone rather than fight ClampScrollX.
  if (DeltaX <> 0) and (not FWordWrap) then
  begin
    NewX := FScrollX - DeltaX;
    if NewX < 0 then NewX := 0;
    if NewX <> FScrollX then
    begin
      FScrollX := NewX;
      ClampScrollX(PPI);   // caps against widest-line width minus the viewport
      // Move the thumb with the text. Guarded: the bar's OnChange writes straight
      // back into FScrollX, which would undo the clamp we just applied.
      if (FHScrollBar <> nil) and FHScrollBar.Visible then
      begin
        FSyncingScroll := True;
        try
          FHScrollBar.Position := FScrollX;
        finally
          FSyncingScroll := False;
        end;
      end;
      Invalidate;
    end;
  end;
end;

procedure TTyMemo.AfterEdit(APPI: Integer);
begin
  ClampCaret;
  { A completed edit parks the affinity, because that is what an insertion point means:
    "the text I just wrote ends here". Placed HERE rather than in InvalidateVisualRows --
    which is the seam every text mutation passes -- because that one is also reached from a
    resize, from a scrollbar appearing and from the WordWrap setter, none of which are the
    user typing; and because the Left/Right arrows must be able to READ the affinity they
    are about to replace, and they do not come through here. }
  DefaultCaretAffinity;
  // NOTE: AfterEdit is anchor-NEUTRAL on purpose. RestoreState (undo/redo) restores a selection and
  // then calls AfterEdit, so collapsing the anchor here would defeat undo re-selection. Edit paths
  // that should drop the selection collapse the anchor themselves before calling AfterEdit (typing,
  // IME, Tab, paste, Enter-split).
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
  Cur, Before, After, Ins: string;
  L: Integer;
begin
  if AStr = '' then Exit;
  { CharCase folds at the single splice point, so typing, IME commits and paste all land
    already-cased and nothing can enter the model in the wrong case. Identity under the
    default ecNormal. }
  Ins := ApplyCharCase(AStr);
  // Ensure the model has a backing line for the caret.
  if FLines.Count = 0 then
    FLines.Add('');
  Cur := FLines[FCaretLine];
  L := UTF8Length(Cur);
  if FCaretCol > L then FCaretCol := L;
  Before := UTF8Copy(Cur, 1, FCaretCol);
  After  := UTF8Copy(Cur, FCaretCol + 1, L - FCaretCol);
  FLines[FCaretLine] := Before + Ins + After;
  FCaretCol := FCaretCol + UTF8Length(Ins);
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
    SBWidth := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), APPI, 96);
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
  // Every text mutation funnels through here -- edits, undo/redo (AfterEdit), the Lines setter,
  // and now a mutation made THROUGH the published Lines as well (FLines.OnChange -> LinesChanged).
  // That last route did not exist when this comment was written, and the comment is exactly what
  // made the hole invisible: it asserted the invariant the code did not have.
  // This is the one seam that must drop the memoised widest-line width;
  // otherwise a stale widest would drive the horizontal scroll range after the text changed.
  FWidestWidthValid := False;
end;

function TTyMemo.RowsFor(AContentWidth, APPI: Integer): TTyVisualRowArray;
begin
  if FVisualRowsValid and (FVisualRowsWidth = AContentWidth) then
    Exit(FVisualRows);
  Result := BuildVisualRows(AContentWidth, APPI);
end;

procedure TTyMemo.CaretToVisual(ALine, ACol, AContentWidth, APPI: Integer;
  out AVisualRow, AX: Integer);
begin
  { The DEFAULT affinity, which is what a caller that does not know about glyphs means: the
    caret stands against the character before it. For a row with no right-to-left script in
    it the two answers are identical, so every existing caller is unchanged. }
  CaretToVisualEx(ALine, ACol, True, AContentWidth, APPI, AVisualRow, AX);
end;

procedure TTyMemo.CaretToVisualEx(ALine, ACol: Integer; AAfterPrev: Boolean;
  AContentWidth, APPI: Integer; out AVisualRow, AX: Integer);
var
  Rows: TTyVisualRowArray;
  i: Integer;
  Line: string;
  Cached: Boolean;
begin
  AVisualRow := 0;
  AX := TextStartX(APPI);
  Cached := FVisualRowsValid and (FVisualRowsWidth = AContentWidth);
  Rows := RowsFor(AContentWidth, APPI);
  if Length(Rows) = 0 then Exit;
  // Find the owning row. Tie-break: a caret at a soft-wrap boundary column binds
  // to the EARLIER row (the one whose EndCol == ACol) rather than the next row
  // whose StartCol == ACol. We accept a row when ACol is within [StartCol,EndCol];
  // because we scan in order and accept the FIRST such row, the earlier row wins
  // the tie at a shared boundary column.
  AVisualRow := High(Rows);   // default: last row (handles col == final EndCol)
  if Cached then
    AVisualRow := CaretOwningRow(ALine, ACol)
  else
    for i := 0 to High(Rows) do
      if (Rows[i].Line = ALine) and (ACol >= Rows[i].StartCol)
         and (ACol <= Rows[i].EndCol) then
      begin
        AVisualRow := i;
        Break;
      end;
  { The ABSOLUTE (full logical line) frame both halves of this pair work in: the row's own
    base plus the caret's x WITHIN the row. For a row that needs no reordering that sum is
    Widths[StartCol] + (Widths[ACol] - Widths[StartCol]) = the plain per-line caret x, so the
    left-to-right answer is exactly the ColPixelXAt this used to return. For a reordered row
    the base is still the prefix sum -- it is only ever subtracted off again by the caller --
    while the part INSIDE the row comes from the run table, which is the half that has to
    match what was drawn.

    The run tables hang off the CACHED row list, so a caller asking about some other content
    width (the headless row tests ask about narrow widths to force a wrap) gets the prefix
    sum rather than an answer read out of a row list that is not the one in the cache. }
  if Cached then
    AX := RowBaseAbsX(AVisualRow, APPI)
      + RowCaretRelX(AVisualRow, ACol - Rows[AVisualRow].StartCol, AAfterPrev, APPI)
  else
  begin
    if ALine < FLines.Count then
      Line := FLines[ALine]
    else
      Line := '';
    AX := ColPixelXAt(Line, ACol, APPI);
  end;
end;

procedure TTyMemo.VisualToCaret(AVisualRow, AX, AContentWidth, APPI: Integer;
  out ALine, ACol: Integer);
var
  Ignored: Boolean;
begin
  VisualToCaretEx(AVisualRow, AX, AContentWidth, APPI, ALine, ACol, Ignored);
end;

procedure TTyMemo.VisualToCaretEx(AVisualRow, AX, AContentWidth, APPI: Integer;
  out ALine, ACol: Integer; out AAfterPrev: Boolean);
var
  Rows: TTyVisualRowArray;
  RB: TTyMemoRowBidi;
  Line: string;
  Col, RelX, i, r, best, bestErr, err, ex: Integer;
  Cached: Boolean;
begin
  ALine := 0;
  ACol := 0;
  AAfterPrev := True;
  Cached := FVisualRowsValid and (FVisualRowsWidth = AContentWidth);
  Rows := RowsFor(AContentWidth, APPI);
  if Length(Rows) = 0 then Exit;
  if AVisualRow < 0 then AVisualRow := 0;
  if AVisualRow > High(Rows) then AVisualRow := High(Rows);
  ALine := Rows[AVisualRow].Line;
  if ALine < FLines.Count then
    Line := FLines[ALine]
  else
    Line := '';

  if Cached and RowBidi(AVisualRow, APPI, RB) then
  begin
    { Row-relative x, in the same frame RowCaretRelX answers in. AX arrives ABSOLUTE (see
      CaretToVisualEx), and ColIndexAtX's own frame adds FScrollX, so both terms are here. }
    RelX := AX + FScrollX - RowBaseAbsX(AVisualRow, APPI);
    { Which RUN the x landed in decides half the answer: at a direction boundary the column
      alone is two different places on screen, so a hit test that returned only the column
      would leave the caret to guess -- and a click on the far side of an embedded run would
      draw the caret on the near side. }
    r := RB.Order[0];
    for i := 0 to High(RB.Order) do
    begin
      r := RB.Order[i];
      if RelX < RB.Runs[r].Right then Break;
    end;
    { Nearest boundary WITHIN that run. Scanned rather than bisected: a run's boundaries
      DESCEND in x for right-to-left text, and a handful of comparisons is nothing next to
      the layout this is reading. }
    best := RB.Runs[r].First;
    bestErr := MaxInt;
    for i := RB.Runs[r].First to RB.Runs[r].Last do
    begin
      ex := RowBidiEdgeX(RB, r, i);
      err := Abs(ex - RelX);
      if err < bestErr then
      begin
        bestErr := err;
        best := i;
      end;
    end;
    { The caret belongs to the run the user aimed at: against the character after it at the
      run's logical start, against the one before it everywhere else. }
    AAfterPrev := best > RB.Runs[r].First;
    ACol := Rows[AVisualRow].StartCol + best;
    Exit;
  end;

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
  // (CharCase first: the multi-line path builds its lines itself rather than going through
  //  DoInsertText, so a pasted block has to be folded here too. Identity under ecNormal.)
  Norm := StringReplace(ApplyCharCase(AStr), #13#10, #10, [rfReplaceAll]);
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
    // Caret sits AFTER the pasted text with no selection (collapse the anchor).
    FSelAnchorLine := FCaretLine;
    FSelAnchorCol := FCaretCol;
    FDesiredCol := FCaretCol;
    AfterEdit(Font.PixelsPerInch);
  finally
    FSuspendUndo := False;
  end;
end;

function TTyMemo.EffectiveFontSize(const S: TTyStyleSet): Integer;
begin
  // Verbatim from TTyEdit.EffectiveFontSize: route through the shared resolver so a skin that
  // suppresses the font-size gets the theme's --font-size-base, not a hardcoded 12pt.
  Result := ResolveFontSize(S);
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
// the shared lazy bitmap. Lifted from TTyEdit.MeasureCodepointWidths. CACHED by line
// content + font signature: a keystroke then re-measures only the edited line, not every
// visible line on every repaint. The returned array is treated read-only by callers.
var
  S: TTyStyleSet;
  EffSize: Integer;
  i, Len, lastLen, lastBLen, aBLen: Integer;
  sig: string;
begin
  Inc(FMeasureLineWidthsCalls);   // diagnostic: entries into the O(L^2) per-char path (perf test)
  S := CurrentStyle;
  EffSize := EffectiveFontSize(S);
  // Drop the caches if the font (name/size/weight/PPI) changed — all widths would be stale.
  sig := S.FontName + '|' + IntToStr(EffSize) + '|' + IntToStr(S.FontWeight) + '|' + IntToStr(APPI);
  if sig <> FWidthCacheSig then
  begin
    FLineWidthCache.Clear;
    FLineTotalWidthCache.Clear;
    FLastMeasuredLine := '';
    FLastMeasuredWidths := nil;
    FWidthCacheSig := sig;
  end;
  if FLineWidthCache.TryGetValue(ALine, Result) then
    Exit;   // cache hit — unchanged line, no re-measure

  Result := nil;
  Len := UTF8Length(ALine);
  SetLength(Result, Len + 1);
  Result[0] := 0;
  if Len > 0 then
  begin
    if FMeasureBmp = nil then
      FMeasureBmp := TBGRABitmap.Create(1, 1);
    TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
    lastLen := UTF8Length(FLastMeasuredLine);
    lastBLen := Length(FLastMeasuredLine);   // BYTE lengths for safe prefix compares (no overread)
    aBLen := Length(ALine);
    // PREFIX measurement (TextSize of growing prefixes) captures inter-glyph kerning as drawn.
    // Incremental: if the edited line just EXTENDED the last one (append at end), reuse its prefix
    // widths and measure only the new tail; if it TRUNCATED it (delete at end), just copy the prefix.
    if (lastLen > 0) and (Length(FLastMeasuredWidths) = lastLen + 1)
       and (aBLen > lastBLen)
       and (CompareByte(PChar(ALine)^, PChar(FLastMeasuredLine)^, lastBLen) = 0) then
    begin
      for i := 0 to lastLen do Result[i] := FLastMeasuredWidths[i];
      for i := lastLen + 1 to Len do
        Result[i] := FMeasureBmp.TextSize(UTF8Copy(ALine, 1, i)).cx;
    end
    else if (lastLen > 0) and (Length(FLastMeasuredWidths) = lastLen + 1)
       and (aBLen < lastBLen) and (aBLen > 0)
       and (CompareByte(PChar(FLastMeasuredLine)^, PChar(ALine)^, aBLen) = 0) then
    begin
      for i := 0 to Len do Result[i] := FLastMeasuredWidths[i];
    end
    else
    begin
      for i := 1 to Len do
        Result[i] := FMeasureBmp.TextSize(UTF8Copy(ALine, 1, i)).cx;
    end;
  end;
  // Remember this as the incremental hint (the line just edited), and cache by content for the
  // unchanged-line fast path (RenderTo / WidestLineWidth). Bound edit-history growth.
  FLastMeasuredLine := ALine;
  FLastMeasuredWidths := Result;
  if FLineWidthCache.Count > 1024 then
    FLineWidthCache.Clear;
  FLineWidthCache.AddOrSetValue(ALine, Result);
end;

function TTyMemo.MeasureLineTotalWidth(const ALine: string; APPI: Integer): Integer;
// Cheap O(L) total width: a SINGLE TextSize(whole line), cached by content. Equivalent to
// MeasureLineWidths(ALine)[High] (the last prefix IS the whole line, same font config) but without
// the O(L^2) per-character prefix loop. Same font-signature drop discipline as FLineWidthCache so a
// theme/DPI change recomputes. Does NOT touch the per-char cache/incremental hint — those stay
// exclusively for visible-line render / caret / selection geometry, whose pixel positions are
// unchanged by this cheap path.
var
  S: TTyStyleSet;
  EffSize: Integer;
  sig: string;
  cachedW: TTyIntArray;
begin
  Result := 0;
  if ALine = '' then Exit;   // empty line has zero width (matches MeasureLineWidths[0] = 0)
  S := CurrentStyle;
  EffSize := EffectiveFontSize(S);
  sig := S.FontName + '|' + IntToStr(EffSize) + '|' + IntToStr(S.FontWeight) + '|' + IntToStr(APPI);
  if sig <> FWidthCacheSig then
  begin
    // Font changed: both caches are stale. Mirror MeasureLineWidths' reset so they stay coherent.
    FLineWidthCache.Clear;
    FLineTotalWidthCache.Clear;
    FLastMeasuredLine := '';
    FLastMeasuredWidths := nil;
    FWidthCacheSig := sig;
  end;
  if FLineTotalWidthCache.TryGetValue(ALine, Result) then
    Exit;   // cache hit — no measurement
  // Reuse an already-cached per-char array if present (its last element is the total) — avoids a
  // redundant TextSize for lines the render/caret path already measured. Read into a LOCAL: never
  // clobber the (FLastMeasuredLine, FLastMeasuredWidths) incremental-edit hint pair, or the next
  // MeasureLineWidths prefix fast-path could reuse a mismatched array.
  if FLineWidthCache.TryGetValue(ALine, cachedW) and (Length(cachedW) > 0) then
    Result := cachedW[High(cachedW)]
  else
  begin
    if FMeasureBmp = nil then
      FMeasureBmp := TBGRABitmap.Create(1, 1);
    TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
    Result := FMeasureBmp.TextSize(ALine).cx;
  end;
  if FLineTotalWidthCache.Count > 4096 then
    FLineTotalWidthCache.Clear;
  FLineTotalWidthCache.AddOrSetValue(ALine, Result);
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

// ---- Bidirectional row layout -------------------------------------------------------
//
// WHY THIS EXISTS. MeasureLineWidths answers "where is column N" with a cumulative sum
// taken in STRING order. That is exactly right for Latin and CJK and simply untrue once the
// glyphs have been reordered: c2cfafc taught TTyPainter to draw a mixed Arabic/Latin line in
// visual order and 7fd44ec fixed TTyEdit, but this control was still walking its prefix sum
// -- so an Arabic paragraph in a memo DREW right and SELECTED wrong. Clicking a glyph put
// the caret on a different one, arrow keys jumped across runs, and a drag highlighted glyphs
// the user had not dragged over.
//
// WHY PER ROW rather than per line, which is the whole of what made this harder than the
// single-line case: RenderTo draws each visual row as its OWN string, at the content left
// edge, so the bidirectional algorithm runs once per row inside TTyPainter and a caret has
// to agree with THAT reordering. A table built for the logical line would put a wrapped
// continuation row's caret at the line's coordinates -- somewhere off to the right of the
// viewport. Under WordWrap=False a row is the whole line and the distinction costs nothing.
//
// WHY NOT TTyPainter.TextCaretX / TextCharIndexAtX, which exist for exactly this. The same
// two structural reasons TTyEdit records, and they apply here with more force:
//
//   * they lay out on the painter's FBmp, which only exists between BeginPaint and EndPaint.
//     A caret is asked for from mouse handlers, key handlers, the scroller and the blink
//     timer, and none of those are painting. Standing a whole painter up per query would be
//     a TBidiTextLayout per keystroke -- the shape of the bug that once cost TTyMemo half a
//     second of latency per key.
//   * TextCaretX answers with TBidiTextLayout.GetCaret, which resolves a direction boundary
//     towards the run that ENDS there and discards the other position. In "ab<alef><bet>cd"
//     that makes columns 2 and 4 the same pixel with no way to tell them apart, and the far
//     end of the embedded run unreachable by any column at all.
//
// So the row is laid out here instead, once per (segment, font, PPI), and every query is an
// array lookup afterwards. The duplication is deliberate and pinned:
// test.memo.bidi.MemoCaretAgreesWithThePainterForUnambiguousIndices renders the same string
// through TTyPainter.TextCaretX and requires the same pixel for every column the painter can
// express, so the two cannot drift apart in silence.

function TTyMemo.LineHasRTL(const ALine: string): Boolean;
begin
  { The memo is one slot deep on purpose. The caret asks about the SAME line on every blink,
    every keystroke and every mouse move of a drag-select, so one slot catches nearly all of
    it; and a miss costs a scan of ONE LINE, never of the document, which is the property
    that makes a thousand left-to-right lines cost what one line costs
    (test.memo.bidi.AThousandLeftToRightLinesCostTheSameGateAsOne pins it as a COUNT, since
    a wall clock could not tell the two apart reliably enough to fail).

    TyTextHasRTL rejects ASCII in one compare and CJK, Cyrillic and Greek on the lead byte
    without decoding, so the miss is cheap too. }
  if FBidiGateSeeded and (ALine = FBidiGateLine) then
    Exit(FBidiGateAnswer);
  Inc(FBidiGateCalls);
  FBidiGateLine := ALine;
  FBidiGateAnswer := TyTextHasRTL(ALine);
  FBidiGateSeeded := True;
  Result := FBidiGateAnswer;
end;

function TTyMemo.RowSegmentOf(AVisualRow: Integer): string;
var
  Line: string;
begin
  Result := '';
  if (AVisualRow < 0) or (AVisualRow > High(FVisualRows)) then Exit;
  if FVisualRows[AVisualRow].Line < FLines.Count then
    Line := FLines[FVisualRows[AVisualRow].Line]
  else
    Line := '';
  Result := UTF8Copy(Line, FVisualRows[AVisualRow].StartCol + 1,
    FVisualRows[AVisualRow].EndCol - FVisualRows[AVisualRow].StartCol);
end;

function TTyMemo.EnsureRowBidi(const ASeg: string; APPI: Integer;
  out ARB: TTyMemoRowBidi): Boolean;
var
  S: TTyStyleSet;
  EffSize, i, r, n, a, b, x: Integer;
  sig: string;
  lay: TBidiTextLayout;
begin
  Inc(FBidiRowLookups);   // diagnostic: the work the LINE gate exists to avoid (perf guard)
  ARB := Default(TTyMemoRowBidi);
  if ASeg = '' then Exit(False);

  S := CurrentStyle;
  EffSize := EffectiveFontSize(S);
  sig := S.FontName + '|' + IntToStr(EffSize) + '|' + IntToStr(S.FontWeight) + '|'
    + IntToStr(APPI);
  if sig <> FRowBidiSig then
  begin
    // Font changed: every x in every table is stale. Same drop discipline as the width caches.
    FRowBidiCache.Clear;
    FRowBidiSig := sig;
  end;
  if FRowBidiCache.TryGetValue(ASeg, ARB) then
    Exit(ARB.Active);

  { THE SECOND GATE, and the one that has to agree with the PAINT. TTyPainter.DrawText asks
    TyTextHasRTL of the very string it is about to draw and takes the bidirectional path only
    when it says yes; a row whose segment carries no right-to-left codepoint is drawn by the
    plain TextRect path. Reading such a row's caret out of a TBidiTextLayout instead would be
    a SECOND rasterisation of the same row, and the two can round differently -- so the
    control's gate has to be the painter's gate, asked of the same string. }
  if TyTextHasRTL(ASeg) then
  begin
    n := UTF8Length(ASeg);
    if FMeasureBmp = nil then
      FMeasureBmp := TBGRABitmap.Create(1, 1);
    // The layout borrows this bitmap's FontRenderer, so its metrics are the ones DrawText
    // will use -- the same four lines, and the same reason, as MeasureLineWidths.
    TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);
    Inc(FBidiLayoutBuilds);   // diagnostic: the work the SEGMENT gate exists to avoid
    lay := TBidiTextLayout.Create(FMeasureBmp.FontRenderer, ASeg);
    try
      { TopLeft at the origin makes every x below relative to the ROW's text start, which is
        the frame the renderer draws the row in. AvailableWidth is left unset for the same
        reason TTyPainter.BuildLineLayout leaves it unset: the wrap has already happened,
        CJK-aware, in BuildVisualRows, and an unset width also stops the layout right-
        aligning a right-to-left paragraph on its own -- which would be the MIRRORING half of
        the job, and that half is not built. }
      lay.TopLeft := PointF(0, 0);
      SetLength(ARB.Lead, n + 1);
      SetLength(ARB.Trail, n + 1);
      { Seed both arrays from the plain caret query so that an index no run claims (BGRA owes
        us a partition of 0..n, but a zero here would be a caret at the row's left edge
        rather than a visible wrong answer) still gets a defensible number. The run walk
        below then overwrites every index it owns. }
      for i := 0 to n do
      begin
        x := Round(lay.GetCaret(i).Top.x);
        ARB.Lead[i] := x;
        ARB.Trail[i] := x;
      end;
      SetLength(ARB.Runs, lay.PartCount);
      for r := 0 to lay.PartCount - 1 do
      begin
        a := lay.PartStartIndex[r];
        b := lay.PartEndIndex[r];
        ARB.Runs[r].First := a;
        ARB.Runs[r].Last := b;
        ARB.Runs[r].RTL := lay.PartRightToLeft[r];
        ARB.Runs[r].Left := Round(lay.PartRectF[r].Left);
        ARB.Runs[r].Right := Round(lay.PartRectF[r].Right);
        for i := a to b do
        begin
          { The run's OWN end carets at its edges. Asking GetCaret there is what collapses
            the two sides of a boundary onto one; asking the run resolves it, because a run
            has exactly one start and one end and they are never the same point. Strictly
            inside a run there is no ambiguity and GetCaret is exact. }
          if i = a then x := Round(lay.PartStartCaret[r].Top.x)
          else if i = b then x := Round(lay.PartEndCaret[r].Top.x)
          else x := Round(lay.GetCaret(i).Top.x);
          if i < b then ARB.Lead[i] := x;    // boundary i faces character i, which is in this run
          if i > a then ARB.Trail[i] := x;   // ...and character i-1, likewise
        end;
      end;
    finally
      lay.Free;
    end;

    { Run indices in left-to-right SCREEN order, for the arrow keys: "the next glyph to the
      right" is in the next run along, which is not the next run in logical order. Insertion
      sort because a row has a handful of runs, not thousands. }
    SetLength(ARB.Order, Length(ARB.Runs));
    for r := 0 to High(ARB.Runs) do
    begin
      i := r;
      while (i > 0) and (ARB.Runs[ARB.Order[i - 1]].Left > ARB.Runs[r].Left) do
      begin
        ARB.Order[i] := ARB.Order[i - 1];
        Dec(i);
      end;
      ARB.Order[i] := r;
    end;
    ARB.Active := Length(ARB.Runs) > 0;
  end;

  // Cached either way: "this segment needs no reordering" is the answer a repaint of a
  // mixed document asks for most often. Capped like the width caches to bound growth.
  if FRowBidiCache.Count > 512 then
    FRowBidiCache.Clear;
  FRowBidiCache.AddOrSetValue(ASeg, ARB);
  Result := ARB.Active;
end;

function TTyMemo.RowBidi(AVisualRow, APPI: Integer; out ARB: TTyMemoRowBidi): Boolean;
var
  Line: string;
begin
  ARB := Default(TTyMemoRowBidi);
  Result := False;
  if (AVisualRow < 0) or (AVisualRow > High(FVisualRows)) then Exit;
  if FVisualRows[AVisualRow].Line < FLines.Count then
    Line := FLines[FVisualRows[AVisualRow].Line]
  else
    Line := '';
  { Gate on the LINE before touching the row: a left-to-right document pays one memoised
    string compare here and never builds a segment substring or hashes a dictionary key. }
  if not LineHasRTL(Line) then Exit;
  Result := EnsureRowBidi(RowSegmentOf(AVisualRow), APPI, ARB);
end;

function TTyMemo.RowBidiEdgeX(const ARB: TTyMemoRowBidi; ARun, AIndex: Integer): Integer;
begin
  { At the run's logical END only Trail was written from this run; everywhere else Lead was.
    (Both arrays hold the same number except at a direction boundary.) }
  if AIndex >= ARB.Runs[ARun].Last then
    Result := ARB.Trail[ARB.Runs[ARun].Last]
  else
    Result := ARB.Lead[AIndex];
end;

function TTyMemo.RowBidiCaretRun(const ARB: TTyMemoRowBidi; AIndex: Integer;
  AAfterPrev: Boolean): Integer;
var
  r: Integer;
begin
  { The affinity names which neighbouring character the caret is standing against, and that
    character's run is the one it belongs to. At the two ends of the row only one of the two
    rules can be satisfied, so the other is the fallback. }
  for r := 0 to High(ARB.Runs) do
    if AAfterPrev then
    begin
      if (AIndex > ARB.Runs[r].First) and (AIndex <= ARB.Runs[r].Last) then Exit(r);
    end
    else
      if (AIndex >= ARB.Runs[r].First) and (AIndex < ARB.Runs[r].Last) then Exit(r);
  for r := 0 to High(ARB.Runs) do
    if (AIndex >= ARB.Runs[r].First) and (AIndex <= ARB.Runs[r].Last) then Exit(r);
  Result := -1;
end;

function TTyMemo.RowBidiNeighbourRun(const ARB: TTyMemoRowBidi;
  ARun, ADir: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(ARB.Order) do
    if ARB.Order[i] = ARun then
    begin
      if ADir > 0 then
      begin
        if i < High(ARB.Order) then Result := ARB.Order[i + 1];
      end
      else
        if i > 0 then Result := ARB.Order[i - 1];
      Exit;
    end;
end;

function TTyMemo.RowCaretRelX(AVisualRow, ARowCol: Integer; AAfterPrev: Boolean;
  APPI: Integer): Integer;
var
  RB: TTyMemoRowBidi;
  Line: string;
  RS, n: Integer;
  Widths: TTyIntArray;
begin
  Result := 0;
  if (AVisualRow < 0) or (AVisualRow > High(FVisualRows)) then Exit;
  RS := FVisualRows[AVisualRow].StartCol;
  if RowBidi(AVisualRow, APPI, RB) then
  begin
    n := Length(RB.Lead) - 1;
    if ARowCol < 0 then ARowCol := 0;
    if ARowCol > n then ARowCol := n;
    if AAfterPrev then
      Result := RB.Trail[ARowCol]
    else
      Result := RB.Lead[ARowCol];
    Exit;
  end;
  { The prefix sum, untouched: the row's own columns measured from its first codepoint. For
    a full-width row (StartCol = 0) Widths[RS] is 0 and this is the per-line caret x this
    control has always produced. }
  if FVisualRows[AVisualRow].Line < FLines.Count then
    Line := FLines[FVisualRows[AVisualRow].Line]
  else
    Line := '';
  if Line = '' then Exit;
  Widths := MeasureLineWidths(Line, APPI);
  if RS + ARowCol < 0 then ARowCol := -RS;
  if RS + ARowCol > High(Widths) then ARowCol := High(Widths) - RS;
  Result := Widths[RS + ARowCol] - Widths[RS];
end;

procedure TTyMemo.RowVisualEdge(AVisualRow, ASide, APPI: Integer;
  out ACol: Integer; out AAfterPrev: Boolean);
var
  RB: TTyMemoRowBidi;
  RS, r, j: Integer;
begin
  ACol := 0;
  AAfterPrev := True;
  if (AVisualRow < 0) or (AVisualRow > High(FVisualRows)) then Exit;
  RS := FVisualRows[AVisualRow].StartCol;
  if not RowBidi(AVisualRow, APPI, RB) then
  begin
    // No reordering: the leftmost caret is the row's first column, the rightmost its last.
    if ASide < 0 then
    begin
      ACol := RS;
      AAfterPrev := False;
    end
    else
    begin
      ACol := FVisualRows[AVisualRow].EndCol;
      AAfterPrev := True;
    end;
    Exit;
  end;
  if Length(RB.Order) = 0 then Exit;
  if ASide < 0 then r := RB.Order[0] else r := RB.Order[High(RB.Order)];
  { Inside a right-to-left run the run's LAST codepoint boundary is its LEFT edge, so which
    end of the run is "the outer one" depends on the run's direction, not on the side. }
  if ASide < 0 then
  begin
    if RB.Runs[r].RTL then j := RB.Runs[r].Last else j := RB.Runs[r].First;
  end
  else
    if RB.Runs[r].RTL then j := RB.Runs[r].First else j := RB.Runs[r].Last;
  ACol := RS + j;
  AAfterPrev := j > RB.Runs[r].First;
end;

procedure TTyMemo.DefaultCaretAffinity;
begin
  FCaretAfterPrev := True;
end;

function TTyMemo.CaretOwningRow(ALine, ACol: Integer): Integer;
var
  i: Integer;
begin
  { Tie-break: a caret at a soft-wrap boundary column binds to the EARLIER row (the one
    whose EndCol == ACol) rather than the next row whose StartCol == ACol. We accept a row
    when ACol is within [StartCol, EndCol]; because we scan in order and accept the FIRST
    such row, the earlier row wins the tie at a shared boundary column.
    Requires FVisualRows to be current -- every caller ensures it first. }
  Result := High(FVisualRows);   // default: last row (handles col == final EndCol)
  for i := 0 to High(FVisualRows) do
    if (FVisualRows[i].Line = ALine) and (ACol >= FVisualRows[i].StartCol)
       and (ACol <= FVisualRows[i].EndCol) then
      Exit(i);
end;

function TTyMemo.CaretDrawXAt(ALine, ACol: Integer; AAfterPrev: Boolean;
  APPI: Integer): Integer;
var
  VRow: Integer;
begin
  { Deliberately NOT routed through CaretToVisualEx, and this is a measured decision rather
    than a stylistic one -- do not "simplify" it back.

    CaretToVisualEx answers in the ABSOLUTE (full logical line) frame: the row's base PLUS
    the caret's x within the row. This function then subtracts the base straight back off.
    Computing both and cancelling them meant four ContentWidthFor calls per caret query
    instead of one, and ContentWidthFor is not cheap -- it resolves a style and asks the
    controller for --scrollbar-size, measured at ~115us against a ~25us width lookup. The
    first cut of this function did exactly that and cost 546us per query on a thousand-line
    memo; finding the row once and taking the row-relative x directly brought it to 139us,
    with no change to a single pixel. On a control whose caret is queried on every keystroke,
    every mouse move of a drag-select and every blink -- and which once had half a second of
    latency per key from uncached measurement -- that is not an acceptable way to arrive at a
    number the arithmetic throws away.

    (The cost is flat in document size either way: 139.3 / 138.9 / 140.7 us at lines 0, 500
    and 999 of a thousand. What was wrong was the constant, not the complexity.)

    For a full-width row (StartCol = 0) RowCaretRelX is Widths[ACol], so this is the
    per-line caret x this control has always drawn. }
  EnsureVisualRows(APPI);
  if Length(FVisualRows) = 0 then
    Exit(TextStartX(APPI));
  VRow := CaretOwningRow(ALine, ACol);
  Result := TextStartX(APPI)
    + RowCaretRelX(VRow, ACol - FVisualRows[VRow].StartCol, AAfterPrev, APPI);
end;

function TTyMemo.CaretDrawX(APPI: Integer): Integer;
begin
  Result := CaretDrawXAt(FCaretLine, FCaretCol, FCaretAfterPrev, APPI);
end;

function TTyMemo.UsesBidiCaret(APPI: Integer): Boolean;
var
  CW, VRow, X: Integer;
  RB: TTyMemoRowBidi;
begin
  CW := ContentWidthFor(APPI);
  EnsureVisualRows(APPI);
  CaretToVisualEx(FCaretLine, FCaretCol, FCaretAfterPrev, CW, APPI, VRow, X);
  Result := RowBidi(VRow, APPI, RB);
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
  AOff, AlignW: Integer;   // Alignment: per-row draw-origin shift, and the width it fits into
  // Selection-band state (resolved once before the visible-row loop).
  SL, SC, EL, EC, X1, X2: Integer;
  // Per-run band state for a reordered row (one band per run; see the band block).
  RowRB: TTyMemoRowBidi;
  RunIdx, SelA, SelB, BandSwap, bandEffEnd: Integer;
  Widths: TTyIntArray;
  BandFill: TTyFill;
  BandColor: TTyColor;
  DrawBand, ShowSel: Boolean;
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
      SBWidth := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), APPI, 96);
    // Keep text/caret above the horizontal scrollbar strip when it's showing.
    if (FHScrollBar <> nil) and FHScrollBar.Visible then
      ContentRect.Bottom := ContentRect.Bottom - MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), APPI, 96);

    LH := LineHeight(APPI);
    ContentTop := ContentRect.Top;

    // Resolve the selection band color ONCE before the visible-row loop (mirrors
    // TTyEdit): the TyTextSelection typeKey (accent-tinted via
    // --selection = alpha(accent,0.30)). Only needed when a selection exists; the
    // band is filled per visible row below.
    SL := 0; SC := 0; EL := 0; EC := 0;
    // HideSelection (TMemo): when unfocused, paint no selection band (the selection is preserved).
    ShowSel := HasSelection and ((Focused or FForceFocused) or not FHideSelection);
    if ShowSel then
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
      { Alignment shifts this row's ORIGIN -- text, band and caret all take the same AOff, so
        the three can never drift apart. Zero under the default taLeftJustify (RowAlignOffset
        exits before measuring), which keeps the unaligned render byte-identical. }
      AlignW := (ContentRect.Right - SBWidth) - ContentRect.Left;
      AOff := RowAlignOffset(vr, AlignW, APPI);
      // Horizontal scroll: shift the row's left edge left by FScrollX so a long
      // line follows the caret; the Right edge stays clipped at the content
      // right (DrawText clips to LineRect), so glyphs never spill past it. With
      // FScrollX = 0 (fitting text or WordWrap=True) LineRect.Left is unchanged,
      // so the no-wrap render is byte-identical to today.
      LineRect := Rect(ContentRect.Left - FScrollX + AOff, y,
        ContentRect.Right - SBWidth, y + LH);

      // Selection band for this row, drawn BENEATH the text (band first so the
      // glyphs sit on top). Reuse the SAME line widths the row draws with so band
      // geometry matches the drawn text exactly. No FScrollX term (added in T3).
      // Generalised per visual row: with RS=0 it reduces to the legacy per-line
      // band exactly. RowBaseW shifts the row's columns so the segment's first
      // codepoint sits at ContentRect.Left.
      if ShowSel and (RL >= SL) and (RL <= EL) then
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
          // Band color from the TyTextSelection typeKey (accent-tinted; mirrors
          // TTyEdit). Theme-overridable, matching selected list rows.
          BandColor := SelStyle.Background.Color;
          BandFill := Default(TTyFill);
          BandFill.Kind := tfkSolid;
          BandFill.Color := BandColor;
          if RowBidi(vr, APPI, RowRB) then
          begin
            { A selection is a LOGICAL range, and a logical range that crosses a direction
              boundary is not one rectangle on screen. Selecting "ab" plus the FIRST letter
              of an embedded Hebrew word highlights the "ab" and that letter -- with the
              SECOND Hebrew letter, which is NOT selected, drawn in the gap between them.
              One band spanning the lot would be telling the user they had selected it.
              So: one band per run, over the part of the run the selection actually covers.
              Columns go row-relative here, which is the frame the run table is in. }
            if bandEndCol < 0 then bandEffEnd := RE else bandEffEnd := bandEndCol;
            for RunIdx := 0 to High(RowRB.Runs) do
            begin
              SelA := bandStartCol - RS;
              if SelA < RowRB.Runs[RunIdx].First then SelA := RowRB.Runs[RunIdx].First;
              SelB := bandEffEnd - RS;
              if SelB > RowRB.Runs[RunIdx].Last then SelB := RowRB.Runs[RunIdx].Last;
              if SelA >= SelB then Continue;
              X1 := RowBidiEdgeX(RowRB, RunIdx, SelA);
              X2 := RowBidiEdgeX(RowRB, RunIdx, SelB);
              // Inside a right-to-left run the later codepoint is the SMALLER x.
              if X2 < X1 then begin BandSwap := X1; X1 := X2; X2 := BandSwap; end;
              X1 := ContentRect.Left + X1 - FScrollX + AOff;
              X2 := ContentRect.Left + X2 - FScrollX + AOff;
              if X1 < ContentRect.Left then X1 := ContentRect.Left;
              if X2 > ContentRect.Right - SBWidth then X2 := ContentRect.Right - SBWidth;
              if X1 < X2 then
                P.FillBackground(Rect(X1, y, X2, y + LH), BandFill, 0);
            end;
            { The trailing-line-break strip. When the selection continues onto a later line
              the plain path fills to the viewport right to show the break is included; that
              indicator is about the ROW, not about any run, so it is drawn from the row's
              rightmost ink rather than folded into one of the run bands. }
            if bandEndCol < 0 then
            begin
              X1 := 0;
              for RunIdx := 0 to High(RowRB.Runs) do
                if RowRB.Runs[RunIdx].Right > X1 then X1 := RowRB.Runs[RunIdx].Right;
              X1 := ContentRect.Left + X1 - FScrollX + AOff;
              X2 := ContentRect.Right - SBWidth;
              if X1 < ContentRect.Left then X1 := ContentRect.Left;
              if X1 < X2 then
                P.FillBackground(Rect(X1, y, X2, y + LH), BandFill, 0);
            end;
          end
          else
          begin
            // Shift the band left by FScrollX (same as the text). The right-edge
            // sentinel (bandEndCol < 0) already means "extend to the viewport right"
            // so it is NOT shifted. Clamp both edges into the content rect so the
            // band never paints over the padding/scrollbar when scrolled. FScrollX=0
            // leaves the band geometry byte-identical to today.
            X1 := ContentRect.Left + (Widths[bandStartCol] - RowBaseW) - FScrollX + AOff;
            if bandEndCol < 0 then
              X2 := ContentRect.Right - SBWidth
            else
              X2 := ContentRect.Left + (Widths[bandEndCol] - RowBaseW) - FScrollX + AOff;
            if X1 < ContentRect.Left then X1 := ContentRect.Left;
            if X2 > ContentRect.Right - SBWidth then X2 := ContentRect.Right - SBWidth;
            if X1 < X2 then
            begin
              BandRect := Rect(X1, y, X2, y + LH);
              P.FillBackground(BandRect, BandFill, 0);
            end;
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
      { The row directly, not through CaretToVisual: the rows are already ensured above and
        the x is taken from the row's own frame just below, so resolving an absolute x here
        only to discard it would pay for a second ContentWidthFor mid-paint. }
      if Length(FVisualRows) = 0 then
        CaretVRow := -1
      else
        CaretVRow := CaretOwningRow(FCaretLine, FCaretCol);
      if (CaretVRow >= FTopRow) and (CaretVRow <= LastVisible)
        and (CaretVRow >= 0) and (CaretVRow <= High(FVisualRows)) then
      begin
        // Row-relative caret X in the same frame the row's text is drawn in, then shifted
        // left by FScrollX so the caret tracks the scrolled text and right by the row's
        // alignment offset. RowCaretRelX is the prefix sum for a row with no right-to-left
        // script in it and the reordered position otherwise, so this one line is both.
        CaretX := R.Left + TextStartX(APPI)
          + RowCaretRelX(CaretVRow, FCaretCol - FVisualRows[CaretVRow].StartCol,
              FCaretAfterPrev, APPI)
          - FScrollX
          + RowAlignOffset(CaretVRow, (ContentRect.Right - SBWidth) - ContentRect.Left, APPI);
        y := ContentTop + (CaretVRow - FTopRow) * LH;
        CaretRect := Rect(CaretX, y + P.Scale(2),
          CaretX + P.Scale(1), y + LH - P.Scale(2));
        P.FillBackground(CaretRect, Default(TTyFill), 0);
        P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
        if not EqualRect(FImeCaretRect, CaretRect) then
        begin
          FImeCaretRect := CaretRect;   // cache for the IME candidate-window query
          TyImeUpdateCaret;           // Qt6: re-query so the candidate follows the caret (no-op elsewhere)
        end;
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
var
  imeFull: string;
begin
  if not Enabled then Exit;          // v1.5 policy: ignore input when disabled
  if FReadOnly then Exit;            // ReadOnly: block printable typing
  { GTK3: the backend truncated this commit into a TUTF8Char on its way here. The whole
    string is still pending in the widgetset, so take it and insert THAT instead. Returns ''
    on every other widgetset and whenever nothing was truncated, so the normal path below is
    untouched. }
  imeFull := TyImeTakeCommit(UTF8Key);
  if imeFull <> '' then
  begin
    HandleImeCommit(imeFull);
    UTF8Key := '';   // consumed: stop the truncated copy being inserted as well
    Exit;
  end;
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

function TTyMemo.GetImeCaretRect: TRect;
begin
  if (not HandleAllocated) or (not Focused) then
    Exit(Rect(0, 0, 0, 0));   // decline -> Qt's default candidate position stands
  Result := FImeCaretRect;
end;

procedure TTyMemo.InitializeWnd;
begin
  inherited InitializeWnd;
  TyImeUninstall(FImeHook);   // defensive: drop any prior hook if the handle is recreated
  { Own-context IME: Qt intercepts the truncating TUTF8Char path; GTK2 attaches a GtkIMContext
    because stock LCL-GTK2 delivers none. The facade picks the right one (nil where unneeded). }
  FImeHook := TyImeInstall(Self, @HandleImeCommit, @GetImeCaretRect);
end;

procedure TTyMemo.DestroyWnd;
begin
  TyImeUninstall(FImeHook);
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
        // Caret is at the start of the new line with no selection (collapse the anchor).
        FSelAnchorLine := FCaretLine;
        FSelAnchorCol := FCaretCol;
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
        // A word jump names a codepoint, not a glyph: it has no side to stand on.
        DefaultCaretAffinity;
      end
      { Left is VISUAL movement in text. MoveCaretVisualH answers False -- having changed
        nothing -- for any row that is not reordered, and the logical walk below is then
        byte-identical to what it always was. }
      else if not MoveCaretVisualH(-1, APPI) then
      begin
        if FCaretCol > 0 then
          Dec(FCaretCol)
        else if FCaretLine > 0 then
        begin
          Dec(FCaretLine);
          FCaretCol := LineLen(FCaretLine);
        end;
        DefaultCaretAffinity;
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
        // A word jump names a codepoint, not a glyph: it has no side to stand on.
        DefaultCaretAffinity;
      end
      // Right is VISUAL movement in text; see the note on VK_LEFT.
      else if not MoveCaretVisualH(+1, APPI) then
      begin
        if FCaretCol < L then
          Inc(FCaretCol)
        else if FCaretLine < MaxLine then
        begin
          Inc(FCaretLine);
          FCaretCol := 0;
        end;
        DefaultCaretAffinity;
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
        { The wrap path is already an x-preserving move; the no-wrap path restores a
          remembered COLUMN, which only names the same screen place when both lines read the
          same way. When either does not, route the no-wrap move through the same
          x-preserving code -- with WordWrap off a visual row IS a logical line, so
          MoveCaretByVisualRow's row arithmetic reduces to the line arithmetic below it,
          clamp and no-op guard included. }
        if FWordWrap or VerticalMoveNeedsX(FCaretLine - 1) then
          MoveCaretByVisualRow(-1, APPI)
        else if FCaretLine > 0 then
        begin
          Dec(FCaretLine);
          // Restore desired column, clamped to the new line length.
          FCaretCol := FDesiredCol;
          if FCaretCol > LineLen(FCaretLine) then
            FCaretCol := LineLen(FCaretLine);
          DefaultCaretAffinity;
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
        // See the note on VK_UP for why a reordered line takes the x-preserving path.
        if FWordWrap or VerticalMoveNeedsX(FCaretLine + 1) then
          MoveCaretByVisualRow(+1, APPI)
        else if FCaretLine < MaxLine then
        begin
          Inc(FCaretLine);
          FCaretCol := FDesiredCol;
          if FCaretCol > LineLen(FCaretLine) then
            FCaretCol := LineLen(FCaretLine);
          DefaultCaretAffinity;
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
      // Home names a logical end, not a glyph: it has no side to stand on.
      DefaultCaretAffinity;
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
      // End likewise: a logical end, not a glyph.
      DefaultCaretAffinity;
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
