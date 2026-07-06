unit tyControls.KeyTips;
{$mode objfpc}{$H+}

{ KeyTips — the Office "press Alt for access-key badges" model. Given a list of captions
  (ribbon tabs, and — later — commands), assign each a UNIQUE single-character access key:
  prefer the caption's first ASCII letter/digit; if that is taken or the caption has no ASCII
  alnum (e.g. a CJK label like 开始), fall back to the next free key from a 1-9 / A-Z pool.

  This is pure + headless-unit-tested. The overlay rendering + the Alt key handling live in
  TTyRibbon and need a real machine. }

interface

uses
  Classes, SysUtils;

type
  TKeyTipArray = array of string;

{ Assign a unique 1-char (uppercase) access key to each caption. Result[i] is the key for
  ACaptions[i]; '' only if the whole pool is exhausted (> 44 items). }
function TyAssignKeyTips(const ACaptions: array of string): TKeyTipArray;

implementation

const
  KeyTipPool = '123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

function FirstAsciiAlnum(const S: string): Char;
var
  i: Integer;
  c: Char;
begin
  Result := #0;
  for i := 1 to Length(S) do
  begin
    c := UpCase(S[i]);
    if ((c >= 'A') and (c <= 'Z')) or ((c >= '0') and (c <= '9')) then
      Exit(c);
  end;
end;

function TyAssignKeyTips(const ACaptions: array of string): TKeyTipArray;
var
  i, j: Integer;
  c: Char;
  used: set of Char;
begin
  SetLength(Result, Length(ACaptions));
  used := [];
  // Pass 1: take the caption's first ASCII alnum when it is still free.
  for i := 0 to High(ACaptions) do
  begin
    c := FirstAsciiAlnum(ACaptions[i]);
    if (c <> #0) and not (c in used) then
    begin
      Result[i] := c;
      Include(used, c);
    end
    else
      Result[i] := '';
  end;
  // Pass 2: give every still-unassigned caption the next free pool key.
  for i := 0 to High(ACaptions) do
    if Result[i] = '' then
      for j := 1 to Length(KeyTipPool) do
        if not (KeyTipPool[j] in used) then
        begin
          Result[i] := KeyTipPool[j];
          Include(used, KeyTipPool[j]);
          Break;
        end;
end;

end.
