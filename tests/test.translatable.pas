unit test.translatable;
{$mode objfpc}{$H+}

{ Every published property a reader reads as prose is a TTranslateString.

  LCL translates a form's strings in TPOTranslator, and GetIdentifierPath (lcltranslator.pas) stops
  at the first line for any property whose type is not exactly TypeInfo(TTranslateString) -- TCaption
  is the same type under another name. A prose property declared plain `string` is therefore never
  translated, whatever the .po holds: in a Chinese UI the balloon hint's description, the input
  dialog's prompt and the alert's text all stayed English. Nothing failed; the strings were just
  read past.

  The sweep builds every palette class on a form, walks its published sub-objects and one item of
  every published collection, and checks each string property whose name says it is prose. The
  name is the only signal there is -- RTTI cannot tell a caption from a file name -- so names that
  end like prose but hold data are listed in CNotProse, each with its reason. }

interface

uses
  Classes, SysUtils, TypInfo, StrUtils, LCLType, Forms, Controls, fpcunit, testregistry,
  LResources, Translations, LCLTranslator,
  tyControls.Alert, tyControls.Dialogs, tyControls.CoolBar,
  test.designregistry;

type
  TTranslatableTest = class(TTestCase)
  published
    procedure TestEveryProsePropertyIsTranslatable;
    procedure TestAProsePropertyReallyTranslates;
  end;

implementation

