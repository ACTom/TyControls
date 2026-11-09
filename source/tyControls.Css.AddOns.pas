unit tyControls.Css.AddOns;
{$mode objfpc}{$H+}

{ The registry an add-on package uses to hand the core its own tycss and its own vocabulary.

  An add-on (a chart package, say) ships tycss for its controls. It registers that text here in
  its initialization section; the theme layer appends TyAddOnCss to every theme it loads, and the
  design-time editor completes against TyCatalogAllTokens / TyCatalogAllTypeKeys, which are the
  generated Css.Catalog arrays plus whatever the registered add-ons define.

  TyCssVocabularyOf extracts a vocabulary from tycss text by exactly the rules of
  scripts/gen-tycss-catalog.ps1 (strip comments; tokens are '--name:' definitions; typeKeys are
  word-bounded TyXxx names; de-duplicated; sorted by byte value), so the vocabulary of light.tycss
  is the generated catalog.

  This unit must not depend on StyleModel: StyleModel depends on it. }

interface

uses
  SysUtils;

type
  TTyCssVocabulary = record
    Tokens, TypeKeys: TStringArray;
  end;

  { A plain procedure called after every registration. }
  TTyAddOnCssListener = procedure;

{ The tokens and typeKeys ACss defines, de-duplicated, ascending by byte value. }
function TyCssVocabularyOf(const ACss: string): TTyCssVocabulary;

