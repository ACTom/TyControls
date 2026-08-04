unit test.parity.buttons;
{$mode objfpc}{$H+}
{ Third parity round -- the button family, the two option groups and the paint surface.

  Every guard here pins a member that the Object Inspector now offers AND the paint path (or
  the event path) now actually reads. That pairing is the whole point: the defect this pass
  exists to remove is the published property a control ignores, so a test that only asserts
  "the property exists" would certify exactly the bug. Where a property changes what is
  DRAWN, the assertion is on pixels; where it changes what is FIRED, on a counter; where it
  changes GEOMETRY, on the pure layout function the paint and the measurement share.

  SpeedButtonOnGradientParentReconstructsTheGradient was the one exception -- it MEASURED a
  known limitation instead of removing it. The limitation is gone, and the measurement it
  recorded is now the assertion. }
interface
uses
  Classes, SysUtils, Types, TypInfo, Math, fpcunit, testregistry,
  Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  tyControls.ImageCollection,
  tyControls.Button, tyControls.GlyphButtons, tyControls.ColorButton,
  tyControls.CheckBox, tyControls.GroupBox, tyControls.CheckGroup,
  tyControls.RadioGroup, tyControls.PaintPanel, tyControls.Panel;

type
  TButtonAccess = class(TTyButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallPreferred(out AW, AH: Integer);
  end;

  TGlyphAccess = class(TTyGlyphButtonBase)
  public
    procedure CallPreferred(out AW, AH: Integer);
    procedure SetLayout(AValue: TTyGlyphLayout);
  end;

  TCheckBoxAccess = class(TTyCheckBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TPanelAccess = class(TTyPanel)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TSpeedAccess = class(TTySpeedButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { --- TTyButton: Alignment + ShowAccelChar --------------------------------- }
  TButtonParityTest = class(TTestCase)
  published
    procedure AlignmentIsPublishedAndCentredByDefault;
    procedure LeftAlignedCaptionMovesTheInkLeft;
    procedure RightAlignedCaptionMovesTheInkRight;
    procedure ShowAccelCharIsPublishedAndOnByDefault;
    procedure ShowAccelCharOffWidensTheMeasuredCaption;
    procedure ShowAccelCharOffDrawsTheAmpersand;
  end;

  { --- TTyGlyphButtonBase: 4-way layout, Spacing, CanShowGlyph -------------- }
  TGlyphButtonParityTest = class(TTestCase)
  published
    procedure GlyphLayoutIsPublishedOnEveryDescendant;
    procedure SplitGlyphRightAnchorsTheGlyphAtTheRightEdge;
    procedure SplitGlyphBottomAnchorsTheGlyphAtTheBottom;
    procedure SplitGlyphRightNeverInvertsTheCaptionRect;
    procedure SpacingIsPublishedWithTheThemeSentinel;
    procedure SpacingOverridesTheThemeGapInTheMeasuredWidth;
    procedure CanShowGlyphIsPublicAndTracksTheSource;
    procedure StackedLayoutsBothOweTheHeight;
  end;

  { --- TTySpeedButton.FindDownButton ---------------------------------------- }
  TSpeedButtonParityTest = class(TTestCase)
  published
    procedure FindDownButtonReturnsThePressedMember;
    procedure FindDownButtonIsNilWhenTheGroupIsAllUp;
    procedure FindDownButtonIgnoresAnUngroupedButton;
    procedure FindDownButtonIgnoresAnotherGroup;
  end;

  { --- TTyCheckGroup -------------------------------------------------------- }
  TCheckGroupParityTest = class(TTestCase)
  private
    FItemChanges, FItemClicks, FLastIndex, FGroupKeys: Integer;
    procedure HItemChange(Sender: TObject; AIndex: Integer);
    procedure HItemClick(Sender: TObject; AIndex: Integer);
    procedure HGroupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  published
    procedure ColumnLayoutDefaultsToRowMajorLikeLcl;
    procedure ColumnLayoutRePlacesTheChildren;
    procedure ButtonsHandsOutTheHostedCheckBox;
    procedure ButtonsRaisesOnAnOutOfRangeIndex;
    procedure CheckEnabledGreysOneItemOnly;
    procedure CheckEnabledRaisesOnAnOutOfRangeIndex;
    procedure CheckEnabledSurvivesAnItemsEdit;
    procedure OnItemClickFiresAlongsideOnItemChange;
    procedure AChildsKeyReachesTheGroupsOnKeyDown;
  end;

  { --- TTyRadioGroup -------------------------------------------------------- }
  TRadioGroupParityTest = class(TTestCase)
  private
    FEnters, FExits, FGroupKeys: Integer;
    FLastEnterSender: TObject;
    procedure HItemEnter(Sender: TObject);
    procedure HItemExit(Sender: TObject);
    procedure HGroupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  published
    procedure ColumnLayoutDefaultsToRowMajorLikeLcl;
    procedure ButtonsHandsOutTheHostedRadio;
    procedure ButtonsRaisesOnAnOutOfRangeIndex;
    procedure OnItemEnterCarriesTheButtonAsSender;
    procedure ItemFocusEventsAreWiredOntoEveryChild;
    procedure ArrowDownMovesTheSelectionOneRow;
    procedure ArrowRightHonoursTheColumnLayout;
    procedure ArrowNavigationStepsOverADisabledItem;
    procedure ArrowNavigationStopsAtTheEnds;
    procedure AChildsKeyReachesTheGroupsOnKeyDown;
  end;

  { --- TTyCheckBox / TTyRadioButton.Alignment ------------------------------- }
  TIndicatorSideParityTest = class(TTestCase)
  published
    procedure AlignmentIsPublishedWithLclsDefaultOnBoth;
    procedure LeftJustifyMovesTheIndicatorToTheRightEdge;
    procedure DefaultKeepsTheIndicatorOnTheLeft;
  end;

  { --- TTyColorButton ------------------------------------------------------- }
  TColorButtonParityTest = class(TTestCase)
  private
    FChange, FChanged: Integer;
    procedure HChange(Sender: TObject);
    procedure HChanged(Sender: TObject);
  published
    procedure ButtonColorRoundTripsThroughTColor;
    procedure ButtonColorIsPublishedButNotStored;
    procedure ButtonColorPreservesTheAlpha;
    procedure OnColorChangedFiresAlongsideOnColorChange;
    procedure AlignmentDefaultsToLeftBesideTheSwatch;
  end;

  { --- TTyGroupBox / TTyPaintPanel ------------------------------------------ }
  TContainerParityTest = class(TTestCase)
  published
    procedure GroupBoxPublishesClientSize;
    procedure GroupBoxPublicationsReachBothGroupDescendants;
    procedure PaintPanelDropsAsASquareSurface;
    { The measurement behind the ancestor recommendation. }
    procedure PaintPanelStillAcceptsChildControls;
    procedure SpeedButtonOnGradientParentReconstructsTheGradient;
  end;

implementation

{ ---------------------------------------------------------------- access --- }

procedure TButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;

procedure TButtonAccess.CallPreferred(out AW, AH: Integer);
begin AW := 0; AH := 0; CalculatePreferredSize(AW, AH, True); end;

procedure TGlyphAccess.CallPreferred(out AW, AH: Integer);
begin AW := 0; AH := 0; CalculatePreferredSize(AW, AH, True); end;

procedure TGlyphAccess.SetLayout(AValue: TTyGlyphLayout);
begin GlyphLayout := AValue; end;

procedure TCheckBoxAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;

procedure TPanelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;

procedure TSpeedAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin inherited RenderTo(ACanvas, ARect, APPI); end;

{ Leftmost / rightmost column holding a pixel that is neither the white page nor the
  flat button face -- i.e. where the caption's ink actually starts and ends. Returns
  -1 / -1 when the strip is blank. }
procedure InkSpanX(ABmp: TBitmap; AW, AH: Integer; out AFirst, ALast: Integer);
var
  R: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
  hit: Boolean;
begin
  AFirst := -1;
  ALast := -1;
  R := TBGRABitmap.Create(ABmp);
  try
    for x := 0 to AW - 1 do
    begin
      hit := False;
      for y := 0 to AH - 1 do
      begin
        p := R.GetPixel(x, y);
        // The themes below paint a white face and black text, so "dark" is the ink.
        if (p.red < 128) and (p.green < 128) and (p.blue < 128) then hit := True;
      end;
      if hit then
      begin
        if AFirst < 0 then AFirst := x;
        ALast := x;
      end;
    end;
  finally
    R.Free;
  end;
end;

{ A controller with one flat, high-contrast rule per key, so ink is unambiguous. }
function FlatController(const ACss: string): TTyStyleController;
begin
  Result := TTyStyleController.Create(nil);
  Result.LoadThemeCss(ACss);
end;

{ ------------------------------------------------------------ TTyButton ---- }

procedure TButtonParityTest.AlignmentIsPublishedAndCentredByDefault;
var
  B: TTyButton;
begin
  AssertTrue('TTyButton publishes Alignment', GetPropInfo(TTyButton, 'Alignment') <> nil);
  { Every descendant inherits it -- the half-a-fix trap this pass keeps hitting. }
  AssertTrue('TTyGlyphButton too', GetPropInfo(TTyGlyphButton, 'Alignment') <> nil);
  AssertTrue('TTySpeedButton too', GetPropInfo(TTySpeedButton, 'Alignment') <> nil);
  AssertTrue('TTyGlyphContainerButton too',
    GetPropInfo(TTyGlyphContainerButton, 'Alignment') <> nil);
  B := TTyButton.Create(nil);
  try
    AssertEquals('default is taCenter, as LCL''s self-drawn button',
      Ord(taCenter), Ord(B.Alignment));
  finally
    B.Free;
  end;
end;

procedure TButtonParityTest.LeftAlignedCaptionMovesTheInkLeft;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TButtonAccess;
  Bmp: TBitmap;
  c0, c1, l0, l1: Integer;
begin
  Ctl := FlatController('TyButton { background: #FFFFFF; color: #000000; ' +
                        'border-width: 0px; padding: 2px; font-size: 12px; }');
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    B := TButtonAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'Go';

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 30);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 30), 96);
    InkSpanX(Bmp, 200, 30, c0, c1);
    AssertTrue('centred caption drew something', c0 >= 0);

    B.Alignment := taLeftJustify;
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 30), 96);
    InkSpanX(Bmp, 200, 30, l0, l1);
    AssertTrue('left-aligned caption drew something', l0 >= 0);

    { The load-bearing assertion: the property is READ by the paint. A published
      Alignment that left the ink where it was would be the exact defect this file guards. }
    AssertTrue(Format('taLeftJustify must move the ink left (centred=%d left=%d)', [c0, l0]),
      l0 < c0);
    AssertTrue('and it must sit near the padded left edge', l0 <= 6);
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TButtonParityTest.RightAlignedCaptionMovesTheInkRight;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TButtonAccess;
  Bmp: TBitmap;
  c0, c1, r0, r1: Integer;
