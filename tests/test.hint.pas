unit test.hint;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry, tyControls.Hint,
  Controls, Forms, tyControls.Edit, tyControls.BalloonHint, tyControls.Notification;

type
  THintTest = class(TTestCase)
  published
    procedure ContentRectAddsPaddingAllSides;
    procedure ContentRectZeroPadding;
  end;

implementation

procedure THintTest.ContentRectAddsPaddingAllSides;
var
  R: TRect;
begin
  // text 40x12, padding L=3 T=2 R=5 B=4  ->  48 x 18
  R := TyHintContentRect(40, 12, 3, 2, 5, 4);
  AssertEquals('left', 0, R.Left);
  AssertEquals('top', 0, R.Top);
  AssertEquals('width', 40 + 3 + 5, R.Right);
  AssertEquals('height', 12 + 2 + 4, R.Bottom);
end;

procedure THintTest.ContentRectZeroPadding;
var
  R: TRect;
begin
  R := TyHintContentRect(30, 10, 0, 0, 0, 0);
  AssertEquals('width', 30, R.Right);
  AssertEquals('height', 10, R.Bottom);
end;


type
  { #178: the hint wraps at MaxWidth; a balloon hint and a toast leave the focus where it was. }
  THint178Test = class(TTestCase)
  published
    procedure TestMaxWidthWrapsTheHint;
  end;

  TPassive178Test = class(TTestCase)
  private
    FForm: TForm;
    FEdit: TTyEdit;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestABalloonHintLeavesTheFocus;
    procedure TestANotificationLeavesTheFocus;
  end;

var
  Passive178WidgetSet: Boolean = False;

procedure THint178Test.TestMaxWidthWrapsTheHint;
var w: TTyHintWindow; one, wrapped: TRect; s: string;
begin
  w := TTyHintWindow.Create(nil);
  try
    s := 'one two three four five six seven eight nine ten eleven twelve';
    one := w.CalcHintRect(0, s, nil);
    wrapped := w.CalcHintRect(120, s, nil);
    AssertTrue(Format('setup: on one line it is wider than 120 (%d)', [one.Right - one.Left]),
      one.Right - one.Left > 120);
    AssertTrue(Format('MaxWidth holds it to 120 (%d)', [wrapped.Right - wrapped.Left]),
      wrapped.Right - wrapped.Left <= 120);
    AssertTrue('on more lines', wrapped.Bottom - wrapped.Top > one.Bottom - one.Top);
    AssertTrue(Format('filling the width it was given, not a word a line (%d)',
      [wrapped.Right - wrapped.Left]), wrapped.Right - wrapped.Left > 70);
    wrapped := w.CalcHintRect(120, '提示文字没有空格也要能在最大宽度处折行显示出来才行', nil);
    AssertTrue(Format('CJK wraps too (%d)', [wrapped.Right - wrapped.Left]),
      wrapped.Right - wrapped.Left <= 120);
  finally
    w.Free;
  end;
end;

procedure TPassive178Test.SetUp;
begin
  if not Passive178WidgetSet then
  begin
    Forms.Application.Initialize;
    Passive178WidgetSet := True;
  end;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 400, 300);   // off screen, but shown: the focus needs it
  FEdit := TTyEdit.Create(FForm);
  FEdit.Parent := FForm;
  FEdit.SetBounds(10, 10, 150, 24);
  FForm.Show;
  Forms.Application.ProcessMessages;
  FEdit.SetFocus;
  Forms.Application.ProcessMessages;
end;

procedure TPassive178Test.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TPassive178Test.TestABalloonHintLeavesTheFocus;
var b: TTyBalloonHint;
begin
  AssertSame('setup: the edit has the focus', FEdit, Screen.ActiveControl);
  b := TTyBalloonHint.Create(nil);
  try
    b.Title := 'Note';
    b.Description := 'A balloon';
    b.HideInterval := 0;
    b.ShowFor(FEdit);
    Forms.Application.ProcessMessages;
    AssertSame('the edit still has the focus', FEdit, Screen.ActiveControl);
    AssertSame('in its form', TCustomForm(FForm), Screen.ActiveCustomForm);
    b.HideHint;
  finally
    b.Free;
  end;
end;

procedure TPassive178Test.TestANotificationLeavesTheFocus;
var n: TTyNotification;
begin
  AssertSame('setup: the edit has the focus', FEdit, Screen.ActiveControl);
  n := TTyNotification.Create(nil);
  try
    n.Title := 'Saved';
    n.Duration := 0;
    n.Show;
    Forms.Application.ProcessMessages;
    AssertSame('the edit still has the focus', FEdit, Screen.ActiveControl);
    AssertSame('in its form', TCustomForm(FForm), Screen.ActiveCustomForm);
    n.Hide;
  finally
    n.Free;
  end;
end;

initialization
  RegisterTest(THint178Test);
  RegisterTest(TPassive178Test);
  RegisterTest(THintTest);
end.
