unit tyControls.TyLabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyLabel = class(TTyGraphicControl)
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
  published
    property Caption;
    property Enabled;
    property Font;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
    property OnClick;
  end;
implementation

function TTyLabel.GetStyleTypeKey: string;
begin
  Result := 'TyLabel';
end;

procedure TTyLabel.Paint;
var
  P: TTyPainter;
  S: TTyStyleSet;
  R, ContentRect: TRect;
begin
  P := TTyPainter.Create;
  try
    R := ClientRect;
    P.BeginPaint(Canvas, R, Font.PixelsPerInch);
    S := CurrentStyle;
    ContentRect := Rect(0, 0, R.Right - R.Left, R.Bottom - R.Top);
    P.DrawText(ContentRect, Caption, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taLeftJustify, tlCenter, False);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
