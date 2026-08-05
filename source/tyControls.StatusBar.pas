unit tyControls.StatusBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller;
type
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
    procedure SetText(const AValue: TCaption);
    procedure SetWidth(AValue: Integer);
    procedure SetAlignment(AValue: TAlignment);
    procedure SetStyle(AValue: TTyStatusPanelStyle);
  public
    constructor Create(ACollection: TCollection); override;
  published
    property Text: TCaption read FText write SetText;
    property Width: Integer read FWidth write SetWidth default 50;
    property Alignment: TAlignment read FAlignment write SetAlignment default taLeftJustify;
    { psOwnerDraw makes this cell the application's: the bar paints the panel background and
      separators as usual, then fires OnDrawPanel for the cell rect and draws no text of its
      own. That is the only way to put a progress bar, a lock icon or a coloured state dot in
      a status cell -- before this, a panel could be plain text and nothing else. }
    property Style: TTyStatusPanelStyle read FStyle write SetStyle default psText;
  end;

  TTyStatusBar = class;

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
  TTyDrawPanelEvent = procedure(AStatusBar: TTyStatusBar; APanel: TTyStatusPanel;
    APainter: TTyPainter; const ARect: TRect) of object;

  TTyStatusBar = class(TTyCustomControl)
  private
    FPanels: TTyStatusPanels;
    FSimplePanel: Boolean;
    FSimpleText: string;
    FSizeGrip: Boolean;
    FAutoHint: Boolean;
    FOnHint: TNotifyEvent;
    FOnDrawPanel: TTyDrawPanelEvent;
    FSavedCursor: TCursor;
    FShowResizeCur: Boolean;
    procedure SetPanels(AValue: TTyStatusPanels);
    procedure SetSimplePanel(AValue: Boolean);
    procedure SetSimpleText(const AValue: string);
    procedure SetSizeGrip(AValue: Boolean);
  protected
    function GetStyleTypeKey: string; override;
    { Which window-resize edge (0 = none) the point sits on, so the status bar -- which covers the
      form's bottom edge + the size-grip corner -- can hand the drag to the OS window resize.
      PROTECTED rather than private because it is the size grip's HIT TEST, and a hit test that
      no test can call is a hit test nobody checks against the paint: the live route to it
      (MouseMove's resize cursor) is gated on TyWindowResizable, i.e. on Windows and a real
      resizable handle, which a headless run never has. }
    function ResizeHitAt(X, Y: Integer): Integer;
    { The two hint seams, as protected virtuals -- LCL's DoHint / DoSetApplicationHint
      (comctrls.pp:157-158). DoHint returns True when the application took the hint over
      via OnHint, in which case the bar writes nothing itself. }
    function DoHint: Boolean; virtual;
    function DoSetApplicationHint(const AHintStr: string): Boolean; virtual;
    { Fires OnDrawPanel for one psOwnerDraw cell. Protected virtual so a descendant can
      paint a cell without stealing the application's event slot. }
    procedure DrawPanel(APanel: TTyStatusPanel; APainter: TTyPainter; const ARect: TRect); virtual;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PanelAtPos(X, Y: Integer): Integer;   // -1 outside any panel / SimplePanel mode
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
  published
    property Panels: TTyStatusPanels read FPanels write SetPanels;
    property SimplePanel: Boolean read FSimplePanel write SetSimplePanel default False;
    property SimpleText: string read FSimpleText write SetSimpleText;
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
    property Align default alBottom;
    property Anchors;
    property StyleClass;
    property Controller;
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
  tyControls.WindowEffects;   // TyStartNativeResize / TyWindowResizable (Windows-gated inside)

const
  CStatusBarPadX = 6;   // logical-px horizontal padding (panels + simple text)
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

{ TTyStatusPanels }
function TTyStatusPanels.GetItem(AIndex: Integer): TTyStatusPanel;
begin Result := TTyStatusPanel(inherited Items[AIndex]); end;
function TTyStatusPanels.Add: TTyStatusPanel;
begin Result := TTyStatusPanel(inherited Add); end;

procedure TTyStatusPanels.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if GetOwner is TTyStatusBar then TTyStatusBar(GetOwner).Invalidate;
end;

{ TTyStatusBar }
constructor TTyStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPanels := TTyStatusPanels.Create(Self, TTyStatusPanel);
  FSizeGrip := True;
  Align := alBottom;
  Width := 200;
  Height := TyDensityHeight(ActiveController, 22);
end;
destructor TTyStatusBar.Destroy;
begin
  FPanels.Free;
  inherited Destroy;
end;
procedure TTyStatusBar.SetPanels(AValue: TTyStatusPanels); begin FPanels.Assign(AValue); end;
procedure TTyStatusBar.SetSimplePanel(AValue: Boolean); begin if FSimplePanel = AValue then Exit; FSimplePanel := AValue; Invalidate; end;
procedure TTyStatusBar.SetSimpleText(const AValue: string); begin if FSimpleText = AValue then Exit; FSimpleText := AValue; if FSimplePanel then Invalidate; end;
procedure TTyStatusBar.SetSizeGrip(AValue: Boolean); begin if FSizeGrip = AValue then Exit; FSizeGrip := AValue; Invalidate; end;

function TTyStatusBar.GetStyleTypeKey: string;
begin Result := 'TyStatusBar'; end;

function TTyStatusBar.DoHint: Boolean;
begin
  { LCL's rule (statusbar.inc:83-88): a handler is a TAKEOVER, not a notification -- when one
    is assigned the bar writes nothing of its own, because the handler's whole purpose is to
    decide where the text goes. }
  Result := Assigned(FOnHint);
  if Result then FOnHint(Self);
end;

function TTyStatusBar.DoSetApplicationHint(const AHintStr: string): Boolean;
begin
  Result := DoHint;
  if Result then Exit;
  if FSimplePanel then
    SimpleText := AHintStr
  else if FPanels.Count > 0 then
    FPanels[0].Text := AHintStr;
  Result := True;
end;

function TTyStatusBar.ExecuteAction(ExeAction: TBasicAction): Boolean;
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

procedure TTyStatusBar.DrawPanel(APanel: TTyStatusPanel; APainter: TTyPainter; const ARect: TRect);
begin
  if Assigned(FOnDrawPanel) then FOnDrawPanel(Self, APanel, APainter, ARect);
end;

function TTyStatusBar.GetPanelIndexAt(X, Y: Integer): Integer;
begin
  Result := PanelAtPos(X, Y);
end;

function TTyStatusBar.PanelAtPos(X, Y: Integer): Integer;
var
  rects: TTyRectArray;
  ws: array of Integer;
  i: Integer;
begin
  Result := -1;
  if FSimplePanel or (FPanels.Count = 0) then Exit;
  if (Y < 0) or (Y >= ClientHeight) then Exit;
  SetLength(ws, FPanels.Count);
  for i := 0 to FPanels.Count - 1 do ws[i] := FPanels[i].Width;
  rects := TyStatusPanelRects(ws, ClientWidth, MulDiv(CStatusBarPadX, Font.PixelsPerInch, 96),
    IsRightToLeft);
  for i := 0 to High(rects) do
    if (X >= rects[i].Left) and (X < rects[i].Right) then Exit(i);
end;

procedure TTyStatusBar.Paint;
begin RenderTo(Canvas, ClientRect, Font.PixelsPerInch); end;

procedure TTyStatusBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, i, padX, sepW, fs, bw, gx, gy, k: Integer;
  bg, grip: TTyFill;
  rects: TTyRectArray;
  ws: array of Integer;
  rtl: Boolean;
  sep, gripBox: TRect;
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
    if FSimplePanel then
      P.DrawText(Rect(padX, 0, W - padX, H), FSimpleText, S.FontName, fs, S.FontWeight, S.TextColor, taLeftJustify, tlCenter, True)
    else
    begin
      SetLength(ws, FPanels.Count);
      for i := 0 to FPanels.Count - 1 do ws[i] := FPanels[i].Width;
      rects := TyStatusPanelRects(ws, W, padX, rtl);
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
          DrawPanel(FPanels[i], P, Rect(rects[i].Left, 0, rects[i].Right, H));
          Continue;
        end;
        P.DrawText(Rect(rects[i].Left + P.Scale(2), 0, rects[i].Right - P.Scale(2), H),
          FPanels[i].Text, S.FontName, fs, S.FontWeight, S.TextColor, FPanels[i].Alignment, tlCenter, True);
      end;
    end;
    if FSizeGrip then    // 3 diagonal dots in the trailing bottom corner, in muted text color
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
        P.FillBackground(sep, grip, P.Scale(1));
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

function TTyStatusBar.ResizeHitAt(X, Y: Integer): Integer;
var
  zone, W, H: Integer;
  gripBox: TRect;
  rtl: Boolean;
begin
  Result := 0;
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
  if FSizeGrip and (Y >= gripBox.Top)
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

procedure TTyStatusBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  { The status bar covers the form's bottom edge, so the OS never sees a resize-border hit there.
    On the size grip / bottom edge, hand the drag to the OS window resize the way any custom resize
    grip does (Windows-only, resizable, non-maximized -- all gated inside TyStartNativeResize). }
  if (Button = mbLeft) and TyStartNativeResize(Self, ResizeHitAt(X, Y)) then
    Exit;   // the OS now owns the drag; don't run the normal click path
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyStatusBar.MouseMove(Shift: TShiftState; X, Y: Integer);
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

procedure TTyStatusBar.MouseLeave;
begin
  if FShowResizeCur then
  begin
    Cursor := FSavedCursor;
    FShowResizeCur := False;
  end;
  inherited MouseLeave;
end;

end.
