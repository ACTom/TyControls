unit tyControls.FontListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Forms,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.FontComboBox;

type
  { A list box of installed font families, each row drawn IN ITS OWN typeface (via the
    TTyListBox.PaintItemContent hook + the shared TyDrawFontRow). The list-box sibling of
    TTyFontComboBox. Populated from Screen.Fonts; SelectedFont is the chosen family. }
  TTyFontListBox = class(TTyListBox)
  private
    function GetSelectedFont: string;
    procedure SetSelectedFont(const AValue: string);
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RefreshFonts;
    property SelectedFont: string read GetSelectedFont write SetSelectedFont;
  end;

implementation

constructor TTyFontListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  RefreshFonts;
end;

procedure TTyFontListBox.RefreshFonts;
begin
  Items.BeginUpdate;
  try
    Items.Clear;
    Items.Assign(Screen.Fonts);
  finally
    Items.EndUpdate;
  end;
  if Items.Count > 0 then ItemIndex := 0;
end;

procedure TTyFontListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  TyDrawFontRow(P, ARowRect, Items[AIndex], AStyle, ResolveFontSize(AStyle));
end;

function TTyFontListBox.GetSelectedFont: string;
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    Result := Items[ItemIndex]
  else
    Result := '';
end;

procedure TTyFontListBox.SetSelectedFont(const AValue: string);
var idx: Integer;
begin
  idx := Items.IndexOf(AValue);
  if idx >= 0 then ItemIndex := idx;
end;

end.
