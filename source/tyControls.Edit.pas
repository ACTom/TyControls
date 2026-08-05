unit tyControls.Edit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8, LazMethodList, Clipbrd,
  ExtCtrls, StdCtrls,
  BGRABitmap, BGRABitmapTypes, BGRATextBidi,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.UndoStack,
  tyControls.Animation, tyControls.QtWS, tyControls.GtkWS;
type
  TTyIntArray = array of Integer;

  { One same-direction stretch of a laid-out line: a contiguous half-open range of LOGICAL
    codepoints [First, Last) that the bidirectional algorithm placed at [Left, Right) on
    screen. A line with no right-to-left script in it is one run and this whole apparatus
    stays asleep; "ab<two hebrew letters>cd" is three, the middle one drawn right-to-left.

    The runs are in LOGICAL order (they partition 0..codepoint count) while Left/Right are
    VISUAL, so run[1].Left < run[0].Left is perfectly normal and is exactly the case the
    prefix sum could not express. }
  TTyBidiRun = record
    First, Last: Integer;
    RTL: Boolean;
    Left, Right: Integer;   // device px, relative to the text origin (as MeasureCodepointWidths is)
  end;
  TTyBidiRunArray = array of TTyBidiRun;

  TTyEdit = class(TTyCustomControl)
  private
    FText: TCaption;
    FCaret: Integer;      // codepoint index 0..UTF8Length(FText)
    { Which of the two glyphs beside FCaret the caret is standing against.

      A codepoint index stops having ONE screen position the moment the text is
      bidirectional: in "ab<alef><bet>cd" the boundary at index 2 is both "after the b" and
      "before the alef", and those are the two OPPOSITE ends of the Hebrew run. True means
      the caret is drawn against the character BEFORE it (where typing and a rightward walk
      leave it), False against the character AFTER it. Both are legitimate answers and the
      Unicode algorithm does not choose; the operation that last moved the caret does, so
      that is what this remembers.

      True is the default and the value every path that does not care leaves behind, because
      it is what an insertion point means: "the text I just wrote ends here". }
    FCaretAfterPrev: Boolean;
    FSelAnchor: Integer;  // codepoint index; no selection <=> FSelAnchor = FCaret
    FMouseSelecting: Boolean;  // true while left button held for drag-select
    FScrollX: Integer;    // horizontal scroll offset in device px (>= 0)
    // Width cache
    FWidthCache: TTyIntArray;
    FWidthCacheValid: Boolean;
    FWidthCacheFontName: string;
    FWidthCacheFontSize: Integer;   // effective pt (after EffectiveFontSize)
    FWidthCachePPI: Integer;
    FWidthCachePassword: string;    // password char active when cache was built
    { --- Bidirectional layout cache; see EnsureBidiLayout for the whole argument ---
      FBidiHasRTL is THE GATE's answer, kept rather than recomputed: whether the text needs
      reordering depends on the text alone, so a font or PPI change cannot flip it and a
      left-to-right field pays one Boolean test per caret query rather than a scan. }
    FBidiGateValid: Boolean;
    FBidiHasRTL: Boolean;
    FBidiValid: Boolean;            // the arrays below match the key fields below
    FBidiActive: Boolean;           // ...and there is something in them worth using
    FBidiRuns: TTyBidiRunArray;     // logical order
    FBidiOrder: TTyIntArray;        // run indices, LEFT-to-RIGHT on screen
    { The x of caret boundary i measured inside the run that owns the character AFTER it
      (Lead) and inside the run that owns the character BEFORE it (Trail). They differ only
      at a direction boundary -- which is the entire point, since that is where one index
      has two positions and BGRA's own GetCaret hands back only the second. }
    FBidiLead: TTyIntArray;
    FBidiTrail: TTyIntArray;
    FBidiKeyFont: string;
    FBidiKeySize: Integer;
    FBidiKeyPPI: Integer;
    FBidiKeyPassword: string;
    // Lazy measuring bitmap (freed in Destroy)
    FMeasureBmp: TBGRABitmap;
    // Undo/redo infrastructure
    FUndoStack: TTyUndoStack;
    FSuspendUndo: Boolean;   // true while a composite op pushes its own step
    FReadOnly: Boolean;
    FMaxLength: Integer;
    FPasswordChar: string;
    FEchoMode: TEchoMode;
    FTextHint: TCaption;
    FAlignment: TAlignment;
    FCharCase: TEditCharCase;
    FNumbersOnly: Boolean;
    FHideSelection: Boolean;
    FModified: Boolean;
    { True only for the duration of a PROGRAMMATIC text write (the published Text setter).
      LCL calls its copy FTextChangedByRealSetText and reads it in exactly one place --
      Change -- to keep `Edit.Text := S` from dirtying the field while typing does
      (include/customedit.inc:615-616). Without the flag the two are indistinguishable,
      which is why a hand-rolled OnChange dirty-tracker can never reproduce Modified. }
    FTextChangeByCode: Boolean;
    FAutoSelect: Boolean;
    FAutoSelected: Boolean;
    FOnChange: TNotifyEvent;
    { Multicast OnChange (LCL stdctrls.pp:853-855 / customedit.inc:91-97). Created lazily:
      an edit that nobody observes must not pay for a TMethodList. }
    FOnChangeHandlers: TMethodList;
    FImeHook: TObject;    // Qt-only IME commit interceptor (nil off Qt); see tyControls.QtWS
    FImeCaretRect: TRect; // caret rect (client device px) cached each paint; fed to the Qt IME query
    // Insert a full IME commit string (Qt: the un-truncated QInputMethodEvent.commitString).
    procedure HandleImeCommit(const ACommitUtf8: string);
    // Caret rect (client device px) for the Qt IME candidate window; empty when not focused.
    function GetImeCaretRect: TRect;
    procedure SetText(const AValue: TCaption);
    procedure SetTextHint(const AValue: TCaption);
    procedure SetCaretPos(AValue: Integer);
    procedure SetReadOnly(const AValue: Boolean);
    procedure SetMaxLength(const AValue: Integer);
    procedure SetPasswordChar(const AValue: string);
    procedure SetEchoMode(const AValue: TEchoMode);
    procedure SetHideSelection(const AValue: Boolean);
    procedure SetAlignment(const AValue: TAlignment);
    procedure SetCharCase(const AValue: TEditCharCase);
    // Selection accessors (read = derived from FSelAnchor/FCaret; write = move selection)
    function GetSelStart: Integer;
    function GetSelLength: Integer;
    function GetSelText: string;
    procedure SetSelStart(const AValue: Integer);
    procedure SetSelLength(const AValue: Integer);
    procedure SetSelText(const AValue: string);
    // Apply CharCase transform to an inserted UTF-8 fragment
    function ApplyCharCase(const AStr: string): string;
    // Selection helpers
    procedure DeleteSelection;
    // Word-wise deletion (splice modelled on DeleteSelection)
    procedure DeleteWordBackward;
    procedure DeleteWordForward;
    { Build (or reuse) the bidirectional run table and the two caret-x arrays for the
      CURRENT display text, font and PPI. Cheap no-op -- one Boolean test -- when the text
      carries no right-to-left script, which is the overwhelmingly common case and the one
      whose cost may not change. }
    procedure EnsureBidiLayout(APPI: Integer);
    { The x of caret boundary AIndex measured INSIDE run ARun. Only meaningful for
      ARun.First <= AIndex <= ARun.Last. }
    function BidiRunEdgeX(ARun, AIndex: Integer): Integer;
    // The run the live caret currently binds to (see FCaretAfterPrev). -1 when there is none.
    function BidiCaretRun: Integer;
    // The run immediately to the left (ADir<0) or right (ADir>0) of ARun on screen; -1 at the end.
    function BidiNeighbourRun(ARun, ADir: Integer): Integer;
    { Move the caret ONE GLYPH in the direction pressed (ADir: -1 left, +1 right) and set
      the affinity the move implies. False when there is nowhere further to go. }
    function MoveCaretVisual(ADir, APPI: Integer): Boolean;
    { Park FCaretAfterPrev at its default -- the caret stands against the character BEFORE
      it. Called by the navigations that move the caret without choosing a glyph for it to
      stand against: a programmatic SelStart or CaretPos, a word jump, End, collapsing a
      selection onto one of its edges. The mouse and the arrow keys DO choose, and set it
      themselves. (Text mutations go through InvalidateWidthCache, which does this too.) }
    procedure DefaultCaretAffinity;
    // Scroll helpers
    procedure EnsureCaretVisible(APPI: Integer);
    procedure ClampScrollX(APPI: Integer);
    // Pin the Windows IME composition window to the on-screen caret
    procedure UpdateImeCaret;
    // Word-classifier helper (pure codepoint logic; no widget dependency)
    function IsWordCodepoint(const CP: string): Boolean;
  protected
    // Blinking caret (Task 10). FCaretVisible defaults True; the timer is created
    // lazily and started ONLY when HandleAllocated, so headless tests never blink
    // and the static-caret pixel tests stay deterministic. Protected so the
    // headless access subclass can reach FCaretVisible.
    FCaretVisible: Boolean;
    FBlinkTimer: TTimer;
    FBlinkElapsedMs: Integer;
    procedure EnsureBlinkTimer;
    procedure HandleBlink(Sender: TObject);
    procedure ResetCaretBlink;
    procedure DoEnter; override;
    procedure DoExit; override;
    function GetStyleTypeKey: string; override;
    procedure DoChange;
    { The one text writer. AByCode=True is a PROGRAMMATIC assignment (the published Text
      setter): the caret parks at the end and Modified comes back False. AByCode=False is a
      write that stands in for a keystroke, which only TTyMaskEdit needs -- it rebuilds the
      whole display string on every accepted character, and routing that through the
      programmatic path would clear the dirty flag on every keypress. }
    procedure SetTextInternal(const AValue: TCaption; AByCode: Boolean);
    // Text measurement helpers (protected so headless access subclasses can call them --
    // the comment that claimed so had been sitting over a PRIVATE block).
    function TextStartX(APPI: Integer): Integer;
    procedure InvalidateWidthCache;
    function EffectiveFontSize(const S: TTyStyleSet): Integer;
    function MeasureCodepointWidths(APPI: Integer): TTyIntArray;
    { WHICH PATH the caret is currently coming from: the bidirectional run table, or the
      prefix sum. A diagnostic, and it has to exist, because pixels cannot answer it -- for
      text with a single run the two paths produce the SAME numbers, so a gate wedged
      permanently open is invisible in the output and shows up only in the cost (a
      TBidiTextLayout per text change, measured at ~3.3 ms against a ~23 us caret query).
      A mutation that forced the gate on passed every geometry guard in the suite until this
      existed. }
    function UsesBidiCaret(APPI: Integer): Boolean;
    // Trailing-widget hook: a subclass reserves RightReserve device-px at the RIGHT of the
    // text area (default 0 => plain edit, byte-identical) and paints its widget there via
    // PaintTrailing; TrailingZone returns the same rect (client px) for hit-testing.
    function RightReserve(APPI: Integer): Integer; virtual;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); virtual;
    function TrailingZone(APPI: Integer): TRect;
    // Filter text about to be inserted (typing / paste / IME). Default returns AText unchanged so
    // plain edits are byte-identical. Called at the single insertion chokepoints (InjectKey after
    // any selected text is deleted, and InjectStringAt), so a subclass sees the residual FText +
    // FCaret (the insert point) and can accept/reject/scrub (e.g. numeric-only). '' => insert nothing.
    function FilterInsert(const AText: string): string; virtual;
    // Insert a raw UTF-8 string at the caret (the bulk path paste/IME funnel through; protected so
    // a headless access subclass can drive it and so subclasses can insert programmatically).
    procedure InjectStringAt(const AStr: string);
    // Horizontal alignment offset (device px) added to the text/caret/selection
    // start under Alignment=taCenter/taRightJustify. Zero when left-aligned or
    // when the text overflows the view (scroll governs; alignment is moot).
    function AlignOffset(APPI: Integer): Integer;
    // Display text: masked when PasswordChar is set, otherwise FText
    function DisplayText: string;
    // Undo/redo state serialization (protected so headless access subclasses
    // can expose them; pure logic, no widget dependency beyond geometry resync).
    function CaptureState: string;
    procedure RestoreState(const S: string);
    procedure BeginUndoStep(AKind: Byte);
    procedure BreakCoalescing;
    // Word-boundary helpers (pure codepoint logic on FText; unit-testable like
    // TyScrollThumbRect). Protected so headless access subclasses can expose
    // them; they have no widget/paint dependency. Indices are codepoint counts.
    function NextWordBoundary(AIdx: Integer): Integer;
    function PrevWordBoundary(AIdx: Integer): Integer;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    // Qt6: install/tear down our own input-method commit interceptor on the native widget
    // (custom controls otherwise only get the TUTF8Char/String[7]-truncated commit). No-op off Qt.
    procedure InitializeWnd; override;
    procedure DestroyWnd; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    // Clipboard virtual hooks (override in tests to avoid real clipboard)
    function ReadClipboardText: string; virtual;
    procedure WriteClipboardText(const S: string); virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure InjectKey(const AChar: TUTF8Char);
    { VIRTUAL, and it matters: these are the erase counterparts of InjectKey, and unlike it
      they splice FText directly instead of passing through FilterInsert -- so a descendant
      that rewrites the whole string (TTyMaskEdit) had no seam here and these two removed a
      raw character from its display, mask literals and placeholders included. Same hole the
      paste path had before FilterInsert existed; found by a guard, not by a user. }
    procedure InjectBackspace; virtual;
    procedure InjectDelete; virtual;
    // Selection API
    function HasSelection: Boolean;
    procedure SelectAll;
    { BREAKING, and deliberately so. This used to COLLAPSE the selection (drop the
      highlight, leave the text); LCL's and Delphi's TCustomEdit.ClearSelection DELETE the
      selected text. Under one name, two opposite meanings -- and the silent direction was
      the dangerous one: code ported from Lazarus called ClearSelection to remove what the
      user had selected, the text stayed, and nothing said so.

      Nothing inside this library called it (grep: every other ClearSelection hit is a
      list/tree/grid deselecting ROWS, which is a different and correct meaning), so the
      change breaks only callers who relied on the collapse. CollapseSelection below is
      that behaviour, kept and named. }
    procedure ClearSelection;
    { Drop the highlight without touching the text -- what ClearSelection used to do. }
    procedure CollapseSelection;
    { Empty the control. One line, but the one LCL name for it -- `Ed.Clear` is what
      ported code writes, and `Text := ''` is what it had to be rewritten to. }
    procedure Clear;
    // Mouse hit test
    function CaretIndexAtX(AX: Integer): Integer; overload;
    { The same, also reporting which side of the boundary the click landed on -- which run
      the user aimed at. Only the pair says where the caret goes: at a direction boundary
      the index alone is two different places on screen. }
    function CaretIndexAtX(AX: Integer; out AAfterPrev: Boolean): Integer; overload;
    // Clipboard API
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard;
    // Rendering helpers (public for headless tests)
    function CaretPixelXAt(ACaretIndex, APPI: Integer): Integer;
    { Where the caret for ACaretIndex is DRAWN, device px in control coordinates before
      the horizontal scroll and the alignment offset are applied -- the same origin
      CaretPixelXAt has always used.

      AAfterPrev is the caret's AFFINITY, and it exists because a codepoint index does not
      have one screen position once the text is bidirectional. In "ab<2 hebrew letters>cd"
      the boundary at index 2 is both "after the b" and "before the first Hebrew letter",
      and those are the two opposite ends of the Hebrew run. True picks the side of the
      character BEFORE the caret (where typing left it), False the side of the character
      AFTER it. For text with no right-to-left run in it the two answers are identical and
      this is exactly CaretPixelXAt. }
    function CaretDrawXAt(ACaretIndex, APPI: Integer; AAfterPrev: Boolean): Integer;
    { Where the LIVE caret is drawn: CaretDrawXAt for CaretPos, resolved with the affinity
      the last caret movement left behind. This -- not CaretPixelXAt -- is what the
      renderer, the scroller and the IME follow, because they follow the caret the user
      can see. }
    function CaretDrawX(APPI: Integer): Integer;
    // Undo/redo API
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    { Multicast OnChange, LCL's stdctrls.pp:853-855. The single OnChange property belongs to
      the application; a validator, a dirty-tracker or a live preview living inside the
      library (or a framework layer above it) has to be able to observe the same edit without
      taking that slot away, and two such observers have to be able to coexist. }
    procedure AddHandlerOnChange(const AnOnChangeEvent: TNotifyEvent; AsFirst: Boolean = False);
    procedure RemoveHandlerOnChange(const AnOnChangeEvent: TNotifyEvent);
    procedure RemoveAllHandlersOfObject(AnObject: TObject); override;
    { Caret index in CODEPOINTS. LCL's TCustomEdit.CaretPos is a TPoint because the same
      class also backs a memo; a single-line edit has no second axis, so this deliberately
      differs -- and differs LOUDLY, since Integer and TPoint share no assignment. (The same
      call was made on the sibling TTySpinEdit; the two now read alike.) The line/column form
      that a multi-line control really needs lives on TTyMemo as CaretLine / CaretCol. }
    property CaretPos: Integer read FCaret write SetCaretPos;
    // Scroll offset (device px, >= 0) — read-only for tests
    property ScrollX: Integer read FScrollX;
    // Selection accessors (runtime; mirror native TCustomEdit's public Sel*).
    // SelStart = min(anchor,caret); SelLength = |caret-anchor|; SelText = the
    // selected substring. Writing SelStart collapses the selection there;
    // writing SelLength extends the caret from SelStart; writing SelText
    // replaces the current selection (single OnChange).
    property SelStart: Integer read GetSelStart write SetSelStart;
    property SelLength: Integer read GetSelLength write SetSelLength;
    property SelText: string read GetSelText write SetSelText;
    { Dirty flag, LCL's TCustomEdit.Modified (stdctrls.pp:867). True once the USER has changed
      the text -- typed, deleted, pasted, cut, undone; False again after a programmatic
      `Text := ...`. That split is the whole point and is the one thing an application cannot
      rebuild from OnChange, because OnChange fires for both. Host code drives enable-Save and
      prompt-on-close off it. Not published: it is run-time state, not a design value. }
    property Modified: Boolean read FModified write FModified;
    { LCL's latch (stdctrls.pp:839): set once AutoSelect has fired for this focus visit so the
      first click inside an already-focused edit does not re-select. Cleared on focus loss. }
    property AutoSelected: Boolean read FAutoSelected write FAutoSelected;
  published
    property Text: TCaption read FText write SetText;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property MaxLength: Integer read FMaxLength write SetMaxLength default 0;
    { The masking character, as a UTF-8 STRING rather than LCL's Char (stdctrls.pp:870) --
      deliberately wider, because the character people actually want is '●' (U+25CF), which
      does not fit in a Char. '' turns masking off.

      #0 is accepted and means '' , because LCL's "off" value IS #0 and `Ed.PasswordChar := #0`
      compiles here (Char converts to string). It used to build a one-character string holding
      NUL, so the field went on masking -- with a glyph nobody can see -- exactly when the
      ported code was asking for plain text. Same for ' ' , which is LCL's emNone. }
    property PasswordChar: string read FPasswordChar write SetPasswordChar;
    { How the text is echoed, LCL's TCustomEdit.EchoMode (stdctrls.pp:863). emNormal shows the
      text, emPassword masks it, emNone shows NOTHING at all -- and emNone had no equivalent
      here at any spelling. Coupled to PasswordChar in both directions exactly as LCL couples
      them (include/customedit.inc:374-387 and 408-424), so setting either keeps the other
      truthful and a form can be written against whichever one it already uses. }
    property EchoMode: TEchoMode read FEchoMode write SetEchoMode default emNormal;
    { When True (the default, as on TEdit -- stdctrls.pp:865) the selection band is not painted
      while the control is unfocused; the selection itself survives. Without it a form with
      three edits paints three "active-looking" selections at once. TTyMemo has had this since
      it shipped; only the Edit was missing it. }
    property HideSelection: Boolean read FHideSelection write SetHideSelection default True;
    { Select the whole text when the control gains focus from the KEYBOARD (Tab/Enter), and on
      the first left click of that focus visit -- LCL's TEdit default (stdctrls.pp:838), and
      what makes "tab in, type the new value" work without an OnEnter handler on every edit. }
    property AutoSelect: Boolean read FAutoSelect write FAutoSelect default True;
    property TextHint: TCaption read FTextHint write SetTextHint;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property CharCase: TEditCharCase read FCharCase write SetCharCase default ecNormal;
    property NumbersOnly: Boolean read FNumbersOnly write FNumbersOnly default False;
    property Enabled;
    property Font;
    { The constructor turns this on (an edit is always a tab stop); declaring the default
      to match is what makes the OPT-OUT work — against the inherited `default False` a
      designer's TabStop=False equals the declared default, is never written to the .lfm,
      and the constructor's True silently wins again at run time. }
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;
implementation

constructor TTyEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  Cursor := crIBeam;
  Width := 140;
  Height := TyDensityHeight(ActiveController, 28);
  FText := '';
  FCaret := 0;
  FCaretAfterPrev := True;     // an insertion point stands after what was written
  FSelAnchor := 0;
  FScrollX := 0;
  FWidthCacheValid := False;
  FBidiGateValid := False;
  FMeasureBmp := nil;
  FUndoStack := TTyUndoStack.Create;
  FSuspendUndo := False;
  FCaretVisible := True;       // solid caret until a real timer toggles it
  FBlinkTimer := nil;          // lazy: created only when HandleAllocated
  FBlinkElapsedMs := 0;
  FEchoMode := emNormal;
  FHideSelection := True;      // TEdit default: no selection band while unfocused
  FAutoSelect := True;         // TEdit default: tab in and the value is selected
  FAutoSelected := False;
  FModified := False;
  { Announce what this is to assistive technology. A self-drawn control has NO native peer for
    a screen reader to fall back on, so without this the whole text-input family reads as an
    unidentified custom control. LCL does the same one line in TCustomEdit.Create
    (include/customedit.inc:87). }
  AccessibleRole := larTextEditorSingleline;
end;

destructor TTyEdit.Destroy;
begin
  // Free the timer first so its OnTimer callback can never fire mid-teardown
  // (mirrors TTyButton.Destroy). It is owned by Self but we free it explicitly.
  FreeAndNil(FBlinkTimer);
  TyQtUninstallIme(FImeHook);   // in case DestroyWnd never ran (Qt-only; no-op elsewhere)
  FUndoStack.Free;
  FMeasureBmp.Free;
  FreeAndNil(FOnChangeHandlers);
  inherited Destroy;
end;

// ---- Multicast OnChange (LCL customedit.inc:91-97) ----

procedure TTyEdit.AddHandlerOnChange(const AnOnChangeEvent: TNotifyEvent;
  AsFirst: Boolean = False);
begin
  if FOnChangeHandlers = nil then FOnChangeHandlers := TMethodList.Create;
  FOnChangeHandlers.Add(TMethod(AnOnChangeEvent), not AsFirst);
end;

procedure TTyEdit.RemoveHandlerOnChange(const AnOnChangeEvent: TNotifyEvent);
begin
  if FOnChangeHandlers <> nil then
    FOnChangeHandlers.Remove(TMethod(AnOnChangeEvent));
end;

procedure TTyEdit.RemoveAllHandlersOfObject(AnObject: TObject);
begin
  inherited RemoveAllHandlersOfObject(AnObject);
  { An observer that is being freed must not stay in the list -- otherwise the next edit
    calls a method on a dead object. LCL overrides this for the same reason. }
  if FOnChangeHandlers <> nil then
    FOnChangeHandlers.RemoveAllMethodsOfObject(AnObject);
end;

// ---- Blinking caret (Task 10) ----

procedure TTyEdit.EnsureBlinkTimer;
begin
  if FBlinkTimer = nil then
  begin
    FBlinkTimer := TTimer.Create(Self);
    FBlinkTimer.Enabled := False;
    FBlinkTimer.Interval := 530;
    FBlinkTimer.OnTimer := @HandleBlink;
  end;
end;

procedure TTyEdit.HandleBlink(Sender: TObject);
begin
  Inc(FBlinkElapsedMs, FBlinkTimer.Interval);
  FCaretVisible := TyCaretVisible(FBlinkElapsedMs, FBlinkTimer.Interval);
  Invalidate;
end;

procedure TTyEdit.ResetCaretBlink;
begin
  FCaretVisible := True;
  FBlinkElapsedMs := 0;
end;

procedure TTyEdit.DoEnter;
begin
  inherited DoEnter;
  { AutoSelect on KEYBOARD focus only -- csLButtonDown is LCL's own test for "this focus came
    from a click" (include/customedit.inc:634), and a click has to be allowed to place the
    caret where it landed. The click case is handled once, in MouseUp. }
  if FAutoSelect and not (csLButtonDown in ControlState) then
  begin
    SelectAll;
    if SelText = FText then FAutoSelected := True;
  end;
  ResetCaretBlink;
  if HandleAllocated then
  begin
    EnsureBlinkTimer;
    FBlinkTimer.Enabled := True;
  end;
  UpdateImeCaret;   // anchor the IME to the caret as soon as we gain focus
  TyGtkImeSetFocus(FImeHook, True);   // GTK2: start our IM context composing (no-op elsewhere)
end;

procedure TTyEdit.DoExit;
begin
  inherited DoExit;
  FAutoSelected := False;   // the next focus visit gets its own auto-select (LCL does this too)
  TyGtkImeSetFocus(FImeHook, False);   // GTK2: stop our IM context composing (no-op elsewhere)
  if FBlinkTimer <> nil then FBlinkTimer.Enabled := False;
  FCaretVisible := True;
  Invalidate;
end;

function TTyEdit.GetStyleTypeKey: string;
begin
  Result := 'TyEdit';
end;

// ---- Change notification ----

procedure TTyEdit.DoChange;
begin
  // Suppressed while a composite op (InjectKey-over-selection, Cut, Paste) runs
  // its inner mutators under FSuspendUndo: the inner DeleteSelection /
  // InjectStringAt must NOT fire OnChange — the composite op fires it once at the
  // end. (FSuspendUndo gates undo-pushes for the same composite ops; OnChange
  // reuses the same "inside a composite" signal so it fires exactly once.)
  if FSuspendUndo then Exit;
  { Dirty-flag bookkeeping sits HERE, at the one point every completed edit passes through, and
    reads the by-code flag exactly as LCL's Change does (include/customedit.inc:613-616). Inside
    a composite op the inner mutators exit above, so a paste-over-selection dirties once. }
  if not FTextChangeByCode then
    FModified := True;
  if Assigned(FOnChange) then
    FOnChange(Self);
  if FOnChangeHandlers <> nil then
    FOnChangeHandlers.CallNotifyEvents(Self);
end;

// ---- Undo/redo machinery ----

function TTyEdit.CaptureState: string;
begin
  // header: caret<TAB>anchor<LF>  then verbatim text
  Result := IntToStr(FCaret) + #9 + IntToStr(FSelAnchor) + #10 + FText;
end;

procedure TTyEdit.RestoreState(const S: string);
var
  NL, TabPos: Integer;
  Header, CaretStr, AnchorStr: string;
  Len: Integer;
  APPI: Integer;
begin
  NL := Pos(#10, S);
  if NL = 0 then Exit;  // malformed; ignore
  Header := Copy(S, 1, NL - 1);
  FText := Copy(S, NL + 1, Length(S) - NL);
  TabPos := Pos(#9, Header);
  if TabPos > 0 then
  begin
    CaretStr := Copy(Header, 1, TabPos - 1);
    AnchorStr := Copy(Header, TabPos + 1, Length(Header) - TabPos);
  end
  else
  begin
    CaretStr := Header;
    AnchorStr := Header;
  end;
  FCaret := StrToIntDef(CaretStr, 0);
  FSelAnchor := StrToIntDef(AnchorStr, FCaret);
  // Clamp to current text bounds
  Len := UTF8Length(FText);
  if FCaret < 0 then FCaret := 0;
  if FCaret > Len then FCaret := Len;
  if FSelAnchor < 0 then FSelAnchor := 0;
  if FSelAnchor > Len then FSelAnchor := Len;
  InvalidateWidthCache;
  APPI := Font.PixelsPerInch;
  ClampScrollX(APPI);
  EnsureCaretVisible(APPI);
  Invalidate;
  DoChange;
end;

procedure TTyEdit.BeginUndoStep(AKind: Byte);
begin
  if FSuspendUndo then Exit;
  FUndoStack.Push(CaptureState, AKind);
end;

procedure TTyEdit.BreakCoalescing;
begin
  { Undo bookkeeping ONLY. It is tempting to default the caret's affinity here too -- every
    caret navigation passes through it -- but the visual arrow walk needs to read the
    affinity it is about to replace, and this runs before it. The default lives in
    InvalidateWidthCache (every text mutation) and at the handful of navigations that move
    the caret without deciding which glyph it stands against. }
  FUndoStack.BreakCoalescing;
end;

procedure TTyEdit.Undo;
begin
  if not Enabled then Exit;
  if FUndoStack.CanUndo then
    RestoreState(FUndoStack.Undo(CaptureState));
end;

procedure TTyEdit.Redo;
begin
  if not Enabled then Exit;
  if FUndoStack.CanRedo then
    RestoreState(FUndoStack.Redo(CaptureState));
end;

function TTyEdit.CanUndo: Boolean;
begin
  Result := FUndoStack.CanUndo;
end;

function TTyEdit.CanRedo: Boolean;
begin
  Result := FUndoStack.CanRedo;
end;

// ---- Selection read helpers ----

function TTyEdit.HasSelection: Boolean;
begin
  Result := FCaret <> FSelAnchor;
end;

function TTyEdit.GetSelStart: Integer;
begin
  if FCaret < FSelAnchor then
    Result := FCaret
  else
    Result := FSelAnchor;
end;

function TTyEdit.GetSelLength: Integer;
begin
  Result := Abs(FCaret - FSelAnchor);
end;

function TTyEdit.GetSelText: string;
begin
  Result := UTF8Copy(FText, SelStart + 1, SelLength);
end;

procedure TTyEdit.SetSelStart(const AValue: Integer);
var
  V, Len: Integer;
begin
  Len := UTF8Length(FText);
  V := AValue;
  if V < 0 then V := 0;
  if V > Len then V := Len;
  // LCL semantics: setting SelStart moves the caret there and collapses the
  // selection (a subsequent SelLength write re-extends it).
  BreakCoalescing;
  FCaret := V;
  FSelAnchor := V;
  DefaultCaretAffinity;
  EnsureCaretVisible(Font.PixelsPerInch);
  ResetCaretBlink;
  Invalidate;
end;

procedure TTyEdit.SetSelLength(const AValue: Integer);
var
  SS, V, Len: Integer;
begin
  Len := UTF8Length(FText);
  // Extend the selection from the current SelStart by AValue codepoints; the
  // anchor stays at SelStart, the caret moves to SelStart+AValue (clamped).
  SS := SelStart;
  V := AValue;
  if V < 0 then V := 0;
  if SS + V > Len then V := Len - SS;
  BreakCoalescing;
  FSelAnchor := SS;
  FCaret := SS + V;
  DefaultCaretAffinity;
  EnsureCaretVisible(Font.PixelsPerInch);
  ResetCaretBlink;
  Invalidate;
end;

procedure TTyEdit.SetSelText(const AValue: string);
var
  TextBefore: string;
begin
  if FReadOnly then Exit;
  TextBefore := FText;
  // Composite op: delete the current selection then insert AValue. Suppress the
  // inner ops' undo-steps + OnChange so the whole replace is one undo and fires
  // OnChange exactly once (mirrors InjectKey-over-selection / Paste).
  BeginUndoStep(uskPaste);
  FSuspendUndo := True;
  try
    if HasSelection then
      DeleteSelection;
    if AValue <> '' then
      InjectStringAt(AValue);
  finally
    FSuspendUndo := False;
  end;
  if FText <> TextBefore then
    DoChange;
end;

procedure TTyEdit.SelectAll;
begin
  BreakCoalescing;
  FSelAnchor := 0;
  FCaret := UTF8Length(FText);
  DefaultCaretAffinity;
  EnsureCaretVisible(Font.PixelsPerInch);
  ResetCaretBlink;
  Invalidate;
end;

procedure TTyEdit.Clear;
begin
  Text := '';
end;

procedure TTyEdit.ClearSelection;
begin
  { Deletes, as LCL does. DeleteSelection already exists and carries the undo step, the
    caret move and the change notification, so this is a rename of intent, not a second
    implementation. }
  if HasSelection then
    DeleteSelection
  else
    CollapseSelection;
end;

procedure TTyEdit.CollapseSelection;
begin
  BreakCoalescing;
  FSelAnchor := FCaret;
  ResetCaretBlink;
  Invalidate;
end;

// ---- Internal mutators ----

procedure TTyEdit.DeleteSelection;
var
  SS, SL: Integer;
  Before, After: string;
  APPI: Integer;
begin
  if not HasSelection then Exit;
  BeginUndoStep(uskDelete);
  SS := SelStart;
  SL := SelLength;
  Before := UTF8Copy(FText, 1, SS);
  After  := UTF8Copy(FText, SS + SL + 1, UTF8Length(FText) - SS - SL);
  FText  := Before + After;
  FCaret := SS;
  FSelAnchor := FCaret;
  InvalidateWidthCache;
  APPI := Font.PixelsPerInch;
  ClampScrollX(APPI);
  EnsureCaretVisible(APPI);
  ResetCaretBlink;
  Invalidate;
  DoChange;
end;

procedure TTyEdit.DeleteWordBackward;
var
  t, Len: Integer;
  Before, After: string;
  APPI: Integer;
begin
  if FReadOnly then Exit;
  if FCaret = 0 then Exit;
  BeginUndoStep(uskDelete);
  Len := UTF8Length(FText);
  t := PrevWordBoundary(FCaret);
  Before := UTF8Copy(FText, 1, t);
  After  := UTF8Copy(FText, FCaret + 1, Len - FCaret);
  FText  := Before + After;
  FCaret := t;
  FSelAnchor := FCaret;
  InvalidateWidthCache;
  APPI := Font.PixelsPerInch;
  ClampScrollX(APPI);
  EnsureCaretVisible(APPI);
  ResetCaretBlink;
  Invalidate;
  DoChange;
end;

procedure TTyEdit.DeleteWordForward;
var
  t, Len: Integer;
  Before, After: string;
  APPI: Integer;
begin
  if FReadOnly then Exit;
  Len := UTF8Length(FText);
  if FCaret >= Len then Exit;
  BeginUndoStep(uskDelete);
  t := NextWordBoundary(FCaret);
  Before := UTF8Copy(FText, 1, FCaret);
  After  := UTF8Copy(FText, t + 1, Len - t);
  FText  := Before + After;
  // caret stays; collapse anchor
  FSelAnchor := FCaret;
  InvalidateWidthCache;
  APPI := Font.PixelsPerInch;
  ClampScrollX(APPI);
  EnsureCaretVisible(APPI);
  ResetCaretBlink;
  Invalidate;
  DoChange;
end;

procedure TTyEdit.SetText(const AValue: TCaption);
begin
  SetTextInternal(AValue, True);   // the published writer is by definition programmatic
end;

procedure TTyEdit.SetTextInternal(const AValue: TCaption; AByCode: Boolean);
var
  APPI: Integer;
begin
  if FText = AValue then Exit;
  BeginUndoStep(uskNone);  // SetText is a distinct (non-typing) undo step
  FText := AValue;
  // Caret moves to end on SetText; collapse selection
  FCaret := UTF8Length(FText);
  FSelAnchor := FCaret;
  InvalidateWidthCache;
  APPI := Font.PixelsPerInch;
  ClampScrollX(APPI);
  EnsureCaretVisible(APPI);
  Invalidate;
  FTextChangeByCode := AByCode;
  try
    DoChange;
  finally
    FTextChangeByCode := False;
  end;
  if AByCode then FModified := False;
end;

procedure TTyEdit.SetCaretPos(AValue: Integer);
var
  Len: Integer;
begin
  Len := UTF8Length(FText);
  if AValue < 0 then AValue := 0;
  if AValue > Len then AValue := Len;
  if (FCaret = AValue) and (FSelAnchor = AValue) then Exit;
  BreakCoalescing;
  FCaret := AValue;
  FSelAnchor := AValue;  // direct CaretPos write collapses selection
  DefaultCaretAffinity;
  EnsureCaretVisible(Font.PixelsPerInch);
  ResetCaretBlink;
  Invalidate;
end;

procedure TTyEdit.SetReadOnly(const AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  Invalidate;
end;

procedure TTyEdit.SetMaxLength(const AValue: Integer);
begin
  if FMaxLength = AValue then Exit;
  FMaxLength := AValue;
end;

procedure TTyEdit.SetPasswordChar(const AValue: string);
var
  V: string;
begin
  if UTF8Length(AValue) > 1 then
    V := UTF8Copy(AValue, 1, 1)
  else
    V := AValue;
  { LCL's off-switch is #0, and `PasswordChar := #0` reaches this setter as a one-character
    string holding NUL. Treating it as a mask glyph is how a ported "stop masking" turned into
    "mask with an invisible character" -- text on screen, none of it readable, nothing raised. }
  if V = #0 then V := '';
  if FPasswordChar = V then Exit;
  FPasswordChar := V;
  { The pair is kept in sync in both directions, as LCL does (customedit.inc:374-387): '' is
    emNormal, ' ' is emNone (show nothing), anything else is emPassword. Assigning FEchoMode
    directly rather than through the property so the two setters cannot recurse. }
  if FPasswordChar = '' then
    FEchoMode := emNormal
  else if FPasswordChar = ' ' then
    FEchoMode := emNone
  else
    FEchoMode := emPassword;
  InvalidateWidthCache;
  Invalidate;
end;

procedure TTyEdit.SetEchoMode(const AValue: TEchoMode);
begin
  if FEchoMode = AValue then Exit;
  FEchoMode := AValue;
  { The other direction of the same coupling (customedit.inc:408-424). emPassword keeps an
    already-chosen glyph and only supplies '*' when there is none. }
  case FEchoMode of
    emNormal: FPasswordChar := '';
    emNone:   FPasswordChar := ' ';
    emPassword:
      if (FPasswordChar = '') or (FPasswordChar = ' ') then FPasswordChar := '*';
  end;
  InvalidateWidthCache;
  Invalidate;
end;

procedure TTyEdit.SetHideSelection(const AValue: Boolean);
begin
  if FHideSelection = AValue then Exit;
  FHideSelection := AValue;
  Invalidate;
end;

procedure TTyEdit.SetTextHint(const AValue: TCaption);
begin
  if FTextHint = AValue then Exit;
  FTextHint := AValue;
  if FText = '' then Invalidate;
end;

procedure TTyEdit.SetAlignment(const AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  // Alignment shifts the visual text/caret/selection start; the width cache
  // (relative offsets) is unaffected, only the draw start, so just repaint.
  Invalidate;
end;

procedure TTyEdit.SetCharCase(const AValue: TEditCharCase);
begin
  if FCharCase = AValue then Exit;
  FCharCase := AValue;
  // Match LCL: re-case the existing buffer when CharCase changes (no caret move,
  // no undo step — purely a display/content normalization).
  if (FText <> '') and (FCharCase <> ecNormal) then
  begin
    FText := ApplyCharCase(FText);
    InvalidateWidthCache;
    Invalidate;
  end;
end;

function TTyEdit.ApplyCharCase(const AStr: string): string;
begin
  case FCharCase of
    ecUppercase: Result := UTF8UpperCase(AStr);
    ecLowerCase: Result := UTF8LowerCase(AStr);
  else
    Result := AStr;
  end;
end;

// ---- Width cache helpers ----

procedure TTyEdit.InvalidateWidthCache;
begin
  FWidthCacheValid := False;
  { The gate's answer and the run table both hang off the TEXT, and this is the one call
    every text mutation already makes -- so it is where they are dropped too, rather than in
    fourteen places that would eventually stop agreeing. }
  FBidiGateValid := False;
  FBidiValid := False;
  FBidiActive := False;
  { And the caret's affinity with it, for the same reason and by the same argument: after a
    text mutation the caret is an insertion point, which by definition stands after what was
    just written. Only the mouse and the arrow keys ever leave it otherwise, and both of
    those set it themselves. }
  FCaretAfterPrev := True;
end;

function TTyEdit.EffectiveFontSize(const S: TTyStyleSet): Integer;
begin
  // Route through the shared resolver so a skin that suppresses TyEdit's font-size gets the
  // theme's --font-size-base (matching default), not a hardcoded 12pt that reads as enlarged.
  Result := ResolveFontSize(S);
end;

// ---- Text measurement helpers ----

function TTyEdit.TextStartX(APPI: Integer): Integer;
var
  S: TTyStyleSet;
begin
  S := CurrentStyle;
  // Same inset logic as RenderTo: left padding scaled at APPI
  Result := MulDiv(S.Padding.Left, APPI, 96);
end;

function TTyEdit.AlignOffset(APPI: Integer): Integer;
var
  S: TTyStyleSet;
  Widths: TTyIntArray;
  StartX, RightPad, ViewWidth, TotalTextWidth, Slack: Integer;
begin
  Result := 0;
  if FAlignment = taLeftJustify then Exit;
  if ClientWidth <= 0 then Exit;
  S := CurrentStyle;
  StartX := MulDiv(S.Padding.Left, APPI, 96);
  RightPad := MulDiv(S.Padding.Right, APPI, 96) + RightReserve(APPI);
  ViewWidth := ClientWidth - StartX - RightPad;
  if ViewWidth <= 0 then Exit;
  Widths := MeasureCodepointWidths(APPI);
  TotalTextWidth := Widths[Length(Widths) - 1];
  // Overflowing text is left-pinned and scroll-driven; alignment is moot.
  Slack := ViewWidth - TotalTextWidth;
  if Slack <= 0 then Exit;
  case FAlignment of
    taRightJustify: Result := Slack;
    taCenter:       Result := Slack div 2;
  end;
end;

function TTyEdit.RightReserve(APPI: Integer): Integer;
begin
  Result := 0;   // plain edit reserves nothing on the right (byte-identical)
end;

procedure TTyEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet);
begin
  // default: no trailing widget
end;

function TTyEdit.TrailingZone(APPI: Integer): TRect;
var
  S: TTyStyleSet;
  res, padR: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  res := RightReserve(APPI);
  if res <= 0 then Exit;
  S := CurrentStyle;
  padR := MulDiv(S.Padding.Right, APPI, 96);
  Result := Rect(ClientWidth - padR - res, MulDiv(S.Padding.Top, APPI, 96),
    ClientWidth - padR, ClientHeight - MulDiv(S.Padding.Bottom, APPI, 96));
end;

function TTyEdit.DisplayText: string;
var
  i, n: Integer;
begin
  if FPasswordChar = '' then
  begin
    Result := FText;
    Exit;
  end;
  n := UTF8Length(FText);
  Result := '';
  for i := 1 to n do
    Result := Result + FPasswordChar;
end;

function TTyEdit.MeasureCodepointWidths(APPI: Integer): TTyIntArray;
// Returns an array of Length=UTF8Length(FText)+1 cumulative x positions (in px)
// relative to the text start, measured on a shared lazy bitmap.
// The result is cached; rebuilds when font/ppi/text/passwordchar change.
// When PasswordChar is active, measurement is done on the masked string so that
// caret positions stay 1:1 with the displayed glyphs.
var
  S: TTyStyleSet;
  EffSize: Integer;
  i, Len: Integer;
  Disp: string;
begin
  S := CurrentStyle;
  EffSize := EffectiveFontSize(S);
  Len := UTF8Length(FText);

  // Check if cache is still valid (includes password char so toggling invalidates)
  if FWidthCacheValid
    and (FWidthCacheFontName = S.FontName)
    and (FWidthCacheFontSize = EffSize)
    and (FWidthCachePPI = APPI)
    and (FWidthCachePassword = FPasswordChar)
    and (Length(FWidthCache) = Len + 1)
  then
  begin
    Result := FWidthCache;
    Exit;
  end;

  // (Re)build cache — measure using the display (masked) string
  Disp := DisplayText;

  SetLength(FWidthCache, Len + 1);
  FWidthCache[0] := 0;

  if Len > 0 then
  begin
    // Ensure measuring bitmap exists (lazy creation)
    if FMeasureBmp = nil then
      FMeasureBmp := TBGRABitmap.Create(1, 1);

    // Configure the font identically to TTyPainter.DrawText so measured glyph
    // widths match what is actually drawn (same BGRA engine + height semantics).
    TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);

    // Cumulative widths via PREFIX measurement on the display string:
    // matches the whole-string draw, capturing kerning/hinting between glyphs.
    for i := 1 to Len do
      FWidthCache[i] := FMeasureBmp.TextSize(UTF8Copy(Disp, 1, i)).cx;
  end;

  FWidthCacheFontName := S.FontName;
  FWidthCacheFontSize := EffSize;
  FWidthCachePPI := APPI;
  FWidthCachePassword := FPasswordChar;
  FWidthCacheValid := True;
  Result := FWidthCache;
end;

// ---- Bidirectional layout ----------------------------------------------------------
//
// WHY THIS EXISTS. MeasureCodepointWidths answers "where is codepoint N" with a cumulative
// sum taken in STRING order. That is exactly right for Latin and CJK and simply untrue once
// the glyphs have been reordered: c2cfafc taught TTyPainter to draw a mixed Arabic/Latin
// line in visual order, and until this the edit still walked its prefix sum -- so an Arabic
// field DREW right and SELECTED wrong. Clicking a glyph put the caret on a different one,
// arrow keys jumped across runs, and a drag-selection highlighted glyphs the user had not
// dragged over.
//
// WHY NOT TTyPainter.TextCaretX / TextCharIndexAtX, which exist for exactly this. Two
// reasons, both structural:
//
//   * they lay out on the painter's FBmp, which only exists between BeginPaint and EndPaint.
//     A caret is asked for from mouse handlers, key handlers, the scroller and the blink
//     timer, and none of those are painting. Standing a whole painter up per query would be
//     a TBidiTextLayout per keystroke -- the shape of the bug that once cost TTyMemo half a
//     second of latency per key.
//   * TextCaretX answers with TBidiTextLayout.GetCaret, which resolves a direction boundary
//     towards the run that ENDS there and discards the other position. In "ab<alef><bet>cd"
//     that makes codepoints 2 and 4 the same pixel with no way to tell them apart, and the
//     far end of the embedded run unreachable by any index at all.
//
// So the line is laid out here instead, ONCE per text/font/PPI change, and every query is an
// array lookup afterwards. The duplication is deliberate and pinned:
// test.edit.bidi.EditCaretAgreesWithThePainterForUnambiguousIndices renders the same string
// through TTyPainter.TextCaretX and requires the same pixel for every index the painter can
// express, so the two cannot drift apart in silence.

procedure TTyEdit.EnsureBidiLayout(APPI: Integer);
var
  S: TTyStyleSet;
  EffSize, i, r, n, a, b, x: Integer;
  Disp: string;
  lay: TBidiTextLayout;
begin
  { THE GATE. Whether a line needs reordering depends on the TEXT and nothing else, so the
    answer outlives a font or PPI change and is kept rather than rescanned. TyTextHasRTL
    rejects ASCII in one compare and CJK, Cyrillic and Greek on the lead byte without
    decoding, and it runs once per text change -- so a left-to-right field's per-query cost
    is the Boolean test below and nothing more.

    It is asked about the DISPLAY text, not about FText: a password field draws a column of
    identical ASCII mask characters, and laying THOSE out bidirectionally would walk the
    caret backwards through a mask that has no direction. }
  if not FBidiGateValid then
  begin
    FBidiGateValid := True;
    FBidiHasRTL := TyTextHasRTL(DisplayText);
    if not FBidiHasRTL then
    begin
      FBidiValid := False;
      FBidiActive := False;
    end;
  end;
  if not FBidiHasRTL then Exit;

  S := CurrentStyle;
  EffSize := EffectiveFontSize(S);
  n := UTF8Length(FText);
  if FBidiValid
    and (FBidiKeyFont = S.FontName)
    and (FBidiKeySize = EffSize)
    and (FBidiKeyPPI = APPI)
    and (FBidiKeyPassword = FPasswordChar)
    and (Length(FBidiLead) = n + 1)
  then
    Exit;

  FBidiValid := True;
  FBidiActive := False;
  FBidiKeyFont := S.FontName;
  FBidiKeySize := EffSize;
  FBidiKeyPPI := APPI;
  FBidiKeyPassword := FPasswordChar;
  SetLength(FBidiRuns, 0);
  SetLength(FBidiOrder, 0);
  SetLength(FBidiLead, 0);
  SetLength(FBidiTrail, 0);
  if n = 0 then Exit;

  Disp := DisplayText;
  if FMeasureBmp = nil then
    FMeasureBmp := TBGRABitmap.Create(1, 1);
  // The same four lines MeasureCodepointWidths runs, and for the same reason: the layout
  // borrows this bitmap's FontRenderer, so its metrics are the ones DrawText will use.
  TyConfigureTextFont(FMeasureBmp, S.FontName, EffSize, S.FontWeight, APPI);

  lay := TBidiTextLayout.Create(FMeasureBmp.FontRenderer, Disp);
  try
    { TopLeft at the origin makes every x below relative to the TEXT START -- the same
      origin FWidthCache uses -- so the callers' existing "content left + align offset +
      width - scroll" arithmetic is untouched. AvailableWidth is left unset for the same
      reason TTyPainter.BuildLineLayout leaves it unset: this is a single-line control, and
      an unset width also stops the layout right-aligning a right-to-left paragraph on its
      own, which would be the MIRRORING half of the job and that half is not built. }
    lay.TopLeft := PointF(0, 0);
    SetLength(FBidiLead, n + 1);
    SetLength(FBidiTrail, n + 1);
    { Seed both arrays from the plain caret query so that an index no run claims (BGRA owes
      us a partition of 0..n, but a zero here would be a caret at the left margin rather
      than a visible wrong answer) still gets a defensible number. The run walk below then
      overwrites every index it owns. }
    for i := 0 to n do
    begin
      x := Round(lay.GetCaret(i).Top.x);
      FBidiLead[i] := x;
      FBidiTrail[i] := x;
    end;
    SetLength(FBidiRuns, lay.PartCount);
    for r := 0 to lay.PartCount - 1 do
    begin
      a := lay.PartStartIndex[r];
      b := lay.PartEndIndex[r];
      FBidiRuns[r].First := a;
      FBidiRuns[r].Last := b;
      FBidiRuns[r].RTL := lay.PartRightToLeft[r];
      FBidiRuns[r].Left := Round(lay.PartRectF[r].Left);
      FBidiRuns[r].Right := Round(lay.PartRectF[r].Right);
      for i := a to b do
      begin
        { The run's OWN end carets at its edges. Asking GetCaret there is what collapses the
          two sides of a boundary onto one; asking the run resolves it, because a run has
          exactly one start and one end and they are never the same point. Strictly inside
          a run there is no ambiguity and GetCaret is exact. }
        if i = a then x := Round(lay.PartStartCaret[r].Top.x)
        else if i = b then x := Round(lay.PartEndCaret[r].Top.x)
        else x := Round(lay.GetCaret(i).Top.x);
        if i < b then FBidiLead[i] := x;    // boundary i faces the character i, which is in this run
        if i > a then FBidiTrail[i] := x;   // ...and character i-1, likewise
      end;
    end;
  finally
    lay.Free;
  end;

  { Run indices in left-to-right SCREEN order, for the arrow keys: "the next glyph to the
    right" is in the next run along, which is not the next run in logical order. Insertion
    sort because a line has a handful of runs, not thousands. }
  SetLength(FBidiOrder, Length(FBidiRuns));
  for r := 0 to High(FBidiRuns) do
  begin
    i := r;
    while (i > 0) and (FBidiRuns[FBidiOrder[i - 1]].Left > FBidiRuns[r].Left) do
    begin
      FBidiOrder[i] := FBidiOrder[i - 1];
      Dec(i);
    end;
    FBidiOrder[i] := r;
  end;
  FBidiActive := Length(FBidiRuns) > 0;
end;

function TTyEdit.BidiRunEdgeX(ARun, AIndex: Integer): Integer;
begin
  { At the run's logical END only Trail was written from this run; everywhere else Lead was.
    (Both arrays hold the same number except at a direction boundary.) }
  if AIndex >= FBidiRuns[ARun].Last then
    Result := FBidiTrail[FBidiRuns[ARun].Last]
  else
    Result := FBidiLead[AIndex];
end;

function TTyEdit.BidiCaretRun: Integer;
var
  r: Integer;
begin
  { The affinity names which neighbouring character the caret is standing against, and that
    character's run is the one it belongs to. At the two ends of the line only one of the
    two rules can be satisfied, so the other is the fallback. }
  for r := 0 to High(FBidiRuns) do
    if FCaretAfterPrev then
    begin
      if (FCaret > FBidiRuns[r].First) and (FCaret <= FBidiRuns[r].Last) then Exit(r);
    end
    else
      if (FCaret >= FBidiRuns[r].First) and (FCaret < FBidiRuns[r].Last) then Exit(r);
  for r := 0 to High(FBidiRuns) do
    if (FCaret >= FBidiRuns[r].First) and (FCaret <= FBidiRuns[r].Last) then Exit(r);
  Result := -1;
end;

function TTyEdit.BidiNeighbourRun(ARun, ADir: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FBidiOrder) do
    if FBidiOrder[i] = ARun then
    begin
      if ADir > 0 then
      begin
        if i < High(FBidiOrder) then Result := FBidiOrder[i + 1];
      end
      else
        if i > 0 then Result := FBidiOrder[i - 1];
      Exit;
    end;
end;

function TTyEdit.UsesBidiCaret(APPI: Integer): Boolean;
begin
  EnsureBidiLayout(APPI);
  Result := FBidiActive;
end;

procedure TTyEdit.DefaultCaretAffinity;
begin
  FCaretAfterPrev := True;
end;

function TTyEdit.MoveCaretVisual(ADir, APPI: Integer): Boolean;
var
  Len, r, q, j: Integer;
begin
  Len := UTF8Length(FText);
  EnsureBidiLayout(APPI);
  if not FBidiActive then
  begin
    // No reordering: one glyph right IS one codepoint forward. Byte-identical to the
    // Inc/Dec this replaced.
    j := FCaret + ADir;
    Result := (j >= 0) and (j <= Len);
    if Result then
    begin
      FCaret := j;
      FCaretAfterPrev := True;
    end;
    Exit;
  end;

  r := BidiCaretRun;
  if r < 0 then Exit(False);
  { Inside a right-to-left run the screen and the string run opposite ways, so a rightward
    keypress is a BACKWARD step through the codepoints. This one line is the whole of
    "Left and Right are visual movement in text". }
  if FBidiRuns[r].RTL then j := FCaret - ADir else j := FCaret + ADir;
  if (j >= FBidiRuns[r].First) and (j <= FBidiRuns[r].Last) then
  begin
    FCaret := j;
    FCaretAfterPrev := j > FBidiRuns[r].First;
    Exit(True);
  end;

  { The step left the run: cross to the one that sits next to it ON SCREEN and land one
    glyph inside it, measured from the edge we arrived at. Landing ON that edge instead
    would be a keypress that did not move the caret, because a run's near edge is the same
    point as its neighbour's far edge. }
  q := BidiNeighbourRun(r, ADir);
  if q < 0 then Exit(False);
  if ADir > 0 then
  begin
    if FBidiRuns[q].RTL then j := FBidiRuns[q].Last - 1 else j := FBidiRuns[q].First + 1;
  end
  else
    if FBidiRuns[q].RTL then j := FBidiRuns[q].First + 1 else j := FBidiRuns[q].Last - 1;
  FCaret := j;
  FCaretAfterPrev := j > FBidiRuns[q].First;
  Result := True;
end;

// ---- Scroll helpers ----

procedure TTyEdit.ClampScrollX(APPI: Integer);
var
  S: TTyStyleSet;
  Widths: TTyIntArray;
  TotalTextWidth, ViewWidth, MaxScroll: Integer;
  RightPad, StartX: Integer;
begin
  if ClientWidth <= 0 then Exit;
  S := CurrentStyle;
  StartX := MulDiv(S.Padding.Left, APPI, 96);
  RightPad := MulDiv(S.Padding.Right, APPI, 96) + RightReserve(APPI);
  ViewWidth := (ClientWidth - StartX - RightPad);
  if ViewWidth < 0 then ViewWidth := 0;
  Widths := MeasureCodepointWidths(APPI);
  TotalTextWidth := Widths[Length(Widths) - 1];
  MaxScroll := TotalTextWidth - ViewWidth;
  if MaxScroll < 0 then MaxScroll := 0;
  if FScrollX > MaxScroll then FScrollX := MaxScroll;
  if FScrollX < 0 then FScrollX := 0;
end;

procedure TTyEdit.EnsureCaretVisible(APPI: Integer);
var
  S: TTyStyleSet;
  Widths: TTyIntArray;
  StartX, RightPad, ViewRight, ViewWidth, MaxScroll: Integer;
  Margin, TotalTextWidth: Integer;
  CaretPx: Integer;
begin
  if ClientWidth <= 0 then Exit;
  S := CurrentStyle;
  StartX := MulDiv(S.Padding.Left, APPI, 96);
  RightPad := MulDiv(S.Padding.Right, APPI, 96) + RightReserve(APPI);
  ViewRight := ClientWidth - RightPad;
  ViewWidth := ViewRight - StartX;
  if ViewWidth < 0 then ViewWidth := 0;

  Widths := MeasureCodepointWidths(APPI);
  TotalTextWidth := Widths[Length(Widths) - 1];

  // Margin: 2 scaled device px
  Margin := MulDiv(2, APPI, 96);

  // Clamp to valid max first
  MaxScroll := TotalTextWidth - ViewWidth;
  if MaxScroll < 0 then MaxScroll := 0;

  { Caret position in control coordinates (before scroll adjustment). Asked of the DRAWN
    caret rather than of the prefix sum: those are the same number for left-to-right text
    and only the drawn one is right for the rest -- and scrolling to where the caret is not
    would leave the user typing off-screen. }
  CaretPx := CaretDrawX(APPI);

  // Scroll right if caret beyond right edge
  if CaretPx - FScrollX > ViewRight - Margin then
    FScrollX := CaretPx - (ViewRight - Margin);

  // Scroll left if caret before left edge
  if CaretPx - FScrollX < StartX + Margin then
    FScrollX := CaretPx - (StartX + Margin);

  // Clamp
  if FScrollX > MaxScroll then FScrollX := MaxScroll;
  if FScrollX < 0 then FScrollX := 0;
  UpdateImeCaret;
end;

procedure TTyEdit.UpdateImeCaret;
{ Keep the Windows IME composition window pinned to the on-screen caret so CJK
  candidates appear at the caret, not the screen origin (we draw our own caret, so
  there is no system caret for the IME to track). Geometry mirrors RenderTo. }
var
  ppi: Integer;
  S: TTyStyleSet;
begin
  if not Focused then Exit;
  ppi := Font.PixelsPerInch;
  S := CurrentStyle;
  TySetImeCaretPos(Self,
    CaretDrawX(ppi) + AlignOffset(ppi) - FScrollX,
    MulDiv(S.Padding.Top, ppi, 96));
end;

// ---- Word-boundary helpers ----
// Pure codepoint logic over FText (no widget/paint dependency) so they are
// unit-testable like TyScrollThumbRect. Indices are codepoint counts in
// 0..UTF8Length(FText). cp@k denotes UTF8Copy(FText, k+1, 1).

function TTyEdit.IsWordCodepoint(const CP: string): Boolean;
// A word codepoint is anything that is not whitespace and not ASCII punctuation.
// Whitespace: #32 (space), #9 (tab), U+00A0 (no-break space).
// ASCII punctuation: ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ ` { | } ~
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

function TTyEdit.NextWordBoundary(AIdx: Integer): Integer;
var
  i, Len: Integer;
begin
  Len := UTF8Length(FText);
  if AIdx < 0 then AIdx := 0;
  if AIdx > Len then AIdx := Len;
  i := AIdx;
  // Skip the current word run, then skip the following non-word run.
  while (i < Len) and IsWordCodepoint(UTF8Copy(FText, i + 1, 1)) do
    Inc(i);
  while (i < Len) and not IsWordCodepoint(UTF8Copy(FText, i + 1, 1)) do
    Inc(i);
  Result := i;
end;

function TTyEdit.PrevWordBoundary(AIdx: Integer): Integer;
var
  i, Len: Integer;
begin
  Len := UTF8Length(FText);
  if AIdx < 0 then AIdx := 0;
  if AIdx > Len then AIdx := Len;
  i := AIdx;
  // Skip the preceding non-word run, then skip the preceding word run.
  while (i > 0) and not IsWordCodepoint(UTF8Copy(FText, i, 1)) do
    Dec(i);
  while (i > 0) and IsWordCodepoint(UTF8Copy(FText, i, 1)) do
    Dec(i);
  Result := i;
end;

// ---- Mouse caret hit-test ----

function TTyEdit.CaretIndexAtX(AX: Integer): Integer;
var
  Ignored: Boolean;
begin
  Result := CaretIndexAtX(AX, Ignored);
end;

function TTyEdit.CaretIndexAtX(AX: Integer; out AAfterPrev: Boolean): Integer;
var
  APPI: Integer;
  Widths: TTyIntArray;
  StartX: Integer;
  RelX: Integer;
  Len, i, r, best, bestErr, err, ex: Integer;
  MidPoint: Integer;
begin
  APPI := Font.PixelsPerInch;
  StartX := TextStartX(APPI);
  // Account for horizontal scroll (add FScrollX) and alignment shift (subtract
  // AlignOffset) so clicks map to the right codepoint under center/right align.
  RelX := AX - StartX - AlignOffset(APPI) + FScrollX;
  Len := UTF8Length(FText);
  AAfterPrev := True;

  EnsureBidiLayout(APPI);
  if FBidiActive then
  begin
    { Which RUN the click landed in decides half the answer: at a direction boundary the
      codepoint index alone is two different places on screen, so a hit test that returned
      only the index would leave the caret to guess -- and a click on the far side of an
      embedded run would draw the caret on the near side. }
    r := FBidiOrder[0];
    for i := 0 to High(FBidiOrder) do
    begin
      r := FBidiOrder[i];
      if RelX < FBidiRuns[r].Right then Break;
    end;
    { Nearest boundary WITHIN that run. Scanned rather than bisected: a run's boundaries
      descend for right-to-left text, and a handful of comparisons is nothing next to the
      layout this is reading. }
    best := FBidiRuns[r].First;
    bestErr := MaxInt;
    for i := FBidiRuns[r].First to FBidiRuns[r].Last do
    begin
      ex := BidiRunEdgeX(r, i);
      err := Abs(ex - RelX);
      if err < bestErr then
      begin
        bestErr := err;
        best := i;
      end;
    end;
    { The caret belongs to the run the user aimed at: against the character after it at the
      run's logical start, against the one before it everywhere else. }
    AAfterPrev := best > FBidiRuns[r].First;
    Exit(best);
  end;

  if RelX <= 0 then
  begin
    Result := 0;
    Exit;
  end;

  Widths := MeasureCodepointWidths(APPI);

  if RelX >= Widths[Len] then
  begin
    Result := Len;
    Exit;
  end;

  // Walk codepoints: find the boundary nearest to RelX
  // Boundaries are at Widths[0]=0, Widths[1], ..., Widths[Len]
  // Boundary i is at Widths[i]; for each inter-boundary gap pick the nearest
  Result := 0;
  for i := 0 to Len - 1 do
  begin
    MidPoint := (Widths[i] + Widths[i + 1]) div 2;
    if RelX <= MidPoint then
    begin
      Result := i;
      Exit;
    end;
    Result := i + 1;
  end;
end;

// ---- Caret pixel position helper ----

function TTyEdit.CaretPixelXAt(ACaretIndex, APPI: Integer): Integer;
var
  Widths: TTyIntArray;
  Len: Integer;
begin
  Len := UTF8Length(FText);
  if ACaretIndex < 0 then ACaretIndex := 0;
  if ACaretIndex > Len then ACaretIndex := Len;
  Result := TextStartX(APPI);
  if Len = 0 then
    Exit;
  Widths := MeasureCodepointWidths(APPI);
  Result := Result + Widths[ACaretIndex];
end;

function TTyEdit.CaretDrawXAt(ACaretIndex, APPI: Integer; AAfterPrev: Boolean): Integer;
var
  Len: Integer;
begin
  { The gate first and the clamp afterwards, deliberately: CaretPixelXAt clamps for itself,
    so a left-to-right field must not pay a second UTF8Length walk of its own text on the
    way past. Measured: with the clamp in front, this cost ~380ns more per query than the
    call it delegates to; behind it, the difference is the Boolean test below. }
  EnsureBidiLayout(APPI);
  if not FBidiActive then
    Exit(CaretPixelXAt(ACaretIndex, APPI));   // the prefix sum, untouched
  Len := UTF8Length(FText);
  if ACaretIndex < 0 then ACaretIndex := 0;
  if ACaretIndex > Len then ACaretIndex := Len;
  if AAfterPrev then
    Result := TextStartX(APPI) + FBidiTrail[ACaretIndex]
  else
    Result := TextStartX(APPI) + FBidiLead[ACaretIndex];
end;

function TTyEdit.CaretDrawX(APPI: Integer): Integer;
begin
  Result := CaretDrawXAt(FCaret, APPI, FCaretAfterPrev);
end;

// ---- Clipboard implementation ----

function TTyEdit.ReadClipboardText: string;
begin
  Result := Clipboard.AsText;
end;

procedure TTyEdit.WriteClipboardText(const S: string);
begin
  Clipboard.AsText := S;
end;

procedure TTyEdit.CopyToClipboard;
begin
  if FPasswordChar <> '' then Exit;
  if not HasSelection then Exit;
  WriteClipboardText(SelText);
end;

procedure TTyEdit.CutToClipboard;
begin
  if FPasswordChar <> '' then Exit;
  if FReadOnly then begin CopyToClipboard; Exit; end;
  if not HasSelection then Exit;
  BeginUndoStep(uskCut);
  WriteClipboardText(SelText);
  FSuspendUndo := True;
  try
    DeleteSelection;
  finally
    FSuspendUndo := False;
  end;
  DoChange;  // composite op fires OnChange once (inner DeleteSelection was suppressed)
end;

procedure TTyEdit.PasteFromClipboard;
var
  S: string;
  i: Integer;
  Filtered: string;
  TextBefore: string;
begin
  if FReadOnly then Exit;
  S := ReadClipboardText;
  if S = '' then Exit;  // truly empty clipboard: full no-op
  TextBefore := FText;
  // Capture ONE undo step up front; suppress the inner DeleteSelection /
  // InjectStringAt steps so the whole paste reverts in a single undo.
  BeginUndoStep(uskPaste);
  FSuspendUndo := True;
  try
    // Strip CR and LF characters (single-line control)
    Filtered := '';
    for i := 1 to Length(S) do
      if (S[i] <> #13) and (S[i] <> #10) then
        Filtered := Filtered + S[i];
    // Even if Filtered='', the clipboard was non-empty so selection must be deleted.
    // (Don't Exit here: flow must reach the post-block DoChange so the deleted
    // selection still notifies once.)
    if HasSelection then
      DeleteSelection;
    if Filtered <> '' then
      InjectStringAt(Filtered);  // insert at caret
  finally
    FSuspendUndo := False;
  end;
  // Composite op fires OnChange exactly once, only if the text actually changed
  // (inner DeleteSelection/InjectStringAt were suppressed via FSuspendUndo).
  if FText <> TextBefore then
    DoChange;
end;

function TTyEdit.FilterInsert(const AText: string): string;
begin
  Result := AText;   // no filtering by default => plain edits are byte-identical
end;

procedure TTyEdit.InjectStringAt(const AStr: string);
var Before, After, Ins: string; InsLen, room, APPI: Integer;
begin
  if AStr = '' then Exit;
  if FReadOnly then Exit;
  // Subclass filter (numeric-only etc.); selection is already deleted by the caller (paste/IME),
  // so FText/FCaret here are the residual text + insert point the filter judges against.
  Ins := FilterInsert(AStr);
  if Ins = '' then Exit;
  // CharCase also applies to bulk insertion (paste / SelText write).
  Ins := ApplyCharCase(Ins);
  if FMaxLength > 0 then
  begin
    room := FMaxLength - UTF8Length(FText);
    if room <= 0 then Exit;
    if UTF8Length(Ins) > room then Ins := UTF8Copy(Ins, 1, room);
  end;
  BeginUndoStep(uskPaste);
  Before := UTF8Copy(FText, 1, FCaret);
  After  := UTF8Copy(FText, FCaret + 1, UTF8Length(FText) - FCaret);
  FText  := Before + Ins + After;
  InsLen := UTF8Length(Ins);
  FCaret := FCaret + InsLen;
  FSelAnchor := FCaret;
  InvalidateWidthCache;
  APPI := Font.PixelsPerInch;
  EnsureCaretVisible(APPI);
  ResetCaretBlink;
  Invalidate;
  DoChange;
end;

// ---- Mouse overrides ----

procedure TTyEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    if ssDouble in Shift then
    begin
      // Double-click: select all
      SelectAll;
      FMouseSelecting := False;
    end
    else
    begin
      // Single click: position caret, collapse selection
      BreakCoalescing;
      // The hit test reports which RUN was aimed at, and at a direction boundary that is
      // the difference between the caret appearing under the pointer and appearing at the
      // far end of an embedded run.
      FCaret := CaretIndexAtX(X, FCaretAfterPrev);
      FSelAnchor := FCaret;
      FMouseSelecting := True;
      EnsureCaretVisible(Font.PixelsPerInch);
      Invalidate;
    end;
    try
      if CanFocus then
        SetFocus;
    except
      // Ignore focus errors in headless/test environments
    end;
  end;
end;

procedure TTyEdit.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FMouseSelecting then
  begin
    // Drag-select: move caret, keep anchor fixed
    BreakCoalescing;
    FCaret := CaretIndexAtX(X, FCaretAfterPrev);
    EnsureCaretVisible(Font.PixelsPerInch);
    Invalidate;
  end;
end;

procedure TTyEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FMouseSelecting := False;
    { First left click of this focus visit selects everything (LCL customedit.inc:520-531).
      On MouseUp, not MouseDown, so a click-and-DRAG keeps the range the user swept out --
      selecting all on the press would throw that away before the drag even starts. }
    if FAutoSelect and not FAutoSelected and not HasSelection then
    begin
      SelectAll;
      if SelText = FText then FAutoSelected := True;
    end;
  end;
end;

procedure TTyEdit.InjectKey(const AChar: TUTF8Char);
var
  Before, After, TextBefore, Ch: string;
  APPI: Integer;
begin
  if FReadOnly then Exit;
  if (AChar = '') or (AChar[1] < #32) then Exit;
  // NumbersOnly: reject any non-digit input (LCL TEdit.NumbersOnly = digits 0-9).
  if FNumbersOnly and ((Length(AChar) <> 1) or (AChar[1] < '0') or (AChar[1] > '9')) then
    Exit;
  // CharCase: transform the inserted char on input.
  Ch := ApplyCharCase(AChar);
  // At cap with no selection: block before pushing an undo step (no state change).
  if (FMaxLength > 0) and (not HasSelection) and (UTF8Length(FText) >= FMaxLength) then Exit;
  TextBefore := FText;
  BeginUndoStep(uskTyping);
  // Replace selection if any (suppress the inner DeleteSelection's own step:
  // the snapshot we just took covers the whole replace-via-typing operation).
  // FSuspendUndo also suppresses the inner DeleteSelection's OnChange — this op
  // fires OnChange once at the end (selection-replace = a single change).
  if HasSelection then
  begin
    FSuspendUndo := True;
    try
      DeleteSelection;
    finally
      FSuspendUndo := False;
    end;
  end;
  // Subclass filter runs AFTER the selection is removed, so it sees the residual FText + FCaret
  // (the insert point) — a valid '-' / '.' typed to REPLACE a selection is therefore accepted.
  Ch := FilterInsert(Ch);
  if Ch = '' then
  begin
    if FText <> TextBefore then DoChange;   // the selection was deleted even though the key is rejected
    Exit;
  end;
  if (FMaxLength > 0) and (UTF8Length(FText) >= FMaxLength) then
  begin
    // At cap after deleting the selection: text changed (selection removed) even
    // though the new char can't be inserted — still notify once.
    if FText <> TextBefore then DoChange;
    Exit;
  end;
  Before := UTF8Copy(FText, 1, FCaret);
  After  := UTF8Copy(FText, FCaret + 1, UTF8Length(FText) - FCaret);
  FText  := Before + Ch + After;
  Inc(FCaret, UTF8Length(Ch));   // advance by CODEPOINTS, not 1: Qt/GTK IME can deliver a multi-codepoint commit
  FSelAnchor := FCaret;
  InvalidateWidthCache;
  APPI := Font.PixelsPerInch;
  EnsureCaretVisible(APPI);
  ResetCaretBlink;
  Invalidate;
  DoChange;
end;

procedure TTyEdit.InjectBackspace;
var
  Len: Integer;
  Before, After: string;
  APPI: Integer;
begin
  if FReadOnly then Exit;
  if HasSelection then
  begin
    DeleteSelection;
    Exit;
  end;
  if FCaret = 0 then Exit;
  BeginUndoStep(uskBackspace);
  Len    := UTF8Length(FText);
  Before := UTF8Copy(FText, 1, FCaret - 1);
  After  := UTF8Copy(FText, FCaret + 1, Len - FCaret);
  FText  := Before + After;
  Dec(FCaret);
  FSelAnchor := FCaret;
  InvalidateWidthCache;
  APPI := Font.PixelsPerInch;
  ClampScrollX(APPI);
  EnsureCaretVisible(APPI);
  ResetCaretBlink;
  Invalidate;
  DoChange;
end;

procedure TTyEdit.InjectDelete;
var
  Len: Integer;
  Before, After: string;
  APPI: Integer;
begin
  if FReadOnly then Exit;
  if HasSelection then
  begin
    DeleteSelection;
    Exit;
  end;
  Len := UTF8Length(FText);
  if FCaret >= Len then Exit;  // no-op at end
  BeginUndoStep(uskDelete);
  Before := UTF8Copy(FText, 1, FCaret);
  After  := UTF8Copy(FText, FCaret + 2, Len - FCaret - 1);
  FText  := Before + After;
  // caret stays; collapse anchor
  FSelAnchor := FCaret;
  InvalidateWidthCache;
  APPI := Font.PixelsPerInch;
  ClampScrollX(APPI);
  EnsureCaretVisible(APPI);
  ResetCaretBlink;
  Invalidate;
  DoChange;
end;

procedure TTyEdit.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  imeFull: string;
begin
  if not Enabled then Exit;
  { GTK3: the backend truncated this commit into a TUTF8Char on its way here. The whole
    string is still pending in the widgetset, so take it and insert THAT instead. Returns ''
    on every other widgetset and whenever nothing was truncated, so the normal path below is
    untouched. }
  imeFull := TyGtkTakeImeCommit(UTF8Key);
  if imeFull <> '' then
  begin
    HandleImeCommit(imeFull);
    UTF8Key := '';   // consumed: stop the truncated copy being inserted as well
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
  InjectKey(UTF8Key);
end;

{ Insert a FULL input-method commit (Qt6 path). LCL's UTF8KeyPress caps a commit at TUTF8Char
  (String[7], ~2 CJK chars); our Qt event filter (tyControls.QtWS) bypasses that and calls this with
  the whole commitString. Mirrors Paste: one undo step, replace any selection, strip CR/LF, fire
  OnChange once. }
procedure TTyEdit.HandleImeCommit(const ACommitUtf8: string);
var
  TextBefore, Filtered: string;
  i: Integer;
begin
  if FReadOnly or not Enabled then Exit;
  if ACommitUtf8 = '' then Exit;
  TextBefore := FText;
  BeginUndoStep(uskTyping);
  FSuspendUndo := True;
  try
    Filtered := '';
    for i := 1 to Length(ACommitUtf8) do
      if (ACommitUtf8[i] <> #13) and (ACommitUtf8[i] <> #10) then
        // NumbersOnly: keep only ASCII digits (CJK/other bytes are >= #128 -> dropped), matching the
        // InjectKey path so an IME commit can't bypass the digit restriction.
        if (not FNumbersOnly) or ((ACommitUtf8[i] >= '0') and (ACommitUtf8[i] <= '9')) then
          Filtered := Filtered + ACommitUtf8[i];
    if HasSelection then DeleteSelection;
    if Filtered <> '' then InjectStringAt(Filtered);
  finally
    FSuspendUndo := False;
  end;
  if FText <> TextBefore then DoChange;
end;

function TTyEdit.GetImeCaretRect: TRect;
begin
  // Empty rect when not focused/painted -> the IME hook declines and Qt's default position stands.
  if (not HandleAllocated) or (not Focused) then
    Exit(Rect(0, 0, 0, 0));
  Result := FImeCaretRect;
end;

procedure TTyEdit.InitializeWnd;
begin
  inherited InitializeWnd;
  // Qt6: intercept the native input method so (1) a multi-char CJK commit isn't truncated to ~2 chars
  // by LCL's TUTF8Char path and (2) the candidate window follows the caret. No-op on Win32/GTK2/Cocoa.
  TyQtUninstallIme(FImeHook);   // defensive: drop any prior hook if the handle is recreated
  FImeHook := TyQtInstallIme(Self, @HandleImeCommit, @GetImeCaretRect);
  if FImeHook = nil then        // GTK2: stock LCL delivers no IME — attach our own GtkIMContext
    FImeHook := TyGtkInstallIme(Self, @HandleImeCommit, @GetImeCaretRect);
end;

procedure TTyEdit.DestroyWnd;
begin
  TyQtUninstallIme(FImeHook);
  inherited DestroyWnd;
end;

procedure TTyEdit.KeyDown(var Key: Word; Shift: TShiftState);
var
  Len: Integer;
  Extending: Boolean;
  HasModifier: Boolean;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  // Any key activity while focused makes the caret solid for one blink cycle.
  ResetCaretBlink;
  Len := UTF8Length(FText);

  { Enter commits the field. The docs said so; the code had no VK_RETURN branch and
    the unit contained no EditingDone call at all, so the one keystroke everybody uses
    to say "done with this box" did nothing -- and OnEditingDone only ever ran on focus
    loss. TTyMemo, where Enter means a newline, already handles VK_RETURN itself.
    Key is NOT swallowed: a form's Default button must still see it. }
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    EditingDone;
    Exit;
  end;

  // Ctrl+A / Meta+A
  if (Key = VK_A) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
  begin
    SelectAll;
    Key := 0;
    Exit;
  end;

  // Ctrl+C / Meta+C
  if (Key = VK_C) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
  begin
    CopyToClipboard;
    Key := 0;
    Exit;
  end;

  // Ctrl+X / Meta+X
  if (Key = VK_X) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
  begin
    CutToClipboard;
    Key := 0;
    Exit;
  end;

  // Ctrl+V / Meta+V
  if (Key = VK_V) and ((ssCtrl in Shift) or (ssMeta in Shift)) then
  begin
    PasteFromClipboard;
    Key := 0;
    Exit;
  end;

  // Redo: Ctrl/Cmd+Shift+Z OR Ctrl+Y. Check redo BEFORE undo so the Shift+Z
  // variant is not swallowed by the plain Ctrl+Z branch below.
  if ( (Key = VK_Z) and ((ssCtrl in Shift) or (ssMeta in Shift)) and (ssShift in Shift) )
     or ( (Key = VK_Y) and ((ssCtrl in Shift) or (ssMeta in Shift)) ) then
  begin
    Redo;
    Key := 0;
    Exit;
  end;

  // Undo: Ctrl/Cmd+Z (no Shift)
  if (Key = VK_Z) and ((ssCtrl in Shift) or (ssMeta in Shift)) and not (ssShift in Shift) then
  begin
    Undo;
    Key := 0;
    Exit;
  end;

  Extending := ssShift in Shift;
  // Modifier combos (Ctrl/Alt/Meta without Shift) on navigation keys must fall through
  HasModifier := (ssCtrl in Shift) or (ssAlt in Shift) or (ssMeta in Shift);

  case Key of
    VK_BACK:
    begin
      // Selection present -> delete selection only (no word-delete).
      // Else Ctrl/Alt -> delete previous word; otherwise delete one cp.
      if HasSelection then
        InjectBackspace
      else if (ssCtrl in Shift) or (ssAlt in Shift) then
        DeleteWordBackward
      else
        InjectBackspace;
      Key := 0;
    end;
    VK_DELETE:
    begin
      if HasSelection then
        InjectDelete
      else if (ssCtrl in Shift) or (ssAlt in Shift) then
        DeleteWordForward
      else
        InjectDelete;
      Key := 0;
    end;
    VK_LEFT:
    begin
      BreakCoalescing;  // any caret nav ends a typing-coalesce run
      if (ssAlt in Shift) or (ssCtrl in Shift) then
      begin
        // Word-wise left: Alt+Left (macOS Option) or Ctrl+Left (Win/Linux).
        // Extending keeps the anchor and moves only the caret to the previous
        // word boundary; otherwise collapse selection. (Cmd/ssMeta falls through.)
        { Word-wise movement stays LOGICAL: a word is a run of codepoints, not a run of
          glyphs, and there is no visual definition of "the previous word" that survives an
          embedded run. Only the affinity is parked. }
        if Extending then
          FCaret := PrevWordBoundary(FCaret)
        else
        begin
          FCaret := PrevWordBoundary(FCaret);
          FSelAnchor := FCaret;
        end;
        DefaultCaretAffinity;
        EnsureCaretVisible(Font.PixelsPerInch);
        Invalidate;
        Key := 0;
      end
      else if HasModifier and not Extending then
        // remaining modifier+arrow (e.g. Cmd/Meta): do NOT consume; fall through
      else
      begin
        { In TEXT, Left and Right are VISUAL movement -- one glyph in the direction pressed,
          whatever that does to the codepoint index underneath. (In lists, grids, tabs and
          menus the same two keys are LAYOUT direction and belong to the mirroring layer,
          which is not built: plans/2026-08-04-rtl-mirroring-scope.md 6.3 item 4.)
          For text with no right-to-left run in it MoveCaretVisual is Dec(FCaret) and the
          bounds test that used to guard it, unchanged. }
        if Extending then
        begin
          // Shift held: move caret left (anchor stays)
          if MoveCaretVisual(-1, Font.PixelsPerInch) then
          begin
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end;
        end
        else
        begin
          { No shift: if selection exists collapse to its LOGICAL start -- a selection is a
            logical range and collapsing it is not a movement through glyphs -- else move. }
          if HasSelection then
          begin
            FCaret := SelStart;
            FSelAnchor := FCaret;
            DefaultCaretAffinity;
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end
          else if MoveCaretVisual(-1, Font.PixelsPerInch) then
          begin
            FSelAnchor := FCaret;
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end;
        end;
        Key := 0;
      end;
    end;
    VK_RIGHT:
    begin
      BreakCoalescing;  // any caret nav ends a typing-coalesce run
      if (ssAlt in Shift) or (ssCtrl in Shift) then
      begin
        // Word-wise right: Alt+Right (macOS Option) or Ctrl+Right (Win/Linux).
        // Extending keeps the anchor and moves only the caret to the next word
        // boundary; otherwise collapse selection. (Cmd/ssMeta falls through.)
        // Logical, like its mirror in the VK_LEFT branch above.
        if Extending then
          FCaret := NextWordBoundary(FCaret)
        else
        begin
          FCaret := NextWordBoundary(FCaret);
          FSelAnchor := FCaret;
        end;
        DefaultCaretAffinity;
        EnsureCaretVisible(Font.PixelsPerInch);
        Invalidate;
        Key := 0;
      end
      else if HasModifier and not Extending then
        // remaining modifier+arrow (e.g. Cmd/Meta): do NOT consume; fall through
      else
      begin
        // Visual movement; see the VK_LEFT branch for the whole argument.
        if Extending then
        begin
          // Shift held: move caret right (anchor stays)
          if MoveCaretVisual(1, Font.PixelsPerInch) then
          begin
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end;
        end
        else
        begin
          // No shift: if selection exists collapse to its LOGICAL end, else move
          if HasSelection then
          begin
            FCaret := SelStart + SelLength;
            FSelAnchor := FCaret;
            DefaultCaretAffinity;
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end
          else if MoveCaretVisual(1, Font.PixelsPerInch) then
          begin
            FSelAnchor := FCaret;
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end;
        end;
        Key := 0;
      end;
    end;
    VK_HOME:
    begin
      BreakCoalescing;  // any caret nav ends a typing-coalesce run
      if HasModifier and not Extending then
        // modifier+home: fall through
      else
      begin
        { Home and End stay LOGICAL -- codepoint 0 and the last codepoint, wherever the
          bidirectional algorithm happened to draw them (6.3 item 3 of the mirroring scope
          note). Only the affinity is visual: the caret at the start of the text stands
          against the character AFTER it, which is what makes it land on that glyph's
          leading edge rather than on the far end of whatever run reaches index 0. }
        FCaretAfterPrev := False;
        if Extending then
        begin
          FCaret := 0;
          EnsureCaretVisible(Font.PixelsPerInch);
          Invalidate;
        end
        else
        begin
          FCaret := 0;
          FSelAnchor := 0;
          EnsureCaretVisible(Font.PixelsPerInch);
          Invalidate;
        end;
        Key := 0;
      end;
    end;
    VK_END:
    begin
      BreakCoalescing;  // any caret nav ends a typing-coalesce run
      if HasModifier and not Extending then
        // modifier+end: fall through
      else
      begin
        // Logical, like Home; the caret at the end of the text stands after the last one.
        DefaultCaretAffinity;
        if Extending then
        begin
          FCaret := Len;
          EnsureCaretVisible(Font.PixelsPerInch);
          Invalidate;
        end
        else
        begin
          FCaret := Len;
          FSelAnchor := Len;
          EnsureCaretVisible(Font.PixelsPerInch);
          Invalidate;
        end;
        Key := 0;
      end;
    end;
  end;
end;

procedure TTyEdit.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, SelStyle: TTyStyleSet;
  ContentRect, BandRect, CaretRect: TRect;
  Widths: TTyIntArray;
  X1, X2, CaretX, AOff: Integer;
  RunIdx, SelA, SelB, Swap: Integer;
  CaretH, CaretMidY: Integer;
  BandFill: TTyFill;
  BandColor: TTyColor;
  EffSize: Integer;
  TextClipRight: Integer;
  HintColor: TTyColor;
  Reserve, ContentFullRight: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    EffSize := EffectiveFontSize(S);
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, ContentRect, S);
    // Inset content by all four padding sides
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    // Reserve a trailing-widget zone on the right (Reserve=0 for a plain edit -> unchanged).
    Reserve := RightReserve(APPI);
    ContentFullRight := ContentRect.Right;
    ContentRect.Right := ContentRect.Right - Reserve;

    // Horizontal alignment offset: shifts the text-start / caret / selection
    // band right by AOff under taCenter/taRightJustify (0 when left-aligned or
    // when the text overflows and scroll governs). DrawText stays left-justified
    // so this single offset keeps glyphs, caret and band geometry in lock-step.
    AOff := AlignOffset(APPI);

    // 1. Selection band (drawn before text so glyphs appear on top)
    { HideSelection (TEdit's default True): no band while unfocused -- the selection itself is
      untouched, only its paint. Gated on the same Focused the caret below uses, so the two can
      never disagree about which edit on the form is the live one. }
    if HasSelection and (Focused or not FHideSelection) then
    begin
      // Band color comes from the TyTextSelection typeKey (accent-tinted via
      // --selection = alpha(accent,0.30)), keeping it theme-overridable and
      // matching selected list rows.
      SelStyle := ActiveController.Model.ResolveStyle('TyTextSelection', '', []);
      BandColor := SelStyle.Background.Color;
      BandFill := Default(TTyFill);
      BandFill.Kind := tfkSolid;
      BandFill.Color := BandColor;

      EnsureBidiLayout(APPI);
      if FBidiActive then
      begin
        { A selection is a LOGICAL range, and a logical range that crosses a direction
          boundary is not one rectangle on screen. Selecting "ab" plus the first letter of
          an embedded Hebrew word highlights the "ab" and that letter -- with the SECOND
          Hebrew letter, which is not selected, drawn in the gap between them. One band
          spanning the lot would be telling the user they had selected it.
          So: one band per run, over the part of the run the selection actually covers. }
        for RunIdx := 0 to High(FBidiRuns) do
        begin
          SelA := SelStart;
          if SelA < FBidiRuns[RunIdx].First then SelA := FBidiRuns[RunIdx].First;
          SelB := SelStart + SelLength;
          if SelB > FBidiRuns[RunIdx].Last then SelB := FBidiRuns[RunIdx].Last;
          if SelA >= SelB then Continue;
          X1 := BidiRunEdgeX(RunIdx, SelA);
          X2 := BidiRunEdgeX(RunIdx, SelB);
          // Inside a right-to-left run the later codepoint is the SMALLER x.
          if X2 < X1 then begin Swap := X1; X1 := X2; X2 := Swap; end;
          X1 := ContentRect.Left + AOff + X1 - FScrollX;
          X2 := ContentRect.Left + AOff + X2 - FScrollX;
          if X1 < ContentRect.Left then X1 := ContentRect.Left;
          if X2 > ContentRect.Right then X2 := ContentRect.Right;
          if X1 < X2 then
            P.FillBackground(Rect(X1, ContentRect.Top, X2, ContentRect.Bottom), BandFill, 0);
        end;
      end
      else
      begin
        Widths := MeasureCodepointWidths(APPI);
        // Apply scroll + alignment offset: shift band left by FScrollX, right by AOff
        X1 := ContentRect.Left + AOff + Widths[SelStart] - FScrollX;
        X2 := ContentRect.Left + AOff + Widths[SelStart + SelLength] - FScrollX;
        // Clamp to content rect
        if X1 < ContentRect.Left then X1 := ContentRect.Left;
        if X2 > ContentRect.Right then X2 := ContentRect.Right;
        if X1 < X2 then
        begin
          BandRect := Rect(X1, ContentRect.Top, X2, ContentRect.Bottom);
          P.FillBackground(BandRect, BandFill, 0);
        end;
      end;
    end;

    // 2. Draw text (on top of selection band) — use EffSize to match measurement
    // Shift the text rect left by FScrollX so the content scrolls; Right is
    // clamped just inside the border so glyphs (incl. their antialias fringe)
    // never paint over the right padding or border strip.
    // When no text is entered and a hint is set, draw the hint in a dim color.
    if (FText = '') and (FTextHint <> '') then
    begin
      HintColor := ActiveController.Model.ResolveStyle('TyTextHint', '', []).TextColor;
      P.DrawText(ContentRect, FTextHint, S.FontName, EffSize, S.FontWeight,
        HintColor, taLeftJustify, tlCenter, True);
    end
    else
    begin
      if FScrollX > 0 then
      begin
        if Length(Widths) = 0 then
          Widths := MeasureCodepointWidths(APPI);
        TextClipRight := ContentRect.Right;
        if (tpBorderColor in S.Present) and (S.BorderWidth > 0) then
          TextClipRight := TextClipRight - P.Scale(S.BorderWidth);
        P.DrawText(
          Rect(ContentRect.Left - FScrollX, ContentRect.Top,
               TextClipRight,
               ContentRect.Bottom),
          DisplayText, S.FontName, EffSize, S.FontWeight,
          S.TextColor, taLeftJustify, tlCenter, False);  // clip+scroll, never ellipsize
      end
      else
        P.DrawText(
          Rect(ContentRect.Left + AOff, ContentRect.Top,
               ContentRect.Right, ContentRect.Bottom),
          DisplayText, S.FontName, EffSize, S.FontWeight,
          S.TextColor, taLeftJustify, tlCenter, False);  // clip+scroll, never ellipsize
    end;

    // 3. Caret (only when focused, no selection, and blink-visible)
    if Focused and not HasSelection and FCaretVisible then
    begin
      // Apply scroll + alignment offset to caret position. CaretDrawX is the prefix sum for
      // left-to-right text and the reordered position otherwise, so this one line is both.
      CaretX := CaretDrawX(APPI) + AOff - FScrollX;
      // Caret height tracks the TEXT (font line height), vertically centered on the content
      // rect — NOT the box height. The text is drawn tlCenter in ContentRect, so its centre is
      // ContentRect's centre; sizing the caret to the measured line height keeps it the same
      // height as the glyphs whether the box is taller OR shorter than the text (e.g. the tree's
      // inline-edit overlay, whose box is the row height, leaves ContentRect shorter than the font
      // and previously yielded a stunted half-height caret).
      CaretH := P.MeasureText('Ag', S.FontName, EffSize, S.FontWeight).cy;
      CaretMidY := (ContentRect.Top + ContentRect.Bottom) div 2;
      CaretRect := Rect(CaretX, CaretMidY - CaretH div 2,
        CaretX + P.Scale(1), CaretMidY - CaretH div 2 + CaretH);
      P.FillBackground(CaretRect, Default(TTyFill), 0);
      P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
      if not EqualRect(FImeCaretRect, CaretRect) then
      begin
        FImeCaretRect := CaretRect;   // cache for the IME candidate-window query
        TyQtImeUpdateCaret;           // Qt6: re-query so the candidate follows the caret (no-op elsewhere)
      end;
    end;

    // 4. Trailing widget (URL open button, combo drop arrow, …) in the reserved right zone.
    if Reserve > 0 then
      PaintTrailing(P, Rect(ContentRect.Right, ContentRect.Top, ContentFullRight, ContentRect.Bottom), S);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyEdit.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
