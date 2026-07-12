unit test.nineslice;
{ Theme-system v3 · Phase B3: nine-slice TILING. 'background-image: url(x) slice(t r b l) repeat'
  tiles the edge/center regions at 1:1 (repeat) instead of stretching them — needed for bitmap
  skins with patterned borders. Without 'repeat' the regions stretch exactly as before. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, BGRABitmap, BGRABitmapTypes,
  fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter;
type
  TNineSliceTest = class(TTestCase)
  private
    function SliceFill(const ACss: string): TTyFill;
    function BuildStripeSource: string;   // 12x12, middle vertical strip = 2px red + 2px blue
    function EdgePixel(const ASrc: string; ATile: Boolean; AX: Integer): TBGRAPixel;
  published
    procedure TestParseSliceRepeat;
    procedure TestParseSliceNoRepeatDefault;
    procedure TestTileRepeatsPatternVsStretch;
  end;

implementation

function TNineSliceTest.SliceFill(const ACss: string): TTyFill;
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { background-image: ' + ACss + '; }');
    Result := m.ResolveStyle('TyButton', '', []).Background;
  finally
    m.Free;
  end;
end;

function TNineSliceTest.BuildStripeSource: string;
var bmp: TBGRABitmap;
begin
  Result := GetTempDir(False) + 'tytilestripe.png';
  bmp := TBGRABitmap.Create(12, 12, BGRA(255, 255, 255, 255));
  try
    bmp.FillRect(4, 0, 6, 12, BGRA(255, 0, 0, 255), dmSet);   // cols 4,5 red
    bmp.FillRect(6, 0, 8, 12, BGRA(0, 0, 255, 255), dmSet);   // cols 6,7 blue
    bmp.SaveToFile(Result);
  finally
    bmp.Free;
  end;
end;

function TNineSliceTest.EdgePixel(const ASrc: string; ATile: Boolean; AX: Integer): TBGRAPixel;
var host: TBitmap; p: TTyPainter; reread: TBGRABitmap;
begin
  host := TBitmap.Create;
  p := TTyPainter.Create;
  try
    host.SetSize(60, 60);
    p.BeginPaint(host.Canvas, Rect(0, 0, 60, 60), 96);
    p.NineSlice(Rect(0, 0, 60, 60), ASrc, Rect(4, 4, 4, 4), ATile);
    p.EndPaint;
    reread := TBGRABitmap.Create(host);
    try
      Result := reread.GetPixel(AX, 1);   // y=1 -> the top edge (middle strip)
    finally
      reread.Free;
    end;
  finally
    p.Free;
    host.Free;
  end;
end;

procedure TNineSliceTest.TestParseSliceRepeat;
var f: TTyFill;
begin
  f := SliceFill('url(skin.png) slice(4 4 4 4) repeat');
  AssertEquals('kind is nine-slice', Ord(tfkNineSlice), Ord(f.Kind));
  AssertTrue('trailing repeat -> SliceRepeat true', f.SliceRepeat);
end;

procedure TNineSliceTest.TestParseSliceNoRepeatDefault;
var f: TTyFill;
begin
  f := SliceFill('url(skin.png) slice(4 4 4 4)');
  AssertFalse('no repeat keyword -> SliceRepeat false (stretch)', f.SliceRepeat);
end;

procedure TNineSliceTest.TestTileRepeatsPatternVsStretch;
var fn: string; pxTile, pxStretch: TBGRAPixel;
begin
  // Source top-middle strip is a 4px RRBB pattern. Blitted into a 60px-wide rect:
  //  - stretched, the 4px pattern smears, so dst x=6 is still in the RED half;
  //  - tiled, the pattern repeats every 4px, so dst x=6 (offset 2 in a tile) is BLUE.
  fn := BuildStripeSource;
  try
    pxStretch := EdgePixel(fn, False, 6);
    pxTile := EdgePixel(fn, True, 6);
    AssertTrue('stretched x=6 is red-dominant', pxStretch.red > pxStretch.blue);
    AssertTrue('tiled x=6 is blue-dominant (pattern repeated, not smeared)', pxTile.blue > pxTile.red);
  finally
    DeleteFile(fn);
  end;
end;

initialization
  RegisterTest(TNineSliceTest);
end.
