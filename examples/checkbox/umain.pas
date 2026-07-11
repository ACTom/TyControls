unit umain;
{$mode objfpc}{$H+}

{ TTyCheckBox demo: a TTyForm + TTyTitleBar shell showcasing the key checkbox features:
  - Tri-state: AllowGrayed=True, clicking cycles through unchecked/checked/grayed, OnChange echoes State
  - Plain two-state checkbox, OnChange echoes Checked
  - Pre-checked (Checked:=True)
  - Disabled (Enabled:=False)
  UI is built entirely in code (no .lfm); controls with no explicit Controller fall back to the global TyDefaultController. }

interface

uses
  Classes, SysUtils, StdCtrls, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.CheckBox, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FTri: TTyCheckBox;
    FTriStatus: TTyLabel;
    FPlain: TTyCheckBox;
    FStatus: TTyLabel;
    procedure TriChange(Sender: TObject);
    procedure PlainChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to locate the repo's themes/ folder }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

function StateName(AState: TCheckBoxState): string;
begin
  case AState of
    cbChecked: Result := '选中 (cbChecked)';
    cbGrayed:  Result := '半选 (cbGrayed)';
  else
    Result := '未选 (cbUnchecked)';
  end;
end;

procedure TMainForm.TriChange(Sender: TObject);
begin
  FTriStatus.Caption := '三态状态：' + StateName(FTri.State);
end;

procedure TMainForm.PlainChange(Sender: TObject);
begin
  if FPlain.Checked then
    FStatus.Caption := '两态状态：已勾选'
  else
    FStatus.Caption := '两态状态：未勾选';
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  Lbl: TTyLabel;
  Cb: TTyCheckBox;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistent engine
  Caption := 'CheckBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 460, 420);
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load theme FIRST

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associates as TTyForm.TitleBar
  Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 34;
  Bar.Caption := 'CheckBox  · TyControls';

  { ---- Tri-state checkbox: AllowGrayed + State cycling ---- }
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(20, 52, 420, 22);
  Lbl.Caption := '三态复选框（点击循环 未选 → 选中 → 半选）：';

  FTri := TTyCheckBox.Create(Self);
  FTri.Parent := Self;
  FTri.SetBounds(24, 78, 280, 24);
  FTri.Caption := '包含全部子项(&A)';
  FTri.AllowGrayed := True;
  FTri.State := cbGrayed;                   // start grayed, to show one of the three states
  FTri.OnChange := @TriChange;

  FTriStatus := TTyLabel.Create(Self);
  FTriStatus.Parent := Self;
  FTriStatus.SetBounds(24, 106, 420, 22);

  { ---- Plain two-state checkbox + OnChange state echo ---- }
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(20, 148, 420, 22);
  Lbl.Caption := '普通两态复选框（OnChange 回显）：';

  FPlain := TTyCheckBox.Create(Self);
  FPlain.Parent := Self;
  FPlain.SetBounds(24, 174, 280, 24);
  FPlain.Caption := '接收邮件通知(&N)';
  FPlain.OnChange := @PlainChange;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 202, 420, 22);

  { ---- Pre-checked (Checked := True) ---- }
  Cb := TTyCheckBox.Create(Self);
  Cb.Parent := Self;
  Cb.SetBounds(24, 244, 280, 24);
  Cb.Caption := '默认已勾选 (Checked)';
  Cb.Checked := True;

  { ---- Disabled ---- }
  Cb := TTyCheckBox.Create(Self);
  Cb.Parent := Self;
  Cb.SetBounds(24, 274, 280, 24);
  Cb.Caption := '禁用且勾选 (Enabled=False)';
  Cb.Checked := True;
  Cb.Enabled := False;

  Cb := TTyCheckBox.Create(Self);
  Cb.Parent := Self;
  Cb.SetBounds(24, 304, 280, 24);
  Cb.Caption := '禁用且未勾选';
  Cb.Enabled := False;

  // prime the status echoes
  TriChange(nil);
  PlainChange(nil);

  ApplyChromeTheme(TyDefaultController);   // theme the whole chrome + form bg LAST
end;

end.
