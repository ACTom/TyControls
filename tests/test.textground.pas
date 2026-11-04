unit test.textground;

{ #199, #200: on Windows, text is what the desktop draws there. In the quality the desktop asks for
  (#199), and in its subpixels even on a control with no background of its own (#200): the words
  go down on what is under them on the canvas, read just before, instead of on a transparent layer
  that cannot hold three coverages for one pixel. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, ExtCtrls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.TyLabel,
  tyControls.HtmlLabel;

type
  TTextGroundTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FHost: TBitmap;
    FBox: TPaintBox;
    procedure BeginFrame(AHost: TBitmap);
    procedure EndFrame(AHost: TBitmap);
    procedure MakeHost(AFormat: TPixelFormat; AGround: TColor);
    function Colourful(ABmp: TBitmap; const ABox: TRect): Integer;
    procedure PaintLayer(const AText: string; AInk: TTyColor);
    procedure CheckLayerIsTextOnTheGround(const AWhat, AText: string; AInk: TTyColor);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheCallLeavesAnOpaqueSurfaceAlone;
    {$IFDEF LCLWin32}
    procedure TestLatinIsWhatTheCanvasDrawsInItsOwnQuality;
    procedure TestChineseIsWhatTheCanvasDrawsInItsOwnQuality;
    procedure TestALineOnALayerIsTheLineOnTheGround;
    procedure TestRightToLeftOnALayerIsTheLineOnTheGround;
    procedure TestItLiesOnAPictureAsOnAnOpaqueCopyOfThePicture;
    procedure TestAControlsGroundIsUnderIt;
    procedure TestOnARealWindowEachLabelIsOnItsOwnGround;
    procedure TestWhatTheLayerDrewUnderTheWordsStays;
    procedure TestOnlyTheWordsRectBecomesOpaque;
    procedure TestACanvasWhoseAlphaMattersKeepsGrey;
    procedure TestABitmapBeingMadeKeepsGrey;
    procedure TestADimmedLayerKeepsGrey;
    procedure TestClearTypeOffKeepsGrey;
    procedure TestAnOpaqueLayerReadsNothing;
    procedure TestALayerReadsOnceAFrame;
    procedure TestAKeptSurfaceReadsNothing;
    procedure TestALabelIsWhatTheCanvasDraws;
    procedure TestAnHtmlLabelHasSubpixels;
    {$ENDIF}
  end;

implementation

uses
  LCLType, LCLIntf, LMessages;

type
  TLabelAccess = class(TTyLabel);
  THtmlAccess = class(TTyHtmlLabel);

const
  W = 360;
  H = 40;
  OX = 10;
  OY = 5;
  CFont = 'Microsoft YaHei UI';
  CSize = 9;
  CWeight = 400;
  CLatin = 'The quick brown fox jumps over the lazy dog 0123456789';
  CChinese = '表格正文和列表正文的文字渲染对比，中文标点符号';
  CMixed = 'Grid 表格 Name 名称 Status 状态 12.5% OK';

procedure TTextGroundTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 600, 400);
  FHost := TBitmap.Create;
  FBox := TPaintBox.Create(FForm);
  FBox.Parent := FForm;
end;

procedure TTextGroundTest.TearDown;
begin
  {$IFDEF LCLWin32}
  TyDesktopClearTypeForceForTest(-1);
  {$ENDIF}
  FreeAndNil(FHost);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
end;

{ A control's canvas with the DC of a paint in it, as TGraphicControl.WMPaint has it. }
procedure TTextGroundTest.BeginFrame(AHost: TBitmap);
begin
  AHost.Canvas.Changing;
  FBox.Canvas.Lock;
  FBox.Canvas.Handle := AHost.Canvas.Handle;
end;

procedure TTextGroundTest.EndFrame(AHost: TBitmap);
begin
  FBox.Canvas.Handle := 0;
  FBox.Canvas.Unlock;
  AHost.Canvas.Changed;
end;

procedure TTextGroundTest.MakeHost(AFormat: TPixelFormat; AGround: TColor);
begin
  FHost.PixelFormat := AFormat;
  FHost.SetSize(W + OX + 8, H + OY + 8);
  FHost.Canvas.Brush.Color := AGround;
  FHost.Canvas.Brush.Style := bsSolid;
  FHost.Canvas.FillRect(0, 0, FHost.Width, FHost.Height);
end;

function TTextGroundTest.Colourful(ABmp: TBitmap; const ABox: TRect): Integer;
var
  shot: TBGRABitmap;
  x, y: Integer;
  p: TBGRAPixel;
begin
  Result := 0;
  shot := TBGRABitmap.Create(ABmp);
  try
    for y := ABox.Top to ABox.Bottom - 1 do
      for x := ABox.Left to ABox.Right - 1 do
      begin
        p := shot.GetPixel(x, y);
        if (Abs(p.red - p.green) > 8) or (Abs(p.green - p.blue) > 8) then Inc(Result);
      end;
  finally
    shot.Free;
  end;
end;

procedure TTextGroundTest.PaintLayer(const AText: string; AInk: TTyColor);
var
  p: TTyPainter;
begin
  p := TTyPainter.Create;
  BeginFrame(FHost);
  try
    p.BeginPaint(FBox.Canvas, Bounds(OX, OY, W, H), 96);
    p.DrawText(Rect(0, 0, W, H), AText, CFont, CSize, CWeight, AInk, taLeftJustify, tlCenter, False);
    p.EndPaint;
  finally
    EndFrame(FHost);
    p.Free;
  end;
end;

{ What the same words leave drawn straight on an opaque copy of what the canvas holds. }
procedure TTextGroundTest.CheckLayerIsTextOnTheGround(const AWhat, AText: string; AInk: TTyColor);
var
  before, part: TBGRABitmap;
  after: TBGRABitmap;
  scratch: TBitmap;
  p: TTyPainter;
  x, y, differ, worst, d: Integer;
  a, b: TBGRAPixel;
begin
  before := TBGRABitmap.Create(FHost);
  part := before.GetPart(Bounds(OX, OY, W, H)) as TBGRABitmap;
  scratch := TBitmap.Create;
  p := TTyPainter.Create;
  after := nil;
  try
    scratch.PixelFormat := pf24bit;
    scratch.SetSize(W, H);
    p.BeginPaintOn(scratch.Canvas, Rect(0, 0, W, H), 96, part);
    p.DrawText(Rect(0, 0, W, H), AText, CFont, CSize, CWeight, AInk, taLeftJustify, tlCenter, False);
    p.EndPaint;
    PaintLayer(AText, AInk);
    after := TBGRABitmap.Create(FHost);
    differ := 0;
    worst := 0;
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do
      begin
        a := after.GetPixel(OX + x, OY + y);
        b := part.GetPixel(x, y);
        d := Abs(a.red - b.red);
        if Abs(a.green - b.green) > d then d := Abs(a.green - b.green);
        if Abs(a.blue - b.blue) > d then d := Abs(a.blue - b.blue);
        if d > 0 then Inc(differ);
        if d > worst then worst := d;
      end;
    AssertEquals(Format('%s: pixels that differ from the words on the ground (worst by %d)',
      [AWhat, worst]), 0, differ);
    { And the rest of the canvas is what it was. }
    AssertTrue(AWhat + ': left of the layer', after.GetPixel(OX - 1, OY + H div 2) = before.GetPixel(OX - 1, OY + H div 2));
    AssertTrue(AWhat + ': below the layer', after.GetPixel(OX + W div 2, OY + H) = before.GetPixel(OX + W div 2, OY + H));
  finally
    p.Free;
    scratch.Free;
    after.Free;
    part.Free;
    before.Free;
  end;
end;

procedure TTextGroundTest.TestTheCallLeavesAnOpaqueSurfaceAlone;
var
  p: TTyPainter;
begin
  MakeHost(pf24bit, clWhite);
  p := TTyPainter.Create;
  try
    p.BeginPaint(FHost.Canvas, Rect(0, 0, W, H), 96);
    p.Bitmap.Fill(BGRA(10, 20, 30, 255));
    p.PrepareTextGround(Rect(0, 0, W, H));
    AssertTrue('the surface is as it was', p.Bitmap.GetPixel(W div 2, H div 2) = BGRA(10, 20, 30, 255));
    p.EndPaint;
  finally
    p.Free;
  end;
end;

{$IFDEF LCLWin32}
procedure TTextGroundTest.TestLatinIsWhatTheCanvasDrawsInItsOwnQuality;

  procedure Check(const AFont: string);
  var
    ours: TBGRABitmap;
    theirs: TBGRABitmap;
    b: TBitmap;
    x, y, differ: Integer;
  begin
    ours := TBGRABitmap.Create(W, H, BGRAWhite);
    b := TBitmap.Create;
    theirs := nil;
    try
      TyConfigureTextFont(ours, AFont, CSize, CWeight, 96);
      ours.TextOut(4, 4, CLatin, BGRABlack);
      b.PixelFormat := pf24bit;
      b.SetSize(W, H);
      b.Canvas.Brush.Color := clWhite;
      b.Canvas.FillRect(0, 0, W, H);
      b.Canvas.Font.Name := AFont;
      b.Canvas.Font.Height := -TyFontHeightPx(CSize, 96);
      b.Canvas.Font.Color := clBlack;
      b.Canvas.Brush.Style := bsClear;
      { No quality asked for: what a TLabel gets, and an ordinary GDI program. }
      b.Canvas.TextOut(4, 4, CLatin);
      theirs := TBGRABitmap.Create(b);
      differ := 0;
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
          if ours.GetPixel(x, y) <> theirs.GetPixel(x, y) then Inc(differ);
      AssertEquals(AFont + ': pixels of the line that differ from the canvas''s', 0, differ);
    finally
      theirs.Free;
      b.Free;
      ours.Free;
    end;
  end;

begin
  Check(CFont);
  Check('Segoe UI');
end;

procedure TTextGroundTest.TestChineseIsWhatTheCanvasDrawsInItsOwnQuality;
var
  ours, theirs: TBGRABitmap;
  b: TBitmap;
  x, y, differ: Integer;
begin
  ours := TBGRABitmap.Create(W, H, BGRAWhite);
  b := TBitmap.Create;
  theirs := nil;
  try
    TyConfigureTextFont(ours, CFont, CSize, CWeight, 96);
    ours.TextOut(4, 4, CChinese, BGRABlack);
    b.PixelFormat := pf24bit;
    b.SetSize(W, H);
    b.Canvas.Brush.Color := clWhite;
    b.Canvas.FillRect(0, 0, W, H);
    b.Canvas.Font.Name := CFont;
    b.Canvas.Font.Height := -TyFontHeightPx(CSize, 96);
    b.Canvas.Font.Color := clBlack;
    b.Canvas.Brush.Style := bsClear;
    b.Canvas.TextOut(4, 4, CChinese);
    theirs := TBGRABitmap.Create(b);
    differ := 0;
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do
        if ours.GetPixel(x, y) <> theirs.GetPixel(x, y) then Inc(differ);
    AssertEquals('pixels of the line that differ from the canvas''s', 0, differ);
  finally
    theirs.Free;
    b.Free;
    ours.Free;
  end;
end;

procedure TTextGroundTest.TestALineOnALayerIsTheLineOnTheGround;
begin
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  CheckLayerIsTextOnTheGround('dark on white', CMixed, TyRGBA(0, 0, 0, 255));
  AssertTrue('the words have subpixels', Colourful(FHost, Bounds(OX, OY, W, H)) > 50);
  MakeHost(pf24bit, $1E1E1E);
  CheckLayerIsTextOnTheGround('light on dark', CMixed, TyRGBA($E5, $E7, $EB, 255));
  MakeHost(pf24bit, $30A0F0);
  CheckLayerIsTextOnTheGround('half ink on colour', CMixed, TyRGBA($10, $20, $30, 128));
end;

procedure TTextGroundTest.TestRightToLeftOnALayerIsTheLineOnTheGround;
begin
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  CheckLayerIsTextOnTheGround('right to left', 'مرحبا بالعالم Acme 3.0', TyRGBA(0, 0, 0, 255));
  AssertTrue('the words have subpixels', Colourful(FHost, Bounds(OX, OY, W, H)) > 50);
end;

procedure TTextGroundTest.TestItLiesOnAPictureAsOnAnOpaqueCopyOfThePicture;
var
  x: Integer;
begin
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  { Stripes under the words: only the real pixels can be right, not any one colour. }
  x := 0;
  while x < FHost.Width do
  begin
    FHost.Canvas.Brush.Color := RGBToColor(255 - (x * 2) mod 200, 240, 180 + x mod 70);
    FHost.Canvas.FillRect(x, 0, x + 7, FHost.Height);
    Inc(x, 7);
  end;
  CheckLayerIsTextOnTheGround('on a picture', CMixed, TyRGBA(0, 0, 0, 255));
end;

procedure TTextGroundTest.TestAControlsGroundIsUnderIt;
const
  LX = 12;
  LY = 18;
  LH = 26;
var
  before, part, after: TBGRABitmap;
  scratch: TBitmap;
  p: TTyPainter;
  x, y, differ: Integer;
begin
  { A graphic control paints with the parent's DC moved to it: what its layer must read is at the
    control, not at the DC's corner. There is a block at the corner to get wrong. }
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  FHost.Canvas.Brush.Color := clBlack;
  FHost.Canvas.FillRect(0, 0, W, 16);
  before := TBGRABitmap.Create(FHost);
  part := before.GetPart(Bounds(LX, LY, W, LH)) as TBGRABitmap;
  scratch := TBitmap.Create;
  after := nil;
  p := TTyPainter.Create;
  try
    scratch.PixelFormat := pf24bit;
    scratch.SetSize(W, LH);
    p.BeginPaintOn(scratch.Canvas, Rect(0, 0, W, LH), 96, part);
    p.DrawText(Rect(0, 0, W, LH), CMixed, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    p.EndPaint;
    BeginFrame(FHost);
    MoveWindowOrgEx(FBox.Canvas.Handle, LX, LY);
    p.BeginPaint(FBox.Canvas, Rect(0, 0, W, LH), 96);
    p.DrawText(Rect(0, 0, W, LH), CMixed, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    p.EndPaint;
    MoveWindowOrgEx(FBox.Canvas.Handle, -LX, -LY);
    EndFrame(FHost);
    after := TBGRABitmap.Create(FHost);
    differ := 0;
    for y := 0 to LH - 1 do
      for x := 0 to W - 1 do
        if after.GetPixel(LX + x, LY + y) <> part.GetPixel(x, y) then Inc(differ);
    AssertEquals('pixels that differ from the words on the ground under the control', 0, differ);
  finally
    p.Free;
    after.Free;
    scratch.Free;
    part.Free;
    before.Free;
  end;
end;

procedure TTextGroundTest.TestOnARealWindowEachLabelIsOnItsOwnGround;
const
  RowH = 26;
  Lines: array[0..2] of string = (CMixed, CChinese, CLatin);
var
  frm: TForm;
  shot: TBGRABitmap;
  b: TBitmap;
  i, x, y, stray: Integer;
  lbl: TTyLabel;
  dc: HDC;
  p: TBGRAPixel;
begin
  { LCL's own BitBlt reads a 32-bit DIB's source through a path that ignores the DC's origin. On a
    memory DC that still lands right, so only a window shows it: the second row read the window's
    corner, with the first row's words in it, and on black. It has to be on a screen, since a
    window wholly off one is never sent a paint: shown for the length of one paint. }
  Forms.Application.Initialize;
  TyDesktopClearTypeForceForTest(1);
  FCtl.LoadThemeCss('TyLabel { color: #000000; font-family: ' + CFont + '; font-size: 9px; }');
  frm := TForm.CreateNew(nil);
  b := TBitmap.Create;
  shot := nil;
  try
    frm.BorderStyle := bsNone;
    frm.ShowInTaskBar := stNever;
    frm.Color := clWhite;
    frm.SetBounds(0, 0, W + 8, 3 * RowH + 8);
    for i := 0 to 2 do
    begin
      lbl := TTyLabel.Create(frm);
      lbl.Parent := frm;
      lbl.Controller := FCtl;
      lbl.AutoSize := False;
      lbl.Font.PixelsPerInch := 96;
      lbl.Caption := Lines[i];
      lbl.SetBounds(4, 4 + i * RowH, W, RowH - 2);
    end;
    frm.Show;
    frm.Repaint;
    Forms.Application.ProcessMessages;
    b.PixelFormat := pf24bit;
    b.SetSize(frm.Width, frm.Height);
    dc := GetDC(frm.Handle);
    try
      b.Canvas.Changing;
      BitBlt(b.Canvas.Handle, 0, 0, b.Width, b.Height, dc, 0, 0, SRCCOPY);
      b.Canvas.Changed;
    finally
      ReleaseDC(frm.Handle, dc);
    end;
    shot := TBGRABitmap.Create(b);
    AssertTrue(Format('precondition: the form painted, at the corner %d,%d,%d',
      [shot.GetPixel(1, 1).red, shot.GetPixel(1, 1).green, shot.GetPixel(1, 1).blue]),
      shot.GetPixel(1, 1) = BGRAWhite);
    stray := 0;
    { Between the rows, and to the right of every row's words, there is only the form. }
    for i := 0 to 2 do
      for y := 4 + i * RowH to 4 + i * RowH + 2 do
        for x := 4 to W do
        begin
          p := shot.GetPixel(x, y);
          if p <> BGRAWhite then Inc(stray);
        end;
    AssertEquals('pixels above each row''s words that are not the form', 0, stray);
    AssertTrue('the words are there, in subpixels', Colourful(b, Rect(0, 0, b.Width, b.Height)) > 200);
  finally
    shot.Free;
    b.Free;
    frm.Free;
  end;
end;

procedure TTextGroundTest.TestWhatTheLayerDrewUnderTheWordsStays;
var
  p: TTyPainter;
  shot, plain: TBGRABitmap;
  hostPlain: TBitmap;
  x, y, worst, d: Integer;
  a, b: TBGRAPixel;

  procedure PaintWith(AHost: TBitmap; AText: Boolean);
  begin
    p := TTyPainter.Create;
    BeginFrame(AHost);
    try
      p.BeginPaint(FBox.Canvas, Bounds(OX, OY, W, H), 96);
      { translucent and opaque paint under where the words will lie, and an edge between them }
      p.Bitmap.FillRect(0, 0, 120, H, BGRA(200, 30, 30, 128), dmSet);
      p.Bitmap.FillRect(120, 0, 200, H, BGRA(30, 30, 200, 255), dmSet);
      if AText then
        p.DrawText(Rect(0, 0, W, H), ' ', CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
      p.EndPaint;
    finally
      EndFrame(AHost);
      p.Free;
    end;
  end;

begin
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, $70D0F0);
  hostPlain := TBitmap.Create;
  shot := nil;
  plain := nil;
  try
    hostPlain.PixelFormat := pf24bit;
    hostPlain.SetSize(FHost.Width, FHost.Height);
    hostPlain.Canvas.Brush.Color := $70D0F0;
    hostPlain.Canvas.FillRect(0, 0, hostPlain.Width, hostPlain.Height);
    { A run with no ink: everything it changes is what the ground did to the layer. }
    PaintWith(FHost, True);
    PaintWith(hostPlain, False);
    shot := TBGRABitmap.Create(FHost);
    plain := TBGRABitmap.Create(hostPlain);
    worst := 0;
    for y := 0 to FHost.Height - 1 do
      for x := 0 to FHost.Width - 1 do
      begin
        a := shot.GetPixel(x, y);
        b := plain.GetPixel(x, y);
        d := Abs(a.red - b.red);
        if Abs(a.green - b.green) > d then d := Abs(a.green - b.green);
        if Abs(a.blue - b.blue) > d then d := Abs(a.blue - b.blue);
        if d > worst then worst := d;
      end;
    AssertTrue('the layer comes out as it would have, worst by ' + IntToStr(worst), worst <= 1);
    AssertTrue('precondition: the translucent paint showed',
      plain.GetPixel(OX + 20, OY + 20) <> BGRA($F0, $D0, $70, 255));
  finally
    plain.Free;
    shot.Free;
    hostPlain.Free;
  end;
end;

procedure TTextGroundTest.TestOnlyTheWordsRectBecomesOpaque;
var
  p: TTyPainter;
begin
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  p := TTyPainter.Create;
  BeginFrame(FHost);
  try
    p.BeginPaint(FBox.Canvas, Bounds(OX, OY, W, H), 96);
    p.DrawText(Rect(20, 5, 200, 30), CMixed, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    AssertEquals('inside the words'' rect', 255, p.Bitmap.GetPixel(20, 5).alpha);
    AssertEquals('at its far corner', 255, p.Bitmap.GetPixel(199, 29).alpha);
    AssertEquals('left of it', 0, p.Bitmap.GetPixel(19, 10).alpha);
    AssertEquals('right of it', 0, p.Bitmap.GetPixel(200, 10).alpha);
    AssertEquals('above it', 0, p.Bitmap.GetPixel(50, 4).alpha);
    AssertEquals('below it', 0, p.Bitmap.GetPixel(50, 30).alpha);
    p.EndPaint;
  finally
    EndFrame(FHost);
    p.Free;
  end;
end;

procedure TTextGroundTest.TestACanvasWhoseAlphaMattersKeepsGrey;
var
  n: Integer;
begin
  { A 32-bit DIB may be someone's picture with real alpha in it, and what it holds would come back
    opaque. }
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf32bit, clWhite);
  n := TyTextGroundReadsForTest;
  PaintLayer(CMixed, TyRGBA(0, 0, 0, 255));
  AssertEquals('nothing was read', n, TyTextGroundReadsForTest);
  AssertEquals('the words are grey', 0, Colourful(FHost, Bounds(OX, OY, W, H)));
end;

procedure TTextGroundTest.TestABitmapBeingMadeKeepsGrey;
var
  p: TTyPainter;
  n: Integer;
begin
  { RenderTo on a bitmap: whoever asked may read the layer's alpha. }
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  n := TyTextGroundReadsForTest;
  p := TTyPainter.Create;
  try
    p.BeginPaint(FHost.Canvas, Bounds(OX, OY, W, H), 96);
    p.DrawText(Rect(0, 0, W, H), CMixed, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    p.EndPaint;
  finally
    p.Free;
  end;
  AssertEquals('nothing was read', n, TyTextGroundReadsForTest);
  AssertEquals('the words are grey', 0, Colourful(FHost, Bounds(OX, OY, W, H)));
end;

procedure TTextGroundTest.TestADimmedLayerKeepsGrey;
var
  p: TTyPainter;
  n: Integer;
begin
  { A disabled control: EndPaint fades the layer toward a base colour, and a slice of the ground in
    it would fade with it. }
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  n := TyTextGroundReadsForTest;
  p := TTyPainter.Create;
  BeginFrame(FHost);
  try
    p.BeginPaint(FBox.Canvas, Bounds(OX, OY, W, H), 96);
    p.Opacity := 0.5;
    p.DrawText(Rect(0, 0, W, H), CMixed, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    p.EndPaint;
  finally
    EndFrame(FHost);
    p.Free;
  end;
  AssertEquals('nothing was read', n, TyTextGroundReadsForTest);
  AssertEquals('the words are grey', 0, Colourful(FHost, Bounds(OX, OY, W, H)));
end;

procedure TTextGroundTest.TestClearTypeOffKeepsGrey;
var
  n: Integer;
begin
  TyDesktopClearTypeForceForTest(0);
  MakeHost(pf24bit, clWhite);
  n := TyTextGroundReadsForTest;
  PaintLayer(CMixed, TyRGBA(0, 0, 0, 255));
  AssertEquals('nothing was read', n, TyTextGroundReadsForTest);
  AssertEquals('the words are grey', 0, Colourful(FHost, Bounds(OX, OY, W, H)));
end;

procedure TTextGroundTest.TestAnOpaqueLayerReadsNothing;
var
  p: TTyPainter;
  n: Integer;
begin
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  n := TyTextGroundReadsForTest;
  p := TTyPainter.Create;
  BeginFrame(FHost);
  try
    p.BeginPaint(FBox.Canvas, Bounds(OX, OY, W, H), 96);
    p.Bitmap.Fill(BGRA(240, 240, 240, 255));
    p.DrawText(Rect(0, 0, W, H), CMixed, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    AssertEquals('a filled control pays nothing', n, TyTextGroundReadsForTest);
    p.EndPaint;
  finally
    EndFrame(FHost);
    p.Free;
  end;
end;

procedure TTextGroundTest.TestALayerReadsOnceAFrame;
var
  p: TTyPainter;
  n: Integer;
begin
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  n := TyTextGroundReadsForTest;
  p := TTyPainter.Create;
  BeginFrame(FHost);
  try
    p.BeginPaint(FBox.Canvas, Bounds(OX, OY, W, H), 96);
    p.DrawText(Rect(0, 0, W, 18), CMixed, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    p.DrawText(Rect(0, 20, W, 38), CLatin, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    AssertEquals('two runs, one read', n + 1, TyTextGroundReadsForTest);
    p.EndPaint;
    p.BeginPaint(FBox.Canvas, Bounds(OX, OY, W, H), 96);
    p.DrawText(Rect(0, 0, W, 18), CMixed, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    AssertEquals('the next frame reads what is there by then', n + 2, TyTextGroundReadsForTest);
    p.EndPaint;
  finally
    EndFrame(FHost);
    p.Free;
  end;
end;

procedure TTextGroundTest.TestAKeptSurfaceReadsNothing;
var
  p: TTyPainter;
  kept: TBGRABitmap;
  n: Integer;
begin
  { A surface that outlives the frame would keep a slice of a canvas that has moved on. }
  TyDesktopClearTypeForceForTest(1);
  MakeHost(pf24bit, clWhite);
  n := TyTextGroundReadsForTest;
  kept := TBGRABitmap.Create(W, H);
  p := TTyPainter.Create;
  BeginFrame(FHost);
  try
    p.BeginPaintOn(FBox.Canvas, Bounds(OX, OY, W, H), 96, kept);
    p.DrawText(Rect(0, 0, W, H), CMixed, CFont, CSize, CWeight, TyRGBA(0, 0, 0, 255), taLeftJustify, tlCenter, False);
    p.EndPaint;
    AssertEquals('nothing was read', n, TyTextGroundReadsForTest);
  finally
    EndFrame(FHost);
    p.Free;
    kept.Free;
  end;
end;

procedure TTextGroundTest.TestALabelIsWhatTheCanvasDraws;
var
  lbl: TTyLabel;
  ref: TBitmap;
  a, b: TBGRABitmap;
  boxA, boxB: TRect;
  x, y, differ: Integer;

  function InkBox(ABmp: TBGRABitmap): TRect;
  var
    px, py: Integer;
  begin
    Result := Rect(ABmp.Width, ABmp.Height, 0, 0);
    for py := 0 to ABmp.Height - 1 do
      for px := 0 to ABmp.Width - 1 do
        if ABmp.GetPixel(px, py) <> BGRAWhite then
        begin
          if px < Result.Left then Result.Left := px;
          if py < Result.Top then Result.Top := py;
          if px >= Result.Right then Result.Right := px + 1;
          if py >= Result.Bottom then Result.Bottom := py + 1;
        end;
  end;

begin
  TyDesktopClearTypeForceForTest(-1);
  FCtl.LoadThemeCss('TyLabel { color: #000000; font-family: ' + CFont + '; font-size: 9px; }');
  lbl := TLabelAccess.Create(FForm);
  lbl.Parent := FForm;
  lbl.Controller := FCtl;
  lbl.AutoSize := False;
  lbl.Font.PixelsPerInch := 96;
  lbl.SetBounds(0, 0, W, H);
  lbl.Caption := CMixed;
  MakeHost(pf24bit, clWhite);
  FHost.Canvas.Changing;
  lbl.Perform(LM_PAINT, WParam(FHost.Canvas.Handle), 0);
  FHost.Canvas.Changed;
  ref := TBitmap.Create;
  a := nil;
  b := nil;
  try
    ref.PixelFormat := pf24bit;
    ref.SetSize(FHost.Width, FHost.Height);
    ref.Canvas.Brush.Color := clWhite;
    ref.Canvas.FillRect(0, 0, ref.Width, ref.Height);
    ref.Canvas.Font.Name := CFont;
    ref.Canvas.Font.Height := -TyFontHeightPx(CSize, 96);
    ref.Canvas.Font.Color := clBlack;
    ref.Canvas.Brush.Style := bsClear;
    ref.Canvas.TextOut(4, 4, CMixed);
    a := TBGRABitmap.Create(FHost);
    b := TBGRABitmap.Create(ref);
    boxA := InkBox(a);
    boxB := InkBox(b);
    AssertTrue('precondition: the label drew', boxA.Right - boxA.Left > 60);
    AssertEquals('as wide', boxB.Right - boxB.Left, boxA.Right - boxA.Left);
    AssertEquals('as tall', boxB.Bottom - boxB.Top, boxA.Bottom - boxA.Top);
    differ := 0;
    for y := 0 to boxA.Bottom - boxA.Top - 1 do
      for x := 0 to boxA.Right - boxA.Left - 1 do
        if a.GetPixel(boxA.Left + x, boxA.Top + y) <> b.GetPixel(boxB.Left + x, boxB.Top + y) then
          Inc(differ);
    AssertEquals('pixels of the label''s words that differ from the canvas''s', 0, differ);
  finally
    a.Free;
    b.Free;
    ref.Free;
  end;
end;

procedure TTextGroundTest.TestAnHtmlLabelHasSubpixels;
var
  lbl: TTyHtmlLabel;
begin
  TyDesktopClearTypeForceForTest(1);
  FCtl.LoadThemeCss('TyHtmlLabel { color: #000000; font-family: ' + CFont + '; font-size: 9px; }');
  lbl := THtmlAccess.Create(FForm);
  lbl.Parent := FForm;
  lbl.Controller := FCtl;
  lbl.Font.PixelsPerInch := 96;
  lbl.SetBounds(0, 0, W, H);
  lbl.Html := CMixed;
  MakeHost(pf24bit, clWhite);
  BeginFrame(FHost);
  try
    THtmlAccess(lbl).RenderTo(FBox.Canvas, Rect(0, 0, W, H), 96);
  finally
    EndFrame(FHost);
  end;
  AssertTrue('the words have subpixels', Colourful(FHost, Rect(0, 0, W, H)) > 50);
end;
{$ENDIF}

initialization
  RegisterTest(TTextGroundTest);

end.
