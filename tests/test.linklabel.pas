unit test.linklabel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, TypInfo, Controls, Graphics, fpcunit, testregistry,
  tyControls.Controller, tyControls.LinkLabel;
type
  { CalculatePreferredSize and MeasureCaption are protected; the AutoSize tests must ask
    them DIRECTLY. Going through Width would measure nothing: LCL's AutoSizeDelayed
    suppresses every re-fit while the parent form has no handle, and the headless runner
    never realises one. }
  TTyLinkLabelAccess = class(TTyLinkLabel)
  public
    procedure CallPreferred(out AW, AH: Integer);
    procedure CallMeasure(APPI: Integer; out AW, AH: Integer);
  end;

  TLinkLabelTest = class(TTestCase)
  published
    procedure TestUnderlineRect;
    procedure TestSmoke;
    procedure TestAutoSizeIsPublishedAndOffByDefault;
    procedure TestPreferredWidthGrowsWithCaption;
    procedure TestPreferredWidthCoversTheUnderline;
    procedure TestRoomierThemeWidensPreferredWidth;
    procedure TestAmpersandIsMeasuredBecauseItIsDrawn;
  end;
implementation

procedure TTyLinkLabelAccess.CallPreferred(out AW, AH: Integer);
begin
  AW := 0; AH := 0;
  CalculatePreferredSize(AW, AH, True);
end;

procedure TTyLinkLabelAccess.CallMeasure(APPI: Integer; out AW, AH: Integer);
begin
  MeasureCaption(APPI, AW, AH);
end;

procedure TLinkLabelTest.TestUnderlineRect;
var r: TRect;
begin
  // Left-aligned: line starts at content left, 1px tall, dropped 3px from bottom.
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), 40, 3, taLeftJustify);
  AssertEquals('left.left',   10, r.Left);
  AssertEquals('left.right',  50, r.Right);
  AssertEquals('left.top',    17, r.Top);
  AssertEquals('left.bottom', 18, r.Bottom);

  // Right-aligned: line ends at content right.
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), 40, 3, taRightJustify);
  AssertEquals('right.left',  70, r.Left);
  AssertEquals('right.right', 110, r.Right);

  // Centred: symmetric inset ((100-40)/2 = 30 -> 10+30 = 40).
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), 40, 3, taCenter);
  AssertEquals('center.left',  40, r.Left);
  AssertEquals('center.right', 80, r.Right);

  // Width wider than content clamps to the content width.
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), 500, 3, taLeftJustify);
  AssertEquals('clamp.left',  10, r.Left);
  AssertEquals('clamp.right', 110, r.Right);

  // Negative width clamps to 0 (empty line).
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), -5, 3, taLeftJustify);
  AssertEquals('neg.left',  10, r.Left);
  AssertEquals('neg.right', 10, r.Right);
end;

procedure TLinkLabelTest.TestSmoke;
var lbl: TTyLinkLabel;
begin
  lbl := TTyLinkLabel.Create(nil);
  try
    lbl.Caption := 'Visit homepage';
    lbl.URL := 'https://example.com';
    lbl.AutoOpen := True;
    lbl.Alignment := taCenter;
    lbl.Layout := tlBottom;
    AssertEquals('caption round-trips', 'Visit homepage', lbl.Caption);
    AssertEquals('url round-trips', 'https://example.com', lbl.URL);
  finally
    lbl.Free;
  end;
end;

procedure TLinkLabelTest.TestAutoSizeIsPublishedAndOffByDefault;
{ AutoSize has to be settable from a .lfm and from the object inspector, and it has to stay
  OFF: this is purely additive, so no designed layout moves unless someone opts in. }
var
  L: TTyLinkLabel;
begin
  L := TTyLinkLabel.Create(nil);
  try
    AssertTrue('AutoSize is published so a .lfm / the OI can set it',
      IsPublishedProp(L, 'AutoSize'));
    AssertFalse('but it stays OFF by default — a designed link keeps its width', L.AutoSize);
  finally
    L.Free;
  end;
end;

procedure TLinkLabelTest.TestPreferredWidthGrowsWithCaption;
{ The whole point: a longer caption must want a wider control instead of being clipped.
  Height must stay unproposed (0 = "no preference on this axis" in LCL) so the link never
  fights a container that pins the row height. }
