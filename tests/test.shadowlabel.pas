unit test.shadowlabel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, TypInfo, Graphics, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.ShadowLabel;
type
  { CalculatePreferredSize is protected; the AutoSize tests must ask it DIRECTLY. Going
    through Width would measure nothing: LCL's AutoSizeDelayed suppresses every re-fit while
    the parent form has no handle, and the headless runner never realises one. }
  TTyShadowLabelAccess = class(TTyShadowLabel)
  public
    procedure CallPreferred(out AW, AH: Integer);
  end;

  TShadowLabelTest = class(TTestCase)
  published
    procedure TestSmoke;
    procedure TestAutoSizeIsPublishedAndOffByDefault;
    procedure TestPreferredWidthGrowsWithCaption;
    procedure TestPreferredWidthIncludesTheShadowThrow;
    procedure TestRoomierThemeWidensPreferredWidth;
    procedure TestAmpersandIsMeasuredBecauseItIsDrawn;
  end;
implementation

procedure TTyShadowLabelAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TShadowLabelTest.TestSmoke;
var
  L: TTyShadowLabel;
begin
  // Construct, set the label's own props, and free with no crash.
  L := TTyShadowLabel.Create(nil);
  try
    L.Caption := 'Hello shadow';
    L.ShadowColor := TyRGBA(10, 20, 30, 90);
    L.ShadowOffsetX := 3;
    L.ShadowOffsetY := 2;
    AssertEquals('caption round-trips', 'Hello shadow', L.Caption);
    AssertEquals('offset X round-trips', 3, L.ShadowOffsetX);
    AssertEquals('offset Y round-trips', 2, L.ShadowOffsetY);
    AssertTrue('shadow colour round-trips', L.ShadowColor = TyRGBA(10, 20, 30, 90));
  finally
    L.Free;
  end;
end;

procedure TShadowLabelTest.TestAutoSizeIsPublishedAndOffByDefault;
{ AutoSize has to be settable from a .lfm and from the object inspector, and it has to stay
  OFF: this is purely additive, so no designed layout moves unless someone opts in. }
var
  L: TTyShadowLabel;
begin
  L := TTyShadowLabel.Create(nil);
  try
    AssertTrue('AutoSize is published so a .lfm / the OI can set it',
      IsPublishedProp(L, 'AutoSize'));
    AssertFalse('but it stays OFF by default — a designed label keeps its width', L.AutoSize);
  finally
    L.Free;
  end;
end;

procedure TShadowLabelTest.TestPreferredWidthGrowsWithCaption;
{ The whole point: a longer caption must want a wider control instead of being clipped.
  Height must stay unproposed (0 = "no preference on this axis" in LCL) so the label never
  fights a container that pins the row height. }
var
  Ctl: TTyStyleController;
  L: TTyShadowLabelAccess;
  w, h, wLong, hLong: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    // Known padding + font so the arithmetic is exact rather than theme-dependent.
    Ctl.LoadThemeCss('TyShadowLabel { background: #FFFFFF; color: #101010; padding: 2px 4px; font-size: 12px; }');
    L := TTyShadowLabelAccess.Create(nil);
    try
      L.Controller := Ctl;
      L.Font.PixelsPerInch := 96;
      L.ShadowOffsetX := 0;      // isolate the caption; the throw has its own test

      L.Caption := 'Title';
      L.CallPreferred(w, h);
      AssertTrue('preferred width leaves room for both 4px paddings', w > 2 * 4);
      AssertEquals('height is left to the layout, not proposed', 0, h);

      L.Caption := 'A considerably longer heading than before';
      L.CallPreferred(wLong, hLong);
      AssertTrue(Format('a longer caption wants more width (%d -> %d)', [w, wLong]), wLong > w);
      AssertEquals('and still proposes no height', 0, hLong);
    finally
      L.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TShadowLabelTest.TestPreferredWidthIncludesTheShadowThrow;
{ This label's own "slot": RenderTo draws the caption TWICE, the shadow pass offset sideways
  by Scale(ShadowOffsetX). That pass runs past the crisp glyphs, so a box sized to the crisp
  text alone has the drop shadow shaved off by the clip. The reserved width must therefore
  grow by exactly the throw — and by the same amount for a NEGATIVE offset, which throws the
  shadow the other way and needs just as much room. }
var
  Ctl: TTyStyleController;
  L: TTyShadowLabelAccess;
  none, thrown, back, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyShadowLabel { background: #FFFFFF; color: #101010; padding: 0px; font-size: 12px; }');
    L := TTyShadowLabelAccess.Create(nil);
    try
      L.Controller := Ctl;
      L.Font.PixelsPerInch := 96;
      L.Caption := 'Heading';

      L.ShadowOffsetX := 0;
      L.CallPreferred(none, h);

      L.ShadowOffsetX := 6;
      L.CallPreferred(thrown, h);
      AssertEquals('the shadow pass reserves its own throw', none + 6, thrown);

      L.ShadowOffsetX := -6;
      L.CallPreferred(back, h);
      AssertEquals('a shadow thrown the other way needs the same room', none + 6, back);

      AssertEquals('and none of this proposes a height', 0, h);
    finally
      L.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TShadowLabelTest.TestRoomierThemeWidensPreferredWidth;
{ The actual bug this exists for: a skin legitimately changes padding (the 'xp' skin asks for
  12px where the default asks 6px), so a hand-set width clips under one skin and not another.
  Same caption, roomier theme -> more preferred width, by exactly the extra padding. }
var
  Ctl: TTyStyleController;
  L: TTyShadowLabelAccess;
  tight, roomy, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    L := TTyShadowLabelAccess.Create(nil);
    try
      L.Controller := Ctl;
      L.Font.PixelsPerInch := 96;
      L.ShadowOffsetX := 1;      // held constant so only the padding moves
      L.Caption := 'Dashboard';

      Ctl.LoadThemeCss('TyShadowLabel { background: #FFFFFF; color: #101010; padding: 2px 4px; font-size: 12px; }');
      L.CallPreferred(tight, h);

      Ctl.LoadThemeCss('TyShadowLabel { background: #FFFFFF; color: #101010; padding: 2px 20px; font-size: 12px; }');
      L.CallPreferred(roomy, h);
      AssertTrue(Format('a roomier theme widens the label (%d -> %d)', [tight, roomy]),
        roomy > tight);
      // 16px more padding per side = 32px more width, and nothing else changed.
      AssertEquals('the extra width is exactly the extra padding', tight + 32, roomy);
      AssertEquals('and no height is proposed either way', 0, h);
    finally
      L.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TShadowLabelTest.TestAmpersandIsMeasuredBecauseItIsDrawn;
{ The mirror image of the button's mnemonic test, and the reason this control must NOT copy
  it: RenderTo hands Caption to DrawText verbatim (no TyParseMnemonic here), so an '&' is a
  real glyph. Measuring it away would under-reserve and clip the caption. }
var
  Ctl: TTyStyleController;
  L: TTyShadowLabelAccess;
  plain, amp, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyShadowLabel { background: #FFFFFF; color: #101010; padding: 0px; font-size: 12px; }');
    L := TTyShadowLabelAccess.Create(nil);
    try
      L.Controller := Ctl;
      L.Font.PixelsPerInch := 96;
      L.ShadowOffsetX := 0;

      L.Caption := 'Save';
      L.CallPreferred(plain, h);
      L.Caption := '&Save';
      L.CallPreferred(amp, h);
      AssertTrue(Format('the ampersand is drawn, so it is measured (%d -> %d)', [plain, amp]),
        amp > plain);
    finally
      L.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TShadowLabelTest);
end.
