unit tyControls.Splitter;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base;

function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer): Integer;

implementation

function TySplitterNewSize(AAlign: TAlign; AStartSize, ADelta, AMinSize, AMaxSize: Integer): Integer;
begin
  case AAlign of
    alRight, alBottom: Result := AStartSize - ADelta;
  else
    Result := AStartSize + ADelta;
  end;
  if Result < AMinSize then Result := AMinSize;
  if (AMaxSize >= AMinSize) and (Result > AMaxSize) then Result := AMaxSize;
end;

end.
