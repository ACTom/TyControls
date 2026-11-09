unit test.css.addons;
{$mode objfpc}{$H+}

{ The add-on registry: an add-on package registers its own tycss and the core's vocabulary
  (tokens, typeKeys) grows with it; the built-in base layer of every style model carries it. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.StyleModel;

type
  { The add-ons registered when a test starts -- a program that links an add-on package has it
    registered by the package's initialization -- set aside so the test sees an empty registry,
    and put back after it. Setting aside is an unregistration and putting back a registration:
    each reseeds the style models alive. }
  TTyAddOnsAside = record
    Names, Texts: TStringArray;
  end;

function TySetAsideAddOns: TTyAddOnsAside;
procedure TyPutBackAddOns(const AAside: TTyAddOnsAside);

type
  TTyCssAddOnsTest = class(TTestCase)
  private
    FRegistered: TStringArray;
    FAside: TTyAddOnsAside;
    { TyRegisterAddOnCss, noting the name for TearDown }
    procedure Reg(const AName, ACss: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheVocabularyOfLightIsTheCatalog;
    procedure TestARegisteredCssJoinsTheCatalog;
    procedure TestReRegisteringReplaces;
    procedure TestNoAddOnIsTheCatalogAlone;
    procedure TestAListenerHearsARegistration;
    procedure TestAListenerHearsAnUnregistration;
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
    procedure TestARegistrationLoadsTheBaseForLiveModelsOnly;
    procedure TestUnregisteringDropsItFromALiveModel;
    procedure TestUnregisteringWhatAnotherBuildsOnDropsBoth;
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
  { builds on cZz: its rule reads cZzInk's variable, so it loads only while cZz is there }
  cUser = 'test.zz.user';
  cUserCss = 'TyZzUser{background:var(--zz-ink);}';

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

{ An unregistration reseeds every live model, so a style model alive across the test (a default
  controller's, say) drops what the test registered from its base layer. }
procedure ForgetAddOn(const AName: string);
begin
  TyUnregisterAddOnCss(AName);
end;

function TySetAsideAddOns: TTyAddOnsAside;
var
  i: Integer;
begin
  Result.Names := TyAddOnNames;
  Result.Texts := nil;
  SetLength(Result.Texts, Length(Result.Names));
  for i := 0 to High(Result.Names) do
  begin
    Result.Texts[i] := TyAddOnCssOf(Result.Names[i]);
    TyUnregisterAddOnCss(Result.Names[i]);
  end;
end;

procedure TyPutBackAddOns(const AAside: TTyAddOnsAside);
var
  i: Integer;
begin
  for i := 0 to High(AAside.Names) do
    TyRegisterAddOnCss(AAside.Names[i], AAside.Texts[i]);
end;

procedure TTyCssAddOnsTest.SetUp;
begin
  inherited SetUp;
  FAside := TySetAsideAddOns;
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
  TyPutBackAddOns(FAside);
  FAside.Names := nil;
  FAside.Texts := nil;
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

procedure TTyCssAddOnsTest.TestAListenerHearsAnUnregistration;
begin
  Reg('t1', 'a{}');
  Reg('t2', 'b{}');
  GHeard := 0;
  GSeen := 'not called';
  TyAddAddOnCssListener(@Heard);
  TyAddAddOnCssListener(@Saw);
  TyUnregisterAddOnCss('t1');
  AssertEquals('heard once', 1, GHeard);
  AssertEquals('after the name was forgotten', 'b{}', GSeen);
  TyUnregisterAddOnCss('t1');
  TyUnregisterAddOnCss('never registered');
  AssertEquals('a name that is not registered tells no one', 1, GHeard);
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

{ The message the construction of a model raised; '' when it was built. }
function CreateRefusal: string;
var
  m: TTyStyleModel;
begin
  Result := '';
  try
    m := TTyStyleModel.Create;
    m.Free;
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

procedure TTyStyleModelAddOnTest.TearDown;
begin
  FreeAndNil(FModel);
  TyUnregisterAddOnCss(cBroken);   // only there if a refusal failed
  ForgetAddOn(cUser);              // only there if an unregistration failed to drop it
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
  { With no model alive nothing loads a text at its registration (start-up pays for no load);
    the next model's seed finds the broken one, drops it and raises. A good add-on registered
    alongside stays. Run on its own the suite has no model alive at all; in a process where
    another one is (a serial full run), that model's reseed refuses the text at its
    registration instead, and what is left behind must be the same. }
  before := TyAddOnCss;
  TyRegisterAddOnCss(cZz, cZzCss);
  good := TyAddOnCss;
  if TyLiveStyleModelCountForTest = 0 then
  begin
    TyRegisterAddOnCss(cBroken, cBrokenCss);   // does not raise
    AssertTrue('recorded for now', Pos(cBrokenCss, TyAddOnCss) > 0);
    msg := CreateRefusal;
    AssertTrue('the first model refused it, naming the add-on: "' + msg + '"',
      Pos(cBroken, msg) > 0);
  end
  else
  begin
    msg := RefusalOf(cBroken, cBrokenCss);
    AssertTrue('refused by the live model elsewhere, naming the add-on: "' + msg + '"',
      Pos(cBroken, msg) > 0);
  end;
  AssertEquals('the broken text is gone, the good one stays', good, TyAddOnCss);
  later := TTyStyleModel.Create;   // raises if the broken text had stayed
  try
    AssertEquals('the next model has the good add-on', '7px', later.ResolveToken('--zz-gap'));
    AssertEquals('and its rule', TTyColor($FF123456),
      later.ResolveStyle('TyZzThing', '', []).Background.Color);
  finally
    later.Free;
  end;
  ForgetAddOn(cZz);
  AssertEquals('back to the start', before, TyAddOnCss);

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

procedure TTyStyleModelAddOnTest.TestARegistrationLoadsTheBaseForLiveModelsOnly;
var
  alive, loads: Integer;
begin
  { One base load per model alive and none more: with none alive (an add-on's initialization,
    at start-up) a registration builds nothing. }
  alive := TyLiveStyleModelCountForTest;
  loads := TyBaseLoadsForTest;
  TyRegisterAddOnCss(cZz, cZzCss);
  AssertEquals('loads with ' + IntToStr(alive) + ' models alive', loads + alive,
    TyBaseLoadsForTest);
  FModel := TTyStyleModel.Create;
  loads := TyBaseLoadsForTest;
  TyRegisterAddOnCss(cZz, cZzCss + cZzInk);
  AssertEquals('loads with one more alive', loads + alive + 1, TyBaseLoadsForTest);
  AssertEquals('and it reached that one', '#13579B', FModel.RawVar('--zz-ink'));
end;

procedure TTyStyleModelAddOnTest.TestUnregisteringDropsItFromALiveModel;
var
  v0: Cardinal;
  later: TTyStyleModel;
begin
  { A third party that unregisters its add-on: the models alive drop it, as a registration
    reaches them. Each memo is read first, so a reseed that left one stale shows. }
  TyRegisterAddOnCss(cZz, cZzCss + cZzInk);
  FModel := TTyStyleModel.Create;
  FModel.LoadFromCss('TyButton{background:#00FF00;}');
  AssertEquals('the token before', '7px', FModel.ResolveToken('--zz-gap'));
  AssertEquals('the raw text before', '7px', FModel.RawVar('--zz-gap'));
  AssertEquals('the metric before', 7, FModel.ResolveMetric('--zz-gap', 3));
  AssertEquals('the colour before', TTyColor($FF13579B),
    FModel.ResolveColorToken('--zz-ink', TTyColor($FF000001)));
  AssertEquals('the rule before', TTyColor($FF123456),
    FModel.ResolveStyle('TyZzThing', '', []).Background.Color);
  v0 := FModel.ThemeVersion;
  TyUnregisterAddOnCss(cZz);
  AssertEquals('forgotten', '', TyAddOnCssOf(cZz));
  AssertTrue('the theme version moves', FModel.ThemeVersion <> v0);
  AssertEquals('the token is gone', '', FModel.ResolveToken('--zz-gap'));
  AssertEquals('the raw text is gone', '', FModel.RawVar('--zz-gap'));
  AssertEquals('the metric falls back', 3, FModel.ResolveMetric('--zz-gap', 3));
  AssertEquals('the colour falls back', TTyColor($FF000001),
    FModel.ResolveColorToken('--zz-ink', TTyColor($FF000001)));
  AssertFalse('the rule is gone', tpBackground in FModel.ResolveStyle('TyZzThing', '', []).Present);
  AssertEquals('the user layer stays', TTyColor($FF00FF00),
    FModel.ResolveStyle('TyButton', '', []).Background.Color);
  later := TTyStyleModel.Create;
  try
    AssertEquals('a new model has none of it either', '', later.ResolveToken('--zz-gap'));
  finally
    later.Free;
  end;
end;

procedure TTyStyleModelAddOnTest.TestUnregisteringWhatAnotherBuildsOnDropsBoth;
var
  msg: string;
begin
  { cUser's rule reads cZz's variable. Without cZz its text does not load, so the reseed drops
    it too; the models alive must end up with neither, not with the base they had. }
  TyRegisterAddOnCss(cZz, cZzCss + cZzInk);
  TyRegisterAddOnCss(cUser, cUserCss);
  FModel := TTyStyleModel.Create;
  AssertEquals('the second builds on the first', TTyColor($FF13579B),
    FModel.ResolveStyle('TyZzUser', '', []).Background.Color);
  msg := '';
  try
    TyUnregisterAddOnCss(cZz);
  except
    on E: Exception do
      msg := E.Message;
  end;
  AssertTrue('raised, naming the add-on unregistered: "' + msg + '"',
    Pos('"' + cZz + '"', msg) > 0);
  AssertTrue('and the one dropped with it', Pos('"' + cUser + '"', msg) > 0);
  AssertEquals('both are forgotten', '', TyAddOnCssOf(cZz) + TyAddOnCssOf(cUser));
  AssertEquals('the live model has neither token', '', FModel.ResolveToken('--zz-gap'));
  AssertFalse('nor rule', tpBackground in FModel.ResolveStyle('TyZzUser', '', []).Present);
  AssertFalse('nor the first one''s', tpBackground in FModel.ResolveStyle('TyZzThing', '', []).Present);
end;

initialization
  RegisterTest(TTyCssAddOnsTest);
  RegisterTest(TTyStyleModelAddOnTest);

end.
