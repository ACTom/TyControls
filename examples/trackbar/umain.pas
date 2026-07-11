unit umain;

{ TTyTrackBar demo:
  - Horizontal track bar (0..100), OnChange updates the status label live
  - Custom-range track bar (-50..50, shows a negative range)
  - Vertical track bar (Orientation = toVertical)
  - Fine-stepping track bar (PageSize / Frequency demo, its own range and readout)
  The main form is a TTyForm + TTyTitleBar; the UI is built entirely in code (no .lfm),
  and the theme is loaded through the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.TrackBar, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FTrack1: TTyTrackBar;   // 0..100 horizontal
    FTrack2: TTyTrackBar;   // -50..50 horizontal
    FTrack3: TTyTrackBar;   // vertical
    FStatus: TTyLabel;      // OnChange readout
    procedure Track1Change(Sender: TObject);
    procedure Track2Change(Sender: TObject);
    procedure Track3Change(Sender: TObject);
    procedure Track4Change(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ Walk upward from the exe's directory to find the repo's themes/ folder (handles lib/<cpu>-<os>/ and .app bundles) }
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
  LblA, LblB, LblC, LblFine: TTyLabel;
  FTrack4: TTyTrackBar;   // fine-stepping demo (PageSize / Frequency)
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: borderless + always-on engine
  Caption := 'TrackBar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 460, 380);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // load the theme first

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> auto-associated as TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TrackBar  · TyControls';

  // Track bar 1: 0..100 (horizontal), drag / arrow-key stepping / mouse wheel
  LblA := TTyLabel.Create(Self);
  LblA.Parent := Self;
  LblA.SetBounds(16, 48, 320, 20);
  LblA.Caption := '音量（0..100，Min/Max/Position）：';

  FTrack1 := TTyTrackBar.Create(Self);
  FTrack1.Parent := Self;
  FTrack1.SetBounds(16, 70, 300, 24);
  FTrack1.Min := 0;
  FTrack1.Max := 100;
  FTrack1.Position := 50;
  FTrack1.Frequency := 10;         // a tick every 10 units
  FTrack1.OnChange := @Track1Change;

  // Track bar 2: -50..50 (horizontal), demonstrates a negative range
  LblB := TTyLabel.Create(Self);
  LblB.Parent := Self;
  LblB.SetBounds(16, 108, 320, 20);
  LblB.Caption := '平衡（-50..50）：';

  FTrack2 := TTyTrackBar.Create(Self);
  FTrack2.Parent := Self;
  FTrack2.SetBounds(16, 130, 300, 24);
  FTrack2.Min := -50;
  FTrack2.Max := 50;
  FTrack2.Position := 0;
  FTrack2.OnChange := @Track2Change;

  // Track bar 4: fine stepping (0..200, PageSize=25 paging, Frequency=25 ticks)
  LblFine := TTyLabel.Create(Self);
  LblFine.Parent := Self;
  LblFine.SetBounds(16, 168, 320, 20);
  LblFine.Caption := '亮度（0..200，PageSize/Frequency=25）：';

  FTrack4 := TTyTrackBar.Create(Self);
  FTrack4.Parent := Self;
  FTrack4.SetBounds(16, 190, 300, 24);
  FTrack4.Min := 0;
  FTrack4.Max := 200;
  FTrack4.Position := 120;
  FTrack4.Frequency := 25;         // a tick every 25 units
  FTrack4.PageSize := 25;          // PageUp/PageDown steps by 25 each time
  FTrack4.OnChange := @Track4Change;

  // Track bar 3: vertical (Orientation = toVertical)
  LblC := TTyLabel.Create(Self);
  LblC.Parent := Self;
  LblC.SetBounds(350, 48, 100, 20);
  LblC.Caption := '垂直：';

  FTrack3 := TTyTrackBar.Create(Self);
  FTrack3.Parent := Self;
  FTrack3.SetBounds(380, 70, 24, 200);
  FTrack3.Orientation := toVertical;      // vertical orientation
  FTrack3.Min := 0;
  FTrack3.Max := 100;
  FTrack3.Position := 40;
  FTrack3.OnChange := @Track3Change;

  // Status label: any track bar's OnChange writes here
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 236, 320, 20);
  FStatus.Caption := Format('音量：%d', [FTrack1.Position]);

  ApplyChromeTheme(TyDefaultController);   // finally apply the chrome + form-background theme in one pass
end;

procedure TMainForm.Track1Change(Sender: TObject);
begin
  FStatus.Caption := Format('音量：%d', [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track2Change(Sender: TObject);
begin
  FStatus.Caption := Format('平衡：%d', [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track3Change(Sender: TObject);
begin
  FStatus.Caption := Format('垂直：%d', [(Sender as TTyTrackBar).Position]);
end;

procedure TMainForm.Track4Change(Sender: TObject);
begin
  FStatus.Caption := Format('亮度：%d', [(Sender as TTyTrackBar).Position]);
end;

end.
