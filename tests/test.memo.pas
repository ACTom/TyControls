unit test.memo;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, LazUTF8, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Memo;
type
  { Probe subclass: exposes protected helpers/fields for headless geometry tests }
  TTyMemoProbe = class(TTyMemo)
  public
    function ProbeLineHeight(APPI: Integer): Integer;
    function ProbeLineCountLogical: Integer;
    function ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
    function ProbeColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
    function ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
    function ProbeCaretLine: Integer;
    function ProbeCaretCol: Integer;
    procedure ProbeSetCaret(ALine, ACol: Integer);
  end;

  TTyMemoTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoProbe;
    procedure SetUpWithPadding(APaddingLeft: Integer);
  protected
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestEmptyLinesIsOneLogicalLine;
    procedure TestSetLinesClampsCaret;
    procedure TestLineHeightPositiveAndStable;
    procedure TestColPixelMonotonic;
    procedure TestColIndexRoundTrip;
    procedure TestCJKColMapping;
  end;

implementation

{ TTyMemoProbe }

function TTyMemoProbe.ProbeLineHeight(APPI: Integer): Integer;
begin
  Result := LineHeight(APPI);
end;

function TTyMemoProbe.ProbeLineCountLogical: Integer;
begin
  Result := LineCountLogical;
end;

function TTyMemoProbe.ProbeColPixelXAt(const ALine: string; ACol, APPI: Integer): Integer;
begin
  Result := ColPixelXAt(ALine, ACol, APPI);
end;

function TTyMemoProbe.ProbeColIndexAtX(const ALine: string; AX, APPI: Integer): Integer;
begin
  Result := ColIndexAtX(ALine, AX, APPI);
end;

function TTyMemoProbe.ProbeMeasureLineWidths(const ALine: string; APPI: Integer): TTyIntArray;
begin
  Result := MeasureLineWidths(ALine, APPI);
end;

function TTyMemoProbe.ProbeCaretLine: Integer;
begin
  Result := CaretLine;
end;

function TTyMemoProbe.ProbeCaretCol: Integer;
begin
  Result := CaretCol;
end;

procedure TTyMemoProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

{ TTyMemoTest }

procedure TTyMemoTest.SetUpWithPadding(APaddingLeft: Integer);
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(Format(
    'TyMemo { background:#FFFFFF; color:#000000; padding:%dpx; font-size:14px; }',
    [APaddingLeft]));
  FMemo := TTyMemoProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;
  FMemo.SetBounds(0, 0, 200, 120);
end;

procedure TTyMemoTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FCtl.Free;
  FCtl := nil;
end;

procedure TTyMemoTest.TestTypeKey;
begin
  SetUpWithPadding(0);
  AssertEquals('TyMemo', (FMemo as ITyStyleable).GetStyleTypeKey);
end;

procedure TTyMemoTest.TestEmptyLinesIsOneLogicalLine;
begin
  SetUpWithPadding(0);
  AssertEquals('fresh memo has 1 logical line', 1, FMemo.ProbeLineCountLogical);
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 0', 0, FMemo.ProbeCaretCol);
end;

procedure TTyMemoTest.TestSetLinesClampsCaret;
var
  L: TStringList;
begin
  SetUpWithPadding(0);
  // Start with 3 lines
  L := TStringList.Create;
  try
    L.Add('line one');
    L.Add('line two');
    L.Add('line three');
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  // Move caret to (2,5) — valid in the 3-line model
  FMemo.ProbeSetCaret(2, 5);
  AssertEquals('caret line is 2', 2, FMemo.ProbeCaretLine);

  // Now assign a 2-line list; caret (2,5) is no longer valid and must clamp
  L := TStringList.Create;
  try
    L.Add('alpha');
    L.Add('be');
    FMemo.Lines := L;
  finally
    L.Free;
  end;
  AssertEquals('logical line count is 2 after reassign', 2, FMemo.ProbeLineCountLogical);
  AssertTrue('caret line clamped into [0,1]',
    (FMemo.ProbeCaretLine >= 0) and (FMemo.ProbeCaretLine <= 1));
  AssertTrue('caret col clamped to its line length',
    FMemo.ProbeCaretCol <= UTF8Length(FMemo.Lines[FMemo.ProbeCaretLine]));
end;

procedure TTyMemoTest.TestLineHeightPositiveAndStable;
var
  H1, H2: Integer;
begin
  SetUpWithPadding(0);
  H1 := FMemo.ProbeLineHeight(96);
  H2 := FMemo.ProbeLineHeight(96);
  AssertTrue('LineHeight(96) > 0', H1 > 0);
  AssertEquals('LineHeight stable across calls', H1, H2);
end;

procedure TTyMemoTest.TestColPixelMonotonic;
var
  x0, x1, x2, x3: Integer;
  ExpectedLeft: Integer;
begin
  SetUpWithPadding(6);
  x0 := FMemo.ProbeColPixelXAt('abc', 0, 96);
  x1 := FMemo.ProbeColPixelXAt('abc', 1, 96);
  x2 := FMemo.ProbeColPixelXAt('abc', 2, 96);
  x3 := FMemo.ProbeColPixelXAt('abc', 3, 96);
  // Padding.Left = 6px scaled at PPI 96 = 6
  ExpectedLeft := MulDiv(6, 96, 96);
  AssertEquals('ColPixelXAt(line,0) = Padding.Left scaled', ExpectedLeft, x0);
  AssertTrue('x1 > x0', x1 > x0);
  AssertTrue('x2 > x1', x2 > x1);
  AssertTrue('x3 > x2', x3 > x2);
end;

procedure TTyMemoTest.TestColIndexRoundTrip;
const
  Line = 'Hello World';
var
  k, px, got: Integer;
begin
  SetUpWithPadding(4);
  for k := 0 to UTF8Length(Line) do
  begin
    px := FMemo.ProbeColPixelXAt(Line, k, 96);
    got := FMemo.ProbeColIndexAtX(Line, px, 96);
    AssertEquals('round-trip col ' + IntToStr(k), k, got);
  end;
end;

procedure TTyMemoTest.TestCJKColMapping;
const
  Line = 'a中b';  // 3 codepoints, 5 bytes
var
  W: TTyIntArray;
  px1, px2, idx: Integer;
begin
  SetUpWithPadding(0);
  W := FMemo.ProbeMeasureLineWidths(Line, 96);
  AssertEquals('MeasureLineWidths length = codepoints+1', 4, Length(W));
  // Indices map at codepoint granularity, not byte granularity.
  // Boundary after codepoint 1 ('a') should round-trip to index 1.
  px1 := FMemo.ProbeColPixelXAt(Line, 1, 96);
  idx := FMemo.ProbeColIndexAtX(Line, px1, 96);
  AssertEquals('codepoint boundary 1 maps to col 1', 1, idx);
  // Boundary after codepoint 2 ('中') -> col 2
  px2 := FMemo.ProbeColPixelXAt(Line, 2, 96);
  idx := FMemo.ProbeColIndexAtX(Line, px2, 96);
  AssertEquals('codepoint boundary 2 maps to col 2', 2, idx);
end;

initialization
  RegisterTest(TTyMemoTest);
end.
