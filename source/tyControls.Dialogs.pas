unit tyControls.Dialogs;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls,
  tyControls.Types;

{ Right-aligns caption buttons in a bar: index 0 is the RIGHTMOST (primary), each successive
  button sits to its left, ASpacing apart, AMargin from the right edge. Pure. }
function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;

implementation

function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;
var
  i, x: Integer;
begin
  SetLength(Result, Length(ASizes));
  x := ABarWidth - AMargin;                 // right edge of the next (rightmost-first) button
  for i := 0 to High(ASizes) do
  begin
    Result[i].Right := x;
    Result[i].Left := x - ASizes[i].cx;
    Result[i].Top := 0;
    Result[i].Bottom := ASizes[i].cy;
    x := Result[i].Left - ASpacing;
  end;
end;

end.
