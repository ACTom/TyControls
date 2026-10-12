unit umain;

{ The data-aware grid (TTyDBGrid) on an in-memory table of a thousand orders. The window, the
  grid with its design-time columns, the navigator and the data sources are designed in
  umain.lfm; the code builds the two tables (TBufDataset needs no database server or file),
  gives the fields their titles and handles the tool row.

  Things to try: scroll with the wheel, the keys or the bar -- the grid only ever holds one
  screen of records; type in a cell (the record goes into editing, the indicator shows it) and
  leave the row to post it, Esc to take it back; Down past the last order adds one; tick a box
  in the Paid column; pick a city from the list (a lookup field: the order's CityID changes);
  click a title to sort by that column (the table does the sorting, through IndexFieldNames);
  Ctrl+click or Shift+arrow to select several orders and delete them in one go; turn Read only
  on. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Forms, Dialogs, DB, BufDataset,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Dialogs,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.CheckBox,
  tyControls.DB.Navigator, tyControls.DB.Grid;

type

  { TMainForm }

  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    OrdersSrc: TDataSource;
    Navigator: TTyDBNavigator;
    BtnDeleteSelected: TTyButton;
    CbReadOnly: TTyCheckBox;
    Grid: TTyDBGrid;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure OrdersSrcStateChange(Sender: TObject);
    procedure OrdersSrcDataChange(Sender: TObject; Field: TField);
    procedure BtnDeleteSelectedClick(Sender: TObject);
    procedure CbReadOnlyChange(Sender: TObject);
    procedure GridTitleClick(Column: TTyDBGridColumn);
    procedure GridMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure GridKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    FOrders: TBufDataset;
    FCities: TBufDataset;
    FSortField: string;
    procedure BuildTables;
    procedure ShowTitles;
    procedure ShowStatus;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsStatusFmt     = 'State: %s  ·  order %d of %d  ·  %d selected  ·  sorted by %s';
  rsStateInactive = 'closed';
  rsStateBrowse   = 'browsing';
  rsStateEdit     = 'editing';
  rsStateInsert   = 'inserting';
  rsStateOther    = 'busy';
  rsTitleID       = 'No.';
  rsTitleCustomer = 'Customer';
  rsTitleCity     = 'City';
  rsTitleDate     = 'Ordered';
  rsTitleAmount   = 'Amount';
  rsTitlePaid     = 'Paid';
  rsTitleNote     = 'Note';
  rsDeleteFmt     = 'Delete the %d selected orders?';
  rsNothingSelected = 'Select orders first: Ctrl+click, or Shift+Up / Shift+Down.';

const
  CCustomers: array[0..11] of string = (
    'Acme Trading', 'Blue River Foods', 'Cedar & Pine', 'Delta Office Supply',
    'Evergreen Books', 'Fjord Fisheries', 'Golden Gate Tea', 'Harbor Hardware',
    'Iris Florists', 'Juniper Studio', 'Kite & Co.', 'Lotus Garden');
  CNotes: array[0..3] of string = (
    'Deliver after 5 pm.', 'Gift wrap, no invoice in the box.',
    'Call before delivery.', 'Second floor, side entrance.');

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
  FSortField := 'ID';
  ShowTitles;
  OrdersSrc.DataSet := FOrders;
  FOrders.First;
  ShowStatus;
end;

procedure TMainForm.BuildTables;

  function AddField(AClass: TFieldClass; const AName: string; ASize: Integer = 0): TField;
  begin
    Result := AClass.Create(FOrders);
    Result.FieldName := AName;
    if ASize > 0 then Result.Size := ASize;
    Result.DataSet := FOrders;
  end;

var
  city: TField;
  i: Integer;
begin
  FCities := TBufDataset.Create(Self);
  FCities.FieldDefs.Add('ID', ftInteger);
  FCities.FieldDefs.Add('Name', ftString, 20);
  FCities.CreateDataset;                   // also opens it
  FCities.AppendRecord([1, 'Shanghai']);
  FCities.AppendRecord([2, 'Beijing']);
  FCities.AppendRecord([3, 'Shenzhen']);
  FCities.AppendRecord([4, 'Hangzhou']);
  FCities.AppendRecord([5, 'Chengdu']);
  FCities.AppendRecord([6, 'Xi''an']);
  FCities.First;

  { The fields are made one by one rather than from FieldDefs: City is a lookup field, which
    only exists as a field object (the grid edits it as a list of the city names and writes
    the chosen city's ID into CityID). }
  FOrders := TBufDataset.Create(Self);
  AddField(TIntegerField, 'ID');
  AddField(TStringField, 'Customer', 30);
  AddField(TIntegerField, 'CityID').Visible := False;
  city := AddField(TStringField, 'City', 20);
  city.FieldKind := fkLookup;
  city.LookupDataSet := FCities;
  city.KeyFields := 'CityID';
  city.LookupKeyFields := 'ID';
  city.LookupResultField := 'Name';
  AddField(TDateField, 'OrderDate');
  AddField(TFloatField, 'Amount');
  AddField(TBooleanField, 'Paid');
  AddField(TMemoField, 'Note');
  FOrders.CreateDataset;                   // also opens it

  { A thousand orders, the same every run. }
  RandSeed := 20261012;
  FOrders.DisableControls;
  try
    for i := 1 to 1000 do
    begin
      FOrders.Append;
      FOrders.FieldByName('ID').AsInteger := i;
      FOrders.FieldByName('Customer').AsString := CCustomers[Random(Length(CCustomers))];
      FOrders.FieldByName('CityID').AsInteger := 1 + Random(6);
      FOrders.FieldByName('OrderDate').AsDateTime := EncodeDate(2026, 1, 1) + Random(280);
      FOrders.FieldByName('Amount').AsFloat := Round(Random * 500000) / 100;
      FOrders.FieldByName('Paid').AsBoolean := Random(4) > 0;
      if i mod 9 = 0 then
        FOrders.FieldByName('Note').AsString := CNotes[(i div 9) mod Length(CNotes)];
      FOrders.Post;
    end;
  finally
    FOrders.EnableControls;
  end;
end;

{ A column's title is its field's DisplayLabel (the columns in umain.lfm set none of their
  own), so the titles are translated resourcestrings; the column the table is sorted by
  carries a mark. }
procedure TMainForm.ShowTitles;

  procedure Title(const AField, AText: string);
  var
    f: TField;
  begin
    f := FOrders.FindField(AField);
    if f = nil then Exit;
    if SameText(AField, FSortField) then
      f.DisplayLabel := AText + ' ▲'
    else
      f.DisplayLabel := AText;
  end;

begin
  Title('ID', rsTitleID);
  Title('Customer', rsTitleCustomer);
  Title('City', rsTitleCity);
  Title('OrderDate', rsTitleDate);
  Title('Amount', rsTitleAmount);
  Title('Paid', rsTitlePaid);
  Title('Note', rsTitleNote);
end;

procedure TMainForm.GridTitleClick(Column: TTyDBGridColumn);
var
  f: TField;
begin
  { The grid does not sort: its rows are a window onto the table. The table sorts --
    TBufDataset by an index on the field (a SQL query would change its ORDER BY). A lookup or
    a memo field has no index to sort by. }
  f := Column.Field;
  if (f = nil) or (f.FieldKind <> fkData) or f.IsBlob then Exit;
  FSortField := f.FieldName;
  FOrders.IndexFieldNames := FSortField;
  ShowTitles;
  ShowStatus;
end;

procedure TMainForm.BtnDeleteSelectedClick(Sender: TObject);
begin
  if Grid.SelectedRows.Count = 0 then
  begin
    TyMessageDlg(rsNothingSelected, mtInformation, [mbOK], 0);
    Exit;
  end;
  if TyMessageDlg(Format(rsDeleteFmt, [Grid.SelectedRows.Count]), mtConfirmation,
    [mbOK, mbCancel], 0) <> mrOK then Exit;
  Grid.SelectedRows.Delete;
  ShowStatus;
end;

procedure TMainForm.CbReadOnlyChange(Sender: TObject);
begin
  { The grid stops editing, inserting and deleting; the table itself is untouched, so the
    navigator can still change it. }
  Grid.ReadOnly := CbReadOnly.Checked;
end;

procedure TMainForm.ShowStatus;
var
  st, sorted: string;
  c: TTyDBGridColumn;
begin
  case OrdersSrc.State of
    dsInactive: st := rsStateInactive;
    dsBrowse:   st := rsStateBrowse;
    dsEdit:     st := rsStateEdit;
    dsInsert:   st := rsStateInsert;
  else
    st := rsStateOther;
  end;
  sorted := FSortField;
  c := Grid.Columns.ColumnByFieldName(FSortField);
  if (c <> nil) and (c.Field <> nil) then sorted := c.Field.DisplayLabel;
  if FOrders <> nil then
    LblStatus.Caption := Format(rsStatusFmt,
      [st, FOrders.RecNo, FOrders.RecordCount, Grid.SelectedRows.Count, sorted])
  else
    LblStatus.Caption := Format(rsStatusFmt, [st, 0, 0, 0, sorted]);
end;

procedure TMainForm.OrdersSrcStateChange(Sender: TObject);
begin
  ShowStatus;
end;

procedure TMainForm.OrdersSrcDataChange(Sender: TObject; Field: TField);
begin
  if Field = nil then ShowStatus;
end;

procedure TMainForm.GridMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  ShowStatus;   // a click may have changed the selection
end;

procedure TMainForm.GridKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  ShowStatus;   // so may Shift+arrow
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
