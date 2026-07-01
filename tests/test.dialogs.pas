unit test.dialogs;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Dialogs, fpcunit, testregistry,
  tyControls.Types, tyControls.Dialogs;
type
  TDialogButtonBarTest = class(TTestCase)
  published
    procedure TestSingleButtonRightAligned;
    procedure TestTwoButtonsOrderedRightToLeft;
    procedure TestMarginAndSpacing;
  end;

  TMsgMappingTest = class(TTestCase)
  published
    procedure TestButtonResult;
    procedure TestButtonCaptionNonEmpty;
    procedure TestOrderedButtonsCompleteAndStable;
    procedure TestTypeSymbol;
    procedure TestEmptyButtonsDefaultsOK;
  end;
implementation

procedure TDialogButtonBarTest.TestSingleButtonRightAligned;
var r: TTyRectArray;
begin
  // one 80-wide button in a 300 bar, margin 12 -> right edge at 300-12=288, left at 208
  r := TyDialogButtonBar([Size(80, 28)], 300, 12, 8);
  AssertEquals('count', 1, Length(r));
  AssertEquals('right', 288, r[0].Right);
  AssertEquals('left', 208, r[0].Left);
end;

procedure TDialogButtonBarTest.TestTwoButtonsOrderedRightToLeft;
var r: TTyRectArray;
begin
  // buttons[0]=60, buttons[1]=80; index 0 is the RIGHTMOST (primary). margin 12, spacing 8.
  // r[0] right=288 left=228 ; r[1] right=228-8=220 left=140
  r := TyDialogButtonBar([Size(60, 28), Size(80, 28)], 300, 12, 8);
  AssertEquals('r0.right', 288, r[0].Right);
  AssertEquals('r0.left', 228, r[0].Left);
  AssertEquals('r1.right', 220, r[1].Right);
  AssertEquals('r1.left', 140, r[1].Left);
end;

procedure TDialogButtonBarTest.TestMarginAndSpacing;
var r: TTyRectArray;
begin
  r := TyDialogButtonBar([Size(50, 24), Size(50, 24)], 200, 10, 6);
  AssertEquals('r0.right', 190, r[0].Right);   // 200-10
  AssertEquals('r1.right', 134, r[1].Right);   // 190-50-6
end;

procedure TMsgMappingTest.TestButtonResult;
begin
  AssertEquals('yes', Ord(mrYes), Ord(TyMsgButtonResult(mbYes)));
  AssertEquals('no', Ord(mrNo), Ord(TyMsgButtonResult(mbNo)));
  AssertEquals('ok', Ord(mrOK), Ord(TyMsgButtonResult(mbOK)));
  AssertEquals('cancel', Ord(mrCancel), Ord(TyMsgButtonResult(mbCancel)));
end;

procedure TMsgMappingTest.TestButtonCaptionNonEmpty;
var b: TMsgDlgBtn;
begin
  for b := Low(TMsgDlgBtn) to High(TMsgDlgBtn) do
    AssertTrue('caption for '+IntToStr(Ord(b)), TyMsgButtonCaption(b) <> '');
end;

procedure TMsgMappingTest.TestOrderedButtonsCompleteAndStable;
var a: TMsgDlgBtnArray;
begin
  a := TyMsgOrderedButtons([mbYes, mbNo, mbCancel]);
  AssertEquals('n', 3, Length(a));
  AssertTrue('yes first', a[0] = mbYes);
  AssertTrue('no second', a[1] = mbNo);
  AssertTrue('cancel third', a[2] = mbCancel);
end;

procedure TMsgMappingTest.TestTypeSymbol;
begin
  AssertTrue('warning symbol', TyMsgTypeSymbol(mtWarning) <> '');
  AssertTrue('error symbol', TyMsgTypeSymbol(mtError) <> '');
  AssertTrue('confirmation symbol', TyMsgTypeSymbol(mtConfirmation) <> '');
end;

procedure TMsgMappingTest.TestEmptyButtonsDefaultsOK;
var a: TMsgDlgBtnArray;
begin
  a := TyMsgOrderedButtons([]);
  AssertEquals('empty -> OK', 1, Length(a));
  AssertTrue('is OK', a[0] = mbOK);
end;

initialization
  RegisterTest(TDialogButtonBarTest);
  RegisterTest(TMsgMappingTest);
end.
