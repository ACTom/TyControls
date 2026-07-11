unit umain;

{ TTyComboBox demo (pure code, no .lfm):
    Left column csDropDownList (read-only, selection only from the list) -- shows
      Sorted ordering, DropDownCount limiting the visible rows, and keyboard
      type-ahead prefix jumping.
    Right column csDropDown (editable field + prefix auto-complete) -- typing a
      prefix pops up the filtered candidate list; also demonstrates CharCase
      (auto-uppercase) and MaxLength (length limit).
    A TTyLabel status bar below subscribes to four events:
      OnChange / OnSelect / OnDropDown / OnCloseUp.
  The form descends from TTyForm (borderless self-drawn window frame) plus a
  single TTyTitleBar; the theme is loaded through the global TyDefaultController
  and then uniformly colored by ApplyChromeTheme. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.ComboBox, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FListCombo: TTyComboBox;   // csDropDownList (read-only)
    FEditCombo: TTyComboBox;   // csDropDown (editable + auto-complete)
    FStatus: TTyLabel;         // event status bar
    procedure ComboChange(Sender: TObject);
    procedure ComboSelect(Sender: TObject);
    procedure ComboDropDown(Sender: TObject);
    procedure ComboCloseUp(Sender: TObject);
    procedure SetStatus(const AEvt: string; ACombo: TTyComboBox);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Search upward from the exe's directory for the repo's themes/ dir (handles lib/<cpu>-<os>/ and .app bundles) }
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
  LblList, LblEdit: TTyLabel;
begin
  // TTyForm.CreateNew -> borderless + persistent engine, but no title bar by default
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyComboBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 520, 320);

  // The theme must be loaded first, before coloring the whole window frame
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // Title bar: Owner=Self auto-associates it with this form's TitleBar property
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyComboBox  · TyControls';

  // ── Left column: csDropDownList (read-only drop-down) ──
  LblList := TTyLabel.Create(Self);
  LblList.Parent := Self;
  LblList.SetBounds(24, 52, 224, 20);
  LblList.Caption := '只读下拉（Sorted 排序，可键盘 type-ahead）：';

  FListCombo := TTyComboBox.Create(Self);
  FListCombo.Parent := Self;
  FListCombo.SetBounds(24, 76, 224, 26);
  FListCombo.Style := csDropDownList;   // selection only from the list
  FListCombo.Sorted := True;            // stays ascending, inserts fall into place
  FListCombo.DropDownCount := 5;        // show at most 5 rows, scroll beyond that
  // Add 8 items out of order: Sorted=True auto-arranges them ascending
  FListCombo.Items.Add('Guangzhou');
  FListCombo.Items.Add('Beijing');
  FListCombo.Items.Add('Shanghai');
  FListCombo.Items.Add('Chengdu');
  FListCombo.Items.Add('Hangzhou');
  FListCombo.Items.Add('Nanjing');
  FListCombo.Items.Add('Wuhan');
  FListCombo.Items.Add('Xian');
  FListCombo.ItemIndex := 0;            // preselect the first item (Beijing after sorting)
  FListCombo.OnChange   := @ComboChange;
  FListCombo.OnSelect   := @ComboSelect;
  FListCombo.OnDropDown := @ComboDropDown;
  FListCombo.OnCloseUp  := @ComboCloseUp;

  // ── Right column: csDropDown (editable + prefix auto-complete) ──
  LblEdit := TTyLabel.Create(Self);
  LblEdit.Parent := Self;
  LblEdit.SetBounds(272, 52, 224, 20);
  LblEdit.Caption := '可编辑（前缀自动完成 / 大写 / 限长 10）：';

  FEditCombo := TTyComboBox.Create(Self);
  FEditCombo.Parent := Self;
  FEditCombo.SetBounds(272, 76, 224, 26);
  FEditCombo.Style := csDropDown;       // editable field + prefix auto-complete popup
  FEditCombo.CharCase := ecUppercase;   // typed text is auto-uppercased
  FEditCombo.MaxLength := 10;           // limit the field length to 10
  FEditCombo.DropDownCount := 6;
  FEditCombo.Items.Add('APPLE');
  FEditCombo.Items.Add('APRICOT');
  FEditCombo.Items.Add('AVOCADO');
  FEditCombo.Items.Add('BANANA');
  FEditCombo.Items.Add('BLUEBERRY');
  FEditCombo.Items.Add('CHERRY');
  FEditCombo.Items.Add('GRAPE');
  FEditCombo.Items.Add('MANGO');
  FEditCombo.OnChange   := @ComboChange;
  FEditCombo.OnSelect   := @ComboSelect;
  FEditCombo.OnDropDown := @ComboDropDown;
  FEditCombo.OnCloseUp  := @ComboCloseUp;

  // ── Event status bar ──
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 140, 472, 22);
  FStatus.Caption := '事件状态：（等待操作，尝试展开或键入前缀）';

  // Whole window frame + background color follow the theme
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.SetStatus(const AEvt: string; ACombo: TTyComboBox);
var
  Which: string;
begin
  if ACombo = FListCombo then
    Which := '只读'
  else
    Which := '可编辑';
  FStatus.Caption := Format('事件状态：[%s] %s → Text="%s" (ItemIndex=%d)',
    [Which, AEvt, ACombo.Text, ACombo.ItemIndex]);
end;

procedure TMainForm.ComboChange(Sender: TObject);
begin
  SetStatus('OnChange', Sender as TTyComboBox);
end;

procedure TMainForm.ComboSelect(Sender: TObject);
begin
  SetStatus('OnSelect', Sender as TTyComboBox);
end;

procedure TMainForm.ComboDropDown(Sender: TObject);
begin
  SetStatus('OnDropDown（展开）', Sender as TTyComboBox);
end;

procedure TMainForm.ComboCloseUp(Sender: TObject);
begin
  SetStatus('OnCloseUp（收起）', Sender as TTyComboBox);
end;

end.
