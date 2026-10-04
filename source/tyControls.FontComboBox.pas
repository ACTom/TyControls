unit tyControls.FontComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox;

{ Draw AFontName into ARect USING AFontName as the typeface (WYSIWYG), inset by the style
  padding; AFontSize is the caller's resolved size. Shared by the font combo's popup list
  and TTyFontListBox. }
procedure TyDrawFontRow(P: TTyPainter; const ARect: TRect; const AFontName: string;
  const AStyle: TTyStyleSet; AFontSize: Integer);

type
  { The drop-down list for TTyFontComboBox: each row is drawn IN ITS OWN font (the row's
    text is a font-family name, so it is rendered using that family). }
  TTyFontPopupList = class(TTyComboPopupList)
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
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    // Re-populate the family list from Screen.Fonts (call after installing fonts).
    procedure RefreshFonts;
    // The selected font family (== the selected item's text). Setting selects the matching
    // item if present.
    property SelectedFont: string read GetSelectedFont write SetSelectedFont;
  end;

{ The font families a font picker lists: Screen.Fonts, in its order, without the names that start
  with '@'. Those are Windows' vertical-writing aliases of the CJK fonts (@SimSun, @新宋体), which
  draw every glyph turned on its side, and no Windows font picker lists them. ADest's contents are
  replaced in one change. }
procedure TyFontPickerFamilies(ADest: TStrings);

implementation

procedure TyFontPickerFamilies(ADest: TStrings);
var
  i: Integer;
  nm: string;
begin
  ADest.BeginUpdate;
  try
    ADest.Clear;
    for i := 0 to Screen.Fonts.Count - 1 do
    begin
      nm := Screen.Fonts[i];
      if (nm <> '') and (nm[1] = '@') then Continue;
      ADest.Add(nm);
    end;
  finally
    ADest.EndUpdate;
  end;
end;

procedure TyDrawFontRow(P: TTyPainter; const ARect: TRect; const AFontName: string;
  const AStyle: TTyStyleSet; AFontSize: Integer);
begin
  P.DrawText(
    Rect(ARect.Left + P.Scale(AStyle.Padding.Left), ARect.Top,
         ARect.Right - P.Scale(AStyle.Padding.Right), ARect.Bottom),
    AFontName, AFontName, AFontSize, AStyle.FontWeight, AStyle.TextColor,
    taLeftJustify, tlCenter, True);
end;

{ TTyFontPopupList }

procedure TTyFontPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  { Owner-draw first, and it has to be spelled out here rather than left to the ancestor:
    this override replaces the whole row, so an inherited call would already be too late.
    True only when the combo really has both an owner-draw Style and a handler; the row
    background is already down and the dispatch runs after EndPaint, from the Paint override
    inherited from TTyComboPopupList. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  // Font name = the row's own text -> draw it in that very family (WYSIWYG).
  TyDrawFontRow(P, ARowRect, Items[AIndex], AStyle, ResolveFontSize(AStyle));
end;

{ TTyFontComboBox }

constructor TTyFontComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { The rows are the fonts installed on THIS machine, not something the author typed. Written
    into a form file they came back on every other machine as the saving machine's fonts -- a
    few hundred names in each .lfm. Reading an Items block still works, which is how a form
    saved by 3.0.0 loads; Loaded then replaces it. }
  FItemsStreamed := False;
  RefreshFonts;
end;

procedure TTyFontComboBox.Loaded;
begin
  inherited Loaded;
  { This machine's fonts again, for a form that still carries another machine's list. The combo
    re-pins its selection by TEXT whenever Items changes, so the chosen family stays chosen at
    whatever row it has here, and one this machine lacks is left unselected rather than swapped
    for whichever font took its row number. }
  TyFontPickerFamilies(Items);
end;

procedure TTyFontComboBox.RefreshFonts;
begin
  Items.BeginUpdate;
  try
    Items.Clear;
    TyFontPickerFamilies(Items);   // installed font families
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
    P.DrawText(ATextRect, Items[ItemIndex], Items[ItemIndex], ResolveFontSize(AStyle),
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
