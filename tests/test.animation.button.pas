unit test.animation.button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller,
  tyControls.Button;
type
  { Probe subclass re-exposes RenderTo, lets tests force-enable animations
    (no wall-clock), simulate hover enter/leave, step the bg-fade animator a
    fixed number of milliseconds, and read back the raw fade progress. }
  TTyButtonAnimProbe = class(TTyButton)
  public
    procedure SetAnimationsEnabled(AValue: Boolean);
    procedure CallMouseEnter;
    procedure CallMouseLeave;
    function StepAnimation(AMs: Integer): Boolean;
    procedure ArmTo(ATarget: Single);
    function BgProgress: Single;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { Steppable hover-color-fade tests (deterministic, no real timers).
    Stylesheet: normal background #333333, hover background #777777. The fade
    blends those via TyLerpColor(normal, hover, FBgAnim.Eased). }
  TTyButtonBgFadeTest = class(TTestCase)
  published
    procedure TestNormalFillAtEasedZero;
    procedure TestHoverFillAfterFullAdvance;
    procedure TestMidProgressBlendsBetween;
    procedure TestHeadlessDefaultSnapsToHover;
    procedure TestAnimationsEnabledDefaultsTrue;
  end;

implementation

const
  NormalChan = $33;  // #333333
  HoverChan  = $77;  // #777777
  W = 80;
  H = 28;
  CX = W div 2;
  CY = H div 2;

function MakeController: TTyStyleController;
begin
  Result := TTyStyleController.Create(nil);
  Result.LoadThemeCss(
    'TyButton { background: #333333; color: #FFFFFF; border-width: 0px; }' +
    'TyButton:hover { background: #777777; }');
end;

function RenderBitmap(AB: TTyButtonAnimProbe): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(W, H);
    AB.RenderTo(Bmp.Canvas, Rect(0, 0, W, H), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ TTyButtonAnimProbe }

procedure TTyButtonAnimProbe.SetAnimationsEnabled(AValue: Boolean);
begin
  AnimationsEnabled := AValue;
end;

procedure TTyButtonAnimProbe.CallMouseEnter;
begin
  MouseEnter;
end;

procedure TTyButtonAnimProbe.CallMouseLeave;
begin
  MouseLeave;
end;

function TTyButtonAnimProbe.StepAnimation(AMs: Integer): Boolean;
begin
  Result := AdvanceAnimation(AMs);
end;

procedure TTyButtonAnimProbe.ArmTo(ATarget: Single);
begin
  ArmBgAnim(ATarget);
end;

function TTyButtonAnimProbe.BgProgress: Single;
begin
  Result := BgAnimProgress;
end;

procedure TTyButtonAnimProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ TTyButtonBgFadeTest }

