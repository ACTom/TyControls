unit test.parity.toolbar;
{$mode objfpc}{$H+}

{ API-parity guards for TTyToolBar.Images and TTyToolBar.ShowCaptions.

  Both used to be published-but-inert knobs: Images was an LCL TImageList (a type NO
  ty control can draw from -- every icon in this library comes from the name-keyed BGRA
  TTyImageCollection), and ShowCaptions was stored, triggered a relayout and was then
  read by nothing. The Object Inspector offered two settings the control ignored.

  These tests pin the wiring that replaced them:
    * the bar LENDS its TTyImageCollection to tool buttons that have none of their own,
      follows/retracts only the reference it lent, and never touches a tool that carries
      its own collection;
    * ShowCaptions reaches each tool's ShowCaption, which makes a tool icon-only, but
      never overrides a per-tool ShowCaption the host wrote itself.

  The paint tests are the ones that actually prove "icon-only": a property flag that
  flips without changing a single pixel would be the same lie in a new place. }

interface
uses
  Classes, SysUtils, Types, TypInfo, Controls, Graphics, Forms,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller,
  tyControls.ImageCollection, tyControls.GlyphButtons, tyControls.ToolBar;

type
  { Exposes the protected paint path so the glyph/caption composite is renderable headlessly. }
  TSpeedButtonAccess = class(TTySpeedButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { Shared fixture: a bar on a form, plus two distinct icon collections. }
  TToolBarParityFixture = class(TTestCase)
  protected
    FForm: TForm;
    FBar: TTyToolBar;
    FColl: TTyImageCollection;
    FOther: TTyImageCollection;
    FTool: TTySpeedButton;
    procedure SetUp; override;
    procedure TearDown; override;
    { A tool button parented onto the bar (nothing else set). }
    function AddTool: TTySpeedButton;
  end;

  TToolBarImagesParityTest = class(TToolBarParityFixture)
  published
    procedure TestImagesIsATyImageCollection;
    procedure TestLendsItsCollectionToANewTool;
    procedure TestSettingImagesReachesToolsAlreadyOnTheBar;
    procedure TestNeverClobbersAToolsOwnCollection;
    procedure TestLentReferenceFollowsTheBar;
    procedure TestTakesBackWhatItLentWhenCleared;
    procedure TestFreedCollectionIsNilled;
  end;

  TToolBarShowCaptionsParityTest = class(TToolBarParityFixture)
  published
    procedure TestShowCaptionIsPublishedAndDefaultsTrue;
    procedure TestBarPropagatesShowCaptionsToTools;
    procedure TestExplicitToolShowCaptionSurvivesTheBar;
    procedure TestExplicitShowCaptionPinsEvenWhenItMatchesTheBar;
    procedure TestIconOnlyRectCenters;
    procedure TestIconOnlyRectClampsAndDegenerates;
  end;

  { Pixel proof that ShowCaption changes what is painted, not just a field. }
  TGlyphButtonCaptionPaintTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FColl: TTyImageCollection;
    { A speed button on FForm/FCtl with a solid 'ico' image glyph tinted GREEN and a
      caption drawn in the theme's RED, so glyph ink and caption ink are separable. }
    function MakeButton(AShowCaption: Boolean; const ACaption: string): TSpeedButtonAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCaptionShownPutsGlyphAtTheLeft;
    procedure TestIconOnlyHidesCaptionAndCentersGlyph;
    procedure TestNoIconKeepsItsCaptionEvenWhenSuppressed;
  end;

implementation

const
  { Paint-test canvas. Content box == client box (the theme sets padding 0), so the
    expected glyph rects are computed straight from these. }
  BtnW = 80;
  BtnH = 40;
  GlyphPx = 16;

procedure TSpeedButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ ---- ink probes ---------------------------------------------------------- }

{ The glyph is tinted pure green, the caption is drawn in pure red and the button
  background is black, so a channel-dominance test tells the two inks apart even on
  antialiased edges. }
function IsGlyphInk(const P: TBGRAPixel): Boolean;
begin
  Result := (P.green > 100) and (P.green > P.red + 40) and (P.green > P.blue + 40);
end;

function IsCaptionInk(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red > 100) and (P.red > P.green + 40) and (P.red > P.blue + 40);
end;

{ Horizontal centre of the glyph ink, or -1 when none was painted. }
function GlyphInkCenterX(ABmp: TBGRABitmap): Integer;
var
  x, y, lo, hi: Integer;
begin
  lo := MaxInt; hi := -1;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
      if IsGlyphInk(ABmp.GetPixel(x, y)) then
      begin
        if x < lo then lo := x;
        if x > hi then hi := x;
      end;
  if hi < 0 then Exit(-1);
  Result := (lo + hi) div 2;
end;

function HasCaptionInk(ABmp: TBGRABitmap): Boolean;
var
  x, y: Integer;
begin
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
      if IsCaptionInk(ABmp.GetPixel(x, y)) then Exit(True);
  Result := False;
end;

{ Render B into a BtnW x BtnH canvas and re-read it. Caller frees the result. }
function RenderButton(B: TSpeedButtonAccess): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(BtnW, BtnH);
    // Pre-fill white: the canvas start state is otherwise undefined, and white is
    // neither glyph ink nor caption ink under the probes above.
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, BtnW, BtnH);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, BtnW, BtnH), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ ---- TToolBarParityFixture ----------------------------------------------- }

