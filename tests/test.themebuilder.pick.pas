unit test.themebuilder.pick;
{ Ctrl+click in the theme builder's preview (phase 2), through the real path: the mouse
  message is Performed on the control, which is what the widgetset (a windowed control) or
  the parent (a graphic one) does -- so it goes through WindowProc, where the hook is. The
  pick is reported, the control never sees the press; a press without Ctrl goes through.
  The coverage check follows in the second half. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Controls, LMessages, LCLType, tbpreview;

type
  TTbPickTests = class(TTestCase)
  private
    FFrame: TTbPreviewFrame;
    FPicks: Integer;
    FKey, FCls: string;
    FClicks: Integer;
    procedure PickStub(Sender: TObject; const ATypeKey, AStyleClass: string);
    procedure ClickStub(Sender: TObject);
    procedure CtrlDown(AControl: TControl; AX: Integer = 0; AY: Integer = 0);
    procedure PlainDown(AControl: TControl);
    procedure Up(AControl: TControl);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestACtrlPressIsAPickAndNotAPress;
    procedure TestAPlainPressGoesThrough;
    procedure TestTheReleaseAfterAPickIsSwallowed;
    procedure TestADisabledLabel;
    procedure TestAControlWithoutATypeKey;
    procedure TestTheSampleWindow;
    procedure TestTheStripIsNotHooked;
    procedure TestUnhooking;
    procedure TestTheFrameGoesCleanly;
  end;

implementation

uses
  ExtCtrls, tyControls.Base, tyControls.Button, tbpick, tbsamplewin;

type
  TTyCustomControlAccess = class(TTyCustomControl);

procedure TTbPickTests.SetUp;
begin
  FFrame := TTbPreviewFrame.Create(nil);
  FFrame.OnPick := @PickStub;
  FPicks := 0;
  FKey := '';
  FCls := '';
  FClicks := 0;
end;

procedure TTbPickTests.TearDown;
begin
  FreeAndNil(FFrame);
end;

procedure TTbPickTests.PickStub(Sender: TObject; const ATypeKey, AStyleClass: string);
begin
  Inc(FPicks);
  FKey := ATypeKey;
  FCls := AStyleClass;
end;

procedure TTbPickTests.ClickStub(Sender: TObject);
begin
  Inc(FClicks);
end;

procedure TTbPickTests.CtrlDown(AControl: TControl; AX: Integer; AY: Integer);
begin
  AControl.Perform(LM_LBUTTONDOWN, MK_LBUTTON or MK_CONTROL, LPARAM((AY shl 16) or (AX and $FFFF)));
end;

procedure TTbPickTests.PlainDown(AControl: TControl);
begin
  AControl.Perform(LM_LBUTTONDOWN, MK_LBUTTON, 0);
end;

procedure TTbPickTests.Up(AControl: TControl);
begin
  AControl.Perform(LM_LBUTTONUP, 0, 0);
end;

procedure TTbPickTests.TestACtrlPressIsAPickAndNotAPress;
begin
  FFrame.BtnPrimary.OnClick := @ClickStub;
  CtrlDown(FFrame.BtnPrimary);
  AssertEquals('P1: one pick', 1, FPicks);
  AssertEquals('P1: the typeKey', 'TyButton', FKey);
  AssertEquals('P1: the variant', 'primary', FCls);
  AssertFalse('P1: the button was not pressed', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  Up(FFrame.BtnPrimary);
  AssertEquals('P1: and not clicked', 0, FClicks);
end;

procedure TTbPickTests.TestAPlainPressGoesThrough;
begin
  PlainDown(FFrame.BtnPrimary);
  AssertEquals('P2: no pick', 0, FPicks);
  AssertTrue('P2: the button was pressed', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  Up(FFrame.BtnPrimary);
  AssertFalse('P2: and released', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
end;

procedure TTbPickTests.TestTheReleaseAfterAPickIsSwallowed;
begin
  FFrame.BtnPrimary.OnClick := @ClickStub;
  CtrlDown(FFrame.BtnPrimary);
  Up(FFrame.BtnPrimary);      { Ctrl let go before the button: still the pick's release }
  AssertEquals('P3: not clicked', 0, FClicks);
  AssertFalse('P3: not pressed', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  PlainDown(FFrame.BtnPrimary);
  AssertTrue('P3: the next plain press goes through', TTyCustomControlAccess(FFrame.BtnPrimary).FPressed);
  Up(FFrame.BtnPrimary);
end;

procedure TTbPickTests.TestADisabledLabel;
var
  lbl: TControl;
begin
  lbl := FFrame.LblDisabled;
  AssertFalse('disabled', lbl.Enabled);
  CtrlDown(lbl.Parent, lbl.Left + lbl.Width div 2, lbl.Top + lbl.Height div 2);
  AssertEquals('P4: one pick', 1, FPicks);
  AssertEquals('P4: the label', 'TyLabel', FKey);
  AssertEquals('P4: no variant', '', FCls);
end;

procedure TTbPickTests.TestAControlWithoutATypeKey;
var
  shape: TShape;
begin
  shape := TShape.Create(nil);
  try
    shape.SetBounds(4, 4, 20, 20);
    shape.Parent := FFrame.PnlSample;
    FFrame.Picker.HookTree(FFrame.PnlSample);
    CtrlDown(shape);
    AssertEquals('P5: one pick', 1, FPicks);
    AssertEquals('P5: the nearest Ty control', 'TyPanel', FKey);
    AssertEquals('P5: no variant', '', FCls);
  finally
    shape.Free;
  end;
end;

procedure TTbPickTests.TestTheSampleWindow;
var
  win: TTbSampleForm;
begin
  win := FFrame.BuildSampleWindow;
  CtrlDown(win.BtnOk);
  AssertEquals('P6: one pick', 1, FPicks);
  AssertEquals('P6: the typeKey', 'TyButton', FKey);
  AssertEquals('P6: the variant', 'primary', FCls);
end;

procedure TTbPickTests.TestTheStripIsNotHooked;
begin
  CtrlDown(FFrame.DarkSwitch);
  Up(FFrame.DarkSwitch);
  AssertEquals('P7: the strip is the tool''s', 0, FPicks);
end;

procedure TTbPickTests.TestUnhooking;
var
  b: TTyButton;
  p: TTbPicker;
  before: TWndMethod;
begin
  b := TTyButton.Create(nil);
  p := TTbPicker.Create(nil);
  try
    before := b.WindowProc;
    p.HookTree(b);
    AssertEquals('P8: one hook', 1, p.HookCount);
    AssertFalse('P8: hooked', TMethod(b.WindowProc).Code = TMethod(before).Code);
    p.UnhookAll;
    AssertEquals('P8: none', 0, p.HookCount);
    AssertTrue('P8: the old one is back (code)', TMethod(b.WindowProc).Code = TMethod(before).Code);
    AssertTrue('P8: the old one is back (data)', TMethod(b.WindowProc).Data = TMethod(before).Data);
  finally
    b.Free;
    p.Free;
  end;
  { the control goes first: the hook forgets it, the picker goes without touching it }
  b := TTyButton.Create(nil);
  p := TTbPicker.Create(nil);
  try
    p.HookTree(b);
    FreeAndNil(b);
    AssertEquals('P8: the freed control is forgotten', 0, p.HookCount);
  finally
    b.Free;
    p.Free;
  end;
end;

procedure TTbPickTests.TestTheFrameGoesCleanly;
begin
  FFrame.BuildSampleWindow;
  CtrlDown(FFrame.BtnPrimary);
  AssertEquals('a pick', 1, FPicks);
  FreeAndNil(FFrame);
  AssertNull('P9: gone', FFrame);
end;

initialization
  RegisterTest(TTbPickTests);
end.
