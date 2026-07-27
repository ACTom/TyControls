unit test.utf8;
{$mode objfpc}{$H+}

{ UTF-8 audit regressions.

  The library's text goes through TTyPainter.DrawText, whose ellipsis fitter was shortening
  by one BYTE -- half a Chinese character -- and is covered by test.painter. This unit holds
  the OTHER places the same assumption had leaked into, one test class per unit so a failure
  names the control that broke.

  Every assertion here is about a STRING, never about pixels: the headless BGRA renderer
  silently swallows a stray continuation byte, so a rendered comparison shows nothing. It is
  the real widgetset that draws the '?' the maintainer reported. }

interface
uses
  Classes, SysUtils, Types, Forms, Controls, LCLType, fpcunit, testregistry,
  LazUTF8, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Columns, tyControls.Painter,
  tyControls.Grid, tyControls.DateTimePicker;

type
  { --- Grid cell clipping ------------------------------------------------- }
  TGridEllipsisTest = class(TTestCase)
  private
    FBmp: TBGRABitmap;
    procedure MakeBitmap;
  protected
    procedure TearDown; override;
  published
    procedure TestFitCutsWholeCharactersAtEveryWidth;
    procedure TestFitLeavesTextThatAlreadyFitsAlone;
    procedure TestFitKeepsTheFirstCharacterWhenNothingFits;
  end;

  { --- Grid: typing a Chinese character to start editing ------------------ }
  TGridAccess = class(TTyStringGrid)
  public
    procedure TypeChar(AChar: Char);
    procedure TypeUtf8(const AChar: string);
    function  IsEditing: Boolean;
    function  EditorText: string;
  end;

  TGridChineseTypingTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    function MakeGrid: TGridAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestChineseKeyStartsEditingWithTheWholeCharacter;
    procedure TestChineseKeyObeysValidChars;
    procedure TestSingleByteKeysAreLeftToKeyPress;
    procedure TestChineseKeyIsIgnoredOnANonEditableCell;
  end;

  { --- DateTimePicker click walk ------------------------------------------ }
  TDateTimeCharWalkTest = class(TTestCase)
  published
    procedure TestWalkVisitsOnlyCharacterBoundaries;
    procedure TestWalkAdvancesOverAsciiOneAtATime;
    procedure TestWalkStopsAtTheEnd;
  end;

implementation

const
  { A Chinese date as the picker renders 'yyyy年mm月dd日': ASCII digits with three-byte
    separators between them. }
  CJK_DATE = '2026年07月28日';

{ Every character of this sample is three bytes, so "ends on a character boundary" is the
  arithmetic "byte count is three times the character count" -- no decoding needed in the
  assertions themselves. }
function AllThreeByteChars(const S: string): Boolean;
begin
  Result := Length(S) = UTF8Length(S) * 3;
end;

{ ── TGridEllipsisTest ────────────────────────────────────────────────────── }

procedure TGridEllipsisTest.MakeBitmap;
begin
  FBmp := TBGRABitmap.Create(1, 1);
  TyConfigureTextFont(FBmp, '', 12, 400, 96);
end;

procedure TGridEllipsisTest.TearDown;
begin
  FreeAndNil(FBmp);
  inherited TearDown;
end;

{ The load-bearing one. Sweep every width from 1px up to the text's full width: whatever the
  fitter gives back, stripped of the '...' it appends, must be a whole number of characters.
  The byte-wise version this replaced fails here -- it stops as soon as the remaining bytes
  fit, and one or two bytes of a three-byte ideograph fit long before the ideograph does. }
procedure TGridEllipsisTest.TestFitCutsWholeCharactersAtEveryWidth;
const
  CJK = '库存台账明细表';
var
  full, w: Integer;
  got, body: string;
