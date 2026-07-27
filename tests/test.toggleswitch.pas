unit test.toggleswitch;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ToggleSwitch, tyControls.ToolBar;
type
  { Probe subclass: exposes protected CurrentStates and RenderTo }
  TTyToggleSwitchProbe = class(TTyToggleSwitch)
  public
    function ExposedCurrentStates: TTyStateSet;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SimulateKeyDown(var Key: Word);
    // Expose the protected preferred-size calculation (what AutoSize resizes to).
    procedure CallPreferred(out AW, AH: Integer);
  end;

  TChangeCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  TTyToggleSwitchAccess = class(TTyToggleSwitch)
  public
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
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
    procedure TestEnterTogglesChecked;
    procedure TestCurrentStatesContainsActiveWhenChecked;
    procedure TestCurrentStatesNoActiveWhenUnchecked;
    procedure TestDisabledIgnoresToggle;
  end;

  { AutoSize / preferred-size suite. Every assertion goes through CalculatePreferredSize
    rather than through Width: LCL's AutoSizeDelayed suppresses auto-sizing while the parent
    form has no handle, and the headless runner never realises one — so reading Width here
    would measure nothing. }
  TTyToggleSwitchAutoSizeTest = class(TTestCase)
  published
    procedure TestAutoSizePublishedAndOffByDefault;
    procedure TestPreferredWidthIsTheSwitchSlotWhenCaptionless;
    procedure TestPreferredWidthIncludesTheGapAndTheCaption;
    procedure TestBiggerThemeFontWidensPreferredWidth;
    procedure TestAutoSizeSurvivesAHeightPinningParent;
  end;

  TTyToggleSwitchPixelTest = class(TTestCase)
  published
    procedure TestOffKnobPixelWhite;
    procedure TestOnKnobPixelWhiteAndTrackBlue;
    { A1 regression: non-zero origin ARect must not displace knob relative to track }
    procedure TestOffsetOriginKnobPositionConsistent;
    { Batch4 Task 9: knob fill sourced from the dedicated TyToggleKnob typeKey }
    procedure TestKnobPixelUsesKnobTypeKey;
    { Task 14: Caption text label drawn beside the switch }
    procedure TestCaptionRendersBesideSwitch;
    { Task 14: empty Caption leaves the switch rendering unchanged }
    procedure TestNoCaptionUnchanged;
  end;

implementation

procedure TTyToggleSwitchAccess.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

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

procedure TTyToggleSwitchProbe.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
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

procedure TTyToggleSwitchTest.TestEnterTogglesChecked;
var
  F: TCustomForm;
  T: TTyToggleSwitchAccess;
  K: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    T := TTyToggleSwitchAccess.Create(F);
    T.Parent := F;
    AssertFalse('off', T.Checked);
    K := VK_RETURN;
    T.DoKeyDown(K, []);
    AssertTrue('enter toggled on', T.Checked);
    AssertEquals('enter consumed', 0, K);
  finally
    F.Free;
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

procedure TTyToggleSwitchTest.TestDisabledIgnoresToggle;
var
  Sw: TTyToggleSwitchProbe;
  Key: Word;
begin
  Sw := TTyToggleSwitchProbe.Create(FForm);
  Sw.Parent := FForm;
  Sw.SetBounds(120, 0, 44, 24);
  try
    Sw.Enabled := False;
    Sw.Checked := False;
    // Space key must NOT toggle when disabled
    Key := VK_SPACE;
    Sw.SimulateKeyDown(Key);
    AssertFalse('disabled space-key toggle ignored', Sw.Checked);
    // Click must NOT toggle when disabled
    Sw.Click;
    AssertFalse('disabled click toggle ignored', Sw.Checked);
  finally
    Sw.Free;
  end;
end;

{ TTyToggleSwitchAutoSizeTest }

procedure TTyToggleSwitchAutoSizeTest.TestAutoSizePublishedAndOffByDefault;
{ AutoSize has to be settable from a .lfm and from the object inspector, and it has to stay
  OFF by default — every existing layout keeps the width it was designed with. }
var
  Sw: TTyToggleSwitch;
begin
  Sw := TTyToggleSwitch.Create(nil);
  try
    AssertTrue('AutoSize is published so a .lfm / the OI can set it',
      IsPublishedProp(Sw, 'AutoSize'));
    AssertFalse('but it stays OFF by default — a designed switch keeps its width', Sw.AutoSize);
  finally
    Sw.Free;
  end;
end;

