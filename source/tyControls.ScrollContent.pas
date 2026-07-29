unit tyControls.ScrollContent;
{$mode objfpc}{$H+}

{ The viewport a scrolling container scrolls.

  WHY IT EXISTS. A self-drawn container paints its border INSIDE its client area, and a child
  control is clipped by the parent's client area -- not by anything we can shrink from Pascal.
  Overriding GetClientRect changes what the LCL computes with; it does not move the boundary the
  widgetset clips against. So on a container whose content MOVES -- which is every scrolling
  container, by design rather than by accident -- the content necessarily travels over the top
  and bottom border. That is not an edge case a caller brought on themselves; it is the normal
  case, every time anyone scrolls.

  The LCL's own TScrollBox never shows this because its border is not self-drawn: it sets
  BorderStyle := bsSingle, which puts the frame in the NON-client area, and the OS clips
  children before they can reach it. A themed border cannot live there.

  So the clipping boundary has to be a real window, and that is this control: a plain container
  inset by the frame, hosting the content, clipping it natively on every widgetset. It is
  deliberately EXPLICIT -- content is parented to the Content viewport, not to the box -- the
  same shape as TTyTabSheet inside TTyPageControl, which this library and its users already
  know. The alternative, silently redirecting anything parented to the box, would leave
  Parent <> what you assigned, ControlCount not counting the content, and coordinates quietly
  shifted; five implicit rules instead of one visible container.

  It paints only the background it inherits: the FRAME belongs to the box around it. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Base;

type
  TTyScrollContent = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  public
    constructor Create(AOwner: TComponent); override;
    { The surface only -- no border. The scrolling box draws the frame, and drawing a second
      one here would put a line where the content is supposed to run under. }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  end;

implementation

uses
  tyControls.Painter;

constructor TTyScrollContent.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { csDesignFixedBounds: the box owns this control's bounds -- they are the viewport, derived
    from the frame and the visible scrollbars, so letting the designer drag them would put the
    viewport somewhere the box will move it back from on the next relayout. }
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoFocus];
  SetInitialBounds(0, 0, 100, 100);
end;

function TTyScrollContent.GetStyleTypeKey: string;
begin
  { Its own key rather than borrowing TyScrollBox: a theme that dresses the box's frame must not
    have that frame resolved a second time for the viewport inside it. }
  Result := 'TyScrollContent';
end;

procedure TTyScrollContent.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    if tpBackground in S.Present then
      P.FillBackground(Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top),
        S.Background, 0);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyScrollContent.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

initialization
  { Runtime .lfm streaming resolves a nested non-field object through the class registry, the
    same reason TTyTabSheet registers itself. }
  RegisterClass(TTyScrollContent);
end.
