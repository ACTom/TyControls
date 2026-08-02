unit tyControls.TabSheet;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  { One page of a TTyPageControl. A themed background surface that hosts dropped
    controls. Its Caption is the TAB label (drawn by the host header), NOT painted
    on the page body. The design-time ControlStyle flags mirror Lazarus TTabSheet so
    the IDE treats it as a fixed, droppable, hide-on-inactive design surface. }
  TTyTabSheet = class(TTyCustomControl)
  protected
    { protected, not private: a test drives the invalidation rule through it. }
    FPaintCache: TTyPaintCache;
  private
  protected
    { Repaint when Caption/Text changes -- the LCL hook that replaces our old setter. }
    procedure TextChanged; override;
    procedure SetParent(AParent: TWinControl); override;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    destructor Destroy; override;
    procedure Invalidate; override;
    constructor Create(AOwner: TComponent); override;
  published
    { Caption is TControl's, not a second string of our own.

      It used to be a field-backed property shadowing TControl.Caption, so a control had
      TWO captions: `P.Caption := 'x'` set ours and left TControl.Text empty, while
      anything reading Text -- an action link, an accessibility query, TControl's own
      csSetCaption wiring, generic code that walks TControl -- saw ''. On LCL these are one
      string: Caption IS Text, routed through RealSetText, and a repaint is arranged by
      overriding TextChanged. That is what this does now. }
    property Caption;
    property StyleClass;
    property Controller;
  end;

implementation

uses
  tyControls.PageControl;   // for TTyPageControl in SetParent (one-way: impl only)

constructor TTyTabSheet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds,
    csNoDesignVisible, csNoFocus];
  Align := alClient;
  Visible := False;
end;

function TTyTabSheet.GetStyleTypeKey: string;
begin
  Result := 'TyTabSheet';
end;

procedure TTyTabSheet.TextChanged;
begin
  inherited TextChanged;
  { The tab LABEL changed, so it is the host header that has to re-lay, not us. }
  if Parent <> nil then
    Parent.Invalidate;
end;

procedure TTyTabSheet.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  { Register with the hosting page control. Fires for AddPage (Parent := PC), for a
    designer drop onto a page control, and for a streamed load when the Parent
    property is applied — so the page list is rebuilt uniformly in all paths. }
  if (AParent <> nil) and (AParent is TTyPageControl) then
    TTyPageControl(AParent).RegisterPage(Self);
end;

procedure TTyTabSheet.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, R, S);   // themed background only — no caption text on the body
    P.EndPaint;
  finally
    P.Free;
  end;
end;

destructor TTyTabSheet.Destroy;
begin
  FPaintCache.Free;
  inherited Destroy;
end;

procedure TTyTabSheet.Invalidate;
begin
  { The one thing the cache keys on: our OWN look changed. A child's damage never reaches
    here, which is exactly why the cache survives it. }
  if FPaintCache <> nil then FPaintCache.Drop;
  inherited Invalidate;
end;

procedure TTyTabSheet.Paint;
var
  w, h: Integer;
begin
  { The designer repaints rarely and streams while it does, so cache only at runtime. }
  if csDesigning in ComponentState then
  begin
      RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
    Exit;
  end;
  w := ClientWidth; h := ClientHeight;
  if (w <= 0) or (h <= 0) then Exit;
  if FPaintCache = nil then FPaintCache := TTyPaintCache.Create;
  if FPaintCache.NeedsRender(w, h) then
    RenderTo(FPaintCache.Canvas, Rect(0, 0, w, h), Font.PixelsPerInch);
  FPaintCache.Blit(Canvas);
end;


initialization
  { Runtime LFM streaming resolves nested (non-field) page objects via the class
    registry; register so a saved form's pages load (mirrors TTyTitleBar in Form.pas). }
  RegisterClass(TTyTabSheet);
end.
