unit tyControls.TabControl;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Controller, tyControls.Painter, tyControls.Base,
  tyControls.Panel;

type
  TTyTabCloseEvent = procedure(Sender: TObject; AIndex: Integer;
    var AllowClose: Boolean) of object;

  TTyTabControl = class;

  { Streamable backing item for one tab page. Caption is published so it
    survives LFM streaming; the hosting TTyPanel is exposed read-only as Page. }
  TTyTabItem = class(TCollectionItem)
  private
    FCaption: string;
    FPage: TTyPanel;
    procedure SetCaption(const AValue: string);
  protected
    function GetDisplayName: string; override;
  public
    property Page: TTyPanel read FPage;
  published
    property Caption: string read FCaption write SetCaption;
  end;

  { Owned collection of TTyTabItem. Routes add/delete/update notifications to
    the owning TTyTabControl so the parallel page/caption arrays stay in sync. }
  TTyTabCollection = class(TOwnedCollection)
  private
    FTabControl: TTyTabControl;
    function GetItem(AIndex: Integer): TTyTabItem;
    procedure SetItem(AIndex: Integer; const AValue: TTyTabItem);
  protected
    procedure Notify(Item: TCollectionItem; Action: TCollectionNotification); override;
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(ATabControl: TTyTabControl);
    function Add: TTyTabItem;
    property Items[AIndex: Integer]: TTyTabItem read GetItem write SetItem; default;
  end;

  TTyTabControl = class(TTyCustomControl)
  private
    FCaptions: TStringList;   // parallel arrays
    FPages:    array of TTyPanel;
    FTabs:     TTyTabCollection;
    FUpdatingTabs: Boolean;   // guards re-entrant collection<->array sync
    FTabIndex: Integer;       // -1 = none
    FTabHeight: Integer;      // logical px, default 28
    FHoverTab: Integer;       // -1 = none
    FOnChange: TNotifyEvent;
    FDestroying: Boolean;
    FTabsClosable: Boolean;
    FOnTabClose: TTyTabCloseEvent;
    FHeaderRects: array of TRect;
    FCloseRects:  array of TRect;

    procedure SetTabs(AValue: TTyTabCollection);
    procedure TabItemAdded(AItem: TTyTabItem);
    procedure TabItemDeleting(AItem: TTyTabItem);
    procedure TabsChanged(AItem: TTyTabItem);
    function  IndexOfPage(APage: TTyPanel): Integer;
    procedure RemovePageInternal(AIndex: Integer; AFree: Boolean);
    procedure SetTabIndex(AValue: Integer);
    procedure SetTabHeight(AValue: Integer);
    procedure SetTabsClosable(AValue: Boolean);
    procedure RebuildLayout(APPI: Integer);
    procedure DoCloseTab(AIndex: Integer);
    function  TabHPx(APPI: Integer): Integer;
    function  GetPage(AIndex: Integer): TTyPanel;
    function  TabCaptionWidth(const ACaption: string;
                              const AStyle: TTyStyleSet; APPI: Integer): Integer;
    procedure ShowOnlyPage(AIndex: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure SetController(AValue: TTyStyleController); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
                        X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function AddTab(const ACaption: string): TTyPanel;
    procedure RemoveTab(AIndex: Integer);
    function TabCount: Integer;
    function TabCaption(AIndex: Integer): string;
    { Public pure-ish geometry for tests: device px, (0,0)-local }
    function TyTabHeaderRect(AIndex: Integer): TRect;
    function TyTabCloseRect(AIndex: Integer): TRect;

    property TabIndex: Integer read FTabIndex write SetTabIndex;
    property Pages[AIndex: Integer]: TTyPanel read GetPage;
  published
    property Tabs: TTyTabCollection read FTabs write SetTabs;
    property TabHeight: Integer read FTabHeight write SetTabHeight default 28;
    property TabsClosable: Boolean read FTabsClosable write SetTabsClosable default False;
    property OnTabClose: TTyTabCloseEvent read FOnTabClose write FOnTabClose;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ TTyTabItem }

procedure TTyTabItem.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Changed(False);
end;

function TTyTabItem.GetDisplayName: string;
begin
  if FCaption <> '' then
    Result := FCaption
  else
    Result := inherited GetDisplayName;
end;

{ TTyTabCollection }

constructor TTyTabCollection.Create(ATabControl: TTyTabControl);
begin
  inherited Create(ATabControl, TTyTabItem);
  FTabControl := ATabControl;
end;

