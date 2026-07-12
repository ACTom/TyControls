unit umain;

{ TTyComboBox demo:
    Left column csDropDownList (read-only, selection only from the list) -- shows
      Sorted ordering, DropDownCount limiting the visible rows, and keyboard
      type-ahead prefix jumping.
    Right column csDropDown (editable field + prefix auto-complete) -- typing a
      prefix pops up the filtered candidate list; also demonstrates CharCase
      (auto-uppercase) and MaxLength (length limit).
    A TTyLabel status bar below subscribes to four events:
      OnChange / OnSelect / OnDropDown / OnCloseUp.
  The window, both combo boxes, their labels, the status bar and the live theme
  switcher are designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is
  the (Sorted-dependent) item population, the event handlers and the theme setup. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    LblList: TTyLabel;
    ListCombo: TTyComboBox;       // csDropDownList (read-only)
    LblEdit: TTyLabel;
    EditCombo: TTyComboBox;       // csDropDown (editable + auto-complete)
    LblStatus: TTyLabel;          // event status bar
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure ComboChange(Sender: TObject);
    procedure ComboSelect(Sender: TObject);
    procedure ComboDropDown(Sender: TObject);
    procedure ComboCloseUp(Sender: TObject);
  private
    procedure SetStatus(const AEvt: string; ACombo: TTyComboBox);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

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

  // Add 8 items out of order: Sorted=True (set in the .lfm) auto-arranges them ascending
  ListCombo.Items.Add('Guangzhou');
  ListCombo.Items.Add('Beijing');
  ListCombo.Items.Add('Shanghai');
  ListCombo.Items.Add('Chengdu');
  ListCombo.Items.Add('Hangzhou');
  ListCombo.Items.Add('Nanjing');
  ListCombo.Items.Add('Wuhan');
  ListCombo.Items.Add('Xian');
  ListCombo.ItemIndex := 0;            // preselect the first item (Beijing after sorting)

  EditCombo.Items.Add('APPLE');
  EditCombo.Items.Add('APRICOT');
  EditCombo.Items.Add('AVOCADO');
  EditCombo.Items.Add('BANANA');
  EditCombo.Items.Add('BLUEBERRY');
  EditCombo.Items.Add('CHERRY');
  EditCombo.Items.Add('GRAPE');
  EditCombo.Items.Add('MANGO');

  // Restore the initial "waiting" status (setting ItemIndex above fires OnChange)
  LblStatus.Caption := '事件状态：（等待操作，尝试展开或键入前缀）';
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

procedure TMainForm.SetStatus(const AEvt: string; ACombo: TTyComboBox);
var
  Which: string;
begin
  if ACombo = ListCombo then
    Which := '只读'
  else
    Which := '可编辑';
  LblStatus.Caption := Format('事件状态：[%s] %s → Text="%s" (ItemIndex=%d)',
    [Which, AEvt, ACombo.Text, ACombo.ItemIndex]);
end;

procedure TMainForm.ComboChange(Sender: TObject);
begin
  SetStatus('OnChange', Sender as TTyComboBox);
end;

procedure TMainForm.ComboSelect(Sender: TObject);
begin
  SetStatus('OnSelect', Sender as TTyComboBox);
end;

procedure TMainForm.ComboDropDown(Sender: TObject);
begin
  SetStatus('OnDropDown（展开）', Sender as TTyComboBox);
end;

procedure TMainForm.ComboCloseUp(Sender: TObject);
begin
  SetStatus('OnCloseUp（收起）', Sender as TTyComboBox);
end;

end.
