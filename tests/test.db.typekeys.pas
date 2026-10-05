unit test.db.typekeys;
{$mode objfpc}{$H+}

{ The data-aware controls' type keys (issue #34, plan Task 10 / C9, D8).

  Every DB control answers a key of its own ('TyDBEdit'), and that key hangs off its base
  control's through the #14 chain -- so a theme that says nothing about the DB controls styles
  each exactly like the control it is built on, and a theme that does can style the DB control
  alone. Checked here:

  * each of the 21 classes answers 'TyDB' + its name, and each key's chain is the one plan D8
    names, the two sub-part keys (the navigator's buttons, the rating's stars) included;
  * the base controls answer the keys those chains end in;
  * in every built-in theme, light and dark, each DB key resolves to exactly the style of its
    base key, at rest, under the pointer, focused and disabled -- no built-in theme has a TyDB
    rule, which is checked first;
  * a theme rule for TyDBEdit changes the DB edit and nothing else. }

interface

uses
  Classes, SysUtils, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.StyleModel, tyControls.Controller,
  tyControls.BuiltinThemes,
  tyControls.Edit, tyControls.MaskEdit, tyControls.Memo, tyControls.TyLabel,
  tyControls.NumericEdit, tyControls.CurrencyEdit, tyControls.SpinEdit,
  tyControls.FloatSpinEdit, tyControls.CheckBox, tyControls.ToggleSwitch,
  tyControls.RadioGroup, tyControls.Segmented, tyControls.Rating, tyControls.ComboBox,
  tyControls.ListBox, tyControls.Image, tyControls.DateTimePicker, tyControls.Calendar,
  tyControls.ToolBar,
  tyControls.DB.Edits, tyControls.DB.Choices, tyControls.DB.Lists, tyControls.DB.Image,
  tyControls.DB.DateTime, tyControls.DB.Navigator;

type
  TDBTypeKeysTest = class(TTestCase)
  private
    function Dump(const S: TTyStyleSet): string;
    function KeyOf(AClass: TControlClass): string;
  published
    procedure TestEveryClassAnswersItsOwnKey;
    procedure TestEveryChainIsThePlansChain;
    procedure TestTheBaseControlsAnswerTheRootKeys;
    procedure TestNoBuiltInThemeHasADBRule;
    procedure TestEveryBuiltInThemeStylesThemLikeTheirBase;
    procedure TestATyDBEditRuleChangesOnlyTheDBEdit;
  end;

implementation

type
  TDBClassRow = record
    DB: TControlClass;
    Key: string;
    Base: TControlClass;   // the control it is built on
  end;
  TDBClassRows = array of TDBClassRow;

  TChainRow = record
    Key: string;
    Chain: string;         // the chain, ' > ' between the keys
  end;

const
  CStates: array[0..3] of TTyStateSet = ([tysNormal], [tysHover], [tysFocused], [tysDisabled]);
  CStateNames: array[0..3] of string = ('at rest', ':hover', ':focus', ':disabled');

  { Plan D8; the two sub-part keys last. }
  CChains: array[0..22] of TChainRow = (
    (Key: 'TyDBEdit'; Chain: 'TyDBEdit > TyEdit'),
    (Key: 'TyDBMaskEdit'; Chain: 'TyDBMaskEdit > TyEdit'),
    (Key: 'TyDBNumericEdit'; Chain: 'TyDBNumericEdit > TyEdit'),
    (Key: 'TyDBCurrencyEdit'; Chain: 'TyDBCurrencyEdit > TyEdit'),
    (Key: 'TyDBFloatSpinEdit'; Chain: 'TyDBFloatSpinEdit > TyEdit'),
    (Key: 'TyDBSpinEdit'; Chain: 'TyDBSpinEdit > TySpinEdit'),
    (Key: 'TyDBMemo'; Chain: 'TyDBMemo > TyMemo'),
    (Key: 'TyDBText'; Chain: 'TyDBText > TyLabel'),
    (Key: 'TyDBCheckBox'; Chain: 'TyDBCheckBox > TyCheckBox'),
    (Key: 'TyDBToggleSwitch'; Chain: 'TyDBToggleSwitch > TyToggleSwitch'),
    (Key: 'TyDBRadioGroup'; Chain: 'TyDBRadioGroup > TyGroupBox'),
    (Key: 'TyDBSegmented'; Chain: 'TyDBSegmented > TySegmented'),
    (Key: 'TyDBRating'; Chain: 'TyDBRating > TyRating'),
    (Key: 'TyDBComboBox'; Chain: 'TyDBComboBox > TyComboBox'),
    (Key: 'TyDBLookupComboBox'; Chain: 'TyDBLookupComboBox > TyDBComboBox > TyComboBox'),
    (Key: 'TyDBListBox'; Chain: 'TyDBListBox > TyListBox'),
    (Key: 'TyDBLookupListBox'; Chain: 'TyDBLookupListBox > TyDBListBox > TyListBox'),
    (Key: 'TyDBImage'; Chain: 'TyDBImage > TyImage'),
    (Key: 'TyDBDateTimePicker'; Chain: 'TyDBDateTimePicker > TyDateTimePicker'),
    (Key: 'TyDBCalendar'; Chain: 'TyDBCalendar > TyCalendar'),
    (Key: 'TyDBNavigator'; Chain: 'TyDBNavigator > TyToolBar'),
    (Key: 'TyDBNavigatorButton'; Chain: 'TyDBNavigatorButton > TyButton'),
    (Key: 'TyDBRatingStar'; Chain: 'TyDBRatingStar > TyRatingStar'));

