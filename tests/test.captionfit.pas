unit test.captionfit;
{$mode objfpc}{$H+}

{ An AutoSize control must be able to DRAW the caption it sized itself for.

  The size floors measured captions on an LCL canvas; the controls draw through the painter,
  whose renderer measures -- and ellipsises against -- its own advance widths. Two rasterisers,
  two roundings. The 3.1 theme editor's checkbox measured 144 px for a caption that needs 147
  and showed "Try it in the previ..."; a tag and a colour button did the same, and a label,
  which never ellipsises, cut the last letter off instead. TTyButton met it first ('&New' drawn
  as "Ne...") and asks the renderer as well. CheckAutoSizeDrawsWholeCaption holds any control
  to that promise.

  Only the captions the two measurements DISAGREE on can tell a fix from the bug, and where they
  disagree depends on the face, the size and the weight: under the test runner's empty fallback
  font they never do. So the check sweeps a few common faces and renders the captions they
  disagree on MOST -- a control may carry a pixel or two of slack of its own (the colour button
  does), and a one-pixel disagreement would pass it with the bug in place. It renders them at the
  width AutoSize hands the control. That width comes from CalculatePreferredSize, which is what
  LCL's AutoSize asks; the headless runner never realises a handle for it to ask on its own.
  Had nothing disagreed, the check proved nothing, and it fails saying so. }

interface

uses
  Classes, SysUtils, Controls, Graphics, tyControls.Controller;

type
  TCaptionRender = procedure(ACanvas: TCanvas; const ARect: TRect; APPI: Integer) of object;

{ AControl: parented on a form whose Color is clWhite (the controls composite onto their
  parent), Controller = ACtl, AutoSize on, Font.PixelsPerInch = 96. ATypeKey: the key whose rule
  styles the caption; the check loads a theme holding that one rule, so every other key falls
  back to the built-in layer. ACentred: the control centres its caption, so in the wider render
  it sits half the extra room further right. }
procedure CheckAutoSizeDrawsWholeCaption(ACtl: TTyStyleController; AControl: TControl;
  const ATypeKey: string; ARender: TCaptionRender; ACentred: Boolean);

implementation

uses
  TypInfo, fpcunit, BGRABitmap, BGRABitmapTypes, tyControls.Painter, tyControls.Accel;

type
  TControlAccess = class(TControl);

const
  { Short Latin captions, where the two rasterisers land within a pixel or two of each other: a
    long caption has slack and would pass with the bug in place. 'Try it in the preview' is the
    one the 3.1 theme editor showed as "Try it in the previ...". }
  cFitCaptions: array[0..13] of string =
    ('Try it in the preview', '&New', 'New', 'Open', 'Reset', 'Accent', 'Density', 'Light',
     'Remember me', 'Show hidden files', 'Match case', 'Whole words only', 'Word wrap',
     'Read only');
  { A face missing on the machine falls back on both sides alike and contributes nothing. }
  cFitFonts: array[0..3] of string = ('Arial', 'Tahoma', 'Segoe UI', 'Microsoft YaHei UI');
  cFitProbes = 8;   // the most-disagreeing captions to render; keeps each check short
  cRoom = 80;       // the extra width of the second render
  cRenderHeight = 28;

type
  TFitProbe = record
    Font: string;
    Size, Weight, Caption: Integer;
    CanvasW, RenderW: Integer;
  end;

var
  GFitProbes: array of TFitProbe;   // swept once per process: it depends on no control
  GFitSwept: Boolean;

