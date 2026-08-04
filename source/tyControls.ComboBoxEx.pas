unit tyControls.ComboBoxEx;
{$mode objfpc}{$H+}

{ TTyComboBoxEx — a combo whose items carry per-item image, indent and payload, drawn
  beside the text in BOTH the field and the drop-down. Subclasses TTyComboBox, injecting
  an image-drawing popup list (CreatePopupList) and an image field (PaintFieldContent).

  The per-row extras live in a design-time COLLECTION, ItemsEx (TTyComboExItems of
  TTyComboExItem) — the reason this control exists rather than being a combo with a
  parallel array. Each entry carries Caption, ImageIndex, OverlayImageIndex,
  SelectedImageIndex, Indent and an untyped Data, and the collection is editable in the
  Object Inspector.

  ItemsEx is the truth; the inherited Items (a TStringList) is a PROJECTION of it, with
  each row's Objects[i] holding that row's TTyComboExItem. That is what glues the extras
  to the caption through Sorted / Delete / a direct Items edit — no side array to desync —
  and it is why the popup list, which the base fills with a plain Items.Assign, reads the
  same entries the field does. Writing to Items directly still works: the collection is
  reconciled to match (see ReconcileFromItems), so a row can never be left without one.

  Images come from a TTyVirtualImageList (Images property): the index-addressed raster
  source whose CachedIndex(AIndex, ASizePx) borrows a bitmap scaled to the target pixel
  size from the collection's render cache — we blit it, we never free or modify it. }

interface
uses
  Classes, SysUtils, Types, Graphics, Controls,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ListBox, tyControls.ComboBox, tyControls.ImageCollection;

type
  TTyComboExItems = class;   { forward }

  { How TTyComboExItems.Sort orders rows. Same members as LCL's TSortType (comctrls.pp),
    declared here so this unit does not have to drag ComCtrls in for one enum. }
  TTyListItemsSortType = (stNone, stData, stText, stBoth);

  TTyComboExItem = class;
  TTyListCompareEvent = function(AList: TTyComboExItems;
    AItem1, AItem2: TTyComboExItem): Integer of object;

  { One row's extended data. Mirrors LCL's TListControlItem + TComboExItem
    (comboex.pas:57-90): Caption/ImageIndex from the first, Indent/OverlayImageIndex/
    SelectedImageIndex from the second, all defaulting to -1 as they do there. }
  TTyComboExItem = class(TCollectionItem)
  private
    FCaption: TCaption;
    FData: TObject;
    FImageIndex: Integer;
    FIndent: Integer;
    FOverlayImageIndex: Integer;
    FSelectedImageIndex: Integer;
    { Sweep mark used by ReconcileFromItems; never streamed. }
    FLive: Boolean;
    procedure SetCaption(const AValue: TCaption);
    procedure SetImageIndex(AValue: Integer);
    procedure SetIndent(AValue: Integer);
    procedure SetOverlayImageIndex(AValue: Integer);
    procedure SetSelectedImageIndex(AValue: Integer);
  public
    constructor Create(ACollection: TCollection); override;
    procedure Assign(ASource: TPersistent); override;
    property Live: Boolean read FLive write FLive;
    { The APPLICATION's object for this row. Not published (a TObject reference cannot be
      streamed); this is the slot Items.Objects[] used to be before the control took it. }
    property Data: TObject read FData write FData;
  published
    property Caption: TCaption read FCaption write SetCaption;
    property ImageIndex: Integer read FImageIndex write SetImageIndex default -1;
    { Left inset in logical px, for tree-like grouping. -1 = none. }
    property Indent: Integer read FIndent write SetIndent default -1;
    { Drawn on top of the row image (a badge / status corner). -1 = none. }
    property OverlayImageIndex: Integer read FOverlayImageIndex write SetOverlayImageIndex default -1;
    { Used INSTEAD of ImageIndex while the row is the selected one. -1 = no swap. }
    property SelectedImageIndex: Integer read FSelectedImageIndex write SetSelectedImageIndex default -1;
  end;

  { The published, design-time-editable collection. Add/AddItem/Insert are the typed
    constructors LCL has; CaseSensitive/SortType/OnCompare + Sort/CustomSort are the
    ordering half (TListControlItems, comboex.pas:93-116). }
  TTyComboExItems = class(TOwnedCollection)
  private
    FCaseSensitive: Boolean;
    FSortType: TTyListItemsSortType;
    FOnCompare: TTyListCompareEvent;
    function GetComboItem(AIndex: Integer): TTyComboExItem;
    procedure SetCaseSensitive(AValue: Boolean);
    procedure SetSortType(AValue: TTyListItemsSortType);
  protected
    function CompareItems(AItem1, AItem2: TTyComboExItem): Integer; virtual;
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TPersistent);
    function Add: TTyComboExItem;
    { One-call row construction, argument-for-argument LCL's TComboExItems.AddItem. }
    function AddItem(const ACaption: string; AImageIndex: Integer = -1;
      AOverlayImageIndex: Integer = -1; ASelectedImageIndex: Integer = -1;
      AIndent: Integer = -1; AData: TObject = nil): TTyComboExItem;
    function Insert(AIndex: Integer): TTyComboExItem;
    { Reorder by SortType (or by ACompare for CustomSort). Both re-index the collection,
      which republishes the projected Items list. }
    procedure Sort;
    procedure CustomSort(ACompare: TTyListCompareEvent);
    property ComboItems[AIndex: Integer]: TTyComboExItem read GetComboItem; default;
  published
    { Applies to the built-in text comparison (and so to SortType = stText/stBoth). }
    property CaseSensitive: Boolean read FCaseSensitive write SetCaseSensitive default False;
    property SortType: TTyListItemsSortType read FSortType write SetSortType default stNone;
    property OnCompare: TTyListCompareEvent read FOnCompare write FOnCompare;
  end;

  { Drop-down list for TTyComboBoxEx: draws image + name per row via the
    TTyListBox.PaintItemContent hook. Its Owner is the combo (CreatePopupList does
    Create(Self)), which supplies the shared draw method and the row entries — the combo
    copies its Items (Objects[] included) into this list, so there is no side array that
    could desync from the names. }
  TTyComboBoxExPopupList = class(TTyListBox)
  protected
    procedure PaintItemContent(P: TTyPainter; const ARowRect: TRect; AIndex: Integer;
      const AStyle: TTyStyleSet); override;
  end;

  { A combo of image + text items. Build rows through ItemsEx (design time or code), or
    with AddItem(text, imageIndex) / Add / Insert. The image source is Images. }
  TTyComboBoxEx = class(TTyComboBox)
  private
    FImages: TTyVirtualImageList;
    FItemsEx: TTyComboExItems;
    { Re-entrancy guard: the two lists write to each other, and every write fires the
      other's change hook. }
    FSyncing: Boolean;
    { ItemIndex streams from the ANCESTOR, i.e. before this class's ItemsEx block, so at
      that moment the list is still empty and the index clamps to -1. Remembered here and
      re-applied in Loaded. }
    FLoadedItemIndex: Integer;
    procedure SetImages(const AValue: TTyVirtualImageList);
    procedure SetItemsEx(const AValue: TTyComboExItems);
    { ItemsEx -> Items. }
    procedure SyncItemsFromEx;
    { Items -> ItemsEx: give every row an entry, drop entries no row references. }
    procedure ReconcileFromItems;
  protected
    function CreatePopupList: TTyListBox; override;
    procedure PaintFieldContent(P: TTyPainter; const ATextRect: TRect; const AStyle: TTyStyleSet); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure DoItemsChanged; override;
    procedure SelectItem(AIndex: Integer); override;
    procedure Loaded; override;
    { Called by ItemsEx whenever the collection changes. }
    procedure ItemsExChanged;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Append with an optional image (AImageIndex < 0 => text only). }
    procedure AddItem(const S: string; AImageIndex: Integer); overload;
    { The inherited form, redirected: on this control Items.Objects[] belongs to the row
      entry, so an application object handed in here goes to that entry's Data instead of
      being read back as a garbage image index. }
    procedure AddItem(const AItem: string; AnObject: TObject); override;
    { LCL's image-aware mutators (comboex.pas:164-176). }
    function  Add: Integer; overload;
    procedure Add(const ACaption: string; AIndent: Integer = -1; AImgIdx: Integer = -1;
      AOverlayImgIdx: Integer = -1; ASelectedImgIdx: Integer = -1); overload;
    procedure Insert(AIndex: Integer; const ACaption: string; AIndent: Integer = -1;
      AImgIdx: Integer = -1; AOverlayImgIdx: Integer = -1; ASelectedImgIdx: Integer = -1);
    procedure Delete(AIndex: Integer);
    procedure DeleteSelected;
    procedure AssignItemsEx(AItems: TStrings); overload;
    procedure AssignItemsEx(AItemsEx: TTyComboExItems); overload;
    { The row entry for AIndex, or nil when out of range. }
    function ItemEx(AIndex: Integer): TTyComboExItem;
    { The image index stored for item AIndex, or -1 when it has no image / is out of
      range. Kept from the pre-ItemsEx API — a lot of code reads rows this way. }
    function ImageIndexOf(AIndex: Integer): Integer;
    { Shared draw: image (left, from Images) + text (right) into ARect. Reused by the
      field and the popup rows so the layout lives in one place. AImageIndex < 0 (or no
      Images) draws text only. }
    procedure DrawImageText(P: TTyPainter; const ARect: TRect; const S: string;
      AImageIndex: Integer; const AStyle: TTyStyleSet);
    { The full row draw: honours Indent, swaps in SelectedImageIndex while selected, and
      stamps OverlayImageIndex on top. Falls back to DrawImageText when AItem is nil. }
    procedure DrawExItem(P: TTyPainter; const ARect: TRect; AItem: TTyComboExItem;
      ASelected: Boolean; const AStyle: TTyStyleSet);
  published
    { The raster image source (index-addressed). A FreeNotification nils this reference
      automatically if the list is freed first. }
    property Images: TTyVirtualImageList read FImages write SetImages;
    { Declared BEFORE any property that depends on the row set so it streams first. }
    property ItemsEx: TTyComboExItems read FItemsEx write SetItemsEx;
  end;

implementation

{ TTyComboExItem }

constructor TTyComboExItem.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FCaption := '';
  FData := nil;
  { LCL's defaults, and they must match the published `default -1` directives or a .lfm
    would omit exactly the values that differ from 0. }
  FImageIndex := -1;
  FIndent := -1;
  FOverlayImageIndex := -1;
  FSelectedImageIndex := -1;
end;

procedure TTyComboExItem.Assign(ASource: TPersistent);
var src: TTyComboExItem;
begin
  if ASource is TTyComboExItem then
  begin
    src := TTyComboExItem(ASource);
    FCaption := src.Caption;
    FImageIndex := src.ImageIndex;
    FIndent := src.Indent;
    FOverlayImageIndex := src.OverlayImageIndex;
    FSelectedImageIndex := src.SelectedImageIndex;
    FData := src.Data;
    Changed(False);
  end
  else
    inherited Assign(ASource);
end;

procedure TTyComboExItem.SetCaption(const AValue: TCaption);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Changed(False);
end;

procedure TTyComboExItem.SetImageIndex(AValue: Integer);
begin
  if FImageIndex = AValue then Exit;
  FImageIndex := AValue;
  Changed(False);
end;

procedure TTyComboExItem.SetIndent(AValue: Integer);
begin
  if FIndent = AValue then Exit;
  FIndent := AValue;
  Changed(False);
end;

procedure TTyComboExItem.SetOverlayImageIndex(AValue: Integer);
begin
  if FOverlayImageIndex = AValue then Exit;
  FOverlayImageIndex := AValue;
  Changed(False);
end;

procedure TTyComboExItem.SetSelectedImageIndex(AValue: Integer);
begin
  if FSelectedImageIndex = AValue then Exit;
  FSelectedImageIndex := AValue;
  Changed(False);
end;

{ TTyComboExItems }

constructor TTyComboExItems.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TTyComboExItem);
  FCaseSensitive := False;
  FSortType := stNone;
end;

function TTyComboExItems.GetComboItem(AIndex: Integer): TTyComboExItem;
begin
  Result := TTyComboExItem(inherited Items[AIndex]);
end;

function TTyComboExItems.Add: TTyComboExItem;
begin
  Result := TTyComboExItem(inherited Add);
end;

function TTyComboExItems.AddItem(const ACaption: string; AImageIndex: Integer;
  AOverlayImageIndex: Integer; ASelectedImageIndex: Integer; AIndent: Integer;
  AData: TObject): TTyComboExItem;
begin
  { One BeginUpdate/EndUpdate around the whole row, so the projected string list is
    rebuilt once rather than once per property. }
  BeginUpdate;
  try
    Result := Add;
    Result.ImageIndex := AImageIndex;
    Result.OverlayImageIndex := AOverlayImageIndex;
    Result.SelectedImageIndex := ASelectedImageIndex;
    Result.Indent := AIndent;
    Result.Data := AData;
    Result.Caption := ACaption;
  finally
    EndUpdate;
  end;
end;

function TTyComboExItems.Insert(AIndex: Integer): TTyComboExItem;
begin
  Result := TTyComboExItem(inherited Insert(AIndex));
end;

procedure TTyComboExItems.SetCaseSensitive(AValue: Boolean);
begin
  if FCaseSensitive = AValue then Exit;
  FCaseSensitive := AValue;
  if FSortType in [stText, stBoth] then Sort;
end;

procedure TTyComboExItems.SetSortType(AValue: TTyListItemsSortType);
begin
  if FSortType = AValue then Exit;
  FSortType := AValue;
  { Setting a sort order applies it at once — otherwise an Object Inspector change would
    do nothing visible until the next edit. }
  if FSortType <> stNone then Sort;
end;

function TTyComboExItems.CompareItems(AItem1, AItem2: TTyComboExItem): Integer;
begin
  { stData / stBoth ask the handler, because only the application knows what its Data
    means; with no handler they fall back to the text so a sort is never a silent no-op. }
  Result := 0;
  case FSortType of
    stNone: Exit;
    stData, stBoth:
      if Assigned(FOnCompare) then
      begin
        Result := FOnCompare(Self, AItem1, AItem2);
        if (Result <> 0) or (FSortType = stData) then Exit;
      end;
  end;
  if FCaseSensitive then
    Result := CompareStr(AItem1.Caption, AItem2.Caption)
  else
    Result := AnsiCompareText(AItem1.Caption, AItem2.Caption);
end;

procedure TTyComboExItems.Sort;
var
  i, j: Integer;
  order: TFPList;
  a, b: TTyComboExItem;
begin
  if Count < 2 then Exit;
  { Insertion sort over the collection's own Index property: TCollection has no Sort, and
    re-indexing in place is what keeps every item's identity (and so every row's pairing
    with its caption) intact. Row counts here are Object-Inspector sized. }
  order := TFPList.Create;
  BeginUpdate;
  try
    for i := 0 to Count - 1 do order.Add(GetComboItem(i));
    for i := 1 to order.Count - 1 do
    begin
      a := TTyComboExItem(order[i]);
      j := i - 1;
      while j >= 0 do
      begin
        b := TTyComboExItem(order[j]);
        if CompareItems(b, a) <= 0 then Break;
        order[j + 1] := b;
        Dec(j);
      end;
      order[j + 1] := a;
    end;
    for i := 0 to order.Count - 1 do
      TTyComboExItem(order[i]).Index := i;
  finally
    EndUpdate;
    order.Free;
  end;