function DBClasses: TDBClassRows;

  procedure Add(ADB: TControlClass; const AKey: string; ABase: TControlClass);
  var
    n: Integer;
  begin
    n := Length(Result);
    SetLength(Result, n + 1);
    Result[n].DB := ADB;
    Result[n].Key := AKey;
    Result[n].Base := ABase;
  end;

begin
  Result := nil;
  Add(TTyDBEdit, 'TyDBEdit', TTyEdit);
  Add(TTyDBMaskEdit, 'TyDBMaskEdit', TTyMaskEdit);
  Add(TTyDBMemo, 'TyDBMemo', TTyMemo);
  Add(TTyDBText, 'TyDBText', TTyLabel);
  Add(TTyDBNumericEdit, 'TyDBNumericEdit', TTyNumericEdit);
  Add(TTyDBCurrencyEdit, 'TyDBCurrencyEdit', TTyCurrencyEdit);
  Add(TTyDBSpinEdit, 'TyDBSpinEdit', TTySpinEdit);
  Add(TTyDBFloatSpinEdit, 'TyDBFloatSpinEdit', TTyFloatSpinEdit);
  Add(TTyDBCheckBox, 'TyDBCheckBox', TTyCheckBox);
  Add(TTyDBToggleSwitch, 'TyDBToggleSwitch', TTyToggleSwitch);
  Add(TTyDBRadioGroup, 'TyDBRadioGroup', TTyRadioGroup);
  Add(TTyDBSegmented, 'TyDBSegmented', TTySegmented);
  Add(TTyDBRating, 'TyDBRating', TTyRating);
  Add(TTyDBComboBox, 'TyDBComboBox', TTyComboBox);
  Add(TTyDBLookupComboBox, 'TyDBLookupComboBox', TTyComboBox);
  Add(TTyDBListBox, 'TyDBListBox', TTyListBox);
  Add(TTyDBLookupListBox, 'TyDBLookupListBox', TTyListBox);
  Add(TTyDBImage, 'TyDBImage', TTyImage);
  Add(TTyDBDateTimePicker, 'TyDBDateTimePicker', TTyDateTimePicker);
  Add(TTyDBCalendar, 'TyDBCalendar', TTyCalendar);
  Add(TTyDBNavigator, 'TyDBNavigator', TTyToolBar);
end;

function ChainText(const AKey: string): string;
var
  c: TStringArray;
  i: Integer;
begin
  c := TyTypeKeyChain(AKey);
  Result := '';
  for i := 0 to High(c) do
  begin
    if i > 0 then Result := Result + ' > ';
    Result := Result + c[i];
  end;
end;

function RootOf(const AChain: string): string;
var
  p: Integer;
begin
  Result := AChain;
  p := Pos(' > ', Result);
  while p > 0 do
  begin
    Delete(Result, 1, p + 2);
    p := Pos(' > ', Result);
  end;
end;

function ParentOf(const AChain: string): string;
var
  rest: string;
  p: Integer;
begin
  rest := AChain;
  p := Pos(' > ', rest);
  Delete(rest, 1, p + 2);
  p := Pos(' > ', rest);
  if p > 0 then rest := Copy(rest, 1, p - 1);
  Result := rest;
end;

