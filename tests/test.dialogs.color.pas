unit test.dialogs.color;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Graphics, Controls, Forms, Dialogs, fpcunit, testregistry,
  tyControls.Types, tyControls.ColorMath, tyControls.ColorGrid, tyControls.Dialogs.Color,
  tyControls.Edit, tyControls.SpinEdit, tyControls.Button, tyControls.StrConsts;
type
  TColorControlsTest = class(TTestCase)
  published
    procedure TestSquareHueRoundTrip;
  end;
  TColorDialogTest = class(TTestCase)
  published
    procedure TestSyncHexToChannels;
    procedure TestSyncRGBToHex;
    procedure TestComponentTwoWay;
  end;
  { Hue and saturation are the PICKER's state, not something re-derived from the RGB model:
    black and grey have no hue to derive, so a naive RGB->HSV round trip snapped the hue bar
    back to red (0) the moment the colour went black or grey. }
  TColorPickerStateTest = class(TTestCase)
  published
    procedure TestHueSurvivesBlack;
    procedure TestValueRoundTripKeepsHue;
    procedure TestGreyKeepsHue;
    procedure TestWhiteKeepsHue;
    procedure TestExternalColorDerivesHue;
  end;
  TColorSwatchGridTest = class(TTestCase)
  published
    procedure TestGridSeeded;
    procedure TestClickCommitsThroughModel;
    procedure TestClickKeepsAlpha;
    procedure TestGreySwatchKeepsHue;
    procedure TestRingFollowsColor;
  end;
  { LCL's Options and CustomColors on TTyColorDialog (#28). }
  TColorDialogOptionsTest = class(TTestCase)
  private
    FDlg: TTyColorDialog;
    FForm: TTyColorForm;
    function AddButton: TTyButton;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestParseCustomColor;
    procedure TestDefaultsKeepTheOldDialog;
    procedure TestNewPropertiesAreNotWrittenAtTheirDefaults;
    procedure TestCustomColorsShowInTheirSlots;
    procedure TestClickingACustomSwatchPicksIt;
    procedure TestAddFillsTheNextSlotsAndOnlyThoseAreWrittenBack;
    procedure TestPreventFullOpenLeavesOnlyTheSwatches;
  end;
implementation

type
  { Protected-member access so a test can deliver a real click. The swatch commit path
    starts in TTyColorGrid.MouseDown, and going through it is the only way to prove the
    dialog actually wired OnChange (calling the handler by hand would not). }
  TSwatchAccess = class(TTyColorGrid)
  public
    procedure ClickAt(X, Y: Integer);
  end;

procedure TSwatchAccess.ClickAt(X, Y: Integer);
begin MouseDown(mbLeft, [], X, Y); end;

{ Centre of swatch cell AIndex in the grid's own coordinates. Mirrors TTyColorGrid's cell
  maths (ClientWidth div Columns by ClientHeight div rows) instead of hard-coding pixels;
  every caller re-checks the point with CellAt before clicking it. }
procedure SwatchCellCenter(AGrid: TTyColorGrid; AIndex: Integer; out X, Y: Integer);
var cw, ch, rows: Integer;
begin
  rows := (AGrid.ColorCount + AGrid.Columns - 1) div AGrid.Columns;
  cw := AGrid.ClientWidth div AGrid.Columns;
  ch := AGrid.ClientHeight div rows;
  X := (AIndex mod AGrid.Columns) * cw + cw div 2;
  Y := (AIndex div AGrid.Columns) * ch + ch div 2;
end;

{ Click swatch AIndex on ADlg's grid, failing the calling test if the point does not land
  on that very cell (so a layout change can never make a click silently miss). }
procedure ClickSwatch(ADlg: TTyColorForm; AIndex: Integer);
var x, y: Integer;
begin
  SwatchCellCenter(ADlg.Swatches, AIndex, x, y);
  TAssert.AssertEquals('click lands on the intended cell', AIndex, ADlg.Swatches.CellAt(x, y));
  TSwatchAccess(ADlg.Swatches).ClickAt(x, y);
end;

procedure TColorControlsTest.TestSquareHueRoundTrip;
var sq: TTyHSVSquare; hb: TTyHueBar;
begin
  sq := TTyHSVSquare.Create(nil);   // parentless construct-only (TTyCustomControl)
  try
    sq.SetHSV(210, 0.5, 0.8);
    AssertEquals('H', 210.0, sq.Hue, 0.5);
    AssertEquals('S', 0.5, sq.Sat, 0.01);
    AssertEquals('V', 0.8, sq.Val, 0.01);
  finally sq.Free; end;
  hb := TTyHueBar.Create(nil);
  try
    hb.Hue := 300;
    AssertEquals('huebar', 300.0, hb.Hue, 0.5);
  finally hb.Free; end;
end;

procedure TColorDialogTest.TestSyncHexToChannels;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.ApplyHexText('#3399CC');
    AssertEquals('R', $33, TyRedOf(d.CurrentColor));
    AssertEquals('G', $99, TyGreenOf(d.CurrentColor));
    AssertEquals('B', $CC, TyBlueOf(d.CurrentColor));
  finally d.Free; end;
end;

procedure TColorDialogTest.TestSyncRGBToHex;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.SetColorValue(TyRGB($12,$34,$56));
    AssertEquals('hex', '#123456', LowerCase(d.HexText));
  finally d.Free; end;
end;

procedure TColorDialogTest.TestComponentTwoWay;
var comp: TTyColorDialog;
begin
  comp := TTyColorDialog.Create(nil);
  try
    comp.Color := TyRGBA($10,$20,$30,$80);
    AssertEquals('lcl rt', Integer(TyColorToLCL(TyRGB($10,$20,$30))), Integer(comp.LCLColor));
    AssertEquals('alpha', $80, comp.Alpha);
    comp.Alpha := $FF;
    AssertEquals('alpha2', $FF, TyAlphaOf(comp.Color));
    comp.LCLColor := clRed;   // sets RGB, preserves alpha
    AssertEquals('lcl set keeps alpha', $FF, TyAlphaOf(comp.Color));
  finally comp.Free; end;
end;

{ ===================== hue/sat are the picker's own state ===================== }

procedure TColorPickerStateTest.TestHueSurvivesBlack;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));   // black: hue is undefined for it
  try
    d.SetPickerHue(210);
    // The colour cannot change (value is still 0) — but the bar must STAY where it was put.
    // Re-deriving hue from the resulting black is what used to snap it back to red.
    AssertEquals('hue bar stays where it was clicked', 210.0, d.PickerHue, 0.5);
    AssertTrue('colour is still black', d.CurrentColor = TyRGBA(0,0,0,255));
  finally d.Free; end;