end;

procedure TTyComboExItems.CustomSort(ACompare: TTyListCompareEvent);
var saveType: TTyListItemsSortType; saveCompare: TTyListCompareEvent;
begin
  if not Assigned(ACompare) then Exit;
  saveType := FSortType;
  saveCompare := FOnCompare;
  try
    FOnCompare := ACompare;
    FSortType := stData;    // "the handler decides, nothing else"
    Sort;
  finally
    FSortType := saveType;
    FOnCompare := saveCompare;
  end;
end;

procedure TTyComboExItems.Update(Item: TCollectionItem);
begin
  { The ONE hook. Every structural path (Add / Insert / Delete / Clear / an Index move in
    Sort) ends in TCollection.Changed, and so in Update — hooking Notify as well would
    only add a rebuild per item in the middle of a BeginUpdate batch, which is precisely
    what BeginUpdate exists to avoid. }
  inherited Update(Item);
  if Owner is TTyComboBoxEx then TTyComboBoxEx(Owner).ItemsExChanged;
end;

{ TTyComboBoxExPopupList }

procedure TTyComboBoxExPopupList.PaintItemContent(P: TTyPainter; const ARowRect: TRect;
  AIndex: Integer; const AStyle: TTyStyleSet);
begin
  { The Owner is the combo (Create(Self) in CreatePopupList); it owns the shared draw
    method and the Images reference. The row entry rides in Objects[] (copied from the
    combo via Items.Assign), so field and popup read the same object. }
  if Owner is TTyComboBoxEx then
    TTyComboBoxEx(Owner).DrawExItem(P, ARowRect,
      TTyComboBoxEx(Owner).ItemEx(AIndex), AIndex = ItemIndex, AStyle)
  else
    inherited PaintItemContent(P, ARowRect, AIndex, AStyle);
