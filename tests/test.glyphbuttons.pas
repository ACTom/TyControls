unit test.glyphbuttons;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, fpcunit, testregistry, Forms, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Types, tyControls.Button, tyControls.IconFont,
  tyControls.GlyphButtons;
type
  { Exposes the protected RenderTo so the glyph paint path is exercisable headlessly. }
  TGlyphButtonAccess = class(TTyGlyphButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TContainerButtonAccess = class(TTyGlyphContainerButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TGlyphButtonTest = class(TTestCase)
  published
    procedure TestTypeKeys;
    procedure TestDefaultSizes;
    procedure TestGlyphDefaults;
    procedure TestPropertiesRoundTrip;
    procedure TestIconFontFreeNotification;
    procedure TestSplitGlyphLeft;
    procedure TestSplitGlyphTop;
    procedure TestSplitNoGlyph;
    procedure TestSplitOversizedGlyphClamps;
    procedure TestPaintWithGlyphSafe;
    procedure TestPaintContainerSafe;
    procedure TestPaintNoFontSafe;
  end;

  TSpeedButtonTest = class(TTestCase)
  published
    procedure TestDefaults;
    procedure TestGroupingRadioBehaviour;
    procedure TestAllowAllUpToggle;
    procedure TestUngroupedClickJustFires;
    procedure TestDisabledClickNoChange;
  end;
implementation

procedure TGlyphButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TContainerButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ ---- TGlyphButtonTest ---- }

procedure TGlyphButtonTest.TestTypeKeys;
var
  B: TTyGlyphButton;
  C: TTyGlyphContainerButton;
  S: TTySpeedButton;
begin
  // The plain glyph button IS a push button and stays on TyButton. The ribbon tile
  // and the toolbar toggle need a different FRAME from a push button, so each owns
  // a key a skin can target without touching every button in the app.
  B := TTyGlyphButton.Create(nil);
  C := TTyGlyphContainerButton.Create(nil);
  S := TTySpeedButton.Create(nil);
  try
    AssertEquals('glyph button reuses TyButton', 'TyButton', (B as ITyStyleable).GetStyleTypeKey);
    AssertEquals('container button owns its key', 'TyGlyphContainerButton', (C as ITyStyleable).GetStyleTypeKey);
    AssertEquals('speed button owns its key', 'TySpeedButton', (S as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free; C.Free; S.Free;
  end;
end;

procedure TGlyphButtonTest.TestDefaultSizes;
var
  B: TTyGlyphButton;
  C: TTyGlyphContainerButton;
begin
  B := TTyGlyphButton.Create(nil);
  C := TTyGlyphContainerButton.Create(nil);
  try
    AssertEquals('glyph button default width', 96, B.Width);
    AssertEquals('glyph button default height', 30, B.Height);
    AssertEquals('container button default width', 72, C.Width);
    AssertEquals('container button default height', 64, C.Height);
    // The container ships a larger default glyph than plain auto-fit.
    AssertEquals('container default GlyphSize', 24, C.GlyphSize);
  finally
    B.Free; C.Free;
  end;
end;

procedure TGlyphButtonTest.TestGlyphDefaults;
var
  B: TTyGlyphButton;
begin
  B := TTyGlyphButton.Create(nil);
  try
    AssertEquals('GlyphSize default 0 (auto)', 0, B.GlyphSize);
    AssertTrue('GlyphColor default is the theme sentinel',
      B.GlyphColor = TyGlyphButtonColorDefault);
    AssertEquals('GlyphName default empty', '', B.GlyphName);
    AssertTrue('IconFont default nil', B.IconFont = nil);
    AssertTrue('glyph props published', IsPublishedProp(B, 'IconFont')
      and IsPublishedProp(B, 'GlyphName') and IsPublishedProp(B, 'GlyphSize')
      and IsPublishedProp(B, 'GlyphColor'));
  finally
    B.Free;
  end;
end;

procedure TGlyphButtonTest.TestPropertiesRoundTrip;
var
  B: TTyGlyphButton;
  Font: TTyIconFont;
begin
  B := TTyGlyphButton.Create(nil);
  Font := TTyIconFont.Create(nil);
  try
    Font.MapGlyph('save', $F0C7);
    // Assigning IconFont + GlyphName must not raise.
    B.IconFont := Font;
    B.GlyphName := 'save';
    B.GlyphSize := 20;
    B.GlyphColor := TyRGB(200, 40, 40);
    AssertSame('IconFont round-trips', Font, B.IconFont);
    AssertEquals('GlyphName round-trips', 'save', B.GlyphName);
    AssertEquals('GlyphSize round-trips', 20, B.GlyphSize);
    AssertTrue('GlyphColor round-trips', B.GlyphColor = TyRGB(200, 40, 40));
    // Negative GlyphSize clamps to 0 (auto), never a bad size.
    B.GlyphSize := -3;
    AssertEquals('negative GlyphSize clamps to 0', 0, B.GlyphSize);
  finally
    Font.Free;
    B.Free;
  end;
end;

procedure TGlyphButtonTest.TestIconFontFreeNotification;
var
  B: TTyGlyphButton;
  Font: TTyIconFont;
begin
  B := TTyGlyphButton.Create(nil);
  Font := TTyIconFont.Create(nil);
  try
    B.IconFont := Font;
    AssertSame('IconFont assigned', Font, B.IconFont);
    // Freeing the referenced font must nil the reference (FreeNotification).
    Font.Free;
    Font := nil;
    AssertTrue('IconFont nilled after the font is freed', B.IconFont = nil);
  finally
    Font.Free;   // no-op when already freed/nil
    B.Free;
  end;
end;

procedure TGlyphButtonTest.TestSplitGlyphLeft;
var
  g, c: TRect;
begin
  // Content rect 100x40, glyph 20px, gap 6px, glyph-left.
  // Glyph: 20x20 square at left, vertically centered -> top = (40-20)/2 = 10.
  // Caption: from glyph.Right(20) + gap(6) = 26 to 100.
  TyGlyphButtonSplit(Rect(0, 0, 100, 40), 20, 6, glLeft, g, c);
  AssertEquals('glyph-left glyph.Left', 0, g.Left);
  AssertEquals('glyph-left glyph.Top', 10, g.Top);
  AssertEquals('glyph-left glyph.Right', 20, g.Right);
  AssertEquals('glyph-left glyph.Bottom', 30, g.Bottom);
  AssertEquals('glyph-left caption.Left', 26, c.Left);
  AssertEquals('glyph-left caption.Top', 0, c.Top);
  AssertEquals('glyph-left caption.Right', 100, c.Right);
  AssertEquals('glyph-left caption.Bottom', 40, c.Bottom);
end;

procedure TGlyphButtonTest.TestSplitGlyphTop;
var
  g, c: TRect;
begin
  // Content rect 60x64, glyph 24px, gap 6px, glyph-top.
  // Glyph: 24x24 square at top, horizontally centered -> left = (60-24)/2 = 18.
  // Caption: from glyph.Bottom(24) + gap(6) = 30 to 64.
  TyGlyphButtonSplit(Rect(0, 0, 60, 64), 24, 6, glTop, g, c);
  AssertEquals('glyph-top glyph.Left', 18, g.Left);
  AssertEquals('glyph-top glyph.Top', 0, g.Top);
  AssertEquals('glyph-top glyph.Right', 42, g.Right);
  AssertEquals('glyph-top glyph.Bottom', 24, g.Bottom);
  AssertEquals('glyph-top caption.Left', 0, c.Left);
  AssertEquals('glyph-top caption.Top', 30, c.Top);
  AssertEquals('glyph-top caption.Right', 60, c.Right);
  AssertEquals('glyph-top caption.Bottom', 64, c.Bottom);
end;

procedure TGlyphButtonTest.TestSplitNoGlyph;
var
  g, c: TRect;
begin
  // Glyph px <= 0 -> empty glyph rect, caption keeps the whole content rect.
  TyGlyphButtonSplit(Rect(5, 7, 105, 47), 0, 6, glLeft, g, c);
  AssertEquals('no-glyph glyph rect is empty (w)', 0, g.Right - g.Left);
  AssertEquals('no-glyph glyph rect is empty (h)', 0, g.Bottom - g.Top);
  AssertEquals('no-glyph caption.Left', 5, c.Left);
  AssertEquals('no-glyph caption.Top', 7, c.Top);
  AssertEquals('no-glyph caption.Right', 105, c.Right);
  AssertEquals('no-glyph caption.Bottom', 47, c.Bottom);
end;

procedure TGlyphButtonTest.TestSplitOversizedGlyphClamps;
var
  g, c: TRect;
begin
  // Glyph wider than the box (glyph-left): clamped to the box width, and the
  // caption collapses to zero width rather than inverting.
  TyGlyphButtonSplit(Rect(0, 0, 30, 20), 50, 6, glLeft, g, c);
  AssertEquals('oversized glyph clamps to box width', 30, g.Right - g.Left);
  AssertTrue('caption never has negative width', c.Right >= c.Left);
  // Glyph taller than the box (glyph-top): clamped to the box height.
  TyGlyphButtonSplit(Rect(0, 0, 40, 18), 50, 6, glTop, g, c);
  AssertEquals('oversized glyph clamps to box height', 18, g.Bottom - g.Top);
  AssertTrue('caption never has negative height', c.Bottom >= c.Top);
end;

procedure TGlyphButtonTest.TestPaintWithGlyphSafe;
var
  B: TGlyphButtonAccess;
  Font: TTyIconFont;
  Bmp: TBitmap;
begin
  // Full glyph-left paint path with a mapped glyph. No real font family is
  // registered, so RenderGlyph yields an empty transparent bitmap — the composite
  // must still be safe (real glyph pixels need an installed font + a machine).
  B := TGlyphButtonAccess.Create(nil);
  Font := TTyIconFont.Create(nil);
  Bmp := TBitmap.Create;
  try
    Font.MapGlyph('save', $F0C7);
    B.IconFont := Font;
    B.GlyphName := 'save';
    B.Caption := 'Save';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(96, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 96, 30), 96);
    AssertTrue('glyph-left RenderTo executed without exception', True);

    // Explicit GlyphSize path must also be safe.
    B.GlyphSize := 16;
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 96, 30), 96);
    AssertTrue('explicit GlyphSize RenderTo executed without exception', True);

    // Pure-icon (empty caption) must also be safe.
    B.Caption := '';
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 96, 30), 96);
    AssertTrue('empty-caption RenderTo executed without exception', True);
  finally
    Bmp.Free;
    Font.Free;
    B.Free;
  end;
