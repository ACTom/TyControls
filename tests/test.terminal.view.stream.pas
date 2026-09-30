unit test.terminal.view.stream;
{$mode objfpc}{$H+}
{ TTyTerminalView and the core's stream hooks (7 期, spec 19.3 / 19.5): the control
  forwards AddStreamHandler / RemoveStreamHandler / StreamClaimed, turns the core's
  OnClaimedInput into its own published event, and while a stream is claimed treats
  the mouse as the program not wanting it (a local selection, the wheel scrolls). The
  fake protocol is test.terminal.stream's TFakeProtocol ('<<GO>>' claims). V1-V6 of
  the phase 7 plan. }

interface

uses
  Classes, SysUtils, Types, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Terminal.Core, tyControls.Terminal, test.terminal.keyboard, test.terminal.view,
  test.terminal.stream;

type
  TTyTerminalViewStreamTests = class(TTestCase)
  private
    F: TTyTermViewFixture;
    P: TFakeProtocol;
    FClaimed: RawByteString;
    FClaimedCount: Integer;
    procedure OnClaimed(Sender: TObject; const AData: RawByteString);
    procedure Claim;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestKeysGoToOnClaimedInput;                    { V1 }
    procedure TestAPasteGoesToOnClaimedInput;                { V2 }
    procedure TestTheMouseSelectsWhileClaimed;               { V3 }
    procedure TestTheWheelScrollsWhileClaimed;               { V4 }
    procedure TestOnClaimedInputIsStreamed;                  { V5 }
    procedure TestTheViewForwardsToTheCore;                  { V6 }
  end;

implementation

procedure TTyTerminalViewStreamTests.SetUp;
begin
  F := TTyTermViewFixture.Create;
  F.SizeTo(20, 5);
  F.View.SetPlatform(False, True);
  F.View.SetPrimaryPlatform(False);
  F.View.OnClaimedInput := @OnClaimed;
  P := TFakeProtocol.Create('', nil, F.View.Core);
  F.ClearRecords;
  FClaimed := '';
  FClaimedCount := 0;
end;

procedure TTyTerminalViewStreamTests.TearDown;
begin
  if (F <> nil) and (P <> nil) then
    F.View.RemoveStreamHandler(P);
  FreeAndNil(F);
  FreeAndNil(P);
end;

procedure TTyTerminalViewStreamTests.OnClaimed(Sender: TObject; const AData: RawByteString);
begin
  FClaimed := FClaimed + AData;
  Inc(FClaimedCount);
end;

procedure TTyTerminalViewStreamTests.Claim;
begin
  F.View.AddStreamHandler(P);
  F.View.WriteSync('<<GO>>');
  AssertTrue('claimed', F.View.StreamClaimed);
  F.ClearRecords;
end;

{ V1. Mutation: the control not wiring FCore.OnClaimedInput. }
procedure TTyTerminalViewStreamTests.TestKeysGoToOnClaimedInput;
var
  k: Word;
begin
  k := Ord('X');
  F.View.PressKey(k, [ssCtrl]);
  AssertEquals('not claimed: Ctrl+X goes to the program', '18', TyTermHex(F.Data));
  AssertEquals('and not to OnClaimedInput', 0, FClaimedCount);
  Claim;
  k := Ord('X');
  F.View.PressKey(k, [ssCtrl]);
  AssertEquals('claimed: to OnClaimedInput', '18', TyTermHex(FClaimed));
  AssertEquals('nothing to the program', 0, F.DataEvents);
end;

