unit umain;

{ TTyListBox demo (TTyForm + TTyTitleBar borderless window):
  Highlights:
    - Items / ItemIndex: fill with many items (30 cities); content taller than the
      viewport -> the built-in scrollbar appears automatically. Up/Down keys,
      PageUp/PageDown, Home/End and the mouse wheel all scroll.
    - OnChange: update the bottom TTyLabel status bar whenever the selection changes
      (single-select shows the item text + index, multi-select the count + names).
    - MultiSelect: checkbox toggles single- / multi-select mode (in multi-select,
      Ctrl-click, Shift-range-select and Space toggle).
    - Sorted: checkbox toggles ascending sort (the selected item keeps its selection
      after being repositioned by text).
    - ItemHeight: left unset it follows the theme's --item-height density metric;
      the button PINS it to 24 / 32 (after which the theme no longer moves it).
    - SelectAll / ClearSelection: select all / clear in multi-select mode.
    - TopIndex: a button scrolls the viewport to row 20 without touching the selection.
    - Selected[]: a button writes an every-other-row selection, and the status bar
      reads the same indexed property back to name what is selected.
    - OnDblClick: double-clicking a row 'activates' it (the classic listbox idiom).
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
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblTitle: TTyLabel;
    ListBox: TTyListBox;
    ChkMulti: TTyCheckBox;
    ChkSorted: TTyCheckBox;
    BtnHeight: TTyButton;
    BtnSelAll: TTyButton;
    BtnClear: TTyButton;
    BtnScroll: TTyButton;      // TopIndex: programmatic scrolling
    BtnWide: TTyButton;        // ScrollWidth: the horizontal bar
    BtnAlternate: TTyButton;   // Selected[]: programmatic per-item selection
    LblHint: TTyLabel;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ListBoxChange(Sender: TObject);
    procedure MultiChange(Sender: TObject);
    procedure SortedChange(Sender: TObject);
    procedure ToggleHeight(Sender: TObject);
    procedure DoSelectAll(Sender: TObject);
    procedure DoClear(Sender: TObject);
    procedure DoScroll(Sender: TObject);
    procedure DoWide(Sender: TObject);
    procedure DoAlternate(Sender: TObject);
    procedure ListBoxDblClick(Sender: TObject);
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
    'Beijing', 'Shanghai', 'Guangzhou', 'Shenzhen', 'Chengdu', 'Hangzhou', 'Wuhan', 'Xi''an',
    'Nanjing', 'Tianjin', 'Chongqing', 'Suzhou', 'Changsha', 'Zhengzhou', 'Qingdao', 'Dalian',
    'Xiamen', 'Ningbo', 'Wuxi', 'Hefei', 'Fuzhou', 'Jinan', 'Kunming', 'Nanchang',
    'Guiyang', 'Harbin', 'Shenyang', 'Shijiazhuang', 'Taiyuan', 'Lanzhou');
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
var
  i, shown: Integer;
  names: string;
begin
  if ListBox.MultiSelect then
  begin
    { SelCount says HOW MANY; Selected[i] says WHICH — the read side of the same indexed
      property DoAlternate writes. Only the first four names are spelled out. }
    names := '';
    shown := 0;
    for i := 0 to ListBox.Items.Count - 1 do
      if ListBox.Selected[i] then
      begin
        Inc(shown);
        if shown <= 4 then
        begin
          if names <> '' then names := names + ', ';
          names := names + ListBox.Items[i];
        end;
      end;
    if shown > 4 then names := names + ', …';
    if names = '' then names := '(none)';
    LblStatus.Caption := Format('Multi-select: %d selected — %s', [ListBox.SelCount, names]);
  end
  else if ListBox.ItemIndex >= 0 then
    LblStatus.Caption := Format('Currently selected: %s (item %d of %d)',
      [ListBox.Items[ListBox.ItemIndex], ListBox.ItemIndex + 1,
       ListBox.Items.Count])
  else
    LblStatus.Caption := 'Currently selected: (none)';
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
  { The FIRST press pins ItemHeight for good: until then the row height is whatever the
    active theme's --item-height metric says (24 classic / 38 modern), so switching skin
    before pressing this shows the density axis moving on its own. }
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

procedure TMainForm.DoScroll(Sender: TObject);
begin
  { TopIndex is the first VISIBLE row: scrolling without touching the selection. The
    control clamps the value to MaxTopIndex (Items.Count - VisibleRows), so it can never
    scroll past the end, and it syncs the built-in scrollbar to the new position. }
  ListBox.TopIndex := 20;
end;

procedure TMainForm.DoWide(Sender: TObject);
begin
  { ScrollWidth is the CONTENT width in logical px -- the number you set, not one measured
    from the items (LCL's semantics). Exceed the box and a horizontal bar appears along the
    bottom; the row area keeps its own width and the rows slide under it.

    Worth demonstrating rather than only unit-testing: where that bar actually ENDS UP is
    the LCL align engine's decision, and a headless test never runs the align engine at
    all (an unshown form leaves the whole tree unaligned). This button is the only place
    the placement gets checked by anyone. }
  if ListBox.ScrollWidth = 0 then
    ListBox.ScrollWidth := 700
  else
    ListBox.ScrollWidth := 0;
  UpdateStatus;
end;

procedure TMainForm.DoAlternate(Sender: TObject);
var
  i: Integer;
begin
  { Selected[] is writable as well as readable. It only holds per item in multi-select
    mode, so switch the mode first (which also clears any stale bits). }
  ChkMulti.Checked := True;   // -> MultiChange -> ListBox.MultiSelect := True
  for i := 0 to ListBox.Items.Count - 1 do
    ListBox.Selected[i] := (i mod 2 = 0);
  UpdateStatus;
end;

procedure TMainForm.ListBoxDblClick(Sender: TObject);
begin
  { Single click selects, DOUBLE click activates — the idiom every listbox user expects.
    OnDblClick comes from the shared TTy control base, so every control has it. }
  if ListBox.ItemIndex >= 0 then
    LblStatus.Caption := Format('Double-clicked (activate): %s',
      [ListBox.Items[ListBox.ItemIndex]]);
end;

end.
