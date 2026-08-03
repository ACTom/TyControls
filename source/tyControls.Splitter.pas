unit tyControls.Splitter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTySplitterCanResizeEvent = procedure(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean) of object;

  { The live feedback bar the deferred resize styles (rsLine, rsPattern) show while the
    button is held. It is a transient SIBLING WINDOW rather than a paint on the parent's
    DC because on Win32 a parent's DC is clipped by its child windows -- a band drawn
    there would disappear behind the very panes it is previewing.
    Runtime-only: created on MouseDown, freed on MouseUp, so it never reaches the
    streamer or the designer. }
  TTySplitterBand = class(TTyCustomControl)
  private
    FBandColor: TTyColor;
    FPatterned: Boolean;
    FAlongY: Boolean;
    procedure SetBandColor(AValue: TTyColor);
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    property BandColor: TTyColor read FBandColor write SetBandColor;
    property Patterned: Boolean read FPatterned write FPatterned;  // rsPattern: dashes, not a solid bar
    property AlongY: Boolean read FAlongY write FAlongY;           // dash run direction (a tall bar dashes vertically)
  end;

  TTySplitter = class(TTyCustomControl)
  private
    FMinSize: Integer;
    FAutoSnap: Boolean;
    FResizeStyle: TResizeStyle;
    FOnCanResize: TTySplitterCanResizeEvent;
    FOnMoved: TNotifyEvent;
    FTarget: TControl;
    FDragging: Boolean;
    FMouseStart: Integer;     // mouse coord (screen-axis) at drag start
    FStartSize: Integer;      // target size at drag start
    FBand: TTySplitterBand;   // nil unless a deferred drag is showing feedback
    function Vertical: Boolean;     // a left/right splitter resizes horizontally
    function FindResizeTarget: TControl;
    function AxisSize(AControl: TControl): Integer;
    function NegotiateSize(ADelta: Integer; out ANewSize: Integer): Boolean;
    procedure ApplySize(ADelta: Integer);
    procedure ShowBand;
    procedure MoveBand(ADelta: Integer);
    procedure HideBand;
    procedure SetMinSize(AValue: Integer);
    procedure UpdateCursor;
  protected
    { nil unless rsLine/rsPattern is mid-drag. Protected so a descendant (and the
      guard tests) can see the feedback without it becoming public API. }
    property DragBand: TTySplitterBand read FBand;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { Enabled feeds the cursor now, so the cursor has to be re-derived when Enabled
      changes -- otherwise the fix only lands on the next MouseEnter, and a splitter
      disabled while the pointer is already over it keeps promising a drag. }
    procedure CMEnabledChanged(var Message: TLMessage); message CM_ENABLEDCHANGED;
    procedure Loaded; override;      // re-derive the cursor after Align streams in
    procedure MouseEnter; override;  // re-derive the cursor when Align was set at RUNTIME (code-created)
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property MinSize: Integer read FMinSize write SetMinSize default 30;
    { Drag a pane past MinSize and it closes, instead of sticking at MinSize with the
      pointer running on without it. Without this there is NO gesture that collapses a
      pane -- MinSize is a floor the drag can never get under, so "drag the sidebar
      shut", which is what a splitter is for half the time, was simply not available.
      LCL ships it on (extctrls.pp AutoSnap default true). }
    property AutoSnap: Boolean read FAutoSnap write FAutoSnap default True;
    property ResizeStyle: TResizeStyle read FResizeStyle write FResizeStyle default rsUpdate;
    property OnCanResize: TTySplitterCanResizeEvent read FOnCanResize write FOnCanResize;
    property OnMoved: TNotifyEvent read FOnMoved write FOnMoved;
    property Align default alLeft;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ AAutoSnap: when the drag lands below AMinSize, collapse to 0 rather than pinning at
  AMinSize. Off, the pane can never be closed by dragging. }
function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer;
  AAutoSnap: Boolean = True): Integer;
{ Bar travel for a given FINAL pane size, with the alRight/alBottom sign inversion. Fed
  the already-clamped size, so the preview band stops exactly where the pane stops. }
function TySplitterBarOffset(AAlign: TAlign; AStartSize, ANewSize: Integer): Integer;

implementation

function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer;
  AAutoSnap: Boolean = True): Integer;
