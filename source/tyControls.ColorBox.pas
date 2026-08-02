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
{ Append (AName, AColor) to AItems, storing the colour intrinsically in Objects[]. }
procedure TyAddColorItem(AItems: TStrings; const AName: string; AColor: TColor);
{ Fill AItems with the classic 16-colour VGA palette (via TyAddColorItem). }
procedure TyAddDefaultColorPalette(AItems: TStrings);
{ Index to select for AColor: the matching item, or a freshly-appended '#RRGGBB' item;
  -1 for clNone (clear). The caller assigns the result to its ItemIndex. Shared by the
  colour combo + list so the (review-hardened) select-or-append logic lives in one place. }
{ AAppendIfMissing: when the colour is not one of AItems, either add a hex-named entry
  for it (what an EDITOR wants -- the cell's current value has to be showable) or report
  -1 and leave the list alone (what a colour PICKER wants: LCL's TColorBox.Selected sets
  ItemIndex := -1 rather than growing its palette, and a setter that silently extends the
  list makes `Selected := X` non-idempotent -- twenty writes, twenty new rows). }
function TySelectColorIndex(AItems: TStrings; AColor: TColor;
  AAppendIfMissing: Boolean = True): Integer;
{ Draw a colour swatch (left) + name (right) into ARect; AFontSize is the caller's resolved
  size. Shared by the colour combo field, its popup list, and TTyColorListBox. }
procedure TyDrawColorRow(P: TTyPainter; const ARect: TRect; AColor: TColor;
  const AName: string; const AStyle: TTyStyleSet; AFontSize: Integer);

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
  published
    { PUBLISHED, as TColorBox does -- it is the control's headline property and it was
      public-only, so the one thing a colour box is for could not be set in the designer
      or streamed to the .lfm. Reading returns the current item's colour (clNone if none);
      writing selects the matching item, or reports clNone when the colour is not in the
      palette. }
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

procedure TyAddColorItem(AItems: TStrings; const AName: string; AColor: TColor);
begin
  AItems.AddObject(AName, TObject(PtrInt(AColor)));
end;

procedure TyAddDefaultColorPalette(AItems: TStrings);
begin
  TyAddColorItem(AItems, 'Black',   clBlack);
  TyAddColorItem(AItems, 'Maroon',  clMaroon);
  TyAddColorItem(AItems, 'Green',   clGreen);
  TyAddColorItem(AItems, 'Olive',   clOlive);
  TyAddColorItem(AItems, 'Navy',    clNavy);
  TyAddColorItem(AItems, 'Purple',  clPurple);
  TyAddColorItem(AItems, 'Teal',    clTeal);
  TyAddColorItem(AItems, 'Gray',    clGray);
  TyAddColorItem(AItems, 'Silver',  clSilver);
  TyAddColorItem(AItems, 'Red',     clRed);
  TyAddColorItem(AItems, 'Lime',    clLime);
  TyAddColorItem(AItems, 'Yellow',  clYellow);
  TyAddColorItem(AItems, 'Blue',    clBlue);
  TyAddColorItem(AItems, 'Fuchsia', clFuchsia);
  TyAddColorItem(AItems, 'Aqua',    clAqua);
  TyAddColorItem(AItems, 'White',   clWhite);
end;

function TySelectColorIndex(AItems: TStrings; AColor: TColor; AAppendIfMissing: Boolean): Integer;
var
  i: Integer;
  target: LongInt;
begin
  if AColor = clNone then Exit(-1);   // clear
  target := ColorToRGB(AColor);
  for i := 0 to AItems.Count - 1 do
    if ColorToRGB(TyColorOfItem(AItems, i)) = target then Exit(i);
  if not AAppendIfMissing then Exit(-1);
  // Not present: append a hex-named item and select it.
  TyAddColorItem(AItems, Format('#%.2x%.2x%.2x', [Red(target), Green(target), Blue(target)]), AColor);
  Result := AItems.Count - 1;
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
  TyAddDefaultColorPalette(Items);
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
  TyAddColorItem(Items, AName, AColor);
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
begin
  ItemIndex := TySelectColorIndex(Items, AValue, False);   // matches, else -1
end;

function TTyColorBox.CreatePopupList: TTyListBox;
begin
  Result := TTyColorPopupList.Create(Self);
end;

procedure TTyColorBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    TyDrawColorRow(P, ATextRect, ColorAt(ItemIndex), Items[ItemIndex], AStyle, ResolveFontSize(AStyle))
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);
end;

end.
