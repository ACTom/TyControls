unit tyControls.AdvancedComboBox;
{$mode objfpc}{$H+}

{ TTyAdvancedComboBox — a combo whose items are RICH two-line rows (an optional left
  IMAGE + a bold TITLE + a dim SUBTITLE). The drop-down list shows all three lines; the
  short field draws only the image + title of the selected item.

  DATA MODEL — identical to TTyAdvancedListBox and sort-safe (no parallel arrays):
    * The two text lines are stored JOINED as `Title + LineEnding + Subtitle` in the item
      string (subtitle may be empty).
    * The image INDEX rides in Items.Objects[i] as TObject(PtrInt(AImageIndex + 1))
      (0 => no image). Items.Assign copies Objects[], so the popup list reads the same
      indices; sorting keys on the whole joined string (title first).

  This unit is self-contained: it defines its OWN popup list (TTyAdvancedComboPopupList).
  It reuses tyControls.AdvancedListBox only for the shared row-draw / split helpers
  (TyDrawAdvancedRow / TySplitAdvancedItem), so the field, popup, and list box all render
  identical rows from one place. Images come from a TTyVirtualImageList (Images property);
  a FreeNotification nils the reference if the list is freed first. }

interface
uses
  Classes, SysUtils, Types, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox, tyControls.ImageCollection,
  tyControls.AdvancedListBox;

type
  { Drop-down list for TTyAdvancedComboBox: draws the full two-line rich row per item via
    the TTyListBox.PaintItemContent hook, reading its OWN Items (the combo copies its
    Items — including Objects[] image indices — into this list via Items.Assign) and the
    owning combo's Images. Its Owner is the combo (CreatePopupList does Create(Self)). }
  TTyAdvancedComboPopupList = class(TTyComboPopupList)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { A combo of rich two-line items. Add items with AddItem(title, subtitle, imageIndex);
    read them back with TitleOf / SubtitleOf / ImageIndexOf. The image source is the
    Images (TTyVirtualImageList). }
  TTyAdvancedComboBox = class(TTyComboBox)
  private
    FImages: TTyVirtualImageList;
    procedure SetImages(const AValue: TTyVirtualImageList);
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    { Locked to csDropDownList: editable/prefix-filtered csDropDown drives a SINGLE-line
      editor + Text from the joined 'Title'+LineEnding+'Subtitle' item string, which would
      leak an embedded newline. Rich two-line items are pick-only. }
    procedure SetStyle(AValue: TTyComboBoxStyle); override;
  public
    { Append a rich row. ATitle + ASubtitle are stored joined by LineEnding (ASubtitle may
      be ''); AImageIndex < 0 => no image (stored in Items.Objects[] as AImageIndex + 1). }
    procedure AddItem(const ATitle, ASubtitle: string; AImageIndex: Integer);
    { The title of item AIndex ('' when out of range). }
    function TitleOf(AIndex: Integer): string;
    { The subtitle of item AIndex ('' when none / out of range). }
    function SubtitleOf(AIndex: Integer): string;
    { The image index stored for item AIndex, or -1 when it has no image / is out of range. }
    function ImageIndexOf(AIndex: Integer): Integer;
    { The list this combo's popup draws with; also the source the popup rows read Images
      from (they cast Owner back to this combo). Exposed for the shared field draw. }
    property ImagesRef: TTyVirtualImageList read FImages;
  published
    { The raster image source (index-addressed). A FreeNotification nils this reference
      automatically if the list is freed first. }
    property Images: TTyVirtualImageList read FImages write SetImages;
  end;

implementation

procedure TTyAdvancedComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  { Pick-only, and ONLY pick-only: the edit box is what the joined two-line item string
    cannot survive, so that is what comes off. Flattening the whole value to csDropDownList
    also killed owner-draw, which is orthogonal to editability and which a rich-row combo is
    the likeliest of all of them to want. }
  inherited SetStyle(TyComboStylePickOnly(AValue));
end;

{ TTyAdvancedComboPopupList }

procedure TTyAdvancedComboPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
var
  imgs: TTyVirtualImageList;
begin
  { Owner-draw first: the rich-row branch below replaces the whole row, so an inherited call
    would be too late. Inert unless the combo has both an owner-draw Style and a handler. }
  if TyComboCollectRowOwnerDraw(Self, ARowRect, AIndex) then Exit;
  // The Owner is the combo (Create(Self) in CreatePopupList); it supplies the Images
  // reference. The image index rides in Objects[] (copied from the combo via Items.Assign):
  // PtrInt(Objects[i]) - 1, so 0 => -1 (no image).
  if Owner is TTyAdvancedComboBox then
  begin
    imgs := TTyAdvancedComboBox(Owner).ImagesRef;
    TyDrawAdvancedRow(P, ARowRect, Items[AIndex], PtrInt(Items.Objects[AIndex]) - 1,
      imgs, AStyle, ResolveFontSize(AStyle));
  end
  else
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
end;

{ TTyAdvancedComboBox }

procedure TTyAdvancedComboBox.SetImages(const AValue: TTyVirtualImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then
    FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then
    FImages.FreeNotification(Self);
  Invalidate;
end;

procedure TTyAdvancedComboBox.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
end;

procedure TTyAdvancedComboBox.AddItem(const ATitle, ASubtitle: string; AImageIndex: Integer);
begin
  // Join the two lines into one entry (both survive Sorted/Delete); the image index rides
  // in Objects[] (offset by +1 so 0 = no image) — copied by Items.Assign into the popup.
  Items.AddObject(ATitle + LineEnding + ASubtitle, TObject(PtrInt(AImageIndex + 1)));
end;

function TTyAdvancedComboBox.TitleOf(AIndex: Integer): string;
var
  t, s: string;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then
  begin
    TySplitAdvancedItem(Items[AIndex], t, s);
    Result := t;
  end
  else
    Result := '';
end;

function TTyAdvancedComboBox.SubtitleOf(AIndex: Integer): string;
var
  t, s: string;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then
  begin
    TySplitAdvancedItem(Items[AIndex], t, s);
    Result := s;
  end
  else
    Result := '';
end;

function TTyAdvancedComboBox.ImageIndexOf(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then
    Result := PtrInt(Items.Objects[AIndex]) - 1
  else
    Result := -1;
end;

procedure TTyAdvancedComboBox.PaintFieldContent(P: TTyPainter; const ATextRect: TRect;
  const AStyle: TTyStyleSet);
var
  titleOnly: string;
begin
  // The field is short: draw the selected item's image + TITLE only (no subtitle line).
  // Pass the title as a joined string with an empty subtitle so TyDrawAdvancedRow centers
  // the single line and reuses the same image layout as the rows.
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
  begin
    titleOnly := TitleOf(ItemIndex);
    TyDrawAdvancedRow(P, ATextRect, titleOnly, ImageIndexOf(ItemIndex), FImages, AStyle,
      ResolveFontSize(AStyle));
  end
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);
end;

function TTyAdvancedComboBox.CreatePopupList: TTyListBox;
begin
  Result := TTyAdvancedComboPopupList.Create(Self);
  Result.ItemHeight := 40;   // taller rows to match the rich two-line layout
end;

end.
