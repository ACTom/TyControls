unit tyControls.ButtonGroup;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller, tyControls.Accel;
type
  { TTyButtonGroup — a horizontal SEGMENTED button bar: N adjacent cells, each a
    caption, laid out edge-to-edge. Single-select (radio, like a segmented control:
    ItemIndex) or multi-select (a toggle set: IsSelected/SetSelected). Each segment
    is custom-drawn via TTyPainter reusing the 'TyButton' token, so a segment looks
    like a button; the selected segment(s) resolve with tysSelected, the hovered one
    with tysHover. Only the group's OUTER corners are rounded (left cell rounds left,
    right cell rounds right, middles are square). }
  TTyButtonGroup = class(TTyCustomControl)
  private
    FItems: TStrings;
    FMultiSelect: Boolean;
    FItemIndex: Integer;
    FSelected: array of Boolean;   // multi-select bit-set (kept sized to Items.Count)
    FHoverSeg: Integer;            // -1 = none; tracked in MouseMove for :hover styling
    FOnSelectionChange: TNotifyEvent;
    procedure SetItems(AValue: TStrings);
    procedure ItemsChanged(Sender: TObject);
    procedure SetMultiSelect(AValue: Boolean);
    procedure SetItemIndex(AValue: Integer);
    procedure EnsureSelectedLen;
    procedure DoSelectionChange;
  protected
    function GetStyleTypeKey: string; override;
    { Hit-test AX to a segment and apply selection, mirroring what a click does.
      Single-select: sets ItemIndex (fires OnSelectionChange iff it changed).
      Multi-select: toggles that segment (always fires OnSelectionChange on a valid
      segment). A hit outside any segment is a no-op. Exposed to tests as a seam. }
    procedure SelectAt(AX: Integer);
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { True iff segment AIndex is selected (single-select: AIndex = ItemIndex;
      multi-select: its bit). Out-of-range -> False. }
    function IsSelected(AIndex: Integer): Boolean;
    { Set segment AIndex's selected flag. Multi-select: sets/clears its bit (fires
      OnSelectionChange on a real change). Single-select: AValue=True selects it
      (=ItemIndex := AIndex); AValue=False clears it only when it was the selected one. }
    procedure SetSelected(AIndex: Integer; AValue: Boolean);
    function Count: Integer;
  published
    property Items: TStrings read FItems write SetItems;
    property MultiSelect: Boolean read FMultiSelect write SetMultiSelect default False;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ Which segment index AX (device px, 0-based from the group's left edge) falls in,
  given the group's device width AWidthPx and segment count ACount. Segments divide
  the width evenly; the last cell absorbs rounding so the tiling exactly covers
  [0, AWidthPx). Returns -1 when empty (ACount <= 0), zero-width, or AX is outside
  [0, AWidthPx). PURE — no control state; unit-tested. }
function TySegmentAt(AX, AWidthPx, ACount: Integer): Integer;

{ The device-px rect of segment AIndex within a group of AWidthPx x AHeightPx and
  ACount segments. Segments tile left-to-right with equal widths; the last cell
  extends to AWidthPx (absorbing the integer-division remainder) so there are no
  gaps/overlaps and the rects cover [0, AWidthPx) x [0, AHeightPx). An out-of-range
  AIndex (or ACount <= 0) yields an empty rect. PURE — unit-tested. }
function TySegmentRect(AIndex, AWidthPx, AHeightPx, ACount: Integer): TRect;

implementation

function TySegmentAt(AX, AWidthPx, ACount: Integer): Integer;
var
  seg, segW: Integer;
begin
  Result := -1;
  if (ACount <= 0) or (AWidthPx <= 0) then Exit;
  if (AX < 0) or (AX >= AWidthPx) then Exit;
  segW := AWidthPx div ACount;
  if segW <= 0 then
  begin
    // Degenerate: fewer device px than segments. Distribute proportionally so a
    // click still maps to a real segment (and the last cell still absorbs the tail).
    seg := (AX * ACount) div AWidthPx;
  end
  else
  begin
    seg := AX div segW;
    // The last cell absorbs the rounding remainder, so any X past the start of the
    // last equal slice belongs to the last segment (never a phantom ACount-th cell).
    if seg > ACount - 1 then seg := ACount - 1;
  end;
  Result := seg;
