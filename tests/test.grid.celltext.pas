unit test.grid.celltext;

{ #198: a grid's text is the ink the same words leave anywhere else. The grid keeps each cell's
  text on a bitmap of its own, so that a hundred thousand rows can scroll; what it lays down from
  there has to be what drawing the words straight on the surface would have left. Every comparison
  here is against that: the same words on a second surface, pixel by pixel. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Columns,
  tyControls.Grid, tyControls.ListView, tyControls.ListView.Layout;

type
  TGridCellTextTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FGrid: TTyStringGrid;
    FHostKept, FHostDirect: TBitmap;
    FKept, FDirect: TTyPainter;
    procedure CloseSurfaces;
    procedure OpenSurfaces(const AGround: TBGRAPixel);
    procedure DrawKept(const ARect: TRect; const AText: string; AInk: TTyColor; AWrap: Boolean = False);
    procedure DrawDirect(const ARect: TRect; const AText: string; AInk: TTyColor);
    procedure AssertSameInk(const AWhat: string; AMinInked: Integer = 100);
    procedure CheckInk(const AWhat: string; const AGround: TBGRAPixel; AInk: TTyColor);
    procedure CheckRealControls(const AWhat, AGround, AInk: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLightInkOnADarkSurface;
    procedure TestDarkInkOnALightSurface;
    procedure TestColouredInkOnAColouredSurface;
    procedure TestTheInksEitherSideOfThePolarityLine;
    procedure TestTranslucentInk;
    procedure TestOneKeptEntryLiesOnAnyGround;
    procedure TestATransparentSurfaceGetsWhatItAlwaysGets;
    procedure TestASurfaceOpaqueOnlyInPlaces;
    procedure TestTheClipIsKept;
    procedure TestACellHalfOffTheSurface;
    procedure TestWrappedText;
    procedure TestRightToLeftText;
    procedure TestAGridCellIsTheListsInkOnDark;
    procedure TestAGridCellIsTheListsInkOnLight;
    {$IFDEF LCLWin32}
    procedure TestClearTypeOffIsTheGreyTextDrawnStraight;
    procedure TestTheDesktopsSettingIsPartOfTheEntry;
    {$ENDIF}
  end;

implementation

uses
  LCLType;

type
  TGridAccess = class(TTyStringGrid)
  public
    procedure Draw(P: TTyPainter; const ARect: TRect; const AText: string; AInk: TTyColor;
      AWrap: Boolean);
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TListAccess = class(TTyListView)
  public
    procedure DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

const
  W = 360;
  H = 60;
  CFont = 'Segoe UI';
  CSize = 9;
  CWeight = 400;
  CLine = 'Alice Paris 节点 Lima Hold 12';
  CBox: TRect = (Left: 8; Top: 6; Right: 340; Bottom: 40);
  { Qt and GTK draw through BGRA's own renderer, on which only the weight agrees: there a kept run
    is one grey, the run drawn straight on an opaque surface is subpixels. }
  CLaidDownAsDrawn = {$IF defined(LCLWin32) or defined(LCLCocoa)}True{$ELSE}False{$ENDIF};

procedure TGridAccess.Draw(P: TTyPainter; const ARect: TRect; const AText: string; AInk: TTyColor;
  AWrap: Boolean);
begin
  DrawCellText(P, ARect, AText, CFont, CSize, CWeight, AInk, taLeftJustify, tlCenter, AWrap);
end;

procedure TGridAccess.DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TListAccess.DoRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

procedure TGridCellTextTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 600, 500);
  FGrid := TGridAccess.Create(FForm);
  FGrid.Parent := FForm;
  FGrid.Controller := FCtl;
  FHostKept := TBitmap.Create;
  FHostKept.PixelFormat := pf32bit;
  FHostKept.SetSize(W, H);
  FHostDirect := TBitmap.Create;
  FHostDirect.PixelFormat := pf32bit;
  FHostDirect.SetSize(W, H);
end;

procedure TGridCellTextTest.TearDown;
begin
  CloseSurfaces;
  FreeAndNil(FHostKept);
  FreeAndNil(FHostDirect);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

procedure TGridCellTextTest.CloseSurfaces;
begin
  if FKept <> nil then
  begin
    FKept.EndPaint;
    FreeAndNil(FKept);
  end;
  if FDirect <> nil then
  begin
    FDirect.EndPaint;
    FreeAndNil(FDirect);
  end;
end;

procedure TGridCellTextTest.OpenSurfaces(const AGround: TBGRAPixel);
begin
  CloseSurfaces;
  FKept := TTyPainter.Create;
  FKept.BeginPaint(FHostKept.Canvas, Rect(0, 0, W, H), 96);
  FKept.Bitmap.Fill(AGround);
  FDirect := TTyPainter.Create;
  FDirect.BeginPaint(FHostDirect.Canvas, Rect(0, 0, W, H), 96);
  FDirect.Bitmap.Fill(AGround);
end;

procedure TGridCellTextTest.DrawKept(const ARect: TRect; const AText: string; AInk: TTyColor;
  AWrap: Boolean);
begin
  TGridAccess(FGrid).Draw(FKept, ARect, AText, AInk, AWrap);
end;

procedure TGridCellTextTest.DrawDirect(const ARect: TRect; const AText: string; AInk: TTyColor);
begin
  FDirect.DrawText(ARect, AText, CFont, CSize, CWeight, AInk, taLeftJustify, tlCenter, False);
end;

procedure TGridCellTextTest.AssertSameInk(const AWhat: string; AMinInked: Integer);
var
  x, y, differ, inked, worst, d, fx, fy: Integer;
  a, b, g: TBGRAPixel;
begin
  if not CLaidDownAsDrawn then Exit;
  g := FDirect.Bitmap.GetPixel(0, 0);
  differ := 0;
  inked := 0;
  worst := 0;
  fx := -1;
  fy := -1;
  for y := 0 to H - 1 do
    for x := 0 to W - 1 do
    begin
      a := FKept.Bitmap.GetPixel(x, y);
      b := FDirect.Bitmap.GetPixel(x, y);
      if b <> g then Inc(inked);
      d := Abs(a.red - b.red);
      if Abs(a.green - b.green) > d then d := Abs(a.green - b.green);
      if Abs(a.blue - b.blue) > d then d := Abs(a.blue - b.blue);
      if Abs(a.alpha - b.alpha) > d then d := Abs(a.alpha - b.alpha);
      if d > 0 then
      begin
        if fx < 0 then
        begin
          fx := x;
          fy := y;
        end;
        Inc(differ);
        if d > worst then worst := d;
      end;
    end;
  AssertTrue(AWhat + ': precondition, the words were drawn (' + IntToStr(inked) + ' pixels)',
    inked >= AMinInked);
  AssertEquals(Format('%s: pixels that differ from the words drawn straight on the surface'
    + ' (first at %d,%d, worst by %d)', [AWhat, fx, fy, worst]), 0, differ);
end;

procedure TGridCellTextTest.CheckInk(const AWhat: string; const AGround: TBGRAPixel; AInk: TTyColor);
begin
  OpenSurfaces(AGround);
  DrawKept(CBox, CLine, AInk);
  DrawDirect(CBox, CLine, AInk);
  AssertSameInk(AWhat);
end;

procedure TGridCellTextTest.TestLightInkOnADarkSurface;
begin
  CheckInk('light on dark', BGRA($1E, $1E, $1E, 255), TyRGBA($E5, $E7, $EB, 255));
end;

procedure TGridCellTextTest.TestDarkInkOnALightSurface;
begin
  CheckInk('dark on light', BGRA(255, 255, 255, 255), TyRGBA($1F, $29, $37, 255));
end;

procedure TGridCellTextTest.TestColouredInkOnAColouredSurface;
begin
  CheckInk('white on accent', BGRA($25, $63, $EB, 255), TyRGBA(255, 255, 255, 255));
  CheckInk('brown on cream', BGRA($FF, $F3, $CD, 255), TyRGBA($8A, $20, $3B, 255));
end;

procedure TGridCellTextTest.TestTheInksEitherSideOfThePolarityLine;
begin
  { Windows weighs light and dark ink differently. The line is the renderer's; an ink on either
    side of it has to be kept in the polarity it would have been drawn in. }
  CheckInk('128 grey on white', BGRA(255, 255, 255, 255), TyRGBA(128, 128, 128, 255));
  CheckInk('129 grey on white', BGRA(255, 255, 255, 255), TyRGBA(129, 129, 129, 255));
  CheckInk('128 grey on black', BGRA(0, 0, 0, 255), TyRGBA(128, 128, 128, 255));
  CheckInk('129 grey on black', BGRA(0, 0, 0, 255), TyRGBA(129, 129, 129, 255));
end;

procedure TGridCellTextTest.TestTranslucentInk;
begin
  CheckInk('half light ink on dark', BGRA($1E, $1E, $1E, 255), TyRGBA($E5, $E7, $EB, 128));
  CheckInk('half dark ink on light', BGRA(255, 255, 255, 255), TyRGBA($1F, $29, $37, 128));
  CheckInk('half light ink on nothing', BGRA(0, 0, 0, 0), TyRGBA($E5, $E7, $EB, 128));
  CheckInk('half dark ink on half a surface', BGRA(255, 255, 255, 128), TyRGBA($1F, $29, $37, 128));
end;

procedure TGridCellTextTest.TestOneKeptEntryLiesOnAnyGround;
var
  n: Integer;
begin
  { A row turning hover or selected keeps its text entry, and the ground under it changes. }
  CheckInk('on the first ground', BGRA($1E, $1E, $1E, 255), TyRGBA($E5, $E7, $EB, 255));
  n := TGridAccess(FGrid).TextCacheCount;
  AssertEquals('precondition: the words were kept', 1, n);
  CheckInk('the same entry on another', BGRA($80, $30, $30, 255), TyRGBA($E5, $E7, $EB, 255));
  AssertEquals('and it was the same entry', n, TGridAccess(FGrid).TextCacheCount);
end;

procedure TGridCellTextTest.TestATransparentSurfaceGetsWhatItAlwaysGets;
var
  x, y, n: Integer;
  p: TBGRAPixel;
begin
  CheckInk('on nothing', BGRA(0, 0, 0, 0), TyRGBA($E5, $E7, $EB, 255));
  if not CLaidDownAsDrawn then Exit;
  n := 0;
  for y := 0 to H - 1 do
    for x := 0 to W - 1 do
    begin
      p := FKept.Bitmap.GetPixel(x, y);
      if p.alpha > 0 then
      begin
        Inc(n);
        AssertTrue('one grey: the ink, covering by alpha',
          (p.red = $E5) and (p.green = $E7) and (p.blue = $EB));
      end;
    end;
  AssertTrue('precondition: there was ink', n > 100);
end;

procedure TGridCellTextTest.TestASurfaceOpaqueOnlyInPlaces;
var
  half: TRect;
begin
  OpenSurfaces(BGRA(0, 0, 0, 0));
  half := Rect(0, 0, 60, H);
  FKept.Bitmap.FillRect(half, BGRA($1E, $1E, $1E, 255), dmSet);
  FDirect.Bitmap.FillRect(half, BGRA($1E, $1E, $1E, 255), dmSet);
  half := Rect(110, 0, W, H);
  FKept.Bitmap.FillRect(half, BGRA($1E, $1E, $1E, 128), dmSet);
  FDirect.Bitmap.FillRect(half, BGRA($1E, $1E, $1E, 128), dmSet);
  DrawKept(CBox, CLine, TyRGBA($E5, $E7, $EB, 255));
  DrawDirect(CBox, CLine, TyRGBA($E5, $E7, $EB, 255));
  AssertSameInk('a surface opaque, clear and half covering in turn');
end;

procedure TGridCellTextTest.TestTheClipIsKept;
var
  clip: TRect;
  x, y, inside, outside: Integer;
begin
  OpenSurfaces(BGRA($1E, $1E, $1E, 255));
  clip := Rect(60, 20, 140, 26);
  FKept.Bitmap.ClipRect := clip;
  FDirect.Bitmap.ClipRect := clip;
  DrawKept(CBox, CLine, TyRGBA($E5, $E7, $EB, 255));
  DrawDirect(CBox, CLine, TyRGBA($E5, $E7, $EB, 255));
  FKept.Bitmap.NoClip;
  FDirect.Bitmap.NoClip;
  AssertSameInk('clipped', 20);
  inside := 0;
  outside := 0;
  for y := 0 to H - 1 do
    for x := 0 to W - 1 do
      if FKept.Bitmap.GetPixel(x, y) <> BGRA($1E, $1E, $1E, 255) then
        if PtInRect(clip, Point(x, y)) then Inc(inside) else Inc(outside);
  AssertTrue('the words show inside the clip', inside > 20);
  AssertEquals('and nowhere else', 0, outside);
end;

procedure TGridCellTextTest.TestACellHalfOffTheSurface;
begin
  { Off every edge in turn: the rows and columns outside the surface are not there to write. }
  OpenSurfaces(BGRA($1E, $1E, $1E, 255));
  DrawKept(Rect(-30, -8, 200, 14), CLine, TyRGBA($E5, $E7, $EB, 255));
  DrawDirect(Rect(-30, -8, 200, 14), CLine, TyRGBA($E5, $E7, $EB, 255));
  AssertSameInk('off the left and top', 50);
  OpenSurfaces(BGRA($1E, $1E, $1E, 255));
  DrawKept(Rect(250, 48, 600, 72), CLine, TyRGBA($E5, $E7, $EB, 255));
  DrawDirect(Rect(250, 48, 600, 72), CLine, TyRGBA($E5, $E7, $EB, 255));
  AssertSameInk('off the right and bottom', 50);
end;

procedure TGridCellTextTest.TestWrappedText;
const
  CWrap = 'Alice Paris 节点 Lima Hold 12 Alice Paris 节点 Lima Hold 12';
var
  st: TTextStyle;
  box: TRect;
begin
  OpenSurfaces(BGRA($1E, $1E, $1E, 255));
  box := Rect(8, 2, 120, 58);
  DrawKept(box, CWrap, TyRGBA($E5, $E7, $EB, 255), True);
  st := Default(TTextStyle);
  st.Alignment := taLeftJustify;
  st.Layout := tlCenter;
  st.SingleLine := False;
  st.Wordbreak := True;
  st.Clipping := True;
  TyConfigureTextFont(FDirect.Bitmap, CFont, CSize, CWeight, 96);
  FDirect.Bitmap.TextRect(box, box.Left, box.Top, CWrap, st, BGRA($E5, $E7, $EB, 255));
  AssertSameInk('wrapped');
end;

procedure TGridCellTextTest.TestRightToLeftText;
const
  CRtl = 'مرحبا بالعالم Acme 3.0';
var
  ink: TTyColor;
begin
  ink := TyRGBA($E5, $E7, $EB, 255);
  OpenSurfaces(BGRA($1E, $1E, $1E, 255));
  DrawKept(CBox, CRtl, ink);
  DrawDirect(CBox, CRtl, ink);
  AssertSameInk('right to left, light ink');
  ink := TyRGBA($1F, $29, $37, 255);
  OpenSurfaces(BGRA(255, 255, 255, 255));
  DrawKept(CBox, CRtl, ink);
  DrawDirect(CBox, CRtl, ink);
  AssertSameInk('right to left, dark ink');
end;

procedure TGridCellTextTest.CheckRealControls(const AWhat, AGround, AInk: string);
const
  CW = 300;
  CH = 120;
var
  list: TTyListView;
  grid: TTyStringGrid;
  it: TTyListItem;
  c: TTyColumn;
  host: TBitmap;
  shotG, shotL: TBGRABitmap;
  boxG, boxL: TRect;
  x, y, differ: Integer;

  function Shot(AControl: TWinControl): TBGRABitmap;
  begin
    host.Canvas.Brush.Color := clWhite;
    host.Canvas.FillRect(Rect(0, 0, CW, CH));
    if AControl is TTyStringGrid then
      TGridAccess(AControl).DoRender(host.Canvas, Rect(0, 0, CW, CH), 96)
    else
      TListAccess(AControl).DoRender(host.Canvas, Rect(0, 0, CW, CH), 96);
    Result := TBGRABitmap.Create(host);
  end;

  function InkBox(ABmp: TBGRABitmap): TRect;
  var
    px, py: Integer;
    g: TBGRAPixel;
  begin
    g := ABmp.GetPixel(CW - 8, CH - 8);
    Result := Rect(CW, CH, 0, 0);
    for py := 0 to CH - 1 do
      for px := 0 to CW - 1 do
        if ABmp.GetPixel(px, py) <> g then
        begin
          if px < Result.Left then Result.Left := px;
          if py < Result.Top then Result.Top := py;
          if px >= Result.Right then Result.Right := px + 1;
          if py >= Result.Bottom then Result.Bottom := py + 1;
        end;
  end;

begin
  if not CLaidDownAsDrawn then Exit;
  FCtl.LoadThemeCss(
    'TyGrid, TyListView { background: ' + AGround + '; color: ' + AInk +
    '; border-width: 0px; padding: 0px; font-family: ' + CFont + '; font-size: 9px; }' +
    'TyGridLine { background: ' + AGround + '; }' +
    'TyGridCell { background: none; color: ' + AInk + '; }' +
    'TyListViewItem { background: none; color: ' + AInk + '; }');
  grid := TGridAccess.Create(FForm);
  grid.Parent := FForm;
  grid.Controller := FCtl;
  grid.Font.PixelsPerInch := 96;
  grid.SetBounds(0, 0, CW, CH);
  c := grid.Header.Columns.Add as TTyColumn;
  c.Width := 200;
  grid.Header.Options := grid.Header.Options - [hoVisible];
  grid.RowCount := 3;
  grid.ShowFocusCell := False;
  grid.SelectionMode := gsmRow;
  grid.Cells[0, 2] := CLine;
  list := TListAccess.Create(FForm);
  list.Parent := FForm;
  list.Controller := FCtl;
  list.Font.PixelsPerInch := 96;
  list.SetBounds(0, 0, CW, CH);
  list.ViewStyle := lvsReport;
  c := list.Header.Columns.Add as TTyColumn;
  c.Width := 280;
  list.Header.Options := list.Header.Options - [hoVisible];
  it := list.Items.Add;
  it.Caption := CLine;
  host := TBitmap.Create;
  shotG := nil;
  shotL := nil;
  try
    host.PixelFormat := pf32bit;
    host.SetSize(CW, CH);
    shotG := Shot(grid);
    shotL := Shot(list);
    boxG := InkBox(shotG);
    boxL := InkBox(shotL);
    AssertTrue(AWhat + ': precondition, the grid drew the words', boxG.Right - boxG.Left > 60);
    AssertEquals(AWhat + ': as wide', boxL.Right - boxL.Left, boxG.Right - boxG.Left);
    AssertEquals(AWhat + ': as tall', boxL.Bottom - boxL.Top, boxG.Bottom - boxG.Top);
    differ := 0;
    for y := 0 to boxG.Bottom - boxG.Top - 1 do
      for x := 0 to boxG.Right - boxG.Left - 1 do
        if shotG.GetPixel(boxG.Left + x, boxG.Top + y) <> shotL.GetPixel(boxL.Left + x, boxL.Top + y) then
          Inc(differ);
    AssertEquals(AWhat + ': pixels of the grid''s words that differ from the list''s', 0, differ);
  finally
    shotG.Free;
    shotL.Free;
    host.Free;
    list.Free;
    grid.Free;
  end;
end;

procedure TGridCellTextTest.TestAGridCellIsTheListsInkOnDark;
begin
  CheckRealControls('dark', '#1E1E1E', '#E5E7EB');
end;

procedure TGridCellTextTest.TestAGridCellIsTheListsInkOnLight;
begin
  CheckRealControls('light', '#FFFFFF', '#1F2937');
end;

{$IFDEF LCLWin32}
procedure TGridCellTextTest.TestClearTypeOffIsTheGreyTextDrawnStraight;
var
  x, y, chroma, c: Integer;
  p: TBGRAPixel;
begin
  TyDesktopClearTypeForceForTest(0);
  try
    CheckInk('ClearType off, black on white', BGRA(255, 255, 255, 255), TyRGBA(0, 0, 0, 255));
    chroma := 0;
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do
      begin
        p := FKept.Bitmap.GetPixel(x, y);
        c := Abs(p.red - p.green) + Abs(p.green - p.blue);
        if c > chroma then chroma := c;
      end;
    AssertEquals('grey, as the desktop draws it', 0, chroma);
    CheckInk('ClearType off, light on dark', BGRA($1E, $1E, $1E, 255), TyRGBA($E5, $E7, $EB, 255));
  finally
    TyDesktopClearTypeForceForTest(-1);
  end;
end;

procedure TGridCellTextTest.TestTheDesktopsSettingIsPartOfTheEntry;
var
  x, y, chroma, c: Integer;
  p: TBGRAPixel;

  function Chroma1: Integer;
  var
    px, py: Integer;
  begin
    Result := 0;
    for py := 0 to H - 1 do
      for px := 0 to W - 1 do
      begin
        p := FKept.Bitmap.GetPixel(px, py);
        c := Abs(p.red - p.green) + Abs(p.green - p.blue);
        if c > Result then Result := c;
      end;
  end;

begin
  x := 0;
  y := 0;
  TyDesktopClearTypeForceForTest(1);
  try
    CheckInk('ClearType on', BGRA(255, 255, 255, 255), TyRGBA(0, 0, 0, 255));
    chroma := Chroma1;
    AssertTrue('precondition: on, the words are subpixels', chroma > 0);
    TyDesktopClearTypeForceForTest(0);
    CheckInk('turned off', BGRA(255, 255, 255, 255), TyRGBA(0, 0, 0, 255));
    AssertEquals('the entry kept while it was on does not come back', 0, Chroma1);
    AssertEquals('two entries', 2, TGridAccess(FGrid).TextCacheCount);
    TyDesktopClearTypeForceForTest(1);
    CheckInk('turned on again', BGRA(255, 255, 255, 255), TyRGBA(0, 0, 0, 255));
    AssertEquals('the first entry serves again', 2, TGridAccess(FGrid).TextCacheCount);
    AssertEquals('as it was', chroma, Chroma1);
  finally
    TyDesktopClearTypeForceForTest(-1);
  end;
  AssertEquals(0, x + y);
end;
{$ENDIF}

initialization
  RegisterTest(TGridCellTextTest);

end.
