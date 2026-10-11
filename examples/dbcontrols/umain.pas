unit umain;

{ The data-aware controls (tycontrols_db) -- all 21 of them on one form, bound to an in-memory
  table. The window, every control and both TDataSource components are designed in umain.lfm,
  where each control's DataSource and DataField are set; the code here builds the two tables
  (TBufDataset needs no database server or file), hooks them to the data sources, and handles
  the few switches on the tool row.

  Things to try: move between rows with the navigator; type in a field and watch the state on
  the status line go to "editing"; press Esc to take an edit back; Post or Cancel with the
  navigator; pick a city in either lookup control and see the CityID raw value change; turn
  Auto edit off (typing no longer starts an edit, the navigator's Edit button still does) or
  Read only on; the fourth row is a new hire with most fields empty (NULL). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, TypInfo, DB, BufDataset,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.CheckBox,
  tyControls.DB.Edits, tyControls.DB.Choices, tyControls.DB.Lists, tyControls.DB.Image,
  tyControls.DB.DateTime, tyControls.DB.Navigator;

type

  { TMainForm }

  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    PeopleSrc: TDataSource;
    CitySrc: TDataSource;
    { the tool row }
    Navigator: TTyDBNavigator;
    CbAutoEdit: TTyCheckBox;
    CbReadOnly: TTyCheckBox;
    BtnClearPhoto: TTyButton;
    { column 1: one line each }
    LblName: TTyLabel;
    EdName: TTyDBEdit;
    LblPhone: TTyLabel;
    EdPhone: TTyDBMaskEdit;
    LblDept: TTyLabel;
    CmbDept: TTyDBComboBox;
    LblSalary: TTyLabel;
    EdSalary: TTyDBCurrencyEdit;
    LblHours: TTyLabel;
    EdHours: TTyDBNumericEdit;
    LblHeight: TTyLabel;
    EdHeight: TTyDBFloatSpinEdit;
    LblYears: TTyLabel;
    EdYears: TTyDBSpinEdit;
    LblBorn: TTyLabel;
    DtBorn: TTyDBDateTimePicker;
    LblCity: TTyLabel;
    CmbCity: TTyDBLookupComboBox;
    LblActive: TTyLabel;
    CbActive: TTyDBCheckBox;
    LblRemote: TTyLabel;
    SwRemote: TTyDBToggleSwitch;
    LblLevel: TTyLabel;
    SegLevel: TTyDBSegmented;
    LblStars: TTyLabel;
    RtStars: TTyDBRating;
    LblNote: TTyLabel;
    MmNote: TTyDBMemo;
    { column 2: lists }
    RgShift: TTyDBRadioGroup;
    LblSkill: TTyLabel;
    LbSkill: TTyDBListBox;
    LblCityList: TTyLabel;
    LbCity: TTyDBLookupListBox;
    { column 3: calendar and photo }
    LblJoined: TTyLabel;
    CalJoined: TTyDBCalendar;
    LblPhoto: TTyLabel;
    ImgPhoto: TTyDBImage;
    { column 4: the raw field values }
    LblRaw: TTyLabel;
    LblRawID: TTyLabel;
    TxtID: TTyDBText;
    LblRawName: TTyLabel;
    TxtName: TTyDBText;
    LblRawPhone: TTyLabel;
    TxtPhone: TTyDBText;
    LblRawDept: TTyLabel;
    TxtDept: TTyDBText;
    LblRawSalary: TTyLabel;
    TxtSalary: TTyDBText;
    LblRawHours: TTyLabel;
    TxtHours: TTyDBText;
    LblRawHeight: TTyLabel;
    TxtHeight: TTyDBText;
    LblRawYears: TTyLabel;
    TxtYears: TTyDBText;
    LblRawBorn: TTyLabel;
    TxtBorn: TTyDBText;
    LblRawCityID: TTyLabel;
    TxtCityID: TTyDBText;
    LblRawActive: TTyLabel;
    TxtActive: TTyDBText;
    LblRawRemote: TTyLabel;
    TxtRemote: TTyDBText;
    LblRawLevel: TTyLabel;
    TxtLevel: TTyDBText;
    LblRawStars: TTyLabel;
    TxtStars: TTyDBText;
    LblRawShift: TTyLabel;
    TxtShift: TTyDBText;
    LblRawSkill: TTyLabel;
    TxtSkill: TTyDBText;
    LblRawJoined: TTyLabel;
    TxtJoined: TTyDBText;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure PeopleSrcStateChange(Sender: TObject);
    procedure PeopleSrcDataChange(Sender: TObject; Field: TField);
    procedure CbAutoEditChange(Sender: TObject);
    procedure CbReadOnlyChange(Sender: TObject);
    procedure BtnClearPhotoClick(Sender: TObject);
  private
    FPeople: TBufDataset;
    FCities: TBufDataset;
    procedure BuildTables;
    procedure ShowStatus;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsStatusFmt     = 'State: %s  ·  record %d of %d';
  rsStateInactive = 'closed';
  rsStateBrowse   = 'browsing';
  rsStateEdit     = 'editing';
  rsStateInsert   = 'inserting';
  rsStateOther    = 'busy';

{ A file next to the program, or next to one of its parent folders: the example runs from its
  own folder or from a build output folder below it. }
function ExampleFile(const AName: string): string;
var
  dir: string;
  i: Integer;
begin
  dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if FileExists(dir + AName) then Exit(dir + AName);
    dir := ExtractFilePath(ExcludeTrailingPathDelimiter(dir));
    if dir = '' then Break;
  end;
  Result := '';
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  BuildTables;
  { The lookup table first: the two lookup controls read it as soon as People is shown. }
  CitySrc.DataSet := FCities;
  PeopleSrc.DataSet := FPeople;
  FPeople.First;
  ShowStatus;
end;

procedure TMainForm.BuildTables;

  procedure AddPerson(AID: Integer; const AName, APhone, ANote, ADept: string;
    ASalary: Currency; AHours, AHeight: Double; AYears: Integer; ABorn, AJoined: TDateTime;
    ACity: Integer; AActive: Boolean; const ARemote, ALevel: string; AStars: Double;
    const AShift, ASkill, APhoto: string);
  var
    photo: string;
  begin
    FPeople.Append;
    FPeople.FieldByName('ID').AsInteger := AID;
    FPeople.FieldByName('Name').AsString := AName;
    FPeople.FieldByName('Phone').AsString := APhone;
    FPeople.FieldByName('Note').AsString := ANote;
    FPeople.FieldByName('Dept').AsString := ADept;
    FPeople.FieldByName('Salary').AsCurrency := ASalary;
    FPeople.FieldByName('Hours').AsFloat := AHours;
    FPeople.FieldByName('Height').AsFloat := AHeight;
    FPeople.FieldByName('Years').AsInteger := AYears;
    FPeople.FieldByName('Born').AsDateTime := ABorn;
    FPeople.FieldByName('Joined').AsDateTime := AJoined;
    FPeople.FieldByName('CityID').AsInteger := ACity;
    FPeople.FieldByName('Active').AsBoolean := AActive;
    FPeople.FieldByName('Remote').AsString := ARemote;
    FPeople.FieldByName('Level').AsString := ALevel;
    FPeople.FieldByName('Stars').AsFloat := AStars;
    FPeople.FieldByName('Shift').AsString := AShift;
    FPeople.FieldByName('Skill').AsString := ASkill;
    { The photo is a plain PNG in a blob field; TTyDBImage recognises it by its content. }
    photo := ExampleFile(APhoto);
    if photo <> '' then
      TBlobField(FPeople.FieldByName('Photo')).LoadFromFile(photo);
    FPeople.Post;
  end;

begin
  FCities := TBufDataset.Create(Self);
  FCities.FieldDefs.Add('ID', ftInteger);
  FCities.FieldDefs.Add('Name', ftString, 20);
  FCities.CreateDataset;                   // also opens it
  FCities.AppendRecord([1, 'Shanghai']);
  FCities.AppendRecord([2, 'Beijing']);
  FCities.AppendRecord([3, 'Shenzhen']);
  FCities.AppendRecord([4, 'Hangzhou']);
  FCities.First;

  FPeople := TBufDataset.Create(Self);
  with FPeople.FieldDefs do
  begin
    Add('ID', ftInteger);
    Add('Name', ftString, 40);
    Add('Phone', ftString, 8);
    Add('Note', ftMemo);
    Add('Dept', ftString, 20);
    Add('Salary', ftCurrency);
    Add('Hours', ftFloat);
    Add('Height', ftFloat);
    Add('Years', ftInteger);
    Add('Born', ftDate);
    Add('Joined', ftDate);
    Add('CityID', ftInteger);
    Add('Active', ftBoolean);
    Add('Remote', ftString, 1);         // 'Y' / 'N', mapped by the switch's ValueChecked
    Add('Level', ftString, 10);
    Add('Stars', ftFloat);
    Add('Shift', ftString, 1);          // 'D' / 'N' / 'F', mapped by the radio group's Values
    Add('Skill', ftString, 20);
    Add('Photo', ftBlob);
  end;
  FPeople.CreateDataset;                   // also opens it
  { Field settings the controls pick up: the masked edit takes the field's EditMask. }
  FPeople.FieldByName('Phone').EditMask := '000-0000;1;_';

  AddPerson(1, 'Lin Chen', '555-0101', 'Leads the desktop client team.', 'Engineering',
    18500, 40, 1.72, 6, EncodeDate(1988, 4, 12), EncodeDate(2019, 3, 4), 1, True, 'N',
    'Senior', 4.5, 'D', 'Pascal', 'photo1.png');
  AddPerson(2, 'Maria Gomez', '555-0144', 'Prefers the night shift; speaks three languages.',
    'Support', 9800, 32.5, 1.65, 2, EncodeDate(1995, 11, 2), EncodeDate(2023, 9, 18), 3, True,
    'Y', 'Middle', 3, 'N', 'SQL', 'photo2.png');
  AddPerson(3, 'Kenji Watanabe', '555-0172', 'On leave until next quarter.', 'Finance',
    12750, 20, 1.80, 9, EncodeDate(1979, 7, 30), EncodeDate(2016, 1, 11), 4, False, 'Y',
    'Senior', 5, 'F', 'Python', 'photo3.png');
  { A new hire with nothing filled in yet: every field but ID and Name is NULL, so this row
    shows what each control does with an empty value. }
  FPeople.Append;
  FPeople.FieldByName('ID').AsInteger := 4;
  FPeople.FieldByName('Name').AsString := 'New hire';
  FPeople.Post;
end;

procedure TMainForm.ShowStatus;
var
  st: string;
begin
  case PeopleSrc.State of
    dsInactive: st := rsStateInactive;
    dsBrowse:   st := rsStateBrowse;
    dsEdit:     st := rsStateEdit;
    dsInsert:   st := rsStateInsert;
  else
    st := rsStateOther;
  end;
  if FPeople <> nil then
    LblStatus.Caption := Format(rsStatusFmt, [st, FPeople.RecNo, FPeople.RecordCount])
  else
    LblStatus.Caption := Format(rsStatusFmt, [st, 0, 0]);
end;

procedure TMainForm.PeopleSrcStateChange(Sender: TObject);
begin
  ShowStatus;
end;

procedure TMainForm.PeopleSrcDataChange(Sender: TObject; Field: TField);
begin
  { Field = nil means the record changed (a scroll, a post, a cancel); a single field's edit
    does not move the record number. }
  if Field = nil then ShowStatus;
end;

procedure TMainForm.CbAutoEditChange(Sender: TObject);
begin
  { AutoEdit off: typing in a field no longer puts the table into editing; the navigator's
    Edit button (or DataSet.Edit) has to do it first, and until then a change is put back. }
  PeopleSrc.AutoEdit := CbAutoEdit.Checked;
end;

procedure TMainForm.CbReadOnlyChange(Sender: TObject);
var
  i: Integer;
  c: TComponent;
begin
  { Every data-aware control on the form that has a ReadOnly property. }
  for i := 0 to ComponentCount - 1 do
  begin
    c := Components[i];
    if (Pos('TTyDB', c.ClassName) = 1) and IsPublishedProp(c, 'ReadOnly') then
      SetOrdProp(c, 'ReadOnly', Ord(CbReadOnly.Checked));
  end;
end;

procedure TMainForm.BtnClearPhotoClick(Sender: TObject);
begin
  { An empty picture is written to the field as NULL. Like the choice controls, the image
    writes to the record at once: the table is now editing, and Post (or Cancel) on the
    navigator decides. }
  ImgPhoto.Picture.Clear;
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