{ The width the old size floors used: an LCL canvas's TextWidth. Only picks the probes. }
function CanvasCaptionWidth(const AText, AFontName: string; ASize, AWeight: Integer): Integer;
var
  Meas: TBitmap;
begin
  Meas := TBitmap.Create;
  try
    Meas.SetSize(1, 1);
    TyConfigureMeasureFont(Meas.Canvas, AFontName, ASize, AWeight, 96);
    Result := Meas.Canvas.TextWidth(AText);
  finally
    Meas.Free;
  end;
end;

{ Ink is any dark channel: black text, and a link's blue too. An anti-aliased fringe is light
  in every channel and is not ink. }
function IsInk(const C: TBGRAPixel): Boolean;
begin
  Result := (C.red < 128) or (C.green < 128) or (C.blue < 128);
end;

{ Render the control at AW and again with cRoom to spare, both over white, and say whether the
  caption came out whole. A caption that fits is drawn the same in both, AShift further right in
  the wide one, and no stroke of it lies outside that span. One that was ellipsised at AW differs
  ("previ..." against "preview"); one that was clipped leaves a stroke past the span in the wide
  one. Only ink counts as a stroke: an anti-aliased fringe one pixel past the advance width is
  normal (the crossbar of a final 't' does it) and no measurement covers it. This judges what the
  user sees, without re-deriving any control's layout here. AInked says the wide render drew
  anything at all: a style without a color draws nothing, and two blank renders always match. }
function RendersWhole(ARender: TCaptionRender; AW, AH, AShift: Integer;
  out AInked: Boolean): Boolean;
var
  bmp: array[0..1] of TBitmap;
  px: array[0..1] of TBGRABitmap;
  i, x, y: Integer;
  a, c: TBGRAPixel;
begin
  Result := True;
  AInked := False;
  for i := 0 to 1 do
  begin
    bmp[i] := TBitmap.Create;
    bmp[i].PixelFormat := pf32bit;
    bmp[i].SetSize(AW + cRoom * i, AH);
    bmp[i].Canvas.Brush.Color := clWhite;
    bmp[i].Canvas.FillRect(0, 0, AW + cRoom * i, AH);
    ARender(bmp[i].Canvas, Rect(0, 0, AW + cRoom * i, AH), 96);
    px[i] := TBGRABitmap.Create(bmp[i]);
  end;
  try
    for y := 0 to AH - 1 do
      for x := 0 to AW + cRoom - 1 do
      begin
        c := px[1].GetPixel(x, y);
        if IsInk(c) then AInked := True;
        if (x >= AShift) and (x < AShift + AW) then
        begin
          a := px[0].GetPixel(x - AShift, y);
          if (a.red <> c.red) or (a.green <> c.green) or (a.blue <> c.blue) then
            Result := False;
        end
        else if IsInk(c) then
          Result := False;   // a stroke of the caption runs on past the width it was given
      end;
  finally
    for i := 0 to 1 do
    begin
      px[i].Free;
      bmp[i].Free;
    end;
  end;
end;

{ Every face x size x weight x caption the renderer measures wider than the canvas, the widest
  disagreements first (a stable insertion sort: ties keep the sweep's order), cut to cFitProbes. }
procedure SweepFitProbes;
var
  f, sz, wt, i, j, n: Integer;
  disp: string;
  mp: Integer;
  p: TFitProbe;
begin
  if GFitSwept then Exit;
  GFitSwept := True;
  n := 0;
  SetLength(GFitProbes, 0);
  for f := Low(cFitFonts) to High(cFitFonts) do
    for sz := 9 to 13 do
      for wt := 0 to 1 do
        for i := Low(cFitCaptions) to High(cFitCaptions) do
        begin
          TyParseMnemonic(cFitCaptions[i], disp, mp);
          p.Font := cFitFonts[f];
          p.Size := sz;
          p.Weight := 400 + 300 * wt;
          p.Caption := i;
          p.CanvasW := CanvasCaptionWidth(disp, p.Font, p.Size, p.Weight);
          p.RenderW := TyMeasureRenderedTextWidth(disp, p.Font, p.Size, p.Weight, 96);
          if p.RenderW <= p.CanvasW then Continue;
          SetLength(GFitProbes, n + 1);
          j := n;
          while (j > 0) and (GFitProbes[j - 1].RenderW - GFitProbes[j - 1].CanvasW <
            p.RenderW - p.CanvasW) do
          begin
            GFitProbes[j] := GFitProbes[j - 1];
            Dec(j);
          end;
          GFitProbes[j] := p;
          Inc(n);
        end;
  if n > cFitProbes then SetLength(GFitProbes, cFitProbes);
end;

procedure CheckAutoSizeDrawsWholeCaption(ACtl: TTyStyleController; AControl: TControl;
  const ATypeKey: string; ARender: TCaptionRender; ACentred: Boolean);
var
  k, w, h, shift: Integer;
  p: TFitProbe;
  whole, inked: Boolean;
begin
  SweepFitProbes;
  TAssert.AssertTrue('precondition: some caption measures wider on the renderer than on ' +
    'the canvas, in at least one of the probed fonts', Length(GFitProbes) > 0);
  if ACentred then shift := cRoom div 2 else shift := 0;
  for k := 0 to High(GFitProbes) do
  begin
    p := GFitProbes[k];
    { The whole rule, not just the font: a theme that names a typeKey replaces the built-in
      layer for it, and a caption with no color is not drawn at all. }
    ACtl.LoadThemeCss(Format('%s { background: #FFFFFF; color: #000000; border-width: 0px; ' +
      'padding: 0px; font-family: %s; font-size: %dpx; font-weight: %d; }',
      [ATypeKey, p.Font, p.Size, p.Weight]));
    SetStrProp(AControl, 'Caption', cFitCaptions[p.Caption]);
    w := 0;
    h := 0;
    TControlAccess(AControl).CalculatePreferredSize(w, h, True);
    whole := RendersWhole(ARender, w, cRenderHeight, shift, inked);
    TAssert.AssertTrue(Format('precondition: %s "%s" draws its caption', [ATypeKey,
      cFitCaptions[p.Caption]]), inked);
    TAssert.AssertTrue(Format('%s, %s %dpt weight %d: "%s" at its AutoSize width %d is ' +
      'drawn whole, not ellipsised or clipped (canvas %d px, renderer %d px)',
      [ATypeKey, p.Font, p.Size, p.Weight, cFitCaptions[p.Caption], w, p.CanvasW, p.RenderW]),
      whole);
  end;
end;

end.
