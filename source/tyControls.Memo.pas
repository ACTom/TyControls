unit tyControls.Memo;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LazUTF8, Clipbrd,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ScrollBar;
type
  // Cumulative-prefix pixel widths, length = codepoints+1 (shared name with Edit).
  TTyIntArray = array of Integer;

  TTyMemo = class(TTyCustomControl)
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
    // 2D selection anchor (codepoint index per line). No selection <=> anchor
    // equals the caret. Mirrors TTyEdit.FSelAnchor generalised to (line,col).
    FSelAnchorLine: Integer;
    FSelAnchorCol: Integer;
    // Index of the first logical line painted (top of the visible window).
    FTopLine: Integer;
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
    function GetLines: TStrings;
    procedure SetLines(AValue: TStrings);
    function EffectiveFontSize(const S: TTyStyleSet): Integer;
    function TextStartX(APPI: Integer): Integer;
    // Codepoint length of a logical line index (0 for the synthetic empty line).
    function LineLen(ALineIndex: Integer): Integer;
    // Fire OnChange (after a model mutation).
    procedure DoChange;
    // Shared post-mutation routine: clamp caret, keep its line visible, repaint,
    // and fire OnChange. (UpdateScrollBar lands with the real scrollbar in T4.)
    procedure AfterEdit(APPI: Integer);
    // Shared post-move routine for pure caret motion: clamp, keep visible, repaint.
    // Never fires OnChange.
    procedure AfterCaretMove(APPI: Integer);
    // Scrollbar OnChange handler -> SetTopLine (guarded against ping-pong).
    procedure ScrollBarChange(Sender: TObject);
    // --- Model mutators (pure UTF8 splice; no key/paint dependency) ---
    procedure DoInsertText(const AStr: string);
    procedure DoSplitLine;
    procedure DoBackspace;
    procedure DoDelete;
    // --- Word-delete mutators (pure UTF8 splice; route through AfterEdit at the
    // call site, like DoBackspace/DoDelete). At a line boundary they fall back to
    // the cross-line merge (DoBackspace / DoDelete). ---
    procedure DeleteWordBackward;
    procedure DeleteWordForward;
  protected
    function GetStyleTypeKey: string; override;
    // Remove the current selection (SelStart..SelEnd): single-line splice, or
    // multi-line merge of first-line head + last-line tail with middle lines
    // dropped. Caret -> SelStart; anchor collapses. Pure mutator — callers route
    // through AfterEdit (matching the Memo's mutator/AfterEdit split). Protected
    // so headless probe subclasses can exercise it directly (like HasSelection).
    procedure DeleteSelection;
    // --- Pure per-line geometry helpers (headless-testable; no paint state) ---
    // Floored at 1 so vertical layout never divides by zero.
    function LineHeight(APPI: Integer): Integer;
    // Always >= 1 (an empty model is one logical, visually present line).
    function LineCountLogical: Integer;
    // Clamp the caret into the current model (line then col).
    procedure ClampCaret;
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
    // tail + whole interior lines + last-line head, joined by LineEnding.
    function SelText: string;
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
    // Highest valid FTopLine = LineCountLogical - VisibleRows, floored 0.
    function MaxTopLine: Integer;
    // Read accessor for FTopLine (tests / property).
    function TopLine: Integer;
    // Top-of-window setter with clamp + guarded scrollbar sync + repaint.
    procedure SetTopLine(AValue: Integer);
    // Create/update/hide the embedded vertical scrollbar (verbatim from ListBox,
    // FItems.Count -> LineCountLogical).
    procedure UpdateScrollBar;
    // Scroll FTopLine so the caret line sits inside the visible window.
    procedure EnsureCaretLineVisible(APPI: Integer);
    // Paint into ACanvas at ARect (RenderTo convention: draw local Rect(0,0,W,H),
    // EndPaint blits at ARect origin). APPI scales padding/line metrics.
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    // Input handlers. Both early-Exit when not Enabled (v1.5 policy); when
    // disabled, KeyDown does NOT consume Key so navigation falls through.
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    // Left-click caret hit-test: Y -> logical line, X -> codepoint column. Early
    // Exit when not Enabled (v1.5 policy). try/except SetFocus like Edit/ListBox.
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
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
  published
    property Lines: TStrings read GetLines write SetLines;
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