function TTyTabCollection.GetItem(AIndex: Integer): TTyTabItem;
begin
  Result := TTyTabItem(inherited Items[AIndex]);
end;

procedure TTyTabCollection.SetItem(AIndex: Integer; const AValue: TTyTabItem);
begin
  inherited Items[AIndex] := AValue;
end;

function TTyTabCollection.Add: TTyTabItem;
begin
  Result := TTyTabItem(inherited Add);
end;

procedure TTyTabCollection.Notify(Item: TCollectionItem;
  Action: TCollectionNotification);
begin
  inherited Notify(Item, Action);
  if FTabControl = nil then Exit;
  case Action of
    cnAdded:
      FTabControl.TabItemAdded(TTyTabItem(Item));
    cnDeleting, cnExtracting:
      FTabControl.TabItemDeleting(TTyTabItem(Item));
  end;
end;

procedure TTyTabCollection.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if FTabControl <> nil then
    FTabControl.TabsChanged(TTyTabItem(Item));
end;

{ TTyTabControl }

constructor TTyTabControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaptions := TStringList.Create;
  FTabs     := TTyTabCollection.Create(Self);
  FTabIndex  := -1;
  FTabHeight := 28;
  FHoverTab  := -1;
  FTabsClosable := False;
  TabStop    := True;
  Width      := 300;
  Height     := 200;
end;

destructor TTyTabControl.Destroy;
begin
  FDestroying := True;
  { FDestroying is set so the collection's Notify is inert while it tears down. }
  FTabs.Free;
  FCaptions.Free;
  { Pages are owned components (Owner=Self) so freed by TComponent.Destroy }
  inherited Destroy;
end;

function TTyTabControl.GetStyleTypeKey: string;
begin
  Result := 'TyTabControl';
end;

{ When the TabControl's Controller changes, propagate it to all existing pages
  so they render with the same style controller rather than the default one. }
procedure TTyTabControl.SetController(AValue: TTyStyleController);
var
  I: Integer;
begin
  inherited SetController(AValue);
  for I := 0 to High(FPages) do
    if FPages[I] <> nil then
      FPages[I].Controller := AValue;
end;

{ Shared tab-header-band height: TabHeight logical px → device px at APPI. }
function TTyTabControl.TabHPx(APPI: Integer): Integer;
begin
  Result := MulDiv(FTabHeight, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyTabControl.GetPage(AIndex: Integer): TTyPanel;
begin
  if (AIndex < 0) or (AIndex >= Length(FPages)) then
    Result := nil
  else
    Result := FPages[AIndex];
end;

function TTyTabControl.TabCount: Integer;
begin
  Result := FCaptions.Count;
end;

function TTyTabControl.TabCaption(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= FCaptions.Count) then
    Result := ''
  else
    Result := FCaptions[AIndex];
end;

{ Measure the rendered caption width using a scratch TBitmap canvas so CJK and
  variable-width fonts are handled correctly (same pattern as TTyGroupBox). }
function TTyTabControl.TabCaptionWidth(const ACaption: string;
  const AStyle: TTyStyleSet; APPI: Integer): Integer;
var
  MeasBmp: TBitmap;
begin
  MeasBmp := TBitmap.Create;
  try
    MeasBmp.SetSize(1, 1);
    MeasBmp.Canvas.Font.Name := AStyle.FontName;
    MeasBmp.Canvas.Font.Size := MulDiv(AStyle.FontSize, APPI, 96);
    Result := MeasBmp.Canvas.TextWidth(ACaption);
  finally
    MeasBmp.Free;
  end;
  if Result < 1 then Result := 1;
end;

procedure TTyTabControl.SetTabsClosable(AValue: Boolean);
begin
  if FTabsClosable = AValue then Exit;
  FTabsClosable := AValue;
  Invalidate;
end;

{ Single-pass cached layout. Builds FHeaderRects/FCloseRects for all tabs.
  Geometry: device px, (0,0)-local. Headers laid left-to-right;
  width = text width + 2×Scale(12), minimum Scale(48). When closable, a
  close-glyph slot is reserved on the right of each header. }
procedure TTyTabControl.RebuildLayout(APPI: Integer);
var
  TabH, Pad, MinW, CloseSize, Gap, CloseSlot, Margin: Integer;
  TabStyle: TTyStyleSet;
  I, X, TW, HW, Cy: Integer;
begin
  SetLength(FHeaderRects, FCaptions.Count);
  SetLength(FCloseRects, FCaptions.Count);

  TabH      := TabHPx(APPI);
  Pad       := MulDiv(12, APPI, 96);
  MinW      := MulDiv(48, APPI, 96);
  CloseSize := MulDiv(14, APPI, 96);
  Gap       := MulDiv(6,  APPI, 96);
  Margin    := MulDiv(6,  APPI, 96);
  CloseSlot := CloseSize + Gap;

  TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', [tysNormal]);

  X := 0;
  for I := 0 to FCaptions.Count - 1 do
  begin
    TW := TabCaptionWidth(FCaptions[I], TabStyle, APPI) + 2 * Pad;
    if FTabsClosable then
    begin
      Inc(TW, CloseSlot);
      if TW < (MinW + CloseSlot) then TW := MinW + CloseSlot;
    end
    else
      if TW < MinW then TW := MinW;

    HW := TW;
    FHeaderRects[I] := Rect(X, 0, X + HW, TabH);

    if FTabsClosable then
    begin
      Cy := (TabH - CloseSize) div 2;
      FCloseRects[I] := Rect(X + HW - Margin - CloseSize, Cy,
                             X + HW - Margin, Cy + CloseSize);
    end
    else
      FCloseRects[I] := Rect(0, 0, 0, 0);

    Inc(X, HW);
  end;
end;

function TTyTabControl.TyTabHeaderRect(AIndex: Integer): TRect;
begin
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FHeaderRects)) then
    Result := Rect(0, 0, 0, 0)
  else
    Result := FHeaderRects[AIndex];
