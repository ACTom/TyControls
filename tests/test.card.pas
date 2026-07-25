unit test.card;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Controller, tyControls.Base, tyControls.Card;
type
  TTyCardTest = class(TTestCase)
  private
    FForm: TForm;
    FCard: TTyCard;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // identity / defaults / container-ness
    procedure TestTypeKey;
    procedure TestDefaults;
    procedure TestIsDesignerContainer;
    procedure TestHostsChild;
    // pure band geometry
    procedure TestBandsTileTheClient;
    procedure TestHiddenStripsGiveTheWholeClientToTheBody;
    procedure TestHeaderWinsWhenSpaceIsShort;
    procedure TestActionsTakeOnlyWhatTheHeaderLeft;
    procedure TestBodyNeverInverts;
    procedure TestDegenerateClient;
    procedure TestBandsHonourClientOrigin;
    // child area
    procedure TestContentRectExcludesHeader;
    procedure TestContentRectExcludesActions;
    procedure TestContentRectInsetByThemePadding;
    procedure TestContentRectMatchesAdjustClientRect;
    procedure TestContentRectGrowsWhenHeaderHidden;
    procedure TestChildAreaNeverOverlapsThePaintedStrips;
    // theme metrics / scaling
    procedure TestHeaderHeightFromThemeMetric;
    procedure TestStripHeightsScaleWithDPI;
    // painting
    procedure TestPaintSmoke;
    procedure TestHeaderSeparatorPaintedAtBandBottom;
    procedure TestNoHeaderSeparatorWhenHeaderHidden;
    procedure TestTitleAlignmentMovesTitleInk;
    procedure TestTitleAlignsWithContentRect;
    procedure TestActionsStripTintPaintedAtBottom;
    procedure TestTitleVisibleWhenThemeOmitsHeaderKey;
    procedure TestBorderlessCardKeepsFullBandRadius;
  end;

implementation

type
  TCardAccess = class(TTyCard)
  public
    function StyleTypeKey: string;
    procedure DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallAdjustClientRect(var ARect: TRect);
  end;

function TCardAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TCardAccess.DoRenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TCardAccess.CallAdjustClientRect(var ARect: TRect);
begin
  AdjustClientRect(ARect);
end;

{ A theme with square corners, no card border and known strip metrics, so the tests
  reason about exact pixel rows instead of fighting anti-aliased rounded corners.
  Header separator = pure red, actions tint = pure blue, card surface = white. }
const
  ProbeCss =
    'TyCard { background: #FFFFFF; color: #000000; border-radius: 0px; ' +
    '  border-width: 0px; padding: 10px; font-size: 12px; }' +
    'TyCardHeader { color: #000000; border-color: #FF0000; border-width: 2px; ' +
    '  font-size: 12px; }' +
    'TyCardActions { background: #0000FF; border-color: #FF0000; border-width: 2px; }';

{ TTyCardTest }

procedure TTyCardTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FCard := TTyCard.Create(FForm);
  FCard.Parent := FForm;
  FCard.SetBounds(0, 0, 240, 160);
  // Pin PPI (macOS defaults to 72) so the strip metrics scale 1:1 in the tests.
  FCard.Font.PixelsPerInch := 96;
end;

procedure TTyCardTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyCardTest.TestTypeKey;
begin
  AssertEquals('TyCard', (FCard as ITyStyleable).GetStyleTypeKey);
end;

procedure TTyCardTest.TestDefaults;
begin
  // A card shows its header out of the box (that IS the point of a card) but not the
  // actions rail — an empty rail would be dead chrome on most cards.
  AssertTrue('header shown by default', FCard.ShowHeader);
  AssertFalse('actions hidden by default', FCard.ShowActions);
  AssertEquals('title empty by default', '', FCard.Title);
end;

procedure TTyCardTest.TestIsDesignerContainer;
begin
  // csAcceptsControls makes the IDE designer drop child controls INTO the card body.
  AssertTrue('card is a designer container', csAcceptsControls in FCard.ControlStyle);
end;

procedure TTyCardTest.TestHostsChild;
var
  Child: TButton;
begin
  Child := TButton.Create(FCard);
  Child.Parent := FCard;
  AssertSame('child parent must be the card', FCard, Child.Parent);
  AssertEquals('card must report one child control', 1, FCard.ControlCount);
end;

procedure TTyCardTest.TestBandsTileTheClient;
var
  lay: TTyCardLayout;