end;

procedure TColorPickerStateTest.TestValueRoundTripKeepsHue;
var d: TTyColorForm; green: TTyColor;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.SetPickerHue(120);
    d.SetPickerSV(1, 1);
    green := d.CurrentColor;
    AssertTrue('picked pure green', green = TyRGBA(0,255,0,255));
    d.SetPickerSV(1, 0);                            // drag value all the way down
    AssertTrue('bottom of the square is black', d.CurrentColor = TyRGBA(0,0,0,255));
    d.SetPickerSV(1, 1);                            // ...and straight back up
    AssertTrue('the same colour comes back', d.CurrentColor = green);
    AssertEquals('hue survived the trip through black', 120.0, d.PickerHue, 0.5);
  finally d.Free; end;
end;

procedure TColorPickerStateTest.TestGreyKeepsHue;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.SetPickerHue(240);
    // Grey arrives from OUTSIDE the picker (the hex box), so H/S/V is re-derived — but a
    // grey has no hue to derive, only a saturation of 0 and a real value.
    d.ApplyHexText('#808080');
    AssertEquals('hue kept', 240.0, d.PickerHue, 0.5);
    AssertEquals('saturation taken from the colour', 0.0, d.PickerSat, 0.01);
    AssertEquals('value taken from the colour', 128/255, d.PickerVal, 0.01);
  finally d.Free; end;
