unit test.parity.memo;
{$mode objfpc}{$H+}
{ API-parity guards for TTyMemo against native TCustomMemo/TCustomEdit.

  Two defects are pinned here.

  (1) Flat offsets must index the SAME string Text returns.
      The LCL contract is explicit:
        customedit.inc:118-121  GetSelText  = UTF8Copy(Text, SelStart + 1, SelLength)
        customedit.inc:222-228  SelectAll   -> SelLength := UTF8Length(Text)
        custommemo.inc:150-156  RealGetText = Lines.Text
      Lines.Text separates lines with TStrings' line break, which is CRLF (TWO
      codepoints) on Windows. A flat offset that charges ONE codepoint per newline
      therefore drifts from Text by one per preceding line -- and is silently correct
      on line 0, which is exactly where this gets tested by hand. These tests put the
      interesting content on the LAST line so the drift cannot hide.

  (2) ScrollBy must scroll the TEXT VIEW, not the child controls.
      custommemo.inc:45-48   TCustomMemo.ScrollBy -> ScrollBy_WS (the text view)
      wincontrol.inc:6255    TWinControl.ScrollBy -> SetBounds on every child
      Inheriting the TWinControl one would drag the memo's own embedded scrollbars
      off their docked edges and leave the text where it was. }
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, StdCtrls, LCLType, LazUTF8,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Memo;
type
  { Probe subclass: the parity surface is public/published except for the scroll
    geometry (TopRow / LineHeight), which the ScrollBy guards need to express a
    pixel delta in whole rows. }
  TTyMemoParityProbe = class(TTyMemo)
  public
    function ProbeTopRow: Integer;
    procedure ProbeSetTopLine(AValue: Integer);
    function ProbeLineHeight(APPI: Integer): Integer;
    procedure ProbeSetCaret(ALine, ACol: Integer);
    procedure ProbeSetAnchor(ALine, ACol: Integer);
    procedure ProbeUpdateScrollBar;
    procedure ProbeSetWordWrap(AValue: Boolean);
  end;

  TTyMemoParityTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoParityProbe;
    procedure SetUpMemo(AWidth: Integer = 200; AHeight: Integer = 120);
    procedure LoadLines(const AItems: array of string);
    // The document prefix that ends at caret (ALine, ACol), joined the way
    // Lines.Text joins it. CaretPos must be the codepoint length of exactly this.
    function PrefixUpTo(ALine, ACol: Integer): string;
    // The vertical scrollbar child, or nil. Used to prove ScrollBy did NOT move it.
    function VBarChild: TControl;
  protected
    procedure TearDown; override;
  published
    // --- Defect 1: flat offsets vs Text ---
    procedure TestSelStartFromPosInTextSelectsThatWord;
    procedure TestSelStartOnFirstLineStillAgrees;
    procedure TestSelTextEqualsUtf8CopyOfText;
    procedure TestCaretPosIsPrefixLengthOfText;
    procedure TestFlatOffsetsCountMultibyteCodepointsNotBytes;
    procedure TestSelectAllSelLengthSpansText;
    // --- Defect 2: ScrollBy ---
    procedure TestScrollByMovesTextViewNotChildren;
    procedure TestScrollBySignMatchesWinControl;
    procedure TestScrollByHorizontalMovesScrollX;
  end;

implementation

{ TTyMemoParityProbe }

function TTyMemoParityProbe.ProbeTopRow: Integer;
begin
  Result := TopRow;
end;

procedure TTyMemoParityProbe.ProbeSetTopLine(AValue: Integer);
begin
  SetTopLine(AValue);
end;

function TTyMemoParityProbe.ProbeLineHeight(APPI: Integer): Integer;
begin
  Result := LineHeight(APPI);
end;

procedure TTyMemoParityProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

procedure TTyMemoParityProbe.ProbeSetAnchor(ALine, ACol: Integer);
begin
  SetSelAnchor(ALine, ACol);
end;

procedure TTyMemoParityProbe.ProbeUpdateScrollBar;
begin
  UpdateScrollBar;