begin
  // The three bands must tile the client EXACTLY: no gap (an unpainted seam) and no
  // overlap (a strip eating the body).
  lay := TyCardLayout(Rect(0, 0, 240, 160), 36, 44);
  AssertEquals('header starts at the client top', 0, lay.Header.Top);
  AssertEquals('header is its full height', 36, lay.Header.Bottom);
  AssertEquals('body starts where the header ends', lay.Header.Bottom, lay.Body.Top);
  AssertEquals('actions start where the body ends', lay.Body.Bottom, lay.Actions.Top);
  AssertEquals('actions end at the client bottom', 160, lay.Actions.Bottom);
  AssertEquals('actions are their full height', 44, lay.Actions.Bottom - lay.Actions.Top);
  AssertEquals('body absorbs the remainder', 160 - 36 - 44, lay.Body.Bottom - lay.Body.Top);
  // Every band spans the full width.
  AssertEquals('header spans the width', 240, lay.Header.Right - lay.Header.Left);
  AssertEquals('body spans the width', 240, lay.Body.Right - lay.Body.Left);
  AssertEquals('actions span the width', 240, lay.Actions.Right - lay.Actions.Left);
end;

procedure TTyCardTest.TestHiddenStripsGiveTheWholeClientToTheBody;
var
  lay: TTyCardLayout;
begin
  // 0 height = "hidden": the band collapses to empty and the body takes everything.
  lay := TyCardLayout(Rect(0, 0, 240, 160), 0, 0);
  AssertTrue('header empty', lay.Header.Bottom <= lay.Header.Top);
  AssertTrue('actions empty', lay.Actions.Bottom <= lay.Actions.Top);
  AssertEquals('body top = client top', 0, lay.Body.Top);
  AssertEquals('body bottom = client bottom', 160, lay.Body.Bottom);
end;

procedure TTyCardTest.TestHeaderWinsWhenSpaceIsShort;
var
  lay: TTyCardLayout;
begin
  // A card squeezed shorter than its header: the header clamps to the client and the
  // body/actions collapse — the title survives, which is the whole point of a card.
  lay := TyCardLayout(Rect(0, 0, 240, 20), 36, 44);
  AssertEquals('header clamps to the client height', 20, lay.Header.Bottom - lay.Header.Top);
  AssertEquals('body collapsed to empty', 0, lay.Body.Bottom - lay.Body.Top);
  AssertEquals('actions collapsed to empty', 0, lay.Actions.Bottom - lay.Actions.Top);
end;

procedure TTyCardTest.TestActionsTakeOnlyWhatTheHeaderLeft;
var
  lay: TTyCardLayout;
begin
  // 50px client, 36px header -> only 14px is left for a 44px rail.
  lay := TyCardLayout(Rect(0, 0, 240, 50), 36, 44);
  AssertEquals('header keeps its full height', 36, lay.Header.Bottom - lay.Header.Top);
  AssertEquals('actions get only the leftovers', 14, lay.Actions.Bottom - lay.Actions.Top);
  AssertEquals('body squeezed to nothing', 0, lay.Body.Bottom - lay.Body.Top);
  AssertEquals('bands still tile: header meets body', lay.Header.Bottom, lay.Body.Top);
  AssertEquals('bands still tile: body meets actions', lay.Body.Bottom, lay.Actions.Top);
end;

procedure TTyCardTest.TestBodyNeverInverts;
var
  lay: TTyCardLayout;
begin
  // Absurd strip heights must never produce a negative-height body (which would make
  // AdjustClientRect hand the designer an inverted rect).
  lay := TyCardLayout(Rect(0, 0, 240, 30), 500, 500);
  AssertTrue('body height >= 0', lay.Body.Bottom >= lay.Body.Top);
  AssertTrue('header never overflows the client', lay.Header.Bottom <= 30);
  AssertTrue('actions never overflow the client', lay.Actions.Bottom - lay.Actions.Top <= 30);
end;

procedure TTyCardTest.TestDegenerateClient;
var
  lay: TTyCardLayout;
