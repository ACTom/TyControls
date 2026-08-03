unit test.divider;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Divider;

type
  { Pure-geometry tests: TyDividerLayout takes only integers, so it runs with no
    window handle and no control instance at all. }
  TTyDividerLayoutTest = class(TTestCase)
  published
    procedure TestLeftJustify;
    procedure TestRightJustify;
    procedure TestCenterHasTwoRules;
    procedure TestNoCaptionFullWidthRule;
    procedure TestRuleVerticallyCentred;
    procedure TestCaptionFillsWidthDropsRule;
    procedure TestCaptionWiderThanWidthClamped;
    procedure TestZeroWidthEmpty;
    procedure TestGapSeparatesCaptionAndRule;
  end;

  { Headless control behaviour: typeKey reuse, defaults, and a render smoke test
    that proves the rule is painted in the resolved theme colour. }
  TTyDividerControlTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestRuleRendersThemeColour;
    procedure TestCaptionRendersThemeColour;
  end;

implementation

type
  TDividerAccess = class(TTyDivider)
  public
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

function TDividerAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TDividerAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ TTyDividerLayoutTest }

procedure TTyDividerLayoutTest.TestLeftJustify;
var
  L: TTyDividerLayout;
begin
  // Width 200, caption 40, gap 6, minRule 4, thick 1. TyDividerIndentAuto = the
  // caption is placed by Alignment, which is what every case below exercises.
  L := TyDividerLayout(200, 24, 40, taLeftJustify, TyDividerIndentAuto, 6, 4, 1);
  // Caption hugs the left, starting at x=0.
  AssertEquals('caption left = 0', 0, L.CaptionRect.Left);
  AssertEquals('caption right = 40', 40, L.CaptionRect.Right);
  // No left rule for left-justified.
  AssertEquals('no left rule (empty)', 0, L.LeftRule.Right - L.LeftRule.Left);
  // Right rule starts after caption + gap and runs to the width.
  AssertEquals('right rule starts after caption+gap', 46, L.RightRule.Left);
  AssertEquals('right rule ends at width', 200, L.RightRule.Right);
end;

procedure TTyDividerLayoutTest.TestRightJustify;
var
  L: TTyDividerLayout;
begin
  L := TyDividerLayout(200, 24, 40, taRightJustify, TyDividerIndentAuto, 6, 4, 1);
  // Caption hugs the right edge.
  AssertEquals('caption right = width', 200, L.CaptionRect.Right);
  AssertEquals('caption left = width - capW', 160, L.CaptionRect.Left);
  // Left rule fills the space to the caption's left; no right rule.
  AssertEquals('left rule starts at 0', 0, L.LeftRule.Left);
  AssertEquals('left rule ends at caption-gap', 154, L.LeftRule.Right);
  AssertEquals('no right rule (empty)', 0, L.RightRule.Right - L.RightRule.Left);
end;

procedure TTyDividerLayoutTest.TestCenterHasTwoRules;
var
  L: TTyDividerLayout;
begin
  L := TyDividerLayout(200, 24, 40, taCenter, TyDividerIndentAuto, 6, 4, 1);
  // Caption centred: (200-40)/2 = 80 .. 120.
  AssertEquals('caption centred left', 80, L.CaptionRect.Left);
  AssertEquals('caption centred right', 120, L.CaptionRect.Right);
  // A rule on EACH side.
  AssertTrue('left rule present', L.LeftRule.Right > L.LeftRule.Left);
  AssertTrue('right rule present', L.RightRule.Right > L.RightRule.Left);
  AssertEquals('left rule from 0', 0, L.LeftRule.Left);
  AssertEquals('left rule to caption-gap', 74, L.LeftRule.Right);
  AssertEquals('right rule from caption+gap', 126, L.RightRule.Left);
  AssertEquals('right rule to width', 200, L.RightRule.Right);
end;

procedure TTyDividerLayoutTest.TestNoCaptionFullWidthRule;
var
  L: TTyDividerLayout;
begin
  // capW = 0 => a single full-width rule; caption empty.
  L := TyDividerLayout(200, 24, 0, taCenter, TyDividerIndentAuto, 6, 4, 1);
  AssertEquals('no caption (empty rect)', 0, L.CaptionRect.Right - L.CaptionRect.Left);
  AssertEquals('rule spans full width (left 0)', 0, L.RightRule.Left);
  AssertEquals('rule spans full width (right 200)', 200, L.RightRule.Right);
end;

procedure TTyDividerLayoutTest.TestRuleVerticallyCentred;
var
  L: TTyDividerLayout;
begin
  // Height 24, thick 4 => rule band top = (24-4)/2 = 10, bottom = 14.
  L := TyDividerLayout(200, 24, 40, taLeftJustify, TyDividerIndentAuto, 6, 4, 4);
  AssertEquals('rule band top centred', 10, L.RightRule.Top);
  AssertEquals('rule band bottom', 14, L.RightRule.Bottom);
end;

procedure TTyDividerLayoutTest.TestCaptionFillsWidthDropsRule;
var
  L: TTyDividerLayout;
begin
  // Caption 196 of 200 leaves only 4 (< gap+minRule) so the rule collapses.
  L := TyDividerLayout(200, 24, 196, taLeftJustify, TyDividerIndentAuto, 6, 4, 1);
  AssertEquals('caption fills nearly all width', 196, L.CaptionRect.Right);
  AssertEquals('right rule dropped (too short)', 0, L.RightRule.Right - L.RightRule.Left);
