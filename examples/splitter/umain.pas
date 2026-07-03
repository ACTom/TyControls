unit umain;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, ExtCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.Panel, tyControls.Splitter, tyControls.TyLabel;
type
  TMainForm = class(TTyForm)
  private
    FStatus: TTyLabel;
    FLeftPanel: TTyPanel;
    FTopPanel: TTyPanel;
    FBottomPanel: TTyPanel;
    procedure HandleMoved(Sender: TObject);
    procedure HandleCanResize(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
  end;
var
  MainForm: TMainForm;
implementation

{ up-search for the repo themes/ dir from the exe location }
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

procedure TMainForm.HandleMoved(Sender: TObject);
begin
  FStatus.Caption := Format('拖动完成 · 左栏宽 %d px · 上区高 %d px',
    [FLeftPanel.Width, FTopPanel.Height]);
end;

procedure TMainForm.HandleCanResize(Sender: TObject; var ANewSize: Integer; var AAccept: Boolean);
begin
  // OnCanResize：可在此否决或钳制新尺寸。此处仅作即时预览。
  FStatus.Caption := Format('拖动中 · 目标尺寸 %d px', [ANewSize]);
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  VSplit, HSplit: TTySplitter;
  ClientHost: TTyPanel;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistent engine
  Caption := 'Splitter 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 760, 520);
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load theme FIRST

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associates as TTyForm.TitleBar
  Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 34;
  Bar.Caption := 'Splitter  · TyControls';

  // 底部状态条：显示拖动读数
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.Height := 30;
  FStatus.Alignment := taCenter;
  FStatus.Caption := '拖动竖直分隔条改变左栏宽度；拖动水平分隔条改变上区高度';

  // ClientHost 承载“左栏 + 竖直分隔条 + 右侧客户区”，避开标题栏/状态条
  ClientHost := TTyPanel.Create(Self);
  ClientHost.Parent := Self;
  ClientHost.Align := alClient;
  ClientHost.Caption := '';

  // 左栏（alLeft）
  FLeftPanel := TTyPanel.Create(Self);
  FLeftPanel.Parent := ClientHost;
  FLeftPanel.Align := alLeft;
  FLeftPanel.Width := 220;
  FLeftPanel.Caption := '左栏 (alLeft)';

  // 竖直分隔条（Align=alLeft → 横向拖动，改变左栏宽度）
  VSplit := TTySplitter.Create(Self);
  VSplit.Parent := ClientHost;
  VSplit.Align := alLeft;          // 紧贴左栏右侧
  VSplit.Width := 6;
  VSplit.MinSize := 120;           // 左栏最小宽度
  VSplit.ResizeStyle := rsUpdate;  // 实时更新（另有 rsLine 延迟到松开）
  VSplit.OnMoved := @HandleMoved;
  VSplit.OnCanResize := @HandleCanResize;

  // 右侧客户区：再做一次水平切分（上区 alTop + 分隔条 + 下区 alClient）
  FTopPanel := TTyPanel.Create(Self);
  FTopPanel.Parent := ClientHost;
  FTopPanel.Align := alTop;
  FTopPanel.Height := 200;
  FTopPanel.Caption := '上区 (alTop)';

  HSplit := TTySplitter.Create(Self);
  HSplit.Parent := ClientHost;
  HSplit.Align := alTop;           // 横放 → 纵向拖动，改变上区高度
  HSplit.Height := 6;
  HSplit.MinSize := 80;
  HSplit.ResizeStyle := rsUpdate;
  HSplit.OnMoved := @HandleMoved;

  FBottomPanel := TTyPanel.Create(Self);
  FBottomPanel.Parent := ClientHost;
  FBottomPanel.Align := alClient;
  FBottomPanel.Caption := '下区 (alClient)';

  ApplyChromeTheme(TyDefaultController);   // theme the whole chrome + form bg LAST
end;

end.
