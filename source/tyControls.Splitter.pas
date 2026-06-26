unit tyControls.Splitter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, ExtCtrls,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTySplitterCanResizeEvent = procedure(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean) of object;

  TTySplitter = class(TTyCustomControl)
  private
    FMinSize: Integer;
    FResizeStyle: TResizeStyle;
    FOnCanResize: TTySplitterCanResizeEvent;
    FOnMoved: TNotifyEvent;
    FTarget: TControl;
    FDragging: Boolean;
    FMouseStart: Integer;     // mouse coord (screen-axis) at drag start
    FStartSize: Integer;      // target size at drag start
    FLineOfs: Integer;        // rsLine ghost position (logical, along axis)
    function Vertical: Boolean;     // a left/right splitter resizes horizontally
    function FindResizeTarget: TControl;
    function AxisSize(AControl: TControl): Integer;
    procedure ApplySize(ANewSize: Integer);
    procedure SetMinSize(AValue: Integer);
    procedure UpdateCursor;
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure Loaded; override;     // re-derive the cursor after Align streams in
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property MinSize: Integer read FMinSize write SetMinSize default 30;
    property ResizeStyle: TResizeStyle read FResizeStyle write FResizeStyle default rsUpdate;
    property OnCanResize: TTySplitterCanResizeEvent read FOnCanResize write FOnCanResize;
    property OnMoved: TNotifyEvent read FOnMoved write FOnMoved;
    property Align default alLeft;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer): Integer;

implementation

function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer): Integer;
begin
  case AAlign of
    alRight, alBottom: Result := AStartSize - ADelta;
  else
    Result := AStartSize + ADelta;
  end;
  if Result < AMinSize then Result := AMinSize;
  if (AMaxSize >= AMinSize) and (Result > AMaxSize) then Result := AMaxSize;
end;

constructor TTySplitter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMinSize := 30;
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
  Result := Align in [alLeft, alRight];   // vertical bar -> resizes width (horizontal drag)
end;

procedure TTySplitter.UpdateCursor;
begin
  if Vertical then Cursor := crHSplit else Cursor := crVSplit;
end;

procedure TTySplitter.Loaded;
begin
  inherited Loaded;
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
      alLeft:   if (c.Left + c.Width <= Left) and (c.Left + c.Width > bestEdge) then begin best := c; bestEdge := c.Left + c.Width; end;
      alRight:  if (c.Left >= Left + Width) and (-c.Left > bestEdge) then begin best := c; bestEdge := -c.Left; end;
      alTop:    if (c.Top + c.Height <= Top) and (c.Top + c.Height > bestEdge) then begin best := c; bestEdge := c.Top + c.Height; end;
      alBottom: if (c.Top >= Top + Height) and (-c.Top > bestEdge) then begin best := c; bestEdge := -c.Top; end;
    end;
  end;
  Result := best;
end;

procedure TTySplitter.ApplySize(ANewSize: Integer);
var
  maxSize, n: Integer;
  accept: Boolean;
begin
  if FTarget = nil then Exit;
  if Vertical then maxSize := Parent.ClientWidth - Width else maxSize := Parent.ClientHeight - Height;
  n := TySplitterNewSize(Align, FStartSize, ANewSize, FMinSize, maxSize);
  accept := True;
  if Assigned(FOnCanResize) then FOnCanResize(Self, n, accept);
  if not accept then Exit;
  if Vertical then FTarget.Width := n else FTarget.Height := n;
end;

procedure TTySplitter.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FTarget := FindResizeTarget;
  if FTarget = nil then Exit;
  FDragging := True;
  FStartSize := AxisSize(FTarget);
  if Vertical then FMouseStart := X else FMouseStart := Y;   // X/Y are control-local; constant origin is fine for a delta
  FLineOfs := 0;
end;

procedure TTySplitter.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  delta: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  if Vertical then delta := X - FMouseStart else delta := Y - FMouseStart;
  if FResizeStyle = rsUpdate then
    ApplySize(delta)
  else
  begin
    FLineOfs := delta;       // rsLine: remember, draw ghost, apply on MouseUp
    Invalidate;
  end;
end;

procedure TTySplitter.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  delta: Integer;
begin
  if FDragging then
  begin
    if FResizeStyle = rsLine then
    begin
      if Vertical then delta := X - FMouseStart else delta := Y - FMouseStart;
      ApplySize(delta);
      FLineOfs := 0;
      Invalidate;
    end;
    FDragging := False;
    FTarget := nil;
    if Assigned(FOnMoved) then FOnMoved(Self);
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
  W, H, cx, cy, i, gap, dot: Integer;
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
    for i := -1 to 1 do
      if Vertical then
        P.FillBackground(Rect(cx - dot div 2, cy + i*gap - dot div 2, cx - dot div 2 + dot, cy + i*gap - dot div 2 + dot), grip, dot div 2)
      else
        P.FillBackground(Rect(cx + i*gap - dot div 2, cy - dot div 2, cx + i*gap - dot div 2 + dot, cy - dot div 2 + dot), grip, dot div 2);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
