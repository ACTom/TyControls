unit tyControls.Dialogs.Find;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Dialogs;

type
  TTyFindChecks = record
    MatchCase, WholeWord, SearchUp: Boolean;
  end;

function TyFindOptionsToChecks(AOpts: TFindOptions): TTyFindChecks;
function TyChecksToFindOptions(const AChecks: TTyFindChecks; ABase: TFindOptions): TFindOptions;

implementation

function TyFindOptionsToChecks(AOpts: TFindOptions): TTyFindChecks;
begin
  Result.MatchCase := frMatchCase in AOpts;
  Result.WholeWord := frWholeWord in AOpts;
  Result.SearchUp  := not (frDown in AOpts);
end;

function TyChecksToFindOptions(const AChecks: TTyFindChecks; ABase: TFindOptions): TFindOptions;
begin
  Result := ABase;
  if AChecks.MatchCase then Include(Result, frMatchCase) else Exclude(Result, frMatchCase);
  if AChecks.WholeWord then Include(Result, frWholeWord) else Exclude(Result, frWholeWord);
  if AChecks.SearchUp  then Exclude(Result, frDown)      else Include(Result, frDown);
end;

end.