begin
  Ctl := FlatController('TyButton { background: #FFFFFF; color: #000000; ' +
                        'border-width: 0px; padding: 2px; font-size: 12px; }');
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    B := TButtonAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'Go';

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 30);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 30), 96);
    InkSpanX(Bmp, 200, 30, c0, c1);

    B.Alignment := taRightJustify;
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 30), 96);
    InkSpanX(Bmp, 200, 30, r0, r1);
    AssertTrue('right-aligned caption drew something', r1 >= 0);
    AssertTrue(Format('taRightJustify must move the ink right (centred=%d right=%d)', [c1, r1]),
      r1 > c1);
    AssertTrue('and it must reach the padded right edge', r1 >= 200 - 8);
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TButtonParityTest.ShowAccelCharIsPublishedAndOnByDefault;
var
  B: TTyButton;
begin
  AssertTrue('TTyButton publishes ShowAccelChar',
    GetPropInfo(TTyButton, 'ShowAccelChar') <> nil);
  AssertTrue('TTySpeedButton too', GetPropInfo(TTySpeedButton, 'ShowAccelChar') <> nil);
  AssertTrue('TTyColorButton too', GetPropInfo(TTyColorButton, 'ShowAccelChar') <> nil);
  B := TTyButton.Create(nil);
  try
    AssertTrue('on by default, as LCL''s is', B.ShowAccelChar);
  finally
    B.Free;
  end;
end;

procedure TButtonParityTest.ShowAccelCharOffWidensTheMeasuredCaption;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TButtonAccess;
  wOn, wOff, h: Integer;
begin
  { The measurement has to follow the switch, or AutoSize would reserve room for a string
    the button no longer draws (or, worse, clip the one it does). }
  Ctl := FlatController('TyButton { background: #FFFFFF; color: #000000; ' +
                        'border-width: 0px; padding: 0px; font-size: 12px; }');
  Form := TForm.CreateNew(nil);
  try
    B := TButtonAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'AT&&T';   // Pascal source: one literal ampersand reaches the caption

    B.ShowAccelChar := True;
    B.CallPreferred(wOn, h);
    B.ShowAccelChar := False;
    B.CallPreferred(wOff, h);
    AssertTrue(Format('the literal ampersand costs width (on=%d off=%d)', [wOn, wOff]),
      wOff > wOn);
  finally
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TButtonParityTest.ShowAccelCharOffDrawsTheAmpersand;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TButtonAccess;
  Bmp: TBitmap;
  on0, on1, off0, off1: Integer;
begin
  Ctl := FlatController('TyButton { background: #FFFFFF; color: #000000; ' +
                        'border-width: 0px; padding: 2px; font-size: 14px; }');
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    B := TButtonAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'AT&&T';
    B.Alignment := taLeftJustify;   // pin the ink's origin so the SPAN is what varies

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(220, 30);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 220, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 220, 30), 96);
    InkSpanX(Bmp, 220, 30, on0, on1);

    B.ShowAccelChar := False;
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 220, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 220, 30), 96);
    InkSpanX(Bmp, 220, 30, off0, off1);

    AssertTrue('both renders drew ink', (on1 >= 0) and (off1 >= 0));
    { With the switch off the '&' is a CHARACTER, so the drawn string is wider. This is the
      user-visible bug: 'AT&T' silently rendered as 'ATT' with a stray accelerator on T. }
    AssertTrue(Format('the ampersand must really be drawn (span on=%d off=%d)',
      [on1 - on0, off1 - off0]), (off1 - off0) > (on1 - on0));
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ ------------------------------------------------------ TTyGlyphButton ----- }

