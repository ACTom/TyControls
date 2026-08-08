unit test.dpi.fontlatch;
{ The SECOND per-monitor DPI latch: an UNSET font size, latched into an explicit one by LCL
  on the first monitor crossing and never undone.
  Full write-up: plans/2026-08-08-permonitor-dpi.md section 5.
  The guard under test: TTyGraphicControl.ScaleFontsPPI / TTyCustomControl.ScaleFontsPPI
  (tyControls.Base.pas) -- read the long comment on the TTyGraphicControl declaration.

  WHAT THIS IS ABOUT, in one paragraph. Font.Height = 0 is how LCL says "the author never
  chose a size", and it is the representation this library reads: TyResolveFontSize consults
  a control's own Font.Size only when it is > 0, otherwise the THEME decides the size. That
  is the theme-lock rule for the font axis. LCL's DPI pass overwrites the 0 with a real
  height (TControl.DoScaleFontPPI, control.inc:1972-1973) so that a plain LCL control's text
  follows the monitor -- correct for LCL, fatal for us, because afterwards every ty control
  is measured and drawn at the height LCL invented instead of the theme's, permanently.

  WHY THIS SUITE IS NOT HOST-DEPENDENT, and why that was worth checking. The DAMAGE done by
  the latch does depend on the host: the value LCL writes is MulDiv(realized device height,
  Font.PixelsPerInch, Screen.PixelsPerInch), so on a machine whose PRIMARY monitor is not
  96 DPI the written size is wrong by 96/primaryDPI. That machine cannot be reproduced here.
  But the LATCH ITSELF is unconditional -- GetFontData of a realized font is never 0, so the
  `Height = 0 -> Height <> 0` transition fires on every host, at every crossing, whatever
  Screen.PixelsPerInch says. The invariant these tests assert ("an unset size is still unset
  after the pass") is therefore both reproducible everywhere AND exactly the property that
  makes the substitution reversible on the machine we cannot reach.

  TestLclItselfDoesLatchTheUnsetSize is the CONTROL GROUP that keeps that claim honest: a
  plain LCL TButton, in the same test, crossed the same way. If LCL ever stops latching, that
  test fails and every other test here becomes vacuous -- stated as its own test so the
  distinction survives in the failure list instead of in someone's memory. (Same device as
  the plain TButton riding inside TControlDpiRoundTripTest, for the same reason.)

  Headless is enough, for the reason TControlDpiRoundTripTest gives: AutoAdjustLayout is a
  direct recursion over Controls[] and never asks the align engine for anything. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, StdCtrls, Graphics, LCLType,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Button, tyControls.CheckBox, tyControls.TyLabel;

type
  { TyResolveFontSize is a plain unit function, but ResolveFontSize (what the controls
    actually call) is protected on both bases. Two probes, one per base, so the guard is
    proved on BOTH -- they descend from TCustomControl and TGraphicControl and share no
    ancestor below TControl, so the override had to be written twice and can be forgotten
    once. TTyLabel below covers the graphic side through a real shipped control as well. }
  TWindowedFontProbe = class(TTyCustomControl)
  public
    function CallResolveFontSize(const AStyle: TTyStyleSet): Integer;
  end;

  { The graphic base has no ResolveFontSize of its own -- each label-family control calls the
    shared TyResolveFontSize with its own (ParentFont, Font.Size). Mirror that here so the
    probe exercises the same expression a real graphic control does. GetStyleTypeKey is
    abstract on the base and must be given a body for the class to be instantiable. }
  TGraphicFontProbe = class(TTyGraphicControl)
  protected
    function GetStyleTypeKey: string; override;
  public
    function CallResolveFontSize(const AStyle: TTyStyleSet): Integer;
  end;

  { ParentFont is PROTECTED on TControl (published only from TWinControl down), and this
    suite deliberately holds its subjects as plain TControl so that a plain LCL TButton can
    go through the very same setup as the control group. A descendant declared here reaches
    the protected member -- same device as TControlDpiRoundTripTest's TParentFontAccess. }
  TParentFontAccess = class(TControl);

  TTyDpiFontLatchTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    { The one crossing, exactly as TCustomForm.WMDPIChanged performs it
      (customform.inc:2273). Nothing is simulated except the message. }
    procedure Cross(APPI: Integer);
    { Put a control in the state this suite is about: born at 96, ParentFont cleared (so
      TyResolveFontSize would consult its Font.Size), and NO size ever chosen. }
    procedure MakeUnsetAt96(ACtl: TControl);
    function Ctx: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLclItselfDoesLatchTheUnsetSize;
    procedure TestUnsetSizeSurvivesOneCrossing;
    procedure TestUnsetSizeSurvivesThreeRoundTrips;
    procedure TestTheGraphicControlBaseIsGuardedToo;
    procedure TestARealGraphicControlKeepsItsUnsetSize;
    procedure TestTheThemeStillDecidesTheSizeAfterACrossing;
    procedure TestTheFontStillFollowsTheMonitor;
    procedure TestAnAuthoredFontSizeIsNotDemoted;
    procedure TestAnAuthoredNegativeHeightIsNotTouched;
    procedure TestParentFontChildrenAreUnaffected;
    procedure TestTheSizeFloorRoundTripsWithAnUnsetFontSize;
  end;

implementation

function TWindowedFontProbe.CallResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := ResolveFontSize(AStyle);
end;

function TGraphicFontProbe.GetStyleTypeKey: string;
begin
  Result := 'TyLabel';
end;

function TGraphicFontProbe.CallResolveFontSize(const AStyle: TTyStyleSet): Integer;
begin
  Result := TyResolveFontSize(AStyle, ParentFont, Font.Size, ActiveController);
end;

{ ===== harness ============================================================== }

procedure TTyDpiFontLatchTest.SetUp;
begin
  inherited SetUp;
  { A controller of this suite's own, for the reason TControlDpiRoundTripTest.Build states:
    otherwise the caption measurements depend on whichever theme an earlier test left on
    TyDefaultController. --font-size-base is the number every assertion below compares
    against, so it is declared here rather than inherited from the run order. }
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(':root { --font-size-base: 9; --line-height: 14; ' +
                    '--checkbox-size: 14; --checkbox-gap: 6; }');
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(50, 50, 640, 480);
  FForm.Font.PixelsPerInch := 96;
  { The FORM keeps an explicit size on purpose. This suite is about what happens to a
    CHILD whose size is unset; giving the form one too would add a second, independent
    latch to every measurement and make the child's failures ambiguous. }
  FForm.Font.Size := 9;
end;

procedure TTyDpiFontLatchTest.TearDown;
begin
  FreeAndNil(FForm);      // owns every control the tests built
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TTyDpiFontLatchTest.Cross(APPI: Integer);
begin
  FForm.AutoAdjustLayout(lapAutoAdjustForDPI, FForm.PixelsPerInch, APPI,
    FForm.Width, MulDiv(FForm.Width, APPI, FForm.PixelsPerInch));
end;

procedure TTyDpiFontLatchTest.MakeUnsetAt96(ACtl: TControl);
begin
  ACtl.Font.PixelsPerInch := 96;   // TFont is born at the SCREEN's PPI (font.inc:625)
  { ParentFont := False WITHOUT choosing a size. This is not a contrived state: it is what
    every control gets from `Font.Color := clRed` or `Font.Name := 'Segoe UI'` in the Object
    Inspector -- TControl.FontChanged clears FParentFont (control.inc:621) and leaves
    Height at 0. It is also the state in which TyResolveFontSize's step 2 becomes reachable,
    which is the whole reason a latched height matters to this library. }
  TParentFontAccess(ACtl).ParentFont := False;
  ACtl.Font.Height := 0;
  ACtl.Font.PixelsPerInch := 96;
end;

function TTyDpiFontLatchTest.Ctx: string;
{ Every failure message carries the host's own numbers. The value LCL writes into an unset
  height is a function of Screen.PixelsPerInch, so a failure here is far cheaper to read
  when the message says what this machine's screen claimed. }
begin
  Result := Format(' [Screen.PixelsPerInch=%d]', [Screen.PixelsPerInch]);
end;

{ ===== the control group ==================================================== }

procedure TTyDpiFontLatchTest.TestLclItselfDoesLatchTheUnsetSize;
{ THE CONTROL GROUP. A plain LCL TButton, same form, same crossing. It proves the defect
  this suite guards against is REAL on this host and that the guard is therefore not
  vacuous. If this ever goes green-by-accident (LCL stopped latching), every other test in
  this class stops meaning anything, and this failure says so directly.

  Note it also pins WHY the latch is host-independent: the value written comes from
  GetFontData of a realized font, which is never 0, so the 0 -> non-0 transition does not
  depend on Screen.PixelsPerInch agreeing or disagreeing with anything. }
var
  b: TButton;
begin
  b := TButton.Create(FForm);
  b.Parent := FForm;
  b.SetBounds(10, 10, 100, 26);
  MakeUnsetAt96(b);
  AssertEquals('precondition: the plain LCL button starts with no chosen size' + Ctx,
    0, b.Font.Height);

  Cross(240);

  AssertTrue('LCL must still latch an unset Font.Height on the first crossing -- if it does'
    + ' not, this suite guards nothing and the guard in tyControls.Base.pas can go' + Ctx,
    b.Font.Height <> 0);
  AssertTrue('...and the latch is what turns an unset SIZE into an explicit one, which is'
    + ' the value TyResolveFontSize would then obey' + Ctx,
    b.Font.Size <> 0);
end;

{ ===== the guard, on both bases ============================================= }

procedure TTyDpiFontLatchTest.TestUnsetSizeSurvivesOneCrossing;
var
  btn: TTyButton;
begin
  btn := TTyButton.Create(FForm);
  btn.Parent := FForm;
  btn.Controller := FCtl;
  btn.SetBounds(10, 50, 100, 29);
  btn.Caption := 'Hello';
  MakeUnsetAt96(btn);

  Cross(240);

  AssertEquals('TTyButton: an unset font size must still be unset after one 96->240'
    + ' crossing -- LCL wrote a height into it and the guard has to put "unset" back' + Ctx,
    0, btn.Font.Height);
  AssertEquals('...and therefore Font.Size, which is what TyResolveFontSize reads' + Ctx,
    0, btn.Font.Size);
end;

procedure TTyDpiFontLatchTest.TestUnsetSizeSurvivesThreeRoundTrips;
{ Three trips, not one, for the reason TControlDpiRoundTripTest gives: "broken forever" is
  about what COMPOUNDS. A one-shot guard that leaked once per trip would pass a single
  there-and-back and still ratchet the caption on a user who drags the window all day. }
var
  btn: TTyButton;
  t: Integer;
begin
  btn := TTyButton.Create(FForm);
  btn.Parent := FForm;
  btn.Controller := FCtl;
  btn.SetBounds(10, 50, 100, 29);
  btn.Caption := 'Hello';
  MakeUnsetAt96(btn);

  for t := 1 to 3 do
  begin
    Cross(240);
    Cross(96);
    AssertEquals(Format('TTyButton: unset font size after trip %d of 3', [t]) + Ctx,
      0, btn.Font.Height);
  end;
  AssertEquals('TTyButton is back at 96 with nothing latched' + Ctx, 96, btn.Font.PixelsPerInch);
end;

procedure TTyDpiFontLatchTest.TestTheGraphicControlBaseIsGuardedToo;
{ The two bases share no ancestor below TControl, so the override exists twice and can be
  forgotten once. This aims straight at the copy that is easiest to miss. }
var
  p: TGraphicFontProbe;
begin
  p := TGraphicFontProbe.Create(FForm);
  p.Parent := FForm;
  p.Controller := FCtl;
  p.SetBounds(10, 90, 100, 20);
  MakeUnsetAt96(p);

  Cross(240);
  Cross(96);

  AssertEquals('TTyGraphicControl base: the unset font size must survive a round trip'
    + ' (the TTyCustomControl twin passing proves nothing about this one)' + Ctx,
    0, p.Font.Height);
end;

procedure TTyDpiFontLatchTest.TestARealGraphicControlKeepsItsUnsetSize;
{ ...and once through a control that actually ships, so the probe above cannot be the only
  evidence. TTyLabel is the graphic-side control that owns a size floor. }
var
  lb: TTyLabel;
begin
  lb := TTyLabel.Create(FForm);
  lb.Parent := FForm;
  lb.Controller := FCtl;
  lb.Caption := 'Label';
  lb.SetBounds(10, 120, 100, 20);
  MakeUnsetAt96(lb);

  Cross(240);

  AssertEquals('TTyLabel: unset font size after a crossing' + Ctx, 0, lb.Font.Height);
end;

{ ===== the consequence, not the flag ======================================== }

procedure TTyDpiFontLatchTest.TestTheThemeStillDecidesTheSizeAfterACrossing;
{ THE POINT OF THE WHOLE THING. Everything above reads a field; this drives the cascade the
  field feeds, which is where a user would actually notice.

  With ParentFont = False and no chosen size, TyResolveFontSize must fall through to the
  theme's --font-size-base (step 3). A latched height turns step 2 on instead -- the control
  silently stops being theme-locked and starts obeying a number LCL invented from the
  PRIMARY monitor's DPI. On this host that number is visibly wrong already; on a 144-DPI
  primary it is wrong by 96/144. Asserted against the controller's own token rather than a
  literal, so a broken theme reports itself as the precondition instead of as this bug. }
var
  p: TWindowedFontProbe;
  empty: TTyStyleSet;
  themeSize, before: Integer;
begin
  p := TWindowedFontProbe.Create(FForm);
  p.Parent := FForm;
  p.Controller := FCtl;
  p.SetBounds(10, 150, 100, 20);
  MakeUnsetAt96(p);

  themeSize := FCtl.Metric('--font-size-base', 0);
  AssertTrue('precondition: the suite''s own theme defines --font-size-base', themeSize > 0);

  empty := Default(TTyStyleSet);    // no per-typeKey font-size, i.e. the theme's base decides
  before := p.CallResolveFontSize(empty);
  AssertEquals('precondition: the theme decides the size before any crossing',
    themeSize, before);

  Cross(240);
  Cross(96);

  AssertEquals('the THEME must still decide the font size after a round trip. A latched'
    + ' Font.Height makes TyResolveFontSize take the explicit-size branch instead, and the'
    + ' control stops being theme-locked for good' + Ctx,
    themeSize, p.CallResolveFontSize(empty));
end;

procedure TTyDpiFontLatchTest.TestTheFontStillFollowsTheMonitor;
{ The other half of the contract, and the reason the guard is not "stop LCL scaling fonts":
  a ty control still has to grow on a bigger monitor. It does so through Font.PixelsPerInch
  (controls draw at MulDiv(ResolveFontSize(style), Font.PixelsPerInch, 96)), which the
  guard deliberately leaves alone. Without this test, `Font.Assign(saved)` -- the obvious
  wrong way to write the guard -- would pass everything above and silently freeze every
  caption at 96 DPI. }
var
  p: TWindowedFontProbe;
begin
  p := TWindowedFontProbe.Create(FForm);
  p.Parent := FForm;
  p.Controller := FCtl;
  p.SetBounds(10, 150, 100, 20);
  MakeUnsetAt96(p);
  AssertEquals('precondition: born at 96', 96, p.Font.PixelsPerInch);

  Cross(240);

  AssertEquals('the font must still arrive at the new monitor PPI -- that is what ty'
    + ' controls scale their drawn text with' + Ctx, 240, p.Font.PixelsPerInch);
  AssertEquals('...while the size stays unset' + Ctx, 0, p.Font.Height);
end;

{ ===== the guard must be inert where a size WAS chosen ====================== }

procedure TTyDpiFontLatchTest.TestAnAuthoredFontSizeIsNotDemoted;
{ The mirror case, and the reason the guard is conditional. An explicitly-set Font.Size is a
  contract this library honours (TFontCascadeTest.TestExplicitControlFontStillWins), and the
  rejected alternative fix -- teaching TyResolveFontSize to distrust the height -- could not
  have kept it, because after the pass an authored 14 pt and a latched 14 pt are the same
  bytes. Guarding the REPRESENTATION is what makes both cases expressible. }
var
  p: TWindowedFontProbe;
  empty: TTyStyleSet;
begin
  p := TWindowedFontProbe.Create(FForm);
  p.Parent := FForm;
  p.Controller := FCtl;
  p.SetBounds(10, 150, 100, 20);
  p.Font.PixelsPerInch := 96;
  p.Font.Size := 14;                      // an author's choice; also clears ParentFont
  AssertFalse('precondition: an explicit size clears ParentFont',
    TParentFontAccess(p).ParentFont);

  empty := Default(TTyStyleSet);
  AssertEquals('precondition: the explicit size outranks the theme base', 14,
    p.CallResolveFontSize(empty));

  Cross(240);
  Cross(96);

  AssertEquals('an AUTHORED font size must come back exactly -- the guard only restores'
    + ' "unset", it must never blank a size the author chose' + Ctx, 14, p.Font.Size);
  AssertEquals('...and it must still outrank the theme' + Ctx, 14,
    p.CallResolveFontSize(empty));
end;

procedure TTyDpiFontLatchTest.TestAnAuthoredNegativeHeightIsNotTouched;
{ Font.Height is the other way to author a size (device px, negative = character height).
  A guard keyed on Font.Size rather than Font.Height would get this wrong in one direction
  or the other, so the distinction is pinned.

  THE HEIGHT BELOW IS CHOSEN, TWICE OVER, AND A MUTANT PROVED BOTH CHOICES NECESSARY.

  It must DIFFER from the height this control inherits from the form. The first version of
  this test wrote -12, which is exactly what Font.Size = 9 at 96 PPI comes to -- i.e. the
  value the control ALREADY had from ParentFont. TFont.SetHeight exits without firing
  Changed when the value is unchanged, so ParentFont was never cleared and nothing was ever
  authored: the probe stayed a ParentFont child, and the -30 it showed after the crossing
  came from the FORM's font being copied down afterwards, not from its own. That version
  passed against a guard mutated to blank EVERY height (see the M3 row in
  plans/2026-08-08-permonitor-dpi.md) -- a textbook centre probe, and it took an explicit
  instrumented run to see it, because every visible number looked right.

  It must also round-trip through MulDiv exactly, so that a real failure is never confused
  with a rounding artefact: -20 * 240/96 = -50 and -50 * 96/240 = -20, both exact.

  Hence the ParentFont precondition assert below. It is the load-bearing line of the test:
  without it, a future edit that happens to pick the inherited value again would silently
  turn this back into a test of nothing. }
var
  p: TWindowedFontProbe;
begin
  p := TWindowedFontProbe.Create(FForm);
  p.Parent := FForm;
  p.Controller := FCtl;
  p.SetBounds(10, 150, 100, 20);
  p.Font.PixelsPerInch := 96;
  p.Font.Height := -20;
  AssertEquals('precondition: an authored height', -20, p.Font.Height);
  AssertFalse('precondition: authoring a height must have CLEARED ParentFont. If it did'
    + ' not, the height equalled the inherited one, nothing was authored, and the rest of'
    + ' this test measures the parent instead of the guard',
    TParentFontAccess(p).ParentFont);

  Cross(240);

  AssertEquals('an authored height scales with the monitor and is NOT blanked'
    + ' (TFont.SetPixelsPerInch rescales it, font.inc:860)' + Ctx,
    MulDiv(-20, 240, 96), p.Font.Height);

  Cross(96);
  AssertEquals('...and comes back' + Ctx, -20, p.Font.Height);
end;

procedure TTyDpiFontLatchTest.TestParentFontChildrenAreUnaffected;
{ ParentFont = True is the LCL DEFAULT and takes a different route through the pass (LCL
  saves and restores it around the whole recursion, control.inc:4221/4228, and the new font
  reaches the child later through CM_PARENTFONTCHANGED). The guard must not disturb it: a
  ParentFont child mirrors its parent, and the form here HAS an explicit size, so the child
  must end up carrying it. Written because the fix's first temptation is to force Height to
  0 unconditionally, which would silently sever ParentFont inheritance.

  MEASURED SCOPE NOTE, and it is why the guard is aimed where it is: for a ParentFont child
  the guard is IRRELEVANT either way. TWinControl.AutoAdjustLayout walks children before
  itself (wincontrol.inc:3932-3935), so the PARENT's font arrives afterwards through
  CM_PARENTFONTCHANGED and overwrites whatever the child's own pass left behind -- confirmed
  by instrumentation: with the guard mutated to blank every height, a ParentFont child still
  came out of the crossing carrying the form's -30, not 0. That is correct behaviour and
  this test pins it, but it also means this test cannot kill a guard mutant, and it is not
  meant to. The guard earns its keep on ParentFont = FALSE controls, which is exactly where
  TyResolveFontSize consults Font.Size at all. }
var
  p: TWindowedFontProbe;
begin
  p := TWindowedFontProbe.Create(FForm);
  p.Parent := FForm;
  p.Controller := FCtl;
  p.SetBounds(10, 150, 100, 20);
  AssertTrue('precondition: the LCL default', TParentFontAccess(p).ParentFont);

  Cross(240);
  Cross(96);

  AssertTrue('a ParentFont child must still be a ParentFont child' + Ctx,
    TParentFontAccess(p).ParentFont);
  AssertEquals('...and must still mirror the form''s explicit size' + Ctx,
    FForm.Font.Size, p.Font.Size);
end;

{ ===== the measured symptom from the plan =================================== }

procedure TTyDpiFontLatchTest.TestTheSizeFloorRoundTripsWithAnUnsetFontSize;
{ The user-visible payoff, and the exact measurement section 5 of the plan recorded as
  UNFIXED: with the size left unset, TTyCheckBox's Constraints floor went 70x17 -> 78x20
  across ONE 96->240->96 trip and never came back, because the caption was being measured
  with a bigger font after the crossing than before it.

  This is deliberately asserted on the FLOOR rather than on Font.Height: the floor is what
  clamps the control's bounds, so it is the thing the user sees, and it fails for the same
  reason whether the latch arrives through this path or a future one. It is also why the
  fix belongs in the library rather than in the harness -- TControlDpiRoundTripTest dodges
  this by pinning an explicit size, which no real application does. }
var
  cb: TTyCheckBox;
  w0, h0: Integer;
begin
  cb := TTyCheckBox.Create(FForm);
  cb.Parent := FForm;
  cb.Controller := FCtl;
  cb.Caption := 'Check me';
  cb.SetBounds(10, 190, 150, 26);
  MakeUnsetAt96(cb);
  cb.Invalidate;                       // re-derive the floor at the settled state

  w0 := cb.Constraints.MinWidth;
  h0 := cb.Constraints.MinHeight;
  AssertTrue('precondition: TTyCheckBox owns a size floor', (w0 > 0) and (h0 > 0));

  Cross(240);
  Cross(96);

  AssertEquals('TTyCheckBox width floor after 96->240->96 with an UNSET font size' + Ctx,
    w0, cb.Constraints.MinWidth);
  AssertEquals('TTyCheckBox height floor after 96->240->96 with an UNSET font size' + Ctx,
    h0, cb.Constraints.MinHeight);
end;

initialization
  RegisterTest(TTyDpiFontLatchTest);

end.
