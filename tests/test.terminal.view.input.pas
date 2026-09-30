unit test.terminal.view.input;
{$mode objfpc}{$H+}
{ TTyTerminalView 的输入与滚回:按键一律经控件自己的 KeyDown / UTF8KeyPress(探针开出来的
  覆盖方法,不是直接调 TyTerminalEvaluateKey);吞键与 OnShortcutQuery 放行;复制粘贴快捷键;
  本地翻页;内嵌滚动条;竖向滚轮三种去向;点击取焦点;输入法。OnData 拼成十六进制串比。
  探针的平台标志默认就是本平台(测试在 Windows 上跑),macOS 的几条改成 mac。 }

interface

uses
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, LCLType, LMessages, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.ScrollBar, tyControls.Terminal.Buffer,
  tyControls.Terminal.Core,
  tyControls.Terminal.Keyboard, tyControls.Terminal.Render, tyControls.Terminal, tyControls.Edit,
  test.terminal.keyboard, test.terminal.view;

type
  TTyTerminalViewInputTests = class(TTestCase)
  private
    F: TTyTermViewFixture;
    FPassKey: Word;
    FPassShift: TShiftState;
    FQueries: Integer;
    FQueryKey: Word;
    FQueryShift: TShiftState;
    procedure Query(Sender: TObject; Key: Word; Shift: TShiftState; var APassToApplication: Boolean);
    procedure HostWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint;
      var Handled: Boolean);
    function Press(AKey: Word; AShift: TShiftState = []): Word;
    procedure TypeIt(const AChar: string);
    function Hex: string;
    procedure Lines(ACount: Integer);
    function Sent: Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPlatformFlagsDefaultToThePlatform;
    procedure TestAnArrowIsSentAndSwallowed;
    procedure TestApplicationCursorFollowsTheProgram;
    procedure TestPrintableKeysWaitForTheirCharacter;
    procedure TestSpaceWaitsToo;
    procedure TestAKeySentInKeyDownDropsItsCharacter;
    procedure TestCharactersTypedWithCtrlAreDropped;
    procedure TestAltGrLeavesTheCharacter;
    procedure TestAltPrefixesEscape;
    procedure TestTabStaysInTheTerminal;
    procedure TestShortcutQueryLetsAKeyThrough;
    procedure TestShortcutQueryIsAskedForLocalActionsToo;
    procedure TestPasteShortcuts;
    procedure TestCtrlCAlwaysGoesToTheProgram;
    procedure TestTheCopyShortcutIsSwallowed;
    procedure TestLocalPaging;
    procedure TestTypingScrollsToTheBottom;
    procedure TestReadOnlySendsNothingButStillPages;
    procedure TestTheImeKeyIsLeftAlone;
    procedure TestTheBarTracksTheBuffer;
    procedure TestDraggingTheBarScrolls;
    procedure TestTheAltScreenDisablesTheBar;
    procedure TestColumnsSurviveTheAltScreen;
    procedure TestTheBarSitsOnTheRightEdge;
    procedure TestTheBarIsAFrameHost;
    procedure TestNoBarAtDesignTime;
    procedure TestTheWheelScrollsTheScrollback;
    procedure TestTheWheelSendsArrowsWithoutScrollback;
    procedure TestTheWheelIsReportedWhenAsked;
    procedure TestX10DoesNotTakeTheWheel;
    procedure TestTheHostsWheelHandlerComesFirst;
    procedure TestAClickTakesFocus;
    procedure TestImeCommitsAreSent;
    procedure TestTheImeAnchorIsTheCursorCell;
    procedure TestMarkedTextIsKeptUntilTheSessionEnds;
    procedure TestACancelledCompositionSendsNothing;
    procedure TestAnImeCommitOutsideASessionIsSentOnce;
    procedure TestAnyButtonTakesFocus;
    procedure TestKeyUpForgetsTheHandledKey;
    procedure TestShiftWheelIsLeftAlone;
    procedure TestReportedWheelPixelsStayInTheGrid;
  end;

implementation

procedure TTyTerminalViewInputTests.SetUp;
begin
  F := TTyTermViewFixture.Create;
  F.SizeTo(20, 5);
  F.ClearRecords;
  FPassKey := 0;
  FPassShift := [];
  FQueries := 0;