end;

procedure TColorPickerStateTest.TestWhiteKeepsHue;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.SetPickerHue(30);
    d.ApplyHexText('#FFFFFF');   // white: any hue would produce it
    AssertEquals('hue kept', 30.0, d.PickerHue, 0.5);
    AssertEquals('value taken from the colour', 1.0, d.PickerVal, 0.01);
  finally d.Free; end;
end;

procedure TColorPickerStateTest.TestExternalColorDerivesHue;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.SetPickerHue(0);
    // A colour that DOES have a hue must still move the picker — keeping the old hue only
    // applies where the derived one is meaningless.
    d.ApplyHexText('#0000FF');
    AssertEquals('hue derived from blue', 240.0, d.PickerHue, 0.5);
    AssertEquals('saturation derived', 1.0, d.PickerSat, 0.01);
    AssertEquals('value derived', 1.0, d.PickerVal, 0.01);
  finally d.Free; end;
end;

{ ===================== quick-pick swatch grid ===================== }

const
  cSwRed  = 9;    // 10th cell of the classic VGA row
  cSwGrey = 24;   // first cell of the appended grey ramp (second row, 9th column)

procedure TColorSwatchGridTest.TestGridSeeded;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    AssertTrue('the dialog has a swatch grid', d.Swatches <> nil);
    // 16 VGA colours + 8 tints + an 8-step grey ramp = two full rows of 16.
    AssertEquals('columns', 16, d.Swatches.Columns);
    AssertEquals('palette fills whole rows', 32, d.Swatches.ColorCount);
    AssertEquals('no remainder', 0, d.Swatches.ColorCount mod d.Swatches.Columns);
    AssertTrue('grid is wide enough to have cells', d.Swatches.ClientWidth >= d.Swatches.Columns);
  finally d.Free; end;
end;

procedure TColorSwatchGridTest.TestClickCommitsThroughModel;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    ClickSwatch(d, cSwRed);
    AssertTrue('the model took the swatch colour', d.CurrentColor = TyRGBA(255,0,0,255));
    // HexText is rendered from the model by the shared sync path, so this also proves the
    // click went through ApplyColor rather than poking FColor.
    AssertEquals('hex box followed', '#ff0000', LowerCase(d.HexText));
  finally d.Free; end;
end;

procedure TColorSwatchGridTest.TestClickKeepsAlpha;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGBA(0,0,0,$40));
  try
    ClickSwatch(d, cSwRed);
    AssertEquals('swatches carry no alpha, so the dialog keeps its own', $40,
      TyAlphaOf(d.CurrentColor));
  finally d.Free; end;
end;

procedure TColorSwatchGridTest.TestGreySwatchKeepsHue;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.SetPickerHue(200);
    ClickSwatch(d, cSwGrey);   // a grey commits like any other outside source
    AssertEquals('saturation went to 0', 0.0, d.PickerSat, 0.01);
    AssertEquals('hue kept', 200.0, d.PickerHue, 0.5);
  finally d.Free; end;
end;

procedure TColorSwatchGridTest.TestRingFollowsColor;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.SetColorValue(TyRGB(255,0,0));
    AssertTrue('the matching swatch is ringed', d.Swatches.Selected = clRed);
    d.SetColorValue(TyRGB(1,2,3));
    AssertTrue('an off-palette colour rings nothing', d.Swatches.Selected = clNone);
  finally d.Free; end;
end;

{ TColorDialogOptionsTest }

procedure TColorDialogOptionsTest.SetUp;
begin
  FDlg := TTyColorDialog.Create(nil);
  FDlg.LCLColor := clBlack;
end;

procedure TColorDialogOptionsTest.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FDlg);
end;

function TColorDialogOptionsTest.AddButton: TTyButton;
var i: Integer;
begin
  Result := nil;
  for i := 0 to FForm.ComponentCount - 1 do
    if (FForm.Components[i] is TTyButton)
    and (TTyButton(FForm.Components[i]).Caption = rsDlgAddCustomColor) then
      Exit(TTyButton(FForm.Components[i]));
