unit tyControls.ComboBoxEx;
{$mode objfpc}{$H+}

{ TTyComboBoxEx — a combo whose items carry an optional per-item image drawn beside
  the text, in BOTH the field and the drop-down. Subclasses TTyComboBox, injecting an
  image-drawing popup list (CreatePopupList) and an image field (PaintFieldContent).

  The per-item image INDEX lives in Items.Objects[i] as TObject(PtrInt(index + 1))
  (0 => no image), so it stays intrinsically aligned with the name through Sorted /
  Delete / direct edits (no parallel array) — and the combo's Items (Objects included)
  are copied into the popup list via Items.Assign, so the popup reads the same indices.

  The images come from a TTyVirtualImageList (Images property): the index-addressed
  raster source whose RenderIndex(AIndex, ASizePx) returns a fresh caller-owned bitmap
  scaled to the target pixel size. }

interface
uses
  Classes, SysUtils, Types, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox, tyControls.ImageCollection;

type
  { Drop-down list for TTyComboBoxEx: draws an image + name per row via the
    TTyListBox.PaintItemContent hook. The image index is carried in each item's
    Objects[] entry (the combo copies its Items — including Objects — into this list),
    so there is no side array that could desync from the names. Its Owner is the combo
    (CreatePopupList does Create(Self)), which supplies the shared draw method. }
  TTyComboBoxExPopupList = class(TTyListBox)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { A combo of image + text items. Add items with AddItem(text, imageIndex); a -1 image
    index means text only. The image source is the Images (TTyVirtualImageList). }
  TTyComboBoxEx = class(TTyComboBox)
  private
    FImages: TTyVirtualImageList;
    procedure SetImages(const AValue: TTyVirtualImageList);
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    { Append an item with an optional image (AImageIndex < 0 => text only). The index
      is stored intrinsically in Items.Objects[] (as AImageIndex + 1). }
    procedure AddItem(const S: string; AImageIndex: Integer);
    { The image index stored for item AIndex, or -1 when it has no image / is out of
      range. Test seam and the paint path's single source of the mapping. }
    function ImageIndexOf(AIndex: Integer): Integer;
    { Shared draw: an image (left, from Images at AImageIndex) + text (right) into ARect.
      Reused by the field and the popup rows so the layout lives in one place. AImageIndex
      < 0 (or no Images) draws text only. }
    procedure DrawImageText(P: TTyPainter; const ARect: TRect; const S: string;
      AImageIndex: Integer; const AStyle: TTyStyleSet);
  published
    { The raster image source (index-addressed). A FreeNotification nils this reference
      automatically if the list is freed first. }
    property Images: TTyVirtualImageList read FImages write SetImages;
  end;

implementation

{ TTyComboBoxExPopupList }

procedure TTyComboBoxExPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  { The Owner is the combo (Create(Self) in CreatePopupList); it owns the shared draw
    method and the Images reference. The image index rides in Objects[] (copied from the
    combo via Items.Assign): PtrInt(Objects[i]) - 1, so 0 => -1 (no image). }
  if Owner is TTyComboBoxEx then
    TTyComboBoxEx(Owner).DrawImageText(P, ARowRect, Items[AIndex],
      PtrInt(Items.Objects[AIndex]) - 1, AStyle)
  else
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
end;

{ TTyComboBoxEx }

procedure TTyComboBoxEx.SetImages(const AValue: TTyVirtualImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then
    FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then
    FImages.FreeNotification(Self);
  Invalidate;
end;

procedure TTyComboBoxEx.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
end;

procedure TTyComboBoxEx.AddItem(const S: string; AImageIndex: Integer);
begin
  { Store the image index intrinsically (offset by +1 so 0 = no image). Objects[] is
    copied by Items.Assign into the popup list, so the mapping can never desync. }
  Items.AddObject(S, TObject(PtrInt(AImageIndex + 1)));
end;

function TTyComboBoxEx.ImageIndexOf(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then
    Result := PtrInt(Items.Objects[AIndex]) - 1
  else
    Result := -1;
end;

procedure TTyComboBoxEx.DrawImageText(P: TTyPainter; const ARect: TRect; const S: string;
  AImageIndex: Integer; const AStyle: TTyStyleSet);
var
  x, sz: Integer;
  textR: TRect;
  bmp: TBGRABitmap;
begin
  x := ARect.Left + P.Scale(4);
  if (FImages <> nil) and (AImageIndex >= 0) and (AImageIndex < FImages.Count) then
  begin
    sz := (ARect.Bottom - ARect.Top) - P.Scale(6);
    if sz < 8 then sz := 8;
    bmp := FImages.RenderIndex(AImageIndex, sz);   // caller frees
    if bmp <> nil then
      try
        P.Bitmap.PutImage(x, ARect.Top + ((ARect.Bottom - ARect.Top - bmp.Height) div 2),
          bmp, dmDrawWithTransparency);
      finally
        bmp.Free;
      end;
    x := x + sz + P.Scale(4);
  end;
  textR := Rect(x, ARect.Top, ARect.Right - P.Scale(4), ARect.Bottom);
  P.DrawText(textR, S, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
    AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

procedure TTyComboBoxEx.PaintFieldContent(P: TTyPainter; const ATextRect: TRect;
  const AStyle: TTyStyleSet);
begin
  if (ItemIndex >= 0) and (ItemIndex < Items.Count) then
    DrawImageText(P, ATextRect, Items[ItemIndex], ImageIndexOf(ItemIndex), AStyle)
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);
end;

function TTyComboBoxEx.CreatePopupList: TTyListBox;
begin
  Result := TTyComboBoxExPopupList.Create(Self);
end;

end.