end;

function TTyTabControl.TyTabCloseRect(AIndex: Integer): TRect;
begin
  if not FTabsClosable then
    Exit(Rect(0, 0, 0, 0));
  RebuildLayout(Font.PixelsPerInch);
  if (AIndex < 0) or (AIndex >= Length(FCloseRects)) then
    Result := Rect(0, 0, 0, 0)
  else
    Result := FCloseRects[AIndex];
end;

procedure TTyTabControl.DoCloseTab(AIndex: Integer);
var
  AllowClose: Boolean;
begin
  if (AIndex < 0) or (AIndex >= FCaptions.Count) then Exit;
  AllowClose := True;
  if Assigned(FOnTabClose) then
    FOnTabClose(Self, AIndex, AllowClose);
  if AllowClose then
    RemoveTab(AIndex);
end;

procedure TTyTabControl.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Top, TabHPx(Font.PixelsPerInch));
end;

{ Show only the page at AIndex (or none when AIndex=-1). }
procedure TTyTabControl.ShowOnlyPage(AIndex: Integer);
var
  I: Integer;
begin
  for I := 0 to Length(FPages) - 1 do
    FPages[I].Visible := (I = AIndex);
end;

procedure TTyTabControl.SetTabIndex(AValue: Integer);
var
  Clamped: Integer;
begin
  if AValue < -1 then
    Clamped := -1
  else if AValue >= FCaptions.Count then
    Clamped := FCaptions.Count - 1
  else
    Clamped := AValue;
  if Clamped = FTabIndex then Exit;
  FTabIndex := Clamped;
  ShowOnlyPage(FTabIndex);
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTabControl.SetTabHeight(AValue: Integer);
begin
  if FTabHeight = AValue then Exit;
  FTabHeight := AValue;
  if FTabHeight < 1 then FTabHeight := 1;
  Invalidate;
end;

{ Public convenience: add a tab through the collection (so the page/caption
  arrays stay in sync) and return its hosting page. The collection's Add fires
  TabItemAdded which creates the page; setting Caption then syncs FCaptions. }
function TTyTabControl.AddTab(const ACaption: string): TTyPanel;
var
  Item: TTyTabItem;
begin
  FUpdatingTabs := True;
  try
    Item := FTabs.Add;          // -> TabItemAdded creates page + caption slot
    Item.Caption := ACaption;   // -> TabsChanged re-syncs FCaptions
  finally
    FUpdatingTabs := False;
  end;
  Result := Item.Page;
end;

procedure TTyTabControl.SetTabs(AValue: TTyTabCollection);
begin
  FTabs.Assign(AValue);
end;

