unit tyControls.StatusBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller;
type
  TTyCustomStatusBar = class;
  TTyStatusBar = class;

  { How a panel's content is produced. psText (the default) draws the panel's own Text with
    the resolved theme style; psOwnerDraw hands the cell to the bar's OnDrawPanel and draws
    nothing itself. Named for LCL's TStatusPanelStyle (comctrls.pp:45) so a `Style :=
    psOwnerDraw` lifted out of a TStatusBar form compiles here unedited. }
  TTyStatusPanelStyle = (psText, psOwnerDraw);

  TTyStatusPanel = class(TCollectionItem)
  private
    FText: TCaption;
    FWidth: Integer;
    FAlignment: TAlignment;
    FStyle: TTyStatusPanelStyle;
    FControl: TControl;
    { The control's own size -- the one it had when the bar last found it at a size the bar
      had not given it -- and the size the bar last gave it (-1: not placed yet). A cell too
      small for the control shrinks it; this is how it gets its size back when the cell grows. }
    FOwnWidth, FOwnHeight: Integer;
    FPlacedWidth, FPlacedHeight: Integer;
    procedure SetText(const AValue: TCaption);
    procedure SetWidth(AValue: Integer);
    procedure SetAlignment(AValue: TAlignment);
    procedure SetStyle(AValue: TTyStatusPanelStyle);
    procedure SetControl(AValue: TControl);
    function OwnerBar: TTyCustomStatusBar;
    { The control's own size, in the bar's device px. }
    function ControlOwnSize: TSize;
  public
    constructor Create(ACollection: TCollection); override;
  published
    property Text: TCaption read FText write SetText;
    { LOGICAL px, like every other size a designer types into this library: the bar scales
      it by its PPI where it lays the panels out (TTyStatusBar.PanelWidthsPx). A value <= 0
      still means "take what is left". }
    property Width: Integer read FWidth write SetWidth default 50;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    { psOwnerDraw makes this cell the application's: the bar paints the panel background and
      separators as usual, then fires OnDrawPanel for the cell rect and draws no text of its
      own. That is how a lock icon or a coloured state dot gets into a status cell; a control
      of its own goes in through Control. }
    property Style: TTyStatusPanelStyle read FStyle write SetStyle default psText;
    { A control that lives in this panel: a spinner beside the text, a small button, a
      progress bar. Assigning it makes it a child of the bar, and the bar keeps it in the
      panel's cell from then on -- at the leading edge (the right one when the bar reads right
      to left), vertically centred, at its own size unless the cell is smaller. A psText
      panel's text starts after it, --statusbar-control-gap further on, and keeps its
      Alignment in the room that is left; a hidden control takes no room. One control serves
      one panel, and a control that is freed or moved to another parent leaves its panel. }
    property Control: TControl read FControl write SetControl;
  end;

  TTyStatusPanels = class(TOwnedCollection)
  private
    function GetItem(AIndex: Integer): TTyStatusPanel;
  protected
    procedure Update(Item: TCollectionItem); override;   // repaint owner on any panel change
  public
    function Add: TTyStatusPanel;
    property Items[AIndex: Integer]: TTyStatusPanel read GetItem; default;
  end;

  { Fired for a psOwnerDraw panel. APainter is the bar's LIVE painter, mid-pass -- draw
    through it, not through the bar's Canvas: a TTyPainter builds into a BGRA layer that
    EndPaint composites, so anything a handler put on the Canvas first would be overwritten.
    This is the same contract as TTyPaintPanel.OnPaintSurface, and the reason the signature
    carries a painter where LCL's TDrawPanelEvent (comctrls.pp:115) carries only a rect and
    expects the handler to reach for StatusBar.Canvas.

    ARect is the panel's cell in the bar's device-px, paint-local coordinates. }
  TTyDrawPanelEvent = procedure(AStatusBar: TTyCustomStatusBar; APanel: TTyStatusPanel;
    APainter: TTyPainter; const ARect: TRect) of object;

  { Fired when a panel is clicked; APanel.Index is its position. }
  TTyPanelClickEvent = procedure(Sender: TObject; APanel: TTyStatusPanel) of object;

  TTyCustomStatusBar = class(TTyCustomControl)
  private
    FPanels: TTyStatusPanels;
    FSimplePanel: Boolean;
    FSimpleText: string;
    FSizeGrip: Boolean;
    FAutoHint: Boolean;
    FOnHint: TNotifyEvent;
    FOnDrawPanel: TTyDrawPanelEvent;
    FOnPanelClick: TTyPanelClickEvent;
    FPressedPanelID: Integer;   // ID of the panel the left button went down on; -1 none
    FPlacing: Boolean;          // PlacePanelControls is moving the controls
    FPlacedSignature: string;   // where the panels' controls were last put, and which showed
    FSavedCursor: TCursor;
    FShowResizeCur: Boolean;
    procedure SetPanels(AValue: TTyStatusPanels);
    procedure SetSimplePanel(AValue: Boolean);
    procedure SetSimpleText(const AValue: TCaption);
    procedure SetSizeGrip(AValue: Boolean);
    function BarPPI: Integer;
    { The point is on the size grip as it is painted: the grip's corner box, when the grip
      is shown. }
    function OverSizeGrip(X, Y: Integer): Boolean;
    { What every text on the bar is drawn through: a panel's Text, SimpleText, DrawPanelText. }
    procedure DrawTextWith(APainter: TTyPainter; const AStyle: TTyStyleSet; AFontSize: Integer;
      const ARect: TRect; const AText: string; AAlignment: TAlignment);
    procedure CMBiDiModeChanged(var Message: TLMessage); message CM_BIDIMODECHANGED;
    procedure CMControlChange(var Message: TCMControlChange); message CM_CONTROLCHANGE;
  protected
    { #114: what AutoSize asks for -- see the body. }
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    function GetStyleTypeKey: string; override;
    { Which window-resize edge (0 = none) the point sits on, so the status bar -- which covers the
      form's bottom edge + the size-grip corner -- can hand the drag to the OS window resize.
      PROTECTED rather than private because it is the size grip's HIT TEST, and a hit test that
      no test can call is a hit test nobody checks against the paint: the live route to it
      (MouseMove's resize cursor) is gated on TyWindowResizable, i.e. on Windows and a real
      resizable handle, which a headless run never has. }
    function ResizeHitAt(X, Y: Integer): Integer;
    { #176: where the bar sits in its window -- on its bottom edge, and in the corner the grip is
      drawn in. The grip and the strip resize the WINDOW, so they only do it from there. }
    procedure WindowEdges(out ABottom, ACorner: Boolean);
    { #176: whether the grip is drawn: SizeGrip on, the window resizable and not maximized, and
      the bar in the window's corner. It was drawn on a window that could not be resized. }
    function GripShown: Boolean;
    { The two hint seams, as protected virtuals -- LCL's DoHint / DoSetApplicationHint
      (comctrls.pp:157-158). DoHint returns True when the application took the hint over
      via OnHint, in which case the bar writes nothing itself. }
    function DoHint: Boolean; virtual;
    function DoSetApplicationHint(const AHintStr: string): Boolean; virtual;
    { Fires OnDrawPanel for one psOwnerDraw cell. Protected virtual so a descendant can
      paint a cell without stealing the application's event slot. }
    procedure DrawPanel(APanel: TTyStatusPanel; APainter: TTyPainter; const ARect: TRect); virtual;
    { Fires OnPanelClick. Protected virtual so a descendant can act on a panel click without
      taking the application's event slot. }
    procedure DoPanelClick(APanel: TTyStatusPanel); virtual;
    { Hands a left press on the size grip or the bottom strip (AEdge: ResizeHitAt's answer) to
      the window, to be dragged as a resize; True when the window took it, and the press is
      then no click. Protected virtual so a descendant can resize its window another way, or
      not at all. }
    function StartWindowResize(AEdge: Integer): Boolean; virtual;
    { The panel a click at (X, Y) is a click on: the one PanelAtPos finds, unless the point is
      on the painted size grip or on a child control. nil when there is none. }
    function ClickPanelAt(X, Y: Integer): TTyStatusPanel;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { The panels' widths in DEVICE px at APPI -- what the paint and the hit test both lay
      the cells out from. }
    function PanelWidthsPx(APPI: Integer): TIntegerDynArray;
    { The panels' cells in a bar AWidth x AHeight device px at APPI: the one layout the paint,
      PanelAtPos, PanelRect and the panels' controls all read. Empty in SimplePanel mode. }
    function PanelCells(AWidth, AHeight, APPI: Integer; ARightToLeft: Boolean): TTyRectArray;
    { Inside ACell: the box APanel's Control goes in (empty without one) and the box its text
      is drawn in -- after the control when that is showing. }
    procedure PanelParts(APanel: TTyStatusPanel; const ACell: TRect; APPI: Integer;
      ARightToLeft: Boolean; out AControlBox, ATextBox: TRect);
    { Puts every panel's Control in its cell. Whatever moves the cells ends here: a resize, a
      panel's width, the PPI, the reading direction, SimplePanel, and each LCL layout pass. }
    procedure PlacePanelControls;
    { A panel was added, removed or changed. }
    procedure PanelsChanged;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Loaded; override;
    procedure BoundsChanged; override;
    procedure StyleLayoutChanged; override;
    procedure AlignControls(AControl: TControl; var RemainingClientRect: TRect); override;
    { The bar accepts controls and still draws its own content, so BorderWidth stays padding. }
    function BorderWidthIsPadding: Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PanelAtPos(X, Y: Integer): Integer;   // -1 outside any panel / SimplePanel mode
    { Panel AIndex's cell in client coordinates, exactly as it is painted and as PanelAtPos
      answers for it; it follows the reading direction. Empty for an index that is no panel
      and in SimplePanel mode. }
    function PanelRect(AIndex: Integer): TRect;
    { Where panel AIndex's text goes, in client coordinates: its cell less the text inset and
      less the room its Control takes. What a psOwnerDraw handler draws into to stay clear of
      the control. Empty where PanelRect is. }
    function PanelTextRect(AIndex: Integer): TRect;
    { The resolved style the bar draws panel text with -- its colour, font name and weight --
      for an OnDrawPanel handler that draws in the bar's own ink. }
    function PanelTextStyle: TTyStyleSet;
    { The font size of panel text, as a TTyPainter text call takes it (AFontSizeLogical). }
    function PanelFontSize: Integer;
    { The same size as a font height in device px at the bar's PPI, for a handler that sizes
      a glyph or an image to the text. }
    function PanelFontHeightPx: Integer;
    { Draws AText into ARect the way a psText panel draws its Text: PanelTextStyle's colour
      and font, vertically centred, AAlignment by reading order, cut with an ellipsis when it
      does not fit. Call it from OnDrawPanel with the painter the handler was given;
      PanelTextRect is the box a panel's own text gets. }
    procedure DrawPanelText(APainter: TTyPainter; const ARect: TRect; const AText: string;
      AAlignment: TAlignment = taLeftJustify);
    { LCL's name for PanelAtPos (comctrls.pp:171) -- same signature, same client-space
      coordinates, same -1 sentinel. It is an alias and not a rename because PanelAtPos
      is this library's own published surface and forms already call it; without the LCL
      spelling, `if StatusBar1.GetPanelIndexAt(X, Y) = 2 then` -- an idiom straight out of
      any ported OnMouseDown handler -- simply failed to compile. }
    function GetPanelIndexAt(X, Y: Integer): Integer;
    { The application-hint sink, LCL's contract exactly (statusbar.inc:268-269): the LCL
      dispatches a TCustomHintAction whenever Application.Hint changes, and a status bar
      with AutoHint on answers it by putting the text in SimpleText / panel 0.

      Which is what makes the hint of a highlighted MENU ITEM visible: the themed menu
      publishes it to Application.Hint, and until now nothing in this library listened. }
    function ExecuteAction(ExeAction: TBasicAction): Boolean; override;
    property Panels: TTyStatusPanels read FPanels write SetPanels;
    property SimplePanel: Boolean read FSimplePanel write SetSimplePanel default False;
    property SimpleText: TCaption read FSimpleText write SetSimpleText;
    property SizeGrip: Boolean read FSizeGrip write SetSizeGrip default True;
    { Show the application's current hint here as the pointer moves over hinted controls
      and highlighted menu items -- the classic status line. Off by default, as in LCL
      (comctrls.pp:179), because turning it on takes over SimpleText / panel 0. }
    property AutoHint: Boolean read FAutoHint write FAutoHint default False;
    { Assign this to format the hint yourself: it fires INSTEAD of the bar's own write, so
      a handler that wants "Ready — <hint>" in panel 2 has somewhere to put it. Reads
      Application.Hint for the text, as LCL's does. }
    property OnHint: TNotifyEvent read FOnHint write FOnHint;
    { Paints a psOwnerDraw panel. See TTyDrawPanelEvent for the painter contract. }
    property OnDrawPanel: TTyDrawPanelEvent read FOnDrawPanel write FOnDrawPanel;
    { A left click on a panel: the button went down and came up on the same one. Not fired
      for a press that resized the window (the size grip, the bottom strip), on the painted
      size grip, on a child control, or in SimplePanel mode. OnClick fires as it always did. }
    property OnPanelClick: TTyPanelClickEvent read FOnPanelClick write FOnPanelClick;
    property Align default alBottom;
  end;

  { TTyStatusBar publishes TTyCustomStatusBar's properties; everything lives in TTyCustomStatusBar. }
  TTyStatusBar = class(TTyCustomStatusBar)
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
    property Panels;
    property SimplePanel;
    property SimpleText;
    property SizeGrip;
    property AutoHint;
    property OnHint;
    property OnDrawPanel;
    property OnPanelClick;
    property Align;
    property Anchors;
  end;

{ ARightToLeft MIRRORS the finished tiling about the bar's vertical centre: panel 0 sits at
  the RIGHT edge and later panels follow leftwards, the fill panel absorbing the slack in the
  same place it did. Done as a reflection of the left-to-right result rather than as a
  reverse tiling loop, because the flush-to-both-edges property (the "last panel runs to the
  edge" rule below exists precisely to guarantee it) is preserved by a reflection for free
  and is exactly what a hand-written reverse loop loses to an off-by-one. }
function TyStatusPanelRects(const AWidths: array of Integer; ATotalWidth, APadding: Integer;
  ARightToLeft: Boolean = False): TTyRectArray;

{ The size grip's corner box in device px: an ASizePx square in the bar's TRAILING bottom
  corner — bottom-right on a left-to-right bar, bottom-LEFT on a mirrored one.

  ONE function because there used to be two. RenderTo laid its three dots out from
  `W - Scale(3) - k*Scale(4)` and ResizeHitAt tested `X >= W - grip`, in different functions,
  each an independent claim about which corner the grip is in — the shape that ships a
  handle drawn in one corner and grabbed in another. Both now take the corner from here and
  differ only in the SIZE they ask for: the hit zone is deliberately more generous than the
  ink, so the grip is grabbable a few px before the pointer is on a dot. }
function TyStatusGripRect(AWidth, AHeight, ASizePx: Integer;
  ARightToLeft: Boolean = False): TRect;

{ Device-px side of that corner at APPI — asked by the paint and by the hit test, so the box
  they share is the same box and not merely the same shape. }
function TyStatusGripZonePx(APPI: Integer): Integer;

implementation

uses
  Forms,                      // Application.Hint + TCustomHintAction (the hint-action sink)
  LCLStrConsts,               // LCL's own "a control can't have itself as a parent"
  tyControls.WindowEffects;   // TyStartNativeResize / TyWindowResizable (Windows-gated inside)

const
  CStatusBarPadX = 6;   // logical-px horizontal padding (panels + simple text)
  CStatusPanelInset = 2;   // logical px between a cell's edges and what is in it
  { The gap between a panel's control and its text when the theme has no
    --statusbar-control-gap (light.tycss carries the same 4). }
  CStatusControlGap = 4;
  { Logical-px side of the size-grip corner, and its device-px floor. The GRAB zone, which is
    deliberately larger than the three dots drawn inside it. }
  CStatusGripZone = 18;
  CStatusGripZoneMin = 14;
  { Win32 WM_NCHITTEST edge codes (== winuser.h), used to hand a bottom/corner drag to the OS. }
  cHTBOTTOM = 15; cHTBOTTOMLEFT = 16; cHTBOTTOMRIGHT = 17;

function TyStatusPanelRects(const AWidths: array of Integer; ATotalWidth, APadding: Integer;
  ARightToLeft: Boolean = False): TTyRectArray;
var
  i, x, fixed, fillIdx, fillW: Integer;
  span: TRect;
begin
  SetLength(Result, Length(AWidths));
  // total fixed width + locate the first fill (<=0) panel
  fixed := 0; fillIdx := -1;
  for i := 0 to High(AWidths) do
    if AWidths[i] > 0 then Inc(fixed, AWidths[i])
    else if fillIdx < 0 then fillIdx := i;
  fillW := ATotalWidth - 2*APadding - fixed;
  if fillW < 0 then fillW := 0;
  x := APadding;
  for i := 0 to High(AWidths) do
  begin
    Result[i].Left := x;
    Result[i].Top := 0;
    if AWidths[i] > 0 then Inc(x, AWidths[i])
    else if i = fillIdx then Inc(x, fillW);   // later <=0 panels add 0
    { The last panel always runs to the right edge, whatever width it was given --
      the native status bar does this (win32wscomctrls sets the final right to -1),
      and without it a bar whose widths do not happen to sum to the client width
      shows a strip of bare parent between the last panel and the frame. }
    if (i = High(AWidths)) and (x < ATotalWidth - APadding) then
      x := ATotalWidth - APadding;
    Result[i].Right := x;
    Result[i].Bottom := 0;   // caller sets vertical extent
  end;
  { MIRROR once, at the end, through LCL's own five-liner (controls.pp:2966) — so the two
    call sites that consume these rects (the hint hit test and the paint) get it from the
    same place and cannot be mirrored one without the other. }
  if ARightToLeft then
  begin
    span := Rect(0, 0, ATotalWidth, 0);
    for i := 0 to High(Result) do
      Result[i] := BidiFlipRect(Result[i], span, True);
  end;
end;

function TyStatusGripRect(AWidth, AHeight, ASizePx: Integer;
  ARightToLeft: Boolean = False): TRect;
begin
  if ASizePx < 0 then ASizePx := 0;
  Result := Rect(AWidth - ASizePx, AHeight - ASizePx, AWidth, AHeight);
  if ARightToLeft then
    Result := BidiFlipRect(Result, Rect(0, 0, AWidth, 0), True);
end;

function TyStatusGripZonePx(APPI: Integer): Integer;
begin
  Result := (CStatusGripZone * APPI) div 96;
  if Result < CStatusGripZoneMin then Result := CStatusGripZoneMin;
end;

{ TTyStatusPanel }
constructor TTyStatusPanel.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FWidth := 50;
  FAlignment := taLeftJustify;
end;
procedure TTyStatusPanel.SetText(const AValue: TCaption);
begin if FText = AValue then Exit; FText := AValue; Changed(False); end;
procedure TTyStatusPanel.SetWidth(AValue: Integer);
begin if FWidth = AValue then Exit; FWidth := AValue; Changed(False); end;
procedure TTyStatusPanel.SetAlignment(AValue: TAlignment);
begin if FAlignment = AValue then Exit; FAlignment := AValue; Changed(False); end;
procedure TTyStatusPanel.SetStyle(AValue: TTyStatusPanelStyle);
begin if FStyle = AValue then Exit; FStyle := AValue; Changed(False); end;

function TTyStatusPanel.OwnerBar: TTyCustomStatusBar;
begin
  if (Collection <> nil) and (Collection.Owner is TTyCustomStatusBar) then
    Result := TTyCustomStatusBar(Collection.Owner)
  else
    Result := nil;
end;

function TTyStatusPanel.ControlOwnSize: TSize;
begin
  Result.cx := 0;
  Result.cy := 0;
  if FControl = nil then Exit;
  { A size the bar did not give it is the control's own: the application set it, or the
    control resized itself. }
  if (FControl.Width <> FPlacedWidth) or (FControl.Height <> FPlacedHeight) then
  begin
    Result.cx := FControl.Width;
    Result.cy := FControl.Height;
  end
  else
  begin
    Result.cx := FOwnWidth;
    Result.cy := FOwnHeight;
  end;
end;

procedure TTyStatusPanel.SetControl(AValue: TControl);
var
  bar: TTyCustomStatusBar;
  other: TTyStatusPanel;
  i: Integer;
begin
  if FControl = AValue then Exit;
  bar := OwnerBar;
  if (AValue <> nil) and (bar <> nil) then
  begin
    { The bar cannot sit in itself, and neither can anything the bar sits in. While a form is
      being read the reference is dropped instead: a setter that raises there stops the whole
      form from loading. }
    if (AValue = bar) or ((AValue is TWinControl) and TWinControl(AValue).IsParentOf(bar)) then
    begin
      if csLoading in bar.ComponentState then Exit;
      raise EInvalidOperation.Create(rsAControlCanNotHaveItselfAsParent);
    end;
    { One control serves one panel. }
    for i := 0 to Collection.Count - 1 do
    begin
      other := TTyStatusPanel(Collection.Items[i]);
      if (other <> Self) and (other.FControl = AValue) then other.SetControl(nil);
    end;
    { The cell places it: an Align would have LCL place it as well. Then it becomes the bar's
      child, as LCL's TCoolBand.SetControl makes a band's control the cool bar's -- which also
      takes it out of a panel of another bar (that bar's CMControlChange). }
    AValue.Align := alNone;
    if AValue.Parent <> bar then AValue.Parent := bar;
  end;
  FControl := AValue;
  FPlacedWidth := -1;     // not placed yet: the size it comes with is its own
  FPlacedHeight := -1;
  Changed(False);
end;

{ TTyStatusPanels }
function TTyStatusPanels.GetItem(AIndex: Integer): TTyStatusPanel;
begin Result := TTyStatusPanel(inherited Items[AIndex]); end;
function TTyStatusPanels.Add: TTyStatusPanel;
begin Result := TTyStatusPanel(inherited Add); end;

procedure TTyStatusPanels.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if GetOwner is TTyCustomStatusBar then TTyCustomStatusBar(GetOwner).PanelsChanged;
end;

{ TTyCustomStatusBar }
constructor TTyCustomStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFitsToStyle := True;   // AutoSize follows the theme (#114)
  { A panel's Control is a child of the bar, so the designer has to be able to drop one in. }
  ControlStyle := ControlStyle + [csAcceptsControls];
  FPanels := TTyStatusPanels.Create(Self, TTyStatusPanel);
  FPressedPanelID := -1;
  FSizeGrip := True;
  Align := alBottom;
  Width := 200;
  Height := TyDensityHeight(ActiveController, 22);
end;

procedure TTyCustomStatusBar.CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
  WithThemeSpace: Boolean);
var
  S: TTyStyleSet;
  ppi, h: Integer;
begin
  { The bar's own height from the theme, or more when the font needs it; the width stays the
    form's. }
  ppi := Font.PixelsPerInch;
  if ppi <= 0 then ppi := 96;
  S := CurrentStyle;
  PreferredWidth := 0;
  PreferredHeight := MulDiv(TyDensityHeight(ActiveController, 22), ppi, 96);
  h := TyFieldPreferredHeight(S, ResolveFontSize(S), ppi);
  if h > PreferredHeight then PreferredHeight := h;
end;
destructor TTyCustomStatusBar.Destroy;
begin
  FPanels.Free;
  inherited Destroy;
end;
procedure TTyCustomStatusBar.SetPanels(AValue: TTyStatusPanels); begin FPanels.Assign(AValue); end;
procedure TTyCustomStatusBar.SetSimplePanel(AValue: Boolean);
begin
  if FSimplePanel = AValue then Exit;
  FSimplePanel := AValue;
  PlacePanelControls;   // the cells are gone, or back
  Invalidate;
end;
procedure TTyCustomStatusBar.SetSimpleText(const AValue: TCaption); begin if FSimpleText = AValue then Exit; FSimpleText := AValue; if FSimplePanel or (FPanels.Count = 0) then Invalidate; end;
procedure TTyCustomStatusBar.SetSizeGrip(AValue: Boolean); begin if FSizeGrip = AValue then Exit; FSizeGrip := AValue; Invalidate; end;

function TTyCustomStatusBar.GetStyleTypeKey: string;
begin Result := 'TyStatusBar'; end;

function TTyCustomStatusBar.DoHint: Boolean;
begin
  { LCL's rule (statusbar.inc:83-88): a handler is a TAKEOVER, not a notification -- when one
    is assigned the bar writes nothing of its own, because the handler's whole purpose is to
    decide where the text goes. }
  Result := Assigned(FOnHint);
  if Result then FOnHint(Self);
end;

function TTyCustomStatusBar.DoSetApplicationHint(const AHintStr: string): Boolean;
begin
  Result := DoHint;
  if Result then Exit;
  if FSimplePanel or (FPanels.Count = 0) then   // #128: a bar with no panels shows SimpleText
    SimpleText := AHintStr
  else
    FPanels[0].Text := AHintStr;
  Result := True;
end;

function TTyCustomStatusBar.ExecuteAction(ExeAction: TBasicAction): Boolean;
begin
  { The LCL turns every Application.Hint change into a TCustomHintAction and executes it
    against the focused control's chain (application.inc:1544-1556); a status bar is where
    that action is meant to land. Without AutoHint the action falls through to the normal
    action handling, so an ordinary TAction assigned to the bar still works. }
  if FAutoHint and (ExeAction is TCustomHintAction) then
    Result := DoSetApplicationHint(TCustomHintAction(ExeAction).Hint)
  else
    Result := inherited ExecuteAction(ExeAction);
end;

procedure TTyCustomStatusBar.DrawPanel(APanel: TTyStatusPanel; APainter: TTyPainter; const ARect: TRect);
begin
  if Assigned(FOnDrawPanel) then FOnDrawPanel(Self, APanel, APainter, ARect);
end;

function TTyCustomStatusBar.GetPanelIndexAt(X, Y: Integer): Integer;
begin
  Result := PanelAtPos(X, Y);
end;

function TTyCustomStatusBar.BarPPI: Integer;
begin
  Result := Font.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

function TTyCustomStatusBar.PanelCells(AWidth, AHeight, APPI: Integer;
  ARightToLeft: Boolean): TTyRectArray;
var
  i: Integer;
begin
  { ONE layout. PanelAtPos and the paint each called TyStatusPanelRects themselves, with a
    padding each of them scaled itself; an application that wanted a panel's rectangle had to
    do it a third time, with a copy of the padding. }
  Result := nil;
  if FSimplePanel or (FPanels.Count = 0) then Exit;
  if APPI <= 0 then APPI := 96;
  Result := TyStatusPanelRects(PanelWidthsPx(APPI), AWidth, MulDiv(CStatusBarPadX, APPI, 96),
    ARightToLeft);
  for i := 0 to High(Result) do
    Result[i].Bottom := AHeight;
end;

function TTyCustomStatusBar.PanelRect(AIndex: Integer): TRect;
var
  cells: TTyRectArray;
begin
  Result := Rect(0, 0, 0, 0);
  cells := PanelCells(ClientWidth, ClientHeight, BarPPI, IsRightToLeft);
  if (AIndex >= 0) and (AIndex <= High(cells)) then Result := cells[AIndex];
end;

function TTyCustomStatusBar.PanelAtPos(X, Y: Integer): Integer;
var
  cells: TTyRectArray;
  i: Integer;
begin
  Result := -1;
  cells := PanelCells(ClientWidth, ClientHeight, BarPPI, IsRightToLeft);
  for i := 0 to High(cells) do
    if PtInRect(cells[i], Types.Point(X, Y)) then Exit(i);
end;

procedure TTyCustomStatusBar.PanelParts(APanel: TTyStatusPanel; const ACell: TRect;
  APPI: Integer; ARightToLeft: Boolean; out AControlBox, ATextBox: TRect);
var
  inset, room, gap, w, h, cellH: Integer;
  own: TSize;
  c: TControl;
begin
  if APPI <= 0 then APPI := 96;
  inset := MulDiv(CStatusPanelInset, APPI, 96);
  ATextBox := Rect(ACell.Left + inset, ACell.Top, ACell.Right - inset, ACell.Bottom);
  AControlBox := Rect(ATextBox.Left, ACell.Top, ATextBox.Left, ACell.Top);
  c := APanel.Control;
  if c <> nil then
  begin
    { The control's size is in the bar's own device px; a paint at another PPI (a preview)
      scales it along with everything else. }
    own := APanel.ControlOwnSize;
    w := own.cx;
    h := own.cy;
    if APPI <> BarPPI then
    begin
      w := MulDiv(w, APPI, BarPPI);
      h := MulDiv(h, APPI, BarPPI);
    end;
    cellH := ACell.Bottom - ACell.Top;
    { At its own size unless the cell is smaller. An AutoSize control keeps its size: it
      would only take it back, and the two would resize it in turn on every layout pass. }
    if not c.AutoSize then
    begin
      room := ATextBox.Right - ATextBox.Left;
      if room < 0 then room := 0;
      if w > room then w := room;
      if h > cellH then h := cellH;
    end;
    { At the leading edge, where the text would start, and reflected inside the text box for
      a right-to-left bar -- so the control and the text can never trade places. }
    AControlBox := Bounds(ATextBox.Left, ACell.Top + (cellH - h) div 2, w, h);
    if ARightToLeft then AControlBox := BidiFlipRect(AControlBox, ATextBox, True);
    { A hidden control takes no room. IsControlVisible, not Visible: the designer shows a
      control whatever its Visible says, so there the text has to make room for it. }
    if c.IsControlVisible and (w > 0) then
    begin
      gap := MulDiv(StyleMetric('--statusbar-control-gap', CStatusControlGap), APPI, 96);
      if ARightToLeft then
        ATextBox.Right := AControlBox.Left - gap
      else
        ATextBox.Left := AControlBox.Right + gap;
    end;
  end;
  { No room at all -- a collapsed cell, or a control that fills its cell: an empty box at the
    end the text runs to, never one turned inside out. }
  if ATextBox.Right < ATextBox.Left then
  begin
    if ARightToLeft then
      ATextBox.Right := ATextBox.Left
    else
      ATextBox.Left := ATextBox.Right;
  end;
end;

function TTyCustomStatusBar.PanelTextRect(AIndex: Integer): TRect;
var
  cells: TTyRectArray;
  box: TRect;
begin
  Result := Rect(0, 0, 0, 0);
  cells := PanelCells(ClientWidth, ClientHeight, BarPPI, IsRightToLeft);
  if (AIndex < 0) or (AIndex > High(cells)) then Exit;
  PanelParts(FPanels[AIndex], cells[AIndex], BarPPI, IsRightToLeft, box, Result);
end;

procedure TTyCustomStatusBar.PlacePanelControls;
var
  cells: TTyRectArray;
  i, ppi: Integer;
  rtl: Boolean;
  p: TTyStatusPanel;
  c: TControl;
  box, txt: TRect;
  own: TSize;
  sig: string;
begin
  if FPlacing or (FPanels = nil) or ([csLoading, csDestroying] * ComponentState <> []) then
    Exit;
  sig := '';
  FPlacing := True;
  try
    ppi := BarPPI;
    rtl := IsRightToLeft;
    cells := PanelCells(ClientWidth, ClientHeight, ppi, rtl);
    for i := 0 to FPanels.Count - 1 do
    begin
      p := FPanels[i];
      c := p.Control;
      if c = nil then Continue;
      own := p.ControlOwnSize;   // read before the bar resizes it: see FOwnWidth
      p.FOwnWidth := own.cx;
      p.FOwnHeight := own.cy;
      if i <= High(cells) then
        PanelParts(p, cells[i], ppi, rtl, box, txt)
      else
        box := Rect(0, 0, 0, 0);   // SimplePanel mode: no cell, so no room
      { In the designer a cell with no room leaves the control as it is: what the designer
        shows is what the form file gets, and a control saved 0 x 0 has lost its own size. }
      if not (IsRectEmpty(box) and (csDesigning in ComponentState)) then
      begin
        c.SetBounds(box.Left, box.Top, box.Right - box.Left, box.Bottom - box.Top);
        p.FPlacedWidth := c.Width;    // read back: a constraint may have had its say
        p.FPlacedHeight := c.Height;
      end;
      sig := sig + Format('%d:%d,%d,%d,%d,%d;',
        [i, c.Left, c.Top, c.Width, c.Height, Ord(c.IsControlVisible)]);
    end;
  finally
    FPlacing := False;
  end;
  { A control that was shown, hidden, moved or resized changed the room its panel's text has,
    and its own invalidation covers only its own rectangle: repaint the bar. }
  if sig <> FPlacedSignature then
  begin
    FPlacedSignature := sig;
    Invalidate;
  end;
end;

procedure TTyCustomStatusBar.PanelsChanged;
begin
  PlacePanelControls;
  Invalidate;
end;

procedure TTyCustomStatusBar.Loaded;
begin
  inherited Loaded;
  PlacePanelControls;   // held back while the form was read
end;

procedure TTyCustomStatusBar.BoundsChanged;
begin
  inherited BoundsChanged;
  PlacePanelControls;
end;

procedure TTyCustomStatusBar.StyleLayoutChanged;
begin
  inherited StyleLayoutChanged;
  PlacePanelControls;   // the PPI came with the font
end;

procedure TTyCustomStatusBar.AlignControls(AControl: TControl; var RemainingClientRect: TRect);
begin
  { Every LCL layout pass comes through here -- a child was moved, resized, shown or hidden.
    After LCL's own pass, so the cell has the last word over an anchor. }
  inherited AlignControls(AControl, RemainingClientRect);
  PlacePanelControls;
end;

function TTyCustomStatusBar.BorderWidthIsPadding: Boolean;
begin
  Result := True;
end;

procedure TTyCustomStatusBar.CMBiDiModeChanged(var Message: TLMessage);
begin
  inherited;
  PlacePanelControls;   // the cells are mirrored
end;

procedure TTyCustomStatusBar.CMControlChange(var Message: TCMControlChange);
var
  i: Integer;
begin
  inherited;
  { A child that leaves the bar leaves its panel: one moved to another parent, and one that
    is freed, which LCL takes out of its parent first (TControl.Destroy). A control is in no
    panel before it is the bar's child, so the message that it arrived finds nothing; and a
    bar that is being destroyed lets its children go without this message. }
  for i := 0 to FPanels.Count - 1 do
    if FPanels[i].FControl = Message.Control then
      FPanels[i].SetControl(nil);
end;

function TTyCustomStatusBar.PanelTextStyle: TTyStyleSet;
begin
  Result := CurrentStyle;
end;

function TTyCustomStatusBar.PanelFontSize: Integer;
begin
  Result := ResolveFontSize(PanelTextStyle);
end;

function TTyCustomStatusBar.PanelFontHeightPx: Integer;
begin
  Result := TyFontHeightPx(PanelFontSize, BarPPI);
end;

procedure TTyCustomStatusBar.DrawTextWith(APainter: TTyPainter; const AStyle: TTyStyleSet;
  AFontSize: Integer; const ARect: TRect; const AText: string; AAlignment: TAlignment);
begin
  APainter.DrawText(ARect, AText, AStyle.FontName, AFontSize, AStyle.FontWeight,
    AStyle.TextColor, AAlignment, tlCenter, True);
end;

procedure TTyCustomStatusBar.DrawPanelText(APainter: TTyPainter; const ARect: TRect;
  const AText: string; AAlignment: TAlignment);
var
  S: TTyStyleSet;
begin
  if APainter = nil then Exit;
  S := PanelTextStyle;
  DrawTextWith(APainter, S, ResolveFontSize(S), ARect, AText, AAlignment);
end;

function TTyCustomStatusBar.PanelWidthsPx(APPI: Integer): TIntegerDynArray;
var
  i: Integer;
begin
  { ONE function for the hit test and the paint, so the cell that is drawn is the cell that
    is pointed at. The panel widths are logical px and used to go in RAW beside a ClientWidth
    and a padding that are device px -- the same number only at 96 PPI, so at 175% a panel
    designed 120 wide stayed 120 px while its text grew to 1.75x and was cut off. }
  Result := nil;
  if APPI <= 0 then APPI := 96;
  SetLength(Result, FPanels.Count);
  for i := 0 to FPanels.Count - 1 do
    Result[i] := MulDiv(FPanels[i].Width, APPI, 96);
end;

procedure TTyCustomStatusBar.Paint;
begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;

procedure TTyCustomStatusBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, i, padX, sepW, fs, bw, gx, gy, k: Integer;
  bg, grip: TTyFill;
  rects: TTyRectArray;
  rtl: Boolean;
  sep, gripBox, ctlBox, textBox: TRect;
begin
  P := TTyPainter.Create;
  try
    { MIRRORING: the panels tile from the right and the size grip moves to the bottom-LEFT.
      Both come from the same pure functions the hit tests use (TyStatusPanelRects,
      TyStatusGripRect), so there is no second copy of the geometry to forget. The panel
      texts' own Alignment is resolved by the painter, which is why arming it is the whole
      of that half. }
    rtl := IsRightToLeft;
    P.BeginPaint(ACanvas, ARect, APPI, rtl);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left; H := ARect.Bottom - ARect.Top;
    padX := P.Scale(CStatusBarPadX);
    fs := ResolveFontSize(S);
    // Lay the form's photo down FIRST so an alpha CSS background tints the photo (glass),
    // like TTyPanel. No-op (False) on solid/non-image themes -> their look is unchanged.
    FillSharpBackdrop(P, Rect(0, 0, W, H));
    // background fill (whole) + a 1px top border line (status-bar look — not a full frame).
    // Paint S.Background directly (not a solid bg.Color rebuild) so an alpha() background is
    // honored OVER the backdrop instead of replacing it with an opaque tint.
    bg := Default(TTyFill); bg.Kind := tfkSolid;
    if tpBackground in S.Present then P.FillBackground(Rect(0, 0, W, H), S.Background, 0);
    bw := P.Scale(S.BorderWidth); if bw < 1 then bw := 1;
    if tpBorderColor in S.Present then
    begin
      bg.Color := S.BorderColor;
      P.FillBackground(Rect(0, 0, W, bw), bg, 0);   // top hairline
    end;
    { #128: SimpleText also on a bar with no panels -- SimplePanel defaults to False here (True
      in LCL), so a bar that was only ever given SimpleText showed nothing at all. }
    if FSimplePanel or (FPanels.Count = 0) then
      DrawTextWith(P, S, fs, Rect(padX, 0, W - padX, H), FSimpleText, taLeftJustify)
    else
    begin
      rects := PanelCells(W, H, APPI, rtl);
      sepW := P.Scale(1); if sepW < 1 then sepW := 1;
      for i := 0 to High(rects) do
      begin
        if (i > 0) and (tpBorderColor in S.Present) then   // separator before each panel after the first (only when border color is present)
        begin
          bg.Color := S.BorderColor;
          { The rule sits on the panel's LEADING edge — reflected inside the cell rather than
            restated for the mirrored case, so it can never end up drawn over the neighbour. }
          sep := Rect(rects[i].Left, P.Scale(3), rects[i].Left + sepW, H - P.Scale(3));
          if rtl then sep := BidiFlipRect(sep, rects[i], True);
          P.FillBackground(sep, bg, 0);
        end;
        { An owner-drawn cell belongs to the application: the bar keeps painting the chrome
          around it (background, the separator rules, the size grip) and hands over the cell
          itself instead of drawing text into it. Fired HERE, inside the pass and through the
          painter, so what the handler draws is composited with everything else -- drawing to
          the Canvas from a handler would be wiped by EndPaint (see TTyDrawPanelEvent). }
        if FPanels[i].Style = psOwnerDraw then
        begin
          DrawPanel(FPanels[i], P, rects[i]);
          Continue;
        end;
        { The text starts after the panel's control, when it has one that is showing. }
        PanelParts(FPanels[i], rects[i], APPI, rtl, ctlBox, textBox);
        DrawTextWith(P, S, fs, textBox, FPanels[i].Text, FPanels[i].Alignment);
      end;
    end;
    if GripShown then    // 3 diagonal dots in the trailing bottom corner, in muted text color
    begin
      grip := Default(TTyFill); grip.Kind := tfkSolid; grip.Color := S.TextColor;
      { The corner comes from the SAME function ResizeHitAt asks — it used to be restated
        here as a bare `W - ...`, which is how a grip gets drawn in one corner and grabbed
        in the other. The dots are laid out against the box's own far corner and reflected
        INSIDE it, so they stay in the zone the hit test answers for whichever way it reads. }
      gripBox := TyStatusGripRect(W, H, TyStatusGripZonePx(APPI), rtl);
      for k := 0 to 2 do
      begin
        gx := gripBox.Right - P.Scale(3) - k*P.Scale(4);
        gy := gripBox.Bottom - P.Scale(3) - k*P.Scale(4);
        sep := Rect(gx, gy, gx + P.Scale(2), gy + P.Scale(2));
        if rtl then sep := BidiFlipRect(sep, gripBox, True);
        P.FillBackground(sep, grip, 1);   // the radius is LOGICAL: the painter scales it
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomStatusBar.WindowEdges(out ABottom, ACorner: Boolean);
var
  f: TCustomForm;
begin
  ABottom := False;
  ACorner := False;
  f := GetParentForm(Self);
  if f = nil then Exit;
  ABottom := Abs(ClientToParent(Types.Point(0, Height), f).Y - f.ClientHeight) <= 1;
  if not ABottom then Exit;
  if IsRightToLeft then
    ACorner := ClientToParent(Types.Point(0, 0), f).X <= 1
  else
    ACorner := Abs(ClientToParent(Types.Point(Width, 0), f).X - f.ClientWidth) <= 1;
end;

function TTyCustomStatusBar.GripShown: Boolean;
var
  f: TCustomForm;
  atBottom, atCorner: Boolean;
begin
  Result := FSizeGrip;
  if not Result then Exit;
  if csDesigning in ComponentState then Exit;   // the designer shows what was set
  f := GetParentForm(Self);
  if f = nil then Exit;                         // drawn on its own (a preview): as set
  if f.WindowState = wsMaximized then Exit(False);
  if not ((f.BorderStyle in [bsSizeable, bsSizeToolWin]) or TyWindowResizable(Self)) then
    Exit(False);
  WindowEdges(atBottom, atCorner);
  Result := atCorner;
end;

function TTyCustomStatusBar.ResizeHitAt(X, Y: Integer): Integer;
var
  zone, W, H: Integer;
  gripBox: TRect;
  rtl, atBottom, atCorner: Boolean;
begin
  Result := 0;
  { #176: SizeGrip off, nothing on the bar resizes the window -- the strip along the bottom still
    did -- and on, only the parts of it that lie on the window's own edge. }
  if not FSizeGrip then Exit;
  WindowEdges(atBottom, atCorner);
  if not atBottom then Exit;
  W := Width; H := Height;
  rtl := IsRightToLeft;
  zone := (5 * Font.PixelsPerInch) div 96;   if zone < 4 then zone := 4;   // bottom-edge strip
  { The grip corner, from the one function RenderTo draws it in. Mirrored, the grip is in the
    bottom-LEFT corner and the drag it hands the OS is that corner's edge code — the bare
    cHTBOTTOMRIGHT here was the second half of the two-copies problem. Bounded on the INNER
    edges only, exactly as the old `X >= W - grip` was: a pointer that has run past the bar's
    own edge during a drag is still on the grip.
    The plain bottom-edge strip below is NOT mirrored: its two branches name real WINDOW
    corners, and the bottom-left corner of a window resizes bottom-left whichever way the
    bar inside it happens to read. }
  gripBox := TyStatusGripRect(W, H, TyStatusGripZonePx(Font.PixelsPerInch), rtl);
  if atCorner and (Y >= gripBox.Top)
     and (((not rtl) and (X >= gripBox.Left)) or (rtl and (X < gripBox.Right))) then
  begin
    if rtl then Result := cHTBOTTOMLEFT else Result := cHTBOTTOMRIGHT;
  end
  else if Y >= H - zone then
  begin
    if X <= zone then Result := cHTBOTTOMLEFT
    else if X >= W - zone then Result := cHTBOTTOMRIGHT
    else Result := cHTBOTTOM;
  end;
end;

procedure TTyCustomStatusBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  pressed: TTyStatusPanel;
begin
  { The status bar covers the form's bottom edge, so the OS never sees a resize-border hit there.
    On the size grip / bottom edge, hand the drag to the OS window resize the way any custom resize
    grip does (Windows-only, resizable, non-maximized -- all gated inside TyStartNativeResize). }
  if Button = mbLeft then FPressedPanelID := -1;
  if (Button = mbLeft) and StartWindowResize(ResizeHitAt(X, Y)) then
    Exit;   // the OS now owns the drag; don't run the normal click path
  if Button = mbLeft then
  begin
    pressed := ClickPanelAt(X, Y);
    if pressed <> nil then FPressedPanelID := pressed.ID;
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyCustomStatusBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  id: Integer;
  released: TTyStatusPanel;
begin
  id := -1;
  if Button = mbLeft then
  begin
    id := FPressedPanelID;
    FPressedPanelID := -1;
  end;
  { OnMouseUp first, and the bar's own pressed state put down: a panel click is where an
    application opens a menu or a dialog, and that should not run in the middle of a release. }
  inherited MouseUp(Button, Shift, X, Y);
  if id < 0 then Exit;
  { The panel is remembered by its ID, not its index: a handler that ran between the press
    and the release may have added or removed panels, and the one under the pointer now is
    then not the one that was pressed. }
  released := ClickPanelAt(X, Y);
  if (released <> nil) and (released.ID = id) then DoPanelClick(released);
end;

function TTyCustomStatusBar.StartWindowResize(AEdge: Integer): Boolean;
begin
  Result := TyStartNativeResize(Self, AEdge);
end;

function TTyCustomStatusBar.OverSizeGrip(X, Y: Integer): Boolean;
begin
  Result := GripShown and PtInRect(
    TyStatusGripRect(Width, Height, TyStatusGripZonePx(BarPPI), IsRightToLeft),
    Types.Point(X, Y));
end;

function TTyCustomStatusBar.ClickPanelAt(X, Y: Integer): TTyStatusPanel;
var
  i: Integer;
begin
  Result := nil;
  i := PanelAtPos(X, Y);
  if i < 0 then Exit;
  { The grip is the window's, also where pressing it resizes nothing (the bar starts a resize
    on Windows only): it is painted over the last panel, not part of it. }
  if OverSizeGrip(X, Y) then Exit;
  { LCL hands a press on an enabled child to that child and the bar never sees it. A
    disabled one it does not: that press arrives here, on a point the child covers. }
  if ControlAtPos(Types.Point(X, Y), [capfAllowDisabled, capfAllowWinControls]) <> nil then
    Exit;
  Result := FPanels[i];
end;

procedure TTyCustomStatusBar.DoPanelClick(APanel: TTyStatusPanel);
begin
  if Assigned(FOnPanelClick) then FOnPanelClick(Self, APanel);
end;

procedure TTyCustomStatusBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  cur: TCursor;
begin
  cur := crDefault;
  if TyWindowResizable(Self) then
    case ResizeHitAt(X, Y) of
      cHTBOTTOM:      cur := crSizeNS;
      cHTBOTTOMRIGHT: cur := crSizeNWSE;
      cHTBOTTOMLEFT:  cur := crSizeNESW;
    end;
  { Show the resize cursor over a resize zone; restore the control's own cursor on leaving,
    without permanently clobbering it (a control that blindly writes crDefault destroys the
    app's chosen cursor -- see the ListView cursor-restore rule). }
  if cur <> crDefault then
  begin
    if not FShowResizeCur then begin FSavedCursor := Cursor; FShowResizeCur := True; end;
    if Cursor <> cur then Cursor := cur;
  end
  else if FShowResizeCur then
  begin
    Cursor := FSavedCursor;
    FShowResizeCur := False;
  end;
  inherited MouseMove(Shift, X, Y);
end;

procedure TTyCustomStatusBar.MouseLeave;
begin
  if FShowResizeCur then
  begin
    Cursor := FSavedCursor;
    FShowResizeCur := False;
  end;
  inherited MouseLeave;
end;

end.