end;

procedure TTyTerminalViewInputTests.TearDown;
begin
  FreeAndNil(F);
end;

procedure TTyTerminalViewInputTests.Query(Sender: TObject; Key: Word; Shift: TShiftState;
  var APassToApplication: Boolean);
begin
  Inc(FQueries);
  FQueryKey := Key;
  FQueryShift := Shift;
  if (Key = FPassKey) and (Shift = FPassShift) then
    APassToApplication := True;
end;

procedure TTyTerminalViewInputTests.HostWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  Handled := True;
end;

function TTyTerminalViewInputTests.Press(AKey: Word; AShift: TShiftState): Word;
begin
  Result := AKey;
  F.View.PressKey(Result, AShift);
end;

procedure TTyTerminalViewInputTests.TypeIt(const AChar: string);
var
  c: TUTF8Char;
begin
  c := AChar;
  F.View.TypeChar(c);
end;

function TTyTerminalViewInputTests.Hex: string;
begin
  Result := TyTermHex(F.Data);
end;

function TTyTerminalViewInputTests.Sent: Boolean;
begin
  Result := F.Data <> '';
end;

procedure TTyTerminalViewInputTests.Lines(ACount: Integer);
var
  s: RawByteString;
  i: Integer;
begin
  s := '';
  for i := 1 to ACount do
    s := s + 'line ' + IntToStr(i) + #13#10;
  F.View.WriteSync(s);
  F.ClearRecords;
end;

procedure TTyTerminalViewInputTests.TestPlatformFlagsDefaultToThePlatform;
begin
  AssertEquals('mac flag', TyTerminalIsMac, F.View.IsMacFlag);
  AssertEquals('windows flag', TyTerminalIsWindows, F.View.IsWindowsFlag);
end;

procedure TTyTerminalViewInputTests.TestAnArrowIsSentAndSwallowed;
var
  k: Word;
begin
  k := Press(VK_UP);
  AssertEquals('the bytes', '1B 5B 41', Hex);
  AssertEquals('swallowed', 0, k);
end;