procedure TGlyphButtonParityTest.GlyphLayoutIsPublishedOnEveryDescendant;
var
  T: TTyGlyphContainerButton;
begin
  { It existed as a PROTECTED property, so reaching it meant subclassing. Publishing it is
    the fix -- on the base and, because a fix that lands on a base and not its descendants
    is half a fix, on all four concrete buttons. }
  AssertTrue('base publishes GlyphLayout',
    GetPropInfo(TTyGlyphButtonBase, 'GlyphLayout') <> nil);
  AssertTrue('TTyGlyphButton', GetPropInfo(TTyGlyphButton, 'GlyphLayout') <> nil);
  AssertTrue('TTySpeedButton', GetPropInfo(TTySpeedButton, 'GlyphLayout') <> nil);
  AssertTrue('TTyGlyphContainerButton',
    GetPropInfo(TTyGlyphContainerButton, 'GlyphLayout') <> nil);
  T := TTyGlyphContainerButton.Create(nil);
  try
    { The ribbon tile redeclares its default so the streamer does not write GlyphLayout into
      every ribbon .lfm merely to restate what the constructor already did. }
    AssertEquals('the tile is glyph-top', Ord(glTop), Ord(T.GlyphLayout));
  finally
    T.Free;
  end;
end;

procedure TGlyphButtonParityTest.SplitGlyphRightAnchorsTheGlyphAtTheRightEdge;
var
  g, c: TRect;
begin
  // 100x40 content, 20px glyph, 6px gap.
  TyGlyphButtonSplit(Rect(0, 0, 100, 40), 20, 6, glRight, g, c);
  AssertEquals('glyph hugs the right edge', 100, g.Right);
  AssertEquals('glyph is its full width', 80, g.Left);
  AssertEquals('glyph is vertically centred', 10, g.Top);
  AssertEquals('glyph is square', 20, g.Bottom - g.Top);
  AssertEquals('caption starts at the left', 0, c.Left);
  AssertEquals('caption stops a gap short of the glyph', 74, c.Right);
end;

procedure TGlyphButtonParityTest.SplitGlyphBottomAnchorsTheGlyphAtTheBottom;
var
  g, c: TRect;
begin
  // 60x64 content, 24px glyph, 6px gap.
  TyGlyphButtonSplit(Rect(0, 0, 60, 64), 24, 6, glBottom, g, c);
  AssertEquals('glyph hugs the bottom edge', 64, g.Bottom);
  AssertEquals('glyph is its full height', 40, g.Top);
  AssertEquals('glyph is horizontally centred', 18, g.Left);
  AssertEquals('caption starts at the top', 0, c.Top);
  AssertEquals('caption stops a gap short of the glyph', 34, c.Bottom);
end;

procedure TGlyphButtonParityTest.SplitGlyphRightNeverInvertsTheCaptionRect;
var
  g, c: TRect;
begin
  { A glyph bigger than the box must COLLAPSE the caption rect, never invert it -- an
    inverted rect is what turns a tight tool bar into a crash or a smear downstream. The
    two layouts that shipped first already guaranteed this; the two new ones must too. }
  TyGlyphButtonSplit(Rect(0, 0, 30, 20), 50, 6, glRight, g, c);
  AssertTrue('caption rect not inverted (right)', c.Right >= c.Left);
  AssertTrue('glyph stays inside the box (right)', g.Left >= 0);
  TyGlyphButtonSplit(Rect(0, 0, 40, 18), 50, 6, glBottom, g, c);
  AssertTrue('caption rect not inverted (bottom)', c.Bottom >= c.Top);
  AssertTrue('glyph stays inside the box (bottom)', g.Top >= 0);
end;

procedure TGlyphButtonParityTest.SpacingIsPublishedWithTheThemeSentinel;
var
  B: TTyGlyphButton;
begin
  AssertTrue('base publishes Spacing', GetPropInfo(TTyGlyphButtonBase, 'Spacing') <> nil);
  AssertTrue('TTySpeedButton too', GetPropInfo(TTySpeedButton, 'Spacing') <> nil);
  B := TTyGlyphButton.Create(nil);
  try
    AssertEquals('-1 = the theme owns the gap', -1, B.Spacing);
    B.Spacing := -7;
    AssertEquals('only one sentinel; anything below -1 clamps to it', -1, B.Spacing);
    B.Spacing := 0;
    AssertEquals('zero is a legitimate literal gap', 0, B.Spacing);
  finally
    B.Free;
  end;
end;

procedure TGlyphButtonParityTest.SpacingOverridesTheThemeGapInTheMeasuredWidth;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TGlyphAccess;
  Coll: TTyImageCollection;
  wTheme, wWide, h: Integer;
begin
  { The gap has to reach the MEASUREMENT, not just the paint: a preferred width that
    disagrees with what is drawn is worse than no AutoSize at all. An image source is set
    so the glyph slot -- and therefore the gap -- is really in play. }
  Ctl := FlatController('TyButton { background: #FFFFFF; color: #000000; ' +
                        'border-width: 0px; padding: 0px; font-size: 12px; }');
  Form := TForm.CreateNew(nil);
  Coll := TTyImageCollection.Create(Form);
  try
    B := TGlyphAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'Save';
    B.Images := Coll;
    B.ImageName := 'anything';   // a name is all HasGlyphSource/CanShowGlyph needs
    B.GlyphSize := 16;
    B.Height := 30;

    B.Spacing := -1;
    B.CallPreferred(wTheme, h);
    B.Spacing := 40;
    B.CallPreferred(wWide, h);
    AssertTrue(Format('a wider Spacing must widen the measurement (theme=%d wide=%d)',
      [wTheme, wWide]), wWide > wTheme);
    { And exactly by the difference, not by some other amount: 40 logical px at 96 PPI
      against the built-in 6px default. }
    AssertEquals('the delta IS the gap difference', 40 - TyGlyphButtonGap, wWide - wTheme);
  finally
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TGlyphButtonParityTest.CanShowGlyphIsPublicAndTracksTheSource;
var
  Form: TForm;
  B: TTyGlyphButton;
  Coll: TTyImageCollection;
begin
  Form := TForm.CreateNew(nil);
  Coll := TTyImageCollection.Create(Form);
  try
    B := TTyGlyphButton.Create(Form);
    B.Parent := Form;
    // Reached from OUTSIDE the class -- that is the whole gap; it used to be protected.
    AssertFalse('no source yet', B.CanShowGlyph);
    B.Images := Coll;
    AssertFalse('a collection with no name is still no source', B.CanShowGlyph);
    B.ImageName := 'save';
    AssertTrue('an image source counts', B.CanShowGlyph);
    B.Images := nil;
    B.ImageName := '';
    AssertFalse('back to nothing', B.CanShowGlyph);
  finally
    Form.Free;
  end;
