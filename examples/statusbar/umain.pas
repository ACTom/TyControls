unit umain;

{ TTyStatusBar demo:
  - Bottom status bar (Align=alBottom) with multiple Panels (each panel has Text/Width/Alignment)
  - A panel with Width <=0 auto-fills the remaining space (fill panel)
  - SizeGrip -- bottom-right resize handle
  - SimplePanel/SimpleText: switch to a single full-width text mode
  - Clicking a button updates a panel's text (multi-panel mode) or the whole-bar text (simple mode)
  UI built entirely in code (no .lfm); the shell is TTyForm + TTyTitleBar, themed via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.StatusBar, tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FBar: TTyStatusBar;
    FClicks: Integer;
    procedure UpdatePanel(Sender: TObject);       // update the left panel's text
    procedure ToggleSimple(Sender: TObject);      // toggle SimplePanel mode
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
  HintLbl: TTyLabel;
  BtnUpdate, BtnSimple: TTyButton;
  P: TTyStatusPanel;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + resident engine
  Caption := 'TTyStatusBar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 520, 320);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyStatusBar  · TyControls';

  // description label
  HintLbl := TTyLabel.Create(Self);
  HintLbl.Parent := Self;
  HintLbl.SetBounds(24, 56, 472, 24);
  HintLbl.Caption := '底部状态栏:多面板 + 尺寸手柄。点击按钮更新面板文本。';

  // bottom status bar -- three fixed panels + one auto-filling fill panel.
  FBar := TTyStatusBar.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alBottom;                   // dock to the bottom (alBottom is already the default)
  FBar.Height := 24;
  FBar.SizeGrip := True;                     // bottom-right resize handle

  P := FBar.Panels.Add;                      // panel 0: status (fill; Width<=0 stretches over the remaining space)
  P.Text := '就绪';
  P.Width := 0;                              // fill panel
  P.Alignment := taLeftJustify;

  P := FBar.Panels.Add;                      // panel 1: click count (centered, fixed width)
  P.Text := '点击:0';
  P.Width := 110;
  P.Alignment := taCenter;

  P := FBar.Panels.Add;                      // panel 2: right-aligned label (fixed width)
  P.Text := 'TyControls';
  P.Width := 110;
  P.Alignment := taRightJustify;

  // action buttons
  BtnUpdate := TTyButton.Create(Self);
  BtnUpdate.Parent := Self;
  BtnUpdate.SetBounds(24, 100, 200, 34);
  BtnUpdate.Caption := '更新状态面板';
  BtnUpdate.StyleClass := 'primary';
  BtnUpdate.OnClick := @UpdatePanel;

  BtnSimple := TTyButton.Create(Self);
  BtnSimple.Parent := Self;
  BtnSimple.SetBounds(24, 144, 200, 34);
  BtnSimple.Caption := '切换 SimplePanel 模式';
  BtnSimple.OnClick := @ToggleSimple;

  ApplyChromeTheme(TyDefaultController);   // finally, theme the form shell and background together
end;

procedure TMainForm.UpdatePanel(Sender: TObject);
begin
  Inc(FClicks);
  if FBar.SimplePanel then
    // simple mode: update the whole-bar text (SetSimpleText triggers a repaint)
    FBar.SimpleText := Format('SimplePanel 模式 · 已点击 %d 次', [FClicks])
  else
  begin
    // multi-panel mode: update the fill panel and the count panel separately
    FBar.Panels[0].Text := Format('已更新 · %s', [FormatDateTime('hh:nn:ss', Now)]);
    FBar.Panels[1].Text := Format('点击:%d', [FClicks]);
  end;
end;

procedure TMainForm.ToggleSimple(Sender: TObject);
begin
  FBar.SimplePanel := not FBar.SimplePanel;   // switch between multi-panel and whole-bar text
  if FBar.SimplePanel then
    FBar.SimpleText := 'SimplePanel:单一整条状态文本'
  else
    FBar.Panels[0].Text := '就绪';
end;

end.