begin
  // A zero-height and an INVERTED client: no crash, no negative bands.
  lay := TyCardLayout(Rect(0, 0, 240, 0), 36, 44);
  AssertEquals('zero client -> empty body', 0, lay.Body.Bottom - lay.Body.Top);
  lay := TyCardLayout(Rect(0, 100, 240, 40), 36, 44);   // Bottom < Top
  AssertTrue('inverted client -> body not inverted', lay.Body.Bottom >= lay.Body.Top);
  AssertTrue('inverted client -> header not inverted', lay.Header.Bottom >= lay.Header.Top);
  AssertTrue('inverted client -> actions not inverted', lay.Actions.Bottom >= lay.Actions.Top);
end;

procedure TTyCardTest.TestBandsHonourClientOrigin;
var
  lay: TTyCardLayout;
begin
  // The bands are expressed in the SAME space as the rect handed in — an offset client
  // (what AdjustClientRect may pass after ChildSizing) must not be flattened to 0.
  lay := TyCardLayout(Rect(5, 12, 245, 172), 36, 44);
  AssertEquals('header keeps the client left', 5, lay.Header.Left);
  AssertEquals('header starts at the client top', 12, lay.Header.Top);
  AssertEquals('header height unchanged by the offset', 36, lay.Header.Bottom - lay.Header.Top);
  AssertEquals('actions end at the client bottom', 172, lay.Actions.Bottom);
  AssertEquals('body meets the header', 48, lay.Body.Top);
end;

procedure TTyCardTest.TestContentRectExcludesHeader;
var
  Ctl: TTyStyleController;
  C: TTyCard;
  r: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    // padding 10, header 36 (metric default), no actions.
    Ctl.LoadThemeCss('TyCard { padding: 10px; border-width: 0px; }');
    C := TTyCard.Create(FForm);
    C.Parent := FForm;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.SetBounds(0, 0, 240, 160);
    C.ShowHeader := True;
    r := C.ContentRect;
    AssertEquals('content top = header height + padding.Top',
      TyCardHeaderHeight + 10, r.Top);
    AssertEquals('content bottom = client bottom - padding.Bottom', 160 - 10, r.Bottom);
  finally
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestContentRectExcludesActions;
var
  Ctl: TTyStyleController;
  C: TTyCard;
  r: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyCard { padding: 10px; border-width: 0px; }');
    C := TTyCard.Create(FForm);
    C.Parent := FForm;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.SetBounds(0, 0, 240, 160);
    C.ShowHeader := False;
    C.ShowActions := True;
    r := C.ContentRect;
    AssertEquals('no header -> content top is just padding', 10, r.Top);
    AssertEquals('content bottom = client bottom - actions - padding.Bottom',
      160 - TyCardActionsHeight - 10, r.Bottom);
  finally
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestContentRectInsetByThemePadding;
var
  Ctl: TTyStyleController;
  C: TTyCard;
  r: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    // Asymmetric padding proves each edge is taken from its OWN token, not one number.
    Ctl.LoadThemeCss('TyCard { padding: 3px 7px 11px 5px; border-width: 0px; }');
    C := TTyCard.Create(FForm);
    C.Parent := FForm;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.SetBounds(0, 0, 240, 160);
    C.ShowHeader := False;
    r := C.ContentRect;
    // CSS shorthand order is top right bottom left.
    AssertEquals('padding.Top', 3, r.Top);
    AssertEquals('padding.Left', 5, r.Left);
    AssertEquals('padding.Right', 240 - 7, r.Right);
    AssertEquals('padding.Bottom', 160 - 11, r.Bottom);
  finally
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestContentRectMatchesAdjustClientRect;
var
  Acc: TCardAccess;
  r, content: TRect;
begin
  // ContentRect is the ONE definition of the child area: a hand-placed child (which
  // reads ContentRect) and an aligned child (which the LCL lays out via
  // AdjustClientRect) must never drift apart.
  Acc := TCardAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Font.PixelsPerInch := 96;
  try
    Acc.SetBounds(0, 0, 240, 160);
    Acc.ShowHeader := True;
    Acc.ShowActions := True;
    r := Acc.ClientRect;
    Acc.CallAdjustClientRect(r);
    content := Acc.ContentRect;
    AssertEquals('same left', r.Left, content.Left);
    AssertEquals('same top', r.Top, content.Top);
    AssertEquals('same right', r.Right, content.Right);
    AssertEquals('same bottom', r.Bottom, content.Bottom);
  finally
    Acc.Free;
  end;
end;

procedure TTyCardTest.TestContentRectGrowsWhenHeaderHidden;
var
  withHdr, without: TRect;
