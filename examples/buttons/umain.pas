unit umain;

{ Command and grouped button demo: GlyphButton / GlyphContainerButton / SpeedButton (grouped) /
  DropDownButton / MenuButton / ColorButton / ButtonGroup.
  Main form TTyForm + TTyTitleBar, built entirely in code (no .lfm).
  The glyph buttons render a star (★) from the system symbol font; on a real machine an icon .ttf looks better. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Menus,
  tyControls.Types, tyControls.Controller, tyControls.Form, tyControls.TyLabel,
  tyControls.IconFont, tyControls.GlyphButtons, tyControls.DropButtons,
  tyControls.ColorButton, tyControls.ButtonGroup, tyControls.Menu;

type
  TMainForm = class(TTyForm)
  private
    FIcons: TTyIconFont;
    FMenu: TTyPopupMenu;
    procedure BuildMenu;
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

procedure TMainForm.BuildMenu;
  procedure AddItem(const ACaption: string);
  var mi: TMenuItem;
  begin
    mi := TMenuItem.Create(FMenu);
    mi.Caption := ACaption;
    FMenu.Items.Add(mi);
  end;
begin
  FMenu := TTyPopupMenu.Create(Self);
  FMenu.Controller := TyDefaultController;
  AddItem('保存副本');
  AddItem('导出为 PDF');
  AddItem('打印…');
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  gb: TTyGlyphButton;
  gc: TTyGlyphContainerButton;
  sb: TTySpeedButton;
  dd: TTyDropDownButton;
  mb: TTyMenuButton;
  cb: TTyColorButton;
  grp: TTyButtonGroup;
  i: Integer;
  cap: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'Buttons 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 480, 360);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'Buttons  · TyControls';

  FIcons := TTyIconFont.Create(Self);
  FIcons.MapGlyph('star', $2605);
  FIcons.FontFamily := 'Segoe UI Symbol';
  BuildMenu;

  // Row 1: glyph command buttons.
  cap := TTyLabel.Create(Self); cap.Parent := Self; cap.SetBounds(20, 48, 200, 18);
  cap.Caption := '图标命令按钮';

  gb := TTyGlyphButton.Create(Self);
  gb.Parent := Self; gb.SetBounds(20, 68, 120, 34);
  gb.Caption := '新建'; gb.IconFont := FIcons; gb.GlyphName := 'star';

  gc := TTyGlyphContainerButton.Create(Self);
  gc.Parent := Self; gc.SetBounds(152, 68, 80, 64);
  gc.Caption := '打开'; gc.IconFont := FIcons; gc.GlyphName := 'star';

  // Row 2: grouped speed buttons (radio, ghost variant for a visible selected state).
  cap := TTyLabel.Create(Self); cap.Parent := Self; cap.SetBounds(250, 48, 200, 18);
  cap.Caption := '分组切换(SpeedButton)';
  for i := 0 to 2 do
  begin
    sb := TTySpeedButton.Create(Self);
    sb.Parent := Self; sb.SetBounds(250 + i * 56, 68, 52, 34);
    sb.StyleClass := 'ghost';
    sb.GroupIndex := 1;
    case i of 0: sb.Caption := '左'; 1: sb.Caption := '中'; else sb.Caption := '右'; end;
    sb.Down := (i = 0);
  end;

  // Row 3: drop-down + menu buttons sharing a popup.
  cap := TTyLabel.Create(Self); cap.Parent := Self; cap.SetBounds(20, 150, 200, 18);
  cap.Caption := '下拉 / 菜单按钮';

  dd := TTyDropDownButton.Create(Self);
  dd.Parent := Self; dd.SetBounds(20, 170, 130, 34);
  dd.Caption := '保存'; dd.DropDownMenu := FMenu;

  mb := TTyMenuButton.Create(Self);
  mb.Parent := Self; mb.SetBounds(162, 170, 110, 34);
  mb.Caption := '更多'; mb.DropDownMenu := FMenu;

  // Row 4: colour button + segmented group.
  cap := TTyLabel.Create(Self); cap.Parent := Self; cap.SetBounds(20, 232, 200, 18);
  cap.Caption := '颜色按钮 / 分段条';

  cb := TTyColorButton.Create(Self);
  cb.Parent := Self; cb.SetBounds(20, 252, 150, 34);
  cb.SelectedColor := TyRGB($3B, $82, $F6);
  cb.ShowText := True;

  grp := TTyButtonGroup.Create(Self);
  grp.Parent := Self; grp.SetBounds(190, 252, 210, 34);
  grp.StyleClass := 'ghost';
  grp.Items.Add('日');
  grp.Items.Add('周');
  grp.Items.Add('月');
  grp.ItemIndex := 0;

  ApplyChromeTheme(TyDefaultController);
end;

end.