end;

function TySegmentRect(AIndex, AWidthPx, AHeightPx, ACount: Integer): TRect;
var
  segW, l, r: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (ACount <= 0) or (AIndex < 0) or (AIndex >= ACount) then Exit;
  if (AWidthPx <= 0) or (AHeightPx <= 0) then Exit;
  segW := AWidthPx div ACount;
  l := AIndex * segW;
  if AIndex = ACount - 1 then
    r := AWidthPx           // last cell absorbs the remainder -> tile covers [0, W)
  else
    r := (AIndex + 1) * segW;
  Result := Rect(l, 0, r, AHeightPx);
end;

{ TTyButtonGroup }

constructor TTyButtonGroup.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TyAccelRegister(Self);
  FItems := TStringList.Create;
  TStringList(FItems).OnChange := @ItemsChanged;
  FMultiSelect := False;
  FItemIndex := -1;
  FHoverSeg := -1;
  Width := 240;
  Height := TyDensityHeight(ActiveController, 30);
end;

destructor TTyButtonGroup.Destroy;
begin
  TyAccelUnregister(Self);
  FItems.Free;
  inherited Destroy;
end;

function TTyButtonGroup.GetStyleTypeKey: string;
begin
  Result := 'TyButton';   // REUSE the button token; no new .tycss rule
end;

function TTyButtonGroup.Count: Integer;
begin
  Result := FItems.Count;
end;

procedure TTyButtonGroup.EnsureSelectedLen;
begin
  if Length(FSelected) <> FItems.Count then
    SetLength(FSelected, FItems.Count);   // new slots default False
end;

procedure TTyButtonGroup.DoSelectionChange;
begin
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

procedure TTyButtonGroup.SetItems(AValue: TStrings);
begin
  FItems.Assign(AValue);   // fires ItemsChanged, which resizes + clamps + repaints
end;

procedure TTyButtonGroup.ItemsChanged(Sender: TObject);
var
  i: Integer;
begin
  // The item list changed structurally. TStrings.OnChange carries no diff, so
  // positional selection bits (and the single-select index) cannot be remapped —
  // keeping them would silently move the selection onto a different item after an
  // insert/delete. Reset selection to a clean state instead (safe over subtly wrong).
  SetLength(FSelected, FItems.Count);
  for i := 0 to High(FSelected) do FSelected[i] := False;
  FItemIndex := -1;
  if FHoverSeg >= FItems.Count then FHoverSeg := -1;
  Invalidate;
end;

procedure TTyButtonGroup.SetMultiSelect(AValue: Boolean);
var
  i: Integer;
begin
  if FMultiSelect = AValue then Exit;
  FMultiSelect := AValue;
  EnsureSelectedLen;
  // Clean slate on any mode switch so stale multi bits never resurface.
  for i := 0 to High(FSelected) do FSelected[i] := False;
  FItemIndex := -1;
  Invalidate;
end;

procedure TTyButtonGroup.SetItemIndex(AValue: Integer);
var
  NewIndex: Integer;
begin
  if (AValue >= 0) and (AValue < FItems.Count) then
    NewIndex := AValue
  else
    NewIndex := -1;
  if NewIndex = FItemIndex then Exit;
  FItemIndex := NewIndex;
  Invalidate;
  DoSelectionChange;
end;

function TTyButtonGroup.IsSelected(AIndex: Integer): Boolean;
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit(False);
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    Result := FSelected[AIndex];
  end
  else
    Result := (AIndex = FItemIndex);
end;

