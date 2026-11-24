unit test.dialogs.focus;
{$mode objfpc}{$H+}

{ #243: where the keyboard focus starts in a dialog, and the order Tab walks it in.

  TTyDialog creates its button strip in its constructor, before a builder adds the content,
  and the Tab order of siblings is the order they were given their parent -- so the strip came
  before everything a dialog contains, and the LCL gives the focus to the first tab stop of a
  form that names no ActiveControl. Every dialog opened with the focus on OK.

  Nothing here shows a window. What a shown form would do is read off the form:

    TabStops    GetTabOrderList, less what Tab passes over (no TabStop, cannot take focus);
    FirstFocus  its ActiveControl, and where it names none, the first of those tab stops.
                That is what TCustomForm.FindDefaultForActiveControl picks for a shown form
                (FindNextControl(nil, True, True, False), customform.inc). The LCL's own
                function cannot be asked here: its CanTab also asks the widgetset, which
                answers False for a control without a window handle.

  A real window was looked at too, on a hidden desktop (gate-tools/probes/dlgfocus.lpr). }

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, Dialogs, LCLType, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Form, tyControls.Panel,
  tyControls.Button, tyControls.Edit, tyControls.Memo, tyControls.ListBox, tyControls.CheckBox,
  tyControls.ImageCollection, tyControls.Icons.Lucide,
  tyControls.Dialogs, tyControls.Dialogs.About, tyControls.Dialogs.Color,
  tyControls.Dialogs.FileDialog, tyControls.Dialogs.Find, tyControls.Dialogs.Font,
  tyControls.Dialogs.IconBrowser, tyControls.Dialogs.ImageCollectionEditor,
  tyControls.Dialogs.Progress, tyControls.Dialogs.SelectPath;

type
  TDialogFocusTest = class(TTestCase)
  private
    FOwner: TComponent;       // owns the wrapper components a test makes
    FDlg: TCustomForm;        // the dialog under test, freed in TearDown
    function FirstFocus(F: TCustomForm): TWinControl;
    { The class names of the tab stops, in Tab order, joined by a blank. }
    function TabStops(F: TCustomForm): string;
    function TabStopAt(F: TCustomForm; AIndex: Integer): TWinControl;
    function Keep(F: TCustomForm): TCustomForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { the rule every dialog gets }
    procedure TheButtonStripIsLastInTheTabOrder;
    procedure ContentAddedBetweenAndAfterTheButtonsStillComesFirst;
    procedure ContentInsideAPanelComesFirstToo;
    procedure FocusStartsOnTheFirstControlOfTheContent;
    procedure WithNothingButButtonsFocusStartsOnTheDefaultButton;
    procedure ADesignedDialogHasTheStripLastOnceItIsLoaded;
    { each dialog }
    procedure AnInputBoxStartsInItsEdit;
    procedure APasswordBoxStartsInItsEdit;
    procedure ATextQueryStartsInItsMemo;
    procedure ASelectValueDialogStartsInItsList;
    procedure TheOpenDialogStartsInTheFileNameBox;
    procedure TheSaveDialogStartsInTheFileNameBox;
    procedure TheOpenDialogWithAPreviewStartsInTheFileNameBox;
    procedure TheFileDialogIsTabbedInTheOrderItIsLaidOut;
    procedure TheFolderDialogStartsInItsTreeAndTabsFromThePathBox;
    procedure TheFontDialogStartsInTheFontList;
    procedure TheColourDialogStartsInTheHexField;
    procedure TheIconBrowserStartsInItsSearchBox;
    procedure TheFindDialogStartsInTheSearchTextEachTimeItIsShown;
    procedure TheReplaceDialogStartsInTheSearchText;
    procedure TheImageCollectionEditorStartsInItsList;
    procedure DialogsOfButtonsOnlyStartOnTheirButton;
  end;

implementation

type
  TDialogCrack = class(TTyDialog);   // Loaded is protected

procedure TDialogFocusTest.SetUp;
begin
  FOwner := TComponent.Create(nil);
  FDlg := nil;
end;

procedure TDialogFocusTest.TearDown;
begin
  FreeAndNil(FDlg);
  FreeAndNil(FOwner);
end;

function TDialogFocusTest.Keep(F: TCustomForm): TCustomForm;
begin
  FreeAndNil(FDlg);
  FDlg := F;
  Result := F;
end;

function TDialogFocusTest.FirstFocus(F: TCustomForm): TWinControl;
begin
  Result := F.ActiveControl;
  if Result = nil then
    Result := TabStopAt(F, 0);
end;