end;

{ TTyComboBoxEx }

constructor TTyComboBoxEx.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItemsEx := TTyComboExItems.Create(Self);
  FLoadedItemIndex := -1;
  { ItemsEx is this control's persisted row set; Items is only its projection. Writing
    both into a .lfm would be two sources of truth for one list. }
  FItemsStreamed := False;
end;

destructor TTyComboBoxEx.Destroy;
begin
  { Free the collection before the inherited destructor drops Items: nothing must read a
    half-torn-down pair, and the projection hook must stop firing first. }
  FSyncing := True;
  FreeAndNil(FItemsEx);
  inherited Destroy;
end;

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

procedure TTyComboBoxEx.SetItemsEx(const AValue: TTyComboExItems);
begin
  { Assign, never replace: the collection instance is ours and the Object Inspector holds
    a reference to it. }
  FItemsEx.Assign(AValue);
end;

procedure TTyComboBoxEx.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
end;

procedure TTyComboBoxEx.ItemsExChanged;
begin
  SyncItemsFromEx;
end;

procedure TTyComboBoxEx.SyncItemsFromEx;
var
  i: Integer;
  InOrder: Boolean;
begin
  if FSyncing or (FItemsEx = nil) or (csDestroying in ComponentState) then Exit;
  FSyncing := True;
  try
    { Fast path: same rows, same order — only captions can have moved, so edit in place
      and leave the selection alone. Not available on a Sorted list, where TStringList
      refuses an indexed write. }
    InOrder := (not Items.Sorted) and (Items.Count = FItemsEx.Count);
    if InOrder then
      for i := 0 to Items.Count - 1 do
        if Items.Objects[i] <> FItemsEx[i] then
        begin
          InOrder := False;
          Break;
        end;
    if InOrder then
    begin
      for i := 0 to Items.Count - 1 do
        if Items[i] <> FItemsEx[i].Caption then Items[i] := FItemsEx[i].Caption;
      Exit;
    end;
    { Structural change: rebuild the projection. BeginUpdate collapses it into one
      OnChange, so the base re-pins the selection once and by text. }
    Items.BeginUpdate;
    try
      Items.Clear;
      for i := 0 to FItemsEx.Count - 1 do
        Items.AddObject(FItemsEx[i].Caption, FItemsEx[i]);
    finally
      Items.EndUpdate;
    end;
  finally
    FSyncing := False;
  end;
