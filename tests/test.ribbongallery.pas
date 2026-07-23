unit test.ribbongallery;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, fpcunit, testregistry, Controls, Graphics,
  tyControls.Base, tyControls.Types, tyControls.IconFont,
  tyControls.RibbonGallery;
type
  { Exposes the protected SelectAt / RenderTo seams so the selection + paint
    paths are exercisable headlessly without the GUI popup. }
  TGalleryAccess = class(TTyRibbonGallery)
  public
    procedure DoSelectAt(AIndex: Integer);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TRibbonGalleryTest = class(TTestCase)
  private
    FSelectCount: Integer;
    procedure OnSelectHandler(Sender: TObject);
  published
    // Pure geometry helpers
    procedure TestInlineCellRect;
    procedure TestInlineCellRectOutOfRange;
    procedure TestGridRectTiling;
    procedure TestGridRectColsClamp;
    procedure TestCellAtBoundaries;
    procedure TestCellAtOutOfRange;
    // Component behaviour
    procedure TestTypeKeyReused;
    procedure TestDefaults;
    procedure TestItemsRoundTrip;
    procedure TestGlyphNamesRoundTrip;
    procedure TestItemIndexFiresOnChange;
    procedure TestItemIndexNoOpNoFire;
    procedure TestSelectAtSeamFires;
    procedure TestItemIndexClampsWhenShrunk;
    procedure TestIconFontFreeNotification;
    // Paint smoke
    procedure TestPaintEmptySafe;
    procedure TestPaintWithItemsSafe;
  end;

implementation

procedure TGalleryAccess.DoSelectAt(AIndex: Integer);
begin
  SelectAt(AIndex);
end;

procedure TGalleryAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ ---- helpers ---- }

procedure TRibbonGalleryTest.OnSelectHandler(Sender: TObject);
begin
  Inc(FSelectCount);
end;

{ ---- pure geometry ---- }

procedure TRibbonGalleryTest.TestInlineCellRect;
var
  r: TRect;
begin
  // Cell 0 in a row of 56px-wide, 40px-tall cells (arrow zone 18px reserved by
  // the caller; the positional helper starts cells at x=0).
  r := TyGalleryInlineCellRect(0, 56, 40, 18);
  AssertEquals('cell0 left', 0, r.Left);
  AssertEquals('cell0 top', 0, r.Top);
  AssertEquals('cell0 right', 56, r.Right);
  AssertEquals('cell0 bottom', 40, r.Bottom);
  // Cell 2 is offset by two cell widths.
  r := TyGalleryInlineCellRect(2, 56, 40, 18);
  AssertEquals('cell2 left', 112, r.Left);
  AssertEquals('cell2 right', 168, r.Right);
  AssertEquals('cell2 bottom', 40, r.Bottom);
end;

procedure TRibbonGalleryTest.TestInlineCellRectOutOfRange;
var
  r: TRect;
begin
  // Negative index is treated as 0 (never a negative-origin rect).
  r := TyGalleryInlineCellRect(-5, 56, 40, 18);
  AssertEquals('neg index -> cell0 left', 0, r.Left);
  AssertEquals('neg index -> cell0 right', 56, r.Right);
end;

procedure TRibbonGalleryTest.TestGridRectTiling;
var
  r: TRect;
begin
  // 3-column grid, 56x44 cells, row-major.
  // Index 0 -> (col0,row0).
  r := TyGalleryGridRect(0, 3, 56, 44);
  AssertEquals('idx0 left', 0, r.Left);
  AssertEquals('idx0 top', 0, r.Top);
  AssertEquals('idx0 right', 56, r.Right);
  AssertEquals('idx0 bottom', 44, r.Bottom);
  // Index 2 -> last column of row 0.
  r := TyGalleryGridRect(2, 3, 56, 44);
  AssertEquals('idx2 left', 112, r.Left);
  AssertEquals('idx2 top', 0, r.Top);
  // Index 3 -> wraps to (col0,row1).
  r := TyGalleryGridRect(3, 3, 56, 44);
  AssertEquals('idx3 left', 0, r.Left);
  AssertEquals('idx3 top', 44, r.Top);
  AssertEquals('idx3 bottom', 88, r.Bottom);
  // Index 5 -> (col2,row1).
  r := TyGalleryGridRect(5, 3, 56, 44);
  AssertEquals('idx5 left', 112, r.Left);
  AssertEquals('idx5 top', 44, r.Top);
end;

procedure TRibbonGalleryTest.TestGridRectColsClamp;
var
  r: TRect;
begin
  // ACols < 1 behaves as a single column (each index its own row).
  r := TyGalleryGridRect(2, 0, 56, 44);
  AssertEquals('cols<1 -> single column, left', 0, r.Left);
  AssertEquals('cols<1 -> single column, top', 88, r.Top);
end;

