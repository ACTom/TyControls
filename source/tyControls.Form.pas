unit tyControls.Form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types;

type
  TTyBorderHit = (bhNone, bhLeft, bhTop, bhRight, bhBottom,
                  bhTopLeft, bhTopRight, bhBottomLeft, bhBottomRight);

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
function TyMaximizedBounds(const AWorkArea: TRect): TRect;

implementation

function TyHitTestBorder(const AClient: TRect; const APt: TPoint; AZone: Integer): TTyBorderHit;
var
  OnLeft, OnRight, OnTop, OnBottom: Boolean;
begin
  Result := bhNone;
  if AZone <= 0 then
    Exit;
  if (APt.X < AClient.Left) or (APt.X > AClient.Right) or
     (APt.Y < AClient.Top) or (APt.Y > AClient.Bottom) then
    Exit;
  OnLeft := APt.X < (AClient.Left + AZone);
  OnRight := APt.X > (AClient.Right - AZone);
  OnTop := APt.Y < (AClient.Top + AZone);
  OnBottom := APt.Y > (AClient.Bottom - AZone);
  if OnTop and OnLeft then
    Result := bhTopLeft
  else if OnTop and OnRight then
    Result := bhTopRight
  else if OnBottom and OnLeft then
    Result := bhBottomLeft
  else if OnBottom and OnRight then
    Result := bhBottomRight
  else if OnLeft then
    Result := bhLeft
  else if OnRight then
    Result := bhRight
  else if OnTop then
    Result := bhTop
  else if OnBottom then
    Result := bhBottom
  else
    Result := bhNone;
end;

function TyMaximizedBounds(const AWorkArea: TRect): TRect;
begin
  Result.Left := AWorkArea.Left;
  Result.Top := AWorkArea.Top;
  Result.Right := AWorkArea.Right;
  Result.Bottom := AWorkArea.Bottom;
end;

end.
