unit tyControls.URLEdit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, LCLType, LCLIntf,
  tyControls.Types, tyControls.Painter, tyControls.StyleModel, tyControls.Edit;

type
  { An edit for URLs: a plain TTyEdit plus a trailing "open" button (a → glyph in the
    reserved right zone) that launches the current text in the default browser. Reuses
    the TTyEdit text engine + 'TyEdit' theme via the RightReserve/PaintTrailing hooks. }
  TTyURLEdit = class(TTyEdit)
  private
    FButtonWidth: Integer;   // logical px of the trailing open button
  protected
    function RightReserve(APPI: Integer): Integer; override;
    procedure PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Launch the current text as a URL in the default browser (also fired by the button).
    procedure OpenURL;
  end;

implementation

constructor TTyURLEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FButtonWidth := 20;
  TextHint := 'https://…';
end;

function TTyURLEdit.RightReserve(APPI: Integer): Integer;
begin
  Result := MulDiv(FButtonWidth, APPI, 96);
end;

procedure TTyURLEdit.PaintTrailing(APainter: TTyPainter; const AZone: TRect; const AStyle: TTyStyleSet);
begin
  APainter.DrawGlyph(AZone, tgArrowRight, AStyle.TextColor, 2);
end;

procedure TTyURLEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and PtInRect(TrailingZone(Font.PixelsPerInch), Point(X, Y)) then
  begin
    OpenURL;
    Exit;   // consumed by the button — don't move the caret / start a selection
  end;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TTyURLEdit.OpenURL;
begin
  if Trim(Text) <> '' then
    LCLIntf.OpenURL(Text);   // qualified: the method shares the name with the LCL routine
end;

end.
