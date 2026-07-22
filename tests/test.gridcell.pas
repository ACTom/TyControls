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
    procedure TestAlClientChildReceivesPaddedInterior;
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

procedure TTyGridCellTest.TestAlClientChildReceivesPaddedInterior;
var cell: TCellAccess; r: TRect;
begin
  { An alClient child is bounded by the cell's AdjustClientRect (the LCL alignment
    contract) — so this probes the padded interior a dropped child RECEIVES, and that
    it never exceeds the cell. The actual child-bounds placement is realized by LCL's
    alignment engine (needs a live window handle, which the headless runner cannot
    create — "failed to create win32 control"); that end-to-end constraint is
    IDE/user-verified. Here we assert the rect directly, as test.card / test.expanel do. }
  cell := TCellAccess.Create(nil);
  try
    cell.Font.PixelsPerInch := 96;
    cell.SetBounds(5, 5, 100, 80);
    cell.Padding := 8;
    r := cell.AdjustedClient;         // the padded interior an alClient child receives
    AssertEquals('interior left',   8, r.Left);
    AssertEquals('interior top',    8, r.Top);
    AssertEquals('fills padded width',  100 - 8 - 8, r.Right - r.Left);
    AssertEquals('fills padded height', 80 - 8 - 8, r.Bottom - r.Top);
    // never exceeds the cell on any side
    AssertTrue('inside the cell (right)',  r.Right <= cell.Width);
    AssertTrue('inside the cell (bottom)', r.Bottom <= cell.Height);
  finally
    cell.Free;
  end;
end;

initialization
  RegisterTest(TTyGridCellTest);
end.