end;

procedure TColorDialogOptionsTest.TestParseCustomColor;
var slot: Integer; c: TColor;
begin
  AssertTrue('ColorA', TyParseCustomColor('ColorA', 'FF0000', slot, c));
  AssertEquals('slot A', 0, slot);
  AssertEquals('a hex TColor: FF0000 is blue', clBlue, c);
  AssertTrue('ColorP', TyParseCustomColor('ColorP', '00FF00', slot, c));
  AssertEquals('slot P', 15, slot);
  AssertFalse('ColorQ: past the 16 slots', TyParseCustomColor('ColorQ', 'FFFFFF', slot, c));
  AssertFalse('ColorAA', TyParseCustomColor('ColorAA', 'FFFFFF', slot, c));
  AssertFalse('lower-case letter', TyParseCustomColor('Colora', 'FFFFFF', slot, c));
  AssertFalse('not a colour name', TyParseCustomColor('Foo', 'FFFFFF', slot, c));
  AssertFalse('bad hex', TyParseCustomColor('ColorB', 'FFGG00', slot, c));
  AssertFalse('empty value', TyParseCustomColor('ColorB', '', slot, c));
end;

procedure TColorDialogOptionsTest.TestDefaultsKeepTheOldDialog;
var plain: TTyColorForm;
begin
  AssertTrue('Options default to LCL''s [cdFullOpen]', FDlg.Options = [cdFullOpen]);
  AssertEquals('no custom colours', 0, FDlg.CustomColors.Count);
  FForm := FDlg.BuildForm;
  AssertTrue('no custom row', FForm.CustomSwatches = nil);
  AssertTrue('no Add button', AddButton = nil);
  plain := TyBuildColorDialog('', FDlg.Color);
  try
    AssertEquals('the same height as the plain dialog', plain.ClientHeight, FForm.ClientHeight);
    AssertTrue('the preview where it always was', EqualRect(plain.PreviewRect, FForm.PreviewRect));
  finally plain.Free; end;
end;

procedure TColorDialogOptionsTest.TestNewPropertiesAreNotWrittenAtTheirDefaults;
var src: TForm; ms, ts: TMemoryStream; L: TStringList; d: TTyColorDialog;
begin
  src := TForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  ts := TMemoryStream.Create;
  L := TStringList.Create;
  try
    d := TTyColorDialog.Create(src);
    d.Name := 'D';
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, ts);
    ts.Position := 0;
    L.LoadFromStream(ts);
    AssertEquals('Options', 0, Pos('Options', L.Text));
    AssertEquals('CustomColors', 0, Pos('CustomColors', L.Text));
  finally
    L.Free; ts.Free; ms.Free; src.Free;
  end;
end;

procedure TColorDialogOptionsTest.TestCustomColorsShowInTheirSlots;
var plain: TTyColorForm; g: TTyColorGrid;
begin
  FDlg.CustomColors.Add('ColorA=0000FF');
  FDlg.CustomColors.Add('ColorC=00FF00');
  FForm := FDlg.BuildForm;
  g := FForm.CustomSwatches;
  AssertTrue('a custom row', g <> nil);
  AssertEquals('16 slots', 16, g.ColorCount);
  AssertEquals('slot A', TColor($0000FF), g.ColorAt(0));
  AssertEquals('slot B: empty, white', clWhite, g.ColorAt(1));
  AssertEquals('slot C', TColor($00FF00), g.ColorAt(2));
  AssertTrue('an Add button', AddButton <> nil);
  plain := TyBuildColorDialog('', FDlg.Color);
  try
    AssertTrue('the preview moved down below the row',
      FForm.PreviewRect.Top > plain.PreviewRect.Top);
    AssertTrue('the dialog grew to hold it', FForm.ClientHeight > plain.ClientHeight);
    AssertTrue('the row sits below the basic colours',
      g.Top >= FForm.Swatches.Top + FForm.Swatches.Height);
    AssertTrue('and above the preview', AddButton.Top + AddButton.Height <= FForm.PreviewRect.Top);
  finally plain.Free; end;