procedure TTyButtonGroup.SetSelected(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    if FSelected[AIndex] = AValue then Exit;
    FSelected[AIndex] := AValue;
    Invalidate;
    DoSelectionChange;
  end
  else if AValue then
    SetItemIndex(AIndex)                      // single mode: True selects it
  else if AIndex = FItemIndex then
    SetItemIndex(-1);                         // clearing the selected one deselects
end;

procedure TTyButtonGroup.SelectAt(AX: Integer);
var
  seg: Integer;
begin
  seg := TySegmentAt(AX, Width, FItems.Count);
  if seg < 0 then Exit;
  if FMultiSelect then
  begin
    EnsureSelectedLen;
    FSelected[seg] := not FSelected[seg];
    Invalidate;
    DoSelectionChange;                        // multi: a click always toggles + fires
  end
  else
    SetItemIndex(seg);                        // single: fires only when index changes
end;

procedure TTyButtonGroup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    SelectAt(X);
end;

procedure TTyButtonGroup.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  seg: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  seg := TySegmentAt(X, Width, FItems.Count);
  if seg <> FHoverSeg then
  begin
    FHoverSeg := seg;
    Invalidate;
  end;
end;

procedure TTyButtonGroup.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverSeg <> -1 then
  begin
    FHoverSeg := -1;
    Invalidate;
  end;
end;

procedure TTyButtonGroup.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  W, H, i, n: Integer;
  segStates: TTyStateSet;
  segStyle: TTyStyleSet;
  segRect: TRect;
  corners: TTyCorners;
  radius: Integer;
  disp: string;
  mp: Integer;
begin
  P := TTyPainter.Create;
  try
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    P.BeginPaint(ACanvas, ARect, APPI);
    // Fill the parent's OPAQUE surface first: unselected ghost segments resolve to a
    // transparent background, which on the Win10 DWM sheet-of-glass would otherwise bleed
    // through as white/mismatched patches on dark themes (same fix as TTyButton).
    TyFillParentBg(Self, P, Rect(0, 0, W, H),
      ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]));
    n := FItems.Count;
    if n <= 0 then
    begin
      // Nothing to draw beyond the frame — resolve the base style so an empty group
      // still fills its background (headless-safe: no segment maths at all).
      P.EndPaint;
      Exit;
    end;

    // The outer corner radius comes from the resolved base style (BorderRadius token).
    // Left cell rounds its left corners, right cell its right corners, middles square.
    radius := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, [tysNormal]).BorderRadius;
    if radius < 0 then radius := 0;

    for i := 0 to n - 1 do
    begin
      // Per-segment state set: disabled wins; else selected (radio index / multi bit)
      // + hover layer on the hovered segment; otherwise normal.
      segStates := [];
      if not Enabled then
        Include(segStates, tysDisabled)
      else
      begin
        if IsSelected(i) then Include(segStates, tysSelected);
        if i = FHoverSeg then Include(segStates, tysHover);
        if segStates = [] then Include(segStates, tysNormal);
      end;

      segStyle := ActiveController.Model.ResolveStyle(GetStyleTypeKey, StyleClass, segStates);

      segRect := TySegmentRect(i, W, H, n);

      // Outer corners only: round the group's left/right edges, square the seams.
      corners := TyCorners(0, 0, 0, 0);
      if i = 0 then begin corners.TL := radius; corners.BL := radius; end;
      if i = n - 1 then begin corners.TR := radius; corners.BR := radius; end;

      // Background fill for this segment (per-corner rounding so seams stay flush).
      if tpBackground in segStyle.Present then
        P.FillBackground(segRect, segStyle.Background, corners);

      // Border around the segment. Adjacent cells share a seam so the doubled 1px
      // stroke reads as a single divider — simple, clean, and keeps each segment's
      // state border (e.g. selected/accent) visible on its own edges.
      if TyBorderVisible(segStyle) then
        P.StrokeBorder(segRect, corners, segStyle.BorderWidth, segStyle.BorderColor);

      // Centered caption, inset horizontally by the style's left/right padding.
      TyParseMnemonic(FItems[i], disp, mp);
      P.DrawText(
        Rect(segRect.Left  + P.Scale(segStyle.Padding.Left),
             segRect.Top,
             segRect.Right - P.Scale(segStyle.Padding.Right),
             segRect.Bottom),
        disp, segStyle.FontName, ResolveFontSize(segStyle), segStyle.FontWeight,
        segStyle.TextColor, taCenter, tlCenter, True, TyAccelGatePos(mp));
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyButtonGroup.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
