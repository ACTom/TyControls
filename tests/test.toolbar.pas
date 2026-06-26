unit test.toolbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.ToolBar, tyControls.Button;
type
  TToolBarGeomTest = class(TTestCase)
  published
    procedure TestLayoutSingleRow;
    procedure TestLayoutWraps;
  end;

  TTyToolBarAccess = class(TTyToolBar)
  public
    procedure ForceLayout;
  end;

  TToolBarControlTest = class(TTestCase)
  published
    procedure TestArrangesButtons;
  end;

implementation

{ TTyToolBarAccess }
procedure TTyToolBarAccess.ForceLayout;
var dummy: TRect;
begin
  // AlignControls uses ClientWidth internally (it ignores the ARect arg); in the headless
  // runner ClientWidth matches TB.Width, so positions are deterministic.
  dummy := Rect(0, 0, Width, Height);
  AlignControls(nil, dummy);
end;
procedure TToolBarGeomTest.TestLayoutSingleRow;
var r: TTyRectArray; rows: Integer;
begin
  // two 40x20 items, indent 4, spacing 2, buttonHeight 24, bar 200 wide
  r := TyToolbarLayout([Size(40,20), Size(40,20)], 200, 4, 2, 24, True, rows);
  AssertEquals('rows', 1, rows);
  AssertEquals('i0.left', 4, r[0].Left);     AssertEquals('i0.right', 44, r[0].Right);
  AssertEquals('i1.left', 46, r[1].Left);    AssertEquals('i1.right', 86, r[1].Right);
  AssertEquals('i0.height=buttonHeight', 24, r[0].Bottom - r[0].Top);
end;
procedure TToolBarGeomTest.TestLayoutWraps;
var r: TTyRectArray; rows: Integer;
begin
  // bar only 90 wide -> third item wraps to row 2
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], 90, 4, 2, 24, True, rows);
  AssertEquals('rows', 2, rows);
  AssertEquals('i2 wrapped to indent', 4, r[2].Left);
  AssertEquals('i2.Top = indent + buttonHeight + spacing', 30, r[2].Top);
end;

{ TToolBarControlTest }

procedure TToolBarControlTest.TestArrangesButtons;
var
  Form: TForm;
  TB: TTyToolBarAccess;
  B1, B2: TTyButton;
  ExpectedLeft: Integer;
begin
  // In headless LCL, Realign posts a deferred message that is never processed
  // without a message pump.  We use a thin probe subclass (TTyToolBarAccess)
  // that calls AlignControls directly, bypassing the deferred path.
  // Width is set explicitly so ClientWidth is a known bar width; AlignControls
  // uses ClientWidth internally (it ignores the ARect arg), so positions are deterministic.
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 200);

    TB := TTyToolBarAccess.Create(Form);
    TB.Parent := Form;
    // alNone: prevent LCL alignment engine from fighting our explicit bounds
    TB.Align := alNone;
    TB.Width := 300;
    TB.Indent := 4;
    TB.ButtonSpacing := 2;
    TB.ButtonHeight := 24;
    TB.Wrapable := True;

    B1 := TTyButton.Create(Form);
    B1.Parent := TB;
    B1.Width := 60;

    B2 := TTyButton.Create(Form);
    B2.Parent := TB;
    B2.Width := 60;

    // Direct synchronous layout call (probe exposes the protected AlignControls).
    // The dummy rect uses TB.Width so the bar-width is 300 and no wrapping occurs.
    TB.ForceLayout;

    // Button 1 should start at Indent; Button 2 right after: Indent + B1.Width + ButtonSpacing
    AssertEquals('b1.Left = indent', TB.Indent, B1.Left);
    ExpectedLeft := TB.Indent + B1.Width + TB.ButtonSpacing;
    AssertEquals('b2.Left = indent + b1.width + spacing', ExpectedLeft, B2.Left);
  finally
    Form.Free;
  end;
end;

initialization
  RegisterTest(TToolBarGeomTest);
  RegisterTest(TToolBarControlTest);
end.