end;

procedure TGlyphButtonParityTest.StackedLayoutsBothOweTheHeight;
var
  Ctl: TTyStyleController;
  Form: TForm;
  B: TGlyphAccess;
  Coll: TTyImageCollection;
  wLeft, wTop, wBottom, wRight, h: Integer;
begin
  { glTop already shared the width with the caption instead of adding to it; glBottom is
    the same stack upside down and must behave identically, and glRight must behave like
    glLeft. Getting this wrong is the classic half-a-fix: the new members compile, look
    right in one layout, and mis-size in the other. }
  Ctl := FlatController('TyButton { background: #FFFFFF; color: #000000; ' +
                        'border-width: 0px; padding: 0px; font-size: 12px; }');
  Form := TForm.CreateNew(nil);
  Coll := TTyImageCollection.Create(Form);
  try
    B := TGlyphAccess.Create(Form);
    B.Parent := Form;
    B.Controller := Ctl;
    B.Font.PixelsPerInch := 96;
    B.Caption := 'A long enough caption';
    B.Images := Coll;
    B.ImageName := 'x';
    B.GlyphSize := 16;
    B.Height := 30;

    B.SetLayout(glLeft);   B.CallPreferred(wLeft, h);
    B.SetLayout(glRight);  B.CallPreferred(wRight, h);
    B.SetLayout(glTop);    B.CallPreferred(wTop, h);
    B.SetLayout(glBottom); B.CallPreferred(wBottom, h);

    AssertEquals('glRight costs the same width as glLeft', wLeft, wRight);
    AssertEquals('glBottom costs the same width as glTop', wTop, wBottom);
    AssertTrue('side-by-side is wider than stacked', wLeft > wTop);
  finally
    Form.Free;
    Ctl.Free;
  end;
end;

{ ------------------------------------------------------ TTySpeedButton ----- }

function MakeSpeed(AParent: TWinControl; AGroup: Integer; ADown: Boolean): TTySpeedButton;
begin
  Result := TTySpeedButton.Create(AParent);
  Result.Parent := AParent;
  Result.GroupIndex := AGroup;
  Result.AllowAllUp := True;   // so a group may legitimately be all-up
  Result.Down := ADown;
end;

procedure TSpeedButtonParityTest.FindDownButtonReturnsThePressedMember;
var
  Form: TForm;
  a, b, c: TTySpeedButton;
begin
  Form := TForm.CreateNew(nil);
  try
    a := MakeSpeed(Form, 1, False);
    b := MakeSpeed(Form, 1, True);
    c := MakeSpeed(Form, 1, False);
    AssertSame('asked from an up member', b, a.FindDownButton);
    AssertSame('asked from the down member itself', b, b.FindDownButton);
    AssertSame('asked from the other up member', b, c.FindDownButton);
  finally
    Form.Free;
  end;
end;

procedure TSpeedButtonParityTest.FindDownButtonIsNilWhenTheGroupIsAllUp;
var
  Form: TForm;
  a: TTySpeedButton;
begin
  Form := TForm.CreateNew(nil);
  try
    a := MakeSpeed(Form, 1, False);
    MakeSpeed(Form, 1, False);
    AssertTrue('all up -> nil', a.FindDownButton = nil);
  finally
    Form.Free;
  end;
end;

procedure TSpeedButtonParityTest.FindDownButtonIgnoresAnUngroupedButton;
var
  Form: TForm;
  loner: TTySpeedButton;
begin
  Form := TForm.CreateNew(nil);
  try
    { GroupIndex 0 means "not grouped". Answering Self here would pretend every plain
      toggle button is a one-member group, which is not a question anyone asked. }
    loner := MakeSpeed(Form, 0, True);
    AssertTrue('ungrouped -> nil even when down', loner.FindDownButton = nil);
  finally
    Form.Free;
  end;
end;

procedure TSpeedButtonParityTest.FindDownButtonIgnoresAnotherGroup;
var
  Form: TForm;
  a: TTySpeedButton;
begin
  Form := TForm.CreateNew(nil);
  try
    a := MakeSpeed(Form, 1, False);
    MakeSpeed(Form, 2, True);    // a different group, pressed
    AssertTrue('a pressed member of ANOTHER group is not ours', a.FindDownButton = nil);
  finally
    Form.Free;
  end;
end;

{ ------------------------------------------------------- TTyCheckGroup ----- }

procedure TCheckGroupParityTest.HItemChange(Sender: TObject; AIndex: Integer);
begin Inc(FItemChanges); FLastIndex := AIndex; end;

procedure TCheckGroupParityTest.HItemClick(Sender: TObject; AIndex: Integer);
begin Inc(FItemClicks); FLastIndex := AIndex; end;

procedure TCheckGroupParityTest.HGroupKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin Inc(FGroupKeys); end;

function MakeCheckGroup(AForm: TForm; const AItems: array of string): TTyCheckGroup;
var i: Integer;
begin
  Result := TTyCheckGroup.Create(AForm);
  Result.Parent := AForm;
  Result.SetBounds(0, 0, 240, 200);
  for i := Low(AItems) to High(AItems) do
    Result.Items.Add(AItems[i]);
end;

procedure TCheckGroupParityTest.ColumnLayoutDefaultsToRowMajorLikeLcl;
var
  G: TTyCheckGroup;
begin
  G := TTyCheckGroup.Create(nil);
  try
    AssertTrue('ColumnLayout is published',
      GetPropInfo(TTyCheckGroup, 'ColumnLayout') <> nil);
    AssertEquals('default is LCL''s clHorizontalThenVertical',
      Ord(clHorizontalThenVertical), Ord(G.ColumnLayout));
  finally
    G.Free;
  end;
end;

procedure TCheckGroupParityTest.ColumnLayoutRePlacesTheChildren;
var
  Form: TForm;
  G: TTyCheckGroup;
  l0, l1: Integer;
begin
  { The knob must move real children, not just a field. Reading the hosted checkbox's Left
    through the new Buttons[] accessor is what makes that assertable at all. }
  Form := TForm.CreateNew(nil);
  try
    G := MakeCheckGroup(Form, ['a', 'b', 'c', 'd']);
    G.Columns := 2;

    // Row-major (the default): item 1 sits in the SECOND column, beside item 0.
    l0 := G.Buttons[0].Left;
    l1 := G.Buttons[1].Left;
    AssertTrue(Format('row-major puts item 1 to the right of item 0 (%d vs %d)', [l0, l1]),
      l1 > l0);
    AssertEquals('and on the same row', G.Buttons[0].Top, G.Buttons[1].Top);

    G.ColumnLayout := clVerticalThenHorizontal;
    AssertEquals('column-major puts item 1 in the same column',
      G.Buttons[0].Left, G.Buttons[1].Left);
    AssertTrue('and on the next row', G.Buttons[1].Top > G.Buttons[0].Top);
  finally
    Form.Free;
  end;
end;

