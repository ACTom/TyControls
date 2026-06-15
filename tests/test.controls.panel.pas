unit test.controls.panel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Panel;
type
  TTyPanelTest = class(TTestCase)
  private
    FForm: TForm;
    FPanel: TTyPanel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaultCaptionEmpty;
    procedure TestImplementsStyleable;
    procedure TestHostsChild;
    procedure TestPaintSmoke;
    procedure TestAlignmentMovesCaptionInk;
  end;
implementation
type
  TPanelAccess = class(TTyPanel)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;
procedure TPanelAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;
procedure TTyPanelTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FPanel := TTyPanel.Create(FForm);
  FPanel.Parent := FForm;
end;
procedure TTyPanelTest.TearDown;
begin
  FForm.Free;
end;
procedure TTyPanelTest.TestTypeKey;
begin
  AssertEquals('TyPanel', FPanel.GetStyleTypeKey);
end;
procedure TTyPanelTest.TestDefaultCaptionEmpty;
begin
  AssertEquals('', FPanel.Caption);
end;
procedure TTyPanelTest.TestImplementsStyleable;
var
  Styleable: ITyStyleable;
begin
  AssertTrue('TTyPanel must support ITyStyleable',
    Supports(FPanel, ITyStyleable, Styleable));
  AssertEquals('TyPanel', Styleable.GetStyleTypeKey);
end;
procedure TTyPanelTest.TestHostsChild;
var
  Child: TButton;
begin
  Child := TButton.Create(FPanel);
  Child.Parent := FPanel;
  AssertSame('child parent must be the panel', FPanel, Child.Parent);
  AssertEquals('panel must report one child control', 1, FPanel.ControlCount);
end;
procedure TTyPanelTest.TestPaintSmoke;
var
  Acc: TPanelAccess;
  Bmp: TBitmap;
begin
  Acc := TPanelAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Caption := 'Panel';
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 60);
    Acc.SmokeRender(Bmp.Canvas, Rect(0, 0, 120, 60), 96);
    AssertTrue('panel RenderTo executed without exception', True);
  finally
    Bmp.Free;
  end;
end;
procedure TTyPanelTest.TestAlignmentMovesCaptionInk;
  function InkCentroidX(A: TAlignment): Double;
  var P: TPanelAccess; bmp: TBitmap; reread: TBGRABitmap; x,y,n: Integer; sx: Double; px: TBGRAPixel;
  begin
    P := TPanelAccess.Create(nil);
    bmp := TBitmap.Create;
    try
      P.Caption := 'Hi'; P.Alignment := A; P.Font.PixelsPerInch := 96;
      bmp.PixelFormat := pf32bit; bmp.SetSize(200, 30);
      bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0,0,200,30);
      P.SmokeRender(bmp.Canvas, Rect(0,0,200,30), 96);
      reread := TBGRABitmap.Create(bmp);
      try
        sx := 0; n := 0;
        for x := 0 to 199 do for y := 4 to 26 do
        begin px := reread.GetPixel(x,y);
          if (px.red<160) and (px.green<160) then begin sx := sx + x; Inc(n); end; end;
        if n = 0 then Result := -1 else Result := sx / n;
      finally reread.Free; end;
    finally bmp.Free; P.Free; end;
  end;
var cl, cr: Double;
begin
  cl := InkCentroidX(taLeftJustify);
  cr := InkCentroidX(taRightJustify);
  AssertTrue('left caption has ink', cl > 0);
  AssertTrue('right-aligned caption ink is further right than left-aligned', cr > cl + 20);
end;
initialization
  RegisterTest(TTyPanelTest);
end.