function TDialogFocusTest.TabStopAt(F: TCustomForm; AIndex: Integer): TWinControl;
var
  L: TFPList;
  i, n: Integer;
  w: TWinControl;
begin
  Result := nil;
  L := TFPList.Create;
  try
    F.GetTabOrderList(L);
    n := -1;
    for i := 0 to L.Count - 1 do
    begin
      w := TWinControl(L[i]);
      if w.TabStop and w.CanFocus then
      begin
        Inc(n);
        if n = AIndex then Exit(w);
      end;
    end;
  finally
    L.Free;
  end;
end;

function TDialogFocusTest.TabStops(F: TCustomForm): string;
var
  i: Integer;
  w: TWinControl;
begin
  Result := '';
  i := 0;
  repeat
    w := TabStopAt(F, i);
    if w = nil then Break;
    if Result <> '' then Result := Result + ' ';
    Result := Result + w.ClassName;
    Inc(i);
  until False;
end;

{ --- the rule every dialog gets ------------------------------------------------------ }

procedure TDialogFocusTest.TheButtonStripIsLastInTheTabOrder;
var
  d: TTyDialog;
  e: TTyEdit;
  ok, cancel: TTyButton;
begin
  d := TTyDialog.CreateNew(nil);
  Keep(d);
  ok := d.AddButton('OK', mrOK, True);
  cancel := d.AddButton('Cancel', mrCancel, False, True);
  e := TTyEdit.Create(d);
  e.Parent := d;
  AssertSame('Tab reaches the content first', e, TabStopAt(d, 0));
  AssertSame('then the buttons, as they were added', ok, TabStopAt(d, 1));
  AssertSame('and the next of them', cancel, TabStopAt(d, 2));
  AssertNull('and nothing after', TabStopAt(d, 3));
end;

procedure TDialogFocusTest.ContentAddedBetweenAndAfterTheButtonsStillComesFirst;
var
  d: TTyDialog;
  e1, e2, e3: TTyEdit;
begin
  { A builder is free to add its buttons whenever it likes; the strip is last all the same. }
  d := TTyDialog.CreateNew(nil);
  Keep(d);
  e1 := TTyEdit.Create(d); e1.Parent := d;
  d.AddButton('OK', mrOK, True);
  e2 := TTyEdit.Create(d); e2.Parent := d;
  d.AddButton('Cancel', mrCancel, False, True);
  e3 := TTyEdit.Create(d); e3.Parent := d;
  AssertSame('first', e1, TabStopAt(d, 0));
  AssertSame('second', e2, TabStopAt(d, 1));
  AssertSame('third', e3, TabStopAt(d, 2));
  AssertEquals('the whole order', 'TTyEdit TTyEdit TTyEdit TTyButton TTyButton', TabStops(d));
end;

procedure TDialogFocusTest.ContentInsideAPanelComesFirstToo;
var
  d: TTyDialog;
  pnl: TTyPanel;
  e: TTyEdit;
begin
  d := TTyDialog.CreateNew(nil);
  Keep(d);
  d.AddButton('OK', mrOK, True);
  pnl := TTyPanel.Create(d);
  pnl.Parent := d;
  e := TTyEdit.Create(d);
  e.Parent := pnl;
  AssertSame('the edit in the panel is the first tab stop', e, TabStopAt(d, 0));
  AssertEquals('the whole order', 'TTyEdit TTyButton', TabStops(d));
end;

procedure TDialogFocusTest.FocusStartsOnTheFirstControlOfTheContent;
var
  d: TTyDialog;
  e: TTyEdit;
begin
  d := TTyDialog.CreateNew(nil);
  Keep(d);
  d.AddButton('OK', mrOK, True);
  d.AddButton('Cancel', mrCancel, False, True);
  e := TTyEdit.Create(d);
  e.Parent := d;
  AssertSame('a dialog an application builds starts in its first field', e, FirstFocus(d));
end;

procedure TDialogFocusTest.WithNothingButButtonsFocusStartsOnTheDefaultButton;
var
  d: TTyDialog;
  w: TWinControl;
begin
  d := TyBuildMessageDialog('Save the changes?', mtConfirmation, [mbYes, mbNo, mbCancel]);
  Keep(d);
  w := FirstFocus(d);
  AssertTrue('a button', w is TTyButton);
  AssertTrue('the default one', TTyButton(w).Default);
end;

procedure TDialogFocusTest.ADesignedDialogHasTheStripLastOnceItIsLoaded;
var
  d: TTyDialog;
  e1, e2: TTyEdit;
