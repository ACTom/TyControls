unit test.terminal.view.mouse;
{$mode objfpc}{$H+}
{ TTyTerminalView 的鼠标(4 期):谁拿鼠标(上报 / 本地选择 / 中键 PRIMARY / 右键菜单)、
  上报的字节、捕获、横向滚轮、选区的接线(多击、列选、自动滚、跟着输出走、该清时清、
  复制、CopyOnSelect、PRIMARY、事件次数)、右键菜单与指针形状。

  坐标一律取 CellRect 算出的格子内像素(探针的 CellLeft / CellCenter / CellRight),不写死
  像素。选区的取整规则(点在格子右半从下一格边界算)由 test.terminal.selection 对上游
  逐像素守着;这里只看接线。平台一律先设成 Windows、PRIMARY 关(与跑测试的机器无关),
  要 macOS 或 X11 的测试自己改。 }

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, Menus, LCLType, fpcunit, testregistry,
  tyControls.Terminal.Buffer, tyControls.Terminal.Core, tyControls.Terminal.Selection, tyControls.Terminal,
  tyControls.StrConsts, test.terminal.keyboard, test.terminal.view;

type
  TTyTerminalViewMouseTests = class(TTestCase)
  private
    F: TTyTermViewFixture;
    FChanges: Integer;
    procedure OnSel(Sender: TObject);
    function V: TTyTerminalViewProbe;
    function Hex: string;
    procedure Reset;
    function Lines(AFrom, ACount: Integer): RawByteString;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestButtonMappingMatchesUpstream;
    procedure TestWithoutProtocolADragSelects;
    procedure TestPressAndReleaseAreReported;
    procedure TestDragsFollowTheProtocol;
    procedure TestTheRouteIsKeptUntilRelease;
    procedure TestOverrideKeyValues;
    procedure TestModifiersAreReported;
    procedure TestMiddleAndRightAreReported;
    procedure TestAllThreeButtonsCapture;
    procedure TestADragOutsideIsClampedToTheGrid;
    procedure TestTheSidewaysWheel;
    procedure TestTakingTheMouseClearsTheSelection;
    procedure TestShiftClickExtendsOnlyWithoutAProtocol;
    procedure TestDoubleAndTripleClicks;
    procedure TestAltDragIsAColumn;
    procedure TestDraggingOffTheTopScrolls;
    procedure TestTheSelectionFollowsOutput;
    procedure TestTypingClearsTheSelection;
    procedure TestWhenTheSelectionIsCleared;
    procedure TestSelectAllOnTheMac;
    procedure TestCopyWritesTheSelection;
    procedure TestCopyOnSelect;
    procedure TestThePrimarySelection;
    procedure TestSelectionEventsCount;
    procedure TestTheMenuWithoutAProtocol;
    procedure TestAReportedRightClickHasNoMenu;
    procedure TestTheMenuBeforeThePress;
    procedure TestOverrideRightClickShowsTheMenu;
    procedure TestTheHostsPopupMenuWins;
    procedure TestMenuItemsAct;
    procedure TestTheMenuKeyOpensAtTheCursor;
    procedure TestRightClickKeepsTheSelection;
    procedure TestRightClickSelectsAWordOnTheMac;
    procedure TestPointerShapes;
    { 4 期期末审查 }
    procedure TestALostReleaseIsFinished;
    procedure TestAPressWhoseReleaseWentElsewhere;
    procedure TestX10HandsTheSidewaysWheelBack;
    procedure TestEveryProtocolChangeClearsTheSelection;
    procedure TestSelectIsClamped;
    procedure TestTheMenuDoesNotReadTheClipboard;
    procedure TestTheMacSelectsAWordForTheHostsMenuToo;
    procedure TestPrimaryIsOfferedNotBuilt;
    procedure TestCopyingTenThousandRowsIsQuick;
    procedure TestAWordWrappedOverManyRows;
  end;

implementation

uses
  fpjson, test.terminal.oracle;

const
  Sgr1006 = #27'[?1000h'#27'[?1006h';

procedure TTyTerminalViewMouseTests.SetUp;
begin
  F := TTyTermViewFixture.Create;
  F.SizeTo(20, 5);
  F.View.SetPlatform(False, True);
  F.View.SetPrimaryPlatform(False);
  F.View.OnSelectionChange := @OnSel;
  FChanges := 0;
end;

procedure TTyTerminalViewMouseTests.TearDown;
begin
  FreeAndNil(F);
end;

procedure TTyTerminalViewMouseTests.OnSel(Sender: TObject);
begin
  Inc(FChanges);
end;

function TTyTerminalViewMouseTests.V: TTyTerminalViewProbe;
begin
  Result := F.View;
end;

function TTyTerminalViewMouseTests.Hex: string;
begin
  Result := TyTermHex(F.Data);
end;

procedure TTyTerminalViewMouseTests.Reset;
begin
  F.Data := '';
  F.DataEvents := 0;
end;

function TTyTerminalViewMouseTests.Lines(AFrom, ACount: Integer): RawByteString;
var
  i: Integer;
begin
  Result := '';
  for i := AFrom to AFrom + ACount - 1 do
    Result := Result + 'line-' + IntToStr(i) + #13#10;
end;

function Sgr(ACode, ACol, ARow: Integer; APress: Boolean): string;
var
  s: RawByteString;
begin
  s := #27'[<' + IntToStr(ACode) + ';' + IntToStr(ACol + 1) + ';' + IntToStr(ARow + 1);
  if APress then s := s + 'M' else s := s + 'm';
  Result := TyTermHex(s);
end;