end;

procedure TGlyphButtonTest.TestPaintContainerSafe;
var
  C: TContainerButtonAccess;
  Font: TTyIconFont;
  Bmp: TBitmap;
begin
  // Full glyph-top paint path.
  C := TContainerButtonAccess.Create(nil);
  Font := TTyIconFont.Create(nil);
  Bmp := TBitmap.Create;
  try
    Font.MapGlyph('save', $F0C7);
    C.IconFont := Font;
    C.GlyphName := 'save';
    C.Caption := 'Save';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(72, 64);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 72, 64), 96);
    AssertTrue('glyph-top RenderTo executed without exception', True);
  finally
    Bmp.Free;
    Font.Free;
    C.Free;
  end;
end;

procedure TGlyphButtonTest.TestPaintNoFontSafe;
var
  B: TGlyphButtonAccess;
  Bmp: TBitmap;
begin
  // No IconFont, non-empty GlyphName: must fall back to a plain caption button and
  // never crash — the glyph plumbing degrades cleanly.
  B := TGlyphButtonAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    B.GlyphName := 'save';   // set, but no font assigned
    B.Caption := 'Save';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(96, 30);
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 96, 30), 96);
    AssertTrue('no-font RenderTo is a safe caption-only paint', True);
  finally
    Bmp.Free;
    B.Free;
  end;