{ Create the hosting page for a freshly-added collection item and wire it into
  the parallel arrays. During csLoading the page is created but selection is
  deferred to Loaded/streaming so we don't fight the streamer. }
procedure TTyTabControl.TabItemAdded(AItem: TTyTabItem);
var
  Page: TTyPanel;
  IsFirst: Boolean;
begin
  if AItem.FPage <> nil then Exit; // already wired (defensive)

  IsFirst := (FCaptions.Count = 0);
  FCaptions.Add(AItem.Caption);

  Page := TTyPanel.Create(Self);
  Page.Parent := Self;
  Page.Align  := alClient;
  Page.Visible := False;
  { Propagate controller so the page renders with the same style as the tab. }
  Page.Controller := Self.Controller;
  AItem.FPage := Page;

  SetLength(FPages, Length(FPages) + 1);
  FPages[High(FPages)] := Page;

  if IsFirst then
  begin
    { Auto-select: bypass setter's clamping by setting FTabIndex directly,
      then manually show the first page and fire nothing (first add, no real
      "change" from a previous selection). }
    FTabIndex := 0;
    Page.Visible := True;
    Invalidate;
  end;
end;

{ A collection item is being deleted/extracted: remove its page (find it via
  the page object so we are robust to reordering). FUpdatingTabs marks that the
  removal originates from the collection so RemovePageInternal does not try to
  delete the item again. }
procedure TTyTabControl.TabItemDeleting(AItem: TTyTabItem);
var
  Idx: Integer;
  SavedUpdating: Boolean;
begin
  if FDestroying then Exit;
  if AItem.FPage = nil then Exit;
  Idx := IndexOfPage(AItem.FPage);
  if Idx < 0 then Exit;
  AItem.FPage := nil;
  SavedUpdating := FUpdatingTabs;
  FUpdatingTabs := True;
  try
    RemovePageInternal(Idx, True);
  finally
    FUpdatingTabs := SavedUpdating;
  end;
end;

{ An item changed (e.g. Caption edited): re-sync the parallel caption array to
  the current item captions and repaint. }
procedure TTyTabControl.TabsChanged(AItem: TTyTabItem);
var
  I: Integer;
begin
  if FDestroying then Exit;
  if csLoading in ComponentState then Exit;
  { Captions array length tracks the page array; only sync overlapping slots. }
  for I := 0 to FTabs.Count - 1 do
    if I < FCaptions.Count then
      FCaptions[I] := FTabs.Items[I].Caption;
  Invalidate;
end;

function TTyTabControl.IndexOfPage(APage: TTyPanel): Integer;
var I: Integer;
begin
  Result := -1;
  for I := 0 to High(FPages) do
    if FPages[I] = APage then
      Exit(I);
end;

procedure TTyTabControl.RemovePageInternal(AIndex: Integer; AFree: Boolean);
var
  OldActive, NewActive, Page: TTyPanel;
  J, ItemIdx: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FPages)) then Exit;

  if (FTabIndex >= 0) and (FTabIndex < Length(FPages)) then
    OldActive := FPages[FTabIndex]
  else
    OldActive := nil;

  Page := FPages[AIndex];

  { Keep the backing collection in sync when the removal originated outside it
    (RemoveTab/close-glyph/external page free). FUpdatingTabs is set when the
    removal already came from the collection, so we skip to avoid recursion. }
  if (not FUpdatingTabs) and (FTabs <> nil) and (not FDestroying) then
  begin
    ItemIdx := -1;
    for J := 0 to FTabs.Count - 1 do
      if FTabs.Items[J].FPage = Page then
      begin
        ItemIdx := J;
        Break;
      end;
    if ItemIdx >= 0 then
    begin
      FUpdatingTabs := True;
      try
        FTabs.Items[ItemIdx].FPage := nil; // make TabItemDeleting a no-op
        FTabs.Delete(ItemIdx);
      finally
        FUpdatingTabs := False;
      end;
    end;
  end;

  FCaptions.Delete(AIndex);
  for J := AIndex to High(FPages) - 1 do
    FPages[J] := FPages[J + 1];
  SetLength(FPages, Length(FPages) - 1);

  if Length(FPages) = 0 then
    FTabIndex := -1
  else if AIndex < FTabIndex then
    Dec(FTabIndex)
  else if AIndex = FTabIndex then
  begin
    if FTabIndex > High(FPages) then
      FTabIndex := High(FPages);
  end;

  if AFree and (Page <> nil) then
    Page.Free;

  ShowOnlyPage(FTabIndex);
  Invalidate;

  if (FTabIndex >= 0) and (FTabIndex < Length(FPages)) then
    NewActive := FPages[FTabIndex]
  else
    NewActive := nil;

  if (NewActive <> OldActive) and Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTabControl.RemoveTab(AIndex: Integer);
begin
  RemovePageInternal(AIndex, True);
end;

procedure TTyTabControl.Notification(AComponent: TComponent; Operation: TOperation);
var
  Idx: Integer;
