unit test.tylabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, Forms, Controls, StdCtrls,
  Graphics, BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.TyLabel;
type
  TTyLabelAccess = class(TTyLabel)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallPreferredSize(var W, H: Integer);
    procedure DoClick;
  end;

  { Handle-free focus target: reports focusable and records SetFocus so the
    click-to-focus path is verifiable headlessly (no win32 handle / no 1407). }
  TFocusProbe = class(TEdit)
  public
    Focused_: Boolean;
    function CanFocus: Boolean; override;
    procedure SetFocus; override;
  end;

  TLabelTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestCaptionProperty;
    procedure TestPaintSmoke;
    procedure TestAlignmentLayoutRender;
    procedure TestAutoSizeFitsCaption;
    procedure TestWordWrapWraps;
    procedure TestFocusControlOnClick;
    procedure TestTransparentDefault;
  end;
implementation

procedure TTyLabelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyLabelAccess.CallPreferredSize(var W, H: Integer);
begin
  CalculatePreferredSize(W, H, True);
end;

procedure TTyLabelAccess.DoClick;
begin
  Click;
end;

function TFocusProbe.CanFocus: Boolean;
begin
  Result := True;
end;

procedure TFocusProbe.SetFocus;
begin
  Focused_ := True;
end;

procedure TLabelTest.TestTypeKey;
var
  L: TTyLabel;
begin
  L := TTyLabel.Create(nil);
  try
    AssertEquals('TyLabel', (L as ITyStyleable).GetStyleTypeKey);
  finally
    L.Free;
  end;
end;

procedure TLabelTest.TestCaptionProperty;
var
  L: TTyLabel;
begin
  L := TTyLabel.Create(nil);
  try
    L.Caption := 'Hello';
    AssertEquals('Hello', L.Caption);
  finally
    L.Free;
  end;
end;

procedure TLabelTest.TestPaintSmoke;
var
  F: TCustomForm;
  L: TTyLabelAccess;
  Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    L := TTyLabelAccess.Create(F);
    L.Parent := F;
    L.Caption := 'Label';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 20);
    L.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 20), 96);
    AssertTrue('label RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

{ Ink centroid (X and Y) of the dark caption pixels over a white backdrop,
  rendered with the given Alignment/Layout. }
procedure RenderCentroid(A: TAlignment; L: TTextLayout; out CX, CY: Double);
var
  G: TTyLabelAccess; Bmp: TBitmap; Reread: TBGRABitmap;
  x, y, n: Integer; sx, sy: Double; px: TBGRAPixel;
begin
  G := TTyLabelAccess.Create(nil); Bmp := TBitmap.Create;
  try
    G.Caption := 'Hi'; G.Alignment := A; G.Layout := L; G.Font.PixelsPerInch := 96;
    Bmp.PixelFormat := pf32bit; Bmp.SetSize(200, 60);
    Bmp.Canvas.Brush.Color := clWhite; Bmp.Canvas.FillRect(0, 0, 200, 60);
    G.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 60), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      sx := 0; sy := 0; n := 0;
      for x := 0 to 199 do for y := 0 to 59 do
      begin
        px := Reread.GetPixel(x, y);
        if (px.red < 160) and (px.green < 160) then
        begin sx := sx + x; sy := sy + y; Inc(n); end;
      end;
      if n = 0 then begin CX := -1; CY := -1; end
      else begin CX := sx / n; CY := sy / n; end;
    finally Reread.Free; end;
  finally Bmp.Free; G.Free; end;
end;

procedure TLabelTest.TestAlignmentLayoutRender;
var
  lcx, lcy, rcx, rcy, tcy, bcy, dummy: Double;
begin
  RenderCentroid(taLeftJustify, tlCenter, lcx, lcy);
  RenderCentroid(taRightJustify, tlCenter, rcx, dummy);
  AssertTrue('left-aligned caption ink present', lcx > 0);
  AssertTrue('right-aligned caption further right', rcx > lcx + 20);

  RenderCentroid(taLeftJustify, tlTop, dummy, tcy);
  RenderCentroid(taLeftJustify, tlBottom, dummy, bcy);
  AssertTrue('top layout ink present', tcy > 0);
  AssertTrue('bottom-layout caption lower than top-layout', bcy > tcy + 15);
end;

procedure TLabelTest.TestAutoSizeFitsCaption;
var
  L: TTyLabelAccess; wShort, hShort, wLong, hLong, wWrap, hWrap: Integer;