begin
  FCard.ShowHeader := True;
  withHdr := FCard.ContentRect;
  FCard.ShowHeader := False;
  without := FCard.ContentRect;
  AssertTrue('hiding the header lifts the content top',
    without.Top < withHdr.Top);
  AssertEquals('the body regains exactly the header band',
    TyCardHeaderHeight, withHdr.Top - without.Top);
end;

procedure TTyCardTest.TestChildAreaNeverOverlapsThePaintedStrips;
{ The core container invariant, swept across sizes and both flags: the child area
  AdjustClientRect hands the LCL must never intersect the strips RenderTo paints —
  otherwise a child sits under the header/rail chrome.

  Note this asserts the CONTRACT rather than driving a real alClient child: the LCL's
  alignment machinery only runs against a live window (headless, an alClient child
  keeps its design bounds — the shipped TTyGroupBox behaves identically here), so a
  child-placement assertion would test the runner, not the card. AdjustClientRect IS
  the input LCL aligns from, and cross-checking it against the painted bands catches
  the real risk: the carve and the paint drifting apart. }
var
  Ctl: TTyStyleController;
  C: TTyCard;
  content, hdr, rail: TRect;
  i: Integer;
  hdrOn, railOn: Boolean;
const
  Heights: array[0..3] of Integer = (160, 100, 60, 90);
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyCard { padding: 10px; border-width: 1px; }');
    C := TTyCard.Create(FForm);
    C.Parent := FForm;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    for i := 0 to High(Heights) do
      for hdrOn := False to True do
        for railOn := False to True do
        begin
          C.SetBounds(0, 0, 240, Heights[i]);
          C.ShowHeader := hdrOn;
          C.ShowActions := railOn;
          content := C.ContentRect;
          hdr := C.HeaderRect;
          rail := C.ActionsRect;
          // Never inverted — an inverted rect would make the designer place children wild.
          AssertTrue(Format('h=%d hdr=%s rail=%s: content not inverted',
            [Heights[i], BoolToStr(hdrOn, True), BoolToStr(railOn, True)]),
            (content.Right >= content.Left) and (content.Bottom >= content.Top));
          // Only a NON-empty content area can overlap anything.
          if content.Bottom > content.Top then
          begin
            if hdr.Bottom > hdr.Top then
              AssertTrue(Format('h=%d hdr=%s rail=%s: content clears the header band',
                [Heights[i], BoolToStr(hdrOn, True), BoolToStr(railOn, True)]),
                content.Top >= hdr.Bottom);
            if rail.Bottom > rail.Top then
              AssertTrue(Format('h=%d hdr=%s rail=%s: content clears the actions band',
                [Heights[i], BoolToStr(hdrOn, True), BoolToStr(railOn, True)]),
                content.Bottom <= rail.Top);
          end;
          // The hidden strips must not reserve anything at all.
          if not hdrOn then
            AssertTrue('hidden header reserves no band', hdr.Bottom <= hdr.Top);
          if not railOn then
            AssertTrue('hidden actions reserve no band', rail.Bottom <= rail.Top);
        end;
  finally
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestHeaderHeightFromThemeMetric;
var
  Ctl: TTyStyleController;
  C: TTyCard;
begin
  // The strip heights are THEME metrics, not hard-coded sizes: a skin retunes the
  // card's proportions and the body follows.
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(
      ':root { --card-header-height: 50px; --card-actions-height: 20px; }' +
      'TyCard { padding: 0px; border-width: 0px; }');
    C := TTyCard.Create(FForm);
    C.Parent := FForm;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.SetBounds(0, 0, 240, 160);
    C.ShowHeader := True;
    C.ShowActions := True;
    AssertEquals('header band follows --card-header-height', 50, C.HeaderRect.Bottom);
    AssertEquals('actions band follows --card-actions-height',
      20, C.ActionsRect.Bottom - C.ActionsRect.Top);
    AssertEquals('content top follows the metric too', 50, C.ContentRect.Top);
  finally
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestStripHeightsScaleWithDPI;
var
  Ctl: TTyStyleController;
  C: TTyCard;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss(
      ':root { --card-header-height: 36px; }' +
      'TyCard { padding: 0px; border-width: 0px; }');
    C := TTyCard.Create(FForm);
    C.Parent := FForm;
    C.Controller := Ctl;
    C.SetBounds(0, 0, 240, 300);
    // At 192 ppi the 36 logical-px header is MulDiv(36, 192, 96) = 72 device px.
    C.Font.PixelsPerInch := 192;
    AssertEquals('header height scales with DPI', 72, C.HeaderRect.Bottom);
    AssertEquals('content top scales with it', 72, C.ContentRect.Top);
  finally
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestPaintSmoke;
var
  Acc: TCardAccess;
  Bmp: TBitmap;
