unit test.rowinspector;
{$mode objfpc}{$H+}

{ An object inspector fed by rows, not by RTTI.

  TRowInspectorTest is the proof: the objects it inspects are plain data -- a description (names,
  kinds, an enum's values, a nested object, sets) and values as text -- held by TFarObject, the
  stand-in for a process the inspector cannot reach into. There is no TPersistent in this unit
  and no property grid: TFarInspector is the code a host writes on top of TTyValueListEditor,
  and the edits go in the way the user makes them (a click on the value cell, the keyboard, a
  pick from the dropped list, a click on a triangle), with the verdicts read off the far objects.

  TValueListRowsTest pins the pieces that host stands on, one at a time: row paths, FindRow,
  display positions, SaveExpanded / RestoreExpanded, BeginUpdate / EndUpdate, FilterText and
  OnFilterRow, OnValueChanging on the programmatic routes, OnGetRowColors. }

interface

uses
  Classes, SysUtils, LCLType, Controls, Graphics, Forms, fpcunit, testregistry, TypInfo,
  BGRABitmap, BGRABitmapTypes,
  tyControls.ListBox, tyControls.ValueListEditor, tyControls.ColorBox,
  test.devicescale.support;

type
  TFarKind = (fkText, fkInteger, fkFloat, fkEnum, fkColor, fkSet, fkObject);

  { One property, as a designer process would describe it over a pipe. }
  TFarProp = record
    Path: string;       // 'Caption', 'Font.Size'
    Category: string;   // of a top-level property
    Kind: TFarKind;
    Choices: string;    // an enum's values, a set's elements: comma-separated
    ReadOnly: Boolean;
  end;

  { The object on the far side: values by path, as text. It checks what it is asked to store,
    as a property's setter would, and may refuse. }
  TFarObject = class
  public
    Values: TStringList;   // path=value
    Writes: TStringList;   // every write asked for, 'path=text', refused ones included
    constructor Create(const ACaption: string);
    destructor Destroy; override;
    function Read(const APath: string): string;
    { False = refused, nothing stored. AStored is the value as the object now reads it. }
    function Write(const APath, AText: string; out AStored: string): Boolean;
  end;

  { Drives the inline editor the way the keyboard does. }
  TInspectorEditAccess = class(TTyValueEdit)
  public
    procedure TypeText(const AText: string);
    procedure PressKey(AKey: Word);
  end;

  { The control, with the user's gestures. }
  TInspectorView = class(TTyValueListEditor)
  protected
    function ExecuteFontDialog(AFont: TFont): Boolean; override;
  public
    procedure ClickValue(ARow: TTyValueRow);
    procedure ClickTriangle(ARow: TTyValueRow);
    procedure TypeInto(ARow: TTyValueRow; const AText: string);
    function Dropped: TTyListBox;
    procedure Pick(ARow: TTyValueRow; const AText: string);
    { The keys of the rows on display, top to bottom, comma-separated -- read from the list the
      control lays out, not through DisplayRow. }
    function Shown: string;
  end;

  { The host: an object inspector over far objects, on a plain value list editor. }
  TFarInspector = class
  private
    FView: TInspectorView;
    FObjects: array of TFarObject;
    FOpen: TStringList;   // the paths of the open rows, kept from one object to the next
    function PropAt(const APath: string; out AProp: TFarProp): Boolean;
    function Merged(const APath: string): string;
    function WriteAll(const APath, AText: string; out AStored: string): Boolean;
    procedure AddProp(AParent: TTyValueRow; const AProp: TFarProp);
    procedure Changing(Sender: TObject; ARow: TTyValueRow; var AText: string; var AAllow: Boolean);
    procedure Changed(Sender: TObject; ARow: TTyValueRow);
    procedure Colours(Sender: TObject; ARow: TTyValueRow; AColors: TStrings);
  public
    ChangedPaths: TStringList;
    constructor Create(AView: TInspectorView);
    destructor Destroy; override;
    procedure Select(const AObjects: array of TFarObject);
    function Row(const APath: string): TTyValueRow;   // fails the test when there is none
  end;

  TRowInspectorTest = class(TTestCase)
  private
    FForm: TForm;
    FView: TInspectorView;
    FHost: TFarInspector;
    FOne, FTwo: TFarObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheRowsAreBuiltFromTheDescription;
    procedure TestATypedValueIsWrittenOnTheFarSideAndReadsBackAsItIsHeld;
    procedure TestARefusalFromTheFarSideKeepsTheRow;
    procedure TestAnEnumIsPickedFromItsList;
    procedure TestASetIsEditedThroughItsElements;
    procedure TestANestedObjectIsEditedThroughItsRows;
    procedure TestAColourRowOffersTheColoursTheHostNames;
    procedure TestTheFilterShowsTheMatchesAndOpensTheRowsAboveThem;
    procedure TestAFilteredRowIsEditedAsUsual;
    procedure TestClearingTheFilterPutsTheRowsBackEvenAcrossARebuild;
    procedure TestARebuildForAnotherObjectKeepsWhatIsOpenAndTheCurrentRow;
    procedure TestWithSeveralObjectsAValueTheyDisagreeOnIsAnEmptyCell;
  end;

  TValueListRowsTest = class(TTestCase)
  private
    FForm: TForm;
    FView: TInspectorView;
    FAsked: TStringList;      // OnValueChanging: 'key=text'
    FAllow: Boolean;
    FRewrite: string;
    FChanged: Integer;
    FFontSeen: string;        // CommitFont as OnValueChanging saw it
    FFilterAsked: TStringList;
    procedure Changing(Sender: TObject; ARow: TTyValueRow; var AText: string; var AAllow: Boolean);
    procedure Changed(Sender: TObject; ARow: TTyValueRow);
    procedure MatchByValue(Sender: TObject; ARow: TTyValueRow; const AFilter: string;
      var AMatch: Boolean);
    procedure NeverSecret(Sender: TObject; ARow: TTyValueRow; const AFilter: string;
      var AMatch: Boolean);
    procedure OnlyTeal(Sender: TObject; ARow: TTyValueRow; AColors: TStrings);
    { Appearance(heading) > Font > Style > fsBold ; Items > [0] > Caption ; Plain }
    procedure BuildTree(out AHead, AFont, AStyle, ABold, AItems, AItem, ACaption, APlain: TTyValueRow);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRowPathJoinsTheKeysAsThePropertyGridDoes;
    procedure TestFindRowIsTheWayBackAndIgnoresCase;
    procedure TestDisplayRowAndDisplayIndexFollowWhatIsOnDisplay;
    procedure TestSelectedRowIsTheRowTheSelectionIsOn;
    procedure TestSaveExpandedKeepsAListUpToDateWithTheRows;
    procedure TestRestoreExpandedOpensTheListedRowsAndClosesTheOthers;
    procedure TestBeginUpdatePutsTheRebuildOffUntilTheLastEndUpdate;
    procedure TestRowsRemovedInsideAnUpdateLeaveTheListAtOnce;
    procedure TestTheFilterLeavesHiddenToTheApplication;
    procedure TestTheFilterLooksAtTheDisplayKeyToo;
    procedure TestAHeadingDoesNotMatchByItself;
    procedure TestOnFilterRowDecidesWhatAMatchIs;
    procedure TestARowTheFilterOpenedCanBeClosedAndANewTextOpensItAgain;
    procedure TestRowsAddedWhileFilteringAreFiltered;
    procedure TestABlankFilterIsNoFilter;
    procedure TestTheSelectionStaysOnItsRowThroughAFilter;
    procedure TestWhileFilteringSaveAndRestoreDealInTheStateBeforeIt;
    procedure TestAFilterChangeStartsAtTheTopWithTheCurrentRowInView;
    procedure TestAnEditInProgressIsCommittedWhenTheFilterChanges;
    procedure TestOnValueChangingIsAskedOnTheProgrammaticRoutes;
    procedure TestOnValueChangingSeesTheFontTheDialogPicked;
    procedure TestOnGetRowColorsReplacesTheListAColourRowOffers;
    procedure TestTheEventsArePublishedAndFilterTextIsNot;
    procedure TestAColourRowWithNoValueDrawsNoSwatch;
  end;

implementation

const
  { The class both far objects are of, as it would be described. }
  FarProps: array[0..11] of TFarProp = (
    (Path: 'Caption';    Category: 'Appearance'; Kind: fkText;    Choices: ''; ReadOnly: False),
    (Path: 'Color';      Category: 'Appearance'; Kind: fkColor;   Choices: ''; ReadOnly: False),
    (Path: 'Font';       Category: 'Appearance'; Kind: fkObject;  Choices: ''; ReadOnly: True),
    (Path: 'Font.Name';  Category: '';           Kind: fkText;    Choices: ''; ReadOnly: False),
    (Path: 'Font.Size';  Category: '';           Kind: fkInteger; Choices: ''; ReadOnly: False),
    (Path: 'Font.Style'; Category: '';           Kind: fkSet;     Choices: 'fsBold,fsItalic'; ReadOnly: False),
    (Path: 'Kind';       Category: 'Appearance'; Kind: fkEnum;    Choices: 'bkCustom,bkOK,bkCancel'; ReadOnly: False),
    (Path: 'Anchors';    Category: 'Layout';     Kind: fkSet;     Choices: 'akLeft,akTop,akRight,akBottom'; ReadOnly: False),
    (Path: 'Handle';     Category: 'Layout';     Kind: fkText;    Choices: ''; ReadOnly: True),
    (Path: 'Height';     Category: 'Layout';     Kind: fkInteger; Choices: ''; ReadOnly: False),
    (Path: 'Scale';      Category: 'Layout';     Kind: fkFloat;   Choices: ''; ReadOnly: False),
    (Path: 'Width';      Category: 'Layout';     Kind: fkInteger; Choices: ''; ReadOnly: False));

  AllShown = 'Appearance,Caption,Color,Font,Kind,Layout,Anchors,Handle,Height,Scale,Width';

var
  WidgetSetReady: Boolean = False;

{ The runner never calls Forms.Application.Initialize; a test that needs window handles does. }
procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

function ParentPath(const APath: string): string;
var i: Integer;
begin
  Result := '';
  for i := Length(APath) downto 1 do
    if APath[i] = '.' then Exit(Copy(APath, 1, i - 1));
end;

function LastName(const APath: string): string;
var p: string;
begin
  p := ParentPath(APath);
  if p = '' then Result := APath else Result := Copy(APath, Length(p) + 2, MaxInt);
end;

{ ---- TFarObject ---- }

constructor TFarObject.Create(const ACaption: string);
begin
  inherited Create;
  Values := TStringList.Create;
  Writes := TStringList.Create;
  Values.Values['Caption'] := ACaption;
  Values.Values['Color'] := 'clRed';
  Values.Values['Font'] := '(TFont)';
  Values.Values['Font.Name'] := 'Arial';
  Values.Values['Font.Size'] := '9';
  Values.Values['Font.Style'] := '[fsBold]';
  Values.Values['Kind'] := 'bkCustom';
  Values.Values['Anchors'] := '[akLeft,akTop]';
  Values.Values['Handle'] := '$1234';
  Values.Values['Height'] := '25';
  Values.Values['Scale'] := '1.5';
  Values.Values['Width'] := '75';
end;

destructor TFarObject.Destroy;
begin
  Values.Free;
  Writes.Free;
  inherited Destroy;
end;

function TFarObject.Read(const APath: string): string;
begin
  Result := Values.Values[APath];
end;

function TFarObject.Write(const APath, AText: string; out AStored: string): Boolean;
var n: Integer;
begin
  Writes.Add(APath + '=' + AText);
  AStored := Read(APath);
  if (APath = 'Width') or (APath = 'Height') or (APath = 'Font.Size') then
  begin
    { An integer, held as the object writes it; a size has its range. }
    if not TryStrToInt(AText, n) or (n < 0) or (n > 1000) then Exit(False);
    Values.Values[APath] := IntToStr(n);
  end
  else if APath = 'Handle' then
    Exit(False)
  else
    Values.Values[APath] := AText;
  AStored := Read(APath);
  Result := True;
end;

{ ---- TInspectorEditAccess / TInspectorView ---- }

procedure TInspectorEditAccess.TypeText(const AText: string);
var i: Integer; k: TUTF8Char;
begin
  SelectAll;                     // the first keystroke replaces the seeded value
  for i := 1 to Length(AText) do
  begin
    k := AText[i];               // ASCII only in these guards
    UTF8KeyPress(k);
  end;
end;

procedure TInspectorEditAccess.PressKey(AKey: Word);
var k: Word;
begin
  k := AKey;
  KeyDown(k, []);
end;

function TInspectorView.ExecuteFontDialog(AFont: TFont): Boolean;
begin
  AFont.Name := 'Courier New';   // what the user picks; no modal window
  AFont.Size := 14;
  Result := True;
end;

procedure TInspectorView.ClickValue(ARow: TTyValueRow);
var f, x, y: Integer; r: TRect;
begin
  f := DisplayIndexOf(ARow);
  if f < 0 then raise EAssertionFailedError.Create(ARow.Key + ' is not on display');
  TopIndex := f;                  // scrolled into view, as the user would
  r := ItemRect(f);
  x := ClientWidth - 24;          // the value column
  y := (r.Top + r.Bottom) div 2;
  MouseDown(mbLeft, [], x, y);
  MouseUp(mbLeft, [], x, y);
end;

{ The triangle sits in the indent slot before the key: left padding, then one slot per level. }
procedure TInspectorView.ClickTriangle(ARow: TTyValueRow);
var f, x, y, level: Integer; p: TTyValueRow; r: TRect;
begin
  f := DisplayIndexOf(ARow);
  if f < 0 then raise EAssertionFailedError.Create(ARow.Key + ' is not on display');
  TopIndex := f;
  level := 0;
  p := ARow.Parent;
  while p <> nil do begin Inc(level); p := p.Parent; end;
  r := ItemRect(f);
  { 14 is the editor's indent slot at the classic density these guards run at. }
  x := MulDiv(CurrentStyle.Padding.Left, Font.PixelsPerInch, 96)
    + level * MulDiv(14, Font.PixelsPerInch, 96) + 4;
  y := (r.Top + r.Bottom) div 2;
  MouseDown(mbLeft, [], x, y);
  MouseUp(mbLeft, [], x, y);
end;

procedure TInspectorView.TypeInto(ARow: TTyValueRow; const AText: string);
begin
  ClickValue(ARow);
  if EditingRow < 0 then
    raise EAssertionFailedError.Create('the click did not open ' + ARow.Key);
  TInspectorEditAccess(InlineEditor).TypeText(AText);
  TInspectorEditAccess(InlineEditor).PressKey(VK_RETURN);
end;

function TInspectorView.Dropped: TTyListBox;
begin
  Result := DropList;
end;

procedure TInspectorView.Pick(ARow: TTyValueRow; const AText: string);
var lst: TTyListBox; i: Integer;
begin
  ClickValue(ARow);
  lst := Dropped;
  if lst = nil then raise EAssertionFailedError.Create('no list dropped for ' + ARow.Key);
  i := lst.Items.IndexOf(AText);
  if i < 0 then
  begin
    EndEdit(False);
    raise EAssertionFailedError.Create('''' + AText + ''' is not in the list for ' + ARow.Key
      + ': ' + lst.Items.CommaText);
  end;
  lst.SelectItem(i);
end;

function TInspectorView.Shown: string;
var i: Integer;
begin
  Result := '';
  for i := 0 to Items.Count - 1 do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + Items[i];
  end;
end;

{ ---- TFarInspector: what a host writes ---- }

constructor TFarInspector.Create(AView: TInspectorView);
begin
  inherited Create;
  FView := AView;
  FOpen := TStringList.Create;
  FOpen.Add('@Appearance');   // the categories start open, the properties closed
  FOpen.Add('@Layout');
  ChangedPaths := TStringList.Create;
  FView.OnValueChanging := @Changing;
  FView.OnValueChanged := @Changed;
  FView.OnGetRowColors := @Colours;
end;

destructor TFarInspector.Destroy;
begin
  FOpen.Free;
  ChangedPaths.Free;
  inherited Destroy;
end;

function TFarInspector.PropAt(const APath: string; out AProp: TFarProp): Boolean;
var i: Integer;
begin
  for i := Low(FarProps) to High(FarProps) do
    if SameText(FarProps[i].Path, APath) then
    begin
      AProp := FarProps[i];
      Exit(True);
    end;
  Result := False;
end;

{ What every selected object reads at APath; '' when they do not agree. }
function TFarInspector.Merged(const APath: string): string;
var k: Integer;
begin
  Result := '';
  if Length(FObjects) = 0 then Exit;
  Result := FObjects[0].Read(APath);
  for k := 1 to High(FObjects) do
    if FObjects[k].Read(APath) <> Result then Exit('');
end;

function TFarInspector.WriteAll(const APath, AText: string; out AStored: string): Boolean;
var k: Integer;
begin
  Result := Length(FObjects) > 0;
  AStored := AText;
  for k := 0 to High(FObjects) do
    if not FObjects[k].Write(APath, AText, AStored) then Exit(False);
end;

procedure TFarInspector.AddProp(AParent: TTyValueRow; const AProp: TFarProp);
var
  made, el: TTyValueRow;
  names: TStringList;
  i: Integer;
  cur: string;
begin
  cur := Merged(AProp.Path);
  made := AParent.AddChild(LastName(AProp.Path), cur);
  made.ReadOnly := AProp.ReadOnly;
  case AProp.Kind of
    fkInteger: made.EditorKind := vekInteger;
    fkFloat:   made.EditorKind := vekFloat;
    fkColor:   made.EditorKind := vekColor;
    fkEnum:
      begin
        made.EditorKind := vekEnum;
        made.EnumValues := StringReplace(AProp.Choices, ',', LineEnding, [rfReplaceAll]);
      end;
    fkSet:
      begin
        { Shown whole, edited through its elements: a boolean row each. }
        made.ReadOnly := True;
        names := TStringList.Create;
        try
          names.CommaText := AProp.Choices;
          for i := 0 to names.Count - 1 do
          begin
            el := made.AddChild(names[i], BoolToStr(Pos(names[i], cur) > 0, 'True', 'False'));
            el.EditorKind := vekBoolean;
          end;
        finally
          names.Free;
        end;
      end;
  end;
  { The properties of a nested object: the ones described below this path. }
  for i := Low(FarProps) to High(FarProps) do
    if SameText(ParentPath(FarProps[i].Path), AProp.Path) then AddProp(made, FarProps[i]);
end;

procedure TFarInspector.Select(const AObjects: array of TFarObject);
var
  i: Integer;
  current: string;
  head: TTyValueRow;
begin
  { What is open and which row is current go from the old rows to the new ones by path. }
  FView.SaveExpanded(FOpen);
  current := FView.RowPath(FView.SelectedRow);
  SetLength(FObjects, Length(AObjects));
  for i := 0 to High(AObjects) do FObjects[i] := AObjects[i];
  FView.BeginUpdate;
  try
    FView.Clear;
    if Length(FObjects) > 0 then
      for i := Low(FarProps) to High(FarProps) do
      begin
        if FarProps[i].Category = '' then Continue;   // a nested one: its parent adds it
        head := FView.FindRow('@' + FarProps[i].Category);
        if head = nil then
        begin
          head := FView.AddRow(FarProps[i].Category, '');
          head.Heading := True;
        end;
        AddProp(head, FarProps[i]);
      end;
    FView.RestoreExpanded(FOpen);
  finally
    FView.EndUpdate;
  end;
  FView.ItemIndex := FView.DisplayIndexOf(FView.FindRow(current));
end;

function TFarInspector.Row(const APath: string): TTyValueRow;
begin
  Result := FView.FindRow(APath);
  if Result = nil then raise EAssertionFailedError.Create('no row at ' + APath);
end;

{ The write happens here, before the row takes the text: the far side is asked, and its answer
  decides. One element of a set is written as the whole set. }
procedure TFarInspector.Changing(Sender: TObject; ARow: TTyValueRow; var AText: string;
  var AAllow: Boolean);
var
  path, setText, stored: string;
  owner: TFarProp;
  names: TStringList;
  i: Integer;
  on_: Boolean;
begin
  path := FView.RowPath(ARow);
  if (ARow.Parent <> nil) and PropAt(FView.RowPath(ARow.Parent), owner) and (owner.Kind = fkSet) then
  begin
    setText := '';
    names := TStringList.Create;
    try
      names.CommaText := owner.Choices;
      for i := 0 to names.Count - 1 do
      begin
        if SameText(names[i], ARow.Key) then on_ := SameText(AText, 'True')
        else on_ := SameText(ARow.Parent.Child[i].Value, 'True');
        if not on_ then Continue;
        if setText <> '' then setText := setText + ',';
        setText := setText + names[i];
      end;
    finally
      names.Free;
    end;
    AAllow := WriteAll(owner.Path, '[' + setText + ']', stored);
    Exit;
  end;
  AAllow := WriteAll(path, AText, stored);
  if AAllow then AText := stored;   // as the far side holds it
end;

procedure TFarInspector.Changed(Sender: TObject; ARow: TTyValueRow);
var owner: TFarProp;
begin
  ChangedPaths.Add(FView.RowPath(ARow));
  { The set's own row follows its elements. Written straight into the row: it is the host's
    own news, not an edit to ask about. }
  if (ARow.Parent <> nil) and PropAt(FView.RowPath(ARow.Parent), owner) and (owner.Kind = fkSet) then
  begin
    ARow.Parent.Value := Merged(owner.Path);
    FView.Invalidate;
  end;
end;

procedure TFarInspector.Colours(Sender: TObject; ARow: TTyValueRow; AColors: TStrings);
begin
  { A component's colours are mostly system colours: offer them all, as the property grid does. }
  TyBuildColorPalette(AColors, [cbStandardColors, cbExtendedColors, cbSystemColors,
    cbIncludeNone, cbIncludeDefault]);
end;

{ ================================================================ the proof }

procedure TRowInspectorTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(40, 40, 460, 760);
  FView := TInspectorView.Create(FForm);
  FView.Parent := FForm;
  FView.SetBounds(0, 0, 440, 720);
  FView.Font.PixelsPerInch := 96;
  FView.KeyColumnWidth := 140;
  FOne := TFarObject.Create('One');
  FTwo := TFarObject.Create('Two');
  FTwo.Values.Values['Font.Size'] := '20';
  FHost := TFarInspector.Create(FView);
  { Shown: a click focuses the control, and focusing a control on a hidden form raises. }
  FForm.Show;
  FView.HandleNeeded;
  FHost.Select([FOne]);
end;

procedure TRowInspectorTest.TearDown;
begin
  FForm.Free;   // owns FView
  FHost.Free;
  FOne.Free;
  FTwo.Free;
end;

procedure TRowInspectorTest.TestTheRowsAreBuiltFromTheDescription;
begin
  AssertEquals('two categories, their properties under them, the nested ones closed',
    AllShown, FView.Shown);
  AssertTrue('a category is a heading', FHost.Row('@Appearance').Heading);
  AssertTrue('Color picks a colour', FHost.Row('Color').EditorKind = vekColor);
  AssertTrue('Kind picks from its values', FHost.Row('Kind').EditorKind = vekEnum);
  AssertTrue('Width takes a whole number', FHost.Row('Width').EditorKind = vekInteger);
  AssertTrue('Scale takes a number', FHost.Row('Scale').EditorKind = vekFloat);
  AssertEquals('the nested object''s properties are rows below it', 3, FHost.Row('Font').ChildCount);
  AssertEquals('a set has a row per element', 4, FHost.Row('Anchors').ChildCount);
  AssertEquals('on when the set holds it', 'True', FHost.Row('Anchors.akTop').Value);
  AssertEquals('off when it does not', 'False', FHost.Row('Anchors.akRight').Value);
  AssertEquals('values come from the far object', 'One', FHost.Row('Caption').Value);
  FView.ClickValue(FHost.Row('Handle'));
  AssertEquals('a read-only property opens no editor', -1, FView.EditingRow);
  FView.ClickValue(FHost.Row('Caption'));
  AssertTrue('a writable one does', FView.EditingRow >= 0);
  FView.EndEdit(False);
  AssertEquals('and nothing was written by looking', 0, FOne.Writes.Count);
end;

procedure TRowInspectorTest.TestATypedValueIsWrittenOnTheFarSideAndReadsBackAsItIsHeld;
begin
  FView.TypeInto(FHost.Row('Width'), '007');
  AssertEquals('the far object was asked for what was typed', 'Width=007', FOne.Writes.CommaText);
  AssertEquals('and holds it', '7', FOne.Read('Width'));
  AssertEquals('the row reads what the object holds, not what was typed', '7',
    FHost.Row('Width').Value);
  AssertEquals('one change announced, by path', 'Width', FHost.ChangedPaths.CommaText);
  AssertEquals('the editor is closed', -1, FView.EditingRow);
end;

procedure TRowInspectorTest.TestARefusalFromTheFarSideKeepsTheRow;
begin
  FView.TypeInto(FHost.Row('Width'), '5000');
  AssertEquals('it was asked', 'Width=5000', FOne.Writes.CommaText);
  AssertEquals('and refused: the object is as it was', '75', FOne.Read('Width'));
  AssertEquals('so is the row', '75', FHost.Row('Width').Value);
  AssertEquals('nothing is announced', 0, FHost.ChangedPaths.Count);
  AssertEquals('the editor is closed', -1, FView.EditingRow);
  FView.TypeInto(FHost.Row('Width'), '500');
  AssertEquals('the same route with a value it takes', '500', FOne.Read('Width'));
  AssertEquals('(row)', '500', FHost.Row('Width').Value);
  AssertEquals('(announced)', 'Width', FHost.ChangedPaths.CommaText);
end;

procedure TRowInspectorTest.TestAnEnumIsPickedFromItsList;
begin
  FView.ClickValue(FHost.Row('Kind'));
  AssertNotNull('the click dropped a list', FView.Dropped);
  AssertEquals('of the described values', 'bkCustom,bkOK,bkCancel', FView.Dropped.Items.CommaText);
  FView.EndEdit(False);
  FView.Pick(FHost.Row('Kind'), 'bkCancel');
  AssertEquals('written', 'bkCancel', FOne.Read('Kind'));
  AssertEquals('shown', 'bkCancel', FHost.Row('Kind').Value);
end;

procedure TRowInspectorTest.TestASetIsEditedThroughItsElements;
begin
  FView.ClickTriangle(FHost.Row('Anchors'));
  AssertTrue('its elements are on display', FView.DisplayIndexOf(FHost.Row('Anchors.akRight')) >= 0);
  FView.Pick(FHost.Row('Anchors.akRight'), 'True');
  AssertEquals('the far object got the whole set', '[akLeft,akTop,akRight]', FOne.Read('Anchors'));
  AssertEquals('the set''s own row follows', '[akLeft,akTop,akRight]', FHost.Row('Anchors').Value);
  FView.Pick(FHost.Row('Anchors.akLeft'), 'False');
  AssertEquals('and an element taken out', '[akTop,akRight]', FOne.Read('Anchors'));
  AssertEquals('(row)', '[akTop,akRight]', FHost.Row('Anchors').Value);
  FView.ClickValue(FHost.Row('Anchors'));
  AssertEquals('the set row itself is not typed into', -1, FView.EditingRow);
end;

procedure TRowInspectorTest.TestANestedObjectIsEditedThroughItsRows;
begin
  AssertEquals('closed: its rows have no place', -1, FView.DisplayIndexOf(FHost.Row('Font.Size')));
  FView.ClickTriangle(FHost.Row('Font'));
  AssertEquals('opened',
    'Appearance,Caption,Color,Font,Name,Size,Style,Kind,Layout,Anchors,Handle,Height,Scale,Width',
    FView.Shown);
  FView.TypeInto(FHost.Row('Font.Size'), '12');
  AssertEquals('the far object was asked by the row''s path', 'Font.Size=12', FOne.Writes.CommaText);
  AssertEquals('and holds it', '12', FOne.Read('Font.Size'));
  FView.ClickTriangle(FHost.Row('Font.Style'));
  FView.Pick(FHost.Row('Font.Style.fsItalic'), 'True');
  AssertEquals('a set two levels down', '[fsBold,fsItalic]', FOne.Read('Font.Style'));
end;

procedure TRowInspectorTest.TestAColourRowOffersTheColoursTheHostNames;
var lst: TTyListBox; i, idx: Integer;
begin
  FView.ClickValue(FHost.Row('Color'));
  lst := FView.Dropped;
  AssertNotNull('the click dropped the swatches', lst);
  idx := -1;
  for i := 0 to lst.Items.Count - 2 do      // the last row is "more…"
    if TyColorOfItem(lst.Items, i) = clBtnFace then idx := i;
  AssertTrue('a system colour is offered, because the host listed it', idx >= 0);
  lst.SelectItem(idx);
  AssertEquals('written by its name', 'clBtnFace', FOne.Read('Color'));
  AssertEquals('shown', 'clBtnFace', FHost.Row('Color').Value);
end;

procedure TRowInspectorTest.TestTheFilterShowsTheMatchesAndOpensTheRowsAboveThem;
begin
  AssertFalse('Font starts closed', FHost.Row('Font').Expanded);
  FView.FilterText := 'SIZE';
  AssertEquals('the match, the rows above it opened, nothing else', 'Appearance,Font,Size',
    FView.Shown);
  FView.FilterText := 'ak';
  AssertEquals('a set''s elements: the set opens for them',
    'Layout,Anchors,akLeft,akTop,akRight,akBottom', FView.Shown);
  FView.FilterText := '';
  AssertEquals('cleared: every row again, Font closed as before the search', AllShown, FView.Shown);
  FView.FilterText := 'font';
  AssertEquals('Font matches by itself: nothing below it does, it is not opened',
    'Appearance,Font', FView.Shown);
  FView.ClickTriangle(FHost.Row('Font'));
  AssertEquals('opened by hand, a matching row keeps the rows below it',
    'Appearance,Font,Name,Size,Style', FView.Shown);
  FView.FilterText := 'nothing like it';
  AssertEquals('no match, no row', '', FView.Shown);
  FView.FilterText := '';
  AssertEquals('cleared: every row again, opened and closed as before the search', AllShown,
    FView.Shown);
end;

procedure TRowInspectorTest.TestAFilteredRowIsEditedAsUsual;
begin
  FView.FilterText := 'wid';
  AssertEquals('the one match under its heading', 'Layout,Width', FView.Shown);
  FView.TypeInto(FHost.Row('Width'), '80');
  AssertEquals('written', '80', FOne.Read('Width'));
  FView.ItemIndex := FView.DisplayIndexOf(FHost.Row('Width'));
  FView.FilterText := '';
  AssertSame('the current row stays current when the filter goes', FHost.Row('Width'),
    FView.SelectedRow);
end;

procedure TRowInspectorTest.TestClearingTheFilterPutsTheRowsBackEvenAcrossARebuild;
begin
  FView.ClickTriangle(FHost.Row('Font'));        // opened by hand
  FView.ClickTriangle(FHost.Row('@Layout'));     // closed by hand
  AssertEquals('before the search', 'Appearance,Caption,Color,Font,Name,Size,Style,Kind,Layout',
    FView.Shown);
  FView.FilterText := 'width';
  AssertEquals('Layout is opened for the match', 'Layout,Width', FView.Shown);
  FHost.Select([FTwo]);                          // the rows are rebuilt while it filters
  AssertEquals('the new rows are filtered too', 'Layout,Width', FView.Shown);
  FView.FilterText := '';
  AssertEquals('cleared: as before the search, on the new rows',
    'Appearance,Caption,Color,Font,Name,Size,Style,Kind,Layout', FView.Shown);
  AssertEquals('(they are the second object''s)', 'Two', FHost.Row('Caption').Value);
end;

procedure TRowInspectorTest.TestARebuildForAnotherObjectKeepsWhatIsOpenAndTheCurrentRow;
var before: TTyValueRow;
begin
  FView.ClickTriangle(FHost.Row('Font'));
  before := FHost.Row('Font.Size');
  FView.ItemIndex := FView.DisplayIndexOf(before);
  AssertEquals('the first object''s', '9', before.Value);
  FHost.Select([FTwo]);
  AssertTrue('Font is still open', FHost.Row('Font').Expanded);
  AssertFalse('Anchors, never opened, is still closed', FHost.Row('Anchors').Expanded);
  AssertEquals('on display as it was',
    'Appearance,Caption,Color,Font,Name,Size,Style,Kind,Layout,Anchors,Handle,Height,Scale,Width',
    FView.Shown);
  AssertNotNull('a row is current', FView.SelectedRow);
  AssertEquals('the one at the same path', 'Font.Size', FView.RowPath(FView.SelectedRow));
  AssertEquals('showing the second object', '20', FView.SelectedRow.Value);
  FView.TypeInto(FHost.Row('Font.Size'), '21');
  AssertEquals('an edit goes to the object now selected', '21', FTwo.Read('Font.Size'));
  AssertEquals('and not to the one before', '9', FOne.Read('Font.Size'));
end;

procedure TRowInspectorTest.TestWithSeveralObjectsAValueTheyDisagreeOnIsAnEmptyCell;
begin
  FHost.Select([FOne, FTwo]);
  AssertEquals('captions differ: an empty cell', '', FHost.Row('Caption').Value);
  AssertEquals('widths agree: the value', '75', FHost.Row('Width').Value);
  FView.TypeInto(FHost.Row('Caption'), 'Both');
  AssertEquals('written into the first', 'Both', FOne.Read('Caption'));
  AssertEquals('and the second', 'Both', FTwo.Read('Caption'));
  AssertEquals('the cell shows it', 'Both', FHost.Row('Caption').Value);
end;

{ ================================================================ the pieces }

procedure TValueListRowsTest.SetUp;
begin
  NeedWidgetSet;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(40, 40, 460, 500);
  FView := TInspectorView.Create(FForm);
  FView.Parent := FForm;
  FView.SetBounds(0, 0, 440, 460);
  FView.Font.PixelsPerInch := 96;
  FAsked := TStringList.Create;
  FFilterAsked := TStringList.Create;
  FAllow := True;
  FRewrite := '';
  FChanged := 0;
  FFontSeen := '';
  FForm.Show;
  FView.HandleNeeded;
end;

procedure TValueListRowsTest.TearDown;
begin
  FForm.Free;
  FAsked.Free;
  FFilterAsked.Free;
end;

procedure TValueListRowsTest.Changing(Sender: TObject; ARow: TTyValueRow; var AText: string;
  var AAllow: Boolean);
begin
  FAsked.Add(ARow.Key + '=' + AText);
  if FView.CommitFont <> nil then
    FFontSeen := Format('%s, %d', [FView.CommitFont.Name, FView.CommitFont.Size]);
  if FRewrite <> '' then AText := FRewrite;
  AAllow := FAllow;
end;

procedure TValueListRowsTest.Changed(Sender: TObject; ARow: TTyValueRow);
begin
  Inc(FChanged);
end;

procedure TValueListRowsTest.MatchByValue(Sender: TObject; ARow: TTyValueRow;
  const AFilter: string; var AMatch: Boolean);
begin
  FFilterAsked.Add(ARow.Key + ':' + AFilter + ':' + BoolToStr(AMatch, 'T', 'F'));
  if Pos(AFilter, LowerCase(ARow.Value)) > 0 then AMatch := True;
end;

procedure TValueListRowsTest.NeverSecret(Sender: TObject; ARow: TTyValueRow;
  const AFilter: string; var AMatch: Boolean);
begin
  if ARow.Key = 'Secret' then AMatch := False;
end;

procedure TValueListRowsTest.OnlyTeal(Sender: TObject; ARow: TTyValueRow; AColors: TStrings);
begin
  FAsked.Add(ARow.Key + ' had ' + IntToStr(AColors.Count));
  AColors.Clear;
  TyAddColorItem(AColors, 'Teal', clTeal);
end;

procedure TValueListRowsTest.BuildTree(out AHead, AFont, AStyle, ABold, AItems, AItem, ACaption,
  APlain: TTyValueRow);
begin
  AHead := FView.AddRow('Appearance', '');
  AHead.Heading := True;
  AFont := AHead.AddChild('Font', '');
  AStyle := AFont.AddChild('Style', '');
  ABold := AStyle.AddChild('fsBold', 'True');
  AItems := FView.AddRow('Items', '');
  AItem := AItems.AddChild('[0]', '');
  ACaption := AItem.AddChild('Caption', 'first');
  APlain := FView.AddRow('Plain', 'x');
  FView.UpdateRows;
end;

procedure TValueListRowsTest.TestRowPathJoinsTheKeysAsThePropertyGridDoes;
var head, font, style, bold, items, item, caption, plain: TTyValueRow;
begin
  BuildTree(head, font, style, bold, items, item, caption, plain);
  AssertEquals('a root row: its key', 'Plain', FView.RowPath(plain));
  AssertEquals('a heading: @ and its key', '@Appearance', FView.RowPath(head));
  AssertEquals('a heading is no part of the path of the rows under it', 'Font', FView.RowPath(font));
  AssertEquals('keys joined by dots', 'Font.Style.fsBold', FView.RowPath(bold));
  AssertEquals('a key in brackets joins without a dot', 'Items[0]', FView.RowPath(item));
  AssertEquals('and the rows below it go on with dots', 'Items[0].Caption', FView.RowPath(caption));
  AssertEquals('no row, no path', '', FView.RowPath(nil));
end;

procedure TValueListRowsTest.TestFindRowIsTheWayBackAndIgnoresCase;
var head, font, style, bold, items, item, caption, plain: TTyValueRow;
begin
  BuildTree(head, font, style, bold, items, item, caption, plain);
  AssertSame('a root row', plain, FView.FindRow('Plain'));
  AssertSame('a nested row', bold, FView.FindRow('Font.Style.fsBold'));
  AssertSame('ignoring case', bold, FView.FindRow('font.STYLE.FSBOLD'));
  AssertSame('an item', item, FView.FindRow('Items[0]'));
  AssertSame('below an item', caption, FView.FindRow('Items[0].Caption'));
  AssertSame('a heading', head, FView.FindRow('@appearance'));
  AssertNull('the heading is not part of a path', FView.FindRow('Appearance.Font'));
  AssertNull('nor found without its @', FView.FindRow('Appearance'));
  AssertNull('no such row', FView.FindRow('Font.Size'));
  AssertNull('the empty path names no row', FView.FindRow(''));
  FView.SetExpanded(font, False);
  AssertSame('a row inside a closed one is still found', bold, FView.FindRow('Font.Style.fsBold'));
end;

procedure TValueListRowsTest.TestDisplayRowAndDisplayIndexFollowWhatIsOnDisplay;
var head, font, style, bold, items, item, caption, plain: TTyValueRow;
begin
  BuildTree(head, font, style, bold, items, item, caption, plain);
  AssertEquals('everything open', 'Appearance,Font,Style,fsBold,Items,[0],Caption,Plain', FView.Shown);
  AssertSame('position 0', head, FView.DisplayRow(0));
  AssertSame('position 3', bold, FView.DisplayRow(3));
  AssertSame('the last', plain, FView.DisplayRow(7));
  AssertNull('past the end', FView.DisplayRow(8));
  AssertNull('before the start', FView.DisplayRow(-1));
  AssertEquals('and back', 3, FView.DisplayIndexOf(bold));
  AssertEquals('(the last)', 7, FView.DisplayIndexOf(plain));
  AssertEquals('nil has no place', -1, FView.DisplayIndexOf(nil));
  FView.SetExpanded(font, False);
  AssertEquals('inside a closed row: no place', -1, FView.DisplayIndexOf(bold));
  AssertSame('the rows after it move up', items, FView.DisplayRow(2));
  AssertEquals('(index)', 5, FView.DisplayIndexOf(plain));
  plain.Hidden := True;
  FView.UpdateRows;
  AssertEquals('a hidden row: no place', -1, FView.DisplayIndexOf(plain));
end;

procedure TValueListRowsTest.TestSelectedRowIsTheRowTheSelectionIsOn;
var head, font, style, bold, items, item, caption, plain: TTyValueRow;
begin
  BuildTree(head, font, style, bold, items, item, caption, plain);
  AssertNull('nothing selected', FView.SelectedRow);
  FView.ItemIndex := 3;
  AssertSame('the row at that position', bold, FView.SelectedRow);
  FView.ItemIndex := 7;
  AssertSame('and at another', plain, FView.SelectedRow);
end;

procedure TValueListRowsTest.TestSaveExpandedKeepsAListUpToDateWithTheRows;
var
  head, font, style, bold, items, item, caption, plain: TTyValueRow;
  open: TStringList;
begin
  BuildTree(head, font, style, bold, items, item, caption, plain);
  open := TStringList.Create;
  try
    open.Add('Ghost.Row');      // a path these rows do not have
    open.Add('Items');          // listed, and about to be closed
    FView.SetExpanded(items, False);
    FView.SetExpanded(style, False);
    FView.SaveExpanded(open);
    AssertTrue('an open row that has rows below it is put on the list', open.IndexOf('Font') >= 0);
    AssertTrue('a heading by its own path', open.IndexOf('@Appearance') >= 0);
    AssertTrue('an item by its', open.IndexOf('Items[0]') >= 0);
    AssertEquals('a closed row that was listed comes off', -1, open.IndexOf('Items'));
    AssertEquals('a closed row is not put on', -1, open.IndexOf('Font.Style'));
    AssertTrue('a path no row has stays, for the rows that will', open.IndexOf('Ghost.Row') >= 0);
    AssertEquals('and that is all', 4, open.Count);
    FView.SetExpanded(style, True);
    FView.SaveExpanded(open);
    AssertTrue('opened since: added', open.IndexOf('Font.Style') >= 0);
    AssertEquals('a row with nothing below it is never listed', -1, open.IndexOf('Plain'));
    AssertEquals('(nor a leaf)', -1, open.IndexOf('Font.Style.fsBold'));
  finally
    open.Free;
  end;
end;

procedure TValueListRowsTest.TestRestoreExpandedOpensTheListedRowsAndClosesTheOthers;
var
  head, font, style, bold, items, item, caption, plain: TTyValueRow;
  open: TStringList;
begin
  BuildTree(head, font, style, bold, items, item, caption, plain);
  FView.SetExpanded(head, False);
  open := TStringList.Create;
  try
    open.Add('@Appearance');
    open.Add('font');           // case ignored, as FindRow does
    open.Add('Items');
    FView.RestoreExpanded(open);
    AssertTrue('listed: opened', head.Expanded);
    AssertTrue('listed in another case: open', font.Expanded);
    AssertFalse('not listed: closed', style.Expanded);
    AssertTrue('listed: stays open', items.Expanded);
    AssertFalse('not listed: closed', item.Expanded);
    AssertEquals('and the display follows at once', 'Appearance,Font,Style,Items,[0],Plain',
      FView.Shown);
  finally
    open.Free;
  end;
end;

procedure TValueListRowsTest.TestBeginUpdatePutsTheRebuildOffUntilTheLastEndUpdate;
var a: TTyValueRow;
begin
  FView.AddRow('Before', '');
  AssertEquals('outside an update every AddRow shows', 1, FView.DisplayRowCount);
  FView.BeginUpdate;
  a := FView.AddRow('A', '');
  a.AddChild('A1', '');
  FView.AddRow('B', '');
  AssertEquals('inside: the rows are there', 3, FView.RowCount);
  AssertEquals('but the display has not been rebuilt', 1, FView.DisplayRowCount);
  FView.BeginUpdate;
  FView.AddRow('C', '');
  FView.EndUpdate;
  AssertEquals('an inner EndUpdate does not rebuild either', 1, FView.DisplayRowCount);
  FView.UpdateRows;
  AssertEquals('nor does UpdateRows', 1, FView.DisplayRowCount);
  FView.SetExpanded(a, False);
  AssertEquals('nor SetExpanded', 1, FView.DisplayRowCount);
  FView.EndUpdate;
  AssertEquals('the last EndUpdate does, once, with everything', 'Before,A,B,C', FView.Shown);
  FView.EndUpdate;   // one too many: ignored
  FView.AddRow('D', '');
  AssertEquals('and the editor is not left holding updates back', 5, FView.DisplayRowCount);
  FView.BeginUpdate;
  FView.AddRow('E', '');
  AssertEquals('nor is the next BeginUpdate cancelled by the stray EndUpdate', 5,
    FView.DisplayRowCount);
  FView.EndUpdate;
  AssertEquals('(shown at its end)', 6, FView.DisplayRowCount);
end;

procedure TValueListRowsTest.TestRowsRemovedInsideAnUpdateLeaveTheListAtOnce;
begin
  FView.AddRow('A', '');
  FView.AddRow('B', '');
  FView.AddRow('C', '');
  FView.ItemIndex := 2;
  FView.BeginUpdate;
  FView.DeleteRow(0);
  AssertEquals('a deleted row is off the display at once', 'B,C', FView.Shown);
  AssertEquals('(the first position is the next row)', 'B', FView.DisplayRow(0).Key);
  AssertEquals('(the selection moved up with its row)', 'C', FView.SelectedRow.Key);
  FView.Clear;
  AssertEquals('and so are cleared rows: nothing on display names a row that is gone', 0,
    FView.DisplayRowCount);
  AssertNull('(no row at position 0)', FView.DisplayRow(0));
  AssertEquals('the list the control lays out is empty too', '', FView.Shown);
  AssertEquals('and nothing is selected', -1, FView.ItemIndex);
  FView.AddRow('New', '');
  AssertEquals('adding is still put off', 0, FView.DisplayRowCount);
  FView.EndUpdate;
  AssertEquals('until the end', 'New', FView.Shown);
end;

procedure TValueListRowsTest.TestTheFilterLeavesHiddenToTheApplication;
var grp, hid, other, far: TTyValueRow;
begin
  grp := FView.AddRow('Group', '');
  hid := grp.AddChild('Width', '1');     // matches, but the application has hidden it
  hid.Hidden := True;
  other := FView.AddRow('Widget', '2');
  far := FView.AddRow('Far', '3');
  FView.UpdateRows;
  AssertEquals('before', 'Group,Widget,Far', FView.Shown);
  FView.FilterText := 'wid';
  AssertEquals('a hidden row is no match for the rows above it, and stays out', 'Widget',
    FView.Shown);
  AssertFalse('a row the filter leaves out is not marked Hidden: that is the application''s',
    far.Hidden);
  AssertFalse('(nor the group)', grp.Hidden);
  AssertTrue('and what the application hid stays hidden', hid.Hidden);
  FView.FilterText := '';
  AssertEquals('cleared: the application''s hidden row is still out', 'Group,Widget,Far', FView.Shown);
  AssertTrue('(still hidden)', hid.Hidden);
  AssertFalse('(still not)', other.Hidden);
end;

procedure TValueListRowsTest.TestTheFilterLooksAtTheDisplayKeyToo;
var w: TTyValueRow;
begin
  w := FView.AddRow('Width', '1');
  w.DisplayKey := 'Breite';
  FView.AddRow('Height', '2');
  FView.FilterText := 'brei';
  AssertEquals('by what the row shows', 'Breite', FView.Shown);
  FView.FilterText := 'WIDT';
  AssertEquals('and by its key, in any case', 'Breite', FView.Shown);
  FView.FilterText := 'eig';
  AssertEquals('the other row', 'Height', FView.Shown);
end;

procedure TValueListRowsTest.TestAHeadingDoesNotMatchByItself;
var head: TTyValueRow;
begin
  head := FView.AddRow('Layout', '');
  head.Heading := True;
  head.AddChild('Width', '1');
  head.AddChild('Lay', '2');
  FView.UpdateRows;
  FView.FilterText := 'layout';
  AssertEquals('the heading''s own text is not searched', '', FView.Shown);
  FView.FilterText := 'lay';
  AssertEquals('it is shown for a row under it', 'Layout,Lay', FView.Shown);
end;

procedure TValueListRowsTest.TestOnFilterRowDecidesWhatAMatchIs;
begin
  FView.AddRow('Color', 'clRed');
  FView.AddRow('Reddish', 'x');
  FView.AddRow('Secret', 'red');
  FView.FilterText := ' Red ';
  AssertEquals('by key alone', 'Reddish', FView.Shown);
  FView.OnFilterRow := @MatchByValue;
  FView.UpdateRows;
  AssertEquals('the handler matches values too', 'Color,Reddish,Secret', FView.Shown);
  AssertTrue('it is handed the text trimmed and in lower case, and the editor''s own answer',
    FFilterAsked.IndexOf('Color:red:F') >= 0);
  AssertTrue('(a key match arrives True)', FFilterAsked.IndexOf('Reddish:red:T') >= 0);
  FView.OnFilterRow := @NeverSecret;
  FView.FilterText := 'e';
  AssertEquals('and it can refuse a row the editor would show', 'Reddish', FView.Shown);
end;

procedure TValueListRowsTest.TestARowTheFilterOpenedCanBeClosedAndANewTextOpensItAgain;
var grp: TTyValueRow;
begin
  grp := FView.AddRow('Group', '');
  grp.AddChild('Width', '1');
  grp.AddChild('Wide', '2');
  FView.SetExpanded(grp, False);
  FView.FilterText := 'wi';
  AssertEquals('opened for its matches', 'Group,Width,Wide', FView.Shown);
  FView.SetExpanded(grp, False);
  AssertEquals('the user closes it', 'Group', FView.Shown);
  FView.UpdateRows;
  AssertEquals('and it stays closed while the text is the same', 'Group', FView.Shown);
  FView.FilterText := 'widt';
  AssertEquals('typing on opens it for the new text', 'Group,Width', FView.Shown);
  FView.FilterText := '';
  AssertFalse('cleared: closed, as before the filter', grp.Expanded);
end;

procedure TValueListRowsTest.TestRowsAddedWhileFilteringAreFiltered;
var grp: TTyValueRow;
begin
  FView.FilterText := 'x';
  FView.AddRow('Axis', '1');
  FView.AddRow('Bee', '2');
  AssertEquals('only the new row that matches', 'Axis', FView.Shown);
  grp := FView.AddRow('Group', '');
  grp.Expanded := False;
  grp.AddChild('Box', '3');
  FView.UpdateRows;
  AssertEquals('a new closed row opens for a match below it', 'Axis,Group,Box', FView.Shown);
  FView.FilterText := '';
  AssertFalse('and is closed again, as it was made, when the filter goes', grp.Expanded);
  AssertEquals('everything', 'Axis,Bee,Group', FView.Shown);
end;

procedure TValueListRowsTest.TestABlankFilterIsNoFilter;
begin
  FView.AddRow('A', '1');
  FView.AddRow('B', '2');
  FView.FilterText := '   ';
  AssertEquals('spaces alone filter nothing', 'A,B', FView.Shown);
  FView.FilterText := ' b ';
  AssertEquals('and are trimmed off a real text', 'B', FView.Shown);
end;

procedure TValueListRowsTest.TestTheSelectionStaysOnItsRowThroughAFilter;
var a, b: TTyValueRow;
begin
  a := FView.AddRow('Alpha', '1');
  b := FView.AddRow('Beta', '2');
  FView.ItemIndex := 1;
  FView.FilterText := 'bet';
  AssertSame('still on Beta, at its new position', b, FView.SelectedRow);
  AssertEquals('(position)', 0, FView.ItemIndex);
  FView.FilterText := 'alp';
  AssertEquals('its row left out: nothing is selected', -1, FView.ItemIndex);
  AssertSame('(Alpha is what shows)', a, FView.DisplayRow(0));
end;

procedure TValueListRowsTest.TestWhileFilteringSaveAndRestoreDealInTheStateBeforeIt;
var
  grp, other: TTyValueRow;
  open: TStringList;
begin
  grp := FView.AddRow('Group', '');
  grp.AddChild('Width', '1');
  other := FView.AddRow('Other', '');
  other.AddChild('Depth', '2');
  FView.SetExpanded(grp, False);
  open := TStringList.Create;
  try
    FView.FilterText := 'wid';
    AssertTrue('the filter opened Group', grp.Expanded);
    FView.SaveExpanded(open);
    AssertEquals('saved while filtering: what was open before it, not what it opened', 'Other',
      open.CommaText);
    open.Clear;
    FView.RestoreExpanded(open);   // nothing is to be open
    AssertEquals('restored closed while filtering: the filter opens the row for its match again',
      'Group,Width', FView.Shown);
    open.Add('Group');
    FView.RestoreExpanded(open);
    AssertEquals('restored open: the same', 'Group,Width', FView.Shown);
    FView.FilterText := '';
    AssertTrue('and what was restored is what the rows go back to: Group open', grp.Expanded);
    AssertFalse('Other closed', other.Expanded);
  finally
    open.Free;
  end;
end;

procedure TValueListRowsTest.TestAnEditInProgressIsCommittedWhenTheFilterChanges;
var w: TTyValueRow;
begin
  w := FView.AddRow('Width', '1');
  FView.AddRow('Height', '2');
  FView.ClickValue(w);
  AssertEquals('the cell is open', 0, FView.EditingRow);
  TInspectorEditAccess(FView.InlineEditor).TypeText('5');
  FView.FilterText := 'hei';
  AssertEquals('the editor is closed', -1, FView.EditingRow);
  AssertEquals('what was typed went into the row it was typed on', '5', w.Value);
  AssertEquals('and the filter shows its match', 'Height', FView.Shown);
end;

procedure TValueListRowsTest.TestAFilterChangeStartsAtTheTopWithTheCurrentRowInView;
var
  i: Integer;
  r: TRect;
begin
  FView.BeginUpdate;
  for i := 0 to 59 do FView.AddRow(Format('Row%.2d', [i]), '');
  FView.EndUpdate;
  AssertTrue('more rows than the control shows', FView.VisibleRowCount < 40);
  FView.TopIndex := 20;
  AssertEquals('scrolled down', 20, FView.TopIndex);
  FView.FilterText := '   ';
  AssertEquals('one blank text for another is no change: the list stays where it is', 20,
    FView.TopIndex);
  FView.FilterText := 'row';
  AssertEquals('every row still matches', 60, FView.DisplayRowCount);
  AssertEquals('a new search starts at the top', 0, FView.TopIndex);
  FView.ItemIndex := 50;
  FView.TopIndex := 0;
  FView.FilterText := 'ro';
  AssertEquals('the current row is still the current row', 50, FView.ItemIndex);
  r := FView.ItemRect(50);
  AssertTrue('and it is in view after the change', (r.Top >= 0) and (r.Bottom <= FView.ClientHeight));
  AssertTrue('(scrolled no further than it takes)', FView.TopIndex < 50);
end;

procedure TValueListRowsTest.TestOnValueChangingIsAskedOnTheProgrammaticRoutes;
var r: TTyValueRow;
begin
  r := FView.AddRow('Width', '10');
  FView.OnValueChanged := @Changed;
  FView.SetRowValue(r, '11');
  AssertEquals('no handler: the value goes in', '11', r.Value);
  AssertEquals('(announced)', 1, FChanged);
  FView.OnValueChanging := @Changing;
  FAllow := False;
  FView.SetRowValue(r, '12');
  AssertEquals('SetRowValue asks', 'Width=12', FAsked.CommaText);
  AssertEquals('refused: the row keeps its value', '11', r.Value);
  AssertEquals('and nothing is announced', 1, FChanged);
  FView.Values['Width'] := '13';
  AssertEquals('Values[] asks', 'Width=13', FAsked[FAsked.Count - 1]);
  AssertEquals('refused', '11', r.Value);
  FView.ValueFromIndex[0] := '14';
  AssertEquals('ValueFromIndex[] asks', 'Width=14', FAsked[FAsked.Count - 1]);
  AssertEquals('refused', '11', r.Value);
  FAllow := True;
  FRewrite := '15';
  FView.SetRowValue(r, '015');
  AssertEquals('allowed, and the text the handler left is what the row holds', '15', r.Value);
  AssertEquals('announced once more', 2, FChanged);
end;

procedure TValueListRowsTest.TestOnValueChangingSeesTheFontTheDialogPicked;
var font, nm: TTyValueRow;
begin
  font := FView.AddRow('Font', 'Arial, 10');
  font.EditorKind := vekFont;
  nm := font.AddChild('Name', 'Arial');
  font.AddChild('Size', '10').EditorKind := vekInteger;
  FView.UpdateRows;
  FView.OnValueChanging := @Changing;
  AssertTrue('no font outside a commit', FView.CommitFont = nil);
  FView.InvokeRowDialog(0);
  AssertEquals('asked once', 1, FAsked.Count);
  AssertEquals('on the font row, with the summary', 'Font=Courier New, 14', FAsked[0]);
  AssertEquals('and the handler could read the font itself', 'Courier New, 14', FFontSeen);
  AssertEquals('allowed: the rows below follow', 'Courier New', nm.Value);
  AssertTrue('and it is gone again afterwards', FView.CommitFont = nil);
end;

procedure TValueListRowsTest.TestOnGetRowColorsReplacesTheListAColourRowOffers;
var lst: TTyListBox; n: Integer;
begin
  FView.AddRow('Color', 'clRed').EditorKind := vekColor;
  FView.ClickValue(FView.Row(0));
  lst := FView.Dropped;
  AssertNotNull('dropped', lst);
  n := lst.Items.Count;
  AssertTrue('the editor''s own colours and "more…"', n > 3);
  FView.EndEdit(False);
  FView.OnGetRowColors := @OnlyTeal;
  FView.ClickValue(FView.Row(0));
  lst := FView.Dropped;
  AssertEquals('the handler was asked once', 1, FAsked.Count);
  AssertEquals('and handed the row and the editor''s own list', 'Color had ' + IntToStr(n - 1),
    FAsked[0]);
  AssertEquals('what it left is what is offered, then the colour the cell holds (it is always '
    + 'on its own list), then "more…"', 3, lst.Items.Count);
  AssertTrue('(teal)', TyColorOfItem(lst.Items, 0) = clTeal);
  AssertTrue('(the cell''s red)', TyColorOfItem(lst.Items, 1) = clRed);
  lst.SelectItem(0);
  AssertEquals('picked', 'clTeal', FView.Row(0).Value);
end;

procedure TValueListRowsTest.TestTheEventsArePublishedAndFilterTextIsNot;
begin
  AssertTrue('OnValueChanging', IsPublishedProp(TTyValueListEditor, 'OnValueChanging'));
  AssertTrue('OnFilterRow', IsPublishedProp(TTyValueListEditor, 'OnFilterRow'));
  AssertTrue('OnGetRowColors', IsPublishedProp(TTyValueListEditor, 'OnGetRowColors'));
  AssertFalse('FilterText is a search box''s text, not a setting',
    IsPublishedProp(TTyValueListEditor, 'FilterText'));
end;

{ A colour row with no value is what a host shows when the selected objects disagree. It used to
  paint a black swatch -- StringToColorDef's fallback -- which reads as "the colour is black". }
procedure TValueListRowsTest.TestAColourRowWithNoValueDrawsNoSwatch;
var
  r: TTyValueRow;
  asText, asEmpty, asRed: TBGRABitmap;
  x, y, differ, red: Integer;
  a, b: TBGRAPixel;
begin
  r := FView.AddRow('Color', '');
  asText := TyPaintOwnSurface(FView, 1);
  r.EditorKind := vekColor;
  asEmpty := TyPaintOwnSurface(FView, 1);
  r.Value := 'clRed';
  asRed := TyPaintOwnSurface(FView, 1);
  try
    differ := 0;
    red := 0;
    for y := 0 to asText.Height - 1 do
      for x := 0 to asText.Width - 1 do
      begin
        a := asText.GetPixel(x, y);
        b := asEmpty.GetPixel(x, y);
        if (a.red <> b.red) or (a.green <> b.green) or (a.blue <> b.blue) then Inc(differ);
        b := asRed.GetPixel(x, y);
        if (b.red = 255) and (b.green = 0) and (b.blue = 0) then Inc(red);
      end;
    AssertEquals('no value: the row is drawn as a text row with no value is', 0, differ);
    AssertTrue('a value: its swatch is drawn (' + IntToStr(red) + ' red px)', red >= 16);
  finally
    asText.Free;
    asEmpty.Free;
    asRed.Free;
  end;
end;

initialization
  RegisterTest(TRowInspectorTest);
  RegisterTest(TValueListRowsTest);
end.
