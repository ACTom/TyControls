unit tyControls.ThemeRegistry;
{$mode objfpc}{$H+}
{ B — Named theme registry (theme-system v2, Phase 2).

  A process-global, case-insensitive name->source map so an application can switch
  skins by NAME instead of by path:  Controller.ThemeName := 'dark'.

  This is the lookup half of the §3.8 "switch current theme" path. The heavy lifting
  (replace layer-1 + bump ThemeVersion) lives in TTyStyleModel.LoadFromFile, which the
  controller drives through the REPLACE path; the registry only resolves a name to the
  theme's source.

  Full ITyThemeSource (directory / zip bundles) is the Bundles feature (C, a later
  commit). Until that lands, a theme is registered by FILE PATH (themes/*.tycss) and
  resolved to that path; the controller loads it via Model.LoadFromFile (the REPLACE
  path that bumps ThemeVersion). The API is deliberately source-shaped (resolve returns
  an opaque "source" string = the file path today) so the file map can widen to
  ITyThemeSource later without changing call sites. }
interface
uses
  Classes, SysUtils;

{ Register a theme NAME bound to a .tycss FILE path. Case-insensitive; re-registering
  the same name replaces the previous binding (last wins). An empty name is ignored. }
procedure TyRegisterThemeFile(const AName, AFileName: string);

{ Register a theme NAME bound to a FOLDER (bundle dir). Until ITyThemeSource lands, the
  entry stylesheet is assumed to be <ADir>/theme.tycss; the resolved source is that path.
  (Back-compat seam for the Bundles feature; today it just composes the entry path.) }
procedure TyRegisterThemeFolder(const AName, ADir: string);

{ Resolve a registered NAME to its source (today: the .tycss file path). Case-insensitive.
  Returns False (and ASource='') if the name is not registered. }
function TyResolveTheme(const AName: string; out ASource: string): Boolean;

{ Register a theme NAME bound to an inline CSS string (a compiled-in built-in theme).
  Case-insensitive; last registration wins. An empty name is ignored. }
procedure TyRegisterThemeCss(const AName, ACss: string);

{ Resolve a registered NAME to its inline CSS. Case-insensitive. False/'' if not a CSS theme. }
function TyResolveThemeCss(const AName: string; out ACss: string): Boolean;

{ All registered theme names (file sources first, then CSS sources). }
function TyThemeNames: TStringArray;

{ Remove a registered name (case-insensitive). No-op if it was not registered. }
procedure TyUnregisterTheme(const AName: string);

{ True if NAME is registered (case-insensitive). }
function TyThemeRegistered(const AName: string): Boolean;

implementation

var
  GThemes: TStringList = nil;   // Name=Source map; CaseSensitive=False, Sorted

function Registry: TStringList;
begin
  if GThemes = nil then
  begin
    GThemes := TStringList.Create;
    GThemes.CaseSensitive := False;   // case-insensitive name lookup (§B)
    // Kept UNSORTED: Values[name]:=v modifies the matching pair in place, which a
    // sorted TStringList forbids ("Operation not allowed on sorted list"). IndexOfName
    // is case-insensitive here (CaseSensitive=False), so name lookups stay correct.
  end;
  Result := GThemes;
end;

type
  { Holds one compiled-in theme's CSS text (a TStringList Value can't carry newlines,
    so CSS sources are stored as objects). }
  TTyThemeCssHolder = class
    Css: string;
    constructor Create(const ACss: string);
  end;

var
  GCssThemes: TStringList = nil;   // Name -> TTyThemeCssHolder; CaseSensitive=False, OwnsObjects

constructor TTyThemeCssHolder.Create(const ACss: string);
begin
  inherited Create;
  Css := ACss;
end;

function CssRegistry: TStringList;
begin
  if GCssThemes = nil then
  begin
    GCssThemes := TStringList.Create;
    GCssThemes.CaseSensitive := False;
    GCssThemes.OwnsObjects := True;
  end;
  Result := GCssThemes;
end;

procedure TyRegisterThemeCss(const AName, ACss: string);
var idx: Integer; nm: string;
begin
  nm := Trim(AName);
  if nm = '' then Exit;
  idx := CssRegistry.IndexOf(nm);
  if idx >= 0 then
    TTyThemeCssHolder(CssRegistry.Objects[idx]).Css := ACss   // last wins
  else
    CssRegistry.AddObject(nm, TTyThemeCssHolder.Create(ACss));
end;

function TyResolveThemeCss(const AName: string; out ACss: string): Boolean;
var idx: Integer;
begin
  ACss := '';
  if (GCssThemes = nil) or (Trim(AName) = '') then Exit(False);
  idx := GCssThemes.IndexOf(Trim(AName));
  if idx < 0 then Exit(False);
  ACss := TTyThemeCssHolder(GCssThemes.Objects[idx]).Css;
  Result := True;
end;

procedure TyRegisterThemeFile(const AName, AFileName: string);
begin
  if Trim(AName) = '' then Exit;
  // Values[] on a case-insensitive list does a case-insensitive name match and
  // replaces in place, giving "last registration wins" with no duplicates.
  Registry.Values[Trim(AName)] := AFileName;
end;

procedure TyRegisterThemeFolder(const AName, ADir: string);
var
  d: string;
begin
  if Trim(AName) = '' then Exit;
  d := ADir;
  if (d <> '') and (d[Length(d)] <> PathDelim) and (d[Length(d)] <> '/')
     and (d[Length(d)] <> '\') then
    d := d + PathDelim;
  // Bundle dirs use theme.tycss as the entry sheet (matches the Bundles design default).
  TyRegisterThemeFile(AName, d + 'theme.tycss');
end;

function TyResolveTheme(const AName: string; out ASource: string): Boolean;
var
  idx: Integer;
begin
  ASource := '';
  if (GThemes = nil) or (Trim(AName) = '') then Exit(False);
  idx := GThemes.IndexOfName(Trim(AName));   // case-insensitive (list is CaseSensitive=False)
  if idx < 0 then Exit(False);
  ASource := GThemes.ValueFromIndex[idx];
  Result := True;
end;

function TyThemeNames: TStringArray;
var
  i, n: Integer;
begin
  n := 0;
  if GThemes <> nil then n := GThemes.Count;
  if GCssThemes <> nil then Inc(n, GCssThemes.Count);
  SetLength(Result, n);
  n := 0;
  if GThemes <> nil then
    for i := 0 to GThemes.Count - 1 do begin Result[n] := GThemes.Names[i]; Inc(n); end;
  if GCssThemes <> nil then
    for i := 0 to GCssThemes.Count - 1 do begin Result[n] := GCssThemes[i]; Inc(n); end;
end;

procedure TyUnregisterTheme(const AName: string);
var
  idx: Integer;
begin
  if (GThemes <> nil) and (Trim(AName) <> '') then
  begin
    idx := GThemes.IndexOfName(Trim(AName));
    if idx >= 0 then GThemes.Delete(idx);
  end;
  if (GCssThemes <> nil) and (Trim(AName) <> '') then
  begin
    idx := GCssThemes.IndexOf(Trim(AName));
    if idx >= 0 then GCssThemes.Delete(idx);
  end;
end;

function TyThemeRegistered(const AName: string): Boolean;
begin
  Result := ((GThemes <> nil) and (Trim(AName) <> '') and (GThemes.IndexOfName(Trim(AName)) >= 0))
         or ((GCssThemes <> nil) and (Trim(AName) <> '') and (GCssThemes.IndexOf(Trim(AName)) >= 0));
end;

finalization
  FreeAndNil(GThemes);
  FreeAndNil(GCssThemes);   // OwnsObjects frees the CSS holders
end.
