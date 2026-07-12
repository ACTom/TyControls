unit umain;

{ TTySplitter demo -- nested docking: a vertical splitter (Align=alLeft) resizes the left
  column, and a horizontal splitter (Align=alTop) nested in the right container resizes the
  top pane. MinSize clamps, ResizeStyle=rsUpdate gives a live drag, and OnMoved / OnCanResize
  report the drag readout. The window, panels, splitters and the live theme switcher are
  designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme
  setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, ExtCtrls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.Panel, tyControls.Splitter, tyControls.TyLabel, tyControls.ComboBox;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    LblStatus: TTyLabel;
    ClientHost: TTyPanel;
    LeftPanel: TTyPanel;
    VSplit: TTySplitter;
    RightHost: TTyPanel;
    TopPanel: TTyPanel;
    HSplit: TTySplitter;
    BottomPanel: TTyPanel;
    procedure FormCreate(Sender: TObject);
    procedure HandleMoved(Sender: TObject);
    procedure HandleCanResize(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean);
    procedure ThemeComboChange(Sender: TObject);
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

procedure TMainForm.HandleMoved(Sender: TObject);
begin
  LblStatus.Caption := Format('拖动完成 · 左栏宽 %d px · 上区高 %d px',
    [LeftPanel.Width, TopPanel.Height]);
end;

procedure TMainForm.HandleCanResize(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean);
begin
  // OnCanResize: veto or clamp the new size here. This just does a live preview.
  LblStatus.Caption := Format('拖动中 · 目标尺寸 %d px', [ANewSize]);
end;

end.
