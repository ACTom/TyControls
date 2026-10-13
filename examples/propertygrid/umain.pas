unit umain;

{ TTyPropertyGrid: the right half shows the published properties of the controls on the left that
  were clicked, and every change made there goes straight into them.

  The window is designed in umain.lfm, the grid included: it starts on Button1 because its
  SelectedComponent says so, with Font expanded because ExpandedProperties lists it. The code
  only answers the grid's events and the tool rows.

  Things to try: click a control on the left; change Caption, Width or Font.Size and watch the
  control follow; tick the box in the Font.Style row. Ctrl+click more controls (the title says how
  many): only what they all have is listed, a value they do not share is an empty cell, and what
  you type goes into every one of them. Type into Filter: the grid keeps the rows whose name holds
  it -- 'size' opens Font for its Size -- and clearing it closes them again. Turn on Writable only
  (OnFilterProperty drops what has no setter), Categories (Layout, Appearance, Behavior...), Show
  events (the handlers by name, read-only). Inspect the string grid, open Header.Columns and press
  Insert, or right-click a column: add, delete, move up and down; the string grid moves its cells
  with the columns. Type 99999999999 into Width: too big for an Integer, the grid refuses it and the
  status line says why (OnPropertyError). Click the check box while it is inspected: it changed
  itself, and Refresh shows it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TypInfo, Controls, Forms,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.CheckBox, tyControls.Edit, tyControls.ProgressBar, tyControls.Panel,
  tyControls.Grid, tyControls.PropertyGrid;

type

  { TMainForm }

  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    SwEvents: TTyToggleSwitch;
    SwWritable: TTyToggleSwitch;
    SwCategories: TTyToggleSwitch;
    LblFilter: TTyLabel;
    FilterEdit: TTyEdit;
    LblPick: TTyLabel;
    Button1: TTyButton;
    Edit1: TTyEdit;
    CheckBox1: TTyCheckBox;
    ProgressBar1: TTyProgressBar;
    Panel1: TTyPanel;
    StringGrid1: TTyStringGrid;
    Grid: TTyPropertyGrid;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure ControlClick(Sender: TObject);
    procedure CheckBox1Change(Sender: TObject);
    procedure SwEventsChange(Sender: TObject);
    procedure SwWritableChange(Sender: TObject);
    procedure SwCategoriesChange(Sender: TObject);
    procedure FilterEditChange(Sender: TObject);
    procedure GridFilterProperty(Sender: TObject; AInstance: TPersistent;
      const APropName: string; var AShow: Boolean);
    procedure GridPropertyChanged(Sender: TObject; AInstance: TPersistent;
      const APropName: string);
    procedure GridPropertyError(Sender: TObject; AInstance: TPersistent;
      const APropName: string; E: Exception);
    procedure GridCollectionChanging(Sender: TObject; ACollection: TCollection;
      AAction: TTyCollectionAction; AIndex, ANewIndex: Integer; var AAllow: Boolean);
  private
    function IsInspected(AObject: TPersistent): Boolean;
    procedure ShowSelection;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsTitleOne   = 'Property grid  ·  %s';
  rsTitleMany  = 'Property grid  ·  %d controls';
  rsInspecting = 'Inspecting %s';
  rsInspectingMany = 'Inspecting %d controls: what they all have, written into each';
  rsChanged    = '%s.%s changed';
  rsRefused    = '%s was not changed: %s';
  rsColumns    = 'The string grid did that itself, so its cells move with the columns';

const
  CPeople: array[0..4, 0..2] of string = (
    ('Li Wei', 'Shanghai', '92'),
    ('Anna Berg', 'Oslo', '87'),
    ('Tom Hardy', 'Leeds', '75'),
    ('Mei Lin', 'Chengdu', '98'),
    ('Jonas Weber', 'Bremen', '81'));

{ An object's name for the status line: a component by its Name, anything else (a font, a
  column) by its class. }
function NameOf(AInstance: TPersistent): string;
begin
  if (AInstance is TComponent) and (TComponent(AInstance).Name <> '') then
    Result := TComponent(AInstance).Name
  else if AInstance <> nil then
    Result := AInstance.ClassName
  else
    Result := '?';
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i, r: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  StringGrid1.RowCount := Length(CPeople);
  for r := 0 to High(CPeople) do
    for i := 0 to 2 do
      StringGrid1.Cells[i, r] := CPeople[r, i];
  ShowSelection;
end;

{ A click inspects that control alone; Ctrl+click (Cmd+click on a Mac) adds it to the controls
  being inspected, or takes it out again. }
procedure TMainForm.ControlClick(Sender: TObject);
var
  objs: array of TPersistent;
  i, n: Integer;
  found: Boolean;
