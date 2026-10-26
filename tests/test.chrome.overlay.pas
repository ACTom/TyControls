unit test.chrome.overlay;
{ Pilot: a container's chrome stays whole on top of its children.

  A child placed on a container's frame or across one of its separators used to cut the
  line: a windowed child owns its pixels, so the container cannot paint there, and a graphic
  child is painted after the container. A container that is an ITyChromeHost (the pilot is
  TTyCard) now hands out its chrome -- the frame, the focus ring, the separators, and its
  parent's background in the corners outside its shape -- and:

    * a TTy windowed child paints every ancestor's chrome that passes over it, last;
    * the host paints its chrome again over its graphic children that reach into it;
    * when the chrome changes, or a child moves on or off it, the children on it repaint.

  A child wholly inside the host's ChromeFreeRect is untouched, and one that declares
  --over-parent-chrome in its StyleOverride opts out.

  The child's own render (RenderTo) plus the overlay step is what is checked here; the
  overlay is the same call the paint message makes. Colours tell the parts apart: the card's
  frame is red, its header separator green, the children blue. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, Controls, Forms, ComCtrls, LCLType, LMessages, fpcunit,
  testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  tyControls.Card, tyControls.Button, tyControls.Panel, tyControls.TyLabel, tyControls.GroupBox,
  tyControls.PageControl, tyControls.TabSheet, tyControls.ToolBar;

type
  TOvlButton = class(TTyButton)
  public
    Invalidations: Integer;
    procedure Invalidate; override;
    function Render: TBGRABitmap;   // its own render, then the ancestors' chrome over it
    function RenderOwn: TBGRABitmap;
  end;

  { A strip that paints its parent's frame over itself, as an embedded scroll bar does. }
  TOvlStrip = class(TOvlButton)
  protected
    function PaintsParentFrame: Boolean; override;
  end;

  TOvlCard = class(TTyCard)
  public
    procedure XRender(ACanvas: TCanvas);
    procedure XChromeChanged;
  end;

  TOvlGroupBox = class(TTyGroupBox)
  public
    procedure XChromeChanged;
  end;

  TOvlSheet = class(TTyTabSheet)
  public
    function Render: TBGRABitmap;
    function RenderOwn: TBGRABitmap;
  end;

  TOvlLabel = class(TTyLabel)
  public
    procedure XRender(ACanvas: TCanvas);
  end;

  { A form, a controller, children painted blue and the colour tests -- what both suites
    stand on. Not registered. }
  TChromeTestBase = class(TTestCase)
  protected
    FCtl: TTyStyleController;
    FForm: TForm;
    function AddButton(AParent: TWinControl; ALeft, ATop, AWidth, AHeight: Integer;
      const AExtraCss: string = ''): TOvlButton;
    function IsRed(const P: TBGRAPixel): Boolean;
    function IsGreen(const P: TBGRAPixel): Boolean;
    function IsBlue(const P: TBGRAPixel): Boolean;
    function Same(A, B: TBGRABitmap): Boolean;
    procedure SetUp; override;
    procedure TearDown; override;
  end;

  TChromeOverlayTest = class(TChromeTestBase)
  private
    FCard: TOvlCard;
  protected
    procedure SetUp; override;
  published
    procedure TestTheFrameIsDrawnOverAChildOnIt;
    procedure TestAChildInsideTheContentIsUntouched;
    procedure TestTheSeparatorIsDrawnOverAChildOnIt;
    procedure TestTheSeparatorStopsAtTheFrame;
    procedure TestTheCornerOutsideTheShapeShowsTheParent;
    procedure TestANestedChildGetsTheOuterFrame;
    procedure TestANestedChildGetsTheSeparatorWhereItIs;
    procedure TestAGraphicChildIsCoveredToo;
    procedure TestAChildCanOptOut;
    procedure TestTheSwitchTurnsItOff;
    procedure TestAChromeChangeRepaintsTheChildrenOnIt;
    procedure TestMovingAChildOntoTheFrameRepaintsIt;
    procedure TestTheChildsPaintMessageDrawsIt;
    procedure TestTheCachedLayerDrawsTheSamePixels;
    procedure TestTheCacheFollowsAChange;
    procedure TestTheCacheGoesWithItsHost;
    procedure TestSkippingCornersStillFillsACorner;
    procedure TestAChildShowsTheFrameTheCardShows;
    procedure TestAChangeAndBackBeforeTheCardPaints;
    procedure TestAChildFollowsTheFrameWhenTheCardResizes;
    procedure TestAFrameThatMovesOffAChildRepaintsIt;
    procedure TestTheHostsPaintMessageChecksItsChrome;
    procedure TestAChildThatComesBackGetsTheFrameAsItIsNow;
  end;

  { The other containers: each one that people put children into keeps its chrome on top. }
  TChromeHostsTest = class(TChromeTestBase)
  private
    function AddPanel(AParent: TWinControl; ALeft, ATop, AWidth, AHeight: Integer;
      const ACss: string): TTyPanel;
  published
    procedure TestAPanelKeepsItsFrameOverAChildFlushInIt;
    procedure TestAPanelsKeptLayerMatchesAFreshOne;
    procedure TestAPanelWithoutABorderLeavesItsChildAlone;
    procedure TestAStripThatDrawsItsHostsFrameIsLeftToIt;
    procedure TestAGroupBoxKeepsItsCaptionOverAChild;
    procedure TestAGroupBoxsKeptLayerMatchesAFreshOne;
    procedure TestTheGroupBoxCaptionIsNotFreeGround;
    procedure TestANewCaptionRepaintsTheChildUnderIt;
    procedure TestAPageGetsThePageControlsFrame;
    procedure TestASideBandKeepsTheFrameOnThePage;
    procedure TestAPageControlsKeptLayerMatchesAFreshOne;
    procedure TestATallToolKeepsTheBarsHairlineOverIt;
    procedure TestABarsLayerIsItsLineAndNothingElse;
  end;

implementation

const
  BLUE_CSS = 'background: #0000ff; border-width: 0; border-radius: 0; ';

{ TOvlButton }

procedure TOvlButton.Invalidate;
begin
  Inc(Invalidations);
  inherited Invalidate;
end;

function TOvlButton.RenderOwn: TBGRABitmap;
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(Width, Height);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, Width, Height);
    RenderTo(b.Canvas, Rect(0, 0, Width, Height), 96);
    Result := TBGRABitmap.Create(b);
  finally
    b.Free;
  end;
end;

function TOvlButton.Render: TBGRABitmap;
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(Width, Height);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, Width, Height);
    RenderTo(b.Canvas, Rect(0, 0, Width, Height), 96);
    TyPaintAncestorChrome(Self, b.Canvas, 96);
    Result := TBGRABitmap.Create(b);
  finally
    b.Free;
  end;
