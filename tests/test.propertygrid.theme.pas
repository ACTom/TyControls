unit test.propertygrid.theme;
{$mode objfpc}{$H+}

{ The property grid's type key (#65, plan D8 / Task 5).

  TTyPropertyGrid answers a key of its own, 'TyPropertyGrid', hung on 'TyValueListEditor' through
  the #14 chain: a theme that says nothing about the property grid styles it exactly like the value
  list editor it is built on, and a theme that does can style the property grid alone. Checked:

  * the grid answers 'TyPropertyGrid' and the chain is 'TyPropertyGrid > TyValueListEditor', and
    the value list editor answers the key the chain ends in;
  * no built-in theme has a TyPropertyGrid rule;
  * in every built-in theme, light and dark, the key resolves to exactly the value list editor's
    style, at rest, under the pointer, focused and disabled;
  * a TyPropertyGrid rule changes the property grid and leaves the value list editor alone. }

interface

uses
  Classes, SysUtils, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.StyleModel, tyControls.Controller,
  tyControls.BuiltinThemes, tyControls.ValueListEditor, tyControls.PropertyGrid;

type
  TPropertyGridTypeKeyTest = class(TTestCase)
  private
    function Dump(const S: TTyStyleSet): string;
    function KeyOf(AClass: TControlClass): string;
  published
    procedure TestTheGridAnswersItsOwnKeyOnTheEditorsChain;
    procedure TestNoBuiltInThemeHasAPropertyGridRule;
    procedure TestEveryBuiltInThemeStylesItLikeTheValueListEditor;
    procedure TestATyPropertyGridRuleChangesOnlyTheGrid;
  end;

implementation

const
  CStates: array[0..3] of TTyStateSet = ([tysNormal], [tysHover], [tysFocused], [tysDisabled]);
  CStateNames: array[0..3] of string = ('at rest', ':hover', ':focus', ':disabled');

