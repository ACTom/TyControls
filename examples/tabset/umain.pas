unit umain;

{ TTyTabSet demo: a pure tab-strip control (no page container); selection = TabIndex + OnChange.
  - Tabs: a TStrings list; add each tab caption one by one
  - TabIndex: the currently selected tab; initialized to 0 (the first)
  - OnChange: fires after a switch; the status label at the bottom shows the current tab live
  - OnChanging: pre-switch veto hook; demonstrates blocking a jump to a "locked" tab
  - TabsClosable + OnTabClose: the tab header shows a close (×) glyph; veto via AllowClose:=False
  - OnReorder: fires after a drag-reorder is committed; the status label reports from->to
  - TabHeight: height of the tab strip
  UI is built purely in code (no .lfm); the shell is a TTyForm + TTyTitleBar,
  and the theme is loaded through the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.TabSet, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FTabSet: TTyTabSet;
    FStatus: TTyLabel;
    procedure TabChanged(Sender: TObject);
    procedure TabChanging(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean);
    procedure TabClosing(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
    procedure TabReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
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
  Result := 'themes' + PathDelim; { fallback: relative to the current directory }
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
begin
  inherited CreateNew(AOwner, 0);          { TTyForm: borderless + always-on engine }
  Caption  := 'TTyTabSet 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 520, 220);

  { Load the light theme first; controls with no explicit Controller use the global TyDefaultController automatically }
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);         { Owner=Self -> auto-associated as TTyForm.TitleBar }
  Bar.Parent  := Self;
  Bar.Align   := alTop;
  Bar.Height  := 34;
  Bar.Caption := 'TTyTabSet  · TyControls';

  { ── Tab strip ──────────────────────────────────────────────────────────── }
  FTabSet := TTyTabSet.Create(Self);
  FTabSet.Parent := Self;
  FTabSet.SetBounds(20, 56, 480, 34);
  FTabSet.TabHeight := 32;

  { Tabs: add each caption to the string list; the "notifications (locked)" tab demonstrates the OnChanging veto }
  FTabSet.Tabs.Add('概览');
  FTabSet.Tabs.Add('详情');
  FTabSet.Tabs.Add('通知(锁定)');
  FTabSet.Tabs.Add('设置');
  FTabSet.Tabs.Add('关于');

  FTabSet.TabIndex := 0;                    { select the first tab initially }

  { Closable tabs: a close (×) glyph appears at the right of the tab header; clicking it fires OnTabClose }
  FTabSet.TabsClosable := True;

  FTabSet.OnChange   := @TabChanged;
  FTabSet.OnChanging := @TabChanging;
  FTabSet.OnTabClose := @TabClosing;
  FTabSet.OnReorder  := @TabReordered;      { fires after a drag-reorder }

  { ── Status label ───────────────────────────────────────────────────────── }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent  := Self;
  FStatus.SetBounds(20, 110, 480, 66);
  FStatus.WordWrap := True;
  FStatus.Caption :=
    '当前页签：概览' + LineEnding +
    '提示：点击切换 · 拖拽可重排 · 点 × 关闭 · "通知(锁定)"页禁止选中';

  ApplyChromeTheme(TyDefaultController);    { finally, theme the form shell and background in one pass }
end;

{ Tab-switch callback: update the status label to show the current tab caption }
procedure TMainForm.TabChanged(Sender: TObject);
begin
  FStatus.Caption := Format('当前页签：%s（TabIndex=%d）',
    [FTabSet.TabCaption(FTabSet.TabIndex), FTabSet.TabIndex]);
end;

{ Pre-switch veto hook: ANewIndex is the target index of the intended switch; clearing AllowChange aborts it.
  Here we block selecting the 3rd tab (the "locked" one) to demonstrate the veto. }
procedure TMainForm.TabChanging(Sender: TObject; ANewIndex: Integer;
  var AllowChange: Boolean);
begin
  if ANewIndex = 2 then
  begin
    AllowChange := False;
    FStatus.Caption := '"通知(锁定)"页已被 OnChanging 否决，无法选中。';
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
    FStatus.Caption := '"概览"页被 OnTabClose 否决，不予关闭。';
  end
  else
    FStatus.Caption := Format('正在关闭页签：%s', [FTabSet.TabCaption(AIndex)]);
end;

{ Drag-reorder commit callback: fires once after a clean drag gesture completes }
procedure TMainForm.TabReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
begin
  FStatus.Caption := Format('页签已重排：%d → %d（当前：%s）',
    [AFromIndex, AToIndex, FTabSet.TabCaption(FTabSet.TabIndex)]);
end;

end.
