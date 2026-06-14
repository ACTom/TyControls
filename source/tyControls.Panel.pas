unit tyControls.Panel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyPanel = class(TTyCustomControl)
  private
    FCaption: string;
    procedure SetCaption(const AValue: string);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
  published
    property Caption: string read FCaption write SetCaption;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;
implementation
constructor TTyPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaption := '';
  Width := 185;
  Height := 41;
end;
function TTyPanel.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;
procedure TTyPanel.SetCaption(const AValue: string);
begin
  if FCaption = AValue then Exit;
  FCaption := AValue;
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
        S.TextColor, taLeftJustify, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;
procedure TTyPanel.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;
end.