end;

procedure TTyComboBoxEx.ReconcileFromItems;
var
  i: Integer;
  it: TTyComboExItem;
  raw: TObject;
begin
  if FSyncing or (FItemsEx = nil) or (csDestroying in ComponentState) then Exit;
  FSyncing := True;
  try
    for i := 0 to FItemsEx.Count - 1 do
      FItemsEx[i].Live := False;
    for i := 0 to Items.Count - 1 do
    begin
      raw := Items.Objects[i];
      it := nil;
      { The slot may hold one of our entries, nil (a plain Items.Add), or — after someone
        called Items.AddObject by hand — an arbitrary object. Only an entry we own and
        have not already claimed for another row counts. }
      if (raw is TTyComboExItem) and (TTyComboExItem(raw).Collection = FItemsEx)
         and not TTyComboExItem(raw).Live then
        it := TTyComboExItem(raw);
      if it = nil then
      begin
        it := FItemsEx.Add;
        it.Data := raw;                  // adopt whatever was there as the row payload
        Items.Objects[i] := it;
      end;
      it.Live := True;
      if it.Caption <> Items[i] then it.Caption := Items[i];
    end;
    for i := FItemsEx.Count - 1 downto 0 do
      if not FItemsEx[i].Live then FItemsEx.Delete(i);
  finally
    FSyncing := False;
  end;
