unit test.ribbonquickaccess;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.RibbonQuickAccess, tyControls.GlyphButtons;
type
  { Probe subclass: exposes protected GetStyleTypeKey + RenderTo for headless assertions. }
  TTyQatAccess = class(TTyRibbonQuickAccess)
  public
    function TypeKey: string;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TRibbonQuickAccessTest = class(TTestCase)
  published
    procedure TestTypeKeyIsRibbon;
    procedure TestContentWidthEmpty;
    procedure TestContentWidthThreeItems;
    procedure TestContentWidthFloorsNegatives;
    procedure TestAddButtonGrowsAndReturnsGlyphButton;
    procedure TestAddButtonAlignIsLeft;
    procedure TestAddButtonParentedToQat;
    procedure TestPaintSmokeNoChildrenDoesNotRaise;
  end;

implementation

{ TTyQatAccess }
function TTyQatAccess.TypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

procedure TTyQatAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

{ TRibbonQuickAccessTest }

procedure TRibbonQuickAccessTest.TestTypeKeyIsRibbon;
var
  Qat: TTyQatAccess;
begin
  Qat := TTyQatAccess.Create(nil);
  try
    // Reuses the ribbon band surface token (no new .tycss rule).
    AssertEquals('typeKey', 'TyRibbon', Qat.TypeKey);
  finally
    Qat.Free;
  end;
end;

procedure TRibbonQuickAccessTest.TestContentWidthEmpty;
begin
  // No items -> just the leading indent.
  AssertEquals('empty = indent', 3, TyQatContentWidth([], 3, 2));
end;

procedure TRibbonQuickAccessTest.TestContentWidthThreeItems;
begin
  // indent 3 + (22+22+22) + spacing 2 * 2 gaps = 3 + 66 + 4 = 73.
  AssertEquals('3 items packed', 73, TyQatContentWidth([22, 22, 22], 3, 2));
  // Single item: indent + width, no spacing added.
  AssertEquals('1 item', 25, TyQatContentWidth([22], 3, 2));
end;

procedure TRibbonQuickAccessTest.TestContentWidthFloorsNegatives;
begin
  // Negative indent/spacing/width all floor to 0: indent(0) + 10 + gap(0) + 10 = 20.
  AssertEquals('negatives floored', 20, TyQatContentWidth([10, -5, 10], -4, -1));
end;

procedure TRibbonQuickAccessTest.TestAddButtonGrowsAndReturnsGlyphButton;
var
  Qat: TTyRibbonQuickAccess;
  B: TTyGlyphButton;
begin
  Qat := TTyRibbonQuickAccess.Create(nil);
  try
    AssertEquals('starts empty', 0, Qat.ControlCount);
    B := Qat.AddButton('Save');
    AssertNotNull('AddButton returned a button', B);
    AssertTrue('is a TTyGlyphButton', B is TTyGlyphButton);
    AssertEquals('control count grew', 1, Qat.ControlCount);
    AssertEquals('caption set', 'Save', B.Caption);
    // A second one grows again.
    Qat.AddButton('Undo');
    AssertEquals('control count grew again', 2, Qat.ControlCount);
  finally
    Qat.Free;
  end;
end;

procedure TRibbonQuickAccessTest.TestAddButtonAlignIsLeft;
var
  Qat: TTyRibbonQuickAccess;
  B: TTyGlyphButton;
begin
  Qat := TTyRibbonQuickAccess.Create(nil);
  try
    B := Qat.AddButton('X');
    AssertTrue('child flows left (Align=alLeft)', B.Align = alLeft);
  finally
    Qat.Free;
  end;
end;

procedure TRibbonQuickAccessTest.TestAddButtonParentedToQat;
var
  Qat: TTyRibbonQuickAccess;
  B: TTyGlyphButton;
begin
  Qat := TTyRibbonQuickAccess.Create(nil);
  try
    B := Qat.AddButton('X');
    AssertSame('parented to the QAT', TWinControl(Qat), TWinControl(B.Parent));
  finally
    Qat.Free;
  end;
end;

procedure TRibbonQuickAccessTest.TestPaintSmokeNoChildrenDoesNotRaise;
var
  Ctl: TTyStyleController;
  Qat: TTyQatAccess;
  Bmp: TBitmap;
begin
  // Render an empty (0-child) QAT to an offscreen canvas; must not raise.
  Ctl := TTyStyleController.Create(nil);
  Qat := TTyQatAccess.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TyRibbon { background: #f3f3f3; border-color: #d0d0d0; border-width: 1px; }');
    Qat.Controller := Ctl;
    Qat.SetBounds(0, 0, 120, 26);
    Qat.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 26);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 120, 26);

    AssertEquals('no children', 0, Qat.ControlCount);
    // The assertion is simply that this completes without an exception.
    Qat.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 26), 96);
    AssertTrue('paint smoke completed', True);
  finally
    Bmp.Free;
    Qat.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TRibbonQuickAccessTest);
end.