var
  Ctl: TTyStyleController;
  L: TTyLinkLabelAccess;
  w, h, wLong, hLong: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    // Known padding + font so the arithmetic is exact rather than theme-dependent.
    Ctl.LoadThemeCss('TyLinkLabel { background: #FFFFFF; color: #0000EE; padding: 2px 4px; font-size: 12px; }');
    L := TTyLinkLabelAccess.Create(nil);
    try
      L.Controller := Ctl;
      L.Font.PixelsPerInch := 96;

      L.Caption := 'Home';
      L.CallPreferred(w, h);
      AssertTrue('preferred width leaves room for both 4px paddings', w > 2 * 4);
      AssertEquals('height is left to the layout, not proposed', 0, h);

      L.Caption := 'Visit the project homepage for details';
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

procedure TLinkLabelTest.TestPreferredWidthCoversTheUnderline;
{ The link's own mark is the accent hairline, and TyLinkUnderlineRect CLAMPS it to the
  content width — so a box too narrow for the caption shortens the underline as well as the
  text. The preferred width must therefore cover the measured caption, and laying the
  underline out inside a box of that width must yield the FULL measured run, unclamped. }
var
  Ctl: TTyStyleController;
  L: TTyLinkLabelAccess;
  w, h, tw, th: Integer;
  under: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyLinkLabel { background: #FFFFFF; color: #0000EE; padding: 0px; font-size: 12px; }');
    L := TTyLinkLabelAccess.Create(nil);
    try
      L.Controller := Ctl;
      L.Font.PixelsPerInch := 96;
      L.Caption := 'Visit homepage';

      L.CallMeasure(96, tw, th);
      L.CallPreferred(w, h);
      AssertTrue('the measured caption is non-empty', tw > 0);
      AssertTrue(Format('preferred width covers the drawn caption (%d >= %d)', [w, tw]),
        w >= tw);

      // The underline the paint path would draw inside a box of the preferred width.
      under := TyLinkUnderlineRect(Rect(0, 0, w, 20), tw, 3, taLeftJustify);
      AssertEquals('the accent underline spans the whole caption, unclamped',
        tw, under.Right - under.Left);
    finally
      L.Free;
    end;
  finally
    Ctl.Free;
  end;
end;

procedure TLinkLabelTest.TestRoomierThemeWidensPreferredWidth;
{ The actual bug this exists for: a skin legitimately changes padding (the 'xp' skin asks for
  12px where the default asks 6px), so a hand-set width clips under one skin and not another.
  Same caption, roomier theme -> more preferred width, by exactly the extra padding. }
var
  Ctl: TTyStyleController;
  L: TTyLinkLabelAccess;
  tight, roomy, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    L := TTyLinkLabelAccess.Create(nil);
    try
      L.Controller := Ctl;
      L.Font.PixelsPerInch := 96;
      L.Caption := 'Documentation';

      Ctl.LoadThemeCss('TyLinkLabel { background: #FFFFFF; color: #0000EE; padding: 2px 4px; font-size: 12px; }');
      L.CallPreferred(tight, h);

      Ctl.LoadThemeCss('TyLinkLabel { background: #FFFFFF; color: #0000EE; padding: 2px 20px; font-size: 12px; }');
      L.CallPreferred(roomy, h);
      AssertTrue(Format('a roomier theme widens the link (%d -> %d)', [tight, roomy]),
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

procedure TLinkLabelTest.TestAmpersandIsMeasuredBecauseItIsDrawn;
{ The mirror image of the button's mnemonic test, and the reason this control must NOT copy
  it: RenderTo hands Caption to DrawText verbatim (a hyperlink has no Alt+key path), so an
  '&' is a real glyph. Measuring it away would under-reserve and clip the caption. }
var
  Ctl: TTyStyleController;
  L: TTyLinkLabelAccess;
  plain, amp, h: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyLinkLabel { background: #FFFFFF; color: #0000EE; padding: 0px; font-size: 12px; }');
    L := TTyLinkLabelAccess.Create(nil);
    try
      L.Controller := Ctl;
      L.Font.PixelsPerInch := 96;

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
  RegisterTest(TLinkLabelTest);
end.
