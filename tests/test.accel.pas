unit test.accel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Controls, Forms, Graphics, LMessages, fpcunit, testregistry, BGRABitmap,
  BGRABitmapTypes, tyControls.Accel, tyControls.Button, tyControls.Panel, tyControls.PageControl,
  tyControls.TabSheet, tyControls.TyLabel, tyControls.Edit, tyControls.ButtonGroup,
  tyControls.ToggleSwitch;
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
    { The page control passes the key to the page shown only -- even to a control that
      would answer it without asking whether it can be seen. }
    procedure TestAHiddenPageIsNotAskedAtAll;
  end;

  { #142: what an accelerator does on the label, the button group and the toggle switch. }
  TAccelReachTest = class(TTestCase)
  private
    FForm: TForm;
    FClicks: Integer;
    procedure Clicked(Sender: TObject);
    function AltKey(AChar: Char): Boolean;
    function WrappedLabelShot(const ACaption: string): TBGRABitmap;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestALabelOnlyFocusesItsControl;
    procedure TestTheMnemonicFindsItsWrappedLine;
    procedure TestAWrappedLabelUnderlinesItsMnemonic;
    procedure TestAButtonGroupSegmentAnswersItsLetter;
    procedure TestAToggleSwitchCaptionIsAMnemonic;
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

type
  { Answers every Alt key, visible or not: what a third-party control may do. }
  TAnyAccelProbe = class(TCustomControl)
  public
    Asked: Integer;
  protected
    function DialogChar(var Message: TLMKey): Boolean; override;
  end;

function TAnyAccelProbe.DialogChar(var Message: TLMKey): Boolean;
begin
  Inc(Asked);
  Result := False;
end;

procedure TAccelVisibilityTest.TestAHiddenPageIsNotAskedAtAll;
var
  f: TForm;
  pc: TTyPageControl;
  probe: TAnyAccelProbe;
begin
  f := TForm.CreateNew(nil);
  try
    pc := TTyPageControl.Create(f);
    pc.Parent := f;
    probe := TAnyAccelProbe.Create(f);
    probe.Parent := pc.AddPage('One');
    pc.AddPage('Two');
    pc.ActivePageIndex := 1;
    AltKey(f, 'x');
    AssertEquals('the hidden page''s control is not asked', 0, probe.Asked);
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

{ ---- TAccelReachTest ---- }

type
  TLabelShot = class(TTyLabel);

var
  ReachWidgetSetReady: Boolean = False;

procedure TAccelReachTest.SetUp;
begin
  if not ReachWidgetSetReady then
  begin
    Forms.Application.Initialize;
    ReachWidgetSetReady := True;
  end;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FForm.Show;
  FClicks := 0;
end;

procedure TAccelReachTest.TearDown;
begin
  TyAccelSetShowing(False);
  FreeAndNil(FForm);
end;

procedure TAccelReachTest.Clicked(Sender: TObject);
begin
  Inc(FClicks);
end;

function TAccelReachTest.AltKey(AChar: Char): Boolean;
var
  m: TLMKey;
begin
  FillChar(m, SizeOf(m), 0);
  m.Msg := LM_SYSCHAR;
  m.CharCode := Ord(UpCase(AChar));
  m.KeyData := $20000000;   // Alt held
  Result := TFormKeyAccess(FForm).DialogChar(m);
end;

procedure TAccelReachTest.TestALabelOnlyFocusesItsControl;
var
  e: TTyEdit;
  l: TTyLabel;
begin
  e := TTyEdit.Create(FForm);
  e.Parent := FForm;
  e.SetBounds(100, 10, 120, 24);
  l := TTyLabel.Create(FForm);
  l.Parent := FForm;
  l.Caption := '&Name';
  l.FocusControl := e;
  l.OnClick := @Clicked;
  AssertTrue('the label answers its letter', AltKey('N'));
  AssertTrue('and its control has the focus', e.Focused);
  AssertEquals('its own OnClick is not the key''s', 0, FClicks);
end;

procedure TAccelReachTest.TestTheMnemonicFindsItsWrappedLine;
var
  lines: TStringList;
  ln, ps: Integer;
begin
  lines := TStringList.Create;
  try
    lines.Add('Alpha');
    lines.Add('beta gamma');
    TyAccelPosInLines('Alpha beta gamma', 7, lines, ln, ps);   // the b
    AssertEquals('second line', 1, ln);
    AssertEquals('its first letter', 1, ps);
    TyAccelPosInLines('Alpha beta gamma', 2, lines, ln, ps);   // the l
    AssertEquals('first line', 0, ln);
    AssertEquals('its second letter', 2, ps);
    TyAccelPosInLines('Alpha beta gamma', 6, lines, ln, ps);   // the space the wrap dropped
    AssertEquals('no line', -1, ln);
    TyAccelPosInLines('Alpha beta gamma', 0, lines, ln, ps);
    AssertEquals('no mnemonic, no line', -1, ln);
    lines.Clear;
    lines.Add('go');
    lines.Add('go');
    TyAccelPosInLines('go go', 4, lines, ln, ps);   // the second g
    AssertEquals('two lines alike: the second', 1, ln);
    AssertEquals('at its start', 1, ps);
  finally
    lines.Free;
  end;
end;

function TAccelReachTest.WrappedLabelShot(const ACaption: string): TBGRABitmap;
var
  l: TLabelShot;
  bmp: TBitmap;
begin
  l := TLabelShot.Create(nil);
  bmp := TBitmap.Create;
  try
    l.Font.PixelsPerInch := 96;
    l.WordWrap := True;
    l.Caption := ACaption;
    l.SetBounds(0, 0, 60, 80);
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(60, 80);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, 60, 80);
    l.RenderTo(bmp.Canvas, Rect(0, 0, 60, 80), 96);
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
    l.Free;
  end;
