unit test.memo.tabs;
{ #97: a tab in TTyMemo advances to the next tab stop.

  BGRABitmap's TextSize / TextOut give #9 no advance, so 'aaa'#9'bbb' was measured and drawn
  as 'aaabbb' and the caret, the hit test and the selection treated the tab as a zero-width
  character. A tab now advances to the next stop, counted from the line's start, and every
  consumer of the line's prefix widths -- the caret, a click, the selection band, the wrap,
  the horizontal scroll range -- agrees with what is drawn, because the drawing places the
  runs between tabs where those widths put them.

  The stop is --memo-tab-size, read as CSS reads tab-size: a number of spaces (8 by default)
  or a length. It is read per control, so one memo can set it in its StyleOverride. A line
  without a tab is measured and drawn exactly as before. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Memo;

type
  TTyMemoTabProbe = class(TTyMemo)
  public
    function Widths(const S: string; APPI: Integer = 96): TTyIntArray;
    function ColX(const S: string; ACol: Integer): Integer;
    function ColAt(const S: string; AX: Integer): Integer;
    function StartX: Integer;
    function Rows(AContentWidth: Integer): TTyVisualRowArray;
    function Widest: Integer;
    function Total: Integer;
    function CaretX: Integer;
    function ContentW: Integer;
    function LH: Integer;
    procedure Select(ALine, AFrom, ATo: Integer);
    procedure Render(ABmp: TBGRABitmap);
  end;

  TTyMemoTabTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoTabProbe;
    function SpaceW(APPI: Integer = 96): Integer;
    function W(const S: string): Integer;   // the width of a tab-free string
    procedure Load(const AItems: array of string);
    function IsInk(ABmp: TBGRABitmap; X, Y: Integer): Boolean;
    function InkIn(ABmp: TBGRABitmap; X0, X1: Integer; AY0: Integer = 0; AY1: Integer = 27): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestATabAdvancesToTheNextStop;
    procedure TestATabOnAStopGoesToTheNextOne;
    procedure TestColumnsLineUp;
    procedure TestTheTokenSetsTheStop;
    procedure TestTheStopScalesWithTheDpi;
    procedure TestTheDrawnTextFollows;
    procedure TestAWrappedRowDrawsItsTabWhereItsCaretIs;
    procedure TestTheCaretAndAClickUseTheStops;
    procedure TestTheSelectionCoversTheTab;
    procedure TestTheWrapCountsTheTab;
    procedure TestTheWrappedRowsFollowTheToken;
    procedure TestTheScrollRangeCountsTheTab;
    procedure TestTheScrollRangeCountsATabInAShortLine;
  end;

implementation

{ TTyMemoTabProbe }

function TTyMemoTabProbe.Widths(const S: string; APPI: Integer): TTyIntArray;
begin
  Result := MeasureLineWidths(S, APPI);
end;

function TTyMemoTabProbe.ColX(const S: string; ACol: Integer): Integer;
begin
  Result := ColPixelXAt(S, ACol, 96);
end;

function TTyMemoTabProbe.ColAt(const S: string; AX: Integer): Integer;
begin
  Result := ColIndexAtX(S, AX, 96);
end;

function TTyMemoTabProbe.StartX: Integer;
begin
  Result := TextStartX(96);
end;

function TTyMemoTabProbe.Rows(AContentWidth: Integer): TTyVisualRowArray;
begin
  Result := BuildVisualRows(AContentWidth, 96);
end;

function TTyMemoTabProbe.Widest: Integer;
begin
  Result := WidestLineWidth(96);
end;

function TTyMemoTabProbe.Total: Integer;
begin
  Result := TotalVisualRows(96);
end;

function TTyMemoTabProbe.CaretX: Integer;
begin
  Result := CaretDrawX(96);
end;

function TTyMemoTabProbe.ContentW: Integer;
begin
  Result := ContentWidthFor(96);
end;

function TTyMemoTabProbe.LH: Integer;
begin
  Result := LineHeight(96);
end;

procedure TTyMemoTabProbe.Select(ALine, AFrom, ATo: Integer);
begin
  SetCaret(ALine, ATo);           { a caret write collapses the selection, so first }
  SetSelAnchor(ALine, AFrom);
  SetForceFocused(True);
end;

procedure TTyMemoTabProbe.Render(ABmp: TBGRABitmap);
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(Width, Height);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, Width, Height);
    RenderTo(b.Canvas, Rect(0, 0, Width, Height), 96);
    ABmp.Assign(b);
  finally
    b.Free;
  end;