procedure TCheckGroupParityTest.ButtonsHandsOutTheHostedCheckBox;
var
  Form: TForm;
  G: TTyCheckGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeCheckGroup(Form, ['one', 'two']);
    AssertEquals('the child carries the item text', 'two', G.Buttons[1].Caption);
    { The point of handing it out: per-item properties the group does not re-expose. }
    G.Buttons[1].Hint := 'not in your edition';
    AssertEquals('a per-item hint is now reachable', 'not in your edition', G.Buttons[1].Hint);
  finally
    Form.Free;
  end;
end;

procedure TCheckGroupParityTest.ButtonsRaisesOnAnOutOfRangeIndex;
var
  Form: TForm;
  G: TTyCheckGroup;
  raised: Boolean;
  b: TTyCheckBox;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeCheckGroup(Form, ['one', 'two']);
    raised := False;
    try
      b := G.Buttons[5];
      if b = nil then ;   // silence the unused-result hint; the raise is the point
    except
      on E: EListError do raised := True;
    end;
    AssertTrue('an out-of-range Buttons[] raises, as LCL''s does', raised);
    raised := False;
    try
      b := G.Buttons[-1];
      if b = nil then ;
    except
      on E: EListError do raised := True;
    end;
    AssertTrue('negative too', raised);
  finally
    Form.Free;
  end;
end;

procedure TCheckGroupParityTest.CheckEnabledGreysOneItemOnly;
var
  Form: TForm;
  G: TTyCheckGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeCheckGroup(Form, ['a', 'b', 'c']);
    AssertTrue('every item starts usable', G.CheckEnabled[1]);
    G.CheckEnabled[1] := False;
    AssertFalse('the one item is greyed', G.CheckEnabled[1]);
    AssertTrue('its neighbours are untouched', G.CheckEnabled[0] and G.CheckEnabled[2]);
    // and it really reached the child, not just a shadow field
    AssertFalse('the hosted checkbox is disabled', G.Buttons[1].Enabled);
  finally
    Form.Free;
  end;
end;

procedure TCheckGroupParityTest.CheckEnabledRaisesOnAnOutOfRangeIndex;
var
  Form: TForm;
  G: TTyCheckGroup;
  raised: Boolean;
  v: Boolean;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeCheckGroup(Form, ['a', 'b']);
    raised := False;
    try
      v := G.CheckEnabled[9];
      if v then ;
    except
      on E: EListError do raised := True;
    end;
    AssertTrue('read out of range raises', raised);
    raised := False;
    try
      G.CheckEnabled[9] := False;
    except
      on E: EListError do raised := True;
    end;
    AssertTrue('write out of range raises', raised);
  finally
    Form.Free;
  end;
end;

procedure TCheckGroupParityTest.CheckEnabledSurvivesAnItemsEdit;
var
  Form: TForm;
  G: TTyCheckGroup;
begin
  { A per-item greying that vanished on the next Items edit would be a knob that works in
    the demo and not in the app -- the same identity rule Checked[] already rides on. }
  Form := TForm.CreateNew(nil);
  try
    G := MakeCheckGroup(Form, ['a', 'b', 'c']);
    G.CheckEnabled[1] := False;      // 'b' is unavailable
    G.Items.Insert(0, 'zero');       // full rebuild; 'b' is now index 2
    AssertEquals('the list really changed', 4, G.Count);
    AssertFalse('the greying followed the ITEM, not the slot', G.CheckEnabled[2]);
    AssertTrue('the item that slid into slot 1 is usable', G.CheckEnabled[1]);
  finally
    Form.Free;
  end;
end;

procedure TCheckGroupParityTest.OnItemClickFiresAlongsideOnItemChange;
var
  Form: TForm;
  G: TTyCheckGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeCheckGroup(Form, ['a', 'b']);
    FItemChanges := 0;
    FItemClicks := 0;
    FLastIndex := -1;
    G.OnItemChange := @HItemChange;
    G.OnItemClick := @HItemClick;
    // A user toggle: drive the hosted child, exactly as a click would.
    G.Buttons[1].Click;
    AssertEquals('our own event still fires', 1, FItemChanges);
    AssertEquals('LCL''s name fires too', 1, FItemClicks);
    AssertEquals('both are told which item', 1, FLastIndex);
  finally
    Form.Free;
  end;
end;

procedure TCheckGroupParityTest.AChildsKeyReachesTheGroupsOnKeyDown;
var
  Form: TForm;
  G: TTyCheckGroup;
  k: Word;
  h: TKeyEvent;
begin
  { The group never holds focus, so before the relays its OnKeyDown could be assigned and
    could never fire -- the silent no-op this pass removes. }
  Form := TForm.CreateNew(nil);
  try
    G := MakeCheckGroup(Form, ['a', 'b']);
    FGroupKeys := 0;
    G.OnKeyDown := @HGroupKeyDown;
    h := G.Buttons[0].OnKeyDown;
    AssertTrue('the child''s key event is wired to the group', Assigned(h));
    k := VK_F5;
    h(G.Buttons[0], k, []);
    AssertEquals('a key typed on a child reaches the group', 1, FGroupKeys);
  finally
    Form.Free;
  end;
end;

{ ------------------------------------------------------- TTyRadioGroup ----- }

procedure TRadioGroupParityTest.HItemEnter(Sender: TObject);
begin Inc(FEnters); FLastEnterSender := Sender; end;

procedure TRadioGroupParityTest.HItemExit(Sender: TObject);
begin Inc(FExits); end;

procedure TRadioGroupParityTest.HGroupKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin Inc(FGroupKeys); end;

function MakeRadioGroup(AForm: TForm; const AItems: array of string): TTyRadioGroup;
var i: Integer;
begin
  Result := TTyRadioGroup.Create(AForm);
  Result.Parent := AForm;
  Result.SetBounds(0, 0, 240, 220);
  for i := Low(AItems) to High(AItems) do
    Result.Items.Add(AItems[i]);
end;

procedure TRadioGroupParityTest.ColumnLayoutDefaultsToRowMajorLikeLcl;
var
  G: TTyRadioGroup;
begin
  G := TTyRadioGroup.Create(nil);
  try
    AssertTrue('ColumnLayout is published',
      GetPropInfo(TTyRadioGroup, 'ColumnLayout') <> nil);
    AssertEquals('default is LCL''s clHorizontalThenVertical',
      Ord(clHorizontalThenVertical), Ord(G.ColumnLayout));
  finally
    G.Free;
  end;
end;

procedure TRadioGroupParityTest.ButtonsHandsOutTheHostedRadio;
var
  Form: TForm;
  G: TTyRadioGroup;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeRadioGroup(Form, ['red', 'green']);
    AssertEquals('the child carries the item text', 'green', G.Buttons[1].Caption);
    G.Buttons[0].Enabled := False;
    AssertFalse('one option can now be disabled on its own', G.Buttons[0].Enabled);
    AssertTrue('without touching its neighbour', G.Buttons[1].Enabled);
  finally
    Form.Free;
  end;
end;

procedure TRadioGroupParityTest.ButtonsRaisesOnAnOutOfRangeIndex;
var
  Form: TForm;
  G: TTyRadioGroup;
  raised: Boolean;
  b: TTyRadioButton;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeRadioGroup(Form, ['red', 'green']);
    raised := False;
    try
      b := G.Buttons[7];
      if b = nil then ;
    except
      on E: EListError do raised := True;
    end;
    AssertTrue('an out-of-range Buttons[] raises, as LCL''s does', raised);
  finally
    Form.Free;
  end;
