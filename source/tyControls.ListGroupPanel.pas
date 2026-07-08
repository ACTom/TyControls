unit tyControls.ListGroupPanel;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.ExPanel;

const
  // Logical (96ppi) defaults. Header band matches the ExPanel caption band; item rows
  // match the ListBox row height so the two families read as one visual system.
  TyListGroupDefaultHeaderHeight = 26;
  TyListGroupDefaultItemHeight   = 24;

type
  { The kind of thing a layout entry describes: a group header band, or one item row. }
  TTyListGroupPartKind = (lgpHeader, lgpItem);

  { One laid-out rectangle in CONTENT space (y measured from 0 at the top of the first
    header, growing downward; a scroll offset is applied by the control at paint/hit time).
    For a header, GroupIndex is the group and ItemIndex is -1; for an item, both are set. }
  TTyListGroupPart = record
    Kind: TTyListGroupPartKind;
    GroupIndex: Integer;
    ItemIndex: Integer;   // -1 for a header
    Rect: TRect;
  end;
  TTyListGroupParts = array of TTyListGroupPart;

  { A group's shape as the pure layout needs it: whether it is expanded and how many
    items it holds. The caller (the control / a test) fills one per group. }
  TTyListGroupShape = record
    Expanded: Boolean;
    ItemCount: Integer;
  end;
  TTyListGroupShapes = array of TTyListGroupShape;

  { The result of a hit test: what kind of part (if any) was hit and its indices.
    Hit=False when the point missed every part (e.g. below the last row). }
  TTyListGroupHit = record
    Hit: Boolean;
    Kind: TTyListGroupPartKind;
    GroupIndex: Integer;
    ItemIndex: Integer;   // -1 for a header hit
  end;

{ ---- PURE, headless-tested layout/hit-test (all in DEVICE pixels) ---- }

{ Build the ordered list of parts for AGroups stacked top-to-bottom in a AClientW-wide
  column: each group contributes ONE header (AHeaderH tall), then — only if that group is
  Expanded — AItemHeight-tall item rows, one per item. All rects are full-width [0..AClientW].
  Content y starts at 0 (no scroll applied here). An empty expanded group contributes only
  its header (no item rects). Returns the parts in visual (top-to-bottom) order. }
function TyListGroupLayout(const AGroups: TTyListGroupShapes;
  AHeaderH, AItemHeight, AClientW: Integer): TTyListGroupParts;

{ Total content height of a layout = bottom of the last part (0 for no groups). }
function TyListGroupContentHeight(const AParts: TTyListGroupParts): Integer;

{ Hit-test APt (already in CONTENT space — the caller adds the scroll offset back) against
  the parts. Returns the FIRST part whose rect contains APt. An item hit wins naturally
  because item rects never overlap their header. Miss -> Hit=False. }
function TyListGroupHitTest(const AParts: TTyListGroupParts; const APt: TPoint): TTyListGroupHit;