{ Registers ACss under AName. The same name again replaces the earlier text in place; a new name
  goes to the end. Every listener is then called once, in the order they were added.
  A listener that raises refuses the registration: the earlier text goes back (or, for a new name,
  no entry is left), every listener already called is called once more so it can put back what
  it had applied (errors there are ignored), and the exception goes on with AName in its
  message. StyleModel's listener reseeds the models alive, so with one alive a text that does
  not load fails here. With none alive (an add-on's initialization) nothing loads it here, and
  start-up pays for no load: the next TTyStyleModel.Create finds it, drops it and raises. }
procedure TyRegisterAddOnCss(const AName, ACss: string);

{ Forgets AName's registration, calling no listener. StyleModel drops an add-on whose text does
  not load with it; tests clean up with it. }
procedure TyUnregisterAddOnCss(const AName: string);

{ Every registered text, in registration order, joined by LineEnding. '' when none. }
function TyAddOnCss: string;

{ The registered names, in registration order, and the text registered under one ('' when
  AName is not registered). }
function TyAddOnNames: TStringArray;
function TyAddOnCssOf(const AName: string): string;

{ The generated catalog arrays united with the registered add-ons' vocabularies,
  de-duplicated, ascending by byte value. }
function TyCatalogAllTokens: TStringArray;
function TyCatalogAllTypeKeys: TStringArray;

procedure TyAddAddOnCssListener(AProc: TTyAddOnCssListener);
procedure TyRemoveAddOnCssListener(AProc: TTyAddOnCssListener);

implementation

uses
  Classes, tyControls.Css.Catalog;

type
  TAddOn = record
    Name, Css: string;
  end;

const
  cAddOnRefused = 'add-on tycss "%s": %s';

var
  GAddOns: array of TAddOn;
  GListeners: array of TTyAddOnCssListener;

function StripComments(const S: string): string;
var
  i, j, n: SizeInt;
begin
  Result := '';
  n := Length(S);
  i := 1;
  while i <= n do
  begin
    if (S[i] = '/') and (i < n) and (S[i + 1] = '*') then
    begin
      j := i + 2;
      while (j < n) and not ((S[j] = '*') and (S[j + 1] = '/')) do
        Inc(j);
      if j < n then
      begin
        i := j + 2;   // skip the whole comment
        Continue;
      end;
      { unterminated: the generator's regex does not match it either, keep the text }
    end;
    Result := Result + S[i];
    Inc(i);
  end;
end;

function IsWordCh(C: Char): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (C >= #128);
end;

function IsSpaceCh(C: Char): Boolean;
begin
  Result := C in [#9, #10, #11, #12, #13, ' '];
end;

function CompareBytes(List: TStringList; I, J: Integer): Integer;
begin
  if List[I] < List[J] then Result := -1
  else if List[I] > List[J] then Result := 1
  else Result := 0;
end;

{ Ascending by byte value, duplicates dropped. }
function SortedUnique(AItems: TStrings): TStringArray;
var
  sl: TStringList;
  i, n: Integer;
begin
  sl := TStringList.Create;
  try
    sl.AddStrings(AItems);
    sl.CustomSort(@CompareBytes);
    SetLength(Result, sl.Count);
    n := 0;
    for i := 0 to sl.Count - 1 do
      if (n = 0) or (Result[n - 1] <> sl[i]) then
      begin
        Result[n] := sl[i];
        Inc(n);
      end;
    SetLength(Result, n);
  finally
    sl.Free;
  end;
end;

function TyCssVocabularyOf(const ACss: string): TTyCssVocabulary;
var
  src: string;
  toks, keys: TStringList;
  i, j, n: SizeInt;
begin
  src := StripComments(ACss);
  n := Length(src);
  toks := TStringList.Create;
  keys := TStringList.Create;
  try
    { tokens: --([a-z][a-z0-9-]*)\s*: }
    i := 1;
    while i <= n - 2 do
    begin
      if (src[i] = '-') and (src[i + 1] = '-') and (src[i + 2] in ['a'..'z']) then
      begin
        j := i + 3;
        while (j <= n) and (src[j] in ['a'..'z', '0'..'9', '-']) do
          Inc(j);
        while (j <= n) and IsSpaceCh(src[j]) do
          Inc(j);
        if (j <= n) and (src[j] = ':') then
        begin
          toks.Add(Copy(src, i, j - i + 1)); // trailing space/colon trimmed below
          i := j + 1;
          Continue;
        end;
      end;
      Inc(i);
    end;
    { keep only the name: strip the whitespace and ':' the scan swept up }
    for i := 0 to toks.Count - 1 do
    begin
      j := Length(toks[i]) - 1;               // drop ':'
      while (j > 0) and IsSpaceCh(toks[i][j]) do
        Dec(j);
      toks[i] := Copy(toks[i], 1, j);
    end;

    { typeKeys: \bTy[A-Za-z][A-Za-z0-9]*\b }
    i := 1;
    while i <= n - 2 do
    begin
      if (src[i] = 'T') and (src[i + 1] = 'y') and (src[i + 2] in ['A'..'Z', 'a'..'z']) and
         ((i = 1) or not IsWordCh(src[i - 1])) then
      begin
        j := i + 3;
        while (j <= n) and (src[j] in ['A'..'Z', 'a'..'z', '0'..'9']) do
          Inc(j);
        if (j > n) or not IsWordCh(src[j]) then
        begin
          keys.Add(Copy(src, i, j - i));
          i := j;
          Continue;
        end;
      end;
      Inc(i);
    end;

    Result.Tokens := SortedUnique(toks);
    Result.TypeKeys := SortedUnique(keys);
  finally
    keys.Free;
    toks.Free;
  end;
end;

function IndexOfAddOn(const AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(GAddOns) do
    if GAddOns[i].Name = AName then
      Exit(i);
  Result := -1;
end;

{ Puts AName back with ACss: in place when it is still registered, else at AIndex (a listener
  may have unregistered it, as StyleModel does with a text that does not load). }
procedure PutBack(const AName, ACss: string; AIndex: Integer);
var
  i, k: Integer;
begin
  i := IndexOfAddOn(AName);
  if i >= 0 then
  begin
    GAddOns[i].Css := ACss;
    Exit;
  end;
  if AIndex > Length(GAddOns) then
    AIndex := Length(GAddOns);
  SetLength(GAddOns, Length(GAddOns) + 1);
  for k := High(GAddOns) downto AIndex + 1 do
    GAddOns[k] := GAddOns[k - 1];
  GAddOns[AIndex].Name := AName;
  GAddOns[AIndex].Css := ACss;
end;

procedure TyRegisterAddOnCss(const AName, ACss: string);
var
  i, n, called, oldIndex: Integer;
  snapshot: array of TTyAddOnCssListener;
  hadOld: Boolean;
  oldCss: string;
begin
  i := IndexOfAddOn(AName);
  hadOld := i >= 0;
  oldIndex := i;
  oldCss := '';
  if hadOld then
    oldCss := GAddOns[i].Css
  else
  begin
    i := Length(GAddOns);
    SetLength(GAddOns, i + 1);
    GAddOns[i].Name := AName;
  end;
  GAddOns[i].Css := ACss;
  { a listener may add or remove listeners; call a copy }
  n := Length(GListeners);
  SetLength(snapshot, n);
  for i := 0 to n - 1 do
    snapshot[i] := GListeners[i];
  called := 0;
  try
    for i := 0 to n - 1 do
    begin
      called := i + 1;
      snapshot[i]();
    end;
  except
    on E: Exception do
    begin
      { refused: nothing of it may stay behind }
      if hadOld then
        PutBack(AName, oldCss, oldIndex)
      else
        TyUnregisterAddOnCss(AName);
      for i := 0 to called - 1 do
        try
          snapshot[i]();
        except
          { the failure to report is the first one }
        end;
      E.Message := Format(cAddOnRefused, [AName, E.Message]);
      raise;
    end;
  end;
end;

procedure TyUnregisterAddOnCss(const AName: string);
var
  i, k: Integer;
begin
  i := IndexOfAddOn(AName);
  if i < 0 then Exit;
  for k := i to High(GAddOns) - 1 do
    GAddOns[k] := GAddOns[k + 1];
  SetLength(GAddOns, Length(GAddOns) - 1);
end;

function TyAddOnCss: string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(GAddOns) do
  begin
    if i > 0 then
      Result := Result + LineEnding;
    Result := Result + GAddOns[i].Css;
  end;
end;

function TyAddOnNames: TStringArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, Length(GAddOns));
  for i := 0 to High(GAddOns) do
    Result[i] := GAddOns[i].Name;
end;

function TyAddOnCssOf(const AName: string): string;
var
  i: Integer;
begin
  i := IndexOfAddOn(AName);
  if i < 0 then
    Result := ''
  else
    Result := GAddOns[i].Css;
end;

function Unite(const ABase: array of string; AWhich: Boolean): TStringArray;
var
  all: TStringList;
  i, k: Integer;
  v: TTyCssVocabulary;
begin
  all := TStringList.Create;
  try
    for i := 0 to High(ABase) do
      all.Add(ABase[i]);
    for i := 0 to High(GAddOns) do
    begin
      v := TyCssVocabularyOf(GAddOns[i].Css);
      if AWhich then
        for k := 0 to High(v.Tokens) do all.Add(v.Tokens[k])
      else
        for k := 0 to High(v.TypeKeys) do all.Add(v.TypeKeys[k]);
    end;
    Result := SortedUnique(all);
  finally
    all.Free;
  end;
end;

function TyCatalogAllTokens: TStringArray;
begin
  Result := Unite(TyCatalogTokens, True);
end;

function TyCatalogAllTypeKeys: TStringArray;
begin
  Result := Unite(TyCatalogTypeKeys, False);
end;

procedure TyAddAddOnCssListener(AProc: TTyAddOnCssListener);
begin
  SetLength(GListeners, Length(GListeners) + 1);
  GListeners[High(GListeners)] := AProc;
end;

procedure TyRemoveAddOnCssListener(AProc: TTyAddOnCssListener);
var
  i, k: Integer;
begin
  for i := 0 to High(GListeners) do
    if GListeners[i] = AProc then
    begin
      for k := i to High(GListeners) - 1 do
        GListeners[k] := GListeners[k + 1];
      SetLength(GListeners, Length(GListeners) - 1);
      Exit;
    end;
end;

end.
