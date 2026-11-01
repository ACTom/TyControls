unit test.enteresc;

{$mode objfpc}{$H+}

{ #144: Enter and Esc are taken only when the focused control does something with them;
  otherwise they are left alone, and LCL hands them to the form's default and cancel buttons
  on key-up (TApplication.DoReturnKey / DoEscapeKey). A control that clears Key in KeyDown
  keeps them from those buttons. }

interface

uses
  Classes, SysUtils, Controls, Forms, LCLType, fpcunit, testregistry,
  tyControls.SpinEdit, tyControls.DateTimePicker, tyControls.Calculator,
  tyControls.ListView, tyControls.TreeView, tyControls.ToggleSwitch;

type
  TEnterEscTest = class(TTestCase)
  private
    FForm: TForm;
    FDone, FActivated, FResults: Integer;
    procedure Done(Sender: TObject);
    procedure Activated(Sender: TObject; AIndex: Integer);
    procedure NodeActivated(Sender: TTyCustomTreeView; Node: PTyTreeNode);
    procedure CalcResult(Sender: TObject);
    function Press(C: TWinControl; AKey: Word): Word;
    procedure Up(C: TWinControl; AKey: Word);
    procedure TypeChar(C: TWinControl; const AChar: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSpinEdit;
    procedure TestDateTimePicker;
    procedure TestCalculator;
    procedure TestListView;
    procedure TestTreeView;
    procedure TestToggleSwitch;
  end;

implementation

type
  TCrack = class(TWinControl);

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TEnterEscTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 400, 300);
  FDone := 0;
  FActivated := 0;
  FResults := 0;
end;

procedure TEnterEscTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TEnterEscTest.Done(Sender: TObject);
begin
  Inc(FDone);
end;

procedure TEnterEscTest.Activated(Sender: TObject; AIndex: Integer);
begin
  Inc(FActivated);
end;

procedure TEnterEscTest.NodeActivated(Sender: TTyCustomTreeView; Node: PTyTreeNode);
begin
  Inc(FActivated);
end;

procedure TEnterEscTest.CalcResult(Sender: TObject);
begin
  Inc(FResults);
end;

function TEnterEscTest.Press(C: TWinControl; AKey: Word): Word;
begin
  Result := AKey;
  TCrack(C).KeyDown(Result, []);
end;

procedure TEnterEscTest.Up(C: TWinControl; AKey: Word);
var
  k: Word;
begin
  k := AKey;
  TCrack(C).KeyUp(k, []);
end;

procedure TEnterEscTest.TypeChar(C: TWinControl; const AChar: string);
var
  k: TUTF8Char;
begin
  k := AChar;
  TCrack(C).UTF8KeyPress(k);
end;

procedure TEnterEscTest.TestSpinEdit;
var
  s: TTySpinEdit;
begin
  s := TTySpinEdit.Create(FForm);
  s.Parent := FForm;
  s.MaxValue := 100;
  s.Value := 5;
  TCrack(s).OnEditingDone := @Done;
  AssertEquals('Enter goes on to the default button', VK_RETURN, Press(s, VK_RETURN));
  AssertEquals('and is an EditingDone', 1, FDone);
  AssertEquals('Esc with nothing typed goes on to the cancel button', VK_ESCAPE, Press(s, VK_ESCAPE));
  TypeChar(s, '7');
  AssertEquals('Esc with a typed value puts it back, and is taken', 0, Press(s, VK_ESCAPE));
  AssertEquals('the value it put back', 5, s.Value);
  TypeChar(s, '4');
  AssertEquals('Enter after typing still goes on', VK_RETURN, Press(s, VK_RETURN));
  AssertTrue('having committed what was typed', s.Value <> 5);
end;

procedure TEnterEscTest.TestDateTimePicker;
var
  d: TTyDateTimePicker;
begin
  d := TTyDateTimePicker.Create(FForm);
  d.Parent := FForm;
  TCrack(d).OnEditingDone := @Done;
  AssertEquals('Enter goes on to the default button', VK_RETURN, Press(d, VK_RETURN));
  AssertEquals('and is an EditingDone', 1, FDone);
  AssertEquals('Esc goes on to the cancel button', VK_ESCAPE, Press(d, VK_ESCAPE));
end;

procedure TEnterEscTest.TestCalculator;
var
  c: TTyCalculator;
begin
  c := TTyCalculator.Create(FForm);
  c.Parent := FForm;
  c.OnChange := @Done;
  AssertEquals('nothing to evaluate: Enter goes on', VK_RETURN, Press(c, VK_RETURN));
  TypeChar(c, #13);   // the character that follows a key-down left alone
  AssertEquals('and its character changes nothing', 0, FDone);
  AssertEquals('nothing to clear: Esc goes on', VK_ESCAPE, Press(c, VK_ESCAPE));
  c.PressKey('1');
  c.PressKey('+');
  c.PressKey('2');
  AssertEquals('an expression: Enter evaluates it', 0, Press(c, VK_RETURN));
  AssertEquals('to 3', 3, c.Value, 1e-9);
  AssertEquals('a result to clear: Esc clears it', 0, Press(c, VK_ESCAPE));
  AssertEquals('cleared', 0, c.Value, 1e-9);
  c.OnResult := @CalcResult;
  AssertEquals('a host waiting for the result: Enter is the calculator''s', 0, Press(c, VK_RETURN));
  AssertEquals('and reaches it', 1, FResults);
end;

procedure TEnterEscTest.TestListView;
var
  l: TTyListView;
begin
  l := TTyListView.Create(FForm);
  l.Parent := FForm;
  l.Items.Add.Caption := 'one';
  l.ItemIndex := 0;
  AssertEquals('no activation handler: Enter goes on', VK_RETURN, Press(l, VK_RETURN));
  l.OnItemActivate := @Activated;
  AssertEquals('with one: Enter activates the row', 0, Press(l, VK_RETURN));
  AssertEquals('activated', 1, FActivated);
end;

procedure TEnterEscTest.TestTreeView;
var
  t: TTyTreeView;
begin
  t := TTyTreeView.Create(FForm);
  t.Parent := FForm;
  t.FocusedNode := t.AddChild(nil);
  AssertEquals('no OnNodeDblClick: Enter goes on', VK_RETURN, Press(t, VK_RETURN));
  t.OnNodeDblClick := @NodeActivated;
  AssertEquals('with one: Enter activates the node', 0, Press(t, VK_RETURN));
  AssertEquals('activated', 1, FActivated);
end;

procedure TEnterEscTest.TestToggleSwitch;
var
  s: TTyToggleSwitch;
begin
  s := TTyToggleSwitch.Create(FForm);
  s.Parent := FForm;
  AssertEquals('Enter goes on to the default button', VK_RETURN, Press(s, VK_RETURN));
  AssertFalse('and toggles nothing', s.Checked);
  AssertEquals('Space is the switch''s', 0, Press(s, VK_SPACE));
  Up(s, VK_SPACE);
  AssertTrue('and toggles it, on the key-up (#151)', s.Checked);
end;

initialization
  RegisterTest(TEnterEscTest);
end.
