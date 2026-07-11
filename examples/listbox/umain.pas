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
  UI built purely in code (no .lfm); the theme is loaded via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.ListBox, tyControls.TyLabel, tyControls.Button,
  tyControls.CheckBox;

type
  TMainForm = class(TTyForm)
  private
    FListBox: TTyListBox;
    FStatus: TTyLabel;
    FChkMulti: TTyCheckBox;
    FChkSorted: TTyCheckBox;
    FBtnHeight: TTyButton;
    FBtnSelAll: TTyButton;
    FBtnClear: TTyButton;
    procedure ListBoxChange(Sender: TObject);
    procedure MultiChange(Sender: TObject);
    procedure SortedChange(Sender: TObject);
    procedure ToggleHeight(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoClear(Sender: TObject);
    procedure UpdateStatus;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to find the repo's themes/ folder (handles lib/<cpu>-<os>/ and .app bundles) }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  LblTitle: TTyLabel;
  Cities: array[0..29] of string = (
    '北京', '上海', '广州', '深圳', '成都', '杭州', '武汉', '西安',
    '南京', '天津', '重庆', '苏州', '长沙', '郑州', '青岛', '大连',
    '厦门', '宁波', '无锡', '合肥', '福州', '济南', '昆明', '南昌',
    '贵阳', '哈尔滨', '沈阳', '石家庄', '太原', '兰州');
  i: Integer;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistence engine
  Caption := 'TTyListBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 420, 420);

  // Load the theme first: controls without an explicit Controller use the global TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'ListBox  · TyControls';

  LblTitle := TTyLabel.Create(Self);
  LblTitle.Parent := Self;
  LblTitle.SetBounds(16, 46, 388, 20);
  LblTitle.Caption := '城市列表（上下键 / PageUp/Down / 滚轮可滚动）：';

  // Bottom status bar: must be created before wiring FListBox.OnChange / assigning ItemIndex,
  // otherwise setting ItemIndex fires OnChange -> UpdateStatus touches the not-yet-created FStatus -> crash
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 376, 388, 20);

  // List box: 30 items, too short to show them all -> the built-in scrollbar appears automatically
  FListBox := TTyListBox.Create(Self);
  FListBox.Parent := Self;
  FListBox.SetBounds(16, 70, 388, 220);
  FListBox.ItemHeight := 24;
  FListBox.OnChange := @ListBoxChange;
  for i := Low(Cities) to High(Cities) do
    FListBox.Items.Add(Cities[i]);
  FListBox.ItemIndex := 0;                  // select the first item by default

  // Multi-select / sort checkboxes
  FChkMulti := TTyCheckBox.Create(Self);
  FChkMulti.Parent := Self;
  FChkMulti.SetBounds(16, 300, 130, 24);
  FChkMulti.Caption := '多选模式';
  FChkMulti.OnChange := @MultiChange;

  FChkSorted := TTyCheckBox.Create(Self);
  FChkSorted.Parent := Self;
  FChkSorted.SetBounds(150, 300, 130, 24);
  FChkSorted.Caption := '升序排序';
  FChkSorted.OnChange := @SortedChange;

  // Row-height toggle / select-all / clear buttons
  FBtnHeight := TTyButton.Create(Self);
  FBtnHeight.Parent := Self;
  FBtnHeight.SetBounds(16, 332, 120, 30);
  FBtnHeight.Caption := '行高 24 / 32';
  FBtnHeight.OnClick := @ToggleHeight;

  FBtnSelAll := TTyButton.Create(Self);
  FBtnSelAll.Parent := Self;
  FBtnSelAll.SetBounds(146, 332, 120, 30);
  FBtnSelAll.Caption := '全选';
  FBtnSelAll.OnClick := @DoSelectAll;

  FBtnClear := TTyButton.Create(Self);
  FBtnClear.Parent := Self;
  FBtnClear.SetBounds(276, 332, 120, 30);
  FBtnClear.Caption := '清空选择';
  FBtnClear.OnClick := @DoClear;

  // Refresh the status-bar text once all controls are ready (FStatus was created earlier)
  UpdateStatus;

  ApplyChromeTheme(TyDefaultController);    // finally theme the form chrome + background together
end;

procedure TMainForm.UpdateStatus;
begin
  if FListBox.MultiSelect then
    FStatus.Caption := Format('多选模式：已选 %d 项（Ctrl 点选 / Shift 连选 / 空格切换）',
      [FListBox.SelCount])
  else if FListBox.ItemIndex >= 0 then
    FStatus.Caption := Format('当前选中：%s（第 %d 项，共 %d 项）',
      [FListBox.Items[FListBox.ItemIndex], FListBox.ItemIndex + 1,
       FListBox.Items.Count])
  else
    FStatus.Caption := '当前选中：（无）';
end;

procedure TMainForm.ListBoxChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.MultiChange(Sender: TObject);
begin
  FListBox.MultiSelect := FChkMulti.Checked;
  UpdateStatus;
end;

procedure TMainForm.SortedChange(Sender: TObject);
begin
  FListBox.Sorted := FChkSorted.Checked;
  UpdateStatus;
end;

procedure TMainForm.ToggleHeight(Sender: TObject);
begin
  if FListBox.ItemHeight = 24 then
    FListBox.ItemHeight := 32
  else
    FListBox.ItemHeight := 24;
end;

procedure TMainForm.DoSelectAll(Sender: TObject);
begin
  FListBox.SelectAll;   // only effective in multi-select mode
  UpdateStatus;
end;

procedure TMainForm.DoClear(Sender: TObject);
begin
  FListBox.ClearSelection;   // only effective in multi-select mode
  UpdateStatus;
end;

end.
