unit test.tabstrip;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, fpcunit, testregistry,
  tyControls.TabStrip;
type
  { Concrete strip backed by a plain caption list, so the page-agnostic header
    engine (TTyCustomTabStrip) can be exercised without a page control. }
  TStripAccess = class(TTyCustomTabStrip)
  private
    FCaps: TStringList;
    FReorderFrom, FReorderTo: Integer;
  protected
    function GetTabCount: Integer; override;
    function GetTabCaption(AIndex: Integer): string; override;
    function GetStyleTypeKey: string; override;
    procedure DoReorderTabs(AFromIndex, AToIndex: Integer); override;
    procedure RemoveTabData(AIndex: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddCap(const S: string);
    procedure CallMouseDown(Btn: TMouseButton; X, Y: Integer);
    procedure CallMouseMove(X, Y: Integer);
    procedure CallMouseUp(Btn: TMouseButton; X, Y: Integer);
    procedure CallMouseLeave;
    procedure CallKeyDown(var Key: Word);
    procedure DoArmFade;
    function  DoAdvance(AMs: Integer): Boolean;
    function  FadeEased: Single;
  end;

  TStripCloseProbe = class
  public
    Count, LastIndex: Integer;
    Veto: Boolean;
    constructor Create;
    procedure Handle(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
  end;

  TTabStripTest = class(TTestCase)
  private
    FForm: TForm;
    FStrip: TStripAccess;
    procedure Build3(AClosable: Boolean = False);
  protected
    procedure TearDown; override;
  published
    procedure TestHeaderRectsOrderedLeftToRight;
    procedure TestClickSelectsTab;
    procedure TestScrollOverflowAndIntoView;
    procedure TestDropIndexAtMidpoints;
    procedure TestClosableWidensAndCloseRectInside;
    procedure TestClickCloseFiresEventAndRemoves;
    procedure TestCloseVetoKeepsTab;
    procedure TestKeyboardNextPrev;
    procedure TestCrossFadeAnimatesToOne;
    procedure TestAnimationsEnabledDefaultsTrue;
  end;

implementation

constructor TStripAccess.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaps := TStringList.Create;
  FReorderFrom := -1;
  FReorderTo := -1;
end;

destructor TStripAccess.Destroy;
begin
  FCaps.Free;
  inherited Destroy;
end;

function TStripAccess.GetTabCount: Integer;
begin
  Result := FCaps.Count;
end;

function TStripAccess.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FCaps.Count) then
    Result := FCaps[AIndex]
  else
    Result := '';
end;

function TStripAccess.GetStyleTypeKey: string;
begin
  Result := 'TyTabControl';   // a themed selector exists; header parts use TyTab/TyTabClose
end;

procedure TStripAccess.DoReorderTabs(AFromIndex, AToIndex: Integer);
begin
  FReorderFrom := AFromIndex;
  FReorderTo := AToIndex;
  if (AFromIndex >= 0) and (AFromIndex < FCaps.Count) and
     (AToIndex >= 0) and (AToIndex < FCaps.Count) then
    FCaps.Move(AFromIndex, AToIndex);
end;

procedure TStripAccess.RemoveTabData(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FCaps.Count) then
    FCaps.Delete(AIndex);
  TabsChanged;
end;

procedure TStripAccess.AddCap(const S: string);
begin
  FCaps.Add(S);
  if TabIndex < 0 then TabIndex := 0;
  TabsChanged;
end;

procedure TStripAccess.CallMouseDown(Btn: TMouseButton; X, Y: Integer);
begin MouseDown(Btn, [], X, Y); end;
procedure TStripAccess.CallMouseMove(X, Y: Integer);
begin MouseMove([], X, Y); end;
procedure TStripAccess.CallMouseUp(Btn: TMouseButton; X, Y: Integer);
begin MouseUp(Btn, [], X, Y); end;
procedure TStripAccess.CallMouseLeave;
begin MouseLeave; end;
procedure TStripAccess.CallKeyDown(var Key: Word);
begin KeyDown(Key, []); end;
procedure TStripAccess.DoArmFade;
begin ArmTabFade; end;
function TStripAccess.DoAdvance(AMs: Integer): Boolean;
begin Result := AdvanceAnimation(AMs); end;
function TStripAccess.FadeEased: Single;
begin Result := GetTabFadeEased; end;

constructor TStripCloseProbe.Create;
begin
  inherited Create;
  Count := 0; LastIndex := -1; Veto := False;
end;

procedure TStripCloseProbe.Handle(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
begin
  Inc(Count);
  LastIndex := AIndex;
  if Veto then AllowClose := False;
end;

procedure TTabStripTest.Build3(AClosable: Boolean);
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 320, 240);
  FStrip := TStripAccess.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.SetBounds(0, 0, 300, 200);
  FStrip.TabsClosable := AClosable;
  FStrip.AddCap('Alpha');
  FStrip.AddCap('Beta');
  FStrip.AddCap('Gamma');
end;

procedure TTabStripTest.TearDown;
begin
  if FForm <> nil then FForm.Free;
  FForm := nil;
end;

procedure TTabStripTest.TestHeaderRectsOrderedLeftToRight;
var R0, R1, R2: TRect;
begin
  Build3;
  R0 := FStrip.TyTabHeaderRect(0);
  R1 := FStrip.TyTabHeaderRect(1);
  R2 := FStrip.TyTabHeaderRect(2);
  AssertTrue('tab0 left of tab1', R0.Left < R1.Left);
  AssertTrue('tab1 left of tab2', R1.Left < R2.Left);
  AssertTrue('tab0 has width', R0.Right > R0.Left);
end;

procedure TTabStripTest.TestClickSelectsTab;
var R1: TRect;
begin
  Build3;
  R1 := FStrip.TyTabHeaderRect(1);
  FStrip.CallMouseDown(mbLeft, (R1.Left + R1.Right) div 2, (R1.Top + R1.Bottom) div 2);
  AssertEquals('click selects tab 1', 1, FStrip.TabIndex);
end;

procedure TTabStripTest.TestScrollOverflowAndIntoView;
var I: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FStrip := TStripAccess.Create(FForm);
  FStrip.Parent := FForm;
  FStrip.Font.PixelsPerInch := 96;
  FStrip.SetBounds(0, 0, 80, 200);   // narrow -> overflow
  for I := 1 to 8 do FStrip.AddCap('Tab ' + IntToStr(I));
  AssertTrue('strip overflows (max scroll > 0)', FStrip.TyMaxHeaderScroll > 0);
  FStrip.ScrollTabIntoView(7);
  AssertTrue('scrolled so last tab is within the visible width',
    FStrip.HeaderRectShifted(7).Right <= FStrip.Width + 1);
end;

procedure TTabStripTest.TestDropIndexAtMidpoints;
var Mid2: Integer;
begin
  Build3;
  Mid2 := (FStrip.TyTabHeaderRect(2).Left + FStrip.TyTabHeaderRect(2).Right) div 2;
  AssertEquals('drop at tab2 midpoint -> index 2', 2, FStrip.TyDropIndexAt(Mid2, 96));
end;

procedure TTabStripTest.TestClosableWidensAndCloseRectInside;
var Hdr, CloseR: TRect;
begin
  Build3(True);
  Hdr := FStrip.TyTabHeaderRect(0);
  CloseR := FStrip.TyTabCloseRect(0);
  AssertTrue('close rect non-empty when closable', CloseR.Right > CloseR.Left);
  AssertTrue('close rect inside its header', (CloseR.Left >= Hdr.Left) and (CloseR.Right <= Hdr.Right));
end;

procedure TTabStripTest.TestClickCloseFiresEventAndRemoves;
var Probe: TStripCloseProbe; C0: TRect;
begin
  Build3(True);
  Probe := TStripCloseProbe.Create;
  try
    FStrip.OnTabClose := @Probe.Handle;
    C0 := FStrip.TyTabCloseRect(0);
    FStrip.CallMouseDown(mbLeft, (C0.Left + C0.Right) div 2, (C0.Top + C0.Bottom) div 2);
    AssertEquals('close fired once', 1, Probe.Count);
    AssertEquals('tab removed', 2, FStrip.TabCount);
  finally
    Probe.Free;
  end;
end;

procedure TTabStripTest.TestCloseVetoKeepsTab;
var Probe: TStripCloseProbe; C0: TRect;
begin
  Build3(True);
  Probe := TStripCloseProbe.Create;
  try
    Probe.Veto := True;
    FStrip.OnTabClose := @Probe.Handle;
    C0 := FStrip.TyTabCloseRect(0);
    FStrip.CallMouseDown(mbLeft, (C0.Left + C0.Right) div 2, (C0.Top + C0.Bottom) div 2);
    AssertEquals('close fired', 1, Probe.Count);
    AssertEquals('vetoed -> tab kept', 3, FStrip.TabCount);
  finally
    Probe.Free;
  end;
end;

procedure TTabStripTest.TestKeyboardNextPrev;
var K: Word;
begin
  Build3;
  FStrip.TabIndex := 0;
  K := VK_RIGHT; FStrip.CallKeyDown(K);
  AssertEquals('VK_RIGHT advances to next tab', 1, FStrip.TabIndex);
  K := VK_LEFT; FStrip.CallKeyDown(K);
  AssertEquals('VK_LEFT goes to previous tab', 0, FStrip.TabIndex);
end;

procedure TTabStripTest.TestCrossFadeAnimatesToOne;
begin
  Build3;
  FStrip.DoArmFade;
  FStrip.DoAdvance(1000);   // large step -> fully eased
  AssertTrue('cross-fade eased toward 1', FStrip.FadeEased > 0.9);
end;

procedure TTabStripTest.TestAnimationsEnabledDefaultsTrue;
begin
  Build3;
  AssertTrue('AnimationsEnabled defaults True', FStrip.AnimationsEnabled);
end;

initialization
  RegisterTest(TTabStripTest);
end.