end;

procedure TRadioGroupParityTest.ItemFocusEventsAreWiredOntoEveryChild;
var
  Form: TForm;
  G: TTyRadioGroup;
  i: Integer;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeRadioGroup(Form, ['a', 'b', 'c']);
    for i := 0 to G.Count - 1 do
    begin
      AssertTrue(Format('child %d has OnEnter wired', [i]), Assigned(G.Buttons[i].OnEnter));
      AssertTrue(Format('child %d has OnExit wired', [i]), Assigned(G.Buttons[i].OnExit));
    end;
  finally
    Form.Free;
  end;
end;

procedure TRadioGroupParityTest.OnItemEnterCarriesTheButtonAsSender;
var
  Form: TForm;
  G: TTyRadioGroup;
  h: TNotifyEvent;
begin
  { Sender must be the BUTTON, not the group -- the whole point is knowing WHICH option the
    keyboard is on, and a Sender of Self would tell nobody. (Focus itself needs a realised
    handle, which the headless runner never has, so the relay is driven directly.) }
  Form := TForm.CreateNew(nil);
  try
    G := MakeRadioGroup(Form, ['a', 'b']);
    FEnters := 0;
    FExits := 0;
    FLastEnterSender := nil;
    G.OnItemEnter := @HItemEnter;
    G.OnItemExit := @HItemExit;
    h := G.Buttons[1].OnEnter;
    h(G.Buttons[1]);
    AssertEquals('OnItemEnter fired', 1, FEnters);
    AssertSame('with the hosted button as Sender', G.Buttons[1], FLastEnterSender);
    h := G.Buttons[1].OnExit;
    h(G.Buttons[1]);
    AssertEquals('OnItemExit fired', 1, FExits);
  finally
    Form.Free;
  end;
end;

procedure TRadioGroupParityTest.ArrowDownMovesTheSelectionOneRow;
var
  Form: TForm;
  G: TTyRadioGroup;
  k: Word;
  h: TKeyEvent;
begin
  { Before this, arrows did nothing at all in a radio group: the only keyboard route was
    Tab-to-each-item plus Space, which CHANGES the selection on the way past every option. }
  Form := TForm.CreateNew(nil);
  try
    G := MakeRadioGroup(Form, ['a', 'b', 'c']);
    G.ItemIndex := 0;
    h := G.Buttons[0].OnKeyDown;
    AssertTrue('the child''s key event is wired', Assigned(h));
    k := VK_DOWN;
    h(G.Buttons[0], k, []);
    AssertEquals('down moves to the next option', 1, G.ItemIndex);
    AssertEquals('and the key is consumed', 0, k);
    k := VK_UP;
    h(G.Buttons[1], k, []);
    AssertEquals('up moves back', 0, G.ItemIndex);
  finally
    Form.Free;
  end;
end;

procedure TRadioGroupParityTest.ArrowRightHonoursTheColumnLayout;
var
  Form: TForm;
  G: TTyRadioGroup;
  k: Word;
  h: TKeyEvent;
begin
  { The arrow must move to the neighbour the user can SEE, so the step has to read the same
    fill order the layout does. In row-major, "right" is +1; in column-major it is +Rows. }
  Form := TForm.CreateNew(nil);
  try
    G := MakeRadioGroup(Form, ['a', 'b', 'c', 'd']);
    G.Columns := 2;
    h := G.Buttons[0].OnKeyDown;

    G.ColumnLayout := clHorizontalThenVertical;   // 0 1 / 2 3
    G.ItemIndex := 0;
    k := VK_RIGHT;
    h(G.Buttons[0], k, []);
    AssertEquals('row-major: right is the next index', 1, G.ItemIndex);

    G.ColumnLayout := clVerticalThenHorizontal;   // 0 2 / 1 3
    G.ItemIndex := 0;
    k := VK_RIGHT;
    h(G.Buttons[0], k, []);
    AssertEquals('column-major: right skips a whole column', 2, G.ItemIndex);
  finally
    Form.Free;
  end;
end;

procedure TRadioGroupParityTest.ArrowNavigationStepsOverADisabledItem;
var
  Form: TForm;
  G: TTyRadioGroup;
  k: Word;
  h: TKeyEvent;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeRadioGroup(Form, ['a', 'b', 'c']);
    G.Buttons[1].Enabled := False;
    G.ItemIndex := 0;
    h := G.Buttons[0].OnKeyDown;
    k := VK_DOWN;
    h(G.Buttons[0], k, []);
    { Stepped OVER, not stopped ON: a disabled option must not become a wall the keyboard
      cannot get past. }
    AssertEquals('the disabled option is skipped', 2, G.ItemIndex);
  finally
    Form.Free;
  end;
end;

procedure TRadioGroupParityTest.ArrowNavigationStopsAtTheEnds;
var
  Form: TForm;
  G: TTyRadioGroup;
  k: Word;
  h: TKeyEvent;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeRadioGroup(Form, ['a', 'b']);
    G.ItemIndex := 1;
    h := G.Buttons[1].OnKeyDown;
    k := VK_DOWN;
    h(G.Buttons[1], k, []);
    AssertEquals('past the last option the selection stays put', 1, G.ItemIndex);
    G.ItemIndex := 0;
    k := VK_UP;
    h(G.Buttons[0], k, []);
    AssertEquals('and before the first one too', 0, G.ItemIndex);
  finally
    Form.Free;
  end;
end;

procedure TRadioGroupParityTest.AChildsKeyReachesTheGroupsOnKeyDown;
var
  Form: TForm;
  G: TTyRadioGroup;
  k: Word;
  h: TKeyEvent;
begin
  Form := TForm.CreateNew(nil);
  try
    G := MakeRadioGroup(Form, ['a', 'b']);
    FGroupKeys := 0;
    G.OnKeyDown := @HGroupKeyDown;
    h := G.Buttons[0].OnKeyDown;
    k := VK_F5;   // not an arrow: it must reach the group and NOT be eaten by navigation
    h(G.Buttons[0], k, []);
    AssertEquals('a key typed on a child reaches the group', 1, FGroupKeys);
    AssertEquals('a non-arrow key is left alone', VK_F5, k);
  finally
    Form.Free;
  end;
end;

{ -------------------------------------------------- indicator alignment ---- }

procedure TIndicatorSideParityTest.AlignmentIsPublishedWithLclsDefaultOnBoth;
var
  C: TTyCheckBox;
  R: TTyRadioButton;
begin
  AssertTrue('TTyCheckBox publishes Alignment', GetPropInfo(TTyCheckBox, 'Alignment') <> nil);
  AssertTrue('TTyRadioButton too', GetPropInfo(TTyRadioButton, 'Alignment') <> nil);
  C := TTyCheckBox.Create(nil);
  R := TTyRadioButton.Create(nil);
  try
    { taRightJustify, LCL's default -- and note what the word names here: the side the
      CAPTION goes, hence indicator-left. It is emphatically not TTyGroupBox.Alignment,
      which is a TAlignment for the caption band. }
    AssertEquals('checkbox default', Ord(taRightJustify), Ord(C.Alignment));
    AssertEquals('radio default', Ord(taRightJustify), Ord(R.Alignment));
  finally
    R.Free;
    C.Free;
  end;
