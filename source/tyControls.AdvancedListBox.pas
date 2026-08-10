unit tyControls.AdvancedListBox;
{$mode objfpc}{$H+}

{ TTyAdvancedListBox — a list box of RICH two-line rows: an optional left IMAGE, a
  bold TITLE line, and a dim SUBTITLE line beneath it (taller rows than a plain list).

  DATA MODEL (sort-safe, no parallel arrays):
    * The two text lines are stored JOINED in the item string as
      `Title + LineEnding + Subtitle` (the subtitle part may be empty), so a single
      TStringList entry carries both — surviving Sorted / Delete and copied verbatim by
      Items.Assign (which is how a combo popup reads the same rows).
    * The image INDEX rides in Items.Objects[i] as TObject(PtrInt(AImageIndex + 1))
      (0 => no image), intrinsically aligned with its row through any reorder.
  Sorting keys on the WHOLE joined string (Title first, so it sorts by title), which is
  the expected order.

  The images come from a TTyVirtualImageList (Images property): its index-addressed
  CachedIndex(AIndex, ASizePx) borrows a bitmap scaled to the target pixel size from
  the collection's render cache — we blit it, we never free or modify it.
  A FreeNotification nils the reference if the list is freed first.

  The row draw is factored into TyDrawAdvancedRow so a combo's popup list can render the
  identical two-line row. All chrome colours/sizes come from the resolved 'TyListItem'
  style — nothing is hard-coded (the subtitle merely reuses the text token at a reduced
  alpha, so its colour still tracks the theme). }

interface
uses
  Classes, SysUtils, ImgList, Types, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ListBox, tyControls.ImageCollection, tyControls.ImageDraw;

{ Split a joined `Title + LineEnding + Subtitle` string into its two parts. ASubtitle is
  '' when the item has no LineEnding. Shared by the control and any popup that stores rows
  the same way. }
procedure TySplitAdvancedItem(const AJoined: string; out ATitle, ASubtitle: string);

{ Shared rich-row draw into ARect on P.Bitmap: an optional left image (from AImages at
  AImageIndex; AImageIndex < 0 or AImages = nil => text only), then the bold TITLE line
  and, below it, the dim SUBTITLE line. All colours/sizes derive from AStyle — the
  subtitle reuses AStyle.TextColor at reduced alpha (still theme-driven). Used by both the
  list box rows and a combo's popup rows so the layout lives in one place. }
procedure TyDrawAdvancedRow(P: TTyPainter; const ARect: TRect; const AJoined: string;
  AImageIndex: Integer; AImages: TCustomImageList; const AStyle: TTyStyleSet;
  AFontSize: Integer);

type
  { A list box whose rows are image + bold title + dim subtitle. Build it with
    AddItem(title, subtitle, imageIndex); read the parts back with TitleOf / SubtitleOf /
    ImageIndexOf. The image source is the Images (TTyVirtualImageList). }
  TTyAdvancedListBox = class(TTyListBox)
  private
    FImages: TCustomImageList;
    procedure SetImages(const AValue: TCustomImageList);
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Append a rich row. ATitle + ASubtitle are stored joined by LineEnding (ASubtitle may
      be ''); AImageIndex < 0 => no image. The image index lives in Items.Objects[]. }
    procedure AddItem(const ATitle, ASubtitle: string; AImageIndex: Integer);
    { The title of row AIndex ('' when out of range). }
    function TitleOf(AIndex: Integer): string;
    { The subtitle of row AIndex ('' when none / out of range). }
    function SubtitleOf(AIndex: Integer): string;
    { The image index stored for row AIndex, or -1 when it has no image / is out of range. }
    function ImageIndexOf(AIndex: Integer): Integer;
  published
    { The raster image source (index-addressed). A FreeNotification nils this reference
      automatically if the list is freed first. }
    property Images: TCustomImageList read FImages write SetImages;
  end;

implementation

procedure TySplitAdvancedItem(const AJoined: string; out ATitle, ASubtitle: string);
var
  p: Integer;
