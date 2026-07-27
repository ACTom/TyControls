unit test.designeditors;
{$mode objfpc}{$H+}

{ Guards for the Object Inspector's STRING properties.

  THE PROBLEM THIS FILE EXISTS FOR. A published string shows up in the inspector as a bare edit
  box. Nothing on screen says what may go into it, so a property with a real vocabulary —
  TTyStyleController.ThemeName, a StyleClass variant, an icon-font glyph name — is guesswork
  until designtime/tyControls.Design.pas hangs a property editor on it. Those registrations are
  the feature; this unit is what keeps them alive.

  WHY THE TESTS PARSE A FILE INSTEAD OF CALLING THE CODE. tests/ cannot LINK
  designtime/tyControls.Design.pas — it pulls in IDEIntf, which the test project does not
  require — so a GetValues result cannot be observed here at all. What CAN be observed is the
  half that decides whether an editor is ever consulted, and it is the half that fails silently:
  RegisterPropertyEditor pairs an editor with a (type, class, property-name) triple and, if any
  of the three is wrong, simply never matches. No error, no warning, no editor. So the parse
  (test.designregistry — the one parser, shared) supplies the registrations and RTTI on the real
  runtime classes says whether each one can ever fire.

  WHAT IS NOT COVERED HERE, honestly: the CONTENT of a value list. Whether the ThemeName
  dropdown really lists every built-in theme is only observable inside a running IDE. }

interface

uses
  Classes, SysUtils, StrUtils, TypInfo, fpcunit, testregistry,
  test.designregistry,
  { The classes the registrations name. Resolved by NAME through the class registry (the
    initialization block below), the same trick test.version.pas uses. }
  tyControls.Base, tyControls.Component, tyControls.Controller, tyControls.Form,
  tyControls.FormSurface, tyControls.Menu, tyControls.Popover, tyControls.IconFont,
  tyControls.CharImage, tyControls.GlyphButtons, tyControls.Ribbon,
  tyControls.Dialogs.FileDialog, tyControls.Dialogs.SelectPath, tyControls.FilterComboBox,
  tyControls.ShellComboBox, tyControls.ShellListView, tyControls.ShellTreeView;

type
  TDesignEditorsTest = class(TTestCase)
  published
    procedure TestEveryRegistrationTargetsARealProperty;
    procedure TestControllerStringPropertiesAreGuided;
    procedure TestThemeFileIsPickedFromAFileDialog;
    procedure TestValueListsStayTypeable;
    procedure TestNoDeclaredPropertyEditorIsUnregistered;
  end;

implementation

const
  { The type expression the string registrations use, whitespace already squeezed out. }
  CStringTypeExpr = 'TypeInfo(string)';

{ Whitespace carries no meaning inside an argument (the registrations wrap across lines), so
  comparisons squeeze it out rather than depending on how a line happened to be broken. }
function Squeezed(const S: string): string;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] > ' ' then Result := Result + S[i];
end;

{ Is APropInfo a PLAIN `string` property — not one of the distinct types that merely happen to
  be strings? The distinction is the whole point: RegisterPropertyEditor matches on the type
  NAME, so `string`, `TCaption`, `TTranslateString` and `TComponentName` are four different
  targets and an editor aimed at one never appears on another. Comparing against TypeInfo(string)
  taken here, rather than against the literal 'AnsiString', keeps the two sides of the comparison
  produced by the same compiler in the same mode. }
function IsPlainString(APropInfo: PPropInfo): Boolean;
begin
  Result := (APropInfo <> nil)
        and (APropInfo^.PropType^.Name = PTypeInfo(TypeInfo(string))^.Name);
end;

{ Every RegisterPropertyEditor call, as parsed records. Caller frees. }
function Registrations: TStringList;
begin
  Result := TStringList.Create;
  try
    CollectPropertyEditorRegistrations(Result);
  except
    Result.Free;
    raise;
  end;
end;

{ The editor class registered for ABase.AProp exactly (no inheritance walk — this asks what the
  source SAYS, not what the inspector would resolve), or '' when there is none. }
function EditorFor(const ABase, AProp: string): string;
var
  regs: TStringList;
  i: Integer;
  ty, base, prop, ed: string;
begin
  Result := '';
  regs := Registrations;
  try
    for i := 0 to regs.Count - 1 do
      if SplitEditorRegistration(regs[i], ty, base, prop, ed)
         and (Squeezed(base) = ABase) and SameText(Squeezed(prop), AProp) then
        Exit(Squeezed(ed));
  finally
    regs.Free;
  end;