end;

{ ---- TSpeedButtonTest ---- }

procedure TSpeedButtonTest.TestDefaults;
var
  S: TTySpeedButton;
begin
  S := TTySpeedButton.Create(nil);
  try
    AssertEquals('GroupIndex default 0', 0, S.GroupIndex);
    AssertFalse('AllowAllUp default False', S.AllowAllUp);
    AssertFalse('Down default False', S.Down);
    AssertTrue('grouping props published',
      IsPublishedProp(S, 'GroupIndex') and IsPublishedProp(S, 'AllowAllUp'));
  finally
    S.Free;
  end;
end;

procedure TSpeedButtonTest.TestGroupingRadioBehaviour;
var
  F: TCustomForm;
  A, B, C: TTySpeedButton;
begin
  // Three grouped speed buttons: clicking one presses it and releases the others.
  F := TCustomForm.CreateNew(nil);
  try
    A := TTySpeedButton.Create(F); A.Parent := F; A.GroupIndex := 1;
    B := TTySpeedButton.Create(F); B.Parent := F; B.GroupIndex := 1;
    C := TTySpeedButton.Create(F); C.Parent := F; C.GroupIndex := 1;

    A.Click;
    AssertTrue('A down after clicking A', A.Down);
    AssertFalse('B up after clicking A', B.Down);
    AssertFalse('C up after clicking A', C.Down);

    B.Click;
    AssertFalse('A up after clicking B', A.Down);
    AssertTrue('B down after clicking B', B.Down);
    AssertFalse('C up after clicking B', C.Down);

    // Radio (AllowAllUp False): clicking the already-down button keeps it down.
    B.Click;
    AssertTrue('radio: re-clicking the down button keeps it down', B.Down);
  finally
    F.Free;
  end;
