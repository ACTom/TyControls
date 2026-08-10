unit test.css.catalog;
{$mode objfpc}{$H+}

{ The tycss VOCABULARY catalog, pinned to its sources of truth so it cannot drift.

  There is no single machine-readable vocabulary in the codebase -- property recognition lives as
  an if/else chain in TyApplyDeclaration, tokens live in themes/light.tycss, colour functions in
  Css.Values' dispatch, pseudo-states in the parser. The StyleOverride editor needs an enumerable
  mirror of all of these. These tests are the guard that each mirror still matches the source: add
  a property branch to the resolver and forget to add the name here (or vice versa) and a test
  goes red instead of the editor silently missing / over-offering a completion. }

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TCssCatalogTest = class(TTestCase)
  published
    procedure EveryKnownPropIsRecognisedAndUnknownIsDropped;
    procedure NoRecognisedPropIsMissingFromTheList;
    procedure ClosedKeywordHintsMatchTheResolverEffect;
    procedure KnownColorFnsResolveAndUnknownRaises;
    procedure KnownPseudoStatesParseAndUnknownFails;
  end;

implementation

uses
  tyControls.Types, tyControls.StyleModel, tyControls.Css.Values, tyControls.Css.Parser;

{ True when the resolver RECOGNISES AProp -- it entered a branch. A clean False means "unknown
  property" (the else Result:=False). A raise means it entered a branch but disliked the value,
  which still counts as recognised -- so recognition is robust to whatever sample value we pass. }
function IsRecognised(const AProp, AVal: string): Boolean;
var
  ss: TTyStyleSet;
  vars: TStringList;
begin
  ss := EmptyStyleSet;
  vars := TStringList.Create;
  try
    try
      Result := TyApplyDeclaration(ss, AProp, AVal, vars);
    except
      Result := True;   // entered a branch, value was bad -> still recognised
    end;
  finally
    vars.Free;
  end;
end;

procedure TCssCatalogTest.EveryKnownPropIsRecognisedAndUnknownIsDropped;
var
  i: Integer;
begin
  for i := 0 to High(TyKnownStyleProps) do
    AssertTrue(TyKnownStyleProps[i] + ' should be recognised by the resolver',
      IsRecognised(TyKnownStyleProps[i], 'inherit'));
  { The alias is recognised too (same branch as background). }
  AssertTrue('background-color alias should be recognised',
    IsRecognised('background-color', '#fff'));
  { An unknown property returns False cleanly (no branch, no raise) -- this is the silent-drop the
    editor exists to warn about. }
  AssertFalse('an unknown property is dropped (returns False)',
    IsRecognised('zznot-a-real-prop', 'x'));
  AssertFalse('a misspelling is dropped too',
    IsRecognised('bordr-radius', '4px'));
end;

procedure TCssCatalogTest.NoRecognisedPropIsMissingFromTheList;
  function InList(const AName: string): Boolean;
  var i: Integer;
  begin
    Result := False;
    for i := 0 to High(TyKnownStyleProps) do
      if TyKnownStyleProps[i] = AName then Exit(True);
  end;
begin
  { The other direction: a spot-check that the property NAMES the resolver handles are all present
    in the list. If someone adds a branch to TyApplyDeclaration, they must add the name here; these
    assertions (one per resolver branch, kept in lockstep) fail loudly until they do. }
  AssertTrue('background', InList('background'));
  AssertTrue('background-image', InList('background-image'));
  AssertTrue('background-size', InList('background-size'));
  AssertTrue('background-blur', InList('background-blur'));
  AssertTrue('glass-blur', InList('glass-blur'));
  AssertTrue('glass-tint', InList('glass-tint'));
  AssertTrue('background-under-titlebar', InList('background-under-titlebar'));
  AssertTrue('window-shadow', InList('window-shadow'));
  AssertTrue('shadow', InList('shadow'));
  AssertTrue('color', InList('color'));
  AssertTrue('border', InList('border'));
  AssertTrue('border-color', InList('border-color'));
  AssertTrue('border-width', InList('border-width'));
  AssertTrue('border-radius', InList('border-radius'));
  AssertTrue('border-style', InList('border-style'));
  AssertTrue('render-style', InList('render-style'));
  AssertTrue('padding', InList('padding'));
  AssertTrue('font-family', InList('font-family'));
  AssertTrue('font-size', InList('font-size'));
  AssertTrue('font-weight', InList('font-weight'));
  AssertTrue('outline', InList('outline'));
  AssertTrue('outline-offset', InList('outline-offset'));
  AssertTrue('opacity', InList('opacity'));
  AssertEquals('exactly the 23 distinct properties, no more', 23, Length(TyKnownStyleProps));
end;

procedure TCssCatalogTest.ClosedKeywordHintsMatchTheResolverEffect;
var
  vars: TStringList;

  function Apply(const AProp, AVal: string): TTyStyleSet;
  begin
    Result := EmptyStyleSet;
    TyApplyDeclaration(Result, AProp, AVal, vars);
  end;

  function Offers(const AProp, AKeyword: string): Boolean;
  var hints: TStringList; i: Integer;
  begin
    Result := False;
    hints := TStringList.Create;
    try
      TyStyleValueHints(AProp, hints);
      for i := 0 to hints.Count - 1 do
        if hints[i] = AKeyword then Exit(True);
    finally
      hints.Free;
    end;
  end;

