unit tyControls.Dialogs;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Dialogs, Forms,
  tyControls.Types;

{ Right-aligns caption buttons in a bar: index 0 is the RIGHTMOST (primary), each successive
  button sits to its left, ASpacing apart, AMargin from the right edge. Pure. }
function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;

type
  TMsgDlgBtnArray = array of TMsgDlgBtn;

function TyMsgButtonCaption(ABtn: TMsgDlgBtn): string;
function TyMsgButtonResult(ABtn: TMsgDlgBtn): TModalResult;
function TyMsgOrderedButtons(AButtons: TMsgDlgButtons): TMsgDlgBtnArray;
function TyMsgTypeSymbol(ADlgType: TMsgDlgType): string;

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


function TyMsgButtonCaption(ABtn: TMsgDlgBtn): string;
begin
  case ABtn of
    mbYes:     Result := 'Yes';
    mbNo:      Result := 'No';
    mbOK:      Result := 'OK';
    mbCancel:  Result := 'Cancel';
    mbAbort:   Result := 'Abort';
    mbRetry:   Result := 'Retry';
    mbIgnore:  Result := 'Ignore';
    mbAll:     Result := 'All';
    mbNoToAll: Result := 'No to All';
    mbYesToAll:Result := 'Yes to All';
    mbHelp:    Result := 'Help';
    mbClose:   Result := 'Close';
  else Result := '';
  end;
end;

function TyMsgButtonResult(ABtn: TMsgDlgBtn): TModalResult;
begin
  case ABtn of
    mbYes:     Result := mrYes;
    mbNo:      Result := mrNo;
    mbOK:      Result := mrOK;
    mbCancel:  Result := mrCancel;
    mbAbort:   Result := mrAbort;
    mbRetry:   Result := mrRetry;
    mbIgnore:  Result := mrIgnore;
    mbAll:     Result := mrAll;
    mbNoToAll: Result := mrNoToAll;
    mbYesToAll:Result := mrYesToAll;
    mbClose:   Result := mrClose;
    mbHelp:    Result := 0;
  else Result := mrNone;
  end;
end;

function TyMsgOrderedButtons(AButtons: TMsgDlgButtons): TMsgDlgBtnArray;
const
  ORDER: array[0..11] of TMsgDlgBtn = (
    mbYes, mbYesToAll, mbNo, mbNoToAll, mbAll, mbOK,
    mbRetry, mbIgnore, mbAbort, mbCancel, mbClose, mbHelp);
var
  b: TMsgDlgBtn;
  n: Integer;
begin
  if AButtons = [] then
  begin
    SetLength(Result, 1);
    Result[0] := mbOK;
    Exit;
  end;
  SetLength(Result, 0);
  n := 0;
  for b in ORDER do
    if b in AButtons then
    begin
      SetLength(Result, n + 1);
      Result[n] := b;
      Inc(n);
    end;
end;

function TyMsgTypeSymbol(ADlgType: TMsgDlgType): string;
begin
  case ADlgType of
    mtWarning:      Result := '!';
    mtError:        Result := #$C3#$97; // × (U+00D7, UTF-8 bytes C3 97)
    mtConfirmation: Result := '?';
    mtInformation:  Result := 'i';
  else Result := '';
  end;
end;

end.