end;

{ TOvlStrip }

function TOvlStrip.PaintsParentFrame: Boolean;
begin
  Result := True;
end;

{ TOvlCard }

procedure TOvlCard.XRender(ACanvas: TCanvas);
begin
  RenderTo(ACanvas, Rect(0, 0, Width, Height), 96);
end;

procedure TOvlCard.XChromeChanged;
begin
  CheckChromeChanged;
end;

{ TOvlGroupBox }

procedure TOvlGroupBox.XChromeChanged;
begin
  CheckChromeChanged;
end;

{ TOvlSheet }

function TOvlSheet.RenderOwn: TBGRABitmap;
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(Width, Height);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, Width, Height);
    RenderTo(b.Canvas, Rect(0, 0, Width, Height), 96);
    Result := TBGRABitmap.Create(b);
  finally
    b.Free;
  end;
end;

function TOvlSheet.Render: TBGRABitmap;
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(Width, Height);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, Width, Height);
    RenderTo(b.Canvas, Rect(0, 0, Width, Height), 96);
    TyPaintAncestorChrome(Self, b.Canvas, 96);
    Result := TBGRABitmap.Create(b);
  finally
    b.Free;
  end;
end;

{ TOvlLabel }

procedure TOvlLabel.XRender(ACanvas: TCanvas);
begin
  RenderTo(ACanvas, BoundsRect, 96);
end;

{ TChromeOverlayTest }

procedure TChromeTestBase.SetUp;
begin
  TyChromeOverlayEnabled := True;
  TyChromeMode := 2;
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
end;

procedure TChromeTestBase.TearDown;
begin
  TyChromeOverlayEnabled := True;
  TyChromeMode := 2;
  FForm.Free;
  FCtl.Free;
end;

procedure TChromeOverlayTest.SetUp;
begin
  inherited SetUp;
  FCtl.StyleOverride := 'TyCardHeader { border-color: #00ff00; border-width: 1px; }';
  FCard := TOvlCard.Create(FForm);
  FCard.Controller := FCtl;
  FCard.Font.PixelsPerInch := 96;
  FCard.SetBounds(10, 10, 220, 170);
  FCard.Title := 'Card';
  FCard.StyleOverride := 'border-color: #ff0000; border-width: 2px; border-radius: 8px;';
  FCard.Parent := FForm;
end;

function TChromeTestBase.AddButton(AParent: TWinControl; ALeft, ATop, AWidth,
  AHeight: Integer; const AExtraCss: string): TOvlButton;
begin
  Result := TOvlButton.Create(FForm);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Caption := '';
  Result.StyleOverride := BLUE_CSS + AExtraCss;
  Result.SetBounds(ALeft, ATop, AWidth, AHeight);
  Result.Parent := AParent;
end;

function TChromeTestBase.IsRed(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red > 200) and (P.green < 80) and (P.blue < 80);
end;

function TChromeTestBase.IsGreen(const P: TBGRAPixel): Boolean;
begin
  Result := (P.green > 200) and (P.red < 80) and (P.blue < 80);
end;

function TChromeTestBase.IsBlue(const P: TBGRAPixel): Boolean;
begin
  Result := (P.blue > 200) and (P.red < 80) and (P.green < 80);
end;

function TChromeTestBase.Same(A, B: TBGRABitmap): Boolean;
var
  x, y: Integer;
begin
  Result := (A.Width = B.Width) and (A.Height = B.Height);
  if not Result then Exit;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if A.GetPixel(x, y) <> B.GetPixel(x, y) then Exit(False);
end;