end;

procedure TTyDividerLayoutTest.TestCaptionWiderThanWidthClamped;
var
  L: TTyDividerLayout;
begin
  // Caption wider than the whole width clamps to the width; no rule fits.
  L := TyDividerLayout(100, 24, 300, taLeftJustify, TyDividerIndentAuto, 6, 4, 1);
  AssertEquals('caption clamped to width', 100, L.CaptionRect.Right);
  AssertEquals('no rule when caption fills all', 0, L.RightRule.Right - L.RightRule.Left);
end;

procedure TTyDividerLayoutTest.TestZeroWidthEmpty;
var
  L: TTyDividerLayout;
begin
  L := TyDividerLayout(0, 24, 40, taCenter, TyDividerIndentAuto, 6, 4, 1);
  AssertEquals('no caption at zero width', 0, L.CaptionRect.Right - L.CaptionRect.Left);
  AssertEquals('no left rule at zero width', 0, L.LeftRule.Right - L.LeftRule.Left);
  AssertEquals('no right rule at zero width', 0, L.RightRule.Right - L.RightRule.Left);
end;

procedure TTyDividerLayoutTest.TestGapSeparatesCaptionAndRule;
var
  L: TTyDividerLayout;
begin
  // The rule must not touch the caption: right-rule left = capRight + gap.
  L := TyDividerLayout(200, 24, 40, taLeftJustify, TyDividerIndentAuto, 10, 4, 1);
  AssertEquals('gap of 10 between caption(40) and rule', 50, L.RightRule.Left);
end;

{ TTyDividerControlTest }

procedure TTyDividerControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TTyDividerControlTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyDividerControlTest.TestTypeKey;
var
  Acc: TDividerAccess;
begin
  Acc := TDividerAccess.Create(FForm);
  Acc.Parent := FForm;
  try
    // Reuses the TyLabel typeKey (no new theme token this batch).
    AssertEquals('TyDivider', Acc.StyleTypeKey);
  finally
    Acc.Free;
  end;
end;

procedure TTyDividerControlTest.TestDefaults;
var
  D: TTyDivider;
begin
  D := TTyDivider.Create(FForm);
  try
    AssertEquals('default caption empty', '', D.Caption);
    AssertEquals('default alignment left', Ord(taLeftJustify), Ord(D.Alignment));
    AssertEquals('default width 150', 150, D.Width);
    AssertEquals('default height 24', 24, D.Height);
  finally
    D.Free;
  end;
end;

{ TestRuleRendersThemeColour
  Theme: TyLabel with an accent border colour. A caption-less left-justified
  divider draws a full-width rule; probe a pixel on the vertical mid-line and
  assert it is the accent (blue-dominant) fill, not blank. }
procedure TTyDividerControlTest.TestRuleRendersThemeColour;
var
  Ctl: TTyStyleController;
  D: TDividerAccess;
  F: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  found: Boolean;
  x, midY: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    // Accent border => the rule takes the border colour; no padding so it spans edge-to-edge.
    Ctl.LoadThemeCss(
      'TyLabel, TyDivider { color: #CCCCCC; border-color: #3B82F6; border-width: 1px; padding: 0px; }');
    D := TDividerAccess.Create(F);
    D.Parent := F;
    D.Controller := Ctl;
    D.Font.PixelsPerInch := 96;
    D.Caption := '';            // no caption -> full-width rule
    D.SetBounds(0, 0, 120, 24);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 24);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 120, 24);
    D.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // The 1px rule is at the vertical centre; scan a small band around mid-height
      // for a blue-dominant pixel (AA may spread it across ~1-2 rows).
      found := False;
      for midY := 10 to 13 do
        for x := 20 to 100 do
        begin
          Px := Reread.GetPixel(x, midY);
          if (Px.blue > 180) and (Px.red < 120) then
          begin
            found := True;
            Break;
          end;
        end;
      AssertTrue('accent rule painted across the divider width', found);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

{ TestCaptionRendersThemeColour
  Left-justified divider with a caption. Probe within the caption area for a
  text-colour (green-tinted here) pixel to prove the caption is drawn in the
  resolved TyLabel text colour, not blank / not the LCL Font. }
procedure TTyDividerControlTest.TestCaptionRendersThemeColour;
var
  Ctl: TTyStyleController;
  D: TDividerAccess;
  F: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  found: Boolean;
  x, y: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  F := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    // Distinct green text colour so we can find caption glyphs against a white bg.
    Ctl.LoadThemeCss(
      'TyLabel, TyDivider { color: #10B981; border-color: #D1D5DB; border-width: 1px; padding: 0px; font-size: 12px; }');
    D := TDividerAccess.Create(F);
    D.Parent := F;
    D.Controller := Ctl;
    D.Font.PixelsPerInch := 96;
    D.Alignment := taLeftJustify;
    D.Caption := 'Section';
    D.SetBounds(0, 0, 200, 24);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 24);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 24);
    D.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Caption sits at the left; scan that band for a green-dominant glyph pixel.
      found := False;
      for y := 2 to 21 do
        for x := 0 to 60 do
        begin
          Px := Reread.GetPixel(x, y);
          if (Px.green > 120) and (Px.green > Px.red + 30) and (Px.green > Px.blue + 30) then
          begin
            found := True;
            Break;
          end;
        end;
      AssertTrue('caption text painted in the theme text colour', found);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    F.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyDividerLayoutTest);
  RegisterTest(TTyDividerControlTest);
end.