procedure TTyTerminalViewInputTests.TestApplicationCursorFollowsTheProgram;
begin
  F.View.WriteSync(#27'[?1h');
  F.ClearRecords;
  Press(VK_UP);
  AssertEquals('application cursor', '1B 4F 41', Hex);
end;

procedure TTyTerminalViewInputTests.TestPrintableKeysWaitForTheirCharacter;
var
  k: Word;
begin
  k := Press(Ord('A'));
  AssertEquals('nothing sent on the key', '', Hex);
  AssertEquals('the key is left alone', Ord('A'), k);
  TypeIt('a');
  AssertEquals('the character is sent', '61', Hex);
end;

procedure TTyTerminalViewInputTests.TestSpaceWaitsToo;
var
  k: Word;
begin
  k := Press(VK_SPACE);
  AssertEquals('nothing on the key', '', Hex);
  AssertEquals('left alone', VK_SPACE, k);
  TypeIt(' ');
  AssertEquals('the character', '20', Hex);
end;

procedure TTyTerminalViewInputTests.TestAKeySentInKeyDownDropsItsCharacter;
begin
  Press(VK_RETURN);
  AssertEquals('Enter', '0D', Hex);
  TypeIt(#13);
  AssertEquals('its character is dropped', '0D', Hex);
  F.ClearRecords;
  Press(Ord('A'), [ssCtrl]);
  AssertEquals('Ctrl+A', '01', Hex);
  TypeIt(#1);
  AssertEquals('its character is dropped', '01', Hex);
end;

procedure TTyTerminalViewInputTests.TestCharactersTypedWithCtrlAreDropped;
begin
  Press(Ord('B'), [ssCtrl, ssShift]);
  AssertEquals('Ctrl+Shift+B has no encoding', '', Hex);
  TypeIt('B');
  AssertEquals('a character typed with Ctrl is dropped', '', Hex);
end;

procedure TTyTerminalViewInputTests.TestAltGrLeavesTheCharacter;
var
  k: Word;
begin
  F.View.SetPlatform(False, True);
  k := Press(Ord('Q'), [ssCtrl, ssAlt]);
  AssertEquals('AltGr+Q sends nothing on the key', '', Hex);
  AssertEquals('and leaves the key', Ord('Q'), k);
  TypeIt('@');
  AssertEquals('the layout''s character goes out', '40', Hex);
end;

procedure TTyTerminalViewInputTests.TestAltPrefixesEscape;
var
  k: Word;
begin
  F.View.SetPlatform(False, True);
  k := Press(Ord('F'), [ssAlt]);
  AssertEquals('Alt+F on Windows', '1B 66', Hex);
  AssertEquals('swallowed', 0, k);
  F.ClearRecords;
  F.View.SetPlatform(True, False);
  F.View.MacOptionIsMeta := False;
  Press(Ord('F'), [ssAlt]);
  AssertEquals('Option+F on macOS is a third-level key', '', Hex);
  F.View.MacOptionIsMeta := True;
  Press(Ord('F'), [ssAlt]);
  AssertEquals('Option as Meta', '1B 66', Hex);
end;

procedure TTyTerminalViewInputTests.TestTabStaysInTheTerminal;
var
  k: Word;
begin
  k := Press(VK_TAB);
  AssertEquals('Tab', '09', Hex);
  AssertEquals('swallowed', 0, k);
end;

procedure TTyTerminalViewInputTests.TestShortcutQueryLetsAKeyThrough;
var
  k: Word;
begin
  F.View.OnShortcutQuery := @Query;
  FPassKey := VK_TAB;
  FPassShift := [];
  k := Press(VK_TAB);
  AssertEquals('let through: nothing sent', '', Hex);
  AssertEquals('let through: the key goes on', VK_TAB, k);
  AssertEquals('asked once', 1, FQueries);
  AssertEquals('asked about this key', VK_TAB, FQueryKey);
  AssertTrue('with this shift', FQueryShift = []);
  k := Press(VK_UP);
  AssertEquals('another key is sent', '1B 5B 41', Hex);
  AssertEquals('and swallowed', 0, k);
  AssertEquals('asked about it too', VK_UP, FQueryKey);
end;

procedure TTyTerminalViewInputTests.TestShortcutQueryIsAskedForLocalActionsToo;
var
  k: Word;
begin
  F.View.OnShortcutQuery := @Query;
  F.View.ClipText := 'x';
  FPassKey := Ord('V');
  FPassShift := [ssCtrl, ssShift];
  k := Press(Ord('V'), [ssCtrl, ssShift]);
  AssertEquals('asked', 1, FQueries);
  AssertEquals('the clipboard was not read', 0, F.View.ClipReads);
  AssertEquals('nothing sent', '', Hex);
  AssertEquals('the key goes on', Ord('V'), k);
end;

procedure TTyTerminalViewInputTests.TestPasteShortcuts;
begin
  F.View.ClipText := 'a'#10'b';
  Press(Ord('V'), [ssCtrl, ssShift]);
  AssertEquals('Ctrl+Shift+V', '61 0D 62', Hex);
  F.ClearRecords;
  Press(VK_INSERT, [ssShift]);
  AssertEquals('Shift+Insert', '61 0D 62', Hex);
  F.View.WriteSync(#27'[?2004h');
  F.ClearRecords;
  Press(Ord('V'), [ssCtrl, ssShift]);
  AssertEquals('bracketed', '1B 5B 32 30 30 7E 61 0D 62 1B 5B 32 30 31 7E', Hex);
  F.View.WriteSync(#27'[?2004l');
  F.View.SetPlatform(True, False);
  F.ClearRecords;
  Press(Ord('V'), [ssMeta]);
  AssertEquals('Cmd+V on macOS', '61 0D 62', Hex);
  F.ClearRecords;
  Press(Ord('V'), [ssCtrl, ssShift]);
  AssertEquals('Ctrl+Shift+V is not paste on macOS', '', Hex);
end;

procedure TTyTerminalViewInputTests.TestCtrlCAlwaysGoesToTheProgram;
begin
  F.View.SetPlatform(False, True);
  Press(Ord('C'), [ssCtrl]);
  AssertEquals('Windows', '03', Hex);
  F.ClearRecords;
  F.View.SetPlatform(True, False);
  Press(Ord('C'), [ssCtrl]);
  AssertEquals('macOS', '03', Hex);
end;

procedure TTyTerminalViewInputTests.TestTheCopyShortcutIsSwallowed;
var
  k: Word;
begin
  k := Press(Ord('C'), [ssCtrl, ssShift]);
  AssertEquals('nothing sent', '', Hex);
  AssertEquals('swallowed', 0, k);
  AssertEquals('no selection, nothing written', 0, F.View.ClipWrites);
end;

procedure TTyTerminalViewInputTests.TestLocalPaging;
var
  buf: TTyTerminalBuffer;
begin
  Lines(100);
  buf := F.View.Core.Buffer;
  Press(VK_PRIOR, [ssShift]);
  AssertEquals('Shift+PgUp: rows - 1', buf.YBase - 4, buf.YDisp);
  Press(VK_NEXT, [ssShift]);
  AssertEquals('Shift+PgDn: back', buf.YBase, buf.YDisp);
  Press(VK_HOME, [ssShift]);
  AssertEquals('Shift+Home: the top', 0, buf.YDisp);
  Press(VK_END, [ssShift]);
  AssertEquals('Shift+End: the bottom', buf.YBase, buf.YDisp);
  AssertEquals('nothing sent', '', Hex);
end;

procedure TTyTerminalViewInputTests.TestTypingScrollsToTheBottom;
var
  buf: TTyTerminalBuffer;
begin
  Lines(100);
  buf := F.View.Core.Buffer;
  F.View.ScrollLines(-10);
  TypeIt('x');
  AssertEquals('typing scrolls to the bottom', buf.YBase, buf.YDisp);
  F.View.ScrollOnUserInput := False;
  F.View.ScrollLines(-10);
  TypeIt('y');
  AssertEquals('not with ScrollOnUserInput off', buf.YBase - 10, buf.YDisp);
end;

procedure TTyTerminalViewInputTests.TestReadOnlySendsNothingButStillPages;
var
  buf: TTyTerminalBuffer;
begin
  Lines(100);
  buf := F.View.Core.Buffer;
  F.View.ReadOnly := True;
  F.View.ClipText := 'paste';
  Press(VK_UP);
  TypeIt('x');
  Press(Ord('V'), [ssCtrl, ssShift]);
  AssertEquals('nothing sent', '', Hex);
  Press(VK_PRIOR, [ssShift]);
  AssertEquals('paging still works', buf.YBase - 4, buf.YDisp);
end;

procedure TTyTerminalViewInputTests.TestTheImeKeyIsLeftAlone;
var
  k: Word;
begin
  F.View.OnShortcutQuery := @Query;
  k := Press(TyVkImeProcess);
  AssertEquals('nothing sent', '', Hex);
  AssertEquals('left alone', TyVkImeProcess, k);
  AssertEquals('not asked', 0, FQueries);
end;

procedure TTyTerminalViewInputTests.TestTheBarTracksTheBuffer;
var
  bar: TTyScrollBar;
  buf: TTyTerminalBuffer;
begin
  Lines(100);
  bar := F.View.Bar;
  buf := F.View.Core.Buffer;
  AssertNotNull('the bar exists', bar);
  AssertEquals('Max is the furthest top position', buf.YBase, bar.Max);
  AssertEquals('PageSize is the rows', 5, bar.PageSize);
  AssertEquals('Position is YDisp', buf.YDisp, bar.Position);
  F.View.ScrollLines(-10);
  AssertEquals('it follows a scroll', buf.YBase - 10, bar.Position);
end;

procedure TTyTerminalViewInputTests.TestDraggingTheBarScrolls;
begin
  Lines(100);
  F.View.Bar.Position := 3;
  AssertEquals('the view follows the bar', 3, F.View.Core.Buffer.YDisp);
end;

procedure TTyTerminalViewInputTests.TestTheAltScreenDisablesTheBar;
begin
  AssertTrue('enabled on the normal screen', F.View.Bar.Enabled);
  F.View.WriteSync(#27'[?1049h');
  AssertFalse('disabled on the alternate screen', F.View.Bar.Enabled);
  F.View.WriteSync(#27'[?1049l');
  AssertTrue('enabled again', F.View.Bar.Enabled);
  F.View.Scrollback := 0;
  AssertFalse('disabled without scrollback', F.View.Bar.Enabled);
end;

procedure TTyTerminalViewInputTests.TestColumnsSurviveTheAltScreen;
var
  cols: Integer;
begin
  cols := F.View.Cols;
  F.ClearRecords;
  F.View.WriteSync(#27'[?1049h');
  AssertEquals('columns on the alternate screen', cols, F.View.Cols);
  AssertTrue('the bar stays visible', F.View.Bar.Visible);
  F.View.WriteSync(#27'[?1049l');
  AssertEquals('columns after', cols, F.View.Cols);
  AssertTrue('the bar still visible', F.View.Bar.Visible);
  AssertEquals('no grid event', 0, Length(F.Grids));
end;

procedure TTyTerminalViewInputTests.TestTheBarSitsOnTheRightEdge;
var
  barW: Integer;
begin
  F.View.AlignNow;
  barW := MulDiv(F.Ctl.Metric('--scrollbar-size', TyScrollbarSize), F.View.Font.PixelsPerInch, 96);
  AssertEquals('width', barW, F.View.Bar.Width);
  AssertEquals('flush right', F.View.ClientWidth - barW, F.View.Bar.Left);
end;

procedure TTyTerminalViewInputTests.TestTheBarIsAFrameHost;
var
  other: TTyScrollBar;
  st: TTyStyleSet;
begin
  other := TTyScrollBar.Create(nil);
  try
    AssertTrue('its own bar', F.View.Embeds(F.View.Bar));
    AssertFalse('another bar', F.View.Embeds(other));
    AssertFalse('nil', F.View.Embeds(nil));
  finally
    other.Free;
  end;
  st := F.View.FrameHostStyle;
  AssertEquals('the frame style is the control''s', IntToHex(F.ThemeBg('TyTerminal'), 6),
    IntToHex(Cardinal(st.Background.Color) and $FFFFFF, 6));
end;

procedure TTyTerminalViewInputTests.TestNoBarAtDesignTime;
var
  fx: TTyTermViewFixture;
  i: Integer;
begin
  fx := TTyTermViewFixture.Create(False);
  try
    fx.View.MakeDesigning;
    fx.View.SetBounds(0, 0, 400, 200);
    fx.View.Parent := fx.Form;
    AssertNull('no bar', fx.View.Bar);
    for i := 0 to fx.View.ControlCount - 1 do
      AssertFalse('no scroll bar child', fx.View.Controls[i] is TTyScrollBar);
  finally
    fx.Free;
  end;
end;

procedure TTyTerminalViewInputTests.TestTheWheelScrollsTheScrollback;
var
  buf: TTyTerminalBuffer;
  y: Integer;
begin
  Lines(100);
  buf := F.View.Core.Buffer;
  y := buf.YDisp;
  AssertTrue('handled', F.View.Wheel([], 120, Point(10, 10)));
  AssertEquals('up a notch: three lines', y - 3, buf.YDisp);
  F.View.Wheel([], -120, Point(10, 10));
  AssertEquals('down a notch', y, buf.YDisp);
  F.View.ScrollLines(-20);
  y := buf.YDisp;
  AssertTrue('half a notch is taken', F.View.Wheel([], 60, Point(10, 10)));
  AssertEquals('half a notch does not scroll', y, buf.YDisp);
  F.View.Wheel([], 60, Point(10, 10));
  AssertEquals('two halves are a notch', y - 3, buf.YDisp);
  AssertEquals('nothing sent', '', Hex);
end;

procedure TTyTerminalViewInputTests.TestTheWheelSendsArrowsWithoutScrollback;
begin
  F.View.WriteSync(#27'[?1049h');
  F.ClearRecords;
  F.View.Wheel([], 120, Point(10, 10));
  AssertEquals('an up arrow', '1B 5B 41', Hex);
  F.View.WriteSync(#27'[?1h');
  F.ClearRecords;
  F.View.Wheel([], 120, Point(10, 10));
  AssertEquals('application cursor', '1B 4F 41', Hex);
  F.View.AlternateScroll := False;
  F.ClearRecords;
  F.View.Wheel([], -120, Point(10, 10));
  AssertEquals('AlternateScroll off: nothing', '', Hex);
end;

procedure TTyTerminalViewInputTests.TestTheWheelIsReportedWhenAsked;
var
  r: TRect;
begin
  F.View.WriteSync(#27'[?1000h'#27'[?1006h');
  F.ClearRecords;
  r := F.View.CellRect(2, 1);
  F.View.Wheel([], 120, Point((r.Left + r.Right) div 2, (r.Top + r.Bottom) div 2));
  AssertEquals('ESC[<64;3;2M', TyTermHex(#27'[<64;3;2M'), Hex);
end;

procedure TTyTerminalViewInputTests.TestX10DoesNotTakeTheWheel;
begin
  F.View.WriteSync(#27'[?1049h'#27'[?9h');
  F.ClearRecords;
  F.View.Wheel([], 120, Point(10, 10));
  AssertEquals('X10 reports no wheel: the arrow key', '1B 5B 41', Hex);
end;

procedure TTyTerminalViewInputTests.TestTheHostsWheelHandlerComesFirst;
var
  y: Integer;
begin
  Lines(100);
  y := F.View.Core.Buffer.YDisp;
  F.View.OnMouseWheel := @HostWheel;
  AssertTrue('handled by the host', F.View.Wheel([], 120, Point(10, 10)));
  AssertEquals('not scrolled', y, F.View.Core.Buffer.YDisp);
  AssertEquals('nothing sent', '', Hex);
end;

function MousePos(X, Y: Integer): PtrInt;
begin
  Result := PtrInt((Y shl 16) or (X and $FFFF));
end;

procedure TTyTerminalViewInputTests.TestAClickTakesFocus;
var
  form: TForm;
  park: TTyEdit;
  v: TTyTerminalView;
begin
  TyTermNeedWidgetSet;
  form := TForm.CreateNew(nil);
  try
    form.SetBounds(-4000, -4000, 640, 480);
    form.Visible := True;
    form.HandleNeeded;
    park := TTyEdit.Create(form);
    park.Parent := form;
    park.SetBounds(8, 8, 160, 26);
    v := TTyTerminalView.Create(form);
    v.Parent := form;
    v.SetBounds(200, 60, 300, 200);
    v.HandleNeeded;
    Forms.Application.ProcessMessages;
    if park.CanFocus then park.SetFocus;
    Forms.Application.ProcessMessages;
    AssertFalse('precondition: the terminal is not focused', form.ActiveControl = v);
    v.Perform(LM_LBUTTONDOWN, MK_LBUTTON, MousePos(40, 40));
    Forms.Application.ProcessMessages;
    AssertTrue('a click focuses the terminal', form.ActiveControl = v);
  finally
    form.Free;
  end;
end;

procedure TTyTerminalViewInputTests.TestImeCommitsAreSent;
begin
  F.View.ImeCommit(#$E4#$B8#$AD#$E6#$96#$87);
  AssertEquals('the commit', 'E4 B8 AD E6 96 87', Hex);
  F.ClearRecords;
  F.View.ReadOnly := True;
  F.View.ImeCommit(#$E4#$B8#$AD);
  AssertEquals('read-only', '', Hex);
end;

procedure TTyTerminalViewInputTests.TestMarkedTextIsKeptUntilTheSessionEnds;
var
  b: TBGRABitmap;
  mark: Cardinal;

  function MarkPixels(B: TBGRABitmap): Integer;
  var
    x, y: Integer;
    r: TRect;
    p: TBGRAPixel;
  begin
    Result := 0;
    r := F.View.CellRect(0, 0);
    for y := r.Top to r.Bottom - 1 do
      for x := r.Left to r.Right - 1 do
      begin
        p := B.GetPixel(x, y);
        if ((Cardinal(p.red) shl 16) or (Cardinal(p.green) shl 8) or p.blue) = mark then Inc(Result);
      end;
  end;

begin
  mark := F.Ctl.Model.ResolveStyle('TyTerminalPreedit', '', []).BorderColor and $FFFFFF;
  F.View.ImeBegin;
  F.View.ImeReplaceText(0, 0, 'zh');
  AssertEquals('nothing sent while composing', '', Hex);
  b := F.Render;
  try
    AssertTrue('the marked text is drawn with its underline', MarkPixels(b) > 0);
  finally
    b.Free;
  end;
  F.View.ImeReplaceText(0, 2, #$E4#$B8#$AD);
  F.View.ImeEnd;
  AssertEquals('sent once, at the end', 'E4 B8 AD', Hex);
  { a second end (a driver that closes twice) must not send the text again }
  F.View.ImeEnd;
  AssertEquals('not sent again', 'E4 B8 AD', Hex);
  b := F.Render;
  try
    AssertEquals('gone after the session', 0, MarkPixels(b));
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewInputTests.TestACancelledCompositionSendsNothing;
begin
  F.View.ImeBegin;
  F.View.ImeReplaceText(0, 0, 'x');
  F.View.ImeReplaceText(0, 1, '');
  F.View.ImeEnd;
  AssertEquals('nothing', '', Hex);
end;

procedure TTyTerminalViewInputTests.TestTheImeAnchorIsTheCursorCell;
var
  b: TBGRABitmap;
begin
  { the real path: a handle, the focus, a frame painted; then what the widgetset asks
    (GetImeCaretRect for the candidate window, ImeCaretBoundClient on macOS) }
  TyTermNeedWidgetSet;
  F.View.HandleNeeded;
  F.View.Enter;
  F.View.WriteSync(#27'[3;5H');
  b := F.Render;
  b.Free;
  AssertTrue('the candidate window''s anchor is the cursor''s cell (col 4, row 2)',
    EqualRect(F.View.CellRect(4, 2), F.View.ImeAnchor));
  AssertTrue('macOS asks the same rectangle', EqualRect(F.View.CellRect(4, 2), F.View.ImeBound));
  F.View.WriteSync(#27'[5;2H');
  b := F.Render;
  b.Free;
  AssertTrue('it follows the cursor', EqualRect(F.View.CellRect(1, 4), F.View.ImeAnchor));
  F.View.Leave;
  AssertTrue('unfocused: no anchor', IsRectEmpty(F.View.ImeAnchor));
  F.View.Enter;
  AssertTrue('focused again: nothing until the next frame is painted', IsRectEmpty(F.View.ImeAnchor));
  b := F.Render;
  b.Free;
  AssertTrue('then the cell again', EqualRect(F.View.CellRect(1, 4), F.View.ImeAnchor));
end;

procedure TTyTerminalViewInputTests.TestAnImeCommitOutsideASessionIsSentOnce;
var
  b: TBGRABitmap;
  mark: Cardinal;
  x, y, n: Integer;
  r: TRect;
begin
  { LCL-Cocoa's dead key: IMEInsertFinalText without a session, no IMESessionEnd after }
  F.View.ImeReplaceText(0, 0, #$C3#$A9);
  AssertEquals('sent at once', 'C3 A9', Hex);
  F.View.ImeEnd;
  AssertEquals('not sent again by a session end', 'C3 A9', Hex);
  mark := F.Ctl.Model.ResolveStyle('TyTerminalPreedit', '', []).BorderColor and $FFFFFF;
  b := F.Render;
  try
    n := 0;
    r := F.View.CellRect(0, 0);
    for y := r.Top to r.Bottom - 1 do
      for x := r.Left to r.Right - 1 do
        if ((Cardinal(b.GetPixel(x, y).red) shl 16) or (Cardinal(b.GetPixel(x, y).green) shl 8)
          or b.GetPixel(x, y).blue) = mark then Inc(n);
    AssertEquals('nothing left in the marked text', 0, n);
  finally
    b.Free;
  end;
end;

procedure TTyTerminalViewInputTests.TestAnyButtonTakesFocus;
var
  form: TForm;
  park: TTyEdit;
  v: TTyTerminalView;

  function ClickFocuses(AMsg: Cardinal; AKeys: PtrInt): Boolean;
  begin
    if park.CanFocus then park.SetFocus;
    Forms.Application.ProcessMessages;
    AssertFalse('precondition: the terminal is not focused', form.ActiveControl = v);
    v.Perform(AMsg, AKeys, MousePos(40, 40));
    Forms.Application.ProcessMessages;
    Result := form.ActiveControl = v;
  end;

begin
  TyTermNeedWidgetSet;
  form := TForm.CreateNew(nil);
  try
    form.SetBounds(-4000, -4000, 640, 480);
    form.Visible := True;
    form.HandleNeeded;
    park := TTyEdit.Create(form);
    park.Parent := form;
    park.SetBounds(8, 8, 160, 26);
    v := TTyTerminalView.Create(form);
    v.Parent := form;
    v.SetBounds(200, 60, 300, 200);
    v.HandleNeeded;
    Forms.Application.ProcessMessages;
    AssertTrue('a middle click focuses the terminal', ClickFocuses(LM_MBUTTONDOWN, MK_MBUTTON));
    AssertTrue('a right click too', ClickFocuses(LM_RBUTTONDOWN, MK_RBUTTON));
    v.TabStop := False;
    AssertFalse('TabStop off: a click leaves the focus where it is (as every control here)',
      ClickFocuses(LM_MBUTTONDOWN, MK_MBUTTON));
  finally
    form.Free;
  end;
end;

procedure TTyTerminalViewInputTests.TestKeyUpForgetsTheHandledKey;
var
  k: Word;
begin
  Press(VK_RETURN);
  AssertEquals('Enter', '0D', Hex);
  { its character never came (the widgetset did not send it); the key comes up }
  k := VK_RETURN;
  F.View.ReleaseKey(k, []);
  TypeIt('x');
  AssertEquals('the next character is not taken for Enter''s', '0D 78', Hex);
end;

procedure TTyTerminalViewInputTests.TestShiftWheelIsLeftAlone;
var
  y: Integer;
begin
  F.View.SetPlatform(False, True);
  F.View.WriteSync(#27'[?1000h'#27'[?1006h');
  F.ClearRecords;
  AssertFalse('a program that wants the wheel: Shift+wheel is not reported, not taken',
    F.View.Wheel([ssShift], 120, Point(10, 10)));
  AssertEquals('nothing sent', '', Hex);
  F.View.WriteSync(#27'[?1000l'#27'[?1049h');
  F.ClearRecords;
  F.View.Wheel([ssShift], 120, Point(10, 10));
  AssertEquals('no scrollback: no arrow keys for Shift+wheel', '', Hex);
  F.View.WriteSync(#27'[?1049l');
  Lines(100);
  y := F.View.Core.Buffer.YDisp;
  AssertFalse('Windows / Linux: Shift+wheel is a sideways scroll, not ours', F.View.Wheel([ssShift], 120, Point(10, 10)));
  AssertEquals('the scrollback did not move', y, F.View.Core.Buffer.YDisp);
  F.View.SetPlatform(True, False);
  AssertTrue('macOS: Shift+wheel scrolls as ever', F.View.Wheel([ssShift], 120, Point(10, 10)));
  AssertEquals('three lines', y - 3, F.View.Core.Buffer.YDisp);
end;

procedure TTyTerminalViewInputTests.TestReportedWheelPixelsStayInTheGrid;
var
  inside, outside: string;
  r: TRect;
begin
  F.View.WriteSync(#27'[?1000h'#27'[?1016h');
  r := F.View.CellRect(F.View.Cols - 1, F.View.Rows - 1);
  F.ClearRecords;
  { the last pixel of the grid }
  F.View.Wheel([], 120, Point(r.Right - 1, r.Bottom - 1));
  inside := Hex;
  F.ClearRecords;
  { past it: in the padding and the scroll bar }
  F.View.Wheel([], 120, Point(F.View.ClientWidth - 1, F.View.ClientHeight - 1));
  outside := Hex;
  AssertTrue('reported', inside <> '');
  AssertEquals('clamped to the grid''s last pixel', inside, outside);
end;

initialization
  RegisterTest(TTyTerminalViewInputTests);
end.
