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
  private
    FCaption: string;
    procedure SetCaption(const AValue: string);
  protected
    procedure SetParent(AParent: TWinControl); override;
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Caption: string read FCaption write SetCaption;
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
  FCaption := '';
end;

function TTyTabSheet.GetStyleTypeKey: string;
begin
  Result := 'TyTabSheet';
end;

procedure TTyTabSheet.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
  if Parent <> nil then
    Parent.Invalidate;   // the tab label changed — re-lay the host header
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

procedure TTyTabSheet.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