end;

procedure TSpeedButtonTest.TestAllowAllUpToggle;
var
  F: TCustomForm;
  A, B: TTySpeedButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    A := TTySpeedButton.Create(F); A.Parent := F; A.GroupIndex := 2; A.AllowAllUp := True;
    B := TTySpeedButton.Create(F); B.Parent := F; B.GroupIndex := 2; B.AllowAllUp := True;

    A.Click;
    AssertTrue('A down after first click', A.Down);
    // AllowAllUp: clicking the down button toggles it back up -> whole group up.
    A.Click;
    AssertFalse('AllowAllUp: re-clicking toggles A back up', A.Down);
    AssertFalse('B still up', B.Down);

    // And it still radios against the sibling.
    A.Click;
    B.Click;
    AssertFalse('A released when B pressed', A.Down);
    AssertTrue('B down', B.Down);
  finally
    F.Free;
  end;
end;

procedure TSpeedButtonTest.TestUngroupedClickJustFires;
var
  F: TCustomForm;
  A, B: TTySpeedButton;
begin
  // GroupIndex = 0 (default): Click does not touch Down or siblings.
  F := TCustomForm.CreateNew(nil);
  try
    A := TTySpeedButton.Create(F); A.Parent := F;   // GroupIndex 0
    B := TTySpeedButton.Create(F); B.Parent := F; B.Down := True;
    A.Click;
    AssertFalse('ungrouped click leaves A up', A.Down);
    AssertTrue('ungrouped click does not release an unrelated down button', B.Down);
  finally
    F.Free;
  end;
end;

procedure TSpeedButtonTest.TestDisabledClickNoChange;
var
  F: TCustomForm;
  A, B: TTySpeedButton;
begin
  // A disabled grouped button's Click is a no-op (no press, no sibling release).
  F := TCustomForm.CreateNew(nil);
  try
    A := TTySpeedButton.Create(F); A.Parent := F; A.GroupIndex := 3; A.Down := True;
    B := TTySpeedButton.Create(F); B.Parent := F; B.GroupIndex := 3; B.Enabled := False;
    B.Click;
    AssertFalse('disabled button did not press', B.Down);
    AssertTrue('disabled click did not release the sibling', A.Down);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TGlyphButtonTest);
  RegisterTest(TSpeedButtonTest);
end.
