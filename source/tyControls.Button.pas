unit tyControls.Button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;
type
  TTyButton = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
    procedure Paint; override;
  public
    procedure Click; override;
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

procedure TTyButton.Click;
begin
  inherited Click;
end;

function TTyButton.GetStyleTypeKey: string;
begin
  Result := 'TyButton';
end;

procedure TTyButton.Paint;
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
    DrawFrame(P, ContentRect, S);
    P.DrawText(ContentRect, Caption, S.FontName, S.FontSize, S.FontWeight,
      S.TextColor, taCenter, tlCenter, True);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

end.