constructor TTyMemo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  FLines := TStringList.Create;
  FCaretLine := 0;
  FCaretCol := 0;
  FDesiredCol := 0;
  FSelAnchorLine := 0;
  FSelAnchorCol := 0;
  FTopLine := 0;
  FScrollBar := nil;
  FSyncingScroll := False;
  FMeasureBmp := nil;
  FForceFocused := False;
  Width := 200;
  Height := 120;
end;

destructor TTyMemo.Destroy;
begin
  FMeasureBmp.Free;
  FLines.Free;
  inherited Destroy;
end;

function TTyMemo.GetStyleTypeKey: string;
begin
  Result := 'TyMemo';
end;

function TTyMemo.GetLines: TStrings;
begin
  Result := FLines;
end;

procedure TTyMemo.SetLines(AValue: TStrings);
begin
  FLines.Assign(AValue);
  ClampCaret;
  // Clamp the window and refresh the scrollbar in case the line count changed.
  if FTopLine > MaxTopLine then FTopLine := MaxTopLine;
  if FTopLine < 0 then FTopLine := 0;
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
  Invalidate;
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

function TTyMemo.SelText: string;
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
end;

procedure TTyMemo.ClearSelection;
begin
  FSelAnchorLine := FCaretLine;
  FSelAnchorCol := FCaretCol;
  Invalidate;
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
  VR, MaxTop: Integer;
begin
  VR := VisibleRows;
  // Scroll up so the caret line is the new top.
  if FCaretLine < FTopLine then
    FTopLine := FCaretLine;
  // Scroll down so the caret line is the last fully visible line: caret in
  // [FTopLine, FTopLine+VR).
  if FCaretLine > FTopLine + VR - 1 then
    FTopLine := FCaretLine - VR + 1;
  // Never scroll past the last valid window / below 0.
  MaxTop := MaxTopLine;
  if FTopLine > MaxTop then FTopLine := MaxTop;
  if FTopLine < 0 then FTopLine := 0;
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

function TTyMemo.MaxTopLine: Integer;
begin
  Result := LineCountLogical - VisibleRows;
  if Result < 0 then Result := 0;
end;

function TTyMemo.TopLine: Integer;
begin
  Result := FTopLine;
end;

