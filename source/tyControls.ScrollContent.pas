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
  private
    FScrollOrigin: TPoint;
    FContentW, FContentH: Integer;
  protected
    function GetStyleTypeKey: string; override;
    { THE CONTAINER CONTRACT, one level down from the box.

      The moment a box is given a viewport, the content lives HERE -- so the three layout
      facts TTyScrollBox spells out for its own children (see its AdjustClientRect /
      GetLogicalClientRect) stop applying to them, because those hooks are on the box and
      the children are not the box's. Without them the viewport is a plain container: it
      lays every ALIGNED child out at its own unscrolled origin, and the align pass that
      follows each scroll drags them straight back. Measured on the forum's scenario
      (tests/scrollcluster A4c): twelve alTop rows inside a viewport, thumb dragged to
      ScrollY=76, first row Top 158 -> 158. It never moved. Un-aligned children scrolled
      fine, which is exactly why this looked like "sometimes it works".

      So the viewport owns the same two hooks, fed by the box through SetScrollOrigin:
      the layout ORIGIN is the scrolled origin, and the layout AREA grows to the content
      on an axis that actually overflows (an alTop stack taller than the viewport needs
      somewhere to stack, or DoAlign clamps every row past the fold onto the last one). }
    function GetLogicalClientRect: TRect; override;
    procedure AdjustClientRect(var ARect: TRect); override;
  public
    constructor Create(AOwner: TComponent); override;
    { Told by the scrolling box, which owns the offset and measures the extent. The viewport
      deliberately derives NEITHER for itself: two places computing the scroll origin is the
      defect this control exists to avoid repeating. }
    procedure SetScrollOrigin(const AOrigin: TPoint; AContentW, AContentH: Integer);
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

procedure TTyScrollContent.SetScrollOrigin(const AOrigin: TPoint;
  AContentW, AContentH: Integer);
begin
  FScrollOrigin := AOrigin;
  FContentW := AContentW;
  FContentH := AContentH;
  { NO InvalidateClientRectCache HERE, and that is a finding rather than an omission.

    The obvious instinct is that changing what the two hooks below return must drop LCL's
    cache of them. It was written that way first, and the mutant that replaced the call with
    a no-op SURVIVED every scenario in tests/scrollcluster -- including two written
    specifically to reach it (A6: an akRight child in the viewport across repeated scrolls;
    A7: the viewport with ChildSizing.Layout set, which is the ONLY path that reads the
    cached rect at all -- wincontrol.inc:948 and :6324).

    The reason is in TControl.InvalidatePreferredSize (control.inc:5748-5757): it walks from
    a control up through every ancestor clearing wcfAdjustedLogicalClientRectValid, and it
    runs on every bounds change. This origin can only move as part of a scroll, a scroll
    always moves the children, so LCL has already dropped the cache before anything can read
    it. The extent cannot move without a child moving either -- it is measured FROM their
    bounds. So the call was dead on every reachable path, and dead code with no guard is
    exactly what this pass exists to remove. If a future change makes the origin movable
    WITHOUT touching a child, put it back -- and add the scenario that catches it. }
end;

function TTyScrollContent.GetLogicalClientRect: TRect;
var
  viewW, viewH: Integer;
begin
  Result := inherited GetLogicalClientRect;
  viewW := Result.Right - Result.Left;
  viewH := Result.Bottom - Result.Top;
  { Only on an axis that OVERFLOWS. Growing unconditionally latches the axis: an aligned
    child's size comes FROM this rect and then feeds BACK into the extent the box measures,
    so a column of alTop rows would keep the grown width forever and never fall back.
    Same guard, same reason, as TTyScrollBox.GetLogicalClientRect. }
  if FContentW > viewW then Result.Right := Result.Left + FContentW;
  if FContentH > viewH then Result.Bottom := Result.Top + FContentH;
end;

procedure TTyScrollContent.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  { WHERE the children start. They are stored in SCROLLED coordinates (the box's ScrollBy
    moved their Left/Top), so the align engine has to agree -- otherwise every realign snaps
    the aligned ones back to the unscrolled spot and quietly eats the scroll. }
  Types.OffsetRect(ARect, -FScrollOrigin.x, -FScrollOrigin.y);
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