procedure TChromeOverlayTest.TestTheFrameIsDrawnOverAChildOnIt;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
begin
  b := AddButton(FCard, 0, 70, 60, 24);
  bmp := b.RenderOwn;
  try
    AssertTrue('precondition: the button covers the frame', IsBlue(bmp.GetPixel(0, 12)));
  finally
    bmp.Free;
  end;
  bmp := b.Render;
  try
    { a 2px frame stroked on the edge: its middle column is all frame, the outer one shares
      its pixel with what is outside the card's shape -- never with the button }
    AssertTrue('the card''s frame, drawn over the button', IsRed(bmp.GetPixel(1, 12)));
    AssertFalse('the outer column is not the button''s', IsBlue(bmp.GetPixel(0, 12)));
    AssertTrue('and only the frame: inside it the button is itself', IsBlue(bmp.GetPixel(10, 12)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestAChildInsideTheContentIsUntouched;
var
  b: TOvlButton;
  r: TRect;
  own, over: TBGRABitmap;
begin
  r := FCard.ContentRect;
  b := AddButton(FCard, r.Left + 8, r.Top + 8, 60, 24);
  own := b.RenderOwn;
  over := b.Render;
  try
    AssertTrue('a child wholly in the content gets nothing drawn over it', Same(own, over));
  finally
    own.Free;
    over.Free;
  end;
end;

procedure TChromeOverlayTest.TestTheSeparatorIsDrawnOverAChildOnIt;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
  sepY: Integer;
begin
  sepY := FCard.HeaderRect.Bottom - 1;   { the header's hairline: its last row }
  b := AddButton(FCard, 40, sepY - 9, 60, 20);
  bmp := b.Render;
  try
    AssertTrue('the header separator, across the button', IsGreen(bmp.GetPixel(20, 9)));
    AssertTrue('above it the button is itself', IsBlue(bmp.GetPixel(20, 4)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestTheSeparatorStopsAtTheFrame;
var
  b: TBitmap;
  bmp: TBGRABitmap;
  sepY: Integer;
begin
  { the hairline runs between the frame's two sides, not over them -- in the card's own paint
    and so in the layer a child gets }
  sepY := FCard.HeaderRect.Bottom - 1;
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(FCard.Width, FCard.Height);
    FCard.XRender(b.Canvas);
    bmp := TBGRABitmap.Create(b);
    try
      AssertTrue('precondition: the separator', IsGreen(bmp.GetPixel(FCard.Width div 2, sepY)));
      AssertTrue('the frame on the left, on the separator''s row', IsRed(bmp.GetPixel(1, sepY)));
      AssertTrue('and on the right', IsRed(bmp.GetPixel(FCard.Width - 2, sepY)));
    finally
      bmp.Free;
    end;
  finally
    b.Free;
  end;
end;

procedure TChromeOverlayTest.TestTheCornerOutsideTheShapeShowsTheParent;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
  pc: TTyColor;
  want, got: TBGRAPixel;
begin
  AssertTrue('precondition: the card has a parent colour', TyResolveParentBg(FCard, pc));
  b := AddButton(FCard, 0, 0, 40, 30);
  bmp := b.Render;
  try
    want := TyColorToBGRA(pc);
    got := bmp.GetPixel(0, 0);
    AssertEquals('outside the rounded corner: what is behind the card (red)', want.red, got.red);
    AssertEquals('(green)', want.green, got.green);
    AssertEquals('(blue)', want.blue, got.blue);
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestANestedChildGetsTheOuterFrame;
var
  p: TTyPanel;
  b: TOvlButton;
  bmp: TBGRABitmap;
begin
  p := TTyPanel.Create(FForm);
  p.Controller := FCtl;
  p.Font.PixelsPerInch := 96;
  p.StyleOverride := 'background: #ffff00; border-width: 0; border-radius: 0;';
  p.SetBounds(0, 70, 100, 60);
  p.Parent := FCard;
  b := AddButton(p, 0, 10, 40, 20);
  bmp := b.Render;
  try
    AssertTrue('the card''s frame passes over the panel and so over its button',
      IsRed(bmp.GetPixel(1, 10)));
    AssertTrue('inside it the button is itself', IsBlue(bmp.GetPixel(10, 10)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestANestedChildGetsTheSeparatorWhereItIs;
var
  p: TTyPanel;
  b: TOvlButton;
  bmp: TBGRABitmap;
  sepY, y: Integer;
begin
  { offsets that are not 0, so the separator lands on the button only where the panel's and
    the button's own positions put it }
  sepY := FCard.HeaderRect.Bottom - 1;
  p := TTyPanel.Create(FForm);
  p.Controller := FCtl;
  p.Font.PixelsPerInch := 96;
  p.StyleOverride := 'background: #ffff00; border-width: 0; border-radius: 0;';
  p.SetBounds(40, sepY - 14, 120, 40);
  p.Parent := FCard;
  b := AddButton(p, 10, 5, 60, 20);
  y := sepY - (sepY - 14) - 5;   { the separator's row, in the button }
  bmp := b.Render;
  try
    AssertTrue('the separator, on the row it crosses', IsGreen(bmp.GetPixel(20, y)));
    AssertTrue('the row above is the button', IsBlue(bmp.GetPixel(20, y - 3)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestAGraphicChildIsCoveredToo;
var
  l: TOvlLabel;
  b: TBitmap;
  bmp: TBGRABitmap;
begin
  l := TOvlLabel.Create(FForm);
  l.Controller := FCtl;
  l.Font.PixelsPerInch := 96;
  l.AutoSize := False;
  l.Transparent := False;   { a label paints its ground only when opaque }
  l.Caption := '';
  l.StyleOverride := BLUE_CSS;
  l.SetBounds(0, 110, 80, 20);
  l.Parent := FCard;
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(FCard.Width, FCard.Height);
    FCard.XRender(b.Canvas);
    l.XRender(b.Canvas);
    bmp := TBGRABitmap.Create(b);
    try
      AssertTrue('precondition: the label covers the frame', IsBlue(bmp.GetPixel(0, 120)));
    finally
      bmp.Free;
    end;
    TyPaintChromeOverGraphicChildren(FCard, b.Canvas, 96);
    bmp := TBGRABitmap.Create(b);
    try
      AssertTrue('the frame, over the label', IsRed(bmp.GetPixel(1, 120)));
      AssertTrue('inside it the label is itself', IsBlue(bmp.GetPixel(20, 120)));
    finally
      bmp.Free;
    end;
  finally
    b.Free;
  end;
end;

procedure TChromeOverlayTest.TestAChildCanOptOut;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
begin
  b := AddButton(FCard, 0, 70, 60, 24, '--over-parent-chrome: 1;');
  bmp := b.Render;
  try
    AssertTrue('a child that asks to stay on top does', IsBlue(bmp.GetPixel(0, 12)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestTheSwitchTurnsItOff;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
begin
  b := AddButton(FCard, 0, 70, 60, 24);
  TyChromeOverlayEnabled := False;
  bmp := b.Render;
  try
    AssertTrue('off: as before the pilot', IsBlue(bmp.GetPixel(0, 12)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestAChromeChangeRepaintsTheChildrenOnIt;
var
  onIt, inside: TOvlButton;
  r: TRect;
begin
  r := FCard.ContentRect;
  onIt := AddButton(FCard, 0, 70, 60, 24);
  inside := AddButton(FCard, r.Left + 8, r.Top + 8, 40, 20);
  FCard.XChromeChanged;   { the first paint: whatever was there before is stale }
  onIt.Invalidations := 0;
  inside.Invalidations := 0;
  FCard.XChromeChanged;
  AssertEquals('nothing changed: nothing repaints', 0, onIt.Invalidations);
  FCard.StyleOverride := 'border-color: #800000; border-width: 2px; border-radius: 8px;';
  FCard.XChromeChanged;
  AssertTrue('the frame changed: the child on it repaints', onIt.Invalidations > 0);
  AssertEquals('the one inside does not', 0, inside.Invalidations);
end;

procedure TChromeOverlayTest.TestMovingAChildOntoTheFrameRepaintsIt;
var
  b: TOvlButton;
  r: TRect;
  quiet, onto: Integer;
begin
  r := FCard.ContentRect;
  b := AddButton(FCard, r.Left + 8, r.Top + 8, 40, 20);
  b.Invalidations := 0;
  b.SetBounds(r.Left + 12, r.Top + 8, 40, 20);
  quiet := b.Invalidations;
  b.Invalidations := 0;
  b.SetBounds(0, r.Top + 8, 40, 20);
  onto := b.Invalidations;
  AssertTrue(Format('moving onto the frame repaints it (%d) where a move inside does not (%d)',
    [onto, quiet]), onto > quiet);
end;

procedure TChromeOverlayTest.TestTheCachedLayerDrawsTheSamePixels;
var
  kids: array[0..2] of TOvlButton;
  i, pass: Integer;
  a, b: TBGRABitmap;
begin
  kids[0] := AddButton(FCard, 0, 70, 60, 24);                          { the frame }
  kids[1] := AddButton(FCard, 0, 0, 40, 30);                           { a corner }
  kids[2] := AddButton(FCard, 40, FCard.HeaderRect.Bottom - 10, 60, 20); { the separator }
  for pass := 0 to 1 do
  begin
    if pass = 1 then   { a see-through card: its layer is kept with the opacity in it }
      FCard.StyleOverride := 'border-color: #ff0000; border-width: 2px; border-radius: 8px;'
        + ' opacity: 0.5;';
    for i := 0 to High(kids) do
    begin
      TyChromeMode := 0;
      a := kids[i].Render;
      TyChromeMode := 2;
      b := kids[i].Render;
      try
        AssertTrue(Format('pass %d, child %d: the kept layer gives what drawing it afresh gives',
          [pass, i]), Same(a, b));
      finally
        a.Free;
        b.Free;
      end;
    end;
  end;
end;

procedure TChromeOverlayTest.TestTheCacheFollowsAChange;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
  p: TBGRAPixel;
begin
  b := AddButton(FCard, 0, 70, 60, 24);
  bmp := b.Render;
  bmp.Free;
  FCard.StyleOverride := 'border-color: #ff00ff; border-width: 2px; border-radius: 8px;';
  bmp := b.Render;
  try
    p := bmp.GetPixel(1, 12);
    AssertTrue(Format('the new frame colour, not the kept old one (%d,%d,%d)',
      [p.red, p.green, p.blue]), (p.red > 200) and (p.blue > 200) and (p.green < 80));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestTheCacheGoesWithItsHost;
var
  before: Int64;
  b: TOvlButton;
  bmp: TBGRABitmap;
begin
  before := TyChromeStats.CacheBytes;
  b := AddButton(FCard, 0, 70, 60, 24);
  bmp := b.Render;
  bmp.Free;
  AssertTrue('the card keeps its layer', TyChromeStats.CacheBytes > before);
  FreeAndNil(FForm);   { the card with it }
  AssertEquals('and lets it go with itself', before, TyChromeStats.CacheBytes);
end;

procedure TChromeOverlayTest.TestSkippingCornersStillFillsACorner;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
  pc: TTyColor;
  want: TBGRAPixel;
begin
  TyChromeMode := 1;
  AssertTrue('precondition: the card has a parent colour', TyResolveParentBg(FCard, pc));
  b := AddButton(FCard, 0, 0, 40, 30);
  bmp := b.Render;
  try
    want := TyColorToBGRA(pc);
    AssertEquals('a band on a corner still gets its parent background', want.red,
      bmp.GetPixel(0, 0).red);
    AssertEquals(want.blue, bmp.GetPixel(0, 0).blue);
  finally
    bmp.Free;
  end;
end;

{ The card takes its chrome once each time it paints, and the bands over its children read
  that instead of asking again: a child drawn between two of the card's paints shows the
  frame the card is showing. }
procedure TChromeOverlayTest.TestAChildShowsTheFrameTheCardShows;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
  p: TBGRAPixel;
begin
  b := AddButton(FCard, 0, 70, 60, 24);
  FCard.XChromeChanged;   { the card paints: red }
  bmp := b.Render;
  bmp.Free;
  FCard.StyleOverride := 'border-color: #ff00ff; border-width: 2px; border-radius: 8px;';
  bmp := b.Render;
  try
    AssertTrue('until the card paints again, the frame it is showing',
      IsRed(bmp.GetPixel(1, 12)));
  finally
    bmp.Free;
  end;
  FCard.XChromeChanged;   { the card paints: magenta }
  bmp := b.Render;
  try
    p := bmp.GetPixel(1, 12);
    AssertTrue(Format('then the new one (%d,%d,%d)', [p.red, p.green, p.blue]),
      (p.red > 200) and (p.blue > 200) and (p.green < 80));
  finally
    bmp.Free;
  end;
end;

{ A layer is drawn from the chrome as it is now and kept under that: a change made and taken
  back before the card paints leaves nothing of itself behind. }
procedure TChromeOverlayTest.TestAChangeAndBackBeforeTheCardPaints;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
  p: TBGRAPixel;
begin
  b := AddButton(FCard, 0, 70, 60, 24);
  FCard.XChromeChanged;   { the card paints: red }
  FCard.StyleOverride := 'border-color: #ff00ff; border-width: 2px; border-radius: 8px;';
  bmp := b.Render;        { drawn before the card paints the change }
  try
    p := bmp.GetPixel(1, 12);
    AssertTrue(Format('precondition: the change, drawn (%d,%d,%d)', [p.red, p.green, p.blue]),
      (p.red > 200) and (p.blue > 200) and (p.green < 80));
  finally
    bmp.Free;
  end;
  FCard.StyleOverride := 'border-color: #ff0000; border-width: 2px; border-radius: 8px;';
  FCard.XChromeChanged;   { back as it was: nothing changed, nothing repaints }
  bmp := b.Render;
  try
    AssertTrue('the frame as it is, not the one taken back', IsRed(bmp.GetPixel(1, 12)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestAChildFollowsTheFrameWhenTheCardResizes;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
begin
  FCard.SetBounds(10, 10, 300, 170);
  b := AddButton(FCard, 180, 70, 40, 24);
  FCard.XChromeChanged;
  bmp := b.Render;
  try
    AssertTrue('precondition: in the wide card the child is clear of the frame',
      IsBlue(bmp.GetPixel(38, 12)));
  finally
    bmp.Free;
  end;
  FCard.SetBounds(10, 10, 220, 170);   { now its right edge is on the frame }
  b.Invalidations := 0;
  FCard.XChromeChanged;
  AssertTrue('the frame came onto it: it repaints', b.Invalidations > 0);
  bmp := b.Render;
  try
    AssertTrue('and gets the frame where the card now has it', IsRed(bmp.GetPixel(38, 12)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestAFrameThatMovesOffAChildRepaintsIt;
var
  b, inside: TOvlButton;
  r: TRect;
begin
  r := FCard.ContentRect;
  b := AddButton(FCard, 180, 70, 40, 24);   { on the right frame of the 220 px card }
  inside := AddButton(FCard, r.Left + 8, r.Top + 8, 40, 20);
  FCard.XChromeChanged;
  FCard.SetBounds(10, 10, 300, 170);        { the frame moves off it }
  b.Invalidations := 0;
  inside.Invalidations := 0;
  FCard.XChromeChanged;
  AssertTrue('it repaints, or it keeps the old stroke', b.Invalidations > 0);
  AssertEquals('one never on the frame does not', 0, inside.Invalidations);
end;

{ The card stops taking its signature while nothing is on its chrome. A child that comes back
  onto it before the card paints again must not find a layer kept for a look the card has
  since left. }
procedure TChromeOverlayTest.TestAChildThatComesBackGetsTheFrameAsItIsNow;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
  p: TBGRAPixel;
  r: TRect;
begin
  b := AddButton(FCard, 0, 70, 60, 24);
  FCard.XChromeChanged;   { the card paints: red }
  bmp := b.Render;        { and a layer is kept for red }
  bmp.Free;
  r := FCard.ContentRect;
  b.SetBounds(r.Left + 8, r.Top + 8, 60, 24);
  FCard.XChromeChanged;   { nothing on the chrome now }
  FCard.StyleOverride := 'border-color: #ff00ff; border-width: 2px; border-radius: 8px;';
  FCard.XChromeChanged;   { the card paints magenta, still with nothing on it }
  b.SetBounds(0, 70, 60, 24);
  bmp := b.Render;
  try
    p := bmp.GetPixel(1, 12);
    AssertTrue(Format('back on the frame: the frame as it is (%d,%d,%d)',
      [p.red, p.green, p.blue]), (p.red > 200) and (p.blue > 200) and (p.green < 80));
  finally
    bmp.Free;
  end;
end;

{ Only these two need a real native window: the console runner never calls
  Application.Initialize, so without it CreateHandle fails with 1407 (as test.base does). }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

{ The real route: a paint message, as the window system sends it, onto a DC. }
function PaintByMessage(AControl: TWinControl): TBGRABitmap;
var
  b: TBitmap;
begin
  b := TBitmap.Create;
  try
    b.PixelFormat := pf32bit;
    b.SetSize(AControl.Width, AControl.Height);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, AControl.Width, AControl.Height);
    AControl.Perform(LM_PAINT, WParam(b.Canvas.Handle), 0);
    Result := TBGRABitmap.Create(b);
  finally
    b.Free;
  end;
end;

procedure TChromeOverlayTest.TestTheChildsPaintMessageDrawsIt;
var
  b: TOvlButton;
  bmp: TBGRABitmap;
begin
  NeedWidgetSet;
  b := AddButton(FCard, 0, 70, 60, 24);
  FForm.HandleNeeded;
  AssertTrue('precondition: the button has a window', b.HandleAllocated);
  bmp := PaintByMessage(b);
  try
    AssertTrue('the paint message ends with the card''s frame over the button',
      IsRed(bmp.GetPixel(1, 12)));
    AssertTrue('after the button itself', IsBlue(bmp.GetPixel(10, 12)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeOverlayTest.TestTheHostsPaintMessageChecksItsChrome;
var
  onIt, inside: TOvlButton;
  r: TRect;
  bmp: TBGRABitmap;
begin
  { The host's own paint message ends with the chrome check, so its first paint repaints the
    child on the frame. (That it also lays its chrome over its graphic children after LCL
    painted them is not reachable here: LCL paints a graphic child only once the form is
    shown, and these tests never show a window. The example's label on the frame is where
    that half is looked at.) }
  r := FCard.ContentRect;
  onIt := AddButton(FCard, 0, 70, 60, 24);
  inside := AddButton(FCard, r.Left + 8, r.Top + 8, 40, 20);
  NeedWidgetSet;
  FForm.HandleNeeded;
  onIt.Invalidations := 0;
  inside.Invalidations := 0;
  bmp := PaintByMessage(FCard);
  bmp.Free;
  AssertTrue('the card''s first paint repaints the child on its frame', onIt.Invalidations > 0);
  AssertEquals('not the one inside', 0, inside.Invalidations);
  onIt.Invalidations := 0;
  bmp := PaintByMessage(FCard);
  bmp.Free;
  AssertEquals('an unchanged frame repaints nothing', 0, onIt.Invalidations);
end;

const
  PANEL_CSS = 'border-color: #ff0000; border-width: 2px; border-radius: 8px;';

{ TChromeHostsTest }

function TChromeHostsTest.AddPanel(AParent: TWinControl; ALeft, ATop, AWidth,
  AHeight: Integer; const ACss: string): TTyPanel;
begin
  Result := TTyPanel.Create(FForm);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Caption := '';
  Result.StyleOverride := ACss;
  Result.SetBounds(ALeft, ATop, AWidth, AHeight);
  Result.Parent := AParent;
end;

{ A panel keeps its children off nothing but BorderWidth: an alClient child sits flush on
  the whole frame and on all four rounded corners. }
procedure TChromeHostsTest.TestAPanelKeepsItsFrameOverAChildFlushInIt;
var
  pn: TTyPanel;
  b: TOvlButton;
  bmp: TBGRABitmap;
begin
  pn := AddPanel(FForm, 10, 10, 200, 120, PANEL_CSS);
  b := AddButton(pn, 0, 0, 200, 120);   { where alClient puts it }
  bmp := b.RenderOwn;
  try
    AssertTrue('precondition: the child covers the frame', IsBlue(bmp.GetPixel(1, 60)));
  finally
    bmp.Free;
  end;
  bmp := b.Render;
  try
    AssertTrue('the panel''s frame, over the child', IsRed(bmp.GetPixel(1, 60)));
    AssertTrue('on the right too', IsRed(bmp.GetPixel(198, 60)));
    AssertFalse('outside the rounded corner, not the child', IsBlue(bmp.GetPixel(0, 0)));
    AssertTrue('inside the frame the child is itself', IsBlue(bmp.GetPixel(100, 60)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeHostsTest.TestAPanelsKeptLayerMatchesAFreshOne;
var
  pn: TTyPanel;
  kids: array[0..1] of TOvlButton;
  i: Integer;
  a, b: TBGRABitmap;
begin
  pn := AddPanel(FForm, 10, 10, 200, 120, PANEL_CSS);
  kids[0] := AddButton(pn, 0, 0, 200, 120);   { the whole frame }
  kids[1] := AddButton(pn, 150, 90, 50, 30);  { a corner }
  for i := 0 to High(kids) do
  begin
    TyChromeMode := 0;
    a := kids[i].Render;
    TyChromeMode := 2;
    b := kids[i].Render;
    try
      AssertTrue(Format('child %d: the kept layer gives what drawing it afresh gives', [i]),
        Same(a, b));
    finally
      a.Free;
      b.Free;
    end;
  end;
end;

{ No border, no focus ring: the panel's rounded shape cannot be seen, so its children keep
  their square corners -- a layout panel with border-width 0 changes nothing. }
procedure TChromeHostsTest.TestAPanelWithoutABorderLeavesItsChildAlone;
var
  pn: TTyPanel;
  b: TOvlButton;
  own, over: TBGRABitmap;
begin
  pn := AddPanel(FForm, 10, 10, 200, 120, 'border-width: 0; border-radius: 8px;');
  b := AddButton(pn, 0, 0, 200, 120);
  own := b.RenderOwn;
  over := b.Render;
  try
    AssertTrue('nothing drawn over the child', Same(own, over));
  finally
    own.Free;
    over.Free;
  end;
end;

{ An embedded scroll bar paints its host's frame over itself already (PaintsParentFrame); a
  second coat would darken the anti-aliased edge. Its host leaves it alone -- the hosts
  further out still draw. }
procedure TChromeHostsTest.TestAStripThatDrawsItsHostsFrameIsLeftToIt;
var
  outer, inner: TTyPanel;
  strip: TOvlStrip;
  plain: TOvlButton;
  bmp: TBGRABitmap;
begin
  outer := AddPanel(FForm, 10, 10, 260, 160, PANEL_CSS);
  inner := AddPanel(outer, 0, 20, 120, 80,
    'border-color: #00ff00; border-width: 2px; border-radius: 0;');
  plain := AddButton(inner, 0, 30, 120, 20);
  bmp := plain.Render;
  try
    AssertTrue('precondition: an ordinary child gets the inner frame',
      IsGreen(bmp.GetPixel(118, 10)));
  finally
    bmp.Free;
  end;
  strip := TOvlStrip.Create(FForm);
  strip.Controller := FCtl;
  strip.Font.PixelsPerInch := 96;
  strip.Caption := '';
  strip.StyleOverride := BLUE_CSS;
  strip.SetBounds(0, 30, 120, 20);
  strip.Parent := inner;
  bmp := strip.Render;
  try
    AssertTrue('the strip''s own host leaves it be', IsBlue(bmp.GetPixel(118, 10)));
    AssertTrue('the host further out still draws its frame', IsRed(bmp.GetPixel(1, 10)));
  finally
    bmp.Free;
  end;
end;

function NewGroupBox(AOwner: TForm; ACtl: TTyStyleController): TOvlGroupBox;
begin
  Result := TOvlGroupBox.Create(AOwner);
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  Result.Caption := 'Caption';
  Result.StyleOverride := PANEL_CSS;
  Result.SetBounds(10, 10, 200, 120);
  Result.Parent := AOwner;
end;

{ A hand-placed child over the caption and the top line: the caption is part of the frame,
  so the gap it breaks in the line and its ink stay on top of the child. }
procedure TChromeHostsTest.TestAGroupBoxKeepsItsCaptionOverAChild;
var
  gb: TOvlGroupBox;
  b: TOvlButton;
  bmp: TBGRABitmap;
  gap: TBGRAPixel;
  x, inkless: Integer;
begin
  gb := NewGroupBox(FForm, FCtl);
  b := AddButton(gb, 0, 0, 120, 40);
  bmp := b.Render;
  try
    gap := bmp.GetPixel(5, 2);   { inside the caption's band, left of its text }
    AssertFalse('the caption''s gap, over the child', IsBlue(gap));
    inkless := 0;
    for x := 8 to 50 do
      if bmp.GetPixel(x, 8) = gap then Inc(inkless);
    AssertTrue('and its text inked across the middle of the band', inkless < 43);
    AssertTrue('the frame''s left line, over the child', IsRed(bmp.GetPixel(1, 30)));
    AssertTrue('above the line and left of the caption, the child itself',
      IsBlue(bmp.GetPixel(1, 3)));
    AssertTrue('below the frame''s line and right of the caption, the child itself',
      IsBlue(bmp.GetPixel(110, 30)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeHostsTest.TestAGroupBoxsKeptLayerMatchesAFreshOne;
var
  gb: TOvlGroupBox;
  b: TOvlButton;
  a, c: TBGRABitmap;
begin
  gb := NewGroupBox(FForm, FCtl);
  b := AddButton(gb, 0, 0, 120, 40);
  TyChromeMode := 0;
  a := b.Render;
  TyChromeMode := 2;
  c := b.Render;
  try
    AssertTrue('the kept layer gives what drawing it afresh gives', Same(a, c));
  finally
    a.Free;
    c.Free;
  end;
end;

{ The caption runs from the top of the box to the bottom of its band, above the frame's line
  too: a child anywhere in that band is under chrome. }
procedure TChromeHostsTest.TestTheGroupBoxCaptionIsNotFreeGround;
var
  gb: TOvlGroupBox;
begin
  gb := NewGroupBox(FForm, FCtl);
  AssertTrue(Format('the free ground starts below the caption''s band (%d)',
    [gb.ChromeFreeRect.Top]), gb.ChromeFreeRect.Top >= 16);
  gb.Caption := '';
  gb.StyleOverride := 'border-width: 0; border-radius: 0;';
  AssertEquals('no caption and no frame: all of it is free', 0, gb.ChromeFreeRect.Top);
end;

procedure TChromeHostsTest.TestANewCaptionRepaintsTheChildUnderIt;
var
  gb: TOvlGroupBox;
  b: TOvlButton;
begin
  gb := NewGroupBox(FForm, FCtl);
  b := AddButton(gb, 0, 0, 120, 40);
  gb.XChromeChanged;
  b.Invalidations := 0;
  gb.XChromeChanged;
  AssertEquals('nothing changed: nothing repaints', 0, b.Invalidations);
  gb.Caption := 'Another caption';
  gb.XChromeChanged;
  AssertTrue('a new caption repaints the child under it', b.Invalidations > 0);
end;

{ A page control with one blue page, laid where the align engine lays it (DisplayRect). }
function NewPagedControl(AOwner: TForm; ACtl: TTyStyleController;
  ASide: TTabPosition; out APage: TOvlSheet): TTyPageControl;
begin
  Result := TTyPageControl.Create(AOwner);
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  Result.StyleOverride := PANEL_CSS;
  Result.TabPosition := ASide;
  Result.Parent := AOwner;
  Result.SetBounds(10, 10, 240, 160);
  APage := TOvlSheet.Create(AOwner);
  APage.Controller := ACtl;
  APage.Font.PixelsPerInch := 96;
  APage.Caption := 'Page';
  APage.StyleOverride := 'background: #0000ff;';
  APage.Parent := Result;
  APage.BoundsRect := Result.DisplayRect;
end;

{ The page fills the box below the band and used to cover three sides of the frame and its
  two far corners. }
procedure TChromeHostsTest.TestAPageGetsThePageControlsFrame;
var
  pc: TTyPageControl;
  pg: TOvlSheet;
  bmp: TBGRABitmap;
  midX, midY: Integer;
begin
  pc := NewPagedControl(FForm, FCtl, tpTop, pg);
  midX := pg.Width div 2;
  midY := pg.Height div 2;
  bmp := pg.RenderOwn;
  try
    AssertTrue('precondition: the page covers the frame', IsBlue(bmp.GetPixel(1, midY)));
  finally
    bmp.Free;
  end;
  bmp := pg.Render;
  try
    AssertTrue('the left side of the frame, over the page', IsRed(bmp.GetPixel(1, midY)));
    AssertTrue('the right side', IsRed(bmp.GetPixel(pg.Width - 2, midY)));
    AssertTrue('the bottom', IsRed(bmp.GetPixel(midX, pg.Height - 2)));
    AssertFalse('outside the rounded far corner, not the page',
      IsBlue(bmp.GetPixel(0, pg.Height - 1)));
    AssertTrue('inside the frame the page is itself', IsBlue(bmp.GetPixel(midX, midY)));
  finally
    bmp.Free;
  end;
  AssertTrue('precondition: the page sits below the band', pg.Top > 0);
end;

{ With the band down the left side, the frame's line along it is pushed 1px into the band
  and its other px lands on the page's first column. }
procedure TChromeHostsTest.TestASideBandKeepsTheFrameOnThePage;
var
  pc: TTyPageControl;
  pg: TOvlSheet;
  bmp: TBGRABitmap;
begin
  pc := NewPagedControl(FForm, FCtl, tpLeft, pg);
  AssertTrue('precondition: the page sits right of the band', pg.Left > 0);
  bmp := pg.Render;
  try
    AssertTrue('the frame''s line along the band, on the page''s first column',
      IsRed(bmp.GetPixel(0, pg.Height div 2)));
    AssertTrue('the far side', IsRed(bmp.GetPixel(pg.Width - 2, pg.Height div 2)));
  finally
    bmp.Free;
  end;
end;

procedure TChromeHostsTest.TestAPageControlsKeptLayerMatchesAFreshOne;
var
  pc: TTyPageControl;
  pg: TOvlSheet;
  a, b: TBGRABitmap;
begin
  pc := NewPagedControl(FForm, FCtl, tpTop, pg);
  TyChromeMode := 0;
  a := pg.Render;
  TyChromeMode := 2;
  b := pg.Render;
  try
    AssertTrue('the kept layer gives what drawing it afresh gives', Same(a, b));
  finally
    a.Free;
    b.Free;
  end;
end;

function NewToolBar(AOwner: TForm; ACtl: TTyStyleController; const ACss: string): TTyToolBar;
begin
  Result := TTyToolBar.Create(AOwner);
  Result.Controller := ACtl;
  Result.Font.PixelsPerInch := 96;
  Result.StyleOverride := ACss;
  Result.Parent := AOwner;
  Result.SetBounds(10, 10, 240, 36);
end;

{ The row shift keeps a tool off the bar's hairline only as far as the vertical pad goes: a
  taller one reaches it. Placed by hand here, where the bar's own layout would put the
  row's bottom. }
procedure TChromeHostsTest.TestATallToolKeepsTheBarsHairlineOverIt;
var
  tb: TTyToolBar;
  b: TOvlButton;
  bmp: TBGRABitmap;
begin
  tb := NewToolBar(FForm, FCtl, 'border-color: #ff0000; border-width: 2px;');
  b := AddButton(tb, 20, 0, 60, 36);
  b.SetBounds(20, 0, 60, 36);   { the bar may have moved it; put it back across the line }
  bmp := b.Render;
  try
    AssertTrue('the hairline, over the tool', IsRed(bmp.GetPixel(30, 35)));
    AssertTrue('its upper row too', IsRed(bmp.GetPixel(30, 34)));
    AssertTrue('above it the tool is itself', IsBlue(bmp.GetPixel(30, 20)));
  finally
    bmp.Free;
  end;
end;

{ The bar draws no frame and no corners, only its hairline: with the line's colour clear, a
  tool across it is left exactly as it painted itself. }
procedure TChromeHostsTest.TestABarsLayerIsItsLineAndNothingElse;
var
  tb: TTyToolBar;
  b: TOvlButton;
  own, over: TBGRABitmap;
begin
  tb := NewToolBar(FForm, FCtl, 'border-color: transparent; border-width: 0; border-radius: 8px;');
  b := AddButton(tb, 0, 0, 60, 36);
  b.SetBounds(0, 0, 60, 36);
  own := b.RenderOwn;
  over := b.Render;
  try
    AssertTrue('nothing drawn over the tool', Same(own, over));
  finally
    own.Free;
    over.Free;
  end;
end;

initialization
  RegisterTest(TChromeOverlayTest);
  RegisterTest(TChromeHostsTest);
end.