end;

{ Follow ANAME up the ancestor chain DECLARED IN THE DESIGN SOURCE and return the first ancestor
  that is not itself declared there — i.e. the LCL base the file specialises. '' when ANAME is
  not declared in the file at all. }
function LclBaseOf(const AName: string): string;
var
  decls: TStringList;
  cur, nm, anc: string;
  i, hops: Integer;
  found: Boolean;
begin
  Result := '';
  decls := TStringList.Create;
  try
    CollectClassDeclarations(decls);
    cur := AName;
    { hops is a cycle brake: a malformed parse could otherwise loop forever on A -> B -> A. }
    for hops := 0 to decls.Count do
    begin
      found := False;
      for i := 0 to decls.Count - 1 do
        if SplitClassDeclaration(decls[i], nm, anc) and SameText(nm, cur) then
        begin
          cur := anc;
          found := True;
          Break;
        end;
      if not found then
      begin
        { The very first lookup failing means ANAME is not declared here at all. }
        if hops = 0 then Exit('');
        Exit(cur);
      end;
    end;
  finally
    decls.Free;
  end;
end;

{ THE CHECK THAT CATCHES A DEAD REGISTRATION. RegisterPropertyEditor takes a PTypeInfo, a class
  and a property NAME, and matches a registration to a property only when the property's own
  type info agrees (kind AND type name — which is why an editor registered with TypeInfo(string)
  never fires on a property declared as TCaption, those being distinct types with the same kind)
  and the class publishes that name. A wrong class, a renamed property or the wrong TypeInfo
  therefore produce no editor and no complaint: the maintainer sees the plain edit box the
  registration was written to replace, and the suite stays green.

  So: resolve each named registration against real RTTI. Blanket registrations (empty property
  name — the TTyFormSurface hide rules) match by type alone and are skipped. }
procedure TDesignEditorsTest.TestEveryRegistrationTargetsARealProperty;
var
  regs, unresolved, missing, mistyped: TStringList;
  i, named: Integer;
  ty, base, prop, ed: string;
  cls: TPersistentClass;
  pi: PPropInfo;
begin
  regs := Registrations;
  unresolved := TStringList.Create;
  missing := TStringList.Create;
  mistyped := TStringList.Create;
  try
    AssertTrue('no RegisterPropertyEditor calls parsed out of'
      + ' designtime/tyControls.Design.pas — the parse has drifted', regs.Count > 0);
    named := 0;
    for i := 0 to regs.Count - 1 do
    begin
      AssertTrue('malformed registration record (expected four fields): ' + regs[i],
        SplitEditorRegistration(regs[i], ty, base, prop, ed));
      ty := Squeezed(ty); base := Squeezed(base); prop := Squeezed(prop);
      if prop = '' then Continue;          // blanket, type-only rule
      Inc(named);
      cls := GetClass(base);
      if cls = nil then
      begin
        unresolved.Add(base);
        Continue;
      end;
      pi := GetPropInfo(cls, prop);
      if pi = nil then
      begin
        missing.Add(base + '.' + prop);
        Continue;
      end;
      { Only the string registrations can be type-checked without a name -> PTypeInfo map, and
        they are the ones this workstream adds; the rest are covered by "the property exists". }
      if (ty = CStringTypeExpr) and not IsPlainString(pi) then
        mistyped.Add(base + '.' + prop + ' is ' + pi^.PropType^.Name);
    end;
    { Anti-vacuity. A parser that returned only the blanket rules would sail through every
      check above having verified nothing; the floor is a floor, not a count — this list only
      ever grows, so it fires when registrations go missing wholesale. }
    AssertTrue(Format('only %d NAMED property-editor registrations were checked — the parse'
      + ' has shrunk and the checks below it are passing vacuously', [named]), named >= 20);
    AssertEquals('property editors registered on classes this test cannot resolve — add them to'
      + ' the RegisterClasses block in tests/test.designeditors.pas:' + LineEnding
      + unresolved.Text, 0, unresolved.Count);
    AssertEquals('property editor registered on a property the class does not publish — the'
      + ' Object Inspector will never consult that editor and shows a plain edit box:'
      + LineEnding + missing.Text, 0, missing.Count);
    AssertEquals('registered with TypeInfo(string) but the property is a DIFFERENT string type'
      + ' — RegisterPropertyEditor compares type names, so this editor never fires:' + LineEnding
      + mistyped.Text, 0, mistyped.Count);
  finally
    mistyped.Free;
    missing.Free;
    unresolved.Free;
    regs.Free;
  end;
