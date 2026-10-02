unit test.customclasses;
{$mode objfpc}{$H+}

{ Guards for the custom-class split (GitHub issue #8).

  WHY THIS UNIT EXISTS. Issue #8 asks for a TTyCustomXxx parent behind every control, so a third
  party can derive from it and publish only what it wants. The split moves every field, method
  and property declaration of TTyXxx into TTyCustomXxx and leaves TTyXxx as nothing but a list of
  `property X;` lines -- and with option A (the LCL way) the base classes stop publishing anything
  too, so every final class republishes the universal properties itself. Three things must come
  through that untouched, and none of them is visible to an ordinary behaviour test:

    * the user's .lfm: a published property's NAME, TYPE, DEFAULT, STORED clause and -- because
      TWriter walks RTTI in NameIndex order -- its POSITION decide what a saved form file says.
      A republished property keeps its default and stored clause, but takes its position from
      wherever it is FIRST published, so the order of the final class's published lines is
      load-bearing;
    * the theme: a control is styled by the type key GetStyleTypeKey answers, not by its Pascal
      class name; the overrides move into the custom class, and the key must not move;
    * a third party's subclass: it must see the same defaults the final class has, which only
      holds when the redeclarations that change a default live in the custom class.

  The snapshot (G6) is taken from the code BEFORE the split and every later task is compared
  against it, field by field. It is a migration guard: Task 32 of the plan retires it. The
  structural guards (G1-G5, G7, G8) stay -- they are what make the next control born split.

  The population is whatever designtime/ registers (test.designregistry parses it; test.version
  RegisterClasses every one of them), plus TTyScrollContent, which is only RegisterClass'd but
  does appear in .lfm files. }

interface

uses
  Classes, SysUtils, StrUtils, TypInfo, FileUtil, Controls, Forms, ImgList, fpcunit, testregistry,
  test.designregistry, test.version,
  tyControls.Base, tyControls.Component, tyControls.Button, tyControls.GlyphButtons,
  tyControls.TabStrip, tyControls.Grid, tyControls.TreeView, tyControls.ShellListView,
  tyControls.IconFont, tyControls.Dialogs.FileDialog, tyControls.ToolWindows,
  tyControls.ScrollContent, tyControls.ListBox, tyControls.TreeSelect, tyControls.Popover,
  tyControls.Notification, tyControls.Types, test.customclasses.mimic;

type
  TTyCustomClassesGuardTest = class(TTestCase)
  published
    procedure TestPublishedSnapshotUnchanged;
    procedure TestSplitClassesSitOnTheirCustomClass;
    procedure TestCustomClassesPublishNothingNew;
    procedure TestCustomAndFinalAgree;
    procedure TestFinalClassesAddNoFields;
    procedure TestEveryRegisteredClassIsAccountedFor;
    procedure TestDerivedControlsHangOnTheCustomChain;
    procedure TestDemotedClassesPublishOnlyTheLclRoot;
    procedure TestBaseClassesPublishNothing;
    procedure TestThirdPartyOnTheBareBaseSeesOnlyTheLclRoot;
    procedure TestGeneratedMimicsMatchTheirFinalClass;
    procedure TestFreshFormFileTextUnchanged;
  end;

{ Shared with the per-phase suites (test.customclasses.p1 ...). }
function CustomClassesSplit: TStrings;
function PublishedNames(AClass: TClass): TStringList;
function LclRootOf(AClass: TClass): TClass;

implementation

const
  CSnapshotFile = 'tests' + PathDelim + 'fixtures' + PathDelim + 'customclasses' + PathDelim
    + 'published-snapshot.txt';
  CFreshStreamsFile = 'tests' + PathDelim + 'fixtures' + PathDelim + 'customclasses' + PathDelim
    + 'fresh-streams.txt';

  { The classes not split, each with its reason. }
  CNotSplit: array[0..19] of string = (
    'TTyForm',              // designer base classes, the TForm role (plan Q5)
    'TTyDialog',            // same
    'TTyPopupMenu',         // LCL does not split TPopupMenu (menus.pp:465)
    'TTyImagesMenu',        // same family
    'TTyMenuEx',            // same family
    'TTySelectPathDialog',  // LCL does not split TCommonDialog descendants (dialogs.pp:87-515)
    'TTyColorDialog',
    'TTyFontDialog',
    'TTyFindDialog',
    'TTyReplaceDialog',
    'TTyOpenDialog',
    'TTySaveDialog',
    'TTyOpenPictureDialog', // extdlgs.pas:74
    'TTySavePictureDialog',
    'TTyOpenPreviewDialog',
    'TTySavePreviewDialog',
    { already TTyCustomToolWindowManager + final; the final carries the implementation for
      unit dependencies (plan Q4) }
    'TTyToolWindowManager',
    'TTyAdvanceChart',      // split after feat/advancechart merges (plan appendix B)
    'TTyCalendar',          // same
    'TTyDateTimePicker');   // same

  { Registered with RegisterClass only: not on the palette, but streamed in .lfm files. }
  CStreamOnly: array[0..0] of string = ('TTyScrollContent');

  { Property type renames the snapshot allows. Columns: class, property, 3.0 type, 4.0 type;
    '*' in the first two matches any. A rename is qualified by class and property unless it is
    meant for every property of that type: TTyFilterComboBox.ShellListView keeps
    TTyShellListView while TTyShellTreeView.ShellListView takes the custom class, so a
    type-wide row would wave a wrong change through.
    The four D11 rows are type-wide on purpose: a component-reference property names the
    custom class wherever it appears, as LCL's Images: TCustomImageList does. }
  CSnapshotTypeRenames: array[0..5, 0..3] of string = (
    ('*', '*', 'TTyIconFont', 'TTyCustomIconFont'),
    ('*', '*', 'TTyStyleController', 'TTyCustomStyleController'),
    ('*', '*', 'TTyImageCollection', 'TTyCustomImageCollection'),
    ('*', '*', 'TTyVirtualImageList', 'TTyCustomVirtualImageList'),
    { Not component references: a host hands out, or takes, any custom child (plan R7-4). }
    ('TTyPageControl', 'ActivePage', 'TTyTabSheet', 'TTyCustomTabSheet'),
    { LCL: TCustomShellTreeView.ShellListView: TCustomShellListView (shellctrls.pas:139). }
    ('TTyShellTreeView', 'ShellListView', 'TTyShellListView', 'TTyCustomShellListView'));

  { G7: where each derived control's custom class must hang (plan appendix C-0), plus the
    intermediate classes. Columns: subject, expected parent, the class whose split activates
    the row. A final-class row checks Subject.ClassParent.ClassParent (the custom class's
    parent); an intermediate row (subject <> activator) checks Subject.ClassParent. }
  CChain: array[0..59, 0..2] of string = (
    ('TTyDropDownButton', 'TTyCustomButton', 'TTyDropDownButton'),
    ('TTyMenuButton', 'TTyCustomButton', 'TTyMenuButton'),
    ('TTyColorButton', 'TTyCustomButton', 'TTyColorButton'),
    ('TTyGlyphButton', 'TTyGlyphButtonBase', 'TTyGlyphButton'),
    ('TTyGlyphContainerButton', 'TTyGlyphButtonBase', 'TTyGlyphContainerButton'),
    ('TTySpeedButton', 'TTyGlyphButtonBase', 'TTySpeedButton'),
    ('TTyToolButton', 'TTyGlyphButtonBase', 'TTyToolButton'),
    ('TTyRibbonAppMenu', 'TTyCustomMenuButton', 'TTyRibbonAppMenu'),
    ('TTyNumericEdit', 'TTyCustomEdit', 'TTyNumericEdit'),
    ('TTyMaskEdit', 'TTyCustomEdit', 'TTyMaskEdit'),
    ('TTyURLEdit', 'TTyCustomEdit', 'TTyURLEdit'),
    ('TTyComboEdit', 'TTyCustomEdit', 'TTyComboEdit'),
    ('TTyCurrencyEdit', 'TTyCustomNumericEdit', 'TTyCurrencyEdit'),
    ('TTyTrackEdit', 'TTyCustomNumericEdit', 'TTyTrackEdit'),
    ('TTyCalcEdit', 'TTyCustomNumericEdit', 'TTyCalcEdit'),
    ('TTyFloatSpinEdit', 'TTyCustomNumericEdit', 'TTyFloatSpinEdit'),
    ('TTyCalcCurrencyEdit', 'TTyCustomCurrencyEdit', 'TTyCalcCurrencyEdit'),
    ('TTyMRUComboBox', 'TTyCustomComboBox', 'TTyMRUComboBox'),
    ('TTyComboBoxEx', 'TTyCustomComboBox', 'TTyComboBoxEx'),
    ('TTyOfficeComboBox', 'TTyCustomComboBox', 'TTyOfficeComboBox'),
    ('TTyAdvancedComboBox', 'TTyCustomComboBox', 'TTyAdvancedComboBox'),
    ('TTyCheckComboBox', 'TTyCustomComboBox', 'TTyCheckComboBox'),
    ('TTyColorBox', 'TTyCustomComboBox', 'TTyColorBox'),
    ('TTyFontComboBox', 'TTyCustomComboBox', 'TTyFontComboBox'),
    ('TTyFontSizeComboBox', 'TTyCustomComboBox', 'TTyFontSizeComboBox'),
    ('TTyFilterComboBox', 'TTyCustomComboBox', 'TTyFilterComboBox'),
    ('TTyShellComboBox', 'TTyCustomComboBox', 'TTyShellComboBox'),
    ('TTyColorComboBox', 'TTyCustomColorBox', 'TTyColorComboBox'),
    ('TTyCheckListBox', 'TTyCustomListBox', 'TTyCheckListBox'),
    ('TTyOfficeListBox', 'TTyCustomListBox', 'TTyOfficeListBox'),
    ('TTyAdvancedListBox', 'TTyCustomListBox', 'TTyAdvancedListBox'),
    ('TTyValueListEditor', 'TTyCustomListBox', 'TTyValueListEditor'),
    ('TTyColorListBox', 'TTyCustomListBox', 'TTyColorListBox'),
    ('TTyFontListBox', 'TTyCustomListBox', 'TTyFontListBox'),
    ('TTyRadioGroup', 'TTyCustomGroupBox', 'TTyRadioGroup'),
    ('TTyCheckGroup', 'TTyCustomGroupBox', 'TTyCheckGroup'),
    ('TTyToolGroupPanel', 'TTyCustomGroupBox', 'TTyToolGroupPanel'),
    ('TTyPaintPanel', 'TTyCustomPanel', 'TTyPaintPanel'),
    ('TTyExPanel', 'TTyCustomPanel', 'TTyExPanel'),
    ('TTyGridPanel', 'TTyCustomPanel', 'TTyGridPanel'),
    ('TTyRelativePanel', 'TTyCustomPanel', 'TTyRelativePanel'),
    ('TTyScrollBox', 'TTyCustomPanel', 'TTyScrollBox'),
    ('TTyControlBar', 'TTyCustomPanel', 'TTyControlBar'),
    ('TTyScrollPanel', 'TTyCustomScrollBox', 'TTyScrollPanel'),
    ('TTyCoolBar', 'TTyCustomControlBar', 'TTyCoolBar'),
    ('TTyToolBarEx', 'TTyCustomToolBar', 'TTyToolBarEx'),
    ('TTyShellTreeView', 'TTyShellTreeLink', 'TTyShellTreeView'),
    ('TTyShellListView', 'TTyCustomListView', 'TTyShellListView'),
    ('TTyPageControl', 'TTyCustomTabStrip', 'TTyPageControl'),
    ('TTyTabSet', 'TTyCustomTabStrip', 'TTyTabSet'),
    ('TTyRibbon', 'TTyCustomTabStrip', 'TTyRibbon'),
    ('TTyDrawGrid', 'TTyCustomGrid', 'TTyDrawGrid'),
    ('TTyStringGrid', 'TTyCustomDrawGrid', 'TTyStringGrid'),
    ('TTyLucideIconFont', 'TTyIconPackFont', 'TTyLucideIconFont'),
    ('TTyLucideImageList', 'TTyCustomVirtualImageList', 'TTyLucideImageList'),
    { intermediates: activated by their family root }
    ('TTyGlyphButtonBase', 'TTyCustomButton', 'TTyButton'),
    ('TTyShellTreeLink', 'TTyCustomTreeView', 'TTyTreeView'),
    ('TTyIconPackFont', 'TTyCustomIconFont', 'TTyIconFont'),
    ('TTyCustomTabStrip', 'TTyCustomControl', 'TTyPageControl'),
    ('TTyCustomGrid', 'TTyCustomControl', 'TTyDrawGrid'));

type
  { Reads the per-row type key of the list-box family (GetItemStyleTypeKey) -- any
    TTyCustomListBox, since 4.0 the derived list boxes are not TTyListBox descendants. }
  TListBoxKeyAccess = class(TTyCustomListBox);

var
  GSplit, GPending, GDemoted: TStringList;

procedure AddAll(AList: TStringList; const ANames: array of string);
var
  i: Integer;
begin
  for i := Low(ANames) to High(ANames) do
    AList.Add(ANames[i]);
end;

function CustomClassesSplit: TStrings;
begin
  Result := GSplit;
end;

{ ------------------------------------------------------------------ populations }

{ The classes that occur as snapshot inputs only (split.py reads them; the comparison skips
  them, because changing them is the point of the plan) -- also the name lookup for the
  intermediate classes, which nothing registers. }
function SnapshotInputs: TList;
begin
  Result := TList.Create;
  Result.Add(TTyCustomControl);
  Result.Add(TTyGraphicControl);
  Result.Add(TTyComponent);
  Result.Add(TTyGlyphButtonBase);
  Result.Add(TTyCustomTabStrip);
  Result.Add(TTyCustomGrid);
  Result.Add(TTyShellTreeLink);
  Result.Add(TTyIconPackFont);
  Result.Add(TTyCustomFileDialog);
  Result.Add(TTyCustomToolWindowManager);
end;

{ Compared too: the LCL roots never change. }
function LclRoots: TList;
begin
  Result := TList.Create;
  Result.Add(TComponent);
  Result.Add(TCustomControl);
  Result.Add(TGraphicControl);
  Result.Add(TCustomImageList);
end;

{ Registered classes (resolved by name; test.version RegisterClasses all of them) plus the
  stream-only ones, sorted by name. Objects[] holds the class. }
function RegisteredPopulation: TStringList;
var
  names: TStringList;
  i: Integer;
  c: TPersistentClass;
begin
  Result := TStringList.Create;
  names := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    for i := Low(CStreamOnly) to High(CStreamOnly) do
      names.Add(CStreamOnly[i]);
    for i := 0 to names.Count - 1 do
    begin
      if Result.IndexOf(names[i]) >= 0 then Continue;
      c := GetClass(names[i]);
      if c = nil then
        raise Exception.CreateFmt('registered class %s does not resolve with GetClass', [names[i]]);
      Result.AddObject(names[i], TObject(c));
    end;
  finally
    names.Free;
  end;
  Result.Sort;
end;

function FindClassByName(const AName: string): TClass;
var
  l: TList;
  i: Integer;
begin
  Result := GetClass(AName);
  if Result <> nil then Exit;
  l := SnapshotInputs;
  try
    for i := 0 to l.Count - 1 do
      if SameText(TClass(l[i]).ClassName, AName) then
        Exit(TClass(l[i]));
  finally
    l.Free;
  end;
  l := LclRoots;
  try
    for i := 0 to l.Count - 1 do
      if SameText(TClass(l[i]).ClassName, AName) then
        Exit(TClass(l[i]));
  finally
    l.Free;
  end;
end;

function InList(const AName: string; const AList: array of string): Boolean;
var
  i: Integer;
begin
  for i := Low(AList) to High(AList) do
    if SameText(AList[i], AName) then
      Exit(True);
  Result := False;
end;

function PublishedNames(AClass: TClass): TStringList;
var
  pl: PPropList;
  n, i: Integer;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := False;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  n := GetPropList(AClass.ClassInfo, pl);
  try
    for i := 0 to n - 1 do
      Result.Add(pl^[i]^.Name);
  finally
    FreeMem(pl);
  end;
end;

function LclRootOf(AClass: TClass): TClass;
begin
  Result := AClass;
  while (Result <> nil) and AnsiStartsStr('TTy', Result.ClassName) do
    Result := Result.ClassParent;
end;

function IsSplitShape(AClass: TClass): Boolean;
begin
  Result := (AClass.ClassParent <> nil)
    and SameText(AClass.ClassParent.ClassName, 'TTyCustom' + Copy(AClass.ClassName, 4, MaxInt));
end;

{ ------------------------------------------------------------------ the snapshot }

function OrdinalKind(AKind: TTypeKind): Boolean;
begin
  Result := AKind in [tkInteger, tkChar, tkEnumeration, tkSet, tkWChar, tkBool, tkInt64, tkQWord];
end;

function StoredCode(PI: PPropInfo): string;
begin
  if ((PI^.PropProcs shr 4) and 3) = ptConst then
  begin
    if PI^.StoredProc <> nil then Result := 'T' else Result := 'F';
  end
  else
    Result := 'D';
end;

function AccessCode(PI: PPropInfo): string;
begin
  Result := '';
  if PI^.GetProc <> nil then Result := Result + 'R';
  if PI^.SetProc <> nil then Result := Result + 'W';
end;

{ Columns 4..9 of a property row: TypeName Kind Default Stored Index Access. }
function AttrColumns(PI: PPropInfo): string;
begin
  Result := PI^.PropType^.Name + #9
    + GetEnumName(TypeInfo(TTypeKind), Ord(PI^.PropType^.Kind)) + #9
    + IntToStr(PI^.Default) + #9
    + StoredCode(PI) + #9
    + IntToStr(PI^.Index) + #9
    + AccessCode(PI);
end;

function NewInstance(AClass: TClass): TComponent;
begin
  if AClass.InheritsFrom(TCustomForm) then
    Result := TCustomFormClass(AClass).CreateNew(nil)
  else
    Result := TComponentClass(AClass).Create(nil);
end;

function SubKeys(AInst: TComponent): string;
begin
  Result := '-';
  try
    if AInst is TTyCustomListBox then
      Result := TListBoxKeyAccess(AInst).GetItemStyleTypeKey
    else if AInst is TTyTreeSelect then
      Result := TTyTreeSelectTree(TTyTreeSelect(AInst).Tree).StyleTypeKey
    else if AInst is TTyPopover then
      Result := TTyPopover(AInst).StyleTypeKey + '|' + TTyPopover(AInst).TitleStyleTypeKey
    else if AInst is TTyNotification then
      Result := TTyNotification(AInst).StyleTypeKey + '|' + TTyNotification(AInst).CloseStyleTypeKey;
  except
    Result := 'x';
  end;
end;

procedure SnapshotClass(AClass: TClass; AFresh: Boolean; AOut: TStrings);
var
  pl: PPropList;
  n, i: Integer;
  chain, key, styleCls, sub, size, fresh: string;
  c: TClass;
  inst: TComponent;
  s: ITyStyleable;
  PI: PPropInfo;
begin
  chain := '';
  c := AClass.ClassParent;
  while c <> nil do
  begin
    if chain <> '' then chain := chain + ',';
    chain := chain + c.ClassName;
    if c = TPersistent then Break;
    c := c.ClassParent;
  end;
  n := GetPropList(AClass.ClassInfo, pl);
  try
    AOut.Add(Format('# %s n=%d chain=%s', [AClass.ClassName, n, chain]));
    inst := nil;
    if AFresh then
    begin
      try
        inst := NewInstance(AClass);
      except
        inst := nil;
      end;
      if inst = nil then
        AOut.Add('#typekey'#9'x'#9'x'#9'x'#9'x')
      else
      begin
        try
          if Supports(inst, ITyStyleable, s) then key := s.GetStyleTypeKey else key := '-';
        except
          key := 'x';
        end;
        s := nil;
        try
          if GetPropInfo(inst, 'StyleClass') <> nil then
            styleCls := GetStrProp(inst, 'StyleClass')
          else
            styleCls := '-';
        except
          styleCls := 'x';
        end;
        sub := SubKeys(inst);
        try
          if inst is TControl then
            size := Format('%dx%d', [TControl(inst).Width, TControl(inst).Height])
          else
            size := '-';
        except
          size := 'x';
        end;
        AOut.Add('#typekey'#9 + key + #9 + styleCls + #9 + sub + #9 + size);
      end;
    end;
    try
      for i := 0 to n - 1 do
      begin
        PI := pl^[i];
        if not AFresh then
          fresh := '-'
        else if inst = nil then
          fresh := 'x'
        else
          try
            if IsStoredProp(inst, PI) then fresh := 's=1' else fresh := 's=0';
            if OrdinalKind(PI^.PropType^.Kind) and (PI^.Default <> Low(LongInt)) then
            begin
              if GetOrdProp(inst, PI) = PI^.Default then
                fresh := fresh + ',d=eq'
              else
                fresh := fresh + ',d=ne';
            end
            else
              fresh := fresh + ',d=-';
          except
            fresh := 'x';
          end;
        AOut.Add(AClass.ClassName + #9 + IntToStr(i) + #9 + PI^.Name + #9 + AttrColumns(PI)
          + #9 + fresh);
      end;
    finally
      if inst <> nil then
        try
          inst.Free;
        except
          { a destructor that needs a parent window must not take the guard down }
        end;
    end;
  finally
    FreeMem(pl);
  end;
end;

{ The whole snapshot, sorted by class name. AScope receives the names whose sections are
  compared (registered, stream-only, LCL roots). }
function BuildSnapshot(AScope: TStrings): TStringList;
var
  all: TStringList;
  reg: TStringList;
  l: TList;
  i: Integer;
begin
  Result := TStringList.Create;
  all := TStringList.Create;
  reg := RegisteredPopulation;
  try
    for i := 0 to reg.Count - 1 do
    begin
      all.AddObject(reg[i], TObject(PtrUInt(1)));
      AScope.Add(reg[i]);
    end;
    l := SnapshotInputs;
    try
      for i := 0 to l.Count - 1 do
        all.AddObject(TClass(l[i]).ClassName, TObject(PtrUInt(2)));
    finally
      l.Free;
    end;
    l := LclRoots;
    try
      for i := 0 to l.Count - 1 do
      begin
        all.AddObject(TClass(l[i]).ClassName, TObject(PtrUInt(3)));
        AScope.Add(TClass(l[i]).ClassName);
      end;
    finally
      l.Free;
    end;
    all.Sort;
    for i := 0 to all.Count - 1 do
      SnapshotClass(FindClassByName(all[i]), PtrUInt(all.Objects[i]) = 1, Result);
  finally
    reg.Free;
    all.Free;
  end;
end;

{ Split lines into sections keyed by class name. Each section's lines are stored as one
  #10-joined string. The header's chain= is cut off: the chain is the one thing the split
  changes on purpose (G1 / G7 own it); n= stays. }
procedure Sectionize(ALines: TStrings; ADest: TStringList);
var
  i, p: Integer;
  cur, body, line: string;
begin
  cur := '';
  body := '';
  for i := 0 to ALines.Count - 1 do
  begin
    line := ALines[i];
    if AnsiStartsStr('# ', line) then
    begin
      if cur <> '' then ADest.Values[cur] := body;
      cur := ExtractWord(2, line, [' ']);
      p := Pos(' chain=', line);
      if p > 0 then line := Copy(line, 1, p - 1);
      body := line;
    end
    else if cur <> '' then
      body := body + #10 + line;
  end;
  if cur <> '' then ADest.Values[cur] := body;
end;

function RenameTypes(const ALine: string): string;
var
  f: TStringArray;
  i: Integer;
begin
  Result := ALine;
  if (ALine = '') or (ALine[1] = '#') then Exit;
  f := ALine.Split([#9]);
  if Length(f) <> 10 then Exit;
  { f: class, index, name, type, ... }
  for i := Low(CSnapshotTypeRenames) to High(CSnapshotTypeRenames) do
    if ((CSnapshotTypeRenames[i, 0] = '*') or (f[0] = CSnapshotTypeRenames[i, 0]))
       and ((CSnapshotTypeRenames[i, 1] = '*') or (f[2] = CSnapshotTypeRenames[i, 1]))
       and (f[3] = CSnapshotTypeRenames[i, 2]) then
      f[3] := CSnapshotTypeRenames[i, 3];
  Result := string.Join(#9, f);
end;

procedure TTyCustomClassesGuardTest.TestPublishedSnapshotUnchanged;
var
  scope, cur, gold, curSec, goldSec, merged: TStringList;
  path, only, a, b, firstMsg, la1, lb1: string;
  i, j, diffs, cls, nmax: Integer;
  la, lb: TStringArray;
  copying: Boolean;
begin
  path := RepoRoot + CSnapshotFile;
  scope := TStringList.Create;
  cur := nil; gold := nil; curSec := nil; goldSec := nil; merged := nil;
  try
    cur := BuildSnapshot(scope);
    cur.LineBreak := #10;
    if GetEnvironmentVariable('TY_WRITE_GOLDEN') = '1' then
    begin
      ForceDirectories(ExtractFilePath(path));
      cur.SaveToFile(path);
      Exit;
    end;
    gold := TStringList.Create;
    only := GetEnvironmentVariable('TY_WRITE_GOLDEN_CLASS');
    if only <> '' then
    begin
      { Replace one class's section only (plan N24): another branch changed that class's
        published set on purpose, and the rest of the fixture must stay the 3.0 record. }
      gold.LoadFromFile(path);
      merged := TStringList.Create;
      merged.LineBreak := #10;
      i := 0;
      while i < gold.Count do
      begin
        if AnsiStartsStr('# ' + only + ' ', gold[i]) then
        begin
          Inc(i);
          while (i < gold.Count) and not AnsiStartsStr('# ', gold[i]) do Inc(i);
          copying := False;
          for j := 0 to cur.Count - 1 do
          begin
            if AnsiStartsStr('# ', cur[j]) then
              copying := AnsiStartsStr('# ' + only + ' ', cur[j]);
            if copying then merged.Add(cur[j]);
          end;
          Continue;
        end;
        merged.Add(gold[i]);
        Inc(i);
      end;
      merged.SaveToFile(path);
      Exit;
    end;

    AssertTrue('snapshot fixture missing: ' + path
      + ' (it is generated once, before the split, with TY_WRITE_GOLDEN=1)', FileExists(path));
    gold.LoadFromFile(path);   // LoadFromFile takes CRLF and LF alike
    { Both sides: a rename lands in its own task (Q8 / D11), so before it the current RTTI still
      says the old name, after it both say the new one. }
    for i := 0 to gold.Count - 1 do
      gold[i] := RenameTypes(gold[i]);
    for i := 0 to cur.Count - 1 do
      cur[i] := RenameTypes(cur[i]);
    curSec := TStringList.Create;
    goldSec := TStringList.Create;
    Sectionize(cur, curSec);
    Sectionize(gold, goldSec);

    diffs := 0;
    firstMsg := '';
    for cls := 0 to scope.Count - 1 do
    begin
      a := goldSec.Values[scope[cls]];
      b := curSec.Values[scope[cls]];
      if a = b then Continue;
      la := a.Split([#10]);
      lb := b.Split([#10]);
      nmax := Length(la);
      if Length(lb) > nmax then nmax := Length(lb);
      for j := 0 to nmax - 1 do
      begin
        if j < Length(la) then la1 := la[j] else la1 := '<missing>';
        if j < Length(lb) then lb1 := lb[j] else lb1 := '<missing>';
        if la1 = lb1 then Continue;
        Inc(diffs);
        if firstMsg = '' then
          firstMsg := Format('class %s, line %d of its section:'#10'  fixture: %s'#10'  now:     %s',
            [scope[cls], j + 1, la1, lb1]);
      end;
    end;
    AssertEquals('published snapshot differs in ' + IntToStr(diffs) + ' line(s); first: '
      + firstMsg, 0, diffs);
  finally
    scope.Free;
    cur.Free;
    gold.Free;
    curSec.Free;
    goldSec.Free;
    merged.Free;
  end;
end;

{ ------------------------------------------------------------------ structural guards }

function SplitClasses: TList;
var
  i: Integer;
  c: TClass;
begin
  Result := TList.Create;
  for i := 0 to GSplit.Count - 1 do
  begin
    c := GetClass(GSplit[i]);
    if c = nil then
      raise Exception.CreateFmt('CSplit names %s, which does not resolve', [GSplit[i]]);
    Result.Add(c);
  end;
end;

procedure TTyCustomClassesGuardTest.TestSplitClassesSitOnTheirCustomClass;
var
  l: TList;
  i: Integer;
  bad: string;
begin
  bad := '';
  l := SplitClasses;
  try
    for i := 0 to l.Count - 1 do
      if not IsSplitShape(TClass(l[i])) then
        bad := bad + ' ' + TClass(l[i]).ClassName + '(parent ' + TClass(l[i]).ClassParent.ClassName + ')';
  finally
    l.Free;
  end;
  AssertEquals('split classes whose direct parent is not TTyCustom<Name>:' + bad, '', bad);
end;

procedure TTyCustomClassesGuardTest.TestCustomClassesPublishNothingNew;
var
  l: TList;
  i, k: Integer;
  bad: string;
  cust, root: TClass;
  cn, rn: TStringList;
begin
  bad := '';
  l := SplitClasses;
  try
    for i := 0 to l.Count - 1 do
    begin
      cust := TClass(l[i]).ClassParent;
      root := LclRootOf(cust);
      cn := PublishedNames(cust);
      rn := PublishedNames(root);
      try
        for k := 0 to cn.Count - 1 do
          if rn.IndexOf(cn[k]) < 0 then
            bad := bad + ' ' + cust.ClassName + ':' + cn[k];
        for k := 0 to rn.Count - 1 do
          if cn.IndexOf(rn[k]) < 0 then
            bad := bad + ' ' + cust.ClassName + ':-' + rn[k];
      finally
        cn.Free;
        rn.Free;
      end;
    end;
  finally
    l.Free;
  end;
  AssertEquals('custom classes publishing more than their LCL root:' + bad, '', bad);
end;

{ Strip Pascal comments, keep line breaks. }
function StripComments(const S: string): string;
var
  i, n: Integer;
begin
  Result := '';
  i := 1;
  n := Length(S);
  while i <= n do
  begin
    if S[i] = '{' then
    begin
      while (i <= n) and (S[i] <> '}') do
      begin
        if S[i] in [#10, #13] then Result := Result + S[i];
        Inc(i);
      end;
      Inc(i);
    end
    else if (S[i] = '(') and (i < n) and (S[i + 1] = '*') then
    begin
      Inc(i, 2);
      while (i < n) and not ((S[i] = '*') and (S[i + 1] = ')')) do
      begin
        if S[i] in [#10, #13] then Result := Result + S[i];
        Inc(i);
      end;
      Inc(i, 2);
    end
    else if (S[i] = '/') and (i < n) and (S[i + 1] = '/') then
    begin
      while (i <= n) and not (S[i] in [#10, #13]) do Inc(i);
    end
    else if S[i] = '''' then
    begin
      Result := Result + S[i];
      Inc(i);
      while (i <= n) and (S[i] <> '''') and not (S[i] in [#10, #13]) do
      begin
        Result := Result + S[i];
        Inc(i);
      end;
      if i <= n then
      begin
        Result := Result + S[i];
        Inc(i);
      end;
    end
    else
    begin
      Result := Result + S[i];
      Inc(i);
    end;
  end;
end;

function IsPropertyOnlyLine(const ALine: string): Boolean;
var
  t, rest: string;
  k: Integer;
begin
  t := Trim(ALine);
  if (t = '') or SameText(t, 'published') then Exit(True);
  Result := False;
  if not AnsiStartsText('property', t) then Exit;
  rest := Trim(Copy(t, 9, MaxInt));
  if (Length(t) <= 8) or not (t[9] in [' ', #9]) then Exit;
  if (rest = '') or (rest[Length(rest)] <> ';') then Exit;
  rest := Trim(Copy(rest, 1, Length(rest) - 1));
  if rest = '' then Exit;
  for k := 1 to Length(rest) do
    if not (rest[k] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit;
  Result := True;
end;

{ G3. The plan's part (a) -- "whatever the custom class publishes has the same RTTI attributes
  on the final class" -- is gone: a final class that holds only `property X;` lines (part (b)
  below) inherits every attribute unchanged, so (a) could only fail where (b) already had, and
  no mutation could turn it red on its own. Where a specifier lives -- custom class or final
  class -- is checked from the third party's side by G9 (TestGeneratedMimicsMatchTheirFinalClass),
  and against 3.0 by G6. }
procedure TTyCustomClassesGuardTest.TestCustomAndFinalAgree;
var
  l: TList;
  i, k, f, ln: Integer;
  bad, src, code, cname, header, line: string;
  files, lines: TStringList;
  found: Boolean;
begin
  bad := '';
  l := SplitClasses;
  files := FindAllFiles(RepoRoot + 'source', '*.pas', False);
  lines := TStringList.Create;
  try
    { (b) source: the final class declaration is nothing but `published` and `property X;`. }
    for i := 0 to l.Count - 1 do
    begin
      cname := TClass(l[i]).ClassName;
      header := cname + ' = class(TTyCustom' + Copy(cname, 4, MaxInt) + ')';
      found := False;
      for f := 0 to files.Count - 1 do
      begin
        src := ReadFileToString(files[f]);
        if Pos(LowerCase(header), LowerCase(src)) = 0 then Continue;
        code := StripComments(src);
        lines.Text := code;
        for ln := 0 to lines.Count - 1 do
        begin
          if not SameText(DelSpace(lines[ln]), DelSpace(header)) then Continue;
          found := True;
          k := ln + 1;
          while k < lines.Count do
          begin
            line := Trim(lines[k]);
            if SameText(line, 'end;') then Break;
            if not IsPropertyOnlyLine(line) then
              bad := bad + LineEnding + '  ' + cname + ': ' + line;
            Inc(k);
          end;
          Break;
        end;
        if found then Break;
      end;
      if not found then
        bad := bad + LineEnding + '  ' + cname + ': declaration `' + header + '` not found in source/';
    end;
    AssertEquals('final classes must hold only `property X;` lines:' + bad, '', bad);
  finally
    l.Free;
    files.Free;
    lines.Free;
  end;
end;

procedure TTyCustomClassesGuardTest.TestFinalClassesAddNoFields;
var
  l: TList;
  i: Integer;
  bad: string;
begin
  bad := '';
  l := SplitClasses;
  try
    for i := 0 to l.Count - 1 do
      if TClass(l[i]).InstanceSize <> TClass(l[i]).ClassParent.InstanceSize then
        bad := bad + ' ' + TClass(l[i]).ClassName;
  finally
    l.Free;
  end;
  AssertEquals('final classes larger than their custom class:' + bad, '', bad);
end;

procedure TTyCustomClassesGuardTest.TestEveryRegisteredClassIsAccountedFor;
var
  pop: TStringList;
  i, hits: Integer;
  bad, n: string;
  c: TClass;
begin
  bad := '';
  pop := RegisteredPopulation;
  try
    { (1) + (2): exactly one list each. }
    for i := 0 to pop.Count - 1 do
    begin
      n := pop[i];
      hits := 0;
      if GSplit.IndexOf(n) >= 0 then Inc(hits);
      if GPending.IndexOf(n) >= 0 then Inc(hits);
      if InList(n, CNotSplit) then Inc(hits);
      if hits <> 1 then
        bad := bad + Format(' %s(in %d lists)', [n, hits]);
    end;
    { (3): pending and not-split classes are NOT split. }
    for i := 0 to pop.Count - 1 do
    begin
      n := pop[i];
      c := TClass(pop.Objects[i]);
      if SameText(n, 'TTyToolWindowManager') then Continue;   // plan Q4: shape exemption
      if ((GPending.IndexOf(n) >= 0) or InList(n, CNotSplit)) and IsSplitShape(c) then
        bad := bad + ' ' + n + '(split but still listed as pending / not split)';
    end;
    { (4): every split class is in the population. }
    for i := 0 to GSplit.Count - 1 do
      if pop.IndexOf(GSplit[i]) < 0 then
        bad := bad + ' ' + GSplit[i] + '(in CSplit but not registered)';
    for i := 0 to GPending.Count - 1 do
      if pop.IndexOf(GPending[i]) < 0 then
        bad := bad + ' ' + GPending[i] + '(in CPending but not registered)';
  finally
    pop.Free;
  end;
  AssertEquals('registered classes not accounted for:' + bad, '', bad);
end;

procedure TTyCustomClassesGuardTest.TestDerivedControlsHangOnTheCustomChain;
var
  reg: TStringList;
  i: Integer;
  bad1, bad2, bad3, subj, want: string;
  c, p, walk: TClass;
  isFinal, inherits: Boolean;
begin
  bad1 := ''; bad2 := ''; bad3 := '';
  reg := RegisteredPopulation;
  try
    for i := Low(CChain) to High(CChain) do
    begin
      if GSplit.IndexOf(CChain[i, 2]) < 0 then Continue;   // not yet active
      subj := CChain[i, 0];
      want := CChain[i, 1];
      isFinal := SameText(subj, CChain[i, 2]);
      c := FindClassByName(subj);
      if c = nil then
      begin
        bad1 := bad1 + ' ' + subj + '(unresolved)';
        Continue;
      end;
      { (1) the expected parent }
      if isFinal then p := c.ClassParent.ClassParent else p := c.ClassParent;
      if p = nil then
        bad1 := bad1 + Format(' %s(nil, want %s)', [subj, want])
      else if not SameText(p.ClassName, want) then
        bad1 := bad1 + Format(' %s(%s, want %s)', [subj, p.ClassName, want]);
      { (2) no registered final class on the way up to the LCL root }
      walk := c.ClassParent;
      while (walk <> nil) and AnsiStartsStr('TTy', walk.ClassName) do
      begin
        if reg.IndexOf(walk.ClassName) >= 0 then
          bad2 := bad2 + ' ' + subj + '<' + walk.ClassName;
        walk := walk.ClassParent;
      end;
      { (3) it does inherit from the expected parent }
      inherits := False;
      walk := c.ClassParent;
      while walk <> nil do
      begin
        if SameText(walk.ClassName, want) then inherits := True;
        walk := walk.ClassParent;
      end;
      if not inherits then
        bad3 := bad3 + ' ' + subj;
    end;
  finally
    reg.Free;
  end;
  AssertEquals('wrong parent:' + bad1, '', bad1);
  AssertEquals('a registered final class sits on the chain:' + bad2, '', bad2);
  AssertEquals('does not inherit from the expected custom parent:' + bad3, '', bad3);
end;

procedure TTyCustomClassesGuardTest.TestDemotedClassesPublishOnlyTheLclRoot;
var
  i, k: Integer;
  c: TClass;
  cn, rn: TStringList;
  bad: string;
begin
  bad := '';
  for i := 0 to GDemoted.Count - 1 do
  begin
    c := FindClassByName(GDemoted[i]);
    if c = nil then
    begin
      bad := bad + ' ' + GDemoted[i] + '(unresolved)';
      Continue;
    end;
    cn := PublishedNames(c);
    rn := PublishedNames(LclRootOf(c));
    try
      for k := 0 to cn.Count - 1 do
        if rn.IndexOf(cn[k]) < 0 then
          bad := bad + ' ' + c.ClassName + ':' + cn[k];
    finally
      cn.Free;
      rn.Free;
    end;
  end;
  AssertEquals('demoted classes still publishing:' + bad, '', bad);
end;

type
  { A third party that derives straight from the windowed base and writes no published
    section -- the shape the incompatibility list (item 2) is about. }
  TBareThirdParty = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  end;

function TBareThirdParty.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';
end;

procedure TTyCustomClassesGuardTest.TestBaseClassesPublishNothing;
const
  CBases: array[0..2] of string = ('TTyCustomControl', 'TTyGraphicControl', 'TTyComponent');
var
  i: Integer;
  c: TClass;
  cn, rn: TStringList;
begin
  for i := Low(CBases) to High(CBases) do
  begin
    AssertTrue(CBases[i] + ' is in CDemoted', GDemoted.IndexOf(CBases[i]) >= 0);
    c := FindClassByName(CBases[i]);
    cn := PublishedNames(c);
    rn := PublishedNames(LclRootOf(c));
    try
      AssertEquals(CBases[i] + ' publishes exactly its LCL root''s names (' + LclRootOf(c).ClassName
        + ')', rn.CommaText, cn.CommaText);
    finally
      cn.Free;
      rn.Free;
    end;
  end;
end;

procedure TTyCustomClassesGuardTest.TestThirdPartyOnTheBareBaseSeesOnlyTheLclRoot;
var
  cn, rn: TStringList;
begin
  cn := PublishedNames(TBareThirdParty);
  rn := PublishedNames(TCustomControl);
  try
    AssertEquals('TCustomControl publishes Name, Tag and TControl''s 13', 15, rn.Count);
    AssertEquals('a class on the bare base publishes only what TCustomControl does',
      rn.CommaText, cn.CommaText);
    AssertTrue('Enabled is no longer published by the base', cn.IndexOf('Enabled') < 0);
    AssertTrue('nor is the library''s own StyleClass', cn.IndexOf('StyleClass') < 0);
  finally
    cn.Free;
    rn.Free;
  end;
end;

{ ------------------------------------------------------------------ G9: the generated mimics }

type
  TCtlStyleAccess = class(TTyCustomControl);
  TGfxStyleAccess = class(TTyGraphicControl);

{ Every published property of AClass in RTTI order: name and the snapshot's attribute columns. }
function RttiRows(AClass: TClass): string;
var
  pl: PPropList;
  n, i: Integer;
begin
  Result := '';
  n := GetPropList(AClass.ClassInfo, pl);
  try
    for i := 0 to n - 1 do
      Result := Result + IntToStr(i) + #9 + pl^[i]^.Name + #9 + AttrColumns(pl^[i]) + LineEnding;
  finally
    if n > 0 then FreeMem(pl);
  end;
end;

{ A published date / time a constructor takes from the clock (TTyAnalogClock.Time is Now) is
  pinned to one value on both instances before they are streamed: two instances made a moment
  apart can straddle a clock tick, and the line would differ for no reason a form file cares
  about. Only the value is pinned; whether the line is written at all still comes from each
  class's own stored / default, which is what G9 compares. }
procedure PinClockValues(AComp: TComponent);
const
  CPinned = 36526.5;   // 2000-01-01 12:00
var
  pl: PPropList;
  n, i: Integer;
  tn: string;
begin
  n := GetPropList(AComp.ClassInfo, pl);
  try
    for i := 0 to n - 1 do
    begin
      if pl^[i]^.PropType^.Kind <> tkFloat then Continue;
      tn := pl^[i]^.PropType^.Name;
      if not (SameText(tn, 'TDateTime') or SameText(tn, 'TDate') or SameText(tn, 'TTime')) then
        Continue;
      if (pl^[i]^.SetProc = nil) or (Abs(GetFloatProp(AComp, pl^[i]) - Now) > 1) then Continue;
      SetFloatProp(AComp, pl^[i], CPinned);
    end;
  finally
    if n > 0 then FreeMem(pl);
  end;
end;

const
  CNoChildStreamed = '<the host wrote no child>';

{ What a fresh instance writes into the .lfm of the form it sits on: AHost is streamed the way
  the IDE saves a form, and what is kept is everything the form writes for its children (the
  one control under test, and whatever it created owned by the form -- a grid panel's cells),
  without the first `object` line (it names the class) and the form's own closing `end`.
  Through the host and not with the control as the root: streamed as the root, a control writes
  the children it creates and owns itself -- scroll bars, cell editors -- which no .lfm ever
  carries, and one of those (the string grid's date editor) starts at Now, so the comparison
  flickered with the clock. A form file never sees those children, so G9 does not either.
  The control's internal children are built by the custom class's constructor for mimic and
  final class alike; what a third party can get wrong shows on the control itself. }
function FreshStreamBody(AHost: TComponent): string;
var
  ms: TMemoryStream;
  ss: TStringStream;
  p: Integer;
begin
  ms := TMemoryStream.Create;
  ss := TStringStream.Create('');
  try
    ms.WriteComponent(AHost);
    ms.Position := 0;
    ObjectBinaryToText(ms, ss);
    Result := ss.DataString;
  finally
    ms.Free;
    ss.Free;
  end;
  { The first child's `object` line: two spaces in, one level below the form. }
  p := Pos(#10'  object ', Result);
  if p = 0 then Exit(CNoChildStreamed);
  Delete(Result, 1, p);
  p := Pos(#10, Result);
  Delete(Result, 1, p);
  { The form's own `end`, the last line. }
  Result := TrimRight(Result);
  if AnsiEndsStr(#10'end', Result) then
    SetLength(Result, Length(Result) - 3);
end;

{ The resolved theme style, as far as a control's look depends on it. }
function StyleText(AComp: TComponent): string;
var
  s: TTyStyleSet;
begin
  if AComp is TTyCustomControl then
    s := TCtlStyleAccess(AComp).CurrentStyle
  else if AComp is TTyGraphicControl then
    s := TGfxStyleAccess(AComp).CurrentStyle
  else
    Exit('-');
  Result := Format('bg=%d/%x txt=%x bc=%x bw=%d bs=%d rs=%d br=%d pad=%d,%d,%d,%d '
    + 'font=%s/%d/%d op=%.3f sh=%x/%d/%d,%d ol=%x/%d/%d',
    [Ord(s.Background.Kind), s.Background.Color, s.TextColor, s.BorderColor, s.BorderWidth,
     Ord(s.BorderStyle), Ord(s.RenderStyle), s.BorderRadius, s.Padding.Left, s.Padding.Top,
     s.Padding.Right, s.Padding.Bottom, s.FontName, s.FontSize, s.FontWeight, s.Opacity,
     s.ShadowColor, s.ShadowBlur, s.ShadowOffset.X, s.ShadowOffset.Y, s.OutlineColor,
     s.OutlineWidth, s.OutlineOffset]);
end;

{ G9 (standing; it does NOT retire with the snapshot). A third party derives TTyCustomXxx and
  publishes what it wants (issue #8). If it publishes exactly what TTyXxx publishes, it must BE
  TTyXxx in every way a form file and a theme can see: same RTTI rows (order, type, default,
  stored, index, access), same fresh stream, same type key, same default size, same resolved
  style. That holds only when every default, stored clause, type key and constructor value the
  final class shows lives in the custom class -- the third party's view, which the snapshot (G6)
  never looked at: G6 compares the final class with 3.0 and passes whether a redeclaration
  sits in the custom class or in the final one. The mimics are generated from source by the
  plan's gen-mimic.py (test.customclasses.mimic); the first check makes a split class without a
  mimic red, so the generator is re-run as each phase splits more. }
procedure TTyCustomClassesGuardTest.TestGeneratedMimicsMatchTheirFinalClass;
var
  i: Integer;
  bad, a, b: string;
  gen, fin: TComponent;
  host, host2: TForm;
  sa, sb: ITyStyleable;
  covered: TStringList;
begin
  bad := '';
  covered := TStringList.Create;
  covered.CaseSensitive := False;
  try
    for i := Low(CGenMimics) to High(CGenMimics) do
    begin
      covered.Add(CGenMimics[i, 1].ClassName);
      if GSplit.IndexOf(CGenMimics[i, 1].ClassName) < 0 then
        bad := bad + LineEnding + '  mimic for a class not in CSplit: ' + CGenMimics[i, 1].ClassName;
      if CGenMimics[i, 0].ClassParent <> CGenMimics[i, 1].ClassParent then
        bad := bad + LineEnding + '  ' + CGenMimics[i, 0].ClassName + ' does not derive from '
          + CGenMimics[i, 1].ClassParent.ClassName;
    end;
    for i := 0 to GSplit.Count - 1 do
      if covered.IndexOf(GSplit[i]) < 0 then
        bad := bad + LineEnding + '  split class without a mimic (re-run gen-mimic.py): ' + GSplit[i];
  finally
    covered.Free;
  end;
  AssertEquals('the generated mimics do not cover CSplit:' + bad, '', bad);

  { Two hosts, so neither instance's TabOrder reflects the other one sitting next to it. }
  host := TForm.CreateNew(nil);
  host2 := TForm.CreateNew(nil);
  try
    host.SetBounds(0, 0, 640, 480);
    host2.SetBounds(0, 0, 640, 480);
    for i := Low(CGenMimics) to High(CGenMimics) do
    begin
      a := RttiRows(CGenMimics[i, 0]);
      b := RttiRows(CGenMimics[i, 1]);
      if a <> b then
        bad := bad + LineEnding + '  RTTI ' + CGenMimics[i, 1].ClassName + LineEnding + '    mimic: '
          + StringReplace(a, LineEnding, ' | ', [rfReplaceAll]) + LineEnding + '    final: '
          + StringReplace(b, LineEnding, ' | ', [rfReplaceAll]);
      gen := TComponentClass(CGenMimics[i, 0]).Create(host);
      fin := TComponentClass(CGenMimics[i, 1]).Create(host2);
      try
        if gen is TControl then TControl(gen).Parent := host;
        if fin is TControl then TControl(fin).Parent := host2;
        PinClockValues(gen);
        PinClockValues(fin);
        a := FreshStreamBody(host);
        b := FreshStreamBody(host2);
        if a = CNoChildStreamed then
          bad := bad + LineEnding + '  fresh stream ' + CGenMimics[i, 1].ClassName
            + ': the host form wrote nothing for it';
        if a <> b then
          bad := bad + LineEnding + '  fresh stream ' + CGenMimics[i, 1].ClassName + LineEnding
            + '--mimic--' + LineEnding + a + '--final--' + LineEnding + b;
        a := '-';
        b := '-';
        if Supports(gen, ITyStyleable, sa) then a := sa.GetStyleTypeKey;
        if Supports(fin, ITyStyleable, sb) then b := sb.GetStyleTypeKey;
        sa := nil;
        sb := nil;
        if a <> b then
          bad := bad + LineEnding + '  type key ' + CGenMimics[i, 1].ClassName + ': ' + a + ' vs ' + b;
        if (gen is TControl) and ((TControl(gen).Width <> TControl(fin).Width)
           or (TControl(gen).Height <> TControl(fin).Height)) then
          bad := bad + LineEnding + Format('  default size %s: %dx%d vs %dx%d',
            [CGenMimics[i, 1].ClassName, TControl(gen).Width, TControl(gen).Height,
             TControl(fin).Width, TControl(fin).Height]);
        a := StyleText(gen);
        b := StyleText(fin);
        if a <> b then
          bad := bad + LineEnding + '  style ' + CGenMimics[i, 1].ClassName + LineEnding + '    mimic: '
            + a + LineEnding + '    final: ' + b;
      finally
        gen.Free;
        fin.Free;
        { And whatever they made owned by the form: a grid panel's cells belong to the form
          (that is how they reach the .lfm) and outlive the panel. Left there, they would be
          written into every later class's comparison. }
        host.DestroyComponents;
        host2.DestroyComponents;
      end;
    end;
  finally
    host.Free;
    host2.Free;
  end;
  AssertTrue('anti-vacuity: no mimics were compared', Length(CGenMimics) >= GSplit.Count);
  AssertEquals('a third party publishing what the final class publishes is not that class:' + bad,
    '', bad);
end;

{ Properties whose fresh value is read off the machine the tests run on: the installed fonts,
  the drives. G10 keeps the line -- whether it is written, and where -- and masks the value. }
const
  CMachineValues: array[0..2, 0..1] of string = (
    ('TTyFontComboBox', 'Items.Strings'),
    ('TTyFontListBox', 'Items.Strings'),
    ('TTyShellTreeView', 'RootNodeCount'));

function IsPropPath(const S: string): Boolean;
var
  i: Integer;
begin
  Result := S <> '';
  for i := 1 to Length(S) do
    if not (S[i] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then Exit(False);
end;

{ Every string value becomes <text>. A fresh instance's strings come from resourcestrings
  (captions, palette names), the locale (a currency symbol, a decimal separator) or the
  machine, and a suite that loads a translation earlier in the run would change them all.
  What G10 is for -- whether a property is written at all, where, and its ordinal value --
  does not need them; G9 compares the strings themselves, mimic against final, in one run. }
function MaskStrings(const ABody: string): string;
var
  lines: TStringList;
  i, p, ind: Integer;
  t: string;
begin
  lines := TStringList.Create;
  try
    lines.Text := ABody;
    for i := 0 to lines.Count - 1 do
    begin
      t := Trim(lines[i]);
      if t = '' then Continue;
      ind := Length(lines[i]) - Length(TrimLeft(lines[i]));
      p := Pos(' = ', t);
      if (p > 1) and (p + 3 <= Length(t)) and (t[p + 3] in ['''', '#'])
         and IsPropPath(Copy(t, 1, p - 1)) then
        lines[i] := StringOfChar(' ', ind) + Copy(t, 1, p + 2) + '<text>'
      else if t[1] in ['''', '#'] then
      begin
        { An item of a string list; the last one carries the list's closing parenthesis. }
        if t[Length(t)] = ')' then
          lines[i] := StringOfChar(' ', ind) + '<text>)'
        else
          lines[i] := StringOfChar(' ', ind) + '<text>';
      end;
    end;
    lines.LineBreak := #10;
    Result := lines.Text;
  finally
    lines.Free;
  end;
end;

function MaskMachineValues(const AClassName, ABody: string): string;
var
  lines: TStringList;
  i, j, k: Integer;
  t: string;
begin
  lines := TStringList.Create;
  try
    lines.Text := ABody;
    for k := Low(CMachineValues) to High(CMachineValues) do
    begin
      if not SameText(CMachineValues[k, 0], AClassName) then Continue;
      for i := 0 to lines.Count - 1 do
      begin
        t := Trim(lines[i]);
        if not AnsiStartsStr(CMachineValues[k, 1] + ' = ', t) then Continue;
        lines[i] := Copy(lines[i], 1, Pos(CMachineValues[k, 1], lines[i]) - 1)
          + CMachineValues[k, 1] + ' = <from the machine>';
        { A string list runs on to the line that closes it: `'last item')`. }
        if AnsiEndsStr('(', t) then
        begin
          j := i + 1;
          while (j < lines.Count) and not AnsiEndsStr(')', Trim(lines[j])) do Inc(j);
          while j > i do
          begin
            if j < lines.Count then lines.Delete(j);
            Dec(j);
          end;
        end;
        Break;
      end;
    end;
    lines.LineBreak := #10;
    Result := lines.Text;
  finally
    lines.Free;
  end;
end;

{ G10 (standing; it does NOT retire with the snapshot). What a fresh instance of every
  registered class writes into the .lfm of the form it is dropped on, frozen in
  tests/fixtures/customclasses/fresh-streams.txt.

  It covers what G9 cannot see once G6 retires: a default, stored clause or constructor value
  that drifts on a CUSTOM class. G9 compares the final class with a third party's mimic, and
  both inherit the drift; G6 compares with the 3.0 record and goes in Task 32. Deleting
  `default True` from TTyCustomTabSheet.TabVisible made every fresh tab sheet start writing
  `TabVisible = True` -- G9 and the per-phase suites stayed green; this goes red.

  Frozen while G6 was green, so the fixture says what 3.0 wrote. Through a host form, as in
  G9 (FreshStreamBody), with clock values pinned, the values read off the machine masked
  (CMachineValues) and every string value masked (MaskStrings). Sizes are measured on Windows,
  as G6's are. The classes this plan does not split
  (CNotSplit) stay out: the forms cannot sit on a form, and the AdvChart-branch classes are
  still being changed elsewhere.

  Rewrite with TY_WRITE_FRESH_STREAMS=1 only when a change to what a form file says is the
  point of the commit; the diff of the fixture is then the review. }
procedure TTyCustomClassesGuardTest.TestFreshFormFileTextUnchanged;
var
  reg, cur, gold, curSec, goldSec: TStringList;
  i, diffs: Integer;
  host: TForm;
  inst: TComponent;
  body, path, firstMsg, a, b: string;
begin
  path := RepoRoot + CFreshStreamsFile;
  reg := RegisteredPopulation;
  cur := TStringList.Create;
  gold := TStringList.Create;
  curSec := TStringList.Create;
  goldSec := TStringList.Create;
  try
    cur.LineBreak := #10;
    for i := 0 to reg.Count - 1 do
    begin
      if InList(reg[i], CNotSplit) then Continue;
      host := TForm.CreateNew(nil);
      try
        host.SetBounds(0, 0, 640, 480);
        try
          inst := TComponentClass(TClass(reg.Objects[i])).Create(host);
          if inst is TControl then TControl(inst).Parent := host;
          PinClockValues(inst);
          body := MaskStrings(MaskMachineValues(reg[i], FreshStreamBody(host)));
        except
          on E: Exception do body := '<' + E.ClassName + ': ' + E.Message + '>';
        end;
      finally
        host.Free;
      end;
      cur.Add('# ' + reg[i]);
      cur.Add(StringReplace(TrimRight(body), #13#10, #10, [rfReplaceAll]));
    end;
    AssertTrue('anti-vacuity: fewer than 150 classes were streamed', cur.Count >= 300);
    if GetEnvironmentVariable('TY_WRITE_FRESH_STREAMS') = '1' then
    begin
      ForceDirectories(ExtractFilePath(path));
      cur.SaveToFile(path);
      Exit;
    end;
    AssertTrue('fresh-stream fixture missing: ' + path + ' (written with TY_WRITE_FRESH_STREAMS=1)',
      FileExists(path));
    gold.LoadFromFile(path);
    { Sections keyed by class; a section is everything up to the next `# ` header line. }
    cur.Text := cur.Text;   // split the joined bodies into lines
    Sectionize(cur, curSec);
    Sectionize(gold, goldSec);
    diffs := 0;
    firstMsg := '';
    for i := 0 to goldSec.Count - 1 do
    begin
      a := goldSec.ValueFromIndex[i];
      b := curSec.Values[goldSec.Names[i]];
      if a = b then Continue;
      Inc(diffs);
      if firstMsg = '' then
        firstMsg := goldSec.Names[i] + #10'--fixture--'#10 + a + #10'--now--'#10 + b;
    end;
    for i := 0 to curSec.Count - 1 do
      if goldSec.IndexOfName(curSec.Names[i]) < 0 then
      begin
        Inc(diffs);
        if firstMsg = '' then
          firstMsg := curSec.Names[i] + ' is not in the fixture (a newly registered class: '
            + 'add its section with TY_WRITE_FRESH_STREAMS=1)';
      end;
    AssertEquals('what a fresh instance writes into a form file changed for ' + IntToStr(diffs)
      + ' class(es); first: ' + firstMsg, 0, diffs);
  finally
    reg.Free;
    cur.Free;
    gold.Free;
    curSec.Free;
    goldSec.Free;
  end;
end;

initialization
  GSplit := TStringList.Create;
  GSplit.CaseSensitive := False;
  GPending := TStringList.Create;
  GPending.CaseSensitive := False;
  GDemoted := TStringList.Create;
  GDemoted.CaseSensitive := False;

  { CSplit: the final classes already split. }
  AddAll(GSplit, [
    // T2 buttons
    'TTyButton', 'TTyGlyphButton', 'TTyGlyphContainerButton', 'TTySpeedButton',
    'TTyDropDownButton', 'TTyMenuButton', 'TTyColorButton', 'TTyButtonGroup',
    // T3 labels
    'TTyLabel', 'TTyHtmlLabel', 'TTyLinkLabel', 'TTyShadowLabel', 'TTyGlowLabel', 'TTyTag',
    'TTyBadge',
    // T4 edits I
    'TTyEdit', 'TTyNumericEdit', 'TTyCurrencyEdit', 'TTyMaskEdit', 'TTyURLEdit', 'TTyComboEdit',
    'TTyTrackEdit', 'TTyCalcEdit', 'TTyCalcCurrencyEdit',
    // T5 edits II
    'TTyCalculator', 'TTyMemo', 'TTySpinEdit', 'TTyFloatSpinEdit', 'TTyUpDown',
    // T6 choice
    'TTyCheckBox', 'TTyRadioButton', 'TTyToggleSwitch', 'TTySegmented',
    // T7 combo boxes I
    'TTyComboBox', 'TTyMRUComboBox', 'TTyComboBoxEx', 'TTyOfficeComboBox', 'TTyAdvancedComboBox',
    'TTyCheckComboBox',
    // T8 combo boxes II
    'TTyColorBox', 'TTyColorComboBox', 'TTyFontComboBox', 'TTyFontSizeComboBox',
    'TTyFilterComboBox', 'TTyShellComboBox',
    // T9 progress and indicators
    'TTyProgressBar', 'TTyGauge', 'TTyMeter', 'TTyLevelMeter', 'TTyCircularProgress',
    'TTyActivityIndicator', 'TTyActivityBar', 'TTyGearActivityIndicator', 'TTySparkline',
    // T10 dials and sliders
    'TTyRating', 'TTyDial', 'TTyGearDial', 'TTyAnalogClock', 'TTyTrackBar',
    // T12 panels
    'TTyPanel', 'TTyPaintPanel', 'TTyExPanel', 'TTyGridPanel', 'TTyRelativePanel', 'TTyScrollBox',
    'TTyScrollPanel', 'TTyControlBar', 'TTyCoolBar', 'TTyGridCell', 'TTyScrollContent',
    // T13 groups and decoration
    'TTyGroupBox', 'TTyRadioGroup', 'TTyCheckGroup', 'TTyToolGroupPanel', 'TTyCard', 'TTyEmpty',
    'TTyBevel', 'TTyDivider', 'TTySplitter', 'TTySizeBox',
    // T14 tabs
    'TTyPageControl', 'TTyTabSet', 'TTyTabSheet', 'TTyListGroupPanel',
    // T15 list boxes
    'TTyListBox', 'TTyCheckListBox', 'TTyOfficeListBox', 'TTyAdvancedListBox',
    'TTyValueListEditor', 'TTyColorListBox', 'TTyFontListBox',
    // T16 compound pickers
    'TTyTransfer', 'TTyTreeSelect', 'TTyCascader',
    // T17 trees and list views
    'TTyTreeView', 'TTyShellTreeView', 'TTyListView', 'TTyShellListView', 'TTyHeaderControl',
    // T18 grids
    'TTyDrawGrid', 'TTyStringGrid',
    // T20 bars
    'TTyStatusBar', 'TTyToolBar', 'TTyToolBarEx', 'TTyToolButton', 'TTyToolSeparator', 'TTyAlert',
    'TTyPagination', 'TTySteps', 'TTyBreadcrumb', 'TTyScrollBar']);

  { CPending: the classes still to split, by task (plan appendix A). Each task moves its own
    names into CSplit; Task 32 deletes this list. }
  AddAll(GPending, [
    // T21 ribbon
    'TTyRibbon', 'TTyRibbonPage', 'TTyRibbonGroup', 'TTyRibbonAppMenu', 'TTyRibbonQuickAccess',
    'TTyRibbonGallery', 'TTyRibbonBackstage',
    // T22 form chrome
    'TTyTitleBar', 'TTyMenuBar', 'TTyFormSurface',
    // T23 images and shapes
    'TTyCharImage', 'TTyImage', 'TTyPreviewBox', 'TTyImageView', 'TTyShape', 'TTyStarShape',
    'TTyArrow', 'TTyChart',
    // T24 colour pickers and terminal
    'TTyColorGrid', 'TTyLColorPicker', 'TTyHSColorPicker', 'TTyTerminalView',
    // T25 tool windows
    'TTyToolWindowBar', 'TTyToolWindow', 'TTyToolWindowActions',
    // T27 controllers
    'TTyStyleController', 'TTyNativeStyler',
    // T28 icon fonts and images
    'TTyIconFont', 'TTyLucideIconFont', 'TTyVirtualImageList', 'TTyLucideImageList',
    'TTyGlyphImageList', 'TTyImageCollection',
    // T29 hints and notifications
    'TTyHint', 'TTyBalloonHint', 'TTyPopover', 'TTyNotification',
    // T30 dialogs
    'TTyMessage', 'TTyInputDialog', 'TTyPasswordDialog', 'TTyTextDialog', 'TTySelectValueDialog',
    'TTyProgressDialog', 'TTyAboutDialog', 'TTyIconBrowserDialog']);

  { CDemoted: base and intermediate classes that publish nothing beyond their LCL root. }
  AddAll(GDemoted, ['TTyCustomControl', 'TTyGraphicControl', 'TTyComponent', 'TTyGlyphButtonBase', 'TTyCustomTabStrip', 'TTyCustomGrid']);

  RegisterTest(TTyCustomClassesGuardTest);

finalization
  GSplit.Free;
  GPending.Free;
  GDemoted.Free;
end.