end;

type
  TCustomSwatchAccess = class(TTyColorGrid)
  public
    procedure ClickAt(X, Y: Integer);
  end;

procedure TCustomSwatchAccess.ClickAt(X, Y: Integer);
begin MouseDown(mbLeft, [], X, Y); end;

procedure TColorDialogOptionsTest.TestClickingACustomSwatchPicksIt;
var g: TTyColorGrid; cw: Integer;
begin
  FDlg.CustomColors.Add('ColorB=8040C0');
  FForm := FDlg.BuildForm;
  g := FForm.CustomSwatches;
  cw := g.ClientWidth div g.Columns;
  AssertEquals('the click lands on slot B', 1, g.CellAt(cw + cw div 2, g.ClientHeight div 2));
  TCustomSwatchAccess(g).ClickAt(cw + cw div 2, g.ClientHeight div 2);
  AssertEquals('the dialog took the custom colour', TColor($8040C0),
    TyColorToLCL(FForm.CurrentColor));
end;

procedure TColorDialogOptionsTest.TestAddFillsTheNextSlotsAndOnlyThoseAreWrittenBack;
var L: TStringList;
begin
  FDlg.CustomColors.Add('ColorA=0000FF');
  FDlg.CustomColors.Add('ColorC=00FF00');
  FDlg.CustomColors.Add('ColorQ=123456');   // LCL lists Q..T too; not ours to touch
  FForm := FDlg.BuildForm;
  FForm.SetColorValue(TyColorFromLCL(TColor($102030), 255));
  FForm.AddCustomColor;
  FForm.SetColorValue(TyColorFromLCL(TColor($405060), 255));
  AddButton.Click;
  AssertEquals('after the last given slot (C): D', TColor($102030), FForm.CustomSwatches.ColorAt(3));
  AssertEquals('then E', TColor($405060), FForm.CustomSwatches.ColorAt(4));
  L := TStringList.Create;
  try
    L.Assign(FDlg.CustomColors);
    FForm.GetCustomColors(L);
    AssertEquals('A kept', '0000FF', L.Values['ColorA']);
    AssertEquals('B never defined: not written', '', L.Values['ColorB']);
    AssertEquals('C kept', '00FF00', L.Values['ColorC']);
    AssertEquals('D added', '102030', L.Values['ColorD']);
    AssertEquals('E added', '405060', L.Values['ColorE']);
    AssertEquals('F untouched', '', L.Values['ColorF']);
    AssertEquals('Q left as it was', '123456', L.Values['ColorQ']);
    AssertEquals('five slots plus Q', 6, L.Count);
  finally L.Free; end;
end;

procedure TColorDialogOptionsTest.TestPreventFullOpenLeavesOnlyTheSwatches;
var i: Integer; c: TComponent;
begin
  FDlg.CustomColors.Add('ColorA=0000FF');
  FDlg.Options := [cdPreventFullOpen];
  FForm := FDlg.BuildForm;
  for i := 0 to FForm.ComponentCount - 1 do
  begin
    c := FForm.Components[i];
    if (c is TTyEdit) or (c is TTySpinEdit) or (c is TTyHSVSquare) or (c is TTyHueBar) then
      AssertFalse(c.ClassName + ' disabled: no colour can be defined', TControl(c).Enabled);
  end;
  AssertFalse('nothing to add to the custom colours', AddButton.Enabled);
  AssertTrue('the basic swatches still pick', FForm.Swatches.Enabled);
  AssertTrue('so do the custom ones', FForm.CustomSwatches.Enabled);
  FDlg.Options := [cdFullOpen];
  FreeAndNil(FForm);
  FForm := FDlg.BuildForm;
  AssertTrue('without it the editors work', AddButton.Enabled);
end;

initialization
  RegisterTest(TColorDialogOptionsTest);
  RegisterTest(TColorControlsTest);
  RegisterTest(TColorDialogTest);
  RegisterTest(TColorPickerStateTest);
  RegisterTest(TColorSwatchGridTest);
end.
