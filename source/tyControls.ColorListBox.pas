unit tyControls.ColorListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ColorBox;

type
  { A list box of named colours: each row shows a colour swatch + name (via the
    TTyListBox.PaintItemContent hook). The colour lives in Items.Objects[i], intrinsically
    aligned with the name (survives Sorted / Delete). Manage via AddColor / ClearColors;
    Selected is the chosen TColor. The list-box sibling of TTyColorBox. }
  TTyColorListBox = class(TTyListBox)
  private
    function GetSelected: TColor;
    procedure SetSelected(const AValue: TColor);
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ClearColors;
    procedure AddColor(const AName: string; AColor: TColor);
    function ColorAt(AIndex: Integer): TColor;
    property Selected: TColor read GetSelected write SetSelected;
  end;

implementation

constructor TTyColorListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAddDefaultColorPalette(Items);
  if Items.Count > 0 then ItemIndex := 0;
end;

procedure TTyColorListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  TyDrawColorRow(P, ARowRect, TyColorOfItem(Items, AIndex), Items[AIndex], AStyle,
    ResolveFontSize(AStyle));
end;

procedure TTyColorListBox.ClearColors;
begin
  Items.Clear;
end;

procedure TTyColorListBox.AddColor(const AName: string; AColor: TColor);
begin
  TyAddColorItem(Items, AName, AColor);
end;

function TTyColorListBox.ColorAt(AIndex: Integer): TColor;
begin
  Result := TyColorOfItem(Items, AIndex);
end;

function TTyColorListBox.GetSelected: TColor;
begin
  Result := ColorAt(ItemIndex);
end;

procedure TTyColorListBox.SetSelected(const AValue: TColor);
begin
  ItemIndex := TySelectColorIndex(Items, AValue);
end;

end.
