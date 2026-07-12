unit umain;

{ TTyTabSet demo: a pure tab-strip control (no page container); selection = TabIndex + OnChange.
  - Tabs: a TStrings list of tab captions
  - TabIndex: the currently selected tab; initialized to 0 (the first)
  - OnChange: fires after a switch; the status label at the bottom shows the current tab live
  - OnChanging: pre-switch veto hook; demonstrates blocking a jump to a "locked" tab
  - TabsClosable + OnTabClose: the tab header shows a close (×) glyph; veto via AllowClose:=False
  - OnReorder: fires after a drag-reorder is committed; the status label reports from->to
  - TabHeight: height of the tab strip
  The window, the tab strip, the status label and the live theme switcher are designed in
  umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.TabSet, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    TabStrip: TTyTabSet;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure TabChanged(Sender: TObject);
    procedure TabChanging(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean);
    procedure TabClosing(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
    procedure TabReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
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

{ Tab-switch callback: update the status label to show the current tab caption }
procedure TMainForm.TabChanged(Sender: TObject);
begin
  LblStatus.Caption := Format('当前页签：%s（TabIndex=%d）',
    [TabStrip.TabCaption(TabStrip.TabIndex), TabStrip.TabIndex]);
end;

{ Pre-switch veto hook: ANewIndex is the target index of the intended switch; clearing AllowChange aborts it.
  Here we block selecting the 3rd tab (the "locked" one) to demonstrate the veto. }
procedure TMainForm.TabChanging(Sender: TObject; ANewIndex: Integer;
  var AllowChange: Boolean);
begin
  if ANewIndex = 2 then
  begin
    AllowChange := False;
    LblStatus.Caption := '"通知(锁定)"页已被 OnChanging 否决，无法选中。';
  end;
end;

{ Tab-close callback: fires when the close (×) glyph on a tab header is clicked. Allowed by default
  (AllowClose is True on entry); the control then removes the tab from Tabs and fixes up TabIndex.
  Here we veto closing the first tab (the overview tab). }
procedure TMainForm.TabClosing(Sender: TObject; AIndex: Integer;
  var AllowClose: Boolean);
begin
  if AIndex = 0 then
  begin
    AllowClose := False;
    LblStatus.Caption := '"概览"页被 OnTabClose 否决，不予关闭。';
  end
  else
    LblStatus.Caption := Format('正在关闭页签：%s', [TabStrip.TabCaption(AIndex)]);
end;

{ Drag-reorder commit callback: fires once after a clean drag gesture completes }
procedure TMainForm.TabReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
begin
  LblStatus.Caption := Format('页签已重排：%d → %d（当前：%s）',
    [AFromIndex, AToIndex, TabStrip.TabCaption(TabStrip.TabIndex)]);
end;

end.
