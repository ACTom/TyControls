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
  // OnCanResize: veto or clamp the new size here. This just does a live preview.
  FStatus.Caption := Format('拖动中 · 目标尺寸 %d px', [ANewSize]);
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  VSplit, HSplit: TTySplitter;
  ClientHost, RightHost: TTyPanel;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistent engine
  Caption := 'Splitter 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 760, 520);
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load theme FIRST

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associates as TTyForm.TitleBar
  Bar.Parent := Self; Bar.Align := alTop; Bar.Height := 34;
  Bar.Caption := 'Splitter  · TyControls';

  // Bottom status bar: shows the drag readout
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.Height := 30;
  FStatus.Alignment := taCenter;
  FStatus.Caption := '拖动竖直分隔条改变左栏宽度；拖动水平分隔条改变上区高度';

  // ClientHost holds "left column + vertical splitter + right client area", clear of the title bar/status bar
  ClientHost := TTyPanel.Create(Self);
  ClientHost.Parent := Self;
  ClientHost.Align := alClient;
  ClientHost.Caption := '';

  // ── Vertical split: left column (alLeft) → vertical splitter (alLeft) → right container (alClient) ──
  // In LCL, sibling alLeft controls dock left-to-right in creation/Left order, so the left
  // column must be created and parented before the splitter, and both before the alClient
  // fill block. The splitter's alLeft neighbor lookup requires its Left to fall past the left
  // column's right edge, so we set Left explicitly to the column width to lock the dock order.

  // Left column (alLeft, created first)
  FLeftPanel := TTyPanel.Create(Self);
  FLeftPanel.Parent := ClientHost;
  FLeftPanel.Align := alLeft;
  FLeftPanel.Width := 220;
  FLeftPanel.Caption := '左栏 (alLeft)';

  // Vertical splitter (Align=alLeft → drags horizontally, changing the left column width; sits against the column's right edge)
  VSplit := TTySplitter.Create(Self);
  VSplit.Parent := ClientHost;
  VSplit.Align := alLeft;
  VSplit.Left := FLeftPanel.Width;  // dock explicitly to the column's right edge, so it doesn't land on the left
  VSplit.Width := 6;
  VSplit.MinSize := 120;            // minimum left-column width
  VSplit.ResizeStyle := rsUpdate;   // update live (rsLine instead would defer until release)
  VSplit.OnMoved := @HandleMoved;
  VSplit.OnCanResize := @HandleCanResize;

  // Right container (alClient, created last): hosts the nested horizontal split
  RightHost := TTyPanel.Create(Self);
  RightHost.Parent := ClientHost;
  RightHost.Align := alClient;
  RightHost.Caption := '';

  // ── Nested horizontal split: top pane (alTop) → horizontal splitter (alTop) → bottom pane (alClient) ──
  FTopPanel := TTyPanel.Create(Self);
  FTopPanel.Parent := RightHost;
  FTopPanel.Align := alTop;
  FTopPanel.Height := 200;
  FTopPanel.Caption := '上区 (alTop)';

  HSplit := TTySplitter.Create(Self);
  HSplit.Parent := RightHost;
  HSplit.Align := alTop;            // horizontal bar → drags vertically, changing the top pane height
  HSplit.Top := FTopPanel.Height;  // dock explicitly below the top pane
  HSplit.Height := 6;
  HSplit.MinSize := 80;
  HSplit.ResizeStyle := rsUpdate;
  HSplit.OnMoved := @HandleMoved;

  FBottomPanel := TTyPanel.Create(Self);
  FBottomPanel.Parent := RightHost;
  FBottomPanel.Align := alClient;
  FBottomPanel.Caption := '下区 (alClient)';

  ApplyChromeTheme(TyDefaultController);   // theme the whole chrome + form bg LAST
end;

end.