end;

procedure TTyComboBoxEx.DoItemsChanged;
begin
  inherited DoItemsChanged;
  ReconcileFromItems;
end;

procedure TTyComboBoxEx.SelectItem(AIndex: Integer);
begin
  { During streaming the ancestor's ItemIndex arrives before this class's ItemsEx block,
    so the list is still empty and AIndex would clamp to -1 and be lost. Remember it. }
  if csLoading in ComponentState then FLoadedItemIndex := AIndex;
  inherited SelectItem(AIndex);
end;

procedure TTyComboBoxEx.Loaded;
begin
  inherited Loaded;
  if (FLoadedItemIndex >= 0) and (FLoadedItemIndex < Items.Count) and (ItemIndex < 0) then
    ItemIndex := FLoadedItemIndex;
end;

procedure TTyComboBoxEx.AddItem(const S: string; AImageIndex: Integer);
begin
  FItemsEx.AddItem(S, AImageIndex);
end;

procedure TTyComboBoxEx.AddItem(const AItem: string; AnObject: TObject);
begin
  FItemsEx.AddItem(AItem, -1, -1, -1, -1, AnObject);
end;

function TTyComboBoxEx.Add: Integer;
begin
  Result := FItemsEx.Add.Index;
end;

procedure TTyComboBoxEx.Add(const ACaption: string; AIndent: Integer; AImgIdx: Integer;
  AOverlayImgIdx: Integer; ASelectedImgIdx: Integer);
