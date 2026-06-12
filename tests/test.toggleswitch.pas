unit test.toggleswitch;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ToggleSwitch;
type
  { Probe subclass: exposes protected CurrentStates and RenderTo }
  TTyToggleSwitchProbe = class(TTyToggleSwitch)
  public
    function ExposedCurrentStates: TTyStateSet;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SimulateKeyDown(var Key: Word);
  end;

  TChangeCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  TTyToggleSwitchTest = class(TTestCase)
  private
    FForm: TForm;
    FSw: TTyToggleSwitch;
    FCounter: TChangeCounter;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestToggleFlipsChecked;
    procedure TestToggleFiresOnChangeOnce;
    procedure TestSetSameValueNoChange;
    procedure TestClickCallsToggle;
    procedure TestSpaceKeyToggle;
    procedure TestCurrentStatesContainsActiveWhenChecked;
    procedure TestCurrentStatesNoActiveWhenUnchecked;
  end;

  TTyToggleSwitchPixelTest = class(TTestCase)
  published
    procedure TestOffKnobPixelWhite;
    procedure TestOnKnobPixelWhiteAndTrackBlue;
  end;

implementation

procedure TChangeCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

function TTyToggleSwitchProbe.ExposedCurrentStates: TTyStateSet;
begin
  Result := CurrentStates;
end;

procedure TTyToggleSwitchProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyToggleSwitchProbe.SimulateKeyDown(var Key: Word);
var
  Shift: TShiftState;
begin
  Shift := [];
  KeyDown(Key, Shift);
end;

{ TTyToggleSwitchTest }

procedure TTyToggleSwitchTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 100);
  FSw := TTyToggleSwitch.Create(FForm);
  FSw.Parent := FForm;
  FSw.SetBounds(0, 0, 44, 24);
  FCounter := TChangeCounter.Create;
  FSw.OnChange := @FCounter.Handle;
end;

procedure TTyToggleSwitchTest.TearDown;
begin
  FCounter.Free;
  FForm.Free;
end;

procedure TTyToggleSwitchTest.TestTypeKey;
begin
  AssertEquals('TyToggleSwitch', (FSw as ITyStyleable).GetStyleTypeKey);
end;

procedure TTyToggleSwitchTest.TestToggleFlipsChecked;
begin
  AssertFalse('starts unchecked', FSw.Checked);
  FSw.Toggle;
  AssertTrue('checked after Toggle', FSw.Checked);
  FSw.Toggle;
  AssertFalse('unchecked after second Toggle', FSw.Checked);
end;

procedure TTyToggleSwitchTest.TestToggleFiresOnChangeOnce;
begin
  FCounter.Count := 0;
  FSw.Toggle;
  AssertEquals('OnChange fired exactly once per Toggle', 1, FCounter.Count);
  FSw.Toggle;
  AssertEquals('OnChange fired again on second Toggle', 2, FCounter.Count);
end;

procedure TTyToggleSwitchTest.TestSetSameValueNoChange;
begin
  FSw.Checked := False;
  FCounter.Count := 0;
  FSw.Checked := False;  // set same value → no change event
  AssertEquals('no OnChange when setting same value', 0, FCounter.Count);
end;

procedure TTyToggleSwitchTest.TestClickCallsToggle;
begin
  AssertFalse('starts unchecked', FSw.Checked);
  FSw.Click;
  AssertTrue('Checked after Click', FSw.Checked);
  FSw.Click;
  AssertFalse('unchecked after second Click', FSw.Checked);
end;

procedure TTyToggleSwitchTest.TestSpaceKeyToggle;
var
  Probe: TTyToggleSwitchProbe;
  Key: Word;
begin
  Probe := TTyToggleSwitchProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.SetBounds(60, 0, 44, 24);
  try
    AssertFalse('probe starts unchecked', Probe.Checked);
    Key := VK_SPACE;
    Probe.SimulateKeyDown(Key);
    AssertTrue('Checked after VK_SPACE', Probe.Checked);
    AssertEquals('Key should be set to 0 (consumed)', 0, Integer(Key));
  finally
    Probe.Free;
  end;
end;