begin
  p := Pos(LineEnding, AJoined);
  if p > 0 then
  begin
    ATitle := Copy(AJoined, 1, p - 1);
    ASubtitle := Copy(AJoined, p + Length(LineEnding), MaxInt);
  end
  else
  begin
    ATitle := AJoined;
    ASubtitle := '';
  end;
end;

procedure TyDrawAdvancedRow(P: TTyPainter; const ARect: TRect; const AJoined: string;
  AImageIndex: Integer; AImages: TCustomImageList; const AStyle: TTyStyleSet;
  AFontSize: Integer);
var
  titleText, subText: string;
  x, sz, rowH, textLeft, midY, pad: Integer;
  titleR, subR: TRect;
  subColor: TTyColor;
  subSize: Integer;
begin
  TySplitAdvancedItem(AJoined, titleText, subText);
  pad := P.Scale(4);
  rowH := ARect.Bottom - ARect.Top;
  x := ARect.Left + pad;

  // Optional left image: a square sized to the row height minus vertical padding,
  // vertically centered. CachedIndex borrows the collection's render — nothing to free.
  if (AImages <> nil) and (AImageIndex >= 0) and (AImageIndex < TyImageCount(AImages)) then
  begin
    sz := rowH - P.Scale(8);
    if sz < 8 then sz := 8;
    TyBlitImage(P.Bitmap, AImages, AImageIndex, x, ARect.Top + ((rowH - sz) div 2), sz,
      P.Scale(96), False);
    x := x + sz + pad;
  end;
  textLeft := x;

  // When there is a subtitle, stack the two lines around the row's vertical center; when
  // there is none, center the single title line in the row.
  subSize := AFontSize - 2;
  if subSize < 1 then subSize := 1;
  // Dim the subtitle by lowering the text token's alpha (RGB stays the theme colour).
  subColor := (AStyle.TextColor and $00FFFFFF)
    or (Cardinal((TyAlphaOf(AStyle.TextColor) * 65) div 100) shl 24);

  if subText <> '' then
  begin
    midY := ARect.Top + (rowH div 2);
    titleR := Rect(textLeft, ARect.Top, ARect.Right - pad, midY);
    subR := Rect(textLeft, midY, ARect.Right - pad, ARect.Bottom);
    P.DrawText(titleR, titleText, AStyle.FontName, AFontSize, 700,
      AStyle.TextColor, taLeftJustify, tlCenter, True);
    P.DrawText(subR, subText, AStyle.FontName, subSize, AStyle.FontWeight,
      subColor, taLeftJustify, tlCenter, True);
  end
  else
  begin
    titleR := Rect(textLeft, ARect.Top, ARect.Right - pad, ARect.Bottom);
    P.DrawText(titleR, titleText, AStyle.FontName, AFontSize, 700,
      AStyle.TextColor, taLeftJustify, tlCenter, True);
  end;
end;

{ TTyAdvancedListBox }

constructor TTyAdvancedListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ItemHeight := 40;   // taller rows to fit two lines
end;

procedure TTyAdvancedListBox.SetImages(const AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then
    FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then
    FImages.FreeNotification(Self);
  Invalidate;
end;

procedure TTyAdvancedListBox.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
end;

procedure TTyAdvancedListBox.AddItem(const ATitle, ASubtitle: string; AImageIndex: Integer);
begin
  // Join the two lines so both survive Sorted/Delete in one entry; the image index rides
  // in Objects[] (offset by +1 so 0 = no image) — copied by Items.Assign, never a side array.
  Items.AddObject(ATitle + LineEnding + ASubtitle, TObject(PtrInt(AImageIndex + 1)));
end;

function TTyAdvancedListBox.TitleOf(AIndex: Integer): string;
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

function TTyAdvancedListBox.SubtitleOf(AIndex: Integer): string;
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

function TTyAdvancedListBox.ImageIndexOf(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then
    Result := PtrInt(Items.Objects[AIndex]) - 1
  else
    Result := -1;
end;

procedure TTyAdvancedListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  TyDrawAdvancedRow(P, ARowRect, Items[AIndex], ImageIndexOf(AIndex), FImages, AStyle,
    ResolveFontSize(AStyle));
end;

end.
