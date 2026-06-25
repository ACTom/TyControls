unit tyControls.Edit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8, Clipbrd,
  ExtCtrls, StdCtrls,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.UndoStack,
  tyControls.Animation, tyControls.QtWS, tyControls.GtkWS;
type
  TTyIntArray = array of Integer;

  TTyEdit = class(TTyCustomControl)
  private
    FText: string;
    FCaret: Integer;      // codepoint index 0..UTF8Length(FText)
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
    // Lazy measuring bitmap (freed in Destroy)
    FMeasureBmp: TBGRABitmap;
    // Undo/redo infrastructure
    FUndoStack: TTyUndoStack;
    FSuspendUndo: Boolean;   // true while a composite op pushes its own step
    FReadOnly: Boolean;
    FMaxLength: Integer;
    FPasswordChar: string;
    FTextHint: string;
    FAlignment: TAlignment;
    FCharCase: TEditCharCase;
    FNumbersOnly: Boolean;
    FOnChange: TNotifyEvent;
    FImeHook: TObject;    // Qt-only IME commit interceptor (nil off Qt); see tyControls.QtWS
    FImeCaretRect: TRect; // caret rect (client device px) cached each paint; fed to the Qt IME query
    // Insert a full IME commit string (Qt: the un-truncated QInputMethodEvent.commitString).
    procedure HandleImeCommit(const ACommitUtf8: string);
    // Caret rect (client device px) for the Qt IME candidate window; empty when not focused.
    function GetImeCaretRect: TRect;
    procedure SetText(const AValue: string);
    procedure SetTextHint(const AValue: string);
    procedure SetCaretPos(AValue: Integer);
    procedure SetReadOnly(const AValue: Boolean);
    procedure SetMaxLength(const AValue: Integer);
    procedure SetPasswordChar(const AValue: string);
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
    // Insert a raw UTF-8 string at the current caret position
    procedure InjectStringAt(const AStr: string);
    // Text measurement helper (moved to protected so subclasses can expose it)
    procedure InvalidateWidthCache;
    function EffectiveFontSize(const S: TTyStyleSet): Integer;
    function MeasureCodepointWidths(APPI: Integer): TTyIntArray;
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
    // Text measurement helper (protected so headless access subclasses can call it)
    function TextStartX(APPI: Integer): Integer;
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
    procedure InjectBackspace;
    procedure InjectDelete;
    // Selection API
    function HasSelection: Boolean;
    procedure SelectAll;
    procedure ClearSelection;
    // Mouse hit test
    function CaretIndexAtX(AX: Integer): Integer;
    // Clipboard API
    procedure CopyToClipboard;
    procedure CutToClipboard;
    procedure PasteFromClipboard;
    // Rendering helpers (public for headless tests)
    function CaretPixelXAt(ACaretIndex, APPI: Integer): Integer;
    // Undo/redo API
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
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
  published
    property Text: string read FText write SetText;
    property ReadOnly: Boolean read FReadOnly write SetReadOnly default False;
    property MaxLength: Integer read FMaxLength write SetMaxLength default 0;
    property PasswordChar: string read FPasswordChar write SetPasswordChar;
    property TextHint: string read FTextHint write SetTextHint;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    property CharCase: TEditCharCase read FCharCase write SetCharCase default ecNormal;
    property NumbersOnly: Boolean read FNumbersOnly write FNumbersOnly default False;
    property Enabled;
    property Font;
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
  Height := 28;
  FText := '';
  FCaret := 0;
  FSelAnchor := 0;
  FScrollX := 0;
  FWidthCacheValid := False;
  FMeasureBmp := nil;
  FUndoStack := TTyUndoStack.Create;
  FSuspendUndo := False;
  FCaretVisible := True;       // solid caret until a real timer toggles it
  FBlinkTimer := nil;          // lazy: created only when HandleAllocated
  FBlinkElapsedMs := 0;
end;

destructor TTyEdit.Destroy;
begin
  // Free the timer first so its OnTimer callback can never fire mid-teardown
  // (mirrors TTyButton.Destroy). It is owned by Self but we free it explicitly.
  FreeAndNil(FBlinkTimer);
  TyQtUninstallIme(FImeHook);   // in case DestroyWnd never ran (Qt-only; no-op elsewhere)
  FUndoStack.Free;
  FMeasureBmp.Free;
  inherited Destroy;
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
  if Assigned(FOnChange) then
    FOnChange(Self);
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
  EnsureCaretVisible(Font.PixelsPerInch);
  ResetCaretBlink;
  Invalidate;
end;

procedure TTyEdit.ClearSelection;
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

procedure TTyEdit.SetText(const AValue: string);
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
  DoChange;
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
begin
  if UTF8Length(AValue) > 1 then
    FPasswordChar := UTF8Copy(AValue, 1, 1)
  else
    FPasswordChar := AValue;
  InvalidateWidthCache;
  Invalidate;
end;

procedure TTyEdit.SetTextHint(const AValue: string);
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
end;