begin
  MakeBitmap;
  AssertTrue('the sample really is three bytes per character', AllThreeByteChars(CJK));
  full := FBmp.TextSize(CJK).cx;
  AssertTrue('the font measured something', full > 0);

  for w := 1 to full do
  begin
    got := TyGridEllipsisFit(FBmp, CJK, w);
    body := got;
    if (Length(body) >= 3) and (Copy(body, Length(body) - 2, 3) = '...') then
      body := Copy(body, 1, Length(body) - 3);
    AssertTrue(Format('width %d: %d bytes is not a whole number of characters',
      [w, Length(body)]), AllThreeByteChars(body));
    AssertTrue(Format('width %d: kept nothing at all', [w]), body <> '');
  end;
end;

procedure TGridEllipsisTest.TestFitLeavesTextThatAlreadyFitsAlone;
const
  CJK = '库存台账';
var
  full: Integer;
begin
  MakeBitmap;
  full := FBmp.TextSize(CJK).cx;
  AssertEquals('room to spare: no truncation, no dots',
    CJK, TyGridEllipsisFit(FBmp, CJK, full + 50));
end;

{ Zero width still has to leave ONE character: a cell showing only '...' says nothing at all,
  and the caller clips the overflow anyway. }
procedure TGridEllipsisTest.TestFitKeepsTheFirstCharacterWhenNothingFits;
const
  CJK = '库存台账明细表';
var
  got: string;
begin
  MakeBitmap;
  got := TyGridEllipsisFit(FBmp, CJK, 0);
  AssertEquals('one character survives, plus the mark', '库' + '...', got);
end;

{ ── TGridAccess ──────────────────────────────────────────────────────────── }

procedure TGridAccess.TypeChar(AChar: Char);
var
  c: Char;
begin
  c := AChar;
  KeyPress(c);
end;

procedure TGridAccess.TypeUtf8(const AChar: string);
var
  k: TUTF8Char;
begin
  k := AChar;
  UTF8KeyPress(k);
end;

function TGridAccess.IsEditing: Boolean;
begin
  Result := Editing;
end;

function TGridAccess.EditorText: string;
begin
  Result := InlineEditor.Text;
end;

{ ── TGridChineseTypingTest ───────────────────────────────────────────────── }

procedure TGridChineseTypingTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyGrid { background: #FFFFFF; color: #000000; border-width: 0px; }' +
    'TyGridCell { color: #000000; }');
end;

procedure TGridChineseTypingTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

function TGridChineseTypingTest.MakeGrid: TGridAccess;
var
  i: Integer;
  c: TTyColumn;
begin
  Result := TGridAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 400, 300);
  for i := 0 to 3 do
  begin
    c := Result.Header.Columns.Add as TTyColumn;
    c.Width := 80;
  end;
  Result.Header.Options := Result.Header.Options - [hoVisible];
  Result.DefaultRowHeight := 20;
  Result.RowCount := 10;
end;

{ The reported symptom, at its source. LCL hands KeyPress a Char(Message.CharCode) -- one
  byte carved out of a UTF-16 code unit -- so '中' arrived as whatever the system codepage
  collapses it to, usually '?'. The whole character only exists on the UTF8KeyPress seam. }
procedure TGridChineseTypingTest.TestChineseKeyStartsEditingWithTheWholeCharacter;
var
  G: TGridAccess;
begin
  G := MakeGrid;
  G.Cells[0, 0] := '旧值';
  G.MoveCursor(0, 0);

  AssertTrue('not editing to begin with', not G.IsEditing);
  G.TypeUtf8('中');
  AssertTrue('a Chinese keystroke opens the editor', G.IsEditing);
  AssertEquals('and it is the whole character, not one of its bytes',
    '中', G.EditorText);
end;

{ ValidChars is a list of CHARACTERS. Looking for '中' in '0123456789' must miss -- and it
  must miss as a whole character, not by happening to find one of its bytes. }
procedure TGridChineseTypingTest.TestChineseKeyObeysValidChars;
var
  G: TGridAccess;
