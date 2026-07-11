unit umain;

{ TTyRadioButton demo (TTyForm + TitleBar skeleton):
  - Two TTyGroupBox containers (title band reserved at the top of each GroupBox), each holding 3 TTyRadioButtons
  - Mutual exclusion (UncheckSiblings) is grouped by Parent: exclusive within a GroupBox, independent across groups
  - Checked: each group has one item selected by default
  - OnChange: any button state change refreshes the status readout in the bottom TTyLabel
  - Demonstrates one disabled item (Enabled=False)
  UI is built purely in code (no .lfm); the theme is loaded via the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.GroupBox, tyControls.CheckBox, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FStatus: TTyLabel;
    { Group A: fruit }
    FFruitApple, FFruitBanana, FFruitMango: TTyRadioButton;
    { Group B: color }
    FColorRed, FColorGreen, FColorBlue: TTyRadioButton;
    procedure RadioChanged(Sender: TObject);
    procedure UpdateStatus;
    function SelectedIn(A, B, C: TTyRadioButton): string;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk up from the exe's directory to find the repo's themes/ dir (handles lib/<cpu>-<os>/ and .app bundles) }
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

{ Create a TTyRadioButton inside the given GroupBox and hook its OnChange event.
  Top is in GroupBox client coordinates (the GroupBox already yields the top title band via AdjustClientRect). }
function AddRadio(AGroup: TTyGroupBox; const ACaption: string; ATop: Integer;
  AHandler: TNotifyEvent): TTyRadioButton;
begin
  Result := TTyRadioButton.Create(AGroup);
  Result.Parent := AGroup;
  Result.SetBounds(10, ATop, 160, 26);
  Result.Caption := ACaption;
  Result.OnChange := AHandler;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  GroupA, GroupB: TTyGroupBox;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + persistent engine
  Caption := 'RadioButton 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 440, 320);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'RadioButton  · TyControls';

  { --- Status label: create it first, it must already exist when OnChange first fires ---
    (AddRadio hooks OnChange, then .Checked := True fires RadioChanged immediately
     -> UpdateStatus -> FStatus.Caption; FStatus must be created before any radio group) }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 236, 408, 24);

  { --- Group A: fruit (exclusive within this GroupBox, title left-aligned) --- }
  GroupA := TTyGroupBox.Create(Self);
  GroupA.Parent := Self;
  GroupA.SetBounds(16, 52, 190, 168);
  GroupA.Caption := '水果';
  GroupA.Alignment := taLeftJustify;

  FFruitApple  := AddRadio(GroupA, '苹果', 24, @RadioChanged);  // Top>=24 yields the 16px title band
  FFruitBanana := AddRadio(GroupA, '香蕉', 56, @RadioChanged);
  FFruitMango  := AddRadio(GroupA, '芒果（缺货）', 88, @RadioChanged);
  FFruitMango.Enabled := False;            // disabled item: unselectable, greyed out

  { --- Group B: color (a separate GroupBox, independent of group A, title centered) --- }
  GroupB := TTyGroupBox.Create(Self);
  GroupB.Parent := Self;
  GroupB.SetBounds(232, 52, 190, 168);
  GroupB.Caption := '颜色';
  GroupB.Alignment := taCenter;

  FColorRed   := AddRadio(GroupB, '红色', 24, @RadioChanged);
  FColorGreen := AddRadio(GroupB, '绿色', 56, @RadioChanged);
  FColorBlue  := AddRadio(GroupB, '蓝色', 88, @RadioChanged);

  { Default selection must come after all radio fields are created: setting Checked fires OnChange immediately ->
    RadioChanged -> UpdateStatus, and UpdateStatus reads all 6 fields -- if any field is still
    nil at that point it crashes (AV on startup, which is exactly what was previously left unfixed). }
  FFruitApple.Checked := True;             // fruit: first item by default
  FColorGreen.Checked := True;             // color: second item by default
  UpdateStatus;                            // all radios built, refresh the final readout once

  ApplyChromeTheme(TyDefaultController);    // finally apply the theme to the chrome + form background in one pass
end;

{ Return the Caption of the currently selected item in a group }
function TMainForm.SelectedIn(A, B, C: TTyRadioButton): string;
begin
  if A.Checked then Result := A.Caption
  else if B.Checked then Result := B.Caption
  else if C.Checked then Result := C.Caption
  else Result := '（无）';
end;

procedure TMainForm.UpdateStatus;
begin
  FStatus.Caption := Format('当前选中  →  水果：%s     颜色：%s',
    [SelectedIn(FFruitApple, FFruitBanana, FFruitMango),
     SelectedIn(FColorRed, FColorGreen, FColorBlue)]);
end;

procedure TMainForm.RadioChanged(Sender: TObject);
begin
  { Any button's Checked change (including one cleared by UncheckSiblings) lands here }
  UpdateStatus;
end;

end.