{ Every field of a resolved style (test.typekeychain's dump), so two styles compare equal only
  when they are -- except the background's image and glass fields where the fill is no image
  and no glass: the model leaves them unset for a gradient, so two resolutions of the same
  gradient differ there by whatever the memory held (seen in the skins with gradient buttons). }
function TDBTypeKeysTest.Dump(const S: TTyStyleSet): string;
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

function TDBTypeKeysTest.KeyOf(AClass: TControlClass): string;
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

procedure TDBTypeKeysTest.TestEveryClassAnswersItsOwnKey;
var
  rows: TDBClassRows;
  i: Integer;
begin
  rows := DBClasses;
  AssertEquals('the 21 data-aware controls', 21, Length(rows));
  for i := 0 to High(rows) do
    AssertEquals(rows[i].DB.ClassName, rows[i].Key, KeyOf(rows[i].DB));
end;

procedure TDBTypeKeysTest.TestEveryChainIsThePlansChain;
var
  i: Integer;
begin
  for i := 0 to High(CChains) do
    AssertEquals(CChains[i].Key, CChains[i].Chain, ChainText(CChains[i].Key));
end;

{ The key each chain ends in is the key the base control itself answers: the DB control falls
  back to the style its base control is actually drawn with. }
procedure TDBTypeKeysTest.TestTheBaseControlsAnswerTheRootKeys;
var
  rows: TDBClassRows;
  i, j: Integer;
  chain: string;
begin
  rows := DBClasses;
  for i := 0 to High(rows) do
  begin
    chain := '';
    for j := 0 to High(CChains) do
      if CChains[j].Key = rows[i].Key then chain := CChains[j].Chain;
    AssertTrue(rows[i].Key + ' has a chain in the table', chain <> '');
    AssertEquals(rows[i].DB.ClassName + ' falls back to what ' + rows[i].Base.ClassName
      + ' answers', RootOf(chain), KeyOf(rows[i].Base));
  end;
end;

procedure TDBTypeKeysTest.TestNoBuiltInThemeHasADBRule;
var
  names: TStringArray;
  i: Integer;
begin
  names := TyBuiltinThemeNames;
  AssertTrue('the built-in pack: default, system and the 15 skins', Length(names) >= 17);
  for i := 0 to High(names) do
    AssertEquals(names[i] + ' says nothing about TyDB keys', 0,
      Pos('tydb', LowerCase(TyBuiltinThemeCss(names[i]))));
end;

{ C9. Each DB key against its parent's key (the base control's for every one but the two
  lookups, whose parent is the DB combo / list box -- and that one's parent is the base): equal
  to the last field, in every theme and mode, in all four states. }
procedure TDBTypeKeysTest.TestEveryBuiltInThemeStylesThemLikeTheirBase;
var
  c: TTyStyleController;
  names: TStringArray;
  miss: TStringList;
  i, m, k, s, compared, differ: Integer;
  parent, a, b: string;
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
        for k := 0 to High(CChains) do
        begin
          parent := ParentOf(CChains[k].Chain);
          for s := 0 to High(CStates) do
          begin
            a := Dump(c.Model.ResolveStyle(parent, '', CStates[s]));
            b := Dump(c.Model.ResolveStyle(CChains[k].Key, '', CStates[s]));
            Inc(compared);
            if a <> b then
            begin
              Inc(differ);
              if miss.Count < 20 then
                miss.Add(Format('%s/%s %s %s: %s' + LineEnding + '    %s: %s',
                  [names[i], c.Mode, CChains[k].Key, CStateNames[s], b, parent, a]));
            end;
          end;
        end;
      end;
    AssertEquals(IntToStr(differ) + ' differ:' + LineEnding + miss.Text, 0, differ);
    AssertEquals('themes x 2 modes x keys x 4 states',
      Length(names) * 2 * Length(CChains) * Length(CStates), compared);
  finally
    miss.Free;
    c.Free;
  end;
end;

{ The other half of the chain's point: a rule for the DB key is for the DB control alone. In
  every built-in theme, with one rule added, the DB edit's background is that rule's and the
  rest of its style is the edit's; the edit, and the other DB keys over TyEdit, are as they
  were. }
procedure TDBTypeKeysTest.TestATyDBEditRuleChangesOnlyTheDBEdit;
const
  CRule = 'TyDBEdit { background: #FF0000; }';
  COthers: array[0..3] of string =
    ('TyDBMaskEdit', 'TyDBNumericEdit', 'TyDBCurrencyEdit', 'TyDBFloatSpinEdit');
var
  c: TTyStyleController;
  names: TStringArray;
  i, k: Integer;
  plainEdit, edit, dbEdit: TTyStyleSet;
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
      plainEdit := c.Model.ResolveStyle('TyEdit', '', [tysNormal]);
      c.LoadThemeCss(TyBuiltinThemeCss(names[i]) + LineEnding + CRule);
      c.Mode := 'light';
      edit := c.Model.ResolveStyle('TyEdit', '', [tysNormal]);
      dbEdit := c.Model.ResolveStyle('TyDBEdit', '', [tysNormal]);
      AssertEquals(where + 'TyEdit is untouched', Dump(plainEdit), Dump(edit));
      AssertTrue(where + 'the DB edit has a background', tpBackground in dbEdit.Present);
      AssertTrue(where + 'a solid one', dbEdit.Background.Kind = tfkSolid);
      AssertEquals(where + 'red', 255, TyRedOf(dbEdit.Background.Color));
      AssertEquals(where + 'red: G', 0, TyGreenOf(dbEdit.Background.Color));
      AssertEquals(where + 'red: B', 0, TyBlueOf(dbEdit.Background.Color));
      AssertEquals(where + 'opaque', 255, TyAlphaOf(dbEdit.Background.Color));
      dbEdit.Background := edit.Background;
      Include(dbEdit.Present, tpBackground);
      if not (tpBackground in edit.Present) then Exclude(dbEdit.Present, tpBackground);
      AssertEquals(where + 'everything else is the edit''s', Dump(edit), Dump(dbEdit));
      for k := 0 to High(COthers) do
        AssertEquals(where + COthers[k] + ' still looks like TyEdit', Dump(edit),
          Dump(c.Model.ResolveStyle(COthers[k], '', [tysNormal])));
    end;
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TDBTypeKeysTest);
end.
