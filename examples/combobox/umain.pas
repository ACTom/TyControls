unit umain;

{ TTyComboBox demo:
    Left column csDropDownList (read-only, selection only from the list) -- shows
      Sorted ordering, DropDownCount limiting the visible rows, and keyboard
      type-ahead prefix jumping.
    Right column csDropDown (editable field + prefix auto-complete) -- its Items and
      its initial Text are authored in umain.lfm; typing a prefix pops up the
      filtered candidate list; also demonstrates CharCase (auto-uppercase) and
      MaxLength (length limit).
    A TTyLabel status bar below subscribes to four events:
      OnChange / OnSelect / OnDropDown / OnCloseUp.
    A button drives the list open/closed in code (DropDown / CloseUp / DroppedDown),
      so the same four events fire without the user touching the combo box.
  The window, both combo boxes, their labels, the status bar and the live theme
  switcher are designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is
  the (Sorted-dependent) item population, the event handlers and the theme setup. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Button, tyControls.ComboBox, tyControls.ToggleSwitch, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblList: TTyLabel;
    ListCombo: TTyComboBox;       // csDropDownList (read-only)
    LblEdit: TTyLabel;
    EditCombo: TTyComboBox;       // csDropDown (editable + auto-complete)
    LblStatus: TTyLabel;          // event status bar
    LblApi: TTyLabel;
    BtnToggleList: TTyButton;     // drives ListCombo open/closed in code
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure ComboChange(Sender: TObject);
    procedure ComboSelect(Sender: TObject);
    procedure ComboDropDown(Sender: TObject);
    procedure ComboCloseUp(Sender: TObject);
    procedure BtnToggleListClick(Sender: TObject);
  private
    FLastCloseUp: QWord;   // tick of the last OnCloseUp; see BtnToggleListClick
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

  // EditCombo needs no code: its Items and its initial Text are set in umain.lfm.

  // Restore the initial "waiting" status (setting ItemIndex above fires OnChange)
  LblStatus.Caption := 'Event state: (awaiting action, try expanding or typing a prefix)';
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
    Which := 'Read-only'
  else
    Which := 'Editable';
  LblStatus.Caption := Format('Event state: [%s] %s → Text="%s" (ItemIndex=%d)',
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
  SetStatus('OnDropDown (expand)', Sender as TTyComboBox);
end;

procedure TMainForm.ComboCloseUp(Sender: TObject);
begin
  FLastCloseUp := GetTickCount64;
  SetStatus('OnCloseUp (collapse)', Sender as TTyComboBox);
end;

procedure TMainForm.BtnToggleListClick(Sender: TObject);
begin
  { DroppedDown reports the popup's state; DropDown/CloseUp drive it. Both routes fire
    OnDropDown/OnCloseUp, so the status bar cannot tell a code-driven open from a click.
    The 200 ms guard is the same reopen-race guard the control applies to its own chevron:
    clicking this button while the list is open deactivates the popup, so it has already
    closed (DroppedDown = False) by the time we get here, and a bare else would reopen it. }
  if ListCombo.DroppedDown then
    ListCombo.CloseUp
  else if GetTickCount64 - FLastCloseUp > 200 then
    ListCombo.DropDown;
end;

end.