begin
  Acc := TCardAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Title := 'Card Title';
  Acc.ShowActions := True;
  Acc.SetBounds(0, 0, 240, 160);
  Acc.Font.PixelsPerInch := 96;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 160);
    Acc.DoRenderTo(Bmp.Canvas, Rect(0, 0, 240, 160), 96);
    AssertTrue('card RenderTo executed without exception', True);
  finally
    Bmp.Free;
  end;
end;

procedure TTyCardTest.TestHeaderSeparatorPaintedAtBandBottom;
{ With a red 2px TyCardHeader border on a white card, the hairline separator must land
  on the LAST rows of the header band (y = 34..35 for a 36px band) and the body just
  below it must stay clean white. }
var
  Ctl: TTyStyleController;
  Acc: TCardAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  onSep, belowSep, aboveSep: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(ProbeCss);
    Acc := TCardAccess.Create(FForm);
    Acc.Parent := FForm;
    Acc.Controller := Ctl;
    Acc.ShowHeader := True;
    Acc.SetBounds(0, 0, 240, 160);
    Acc.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 160);
    Acc.DoRenderTo(Bmp.Canvas, Rect(0, 0, 240, 160), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Sample at x=120 (mid-width, clear of any corner work).
      onSep := Reread.GetPixel(120, TyCardHeaderHeight - 1);   // y=35, last separator row
      AssertTrue('separator row is red-dominant', onSep.red > 150);
      AssertTrue('separator row is not white', onSep.blue < 100);
      // The body immediately under the band is the card surface (white).
      belowSep := Reread.GetPixel(120, TyCardHeaderHeight + 2);
      AssertTrue('body under the separator stays white', belowSep.blue > 200);
      // The header band above the separator has no tint in this theme -> card surface.
      aboveSep := Reread.GetPixel(120, TyCardHeaderHeight div 2);
      AssertTrue('untinted header band shows the card surface', aboveSep.blue > 200);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestNoHeaderSeparatorWhenHeaderHidden;
{ ShowHeader=False must remove the CHROME, not just the text: no separator anywhere in
  the band the header would have occupied. }
var
  Ctl: TTyStyleController;
  Acc: TCardAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  y: Integer;
  px: TBGRAPixel;
  redRows: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(ProbeCss);
    Acc := TCardAccess.Create(FForm);
    Acc.Parent := FForm;
    Acc.Controller := Ctl;
    Acc.ShowHeader := False;
    Acc.SetBounds(0, 0, 240, 160);
    Acc.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 160);
    Acc.DoRenderTo(Bmp.Canvas, Rect(0, 0, 240, 160), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      redRows := 0;
      for y := 0 to TyCardHeaderHeight + 4 do
      begin
        px := Reread.GetPixel(120, y);
        if (px.red > 150) and (px.blue < 100) then Inc(redRows);
      end;
      AssertEquals('no separator rows painted with the header hidden', 0, redRows);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestTitleAlignmentMovesTitleInk;
{ TitleAlignment must actually move the drawn title, not just round-trip: compare the
  ink centroid inside the header band for left vs right alignment. }
  function InkCentroidX(A: TAlignment): Double;
  var
    Ctl: TTyStyleController;
    Acc: TCardAccess;
    bmp: TBitmap;
    reread: TBGRABitmap;
    x, y, n: Integer;
    sx: Double;
    px: TBGRAPixel;
  begin
    Ctl := TTyStyleController.Create(nil);
    bmp := TBitmap.Create;
    try
      Ctl.LoadThemeCss(ProbeCss);
      Acc := TCardAccess.Create(nil);
      try
        Acc.Controller := Ctl;
        Acc.Title := 'Hi';
        Acc.TitleAlignment := A;
        Acc.ShowHeader := True;
        Acc.Font.PixelsPerInch := 96;
        Acc.SetBounds(0, 0, 240, 160);
        bmp.PixelFormat := pf32bit;
        bmp.SetSize(240, 160);
        Acc.DoRenderTo(bmp.Canvas, Rect(0, 0, 240, 160), 96);
        reread := TBGRABitmap.Create(bmp);
        try
          sx := 0; n := 0;
          // Scan the header band ABOVE the separator so only title ink is counted.
          for x := 0 to 239 do
            for y := 0 to TyCardHeaderHeight - 4 do
            begin
              px := reread.GetPixel(x, y);
              if (px.red < 160) and (px.green < 160) and (px.blue < 160) then
              begin
                sx := sx + x;
                Inc(n);
              end;
            end;
          if n = 0 then Result := -1 else Result := sx / n;
        finally
          reread.Free;
        end;
      finally
        Acc.Free;
      end;
    finally
      bmp.Free;
      Ctl.Free;
    end;
  end;
var
  cl, cr: Double;
begin
  cl := InkCentroidX(taLeftJustify);
  cr := InkCentroidX(taRightJustify);
  AssertTrue('left-aligned title ink present', cl > 0);
  AssertTrue('right-aligned title ink present', cr > 0);
  AssertTrue('right-aligned title sits further right', cr > cl + 100);
end;

procedure TTyCardTest.TestTitleAlignsWithContentRect;
{ The card's promise (see ContentRect's doc): a left-aligned title lines up with the body
  content, i.e. its ink starts at ContentRect.Left plus only the glyph's small left
  bearing — NOT a whole extra padding. Guards against the title path double-insetting
  (once for the header band, again for the title) while hand-placed children, which read
  ContentRect, get a single inset. Rendered at 96 PPI with a border-less probe theme so
  the numbers are exact. }