begin
  FItemsEx.AddItem(ACaption, AImgIdx, AOverlayImgIdx, ASelectedImgIdx, AIndent);
end;

procedure TTyComboBoxEx.Insert(AIndex: Integer; const ACaption: string; AIndent: Integer;
  AImgIdx: Integer; AOverlayImgIdx: Integer; ASelectedImgIdx: Integer);
var it: TTyComboExItem;
begin
  if AIndex < 0 then AIndex := 0;
  if AIndex > FItemsEx.Count then AIndex := FItemsEx.Count;
  FItemsEx.BeginUpdate;
  try
    it := FItemsEx.Insert(AIndex);
    it.ImageIndex := AImgIdx;
    it.OverlayImageIndex := AOverlayImgIdx;
    it.SelectedImageIndex := ASelectedImgIdx;
    it.Indent := AIndent;
    it.Caption := ACaption;
  finally
    FItemsEx.EndUpdate;
  end;
end;

procedure TTyComboBoxEx.Delete(AIndex: Integer);
begin
  if (AIndex >= 0) and (AIndex < FItemsEx.Count) then FItemsEx.Delete(AIndex);
end;

procedure TTyComboBoxEx.DeleteSelected;
var it: TTyComboExItem;
begin
  { Delete the SELECTED ROW, which under Sorted is not the collection entry at the same
    ordinal — go through the row's entry, not through ItemIndex twice. }
  it := ItemEx(ItemIndex);
  if it <> nil then FItemsEx.Delete(it.Index);
end;

procedure TTyComboBoxEx.AssignItemsEx(AItems: TStrings);
var i: Integer;
begin
  if AItems = nil then Exit;
  FItemsEx.BeginUpdate;
  try
    FItemsEx.Clear;
    for i := 0 to AItems.Count - 1 do
      FItemsEx.AddItem(AItems[i], -1, -1, -1, -1, AItems.Objects[i]);
  finally
    FItemsEx.EndUpdate;
  end;
end;

procedure TTyComboBoxEx.AssignItemsEx(AItemsEx: TTyComboExItems);
begin
  if AItemsEx = nil then Exit;
  FItemsEx.Assign(AItemsEx);
end;

function TTyComboBoxEx.ItemEx(AIndex: Integer): TTyComboExItem;
var raw: TObject;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex >= Items.Count) then Exit;
  raw := Items.Objects[AIndex];
  if raw is TTyComboExItem then Result := TTyComboExItem(raw);
