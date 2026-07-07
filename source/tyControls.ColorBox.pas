unit tyControls.ColorBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox;

{ TColor -> TTyColor ($AARRGGBB, opaque). Resolves system (clXxx) colours. Pure. }
function TyTColorToTy(AColor: TColor): TTyColor;
{ The colour carried in AItems.Objects[AIndex] (clNone if out of range). }
function TyColorOfItem(AItems: TStrings; AIndex: Integer): TColor;

type
  { Drop-down list for TTyColorBox: draws a colour swatch + name per row via the
    TTyListBox.PaintItemContent hook. The colour is carried in each item's Objects[] entry
    (the combo copies its Items — including Objects — into this list), so there is no side
    array that could desync from the names. }
  TTyColorPopupList = class(TTyListBox)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { A combo of named colours: the field and the drop-down each show a colour swatch beside
    the name. Subclasses TTyComboBox, injecting a swatch-drawing popup list (CreatePopupList)
    and a swatch field (PaintFieldContent). The colour lives in Items.Objects[i], so it stays
    intrinsically aligned with the name through Sorted / Delete / direct edits (no parallel
    array). Locked to csDropDownList (pick-only): a filtered editable popup would break the
    swatch↔name mapping. Manage colours via AddColor / ClearColors; Selected is the TColor. }
  TTyColorBox = class(TTyComboBox)
  private
    function GetSelected: TColor;
    procedure SetSelected(const AValue: TColor);
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    procedure SetStyle(AValue: TTyComboBoxStyle); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ClearColors;
    procedure AddColor(const AName: string; AColor: TColor);
    // Colour of item AIndex (clNone if out of range).
    function ColorAt(AIndex: Integer): TColor;
    // The selected colour. Reading returns the current item's colour (clNone if none);
    // writing selects the matching item, or (clNone -> clear; otherwise) appends a '#RRGGBB'
    // item and selects it.
    property Selected: TColor read GetSelected write SetSelected;
  end;

implementation

function TyTColorToTy(AColor: TColor): TTyColor;
var rgb: LongInt;
begin
  rgb := ColorToRGB(AColor);
  Result := TTyColor($FF000000) or (TTyColor(Red(rgb)) shl 16)
    or (TTyColor(Green(rgb)) shl 8) or TTyColor(Blue(rgb));
end;

function TyColorOfItem(AItems: TStrings; AIndex: Integer): TColor;
begin
  if (AIndex >= 0) and (AIndex < AItems.Count) then
    Result := TColor(PtrInt(AItems.Objects[AIndex]))
  else
    Result := clNone;
end;

{ Shared swatch-row draw: a square colour swatch on the left + the name to its right.
  AFontSize is the caller's resolved size (list rows differ from the field). }
procedure TyDrawColorRow(P: TTyPainter; const ARect: TRect; AColor: TColor;
  const AName: string; const AStyle: TTyStyleSet; AFontSize: Integer);
var
  pad, sw, maxSw, top: Integer;
  swR, txR: TRect;
  f: TTyFill;
begin
  pad := P.Scale(4);
  sw := (ARect.Bottom - ARect.Top) - 2 * pad;   // square swatch, height-derived
  if sw < 4 then sw := 4;
  maxSw := (ARect.Right - ARect.Left) - 2 * pad;
  if sw > maxSw then sw := maxSw;
  if sw < 1 then Exit;
  top := ARect.Top + ((ARect.Bottom - ARect.Top) - sw) div 2;
  swR := Rect(ARect.Left + pad, top, ARect.Left + pad + sw, top + sw);
  f := Default(TTyFill);
  f.Kind := tfkSolid;
  f.Color := TyTColorToTy(AColor);
  P.FillBackground(swR, f, 2);
  P.StrokeBorder(swR, 2, 1, AStyle.TextColor);   // theme-driven outline so light swatches show
  txR := Rect(swR.Right + pad, ARect.Top, ARect.Right - pad, ARect.Bottom);
  P.DrawText(txR, AName, AStyle.FontName, AFontSize, AStyle.FontWeight,
    AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

{ TTyColorPopupList }

procedure TTyColorPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  TyDrawColorRow(P, ARowRect, TyColorOfItem(Items, AIndex), Items[AIndex], AStyle,
    ResolveFontSize(AStyle));
end;

{ TTyColorBox }

constructor TTyColorBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Curated 16-colour palette (the classic VGA names). Users can ClearColors + AddColor.
  AddColor('Black',   clBlack);
  AddColor('Maroon',  clMaroon);
  AddColor('Green',   clGreen);
  AddColor('Olive',   clOlive);
  AddColor('Navy',    clNavy);
  AddColor('Purple',  clPurple);
  AddColor('Teal',    clTeal);
  AddColor('Gray',    clGray);
  AddColor('Silver',  clSilver);
  AddColor('Red',     clRed);
  AddColor('Lime',    clLime);
  AddColor('Yellow',  clYellow);
  AddColor('Blue',    clBlue);
  AddColor('Fuchsia', clFuchsia);
  AddColor('Aqua',    clAqua);
  AddColor('White',   clWhite);
  if Items.Count > 0 then ItemIndex := 0;
end;

procedure TTyColorBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  // A colour box is always pick-only: the editable csDropDown popup is prefix-FILTERED,
  // which would map row indices to the wrong swatches. Ignore any attempt to change it.
  inherited SetStyle(csDropDownList);
end;

procedure TTyColorBox.ClearColors;
begin
  Items.Clear;
end;

procedure TTyColorBox.AddColor(const AName: string; AColor: TColor);
begin
  // Store the colour in the item's Objects[] so it can never desync from the name.
  Items.AddObject(AName, TObject(PtrInt(AColor)));
end;

function TTyColorBox.ColorAt(AIndex: Integer): TColor;
begin
  Result := TyColorOfItem(Items, AIndex);
end;

function TTyColorBox.GetSelected: TColor;
begin
  Result := ColorAt(ItemIndex);
end;

procedure TTyColorBox.SetSelected(const AValue: TColor);
var
  i: Integer;
  target: LongInt;
begin
  if AValue = clNone then
  begin
    ItemIndex := -1;   // clear (mirrors GetSelected returning clNone for ItemIndex < 0)
    Exit;
  end;
  target := ColorToRGB(AValue);
  for i := 0 to Items.Count - 1 do
    if ColorToRGB(ColorAt(i)) = target then
    begin
      ItemIndex := i;
      Exit;
    end;
  // Not in the palette: append a hex-named item and select it.
  AddColor(Format('#%.2x%.2x%.2x', [Red(target), Green(target), Blue(target)]), AValue);
  ItemIndex := Items.Count - 1;
end;

function TTyColorBox.CreatePopupList: TTyListBox;
begin
  Result := TTyColorPopupList.Create(Self);
end;

procedure TTyColorBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    TyDrawColorRow(P, ATextRect, ColorAt(ItemIndex), Items[ItemIndex], AStyle, AStyle.FontSize)
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);
end;

end.