end;

{ THE WORKSTREAM'S PROMISE, stated as a rule instead of as three names: a style controller is
  configured almost entirely through strings, and every one of them must come with the
  vocabulary that makes it fillable. The population is read from RTTI, not written here, so a
  fourth string property added to the controller tomorrow is held to the same rule.

  Plain `string` properties only, and TComponent.Name is excluded by name: it belongs to the
  IDE, and FPC's TComponentName is a plain alias of string rather than `type string`, so RTTI
  cannot tell the two apart. }
procedure TDesignEditorsTest.TestControllerStringPropertiesAreGuided;
var
  regs, unguided, found: TStringList;
  props: PPropList;
  n, i, j: Integer;
  ty, base, prop, ed, want: string;
  cls: TPersistentClass;
  guided: Boolean;
begin
  regs := Registrations;
  unguided := TStringList.Create;
  found := TStringList.Create;
  try
    n := GetPropList(TTyStyleController, props);
    try
      for i := 0 to n - 1 do
      begin
        if not IsPlainString(props^[i]) then Continue;
        want := props^[i]^.Name;
        { TComponent.Name is the IDE's, not ours. It cannot be filtered by type the way the
          comment above hoped: FPC declares TComponentName as a plain ALIAS of string, not as
          `type string`, so it shares AnsiString's RTTI and is indistinguishable from a
          genuine string property. Excluding it by name is the only honest option. }
        if SameText(want, 'Name') then Continue;
        found.Add(want);
        guided := False;
        for j := 0 to regs.Count - 1 do
          if SplitEditorRegistration(regs[j], ty, base, prop, ed)
             and (Squeezed(ty) = CStringTypeExpr) and SameText(Squeezed(prop), want) then
          begin
            { Registering on an ANCESTOR counts — Version rides in on TTyComponent — but only
              if that ancestor is one the controller actually descends from. }
            cls := GetClass(Squeezed(base));
            if (cls <> nil) and TTyStyleController.InheritsFrom(cls) then
            begin
              guided := True;
              Break;
            end;
          end;
        if not guided then unguided.Add(want);
      end;
    finally
      if n > 0 then FreeMem(props);
    end;
    { Anti-vacuity: RTTI must actually have handed us the properties. Without this the test
      passes loudly on an empty sweep. }
    AssertTrue('RTTI reported no published string properties on TTyStyleController — the sweep'
      + ' checked nothing', found.Count >= 4);
    AssertTrue('the sweep did not even see ThemeName: ' + StringReplace(Trim(found.Text),
      LineEnding, ', ', [rfReplaceAll]), found.IndexOf('ThemeName') >= 0);
    AssertEquals('published string properties of TTyStyleController with no Object Inspector'
      + ' editor — these are the empty boxes a maintainer cannot fill:' + LineEnding
      + unguided.Text, 0, unguided.Count);
  finally
    found.Free;
    unguided.Free;
    regs.Free;
  end;
end;

{ ThemeFile names a file on disk, so it is PICKED, not typed. In property-editor terms that is
  the difference between specialising LCL's TFileNamePropertyEditor (paDialog + a '...' button
  that opens a file dialog) and specialising TStringPropertyEditor (an edit box). Which base a
  declared editor sits on is therefore the behaviour, and it is readable from the source. }
procedure TDesignEditorsTest.TestThemeFileIsPickedFromAFileDialog;
var
  ed: string;
begin
  { Anti-vacuity for the declaration parse itself: a scan that matched nothing would make every
    LclBaseOf answer '' and the assertions below meaningless. }
  AssertEquals('the class-declaration parse no longer sees the StyleClass editor — it has'
    + ' drifted and every ancestry check below is vacuous',
    'TStringPropertyEditor', LclBaseOf('TTyStyleClassPropertyEditor'));

  ed := EditorFor('TTyStyleController', 'ThemeFile');
  AssertTrue('TTyStyleController.ThemeFile has no property editor at all', ed <> '');
  AssertEquals('TTyStyleController.ThemeFile must be picked with a file dialog, i.e. its editor'
    + ' must specialise LCL''s file-name editor', 'TFileNamePropertyEditor', LclBaseOf(ed));

  { The other two are lists, not dialogs — a file dialog over a theme NAME would be nonsense. }
  ed := EditorFor('TTyStyleController', 'ThemeName');
  AssertTrue('TTyStyleController.ThemeName has no property editor at all', ed <> '');
  AssertEquals('TTyStyleController.ThemeName must be a string editor offering a value list',
    'TStringPropertyEditor', LclBaseOf(ed));
  ed := EditorFor('TTyStyleController', 'Mode');
  AssertTrue('TTyStyleController.Mode has no property editor at all', ed <> '');
  AssertEquals('TTyStyleController.Mode must be a string editor offering a value list',
    'TStringPropertyEditor', LclBaseOf(ed));
