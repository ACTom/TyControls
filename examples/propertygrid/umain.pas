unit umain;

{ TTyPropertyGrid: the right half shows the published properties of whichever control on the
  left was clicked last, and every change made there goes straight into that control.

  The window is designed in umain.lfm, the grid included: it starts on Button1 because its
  SelectedComponent says so, with Font expanded because ExpandedProperties lists it. The code
  only answers the grid's events and the tool row.

  Things to try: click a control on the left; change Caption, Width or Font.Size and watch the
  control follow; tick the box in the Font.Style row; open the grid's Header.Columns and rename a
  column; type 99999999999 into Width (too big for an Integer: the grid refuses it, and the status
  line says why, through OnPropertyError); turn on Show events (the handlers are listed by name, read-only);
  type into Filter -- OnFilterProperty keeps the matching rows; click the check box while it is
  inspected (the control changed itself, Refresh shows it). }

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
    procedure FilterEditChange(Sender: TObject);
    procedure GridFilterProperty(Sender: TObject; AInstance: TPersistent;
      const APropName: string; var AShow: Boolean);
    procedure GridPropertyChanged(Sender: TObject; AInstance: TPersistent;
      const APropName: string);
    procedure GridPropertyError(Sender: TObject; AInstance: TPersistent;
      const APropName: string; E: Exception);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsInspecting = 'Inspecting %s';
  rsChanged    = '%s.%s changed';
  rsRefused    = '%s was not changed: %s';

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
end;

procedure TMainForm.ControlClick(Sender: TObject);
begin
  Grid.SelectedComponent := Sender as TComponent;
  LblStatus.Caption := Format(rsInspecting, [NameOf(Grid.SelectedComponent)]);
end;

{ The check box changed itself (a click on it). The grid shows what it read last; Refresh reads
  the values again and keeps the expanded rows and the current row. }
procedure TMainForm.CheckBox1Change(Sender: TObject);
begin
  if Grid.SelectedComponent = CheckBox1 then Grid.Refresh;
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

{ OnFilterProperty is asked while the rows are built, so a new filter needs a Rebuild. }
procedure TMainForm.FilterEditChange(Sender: TObject);
begin
  Grid.Rebuild;
end;

procedure TMainForm.GridFilterProperty(Sender: TObject; AInstance: TPersistent;
  const APropName: string; var AShow: Boolean);
var
  f: string;
begin
  { Only the control's own properties are filtered. A sub-property (Font.Size) is asked about
    too, with the font as AInstance -- filtering those as well would hide Size whenever the
    filter is 'Font', and Font whenever it is 'Size'. }
  if AInstance <> Grid.SelectedObject then Exit;
  f := Trim(FilterEdit.Text);
  if f <> '' then
    AShow := Pos(LowerCase(f), LowerCase(APropName)) > 0;
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