begin
  { A dialog designed as a form stores a TabOrder for each control it holds, and those are
    applied at the end of loading -- after the constructor put the strip last. Stood in for
    here by giving the controls their numbers by hand, which can leave one after the strip. }
  d := TTyDialog.CreateNew(nil);
  Keep(d);
  d.AddButton('OK', mrOK, True);
  e1 := TTyEdit.Create(d); e1.Parent := d;
  e2 := TTyEdit.Create(d); e2.Parent := d;
  e1.TabOrder := High(TTabOrder);   // "last", which is past the strip
  AssertEquals('precondition: a control has got behind the buttons',
    'TTyEdit TTyButton TTyEdit', TabStops(d));
  TDialogCrack(d).Loaded;
  AssertEquals('loaded, the buttons close the Tab order again', 'TTyEdit TTyEdit TTyButton',
    TabStops(d));
  AssertSame('and the order among the content is the stored one', e2, TabStopAt(d, 0));
end;

{ --- each dialog --------------------------------------------------------------------- }

procedure TDialogFocusTest.AnInputBoxStartsInItsEdit;
var
  d: TTyDialog;
  e: TTyEdit;
begin
  d := TyBuildInputDialog('Name', 'Your name:', 'Tom', e);
  Keep(d);
  AssertSame('the edit', e, FirstFocus(d));
  AssertEquals('Tab then goes to the buttons', 'TTyEdit TTyButton TTyButton', TabStops(d));
end;

procedure TDialogFocusTest.APasswordBoxStartsInItsEdit;
var
  d: TTyDialog;
  e: TTyEdit;
begin
  d := TyBuildPasswordDialog('Password', 'Password:', '*', e);
  Keep(d);
  AssertSame('the edit', e, FirstFocus(d));
end;

procedure TDialogFocusTest.ATextQueryStartsInItsMemo;
var
  d: TTyDialog;
  m: TTyMemo;
begin
  d := TyBuildTextDialog('Notes', 'Notes:', 'line one', m);
  Keep(d);
  AssertSame('the memo', m, FirstFocus(d));
end;

procedure TDialogFocusTest.ASelectValueDialogStartsInItsList;
var
  d: TTyDialog;
  lb: TTyListBox;
  items: TStringList;
begin
  items := TStringList.Create;
  try
    items.Add('one'); items.Add('two');
    d := TyBuildSelectValueDialog('Pick', 'Pick one:', items, 1, lb);
    Keep(d);
    AssertSame('the list', lb, FirstFocus(d));
  finally
    items.Free;
  end;
end;

procedure TDialogFocusTest.TheOpenDialogStartsInTheFileNameBox;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(False, False, 'Open');
  Keep(d);
  AssertSame('the file name box', d.NameEdit, FirstFocus(d));
end;

procedure TDialogFocusTest.TheSaveDialogStartsInTheFileNameBox;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(True, False, 'Save');
  Keep(d);
  AssertSame('the file name box', d.NameEdit, FirstFocus(d));
end;

procedure TDialogFocusTest.TheOpenDialogWithAPreviewStartsInTheFileNameBox;
var
  d: TTyFileDialogForm;
begin
  d := TyBuildFileDialog(False, True, 'Open picture');
  Keep(d);
  AssertSame('the file name box', d.NameEdit, FirstFocus(d));
end;

procedure TDialogFocusTest.TheFileDialogIsTabbedInTheOrderItIsLaidOut;
var
  d: TTyFileDialogForm;
  order: string;
const
  { top row: the folder box, the view box; the middle: tree, list; below: name, then type }
  cContent = 'TTyShellComboBox TTyComboBox TTyShellTreeView TTyShellListView TTyEdit '
    + 'TTyFilterComboBox ';
begin
  d := TyBuildFileDialog(True, False, 'Save');
  Keep(d);
  order := TabStops(d) + ' ';
  AssertEquals('the content, top to bottom and left to right', cContent,
    Copy(order, 1, Length(cContent)));
  AssertSame('the name box is the one before the file type box', d.NameEdit, TabStopAt(d, 4));
  AssertEquals('and only the buttons of the strip come after', '',
    StringReplace(Copy(order, Length(cContent) + 1, MaxInt), 'TTyButton ', '', [rfReplaceAll]));
end;

procedure TDialogFocusTest.TheFolderDialogStartsInItsTreeAndTabsFromThePathBox;
var
  d: TTySelectPathForm;