end;

function TTyComboBoxEx.ImageIndexOf(AIndex: Integer): Integer;
var it: TTyComboExItem;
begin
  it := ItemEx(AIndex);
  if it <> nil then Result := it.ImageIndex else Result := -1;
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
    bmp := FImages.CachedIndex(AImageIndex, sz);   // borrowed; do NOT free
    if bmp <> nil then
      P.Bitmap.PutImage(x, ARect.Top + ((ARect.Bottom - ARect.Top - bmp.Height) div 2),
        bmp, dmDrawWithTransparency);
    x := x + sz + P.Scale(4);
  end;
  textR := Rect(x, ARect.Top, ARect.Right - P.Scale(4), ARect.Bottom);
  P.DrawText(textR, S, AStyle.FontName, ResolveFontSize(AStyle), AStyle.FontWeight,
    AStyle.TextColor, taLeftJustify, tlCenter, True);
end;

procedure TTyComboBoxEx.DrawExItem(P: TTyPainter; const ARect: TRect;
  AItem: TTyComboExItem; ASelected: Boolean; const AStyle: TTyStyleSet);
var
  imgIdx, sz, x, y: Integer;
  R: TRect;
  bmp: TBGRABitmap;
begin
  if AItem = nil then Exit;
  R := ARect;
  { Indent is a left inset in LOGICAL px, so it has to be scaled like every other
    geometry value or it would shrink on a HiDPI screen. }
  if AItem.Indent > 0 then Inc(R.Left, P.Scale(AItem.Indent));

  { A selected row swaps in SelectedImageIndex when it has one — that is the whole point
    of the field having a different icon once picked. }
  imgIdx := AItem.ImageIndex;
  if ASelected and (AItem.SelectedImageIndex >= 0) then imgIdx := AItem.SelectedImageIndex;

  DrawImageText(P, R, AItem.Caption, imgIdx, AStyle);

  { The overlay stamps ON the row image, so it only means anything when one was drawn. }
  if (FImages = nil) or (imgIdx < 0) or (imgIdx >= FImages.Count) then Exit;
  if (AItem.OverlayImageIndex < 0) or (AItem.OverlayImageIndex >= FImages.Count) then Exit;
  sz := (R.Bottom - R.Top) - P.Scale(6);
  if sz < 8 then sz := 8;
  bmp := FImages.CachedIndex(AItem.OverlayImageIndex, sz);   // borrowed; do NOT free
  if bmp = nil then Exit;
  x := R.Left + P.Scale(4);
  y := R.Top + ((R.Bottom - R.Top - bmp.Height) div 2);
  P.Bitmap.PutImage(x, y, bmp, dmDrawWithTransparency);
end;

procedure TTyComboBoxEx.PaintFieldContent(P: TTyPainter; const ATextRect: TRect;
  const AStyle: TTyStyleSet);
var it: TTyComboExItem;
begin
  it := ItemEx(ItemIndex);
  if it <> nil then
    { The field always shows the row as SELECTED — it is, by definition, the picked one. }
    DrawExItem(P, ATextRect, it, True, AStyle)
  else
    inherited PaintFieldContent(P, ATextRect, AStyle);   // empty field -> the TextHint
end;

function TTyComboBoxEx.CreatePopupList: TTyListBox;
begin
  Result := TTyComboBoxExPopupList.Create(Self);
end;

end.