begin
  G := MakeGrid;
  TTyGridColumn(G.Header.Columns.Items[1]).ValidChars := '0123456789';
  G.MoveCursor(1, 0);

  G.TypeUtf8('中');
  AssertTrue('a digits-only column refuses a Chinese character', not G.IsEditing);
end;

{ The single-byte path is KeyPress's, and stays KeyPress's: handling it here as well would
  open the editor twice (and swallow the key the wrong way round). }
procedure TGridChineseTypingTest.TestSingleByteKeysAreLeftToKeyPress;
var
  G: TGridAccess;
begin
  G := MakeGrid;
  G.MoveCursor(0, 0);

  G.TypeUtf8('X');
  AssertTrue('UTF8KeyPress does not act on an ASCII key', not G.IsEditing);

  G.TypeChar('X');
  AssertTrue('KeyPress still does', G.IsEditing);
  AssertEquals('with the typed character as the first one', 'X', G.EditorText);
end;

{ Same refusal rules as the ASCII path: a cell with no editor is not opened by any key. }
procedure TGridChineseTypingTest.TestChineseKeyIsIgnoredOnANonEditableCell;
var
  G: TGridAccess;
begin
  G := MakeGrid;
  TTyGridColumn(G.Header.Columns.Items[2]).EditorKind := gekNone;
  G.MoveCursor(2, 0);

  G.TypeUtf8('中');
  AssertTrue('a read-only cell stays closed', not G.IsEditing);
end;

{ ── TDateTimeCharWalkTest ────────────────────────────────────────────────── }

{ The picker turns a click x into a byte offset by measuring longer and longer prefixes of
  the rendered text. Those prefixes must be whole characters: a Chinese format carries
  three-byte separators, and the width of half a separator is whatever the renderer invents.
  Walking from 0 with this function must therefore only ever land between characters. }
procedure TDateTimeCharWalkTest.TestWalkVisitsOnlyCharacterBoundaries;
var
  ofs, guard: Integer;
begin
  ofs := 0;
  guard := 0;
  while ofs < Length(CJK_DATE) do
  begin
    { "ofs is a character boundary", stated so nothing can satisfy it by accident: count the
      characters in the first ofs bytes, take that many characters off the WHOLE string, and
      you must land on byte ofs again. Cut a separator in half and you do not -- the codepoint
      count rounds the half-character up, so the re-taken prefix overshoots. }
    AssertEquals(Format('offset %d cuts a character in half', [ofs]), ofs,
      Length(UTF8Copy(CJK_DATE, 1, UTF8Length(Copy(CJK_DATE, 1, ofs)))));
    ofs := TyDateTimeNextCharOffset(CJK_DATE, ofs);
    Inc(guard);
    AssertTrue('the walk must terminate', guard <= Length(CJK_DATE) + 1);
  end;
  AssertEquals('the walk ends exactly at the end', Length(CJK_DATE), ofs);
end;

procedure TDateTimeCharWalkTest.TestWalkAdvancesOverAsciiOneAtATime;
begin
  AssertEquals('ASCII steps one byte', 1, TyDateTimeNextCharOffset('2026/07/28', 0));
  AssertEquals('and keeps stepping one byte', 5, TyDateTimeNextCharOffset('2026/07/28', 4));
end;

procedure TDateTimeCharWalkTest.TestWalkStopsAtTheEnd;
begin
  AssertEquals('at the end it stays at the end',
    Length(CJK_DATE), TyDateTimeNextCharOffset(CJK_DATE, Length(CJK_DATE)));
  AssertEquals('past the end it clamps',
    Length(CJK_DATE), TyDateTimeNextCharOffset(CJK_DATE, Length(CJK_DATE) + 10));
  AssertEquals('a negative offset restarts at zero', 0,
    TyDateTimeNextCharOffset(CJK_DATE, -5));
end;

initialization
  RegisterTest(TGridEllipsisTest);
  RegisterTest(TGridChineseTypingTest);
  RegisterTest(TDateTimeCharWalkTest);

end.
