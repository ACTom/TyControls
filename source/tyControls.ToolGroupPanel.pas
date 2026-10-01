unit tyControls.ToolGroupPanel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.GroupBox,
  tyControls.Button;
type
  { TTyToolGroupPanel — a titled group of TOOL BUTTONS, styled like a ribbon group
    but usable OUTSIDE a ribbon. Descends from TTyCustomGroupBox, so it inherits the themed
    titled frame + the caption-band client inset (AdjustClientRect) for free, but it
    carries its OWN 'TyToolGroupPanel' typeKey (see GetStyleTypeKey). It hosts
    TTyButton children in a horizontal FLOW that WRAPS to a new row when the next button
    would overrun the inset client width.

    Two ways to fill it:
      - AddButton(caption, onclick) creates a themed ghost TTyButton child, flow-positions
        it, and returns it. Buttons added this way are the USER's controls (they are NOT
        marked csNoDesignVisible — this is a real container, not an auto-populated helper).
      - Or drop child controls at design time (csAcceptsControls is kept): they are laid
        out in the same flow on the next relayout.

    Relayout runs on resize and after every AddButton. }
  TTyCustomToolGroupPanel = class(TTyCustomGroupBox)
  private
    FSpacing: Integer;
    FButtonHeight: Integer;
    FInLayout: Boolean;
    procedure SetSpacing(AValue: Integer);
    procedure SetButtonHeight(AValue: Integer);
    procedure Relayout;
  protected
    { Its own key, NOT the group box's. This is a different THING reusing the group
      box's code: a ribbon-style tool group. The design system already separates the
      two concepts — 'TyRibbonGroup' is deliberately styled unlike 'TyGroupBox'
      (transparent, muted caption, hairline border vs. the form group box's padded,
      radiused frame) — and pinned to 'TyGroupBox' a theme could not make a standalone
      tool group match its own ribbon groups without restyling every form group box.
      Caption PLACEMENT stays TTyGroupBox's top band (it is hard-coded in its RenderTo),
      so this key buys colours/border/padding/font, not a ribbon-style bottom caption. }
    function GetStyleTypeKey: string; override;
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Create a themed ghost TTyButton child with ACaption (and optional OnClick), owned
      by Self, flow-positioned into the inset client area, and return it. The returned
      button is the caller's to configure further. }
    function AddButton(const ACaption: string; AOnClick: TNotifyEvent = nil): TTyButton;
    { Gap (logical px) between adjacent buttons horizontally, and between wrapped rows. }
    property Spacing: Integer read FSpacing write SetSpacing default 4;
    { Height (logical px) every flowed button is given (widths keep each button's own). }
    property ButtonHeight: Integer read FButtonHeight write SetButtonHeight default 26;
  end;

  { TTyToolGroupPanel publishes TTyCustomToolGroupPanel's properties; everything lives in TTyCustomToolGroupPanel. }
  TTyToolGroupPanel = class(TTyCustomToolGroupPanel)
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
    property Caption;
    property Alignment;
    property ClientWidth;
    property ClientHeight;
    property DockSite;
    property UseDockManager;
    property OnDockDrop;
    property OnDockOver;
    property OnUnDock;
    property OnGetSiteInfo;
    property OnGetDockCaption;
    property OnStartDock;
    property OnEndDock;
    property Align;
    property Anchors;
    property Spacing;
    property ButtonHeight;
  end;

{ Flow the given button sizes left-to-right inside AClient, wrapping to a new row when
  the next button's right edge would exceed AClient.Right. Every row is AButtonHeight tall;
  ASpacing separates buttons horizontally and rows vertically. Each returned rect keeps its
  button's own width (AButtonSizes[i].cx) but is forced to AButtonHeight tall. The first
  button on a row never wraps (so an over-wide button still gets a rect, just overflowing).
  Coordinates are relative to AClient's top-left origin folded in (rects are absolute within
  the client rect). PURE geometry — no control state; unit-tested directly. }
function TyToolFlowRects(const AClient: TRect; const AButtonSizes: array of TSize;
  ASpacing, AButtonHeight: Integer): TTyRectArray;

implementation

function TyToolFlowRects(const AClient: TRect; const AButtonSizes: array of TSize;
  ASpacing, AButtonHeight: Integer): TTyRectArray;
var
  i, x, y, rowRight: Integer;
begin
  SetLength(Result, Length(AButtonSizes));
  if ASpacing < 0 then ASpacing := 0;
  if AButtonHeight < 1 then AButtonHeight := 1;
  x := AClient.Left;
  y := AClient.Top;
  rowRight := AClient.Right;
  for i := 0 to High(AButtonSizes) do
  begin
    // Wrap when this is not the first button on the row AND it would overrun the client
    // right edge. i>0 alone is not enough: the first-on-row test is "x = AClient.Left".
    if (x > AClient.Left) and (x + AButtonSizes[i].cx > rowRight) then
    begin
      x := AClient.Left;
      Inc(y, AButtonHeight + ASpacing);
    end;
    Result[i].Left := x;
    Result[i].Top := y;
    Result[i].Right := x + AButtonSizes[i].cx;
    Result[i].Bottom := y + AButtonHeight;
    Inc(x, AButtonSizes[i].cx + ASpacing);
  end;
end;

{ TTyCustomToolGroupPanel }

constructor TTyCustomToolGroupPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // csAcceptsControls is set by TTyGroupBox; keep it — this is a real container.
  FSpacing := 4;
  FButtonHeight := 26;
  Width := 220;
  Height := 92;
end;

function TTyCustomToolGroupPanel.GetStyleTypeKey: string;
begin
  Result := 'TyToolGroupPanel';
end;

procedure TTyCustomToolGroupPanel.SetSpacing(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if FSpacing = AValue then Exit;
  FSpacing := AValue;
  Relayout;
end;

procedure TTyCustomToolGroupPanel.SetButtonHeight(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FButtonHeight = AValue then Exit;
  FButtonHeight := AValue;
  Relayout;
end;

procedure TTyCustomToolGroupPanel.Relayout;
begin
  if csDestroying in ComponentState then Exit;
  Realign;      // re-runs AlignControls over the children
  Invalidate;
end;

procedure TTyCustomToolGroupPanel.AlignControls(AControl: TControl; var ARect: TRect);
var
  i, n: Integer;
  list: array of TControl;
  sizes: array of TSize;
  rects: TTyRectArray;
  cr: TRect;
  ctl: TControl;
  ppi, spacingPx, rowH: Integer;
begin
  // Re-entrancy guard: SetBounds on the children can loop back through AlignControls.
  if FInLayout then
  begin
    inherited AlignControls(AControl, ARect);
    Exit;
  end;
  FInLayout := True;
  try
    inherited AlignControls(AControl, ARect);   // let LCL align any alXxx children first

    // Collect visible, flow-eligible children (skip alClient/alTop/... anchored ones —
    // only alNone children participate in the manual flow, matching a ribbon group).
    SetLength(list, ControlCount); n := 0;
    for i := 0 to ControlCount - 1 do
    begin
      ctl := Controls[i];
      if ctl.Visible and (ctl.Align = alNone) then
      begin
        list[n] := ctl;
        Inc(n);
      end;
    end;
    if n = 0 then Exit;
    SetLength(list, n);
    SetLength(sizes, n);
    for i := 0 to n - 1 do
    begin
      sizes[i].cx := list[i].Width;
      sizes[i].cy := list[i].Height;
    end;

    // GetClientRect returns the RAW client rect — LCL applies AdjustClientRect only to ALIGNED
    // children, and our flowed buttons are alNone + placed by SetBounds. Inset it ourselves so
    // they drop below the caption band (else they paint over the group caption).
    cr := ClientRect;
    AdjustClientRect(cr);             // TTyGroupBox insets Top below the caption band
    { Spacing and ButtonHeight are LOGICAL px, as their declarations say; the client rect
      and the children's widths beside them are device px. And the row is as tall as the
      tallest child will really BE: SetBounds clamps a button up to its own floor, so rows
      pitched at the bare ButtonHeight ran into one another as soon as the floor was the
      taller of the two. }
    ppi := Font.PixelsPerInch;
    if ppi <= 0 then ppi := 96;
    spacingPx := MulDiv(FSpacing, ppi, 96);
    rowH := MulDiv(FButtonHeight, ppi, 96);
    for i := 0 to n - 1 do
      if list[i].Constraints.MinHeight > rowH then rowH := list[i].Constraints.MinHeight;
    rects := TyToolFlowRects(cr, sizes, spacingPx, rowH);
    for i := 0 to n - 1 do
      list[i].SetBounds(rects[i].Left, rects[i].Top, list[i].Width, rowH);
  finally
    FInLayout := False;
  end;
end;

function TTyCustomToolGroupPanel.AddButton(const ACaption: string; AOnClick: TNotifyEvent): TTyButton;
begin
  Result := TTyButton.Create(Self);
  Result.Parent := Self;
  Result.StyleClass := 'ghost';      // ribbon-group tool look
  Result.Caption := ACaption;
  Result.Height := MulDiv(FButtonHeight, Font.PixelsPerInch, 96);
  // Buttons added via AddButton are the USER's controls: do NOT mark csNoDesignVisible.
  if Assigned(AOnClick) then Result.OnClick := AOnClick;
  Relayout;
end;

end.
