unit test.accel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, Forms, LMessages, fpcunit, testregistry, tyControls.Accel,
  tyControls.Button, tyControls.Panel, tyControls.PageControl, tyControls.TabSheet;
type
  TAccelTest = class(TTestCase)
  published
    procedure TestParseMnemonic;
    procedure TestGatePosOffByDefault;
  end;

  { #142: an Alt key reaches only controls the user can see. }
  TAccelVisibilityTest = class(TTestCase)
  private
    FClicks: TStringList;
    procedure Clicked(Sender: TObject);
    function AltKey(AForm: TForm; AChar: Char): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAButtonOnAHiddenPageDoesNotAnswer;
    procedure TestAButtonInAHiddenPanelDoesNotAnswer;
    procedure TestAPageControlInADisabledPanelKeepsItsPage;
  end;
implementation
procedure TAccelTest.TestParseMnemonic;
var d: string; p: Integer; m: Char;
begin
  m := TyParseMnemonic('&File', d, p);
  AssertEquals('display', 'File', d);
  AssertEquals('mnemonic', 'F', m);
  AssertEquals('pos', 1, p);
  m := TyParseMnemonic('a && b', d, p);
  AssertEquals('literal amp', 'a & b', d);
  AssertEquals('no mnemonic', #0, m);
end;
procedure TAccelTest.TestGatePosOffByDefault;
begin
  // No Alt held in a headless run -> gate returns 0 (underline suppressed).
  AssertEquals('gate off', 0, TyAccelGatePos(3));
end;
type
  TFormKeyAccess = class(TForm);

procedure TAccelVisibilityTest.SetUp;
begin
  FClicks := TStringList.Create;
end;

procedure TAccelVisibilityTest.TearDown;
begin
  FClicks.Free;
end;

procedure TAccelVisibilityTest.Clicked(Sender: TObject);
begin
  FClicks.Add(TTyButton(Sender).Caption);
end;

function TAccelVisibilityTest.AltKey(AForm: TForm; AChar: Char): Boolean;
var
  m: TLMKey;
begin
  FillChar(m, SizeOf(m), 0);
  m.Msg := LM_SYSCHAR;
  m.CharCode := Ord(UpCase(AChar));
  m.KeyData := $20000000;   // Alt held, as the widgetset reports it
  Result := TFormKeyAccess(AForm).DialogChar(m);
end;

function MakeButton(AParent: TWinControl; const ACaption: string; AOnClick: TNotifyEvent): TTyButton;
begin
  Result := TTyButton.Create(AParent);
  Result.Caption := ACaption;
  Result.Parent := AParent;
  Result.OnClick := AOnClick;
end;

procedure TAccelVisibilityTest.TestAButtonOnAHiddenPageDoesNotAnswer;
var
  f: TForm;
  pc: TTyPageControl;
begin
  f := TForm.CreateNew(nil);
  try
    pc := TTyPageControl.Create(f);
    pc.Parent := f;
    MakeButton(pc.AddPage('One'), '&Save', @Clicked);
    MakeButton(pc.AddPage('Two'), '&Send', @Clicked);
    pc.ActivePageIndex := 1;
    AltKey(f, 's');
    AssertEquals('only the button on the page shown answers', '&Send', FClicks.Text.Trim);
  finally
    f.Free;
  end;
end;

procedure TAccelVisibilityTest.TestAButtonInAHiddenPanelDoesNotAnswer;
var
  f: TForm;
  p: TTyPanel;
begin
  f := TForm.CreateNew(nil);
  try
    p := TTyPanel.Create(f);
    p.Parent := f;
    MakeButton(p, '&Save', @Clicked);
    p.Visible := False;
    MakeButton(f, '&Send', @Clicked);
    AltKey(f, 's');
    AssertEquals('the hidden panel''s button does not take the key', '&Send', FClicks.Text.Trim);
  finally
    f.Free;
  end;
end;

procedure TAccelVisibilityTest.TestAPageControlInADisabledPanelKeepsItsPage;
var
  f: TForm;
  p: TTyPanel;
  pc: TTyPageControl;
begin
  f := TForm.CreateNew(nil);
  try
    p := TTyPanel.Create(f);
    p.Parent := f;
    pc := TTyPageControl.Create(f);
    pc.Parent := p;
    pc.AddPage('One');
    pc.AddPage('&Two');
    pc.ActivePageIndex := 0;
    p.Enabled := False;
    AltKey(f, 't');
    AssertEquals('a disabled page control keeps its page', 0, pc.ActivePageIndex);
  finally
    f.Free;
  end;
end;

initialization
  RegisterTest(TAccelTest);
  RegisterTest(TAccelVisibilityTest);
end.
