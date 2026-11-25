unit test.fieldwidth;
{$mode objfpc}{$H+}

{ #248: a combo box and a spin edit can say how wide they must be to show a text whole.

  The dialogs of the library gave such fields a typed width -- 120 px for the view box of the
  file dialog, 56 px for a colour channel -- and at modern density, where the font is larger,
  the text no longer fitted: "Large icons" was cut with an ellipsis and 255 read as 55.
  FieldWidthFor is what those layouts ask now, so it has to be the exact inverse of what the
  control paints, and that is what is tested here, by the pictures:

    at the width it answers, the field paints the same text as a field with room to spare;
    one pixel narrower, it does not.

  The themes draw the text red on white with no border, so the ink in the text zone is the
  text and nothing else. Their paddings differ left from right, and the second theme has
  another font size and another button width, so an answer that took the wrong padding, a
  fixed font or a fixed button would be seen. The same again at 168 PPI. }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.ComboBox,
  tyControls.SpinEdit;

type
  TFieldWidthTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FPPI: Integer;
    function Px(ALogical: Integer): Integer;
    function NewCombo(const AText: string): TTyComboBox;
    function NewSpin(AMin, AMax, AValue: Integer): TTySpinEdit;
    { The control painted AWidth wide, as a picture the caller frees. }
    function Shot(C: TWinControl; AWidth: Integer): TBGRABitmap;
    { How many pixels of columns [0, ACols) differ between two pictures / carry ink in one. }
    function Differ(A, B: TBGRABitmap; ACols: Integer): Integer;
    function Ink(A: TBGRABitmap; ACols: Integer): Integer;
    { The round trip for one field: whole at AWidth, not whole one pixel narrower. ATextCols
      is how many columns from the left belong to the text at AWidth. }
    procedure CheckRoundTrip(const AWhat: string; C: TWinControl; AWidth, ATextCols: Integer);
    procedure ComboRoundTrips(const ATheme: string; APPI: Integer);
    procedure SpinRoundTrips(const ATheme: string; APPI: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure AComboThatWideShowsItsItemWholeAndOnePixelLessDoesNot;
    procedure TheSameAt168PPI;
    procedure ASpinEditThatWideShowsItsNumberWholeAndOnePixelLessDoesNot;
    procedure TheSameForTheSpinEditAt168PPI;
    procedure AnEmptyTextStillHasItsPaddingAndItsButtons;
  end;

implementation

const
  cThemeA =
    'TyComboBox { background: #FFFFFF; color: #FF0000; padding: 4px 12px 4px 6px; '
    + 'border-width: 0px; font-size: 12px; }'
    + 'TySpinEdit { background: #FFFFFF; color: #FF0000; padding: 4px 9px 4px 5px; '
    + 'border-width: 0px; font-size: 12px; }';
  cThemeB =
    ':root { --field-button-width: 27px; --field-drop-pad: 5px; }'
    + 'TyComboBox { background: #FFFFFF; color: #FF0000; padding: 2px 3px 2px 14px; '
    + 'border-width: 0px; font-size: 19px; font-weight: bold; }'
    + 'TySpinEdit { background: #FFFFFF; color: #FF0000; padding: 2px 4px 2px 13px; '
    + 'border-width: 0px; font-size: 19px; font-weight: bold; }';
  cTexts: array[0..4] of string =
    ('Details', 'Large icons', '详细信息', 'Microsoft YaHei UI', 'List');

type
  TComboAcc = class(TTyComboBox);
  TSpinAcc = class(TTySpinEdit);

procedure TFieldWidthTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FPPI := 96;
end;

procedure TFieldWidthTest.TearDown;
begin
  FForm.Free;
  FCtl.Free;
end;

function TFieldWidthTest.Px(ALogical: Integer): Integer;
begin
  Result := MulDiv(ALogical, FPPI, 96);
end;

function TFieldWidthTest.NewCombo(const AText: string): TTyComboBox;
begin
  Result := TTyComboBox.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := FPPI;
  Result.SetBounds(0, 0, 400, Px(34));
  Result.Style := csDropDownList;
  Result.Items.Add(AText);
  Result.ItemIndex := 0;
end;

function TFieldWidthTest.NewSpin(AMin, AMax, AValue: Integer): TTySpinEdit;
begin
  Result := TTySpinEdit.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := FPPI;
  Result.SetBounds(0, 0, 400, Px(34));
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Value := AValue;
end;

function TFieldWidthTest.Shot(C: TWinControl; AWidth: Integer): TBGRABitmap;
var
  bmp: TBitmap;
  r: TRect;
  pass: Integer;
begin
  C.Width := AWidth;
  AssertEquals('precondition: the control took the width it was given', AWidth, C.Width);
  r := Rect(0, 0, C.Width, C.Height);
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(C.Width, C.Height);
    bmp.Canvas.Brush.Color := clWhite;
    for pass := 1 to 2 do   { twice: the first paint of a control is the one that sets it up }
    begin
      bmp.Canvas.FillRect(r);
      if C is TTyComboBox then TComboAcc(C).RenderTo(bmp.Canvas, r, FPPI)
      else TSpinAcc(C).RenderTo(bmp.Canvas, r, FPPI);
    end;
    Result := TBGRABitmap.Create(bmp);
  finally
    bmp.Free;
  end;
end;

function TFieldWidthTest.Differ(A, B: TBGRABitmap; ACols: Integer): Integer;
var
  x, y: Integer;
  p, q: PBGRAPixel;
begin
  Result := 0;
  AssertEquals('precondition: the two pictures are equally tall', A.Height, B.Height);
  for y := 0 to A.Height - 1 do
  begin
    p := A.ScanLine[y];
    q := B.ScanLine[y];
    for x := 0 to ACols - 1 do
      if (p[x].red <> q[x].red) or (p[x].green <> q[x].green) or (p[x].blue <> q[x].blue) then
        Inc(Result);
  end;
end;

function TFieldWidthTest.Ink(A: TBGRABitmap; ACols: Integer): Integer;
var
  x, y: Integer;
  p: PBGRAPixel;
begin
  Result := 0;
  for y := 0 to A.Height - 1 do
  begin
    p := A.ScanLine[y];
    for x := 0 to ACols - 1 do
      if (p[x].red > 150) and (p[x].green < 180) then Inc(Result);   { red on white }
  end;
end;

procedure TFieldWidthTest.CheckRoundTrip(const AWhat: string; C: TWinControl;
  AWidth, ATextCols: Integer);
var
  roomy, exact, tight: TBGRABitmap;
begin
  AssertTrue(AWhat + ': an answer that leaves the text some columns (got ' + IntToStr(AWidth)
    + ', of which ' + IntToStr(ATextCols) + ' for the text)', ATextCols > 0);
  roomy := Shot(C, AWidth + Px(80));
  exact := Shot(C, AWidth);
  tight := Shot(C, AWidth - 1);
  try
    AssertTrue(AWhat + ': precondition -- with room to spare the text is painted',
      Ink(roomy, ATextCols) > 0);
    AssertEquals(AWhat + ': at the width it answers (' + IntToStr(AWidth)
      + ') the field paints what a roomier one paints -- pixels that differ',
      0, Differ(exact, roomy, ATextCols));
    AssertTrue(AWhat + ': one pixel narrower (' + IntToStr(AWidth - 1)
      + ') it no longer does, so the answer is not a generous one',
      Differ(tight, roomy, ATextCols - 1) > 0);
  finally
    roomy.Free;
    exact.Free;
    tight.Free;
  end;
end;

procedure TFieldWidthTest.ComboRoundTrips(const ATheme: string; APPI: Integer);
var
  i, w: Integer;
  c: TTyComboBox;
begin
  FPPI := APPI;
  FCtl.LoadThemeCss(ATheme);
  for i := 0 to High(cTexts) do
  begin
    c := NewCombo(cTexts[i]);
    try
      w := TComboAcc(c).FieldWidthFor(cTexts[i]);
      CheckRoundTrip(Format('combo "%s" at %d PPI', [cTexts[i], APPI]), c, w,
        w - Px(TyDropZoneWidth(FCtl)));
    finally
      c.Free;
    end;
  end;
end;

procedure TFieldWidthTest.SpinRoundTrips(const ATheme: string; APPI: Integer);
const
  cValues: array[0..4] of Integer = (0, 7, 100, 255, -12345);
var
  i, w: Integer;
  s: TTySpinEdit;
begin
  FPPI := APPI;
  FCtl.LoadThemeCss(ATheme);
  for i := 0 to High(cValues) do
  begin
    s := NewSpin(-99999, 99999, cValues[i]);
    try
      AssertEquals('precondition: the field holds the number', IntToStr(cValues[i]), s.Text);
      w := TSpinAcc(s).FieldWidthFor(s.Text);
      CheckRoundTrip(Format('spin edit %d at %d PPI', [cValues[i], APPI]), s, w,
        w - Px(FCtl.Metric('--field-button-width', TyFieldButtonWidth)));
    finally
      s.Free;
    end;
  end;
end;

procedure TFieldWidthTest.AComboThatWideShowsItsItemWholeAndOnePixelLessDoesNot;
begin
  ComboRoundTrips(cThemeA, 96);
  ComboRoundTrips(cThemeB, 96);
end;

procedure TFieldWidthTest.TheSameAt168PPI;
begin
  ComboRoundTrips(cThemeA, 168);
  ComboRoundTrips(cThemeB, 168);
end;

procedure TFieldWidthTest.ASpinEditThatWideShowsItsNumberWholeAndOnePixelLessDoesNot;
begin
  SpinRoundTrips(cThemeA, 96);
  SpinRoundTrips(cThemeB, 96);
end;

procedure TFieldWidthTest.TheSameForTheSpinEditAt168PPI;
begin
  SpinRoundTrips(cThemeA, 168);
  SpinRoundTrips(cThemeB, 168);
end;

procedure TFieldWidthTest.AnEmptyTextStillHasItsPaddingAndItsButtons;
var
  c: TTyComboBox;
  s: TTySpinEdit;
begin
  { theme A at 96 PPI: left padding 6 + the drop zone; 5 + 9 + the spin buttons }
  FCtl.LoadThemeCss(cThemeA);
  c := NewCombo('x');
  s := NewSpin(0, 9, 1);
  try
    AssertEquals('a combo with nothing to show: its left padding and its drop zone',
      6 + TyDropZoneWidth(FCtl), TComboAcc(c).FieldWidthFor(''));
    AssertEquals('a spin edit with nothing to show: both paddings and its buttons',
      5 + 9 + FCtl.Metric('--field-button-width', TyFieldButtonWidth),
      TSpinAcc(s).FieldWidthFor(''));
  finally
    c.Free;
    s.Free;
  end;
end;

initialization
  RegisterTest(TFieldWidthTest);
end.
