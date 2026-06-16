unit test.memo.props;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, StdCtrls, LCLType, LazUTF8,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.StyleModel, tyControls.Base,
  tyControls.ScrollBar,
  tyControls.Memo;
type
  { Probe subclass: exposes just what the Task-10 property tests need on top of the
    published API (the flat Sel*/CaretPos/Text/WantTabs/WantReturns/ScrollBars are
    public/published, so most are reached directly). Adds a force-focused hook and a
    scrollbar-visibility probe so the ScrollBars=ssNone test can assert the embedded
    bar stays hidden even under overflow, plus injectors for Tab/Enter. }
  TTyMemoPropsProbe = class(TTyMemo)
  public
    procedure ProbeInjectKey(AKey: Word; AShift: TShiftState);
    function ProbeScrollBarVisible: Boolean;
    function ProbeLineCount: Integer;
    function ProbeLine(AIndex: Integer): string;
    function ProbeCaretLine: Integer;
    function ProbeCaretCol: Integer;
    procedure ProbeSetCaret(ALine, ACol: Integer);
    procedure ProbeSetAnchor(ALine, ACol: Integer);
  end;

  TTyMemoPropsTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoPropsProbe;
    FChangeCount: Integer;
    procedure SetUpMemo;
    procedure OnMemoChange(Sender: TObject);
    procedure LoadLines(const AItems: array of string);
  protected
    procedure TearDown; override;
  published
    procedure TestFlatSelAndCaretPos;
    procedure TestTextAccessor;
    procedure TestWantReturnsFalseNoNewline;
    procedure TestWantTabsTrueInsertsTab;
    procedure TestScrollBarsNoneHidesScrollbar;
  end;

implementation

{ TTyMemoPropsProbe }

procedure TTyMemoPropsProbe.ProbeInjectKey(AKey: Word; AShift: TShiftState);
var
  K: Word;
begin
  K := AKey;
  KeyDown(K, AShift);
end;

function TTyMemoPropsProbe.ProbeScrollBarVisible: Boolean;
begin
  // The embedded vertical scrollbar is nil until first needed; a nil bar counts
  // as not-visible. Force the scrollbar geometry to settle first.
  UpdateScrollBar;
  Result := ScrollBarVisible;
end;

function TTyMemoPropsProbe.ProbeLineCount: Integer;
begin
  Result := Lines.Count;
end;

function TTyMemoPropsProbe.ProbeLine(AIndex: Integer): string;
begin
  Result := Lines[AIndex];
end;

function TTyMemoPropsProbe.ProbeCaretLine: Integer;
begin
  Result := CaretLine;
end;

function TTyMemoPropsProbe.ProbeCaretCol: Integer;
begin
  Result := CaretCol;
end;

procedure TTyMemoPropsProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

procedure TTyMemoPropsProbe.ProbeSetAnchor(ALine, ACol: Integer);
begin
  SetSelAnchor(ALine, ACol);
end;

{ TTyMemoPropsTest }

procedure TTyMemoPropsTest.SetUpMemo;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo := TTyMemoPropsProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;
  FMemo.SetBounds(0, 0, 200, 120);
  FChangeCount := 0;
  FMemo.OnChange := @OnMemoChange;
end;

procedure TTyMemoPropsTest.OnMemoChange(Sender: TObject);
begin
  Inc(FChangeCount);
end;

procedure TTyMemoPropsTest.LoadLines(const AItems: array of string);
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

procedure TTyMemoPropsTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FCtl.Free;
  FCtl := nil;
end;

{ TestFlatSelAndCaretPos
  Multi-line model 'ab' / 'cde' / 'f'. The flat codepoint offset counts the newline
  between lines as one codepoint, so the flat origin of each line is:
    line0 'ab'  -> 0
    line1 'cde' -> 3  (len 2 + 1 newline)
    line2 'f'   -> 7  (3 + 3 + 1)
  CaretPos := 5 lands on line1 col2 (offset 3 + 2). A selection anchored at flat 1
  ('a|b') to caret flat 6 ('cde|') has SelStart=1, SelLength=5, and SelText spans the
  newline: 'b' + LineEnding + 'cde'. }
procedure TTyMemoPropsTest.TestFlatSelAndCaretPos;
begin
  SetUpMemo;
  LoadLines(['ab', 'cde', 'f']);

  // CaretPos write maps flat offset -> (line,col); read maps back.
  FMemo.CaretPos := 5;
  AssertEquals('caret line for flat 5', 1, FMemo.ProbeCaretLine);
  AssertEquals('caret col for flat 5', 2, FMemo.ProbeCaretCol);
  AssertEquals('CaretPos reads back flat 5', 5, FMemo.CaretPos);

  // SelStart/SelLength write: place a selection from flat 1 to flat 6.
  FMemo.SelStart := 1;
  FMemo.SelLength := 5;
  AssertEquals('SelStart reads flat 1', 1, FMemo.SelStart);
  AssertEquals('SelLength reads 5', 5, FMemo.SelLength);
  AssertEquals('SelText spans the newline', 'b' + LineEnding + 'cde', FMemo.SelText);
  // Caret sits at the far end of the selection (flat 6).
  AssertEquals('CaretPos at selection end flat 6', 6, FMemo.CaretPos);

  // SelText write replaces the selection ('b'<LE>'cde') with 'Z' (one OnChange):
  // deleting flat[1..6] merges line0 head 'a' with line1 tail '' -> 'a', leaving
  // line2 'f' below; inserting 'Z' at the caret yields line0 'aZ', line1 'f'.
  FChangeCount := 0;
  FMemo.SelText := 'Z';
  AssertEquals('after replace: 2 lines', 2, FMemo.ProbeLineCount);
  AssertEquals('after replace: line 0 = aZ', 'aZ', FMemo.ProbeLine(0));
  AssertEquals('after replace: line 1 = f', 'f', FMemo.ProbeLine(1));
  AssertEquals('SelText write fires OnChange once', 1, FChangeCount);
