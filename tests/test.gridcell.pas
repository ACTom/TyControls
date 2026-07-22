unit test.gridcell;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, TypInfo, fpcunit, testregistry,
  tyControls.GridCell;
type
  TTyGridCellTest = class(TTestCase)
  published
    procedure TestPublishesDesignerProperties;
    procedure TestPaddingInsetsClientRect;
    procedure TestAlClientChildConstrainedToCell;
  end;
implementation

type
  { Exposes the protected AdjustClientRect so the padded content rect can be probed
    headlessly — LCL's ClientRect does NOT apply AdjustClientRect (it only insets the
    area used to align children), so we call the override directly, as test.card /
    test.expanel do for the same reason. }
  TCellAccess = class(TTyGridCell)
  public
    function AdjustedClient: TRect;
  end;

function TCellAccess.AdjustedClient: TRect;
begin
  Result := Rect(0, 0, Width, Height);
  AdjustClientRect(Result);
end;

procedure TTyGridCellTest.TestPublishesDesignerProperties;
const cMust: array[0..6] of string =
  ('Padding', 'Col', 'Row', 'Align', 'Anchors', 'Visible', 'BorderSpacing');
var i: Integer;
begin
  for i := 0 to High(cMust) do
    AssertTrue('TTyGridCell must publish ' + cMust[i],
      GetPropInfo(TTyGridCell, cMust[i]) <> nil);
end;

procedure TTyGridCellTest.TestPaddingInsetsClientRect;
var cell: TCellAccess; r: TRect;
begin
  cell := TCellAccess.Create(nil);
  try
    cell.Font.PixelsPerInch := 96;   // pin DPI so MulDiv(pad,ppi,96) is exact
    cell.SetBounds(0, 0, 100, 80);
    cell.Padding := 10;
    r := cell.AdjustedClient;         // AdjustClientRect applied
    AssertEquals('left inset',   10, r.Left);
    AssertEquals('top inset',    10, r.Top);
    AssertEquals('right inset',  90, r.Right);
    AssertEquals('bottom inset', 70, r.Bottom);
  finally
    cell.Free;
  end;
end;

procedure TTyGridCellTest.TestAlClientChildConstrainedToCell;
var cell: TCellAccess; child: TControl; r: TRect;
begin
  { An alClient child is bounded by the cell's AdjustClientRect (the LCL alignment
    contract). We assert that rect directly: realizing a real window handle is not
    possible in the headless runner ("failed to create win32 control"), so — as
    test.card / test.expanel do — we probe the constraint through AdjustClientRect. }
  cell := TCellAccess.Create(nil);
  try
    cell.Font.PixelsPerInch := 96;
    cell.SetBounds(5, 5, 100, 80);
    cell.Padding := 8;
    child := TControl.Create(cell);
    child.Parent := cell;
    child.Align := alClient;          // the scenario: a dropped, cell-filling child
    r := cell.AdjustedClient;         // the padded interior an alClient child receives
    AssertEquals('constrained left',   8, r.Left);
    AssertEquals('constrained top',    8, r.Top);
    AssertEquals('fills padded width',  100 - 8 - 8, r.Right - r.Left);
    AssertEquals('fills padded height', 80 - 8 - 8, r.Bottom - r.Top);
    // "constrained" = never exceeds the cell on any side
    AssertTrue('inside the cell (right)',  r.Right <= cell.Width);
    AssertTrue('inside the cell (bottom)', r.Bottom <= cell.Height);
  finally
    cell.Free;
  end;
end;

initialization
  RegisterTest(TTyGridCellTest);
end.
