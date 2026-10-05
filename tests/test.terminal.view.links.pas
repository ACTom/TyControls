unit test.terminal.view.links;
{$mode objfpc}{$H+}
{ TTyTerminalView 的链接与 OSC 52(4 期):按着 Ctrl(macOS Cmd)悬停、手形、Ctrl+单击交宿主
  (程序接管鼠标时也是)、DetectUrls / AllowNonHttpLinks、双击选整条、输出改了行时悬停
  跟着变;OSC 52 三种策略与宿主的同意。

  链接的范围由 test.terminal.links 对上游逐项守着;这里只看接线。 }

interface

uses
  Classes, SysUtils, Types, Forms, Controls, LCLType, LMessages, fpcunit, testregistry, fpjson,
  tyControls.Terminal.Buffer, tyControls.Terminal.Links, tyControls.Terminal, test.terminal.keyboard,
  test.terminal.view, test.terminal.oracle;

type
  TTyTerminalViewLinkTests = class(TTestCase)
  private
    F: TTyTermViewFixture;
    FLinks: TStringList;
    FOscCalls: TStringList;
    FAllowAnswer: Integer;          { -1 leave as given, 0 refuse, 1 allow }
    FTextAnswer: string;
    FTextSet: Boolean;
    procedure OnLink(Sender: TObject; const AUri: string; AFromOsc8: Boolean);
    procedure OnOsc52(Sender: TObject; AWrite: Boolean; const ASelection: string;
      var AText: string; var AAllow: Boolean);
    procedure OnOsc52Raises(Sender: TObject; AWrite: Boolean; const ASelection: string;
      var AText: string; var AAllow: Boolean);
    function V: TTyTerminalViewProbe;
    procedure CtrlClick(const P: TPoint);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCtrlHoverFindsAWebAddress;
    procedure TestTheModifierKeyAloneTogglesTheHover;
    procedure TestCmdOnTheMac;
    procedure TestAHandPointer;
    procedure TestCtrlClickActivates;
    procedure TestALinkWinsOverTheProgram;
    procedure TestDetectUrlsOff;
    procedure TestNonHttpOsc8Links;
    procedure TestADoubleClickSelectsTheWholeLink;
    procedure TestTheHoverFollowsNewOutput;
    procedure TestLinksAreNotOpenedByTheControl;
    procedure TestOsc52OffDropsEverything;
    procedure TestOsc52WriteAsksTheHost;
    procedure TestOsc52ReadNeedsConsent;
    procedure TestOsc52SurvivesAReset;
    { 4 期期末审查 }
    procedure TestACtrlClickSurvivesTheCaptureGoingFirst;
    procedure TestOsc52ExceptionsStayInside;
    { 5 期:改尺寸 }
    procedure TestAResizeDropsTheHover;
    procedure TestALongLineUnderAnOldConPtyMapsAsUpstream;
  end;

function TyTermOsc8(const AUri, AText: RawByteString): RawByteString;

implementation

const
  Url = 'see https://example.com now';

function TyTermOsc8(const AUri, AText: RawByteString): RawByteString;
begin
  Result := #27']8;;' + AUri + #27'\' + AText + #27']8;;'#27'\';
end;

procedure TTyTerminalViewLinkTests.SetUp;
begin
  F := TTyTermViewFixture.Create;
  F.SizeTo(40, 5);
  F.View.SetPlatform(False, True);
  F.View.SetPrimaryPlatform(False);
  F.View.OnLinkActivate := @OnLink;
  FLinks := TStringList.Create;
  FOscCalls := TStringList.Create;
  FAllowAnswer := -1;
  FTextSet := False;
end;

procedure TTyTerminalViewLinkTests.TearDown;
begin
  FreeAndNil(F);
  FreeAndNil(FLinks);
  FreeAndNil(FOscCalls);
end;

procedure TTyTerminalViewLinkTests.OnLink(Sender: TObject; const AUri: string; AFromOsc8: Boolean);
begin
  FLinks.Add(AUri + '|' + BoolToStr(AFromOsc8, 'osc8', 'url'));
end;

procedure TTyTerminalViewLinkTests.OnOsc52(Sender: TObject; AWrite: Boolean; const ASelection: string;
  var AText: string; var AAllow: Boolean);
