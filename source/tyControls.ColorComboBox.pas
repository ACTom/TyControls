unit tyControls.ColorComboBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox, tyControls.ColorBox, tyControls.Dialogs.Color;

type
  { The drop-down list for TTyColorComboBox: like TTyColorPopupList, but a row whose colour
    is clNone (the "more…" sentinel) is drawn as plain text instead of a swatch. }
  TTyColorMorePopupList = class(TTyComboPopupList)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { TTyColorBox + a trailing "more…" row that opens the themed colour dialog; the picked
    colour is inserted before "more" and selected. The "more…" item is marked by a clNone
    colour in Objects[], so it renders as plain text and is detected without a side flag.
    Kept last, so appended custom colours slot in above it. }
  TTyColorComboBox = class(TTyColorBox)
  private
    FMoreCaption: string;
    FPrevIndex: Integer;    // last real selection, to revert a cancelled "more…"
    procedure SetMoreCaption(const AValue: string);
    function IsMoreIndex(AIndex: Integer): Boolean;
    procedure RebuildMoreItem;
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    procedure DoSelect; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property MoreCaption: string read FMoreCaption write SetMoreCaption;
  end;

implementation

{ TTyColorMorePopupList }

procedure TTyColorMorePopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var c: TColor;
begin
  { Owner-draw first: both branches below replace the whole row, so an inherited call would
    be too late. Inert unless the combo has both an owner-draw Style and a handler. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  c := TyColorOfItem(Items, AIndex);
  if c = clNone then
    // the "more…" row: plain text, no swatch.
    P.DrawText(
      Rect(ARowRect.Left + P.Scale(AStyle.Padding.Left), ARowRect.Top,
           ARowRect.Right - P.Scale(AStyle.Padding.Right), ARowRect.Bottom),
      Items[AIndex], AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
      AStyle.TextColor, taLeftJustify, tlCenter, True)
  else
    TyDrawColorRow(P, ARowRect, c, Items[AIndex], AStyle, ResolveFontSize(AStyle));
end;

{ TTyColorComboBox }

constructor TTyColorComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);        // fills the 16-colour palette + selects index 0
  FMoreCaption := 'More…';
  FPrevIndex := ItemIndex;
  RebuildMoreItem;
end;

procedure TTyColorComboBox.RebuildMoreItem;
var i: Integer;
begin
  // Drop any existing "more…" (clNone) row, then append a fresh one at the end.
  for i := Items.Count - 1 downto 0 do
    if TyColorOfItem(Items, i) = clNone then Items.Delete(i);
  TyAddColorItem(Items, FMoreCaption, clNone);
end;

procedure TTyColorComboBox.SetMoreCaption(const AValue: string);
begin
  if FMoreCaption = AValue then Exit;
  FMoreCaption := AValue;
  RebuildMoreItem;
end;

function TTyColorComboBox.IsMoreIndex(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex < Items.Count) and (ColorAt(AIndex) = clNone);
end;

function TTyColorComboBox.CreatePopupList: TTyListBox;
begin
  Result := TTyColorMorePopupList.Create(Self);
end;

procedure TTyColorComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet);
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) and not IsMoreIndex(ItemIndex) then
    TyDrawColorRow(P, ATextRect, ColorAt(ItemIndex), Items[ItemIndex], AStyle, ResolveFontSize(AStyle))
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);   // "more…" / none -> plain text
end;

procedure TTyColorComboBox.DoSelect;
var
  c: TColor;
  a: Byte;
  moreIdx: Integer;
begin
  if IsMoreIndex(ItemIndex) then
  begin
    moreIdx := ItemIndex;
    c := ColorAt(FPrevIndex);
    if c = clNone then c := clBlack;
    a := 255;
    if TySelectColor(FMoreCaption, c, a) then
    begin
      // Insert the picked colour just above "more…" and select it.
      Items.InsertObject(moreIdx, Format('#%.2x%.2x%.2x',
        [Red(ColorToRGB(c)), Green(ColorToRGB(c)), Blue(ColorToRGB(c))]), TObject(PtrInt(c)));
      ItemIndex := moreIdx;
      FPrevIndex := moreIdx;
      inherited DoSelect;
    end
    else
      ItemIndex := FPrevIndex;   // cancelled -> restore the previous real selection
  end
  else
  begin
    FPrevIndex := ItemIndex;
    inherited DoSelect;
  end;
end;

end.