var
  Ctl: TTyStyleController;
  Acc: TCardAccess;
  bmp: TBitmap;
  reread: TBGRABitmap;
  x, y, inkLeft: Integer;
  hasInk: Boolean;
  px: TBGRAPixel;
  content: TRect;
begin
  Ctl := TTyStyleController.Create(nil);
  bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(ProbeCss);   // card border 0, padding 10, black title on a white card
    Acc := TCardAccess.Create(nil);
    try
      Acc.Controller := Ctl;
      Acc.Title := 'HH';          // near-zero left side bearing, so ink ~ textRect.Left
      Acc.TitleAlignment := taLeftJustify;
      Acc.ShowHeader := True;
      Acc.Font.PixelsPerInch := 96;
      Acc.SetBounds(0, 0, 240, 160);
      content := Acc.ContentRect;
      bmp.PixelFormat := pf32bit;
      bmp.SetSize(240, 160);
      bmp.Canvas.Brush.Color := clWhite;
      bmp.Canvas.FillRect(0, 0, 240, 160);
      Acc.DoRenderTo(bmp.Canvas, Rect(0, 0, 240, 160), 96);
      reread := TBGRABitmap.Create(bmp);
      try
        inkLeft := 240;
        for x := 0 to 239 do
        begin
          hasInk := False;
          for y := 0 to TyCardHeaderHeight - 4 do   // header band, above the separator
          begin
            px := reread.GetPixel(x, y);
            if (px.red < 160) and (px.green < 160) and (px.blue < 160) then
            begin hasInk := True; Break; end;
          end;
          if hasInk then begin inkLeft := x; Break; end;
        end;
      finally
        reread.Free;
      end;
      AssertTrue('title drew some ink', inkLeft < 240);
      // Single inset: ink at ContentRect.Left (+ tiny bearing). A double inset would land
      // near 2*padding = 20, well outside this window.
      AssertTrue(Format('title ink left %d lines up with ContentRect.Left %d (not double-inset)',
        [inkLeft, content.Left]),
        (inkLeft >= content.Left - 1) and (inkLeft <= content.Left + 5));
    finally
      Acc.Free;
    end;
  finally
    bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestActionsStripTintPaintedAtBottom;
{ The actions rail carries its own themed tint (blue here) and it must occupy exactly
  the bottom band — the body above it stays the card surface. }
