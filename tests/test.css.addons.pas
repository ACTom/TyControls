unit test.css.addons;
{$mode objfpc}{$H+}

{ The add-on registry: an add-on package registers its own tycss and the core's vocabulary
  (tokens, typeKeys) grows with it; the built-in base layer of every style model carries it. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.StyleModel;

type
  TTyCssAddOnsTest = class(TTestCase)
  private
    FRegistered: TStringArray;
    { TyRegisterAddOnCss, noting the name for TearDown }
    procedure Reg(const AName, ACss: string);
  protected
    procedure TearDown; override;
  published
    procedure TestTheVocabularyOfLightIsTheCatalog;
    procedure TestARegisteredCssJoinsTheCatalog;
    procedure TestReRegisteringReplaces;
    procedure TestNoAddOnIsTheCatalogAlone;
    procedure TestAListenerHearsARegistration;
    procedure TestCommentsAndUsagesAreNotVocabulary;
    procedure TestARefusingListenerRollsTheRegistrationBack;
  end;

  { What an add-on registered is in the built-in base layer of every style model, one made
    before the registration included, under the user layer as light.tycss's own rules are. }
  TTyStyleModelAddOnTest = class(TTestCase)
  private
    FModel: TTyStyleModel;
  protected
    procedure TearDown; override;
  published
    procedure TestAnAddOnRuleReachesANewModel;
    procedure TestARegistrationAfterTheModelReachesIt;
    procedure TestAUserThemeOverridesAnAddOnRule;
    procedure TestAModeSwitchKeepsTheAddOn;
    procedure TestARegistrationKeepsTheUserLayer;
    procedure TestAUserRuleBeforeALateRegistrationStillWins;
    procedure TestAFreedModelLeavesTheLiveList;
    procedure TestABrokenAddOnIsRefusedAndLeavesNothing;
  end;

implementation

uses
  tyControls.Types, tyControls.Css.Catalog, tyControls.Css.AddOns;

const
  cZz = 'test.zz';
  cZzCss = ':root{--zz-gap:7px;} TyZzThing{background:#123456;}';
  cZzDark = ' @mode dark { :root{--zz-gap:9px;} }';
  cZzInk = ' :root{--zz-ink:#13579B;}';
  cZzOther = ' TyZzOther{background:#654321;}';
  { parses, but its rule names a variable nobody defines: the load refuses it }
  cBroken = 'test.zz.broken';
  cBrokenCss = ':root{--zz-gap:8px;} TyZzThing{background:var(--zz-nowhere);}';

var
  GHeard: Integer;

procedure Heard;
begin
  Inc(GHeard);
end;

var
  GSeen: string;

procedure Saw;
begin
  GSeen := TyAddOnCss;
end;

procedure Refuse;
begin
  if Pos('REFUSE', TyAddOnCss) > 0 then
    raise Exception.Create('refused here');
end;

function LightText: string;
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim +
      'light.tycss');
    Result := sl.Text;
  finally
    sl.Free;
  end;
end;

function Has(const A: TStringArray; const S: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(A) do
    if A[i] = S then
      Exit(True);
  Result := False;
end;

procedure AssertAscending(const AMsg: string; const A: TStringArray);
var
  i: Integer;
begin
  for i := 1 to High(A) do
    TTestCase.AssertTrue(AMsg + ' ascending at ' + IntToStr(i), A[i - 1] < A[i]);
end;

{ TyUnregisterAddOnCss tells no listener, so a style model alive across the test (a default
  controller's, say) would keep what the test registered in its base layer. Registering the name
  empty first reseeds every live model without it; unregistering then drops the empty entry. }
procedure ForgetAddOn(const AName: string);
begin
  TyRegisterAddOnCss(AName, '');
  TyUnregisterAddOnCss(AName);
end;

procedure TTyCssAddOnsTest.Reg(const AName, ACss: string);
begin
  if not Has(FRegistered, AName) then
  begin
    SetLength(FRegistered, Length(FRegistered) + 1);
    FRegistered[High(FRegistered)] := AName;
  end;
  TyRegisterAddOnCss(AName, ACss);
end;

procedure TTyCssAddOnsTest.TearDown;
var
  i: Integer;
begin
  TyRemoveAddOnCssListener(@Heard);
  TyRemoveAddOnCssListener(@Saw);
  TyRemoveAddOnCssListener(@Refuse);
  for i := 0 to High(FRegistered) do
    ForgetAddOn(FRegistered[i]);
  FRegistered := nil;
  inherited TearDown;
end;

procedure TTyCssAddOnsTest.TestTheVocabularyOfLightIsTheCatalog;
var
  v: TTyCssVocabulary;
  i: Integer;
begin
  v := TyCssVocabularyOf(LightText);
  AssertEquals('token count', Length(TyCatalogTokens), Length(v.Tokens));
  AssertEquals('typeKey count', Length(TyCatalogTypeKeys), Length(v.TypeKeys));
  for i := 0 to High(v.Tokens) do
    AssertEquals('token ' + IntToStr(i), TyCatalogTokens[i], v.Tokens[i]);
  for i := 0 to High(v.TypeKeys) do
    AssertEquals('typeKey ' + IntToStr(i), TyCatalogTypeKeys[i], v.TypeKeys[i]);
end;

procedure TTyCssAddOnsTest.TestARegisteredCssJoinsTheCatalog;
var
  t, k: TStringArray;
begin
  Reg('t1', ':root{--zz-a:1px;} TyZzThing{color:#FF0000;}');
  t := TyCatalogAllTokens;
  k := TyCatalogAllTypeKeys;
  AssertTrue('--zz-a joined', Has(t, '--zz-a'));
  AssertTrue('TyZzThing joined', Has(k, 'TyZzThing'));
  AssertTrue('the catalog stays', Has(t, '--accent'));
  AssertAscending('tokens', t);
  AssertAscending('typeKeys', k);
end;

procedure TTyCssAddOnsTest.TestReRegisteringReplaces;
begin
  Reg('t1', 'FIRST{}');
  Reg('t1', 'SECOND{}');
  AssertEquals('only the second', 'SECOND{}', TyAddOnCss);
  Reg('t2', 'THIRD{}');
  AssertEquals('registration order', 'SECOND{}' + LineEnding + 'THIRD{}', TyAddOnCss);
end;

procedure TTyCssAddOnsTest.TestNoAddOnIsTheCatalogAlone;
var
  t, k: TStringArray;
  i: Integer;
begin
  AssertEquals('no css', '', TyAddOnCss);
  t := TyCatalogAllTokens;
  k := TyCatalogAllTypeKeys;
  AssertEquals('token count', Length(TyCatalogTokens), Length(t));
  AssertEquals('typeKey count', Length(TyCatalogTypeKeys), Length(k));
  for i := 0 to High(t) do
    AssertEquals('token ' + IntToStr(i), TyCatalogTokens[i], t[i]);
  for i := 0 to High(k) do
    AssertEquals('typeKey ' + IntToStr(i), TyCatalogTypeKeys[i], k[i]);
end;

procedure TTyCssAddOnsTest.TestAListenerHearsARegistration;
begin
  GHeard := 0;
  TyAddAddOnCssListener(@Heard);
  Reg('t1', 'a{}');
  AssertEquals('heard once', 1, GHeard);
  TyRemoveAddOnCssListener(@Heard);
  Reg('t1', 'b{}');
  AssertEquals('not after removal', 1, GHeard);
end;

procedure TTyCssAddOnsTest.TestCommentsAndUsagesAreNotVocabulary;
var
  v: TTyCssVocabulary;
begin
  v := TyCssVocabularyOf('/* TyInComment --in-comment: 1 */ TyReal{--b : 2; --b:3; ' +
    'color: var(--used); x: TyNot_this} Ty1 TyAb2 TyAb2');
  AssertEquals('one token, de-duplicated', 1, Length(v.Tokens));
  AssertEquals('--b', '--b', v.Tokens[0]);
  AssertEquals('typeKeys', 2, Length(v.TypeKeys));
  AssertEquals('TyAb2', 'TyAb2', v.TypeKeys[0]);
  AssertEquals('TyReal', 'TyReal', v.TypeKeys[1]);
end;

procedure TTyCssAddOnsTest.TestARefusingListenerRollsTheRegistrationBack;
var
  msg: string;
begin
  Reg('t1', 'KEEP{}');
  TyAddAddOnCssListener(@Saw);
  TyAddAddOnCssListener(@Refuse);
  msg := '';
  try
    Reg('t1', 'REFUSE{}');
  except
    on E: Exception do
      msg := E.Message;
  end;
  AssertTrue('raised, naming the add-on: "' + msg + '"', Pos('"t1"', msg) > 0);
  AssertTrue('with the listener''s own message', Pos('refused here', msg) > 0);
  AssertEquals('the earlier text is back', 'KEEP{}', TyAddOnCss);
  AssertEquals('a listener called before the refusal heard the rollback', 'KEEP{}', GSeen);
end;

{ TTyStyleModelAddOnTest }

{ The message a refused registration raised; '' when it was accepted. }
function RefusalOf(const AName, ACss: string): string;
begin
  Result := '';
  try
    TyRegisterAddOnCss(AName, ACss);
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

procedure TTyStyleModelAddOnTest.TearDown;
begin
  FreeAndNil(FModel);
  TyUnregisterAddOnCss(cBroken);   // only there if a refusal failed; before the reseed below
  ForgetAddOn(cZz);
  inherited TearDown;
end;

procedure TTyStyleModelAddOnTest.TestAnAddOnRuleReachesANewModel;
begin
  TyRegisterAddOnCss(cZz, cZzCss);
  FModel := TTyStyleModel.Create;
  AssertEquals('the add-on token', '7px', FModel.ResolveToken('--zz-gap'));
  AssertEquals('the add-on rule', TTyColor($FF123456),
    FModel.ResolveStyle('TyZzThing', '', []).Background.Color);
end;

procedure TTyStyleModelAddOnTest.TestARegistrationAfterTheModelReachesIt;
var
  v0: Cardinal;
begin
  FModel := TTyStyleModel.Create;
  { one read through each memo, so each holds the answer from before the registration }
  AssertEquals('no token yet', '', FModel.ResolveToken('--zz-gap'));
  AssertEquals('no raw text yet', '', FModel.RawVar('--zz-gap'));
  AssertEquals('no metric yet', 3, FModel.ResolveMetric('--zz-gap', 3));
  AssertFalse('no rule yet', tpBackground in FModel.ResolveStyle('TyZzThing', '', []).Present);
  AssertEquals('no colour yet', TTyColor($FF000001),
    FModel.ResolveColorToken('--zz-ink', TTyColor($FF000001)));
  v0 := FModel.ThemeVersion;
  TyRegisterAddOnCss(cZz, cZzCss + cZzInk);
  AssertTrue('the theme version moves', FModel.ThemeVersion <> v0);
  AssertEquals('the colour', TTyColor($FF13579B),
    FModel.ResolveColorToken('--zz-ink', TTyColor($FF000001)));
  AssertEquals('the token', '7px', FModel.ResolveToken('--zz-gap'));
  AssertEquals('the raw text', '7px', FModel.RawVar('--zz-gap'));
  AssertEquals('the metric', 7, FModel.ResolveMetric('--zz-gap', 3));
  AssertEquals('the rule', TTyColor($FF123456),
    FModel.ResolveStyle('TyZzThing', '', []).Background.Color);
end;

procedure TTyStyleModelAddOnTest.TestAUserThemeOverridesAnAddOnRule;
begin
  TyRegisterAddOnCss(cZz, cZzCss);
  FModel := TTyStyleModel.Create;
  FModel.LoadFromCss('TyZzThing{background:#FF0000;}');
  AssertEquals('the user rule', TTyColor($FFFF0000),
    FModel.ResolveStyle('TyZzThing', '', []).Background.Color);
  AssertEquals('the add-on token', '7px', FModel.ResolveToken('--zz-gap'));
end;

procedure TTyStyleModelAddOnTest.TestAModeSwitchKeepsTheAddOn;
const
  { The base layer's @mode blocks lie under a dual-mode user theme only (RebuildMergedVars), as
    TyBuiltinBaseModeCss's do. This one has both modes and nothing the add-on names. }
  cDual = '@mode light { :root{--zz-own:1px;} } @mode dark { :root{--zz-own:2px;} }';
var
  later: TTyStyleModel;

  procedure Check(AModel: TTyStyleModel; const AWhich: string);
  begin
    AModel.SetMode('dark');
    AssertEquals(AWhich + ': dark', '9px', AModel.ResolveToken('--zz-gap'));
    AModel.SetMode('light');
    AssertEquals(AWhich + ': light', '7px', AModel.ResolveToken('--zz-gap'));
  end;

begin
  FModel := TTyStyleModel.Create;
  FModel.LoadFromCss(cDual);
  FModel.SetMode('light');
  AssertEquals('nothing before', '', FModel.ResolveToken('--zz-gap'));
  TyRegisterAddOnCss(cZz, cZzCss + cZzDark);
  Check(FModel, 'a model made before');
  later := TTyStyleModel.Create;
  try
    later.LoadFromCss(cDual);
    Check(later, 'a model made after');
  finally
    later.Free;
  end;
end;

procedure TTyStyleModelAddOnTest.TestARegistrationKeepsTheUserLayer;
var
  dir, asset: string;
  sl: TStringList;
begin
  { a theme FILE, so the model also holds the folder its url() assets resolve against }
  dir := IncludeTrailingPathDelimiter(GetTempDir) + 'tyaddon_' + IntToStr(GetProcessID) + '_' +
    IntToStr(Random(1 shl 30)) + PathDelim;
  ForceDirectories(dir);
  sl := TStringList.Create;
  try
    sl.Text := 'not read';
    sl.SaveToFile(dir + 'zz.png');
    sl.Text := ':root{--zz-own:3px;} TyButton{background:#00FF00;} ' +
      'TyZzPicture{background-image:url(zz.png);} ' +
      '@mode light { :root{--zz-lit:4px;} } @mode dark { :root{--zz-lit:5px;} }';
    sl.SaveToFile(dir + 'user.tycss');
  finally
    sl.Free;
  end;
  try
    asset := ExtractFilePath(ExpandFileName(dir + 'user.tycss')) + 'zz.png';
    FModel := TTyStyleModel.Create;
    FModel.LoadFromFile(dir + 'user.tycss');
    FModel.SetMode('dark');
    FModel.SetVarOverride('accent', '#ABCDEF');
    AssertEquals('the asset before', asset,
      FModel.ResolveStyle('TyZzPicture', '', []).Background.ImagePath);
    TyRegisterAddOnCss(cZz, cZzCss);
    AssertEquals('the add-on token', '7px', FModel.ResolveToken('--zz-gap'));
    AssertEquals('the user rule', TTyColor($FF00FF00),
      FModel.ResolveStyle('TyButton', '', []).Background.Color);
    AssertEquals('the user :root', '3px', FModel.ResolveToken('--zz-own'));
    AssertEquals('the mode', 'dark', FModel.Mode);
    AssertEquals('the user @mode', '5px', FModel.ResolveToken('--zz-lit'));
    AssertEquals('the base @mode under it', '#E5E7EB', FModel.ResolveToken('--on-surface'));
    AssertEquals('the runtime override', '#ABCDEF', FModel.VarOverride('accent'));
    AssertEquals('the override applies', '#ABCDEF', FModel.ResolveToken('--accent'));
    AssertEquals('the theme''s folder', asset,
      FModel.ResolveStyle('TyZzPicture', '', []).Background.ImagePath);
  finally
    DeleteFile(dir + 'zz.png');
    DeleteFile(dir + 'user.tycss');
    RemoveDir(dir);
  end;
end;

procedure TTyStyleModelAddOnTest.TestAUserRuleBeforeALateRegistrationStillWins;
begin
  FModel := TTyStyleModel.Create;
  FModel.LoadFromCss('TyZzThing { background: #FF0000; }');
  AssertEquals('the user rule before', TTyColor($FFFF0000),
    FModel.ResolveStyle('TyZzThing', '', []).Background.Color);
  TyRegisterAddOnCss(cZz, cZzCss + cZzOther);
  AssertEquals('the user rule still wins', TTyColor($FFFF0000),
    FModel.ResolveStyle('TyZzThing', '', []).Background.Color);
  AssertEquals('a typeKey the user left to the add-on', TTyColor($FF654321),
    FModel.ResolveStyle('TyZzOther', '', []).Background.Color);
end;

procedure TTyStyleModelAddOnTest.TestAFreedModelLeavesTheLiveList;
var
  n: Integer;
  m: TTyStyleModel;
begin
  n := TyLiveStyleModelCountForTest;
  m := TTyStyleModel.Create;
  AssertEquals('a new model is listed', n + 1, TyLiveStyleModelCountForTest);
  m.Free;
  AssertEquals('a freed one is not', n, TyLiveStyleModelCountForTest);
  { a registration then reseeds the models alive only, not the freed one }
  TyRegisterAddOnCss(cZz, cZzCss);
  AssertEquals('still not', n, TyLiveStyleModelCountForTest);
end;

procedure TTyStyleModelAddOnTest.TestABrokenAddOnIsRefusedAndLeavesNothing;
var
  msg, before, good: string;
  later: TTyStyleModel;
  bg: TTyColor;
begin
  { No model of the test's own is alive. Run on its own, the suite has none alive at all, so the
    registration is checked by the listener's trial load; in a process where another model is
    alive, by its reseed. The outcome must be the same. }
  before := TyAddOnCss;
  msg := RefusalOf(cBroken, cBrokenCss);
  AssertTrue('refused, naming the add-on: "' + msg + '"', Pos(cBroken, msg) > 0);
  AssertEquals('nothing registered', before, TyAddOnCss);
  later := TTyStyleModel.Create;   // raises if the text had stayed
  try
    AssertEquals('a new model has none of it', '', later.ResolveToken('--zz-gap'));
  finally
    later.Free;
  end;

  { the same with a live model }
  FModel := TTyStyleModel.Create;
  bg := FModel.ResolveStyle('TyButton', 'primary', []).Background.Color;
  msg := RefusalOf(cBroken, cBrokenCss);
  AssertTrue('refused with a live model, naming the add-on: "' + msg + '"', Pos(cBroken, msg) > 0);
  AssertEquals('still nothing registered', before, TyAddOnCss);
  AssertEquals('the live model has none of it', '', FModel.ResolveToken('--zz-gap'));
  AssertEquals('the live model resolves as before', bg,
    FModel.ResolveStyle('TyButton', 'primary', []).Background.Color);

  { a good name re-registered with a broken text keeps its good text }
  TyRegisterAddOnCss(cZz, cZzCss);
  good := TyAddOnCss;
  msg := RefusalOf(cZz, cBrokenCss);
  AssertTrue('the re-registration refused, naming the add-on: "' + msg + '"', Pos(cZz, msg) > 0);
  AssertEquals('the good text kept', good, TyAddOnCss);
  AssertEquals('the live model keeps the good token', '7px', FModel.ResolveToken('--zz-gap'));
  AssertEquals('and the good rule', TTyColor($FF123456),
    FModel.ResolveStyle('TyZzThing', '', []).Background.Color);
  later := TTyStyleModel.Create;
  try
    AssertEquals('a new model has the good text', '7px', later.ResolveToken('--zz-gap'));
  finally
    later.Free;
  end;
end;

initialization
  RegisterTest(TTyCssAddOnsTest);
  RegisterTest(TTyStyleModelAddOnTest);

end.
