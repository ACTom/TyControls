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
  Classes, SysUtils, Types, Graphics, Controls, Forms, LCLType, LMessages, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Controller, tyControls.Base,
  tyControls.Card, tyControls.Button, tyControls.Panel, tyControls.TyLabel;

type
  TOvlButton = class(TTyButton)
  public
    Invalidations: Integer;
    procedure Invalidate; override;
    function Render: TBGRABitmap;   // its own render, then the ancestors' chrome over it
    function RenderOwn: TBGRABitmap;
  end;

  TOvlCard = class(TTyCard)
  public
    procedure XRender(ACanvas: TCanvas);
    procedure XChromeChanged;
  end;

  TOvlLabel = class(TTyLabel)
  public
    procedure XRender(ACanvas: TCanvas);
  end;

  TChromeOverlayTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FCard: TOvlCard;
    function AddButton(AParent: TWinControl; ALeft, ATop, AWidth, AHeight: Integer;
      const AExtraCss: string = ''): TOvlButton;
    function IsRed(const P: TBGRAPixel): Boolean;
    function IsGreen(const P: TBGRAPixel): Boolean;
    function IsBlue(const P: TBGRAPixel): Boolean;
    function Same(A, B: TBGRABitmap): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
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
    procedure TestTheHostsPaintMessageChecksItsChrome;
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

{ TOvlCard }

procedure TOvlCard.XRender(ACanvas: TCanvas);
begin
  RenderTo(ACanvas, Rect(0, 0, Width, Height), 96);
end;

procedure TOvlCard.XChromeChanged;
begin
  CheckChromeChanged;
end;

{ TOvlLabel }

procedure TOvlLabel.XRender(ACanvas: TCanvas);
begin
  RenderTo(ACanvas, BoundsRect, 96);
end;

{ TChromeOverlayTest }

procedure TChromeOverlayTest.SetUp;
begin
  TyChromeOverlayEnabled := True;
  TyChromeMode := 2;
  FCtl := TTyStyleController.Create(nil);
  FCtl.StyleOverride := 'TyCardHeader { border-color: #00ff00; border-width: 1px; }';
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FCard := TOvlCard.Create(FForm);
  FCard.Controller := FCtl;
  FCard.Font.PixelsPerInch := 96;
  FCard.SetBounds(10, 10, 220, 170);
  FCard.Title := 'Card';
  FCard.StyleOverride := 'border-color: #ff0000; border-width: 2px; border-radius: 8px;';
  FCard.Parent := FForm;
end;

procedure TChromeOverlayTest.TearDown;
begin
  TyChromeOverlayEnabled := True;
  TyChromeMode := 2;
  FForm.Free;
  FCtl.Free;
end;

function TChromeOverlayTest.AddButton(AParent: TWinControl; ALeft, ATop, AWidth,
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

function TChromeOverlayTest.IsRed(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red > 200) and (P.green < 80) and (P.blue < 80);
end;

function TChromeOverlayTest.IsGreen(const P: TBGRAPixel): Boolean;
begin
  Result := (P.green > 200) and (P.red < 80) and (P.blue < 80);
end;

function TChromeOverlayTest.IsBlue(const P: TBGRAPixel): Boolean;
begin
  Result := (P.blue > 200) and (P.red < 80) and (P.green < 80);
end;

function TChromeOverlayTest.Same(A, B: TBGRABitmap): Boolean;
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

initialization
  RegisterTest(TChromeOverlayTest);
end.