{ terminal-mouse-events.json's send part: the buttons _sendEvent passes on, for LCL's
  events. A press / release of the DOM's button b is LCL's b (0 left, 1 middle, 2 right,
  3 / 4 the extra buttons); a move's buttons bits (1 left, 2 right, 4 middle) are the
  Shift state's ssLeft / ssRight / ssMiddle. Upstream passes NONE on for the extra
  buttons' press and release, and the core drops a NONE that is not a move -- the control
  does not send it at all, which is the same on the wire. }
procedure TTyTerminalViewMouseTests.TestButtonMappingMatchesUpstream;
const
  Buttons: array[0..4] of TMouseButton = (mbLeft, mbMiddle, mbRight, mbExtra1, mbExtra2);
  Actions: array[0..2] of TTyTerminalMouseAction = (tmaDown, tmaUp, tmaMove);
var
  miss: TTyTermMisses;
  fx: TTyTermFixtures;
  rows, r, o: TJSONArray;
  i, want, got: Integer;
  shift: TShiftState;
  b: TTyTerminalMouseButton;
begin
  miss := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('mouse-events', miss);
    try
      rows := fx[0].Arrays['send'];
      for i := 0 to rows.Count - 1 do
      begin
        r := rows.Arrays[i];
        shift := [];
        if r.Integers[0] = 2 then
        begin
          if r.Integers[2] and 1 <> 0 then Include(shift, ssLeft);
          if r.Integers[2] and 2 <> 0 then Include(shift, ssRight);
          if r.Integers[2] and 4 <> 0 then Include(shift, ssMiddle);
        end;
        b := TyTerminalMouseButtonFor(Actions[r.Integers[0]], Buttons[r.Integers[1]], shift);
        if r.Items[6].JSONType = jtNull then
          want := -1
        else
        begin
          o := TJSONArray(r.Items[6]);
          want := o.Integers[0];
          { the modifiers go through unchanged }
          miss.AddCompared;
          if (o.Booleans[2] <> r.Booleans[3]) or (o.Booleans[3] <> r.Booleans[4]) or (o.Booleans[4] <> r.Booleans[5]) then
            miss.Add(IntToStr(i), 'modifiers', 'passed on', 'changed');
        end;
        got := Ord(b);
        miss.AddCompared;
        if want <> got then
          miss.Add(Format('type %d button %d buttons %d', [r.Integers[0], r.Integers[1], r.Integers[2]]),
            'button', IntToStr(want), IntToStr(got));
      end;
      AssertEquals(miss.Text, 0, miss.Count);
      AssertTrue('rows read', rows.Count > 40);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    miss.Free;
  end;
  AssertTrue('tmbNone is 3, as upstream''s NONE', Ord(tmbNone) = 3);
end;

procedure TTyTerminalViewMouseTests.TestWithoutProtocolADragSelects;
begin
  V.WriteSync('hello world');
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 0));
  V.MoveTo([ssLeft], V.CellRight(5, 0));
  V.Up(mbLeft, [], V.CellRight(5, 0));
  AssertEquals('the right half of a cell reaches the next boundary', 'hello ', V.SelectionText);
  AssertEquals('nothing reported', '', Hex);
  AssertTrue('the route was the selection', V.MouseRoute = mrNone);
end;

procedure TTyTerminalViewMouseTests.TestPressAndReleaseAreReported;
begin
  V.WriteSync(Sgr1006);
  V.Down(mbLeft, [ssLeft], V.CellCenter(2, 1));
  AssertEquals('press', Sgr(0, 2, 1, True), Hex);
  Reset;
  V.Up(mbLeft, [], V.CellCenter(2, 1));
  AssertEquals('release', Sgr(0, 2, 1, False), Hex);
  AssertFalse('no selection', V.HasSelection);
end;

