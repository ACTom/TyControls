unit tyControls.ListBox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.ScrollBar;
type
  TTyListBox = class(TTyCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FItemHeight: Integer;
    FTopIndex: Integer;
    FOnChange: TNotifyEvent;
    FHoverRow: Integer;       // -1 = none; set in MouseMove, cleared in MouseLeave
    FScrollBar: TTyScrollBar; // nil until first needed
    FSyncingScroll: Boolean;  // reentrancy guard
    procedure SetItems(const AValue: TStringList);
    procedure SetItemIndex(const AValue: Integer);
    procedure SetItemHeight(const AValue: Integer);
    procedure SetTopIndex(const AValue: Integer);
    function ScaledItemHeight: Integer;
    function MaxTopIndex: Integer;
    procedure EnsureSelectionVisible;
    procedure ScrollBarChange(Sender: TObject);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    procedure Resize; override;
    procedure UpdateScrollBar;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SelectItem(AIndex: Integer);
    function VisibleRows: Integer;
    // Public helper for headless keyboard tests
    procedure SimulateKeyDown(AKey: Word);
  published
    property Items: TStringList read FItems write SetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    property ItemHeight: Integer read FItemHeight write SetItemHeight default 24;
    property TopIndex: Integer read FTopIndex write SetTopIndex default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ TTyListBox }

constructor TTyListBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItemIndex := -1;
  FItemHeight := 24;
  FTopIndex := 0;
  FHoverRow := -1;
  FScrollBar := nil;
  FSyncingScroll := False;
  TabStop := True;
  Width := 160;
  Height := 120;
end;

destructor TTyListBox.Destroy;
begin
  FItems.Free;
  // FScrollBar is owned by Self (via Create(Self)) so it is freed by TComponent
  inherited Destroy;
end;

function TTyListBox.GetStyleTypeKey: string;
begin
  Result := 'TyListBox';
end;

procedure TTyListBox.SetItems(const AValue: TStringList);
begin
  FItems.Assign(AValue);
  // Clamp TopIndex and ItemIndex in case list shrank
  if FTopIndex > MaxTopIndex then
    FTopIndex := MaxTopIndex;
  if (FItemIndex >= 0) and (FItemIndex >= FItems.Count) then
  begin
    FItemIndex := -1;
    if Assigned(FOnChange) then
      FOnChange(Self);
  end;
  UpdateScrollBar;
  Invalidate;
end;

procedure TTyListBox.SetItemIndex(const AValue: Integer);
begin
  SelectItem(AValue);
end;

procedure TTyListBox.SetItemHeight(const AValue: Integer);
begin
  if FItemHeight = AValue then Exit;
  FItemHeight := AValue;
  if FItemHeight < 1 then FItemHeight := 1;
  UpdateScrollBar;
  Invalidate;
end;

function TTyListBox.MaxTopIndex: Integer;
begin
  Result := FItems.Count - VisibleRows;
  if Result < 0 then Result := 0;
end;