procedure TToolBarParityFixture.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 200);
  FBar := TTyToolBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alNone;          // keep the LCL align engine off our explicit bounds
  FBar.SetBounds(0, 0, 300, 30);
  FColl := TTyImageCollection.Create(FForm);
  FOther := TTyImageCollection.Create(FForm);
  FTool := nil;
end;

procedure TToolBarParityFixture.TearDown;
begin
  FreeAndNil(FForm);   // owns the bar, the tools and both collections
end;

function TToolBarParityFixture.AddTool: TTySpeedButton;
begin
  Result := TTySpeedButton.Create(FForm);
  Result.Parent := FBar;
end;

{ ---- TToolBarImagesParityTest -------------------------------------------- }

procedure TToolBarImagesParityTest.TestImagesIsATyImageCollection;
var
  PI: PPropInfo;
begin
  PI := GetPropInfo(FBar, 'Images');
  AssertTrue('Images is published', PI <> nil);
  // An LCL TImageList is index-keyed and nothing in this library renders from one:
  // whatever a host assigned there could never reach a tool button. The bar's icon
  // source has to be the same name-keyed BGRA collection the buttons consume.
  AssertEquals('Images must be the collection the tool buttons can actually draw from',
    'TTyImageCollection', string(PI^.PropType^.Name));
end;

procedure TToolBarImagesParityTest.TestLendsItsCollectionToANewTool;
begin
  FBar.Images := FColl;
  FTool := AddTool;    // joins the bar afterwards
  AssertSame('a tool with no collection of its own draws from the bar''s',
    FColl, FTool.Images);
end;

procedure TToolBarImagesParityTest.TestSettingImagesReachesToolsAlreadyOnTheBar;
begin
  FTool := AddTool;    // on the bar BEFORE it has any collection
  AssertTrue('no collection yet', FTool.Images = nil);
  FBar.Images := FColl;
  AssertSame('assigning Images reaches the tools already docked', FColl, FTool.Images);
end;

procedure TToolBarImagesParityTest.TestNeverClobbersAToolsOwnCollection;
begin
  FTool := AddTool;
  FTool.Images := FOther;          // the app made its own choice for this tool
  FBar.Images := FColl;
  AssertSame('the bar must not overwrite a tool that carries its own collection',
    FOther, FTool.Images);
  FBar.Images := nil;
  AssertSame('...and clearing the bar must not take away what it never lent',
    FOther, FTool.Images);
end;

procedure TToolBarImagesParityTest.TestLentReferenceFollowsTheBar;
begin
  FBar.Images := FColl;
  FTool := AddTool;
  AssertSame('lent the first collection', FColl, FTool.Images);
  FBar.Images := FOther;
  AssertSame('the lent reference follows the bar to the new collection',
    FOther, FTool.Images);
end;

procedure TToolBarImagesParityTest.TestTakesBackWhatItLentWhenCleared;
begin
  FBar.Images := FColl;
  FTool := AddTool;
  FBar.Images := nil;
  AssertTrue('clearing the bar takes back the reference it lent', FTool.Images = nil);
end;

procedure TToolBarImagesParityTest.TestFreedCollectionIsNilled;
var
  C: TTyImageCollection;
begin
  // Owner nil ON PURPOSE: with no shared owner the opRemove only arrives if the bar
  // registered a FreeNotification, so this pins the registration, not the Notification
  // override. Without it the bar (and every reference it lent) would dangle.
  C := TTyImageCollection.Create(nil);
  try
    FBar.Images := C;
    AssertSame('assigned', C, FBar.Images);
  finally
    FreeAndNil(C);
  end;
  AssertTrue('freeing the collection nils the bar''s reference', FBar.Images = nil);
end;

{ ---- TToolBarShowCaptionsParityTest -------------------------------------- }

