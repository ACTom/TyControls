unit tyControls.PaintPanel;
{$mode objfpc}{$H+}
{ TTyPaintPanel — an owner-draw surface panel.

  A TTyCustomPanel descendant (reuses the 'TyPanel' typeKey / theme) that, after painting the
  themed frame and insetting the content by the theme padding, fires OnPaintSurface so the
  host application can draw straight into the SAME paint pass with the library painter
  (TTyPainter). The handler receives the live painter and the content rectangle (device px,
  padding-inset) and may use the full painter API — FillBackground / StrokeBorder / DrawText
  / DrawGlyph / Bitmap.Canvas2D — with all output composited by the panel's EndPaint.

  With no handler assigned it is byte-compatible with a plain TTyPanel (it still draws the
  optional Caption). It remains a real LCL container (csAcceptsControls) so child controls
  may parent onto it.

  NOT to be confused with the OnPaint every ty control inherits from tyControls.Base. The
  two hooks sit on opposite sides of the composite and are not interchangeable:
    OnPaintSurface  fires INSIDE the pass, before EndPaint, and hands over the TTyPainter --
                    so the handler draws in theme tokens and its output is composited with
                    the panel's own. This is the owner-draw seam.
    OnPaint         fires AFTER the composite has landed, and hands over the LCL Canvas --
                    so the handler can only draw ON TOP of the finished control. This is the
                    overlay seam, and it is the only one available on controls that are not
                    TTyPaintPanel.
  Drawing to the Canvas from an OnPaintSurface handler is the classic mistake here: EndPaint
  has not run yet, so the composite overwrites it. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Panel;
type
  { Fired once per paint, AFTER the themed frame + padding inset and BEFORE the painter is
    composited to the canvas. APainter is the live library painter (do NOT free it, do NOT
    call BeginPaint/EndPaint on it); AContent is the padding-inset content rect in device
    px, ready to draw into. }
  TTyPaintSurfaceEvent = procedure(Sender: TObject; APainter: TTyPainter;
    const AContent: TRect) of object;

  TTyCustomPaintPanel = class(TTyCustomPanel)
  private
    FOnPaintSurface: TTyPaintSurfaceEvent;
  protected
    { Reimplements the TTyPanel paint skeleton so the owner-draw event fires inside the same
      painter pass (between the content draw and EndPaint). Kept minimal + byte-compatible
      with the base when no handler is set. }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    { Draw the panel's surface yourself with the library painter, inside the panel's own
      paint pass. Called after the themed frame + padding inset; AContent is the content
      rect (device px). }
    property OnPaintSurface: TTyPaintSurfaceEvent read FOnPaintSurface write FOnPaintSurface;
  end;

  { TTyPaintPanel publishes TTyCustomPaintPanel's properties; everything lives in TTyCustomPaintPanel. }
  TTyPaintPanel = class(TTyCustomPaintPanel)
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
    property VerticalAlignment;
    property WordWrap;
    property ShowAccelChar;
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
    property OnPaintSurface;
  end;

{ Pure geometry, exposed for headless tests: the content rect after the themed frame is
  drawn — ARect (device px) inset by the style padding, scaled by APPI. Mirrors what
  RenderTo hands to OnPaintSurface, without a window handle or a painter. }
function TyPaintPanelContentRect(const ARect: TRect; const APadding: TRect; APPI: Integer): TRect;

implementation

function TyPaintPanelContentRect(const ARect: TRect; const APadding: TRect; APPI: Integer): TRect;

  function ScaleLP(ALogical: Integer): Integer;
  begin
    if APPI <= 0 then
      Result := ALogical
    else
      Result := MulDiv(ALogical, APPI, 96);
  end;

begin
  // Content is the frame rect (origin-normalised, as RenderTo builds it) inset by the
  // padding on each edge. Same MulDiv scaling TTyPainter.Scale applies.
  Result := Rect(
    (ARect.Left)   + ScaleLP(APadding.Left),
    (ARect.Top)    + ScaleLP(APadding.Top),
    (ARect.Right)  - ScaleLP(APadding.Right),
    (ARect.Bottom) - ScaleLP(APadding.Bottom)
  );
end;

constructor TTyCustomPaintPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Inherit TTyPanel's container behaviour (csAcceptsControls); an owner-draw surface is
  // still a real container, so leave that intact.
  { But NOT its shape. TTyPanel is a caption strip and lands 185x41; a drawing surface has no
    intrinsic aspect, so it arrives as a letterbox in which anything drawn is clipped and the
    first thing a user must do is resize it. Square, and the same 105x105 TPaintBox picks for
    the same reason (include/paintbox.inc:50-54). }
  Width := 105;
  Height := 105;
end;

procedure TTyCustomPaintPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  FrameRect, ContentRect: TRect;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // Origin-normalised frame rect, exactly as TTyPanel.RenderTo builds it.
    FrameRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, FrameRect, S);
    // Inset content by the theme padding (same scaling as the base).
    ContentRect := Rect(
      FrameRect.Left   + P.Scale(S.Padding.Left),
      FrameRect.Top    + P.Scale(S.Padding.Top),
      FrameRect.Right  - P.Scale(S.Padding.Right),
      FrameRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    // Optional caption first (base behaviour), so the owner-draw handler paints on top.
    if Caption <> '' then
      P.DrawText(ContentRect, Caption, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, Alignment, tlCenter, True);
    // Owner-draw: hand the live painter + content rect to the app, inside this paint pass.
    if Assigned(FOnPaintSurface) then
      FOnPaintSurface(Self, P, ContentRect);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomPaintPanel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
