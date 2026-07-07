unit tyControls.FontComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox;

type
  { The drop-down list for TTyFontComboBox: each row is drawn IN ITS OWN font (the row's
    text is a font-family name, so it is rendered using that family). }
  TTyFontPopupList = class(TTyListBox)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { A combo of installed font families, each item (field + drop-down) drawn in its own
    typeface — a WYSIWYG font picker. Subclasses TTyComboBox; the chosen family is
    SelectedFont (== Text). Populated from Screen.Fonts; RefreshFonts re-reads them.
    Reuses the 'TyComboBox' / 'TyListItem' theming. }
  TTyFontComboBox = class(TTyComboBox)
  private
    function GetSelectedFont: string;
    procedure SetSelectedFont(const AValue: string);
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Re-populate the family list from Screen.Fonts (call after installing fonts).
    procedure RefreshFonts;
    // The selected font family (== the selected item's text). Setting selects the matching
    // item if present.
    property SelectedFont: string read GetSelectedFont write SetSelectedFont;
  end;

implementation

{ TTyFontPopupList }

procedure TTyFontPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  // Font name = the row's own text -> draw it in that very family (WYSIWYG).
  P.DrawText(
    Rect(ARowRect.Left + P.Scale(AStyle.Padding.Left), ARowRect.Top,
         ARowRect.Right - P.Scale(AStyle.Padding.Right), ARowRect.Bottom),
    Items[AIndex], Items[AIndex], ResolveFontSize(AStyle), AStyle.FontWeight,
    AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

{ TTyFontComboBox }

constructor TTyFontComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  RefreshFonts;
end;

procedure TTyFontComboBox.RefreshFonts;
begin
  Items.BeginUpdate;
  try
    Items.Clear;
    Items.Assign(Screen.Fonts);   // installed font families
  finally
    Items.EndUpdate;
  end;
  if Items.Count > 0 then ItemIndex := 0;
end;

function TTyFontComboBox.CreatePopupList: TTyListBox;
begin
  Result := TTyFontPopupList.Create(Self);
end;

procedure TTyFontComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    P.DrawText(ATextRect, Items[ItemIndex], Items[ItemIndex], AStyle.FontSize,
      AStyle.FontWeight, AStyle.TextColor, taLeftJustify, tlCenter, True)
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);
end;

function TTyFontComboBox.GetSelectedFont: string;
begin
  Result := Text;
end;

procedure TTyFontComboBox.SetSelectedFont(const AValue: string);
var idx: Integer;
begin
  idx := Items.IndexOf(AValue);
  if idx >= 0 then ItemIndex := idx;
end;

end.
