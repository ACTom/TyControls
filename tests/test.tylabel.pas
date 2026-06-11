unit test.tylabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, Graphics,
  tyControls.Base, tyControls.TyLabel;
type
  TTyLabelAccess = class(TTyLabel)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TLabelTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestCaptionProperty;
    procedure TestPaintSmoke;
  end;
implementation

procedure TTyLabelAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
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

initialization
  RegisterTest(TLabelTest);
end.