begin
  FOscCalls.Add(Format('%s|%s|%s|%s', [BoolToStr(AWrite, 'write', 'read'), ASelection, AText,
    BoolToStr(AAllow, 'allow', 'refuse')]));
  if FAllowAnswer = 0 then AAllow := False;
  if FAllowAnswer = 1 then AAllow := True;
  if FTextSet then AText := FTextAnswer;
end;

procedure TTyTerminalViewLinkTests.OnOsc52Raises(Sender: TObject; AWrite: Boolean; const ASelection: string;
  var AText: string; var AAllow: Boolean);
begin
  FOscCalls.Add('raised');
  raise Exception.Create('the host raises');
end;

function TTyTerminalViewLinkTests.V: TTyTerminalViewProbe;
begin
  Result := F.View;
end;

procedure TTyTerminalViewLinkTests.CtrlClick(const P: TPoint);
begin
  V.MoveTo([ssCtrl], P);
  V.Down(mbLeft, [ssLeft, ssCtrl], P);
  V.Up(mbLeft, [ssCtrl], P);
end;

procedure TTyTerminalViewLinkTests.TestCtrlHoverFindsAWebAddress;
var
  l: TTyTermLink;
begin
  V.WriteSync(Url);
  V.MoveTo([], V.CellCenter(8, 0));
  AssertFalse('without Ctrl: plain text', V.HoverOn);
  V.MoveTo([ssCtrl], V.CellCenter(8, 0));
  AssertTrue('with Ctrl: a link', V.HoverOn);
  l := V.HoverNow;
  AssertEquals('https://example.com', l.Text);
  AssertEquals('starts at column 5 (1-based)', 5, l.Range.StartX);
  AssertEquals('ends at column 23', 23, l.Range.EndX);
  AssertEquals('on the buffer row (1-based)', V.Core.Buffer.YBase + 1, l.Range.StartY);
  AssertEquals('one row', l.Range.StartY, l.Range.EndY);
  AssertTrue('a web address', l.Source = tlsUrl);
end;

procedure TTyTerminalViewLinkTests.TestTheModifierKeyAloneTogglesTheHover;
begin
  V.WriteSync(Url);
  V.MoveTo([], V.CellCenter(8, 0));
  AssertFalse(V.HoverOn);
  V.KeyDownNow(VK_CONTROL, [ssCtrl]);
  AssertTrue('Ctrl down: the link under the pointer', V.HoverOn);
  V.KeyUpNow(VK_CONTROL, []);
  AssertFalse('Ctrl up: gone', V.HoverOn);
  AssertEquals('nothing sent', '', F.Data);
end;

procedure TTyTerminalViewLinkTests.TestCmdOnTheMac;
begin
  V.SetPlatform(True, False);
  V.WriteSync(Url);
  V.MoveTo([ssCtrl], V.CellCenter(8, 0));
  AssertFalse('Ctrl is not the key on macOS', V.HoverOn);
  V.MoveTo([ssMeta], V.CellCenter(8, 0));
  AssertTrue('Cmd is', V.HoverOn);
end;

procedure TTyTerminalViewLinkTests.TestAHandPointer;
begin
  V.WriteSync(Url);
  V.MoveTo([ssCtrl], V.CellCenter(8, 0));
  AssertEquals('a hand over the link', Ord(crHandPoint), Ord(V.LastTempCursor));
  V.MoveTo([ssCtrl], V.CellCenter(30, 0));
  AssertEquals('off it: the I-beam', Ord(crIBeam), Ord(V.LastTempCursor));
end;