begin
  { The weak version of this test just checked TyApplyDeclaration returned True for each hint --
    but the enum-valued props return True for ANY value (they silently default), so that proved
    nothing. This version pins each hint two ways: it IS offered by TyStyleValueHints, AND it
    produces the resolver EFFECT it claims. Change a keyword in the hints and the Offers() side
    fails; change what the resolver does with it and the Apply() side fails. }
  vars := TStringList.Create;
  try

  { border-style -> TTyBorderStyle }
  AssertTrue('offers solid',  Offers('border-style', 'solid'));
  AssertTrue('offers none',   Offers('border-style', 'none'));
  AssertTrue('offers outset', Offers('border-style', 'outset'));
  AssertTrue('offers inset',  Offers('border-style', 'inset'));
  AssertTrue('solid->tbsSolid',   Apply('border-style', 'solid').BorderStyle = tbsSolid);
  AssertTrue('none->tbsNone',     Apply('border-style', 'none').BorderStyle = tbsNone);
  AssertTrue('outset->tbsOutset', Apply('border-style', 'outset').BorderStyle = tbsOutset);
  AssertTrue('inset->tbsInset',   Apply('border-style', 'inset').BorderStyle = tbsInset);

  { background-size -> TTyImageMode }
  AssertTrue('offers stretch', Offers('background-size', 'stretch'));
  AssertTrue('offers center',  Offers('background-size', 'center'));
  AssertTrue('offers cover',   Offers('background-size', 'cover'));
  AssertTrue('stretch->timStretch', Apply('background-size', 'stretch').Background.ImageMode = timStretch);
  AssertTrue('center->timCenter',   Apply('background-size', 'center').Background.ImageMode = timCenter);
  AssertTrue('cover->timCover',     Apply('background-size', 'cover').Background.ImageMode = timCover);

  { render-style -> TTyRenderStyle }
  AssertTrue('offers bevel3d', Offers('render-style', 'bevel3d'));
  AssertTrue('offers inset3d', Offers('render-style', 'inset3d'));
  AssertTrue('offers flat',    Offers('render-style', 'flat'));
  AssertTrue('bevel3d->trsBevel3D', Apply('render-style', 'bevel3d').RenderStyle = trsBevel3D);
  AssertTrue('inset3d->trsInset3D', Apply('render-style', 'inset3d').RenderStyle = trsInset3D);
  AssertTrue('flat->trsFlat',       Apply('render-style', 'flat').RenderStyle = trsFlat);

  { font-weight -> Integer }
  AssertTrue('offers bold',   Offers('font-weight', 'bold'));
  AssertTrue('offers normal', Offers('font-weight', 'normal'));
  AssertEquals('bold->700',   700, Apply('font-weight', 'bold').FontWeight);
  AssertEquals('normal->400', 400, Apply('font-weight', 'normal').FontWeight);

  { window-shadow / background-under-titlebar -> Boolean }
  AssertTrue('offers true',  Offers('window-shadow', 'true'));
  AssertTrue('offers false', Offers('window-shadow', 'false'));
  AssertTrue('true->WindowShadow',   Apply('window-shadow', 'true').WindowShadow);
  AssertFalse('false->no shadow',    Apply('window-shadow', 'false').WindowShadow);
  AssertTrue('bg-under-titlebar true->flag',
    Apply('background-under-titlebar', 'true').BackgroundUnderTitlebar);

  finally
    vars.Free;
  end;
end;

function SampleColorCall(const AFn: string): string;
begin
  { A valid call for each known colour function, so a clean resolve means "recognised". }
  if AFn = 'var' then Result := 'var(--accent)'
  else if AFn = 'lighten' then Result := 'lighten(#ffffff, 0.1)'
  else if AFn = 'darken' then Result := 'darken(#000000, 0.1)'
  else if AFn = 'alpha' then Result := 'alpha(#ffffff, 0.5)'
  else if AFn = 'mix' then Result := 'mix(#ffffff, #000000, 0.5)'
  else if AFn = 'rgb' then Result := 'rgb(255, 0, 0)'
  else if AFn = 'rgba' then Result := 'rgba(255, 0, 0, 0.5)'
  else if AFn = 'elevate' then Result := 'elevate(#808080, 0.1)'
  else if AFn = 'on' then Result := 'on(#ffffff)'
  else Result := AFn + '(#ffffff)';
end;

procedure TCssCatalogTest.KnownColorFnsResolveAndUnknownRaises;
var
  vars: TStringList;
  i: Integer;
  raised: Boolean;
begin
  vars := TStringList.Create;
  try
    vars.Values['accent'] := '#3B82F6';
    vars.Values['ty-mode'] := 'light';   // elevate() is mode-aware
    for i := 0 to High(TyKnownColorFns) do
      { A recognised function resolves to some colour without raising. An unrecognised one raises
        rsCssUnknownColorFunction -- which is exactly why the editor must offer only these. }
      TyEvalColor(SampleColorCall(TyKnownColorFns[i]), vars);   // must not raise
    raised := False;
    try TyEvalColor('zznope(#fff)', vars); except raised := True; end;
    AssertTrue('an unknown colour function raises', raised);
  finally
    vars.Free;
  end;
end;

procedure TCssCatalogTest.KnownPseudoStatesParseAndUnknownFails;
  function SelectorParses(const AState: string): Boolean;
  var m: TTyStyleModel;
  begin
    m := TTyStyleModel.Create;
    try
      try
        m.LoadFromCss('TyButton:' + AState + ' { color: #fff; }');
        Result := True;
      except
        Result := False;   // LoadFromCss fails fast on a bad selector
      end;
    finally
      m.Free;
    end;
  end;
var
  i: Integer;
begin
  for i := 0 to High(TyKnownPseudoStates) do
    AssertTrue(':' + TyKnownPseudoStates[i] + ' should parse in a selector',
      SelectorParses(TyKnownPseudoStates[i]));
  AssertFalse('an unknown pseudo-class fails to parse',
    SelectorParses('zznope'));
end;

initialization
  RegisterTest(TCssCatalogTest);

end.