end;

procedure TTyMemoParityProbe.ProbeSetWordWrap(AValue: Boolean);
begin
  WordWrap := AValue;
end;

{ TTyMemoParityTest }

procedure TTyMemoParityTest.SetUpMemo(AWidth: Integer = 200; AHeight: Integer = 120);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyMemo { background:#FFFFFF; color:#000000; border-width:0px; padding:0px; font-size:14px; }');
  FMemo := TTyMemoParityProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;   // pin 96; macOS default is 72
  FMemo.SetBounds(0, 0, AWidth, AHeight);
end;

procedure TTyMemoParityTest.LoadLines(const AItems: array of string);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    for i := Low(AItems) to High(AItems) do
      L.Add(AItems[i]);
    FMemo.Lines := L;
  finally
    L.Free;
  end;
end;

function TTyMemoParityTest.PrefixUpTo(ALine, ACol: Integer): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to ALine - 1 do
    Result := Result + FMemo.Lines[i] + LineEnding;
  Result := Result + UTF8Copy(FMemo.Lines[ALine], 1, ACol);
end;

function TTyMemoParityTest.VBarChild: TControl;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to FMemo.ControlCount - 1 do
    if FMemo.Controls[i].Visible and (FMemo.Controls[i].Align = alRight) then
      Exit(FMemo.Controls[i]);
end;

procedure TTyMemoParityTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FCtl.Free;
  FCtl := nil;
end;

// --------------------------------------------------------------------------
// Defect 1: SelStart/SelLength/CaretPos index the string Text returns
// --------------------------------------------------------------------------

{ The headline case: a caller locates a word in Text and selects it by offset.
    Memo.SelStart := Pos(needle, Memo.Text) - 1;
    Memo.SelLength := Length(needle);
  This is the documented native idiom (customedit.inc:120 defines SelText as
  UTF8Copy(Text, SelStart+1, SelLength)). The needle sits on the LAST line, so a
  flat offset that charges one codepoint per newline instead of the full CRLF
  lands two codepoints early and slices the wrong word. }
procedure TTyMemoParityTest.TestSelStartFromPosInTextSelectsThatWord;
const
  NEEDLE = 'delta';
var
  Idx: Integer;
begin
  SetUpMemo;
  LoadLines(['alpha', 'beta', 'gamma delta']);
  Idx := UTF8Length(UTF8Copy(FMemo.Text, 1, Pos(NEEDLE, FMemo.Text) - 1));
  FMemo.SelStart := Idx;
  FMemo.SelLength := UTF8Length(NEEDLE);
  AssertEquals('SelStart := Pos(needle, Text)-1 selects the needle',
    NEEDLE, FMemo.SelText);
  AssertEquals('SelStart reads back what was written', Idx, FMemo.SelStart);
end;

{ Regression companion to the above: the same idiom on line 0 was ALWAYS correct
  (no preceding newline to miscount), and must stay correct. If this one goes red
  the newline width was applied where there is no newline. }
procedure TTyMemoParityTest.TestSelStartOnFirstLineStillAgrees;
const
  NEEDLE = 'lpha';
var
  Idx: Integer;
begin
  SetUpMemo;
  LoadLines(['alpha', 'beta', 'gamma delta']);
  Idx := UTF8Length(UTF8Copy(FMemo.Text, 1, Pos(NEEDLE, FMemo.Text) - 1));
  AssertEquals('needle starts at flat 1 on line 0', 1, Idx);
  FMemo.SelStart := Idx;
  FMemo.SelLength := UTF8Length(NEEDLE);
  AssertEquals('line-0 offsets are unaffected', NEEDLE, FMemo.SelText);
end;

{ TCustomEdit.GetSelText IS UTF8Copy(Text, SelStart+1, SelLength) -- so for any
  selection the two must be the same string. A multi-line selection is the case
  that fails when the newline width is wrong on either side of the identity. }
procedure TTyMemoParityTest.TestSelTextEqualsUtf8CopyOfText;
begin
  SetUpMemo;
  LoadLines(['alpha', 'beta', 'gamma delta']);
  // Select from line 1 col 1 through line 2 col 5: 'eta' <LE> 'gamma'. Caret FIRST,
  // then the anchor -- a direct caret write collapses the selection onto itself.
  FMemo.ProbeSetCaret(2, 5);
  FMemo.ProbeSetAnchor(1, 1);
  AssertTrue('precondition: a selection exists', FMemo.SelLength > 0);
  AssertEquals('multi-line SelText = UTF8Copy(Text, SelStart+1, SelLength)',
    UTF8Copy(FMemo.Text, FMemo.SelStart + 1, FMemo.SelLength), FMemo.SelText);
  AssertEquals('and it is the expected text',
    'eta' + LineEnding + 'gamma', FMemo.SelText);
end;

{ CaretPos is the codepoint length of the document prefix that ends at the caret.
  Walk EVERY caret position in a 3-line document: any newline miscount shows up
  from line 1 onwards and compounds on line 2. }
procedure TTyMemoParityTest.TestCaretPosIsPrefixLengthOfText;
var
  L, C: Integer;
  Prefix: string;
begin
  SetUpMemo;
  LoadLines(['alpha', 'beta', 'gamma delta']);
  for L := 0 to FMemo.Lines.Count - 1 do
    for C := 0 to UTF8Length(FMemo.Lines[L]) do
    begin
      FMemo.ProbeSetCaret(L, C);
      Prefix := PrefixUpTo(L, C);
      AssertEquals(Format('CaretPos at (%d,%d) = prefix codepoints', [L, C]),
        UTF8Length(Prefix), FMemo.CaretPos);
      // ...and the round trip: writing that offset back lands on the same prefix.
      FMemo.CaretPos := UTF8Length(Prefix);
      AssertEquals(Format('CaretPos round-trips at (%d,%d)', [L, C]),
        Prefix, UTF8Copy(FMemo.Text, 1, FMemo.CaretPos));
    end;
end;

{ Offsets are CODEPOINTS, not bytes (customedit.inc uses UTF8Copy/UTF8Length).
  Multibyte lines above the caret would inflate a byte-based offset; the CRLF
  separators are still two codepoints each. }
procedure TTyMemoParityTest.TestFlatOffsetsCountMultibyteCodepointsNotBytes;
var
  NL: Integer;
begin
  SetUpMemo;
  LoadLines(['汉字', 'ab', '你好世界']);
  NL := UTF8Length(LineEnding);
  FMemo.ProbeSetCaret(2, 1);
  // 2 codepoints + NL + 2 codepoints + NL + 1
  AssertEquals('flat offset counts codepoints and full line breaks',
    2 + NL + 2 + NL + 1, FMemo.CaretPos);
  AssertEquals('prefix agrees with Text',
    PrefixUpTo(2, 1), UTF8Copy(FMemo.Text, 1, FMemo.CaretPos));
end;

{ SelectAll must span the whole document in the SAME units Text uses. Text carries
  a trailing line break after the last line (TStrings.GetTextStr appends one unless
  SkipLastLineBreak), and no caret can sit past the end of the last line, so the
  selection is Text minus that trailing break. }
procedure TTyMemoParityTest.TestSelectAllSelLengthSpansText;
begin
  SetUpMemo;
  LoadLines(['alpha', 'beta', 'gamma delta']);
  FMemo.SelectAll;
  AssertEquals('SelStart after SelectAll', 0, FMemo.SelStart);
  AssertEquals('SelLength spans Text minus its trailing break',
    UTF8Length(FMemo.Text) - UTF8Length(LineEnding), FMemo.SelLength);
  AssertEquals('SelText is the whole document',
    UTF8Copy(FMemo.Text, 1, FMemo.SelLength), FMemo.SelText);
end;

// --------------------------------------------------------------------------
// Defect 2: ScrollBy scrolls the text view
// --------------------------------------------------------------------------

{ TCustomMemo.ScrollBy scrolls the TEXT (custommemo.inc:45-48). Inheriting
  TWinControl.ScrollBy (wincontrol.inc:6255) would instead SetBounds every child --
  here that means yanking the memo's own docked vertical scrollbar sideways while
  the text stays put. Assert both halves: the view moved, the child did not. }
procedure TTyMemoParityTest.TestScrollByMovesTextViewNotChildren;
var
  L: TStringList;
  i, LH, BarLeft, BarTop: Integer;
  Bar: TControl;
begin
  SetUpMemo;
  L := TStringList.Create;
  try
    for i := 0 to 99 do L.Add('line ' + IntToStr(i));
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  FMemo.ScrollBars := ssVertical;      // force the child bar to exist
  FMemo.ProbeUpdateScrollBar;
  Bar := VBarChild;
  AssertTrue('the vertical scrollbar child exists', Bar <> nil);
  BarLeft := Bar.Left;
  BarTop := Bar.Top;

  LH := FMemo.ProbeLineHeight(96);
  FMemo.ProbeSetTopLine(0);
  // Negative DeltaY = content moves up = scroll DOWN (the TWinControl sign, which
  // TTyScrollBox also relies on: it calls ScrollBy(-dx,-dy) to advance its offset).
  FMemo.ScrollBy(0, -3 * LH);
  AssertEquals('ScrollBy scrolled the text view down 3 rows', 3, FMemo.ProbeTopRow);
  AssertEquals('ScrollBy did not move the scrollbar child (left)', BarLeft, Bar.Left);
  AssertEquals('ScrollBy did not move the scrollbar child (top)', BarTop, Bar.Top);
end;

{ Sign convention, both directions: positive DeltaY moves the CONTENT down, i.e.
  reveals earlier rows (TopRow decreases). Getting this backwards is the classic
  silent scroll bug, so pin it explicitly. }
procedure TTyMemoParityTest.TestScrollBySignMatchesWinControl;
var
  L: TStringList;
  i, LH: Integer;
begin
  SetUpMemo;
  L := TStringList.Create;
  try
    for i := 0 to 99 do L.Add('line ' + IntToStr(i));
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  LH := FMemo.ProbeLineHeight(96);
  FMemo.ProbeSetTopLine(20);
  FMemo.ScrollBy(0, 5 * LH);
  AssertEquals('positive DeltaY reveals earlier rows', 15, FMemo.ProbeTopRow);
  FMemo.ScrollBy(0, -2 * LH);
  AssertEquals('negative DeltaY reveals later rows', 17, FMemo.ProbeTopRow);
  // Clamped, never negative.
  FMemo.ScrollBy(0, 1000 * LH);
  AssertEquals('scrolling past the top clamps at row 0', 0, FMemo.ProbeTopRow);
end;

{ DeltaX moves the horizontal text offset (device px), same sign rule: a positive
  DeltaX moves the content right, so the scroll offset shrinks. }
procedure TTyMemoParityTest.TestScrollByHorizontalMovesScrollX;
const
  LONG_LINE = 'the quick brown fox jumps over the lazy dog again and again';
var
  Before: Integer;
begin
  SetUpMemo(80, 120);
  FMemo.ProbeSetWordWrap(False);
  LoadLines([LONG_LINE]);
  // Drive the caret to end-of-line so the view is scrolled right.
  FMemo.ProbeSetCaret(0, 0);
  FMemo.InjectKey(VK_END, []);
  Before := FMemo.ScrollX;
  AssertTrue('precondition: the view is scrolled right', Before > 0);
  FMemo.ScrollBy(10, 0);
  AssertEquals('positive DeltaX moves the content right (offset shrinks)',
    Before - 10, FMemo.ScrollX);
  FMemo.ScrollBy(-4, 0);
  AssertEquals('negative DeltaX moves the content left (offset grows)',
    Before - 6, FMemo.ScrollX);
  // Clamped at 0.
  FMemo.ScrollBy(100000, 0);
  AssertEquals('scrolling past the left edge clamps at 0', 0, FMemo.ScrollX);
end;

initialization
  RegisterTest(TTyMemoParityTest);
end.
