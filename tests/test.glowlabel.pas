unit test.glowlabel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, TypInfo, Graphics, fpcunit, testregistry,
  tyControls.Controller, tyControls.GlowLabel;
type
  { CalculatePreferredSize is protected; the AutoSize tests must ask it DIRECTLY. Going
    through Width would measure nothing: LCL's AutoSizeDelayed suppresses every re-fit while
    the parent form has no handle, and the headless runner never realises one. }
  TTyGlowLabelAccess = class(TTyGlowLabel)
  public
    procedure CallPreferred(out AW, AH: Integer);
  end;

  TGlowLabelTest = class(TTestCase)
  published
    procedure TestClampRadius;
    procedure TestSmoke;
    procedure TestAutoSizeIsPublishedAndOffByDefault;
    procedure TestPreferredWidthGrowsWithCaption;
    procedure TestPreferredWidthIncludesTheHalo;
    procedure TestRoomierThemeWidensPreferredWidth;
    procedure TestMnemonicMarkerAddsNoWidth;
  end;
implementation

procedure TTyGlowLabelAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TGlowLabelTest.TestClampRadius;
begin
  AssertEquals('negative -> 0', 0, TyGlowClampRadius(-3));
  AssertEquals('zero passes', 0, TyGlowClampRadius(0));
  AssertEquals('in range passes', 4, TyGlowClampRadius(4));
  AssertEquals('upper bound', 64, TyGlowClampRadius(64));
  AssertEquals('over max clamps', 64, TyGlowClampRadius(999));
end;

procedure TGlowLabelTest.TestSmoke;
var G: TTyGlowLabel;
begin
  // Construct, set the effect props, free — no crash (headless).
  G := TTyGlowLabel.Create(nil);
  try
    G.Caption := 'Glow &Label';
    G.GlowColor := $80FF3366;
    G.GlowRadius := 6;
    AssertEquals('radius stored', 6, G.GlowRadius);
    G.GlowRadius := -10;   // clamps through the setter
    AssertEquals('radius clamped', 0, G.GlowRadius);
  finally
    G.Free;
  end;
end;

procedure TGlowLabelTest.TestAutoSizeIsPublishedAndOffByDefault;
{ AutoSize has to be settable from a .lfm and from the object inspector, and it has to stay
  OFF: this is purely additive, so no designed layout moves unless someone opts in. }
var
  G: TTyGlowLabel;
begin
  G := TTyGlowLabel.Create(nil);
  try
    AssertTrue('AutoSize is published so a .lfm / the OI can set it',
      IsPublishedProp(G, 'AutoSize'));
    AssertFalse('but it stays OFF by default — a designed label keeps its width', G.AutoSize);
  finally
    G.Free;
  end;
end;

procedure TGlowLabelTest.TestPreferredWidthGrowsWithCaption;
{ The whole point: a longer caption must want a wider control instead of being clipped.
  Height must stay unproposed (0 = "no preference on this axis" in LCL) so the label never
  fights a container that pins the row height. }
var
  Ctl: TTyStyleController;
  G: TTyGlowLabelAccess;
  w, h, wLong, hLong: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    // Known padding + font so the arithmetic is exact rather than theme-dependent.
    Ctl.LoadThemeCss('TyGlowLabel { background: #FFFFFF; color: #101010; padding: 2px 4px; font-size: 12px; }');
    G := TTyGlowLabelAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.GlowRadius := 0;         // isolate the caption; the halo has its own test

      G.Caption := 'Aero';
      G.CallPreferred(w, h);
      AssertTrue('preferred width leaves room for both 4px paddings', w > 2 * 4);
      AssertEquals('height is left to the layout, not proposed', 0, h);

      G.Caption := 'A considerably longer glowing heading';
      G.CallPreferred(wLong, hLong);
      AssertTrue(Format('a longer caption wants more width (%d -> %d)', [w, wLong]), wLong > w);
      AssertEquals('and still proposes no height', 0, hLong);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TGlowLabelTest.TestPreferredWidthIncludesTheHalo;
{ This label's own "slot": the glow layer is the same text blurred by Scale(GlowRadius), so
  the halo bleeds one radius OUTWARD from the glyphs on every side, and the blur lives on a
  layer the size of the control's own bitmap — anything past the edge is clipped away. A box
  sized to the crisp text alone therefore shows a halo with its outer edge shaved off, so the
  reserved width must grow by one radius PER SIDE. }
var
  Ctl: TTyStyleController;
  G: TTyGlowLabelAccess;
  flat, haloed, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyGlowLabel { background: #FFFFFF; color: #101010; padding: 0px; font-size: 12px; }');
    G := TTyGlowLabelAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.Caption := 'Heading';

      G.GlowRadius := 0;
      G.CallPreferred(flat, h);

      G.GlowRadius := 8;
      G.CallPreferred(haloed, h);
      AssertEquals('the halo reserves one radius on each side', flat + 2 * 8, haloed);
      AssertEquals('and still proposes no height', 0, h);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TGlowLabelTest.TestRoomierThemeWidensPreferredWidth;
{ The actual bug this exists for: a skin legitimately changes padding (the 'xp' skin asks for
  12px where the default asks 6px), so a hand-set width clips under one skin and not another.
  Same caption, roomier theme -> more preferred width, by exactly the extra padding. }
var
  Ctl: TTyStyleController;
  G: TTyGlowLabelAccess;
  tight, roomy, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    G := TTyGlowLabelAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.GlowRadius := 4;         // held constant so only the padding moves
      G.Caption := 'Dashboard';

      Ctl.LoadThemeCss('TyGlowLabel { background: #FFFFFF; color: #101010; padding: 2px 4px; font-size: 12px; }');
      G.CallPreferred(tight, h);

      Ctl.LoadThemeCss('TyGlowLabel { background: #FFFFFF; color: #101010; padding: 2px 20px; font-size: 12px; }');
      G.CallPreferred(roomy, h);
      AssertTrue(Format('a roomier theme widens the label (%d -> %d)', [tight, roomy]),
        roomy > tight);
      // 16px more padding per side = 32px more width, and nothing else changed.
      AssertEquals('the extra width is exactly the extra padding', tight + 32, roomy);
      AssertEquals('and no height is proposed either way', 0, h);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TGlowLabelTest.TestMnemonicMarkerAddsNoWidth;
{ Unlike its two sibling labels, this one DOES parse mnemonics: RenderTo draws the
  TyParseMnemonic'd text, so the '&' becomes an underline, not a glyph. Measuring it as a
  character would over-reserve and make AutoSize disagree with the paint. }
var
  Ctl: TTyStyleController;
  G: TTyGlowLabelAccess;
  plain, marked, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyGlowLabel { background: #FFFFFF; color: #101010; padding: 0px; font-size: 12px; }');
    G := TTyGlowLabelAccess.Create(nil);
    try
      G.Controller := Ctl;
      G.Font.PixelsPerInch := 96;
      G.GlowRadius := 0;

      G.Caption := 'Save';
      G.CallPreferred(plain, h);
      G.Caption := '&Save';
      G.CallPreferred(marked, h);
      AssertEquals('a mnemonic marker adds no width', plain, marked);
    finally
      G.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TGlowLabelTest);
end.
