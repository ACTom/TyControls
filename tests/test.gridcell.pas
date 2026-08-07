unit test.gridcell;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, TypInfo,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Panel, tyControls.GridCell;
type
  TTyGridCellTest = class(TTestCase)
  published
    procedure TestPublishesDesignerProperties;
    procedure TestPaddingInsetsClientRect;
    procedure TestAlClientChildReceivesPaddedInterior;
    procedure TestOwnTypeKeyNotTheDataGridCell;
    procedure TestPaintTakesTheParentBackground;
  end;
implementation

type
  { Exposes the protected AdjustClientRect so the padded content rect can be probed
    headlessly — LCL's ClientRect does NOT apply AdjustClientRect (it only insets the
    area used to align children), so we call the override directly, as test.card /
    test.expanel do for the same reason. Also exposes GetStyleTypeKey and the split-out
    RenderTo, the same access-subclass pattern test.bevel uses to drive a paint path
    with no window handle. }
  TCellAccess = class(TTyGridCell)
  public
    function AdjustedClient: TRect;
    function StyleTypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

function TCellAccess.AdjustedClient: TRect;
begin
  Result := Rect(0, 0, Width, Height);
  AdjustClientRect(Result);
end;

function TCellAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TCellAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
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

{ The layout cell answered to 'TyGridCell' — the DATA grid's body-cell key, which
  themes/light.tycss defines (background/color/padding plus :hover and :selected). One key,
  two unrelated controls: a skin tinting data cells silently tinted every layout cell, and a
  skin wanting to give the layout cell a surface could not, because the data cell's base rule
  is `background: none` by design. Pin the split so nobody re-borrows it. }
procedure TTyGridCellTest.TestOwnTypeKeyNotTheDataGridCell;
var cell: TCellAccess;
begin
  cell := TCellAccess.Create(nil);
  try
    AssertEquals('the layout cell owns TyGridPanelCell',
      'TyGridPanelCell', cell.StyleTypeKey);
    AssertTrue('…and must NOT answer to the data grid''s TyGridCell',
      cell.StyleTypeKey <> 'TyGridCell');
  finally
    cell.Free;
  end;
end;

{ **The empty-Paint bug.** A cell is a WINDOWED control: its own HWND is erased with the
  control's LCL Color before Paint runs, and Paint used to draw nothing at all, so whatever
  the widgetset erased with was the final picture — a system-coloured rectangle punched
  through the window. Under a dark theme that is a LIGHT patch (what the user reported);
  over a gradient form background it is a flat patch breaking the sweep.

  Drive the paint path onto a canvas pre-filled with a colour NOTHING in the theme would
  choose (magenta), the way test.bevel renders onto a black ground. If Paint still draws
  nothing the magenta survives; it must instead be replaced by the parent panel's themed
  surface, which is what TyFillParentBg fetches. }
procedure TTyGridCellTest.TestPaintTakesTheParentBackground;
const
  W = 40; H = 30;
  { A parent whose surface is an unmistakable, fully-saturated green — so "the cell took
    the parent's colour" cannot be confused with a default grey or with the magenta ground. }
  CParentCss = 'TyPanel { background: #00C000; border-width: 0px; border-radius: 0px; }';
var
  ctl: TTyStyleController;
  frm: TForm;
  host: TTyPanel;
  cell: TCellAccess;
  bmp: TBitmap;
  probe: TBGRABitmap;
  px: TBGRAPixel;
  x, y, magenta: Integer;
begin
  ctl := TTyStyleController.Create(nil);
  frm := TForm.CreateNew(nil);
  bmp := TBitmap.Create;
  probe := nil;
  try
    ctl.LoadThemeCss(CParentCss);
    host := TTyPanel.Create(frm);
    host.Parent := frm;
    host.Controller := ctl;
    host.SetBounds(0, 0, 200, 150);

    cell := TCellAccess.Create(frm);
    cell.Parent := host;          { the cell's backdrop is this panel }
    cell.Controller := ctl;
    cell.Font.PixelsPerInch := 96;
    cell.SetBounds(0, 0, W, H);

    bmp.PixelFormat := pf32bit;
    bmp.SetSize(W, H);
    bmp.Canvas.Brush.Color := TColor($FF00FF);   // magenta "erase" ground
    bmp.Canvas.FillRect(0, 0, W, H);
    cell.RenderTo(bmp.Canvas, Rect(0, 0, W, H), 96);
    probe := TBGRABitmap.Create(bmp);

    magenta := 0;
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do
      begin
        px := probe.GetPixel(x, y);
        if (px.red > 200) and (px.blue > 200) and (px.green < 80) then Inc(magenta);
      end;
    AssertEquals('no erase-colour pixel may survive Paint — an empty Paint leaves the '
      + 'whole cell showing whatever the widgetset erased with', 0, magenta);

    { And it is specifically the PARENT's colour that replaced it. Probe the corners
      (edges, not the centre) so a fill that covered only part of the rect still fails. }
    px := probe.GetPixel(0, 0);
    AssertTrue(Format('top-left takes the parent surface (got %d,%d,%d)',
      [px.red, px.green, px.blue]),
      (px.green > 150) and (px.red < 80) and (px.blue < 80));
    px := probe.GetPixel(W - 1, H - 1);
    AssertTrue(Format('bottom-right takes the parent surface (got %d,%d,%d)',
      [px.red, px.green, px.blue]),
      (px.green > 150) and (px.red < 80) and (px.blue < 80));
  finally
    probe.Free;
    bmp.Free;
    frm.Free;
    ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyGridCellTest);
end.