begin
  case AAlign of
    alRight, alBottom: Result := AStartSize - ADelta;
  else
    Result := AStartSize + ADelta;
  end;
  if Result < AMinSize then
  begin
    if AAutoSnap then Result := 0 else Result := AMinSize;
  end;
  if (AMaxSize >= AMinSize) and (Result > AMaxSize) then Result := AMaxSize;
end;

{ How far the BAR travels when the pane it drives ends up ANewSize. Fed the size that
  TySplitterNewSize already clamped, so the feedback band stops exactly where the resize
  stops -- without this the band would keep sliding past MinSize while the mouse does,
  then snap somewhere else on release. }
function TySplitterBarOffset(AAlign: TAlign; AStartSize, ANewSize: Integer): Integer;
begin
  Result := ANewSize - AStartSize;
  // alRight/alBottom panes grow AWAY from the pointer, so the pane's size change and the
  // bar's travel carry opposite signs.
  if AAlign in [alRight, alBottom] then Result := -Result;
end;

{ TTySplitterBand }

constructor TTySplitterBand.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // It lives only between MouseDown and MouseUp; keep it out of the designer's reach
  // in case a host ever creates one while designing.
  ControlStyle := ControlStyle + [csNoDesignVisible];
end;

{ Deliberately the SPLITTER's key: the band is the splitter's own preview, so it takes the
  splitter's resolved colour and a theme recolours both at once. Inventing a band-only key
  would need an entry in every shipped theme before it resolved to anything. }
function TTySplitterBand.GetStyleTypeKey: string;
begin
  Result := 'TySplitter';
end;

procedure TTySplitterBand.SetBandColor(AValue: TTyColor);
begin
  FBandColor := AValue;
  // A windowed control erases to its LCL Color before Paint runs. Left at the parent's
  // colour, the band flashes the pane's background on every move of the drag.
  Color := TyColorToLCL(AValue);
end;

procedure TTySplitterBand.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTySplitterBand.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  bar: TTyFill;
  W, H, seg, step, i, e: Integer;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    bar := Default(TTyFill);
    bar.Kind := tfkSolid;
    bar.Color := FBandColor;
    if not FPatterned then
      P.FillBackground(Rect(0, 0, W, H), bar, 0)
    else
    begin
      // rsPattern is rsLine's dotted twin: same bar, drawn as dashes so it reads as a
      // preview rather than as a pane edge that is already there.
      seg := P.Scale(3);
      if seg < 1 then seg := 1;      // a sub-1px dash would erase the band entirely on small PPI
      step := seg * 2;
      i := 0;
      if FAlongY then
        while i < H do
        begin
          e := i + seg;
          if e > H then e := H;
          P.FillBackground(Rect(0, i, W, e), bar, 0);
          Inc(i, step);
        end
      else
        while i < W do
        begin
          e := i + seg;
          if e > W then e := W;
          P.FillBackground(Rect(i, 0, e, H), bar, 0);
          Inc(i, step);
        end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

constructor TTySplitter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMinSize := 30;
  FAutoSnap := True;
  FResizeStyle := rsUpdate;
  Align := alLeft;
  Width := 5;
  Height := 100;
  UpdateCursor;
end;

function TTySplitter.GetStyleTypeKey: string;
begin
  Result := 'TySplitter';
end;

function TTySplitter.Vertical: Boolean;
begin
  // Returns True when the splitter BAR is vertical (Align in [alLeft, alRight]),
  // i.e. it resizes the neighbour's WIDTH via a horizontal drag.
  Result := Align in [alLeft, alRight];
end;

procedure TTySplitter.UpdateCursor;
begin
  { A disabled splitter must not advertise a drag it will refuse. It kept showing the
    resize cursor, so the pointer promised a drag over a control that ignores MouseDown --
    the user pulls, nothing moves, and there is nothing on screen saying why. LCL
    re-derives the cursor from Enabled for the same reason. }
  if not Enabled then
    Cursor := crDefault
  else if Vertical then
    Cursor := crHSplit
  else
    Cursor := crVSplit;
end;

procedure TTySplitter.CMEnabledChanged(var Message: TLMessage);
begin
  inherited;
  UpdateCursor;
end;

procedure TTySplitter.Loaded;
begin
  inherited Loaded;
  UpdateCursor;
