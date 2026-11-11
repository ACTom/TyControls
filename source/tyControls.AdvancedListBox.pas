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
    * A row that ItemEnabled turned OFF has bit 30 set in that same slot, so the flag goes
      wherever the row and its image index go. A row that is on -- every row until it is
      turned off -- keeps exactly the value above. Read the slot through
      TyAdvancedItemImageIndex / TyAdvancedItemEnabled rather than by subtracting 1.
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

{ What a rich row keeps in its Items.Objects[] slot (the unit header, DATA MODEL): the image
  index, -1 for none, and whether the row is on. For the list box and for anything that
  holds rows copied from one -- the rich combo and its popup. }
function TyAdvancedItemImageIndex(AObject: TObject): Integer;
function TyAdvancedItemEnabled(AObject: TObject): Boolean;

{ Shared rich-row draw into ARect on P.Bitmap: an optional left image (from AImages at
  AImageIndex; AImageIndex < 0 or AImages = nil => text only), then the bold TITLE line
  and, below it, the dim SUBTITLE line. All colours/sizes derive from AStyle — the
  subtitle reuses AStyle.TextColor at reduced alpha (still theme-driven). Used by both the
  list box rows and a combo's popup rows so the layout lives in one place. }
procedure TyDrawAdvancedRow(P: TTyPainter; const ARect: TRect; const AJoined: string;
  AImageIndex: Integer; AImages: TCustomImageList; const AStyle: TTyStyleSet;
  AFontSize: Integer; ARightToLeft: Boolean = False; AGhosted: Boolean = False);
{ #153: ARightToLeft -- a list row's RtlRowLayout -- puts the image on the right and the text
  against it, right-aligned. A painter already armed for mirroring turns the row itself (a
  combo's field), so it passes False.
  AGhosted: the row is turned off, AStyle being its disabled style. Its image is drawn faded;
  a font glyph already wears the disabled ink and is not faded on top of it. }

type
  { A list box whose rows are image + bold title + dim subtitle. Build it with
    AddItem(title, subtitle, imageIndex); read the parts back with TitleOf / SubtitleOf /
    ImageIndexOf. The image source is the Images (TTyVirtualImageList). }
  TTyCustomAdvancedListBox = class(TTyCustomListBox)
  private
    FImages: TCustomImageList;
    procedure SetImages(const AValue: TCustomImageList);
    function GetItemEnabled(AIndex: Integer): Boolean;
    procedure SetItemEnabled(AIndex: Integer; AValue: Boolean);
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
    function ItemStatesFor(AIndex: Integer; ABaseStates: TTyStateSet): TTyStateSet; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Append a rich row. ATitle + ASubtitle are stored joined by LineEnding (ASubtitle may
      be ''); AImageIndex < 0 => no image. The image index lives in Items.Objects[]. The row
      starts on (ItemEnabled). }
    procedure AddItem(const ATitle, ASubtitle: string; AImageIndex: Integer);
    { The title of row AIndex ('' when out of range). }
    function TitleOf(AIndex: Integer): string;
    { The subtitle of row AIndex ('' when none / out of range). }
    function SubtitleOf(AIndex: Integer): string;
    { The image index stored for row AIndex, or -1 when it has no image / is out of range. }
    function ImageIndexOf(AIndex: Integer): Integer;
    { Turn one row off: it is drawn in the theme's disabled row style -- its text in the
      disabled ink, its image ghosted -- like a row TTyCheckListBox.ItemEnabled turns off.
      It is a look, as in LCL's check list: the row can still be selected and clicked, and
      what a click on it does is the application's to decide. True for every row until it
      is set, and for an index out of range. }
    property ItemEnabled[AIndex: Integer]: Boolean read GetItemEnabled write SetItemEnabled;
    { The raster image source (index-addressed). A FreeNotification nils this reference
      automatically if the list is freed first. }
    property Images: TCustomImageList read FImages write SetImages;
  end;

  { TTyAdvancedListBox publishes TTyCustomAdvancedListBox's properties; everything lives in TTyCustomAdvancedListBox. }
  TTyAdvancedListBox = class(TTyCustomAdvancedListBox)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Items;
    property ItemIndex;
    property MultiSelect;
    property ExtendedSelect;
    property Sorted;
    property ItemHeight;
    property ScrollWidth;
    property ScrollBarAutoHide;
    property TopIndex;
    property OnChange;
    property OnSelectionChange;
    property Align;
    property Anchors;
    property Images;
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

const
  { Bit 30 of a row's slot: the row is turned off. Above any image index + 1 a list can hold,
    and inside a PtrInt on a 32-bit target. }
  AdvancedItemOff = PtrInt(1) shl 30;

function TyAdvancedItemEnabled(AObject: TObject): Boolean;
begin
  { A slot that is not positive is a row with no image, written before the flag existed or
    with a negative index: it has no flag to read. }
  Result := (PtrInt(AObject) <= 0) or ((PtrInt(AObject) and AdvancedItemOff) = 0);
end;

function TyAdvancedItemImageIndex(AObject: TObject): Integer;
var
  v: PtrInt;
begin
  v := PtrInt(AObject);
  if v > 0 then v := v and not AdvancedItemOff;
  Result := v - 1;
end;

procedure TyDrawAdvancedRow(P: TTyPainter; const ARect: TRect; const AJoined: string;
  AImageIndex: Integer; AImages: TCustomImageList; const AStyle: TTyStyleSet;
  AFontSize: Integer; ARightToLeft: Boolean; AGhosted: Boolean);
var
  titleText, subText: string;
  x, sz, rowH, textLeft, textRight, midY, pad: Integer;
  titleR, subR: TRect;
  al: TAlignment;
  subColor: TTyColor;
  subSize: Integer;
begin
  TySplitAdvancedItem(AJoined, titleText, subText);
  pad := P.Scale(4);
  rowH := ARect.Bottom - ARect.Top;
  x := ARect.Left + pad;
  textRight := ARect.Right - pad;

  // Optional left image: a square sized to the row height minus vertical padding,
  // vertically centered. CachedIndex borrows the collection's render — nothing to free.
  // A font glyph of our own list is drawn in the row's ink, like the title beside it.
  if (AImages <> nil) and (AImageIndex >= 0) and (AImageIndex < TyImageCount(AImages)) then
  begin
    sz := rowH - P.Scale(8);
    if sz < P.Scale(8) then sz := P.Scale(8);
    if ARightToLeft then
    begin
      TyBlitImageScaled(P, AImages, AImageIndex, textRight - sz, ARect.Top + ((rowH - sz) div 2),
        sz, AGhosted, AStyle.TextColor);
      textRight := textRight - sz - pad;
    end
    else
    begin
      TyBlitImageScaled(P, AImages, AImageIndex, x, ARect.Top + ((rowH - sz) div 2), sz, AGhosted,
        AStyle.TextColor);
      x := x + sz + pad;
    end;
  end;
  textLeft := x;
  if ARightToLeft then al := taRightJustify else al := taLeftJustify;

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
    titleR := Rect(textLeft, ARect.Top, textRight, midY);
    subR := Rect(textLeft, midY, textRight, ARect.Bottom);
    P.DrawText(titleR, titleText, AStyle.FontName, AFontSize,
      700 or (AStyle.FontWeight and not TyFontWeightMask),   // bold over the font's italic etc. (#113)
      AStyle.TextColor, al, tlCenter, True);
    P.DrawText(subR, subText, AStyle.FontName, subSize, AStyle.FontWeight,
      subColor, al, tlCenter, True);
  end
  else
  begin
    titleR := Rect(textLeft, ARect.Top, textRight, ARect.Bottom);
    P.DrawText(titleR, titleText, AStyle.FontName, AFontSize,
      700 or (AStyle.FontWeight and not TyFontWeightMask),   // bold over the font's italic etc. (#113)
      AStyle.TextColor, al, tlCenter, True);
  end;
end;

{ TTyCustomAdvancedListBox }

constructor TTyCustomAdvancedListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ItemHeight := 40;   // taller rows to fit two lines
end;

procedure TTyCustomAdvancedListBox.SetImages(const AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then
    FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then
    FImages.FreeNotification(Self);
  Invalidate;
end;

procedure TTyCustomAdvancedListBox.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
end;

procedure TTyCustomAdvancedListBox.AddItem(const ATitle, ASubtitle: string; AImageIndex: Integer);
begin
  // Join the two lines so both survive Sorted/Delete in one entry; the image index rides
  // in Objects[] (offset by +1 so 0 = no image) — copied by Items.Assign, never a side array.
  Items.AddObject(ATitle + LineEnding + ASubtitle, TObject(PtrInt(AImageIndex + 1)));
end;

function TTyCustomAdvancedListBox.TitleOf(AIndex: Integer): string;
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

function TTyCustomAdvancedListBox.SubtitleOf(AIndex: Integer): string;
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

function TTyCustomAdvancedListBox.ImageIndexOf(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < Items.Count) then
    Result := TyAdvancedItemImageIndex(Items.Objects[AIndex])
  else
    Result := -1;
end;

function TTyCustomAdvancedListBox.GetItemEnabled(AIndex: Integer): Boolean;
begin
  Result := (AIndex < 0) or (AIndex >= Items.Count)
    or TyAdvancedItemEnabled(Items.Objects[AIndex]);
end;

procedure TTyCustomAdvancedListBox.SetItemEnabled(AIndex: Integer; AValue: Boolean);
var
  v: PtrInt;
begin
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  if GetItemEnabled(AIndex) = AValue then Exit;
  v := PtrInt(Items.Objects[AIndex]);
  if AValue then
    v := v and not AdvancedItemOff   { back to the bare image index + 1 }
  else
  begin
    if v < 0 then v := 0;            { "no image" written as a negative index }
    v := v or AdvancedItemOff;
  end;
  Items.Objects[AIndex] := TObject(v);   { the list's own change notice repaints }
end;

function TTyCustomAdvancedListBox.ItemStatesFor(AIndex: Integer; ABaseStates: TTyStateSet): TTyStateSet;
begin
  Result := inherited ItemStatesFor(AIndex, ABaseStates);
  { A row that is off resolves the row style's :disabled, as TTyCheckListBox's does. It keeps
    tysActive: it can still be the selected row. }
  if not GetItemEnabled(AIndex) then
  begin
    Exclude(Result, tysNormal);
    Exclude(Result, tysHover);
    Include(Result, tysDisabled);
  end;
end;

procedure TTyCustomAdvancedListBox.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  TyDrawAdvancedRow(P, ARowRect, Items[AIndex], ImageIndexOf(AIndex), FImages, AStyle,
    ResolveFontSize(AStyle), RtlRowLayout,   // #153
    not GetItemEnabled(AIndex));
end;

end.
