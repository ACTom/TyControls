unit tyControls.Panel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyPanel = class(TTyCustomControl)
  protected
    { protected, not private: a test drives the invalidation rule through it. }
    FPaintCache: TTyPaintCache;
  private
    FCaption: TCaption;
    FAlignment: TAlignment;
    procedure SetCaption(const AValue: TCaption);
    procedure SetAlignment(AValue: TAlignment);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    destructor Destroy; override;
    procedure Invalidate; override;
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
  published
    property Caption: TCaption read FCaption write SetCaption;
    property Alignment: TAlignment read FAlignment write SetAlignment default taCenter;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;
implementation
constructor TTyPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Designer container: the IDE drops child controls INTO the panel.
  ControlStyle := ControlStyle + [csAcceptsControls];
  FCaption := '';
  FAlignment := taCenter;
  Width := 185;
  Height := 41;
end;
function TTyPanel.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;
procedure TTyPanel.SetCaption(const AValue: TCaption);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  Invalidate;
end;
procedure TTyPanel.SetAlignment(AValue: TAlignment);
begin
  if FAlignment = AValue then Exit;
  FAlignment := AValue;
  Invalidate;
end;
procedure TTyPanel.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ContentRect: TRect;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    ContentRect := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    DrawFrame(P, ContentRect, S);
    // Inset content by padding
    ContentRect := Rect(
      ContentRect.Left   + P.Scale(S.Padding.Left),
      ContentRect.Top    + P.Scale(S.Padding.Top),
      ContentRect.Right  - P.Scale(S.Padding.Right),
      ContentRect.Bottom - P.Scale(S.Padding.Bottom)
    );
    if FCaption <> '' then
      P.DrawText(ContentRect, FCaption, S.FontName, ResolveFontSize(S), S.FontWeight,
        S.TextColor, FAlignment, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;
destructor TTyPanel.Destroy;
begin
  FPaintCache.Free;
  inherited Destroy;
end;

procedure TTyPanel.Invalidate;
begin
  { The one thing the cache keys on: our OWN look changed. A child's damage never reaches
    here, which is exactly why the cache survives it. }
  if FPaintCache <> nil then FPaintCache.Drop;
  inherited Invalidate;
end;

procedure TTyPanel.Paint;
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

end.