type
  { Internal per-item model. }
  TTyListGroupItem = record
    Caption: string;
    ImageIndex: Integer;
  end;

  { Internal per-group model: a caption, an expanded flag, and its items. }
  TTyListGroupData = record
    Caption: string;
    Expanded: Boolean;
    Items: array of TTyListGroupItem;
  end;

  TTyListGroupToggleEvent = procedure(Sender: TObject; AGroupIndex: Integer) of object;
  TTyListGroupItemEvent = procedure(Sender: TObject; AGroupIndex, AItemIndex: Integer) of object;

  { TTyListGroupPanel — an Outlook-style grouped, expandable (accordion) list.

    A vertical stack of named GROUPS. Each group is a header band (caption + a chevron,
    reusing the ExPanel chevron geometry) that toggles the group open/closed. When open a
    group shows its ITEMS, one caption per row. Clicking a header toggles Expanded (and fires
    OnGroupToggle); clicking an item selects it (SelectedGroup/SelectedItem) and fires
    OnItemClick.

    SCROLLING: when the stacked content is taller than the control it is CLIPPED to the
    client and the mouse wheel pans it (FScrollOffset). This keeps the whole layout in the
    pure geometry functions (no embedded child scrollbar). Content shorter than the client
    pins the offset to 0.

    THEMING (reuses existing typeKeys — NO new .tycss):
      * the frame (background + border) is 'TyPanel' (GetStyleTypeKey);
      * each header band is painted with the 'TyTreeHeaderSection' style (it carries
        :hover / :selected states) with the 'TyTreeHeader' text colour;
      * each item row is painted with the 'TyListItem' style (:hover / :active).
    All colours are theme-driven. }

  TTyListGroupPanel = class(TTyCustomControl)
  private
    FGroups: array of TTyListGroupData;
    FHeaderHeight: Integer;
    FItemHeight: Integer;
    FSelGroup: Integer;     // -1 = none
    FSelItem: Integer;      // -1 = none
    FHoverKind: TTyListGroupPartKind;
    FHoverGroup: Integer;   // -1 = none
    FHoverItem: Integer;    // -1 = none
    FScrollOffset: Integer; // device px content is shifted UP by (>=0)
    FOnGroupToggle: TTyListGroupToggleEvent;
    FOnItemClick: TTyListGroupItemEvent;
    procedure SetHeaderHeight(AValue: Integer);
    procedure SetItemHeight(AValue: Integer);
    function ScaledHeaderHeight: Integer;
    function ScaledItemHeight: Integer;
    { Build the pure shapes array from the live group model. }
    function BuildShapes: TTyListGroupShapes;
    { The device-space layout (content coords, no scroll applied), for the current client width. }
    function BuildLayout: TTyListGroupParts;
    function MaxScrollOffset: Integer;
    procedure ClampScroll;
    procedure SetSelGroup(AValue: Integer);
    procedure SetSelItem(AValue: Integer);
    procedure ClearHover;
    function GroupExpanded(AGroup: Integer): Boolean;
    procedure SetGroupExpanded(AGroup: Integer; AValue: Boolean);
    function GetGroupCaption(AGroup: Integer): string;
    procedure SetGroupCaption(AGroup: Integer; const AValue: string);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Model mutation. }
    function AddGroup(const ACaption: string): Integer;
    function AddItem(AGroupIndex: Integer; const ACaption: string; AImageIndex: Integer = -1): Integer;
    procedure Clear;
    function GroupCount: Integer;
    function ItemCount(AGroupIndex: Integer): Integer;
    function ItemCaption(AGroupIndex, AItemIndex: Integer): string;
    function ItemImageIndex(AGroupIndex, AItemIndex: Integer): Integer;

    { Toggle a group's expand state (fires OnGroupToggle on a real change). }
    procedure ToggleGroup(AGroupIndex: Integer);
    { Select an item (fires OnItemClick on a real change). Pass (-1,-1) to clear. }
    procedure SelectItem(AGroupIndex, AItemIndex: Integer);

    { Per-group accessors. }
    property Expanded[AGroup: Integer]: Boolean read GroupExpanded write SetGroupExpanded;
    property GroupCaption[AGroup: Integer]: string read GetGroupCaption write SetGroupCaption;

    { The currently-selected item (both -1 when nothing is selected). }
    property SelectedGroup: Integer read FSelGroup write SetSelGroup;
    property SelectedItem: Integer read FSelItem write SetSelItem;

    { Current vertical scroll offset (device px, 0..MaxScrollOffset); wheel-driven. }
    property ScrollOffset: Integer read FScrollOffset;
  published
    property HeaderHeight: Integer read FHeaderHeight write SetHeaderHeight
      default TyListGroupDefaultHeaderHeight;
    property ItemHeight: Integer read FItemHeight write SetItemHeight
      default TyListGroupDefaultItemHeight;
    property OnGroupToggle: TTyListGroupToggleEvent read FOnGroupToggle write FOnGroupToggle;
    property OnItemClick: TTyListGroupItemEvent read FOnItemClick write FOnItemClick;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property TabStop default True;
  end;

implementation

{ ---- pure geometry ---- }

function TyListGroupLayout(const AGroups: TTyListGroupShapes;
  AHeaderH, AItemHeight, AClientW: Integer): TTyListGroupParts;
var
  g, it, y, n, hh, ih: Integer;
begin
  Result := nil;
  hh := AHeaderH;  if hh < 1 then hh := 1;
  ih := AItemHeight;  if ih < 1 then ih := 1;
  // Count parts first so we can size the array once (header per group + items of expanded groups).
  n := 0;
  for g := 0 to High(AGroups) do
  begin
    Inc(n);   // the header
    if AGroups[g].Expanded and (AGroups[g].ItemCount > 0) then
      Inc(n, AGroups[g].ItemCount);
  end;
  SetLength(Result, n);
  y := 0;
  n := 0;
  for g := 0 to High(AGroups) do
  begin
    Result[n].Kind := lgpHeader;
    Result[n].GroupIndex := g;
    Result[n].ItemIndex := -1;
    Result[n].Rect := Rect(0, y, AClientW, y + hh);
    Inc(y, hh);
    Inc(n);
    if AGroups[g].Expanded then
      for it := 0 to AGroups[g].ItemCount - 1 do
      begin
        Result[n].Kind := lgpItem;
        Result[n].GroupIndex := g;
        Result[n].ItemIndex := it;
        Result[n].Rect := Rect(0, y, AClientW, y + ih);
        Inc(y, ih);
        Inc(n);
      end;
  end;
end;

function TyListGroupContentHeight(const AParts: TTyListGroupParts): Integer;
begin
  if Length(AParts) = 0 then
    Result := 0
  else
    Result := AParts[High(AParts)].Rect.Bottom;
end;

function TyListGroupHitTest(const AParts: TTyListGroupParts; const APt: TPoint): TTyListGroupHit;
var
  i: Integer;
begin
  Result := Default(TTyListGroupHit);
  Result.Hit := False;
  Result.GroupIndex := -1;
  Result.ItemIndex := -1;
  for i := 0 to High(AParts) do
    if PtInRect(AParts[i].Rect, APt) then
    begin
      Result.Hit := True;
      Result.Kind := AParts[i].Kind;
      Result.GroupIndex := AParts[i].GroupIndex;
      Result.ItemIndex := AParts[i].ItemIndex;
      Exit;
    end;
end;

{ ---- TTyListGroupPanel ---- }

constructor TTyListGroupPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHeaderHeight := TyListGroupDefaultHeaderHeight;
  FItemHeight := TyListGroupDefaultItemHeight;
  FSelGroup := -1;
  FSelItem := -1;
  FHoverGroup := -1;
  FHoverItem := -1;
  FScrollOffset := 0;
  TabStop := True;
  Width := 200;
  Height := 260;
end;

destructor TTyListGroupPanel.Destroy;
begin
  inherited Destroy;
end;

function TTyListGroupPanel.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;

function TTyListGroupPanel.ScaledHeaderHeight: Integer;
begin
  Result := MulDiv(FHeaderHeight, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyListGroupPanel.ScaledItemHeight: Integer;
begin
  Result := MulDiv(FItemHeight, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyListGroupPanel.BuildShapes: TTyListGroupShapes;
var
  g: Integer;
begin
  SetLength(Result, Length(FGroups));
  for g := 0 to High(FGroups) do
  begin
    Result[g].Expanded := FGroups[g].Expanded;
    Result[g].ItemCount := Length(FGroups[g].Items);
  end;
end;

function TTyListGroupPanel.BuildLayout: TTyListGroupParts;
begin
  Result := TyListGroupLayout(BuildShapes, ScaledHeaderHeight, ScaledItemHeight, Width);
end;

function TTyListGroupPanel.MaxScrollOffset: Integer;
var
  contentH: Integer;
begin
  contentH := TyListGroupContentHeight(BuildLayout);
  Result := contentH - Height;
  if Result < 0 then Result := 0;
end;

procedure TTyListGroupPanel.ClampScroll;
var
  m: Integer;
begin
  m := MaxScrollOffset;
  if FScrollOffset > m then FScrollOffset := m;
  if FScrollOffset < 0 then FScrollOffset := 0;
end;

procedure TTyListGroupPanel.SetHeaderHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FHeaderHeight = AValue then Exit;
  FHeaderHeight := AValue;
  ClampScroll;
  Invalidate;
end;

procedure TTyListGroupPanel.SetItemHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FItemHeight = AValue then Exit;
  FItemHeight := AValue;
  ClampScroll;
  Invalidate;
end;

function TTyListGroupPanel.AddGroup(const ACaption: string): Integer;
begin
  Result := Length(FGroups);
  SetLength(FGroups, Result + 1);
  FGroups[Result].Caption := ACaption;
  FGroups[Result].Expanded := False;
  SetLength(FGroups[Result].Items, 0);
  ClampScroll;
  Invalidate;
end;

function TTyListGroupPanel.AddItem(AGroupIndex: Integer; const ACaption: string;
  AImageIndex: Integer): Integer;
var
  n: Integer;
begin
  if (AGroupIndex < 0) or (AGroupIndex > High(FGroups)) then Exit(-1);
  n := Length(FGroups[AGroupIndex].Items);
  SetLength(FGroups[AGroupIndex].Items, n + 1);
  FGroups[AGroupIndex].Items[n].Caption := ACaption;
  FGroups[AGroupIndex].Items[n].ImageIndex := AImageIndex;
  Result := n;
  ClampScroll;
  Invalidate;
end;

procedure TTyListGroupPanel.Clear;
begin
  SetLength(FGroups, 0);
  FSelGroup := -1;
  FSelItem := -1;
  FHoverGroup := -1;
  FHoverItem := -1;
  FScrollOffset := 0;
  Invalidate;
end;

function TTyListGroupPanel.GroupCount: Integer;
begin
  Result := Length(FGroups);
end;

function TTyListGroupPanel.ItemCount(AGroupIndex: Integer): Integer;
begin
  if (AGroupIndex < 0) or (AGroupIndex > High(FGroups)) then Exit(0);
  Result := Length(FGroups[AGroupIndex].Items);
end;

function TTyListGroupPanel.ItemCaption(AGroupIndex, AItemIndex: Integer): string;
begin
  Result := '';
  if (AGroupIndex < 0) or (AGroupIndex > High(FGroups)) then Exit;
  if (AItemIndex < 0) or (AItemIndex > High(FGroups[AGroupIndex].Items)) then Exit;
  Result := FGroups[AGroupIndex].Items[AItemIndex].Caption;
end;

function TTyListGroupPanel.ItemImageIndex(AGroupIndex, AItemIndex: Integer): Integer;
begin
  Result := -1;
  if (AGroupIndex < 0) or (AGroupIndex > High(FGroups)) then Exit;
  if (AItemIndex < 0) or (AItemIndex > High(FGroups[AGroupIndex].Items)) then Exit;
  Result := FGroups[AGroupIndex].Items[AItemIndex].ImageIndex;
end;

function TTyListGroupPanel.GroupExpanded(AGroup: Integer): Boolean;
begin
  if (AGroup < 0) or (AGroup > High(FGroups)) then Exit(False);
  Result := FGroups[AGroup].Expanded;
end;

procedure TTyListGroupPanel.SetGroupExpanded(AGroup: Integer; AValue: Boolean);
begin
  if (AGroup < 0) or (AGroup > High(FGroups)) then Exit;
  if FGroups[AGroup].Expanded = AValue then Exit;
  FGroups[AGroup].Expanded := AValue;
  ClampScroll;
  Invalidate;
  if Assigned(FOnGroupToggle) then FOnGroupToggle(Self, AGroup);
end;

function TTyListGroupPanel.GetGroupCaption(AGroup: Integer): string;
begin
  Result := '';
  if (AGroup < 0) or (AGroup > High(FGroups)) then Exit;
  Result := FGroups[AGroup].Caption;
end;

procedure TTyListGroupPanel.SetGroupCaption(AGroup: Integer; const AValue: string);
begin
  if (AGroup < 0) or (AGroup > High(FGroups)) then Exit;
  if FGroups[AGroup].Caption = AValue then Exit;
  FGroups[AGroup].Caption := AValue;
  Invalidate;
end;

procedure TTyListGroupPanel.ToggleGroup(AGroupIndex: Integer);
begin
  if (AGroupIndex < 0) or (AGroupIndex > High(FGroups)) then Exit;
  SetGroupExpanded(AGroupIndex, not FGroups[AGroupIndex].Expanded);
end;

procedure TTyListGroupPanel.SelectItem(AGroupIndex, AItemIndex: Integer);
var
  valid: Boolean;
begin
  valid := (AGroupIndex >= 0) and (AGroupIndex <= High(FGroups))
    and (AItemIndex >= 0) and (AItemIndex <= High(FGroups[AGroupIndex].Items));
  if not valid then
  begin
    AGroupIndex := -1;
    AItemIndex := -1;
  end;
  if (FSelGroup = AGroupIndex) and (FSelItem = AItemIndex) then Exit;
  FSelGroup := AGroupIndex;
  FSelItem := AItemIndex;
  Invalidate;
  if valid and Assigned(FOnItemClick) then FOnItemClick(Self, AGroupIndex, AItemIndex);
end;

procedure TTyListGroupPanel.SetSelGroup(AValue: Integer);
begin
  SelectItem(AValue, FSelItem);
end;

procedure TTyListGroupPanel.SetSelItem(AValue: Integer);
begin
  SelectItem(FSelGroup, AValue);
end;

procedure TTyListGroupPanel.ClearHover;
begin
  if (FHoverGroup <> -1) or (FHoverItem <> -1) then
  begin
    FHoverGroup := -1;
    FHoverItem := -1;
    Invalidate;
  end;
end;

procedure TTyListGroupPanel.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  parts: TTyListGroupParts;
  hit: TTyListGroupHit;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  parts := BuildLayout;
  hit := TyListGroupHitTest(parts, Point(X, Y + FScrollOffset));
  if hit.Hit then
  begin
    if hit.Kind = lgpHeader then
      ToggleGroup(hit.GroupIndex)
    else
      SelectItem(hit.GroupIndex, hit.ItemIndex);
  end;
  try
    if CanFocus then SetFocus;
  except
    // headless / no-handle: ignore
  end;
end;

procedure TTyListGroupPanel.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  parts: TTyListGroupParts;
  hit: TTyListGroupHit;
  newKind: TTyListGroupPartKind;
  newGroup, newItem: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  parts := BuildLayout;
  hit := TyListGroupHitTest(parts, Point(X, Y + FScrollOffset));
  if hit.Hit then
  begin
    newKind := hit.Kind;
    newGroup := hit.GroupIndex;
    newItem := hit.ItemIndex;
  end
  else
  begin
    newKind := lgpHeader;
    newGroup := -1;
    newItem := -1;
  end;
  if (newKind <> FHoverKind) or (newGroup <> FHoverGroup) or (newItem <> FHoverItem) then
  begin
    FHoverKind := newKind;
    FHoverGroup := newGroup;
    FHoverItem := newItem;
    Invalidate;
  end;
end;

procedure TTyListGroupPanel.MouseLeave;
begin
  inherited MouseLeave;
  ClearHover;
end;

function TTyListGroupPanel.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  step, m, old: Integer;
begin
  if not Enabled then Exit(False);
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then Exit(True);
  m := MaxScrollOffset;
  if m <= 0 then Exit(False);   // nothing to scroll
  step := ScaledItemHeight * 3;
  old := FScrollOffset;
  if WheelDelta > 0 then
    Dec(FScrollOffset, step)
  else
    Inc(FScrollOffset, step);
  if FScrollOffset > m then FScrollOffset := m;
  if FScrollOffset < 0 then FScrollOffset := 0;
  if FScrollOffset <> old then Invalidate;
  Result := True;
end;

procedure TTyListGroupPanel.Resize;
begin
  inherited Resize;
  ClampScroll;
end;

procedure TTyListGroupPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle, HdrStyle, ItemStyle: TTyStyleSet;
  R, partR, textR, chevRect: TRect;
  parts: TTyListGroupParts;
  i, hdrH, chevZone: Integer;
  states: TTyStateSet;
  tri: TTyTriangle;
  ctx: TBGRACanvas2D;
  savedClip: TRect;
  cap: string;
  selected, hovered: Boolean;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    BoxStyle := CurrentStyle;
    DrawFrame(P, R, BoxStyle);

    hdrH := MulDiv(FHeaderHeight, APPI, 96);
    if hdrH < 1 then hdrH := 1;

    // Recompute the layout in DEVICE space using APPI (RenderTo may be called with a test
    // PPI that differs from Font.PixelsPerInch), so paint geometry == the pure layout.
    parts := TyListGroupLayout(BuildShapes, hdrH,
      MulDiv(FItemHeight, APPI, 96), R.Right - R.Left);

    // Clip everything to the frame interior so scrolled content never paints over the border.
    savedClip := P.Bitmap.ClipRect;
    P.Bitmap.ClipRect := Rect(R.Left + P.Scale(BoxStyle.BorderWidth),
      R.Top + P.Scale(BoxStyle.BorderWidth),
      R.Right - P.Scale(BoxStyle.BorderWidth),
      R.Bottom - P.Scale(BoxStyle.BorderWidth));

    for i := 0 to High(parts) do
    begin
      // Shift content up by the scroll offset.
      partR := parts[i].Rect;
      OffsetRect(partR, 0, -FScrollOffset);
      // Skip parts entirely outside the visible band.
      if (partR.Bottom <= R.Top) or (partR.Top >= R.Bottom) then Continue;

      if parts[i].Kind = lgpHeader then
      begin
        hovered := (FHoverGroup = parts[i].GroupIndex) and (FHoverItem = -1)
          and (FHoverKind = lgpHeader);
        states := [];
        if GroupExpanded(parts[i].GroupIndex) then Include(states, tysSelected)
        else if hovered then Include(states, tysHover)
        else Include(states, tysNormal);
        HdrStyle := ActiveController.Model.ResolveStyle('TyTreeHeaderSection', '', states);

        if tpBackground in HdrStyle.Present then
          P.FillBackground(partR, HdrStyle.Background, 0);

        // Chevron (down when expanded, right when collapsed), reusing the ExPanel geometry.
        tri := TyExPanelChevronPoints(partR, GroupExpanded(parts[i].GroupIndex));
        ctx := P.Bitmap.Canvas2D;
        ctx.beginPath;
        ctx.moveTo(tri[0].X + 0.5, tri[0].Y + 0.5);
        ctx.lineTo(tri[1].X + 0.5, tri[1].Y + 0.5);
        ctx.lineTo(tri[2].X + 0.5, tri[2].Y + 0.5);
        ctx.closePath;
        ctx.fillStyle(TyColorToBGRA(HdrStyle.TextColor));
        ctx.fill;

        // Caption to the right of the chevron gutter.
        cap := GetGroupCaption(parts[i].GroupIndex);
        if cap <> '' then
        begin
          chevZone := partR.Bottom - partR.Top;   // gutter == band height (chevron centre)
          textR := Rect(partR.Left + chevZone, partR.Top,
            partR.Right - P.Scale(HdrStyle.Padding.Right), partR.Bottom);
          P.DrawText(textR, cap, HdrStyle.FontName, ResolveFontSize(HdrStyle),
            HdrStyle.FontWeight, HdrStyle.TextColor, taLeftJustify, tlCenter, True);
        end;
      end
      else
      begin
        // Item row.
        selected := (parts[i].GroupIndex = FSelGroup) and (parts[i].ItemIndex = FSelItem);
        hovered := (FHoverKind = lgpItem) and (FHoverGroup = parts[i].GroupIndex)
          and (FHoverItem = parts[i].ItemIndex);
        states := [];
        if selected then Include(states, tysActive)
        else if hovered then Include(states, tysHover)
        else Include(states, tysNormal);
        ItemStyle := ActiveController.Model.ResolveStyle('TyListItem', '', states);

        if tpBackground in ItemStyle.Present then
          P.FillBackground(partR, ItemStyle.Background, 0);

        cap := ItemCaption(parts[i].GroupIndex, parts[i].ItemIndex);
        // Indent items one header-height in, so they sit under the header caption.
        textR := Rect(partR.Left + hdrH + P.Scale(ItemStyle.Padding.Left), partR.Top,
          partR.Right - P.Scale(ItemStyle.Padding.Right), partR.Bottom);
        P.DrawText(textR, cap, ItemStyle.FontName, ResolveFontSize(ItemStyle),
          ItemStyle.FontWeight, ItemStyle.TextColor, taLeftJustify, tlCenter, True);
      end;
    end;

    P.Bitmap.ClipRect := savedClip;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyListGroupPanel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