function TTyEdit.EffectiveFontSize(const S: TTyStyleSet): Integer;
begin
  if S.FontSize > 0 then
    Result := S.FontSize
  else
    Result := 12;  // fallback 12pt
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
  RightPad := MulDiv(S.Padding.Right, APPI, 96);
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
  RightPad := MulDiv(S.Padding.Right, APPI, 96);
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
  RightPad := MulDiv(S.Padding.Right, APPI, 96);
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

  // Caret position in control coordinates (before scroll adjustment)
  CaretPx := StartX + Widths[FCaret];

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
    CaretPixelXAt(FCaret, ppi) + AlignOffset(ppi) - FScrollX,
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
  APPI: Integer;
  Widths: TTyIntArray;
  StartX: Integer;
  RelX: Integer;
  Len, i: Integer;
  MidPoint: Integer;
begin
  APPI := Font.PixelsPerInch;
  StartX := TextStartX(APPI);
  // Account for horizontal scroll (add FScrollX) and alignment shift (subtract
  // AlignOffset) so clicks map to the right codepoint under center/right align.
  RelX := AX - StartX - AlignOffset(APPI) + FScrollX;
  Len := UTF8Length(FText);

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

procedure TTyEdit.InjectStringAt(const AStr: string);
var Before, After, Ins: string; InsLen, room, APPI: Integer;
begin
  if AStr = '' then Exit;
  if FReadOnly then Exit;
  // CharCase also applies to bulk insertion (paste / SelText write).
  Ins := ApplyCharCase(AStr);
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
      FCaret := CaretIndexAtX(X);
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
    FCaret := CaretIndexAtX(X);
    EnsureCaretVisible(Font.PixelsPerInch);
    Invalidate;
  end;
end;

procedure TTyEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
    FMouseSelecting := False;
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
begin
  if not Enabled then Exit;
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
        if Extending then
          FCaret := PrevWordBoundary(FCaret)
        else
        begin
          FCaret := PrevWordBoundary(FCaret);
          FSelAnchor := FCaret;
        end;
        EnsureCaretVisible(Font.PixelsPerInch);
        Invalidate;
        Key := 0;
      end
      else if HasModifier and not Extending then
        // remaining modifier+arrow (e.g. Cmd/Meta): do NOT consume; fall through
      else
      begin
        if Extending then
        begin
          // Shift held: move caret left (anchor stays)
          if FCaret > 0 then
          begin
            Dec(FCaret);
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end;
        end
        else
        begin
          // No shift: if selection exists collapse to left edge, else move
          if HasSelection then
          begin
            FCaret := SelStart;
            FSelAnchor := FCaret;
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end
          else if FCaret > 0 then
          begin
            Dec(FCaret);
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
        if Extending then
          FCaret := NextWordBoundary(FCaret)
        else
        begin
          FCaret := NextWordBoundary(FCaret);
          FSelAnchor := FCaret;
        end;
        EnsureCaretVisible(Font.PixelsPerInch);
        Invalidate;
        Key := 0;
      end
      else if HasModifier and not Extending then
        // remaining modifier+arrow (e.g. Cmd/Meta): do NOT consume; fall through
      else
      begin
        if Extending then
        begin
          // Shift held: move caret right (anchor stays)
          if FCaret < Len then
          begin
            Inc(FCaret);
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end;
        end
        else
        begin
          // No shift: if selection exists collapse to right edge, else move
          if HasSelection then
          begin
            FCaret := SelStart + SelLength;
            FSelAnchor := FCaret;
            EnsureCaretVisible(Font.PixelsPerInch);
            Invalidate;
          end
          else if FCaret < Len then
          begin
            Inc(FCaret);
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
  BandFill: TTyFill;
  BandColor: TTyColor;
  EffSize: Integer;
  TextClipRight: Integer;
  HintColor: TTyColor;
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

    // Horizontal alignment offset: shifts the text-start / caret / selection
    // band right by AOff under taCenter/taRightJustify (0 when left-aligned or
    // when the text overflows and scroll governs). DrawText stays left-justified
    // so this single offset keeps glyphs, caret and band geometry in lock-step.
    AOff := AlignOffset(APPI);

    // 1. Selection band (drawn before text so glyphs appear on top)
    if HasSelection then
    begin
      // Band color comes from the TyTextSelection typeKey (accent-tinted via
      // --selection = alpha(accent,0.30)), keeping it theme-overridable and
      // matching selected list rows.
      SelStyle := ActiveController.Model.ResolveStyle('TyTextSelection', '', []);

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
        BandColor := SelStyle.Background.Color;
        BandFill := Default(TTyFill);
        BandFill.Kind := tfkSolid;
        BandFill.Color := BandColor;
        P.FillBackground(BandRect, BandFill, 0);
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
      if Length(Widths) = 0 then
        Widths := MeasureCodepointWidths(APPI);
      // Apply scroll + alignment offset to caret position
      CaretX := ContentRect.Left + AOff + Widths[FCaret] - FScrollX;
      CaretRect := Rect(CaretX, ContentRect.Top + P.Scale(2),
        CaretX + P.Scale(1), ContentRect.Bottom - P.Scale(2));
      P.FillBackground(CaretRect, Default(TTyFill), 0);
      P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
      FImeCaretRect := CaretRect;   // cache for the Qt IME candidate-window query
    end;

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