procedure TToolBarShowCaptionsParityTest.TestShowCaptionIsPublishedAndDefaultsTrue;
var
  B: TTyGlyphButton;
begin
  B := TTyGlyphButton.Create(nil);
  try
    AssertTrue('ShowCaption is published on the glyph button',
      IsPublishedProp(B, 'ShowCaption'));
    // A glyph button used on its own is icon + caption; only a container asks for
    // icon-only, so the standalone default has to stay "show it".
    AssertTrue('a glyph button shows its caption by default', B.ShowCaption);
  finally
    B.Free;
  end;
end;

procedure TToolBarShowCaptionsParityTest.TestBarPropagatesShowCaptionsToTools;
begin
  FTool := AddTool;
  // LCL parity: the bar's default (False) means icon-only tools.
  AssertFalse('a tool joins the bar with the bar''s ShowCaptions', FTool.ShowCaption);
  FBar.ShowCaptions := True;
  AssertTrue('turning captions on reaches the tools', FTool.ShowCaption);
  FBar.ShowCaptions := False;
  AssertFalse('turning captions off reaches the tools', FTool.ShowCaption);
end;

procedure TToolBarShowCaptionsParityTest.TestExplicitToolShowCaptionSurvivesTheBar;
begin
  FTool := AddTool;
  FTool.ShowCaption := True;       // this one tool wants its label whatever the bar says
  FBar.ShowCaptions := False;
  AssertTrue('a per-tool ShowCaption must survive the bar''s default', FTool.ShowCaption);
  FBar.ShowCaptions := True;
  FBar.ShowCaptions := False;
  AssertTrue('...and every later change to it', FTool.ShowCaption);
end;

procedure TToolBarShowCaptionsParityTest.TestExplicitShowCaptionPinsEvenWhenItMatchesTheBar;
begin
  FTool := AddTool;                // joins with the bar's default: ShowCaption = False
  FTool.ShowCaption := False;      // the host asks for icon-only ON THIS TOOL, same value
  // Writing the property is the claim, not the value change: if the claim were only
  // recorded when the value actually moved, this tool would silently follow the bar
  // back up. It must stay icon-only.
  FBar.ShowCaptions := True;
  AssertFalse('writing the value the bar already pushed still pins the tool',
    FTool.ShowCaption);
end;

procedure TToolBarShowCaptionsParityTest.TestIconOnlyRectCenters;
var
  R: TRect;
begin
  // 100x40 box, 20px glyph -> centred on BOTH axes: (40,10)-(60,30). The caption-less
  // glyph must NOT keep the glyph-left anchor, or an icon-only tool would hug its left
  // edge with dead space where the text used to be.
  R := TyGlyphButtonIconOnlyRect(Rect(0, 0, 100, 40), 20);
  AssertEquals('icon-only glyph.Left', 40, R.Left);
  AssertEquals('icon-only glyph.Top', 10, R.Top);
  AssertEquals('icon-only glyph.Right', 60, R.Right);
  AssertEquals('icon-only glyph.Bottom', 30, R.Bottom);
  // An offset content rect centres inside ITS box, not the control's origin.
  R := TyGlyphButtonIconOnlyRect(Rect(10, 5, 50, 25), 10);
  AssertEquals('offset icon-only glyph.Left', 25, R.Left);
  AssertEquals('offset icon-only glyph.Top', 10, R.Top);
end;

procedure TToolBarShowCaptionsParityTest.TestIconOnlyRectClampsAndDegenerates;
var
  R: TRect;
begin
  // Oversized glyph clamps to the box's SHORT side and stays inside the box.
  R := TyGlyphButtonIconOnlyRect(Rect(0, 0, 30, 18), 50);
  AssertEquals('clamped to the short side (w)', 18, R.Right - R.Left);
  AssertEquals('clamped to the short side (h)', 18, R.Bottom - R.Top);
  AssertTrue('never overhangs the content box',
    (R.Left >= 0) and (R.Right <= 30) and (R.Top >= 0) and (R.Bottom <= 18));
  // No glyph -> an empty rect at the content origin, never a negative one.
  R := TyGlyphButtonIconOnlyRect(Rect(5, 7, 105, 47), 0);
  AssertEquals('no glyph -> empty (w)', 0, R.Right - R.Left);
  AssertEquals('no glyph -> empty (h)', 0, R.Bottom - R.Top);
  // Degenerate box -> likewise empty (and no negative dimension).
  R := TyGlyphButtonIconOnlyRect(Rect(4, 4, 4, 4), 16);
  AssertEquals('degenerate box -> empty (w)', 0, R.Right - R.Left);
  AssertEquals('degenerate box -> empty (h)', 0, R.Bottom - R.Top);