var
  Ctl: TTyStyleController;
  Acc: TCardAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  inRail, aboveRail: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(ProbeCss);
    Acc := TCardAccess.Create(FForm);
    Acc.Parent := FForm;
    Acc.Controller := Ctl;
    Acc.ShowHeader := False;
    Acc.ShowActions := True;
    Acc.SetBounds(0, 0, 240, 160);
    Acc.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 160);
    Acc.DoRenderTo(Bmp.Canvas, Rect(0, 0, 240, 160), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Well inside the rail (below its top separator), mid-width.
      inRail := Reread.GetPixel(120, 160 - (TyCardActionsHeight div 2));
      AssertTrue('actions rail is blue-dominant', inRail.blue > 150);
      AssertTrue('actions rail is not the white surface', inRail.red < 100);
      // Just above the rail band the body is still the card surface.
      aboveRail := Reread.GetPixel(120, 160 - TyCardActionsHeight - 5);
      AssertTrue('body above the rail stays white', aboveRail.red > 200);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestTitleVisibleWhenThemeOmitsHeaderKey;
{ A skin that styles TyCard but never defines TyCardHeader resolves an EMPTY style set
  for the header — whose colour is $00000000, i.e. a fully TRANSPARENT title. The card
  must fall back to its own text colour so a partial skin degrades to a readable card
  rather than a silently blank strip. Counts dark ink in the header band. }
var
  Ctl: TTyStyleController;
  Acc: TCardAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  x, y, ink: Integer;
  px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    // NOTE: no TyCardHeader rule at all — that is the whole point of this test.
    Ctl.LoadThemeCss(
      'TyCard { background: #FFFFFF; color: #000000; border-width: 0px; ' +
      '  border-radius: 0px; padding: 10px; font-size: 12px; }');
    Acc := TCardAccess.Create(FForm);
    Acc.Parent := FForm;
    Acc.Controller := Ctl;
    Acc.ShowHeader := True;
    Acc.Title := 'Visible';
    Acc.SetBounds(0, 0, 240, 160);
    Acc.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 160);
    Acc.DoRenderTo(Bmp.Canvas, Rect(0, 0, 240, 160), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      ink := 0;
      for x := 0 to 239 do
        for y := 0 to TyCardHeaderHeight - 1 do
        begin
          px := Reread.GetPixel(x, y);
          if (px.red < 128) and (px.green < 128) and (px.blue < 128) then Inc(ink);
        end;
      AssertTrue('title ink is drawn even with no TyCardHeader rule (not invisible)',
        ink > 20);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

procedure TTyCardTest.TestBorderlessCardKeepsFullBandRadius;
{ Adversarial-review finding (CONFIRMED): the header band's outer corner radii were shrunk by
  the RAW border-width token, even when the border was present-but-not-drawn (a width with no
  colour). With no stroke the band fills flush to the card edge, so its corner must keep the
  card's FULL radius; shrinking it under-rounds, and the header tint spills past where the
  card's own rounded corner curves away. Here: radius 12, border-width 4, but NO border colour
  -> the border is not drawn (bw=0), so the header corner must stay radius 12, not 12-4=8.

  Sample the top-left corner at (3,3): it lies OUTSIDE a radius-12 arc but INSIDE a radius-8
  one. Full radius -> the corner is unpainted (white pre-fill shows). Under-rounded -> the
  blue header tint reaches (3,3). The red channel separates them cleanly (white 255 vs blue 59). }
var
  Ctl: TTyStyleController;
  Acc: TCardAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  corner: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyCard { background: #FFFFFF; color: #000000; border-radius: 12px; ' +
      '  border-width: 4px; padding: 8px; font-size: 12px; }' +
      'TyCardHeader { background: #3B82F6; color: #000000; font-size: 12px; }');
    Acc := TCardAccess.Create(FForm);
    Acc.Parent := FForm;
    Acc.Controller := Ctl;
    Acc.ShowHeader := True;
    Acc.SetBounds(0, 0, 240, 160);
    Acc.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 160);
    Acc.DoRenderTo(Bmp.Canvas, Rect(0, 0, 240, 160), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // (3,3) lies OUTSIDE a radius-12 arc but INSIDE a radius-8 one. Full radius (the fix) ->
      // the header tint stops short of the corner, so (3,3) is NOT blue. Under-rounded (the
      // bug) -> the blue tint reaches (3,3). Test "is it the header blue", not "is it white":
      // the unpainted corner is a transparent (alpha-0) region GDI leaves black, so a
      // white-vs-black check would be unreliable, but "not blue" holds either way.
      corner := Reread.GetPixel(3, 3);
      AssertFalse(Format('border-less card keeps its full corner radius: the header tint must '
        + 'not spill into the corner (RGB at (3,3)=%d,%d,%d)',
        [corner.red, corner.green, corner.blue]),
        (corner.blue > 120) and (corner.blue > corner.red + 40));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyCardTest);
end.