begin
  inherited Notification(AComponent, Operation);
  if FDestroying then Exit;
  if (Operation = opRemove) and (AComponent is TTyPanel) then
  begin
    Idx := IndexOfPage(TTyPanel(AComponent));
    if Idx >= 0 then
      RemovePageInternal(Idx, False);
  end;
end;

procedure TTyTabControl.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle, TabStyle: TTyStyleSet;
  R: TRect;
  W, H, TabH, I: Integer;
  HdrRect, TextRect: TRect;
  TabStates: TTyStateSet;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    W := R.Right;
    H := R.Bottom;
    P.BeginPaint(ACanvas, ARect, APPI);

    BoxStyle := CurrentStyle;
    TabH := TabHPx(APPI);

    { Draw content area frame below header strip.
      Overlap by 1px so the active tab can visually merge with the content panel. }
    DrawFrame(P, Rect(0, TabH - MulDiv(1, APPI, 96), W, H), BoxStyle);

    { Draw each tab header }
    RebuildLayout(APPI);

    for I := 0 to FCaptions.Count - 1 do
    begin
      HdrRect := FHeaderRects[I];

      { Determine state }
      TabStates := [];
      if I = FTabIndex then
        Include(TabStates, tysActive)
      else if I = FHoverTab then
        Include(TabStates, tysHover)
      else
        Include(TabStates, tysNormal);

      TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', TabStates);

      { Fill header background }
      if tpBackground in TabStyle.Present then
        P.FillBackground(HdrRect, TabStyle.Background, 0);

      { Draw caption centered in header (clipped to left of close glyph) }
      TextRect := HdrRect;
      if FTabsClosable then
        TextRect.Right := FCloseRects[I].Left;
      P.DrawText(TextRect,
        FCaptions[I],
        TabStyle.FontName, TabStyle.FontSize, TabStyle.FontWeight,
        TabStyle.TextColor,
        taCenter, tlCenter, True);

      if FTabsClosable then
        P.DrawGlyph(FCloseRects[I], tgClose, TabStyle.TextColor, 1);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyTabControl.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ Mouse: hit-test headers on left-click }
procedure TTyTabControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  PPI, TabH, I: Integer;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    PPI  := Font.PixelsPerInch;
    TabH := TabHPx(PPI);
    if Y < TabH then
    begin
      RebuildLayout(PPI);
      for I := 0 to FCaptions.Count - 1 do
      begin
        if (X >= FHeaderRects[I].Left) and (X < FHeaderRects[I].Right) then
        begin
          if FTabsClosable and
             (X >= FCloseRects[I].Left) and (X < FCloseRects[I].Right) and
             (Y >= FCloseRects[I].Top) and (Y < FCloseRects[I].Bottom) then
            DoCloseTab(I)
          else
            TabIndex := I;
          Break;
        end;
      end;
    end;
    try
      if CanFocus then SetFocus;
    except
      { Ignore focus errors in headless/test environments }
    end;
  end;
end;

procedure TTyTabControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  PPI, TabH, NewHover, I: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  PPI  := Font.PixelsPerInch;
  TabH := TabHPx(PPI);
  NewHover := -1;
  if Y < TabH then
  begin
    RebuildLayout(PPI);
    for I := 0 to FCaptions.Count - 1 do
      if (X >= FHeaderRects[I].Left) and (X < FHeaderRects[I].Right) then
      begin
        NewHover := I;
        Break;
      end;
  end;
  if NewHover <> FHoverTab then
  begin
    FHoverTab := NewHover;
    Invalidate;
  end;
end;

procedure TTyTabControl.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverTab <> -1 then
  begin
    FHoverTab := -1;
    Invalidate;
  end;
end;

{ Keyboard: VK_LEFT/VK_RIGHT move TabIndex; clamp at ends; consume key }
procedure TTyTabControl.KeyDown(var Key: Word; Shift: TShiftState);
var
  NewIndex: Integer;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if FCaptions.Count = 0 then Exit;
  case Key of
    VK_RIGHT:
    begin
      NewIndex := FTabIndex + 1;
      if NewIndex >= FCaptions.Count then
        NewIndex := FCaptions.Count - 1;
      TabIndex := NewIndex;
      Key := 0;
    end;
    VK_LEFT:
    begin
      NewIndex := FTabIndex - 1;
      if NewIndex < 0 then NewIndex := 0;
      TabIndex := NewIndex;
      Key := 0;
    end;
  end;
end;

end.