procedure TTyToggleSwitchTest.TestCurrentStatesContainsActiveWhenChecked;
var
  Probe: TTyToggleSwitchProbe;
begin
  Probe := TTyToggleSwitchProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.SetBounds(60, 0, 44, 24);
  try
    Probe.Checked := True;
    AssertTrue('tysActive in CurrentStates when Checked',
      tysActive in Probe.ExposedCurrentStates);
  finally
    Probe.Free;
  end;
end;

procedure TTyToggleSwitchTest.TestCurrentStatesNoActiveWhenUnchecked;
var
  Probe: TTyToggleSwitchProbe;
begin
  Probe := TTyToggleSwitchProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.SetBounds(60, 0, 44, 24);
  try
    Probe.Checked := False;
    AssertFalse('tysActive NOT in CurrentStates when unchecked',
      tysActive in Probe.ExposedCurrentStates);
  finally
    Probe.Free;
  end;
end;

{ TTyToggleSwitchPixelTest }

procedure TTyToggleSwitchPixelTest.TestOffKnobPixelWhite;
{ OFF state: knob is on the left side.
  Stylesheet: track gray, :active track blue, knob = TextColor white.
  44x24 bitmap @96ppi.
  Margin = Scale(3) = 3px at 96ppi.
  Knob side = 24 - 2*3 = 18px. Knob at left margin (x=3..21, y=3..21).
  Probe: (12, 12) should be knob → white-ish (R,G,B all > 200).
  Probe: (36, 12) should be right track side → dark (R < 100). }
var
  Ctl: TTyStyleController;
  Form: TForm;
  Sw: TTyToggleSwitchProbe;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxKnob, PxTrack: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyToggleSwitch { background: #444444; color: #FFFFFF; border-width: 0px; }' +
      'TyToggleSwitch:active { background: #3B82F6; }');
    Sw := TTyToggleSwitchProbe.Create(Form);
    Sw.Parent := Form;
    Sw.Controller := Ctl;
    Sw.Checked := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(44, 24);
    Sw.RenderTo(Bmp.Canvas, Rect(0, 0, 44, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      PxKnob  := Reread.GetPixel(12, 12);  // left side: knob
      PxTrack := Reread.GetPixel(36, 12);  // right side: dark track

      AssertTrue('OFF knob R > 200 (white)', PxKnob.red > 200);
      AssertTrue('OFF knob G > 200 (white)', PxKnob.green > 200);
      AssertTrue('OFF knob B > 200 (white)', PxKnob.blue > 200);

      AssertTrue('OFF track right: R < 100 (dark)', PxTrack.red < 100);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TTyToggleSwitchPixelTest.TestOnKnobPixelWhiteAndTrackBlue;
{ ON state: knob is on the right side.
  Same stylesheet. Checked := True → :active → blue track.
  Probe (32, 12): right side → knob white.
  Probe (12, 12): left side → blue track (B > 180, R < 120). }
var
  Ctl: TTyStyleController;
  Form: TForm;
  Sw: TTyToggleSwitchProbe;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxKnob, PxTrack: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyToggleSwitch { background: #444444; color: #FFFFFF; border-width: 0px; }' +
      'TyToggleSwitch:active { background: #3B82F6; }');
    Sw := TTyToggleSwitchProbe.Create(Form);
    Sw.Parent := Form;
    Sw.Controller := Ctl;
    Sw.Checked := True;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(44, 24);
    Sw.RenderTo(Bmp.Canvas, Rect(0, 0, 44, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      PxKnob  := Reread.GetPixel(32, 12);  // right side: knob
      PxTrack := Reread.GetPixel(12, 12);  // left side: blue track

      AssertTrue('ON knob R > 200 (white)',   PxKnob.red > 200);
      AssertTrue('ON knob G > 200 (white)',   PxKnob.green > 200);
      AssertTrue('ON knob B > 200 (white)',   PxKnob.blue > 200);

      AssertTrue('ON track left: B > 180 (blue dominant)', PxTrack.blue > 180);
      AssertTrue('ON track left: R < 120 (not red)',       PxTrack.red < 120);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyToggleSwitchTest);
  RegisterTest(TTyToggleSwitchPixelTest);
end.
