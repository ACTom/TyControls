unit umain;

{ TTyListBox demo (TTyForm + TTyTitleBar borderless window):
  Highlights:
    - Items / ItemIndex: fill with many items (30 cities); content taller than the
      viewport -> the built-in scrollbar appears automatically. Up/Down keys,
      PageUp/PageDown, Home/End and the mouse wheel all scroll.
    - OnChange: update the bottom TTyLabel status bar whenever the selection changes
      (single-select shows the item text + index, multi-select shows the count).
    - MultiSelect: checkbox toggles single- / multi-select mode (in multi-select,
      Ctrl-click, Shift-range-select and Space toggle).
    - Sorted: checkbox toggles ascending sort (the selected item keeps its selection
      after being repositioned by text).
    - ItemHeight: button toggles the row height between 24 and 32.
    - SelectAll / ClearSelection: select all / clear in multi-select mode.
  The window, the list box, every control and the live theme switcher are designed in
  umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup
  plus the runtime Items population only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ListBox, tyControls.TyLabel, tyControls.Button,
  tyControls.CheckBox, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    LblTitle: TTyLabel;
    ListBox: TTyListBox;
    ChkMulti: TTyCheckBox;
    ChkSorted: TTyCheckBox;
    BtnHeight: TTyButton;
    BtnSelAll: TTyButton;
    BtnClear: TTyButton;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ListBoxChange(Sender: TObject);
    procedure MultiChange(Sender: TObject);
    procedure SortedChange(Sender: TObject);
    procedure ToggleHeight(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoClear(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  private
    procedure UpdateStatus;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
const
  Cities: array[0..29] of string = (
    '北京', '上海', '广州', '深圳', '成都', '杭州', '武汉', '西安',
    '南京', '天津', '重庆', '苏州', '长沙', '郑州', '青岛', '大连',
    '厦门', '宁波', '无锡', '合肥', '福州', '济南', '昆明', '南昌',
    '贵阳', '哈尔滨', '沈阳', '石家庄', '太原', '兰州');
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

  // Fill the list box (30 items, too short to show them all -> the built-in scrollbar
  // appears automatically), then select the first item by default.
  for i := Low(Cities) to High(Cities) do
    ListBox.Items.Add(Cities[i]);
  ListBox.ItemIndex := 0;

  UpdateStatus;   // refresh the status-bar text once all controls are ready
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

procedure TMainForm.UpdateStatus;
begin
  if ListBox.MultiSelect then
    LblStatus.Caption := Format('多选模式：已选 %d 项（Ctrl 点选 / Shift 连选 / 空格切换）',
      [ListBox.SelCount])
  else if ListBox.ItemIndex >= 0 then
    LblStatus.Caption := Format('当前选中：%s（第 %d 项，共 %d 项）',
      [ListBox.Items[ListBox.ItemIndex], ListBox.ItemIndex + 1,
       ListBox.Items.Count])
  else
    LblStatus.Caption := '当前选中：（无）';
end;

procedure TMainForm.ListBoxChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.MultiChange(Sender: TObject);
begin
  ListBox.MultiSelect := ChkMulti.Checked;
  UpdateStatus;
end;

procedure TMainForm.SortedChange(Sender: TObject);
begin
  ListBox.Sorted := ChkSorted.Checked;
  UpdateStatus;
end;

procedure TMainForm.ToggleHeight(Sender: TObject);
begin
  if ListBox.ItemHeight = 24 then
    ListBox.ItemHeight := 32
  else
    ListBox.ItemHeight := 24;
end;

procedure TMainForm.DoSelectAll(Sender: TObject);
begin
  ListBox.SelectAll;   // only effective in multi-select mode
  UpdateStatus;
end;

procedure TMainForm.DoClear(Sender: TObject);
begin
  ListBox.ClearSelection;   // only effective in multi-select mode
  UpdateStatus;
end;

end.
