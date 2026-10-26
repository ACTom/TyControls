unit test.glyphnone;
{ #129: TTyGlyphKind has tgNone. A glyph button starts at it, choosing it takes a GlyphKind off
  again -- in code or in the designer -- and a form file does not carry it; the painter draws
  nothing for it. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Types, Graphics, Forms, fpcunit, testregistry, BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.GlyphButtons;

type
  TSpeedProbe = class(TTySpeedButton)
  public
    function Render: TBitmap;
  end;

  TGlyphNoneTest = class(TTestCase)
  published
    procedure TestAGlyphButtonStartsAtTgNone;
    procedure TestTgNoneTakesTheGlyphOff;
    procedure TestAFormFileDoesNotCarryTgNone;
    procedure TestThePainterDrawsNothingForTgNone;
  end;

implementation

function TSpeedProbe.Render: TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(60, 30);
  RenderTo(Result.Canvas, Rect(0, 0, 60, 30), 96);
end;

function SamePixels(A, B: TBitmap): Boolean;
var
  x, y: Integer;
begin
  Result := False;
  for y := 0 to A.Height - 1 do
    for x := 0 to A.Width - 1 do
      if ColorToRGB(A.Canvas.Pixels[x, y]) <> ColorToRGB(B.Canvas.Pixels[x, y]) then Exit;
  Result := True;
end;

procedure TGlyphNoneTest.TestAGlyphButtonStartsAtTgNone;
var
  b: TTySpeedButton;
begin
  b := TTySpeedButton.Create(nil);
  try
    AssertTrue('no glyph kind to begin with', b.GlyphKind = tgNone);
  finally
    b.Free;
  end;
end;

procedure TGlyphNoneTest.TestTgNoneTakesTheGlyphOff;
var
  plain, b: TSpeedProbe;
  x, y: TBitmap;
begin
  plain := TSpeedProbe.Create(nil);
  b := TSpeedProbe.Create(nil);
  x := nil;
  y := nil;
  try
    plain.SetBounds(0, 0, 60, 30);
    b.SetBounds(0, 0, 60, 30);
    b.GlyphKind := tgArrowLeft;
    b.GlyphKind := tgNone;
    x := plain.Render;
    y := b.Render;
    AssertTrue('the button paints as one that never had a glyph', SamePixels(x, y));
  finally
    x.Free;
    y.Free;
    plain.Free;
    b.Free;
  end;
end;

procedure TGlyphNoneTest.TestAFormFileDoesNotCarryTgNone;
var
  f: TForm;
  b: TTySpeedButton;
  ms, ts: TMemoryStream;
  txt: TStringList;
begin
  f := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  txt := TStringList.Create;
  try
    b := TTySpeedButton.Create(f);
    b.Name := 'B';
    b.Parent := f;
    b.GlyphKind := tgClose;
    b.GlyphKind := tgNone;
    ms.WriteComponent(f);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    txt.LoadFromStream(ts);
    AssertEquals('no GlyphKind line' + LineEnding + txt.Text, 0, Pos('GlyphKind', txt.Text));
  finally
    txt.Free;
    ts.Free;
    ms.Free;
    f.Free;
  end;
end;

procedure TGlyphNoneTest.TestThePainterDrawsNothingForTgNone;
var
  bmp: TBitmap;
  p: TTyPainter;
  x, y: Integer;
begin
  bmp := TBitmap.Create;
  p := TTyPainter.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(24, 24);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, 24, 24);
    p.BeginPaint(bmp.Canvas, Rect(0, 0, 24, 24), 96);
    p.DrawGlyph(Rect(0, 0, 24, 24), tgNone, TyRGBA(0, 0, 0, 255), 2);
    p.EndPaint;
    for y := 0 to 23 do
      for x := 0 to 23 do
        AssertEquals('no ink', ColorToRGB(clWhite), ColorToRGB(bmp.Canvas.Pixels[x, y]));
  finally
    p.Free;
    bmp.Free;
  end;
end;

initialization
  RegisterTest(TGlyphNoneTest);
end.
