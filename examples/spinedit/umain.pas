unit umain;

{ TTySpinEdit demo:
  Showcases the main published properties and events of this integer spin box
  (the implementation is integer-only; decimals are not supported):
    - Value / MinValue / MaxValue / Increment, with OnChange writing live to the status bar
    - Negative range (-50..50, step 5)
    - Alignment (right-justified), MaxLength (limits the number of digits entered)
    - ReadOnly (locked: no editing/stepping/wheel)
  Interaction: up/down arrow buttons, keyboard ↑/↓, mouse wheel, or typing then Enter to commit.
  The UI is built entirely in code (no .lfm); the main form is TTyForm + TTyTitleBar, and the
  theme is loaded through the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.SpinEdit, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FSpinQty: TTySpinEdit;      // 0..100 step 1
    FSpinOfs: TTySpinEdit;      // -50..50 step 5 (negative range)
    FSpinYear: TTySpinEdit;     // right-justified + MaxLength
    FSpinLock: TTySpinEdit;     // ReadOnly locked
    FStatus: TTyLabel;          // OnChange status output
    procedure SpinChange(Sender: TObject);
    procedure UpdateStatus(const ATag: string; ASpin: TTySpinEdit);
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
  Lbl: TTyLabel;

  function AddLabel(ATop: Integer; const ACaption: string): TTyLabel;
  begin
    Result := TTyLabel.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(24, ATop, 380, 20);
    Result.Caption := ACaption;
  end;

begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistent paint engine
  Caption := 'TTySpinEdit 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 440, 420);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'SpinEdit  · TyControls';

  // ① Quantity: 0..100, step 1
  AddLabel(52, '数量（0..100，步进 1；箭头/方向键/滚轮/键入）：');
  FSpinQty := TTySpinEdit.Create(Self);
  FSpinQty.Parent := Self;
  FSpinQty.SetBounds(24, 76, 130, 28);
  FSpinQty.MinValue := 0;
  FSpinQty.MaxValue := 100;
  FSpinQty.Increment := 1;
  FSpinQty.Value := 10;
  FSpinQty.OnChange := @SpinChange;

  // ② Offset: -50..50, step 5 (negative range + custom step)
  AddLabel(120, '偏移（-50..50，步进 5，含负值范围）：');
  FSpinOfs := TTySpinEdit.Create(Self);
  FSpinOfs.Parent := Self;
  FSpinOfs.SetBounds(24, 144, 130, 28);
  FSpinOfs.MinValue := -50;
  FSpinOfs.MaxValue := 50;
  FSpinOfs.Increment := 5;
  FSpinOfs.Value := 0;
  FSpinOfs.OnChange := @SpinChange;

  // ③ Year: right-justified + MaxLength=4 (limits the number of digits entered)
  AddLabel(188, '年份（右对齐 Alignment，MaxLength=4）：');
  FSpinYear := TTySpinEdit.Create(Self);
  FSpinYear.Parent := Self;
  FSpinYear.SetBounds(24, 212, 130, 28);
  FSpinYear.MinValue := 1900;
  FSpinYear.MaxValue := 2100;
  FSpinYear.Alignment := taRightJustify;
  FSpinYear.MaxLength := 4;
  FSpinYear.Value := 2026;
  FSpinYear.OnChange := @SpinChange;

  // ④ Locked: ReadOnly=True (no editing/stepping/wheel)
  AddLabel(256, '锁定（ReadOnly=True：不可编辑/步进/滚轮）：');
  FSpinLock := TTySpinEdit.Create(Self);
  FSpinLock.Parent := Self;
  FSpinLock.SetBounds(24, 280, 130, 28);
  FSpinLock.MinValue := 0;
  FSpinLock.MaxValue := 999;
  FSpinLock.Value := 42;
  FSpinLock.ReadOnly := True;
  FSpinLock.OnChange := @SpinChange;

  // Status bar: the OnChange of any SpinEdit prints here
  Lbl := AddLabel(332, '状态：');
  Lbl.SetBounds(24, 332, 60, 20);
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(84, 332, 336, 20);
  FStatus.Caption := '（改变任一数值以查看 OnChange 输出）';

  ApplyChromeTheme(TyDefaultController);   // finally apply the whole-form look + background coloring in one pass
end;

procedure TMainForm.UpdateStatus(const ATag: string; ASpin: TTySpinEdit);
begin
  FStatus.Caption := Format('%s → %d', [ATag, ASpin.Value]);
end;

procedure TMainForm.SpinChange(Sender: TObject);
begin
  if Sender = FSpinQty then
    UpdateStatus('数量', FSpinQty)
  else if Sender = FSpinOfs then
    UpdateStatus('偏移', FSpinOfs)
  else if Sender = FSpinYear then
    UpdateStatus('年份', FSpinYear)
  else if Sender = FSpinLock then
    UpdateStatus('锁定', FSpinLock);
end;

end.