begin
  // AutoSize drives CalculatePreferredSize; assert the measured extent tracks the
  // caption. (Applying it to on-screen bounds needs a window handle, flaky headless.)
  L := TTyLabelAccess.Create(nil);
  try
    L.Font.PixelsPerInch := 96;
    AssertFalse('AutoSize default False', L.AutoSize);
    L.AutoSize := True;
    AssertTrue('AutoSize settable True', L.AutoSize);

    L.Caption := 'Hi';
    wShort := 0; hShort := 0; L.CallPreferredSize(wShort, hShort);
    AssertTrue('short caption preferred width > 0', wShort > 0);
    AssertTrue('preferred height fits a line (>=8px)', hShort >= 8);

    L.Caption := 'A much wider caption text here';
    wLong := 0; hLong := 0; L.CallPreferredSize(wLong, hLong);
    AssertTrue('wider caption -> wider preferred width', wLong > wShort + 40);

    // WordWrap+AutoSize: at a narrow width the wrapped text is taller (>1 line).
    L.Width := 60;
    L.WordWrap := True;
    L.Caption := 'one two three four five six';
    wWrap := 0; hWrap := 0; L.CallPreferredSize(wWrap, hWrap);
    AssertTrue('wrapped preferred width bounded by control width', wWrap <= 60 + 8);
    AssertTrue('wrapped preferred height spans multiple lines', hWrap > hShort + 8);
  finally
    L.Free;
  end;
end;

procedure TLabelTest.TestWordWrapWraps;
  function InkBands(WordWrap: Boolean): Integer;
  var
    G: TTyLabelAccess; Bmp: TBitmap; Reread: TBGRABitmap;
    x, y, bands: Integer; rowHasInk, prevRowInk: Boolean; px: TBGRAPixel;
  begin
    G := TTyLabelAccess.Create(nil); Bmp := TBitmap.Create;
    try
      G.Font.PixelsPerInch := 96;
      G.WordWrap := WordWrap;
      G.Caption := 'one two three four five six';
      Bmp.PixelFormat := pf32bit; Bmp.SetSize(60, 80);
      Bmp.Canvas.Brush.Color := clWhite; Bmp.Canvas.FillRect(0, 0, 60, 80);
      G.RenderTo(Bmp.Canvas, Rect(0, 0, 60, 80), 96);
      Reread := TBGRABitmap.Create(Bmp);
      try
        bands := 0; prevRowInk := False;
        for y := 0 to 79 do
        begin
          rowHasInk := False;
          for x := 0 to 59 do
          begin
            px := Reread.GetPixel(x, y);
            if (px.red < 160) and (px.green < 160) then
            begin rowHasInk := True; Break; end;
          end;
          if rowHasInk and not prevRowInk then Inc(bands);
          prevRowInk := rowHasInk;
        end;
        Result := bands;
      finally Reread.Free; end;
    finally Bmp.Free; G.Free; end;
  end;
begin
  AssertEquals('no-wrap single ink band', 1, InkBands(False));
  AssertTrue('word-wrap produces >1 ink band', InkBands(True) >= 2);
end;

procedure TLabelTest.TestFocusControlOnClick;
var
  L: TTyLabelAccess; E: TFocusProbe;
begin
  E := TFocusProbe.Create(nil);
  L := TTyLabelAccess.Create(nil);
  try
    L.FocusControl := E;
    AssertSame('FocusControl round-trips', TWinControl(E), L.FocusControl);
    AssertFalse('not focused before click', E.Focused_);
    L.DoClick;
    AssertTrue('clicking label focuses the FocusControl (CanFocus path)', E.Focused_);

    // No target: Click must be a safe no-op.
    L.FocusControl := nil;
    L.DoClick;
    AssertTrue('click with nil FocusControl does not raise', True);
  finally
    L.Free;
    E.Free;
  end;
end;

procedure TLabelTest.TestTransparentDefault;
var
  L: TTyLabel;
  G: TTyLabelAccess; Bmp: TBitmap; Reread: TBGRABitmap; px: TBGRAPixel;
begin
  L := TTyLabel.Create(nil);
  try
    AssertTrue('Transparent default is True', L.Transparent);
  finally
    L.Free;
  end;

  // Default (transparent): a white backdrop shows through where there is no text.
  G := TTyLabelAccess.Create(nil); Bmp := TBitmap.Create;
  try
    G.Font.PixelsPerInch := 96;
    G.Caption := '';
    Bmp.PixelFormat := pf32bit; Bmp.SetSize(80, 24);
    Bmp.Canvas.Brush.Color := clWhite; Bmp.Canvas.FillRect(0, 0, 80, 24);
    G.RenderTo(Bmp.Canvas, Rect(0, 0, 80, 24), 96);
    Reread := TBGRABitmap.Create(Bmp);
    try
      px := Reread.GetPixel(40, 12);
      AssertTrue('transparent label leaves backdrop white', (px.red > 240) and (px.green > 240) and (px.blue > 240));
    finally Reread.Free; end;
  finally Bmp.Free; G.Free; end;
end;

initialization
  RegisterTest(TLabelTest);
end.
