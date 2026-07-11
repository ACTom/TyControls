unit umain;

{ TTyButton demo:
  - StyleClass variants: default / primary / danger / ghost
  - Down (:selected sticky checked state, toggled by click)
  - badge ShowBadge / BadgeValue / BadgePosition (>99 shows 99+)
  - Default (triggered by Enter) / Cancel (triggered by Esc) / ModalResult
  - & mnemonics (Alt+letter activation)
  - Enabled disabled state
  - OnClick reported to the status label
  UI is built purely in code (no .lfm); the shell is a TTyForm + TTyTitleBar, with the theme loaded via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FCount: Integer;
    FStatus: TTyLabel;
    procedure ButtonClicked(Sender: TObject);
    procedure GhostToggle(Sender: TObject);   // click toggles the ghost button's checked state
    procedure DefaultClicked(Sender: TObject);
    procedure CancelClicked(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to find the repo's themes/ directory (handles lib/<cpu>-<os>/ and .app bundles) }
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

  function AddButton(const ACaption, AStyleClass: string;
    ALeft, ATop: Integer): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(ALeft, ATop, 168, 32);
    Result.Caption := ACaption;
    Result.StyleClass := AStyleClass;   // maps to TyButton.<variant> in the .tycss
    Result.OnClick := @ButtonClicked;
  end;

var
  Bar: TTyTitleBar;
  B: TTyButton;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + resident engine
  Caption := 'TTyButton 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 460, 420);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyButton  · TyControls';

  // Left column: StyleClass variants + disabled state. The & prefix = mnemonic (Alt+letter triggers).
  AddButton('默认按钮(&D)', '', 24, 52);
  AddButton('主要按钮(&P)', 'primary', 24, 92);   // TyButton.primary
  AddButton('危险按钮(&X)', 'danger', 24, 132);   // TyButton.danger

  B := AddButton('禁用按钮', 'primary', 24, 172);
  B.Enabled := False;                     // :disabled (the theme usually dims it via opacity)

  // Left column: Ghost (transparent) + checked state -- transparent normally, only showing a border/fill on hover/click/checked.
  B := TTyButton.Create(Self);
  B.Parent := Self;
  B.SetBounds(24, 212, 168, 32);
  B.Caption := 'Ghost / 选中';
  B.StyleClass := 'ghost';                 // TyButton.ghost
  B.Down := True;                          // sticky checked (:selected)
  B.OnClick := @GhostToggle;               // click toggles checked

  // Right column: numeric badges -- different corners, >99 shows 99+, styling driven by the TyBadge theme keys.
  B := TTyButton.Create(Self);
  B.Parent := Self;
  B.SetBounds(256, 52, 168, 32);
  B.Caption := '消息';
  B.ShowBadge := True;
  B.BadgeValue := 128;                     // shows "99+"
  B.BadgePosition := bpTopRight;
  B.OnClick := @ButtonClicked;

  B := TTyButton.Create(Self);
  B.Parent := Self;
  B.SetBounds(256, 92, 168, 32);
  B.Caption := '通知';
  B.ShowBadge := True;
  B.BadgeValue := 3;
  B.BadgePosition := bpBottomRight;
  B.OnClick := @ButtonClicked;

  // Right column: Default / Cancel / ModalResult -- Enter triggers Default, Esc triggers Cancel.
  B := AddButton('确定(回车)', 'primary', 256, 132);
  B.Default := True;                       // activated by the form's Enter key
  B.ModalResult := mrOk;                   // sets Form.ModalResult when modal
  B.OnClick := @DefaultClicked;

  B := AddButton('取消(Esc)', '', 256, 172);
  B.Cancel := True;                        // activated by the form's Esc key
  B.ModalResult := mrCancel;
  B.OnClick := @CancelClicked;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 356, 412, 24);
  FStatus.Caption := '点击次数:0';

  ApplyChromeTheme(TyDefaultController);   // finally theme the form shell and background together
end;

procedure TMainForm.ButtonClicked(Sender: TObject);
begin
  Inc(FCount);
  FStatus.Caption := Format('点击次数:%d(%s)',
    [FCount, (Sender as TTyButton).Caption]);
end;

procedure TMainForm.GhostToggle(Sender: TObject);
begin
  with Sender as TTyButton do
    Down := not Down;   // toggle the sticky checked state
  ButtonClicked(Sender);
end;

procedure TMainForm.DefaultClicked(Sender: TObject);
begin
  Inc(FCount);
  FStatus.Caption := Format('点击次数:%d(默认按钮 · 回车/ModalResult=mrOk)', [FCount]);
end;

procedure TMainForm.CancelClicked(Sender: TObject);
begin
  Inc(FCount);
  FStatus.Caption := Format('点击次数:%d(取消按钮 · Esc/ModalResult=mrCancel)', [FCount]);
end;

end.
