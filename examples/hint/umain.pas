unit umain;

{ 提示示例:TTyHint(主题化 tooltip,全应用生效)+ TTyBalloonHint(带指针气泡)。
  主窗体 TTyForm + TTyTitleBar;纯代码创建(无 .lfm)。
  把鼠标悬停到按钮上看主题化 tooltip;点“显示气泡”看带指针的气泡标注。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.TyLabel, tyControls.Button, tyControls.Hint, tyControls.BalloonHint;

type
  TMainForm = class(TTyForm)
  private
    FBalloon: TTyBalloonHint;
    FBalloonBtn: TTyButton;
    procedure ShowBalloon(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

function ThemesDir: string;
var Dir: string; i: Integer;
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

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  Lbl: TTyLabel;
  Save, Del: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Hint 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 440, 280);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'Hint  · TyControls';

  // Install the app-wide themed tooltip. Every control's Hint now uses it.
  TTyHint.Create(Self);

  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(24, 52, 392, 24);
  Lbl.Caption := '悬停按钮看主题化 tooltip;点“显示气泡”看带指针气泡。';

  Save := TTyButton.Create(Self);
  Save.Parent := Self;
  Save.SetBounds(24, 92, 120, 34);
  Save.Caption := '保存';
  Save.Hint := '保存当前文档 (Ctrl+S)';
  Save.ShowHint := True;

  Del := TTyButton.Create(Self);
  Del.Parent := Self;
  Del.SetBounds(160, 92, 120, 34);
  Del.Caption := '删除';
  Del.Hint := '删除选中项' + LineEnding + '此操作不可撤销';
  Del.ShowHint := True;

  FBalloonBtn := TTyButton.Create(Self);
  FBalloonBtn.Parent := Self;
  FBalloonBtn.SetBounds(24, 150, 160, 34);
  FBalloonBtn.Caption := '显示气泡';
  FBalloonBtn.OnClick := @ShowBalloon;

  FBalloon := TTyBalloonHint.Create(Self);
  FBalloon.Title := '已保存';
  FBalloon.Description := '文档已写入磁盘。';
  FBalloon.Icon := biInfo;

  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.ShowBalloon(Sender: TObject);
begin
  FBalloon.ShowFor(FBalloonBtn);
end;

end.