procedure TTyMemo.SetTopLine(AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < 0 then Clamped := 0;
  if Clamped > MaxTopLine then Clamped := MaxTopLine;
  if FTopLine = Clamped then Exit;
  FTopLine := Clamped;
  // Sync scrollbar position (guard reentrancy).
  if (not FSyncingScroll) and (FScrollBar <> nil) and FScrollBar.Visible then
  begin
    FSyncingScroll := True;
    try
      FScrollBar.Position := FTopLine;
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
  VR, MaxPos, MaxTop: Integer;
begin
  VR := VisibleRows;
  // Clamp FTopLine in case Lines were mutated directly (without SetLines).
  MaxTop := LineCountLogical - VR;
  if MaxTop < 0 then MaxTop := 0;
  if FTopLine > MaxTop then FTopLine := MaxTop;
  if LineCountLogical > VR then
  begin
    // Ensure scrollbar created.
    if FScrollBar = nil then
    begin
      FScrollBar := TTyScrollBar.Create(Self);
      FScrollBar.Parent := Self;
      FScrollBar.Kind := sbVertical;
      FScrollBar.Align := alRight;
      FScrollBar.OnChange := @ScrollBarChange;
    end;
    // Update DPI-dependent width and controller every call so DPI changes take effect.
    FScrollBar.Width := MulDiv(12, Font.PixelsPerInch, 96);
    FScrollBar.Controller := Self.Controller;
    MaxPos := LineCountLogical - VR;
    if MaxPos < 0 then MaxPos := 0;
    FSyncingScroll := True;
    try
      FScrollBar.Min := 0;
      FScrollBar.Max := MaxPos;
      FScrollBar.PageSize := VR;
      FScrollBar.Position := FTopLine;
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

procedure TTyMemo.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  APPI, LH, Line: Integer;
  S: string;
begin
  if not Enabled then Exit;          // v1.5 policy: ignore input when disabled
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  APPI := Font.PixelsPerInch;
  LH := LineHeight(APPI);
  // Y -> logical line (mirror TTyListBox row math), clamped to the last line.
  Line := FTopLine + (Y div LH);
  if Line < 0 then Line := 0;
  if Line > LineCountLogical - 1 then Line := LineCountLogical - 1;
  if Line < FLines.Count then
    S := FLines[Line]
  else
    S := '';
  FCaretLine := Line;
  // X -> nearest codepoint boundary on the resolved line (per-line ColIndexAtX).
  FCaretCol := ColIndexAtX(S, X, APPI);
  FDesiredCol := FCaretCol;
  try
    if CanFocus then
      SetFocus;
  except
    // Ignore focus errors in headless/test environments.
  end;
  Invalidate;
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
  // WheelDelta > 0 = scroll up (TopLine decreases)
  // WheelDelta < 0 = scroll down (TopLine increases)
  if WheelDelta > 0 then
    Delta := -3
  else
    Delta := 3;
  SetTopLine(FTopLine + Delta);
  Result := True;
end;

procedure TTyMemo.Resize;
begin
  inherited Resize;
  UpdateScrollBar;
end;

procedure TTyMemo.AfterEdit(APPI: Integer);
begin
  ClampCaret;
  EnsureCaretLineVisible(APPI);
  UpdateScrollBar;
  Invalidate;
  DoChange;
end;

procedure TTyMemo.AfterCaretMove(APPI: Integer);
begin
  ClampCaret;
  EnsureCaretLineVisible(APPI);
  Invalidate;
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

// ---- Word-delete mutators (pure UTF8 splice on the caret line; fall back to the
// cross-line merge at the line boundary). Callers route through AfterEdit. ----

procedure TTyMemo.DeleteWordBackward;
var
  Cur, Before, After: string;
  t, L: Integer;
begin
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
  WriteClipboardText(SelText);
end;

procedure TTyMemo.CutToClipboard;
begin
  if not HasSelection then Exit;
  WriteClipboardText(SelText);
  DeleteSelection;
  // Route through AfterEdit so OnChange fires (DeleteSelection is a pure mutator).
  AfterEdit(Font.PixelsPerInch);
end;

procedure TTyMemo.PasteFromClipboard;
// Multi-line paste: read the clipboard, normalise line breaks, split into
// segments and splice them into the model. A truly-empty clipboard is a full
// no-op (mirrors TTyEdit). A non-empty-but-CRLF-only clipboard (e.g. #10) still
// deletes any selection and inserts the resulting (possibly empty) segments,
// which mutates the model and fires OnChange.
var
  S, Norm, Cur, Head, Tail: string;
  Segs: TStringList;
  i, InsertAt: Integer;
begin
  S := ReadClipboardText;
  if S = '' then Exit;  // truly-empty clipboard: full no-op (Edit 551)
  if HasSelection then DeleteSelection;

  // Normalise CR/LF: CRLF -> LF, lone CR -> LF, so each remaining LF is one break.
  Norm := StringReplace(S, #13#10, #10, [rfReplaceAll]);
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
    FDesiredCol := FCaretCol;
    AfterEdit(Font.PixelsPerInch);
  finally
    Segs.Free;
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
// Midpoint-nearest codepoint boundary (lifted from TTyEdit.CaretIndexAtX,
// without horizontal-scroll handling — that belongs to the painting task).
var
  Widths: TTyIntArray;
  StartX, RelX, Len, i, MidPoint: Integer;
begin
  StartX := TextStartX(APPI);
  RelX := AX - StartX;
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
// Visible-line loop + static caret. Mirrors TTyListBox.RenderTo but uses the
// MEMO's own style for every line (no per-row TyListItem resolve) and draws text
// top-aligned in fixed LineHeight cells. Scrollbar width is 0 in this task; the
// real scrollbar (T4) will subtract it from the right edge.
var
  P: TTyPainter;
  S, FS: TTyStyleSet;
  R, ContentRect, LineRect, CaretRect, BandRect: TRect;
  SBWidth, LH, ContentTop, LastVisible, i, y: Integer;
  EffSize, CaretX: Integer;
  Line: string;
  // Selection-band state (resolved once before the visible-line loop).
  SL, SC, EL, EC, X1, X2: Integer;
  Widths: TTyIntArray;
  BandFill: TTyFill;
  BandColor: TTyColor;
  BandAlpha: Byte;
  FocusBorderColor: TTyColor;
begin
  // Keep the scrollbar in sync (cheap; catches external Lines mutations).
  UpdateScrollBar;

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
      SBWidth := MulDiv(12, APPI, 96);

    LH := LineHeight(APPI);
    ContentTop := ContentRect.Top;

    // Resolve the focus band color ONCE before the visible-line loop (verbatim
    // from TTyEdit): the :focus border-color, or the text color if absent. Only
    // needed when a selection exists; the band is filled per visible line below.
    SL := 0; SC := 0; EL := 0; EC := 0;
    FocusBorderColor := S.TextColor;
    if HasSelection then
    begin
      FS := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysFocused]);
      if tpBorderColor in FS.Present then
        FocusBorderColor := FS.BorderColor
      else
        FocusBorderColor := S.TextColor;
      GetOrderedSel(SL, SC, EL, EC);
    end;

    // Last visible logical line: fill the content height with LH-tall cells.
    LastVisible := FTopLine + (ContentRect.Bottom - ContentTop) div LH;
    if LastVisible > LineCountLogical - 1 then
      LastVisible := LineCountLogical - 1;

    for i := FTopLine to LastVisible do
    begin
      if i < FLines.Count then
        Line := FLines[i]
      else
        Line := '';
      y := ContentTop + (i - FTopLine) * LH;
      LineRect := Rect(ContentRect.Left, y, ContentRect.Right - SBWidth, y + LH);

      // Selection band for this row, drawn BENEATH the text (band first so the
      // glyphs sit on top). Reuse the SAME Line/MeasureLineWidths the row draws
      // with so band geometry matches the drawn text exactly. No FScrollX term.
      if HasSelection and (i >= SL) and (i <= EL) then
      begin
        Widths := MeasureLineWidths(Line, APPI);
        // X-range rules per row position within [SL..EL].
        if (i > SL) and (i < EL) then
        begin
          // Interior line: full content width.
          X1 := ContentRect.Left;
          X2 := ContentRect.Right - SBWidth;
        end
        else if (SL = EL) then
        begin
          // Single selected line: [SC..EC] on this line.
          X1 := ContentRect.Left + Widths[SC];
          X2 := ContentRect.Left + Widths[EC];
        end
        else if i = SL then
        begin
          // First line of a multi-line selection: from SC to the right edge.
          X1 := ContentRect.Left + Widths[SC];
          X2 := ContentRect.Right - SBWidth;
        end
        else
        begin
          // Last line (i = EL, EL > SL): from the left edge to EC.
          X1 := ContentRect.Left;
          X2 := ContentRect.Left + Widths[EC];
        end;
        if X1 < X2 then
        begin
          BandRect := Rect(X1, y, X2, y + LH);
          // ~35% alpha band tinted with the focus border color (verbatim TTyEdit).
          BandAlpha := $59;
          BandColor := TyRGBA(TyRedOf(FocusBorderColor), TyGreenOf(FocusBorderColor),
            TyBlueOf(FocusBorderColor), BandAlpha);
          BandFill := Default(TTyFill);
          BandFill.Kind := tfkSolid;
          BandFill.Color := BandColor;
          P.FillBackground(BandRect, BandFill, 0);
        end;
      end;

      P.DrawText(LineRect, Line, S.FontName, EffSize, S.FontWeight,
        S.TextColor, taLeftJustify, tlTop, False);
    end;

    // Static caret: only when focused (or headless-forced), no active selection,
    // and the caret line is currently visible. 1px bar like TTyEdit, inset 2px
    // top/bottom in the cell. Gated on not HasSelection so the caret hides while
    // a selection band is shown (matches TTyEdit; additive — existing single-caret
    // tests never set a selection).
    if (Focused or FForceFocused) and not HasSelection
      and (FCaretLine >= FTopLine) and (FCaretLine <= LastVisible) then
    begin
      if FCaretLine < FLines.Count then
        Line := FLines[FCaretLine]
      else
        Line := '';
      CaretX := R.Left + ColPixelXAt(Line, FCaretCol, APPI);
      y := ContentTop + (FCaretLine - FTopLine) * LH;
      CaretRect := Rect(CaretX, y + P.Scale(2),
        CaretX + P.Scale(1), y + LH - P.Scale(2));
      P.FillBackground(CaretRect, Default(TTyFill), 0);
      P.StrokeBorder(CaretRect, 0, 1, S.TextColor);
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
  inherited UTF8KeyPress(UTF8Key);
  // Printable codepoints only; control chars (Enter/Tab/etc.) are handled in
  // KeyDown or ignored here.
  if (UTF8Key = '') or (UTF8Key[1] < #32) then Exit;
  // A selection is replaced by the typed text (delete-then-insert, like
  // TTyEdit.InjectKey 643 — NOT an early exit).
  if HasSelection then DeleteSelection;
  DoInsertText(UTF8Key);
  FDesiredCol := FCaretCol;          // horizontal edit refreshes desired column
  AfterEdit(Font.PixelsPerInch);
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

  case Key of
    VK_RETURN:
    begin
      // Enter on a selection replaces it with a line break (delete-then-split).
      if HasSelection then DeleteSelection;
      DoSplitLine;
      FDesiredCol := FCaretCol;
      AfterEdit(APPI);
      Key := 0;
    end;
    VK_BACK:
    begin
      // A selection is deleted wholesale (never falls to the prev-char path),
      // checked BEFORE the (0,0) no-op guard so a selection always mutates.
      if HasSelection then
      begin
        DeleteSelection;
        FDesiredCol := FCaretCol;
        AfterEdit(APPI);
        Key := 0;
        Exit;
      end;
      // (0,0): no model change, no OnChange, but key is consumed.
      if (FCaretCol = 0) and (FCaretLine = 0) then
      begin
        Key := 0;
        Exit;
      end;
      // Ctrl/Alt+Backspace deletes the previous word (within the line; at col 0 it
      // falls back to the cross-line merge inside DeleteWordBackward). Precedence
      // selection > word > single, mirroring TTyEdit.
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
      // A selection is deleted wholesale, checked BEFORE the end-of-doc guard
      // so a selection always mutates regardless of caret position.
      if HasSelection then
      begin
        DeleteSelection;
        FDesiredCol := FCaretCol;
        AfterEdit(APPI);
        Key := 0;
        Exit;
      end;
      L := LineLen(FCaretLine);
      // End of document (last line, last col): no change, no OnChange.
      if (FCaretCol >= L) and (FCaretLine >= MaxLine) then
      begin
        Key := 0;
        Exit;
      end;
      // Ctrl/Alt+Delete deletes the next word (within the line; at line end it
      // falls back to the cross-line merge inside DeleteWordForward).
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
      if FCaretLine > 0 then
      begin
        Dec(FCaretLine);
        // Restore desired column, clamped to the new line length.
        FCaretCol := FDesiredCol;
        if FCaretCol > LineLen(FCaretLine) then
          FCaretCol := LineLen(FCaretLine);
      end;
      // FDesiredCol preserved across vertical motion.
      if not Extending then
      begin
        FSelAnchorLine := FCaretLine;
        FSelAnchorCol := FCaretCol;
      end;
      AfterCaretMove(APPI);
      Key := 0;
    end;
    VK_DOWN:
    begin
      if FCaretLine < MaxLine then
      begin
        Inc(FCaretLine);
        FCaretCol := FDesiredCol;
        if FCaretCol > LineLen(FCaretLine) then
          FCaretCol := LineLen(FCaretLine);
      end;
      // FDesiredCol preserved across vertical motion.
      if not Extending then
      begin
        FSelAnchorLine := FCaretLine;
        FSelAnchorCol := FCaretCol;
      end;
      AfterCaretMove(APPI);
      Key := 0;
    end;
    VK_HOME:
    begin
      if CtrlLike then
      begin
        FCaretLine := 0;
        FCaretCol := 0;
      end
      else
        FCaretCol := 0;          // line-local
      FDesiredCol := FCaretCol;
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
        FCaretLine := MaxLine;
        FCaretCol := LineLen(FCaretLine);
      end
      else
        FCaretCol := LineLen(FCaretLine);  // line-local
      FDesiredCol := FCaretCol;
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
  InjectKey(VK_BACK, []);
end;

procedure TTyMemo.InjectDelete;
begin
  InjectKey(VK_DELETE, []);
end;

end.