end;

function SameShot(A, B: TBGRABitmap): Boolean;
var
  x, y: Integer;
begin
  Result := (A.Width = B.Width) and (A.Height = B.Height);
  if Result then
    for y := 0 to A.Height - 1 do
      for x := 0 to A.Width - 1 do
        if A.GetPixel(x, y) <> B.GetPixel(x, y) then Exit(False);
end;

procedure TAccelReachTest.TestAWrappedLabelUnderlinesItsMnemonic;
var
  plain, marked: TBGRABitmap;
begin
  { 'Alpha' fits a 60 px line and 'beta' goes to the next: the b is underlined there. }
  plain := WrappedLabelShot('Alpha beta');
  marked := WrappedLabelShot('Alpha &beta');
  try
    AssertTrue('setup: with Alt up the two look the same', SameShot(plain, marked));
  finally
    plain.Free;
    marked.Free;
  end;
  TyAccelSetShowing(True);
  plain := WrappedLabelShot('Alpha beta');
  marked := WrappedLabelShot('Alpha &beta');
  try
    AssertFalse('with Alt down the wrapped mnemonic is underlined', SameShot(plain, marked));
  finally
    plain.Free;
    marked.Free;
  end;
end;

procedure TAccelReachTest.TestAButtonGroupSegmentAnswersItsLetter;
var
  g: TTyButtonGroup;
begin
  g := TTyButtonGroup.Create(FForm);
  g.Parent := FForm;
  g.Items.Add('&One');
  g.Items.Add('&Two');
  AssertTrue('the group answers a segment''s letter', AltKey('T'));
  AssertEquals('and picks that segment', 1, g.ItemIndex);
end;

procedure TAccelReachTest.TestAToggleSwitchCaptionIsAMnemonic;
var
  a, b: TTyToggleSwitch;
  wa, ha, wb, hb: Integer;
begin
  a := TTyToggleSwitch.Create(FForm);
  a.Parent := FForm;
  a.Caption := '&Wifi';
  AssertTrue('the switch answers its letter', AltKey('W'));
  AssertTrue('and switches on', a.Checked);
  b := TTyToggleSwitch.Create(FForm);
  b.Parent := FForm;
  b.Caption := 'Wifi';
  wa := 0; ha := 0; wb := 0; hb := 0;
  a.GetPreferredSize(wa, ha, True, False);
  b.GetPreferredSize(wb, hb, True, False);
  AssertEquals('the & is not drawn, so it takes no room', wb, wa);
end;

initialization
  RegisterTest(TAccelTest);
  RegisterTest(TAccelVisibilityTest);
  RegisterTest(TAccelReachTest);
end.