end;

{ THE RULE THE WHOLE FEATURE RESTS ON. paValueList alone gives the Object Inspector an EDITABLE
  combo; adding paPickList makes it a closed list. Every vocabulary TyControls offers is
  open-ended — a theme name the application registers at run time, a StyleClass variant from a
  theme this IDE never loaded, a glyph added to the icon font later — so a pick-list would turn
  a helpful dropdown into a fence around values that are perfectly legal. The check is coarse on
  purpose: the attribute is nowhere in the file, so nothing can quietly acquire it. (Comments and
  literals are stripped, so the prose EXPLAINING paPickList does not trip it.) }
procedure TDesignEditorsTest.TestValueListsStayTypeable;
var
  code: string;
begin
  code := UpperCase(DesignSourceCode);   // Pascal is case-insensitive; so is this check
  AssertTrue('the design source was not read', Pos('REGISTERPROPERTYEDITOR', code) > 0);
  AssertTrue('paPickList appears in designtime/tyControls.Design.pas: some value list has been'
    + ' turned into a closed drop-down, and a legal value that is not on the list can no longer'
    + ' be typed. If a property really does have a CLOSED vocabulary, say so here — do not just'
    + ' delete the check', Pos('PAPICKLIST', code) = 0);
end;

{ An editor class that is written but never registered is the exact shape of a change that looks
  done and does nothing — the code is there, the Object Inspector never sees it. Any class
  declared in this file whose ancestry roots at an LCL *PropertyEditor / *Property base must
  appear as the editor argument of some registration. }
procedure TDesignEditorsTest.TestNoDeclaredPropertyEditorIsUnregistered;
var
  decls, regs, used, dead: TStringList;
  i, editors: Integer;
  nm, anc, root, ty, base, prop, ed: string;
begin
  decls := TStringList.Create;
  regs := Registrations;
  used := TStringList.Create;
  dead := TStringList.Create;
  try
    CollectClassDeclarations(decls);
    AssertTrue('no class declarations parsed out of designtime/tyControls.Design.pas',
      decls.Count > 0);
    for i := 0 to regs.Count - 1 do
      if SplitEditorRegistration(regs[i], ty, base, prop, ed) then
        used.Add(Squeezed(ed));
    editors := 0;
    for i := 0 to decls.Count - 1 do
    begin
      if not SplitClassDeclaration(decls[i], nm, anc) then Continue;
      root := LclBaseOf(nm);
      { LCL's property-editor bases all end one of two ways; component editors, file
        descriptors and project descriptors do not, and are none of this test's business. }
      if not (AnsiEndsText('PropertyEditor', root) or AnsiEndsText('Property', root)) then
        Continue;
      Inc(editors);
      if used.IndexOf(nm) < 0 then dead.Add(nm + ' (a ' + root + ')');
    end;
    AssertTrue(Format('only %d property-editor classes were recognised in the design source —'
      + ' the ancestry parse has drifted and this check is vacuous', [editors]), editors >= 6);
    AssertEquals('property editor declared but never registered — it is dead code and the'
      + ' property it was written for still shows a plain edit box:' + LineEnding + dead.Text,
      0, dead.Count);
  finally
    dead.Free;
    used.Free;
    regs.Free;
    decls.Free;
  end;
end;

initialization
  { Name -> class, so a base parsed out of the registrations can be resolved. Not the list under
    test: TestEveryRegistrationTargetsARealProperty fails (with the name) when it falls behind
    designtime/tyControls.Design.pas. }
  RegisterClasses([
    TTyGraphicControl, TTyCustomControl, TTyComponent, TTyStyleController, TTyForm,
    TTyFormSurface, TTyPopupMenu, TTyPopover, TTyIconFont, TTyCharImage, TTyGlyphButtonBase,
    TTyRibbonPage, TTyCustomFileDialog, TTyFilterComboBox, TTySelectPathDialog,
    TTyShellComboBox, TTyShellListView, TTyShellTreeView]);
  RegisterTest(TDesignEditorsTest);

end.