procedure TRibbonGalleryTest.TestCellAtBoundaries;
begin
  // 3 cols, 56x44 cells, 6 items.
  // Just inside cell 0.
  AssertEquals('(0,0) -> idx0', 0, TyGalleryCellAt(0, 0, 3, 56, 44, 6));
  AssertEquals('(55,43) -> idx0', 0, TyGalleryCellAt(55, 43, 3, 56, 44, 6));
  // First pixel of the next column -> idx1.
  AssertEquals('(56,0) -> idx1', 1, TyGalleryCellAt(56, 0, 3, 56, 44, 6));
  // First pixel of the next row -> idx3.
  AssertEquals('(0,44) -> idx3', 3, TyGalleryCellAt(0, 44, 3, 56, 44, 6));
  // Last column, second row -> idx5.
  AssertEquals('(112,44) -> idx5', 5, TyGalleryCellAt(112, 44, 3, 56, 44, 6));
end;

procedure TRibbonGalleryTest.TestCellAtOutOfRange;
begin
  // Right of the last column -> -1.
  AssertEquals('past last column', -1, TyGalleryCellAt(200, 0, 3, 56, 44, 6));
  // Negative coords -> -1.
  AssertEquals('negative X', -1, TyGalleryCellAt(-1, 0, 3, 56, 44, 6));
  AssertEquals('negative Y', -1, TyGalleryCellAt(0, -1, 3, 56, 44, 6));
  // Past the item count (row 2, col 0 = idx6 but only 6 items) -> -1.
  AssertEquals('past item count', -1, TyGalleryCellAt(0, 88, 3, 56, 44, 6));
  // Zero items -> -1.
  AssertEquals('zero items', -1, TyGalleryCellAt(0, 0, 3, 56, 44, 0));
end;

{ ---- component behaviour ---- }

procedure TRibbonGalleryTest.TestTypeKeyReused;
var
  G: TTyRibbonGallery;
begin
  // REUSE the TyListBox surface token — no new .tycss selector.
  G := TTyRibbonGallery.Create(nil);
  try
    AssertEquals('gallery owns TyRibbonGallery', 'TyRibbonGallery',
      (G as ITyStyleable).GetStyleTypeKey);
  finally
    G.Free;
  end;
end;

procedure TRibbonGalleryTest.TestDefaults;
var
  G: TTyRibbonGallery;
begin
  G := TTyRibbonGallery.Create(nil);
  try
    AssertEquals('ItemIndex default -1', -1, G.ItemIndex);
    AssertEquals('VisibleColumns default 3', 3, G.VisibleColumns);
    AssertTrue('IconFont default nil', G.IconFont = nil);
    AssertEquals('Items empty by default', 0, G.Items.Count);
    AssertEquals('GlyphNames empty by default', 0, G.GlyphNames.Count);
    AssertTrue('props published',
      IsPublishedProp(G, 'Items') and IsPublishedProp(G, 'GlyphNames')
      and IsPublishedProp(G, 'IconFont') and IsPublishedProp(G, 'ItemIndex')
      and IsPublishedProp(G, 'VisibleColumns'));
  finally
    G.Free;
  end;
end;

procedure TRibbonGalleryTest.TestItemsRoundTrip;
var
  G: TTyRibbonGallery;
  L: TStringList;
begin
  G := TTyRibbonGallery.Create(nil);
  L := TStringList.Create;
  try
    L.Add('Red'); L.Add('Green'); L.Add('Blue');
    G.Items := L;
    AssertEquals('Items count', 3, G.Items.Count);
    AssertEquals('Items[0]', 'Red', G.Items[0]);
    AssertEquals('Items[2]', 'Blue', G.Items[2]);
  finally
    L.Free;
    G.Free;
  end;
end;

procedure TRibbonGalleryTest.TestGlyphNamesRoundTrip;
var
  G: TTyRibbonGallery;
  L: TStringList;
begin
  G := TTyRibbonGallery.Create(nil);
  L := TStringList.Create;
  try
    L.Add('save'); L.Add('open');
    G.GlyphNames := L;
    AssertEquals('GlyphNames count', 2, G.GlyphNames.Count);
    AssertEquals('GlyphNames[0]', 'save', G.GlyphNames[0]);
    AssertEquals('GlyphNames[1]', 'open', G.GlyphNames[1]);
  finally
    L.Free;
    G.Free;
  end;
end;

procedure TRibbonGalleryTest.TestItemIndexFiresOnChange;
var
  G: TTyRibbonGallery;
begin
  G := TTyRibbonGallery.Create(nil);
  try
    G.Items.Add('A'); G.Items.Add('B'); G.Items.Add('C');
    FSelectCount := 0;
    G.OnSelect := @OnSelectHandler;
    G.ItemIndex := 1;
    AssertEquals('ItemIndex changed', 1, G.ItemIndex);
    AssertEquals('OnSelect fired once', 1, FSelectCount);
  finally
    G.Free;
  end;