procedure TTyButtonBgFadeTest.TestNormalFillAtEasedZero;
{ With animations enabled but the fade at rest (Eased=0), the centre pixel is
  the normal background #333333. (No caption -> centre is pure background.) }
var
  Ctl: TTyStyleController;
  B: TTyButtonAnimProbe;
  Bmp: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := MakeController;
  try
    B := TTyButtonAnimProbe.Create(nil);
    try
      B.Controller := Ctl;
      B.SetAnimationsEnabled(True);
      B.Caption := '';
      AssertTrue('fade starts at 0', Abs(B.BgProgress - 0.0) < 1e-6);
      Bmp := RenderBitmap(B);
      try
        Px := Bmp.GetPixel(CX, CY);
        AssertTrue('R ~ normal #33', Abs(Integer(Px.red) - NormalChan) <= 6);
        AssertTrue('G ~ normal #33', Abs(Integer(Px.green) - NormalChan) <= 6);
        AssertTrue('B ~ normal #33', Abs(Integer(Px.blue) - NormalChan) <= 6);
      finally
        Bmp.Free;
      end;
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyButtonBgFadeTest.TestHoverFillAfterFullAdvance;
{ The settled hover state: MouseEnter (headless -> snaps the fade to Eased=1 and
  sets FHover) lands the centre pixel on the hover background #777777. This is
  the settled end-state of the slide; the interpolating midpoint is covered by
  TestMidProgressBlendsBetween. }
var
  Ctl: TTyStyleController;
  B: TTyButtonAnimProbe;
  Bmp: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := MakeController;
  try
    B := TTyButtonAnimProbe.Create(nil);
    try
      B.Controller := Ctl;
      B.SetAnimationsEnabled(True);
      B.Caption := '';
      B.CallMouseEnter;      // headless -> snaps to settled hover (Eased=1, FHover)
      AssertTrue('fade reaches 1.0',
        Abs(B.BgProgress - 1.0) < 1e-6);
      Bmp := RenderBitmap(B);
      try
        Px := Bmp.GetPixel(CX, CY);
        AssertTrue('R ~ hover #77', Abs(Integer(Px.red) - HoverChan) <= 6);
        AssertTrue('G ~ hover #77', Abs(Integer(Px.green) - HoverChan) <= 6);
        AssertTrue('B ~ hover #77', Abs(Integer(Px.blue) - HoverChan) <= 6);
      finally
        Bmp.Free;
      end;
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyButtonBgFadeTest.TestMidProgressBlendsBetween;
{ At mid progress the centre pixel channel sits strictly between the normal
  (#33) and hover (#77) channel values: a real interpolation, not a snap. }
var
  Ctl: TTyStyleController;
  B: TTyButtonAnimProbe;
  Bmp: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := MakeController;
  try
    B := TTyButtonAnimProbe.Create(nil);
    try
      B.Controller := Ctl;
      B.SetAnimationsEnabled(True);
      B.Caption := '';
      B.ArmTo(1);           // arm toward hover without snapping
      B.StepAnimation(40);  // partial -> between 0 and 1 (eased)
      AssertTrue('raw progress strictly between 0 and 1',
        (B.BgProgress > 0.0) and (B.BgProgress < 1.0));
      Bmp := RenderBitmap(B);
      try
        Px := Bmp.GetPixel(CX, CY);
        AssertTrue('R blended above normal #33', Px.red > NormalChan + 2);
        AssertTrue('R blended below hover #77',  Px.red < HoverChan - 2);
      finally
        Bmp.Free;
      end;
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyButtonBgFadeTest.TestHeadlessDefaultSnapsToHover;
{ Headless (no window handle): MouseEnter snaps the fade straight to hover so
  the centre pixel is #777777 with no advancing required. Animations now default
  ON, but the snap is gated on HandleAllocated, so handle-less render tests still
  settle to the final state — this is what keeps the existing paint tests green. }
var
  Ctl: TTyStyleController;
  B: TTyButtonAnimProbe;
  Bmp: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := MakeController;
  try
    B := TTyButtonAnimProbe.Create(nil);
    try
      B.Controller := Ctl;
      // animations default ON now; with no window handle the hover path snaps
      B.Caption := '';
      B.CallMouseEnter;
      AssertTrue('headless snap: fade = 1.0 immediately',
        Abs(B.BgProgress - 1.0) < 1e-6);
      Bmp := RenderBitmap(B);
      try
        Px := Bmp.GetPixel(CX, CY);
        AssertTrue('snapped hover R ~ #77', Abs(Integer(Px.red) - HoverChan) <= 6);
      finally
        Bmp.Free;
      end;
    finally
      B.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyButtonBgFadeTest.TestAnimationsEnabledDefaultsTrue;
{ Motion is on out of the box: a freshly-created button has AnimationsEnabled
  True by default. (Headless render tests stay green because the state-change
  path still snaps when there is no window handle.) }
var
  B: TTyButton;
begin
  B := TTyButton.Create(nil);
  try
    AssertTrue('AnimationsEnabled defaults to True', B.AnimationsEnabled);
  finally
    B.Free;
  end;
end;

initialization
  RegisterTest(TTyButtonBgFadeTest);
end.