end;

procedure TTySplitter.MouseEnter;
begin
  inherited MouseEnter;
  { The cursor is derived from Align. Loaded covers streamed (.lfm) splitters, but a
    code-created splitter that sets Align AFTER construction (e.g. Align:=alTop for a
    horizontal bar) never re-derived it and kept the constructor's alLeft cursor.
    Re-derive on hover so the resize cursor always matches the current Align. }
  UpdateCursor;
end;

procedure TTySplitter.SetMinSize(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  FMinSize := AValue;
end;

function TTySplitter.AxisSize(AControl: TControl): Integer;
begin
  if Vertical then Result := AControl.Width else Result := AControl.Height;
end;

// Mirror TCustomSplitter: the resized control is the sibling immediately on the
// anchored side of the splitter (left of an alLeft bar, above an alTop bar, etc.),
// overlapping the perpendicular extent.
function TTySplitter.FindResizeTarget: TControl;
var
  i: Integer;
  c, best: TControl;
  bestEdge: Integer;
begin
  Result := nil; best := nil;
  if Parent = nil then Exit;
  bestEdge := Low(Integer);
  for i := 0 to Parent.ControlCount - 1 do
  begin
    c := Parent.Controls[i];
    if (c = Self) or (not c.Visible) then Continue;
    case Align of
      alLeft:   if (c.Left + c.Width <= Left) and (c.Left + c.Width > bestEdge)
                   and (c.Top < Top + Height) and (c.Top + c.Height > Top) then begin best := c; bestEdge := c.Left + c.Width; end;
      alRight:  if (c.Left >= Left + Width) and (-c.Left > bestEdge)
                   and (c.Top < Top + Height) and (c.Top + c.Height > Top) then begin best := c; bestEdge := -c.Left; end;
      alTop:    if (c.Top + c.Height <= Top) and (c.Top + c.Height > bestEdge)
                   and (c.Left < Left + Width) and (c.Left + c.Width > Left) then begin best := c; bestEdge := c.Top + c.Height; end;
      alBottom: if (c.Top >= Top + Height) and (-c.Top > bestEdge)
                   and (c.Left < Left + Width) and (c.Left + c.Width > Left) then begin best := c; bestEdge := -c.Top; end;
    end;
  end;
  Result := best;
end;

{ The clamp + OnCanResize negotiation, shared by the live resize and the deferred band.
  Factored out so the preview cannot drift from what release will actually commit: one
  clamp, one veto, one answer. False = no target, or the handler refused. }
function TTySplitter.NegotiateSize(ADelta: Integer; out ANewSize: Integer): Boolean;
var
  maxSize: Integer;
  accept: Boolean;
begin
  Result := False;
  ANewSize := FStartSize;
  if FTarget = nil then Exit;
  if Vertical then maxSize := Parent.ClientWidth - Width else maxSize := Parent.ClientHeight - Height;
  { AutoSnap must reach the shared negotiator, or the band previews a size the release
    will not honour -- the preview and the commit have to come from one clamp. }
  ANewSize := TySplitterNewSize(Align, FStartSize, ADelta, FMinSize, maxSize, FAutoSnap);
  accept := True;
  if Assigned(FOnCanResize) then FOnCanResize(Self, ANewSize, accept);
  Result := accept;
end;

procedure TTySplitter.ApplySize(ADelta: Integer);
var
  n: Integer;
begin
  if not NegotiateSize(ADelta, n) then Exit;
  if Vertical then FTarget.Width := n else FTarget.Height := n;
end;

procedure TTySplitter.ShowBand;
var
  S: TTyStyleSet;
begin
  if (FBand <> nil) or (Parent = nil) then Exit;
  FBand := TTySplitterBand.Create(Self);   // owned by us: a splitter freed mid-drag takes it along
  FBand.Controller := Controller;
  S := CurrentStyle;
  // The band borrows the splitter's own resolved text colour -- the token the grip dots
  // already use -- so `TySplitter { color: ... }` recolours both and nothing is baked in.
  FBand.BandColor := S.TextColor;
  FBand.Patterned := FResizeStyle = rsPattern;
  FBand.AlongY := Vertical;
  FBand.Cursor := Cursor;   // the band sits under the pointer: keep the resize cursor
  FBand.Parent := Parent;
  FBand.BoundsRect := BoundsRect;
  FBand.BringToFront;       // windowed panes would otherwise cover the preview
end;

procedure TTySplitter.MoveBand(ADelta: Integer);
var
  n: Integer;
  r: TRect;
begin
  if FBand = nil then Exit;                    // rsNone/rsUpdate: nothing to move
  if not NegotiateSize(ADelta, n) then Exit;   // refused: leave the band where it was
  // A deferred drag never moves the splitter, so BoundsRect is still the drag-start rect
  // and the offset can be measured from it every time (no drift over a long drag).
  r := BoundsRect;
  if Vertical then Types.OffsetRect(r, TySplitterBarOffset(Align, FStartSize, n), 0)
  else Types.OffsetRect(r, 0, TySplitterBarOffset(Align, FStartSize, n));
  FBand.BoundsRect := r;
end;

procedure TTySplitter.HideBand;
begin
  FreeAndNil(FBand);
end;

procedure TTySplitter.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FTarget := FindResizeTarget;
  if FTarget = nil then Exit;
  FDragging := True;
  FStartSize := AxisSize(FTarget);
  // Measure the mouse in SCREEN coords. An alLeft/alTop splitter slides as it resizes the
  // neighbour, so a control-LOCAL delta tracks the mouse at half speed (W = (start + mouseDelta)/2).
  // Screen coords are a stable reference, so the resize follows the mouse 1:1.
  if Vertical then FMouseStart := ClientToScreen(Point(X, Y)).X
  else FMouseStart := ClientToScreen(Point(X, Y)).Y;
  if FResizeStyle in [rsLine, rsPattern] then ShowBand;
end;

procedure TTySplitter.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  delta: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  // Left button no longer held (stolen/missed MouseUp — capture theft, modal, Alt+Tab): stop
  // dragging rather than resize under a released cursor on later button-less hover moves.
  // The band goes with it, or it would hang over the layout until the next drag.
  if not (ssLeft in Shift) then begin FDragging := False; HideBand; Exit; end;
  if Vertical then delta := ClientToScreen(Point(X, Y)).X - FMouseStart
  else delta := ClientToScreen(Point(X, Y)).Y - FMouseStart;
  if FResizeStyle = rsUpdate then
    ApplySize(delta)
  else
    // rsLine/rsPattern track the pointer with the feedback band and commit on release;
    // rsNone has no band, so this is a no-op and only MouseUp resizes.
    MoveBand(delta);
end;

procedure TTySplitter.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  delta: Integer;
begin
  if FDragging then
  begin
    // Every style except rsUpdate defers the resize to here — rsUpdate already applied it
    // on each move. Missing this is what left rsPattern and rsNone dragging nothing at all.
    if FResizeStyle <> rsUpdate then
    begin
      if Vertical then delta := ClientToScreen(Point(X, Y)).X - FMouseStart
      else delta := ClientToScreen(Point(X, Y)).Y - FMouseStart;
      ApplySize(delta);
    end;
    HideBand;
    FDragging := False;
    // Fire OnMoved only when the resize actually changed the target's size
    // (mirrors TCustomSplitter behaviour).
    if Assigned(FOnMoved) and (FTarget <> nil) and (AxisSize(FTarget) <> FStartSize) then
      FOnMoved(Self);
    FTarget := nil;
  end;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TTySplitter.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTySplitter.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  W, H, cx, cy, i, gap, dot, half: Integer;
  grip: TTyFill;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    DrawFrame(P, Rect(0, 0, W, H), S);     // honors a themed background if set (default: none)
    // 3 grip dots centered, in S.TextColor
    grip := Default(TTyFill);
    grip.Kind := tfkSolid;
    grip.Color := S.TextColor;
    dot := P.Scale(2);
    gap := P.Scale(3);
    cx := W div 2; cy := H div 2;
    half := dot div 2;
    for i := -1 to 1 do
      if Vertical then
        P.FillBackground(Rect(cx - half, cy + i*gap - half, cx - half + dot, cy + i*gap - half + dot), grip, half)
      else
        P.FillBackground(Rect(cx + i*gap - half, cy - half, cx + i*gap - half + dot, cy - half + dot), grip, half);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
