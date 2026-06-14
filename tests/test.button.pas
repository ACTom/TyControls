unit test.button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, Graphics, LCLType,
  tyControls.Base, tyControls.Button;
type
  // Expose protected RenderTo for testing
  TTyButtonAccess = class(TTyButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
  end;

  TButtonTest = class(TTestCase)
  private
    FClicked: Integer;
    procedure HandleClick(Sender: TObject);
  published
    procedure TestTypeKey;
    procedure TestOnClickFires;
    procedure TestPaintSmoke;
    procedure TestSpaceKeyFiresClick;
    procedure TestDisabledKeyNotConsumedNoClick;
  end;
implementation

procedure TTyButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyButtonAccess.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TButtonTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TButtonTest.TestTypeKey;
var
  B: TTyButton;
begin
  B := TTyButton.Create(nil);
  try
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TButtonTest.TestOnClickFires;
var
  F: TCustomForm;
  B: TTyButton;
begin
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButton.Create(F);
    B.Parent := F;
    B.OnClick := @HandleClick;
    B.Click;
    AssertEquals(1, FClicked);
  finally
    F.Free;
  end;
end;

procedure TButtonTest.TestPaintSmoke;
var
  F: TCustomForm;
  B: TTyButtonAccess;
  Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    B := TTyButtonAccess.Create(F);
    B.Parent := F;
    B.Caption := 'OK';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(80, 28);
    // This actually executes paint code — if RenderTo raises, test fails
    B.RenderTo(Bmp.Canvas, Rect(0, 0, 80, 28), 96);
    AssertTrue('button RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

procedure TButtonTest.TestSpaceKeyFiresClick;
var F: TCustomForm; B: TTyButtonAccess; K: Word;
begin
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButtonAccess.Create(F); B.Parent := F; B.OnClick := @HandleClick;
    K := VK_SPACE; B.DoKeyDown(K, []);
    AssertEquals('space fired click', 1, FClicked);
    AssertEquals('space consumed', 0, K);
    K := VK_RETURN; B.DoKeyDown(K, []);
    AssertEquals('enter fired click', 2, FClicked);
  finally F.Free; end;
end;

procedure TButtonTest.TestDisabledKeyNotConsumedNoClick;
var F: TCustomForm; B: TTyButtonAccess; K: Word;
begin
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButtonAccess.Create(F); B.Parent := F; B.OnClick := @HandleClick;
    B.Enabled := False;
    K := VK_SPACE; B.DoKeyDown(K, []);
    AssertEquals('disabled: no click', 0, FClicked);
    AssertEquals('disabled: key NOT consumed', VK_SPACE, K);
  finally F.Free; end;
end;

initialization
  RegisterTest(TButtonTest);
end.