{ Every field of a resolved style (test.db.typekeys' dump): two styles compare equal only when
  they are, except the image and glass fields of a fill that is neither (left unset, so they
  differ by whatever the memory held). }
function TPropertyGridTypeKeyTest.Dump(const S: TTyStyleSet): string;
var
  p: TTyProp;
  i: Integer;
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := 'pres=';
  for p := Low(TTyProp) to High(TTyProp) do
    if p in S.Present then Result := Result + IntToStr(Ord(p)) + ',';
  with S.Background do
  begin
    Result := Result + Format(' bg=%d/%x/%x/%x/%.3f',
      [Ord(Kind), Color, GradFrom, GradTo, GradAngleDeg], fs);
    if Kind in [tfkNineSlice, tfkImage] then
      Result := Result + Format(' img=%s/%d,%d,%d,%d/%d/%d/%d',
        [ImagePath, SliceInsets.Left, SliceInsets.Top, SliceInsets.Right, SliceInsets.Bottom,
         Ord(SliceRepeat), Ord(ImageMode), Blur], fs);
    if tpGlass in S.Present then
      Result := Result + Format(' glass=%d/%x', [GlassBlur, GlassTint], fs);
    for i := 0 to High(GradStops) do
      Result := Result + Format(' stop=%x@%.3f', [GradStops[i].Color, GradStops[i].Pos], fs);
  end;
  Result := Result + Format(' ut=%d ws=%d txt=%x bd=%x/%d/%d rs=%d rad=%d/%d,%d,%d,%d' +
    ' pad=%d,%d,%d,%d fnt=%s/%d/%d op=%.3f sh=%x/%d/%d,%d ol=%x/%d/%d',
    [Ord(S.BackgroundUnderTitlebar), Ord(S.WindowShadow), S.TextColor, S.BorderColor,
     S.BorderWidth, Ord(S.BorderStyle), Ord(S.RenderStyle), S.BorderRadius,
     S.Radius.TL, S.Radius.TR, S.Radius.BR, S.Radius.BL,
     S.Padding.Left, S.Padding.Top, S.Padding.Right, S.Padding.Bottom,
     S.FontName, S.FontSize, S.FontWeight, S.Opacity,
     S.ShadowColor, S.ShadowBlur, S.ShadowOffset.X, S.ShadowOffset.Y,
     S.OutlineColor, S.OutlineWidth, S.OutlineOffset], fs);
end;

function TPropertyGridTypeKeyTest.KeyOf(AClass: TControlClass): string;
var
  c: TControl;
  s: ITyStyleable;
begin
  Result := '';
  c := AClass.Create(nil);
  try
    if Supports(c, ITyStyleable, s) then
      Result := s.GetStyleTypeKey;
    s := nil;
  finally
    c.Free;
  end;
end;

procedure TPropertyGridTypeKeyTest.TestTheGridAnswersItsOwnKeyOnTheEditorsChain;
var
  c: TStringArray;
  i: Integer;
  chain: string;
begin
  AssertEquals('its own key', 'TyPropertyGrid', KeyOf(TTyPropertyGrid));
  c := TyTypeKeyChain('TyPropertyGrid');
  chain := '';
  for i := 0 to High(c) do
  begin
    if i > 0 then chain := chain + ' > ';
    chain := chain + c[i];
  end;
  AssertEquals('hung on the value list editor', 'TyPropertyGrid > TyValueListEditor', chain);
  AssertEquals('which is what the value list editor answers', 'TyValueListEditor',
    KeyOf(TTyValueListEditor));
end;

procedure TPropertyGridTypeKeyTest.TestNoBuiltInThemeHasAPropertyGridRule;
var
  names: TStringArray;
  i: Integer;
begin
  names := TyBuiltinThemeNames;
  AssertTrue('the built-in pack: default, system and the skins', Length(names) >= 17);
  for i := 0 to High(names) do
    AssertEquals(names[i] + ' says nothing about TyPropertyGrid', 0,
      Pos('typropertygrid', LowerCase(TyBuiltinThemeCss(names[i]))));
end;

procedure TPropertyGridTypeKeyTest.TestEveryBuiltInThemeStylesItLikeTheValueListEditor;
var
  c: TTyStyleController;
  names: TStringArray;
  miss: TStringList;
  i, m, s, compared, differ: Integer;
  a, b: string;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  c := TTyStyleController.Create(nil);
  miss := TStringList.Create;
  try
    compared := 0;
    differ := 0;
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        c.ThemeName := names[i];
        if m = 0 then c.Mode := 'light' else c.Mode := 'dark';
        for s := 0 to High(CStates) do
        begin
          a := Dump(c.Model.ResolveStyle('TyValueListEditor', '', CStates[s]));
          b := Dump(c.Model.ResolveStyle('TyPropertyGrid', '', CStates[s]));
          Inc(compared);
          if a <> b then
          begin
            Inc(differ);
            if miss.Count < 20 then
              miss.Add(Format('%s/%s %s: %s' + LineEnding + '    TyValueListEditor: %s',
                [names[i], c.Mode, CStateNames[s], b, a]));
          end;
        end;
      end;
    AssertEquals(IntToStr(differ) + ' differ:' + LineEnding + miss.Text, 0, differ);
    AssertEquals('themes x 2 modes x 4 states', Length(names) * 2 * Length(CStates), compared);
  finally
    miss.Free;
    c.Free;
  end;
end;

procedure TPropertyGridTypeKeyTest.TestATyPropertyGridRuleChangesOnlyTheGrid;
const
  CRule = 'TyPropertyGrid { background: #FF0000; }';
var
  c: TTyStyleController;
  names: TStringArray;
  i: Integer;
  plain, vle, grid: TTyStyleSet;
  where: string;
begin
  names := TyBuiltinThemeNames;
  c := TTyStyleController.Create(nil);
  try
    for i := 0 to High(names) do
    begin
      where := names[i] + ': ';
      c.LoadThemeCss(TyBuiltinThemeCss(names[i]));
      c.Mode := 'light';
      plain := c.Model.ResolveStyle('TyValueListEditor', '', [tysNormal]);
      c.LoadThemeCss(TyBuiltinThemeCss(names[i]) + LineEnding + CRule);
      c.Mode := 'light';
      vle := c.Model.ResolveStyle('TyValueListEditor', '', [tysNormal]);
      grid := c.Model.ResolveStyle('TyPropertyGrid', '', [tysNormal]);
      AssertEquals(where + 'the value list editor is untouched', Dump(plain), Dump(vle));
      AssertTrue(where + 'the grid has a background', tpBackground in grid.Present);
      AssertEquals(where + 'red', 255, TyRedOf(grid.Background.Color));
      AssertEquals(where + 'red: G', 0, TyGreenOf(grid.Background.Color));
      grid.Background := vle.Background;
      if not (tpBackground in vle.Present) then Exclude(grid.Present, tpBackground);
      AssertEquals(where + 'everything else is the editor''s', Dump(vle), Dump(grid));
    end;
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TPropertyGridTypeKeyTest);
end.