procedure TTyToggleSwitchAutoSizeTest.TestPreferredWidthIsTheSwitchSlotWhenCaptionless;
{ With no caption the switch is just its pill, and RenderTo derives the pill's width from the
  device HEIGHT (the 44:24 aspect). The preferred width must include that slot — a control that
  only reserved its text would collapse the pill to nothing. And it must propose NO height. }
var
  Ctl: TTyStyleController;
  Sw: TTyToggleSwitchProbe;
  w, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyToggleSwitch { background: #444444; color: #000000; font-size: 12px; }');
    Sw := TTyToggleSwitchProbe.Create(nil);
    try
      Sw.Controller := Ctl;
      Sw.Font.PixelsPerInch := 96;
      Sw.Height := 24;
      Sw.CallPreferred(w, h);
      AssertEquals('a bare switch wants exactly its 44:24 pill', 44, w);
      { Height is deliberately UNSET (0 = "no preference on this axis" in LCL): the switch
        widens for its caption, but its height belongs to whoever lays out the row. Proposing
        one makes it fight any container that pins a height (TTyToolBar pins every child to its
        ButtonHeight) until LCL aborts with "TControl.ChangeBounds loop detected". }
      AssertEquals('height is left to the layout, not proposed', 0, h);

      // The slot really is height-derived, exactly as the paint computes it.
      Sw.Height := 48;
      Sw.CallPreferred(w, h);
      AssertEquals('a taller switch wants a proportionally wider pill', 88, w);
      AssertEquals('and still proposes no height', 0, h);
    finally
      Sw.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyToggleSwitchAutoSizeTest.TestPreferredWidthIncludesTheGapAndTheCaption;
{ With a caption, RenderTo draws it into [pill right edge + TyCheckBoxGap, client right edge],
  left-justified and CLIPPED to that strip — so the preferred width must be pill + gap + text.
  A caption swapped in at runtime (the longer translation pushed in after the .lfm sized the
  control) must make the switch want more width, not lose its last glyphs. }
var
  Ctl: TTyStyleController;
  Sw: TTyToggleSwitchProbe;
  bare, short, long, plain, amp, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyToggleSwitch { background: #444444; color: #000000; font-size: 12px; }');
    Sw := TTyToggleSwitchProbe.Create(nil);
    try
      Sw.Controller := Ctl;
      Sw.Font.PixelsPerInch := 96;
      Sw.Height := 24;
      Sw.AutoSize := True;
      Sw.CallPreferred(bare, h);          // no caption yet: pill only

      Sw.Caption := 'On';
      Sw.CallPreferred(short, h);
      AssertTrue(Format('a caption adds the %dpx gap AND its own ink (%d -> %d)',
        [TyCheckBoxGap, bare, short]), short > bare + TyCheckBoxGap);
      AssertEquals('still no height proposed', 0, h);

      Sw.Caption := 'Enable background synchronisation';
      Sw.CallPreferred(long, h);
      AssertTrue(Format('a longer caption wants more width (%d -> %d)', [short, long]),
        long > short);

      { The switch draws FCaption verbatim (it is not an accelerator target), so a '&' is a
        real character here and DOES cost width — the point of this pair is that measuring and
        drawing agree, whichever string the caption is. }
      Sw.Caption := 'Save';
      Sw.CallPreferred(plain, h);
      Sw.Caption := '&Save';
      Sw.CallPreferred(amp, h);
      AssertTrue('the measured string is the drawn string, character for character',
        amp >= plain);
    finally
      Sw.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyToggleSwitchAutoSizeTest.TestBiggerThemeFontWidensPreferredWidth;
{ The reported bug in its cross-platform half: a skin (or another platform's default font)
  measures the SAME caption wider, and a fixed-width switch clips it. A theme switch reaches
  the control as a bare Invalidate, which is where the re-fit has to happen.
  Note what is NOT asserted here: padding. TyToggleSwitch's paint path never insets by the
  padding token (the theme does not give it one), so reserving padding would over-reserve and
  make AutoSize lie about where the caption starts — the preferred width mirrors the paint,
  and nothing else. TTyButtonGroup, whose cells ARE padded, carries that half of the story. }
var
  Ctl: TTyStyleController;
  Sw: TTyToggleSwitchProbe;
  small, big, padA, padB, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Sw := TTyToggleSwitchProbe.Create(nil);
    try
      Sw.Controller := Ctl;
      Sw.Font.PixelsPerInch := 96;
      Sw.Height := 24;
      Sw.AutoSize := True;
      Sw.Caption := 'Synchronise automatically';

      Ctl.LoadThemeCss('TyToggleSwitch { background: #444444; color: #000000; font-size: 9px; }');
      Sw.CallPreferred(small, h);
      Ctl.LoadThemeCss('TyToggleSwitch { background: #444444; color: #000000; font-size: 20px; }');
      Sw.CallPreferred(big, h);
      AssertTrue(Format('a bigger theme font widens the switch (%d -> %d)', [small, big]),
        big > small);
      AssertEquals('and still proposes no height', 0, h);

      // Padding is not part of this control's geometry: same font, wildly different padding,
      // same answer. If the paint ever starts honouring it, this pair fails and points here.
      Ctl.LoadThemeCss('TyToggleSwitch { background: #444444; color: #000000; font-size: 12px; padding: 0px 0px; }');
      Sw.CallPreferred(padA, h);
      Ctl.LoadThemeCss('TyToggleSwitch { background: #444444; color: #000000; font-size: 12px; padding: 0px 40px; }');
      Sw.CallPreferred(padB, h);
      AssertEquals('the toggle reserves what it draws: no padding in the paint, none reserved',
        padA, padB);
    finally
      Sw.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyToggleSwitchAutoSizeTest.TestAutoSizeSurvivesAHeightPinningParent;
{ The regression that killed the demo at startup for TTyButton: a bar pins every child's
  height, the child proposes its own, and the two bounce until LCL aborts with
  "TControl.ChangeBounds loop detected". An AutoSize switch on a real TTyToolBar must simply
  settle — and settle at the BAR's height, not its own idea of one. }
var
  F: TForm;
  Bar: TTyToolBar;
  Sw: TTyToggleSwitch;
  hBefore: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    Bar := TTyToolBar.Create(F);
    Bar.Parent := F;
    Bar.Align := alTop;
    Bar.ButtonHeight := 24;

    Sw := TTyToggleSwitch.Create(F);
    Sw.Parent := Bar;
    Sw.Font.PixelsPerInch := 96;
    Sw.Caption := 'Wrap';
    Sw.AutoSize := True;          // this is the shape that used to loop
    hBefore := Sw.Height;

    // Grow the caption the way a translation does: it must not start a bounds war.
    Sw.Caption := 'Wrap long lines in the editor pane';
    Bar.Realign;

    AssertEquals('the bar still owns the height', hBefore, Sw.Height);
    AssertTrue('and the switch is still a sane size', (Sw.Width > 0) and (Sw.Height > 0));
  finally
    F.Free;
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

{ TestOffsetOriginKnobPositionConsistent
  Regression for the A1 split-bug: frame used ARect-absolute coords while knob
  used (0,0)-local coords, so a non-zero ARect.Left/Top would misplace the knob.

  Setup: ARect = Rect(10, 10, 54, 34) — a 44x24 control starting at (10,10).
  Render into a 64x44 bitmap.  BeginPaint creates a 44x24 local bitmap; EndPaint
  blits it at (10,10) on the 64x44 canvas.

  At 96 ppi, OFF state:
    Margin = Scale(3) = 3 dev-px  →  knob covers local x=3..21, y=3..21.
    Centre of knob in local bitmap: (12, 12).
    Centre of knob in destination  : (10+12, 10+12) = (22, 22).

  Assert (22, 22) is knob-white (R,G,B all > 200).
  Assert (10+36, 10+12) = (46, 22) is track-dark (R < 100).
  Before the fix, the frame would have been painted offset by +10,+10 inside the
  44x24 local bitmap (mostly outside it), so pixel (22,22) would be track-dark,
  not knob-white. }
procedure TTyToggleSwitchPixelTest.TestOffsetOriginKnobPositionConsistent;
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

    { Render into a 64x44 bitmap with ARect starting at (10,10). }
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(64, 44);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 64, 44);
    Sw.RenderTo(Bmp.Canvas, Rect(10, 10, 54, 34), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      { (10+12, 10+12) = (22,22): knob centre — must be white }
      PxKnob  := Reread.GetPixel(22, 22);
      { (10+36, 10+12) = (46,22): right-side track — must be dark }
      PxTrack := Reread.GetPixel(46, 22);

      AssertTrue(
        Format('offset-origin OFF knob R > 200 (white, got R=%d G=%d B=%d)',
          [PxKnob.red, PxKnob.green, PxKnob.blue]),
        PxKnob.red > 200);
      AssertTrue(
        Format('offset-origin OFF knob G > 200 (white, got R=%d G=%d B=%d)',
          [PxKnob.red, PxKnob.green, PxKnob.blue]),
        PxKnob.green > 200);
      AssertTrue(
        Format('offset-origin OFF knob B > 200 (white, got R=%d G=%d B=%d)',
          [PxKnob.red, PxKnob.green, PxKnob.blue]),
        PxKnob.blue > 200);

      AssertTrue(
        Format('offset-origin track right: R < 100 (dark, got R=%d G=%d B=%d)',
          [PxTrack.red, PxTrack.green, PxTrack.blue]),
        PxTrack.red < 100);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TTyToggleSwitchPixelTest.TestKnobPixelUsesKnobTypeKey;
{ Batch4 Task 9: the knob fill comes from the dedicated TyToggleKnob typeKey,
  not the parent's TyToggleSwitch.color. Style TyToggleKnob to a distinct
  green (#00FF00) and assert the OFF knob centre is green-dominant. The track
  TextColor is set to red to prove it is NOT what paints the knob anymore. }
var
  Ctl: TTyStyleController;
  Form: TForm;
  Sw: TTyToggleSwitchProbe;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxKnob: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyToggleSwitch { background: #444444; color: #FF0000; border-width: 0px; }' +
      'TyToggleKnob { background: #00FF00; border-radius: 12px; }');
    Sw := TTyToggleSwitchProbe.Create(Form);
    Sw.Parent := Form;
    Sw.Controller := Ctl;
    Sw.Checked := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(44, 24);
    Sw.RenderTo(Bmp.Canvas, Rect(0, 0, 44, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      PxKnob := Reread.GetPixel(12, 12);  // left side: knob centre
      AssertTrue('knob from TyToggleKnob: G > 200 (green-dominant)', PxKnob.green > 200);
      AssertTrue('knob from TyToggleKnob: R < 80 (not red TextColor)', PxKnob.red < 80);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TTyToggleSwitchPixelTest.TestCaptionRendersBesideSwitch;
{ Task 14: with Caption set, the text label is drawn to the RIGHT of the
  fixed-width switch zone. The switch sits in a 44-wide zone on the left
  (default 24px height → 44px zone). Render a 140x24 control with a green
  caption colour and probe the caption zone (x > switch zone) for green ink.
  Also confirm the switch still toggles its Checked state. }
var
  Ctl: TTyStyleController;
  Form: TForm;
  Sw: TTyToggleSwitchProbe;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  X, Y: Integer;
  FoundInk: Boolean;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    // Caption text colour bright green so ink is easy to detect against the
    // white default background. Track grey, knob white (irrelevant here).
    Ctl.LoadThemeCss(
      'TyToggleSwitch { background: #444444; color: #00FF00; border-width: 0px; font-size: 12px; }');
    Sw := TTyToggleSwitchProbe.Create(Form);
    Sw.Parent := Form;
    Sw.Controller := Ctl;
    Sw.Caption := 'On';
    Sw.Checked := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(140, 24);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 140, 24);
    Sw.RenderTo(Bmp.Canvas, Rect(0, 0, 140, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Scan the caption zone (x from 50 onward, right of the ~44px switch zone)
      // for any green-dominant ink (the caption glyphs).
      FoundInk := False;
      for X := 50 to 139 do
        for Y := 0 to 23 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.green > 120) and (Px.red < 120) and (Px.blue < 120) then
          begin
            FoundInk := True;
            Break;
          end;
        end;
      AssertTrue('caption ink (green) present in the zone right of the switch', FoundInk);
    finally
      Reread.Free;
    end;

    // Switch still toggles.
    AssertFalse('starts unchecked', Sw.Checked);
    Sw.Toggle;
    AssertTrue('checked after Toggle', Sw.Checked);
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TTyToggleSwitchPixelTest.TestNoCaptionUnchanged;
{ Task 14: with Caption empty, the switch renders exactly as before — the
  no-caption pixel layout (knob white at x=12, dark track right at x=36 on a
  44x24 control) must be identical to the pre-Caption baseline. }
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
    Sw.Caption := '';          // empty caption → unchanged layout
    Sw.Checked := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(44, 24);
    Sw.RenderTo(Bmp.Canvas, Rect(0, 0, 44, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      PxKnob  := Reread.GetPixel(12, 12);  // left side: knob, must be white
      PxTrack := Reread.GetPixel(36, 12);  // right side: dark track

      AssertTrue('no-caption OFF knob R > 200 (white)', PxKnob.red > 200);
      AssertTrue('no-caption OFF knob G > 200 (white)', PxKnob.green > 200);
      AssertTrue('no-caption OFF knob B > 200 (white)', PxKnob.blue > 200);
      AssertTrue('no-caption OFF track right: R < 100 (dark)', PxTrack.red < 100);
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
  RegisterTest(TTyToggleSwitchAutoSizeTest);
  RegisterTest(TTyToggleSwitchPixelTest);
end.
