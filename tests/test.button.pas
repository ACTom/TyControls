unit test.button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Forms, Controls, Graphics, LCLType,
  tyControls.Base, tyControls.Button;
type
  // Expose protected RenderTo for testing
  TTyButtonAccess = class(TTyButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
    // Drive the CM_DIALOGKEY handler headlessly: build a TCMDialogKey carrying
    // ACharCode and dispatch it, exercising the same routing a real form would.
    procedure DispatchDialogKey(ACharCode: Word);
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
    procedure TestAnimationsEnabledIsPublished;
    procedure TestModalResultSetOnClick;
    procedure TestDefaultRespondsToEnter;
    procedure TestCancelRespondsToEscape;
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

procedure TTyButtonAccess.DispatchDialogKey(ACharCode: Word);
var
  Msg: TCMDialogKey;
begin
  FillChar(Msg, SizeOf(Msg), 0);
  Msg.Msg := CM_DIALOGKEY;
  Msg.CharCode := ACharCode;
  Dispatch(Msg);
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

procedure TButtonTest.TestAnimationsEnabledIsPublished;
var
  B: TTyButton;
begin
  B := TTyButton.Create(nil);
  try
    AssertTrue('AnimationsEnabled is a published property (designer/streaming access)',
      IsPublishedProp(B, 'AnimationsEnabled'));
  finally
    B.Free;
  end;
end;

procedure TButtonTest.TestModalResultSetOnClick;
var
  F: TCustomForm;
  B: TTyButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButton.Create(F);
    B.Parent := F;
    B.ModalResult := mrOk;
    AssertEquals('form ModalResult starts unset', mrNone, F.ModalResult);
    B.Click;
    AssertEquals('click sets host form ModalResult', mrOk, F.ModalResult);
  finally
    F.Free;
  end;
end;

procedure TButtonTest.TestDefaultRespondsToEnter;
var
  B: TTyButtonAccess;
begin
  // Default=True => the dialog-key seam wants VK_RETURN (Enter triggers Click),
  // and does NOT want VK_ESCAPE.
  FClicked := 0;
  B := TTyButtonAccess.Create(nil);
  try
    B.OnClick := @HandleClick;
    B.Default := True;
    AssertTrue('Default wants VK_RETURN', B.WantsDialogKey(VK_RETURN));
    AssertFalse('Default does NOT want VK_ESCAPE', B.WantsDialogKey(VK_ESCAPE));
    // The seam-driven dialog-key dispatch fires Click for the wanted key only.
    B.DispatchDialogKey(VK_ESCAPE);
    AssertEquals('Escape does not click a Default button', 0, FClicked);
    B.DispatchDialogKey(VK_RETURN);
    AssertEquals('Enter clicks a Default button', 1, FClicked);
  finally
    B.Free;
  end;
end;

procedure TButtonTest.TestCancelRespondsToEscape;
var
  B: TTyButtonAccess;
begin
  // Cancel=True => the dialog-key seam wants VK_ESCAPE (Esc triggers Click),
  // and does NOT want VK_RETURN.
  FClicked := 0;
  B := TTyButtonAccess.Create(nil);
  try
    B.OnClick := @HandleClick;
    B.Cancel := True;
    AssertTrue('Cancel wants VK_ESCAPE', B.WantsDialogKey(VK_ESCAPE));
    AssertFalse('Cancel does NOT want VK_RETURN', B.WantsDialogKey(VK_RETURN));
    B.DispatchDialogKey(VK_RETURN);
    AssertEquals('Enter does not click a Cancel button', 0, FClicked);
    B.DispatchDialogKey(VK_ESCAPE);
    AssertEquals('Escape clicks a Cancel button', 1, FClicked);
  finally
    B.Free;
  end;
end;

initialization
  RegisterTest(TButtonTest);
end.