begin
  if ssModifier in GetKeyShiftState then
  begin
    SetLength(objs, Grid.SelectedCount + 1);
    n := 0;
    found := False;
    for i := 0 to Grid.SelectedCount - 1 do
      if Grid.SelectedObjects[i] = Sender then
        found := True
      else
      begin
        objs[n] := Grid.SelectedObjects[i];
        Inc(n);
      end;
    if not found then
    begin
      objs[n] := Sender as TPersistent;
      Inc(n);
    end;
    SetLength(objs, n);
    Grid.SelectObjects(objs);
  end
  else
    Grid.SelectedComponent := Sender as TComponent;
  ShowSelection;
end;

function TMainForm.IsInspected(AObject: TPersistent): Boolean;
var i: Integer;
begin
  for i := 0 to Grid.SelectedCount - 1 do
    if Grid.SelectedObjects[i] = AObject then Exit(True);
  Result := False;
end;

procedure TMainForm.ShowSelection;
begin
  if Grid.SelectedCount > 1 then
  begin
    Bar.Caption := Format(rsTitleMany, [Grid.SelectedCount]);
    LblStatus.Caption := Format(rsInspectingMany, [Grid.SelectedCount]);
  end
  else
  begin
    Bar.Caption := Format(rsTitleOne, [NameOf(Grid.SelectedObject)]);
    LblStatus.Caption := Format(rsInspecting, [NameOf(Grid.SelectedObject)]);
  end;
end;

{ The check box changed itself (a click on it). The grid shows what it read last; Refresh reads
  the values again and keeps the expanded rows and the current row. }
procedure TMainForm.CheckBox1Change(Sender: TObject);
begin
  if IsInspected(CheckBox1) then Grid.Refresh;
end;

{ Event handlers are left out by default (TypeFilter without tkMethod): there is no code to hook
  up at run time, so they can only be looked at. }
procedure TMainForm.SwEventsChange(Sender: TObject);
begin
  if SwEvents.Checked then
    Grid.TypeFilter := Grid.TypeFilter + [tkMethod]
  else
    Grid.TypeFilter := Grid.TypeFilter - [tkMethod];
end;

{ OnFilterProperty is asked while the rows are built, so a change to what it decides needs a
  Rebuild. }
procedure TMainForm.SwWritableChange(Sender: TObject);
begin
  Grid.Rebuild;
end;

procedure TMainForm.SwCategoriesChange(Sender: TObject);
begin
  Grid.ShowCategories := SwCategories.Checked;
end;

{ The grid filters by name itself: the rows whose name holds the text stay, a sub-property's
  parents open for it, and an empty filter puts the rows back as they were. }
procedure TMainForm.FilterEditChange(Sender: TObject);
begin
  Grid.FilterText := FilterEdit.Text;
end;

{ Writable only: a property without a setter is left out -- except an object (Font,
  Constraints), whose own properties can be written all the same. The grid asks this before it
  applies FilterText, so the two work together. }
procedure TMainForm.GridFilterProperty(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var AShow: Boolean);
var
  pi: PPropInfo;
begin
  if not SwWritable.Checked then Exit;
  pi := GetPropInfo(AInstance, APropName);
  if (pi <> nil) and (pi^.SetProc = nil) and (pi^.PropType^.Kind <> tkClass) then
    AShow := False;
end;

procedure TMainForm.GridPropertyChanged(Sender: TObject; AInstance: TPersistent;
  const APropName: string);
begin
  LblStatus.Caption := Format(rsChanged, [NameOf(AInstance), APropName]);
end;

{ Without this handler a refused value raises, and the application shows its error box. Here the
  status line says it instead; either way the row keeps the value the control has. }
procedure TMainForm.GridPropertyError(Sender: TObject; AInstance: TPersistent;
  const APropName: string; E: Exception);
begin
  LblStatus.Caption := Format(rsRefused, [APropName, E.Message]);
end;

{ The grid adds, deletes and moves collection items through TCollection itself. A string grid
  keeps its cells by column index, so a column added, deleted or moved that way would leave the
  cells where they were. Here the grid is told no, and the string grid does it with its own
  methods, which take the cells along (a moved column keeps its index: the string grid shows it
  in another place). Refresh then shows the columns as they are now. }
procedure TMainForm.GridCollectionChanging(Sender: TObject; ACollection: TCollection;
  AAction: TTyCollectionAction; AIndex, ANewIndex: Integer; var AAllow: Boolean);
begin
  if ACollection <> StringGrid1.Header.Columns then Exit;
  AAllow := False;
  case AAction of
    caAdd:    StringGrid1.InsertColumn(ANewIndex);
    caDelete: StringGrid1.DeleteColumn(AIndex);
    caMove:   StringGrid1.MoveColumn(AIndex, ANewIndex);
  end;
  Grid.Refresh;
  LblStatus.Caption := rsColumns;
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

end.