procedure TTyListBox.SetTopIndex(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < 0 then Clamped := 0;
  if Clamped > MaxTopIndex then Clamped := MaxTopIndex;
  if FTopIndex = Clamped then Exit;
  FTopIndex := Clamped;
  // Sync scrollbar position (guard reentrancy)
  if (not FSyncingScroll) and (FScrollBar <> nil) and FScrollBar.Visible then
  begin
    FSyncingScroll := True;
    try
      FScrollBar.Position := FTopIndex;
    finally
      FSyncingScroll := False;
    end;
  end;
  Invalidate;
end;

function TTyListBox.ScaledItemHeight: Integer;
begin
  Result := MulDiv(FItemHeight, Font.PixelsPerInch, 96);
  if Result < 1 then Result := 1;
end;

function TTyListBox.VisibleRows: Integer;
var
  SH: Integer;
begin
  SH := ScaledItemHeight;
  // Use Height rather than ClientHeight so the result is testable headlessly
  // (in headless LCL without a native handle, ClientHeight can lag behind SetBounds).
  // For this borderless control Height = ClientHeight at runtime.
  Result := Height div SH;
  if Result < 1 then Result := 1;
end;

procedure TTyListBox.EnsureSelectionVisible;
var
  VR: Integer;
begin
  if FItemIndex < 0 then Exit;
  VR := VisibleRows;
  if FItemIndex < FTopIndex then
    FTopIndex := FItemIndex
  else if FItemIndex >= FTopIndex + VR then
    FTopIndex := FItemIndex - VR + 1;
  // Clamp TopIndex to valid range
  if FTopIndex < 0 then FTopIndex := 0;
  if FTopIndex > MaxTopIndex then FTopIndex := MaxTopIndex;
end;

procedure TTyListBox.SelectItem(AIndex: Integer);
var
  NewIndex: Integer;
begin
  if (AIndex >= 0) and (AIndex < FItems.Count) then
    NewIndex := AIndex
  else
    NewIndex := -1;
  if NewIndex = FItemIndex then Exit;
  FItemIndex := NewIndex;
  EnsureSelectionVisible;
  UpdateScrollBar;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyListBox.ScrollBarChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FSyncingScroll := True;
  try
    SetTopIndex(FScrollBar.Position);
  finally
    FSyncingScroll := False;
  end;
end;

procedure TTyListBox.UpdateScrollBar;
var
  VR, MaxPos, MaxTop: Integer;
begin
  VR := VisibleRows;
  // Clamp FTopIndex in case Items were mutated directly (Clear/Add without SetItems)
  MaxTop := FItems.Count - VR;
  if MaxTop < 0 then MaxTop := 0;
  if FTopIndex > MaxTop then FTopIndex := MaxTop;
  if FItems.Count > VR then
  begin
    // Ensure scrollbar created
    if FScrollBar = nil then
    begin
      FScrollBar := TTyScrollBar.Create(Self);
      FScrollBar.Parent := Self;
      FScrollBar.Kind := sbVertical;
      FScrollBar.Align := alRight;
      FScrollBar.OnChange := @ScrollBarChange;
    end;
    // Update DPI-dependent width and controller every call so DPI changes take effect
    FScrollBar.Width := MulDiv(12, Font.PixelsPerInch, 96);
    FScrollBar.Controller := Self.Controller;
    MaxPos := FItems.Count - VR;
    if MaxPos < 0 then MaxPos := 0;
    FSyncingScroll := True;
    try
      FScrollBar.Min := 0;
      FScrollBar.Max := MaxPos;
      FScrollBar.PageSize := VR;
      FScrollBar.Position := FTopIndex;
    finally
      FSyncingScroll := False;
    end;
    FScrollBar.Visible := True;
  end
  else
  begin
    if FScrollBar <> nil then
      FScrollBar.Visible := False;
  end;
end;

procedure TTyListBox.KeyDown(var Key: Word; Shift: TShiftState);
var
  Count, NewIndex: Integer;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  Count := FItems.Count;
  if Count = 0 then Exit;

  case Key of
    VK_UP:
    begin
      if FItemIndex <= 0 then
        NewIndex := 0
      else
        NewIndex := FItemIndex - 1;
      SelectItem(NewIndex);
      Key := 0;
    end;
    VK_DOWN:
    begin
      if FItemIndex < 0 then
        NewIndex := 0
      else if FItemIndex < Count - 1 then
        NewIndex := FItemIndex + 1
      else
        NewIndex := Count - 1;
      SelectItem(NewIndex);
      Key := 0;
    end;
    VK_HOME:
    begin
      SelectItem(0);
      Key := 0;
    end;
    VK_END:
    begin
      SelectItem(Count - 1);
      Key := 0;
    end;
  end;
end;

procedure TTyListBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
  SH: Integer;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    SH := ScaledItemHeight;
    Row := FTopIndex + (Y div SH);
    if (Row >= 0) and (Row < FItems.Count) then
      SelectItem(Row);
    try
      if CanFocus then
        SetFocus;
    except
      // Ignore focus errors in headless/test environments
    end;
  end;
end;

procedure TTyListBox.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  SH, NewRow: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  SH := ScaledItemHeight;
  NewRow := FTopIndex + (Y div SH);
  if (NewRow < 0) or (NewRow >= FItems.Count) then
    NewRow := -1;
  if NewRow <> FHoverRow then
  begin
    FHoverRow := NewRow;
    Invalidate;
  end;
end;

procedure TTyListBox.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverRow <> -1 then
  begin
    FHoverRow := -1;
    Invalidate;
  end;
end;

function TTyListBox.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  Delta: Integer;
begin
  if not Enabled then Exit(False);
  // Let the user's OnMouseWheel handler run first; if it consumes the event, stop.
  if inherited DoMouseWheel(Shift, WheelDelta, MousePos) then
  begin
    Result := True;
    Exit;
  end;
  // WheelDelta > 0 = scroll up (TopIndex decreases)
  // WheelDelta < 0 = scroll down (TopIndex increases)
  if WheelDelta > 0 then
    Delta := -3
  else
    Delta := 3;
  SetTopIndex(FTopIndex + Delta);
  Result := True;
end;

procedure TTyListBox.Resize;
begin
  inherited Resize;
  UpdateScrollBar;
end;

procedure TTyListBox.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle, RowStyle: TTyStyleSet;
  R, ContentRect, RowRect: TRect;
  SBWidth, SH, i, LastRow: Integer;
  ItemStates: TTyStateSet;
begin
  // Keep scrollbar in sync (cheap; catches external Items.Add calls)
  UpdateScrollBar;

  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    BoxStyle := CurrentStyle;
    DrawFrame(P, R, BoxStyle);

    // Content area = full rect inset by the LISTBOX style's Padding
    ContentRect := Rect(
      R.Left   + P.Scale(BoxStyle.Padding.Left),
      R.Top    + P.Scale(BoxStyle.Padding.Top),
      R.Right  - P.Scale(BoxStyle.Padding.Right),
      R.Bottom - P.Scale(BoxStyle.Padding.Bottom)
    );

    // Subtract scrollbar width when visible
    SBWidth := 0;
    if (FScrollBar <> nil) and FScrollBar.Visible then
      SBWidth := MulDiv(12, APPI, 96);

    SH := MulDiv(FItemHeight, APPI, 96);
    if SH < 1 then SH := 1;
    LastRow := FTopIndex + VisibleRows - 1;
    if LastRow >= FItems.Count - 1 then
      LastRow := FItems.Count - 1;

    for i := FTopIndex to LastRow do
    begin
      // Determine item states
      ItemStates := [];
      if i = FItemIndex then
        Include(ItemStates, tysActive)
      else if i = FHoverRow then
        Include(ItemStates, tysHover)
      else
        Include(ItemStates, tysNormal);

      // Resolve TyListItem style for this row
      RowStyle := ActiveController.Model.ResolveStyle('TyListItem', '', ItemStates);

      // Row rect: full content width minus scrollbar, height = scaledItemHeight
      RowRect := Rect(
        ContentRect.Left,
        ContentRect.Top + (i - FTopIndex) * SH,
        ContentRect.Right - SBWidth,
        ContentRect.Top + (i - FTopIndex + 1) * SH
      );

      // Fill row background if the style has one
      if tpBackground in RowStyle.Present then
        P.FillBackground(RowRect, RowStyle.Background, RowStyle.BorderRadius);

      // Draw item text, inset by item padding
      P.DrawText(
        Rect(RowRect.Left + P.Scale(RowStyle.Padding.Left),
             RowRect.Top,
             RowRect.Right - P.Scale(RowStyle.Padding.Right),
             RowRect.Bottom),
        FItems[i],
        RowStyle.FontName, RowStyle.FontSize, RowStyle.FontWeight,
        RowStyle.TextColor,
        taLeftJustify, tlCenter, True
      );
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyListBox.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyListBox.SimulateKeyDown(AKey: Word);
begin
  KeyDown(AKey, []);
end;

end.