end;

{ TTyMemoTabTest }

procedure TTyMemoTabTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FMemo := TTyMemoTabProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;
  FMemo.SetBounds(0, 0, 400, 120);
end;

procedure TTyMemoTabTest.TearDown;
begin
  FMemo.Free;
  FCtl.Free;
end;

function TTyMemoTabTest.SpaceW(APPI: Integer): Integer;
begin
  Result := FMemo.Widths(' ', APPI)[1];
  AssertTrue('precondition: a space has a width', Result > 0);
end;

function TTyMemoTabTest.W(const S: string): Integer;
var
  a: TTyIntArray;
begin
  a := FMemo.Widths(S);
  Result := a[High(a)];
end;

procedure TTyMemoTabTest.Load(const AItems: array of string);
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

function TTyMemoTabTest.IsInk(ABmp: TBGRABitmap; X, Y: Integer): Boolean;
var
  p: TBGRAPixel;
begin
  p := ABmp.GetPixel(X, Y);
  Result := (p.red < 110) and (p.green < 110) and (p.blue < 110);
end;

function TTyMemoTabTest.InkIn(ABmp: TBGRABitmap; X0, X1: Integer; AY0: Integer;
  AY1: Integer): Boolean;
var
  x, y: Integer;
begin
  { by default the first text row: well inside the top 28 px of the memo }
  for x := X0 to X1 do
    for y := AY0 to AY1 do
      if IsInk(ABmp, x, y) then Exit(True);
  Result := False;
end;

procedure TTyMemoTabTest.TestATabAdvancesToTheNextStop;
var
  wd: TTyIntArray;
  t: Integer;