end;

{ TestTextAccessor
  Text:= sets all lines from a whole string split on line breaks; Text reads the
  whole string back joined with the platform line break (TStrings.Text semantics). }
procedure TTyMemoPropsTest.TestTextAccessor;
begin
  SetUpMemo;
  FChangeCount := 0;
  FMemo.Text := 'one' + LineEnding + 'two' + LineEnding + 'three';
  AssertEquals('Text set: 3 lines', 3, FMemo.ProbeLineCount);
  AssertEquals('line 0', 'one', FMemo.ProbeLine(0));
  AssertEquals('line 1', 'two', FMemo.ProbeLine(1));
  AssertEquals('line 2', 'three', FMemo.ProbeLine(2));
  // Text reads = TStrings.Text, which appends a trailing line break after the last
  // line (native TMemo.Text semantics via Lines.Text).
  AssertEquals('Text read = whole string with trailing break',
    'one' + LineEnding + 'two' + LineEnding + 'three' + LineEnding, FMemo.Text);
  AssertTrue('Text write fired OnChange', FChangeCount >= 1);
end;

{ TestWantReturnsFalseNoNewline
  WantReturns:=False -> Enter does NOT insert a line break (the form's default
  button would handle it). The model stays one line. With the default (True) Enter
  splits as usual. }
procedure TTyMemoPropsTest.TestWantReturnsFalseNoNewline;
begin
  SetUpMemo;
  LoadLines(['abc']);
  FMemo.WantReturns := False;
  FMemo.ProbeSetCaret(0, 1);
  FMemo.ProbeInjectKey(VK_RETURN, []);
  AssertEquals('WantReturns=False: still one line', 1, FMemo.ProbeLineCount);
  AssertEquals('WantReturns=False: text unchanged', 'abc', FMemo.ProbeLine(0));

  // Sanity: default WantReturns=True still splits.
  FMemo.WantReturns := True;
  FMemo.ProbeSetCaret(0, 1);
  FMemo.ProbeInjectKey(VK_RETURN, []);
  AssertEquals('WantReturns=True: split into two lines', 2, FMemo.ProbeLineCount);
end;

{ TestWantTabsTrueInsertsTab
  WantTabs:=True -> a Tab key inserts a literal tab char into the text. With the
  default (False) Tab navigates and does not mutate the text. }
procedure TTyMemoPropsTest.TestWantTabsTrueInsertsTab;
begin
  SetUpMemo;
  LoadLines(['ab']);
  FMemo.WantTabs := True;
  FMemo.ProbeSetCaret(0, 1);
  FMemo.ProbeInjectKey(VK_TAB, []);
  AssertEquals('WantTabs=True: tab inserted between a and b', 'a' + #9 + 'b',
    FMemo.ProbeLine(0));
  AssertEquals('caret advanced past the tab', 2, FMemo.ProbeCaretCol);

  // Sanity: default WantTabs=False does NOT insert a tab (Tab navigates instead).
  LoadLines(['ab']);
  FMemo.WantTabs := False;
  FMemo.ProbeSetCaret(0, 1);
  FMemo.ProbeInjectKey(VK_TAB, []);
  AssertEquals('WantTabs=False: text unchanged (no tab inserted)', 'ab',
    FMemo.ProbeLine(0));
end;

{ TestScrollBarsNoneHidesScrollbar
  Fill the memo with enough lines to overflow the visible window. With the default
  ScrollBars (ssAutoVertical) the embedded bar shows. With ScrollBars:=ssNone the
  bar must stay hidden even though the content overflows. }
procedure TTyMemoPropsTest.TestScrollBarsNoneHidesScrollbar;
var
  L: TStringList;
  i: Integer;
begin
  SetUpMemo;
  L := TStringList.Create;
  try
    for i := 0 to 99 do
      L.Add('line ' + IntToStr(i));
    FMemo.Lines := L;
  finally
    L.Free;
  end;

  // Default ScrollBars = ssAutoVertical: overflow shows the bar.
  AssertTrue('default ScrollBars shows the bar under overflow',
    FMemo.ProbeScrollBarVisible);

  // ssNone hides the embedded bar entirely, even under overflow.
  FMemo.ScrollBars := ssNone;
  AssertFalse('ScrollBars=ssNone hides the bar under overflow',
    FMemo.ProbeScrollBarVisible);

  // ssVertical forces it visible again.
  FMemo.ScrollBars := ssVertical;
  AssertTrue('ScrollBars=ssVertical shows the bar', FMemo.ProbeScrollBarVisible);
end;

initialization
  RegisterTest(TTyMemoPropsTest);
end.
