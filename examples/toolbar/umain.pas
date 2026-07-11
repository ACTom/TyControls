unit umain;

{ TTyToolBar + TTyToolSeparator demo:
  - alTop top toolbar holding several TTyButton tool buttons (the toolbar rewrites Flat buttons into the ghost variant)
  - TTyToolSeparator inserts a vertical divider between button groups
  - ButtonHeight / ButtonSpacing / Indent control button size and layout
  - Flat (flat/ghost) . Wrapable (auto-wrap when too wide; toolbar grows taller as the row count changes)
  - each tool button's OnClick reports to the bottom TTyLabel status label
  UI is built purely in code (no .lfm); the shell is TTyForm + TTyTitleBar, with the theme loaded via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.ToolBar, tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FStatus: TTyLabel;
    procedure ToolClicked(Sender: TObject);
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

  { Add a tool button to the toolbar. Parent=toolbar -> the toolbar handles layout and the ghost variant. }
  function AddTool(ABar: TTyToolBar; const ACaption: string; AWidth: Integer): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := ABar;
    Result.Width := AWidth;   { height is governed uniformly by the toolbar's ButtonHeight }
    Result.Caption := ACaption;
    Result.OnClick := @ToolClicked;
  end;

var
  Bar: TTyTitleBar;
  ToolBar: TTyToolBar;
  Sep: TTyToolSeparator;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + resident engine
  Caption := 'TTyToolBar 示例';
  Position := poScreenCenter;
  // Deliberately pick a narrow width: 6+ 72px tool buttons won't fit on one row,
  // triggering Wrapable auto-wrap so the toolbar grows with the row count (the core feature on show).
  SetBounds(0, 0, 360, 340);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyToolBar  · TyControls';

  // Top toolbar: alTop sits right below the title bar and grows taller with the row count.
  ToolBar := TTyToolBar.Create(Self);
  ToolBar.Parent := Self;
  ToolBar.Align := alTop;          // alTop is the default; stated explicitly here (self-documenting)
  ToolBar.Top := 34;               // positioned below the title bar
  ToolBar.Flat := True;            // flat tool buttons (child buttons rewritten to the ghost variant; True by default, stated explicitly)
  ToolBar.Wrapable := True;        // auto-wrap when width is insufficient; more rows makes the toolbar taller (deliberately shown here)
  ToolBar.ButtonHeight := 28;      // uniform button height
  ToolBar.ButtonSpacing := 4;      // spacing between adjacent buttons
  ToolBar.Indent := 6;             // margin before the first button / top edge

  // In the narrow 360px toolbar the following 9 72px tool buttons (plus separators) won't fit on one row;
  // they wrap onto rows 2 and 3 and the toolbar grows accordingly -- that's the Wrapable effect.

  // First group: file operations
  AddTool(ToolBar, '新建', 72);
  AddTool(ToolBar, '打开', 72);
  AddTool(ToolBar, '保存', 72);

  // Separator: insert a vertical divider between the two groups (Parent=toolbar, takes part in layout)
  Sep := TTyToolSeparator.Create(Self);
  Sep.Parent := ToolBar;

  // Second group: edit operations
  AddTool(ToolBar, '剪切', 72);
  AddTool(ToolBar, '复制', 72);
  AddTool(ToolBar, '粘贴', 72);

  // Separator: between the second and third groups
  Sep := TTyToolSeparator.Create(Self);
  Sep.Parent := ToolBar;

  // Third group: search operations (pushes the total high enough to force wrapping)
  AddTool(ToolBar, '查找', 72);
  AddTool(ToolBar, '替换', 72);
  AddTool(ToolBar, '全选', 72);

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  // Placed after the toolbar's wrap (up to 3 rows) so it isn't covered by the toolbar.
  FStatus.SetBounds(24, 190, 312, 24);
  FStatus.Caption := '就绪:点击任一工具按钮';

  ApplyChromeTheme(TyDefaultController);   // finally theme the form shell and background in one pass
end;

procedure TMainForm.ToolClicked(Sender: TObject);
begin
  FStatus.Caption := Format('已触发工具:%s', [(Sender as TTyButton).Caption]);
end;

end.