begin
  d := TyBuildSelectPathDialog('Folder', '');
  Keep(d);
  AssertEquals('the tree is where one picks', 'TTyTreeView', FirstFocus(d).ClassName);
  AssertEquals('Tab walks it top to bottom: the path box, the tree, the buttons',
    'TTyEdit TTyTreeView TTyButton TTyButton', TabStops(d));
end;

procedure TDialogFocusTest.TheFontDialogStartsInTheFontList;
var
  d: TTyFontForm;
  f: TFont;
  fams: TStringList;
begin
  f := TFont.Create;
  fams := TStringList.Create;
  try
    fams.Add('Arial'); fams.Add('Courier New');
    d := TyBuildFontDialog('Font', f, fams);
    Keep(d);
    AssertEquals('the font list', 'TTyFontListBox', FirstFocus(d).ClassName);
  finally
    fams.Free;
    f.Free;
  end;
end;

procedure TDialogFocusTest.TheColourDialogStartsInTheHexField;
var
  d: TTyColorForm;
  w: TWinControl;
begin
  d := TyBuildColorDialog('Colour', TyRGB(51, 102, 204));
  Keep(d);
  w := FirstFocus(d);
  AssertTrue('an edit', w is TTyEdit);
  { The field shows the alpha too (#3366CCFF); HexText is the colour without it. }
  AssertEquals('the one that holds the colour as text', d.HexText,
    Copy(TTyEdit(w).Text, 1, Length(d.HexText)));
  AssertEquals('Tab still starts with the picker, left of it',
    'TTyHSVSquare', TabStopAt(d, 0).ClassName);
end;

procedure TDialogFocusTest.TheIconBrowserStartsInItsSearchBox;
var
  d: TTyIconBrowserForm;
begin
  d := TyBuildIconBrowserDialog('Icons', TyLucideFont);
  Keep(d);
  AssertEquals('the search box', 'TTyEdit', FirstFocus(d).ClassName);
end;

procedure TDialogFocusTest.TheFindDialogStartsInTheSearchTextEachTimeItIsShown;
var
  fd: TTyFindDialog;
  f: TTyFindForm;
begin
  fd := TTyFindDialog.Create(FOwner);
  fd.FindText := 'needle';
  f := fd.BuildForm;
  AssertSame('the search text', f.FindEdit, FirstFocus(f));
  AssertEquals('all of it selected, to be typed over', Length('needle'), f.FindEdit.SelLength);

  { The window is built once and shown again by the next Execute; the focus is wherever the
    user left it. Asking for the dialog again is asking to search for something. }
  f.ActiveControl := f.MatchCaseCheck;
  f.FindEdit.SelLength := 0;
  AssertSame('the same window again', f, fd.BuildForm);
  AssertSame('back in the search text', f.FindEdit, f.ActiveControl);
  AssertEquals('selected again', Length('needle'), f.FindEdit.SelLength);
end;

procedure TDialogFocusTest.TheReplaceDialogStartsInTheSearchText;
var
  rd: TTyReplaceDialog;
  f: TTyFindForm;
begin
  rd := TTyReplaceDialog.Create(FOwner);
  rd.FindText := 'needle';
  f := rd.BuildForm;
  AssertSame('the search text, not the replacement', f.FindEdit, FirstFocus(f));
  AssertSame('Tab goes on to the replacement', f.ReplaceEdit, TabStopAt(f, 1));
end;

procedure TDialogFocusTest.TheImageCollectionEditorStartsInItsList;
var
  ic: TTyImageCollection;
  d: TTyImageCollectionEditorForm;
begin
  ic := TTyImageCollection.Create(FOwner);
  d := TyBuildImageCollectionEditor(ic);
  Keep(d);
  AssertEquals('the list of images', 'TTyListBox', FirstFocus(d).ClassName);
end;

procedure TDialogFocusTest.DialogsOfButtonsOnlyStartOnTheirButton;
var
  d: TTyDialog;
  pd: TTyProgressDialog;
begin
  { Nothing to move the focus to: these were right, and stay so. }
  d := TyBuildMessageDialog('Done.', mtInformation, [mbOK]);
  Keep(d);
  AssertEquals('message', 'TTyButton', FirstFocus(d).ClassName);
  d := TyBuildAboutDialog('About', 'Probe', '1.0', 'A probe.', '(c)', 'MIT', 'https://example.org');
  Keep(d);
  AssertEquals('about', 'TTyButton', FirstFocus(d).ClassName);
  pd := TTyProgressDialog.Create(FOwner);
  pd.Cancelable := True;
  AssertEquals('progress', 'TTyButton', FirstFocus(pd.BuildForm).ClassName);
end;

initialization
  RegisterTest(TDialogFocusTest);
end.