{ V2. A paste is encoded (bracketed, LF -> CR) before it is redirected. }
procedure TTyTerminalViewStreamTests.TestAPasteGoesToOnClaimedInput;
begin
  F.View.WriteSync(#27'[?2004h');
  Claim;
  F.View.Paste('a'#10'b');
  AssertEquals('bracketed, CR', TyTermHex(#27'[200~a'#13'b'#27'[201~'), TyTermHex(FClaimed));
  AssertEquals('nothing to the program', 0, F.DataEvents);
end;

{ V3. Mutation: Reporting not looking at the claim. }
procedure TTyTerminalViewStreamTests.TestTheMouseSelectsWhileClaimed;
begin
  F.View.WriteSync('hello world'#27'[?1000h');
  F.View.Down(mbLeft, [ssLeft], F.View.CellCenter(2, 0));
  F.View.Up(mbLeft, [], F.View.CellCenter(2, 0));
  AssertTrue('not claimed: the press is reported', F.DataEvents > 0);
  F.ClearRecords;
  Claim;
  F.View.Down(mbLeft, [ssLeft], F.View.CellLeft(0, 0));
  F.View.MoveTo([ssLeft], F.View.CellRight(4, 0));
  F.View.Up(mbLeft, [], F.View.CellRight(4, 0));
  AssertEquals('nothing reported', 0, F.DataEvents);
  AssertEquals('nothing redirected', 0, FClaimedCount);
  AssertTrue('a local selection', F.View.HasSelection);
  AssertEquals('hello', F.View.SelectionText);
end;

{ V4. Two guards stand here: the view's Reporting and the core's TriggerMouseEvent (a
  report the core refuses falls back to scrolling). Each alone is pinned elsewhere (V3,
  and the stream suite's TestNoMouseReportWhileClaimed); this goes red when both go. }
procedure TTyTerminalViewStreamTests.TestTheWheelScrollsWhileClaimed;
var
  i, ydisp: Integer;
begin
  for i := 1 to 30 do
    F.View.WriteSync('line ' + IntToStr(i) + #13#10);
  F.View.WriteSync(#27'[?1000h');
  Claim;
  ydisp := F.View.Core.Buffer.YDisp;
  AssertTrue('taken', F.View.Wheel([], 120, F.View.CellCenter(2, 2)));
  AssertTrue('the viewport moved up', F.View.Core.Buffer.YDisp < ydisp);
  AssertEquals('nothing to the program', 0, F.DataEvents);
  AssertEquals('nothing redirected', 0, FClaimedCount);
end;

type
  { the event must name a published method of the root: the view is the root here }
  TClaimView = class(TTyTerminalView)
  published
    procedure Claimed(Sender: TObject; const AData: RawByteString);
  end;

procedure TClaimView.Claimed(Sender: TObject; const AData: RawByteString);
begin
end;

{ V5. The published event goes through the stream like any other. }
procedure TTyTerminalViewStreamTests.TestOnClaimedInputIsStreamed;
var
  src, dst: TClaimView;
  ms: TMemoryStream;
  m: TMethod;
begin
  { no parent: no scroll bar child, only the view }
  src := TClaimView.Create(nil);
  dst := TClaimView.Create(nil);
  ms := TMemoryStream.Create;
  try
    src.OnClaimedInput := @src.Claimed;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    m := TMethod(dst.OnClaimedInput);
    AssertTrue('the event came back', m.Code = dst.MethodAddress('Claimed'));
    AssertTrue('bound to the view read', m.Data = Pointer(dst));
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

{ V6. Mutation: StreamClaimed reading the wrong thing. }
procedure TTyTerminalViewStreamTests.TestTheViewForwardsToTheCore;
begin
  AssertEquals('none yet', 0, F.View.Core.StreamHandlerCount);
  F.View.AddStreamHandler(P);
  AssertEquals('added to the core', 1, F.View.Core.StreamHandlerCount);
  AssertFalse('not claimed', F.View.StreamClaimed);
  AssertEquals('the core agrees', F.View.Core.StreamClaimed, F.View.StreamClaimed);
  F.View.WriteSync('<<GO>>');
  AssertTrue('claimed', F.View.StreamClaimed);
  AssertEquals('the core agrees', F.View.Core.StreamClaimed, F.View.StreamClaimed);
  F.View.RemoveStreamHandler(P);
  AssertEquals('removed from the core', 0, F.View.Core.StreamHandlerCount);
  AssertFalse('the claim ended with it', F.View.StreamClaimed);
end;

initialization
  RegisterTest(TTyTerminalViewStreamTests);
end.