procedure TTyTerminalViewLinkTests.TestCtrlClickActivates;
begin
  V.WriteSync(Url + #13#10 + TyTermOsc8('https://example.org', 'ORG'));
  CtrlClick(V.CellCenter(8, 0));
  AssertEquals('one', 1, FLinks.Count);
  AssertEquals('https://example.com|url', FLinks[0]);
  CtrlClick(V.CellCenter(1, 1));
  AssertEquals('two', 2, FLinks.Count);
  AssertEquals('https://example.org|osc8', FLinks[1]);
  { pressed on the link, released off it }
  V.MoveTo([ssCtrl], V.CellCenter(8, 0));
  V.Down(mbLeft, [ssLeft, ssCtrl], V.CellCenter(8, 0));
  V.MoveTo([ssLeft, ssCtrl], V.CellCenter(30, 0));
  V.Up(mbLeft, [ssCtrl], V.CellCenter(30, 0));
  AssertEquals('released elsewhere: nothing', 2, FLinks.Count);
  AssertFalse('and nothing selected', V.HasSelection);
end;

procedure TTyTerminalViewLinkTests.TestALinkWinsOverTheProgram;
begin
  V.WriteSync(#27'[?1000h'#27'[?1006h' + Url);
  CtrlClick(V.CellCenter(8, 0));
  AssertEquals('the link', 1, FLinks.Count);
  AssertEquals('nothing reported', '', F.Data);
  CtrlClick(V.CellCenter(35, 2));
  AssertEquals('no link there: reported, Ctrl and all',
    TyTermHex(#27'[<16;36;3M') + ' ' + TyTermHex(#27'[<16;36;3m'), TyTermHex(F.Data));
end;

procedure TTyTerminalViewLinkTests.TestDetectUrlsOff;
begin
  V.DetectUrls := False;
  V.WriteSync(Url + #13#10 + TyTermOsc8('https://example.org', 'ORG'));
  V.MoveTo([ssCtrl], V.CellCenter(8, 0));
  AssertFalse('no web addresses', V.HoverOn);
  V.MoveTo([ssCtrl], V.CellCenter(1, 1));
  AssertTrue('OSC 8 still', V.HoverOn);
end;

procedure TTyTerminalViewLinkTests.TestNonHttpOsc8Links;
begin
  V.WriteSync(TyTermOsc8('file:///tmp/a', 'FILE'));
  V.MoveTo([ssCtrl], V.CellCenter(1, 0));
  AssertFalse('file:// is no link by default', V.HoverOn);
  V.AllowNonHttpLinks := True;
  V.MoveTo([ssCtrl], V.CellCenter(2, 0));
  AssertTrue('allowed', V.HoverOn);
  CtrlClick(V.CellCenter(2, 0));
  AssertEquals('handed over as it is', 'file:///tmp/a|osc8', FLinks[0]);
end;

procedure TTyTerminalViewLinkTests.TestADoubleClickSelectsTheWholeLink;
begin
  { the comma is a word separator: a word stops there, the address does not }
  V.WriteSync('see http://a.com/a,b ok');
  V.ClickAt(mbLeft, [], V.CellCenter(19, 0));
  V.ClickAt(mbLeft, [ssDouble], V.CellCenter(19, 0));
  AssertEquals('the whole address, no Ctrl needed', 'http://a.com/a,b', V.SelectionText);
end;

procedure TTyTerminalViewLinkTests.TestTheHoverFollowsNewOutput;
begin
  V.WriteSync(Url);
  V.MoveTo([ssCtrl], V.CellCenter(8, 0));
  AssertTrue(V.HoverOn);
  V.WriteSync(#13'plain text'#27'[K');
  AssertFalse('the line was rewritten: no link under the pointer', V.HoverOn);
end;

procedure TTyTerminalViewLinkTests.TestLinksAreNotOpenedByTheControl;
begin
  V.OnLinkActivate := nil;
  V.WriteSync(Url);
  CtrlClick(V.CellCenter(8, 0));
  AssertEquals('nothing sent', '', F.Data);
  AssertFalse('nothing selected', V.HasSelection);
end;

procedure TTyTerminalViewLinkTests.TestOsc52OffDropsEverything;
begin
  V.OnOsc52 := @OnOsc52;
  AssertTrue('off by default', V.Osc52 = to52Off);
  V.WriteSync(#27']52;c;aGVsbG8='#7#27']52;c;?'#7);
  AssertEquals('no write', 0, V.ClipWrites);
  AssertEquals('no read', 0, V.ClipReads);
  AssertEquals('no answer', '', F.Data);
  AssertEquals('the host is not asked', 0, FOscCalls.Count);
  AssertEquals('and OnOsc does not see it', 0, Length(F.OscIdents));
end;

procedure TTyTerminalViewLinkTests.TestOsc52WriteAsksTheHost;
begin
  V.OnOsc52 := @OnOsc52;
  V.Osc52 := to52Write;
  V.WriteSync(#27']52;c;aGVsbG8='#7);
  AssertEquals('asked', 'write|c|hello|allow', Trim(FOscCalls.Text));
  AssertEquals('written', 'hello', V.ClipWritten);
  AssertEquals(1, V.ClipWrites);
  FAllowAnswer := 0;
  V.WriteSync(#27']52;c;aGk='#7);
  AssertEquals('refused: not written', 1, V.ClipWrites);
  FAllowAnswer := -1;
  FTextSet := True;
  FTextAnswer := 'x';
  V.WriteSync(#27']52;c;aGk='#7);
  AssertEquals('the host''s text', 'x', V.ClipWritten);
  FOscCalls.Clear;
  V.WriteSync(#27']52;c;?'#7);
  AssertEquals('reading is not allowed: not asked', 0, FOscCalls.Count);
  AssertEquals('no answer', '', F.Data);
end;

procedure TTyTerminalViewLinkTests.TestOsc52ReadNeedsConsent;
begin
  V.Osc52 := to52ReadWrite;
  V.ClipText := 'hi';
  V.WriteSync(#27']52;c;?'#7);
  AssertEquals('no handler: no answer', '', F.Data);
  V.OnOsc52 := @OnOsc52;
  V.WriteSync(#27']52;c;?'#7);
  AssertEquals('asked, refused by default', 'read|c|hi|refuse', Trim(FOscCalls.Text));
  AssertEquals('no answer', '', F.Data);
  FAllowAnswer := 1;
  V.WriteSync('some text');
  V.Select(0, V.Core.Buffer.YBase, 4);
  V.WriteSync(#27']52;c;?'#7);
  AssertEquals('allowed: the answer', TyTermHex(#27']52;c;aGk='#7), TyTermHex(F.Data));
  AssertTrue('the answer is not typing: the selection stays', V.HasSelection);
end;

procedure TTyTerminalViewLinkTests.TestOsc52SurvivesAReset;
begin
  V.Reset;
  V.Osc52 := to52Write;
  V.WriteSync(#27']52;c;aGVsbG8='#7);
  AssertEquals('still handled after a reset', 'hello', V.ClipWritten);
end;

{ LCL's button-up message lets the capture go before it calls MouseUp: that capture
  change is the release itself, not a lost one -- the Ctrl+click still opens the link }
procedure TTyTerminalViewLinkTests.TestACtrlClickSurvivesTheCaptureGoingFirst;
var
  p: TPoint;
begin
  V.WriteSync(Url);
  V.UseFakeButtons := True;
  V.FakeButtons := [];
  V.LoseCaptureInUp := True;
  p := V.CellCenter(8, 0);
  V.MoveTo([ssCtrl], p);
  V.Down(mbLeft, [ssLeft, ssCtrl], p);
  V.Perform(LM_LBUTTONUP, MK_CONTROL, PtrInt((p.Y shl 16) or (p.X and $FFFF)));
  AssertEquals('activated', 1, FLinks.Count);
  AssertEquals('https://example.com|url', FLinks[0]);
  AssertTrue('free', V.MouseRoute = mrNone);
end;

{ the OSC 52 handler runs inside Parse: what the host's event or the clipboard raises
  stays in it -- the rest of the chunk is still parsed, nothing reaches the writer }
procedure TTyTerminalViewLinkTests.TestOsc52ExceptionsStayInside;
begin
  V.Osc52 := to52ReadWrite;
  V.OnOsc52 := @OnOsc52Raises;
  V.WriteSync(#27']52;c;aGk='#7'after');
  AssertEquals('the host was asked', 1, FOscCalls.Count);
  AssertEquals('the rest of the chunk: parsed', 'after', F.RowText(0));
  AssertEquals('nothing written', 0, V.ClipWrites);
  V.WriteSync(#13#10#27']52;c;?'#7'again');
  AssertEquals('a read too', 'again', F.RowText(1));
  AssertEquals('no answer', '', F.Data);
  { the clipboard itself raising }
  V.OnOsc52 := @OnOsc52;
  FAllowAnswer := 1;
  V.ClipRaises := True;
  V.WriteSync(#13#10#27']52;c;?'#7'third'#27']52;c;aGk='#7'fourth');
  AssertEquals('reading a busy clipboard', 'thirdfourth', F.RowText(2));
  AssertEquals('no answer', '', F.Data);
end;

{ ---- 5 期:改尺寸 ------------------------------------------------------------------------ }

{ Linkifier.ts:47-50: a resize drops the current link (its range points at the old
  layout); the next pointer move finds it again in the new one }
procedure TTyTerminalViewLinkTests.TestAResizeDropsTheHover;
var
  i: Integer;
  covered: Boolean;
  l: TTyTermLink;
begin
  V.WriteSync('see https://example.com/' + StringOfChar('a', 40) + ' ok'#13#10'$ ');
  V.MoveTo([ssCtrl], V.CellCenter(8, 0));
  AssertTrue('hovered', V.HoverOn);
  AssertEquals('a hand over it', Ord(crHandPoint), Ord(V.LastTempCursor));
  AssertEquals('over two rows', 2, V.HoverNow.Range.EndY - V.HoverNow.Range.StartY + 1);
  V.ClearInvalidated;
  F.SizeTo(70, 5);
  AssertEquals('70 columns', 70, V.Cols);
  AssertFalse('the resize dropped the hover', V.HoverOn);
  AssertEquals('and the hand with it', Ord(crIBeam), Ord(V.LastTempCursor));
  covered := False;
  for i := 0 to High(V.Invalidated) do
    if (V.Invalidated[i].X <= 0) and (V.Invalidated[i].Y >= 1) then
      covered := True;
  AssertTrue('the rows it underlined were repainted', covered);
  V.MoveTo([ssCtrl], V.CellCenter(8, 0));
  AssertTrue('found again', V.HoverOn);
  AssertTrue('the link at that cell now',
    TyTermFindLinkAt(V.Core.Buffer, V.Core.Links, 8, V.Core.Buffer.YDisp, V.Cols, True, False, l));
  AssertTrue('the same range', TyTermLinkEquals(l, V.HoverNow));
  AssertEquals('one row at 70 columns', V.HoverNow.Range.StartY, V.HoverNow.Range.EndY);
end;

{ An old ConPTY keeps a line longer than the grid after a narrower resize; the web
  address on it maps back over the whole line, as upstream does (url-cases.js,
  scene reflow-old-conpty-long-line) -- not cut at the grid's width }
procedure TTyTerminalViewLinkTests.TestALongLineUnderAnOldConPtyMapsAsUpstream;
var
  m: TTyTermMisses;
  fx: TTyTermFixtures;
  scenes, web: TJSONArray;
  scene, q: TJSONObject;
  i, k: Integer;
  wp: TTyTerminalWindowsPty;
  found: Boolean;
begin
  m := TTyTermMisses.Create;
  try
    fx := TyTermLoadFixtures('links', m);
    try
      scenes := fx[0].Arrays['lines'];
      found := False;
      for i := 0 to scenes.Count - 1 do
      begin
        scene := scenes.Objects[i];
        if scene.Strings['id'] <> 'reflow-old-conpty-long-line' then
          Continue;
        found := True;
        F.SizeTo(scene.Integers['cols'], scene.Integers['rows']);
        wp.Backend := twpConPty;
        wp.BuildNumber := scene.Objects['windowsPty'].Integers['buildNumber'];
        V.Core.WindowsPty := wp;
        V.WriteSync(TyTermBase64Bytes(scene.Strings['write']));
        F.SizeTo(scene.Arrays['resize'].Integers[0], scene.Arrays['resize'].Integers[1]);
        AssertEquals('narrower', scene.Arrays['resize'].Integers[0], V.Cols);
        AssertTrue('a line longer than the grid', V.Core.Buffer.GetLine(0).Length > V.Cols);
        q := nil;
        for k := 0 to scene.Arrays['queries'].Count - 1 do
          if scene.Arrays['queries'].Objects[k].Integers['y'] = 1 then
            q := scene.Arrays['queries'].Objects[k];
        AssertTrue('the query of row 1', q <> nil);
        web := q.Arrays['web'];
        AssertEquals('upstream finds one address', 1, web.Count);
        V.MoveTo([ssCtrl], V.CellCenter(5, 0));
        AssertTrue('hovered', V.HoverOn);
        AssertEquals('start x', web.Objects[0].Arrays['range'].Integers[0], V.HoverNow.Range.StartX);
        AssertEquals('start y', web.Objects[0].Arrays['range'].Integers[1], V.HoverNow.Range.StartY);
        AssertEquals('end x', web.Objects[0].Arrays['range'].Integers[2], V.HoverNow.Range.EndX);
        AssertEquals('end y', web.Objects[0].Arrays['range'].Integers[3], V.HoverNow.Range.EndY);
      end;
      AssertTrue('scene found', found);
    finally
      TyTermFreeFixtures(fx);
    end;
  finally
    m.Free;
  end;
end;

initialization
  RegisterTest(TTyTerminalViewLinkTests);
end.