begin
  t := 8 * SpaceW;
  AssertTrue('precondition: "aaa" is short of the first stop', W('aaa') < t);
  wd := FMemo.Widths('aaa'#9'bbb');
  AssertEquals('before the tab, as without it', W('aaa'), wd[3]);
  AssertEquals('the tab ends on the first stop, eight spaces in', t, wd[4]);
  AssertEquals('the text after it starts there', t + W('b'), wd[5]);
  AssertEquals('and runs on as text does', t + W('bbb'), wd[7]);
end;

procedure TTyMemoTabTest.TestATabOnAStopGoesToTheNextOne;
var
  wd: TTyIntArray;
  t: Integer;
begin
  t := 8 * SpaceW;
  wd := FMemo.Widths(#9#9'x');
  AssertEquals('the first tab', t, wd[1]);
  AssertEquals('a tab that starts on a stop goes to the next one', 2 * t, wd[2]);
  AssertEquals(2 * t + W('x'), wd[3]);
end;

procedure TTyMemoTabTest.TestColumnsLineUp;
var
  t, n: Integer;
  wd: TTyIntArray;
  long: string;
begin
  t := 8 * SpaceW;
  AssertTrue('precondition: "abcde" is short of the first stop', W('abcde') < t);
  AssertEquals('a short cell', t, FMemo.Widths('a'#9'x')[2]);
  AssertEquals('a longer one: the next column starts at the same x', t,
    FMemo.Widths('abcde'#9'x')[6]);
  long := 'abcdefghijklmnop';
  AssertTrue('precondition: a cell past the first stop', W(long) > t);
  n := Length(long);
  wd := FMemo.Widths(long + #9'x');
  AssertEquals('a cell past a stop moves the next column to the stop after it',
    (W(long) div t + 1) * t, wd[n + 1]);
end;

procedure TTyMemoTabTest.TestTheTokenSetsTheStop;
var
  sp: Integer;
begin
  sp := SpaceW;
  AssertEquals('the default: eight spaces', 8 * sp, FMemo.Widths(#9'x')[1]);
  FMemo.StyleOverride := '--memo-tab-size: 4';
  AssertEquals('this memo''s own: four spaces', 4 * sp, FMemo.Widths(#9'x')[1]);
  FMemo.StyleOverride := '--memo-tab-size: 40px';
  AssertEquals('a length, as CSS tab-size takes one', 40, FMemo.Widths(#9'x')[1]);
  FMemo.StyleOverride := '';
  AssertEquals('back to the default', 8 * sp, FMemo.Widths(#9'x')[1]);
  FCtl.StyleOverride := ':root { --memo-tab-size: 2; }';
  AssertEquals('the theme sets it for every memo', 2 * sp, FMemo.Widths(#9'x')[1]);
end;

procedure TTyMemoTabTest.TestTheStopScalesWithTheDpi;
begin
  AssertEquals('spaces: eight of the 192 dpi space', 8 * SpaceW(192), FMemo.Widths(#9'x', 192)[1]);
  FMemo.StyleOverride := '--memo-tab-size: 40px';
  AssertEquals('a length: logical px', 80, FMemo.Widths(#9'x', 192)[1]);
end;

procedure TTyMemoTabTest.TestTheDrawnTextFollows;
var
  bmp: TBGRABitmap;
  x0, t, aw, bw: Integer;
begin
  Load(['a'#9'b']);
  x0 := FMemo.StartX;
  t := 8 * SpaceW;
  aw := W('a');
  bw := W('b');
  AssertTrue('precondition: room between the a and the stop', aw + 6 < t);
  bmp := TBGRABitmap.Create(FMemo.Width, FMemo.Height);
  try
    FMemo.Render(bmp);
    AssertTrue('precondition: the a is drawn', InkIn(bmp, x0, x0 + aw));
    AssertFalse('nothing between the a and the stop', InkIn(bmp, x0 + aw + 2, x0 + t - 2));
    AssertTrue('the b is drawn at the stop', InkIn(bmp, x0 + t, x0 + t + bw));
  finally
    bmp.Free;
  end;
end;

procedure TTyMemoTabTest.TestAWrappedRowDrawsItsTabWhereItsCaretIs;
const
  LINE = 'aaaaaaaa bb'#9'c';
var
  bmp: TBGRABitmap;
  rows: TTyVisualRowArray;
  wd: TTyIntArray;
  x0, lh, cx, y0: Integer;
begin
  { the second row starts at "bb": its tab stop is counted from the LINE's start, and its
    text is drawn from the row's own left edge, so the c lands at the line's stop less the
    row's start -- where the caret and a click put it }
  Load([LINE]);
  FMemo.WordWrap := True;
  FMemo.Width := FMemo.Width - FMemo.ContentW + W('aaaaaaaa bb') - 2;
  rows := FMemo.Rows(FMemo.ContentW);
  AssertEquals('precondition: two rows', 2, Length(rows));
  AssertEquals('precondition: the second starts at "bb"', 9, rows[1].StartCol);
  wd := FMemo.Widths(LINE);
  cx := wd[12] - wd[9];
  x0 := FMemo.StartX;
  lh := FMemo.LH;
  y0 := lh + 6;
  bmp := TBGRABitmap.Create(FMemo.Width, FMemo.Height);
  try
    FMemo.Render(bmp);
    AssertTrue('precondition: the bb is drawn on the second row',
      InkIn(bmp, x0, x0 + W('bb'), y0, 2 * lh));
    AssertFalse('nothing between the bb and the stop',
      InkIn(bmp, x0 + W('bb') + 2, x0 + cx - 2, y0, 2 * lh));
    AssertTrue('the c at the stop, as the row measures it',
      InkIn(bmp, x0 + cx, x0 + cx + W('c'), y0, 2 * lh));
  finally
    bmp.Free;
  end;
end;

procedure TTyMemoTabTest.TestTheCaretAndAClickUseTheStops;
var
  wd: TTyIntArray;
  x0, t, mid: Integer;
begin
  Load(['a'#9'b']);
  x0 := FMemo.StartX;
  t := 8 * SpaceW;
  AssertEquals('the column after the tab', x0 + t, FMemo.ColX('a'#9'b', 2));
  wd := FMemo.Widths('a'#9'b');
  mid := x0 + (wd[1] + wd[2]) div 2;
  AssertEquals('a click just past the middle of the tab lands after it', 2,
    FMemo.ColAt('a'#9'b', mid + 1));
  AssertEquals('a click just short of it, before it', 1, FMemo.ColAt('a'#9'b', mid - 1));
  FMemo.SetCaret(0, 2);
  AssertEquals('the drawn caret', x0 + t, FMemo.CaretX);
end;

procedure TTyMemoTabTest.TestTheSelectionCoversTheTab;
var
  bmp: TBGRABitmap;
  x0, t, aw, y: Integer;
  bg, p: TBGRAPixel;
begin
  Load(['a'#9'b']);
  x0 := FMemo.StartX;
  t := 8 * SpaceW;
  aw := W('a');
  FMemo.Select(0, 1, 2);   { the tab alone }
  bmp := TBGRABitmap.Create(FMemo.Width, FMemo.Height);
  try
    FMemo.Render(bmp);
    y := 10;
    bg := bmp.GetPixel(x0 + t + W('b') + 20, y);
    p := bmp.GetPixel(x0 + (aw + t) div 2, y);
    AssertTrue('the band fills the tab''s width',
      (p.red <> bg.red) or (p.green <> bg.green) or (p.blue <> bg.blue));
    p := bmp.GetPixel(x0 + t + W('b') + 4, y);
    AssertTrue('and stops at the stop: past the b is the ground',
      (p.red = bg.red) and (p.green = bg.green) and (p.blue = bg.blue));
  finally
    bmp.Free;
  end;
end;

procedure TTyMemoTabTest.TestTheWrapCountsTheTab;
var
  rows: TTyVisualRowArray;
  t, cw: Integer;
begin
  Load(['aaa'#9'bbb']);
  t := 8 * SpaceW;
  cw := t + W('bbb') - 1;
  AssertTrue('precondition: without the tab''s width the line would fit', W('aaabbb') <= cw);
  FMemo.WordWrap := True;
  rows := FMemo.Rows(cw);
  AssertEquals('it wraps: the tab takes its room', 2, Length(rows));
  AssertTrue('at the tab', (rows[0].EndCol >= 3) and (rows[0].EndCol <= 4));
  AssertEquals('the rest on the second row', 7, rows[1].EndCol);
end;

procedure TTyMemoTabTest.TestTheWrappedRowsFollowTheToken;
begin
  Load(['a'#9'b']);
  FMemo.WordWrap := True;
  AssertEquals('precondition: one row at the default stop', 1, FMemo.Total);
  FMemo.StyleOverride := '--memo-tab-size: 600px';
  { the tab alone is wider than the row, so it gets one of its own: a, the tab, b }
  AssertEquals('a stop past the edge wraps the line', 3, FMemo.Total);
  FMemo.StyleOverride := '';
  AssertEquals('and back', 1, FMemo.Total);
end;

procedure TTyMemoTabTest.TestTheScrollRangeCountsTheTab;
var
  t: Integer;
begin
  Load(['aaa'#9'bbb', 'aaaa']);
  t := 8 * SpaceW;
  AssertTrue('precondition: the tab makes the line wider than its letters',
    W('aaabbb') < t + W('bbb'));
  AssertEquals('the widest line, tab and all', t + W('bbb'), FMemo.Widest);
end;

procedure TTyMemoTabTest.TestTheScrollRangeCountsATabInAShortLine;
var
  t: Integer;
begin
  { the widest-line scan estimates a line by its characters and measures only the lines
    that could win; a tab's advance is not a character's width, so a short line with a tab
    can be the widest though its letters are few }
  Load(['abcdefg', 'a'#9'b']);
  t := 8 * SpaceW;
  AssertTrue('precondition: the letters of the tab line are fewer',
    W('ab') + 12 < W('abcdefg'));
  AssertTrue('precondition: and it is the wider line', t + W('b') > W('abcdefg'));
  AssertEquals('the widest line is the one with the tab', t + W('b'), FMemo.Widest);
end;

initialization
  RegisterTest(TTyMemoTabTest);
end.