procedure TTyTerminalViewMouseTests.TestDragsFollowTheProtocol;
begin
  { 1000: presses only }
  V.WriteSync(Sgr1006);
  V.Down(mbLeft, [ssLeft], V.CellCenter(1, 1));
  Reset;
  V.MoveTo([ssLeft], V.CellCenter(3, 1));
  AssertEquals('1000: no drags', '', Hex);
  V.Up(mbLeft, [], V.CellCenter(3, 1));
  { 1002: drags }
  V.WriteSync(#27'[?1002h');
  V.Down(mbLeft, [ssLeft], V.CellCenter(1, 1));
  Reset;
  V.MoveTo([ssLeft], V.CellCenter(3, 1));
  AssertEquals('1002: a drag', Sgr(32, 3, 1, True), Hex);
  V.Up(mbLeft, [], V.CellCenter(3, 1));
  Reset;
  V.MoveTo([], V.CellCenter(5, 2));
  AssertEquals('1002: no plain moves', '', Hex);
  { 1003: plain moves }
  V.WriteSync(#27'[?1003h');
  Reset;
  V.MoveTo([], V.CellCenter(6, 2));
  AssertEquals('1003: a plain move', Sgr(35, 6, 2, True), Hex);
  { 1002, middle and right held: middle before right }
  V.WriteSync(#27'[?1003l'#27'[?1002h');
  V.Down(mbMiddle, [ssMiddle], V.CellCenter(1, 3));
  Reset;
  V.MoveTo([ssMiddle, ssRight], V.CellCenter(2, 3));
  AssertEquals('middle before right', Sgr(33, 2, 3, True), Hex);
  V.Up(mbMiddle, [], V.CellCenter(2, 3));
end;

procedure TTyTerminalViewMouseTests.TestTheRouteIsKeptUntilRelease;
begin
  V.WriteSync(#27'[?1002h'#27'[?1006h');
  V.WriteSync('hello world');
  V.Down(mbLeft, [ssLeft, ssShift], V.CellLeft(0, 0));
  AssertTrue('the override key keeps it local', V.MouseRoute = mrSelect);
  V.MoveTo([ssLeft], V.CellRight(3, 0));
  AssertTrue('still selecting with Shift let go', V.MouseRoute = mrSelect);
  AssertEquals('nothing reported', '', Hex);
  V.Up(mbLeft, [], V.CellRight(3, 0));
  AssertEquals('selected', 'hell', V.SelectionText);
  V.Down(mbLeft, [ssLeft], V.CellCenter(1, 0));
  AssertTrue('a new press without Shift is reported', F.Data <> '');
  V.Up(mbLeft, [], V.CellCenter(1, 0));
end;

procedure TTyTerminalViewMouseTests.TestOverrideKeyValues;
begin
  V.WriteSync(Sgr1006);
  { Windows, default: Shift }
  V.ClickAt(mbLeft, [ssShift], V.CellCenter(1, 1));
  AssertEquals('Windows: Shift is local', '', Hex);
  { macOS, default: Option (Alt); Shift is reported, shift bit and all }
  V.SetPlatform(True, False);
  V.ClickAt(mbLeft, [ssAlt], V.CellCenter(1, 1));
  AssertEquals('macOS: Alt is local', '', Hex);
  V.Down(mbLeft, [ssLeft, ssShift], V.CellCenter(1, 1));
  AssertEquals('macOS: Shift is reported', Sgr(4, 1, 1, True), Hex);
  V.Up(mbLeft, [ssShift], V.CellCenter(1, 1));
  { tsoAlt on Windows }
  V.SetPlatform(False, True);
  V.SelectionOverrideKey := tsoAlt;
  Reset;
  V.ClickAt(mbLeft, [ssAlt], V.CellCenter(1, 1));
  AssertEquals('tsoAlt: Alt is local', '', Hex);
  { tsoNone: nothing is }
  V.SelectionOverrideKey := tsoNone;
  V.Down(mbLeft, [ssLeft, ssShift], V.CellCenter(1, 1));
  AssertEquals('tsoNone: Shift is reported', Sgr(4, 1, 1, True), Hex);
  V.Up(mbLeft, [ssShift], V.CellCenter(1, 1));
end;

procedure TTyTerminalViewMouseTests.TestModifiersAreReported;
begin
  V.WriteSync(Sgr1006);
  V.Down(mbLeft, [ssLeft, ssCtrl, ssAlt], V.CellCenter(1, 1));
  AssertEquals('Ctrl 16 + Alt 8', Sgr(24, 1, 1, True), Hex);
end;

procedure TTyTerminalViewMouseTests.TestMiddleAndRightAreReported;
begin
  V.WriteSync(Sgr1006);
  V.Down(mbMiddle, [ssMiddle], V.CellCenter(1, 1));
  AssertEquals('middle', Sgr(1, 1, 1, True), Hex);
  V.Up(mbMiddle, [], V.CellCenter(1, 1));
  Reset;
  V.Down(mbRight, [ssRight], V.CellCenter(1, 1));
  AssertEquals('right', Sgr(2, 1, 1, True), Hex);
  V.Up(mbRight, [], V.CellCenter(1, 1));
  Reset;
  V.Down(mbExtra1, [], V.CellCenter(1, 1));
  V.Up(mbExtra1, [], V.CellCenter(1, 1));
  AssertEquals('the fourth button: nothing', '', Hex);
end;

procedure TTyTerminalViewMouseTests.TestAllThreeButtonsCapture;
begin
  AssertTrue('left, middle and right capture the mouse', V.CaptureMouseButtons = [mbLeft, mbMiddle, mbRight]);
end;

procedure TTyTerminalViewMouseTests.TestADragOutsideIsClampedToTheGrid;
begin
  V.WriteSync(#27'[?1002h'#27'[?1006h');
  V.Down(mbLeft, [ssLeft], V.CellCenter(1, 1));
  Reset;
  V.MoveTo([ssLeft], -50, 10000);
  AssertEquals('clamped to the first column, the last row', Sgr(32, 0, 4, True), Hex);
  V.Up(mbLeft, [], -50, 10000);
end;

procedure TTyTerminalViewMouseTests.TestTheSidewaysWheel;
begin
  V.WriteSync(Sgr1006);
  AssertTrue('taken', V.WheelHorz([], -120, V.CellCenter(1, 1)));
  AssertEquals('left: 66', Sgr(66, 1, 1, True), Hex);
  Reset;
  V.WheelHorz([], 120, V.CellCenter(1, 1));
  AssertEquals('right: 67', Sgr(67, 1, 1, True), Hex);
  Reset;
  V.WheelHorz([], 60, V.CellCenter(1, 1));
  AssertEquals('half a notch: nothing yet', '', Hex);
  V.WheelHorz([], 60, V.CellCenter(1, 1));
  AssertEquals('the second half: one', Sgr(67, 1, 1, True), Hex);
  V.WriteSync(#27'[?1000l');
  Reset;
  AssertFalse('no protocol: handed back', V.WheelHorz([], -120, V.CellCenter(1, 1)));
  AssertEquals('nothing sent', '', Hex);
end;

procedure TTyTerminalViewMouseTests.TestTakingTheMouseClearsTheSelection;
begin
  V.WriteSync('hello world');
  V.Select(0, V.Core.Buffer.YBase, 5);
  AssertTrue('selected', V.HasSelection);
  FChanges := 0;
  V.WriteSync(#27'[?1000h');
  AssertFalse('the program took the mouse: cleared', V.HasSelection);
  AssertEquals('one change', 1, FChanges);
end;

procedure TTyTerminalViewMouseTests.TestShiftClickExtendsOnlyWithoutAProtocol;
begin
  V.WriteSync('hello world');
  V.ClickAt(mbLeft, [], V.CellLeft(0, 0));
  V.ClickAt(mbLeft, [ssShift], V.CellLeft(4, 0));
  AssertEquals('extended', 'hell', V.SelectionText);
  V.WriteSync(#27'[?1000h');
  V.ClickAt(mbLeft, [ssShift], V.CellLeft(2, 0));
  AssertFalse('a program has the mouse: Shift is the override key, a new start', V.HasSelection);
  AssertTrue('the start is where it was pressed', V.Sel.Model.HasStart and (V.Sel.Model.Start.Col = 2));
end;

procedure TTyTerminalViewMouseTests.TestDoubleAndTripleClicks;
begin
  V.WriteSync('foo bar.baz qux');
  V.ClickAt(mbLeft, [], V.CellCenter(5, 0));
  V.ClickAt(mbLeft, [ssDouble], V.CellCenter(5, 0));
  AssertEquals('a double click: the word (the full stop is no separator)', 'bar.baz', V.SelectionText);
  V.ClickAt(mbLeft, [], V.CellCenter(5, 0));
  AssertEquals('the third: the line', 'foo bar.baz qux', V.SelectionText);
end;

procedure TTyTerminalViewMouseTests.TestAltDragIsAColumn;
begin
  V.WriteSync('abcdef'#13#10'abcdef'#13#10'abcdef');
  V.Down(mbLeft, [ssLeft, ssAlt], V.CellLeft(1, 0));
  V.MoveTo([ssLeft, ssAlt], V.CellLeft(3, 2));
  V.Up(mbLeft, [ssAlt], V.CellLeft(3, 2));
  AssertTrue('a column', V.Sel.Mode = tsmColumn);
  AssertEquals('three rows of two', 'bc' + LineEnding + 'bc' + LineEnding + 'bc', V.SelectionText);
  { macOS, the default override (Option) and a program with the mouse: Alt is the
    override key, so the selection is local but not a column }
  V.SetPlatform(True, False);
  V.WriteSync(#27'[?1000h');
  V.Down(mbLeft, [ssLeft, ssAlt], V.CellLeft(1, 0));
  V.MoveTo([ssLeft, ssAlt], V.CellLeft(3, 2));
  V.Up(mbLeft, [ssAlt], V.CellLeft(3, 2));
  AssertTrue('local', V.HasSelection);
  AssertTrue('not a column', V.Sel.Mode <> tsmColumn);
  AssertEquals('nothing reported', '', Hex);
end;

procedure TTyTerminalViewMouseTests.TestDraggingOffTheTopScrolls;
var
  top, ydisp, want: Integer;
  r: TRect;
begin
  V.WriteSync(Lines(0, 100));
  r := V.CellRect(0, 0);
  top := r.Top;
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 2));
  AssertTrue('the drag timer runs', V.DragTimerOn);
  V.MoveTo([ssLeft], V.CellLeft(3, 0).X, top - 30);
  ydisp := V.Core.Buffer.YDisp;
  want := TyTermDragScrollAmount(-30, V.Rows * (r.Bottom - r.Top), MulDiv(50, V.Font.PixelsPerInch, 96));
  AssertTrue('above: a negative speed', want < 0);
  V.TickDrag;
  AssertEquals('scrolled by the speed', ydisp + want, V.Core.Buffer.YDisp);
  AssertTrue('an end', V.Sel.Model.HasEnd);
  AssertEquals('the end moved to the top row', V.Core.Buffer.YDisp, V.Sel.Model.Finish.Row);
  V.Up(mbLeft, [], V.CellLeft(3, 0).X, top - 30);
  AssertFalse('stopped', V.DragTimerOn);
end;

procedure TTyTerminalViewMouseTests.TestTheSelectionFollowsOutput;
begin
  V.Scrollback := 10;
  V.WriteSync(Lines(0, 12));
  V.SelectLines(3, 3);
  AssertEquals('line-3', V.SelectionText);
  V.WriteSync(Lines(12, 3));
  AssertEquals('it moved with its line', 'line-3', V.SelectionText);
  V.WriteSync(Lines(15, 20));
  AssertFalse('trimmed away', V.HasSelection);
end;

procedure TTyTerminalViewMouseTests.TestTypingClearsTheSelection;
var
  ch: TUTF8Char;
begin
  V.WriteSync('hello');
  V.Select(0, V.Core.Buffer.YBase, 3);
  ch := 'x';
  V.TypeChar(ch);
  AssertFalse('typing clears', V.HasSelection);
  V.ReadOnly := True;
  V.Select(0, V.Core.Buffer.YBase, 3);
  ch := 'x';
  V.TypeChar(ch);
  AssertTrue('read-only: nothing is typed, nothing cleared', V.HasSelection);
end;

procedure TTyTerminalViewMouseTests.TestWhenTheSelectionIsCleared;

  procedure Pick;
  begin
    V.Select(0, V.Core.Buffer.YBase, 3);
    FChanges := 0;
  end;

var
  wp: TTyTerminalWindowsPty;
begin
  V.WriteSync(Lines(0, 10) + 'hello world');
  { phase 5: a new column count that rewraps the buffer clears (the plan's question one
    #2; upstream keeps the coordinates, SelectionService.ts:158-162 -- "pinned the
    no-reflow answer" before) ... }
  Pick;
  F.SizeTo(25, 5);
  AssertEquals('25 columns', 25, V.Cols);
  AssertFalse('more columns, rewrapped: cleared', V.HasSelection);
  AssertEquals('one change (columns)', 1, FChanges);
  { ... one that does not (an old ConPTY) keeps it, as upstream }
  wp.Backend := twpConPty;
  wp.BuildNumber := 19044;
  V.Core.WindowsPty := wp;
  Pick;
  F.SizeTo(27, 5);
  AssertEquals('27 columns', 27, V.Cols);
  AssertTrue('more columns, not rewrapped: kept', V.HasSelection);
  AssertEquals('no change', 0, FChanges);
  F.SizeTo(25, 5);
  wp.Backend := twpNone;
  wp.BuildNumber := 0;
  V.Core.WindowsPty := wp;
  Pick;
  F.SizeTo(25, 6);
  AssertEquals('6 rows', 6, V.Rows);
  AssertFalse('more rows: cleared', V.HasSelection);
  AssertEquals('one change (rows)', 1, FChanges);
  Pick;
  V.WriteSync(#27'[?1049h');
  AssertFalse('the other screen: cleared', V.HasSelection);
  AssertEquals('one change (screen)', 1, FChanges);
  V.WriteSync(#27'[?1049l');
  Pick;
  V.Clear;
  AssertFalse('the scrollback cleared: cleared', V.HasSelection);
  AssertEquals('one change (clear)', 1, FChanges);
  Pick;
  V.Reset;
  AssertFalse('reset: cleared', V.HasSelection);
  AssertEquals('one change (reset)', 1, FChanges);
end;

procedure TTyTerminalViewMouseTests.TestSelectAllOnTheMac;
var
  key: Word;
begin
  V.WriteSync('hello');
  V.SetPlatform(True, False);
  key := Ord('A');
  V.PressKey(key, [ssMeta]);
  AssertTrue('Cmd+A selects all', V.HasSelection);
  AssertEquals('taken', 0, key);
  AssertEquals('nothing sent', '', Hex);
  V.ClearSelection;
  V.SetPlatform(False, True);
  key := Ord('A');
  V.PressKey(key, [ssCtrl]);
  AssertEquals('Ctrl+A on Windows is ^A', '01', Hex);
  AssertFalse('no selection', V.HasSelection);
end;

procedure TTyTerminalViewMouseTests.TestCopyWritesTheSelection;
var
  key: Word;
begin
  V.WriteSync('one'#13#10'two');
  V.SelectLines(0, 1);
  key := Ord('C');
  V.PressKey(key, [ssCtrl, ssShift]);
  AssertEquals('one write', 1, V.ClipWrites);
  AssertEquals('the two rows', 'one' + LineEnding + 'two', V.ClipWritten);
  V.ClearSelection;
  key := Ord('C');
  V.PressKey(key, [ssCtrl, ssShift]);
  AssertEquals('no selection: nothing written', 1, V.ClipWrites);
end;

procedure TTyTerminalViewMouseTests.TestCopyOnSelect;
var
  key: Word;
begin
  V.WriteSync('hello world');
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 0));
  V.MoveTo([ssLeft], V.CellLeft(4, 0));
  V.Up(mbLeft, [], V.CellLeft(4, 0));
  AssertEquals('off by default: nothing written', 0, V.ClipWrites);
  V.CopyOnSelect := True;
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 0));
  V.MoveTo([ssLeft], V.CellLeft(4, 0));
  V.Up(mbLeft, [], V.CellLeft(4, 0));
  AssertEquals('on: one write on release', 1, V.ClipWrites);
  AssertEquals('hell', V.ClipWritten);
  V.SetPlatform(True, False);
  key := Ord('A');
  V.PressKey(key, [ssMeta]);
  AssertEquals('Cmd+A writes too', 2, V.ClipWrites);
end;

procedure TTyTerminalViewMouseTests.TestThePrimarySelection;
begin
  V.WriteSync('hello world');
  V.SetPrimaryPlatform(True);
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 0));
  V.MoveTo([ssLeft], V.CellLeft(4, 0));
  V.Up(mbLeft, [], V.CellLeft(4, 0));
  AssertEquals('X11: the selection is offered as PRIMARY on release', 1, V.PrimaryOffers);
  AssertEquals('its text is given when asked', 'hell', V.PrimaryNow);
  V.PrimaryText := 'pasted';
  Reset;
  V.ClickAt(mbMiddle, [], V.CellCenter(3, 2));
  AssertEquals('the middle button pastes it', TyTermHex('pasted'), Hex);
  V.WriteSync(#27'[?2004h');
  Reset;
  V.ClickAt(mbMiddle, [], V.CellCenter(3, 2));
  AssertEquals('bracketed', TyTermHex(#27'[200~pasted'#27'[201~'), Hex);
  V.WriteSync(Sgr1006);
  Reset;
  V.ClickAt(mbMiddle, [], V.CellCenter(3, 2));
  AssertEquals('a program with the mouse gets the button instead',
    Sgr(1, 3, 2, True) + ' ' + Sgr(1, 3, 2, False), Hex);
  V.WriteSync(#27'[?1000l');
  V.SetPrimaryPlatform(False);
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 0));
  V.MoveTo([ssLeft], V.CellLeft(3, 0));
  V.Up(mbLeft, [], V.CellLeft(3, 0));
  AssertEquals('elsewhere: not offered', 1, V.PrimaryOffers);
  Reset;
  V.ClickAt(mbMiddle, [], V.CellCenter(3, 2));
  AssertEquals('elsewhere: the middle button does nothing', '', Hex);
end;

procedure TTyTerminalViewMouseTests.TestSelectionEventsCount;
begin
  V.WriteSync('hello');
  V.SelectAll;
  AssertEquals('select all', 1, FChanges);
  V.ClearSelection;
  AssertEquals('clear', 2, FChanges);
  V.Select(0, V.Core.Buffer.YBase, 3);
  AssertEquals('select', 3, FChanges);
  V.Select(0, V.Core.Buffer.YBase, 3);
  AssertEquals('the same again: no change', 3, FChanges);
end;

procedure TTyTerminalViewMouseTests.TestTheMenuWithoutAProtocol;
begin
  AssertTrue('handled', V.ContextPopup(Point(10, 10)));
  AssertEquals('shown', 1, V.MenuShows);
  AssertEquals(rsTextMenuCopy, V.MenuItem(0).Caption);
  AssertEquals(rsTextMenuPaste, V.MenuItem(1).Caption);
  AssertTrue('a separator', V.MenuItem(2).IsLine);
  AssertEquals(rsTextMenuSelectAll, V.MenuItem(3).Caption);
  AssertEquals(rsTerminalMenuClear, V.MenuItem(4).Caption);
  AssertFalse('no selection: copy is grey', V.MenuItem(0).Enabled);
  V.ClipText := '';
  AssertFalse('nothing to paste: paste is grey', V.MenuItem(1).Enabled);
  V.ClipText := 'x';
  AssertTrue('something to paste', V.MenuItem(1).Enabled);
  V.ReadOnly := True;
  AssertFalse('read-only: paste is grey', V.MenuItem(1).Enabled);
  AssertTrue('select all', V.MenuItem(3).Enabled);
  AssertTrue('clear', V.MenuItem(4).Enabled);
end;

procedure TTyTerminalViewMouseTests.TestAReportedRightClickHasNoMenu;
begin
  V.WriteSync(#27'[?1000h');
  V.ClickAt(mbRight, [], V.CellCenter(1, 1));
  AssertTrue('reported', F.Data <> '');
  AssertTrue('handled', V.ContextPopup(V.CellCenter(1, 1)));
  AssertEquals('no menu', 0, V.MenuShows);
  { Shift pressed between the reported press and the menu: the press went to the
    program all the same -- it is the press that decides, not the key now }
  V.UseFakeShift := True;
  V.FakeShift := [ssShift];
  V.ClickAt(mbRight, [], V.CellCenter(1, 1));
  AssertTrue('handled again', V.ContextPopup(V.CellCenter(1, 1)));
  AssertEquals('still no menu', 0, V.MenuShows);
end;

procedure TTyTerminalViewMouseTests.TestTheMenuBeforeThePress;
begin
  V.WriteSync(#27'[?1000h');
  V.UseFakeShift := True;
  V.FakeShift := [];
  V.ContextPopup(V.CellCenter(1, 1));
  AssertEquals('the press will be reported: no menu', 0, V.MenuShows);
  V.FakeShift := [ssShift];
  V.ContextPopup(V.CellCenter(1, 1));
  AssertEquals('the override key held: the menu', 1, V.MenuShows);
end;

procedure TTyTerminalViewMouseTests.TestOverrideRightClickShowsTheMenu;
begin
  V.WriteSync(#27'[?1000h');
  V.ClickAt(mbRight, [ssShift], V.CellCenter(1, 1));
  AssertEquals('not reported', '', Hex);
  V.UseFakeShift := True;
  V.FakeShift := [];                         { Shift let go before the menu came }
  AssertTrue('handled', V.ContextPopup(V.CellCenter(1, 1)));
  AssertEquals('the menu', 1, V.MenuShows);
end;

procedure TTyTerminalViewMouseTests.TestTheHostsPopupMenuWins;
begin
  V.PopupMenu := TPopupMenu.Create(F.Form);
  AssertFalse('left to LCL', V.ContextPopup(Point(10, 10)));
  AssertEquals('ours not shown', 0, V.MenuShows);
end;

procedure TTyTerminalViewMouseTests.TestMenuItemsAct;
begin
  V.WriteSync(Lines(0, 10) + 'hello');
  AssertTrue('some scrollback', V.Core.Buffer.YBase > 0);
  V.Select(0, V.Core.Buffer.YBase + 4, 5);
  V.MenuItem(0).Click;
  AssertEquals('copy', 'hello', V.ClipWritten);
  V.ClearSelection;
  V.MenuItem(3).Click;
  AssertTrue('select all', V.HasSelection);
  V.MenuItem(4).Click;
  AssertEquals('clear: the scrollback is gone', 0, V.Core.Buffer.YBase);
  AssertEquals('clear is no reset: the text is still there', 'hello', F.RowText(0));
end;

procedure TTyTerminalViewMouseTests.TestTheMenuKeyOpensAtTheCursor;
var
  r: TRect;
begin
  V.WriteSync(#27'[3;5H');
  AssertTrue('handled', V.ContextPopup(Point(-1, -1)));
  r := V.CellRect(4, 2);
  AssertEquals('x: the cursor cell''s left', r.Left, V.MenuShownAt.X);
  AssertEquals('y: its bottom', r.Bottom, V.MenuShownAt.Y);
end;

procedure TTyTerminalViewMouseTests.TestRightClickKeepsTheSelection;
begin
  V.WriteSync('hello world');
  V.Select(0, V.Core.Buffer.YBase, 5);
  FChanges := 0;
  V.ClickAt(mbRight, [], V.CellCenter(8, 0));
  AssertEquals('kept', 'hello', V.SelectionText);
  AssertEquals('no change', 0, FChanges);
end;

procedure TTyTerminalViewMouseTests.TestRightClickSelectsAWordOnTheMac;
begin
  V.SetPlatform(True, False);
  V.WriteSync('foo bar    baz');
  V.ClickAt(mbRight, [], V.CellCenter(5, 0));
  V.ContextPopup(V.CellCenter(5, 0));
  AssertEquals('the word under the pointer', 'bar', V.SelectionText);
  V.ClearSelection;
  V.ClickAt(mbRight, [], V.CellCenter(8, 0));
  V.ContextPopup(V.CellCenter(8, 0));
  AssertFalse('whitespace is not selected', V.HasSelection);
end;

procedure TTyTerminalViewMouseTests.TestPointerShapes;
begin
  V.MoveTo([], V.CellCenter(1, 1));
  AssertEquals('text: an I-beam', Ord(crIBeam), Ord(V.LastTempCursor));
  V.WriteSync(#27'[?1000h');
  V.MoveTo([], V.CellCenter(2, 1));
  AssertEquals('a program has the mouse: the arrow', Ord(crDefault), Ord(V.LastTempCursor));
  V.MoveTo([ssShift], V.CellCenter(3, 1));
  AssertEquals('with the override key: an I-beam', Ord(crIBeam), Ord(V.LastTempCursor));
  V.WriteSync(#27'[?1000l');
  V.MoveTo([ssAlt], V.CellCenter(4, 1));
  AssertEquals('Alt: a column, a cross', Ord(crCross), Ord(V.LastTempCursor));
  V.Cursor := crHelp;
  V.MoveTo([], V.CellCenter(5, 1));
  AssertEquals('the host''s cursor', Ord(crHelp), Ord(V.LastTempCursor));
end;

{ ---- 4 期期末审查 ------------------------------------------------------------------- }

{ the release never comes (the capture was taken: Alt+Tab, a modal dialog): once the
  buttons are up, the press is finished as a release would -- not before }
procedure TTyTerminalViewMouseTests.TestALostReleaseIsFinished;
begin
  V.WriteSync('hello world');
  V.CopyOnSelect := True;
  V.UseFakeButtons := True;
  { a drag, then the capture goes while the button is still down: nothing yet }
  V.FakeButtons := [ssLeft];
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 0));
  V.MoveTo([ssLeft], V.CellLeft(4, 0));
  AssertTrue('selecting', V.MouseRoute = mrSelect);
  AssertTrue('the drag timer runs', V.DragTimerOn);
  V.LoseCapture;
  AssertTrue('the button is still down: the press goes on', V.MouseRoute = mrSelect);
  AssertEquals('not finished', 0, V.ClipWrites);
  { the button came up somewhere else }
  V.FakeButtons := [];
  V.LoseCapture;
  AssertTrue('the route is free', V.MouseRoute = mrNone);
  AssertFalse('the drag timer stopped', V.DragTimerOn);
  AssertFalse('the selection is not dragging any more', V.Sel.Dragging);
  AssertEquals('finished as a release: CopyOnSelect wrote it', 1, V.ClipWrites);
  AssertEquals('hell', V.ClipWritten);
  { reported: the program gets the release it would have got }
  V.WriteSync(Sgr1006);
  V.FakeButtons := [ssLeft];
  V.Down(mbLeft, [ssLeft], V.CellCenter(2, 1));
  Reset;
  V.FakeButtons := [];
  V.LoseCapture;
  AssertEquals('the release is reported', Sgr(0, 2, 1, False), Hex);
  AssertTrue('the route is free', V.MouseRoute = mrNone);
  { focus lost the same way }
  V.WriteSync(#27'[?1000l');
  V.FakeButtons := [ssLeft];
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 1));
  V.FakeButtons := [];
  V.Leave;
  AssertTrue('focus lost with the button up: finished', V.MouseRoute = mrNone);
  { the next press routes afresh }
  V.WriteSync(Sgr1006);
  Reset;
  V.Down(mbLeft, [ssLeft], V.CellCenter(3, 1));
  AssertEquals('a new press is reported', Sgr(0, 3, 1, True), Hex);
end;

{ no capture event at all, the release just went to another window: the next press of
  the same button finishes the old one first }
procedure TTyTerminalViewMouseTests.TestAPressWhoseReleaseWentElsewhere;
begin
  V.WriteSync(Sgr1006);
  V.Down(mbLeft, [ssLeft], V.CellCenter(2, 1));
  Reset;
  V.Down(mbLeft, [ssLeft], V.CellCenter(5, 1));
  AssertEquals('the lost release, then the new press',
    Sgr(0, 2, 1, False) + ' ' + Sgr(0, 5, 1, True), Hex);
  Reset;
  V.Up(mbLeft, [], V.CellCenter(5, 1));
  AssertEquals('and its own release', Sgr(0, 5, 1, False), Hex);
  AssertTrue('free', V.MouseRoute = mrNone);
end;

{ X10 reports presses only: the sideways wheel is not the program's, it goes to the
  parent -- a half notch too }
procedure TTyTerminalViewMouseTests.TestX10HandsTheSidewaysWheelBack;
begin
  V.WriteSync(#27'[?9h');
  AssertFalse('X10: handed back', V.WheelHorz([], -120, V.CellCenter(1, 1)));
  AssertFalse('half a notch too', V.WheelHorz([], 60, V.CellCenter(1, 1)));
  AssertEquals('nothing sent', '', Hex);
  V.WriteSync(#27'[?9l'#27'[?1000h');
  AssertTrue('1000: taken', V.WheelHorz([], -120, V.CellCenter(1, 1)));
  AssertTrue('something sent', Hex <> '');
end;

{ upstream disables (and clears) the selection on every protocol change that leaves one
  on (MouseService.ts:380-393), not only the first }
procedure TTyTerminalViewMouseTests.TestEveryProtocolChangeClearsTheSelection;
begin
  V.WriteSync('hello world');
  V.WriteSync(#27'[?1000h');
  V.Select(0, V.Core.Buffer.YBase, 5);
  AssertTrue('selected under 1000', V.HasSelection);
  V.WriteSync(#27'[?1002h');
  AssertFalse('1000 -> 1002: cleared', V.HasSelection);
  V.Select(0, V.Core.Buffer.YBase, 5);
  V.WriteSync(#27'[?1003h');
  AssertFalse('1002 -> 1003: cleared', V.HasSelection);
  V.Select(0, V.Core.Buffer.YBase, 5);
  V.WriteSync(#27'[?1003l');
  AssertTrue('switched off: kept', V.HasSelection);
end;

procedure TTyTerminalViewMouseTests.TestSelectIsClamped;
var
  p: TTyTermSelPoint;
  last: Integer;
begin
  V.WriteSync('hello');
  last := V.Core.Buffer.Lines.Length - 1;
  V.Select(0, V.Core.Buffer.YBase, MaxInt);
  AssertTrue('a selection', V.HasSelection);
  AssertTrue('it has an end', V.Sel.FinalEnd(p));
  AssertTrue(Format('the end is in the buffer (row %d of %d)', [p.Row, last]), (p.Row >= 0) and (p.Row <= last));
  AssertTrue(Format('the end column is on the grid (%d)', [p.Col]), (p.Col >= 0) and (p.Col <= V.Cols));
  AssertEquals('everything to the end', 'hello', Copy(V.SelectionText, 1, 5));
  V.Select(-5, -3, 3);
  AssertEquals('from the top left', 'hel', V.SelectionText);
  V.Select(MaxInt, MaxInt, 5);
  AssertFalse('past the end: nothing', V.HasSelection);
  V.Select(1, V.Core.Buffer.YBase, -4);
  AssertFalse('a negative length: nothing', V.HasSelection);
end;

procedure TTyTerminalViewMouseTests.TestTheMenuDoesNotReadTheClipboard;
var
  reads: Integer;
begin
  V.ClipText := 'a very long clipboard';
  reads := V.ClipReads;
  AssertTrue('something to paste', V.MenuItem(1).Enabled);
  AssertEquals('the clipboard was not read', reads, V.ClipReads);
  AssertTrue('only asked whether there is text', V.ClipHasTextAsks > 0);
end;

{ macOS selects the word under a right click before the menu -- the host's too }
procedure TTyTerminalViewMouseTests.TestTheMacSelectsAWordForTheHostsMenuToo;
begin
  V.SetPlatform(True, False);
  V.PopupMenu := TPopupMenu.Create(F.Form);
  V.WriteSync('foo bar    baz');
  V.ClickAt(mbRight, [], V.CellCenter(5, 0));
  AssertFalse('the host''s menu: left to LCL', V.ContextPopup(V.CellCenter(5, 0)));
  AssertEquals('ours not shown', 0, V.MenuShows);
  AssertEquals('the word is selected for it', 'bar', V.SelectionText);
end;

{ X11: the release only offers PRIMARY; the text is made when someone asks -- and not
  at all when neither PRIMARY nor CopyOnSelect wants it }
procedure TTyTerminalViewMouseTests.TestPrimaryIsOfferedNotBuilt;
var
  builds: Integer;
begin
  V.WriteSync('hello world');
  builds := V.Sel.TextBuilds;
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 0));
  V.MoveTo([ssLeft], V.CellLeft(4, 0));
  V.Up(mbLeft, [], V.CellLeft(4, 0));
  AssertEquals('neither wanted: the text was not made', builds, V.Sel.TextBuilds);
  V.SetPrimaryPlatform(True);
  V.Down(mbLeft, [ssLeft], V.CellLeft(0, 0));
  V.MoveTo([ssLeft], V.CellLeft(4, 0));
  V.Up(mbLeft, [], V.CellLeft(4, 0));
  AssertEquals('offered', 1, V.PrimaryOffers);
  AssertEquals('still not made', builds, V.Sel.TextBuilds);
  AssertEquals('made when asked', 'hell', V.PrimaryNow);
  AssertEquals('once', builds + 1, V.Sel.TextBuilds);
end;

{ ten thousand rows -- half of them one line wrapped over them all -- copied: two passes
  over the rows, not a string grown row by row. THE BOUND, 1000 ms: the text is about
  200 KB; see the sign-off for the time measured, the quadratic build it replaced took
  seconds }
procedure TTyTerminalViewMouseTests.TestCopyingTenThousandRowsIsQuick;
const
  Plain = 5000;
  Wrapped = 5000;
var
  s: RawByteString;
  i: Integer;
  t0, took: QWord;
  t: string;
begin
  V.Scrollback := Plain + Wrapped + 100;
  s := '';
  for i := 1 to Plain do
    s := s + StringOfChar('p', 19) + #13#10;
  V.WriteSync(s);
  { one line over Wrapped rows }
  V.WriteSync(StringOfChar('w', Wrapped * V.Cols) + #13#10);
  V.SelectAll;
  t0 := GetTickCount64;
  t := V.SelectionText;
  took := GetTickCount64 - t0;
  AssertEquals('every plain row is there', Plain,
    (Length(t) - Wrapped * V.Cols) div (19 + Length(LineEnding)));
  AssertTrue('the wrapped line is one line', Pos(StringOfChar('w', Wrapped * V.Cols), t) > 0);
  AssertTrue(Format('copied within 1000 ms (%d ms)', [took]), took < 1000);
end;

{ a double click in a word wrapped over twenty thousand rows takes the whole word:
  upstream follows it up and down one recursion per row; here two loops (a stack as
  deep as the word is long is not something a click should need) }
procedure TTyTerminalViewMouseTests.TestAWordWrappedOverManyRows;
const
  N = 20000;
var
  t: string;
begin
  V.Scrollback := N + 100;
  V.WriteSync(StringOfChar('w', N * V.Cols) + #13#10 + 'next');
  V.ScrollLines(-(N div 2));
  V.ClickAt(mbLeft, [], V.CellCenter(5, 2));
  V.ClickAt(mbLeft, [ssDouble], V.CellCenter(5, 2));
  t := V.SelectionText;
  AssertEquals('the whole word', N * V.Cols, Length(t));
  AssertEquals('and nothing else', StringOfChar('w', N * V.Cols), t);
end;

initialization
  RegisterTest(TTyTerminalViewMouseTests);
end.