end;

{ The leftmost column holding accent-blue fill (the checked indicator box). -1 if none. }
function FirstAccentX(ABmp: TBitmap; AW, AH: Integer): Integer;
var
  R: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := -1;
  R := TBGRABitmap.Create(ABmp);
  try
    for x := 0 to AW - 1 do
      for y := 0 to AH - 1 do
      begin
        p := R.GetPixel(x, y);
        if (p.blue > 180) and (p.red < 120) then Exit(x);
      end;
  finally
    R.Free;
  end;
end;

procedure TIndicatorSideParityTest.LeftJustifyMovesTheIndicatorToTheRightEdge;
var
  Ctl: TTyStyleController;
  Form: TForm;
  C: TCheckBoxAccess;
  Bmp: TBitmap;
  xDefault, xFlipped: Integer;
begin
  Ctl := FlatController(
    'TyCheckBox { background: #FFFFFF; color: #101010; border-width: 0px; padding: 0px; }' +
    'TyCheckBox:active { background: #3B82F6; color: #FFFFFF; }');
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    C := TCheckBoxAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := True;   // accent fill makes the indicator findable

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(160, 24);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 160, 24);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 160, 24), 96);
    xDefault := FirstAccentX(Bmp, 160, 24);
    AssertTrue('the indicator was found at the default', xDefault >= 0);
    AssertTrue('and it starts at the left edge', xDefault <= 2);

    C.Alignment := taLeftJustify;
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 160, 24);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 160, 24), 96);
    xFlipped := FirstAccentX(Bmp, 160, 24);
    AssertTrue('the indicator was found flipped', xFlipped >= 0);
    { The load-bearing assertion: the property is READ by the paint. }
    AssertTrue(Format('taLeftJustify must move the indicator right (%d -> %d)',
      [xDefault, xFlipped]), xFlipped > xDefault);
    AssertTrue('and it must reach the right edge', xFlipped >= 160 - 24);
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TIndicatorSideParityTest.DefaultKeepsTheIndicatorOnTheLeft;
var
  R: TTyRadioButton;
begin
  { A cheap regression sentinel next to the pixel test: the default must not drift, because
    every form ever built with this library assumes indicator-left. }
  R := TTyRadioButton.Create(nil);
  try
    AssertEquals('unchanged default', Ord(taRightJustify), Ord(R.Alignment));
  finally
    R.Free;
  end;
end;

{ ------------------------------------------------------ TTyColorButton ----- }

procedure TColorButtonParityTest.HChange(Sender: TObject);
begin Inc(FChange); end;

procedure TColorButtonParityTest.HChanged(Sender: TObject);
begin Inc(FChanged); end;

procedure TColorButtonParityTest.ButtonColorRoundTripsThroughTColor;
var
  B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    AssertTrue('ButtonColor is published', GetPropInfo(TTyColorButton, 'ButtonColor') <> nil);
    { The one line every ported TColorButton user writes. Assigning clRed to SelectedColor
      instead would be read as ARGB and come out a different colour, silently. }
    B.ButtonColor := clRed;
    AssertEquals('reads back as the same TColor', clRed, B.ButtonColor);
    AssertEquals('and the swatch really is red', 255, TyRedOf(B.SelectedColor));
    AssertEquals('with no green', 0, TyGreenOf(B.SelectedColor));
    AssertEquals('and no blue', 0, TyBlueOf(B.SelectedColor));
  finally
    B.Free;
  end;
end;

procedure TColorButtonParityTest.ButtonColorIsPublishedButNotStored;
var
  B: TTyColorButton;
begin
  { Published so a ported .lfm line loads; not stored so our own .lfm does not carry the
    same colour twice under two names. }
  B := TTyColorButton.Create(nil);
  try
    B.ButtonColor := clLime;
    AssertFalse('ButtonColor must not be streamed', IsStoredProp(B, 'ButtonColor'));
    AssertTrue('SelectedColor is the stored one', IsStoredProp(B, 'SelectedColor'));
  finally
    B.Free;
  end;
end;

procedure TColorButtonParityTest.ButtonColorPreservesTheAlpha;
var
  B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    B.SelectedColor := TyRGBA(10, 20, 30, 128);
    B.ButtonColor := clWhite;
    AssertEquals('a TColor carries no alpha, so ours must survive the write',
      128, TyAlphaOf(B.SelectedColor));
  finally
    B.Free;
  end;
end;

procedure TColorButtonParityTest.OnColorChangedFiresAlongsideOnColorChange;
var
  B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    FChange := 0;
    FChanged := 0;
    B.OnColorChange := @HChange;
    B.OnColorChanged := @HChanged;
    B.SelectedColor := TyRGB(1, 2, 3);
    AssertEquals('our own event fires', 1, FChange);
    AssertEquals('LCL''s name fires too', 1, FChanged);
    B.SelectedColor := TyRGB(1, 2, 3);   // no change
    AssertEquals('and neither fires for a no-op write', 1, FChange);
    AssertEquals('neither', 1, FChanged);
  finally
    B.Free;
  end;
end;

procedure TColorButtonParityTest.AlignmentDefaultsToLeftBesideTheSwatch;
var
  B: TTyColorButton;
begin
  B := TTyColorButton.Create(nil);
  try
    { The caption sits in the strip left over beside the swatch, so it starts at that
      strip's edge -- hence a default the base does not have. The constructor and the
      DECLARED default must agree, or the streamer writes the line into every .lfm that
      holds one of these; asserting both halves is what pins that. }
    AssertEquals('the constructor sets taLeftJustify', Ord(taLeftJustify), Ord(B.Alignment));
    AssertEquals('and the redeclared default says the same',
      Ord(taLeftJustify), GetPropInfo(TTyColorButton, 'Alignment')^.Default);
    AssertEquals('while the base still declares taCenter',
      Ord(taCenter), GetPropInfo(TTyButton, 'Alignment')^.Default);
  finally
    B.Free;
  end;
end;

{ -------------------------------------------------------- the containers --- }

procedure TContainerParityTest.GroupBoxPublishesClientSize;
begin
  { ClientWidth/ClientHeight are the real gap: nothing in the library published them, so a
    ported .lfm that pinned a group box's CLIENT size silently lost those lines, and a
    designer user had to add the caption band and the padding by hand. }
  AssertTrue('ClientWidth', GetPropInfo(TTyGroupBox, 'ClientWidth') <> nil);
  AssertTrue('ClientHeight', GetPropInfo(TTyGroupBox, 'ClientHeight') <> nil);
  { AutoSize is asserted here too, but as a REFUTATION rather than a fix: the audit said a
    ty group box could not hug its contents because AutoSize was unpublished. It was
    published all along, on the windowed base, for every control in the library. Kept so
    nobody "fixes" it again by restating the publication. }
  AssertTrue('AutoSize was already published by the base',
    GetPropInfo(TTyGroupBox, 'AutoSize') <> nil);
  AssertTrue('and by that base directly', GetPropInfo(TTyPanel, 'AutoSize') <> nil);