end;

{ ---- TGlyphButtonCaptionPaintTest ---------------------------------------- }

procedure TGlyphButtonCaptionPaintTest.SetUp;
var
  Master: TBGRABitmap;
begin
  FCtl := TTyStyleController.Create(nil);
  // Black plate, RED caption ink, no padding -> the content box IS the client box, so
  // the expected glyph rects below are exact.
  FCtl.LoadThemeCss(
    'TySpeedButton { background: #000000; color: #FF0000; padding: 0px; '
    + 'border-width: 0px; font-size: 14px; }');
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 200);
  FColl := TTyImageCollection.Create(FForm);
  // A fully opaque square master: GetBitmap scales it 1:1 into the glyph square and
  // TyTintBitmapAlpha recolours it to GlyphColor, so the drawn glyph is a solid block
  // of a known colour -- deterministic headless ink, no font required.
  Master := TBGRABitmap.Create(GlyphPx, GlyphPx, BGRAWhite);
  try
    FColl.AddBitmap('ico', Master);
  finally
    Master.Free;
  end;
end;

procedure TGlyphButtonCaptionPaintTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

function TGlyphButtonCaptionPaintTest.MakeButton(AShowCaption: Boolean;
  const ACaption: string): TSpeedButtonAccess;
begin
  Result := TSpeedButtonAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;     // Scale() 1:1, so logical == device px
  Result.SetBounds(0, 0, BtnW, BtnH);
  Result.GlyphSize := GlyphPx;
  Result.GlyphColor := TyRGB(0, 255, 0);   // GREEN, distinct from the red caption ink
  Result.Caption := ACaption;
  Result.ShowCaption := AShowCaption;
end;

procedure TGlyphButtonCaptionPaintTest.TestCaptionShownPutsGlyphAtTheLeft;
var
  B: TSpeedButtonAccess;
  Img: TBGRABitmap;
  cx: Integer;
begin
  // Baseline (ShowCaption = True): glyph-left anchor -> a 16px glyph at x 0..16
  // (centre 8) with the caption drawn to its right.
  B := MakeButton(True, 'MMMM');
  B.Images := FColl;
  B.ImageName := 'ico';
  Img := RenderButton(B);
  try
    cx := GlyphInkCenterX(Img);
    AssertTrue('the glyph was painted', cx >= 0);
    AssertTrue(Format('glyph stays left-anchored beside the caption (centre x=%d, expected ~8)',
      [cx]), (cx >= 4) and (cx <= 12));
    AssertTrue('the caption is painted when ShowCaption is on', HasCaptionInk(Img));
  finally
    Img.Free;
  end;
end;

procedure TGlyphButtonCaptionPaintTest.TestIconOnlyHidesCaptionAndCentersGlyph;
var
  B: TSpeedButtonAccess;
  Img: TBGRABitmap;
  cx: Integer;
begin
  // ShowCaption = False with an icon available: NO caption ink anywhere, and the glyph
  // re-centres in the whole 80px content box (centre 40, not the left-anchored 8).
  B := MakeButton(False, 'MMMM');
  B.Images := FColl;
  B.ImageName := 'ico';
  Img := RenderButton(B);
  try
    cx := GlyphInkCenterX(Img);
    AssertTrue('the glyph is still painted', cx >= 0);
    AssertTrue(Format('icon-only re-centres the glyph (centre x=%d, expected ~40)',
      [cx]), (cx >= 36) and (cx <= 44));
    AssertFalse('icon-only must paint no caption at all', HasCaptionInk(Img));
  finally
    Img.Free;
  end;
end;

procedure TGlyphButtonCaptionPaintTest.TestNoIconKeepsItsCaptionEvenWhenSuppressed;
var
  B: TSpeedButtonAccess;
  Img: TBGRABitmap;
begin
  // No image and no icon font: there is nothing to show INSTEAD of the caption, so
  // suppressing it would paint an empty box. Since the bar's LCL-parity default is
  // ShowCaptions = False, that would blank every caption-only tool in every app.
  B := MakeButton(False, 'MMMM');   // no Images / ImageName assigned
  Img := RenderButton(B);
  try
    AssertEquals('no glyph source -> no glyph ink', -1, GlyphInkCenterX(Img));
    AssertTrue('a tool with no icon keeps its caption', HasCaptionInk(Img));
  finally
    Img.Free;
  end;
end;

initialization
  RegisterTest(TToolBarImagesParityTest);
  RegisterTest(TToolBarShowCaptionsParityTest);
  RegisterTest(TGlyphButtonCaptionPaintTest);
end.