const
  { What a prose property's name ends with. }
  CProseEndings: array[0..7] of string =
    ('Caption', 'Title', 'Text', 'Hint', 'Description', 'Prompt', 'Message', 'Msg');

  { Properties whose name ends like prose but whose value is data the program or the user supplies,
    never a string a translator writes. }
  CNotProse: array[0..5] of string = (
    'FindText',      // what the user searches for (find / replace dialogs)
    'ReplaceText',   // what the user replaces it with
    'SelText',       // the selected part of an edit's text, at run time
    'PaintedText',   // what the date picker paints this moment, read-only state
    'DefaultExt',    // a file extension; only its spelling ends in "Ext"
    'Context');      // a ribbon page's context NAME, matched by ShowContext -- translating
                     // it would break the match

function IsProse(const AName: string): Boolean;
var
  s: string;
begin
  for s in CNotProse do
    if SameText(s, AName) then Exit(False);
  for s in CProseEndings do
    if AnsiEndsText(s, AName) then Exit(True);
  Result := False;
end;

procedure CheckClass(AClass: TClass; const AWhere: string; ABad, ASeen: TStrings);
var
  props: PPropList;
  n, i: Integer;
  pi: PPropInfo;
begin
  if ASeen.IndexOf(AClass.ClassName) >= 0 then Exit;
  ASeen.Add(AClass.ClassName);
  n := GetPropList(AClass, props);
  try
    for i := 0 to n - 1 do
    begin
      pi := props^[i];
      if not (pi^.PropType^.Kind in [tkSString, tkLString, tkAString, tkWString, tkUString]) then
        Continue;
      if not IsProse(pi^.Name) then Continue;
      if pi^.PropType <> TypeInfo(TTranslateString) then
        ABad.Add(Format('%s.%s: %s (via %s)', [AClass.ClassName, pi^.Name, pi^.PropType^.Name, AWhere]));
    end;
  finally
    FreeMem(props);
  end;
end;

{ The object, its published sub-objects and sub-components, and an item of each collection. }
procedure Walk(AObj: TPersistent; const AWhere: string; ABad, ASeen: TStrings; ADepth: Integer);
var
  props: PPropList;
  n, i: Integer;
  pi: PPropInfo;
  v: TObject;
  item: TCollectionItem;
begin
  CheckClass(AObj.ClassType, AWhere, ABad, ASeen);
  if ADepth > 4 then Exit;
  n := GetPropList(AObj.ClassType, props);
  try
    for i := 0 to n - 1 do
    begin
      pi := props^[i];
      if pi^.PropType^.Kind <> tkClass then Continue;
      v := GetObjectProp(AObj, pi);
      if v is TCollection then
      begin
        if ASeen.IndexOf(TCollection(v).ItemClass.ClassName) >= 0 then Continue;
        item := TCollection(v).Add;
        try
          Walk(item, AWhere + '.' + pi^.Name + '[]', ABad, ASeen, ADepth + 1);
        finally
          item.Free;
        end;
      end
      else if (v is TComponent) then
      begin
        { a sub-component of the object's own (csSubComponent), never a reference to another }
        if (csSubComponent in TComponent(v).ComponentStyle) and (AObj is TComponent)
          and (TComponent(v).Owner = TComponent(AObj)) then
          Walk(TPersistent(v), AWhere + '.' + pi^.Name, ABad, ASeen, ADepth + 1);
      end
      else if v is TPersistent then
        Walk(TPersistent(v), AWhere + '.' + pi^.Name, ABad, ASeen, ADepth + 1);
    end;
  finally
    FreeMem(props);
  end;
end;

procedure TTranslatableTest.TestEveryProsePropertyIsTranslatable;
var
  names, bad, seen: TStringList;
  i: Integer;
  cls: TPersistentClass;
  form: TForm;
  c: TComponent;
begin
  names := TStringList.Create;
  bad := TStringList.Create;
  seen := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    AssertTrue('the design-registry parser found the palette', names.IndexOf('TTyButton') >= 0);
    for i := 0 to names.Count - 1 do
    begin
      cls := GetClass(names[i]);
      if (cls = nil) or not cls.InheritsFrom(TComponent) or cls.InheritsFrom(TCustomForm) then
        Continue;
      form := TForm.CreateNew(nil);
      try
        c := TComponentClass(cls).Create(form);
        if c is TControl then TControl(c).Parent := form;
        Walk(c, names[i], bad, seen, 0);
      finally
        form.Free;
      end;
    end;
    AssertTrue(Format('the sweep must reach the palette and its parts, and it saw %d classes',
      [seen.Count]), seen.Count > 150);
    bad.Sort;
    AssertEquals('prose properties LCL will never translate (declare them TCaption / ' +
      'TTranslateString, or list a data property in CNotProse):' + LineEnding + bad.Text,
      0, bad.Count);
  finally
    seen.Free;
    bad.Free;
    names.Free;
  end;
end;

{ The guard above checks the type; this checks what the type is FOR. LCL's own translator walks a
  live form (TUpdateTranslator.UpdateTranslation -- the path SetDefaultLang takes for open forms;
  loading a form goes through the same GetIdentifierPath gate) and must replace a control's, a
  non-visual component's and a collection item's prose with the catalogue's. Matched by the English
  text, the way LCL falls back when the identifier path is not in the catalogue. Declared plain
  `string`, all three were skipped. }
procedure TTranslatableTest.TestAProsePropertyReallyTranslates;
const
  PO =
    'msgid ""' + LineEnding +
    'msgstr "Content-Type: text/plain; charset=UTF-8\n"' + LineEnding + LineEnding +
    '#: test.alert' + LineEnding + 'msgid "Disk almost full"' + LineEnding +
    'msgstr "DISK ALMOST FULL"' + LineEnding + LineEnding +
    '#: test.prompt' + LineEnding + 'msgid "Enter a name:"' + LineEnding +
    'msgstr "ENTER A NAME:"' + LineEnding + LineEnding +
    '#: test.band' + LineEnding + 'msgid "Standard"' + LineEnding +
    'msgstr "STANDARD"' + LineEnding;
var
  form: TForm;
  alert: TTyAlert;
  dlg: TTyInputDialog;
  bar: TTyCoolBar;
  band: TTyCoolBand;
  ss: TStringStream;
  tr: TPOTranslator;
  old: TAbstractTranslator;
begin
  form := TForm.CreateNew(nil);
  ss := TStringStream.Create(PO);
  tr := TPOTranslator.Create(TPOFile.Create(ss, True));   // owns the TPOFile
  old := LRSTranslator;
  LRSTranslator := tr;
  try
    alert := TTyAlert.Create(form);
    alert.Name := 'Alert1';
    alert.Parent := form;
    alert.Description := 'Disk almost full';
    dlg := TTyInputDialog.Create(form);
    dlg.Name := 'Dlg1';
    dlg.Prompt := 'Enter a name:';
    bar := TTyCoolBar.Create(form);
    bar.Name := 'Bar1';
    bar.Parent := form;
    band := bar.Bands.Add;
    band.Text := 'Standard';
    tr.UpdateTranslation(form);
    AssertEquals('a control''s prose', 'DISK ALMOST FULL', alert.Description);
    AssertEquals('a non-visual component''s prose', 'ENTER A NAME:', dlg.Prompt);
    AssertEquals('a collection item''s prose', 'STANDARD', band.Text);
  finally
    LRSTranslator := old;
    tr.Free;
    form.Free;
    ss.Free;
  end;
end;

initialization
  RegisterTest(TTranslatableTest);
end.