end;

procedure TContainerParityTest.GroupBoxPublicationsReachBothGroupDescendants;
begin
  { A fix that lands on a base and not its descendants is half a fix -- three times this
    pass. Both group classes inherit the frame, so both must inherit the publications. }
  AssertTrue('check group ClientWidth', GetPropInfo(TTyCheckGroup, 'ClientWidth') <> nil);
  AssertTrue('check group ClientHeight', GetPropInfo(TTyCheckGroup, 'ClientHeight') <> nil);
  AssertTrue('radio group ClientWidth', GetPropInfo(TTyRadioGroup, 'ClientWidth') <> nil);
  AssertTrue('radio group ClientHeight', GetPropInfo(TTyRadioGroup, 'ClientHeight') <> nil);
end;

procedure TContainerParityTest.PaintPanelDropsAsASquareSurface;
var
  P: TTyPaintPanel;
begin
  P := TTyPaintPanel.Create(nil);
  try
    { It used to inherit TTyPanel's 185x41 caption-strip shape, so a drawing surface arrived
      as a letterbox in which anything drawn was clipped. Square, like TPaintBox's 105x105. }
    AssertEquals('width', 105, P.Width);
    AssertEquals('height', 105, P.Height);
  finally
    P.Free;
  end;
end;

procedure TContainerParityTest.PaintPanelStillAcceptsChildControls;
var
  P: TTyPaintPanel;
  Kid: TTyButton;
begin
  { THE MEASUREMENT behind the ancestor decision, pinned so it cannot be lost.

    LCL's TPaintBox is a TGraphicControl: no handle, so it is genuinely transparent over
    whatever the parent painted -- and, being a TControl rather than a TWinControl, it has
    no Controls[] at all and CANNOT host children. TTyPaintPanel can, today. Rebasing it on
    TTyGraphicControl to buy the transparency would therefore REMOVE a capability it ships,
    silently breaking every form that dropped a control onto one. That is why the ancestor
    was left alone; if this assertion ever has to be deleted, the trade-off has been made
    deliberately rather than by accident. }
  P := TTyPaintPanel.Create(nil);
  try
    AssertTrue('it is a windowed container', P is TWinControl);
    AssertTrue('and declares itself one', csAcceptsControls in P.ControlStyle);
    Kid := TTyButton.Create(P);
    Kid.Parent := P;
    AssertEquals('a child really parents onto it', 1, P.ControlCount);
  finally
    P.Free;
  end;
end;

procedure TContainerParityTest.SpeedButtonOnGradientParentReconstructsTheGradient;
var
  Ctl: TTyStyleController;
  Form: TForm;
  Panel: TPanelAccess;
  Btn: TSpeedAccess;
  PanelBmp, BtnBmp: TBitmap;
  R: TBGRABitmap;
  pTop, pBottom, bTop, bBottom: TBGRAPixel;
  parentSpread, buttonSpread: Integer;
begin
  { The measurement that drove the fix, kept as the assertion it became.

    TTySpeedButton is windowed where LCL's TSpeedButton is a TGraphicControl, so it cannot
    simply let the parent show through: it reconstructs the parent's backdrop itself, via
    TyFillParentBg. On an IMAGE-backed form that reconstruction has always been exact (the
    real photo slice at the control's offset). On a GRADIENT parent it was not --
    TyResolveParentBg collapsed the whole ramp to one representative colour, so the button
    painted a FLAT patch where the parent varied, and the error at the far end was the
    entire parent spread. Recorded here at the time: parent spread > 200 of 255, button
    spread < 8.

    Now the button gets its own SLICE of the parent's sweep, so the two spreads agree.
    Numbers, not adjectives, in the same units the defect was measured in. }
  { 90deg is the VERTICAL axis for this painter (GradientEndpoints takes dy = sin(angle)),
    so the parent varies down exactly the axis the two sample points walk. }
  Ctl := FlatController(
    'TyPanel { background: linear-gradient(90deg, #000000, #FFFFFF); border-width: 0px; ' +
    'padding: 0px; }' +
    'TySpeedButton { background: rgba(0,0,0,0); border-width: 0px; padding: 0px; }');
  Form := TForm.CreateNew(nil);
  PanelBmp := TBitmap.Create;
  BtnBmp := TBitmap.Create;
  try
    Panel := TPanelAccess.Create(Form);
    Panel.Parent := Form;
    Panel.Controller := Ctl;
    Panel.Caption := '';
    Panel.SetBounds(0, 0, 120, 120);

    Btn := TSpeedAccess.Create(Panel);
    Btn.Parent := Panel;
    Btn.Controller := Ctl;
    Btn.Caption := '';
    Btn.SetBounds(0, 0, 120, 120);   // covering the panel makes the two directly comparable

    PanelBmp.PixelFormat := pf32bit;
    PanelBmp.SetSize(120, 120);
    Panel.RenderTo(PanelBmp.Canvas, Rect(0, 0, 120, 120), 96);

    BtnBmp.PixelFormat := pf32bit;
    BtnBmp.SetSize(120, 120);
    Btn.RenderTo(BtnBmp.Canvas, Rect(0, 0, 120, 120), 96);

    R := TBGRABitmap.Create(PanelBmp);
    try
      pTop := R.GetPixel(60, 4);
      pBottom := R.GetPixel(60, 115);
    finally
      R.Free;
    end;
    R := TBGRABitmap.Create(BtnBmp);
    try
      bTop := R.GetPixel(60, 4);
      bBottom := R.GetPixel(60, 115);
    finally
      R.Free;
    end;

    parentSpread := Abs(Integer(pBottom.green) - Integer(pTop.green));
    buttonSpread := Abs(Integer(bBottom.green) - Integer(bTop.green));

    AssertTrue(Format('the parent really does vary down its height (spread=%d)',
      [parentSpread]), parentSpread > 200);
    AssertTrue(Format('the button sweeps as far as the parent (parent=%d button=%d)',
      [parentSpread, buttonSpread]), Abs(buttonSpread - parentSpread) <= 4);
    { Spread alone would also be satisfied by a REVERSED ramp, so pin both ends by value. }
    AssertTrue(Format('and starts where the parent starts (parent=%d button=%d)',
      [pTop.green, bTop.green]), Abs(Integer(bTop.green) - Integer(pTop.green)) <= 4);
    AssertTrue(Format('and ends where the parent ends (parent=%d button=%d)',
      [pBottom.green, bBottom.green]), Abs(Integer(bBottom.green) - Integer(pBottom.green)) <= 4);
  finally
    BtnBmp.Free;
    PanelBmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TButtonParityTest);
  RegisterTest(TGlyphButtonParityTest);
  RegisterTest(TSpeedButtonParityTest);
  RegisterTest(TCheckGroupParityTest);
  RegisterTest(TRadioGroupParityTest);
  RegisterTest(TIndicatorSideParityTest);
  RegisterTest(TColorButtonParityTest);
  RegisterTest(TContainerParityTest);
end.