end;

procedure TRibbonGalleryTest.TestItemIndexNoOpNoFire;
var
  G: TTyRibbonGallery;
begin
  G := TTyRibbonGallery.Create(nil);
  try
    G.Items.Add('A'); G.Items.Add('B');
    G.ItemIndex := 0;              // first change
    FSelectCount := 0;
    G.OnSelect := @OnSelectHandler;
    G.ItemIndex := 0;              // no-op: same index
    AssertEquals('no-op does not fire OnSelect', 0, FSelectCount);
    // Out-of-range collapses to -1; from 0 that IS a change (fires once).
    G.ItemIndex := 99;
    AssertEquals('out-of-range -> -1', -1, G.ItemIndex);
    AssertEquals('out-of-range change fired once', 1, FSelectCount);
    // Setting -1 again is a no-op.
    G.ItemIndex := -1;
    AssertEquals('-1 -> -1 no-op no fire', 1, FSelectCount);
  finally
    G.Free;
  end;
end;

procedure TRibbonGalleryTest.TestSelectAtSeamFires;
var
  G: TGalleryAccess;
begin
  G := TGalleryAccess.Create(nil);
  try
    G.Items.Add('A'); G.Items.Add('B'); G.Items.Add('C');
    FSelectCount := 0;
    G.OnSelect := @OnSelectHandler;
    G.DoSelectAt(2);
    AssertEquals('SelectAt set ItemIndex', 2, G.ItemIndex);
    AssertEquals('SelectAt fired OnSelect once', 1, FSelectCount);
    // Re-selecting the same index via the seam is a no-op.
    G.DoSelectAt(2);
    AssertEquals('SelectAt no-op no fire', 1, FSelectCount);
  finally
    G.Free;
  end;
end;

procedure TRibbonGalleryTest.TestItemIndexClampsWhenShrunk;
var
  G: TTyRibbonGallery;
begin
  G := TTyRibbonGallery.Create(nil);
  try
    G.Items.Add('A'); G.Items.Add('B'); G.Items.Add('C');
    G.ItemIndex := 2;
    FSelectCount := 0;
    G.OnSelect := @OnSelectHandler;
    // Shrinking the list below the selection collapses ItemIndex to -1 and fires.
    G.Items.Clear;
    AssertEquals('ItemIndex clamped to -1 on clear', -1, G.ItemIndex);
    AssertEquals('clamp fired OnSelect once', 1, FSelectCount);
  finally
    G.Free;
  end;
end;

procedure TRibbonGalleryTest.TestIconFontFreeNotification;
var
  G: TTyRibbonGallery;
  Font: TTyIconFont;
begin
  G := TTyRibbonGallery.Create(nil);
  Font := TTyIconFont.Create(nil);
  try
    G.IconFont := Font;
    AssertSame('IconFont assigned', Font, G.IconFont);
    Font.Free;
    Font := nil;
    AssertTrue('IconFont nilled after font freed', G.IconFont = nil);
  finally
    Font.Free;   // no-op when already nil
    G.Free;
  end;
end;

{ ---- paint smoke ---- }

procedure TRibbonGalleryTest.TestPaintEmptySafe;
var
  G: TGalleryAccess;
  Bmp: TBitmap;
begin
  // Paint with ZERO items must not raise (no cells, just the frame + arrow).
  G := TGalleryAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 40);
    G.SetBounds(0, 0, 200, 40);
    G.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 40), 96);
    AssertTrue('empty-gallery RenderTo executed without exception', True);
  finally
    Bmp.Free;
    G.Free;
  end;
end;

procedure TRibbonGalleryTest.TestPaintWithItemsSafe;
var
  G: TGalleryAccess;
  Font: TTyIconFont;
  Bmp: TBitmap;
begin
  // Paint with items (and a glyph name) must not raise. No real font family is
  // registered, and there is no window handle, so the glyph path is a safe no-op
  // (caption-only) — the composite must still complete.
  G := TGalleryAccess.Create(nil);
  Font := TTyIconFont.Create(nil);
  Bmp := TBitmap.Create;
  try
    Font.MapGlyph('save', $F0C7);
    G.IconFont := Font;
    G.Items.Add('Red'); G.Items.Add('Green'); G.Items.Add('Blue'); G.Items.Add('Cyan');
    G.GlyphNames.Add('save');
    G.ItemIndex := 1;   // a selected cell drawn in its :selected state
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 40);
    G.SetBounds(0, 0, 200, 40);
    G.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 40), 96);
    AssertTrue('items RenderTo executed without exception', True);
  finally
    Bmp.Free;
    Font.Free;
    G.Free;
  end;
end;

initialization
  RegisterTest(TRibbonGalleryTest);
end.
