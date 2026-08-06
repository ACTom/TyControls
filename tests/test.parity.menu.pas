unit test.parity.menu;
{$mode objfpc}{$H+}

{ API-parity guards for the four members TTyPopupMenu inherits, publishes and used to
  ignore: TrackButton, TMenuItem.GlyphShowMode, TMenuItem.SubMenuImages(+Width) and the
  OwnerDraw / OnDrawItem / OnMeasureItem protocol.

  All four were settable from the Object Inspector and read by nothing -- the same defect
  class as a published Caption that is never painted. The tests below pin the wiring that
  replaced them, and most of them are PAINT tests on purpose: a flag that flips without
  changing a pixel would be the same lie in a new place. }

interface
uses
  Classes, SysUtils, Math, Types, Controls, Graphics, Forms, Menus, ImgList,
  LCLType, LCLIntf, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.ImageCollection, tyControls.Menu;

type
  { Probe subclass: exposes the protected render/geometry seams plus a mouse-up injector,
    so the whole row pipeline is exercised headlessly against a bitmap canvas. }
  TMenuViewProbe = class(TTyMenuView)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function RowTop(AIndex, APPI: Integer): Integer;
    function RowHeight(AIndex, APPI: Integer): Integer;
    function RowAtY(AY, APPI: Integer): Integer;
    function MeasureHeight(APPI: Integer): Integer;
    function MeasureWidth(APPI: Integer): Integer;
    procedure SetHighlight(AIndex: Integer);
    { A button release over the row at device-Y AY. TControl.Click (the LEFT path) is
      public and driven directly; the right button only ever arrives through MouseUp. }
    procedure SimulateMouseUp(AButton: TMouseButton; AY: Integer);
  end;

  { Shared fixture: a controller with a black popup surface and white row text, so a
    coloured icon (or an owner-drawn block) is separable from everything else. }
  TMenuParityFixture = class(TTestCase)
  protected
    FCtl: TTyStyleController;
    FMenu: TPopupMenu;
    FView: TMenuViewProbe;
    procedure SetUp; override;
    procedure TearDown; override;
    { Render FView into a WxH bitmap and read it back. Caller frees the result. }
    function Render(AWidth, AHeight: Integer): TBGRABitmap;
  end;

  TMenuGlyphShowModeTest = class(TMenuParityFixture)
  private
    FColl: TTyImageCollection;
    FImages: TTyVirtualImageList;
    { One item captioned 'Save' with ImageIndex 0 and the given glyph mode, rendered. }
    function RenderItemWithMode(AMode: TGlyphShowMode): TBGRABitmap;
  protected
    procedure SetUp; override;
  published
    procedure TestAlwaysDrawsTheIcon;
    procedure TestNeverDrawsNoIcon;
    procedure TestGlyphVisibleFollowsTheModeAndTheApplication;
    procedure TestBuildRowsCarriesGlyphVisible;
  end;

  TMenuSubMenuImagesTest = class(TMenuParityFixture)
  private
    FList: TCustomImageList;      // 16px, RED
    FWide: TCustomImageList;      // 48px, RED -- for the slot/row floor
    FSub: TMenuItem;
    FColl: TTyImageCollection;
    FTyImages: TTyVirtualImageList;   // GREEN, the library's own icon column
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSubMenuImagesDrawsTheSubmenuIcon;
    procedure TestNearestAncestorWins;
    procedure TestBuildRowsCarriesTheResolvedListAndWidth;
    procedure TestSubMenuImagesBeatsTheLibraryIconColumn;
    procedure TestWideIconsWidenTheSlotAndTheRow;
    procedure TestDisabledRowGetsTheGreyedIcon;
  end;

  TMenuTrackButtonTest = class(TMenuParityFixture)
  private
    FActivated: Integer;
    procedure HandleActivate(Sender: TObject; AIndex: Integer);
    { One enabled row, wired to HandleActivate, with FActivated reset to -1. }
    procedure OneRow;
  published
    procedure TestRightButtonActivatesByDefault;
    procedure TestLeftButtonOnlyUnderTbLeftButton;
    procedure TestTrackButtonReachesTheRendererView;
  end;

  { The owner-draw protocol: OwnerDraw gates it, OnMeasureItem sizes each row and
    OnDrawItem paints it (per item, falling back to the menu's own handlers). }
  TMenuOwnerDrawTest = class(TMenuParityFixture)
  private
    FDrawCalls: Integer;
    FLastState: TOwnerDrawState;
    FLastRect: TRect;
    FMeasureCalls: Integer;
    FMeasureHeight: Integer;
    FStaleInkRows: Integer;      // rows whose DC ink was NOT the one the handler asked for
    FProbeRect: array of TRect;  // each call's own ARect, in canvas coords
    FProbeCount: Integer;
    procedure HandleDrawItem(Sender: TObject; ACanvas: TCanvas; ARect: TRect;
      AState: TOwnerDrawState);
    procedure HandleMeasureItem(Sender: TObject; ACanvas: TCanvas;
      var AWidth, AHeight: Integer);
    { OnDrawItem: ask for the SAME pen + ink on EVERY call -- the shape that catches a
      canvas whose cached state no longer describes its DC. Strokes the row's own edge
      pixels and records the rect it was handed. }
    procedure HandleDrawItemSameStateEveryCall(Sender: TObject; ACanvas: TCanvas;
      ARect: TRect; AState: TOwnerDrawState);
    { Three plain rows on FMenu; returns the middle one. }
    function ThreeRows: TMenuItem;
  published
    procedure TestOwnerDrawPaintsTheRowAndSuppressesTheDefaultContent;
    procedure TestNothingHappensWhileOwnerDrawIsOff;
    procedure TestMenuLevelHandlerCoversItemsWithoutOne;
    procedure TestDrawRectIsTheRowAndStateReportsSelected;
    procedure TestStateReportsDisabledAndCheckedAndDefault;
    procedure TestMeasureItemSetsTheRowHeight;
    procedure TestMeasuredRowsStillHitTestWhereTheyPaint;
    procedure TestMeasureItemIgnoredWhileOwnerDrawIsOff;
    procedure TestMeasureItemIsAskedOncePerRow;
    procedure TestOwnerDrawReachesTheRendererView;
    procedure TestOwnerDrawReachesAMenuBarDropdown;
    { EVERY owner-drawn row inks with what its handler asked for -- not with what the
      previous row left in the DC. The view brackets each callback in a DC save/restore;
      if that restore is not one the LCL canvas knows about, the canvas keeps believing
      its Pen/Font are still selected and a handler that re-assigns the SAME value draws
      with the restored (foreign) object instead. Renders an icon row alongside, so both
      post-EndPaint GDI passes are live on the one popup. }
    procedure TestOwnerDrawStateSurvivesEveryRow;
  end;

implementation

const
  { Paint canvas. Wide enough that the caption never reaches the icon slot. }
  ViewW = 220;
  ViewH = 120;

{ ---- ink probes ---------------------------------------------------------- }

function IsGreenInk(const P: TBGRAPixel): Boolean;
begin
  Result := (P.green > 100) and (P.green > P.red + 40) and (P.green > P.blue + 40);
end;

function IsRedInk(const P: TBGRAPixel): Boolean;
begin
  Result := (P.red > 100) and (P.red > P.green + 40) and (P.red > P.blue + 40);
end;

function IsBlueInk(const P: TBGRAPixel): Boolean;
begin
  Result := (P.blue > 100) and (P.blue > P.red + 40) and (P.blue > P.green + 40);
end;

{ A one-image LCL list holding an opaque square of ASize px in AColor. Built through BGRA
  so the alpha channel is genuinely opaque -- a GDI-filled pf32bit TBitmap can arrive with
  alpha 0 and vanish when the image list composites it. }
function MakeImageList(ASize: Integer; const AColor: TBGRAPixel): TCustomImageList;
var
  Src: TBGRABitmap;
begin
  Result := TImageList.Create(nil);
  Result.Width := ASize;
  Result.Height := ASize;
  Src := TBGRABitmap.Create(ASize, ASize, AColor);
  try
    Result.Add(Src.Bitmap, nil);
  finally
    Src.Free;
  end;
end;

{ White pixels inside a horizontal band, left of AMaxX. The popup surface is black and
  the row text is white, so this counts CAPTION ink -- i.e. default row content that an
  owner-draw handler was supposed to have replaced. }
function CountCaptionInkInBand(ABmp: TBGRABitmap; ATop, ABottom, AMaxX: Integer): Integer;
var
  x, y: Integer;
  P: TBGRAPixel;
begin
  Result := 0;
  for y := Max(0, ATop) to Min(ABmp.Height - 1, ABottom - 1) do
    for x := 0 to Min(ABmp.Width, AMaxX) - 1 do
    begin
      P := ABmp.GetPixel(x, y);
      if (P.red > 200) and (P.green > 200) and (P.blue > 200) then Inc(Result);
    end;
end;

function CountInk(ABmp: TBGRABitmap; AProbe: Integer): Integer;
var
  x, y: Integer;
  hit: Boolean;
begin
  Result := 0;
  for y := 0 to ABmp.Height - 1 do
    for x := 0 to ABmp.Width - 1 do
    begin
      case AProbe of
        0: hit := IsGreenInk(ABmp.GetPixel(x, y));
        2: hit := IsBlueInk(ABmp.GetPixel(x, y));
      else
        hit := IsRedInk(ABmp.GetPixel(x, y));
      end;
      if hit then Inc(Result);
    end;
end;

{ ---- TMenuViewProbe ------------------------------------------------------ }

procedure TMenuViewProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

function TMenuViewProbe.RowTop(AIndex, APPI: Integer): Integer;
begin
  Result := inherited RowTop(AIndex, APPI);
end;

function TMenuViewProbe.RowHeight(AIndex, APPI: Integer): Integer;
begin
  Result := inherited RowHeight(AIndex, APPI);
end;

function TMenuViewProbe.RowAtY(AY, APPI: Integer): Integer;
begin
  Result := inherited RowAtY(AY, APPI);
end;

function TMenuViewProbe.MeasureHeight(APPI: Integer): Integer;
begin
  Result := inherited MeasureHeight(APPI);
end;

function TMenuViewProbe.MeasureWidth(APPI: Integer): Integer;
begin
  Result := inherited MeasureWidth(APPI);
end;

procedure TMenuViewProbe.SetHighlight(AIndex: Integer);
begin
  inherited SetHighlight(AIndex);
end;

procedure TMenuViewProbe.SimulateMouseUp(AButton: TMouseButton; AY: Integer);
begin
  MouseUp(AButton, [], 4, AY);
end;

{ ---- TMenuParityFixture -------------------------------------------------- }

procedure TMenuParityFixture.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  // Black popup plate, transparent rows, white text: any coloured pixel in the render
  // came from an icon or from an owner-draw handler, never from the chrome.
  FCtl.LoadThemeCss(
    'TyMenuView { background: #000000; color: #FFFFFF; padding: 4px; '
    + 'border-width: 0px; border-radius: 0px; }'
    + 'TyMenuPopup { background: #000000; border-radius: 0px; }'
    + 'TyMenuItem { background: alpha(#FFFFFF, 0); color: #FFFFFF; '
    + 'border-color: #FFFFFF; border-radius: 0px; padding: 4px; font-size: 12px; }');
  FMenu := TPopupMenu.Create(nil);
  FView := TMenuViewProbe.Create(nil);
  FView.Controller := FCtl;
  FView.Font.PixelsPerInch := 96;   // Scale() 1:1, so logical px == device px
end;

procedure TMenuParityFixture.TearDown;
begin
  FreeAndNil(FView);
  FreeAndNil(FMenu);
  FreeAndNil(FCtl);
end;

function TMenuParityFixture.Render(AWidth, AHeight: Integer): TBGRABitmap;
var
  Bmp: TBitmap;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(AWidth, AHeight);
    // Pre-fill white: neither probe matches white, so a blank render reads as "no ink".
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, AWidth, AHeight);
    FView.RenderTo(Bmp.Canvas, Rect(0, 0, AWidth, AHeight), 96);
    Result := TBGRABitmap.Create(Bmp);
  finally
    Bmp.Free;
  end;
end;

{ ---- TMenuGlyphShowModeTest ---------------------------------------------- }

procedure TMenuGlyphShowModeTest.SetUp;
var
  Master: TBGRABitmap;
begin
  inherited SetUp;
  FColl := TTyImageCollection.Create(FView);
  FImages := TTyVirtualImageList.Create(FView);
  FImages.Collection := FColl;
  FImages.Names.Text := 'ico';
  // A fully opaque GREEN square: the icon draws as a solid block of known colour, so
  // "was the glyph painted" is a pixel question, not a property question.
  Master := TBGRABitmap.Create(16, 16, BGRA(0, 255, 0, 255));
  try
    FColl.AddBitmap('ico', Master);
  finally
    Master.Free;
  end;
  FView.Images := FImages;
end;

function TMenuGlyphShowModeTest.RenderItemWithMode(AMode: TGlyphShowMode): TBGRABitmap;
var
  it: TMenuItem;
begin
  FMenu.Items.Clear;
  it := TMenuItem.Create(FMenu);
  it.Caption := 'Save';
  it.ImageIndex := 0;
  it.GlyphShowMode := AMode;
  FMenu.Items.Add(it);
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  Result := Render(ViewW, ViewH);
end;

procedure TMenuGlyphShowModeTest.TestAlwaysDrawsTheIcon;
var
  Img: TBGRABitmap;
begin
  Img := RenderItemWithMode(gsmAlways);
  try
    AssertTrue('gsmAlways must paint the item icon', CountInk(Img, 0) > 20);
  finally
    Img.Free;
  end;
end;

procedure TMenuGlyphShowModeTest.TestNeverDrawsNoIcon;
var
  Img: TBGRABitmap;
begin
  // The whole point of gsmNever: this item opts out of the icon column while its
  // siblings keep theirs. Drawing it anyway makes the setting a decoration.
  Img := RenderItemWithMode(gsmNever);
  try
    AssertEquals('gsmNever must paint no icon at all', 0, CountInk(Img, 0));
  finally
    Img.Free;
  end;
end;

procedure TMenuGlyphShowModeTest.TestGlyphVisibleFollowsTheModeAndTheApplication;
var
  it: TMenuItem;
  saved: TApplicationShowGlyphs;
  viaApp: Boolean;
begin
  it := TMenuItem.Create(FMenu);
  it.Caption := 'Save';
  FMenu.Items.Add(it);
  saved := Application.ShowMenuGlyphs;   // global; every branch below restores it
  try
    it.GlyphShowMode := gsmAlways;
    Application.ShowMenuGlyphs := sbgNever;
    AssertTrue('gsmAlways overrides the application setting', TyMenuGlyphVisible(it));

    it.GlyphShowMode := gsmNever;
    Application.ShowMenuGlyphs := sbgAlways;
    AssertFalse('gsmNever overrides the application setting', TyMenuGlyphVisible(it));

    // gsmApplication is the TMenuItem DEFAULT, so this branch is what most menus take.
    it.GlyphShowMode := gsmApplication;
    Application.ShowMenuGlyphs := sbgAlways;
    AssertTrue('gsmApplication + sbgAlways shows', TyMenuGlyphVisible(it));
    Application.ShowMenuGlyphs := sbgNever;
    AssertFalse('gsmApplication + sbgNever hides -- one app-wide switch, every menu',
      TyMenuGlyphVisible(it));

    { The two system-driven paths must agree: whatever the desktop says, gsmSystem and
      gsmApplication-with-sbgSystem are the same question. Asserting the OS value itself
      would only pin this machine. }
    Application.ShowMenuGlyphs := sbgSystem;
    it.GlyphShowMode := gsmApplication;
    viaApp := TyMenuGlyphVisible(it);
    it.GlyphShowMode := gsmSystem;
    AssertEquals('gsmSystem and gsmApplication+sbgSystem ask the same thing',
      viaApp, TyMenuGlyphVisible(it));
  finally
    Application.ShowMenuGlyphs := saved;
  end;
  AssertFalse('a nil item has no glyph (and must not crash)', TyMenuGlyphVisible(nil));
end;

procedure TMenuGlyphShowModeTest.TestBuildRowsCarriesGlyphVisible;
var
  a, b: TMenuItem;
  rows: TTyMenuRowArray;
begin
  // Per ITEM, not per menu: one row opting out must not take the others with it.
  a := TMenuItem.Create(FMenu); a.Caption := 'Shown';  a.GlyphShowMode := gsmAlways;
  FMenu.Items.Add(a);
  b := TMenuItem.Create(FMenu); b.Caption := 'Hidden'; b.GlyphShowMode := gsmNever;
  FMenu.Items.Add(b);
  rows := TyBuildMenuRows(FMenu.Items);
  AssertTrue ('gsmAlways row carries GlyphVisible', rows[0].GlyphVisible);
  AssertFalse('gsmNever row does not', rows[1].GlyphVisible);
end;

{ ---- TMenuSubMenuImagesTest ---------------------------------------------- }

procedure TMenuSubMenuImagesTest.SetUp;
var
  Master: TBGRABitmap;
  leaf: TMenuItem;
begin
  inherited SetUp;
  FList := MakeImageList(16, BGRA(255, 0, 0, 255));   // RED
  FWide := MakeImageList(48, BGRA(255, 0, 0, 255));   // RED, three times the check slot

  // The library's own icon column, in GREEN, so a precedence clash is separable.
  FColl := TTyImageCollection.Create(FView);
  FTyImages := TTyVirtualImageList.Create(FView);
  FTyImages.Collection := FColl;
  FTyImages.Names.Text := 'ico';
  Master := TBGRABitmap.Create(16, 16, BGRA(0, 255, 0, 255));
  try
    FColl.AddBitmap('ico', Master);
  finally
    Master.Free;
  end;

  FSub := TMenuItem.Create(FMenu);
  FSub.Caption := 'Recent';
  FMenu.Items.Add(FSub);
  leaf := TMenuItem.Create(FMenu);
  leaf.Caption := 'doc.txt';
  leaf.ImageIndex := 0;
  FSub.Add(leaf);
end;

procedure TMenuSubMenuImagesTest.TearDown;
begin
  FreeAndNil(FList);
  FreeAndNil(FWide);
  inherited TearDown;
end;

procedure TMenuSubMenuImagesTest.TestSubMenuImagesDrawsTheSubmenuIcon;
var
  Img: TBGRABitmap;
begin
  // Without it the cascade inherits whatever the level above had, so a submenu could
  // never carry its own icon set -- which is the only thing SubMenuImages is for.
  FSub.SubMenuImages := FList;
  FView.SetRows(TyBuildMenuRows(FSub));
  Img := Render(ViewW, ViewH);
  try
    AssertTrue('a submenu row draws from its parent item''s SubMenuImages',
      CountInk(Img, 1) > 20);
  finally
    Img.Free;
  end;
end;

procedure TMenuSubMenuImagesTest.TestNearestAncestorWins;
var
  rows: TTyMenuRowArray;
  other: TCustomImageList;
begin
  { LCL's rule (TMenuItem.GetImageList): walk up for the NEAREST SubMenuImages, and only
    when there is none fall back to the menu's own Images. A per-submenu override that the
    top level's list could outrank would be no override at all. }
  other := MakeImageList(16, BGRA(0, 0, 255, 255));
  try
    FMenu.Images := other;            // the menu-wide fallback
    rows := TyBuildMenuRows(FMenu.Items);
    AssertSame('with no SubMenuImages anywhere, the menu''s own Images is the source',
      other, rows[0].LCLImages);

    FSub.SubMenuImages := FList;      // ...now the submenu declares its own
    rows := TyBuildMenuRows(FSub);
    AssertSame('a submenu row prefers its parent item''s SubMenuImages',
      FList, rows[0].LCLImages);
    rows := TyBuildMenuRows(FMenu.Items);
    AssertSame('...and the level ABOVE keeps the menu-wide list', other, rows[0].LCLImages);
  finally
    FMenu.Images := nil;
    other.Free;
  end;
end;

procedure TMenuSubMenuImagesTest.TestBuildRowsCarriesTheResolvedListAndWidth;
var
  rows: TTyMenuRowArray;
begin
  FSub.SubMenuImages := FList;
  FSub.SubMenuImagesWidth := 24;      // the 96-PPI width the LCL contract asks for
  rows := TyBuildMenuRows(FSub);
  AssertSame  ('list carried onto the row', FList, rows[0].LCLImages);
  AssertEquals('width carried onto the row', 24, rows[0].LCLImagesWidth);

  { GetImageList leaves its width OUT parameter untouched on the nil path, so a row with
    no list at all must still report 0 rather than whatever was on the stack. }
  FSub.SubMenuImages := nil;
  rows := TyBuildMenuRows(FSub);
  AssertTrue  ('no list resolved', rows[0].LCLImages = nil);
  AssertEquals('and no stale width with it', 0, rows[0].LCLImagesWidth);
end;

procedure TMenuSubMenuImagesTest.TestSubMenuImagesBeatsTheLibraryIconColumn;
var
  Img: TBGRABitmap;
begin
  { Documented precedence: an explicitly resolved LCL list wins over the library's own
    TTyVirtualImageList, because SubMenuImages is a deliberate per-submenu statement.
    (They cannot collide from the designer: TTyImagesMenu.Images shadows TMenu.Images.) }
  FView.Images := FTyImages;          // GREEN
  FSub.SubMenuImages := FList;        // RED
  FView.SetRows(TyBuildMenuRows(FSub));
  Img := Render(ViewW, ViewH);
  try
    AssertTrue ('the submenu''s own list is what gets drawn', CountInk(Img, 1) > 20);
    AssertEquals('and the library icon column stands down', 0, CountInk(Img, 0));
  finally
    Img.Free;
  end;
end;

procedure TMenuSubMenuImagesTest.TestWideIconsWidenTheSlotAndTheRow;
var
  narrowW, narrowH, wideW, wideH: Integer;
begin
  { The themed --menu-check-slot is 18px and the row is text-height. A 48px image list
    would paint straight over the caption and be clipped top and bottom, so the theme
    value is the FLOOR: the icon's own size pushes both out. }
  FSub.SubMenuImages := FList;
  FView.SetRows(TyBuildMenuRows(FSub));
  narrowW := FView.MeasureWidth(96);
  narrowH := FView.MeasureHeight(96);

  FSub.SubMenuImages := FWide;
  FView.SetRows(TyBuildMenuRows(FSub));
  wideW := FView.MeasureWidth(96);
  wideH := FView.MeasureHeight(96);

  AssertEquals('a 48px icon widens the left slot by exactly the extra 30px it needs',
    narrowW + 30, wideW);
  AssertTrue('...and the row grows tall enough to hold it',
    (wideH >= 48) and (wideH > narrowH));
end;

procedure TMenuSubMenuImagesTest.TestDisabledRowGetsTheGreyedIcon;
var
  Img: TBGRABitmap;
begin
  { The 5th argument of TScaledImageListResolution.Draw is AEnabled, not "greyed" -- and
    the same call has a TGraphicsDrawEffect overload, so the inverted sense compiles
    cleanly and simply draws every icon the wrong way round. An enabled row keeps its
    colour; a disabled one is greyed, which is what "unavailable" has to look like. }
  FSub.SubMenuImages := FList;                  // RED
  FView.SetRows(TyBuildMenuRows(FSub));
  Img := Render(ViewW, ViewH);
  try
    AssertTrue('an enabled row keeps its icon''s colour', CountInk(Img, 1) > 20);
  finally
    Img.Free;
  end;

  FSub.Items[0].Enabled := False;
  FView.SetRows(TyBuildMenuRows(FSub));
  Img := Render(ViewW, ViewH);
  try
    AssertEquals('a disabled row''s icon is greyed, so no red survives',
      0, CountInk(Img, 1));
  finally
    Img.Free;
  end;
end;

{ ---- TMenuTrackButtonTest ------------------------------------------------ }

procedure TMenuTrackButtonTest.HandleActivate(Sender: TObject; AIndex: Integer);
begin
  FActivated := AIndex;
end;

procedure TMenuTrackButtonTest.OneRow;
var
  it: TMenuItem;
begin
  it := TMenuItem.Create(FMenu);
  it.Caption := 'Refresh';
  FMenu.Items.Add(it);
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  FView.OnActivateRow := @HandleActivate;
  FActivated := -1;
end;

procedure TMenuTrackButtonTest.TestRightButtonActivatesByDefault;
begin
  // tbRightButton is the LCL default and means what TPM_RIGHTBUTTON means on Win32:
  // BOTH buttons select. Press-right / drag / release-on-a-row is how a right-click
  // menu is normally driven, and it did nothing at all.
  OneRow;
  AssertEquals('the default is tbRightButton', Ord(tbRightButton), Ord(FView.TrackButton));
  AssertTrue('both buttons select under tbRightButton', FView.ActivatesOn(mbRight));
  FView.SimulateMouseUp(mbRight, FView.RowTop(0, 96) + 2);
  AssertEquals('the right button activates the row under it', 0, FActivated);
end;

procedure TMenuTrackButtonTest.TestLeftButtonOnlyUnderTbLeftButton;
begin
  // tbLeftButton is the narrower claim: left only. That is the whole content of the
  // property, so it has to actually turn the right button off.
  OneRow;
  FView.TrackButton := tbLeftButton;
  AssertTrue ('the left button always selects', FView.ActivatesOn(mbLeft));
  AssertFalse('the right button does not, under tbLeftButton', FView.ActivatesOn(mbRight));
  FView.SimulateMouseUp(mbRight, FView.RowTop(0, 96) + 2);
  AssertEquals('a right release must not activate anything', -1, FActivated);
  // ...while the left path (TControl.Click) is untouched by either setting.
  FView.SetHighlight(0);
  FView.Click;
  AssertEquals('the left button still activates', 0, FActivated);
end;

procedure TMenuTrackButtonTest.TestTrackButtonReachesTheRendererView;
var
  pm: TTyPopupMenu;
begin
  // The property lives on TPopupMenu and the decision lives in the view: pin the wiring
  // between them, not merely that the field was stored.
  pm := TTyPopupMenu.Create(nil);
  try
    pm.Controller := FCtl;
    AssertEquals('TTyPopupMenu starts at the LCL default',
      Ord(tbRightButton), Ord(pm.RendererForTest.ViewForTest.TrackButton));
    pm.TrackButton := tbLeftButton;
    AssertEquals('setting it on the menu reaches the view that reads it',
      Ord(tbLeftButton), Ord(pm.RendererForTest.ViewForTest.TrackButton));
  finally
    pm.Free;
  end;
end;

{ ---- TMenuOwnerDrawTest -------------------------------------------------- }

procedure TMenuOwnerDrawTest.HandleDrawItem(Sender: TObject; ACanvas: TCanvas;
  ARect: TRect; AState: TOwnerDrawState);
begin
  Inc(FDrawCalls);
  FLastState := AState;
  FLastRect := ARect;
  { A narrow GREEN marker at the row's right edge, NOT a full fill: the caption would
    be hidden under a full fill whether or not the default content was suppressed, so
    the left of the row is deliberately left for the white-ink probe to inspect. }
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := clLime;
  ACanvas.FillRect(Rect(ARect.Right - 12, ARect.Top, ARect.Right, ARect.Bottom));
end;

procedure TMenuOwnerDrawTest.HandleMeasureItem(Sender: TObject; ACanvas: TCanvas;
  var AWidth, AHeight: Integer);
begin
  Inc(FMeasureCalls);
  AHeight := FMeasureHeight;
end;

function TMenuOwnerDrawTest.ThreeRows: TMenuItem;
var
  i: Integer;
  it: TMenuItem;
begin
  Result := nil;
  for i := 0 to 2 do
  begin
    it := TMenuItem.Create(FMenu);
    it.Caption := 'Row' + IntToStr(i);
    FMenu.Items.Add(it);
    if i = 1 then Result := it;
  end;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
end;

procedure TMenuOwnerDrawTest.TestOwnerDrawPaintsTheRowAndSuppressesTheDefaultContent;
var
  mid: TMenuItem;
  Img: TBGRABitmap;
begin
  mid := ThreeRows;
  mid.OnDrawItem := @HandleDrawItem;
  FView.OwnerDraw := True;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));   // re-snapshot with the handler attached
  FDrawCalls := 0;
  Img := Render(ViewW, ViewH);
  try
    AssertEquals('the handler ran once, for the one row that has it', 1, FDrawCalls);
    AssertTrue('and its pixels are on the canvas', CountInk(Img, 0) > 50);
    // The row is the app's now: OUR caption must not still be under the handler's work.
    AssertEquals('the default row content is suppressed where the app draws', 0,
      CountCaptionInkInBand(Img, FView.RowTop(1, 96), FView.RowTop(1, 96)
        + FView.RowHeight(1, 96), ViewW - 12));
    // ...and only that row: a sibling without a handler keeps its ordinary caption.
    AssertTrue('a row with no handler is untouched',
      CountCaptionInkInBand(Img, FView.RowTop(0, 96), FView.RowTop(0, 96)
        + FView.RowHeight(0, 96), ViewW - 12) > 0);
  finally
    Img.Free;
  end;
end;

procedure TMenuOwnerDrawTest.TestNothingHappensWhileOwnerDrawIsOff;
var
  mid: TMenuItem;
  Img: TBGRABitmap;
begin
  // OwnerDraw is the gate. An OnDrawItem left on an item must not silently take over
  // the row -- that is what "default False" promises.
  mid := ThreeRows;
  mid.OnDrawItem := @HandleDrawItem;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  FDrawCalls := 0;
  Img := Render(ViewW, ViewH);
  try
    AssertEquals('OnDrawItem is not called while OwnerDraw is False', 0, FDrawCalls);
    AssertEquals('...and nothing of it is painted', 0, CountInk(Img, 0));
  finally
    Img.Free;
  end;
end;

procedure TMenuOwnerDrawTest.TestMenuLevelHandlerCoversItemsWithoutOne;
var
  Img: TBGRABitmap;
begin
  // TMenuItem.DoDrawItem falls back to the parent MENU's handler, which is how one
  // handler owner-draws a whole menu. Honouring only per-item handlers would leave
  // TMenu.OnDrawItem as the next dead property.
  ThreeRows;
  FMenu.OnDrawItem := @HandleDrawItem;   // on the menu, on no item
  FView.OwnerDraw := True;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  FDrawCalls := 0;
  Img := Render(ViewW, ViewH);
  try
    AssertEquals('one menu-level handler covers every row', 3, FDrawCalls);
    AssertTrue('and paints them', CountInk(Img, 0) > 50);
  finally
    Img.Free;
  end;
end;

procedure TMenuOwnerDrawTest.TestDrawRectIsTheRowAndStateReportsSelected;
var
  mid: TMenuItem;
  Img: TBGRABitmap;
begin
  mid := ThreeRows;
  mid.OnDrawItem := @HandleDrawItem;
  FView.OwnerDraw := True;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  FView.SetHighlight(1);
  Img := Render(ViewW, ViewH);
  try
    AssertEquals('the handler is given its own row''s top',
      FView.RowTop(1, 96), FLastRect.Top);
    AssertEquals('...and its own row''s height',
      FView.RowHeight(1, 96), FLastRect.Bottom - FLastRect.Top);
    AssertTrue('a highlighted row is reported odSelected', odSelected in FLastState);
    { The themed background goes down first so a handler that only writes text still
      lands on the right highlight -- and the handler has to be told, or it will paint
      one of its own over ours. }
    AssertTrue('and odBackgroundPainted says the background is already there',
      odBackgroundPainted in FLastState);
  finally
    Img.Free;
  end;
end;

procedure TMenuOwnerDrawTest.TestStateReportsDisabledAndCheckedAndDefault;
var
  mid: TMenuItem;
  Img: TBGRABitmap;
begin
  mid := ThreeRows;
  mid.OnDrawItem := @HandleDrawItem;
  mid.Enabled := False;
  mid.Checked := True;
  mid.Default := True;
  FView.OwnerDraw := True;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  Img := Render(ViewW, ViewH);
  try
    // Everything the default renderer would have expressed in pixels, handed over as flags.
    AssertTrue('disabled', odDisabled in FLastState);
    AssertTrue('greyed travels with disabled', odGrayed in FLastState);
    AssertTrue('checked', odChecked in FLastState);
    AssertTrue('default item', odDefault in FLastState);
    AssertFalse('a disabled row is never reported selected', odSelected in FLastState);
  finally
    Img.Free;
  end;
end;

procedure TMenuOwnerDrawTest.TestMeasureItemSetsTheRowHeight;
var
  defaultH: Integer;
begin
  ThreeRows;
  defaultH := FView.RowHeight(0, 96);
  FMenu.OnMeasureItem := @HandleMeasureItem;
  FMeasureHeight := defaultH + 25;
  FView.OwnerDraw := True;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  AssertEquals('OnMeasureItem decides the row height', defaultH + 25, FView.RowHeight(1, 96));
  AssertEquals('and the rows stack on the measured height, not the themed one',
    FView.RowTop(0, 96) + defaultH + 25, FView.RowTop(1, 96));
  AssertTrue('so the popup is measured tall enough to hold them',
    FView.MeasureHeight(96) >= 3 * (defaultH + 25));
end;

procedure TMenuOwnerDrawTest.TestMeasuredRowsStillHitTestWhereTheyPaint;
var
  defaultH: Integer;
begin
  // A menu that paints rows at one height and hit-tests them at another activates the
  // wrong command, which is worse than not honouring OnMeasureItem at all.
  ThreeRows;
  defaultH := FView.RowHeight(0, 96);
  FMenu.OnMeasureItem := @HandleMeasureItem;
  FMeasureHeight := defaultH + 25;
  FView.OwnerDraw := True;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  AssertEquals('top of row 2 hits row 2', 2, FView.RowAtY(FView.RowTop(2, 96), 96));
  AssertEquals('bottom of row 2 hits row 2',
    2, FView.RowAtY(FView.RowTop(2, 96) + defaultH + 24, 96));
  AssertEquals('one past it hits nothing',
    -1, FView.RowAtY(FView.RowTop(2, 96) + defaultH + 25, 96));
end;

procedure TMenuOwnerDrawTest.TestMeasureItemIgnoredWhileOwnerDrawIsOff;
var
  defaultH: Integer;
begin
  ThreeRows;
  defaultH := FView.RowHeight(0, 96);
  FMenu.OnMeasureItem := @HandleMeasureItem;
  FMeasureHeight := defaultH + 25;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  FMeasureCalls := 0;
  AssertEquals('the themed height stands while OwnerDraw is False',
    defaultH, FView.RowHeight(1, 96));
  AssertEquals('and the handler is never asked', 0, FMeasureCalls);
end;

procedure TMenuOwnerDrawTest.TestMeasureItemIsAskedOncePerRow;
begin
  { RowTop walks every earlier row, so an un-memoised measure would call the app's
    handler O(n^2) times per layout -- on every mouse move. }
  ThreeRows;
  FMenu.OnMeasureItem := @HandleMeasureItem;
  FMeasureHeight := 30;
  FView.OwnerDraw := True;
  FView.SetRows(TyBuildMenuRows(FMenu.Items));
  FMeasureCalls := 0;
  FView.MeasureHeight(96);
  FView.RowTop(2, 96);
  FView.RowAtY(50, 96);
  AssertEquals('three rows, three measure calls, however often geometry is asked',
    3, FMeasureCalls);
end;

procedure TMenuOwnerDrawTest.TestOwnerDrawReachesTheRendererView;
var
  pm: TTyPopupMenu;
begin
  pm := TTyPopupMenu.Create(nil);
  try
    pm.Controller := FCtl;
    AssertFalse('TTyPopupMenu starts at the LCL default (False)',
      pm.RendererForTest.ViewForTest.OwnerDraw);
    pm.OwnerDraw := True;
    AssertTrue('setting it on the menu reaches the view that reads it',
      pm.RendererForTest.ViewForTest.OwnerDraw);
  finally
    pm.Free;
  end;
end;

procedure TMenuOwnerDrawTest.TestOwnerDrawReachesAMenuBarDropdown;
var
  bar: TTyMenuBar;
  mm: TMainMenu;
  top, leaf: TMenuItem;
begin
  { A TMainMenu publishes the very same owner-draw protocol, and its dropdown is rendered
    by the very same view. Honouring it only in context menus would leave the property
    half-dead in the other half of the library. }
  mm := TMainMenu.Create(nil);
  bar := TTyMenuBar.Create(nil);
  try
    top := TMenuItem.Create(mm); top.Caption := 'File'; mm.Items.Add(top);
    leaf := TMenuItem.Create(mm); leaf.Caption := 'Open'; top.Add(leaf);
    mm.OwnerDraw := True;
    bar.Controller := FCtl;
    bar.Menu := mm;
    bar.OpenTopForTest(0);   // the single door into a top item (click / hover / Alt)
    AssertTrue('the bar built a dropdown host', bar.PopupForTest <> nil);
    AssertTrue('the main menu''s OwnerDraw reaches the dropdown''s view',
      bar.PopupForTest.ViewForTest.OwnerDraw);
  finally
    bar.Free;
    mm.Free;
  end;
end;

{ The shape that catches a canvas whose cached state no longer describes its DC: the SAME
  pen colour and the SAME ink on every call. An LCL TCanvas only re-selects an object when
  one of its properties actually CHANGES, so from the second row on nothing is re-selected
  and the stroke lands with whatever object the DC is currently holding.

  Brush + FillRect is deliberately NOT used -- LCL hands FillRect the brush handle
  explicitly, so it is the one primitive this defect cannot bite, and a guard written
  around it passes against the broken code. (TestOwnerDrawPaintsTheRowAndSuppressesThe-
  DefaultContent above is exactly that shape, which is why it never saw any of this.)

  The strokes run along the row's own top and bottom edges, never across it: the four
  corner pixels are what gets probed, because a probe in the middle of a row survives any
  drift that leaves SOME of the row green. }
procedure TMenuOwnerDrawTest.HandleDrawItemSameStateEveryCall(Sender: TObject;
  ACanvas: TCanvas; ARect: TRect; AState: TOwnerDrawState);
const
  Probe = TColor($00C800);   // GREEN, identical on every call
begin
  Inc(FDrawCalls);
  if FProbeCount = Length(FProbeRect) then
    SetLength(FProbeRect, Length(FProbeRect) + 8);
  FProbeRect[FProbeCount] := ARect;
  Inc(FProbeCount);

  ACanvas.Pen.Color   := Probe;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Font.Color  := Probe;

  { LineTo stops one short of its end point, so these two strokes cover exactly the four
    corners: (Left,Top), (Right-1,Top), (Left,Bottom-1) and (Right-1,Bottom-1). }
  ACanvas.MoveTo(ARect.Left, ARect.Top);
  ACanvas.LineTo(ARect.Right, ARect.Top);
  ACanvas.MoveTo(ARect.Left, ARect.Bottom - 1);
  ACanvas.LineTo(ARect.Right, ARect.Bottom - 1);

  { The same question asked of the text path, which is what an owner-drawn caption
    actually rides on: after a text op the DC must hold the ink we asked for. LCL sets
    the DC's text colour inside the FONT selection, so a cached-valid font means
    SetTextColor is never reached and the ink is whatever the restore put back. }
  ACanvas.TextOut(ARect.Left + 2, ARect.Top + 2, 'x');
  if LCLIntf.GetTextColor(ACanvas.Handle) <> Probe then Inc(FStaleInkRows);
end;

{ Every owner-drawn row must ink with what ITS handler asked for. The view brackets each
  callback in a DC save/restore so one handler cannot leak its clip into the next; the
  restore has to be one the LCL canvas knows about, or the canvas goes on believing its
  Pen/Font are still selected into the DC while the restore has swapped them out -- and
  the second row onwards paints with the previous DC state instead of the app's.

  Non-vacuous by construction: the canvas's pen and ink are seeded RED and driven into the
  DC first, so a row that skips the re-select strokes red, not green.

  An icon row rides along on the same popup. Unlike the tree -- where an owner-drawn cell
  can never also collect an icon -- the menu's owner-draw gate is PER ITEM, so a row with
  no OnDrawItem keeps its ordinary icon and both post-EndPaint GDI passes are live at
  once. This is the case that makes the icon pass a neighbour of the callback pass. }
procedure TMenuOwnerDrawTest.TestOwnerDrawStateSurvivesEveryRow;
const
  SeedRed  = TColor($0000DC);   // BGR literal: pure red
  CanvasH  = 240;
var
  i, k, xr: Integer;
  it: TMenuItem;
  list: TCustomImageList;
  Bmp: TBitmap;
  Img: TBGRABitmap;
  R: TRect;

  procedure AssertGreenAt(const AWhere: string; x, y: Integer);
  var P: TBGRAPixel;
  begin
    P := Img.GetPixel(x, y);
    AssertTrue(Format('%s at (%d,%d) drew with the DC''s pen, not the handler''s ' +
      '(got R%d G%d B%d, seeded red)', [AWhere, x, y, P.red, P.green, P.blue]),
      (P.green > 160) and (P.red < 96) and (P.blue < 96));
  end;

begin
  { Rows 0-1 carry an LCL icon and NO handler; rows 2-4 are owner-drawn. Three callbacks
    is the point -- the defect starts at the second one. }
  list := MakeImageList(16, BGRA(0, 0, 255, 255));   // BLUE, distinct from seed and probe
  Bmp := TBitmap.Create;
  try
    FMenu.Images := list;
    for i := 0 to 4 do
    begin
      it := TMenuItem.Create(FMenu);
      it.Caption := 'Row' + IntToStr(i);
      if i < 2 then it.ImageIndex := 0
      else it.OnDrawItem := @HandleDrawItemSameStateEveryCall;
      FMenu.Items.Add(it);
    end;
    FView.OwnerDraw := True;
    FView.SetRows(TyBuildMenuRows(FMenu.Items));
    FDrawCalls := 0; FProbeCount := 0; FStaleInkRows := 0;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(ViewW, CanvasH);
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, ViewW, CanvasH);
    { Seed the canvas's PEN and INK red and drive BOTH into the DC, so "whatever the DC is
      currently holding" is a colour the handler never asks for. Off-surface, so the seed
      strokes themselves cannot be mistaken for a probe. }
    Bmp.Canvas.Pen.Color  := SeedRed;
    Bmp.Canvas.Font.Color := SeedRed;
    Bmp.Canvas.MoveTo(-8, -8);
    Bmp.Canvas.LineTo(-4, -8);
    Bmp.Canvas.TextOut(-40, -40, 'x');

    FView.RenderTo(Bmp.Canvas, Rect(0, 0, ViewW, CanvasH), 96);
    Img := TBGRABitmap.Create(Bmp);
    try
      AssertEquals('three rows were owner-drawn', 3, FDrawCalls);
      AssertTrue('...and the icon rows kept their own pass alive on the same popup',
        CountInk(Img, 2) > 50);

      for k := 0 to FProbeCount - 1 do
      begin
        R := FProbeRect[k];
        xr := Min(R.Right - 1, ViewW - 1);
        AssertTrue('the probed row has room to stroke', (R.Left < xr) and (R.Bottom - R.Top >= 4));
        AssertGreenAt(Format('row %d: top-left', [k]),     R.Left, R.Top);
        AssertGreenAt(Format('row %d: top-right', [k]),    xr,     R.Top);
        AssertGreenAt(Format('row %d: bottom-left', [k]),  R.Left, R.Bottom - 1);
        AssertGreenAt(Format('row %d: bottom-right', [k]), xr,     R.Bottom - 1);
      end;
      AssertEquals('every row inked with the colour its handler set', 0, FStaleInkRows);
    finally
      Img.Free;
    end;
  finally
    FMenu.Images := nil;
    Bmp.Free;
    list.Free;
  end;
end;

initialization
  RegisterTest(TMenuGlyphShowModeTest);
  RegisterTest(TMenuSubMenuImagesTest);
  RegisterTest(TMenuTrackButtonTest);
  RegisterTest(TMenuOwnerDrawTest);
end.
