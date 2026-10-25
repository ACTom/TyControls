unit umain;

{ Pilot: a container's chrome stays whole on top of its children (ITyChromeHost, TTyCard for
  now). Each card here has children placed ON its frame, across its corners and across the
  hairlines under its title and over its actions rail -- the places where a child used to cut
  the line. The switch turns the overlay off for a before/after look; Measure redraws the
  whole window a number of times both ways and shows what one redraw costs. Hover a card:
  its frame changes colour, and the part over the children follows. The window, the cards
  and every child are designed in umain.lfm; the code here is handlers and theme setup. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, LCLType, LCLIntf,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Base,
  tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Card, tyControls.Panel, tyControls.Edit, tyControls.ListBox;

type

  { TMainForm }

  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    Surface: TTyFormSurface;
    OverlaySwitch: TTyToggleSwitch;
    BtnMeasure: TTyButton;
    LblMeasure: TTyLabel;
    CardEdges: TTyCard;
    BtnLeftEdge: TTyButton;
    PnlHeaderLine: TTyPanel;
    LblRightEdge: TTyLabel;
    EdtCorner: TTyEdit;
    BtnOptedOut: TTyButton;
    CardNested: TTyCard;
    PnlInner: TTyPanel;
    BtnInnerEdge: TTyButton;
    LstCorner: TTyListBox;
    CardActions: TTyCard;
    BtnAcrossActions: TTyButton;
    BtnActionsCorner: TTyButton;
    LblHint: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure OverlaySwitchChange(Sender: TObject);
    procedure BtnMeasureClick(Sender: TObject);
  private
    procedure RedrawAll;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsMeasureFmt = 'One redraw of this window: %.1f ms with the frame on top, %.1f ms without';
  rsItem = 'Item %d';

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background
  for i := 1 to 6 do
    LstCorner.Items.Add(Format(rsItem, [i]));
  OverlaySwitch.Checked := TyChromeOverlayEnabled;
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
end;

{ Every window, children included, painted again now: the overlay is drawn by each child
  over itself, so turning it on or off has to reach all of them. }
procedure TMainForm.RedrawAll;
begin
  if not HandleAllocated then Exit;   // FormCreate sets the switch before there is a window
  RedrawWindow(Handle, nil, 0, RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
end;

procedure TMainForm.OverlaySwitchChange(Sender: TObject);
begin
  TyChromeOverlayEnabled := OverlaySwitch.Checked;
  RedrawAll;
end;

procedure TMainForm.BtnMeasureClick(Sender: TObject);
const
  ROUNDS = 40;
var
  keep: Boolean;
  withMs, withoutMs: Double;

  function Time(AOn: Boolean): Double;
  var
    t0: QWord;
    i: Integer;
  begin
    TyChromeOverlayEnabled := AOn;
    RedrawAll;   // warm the caches before the clock starts
    t0 := GetTickCount64;
    for i := 1 to ROUNDS do
      RedrawAll;
    Result := (GetTickCount64 - t0) / ROUNDS;
  end;

begin
  keep := TyChromeOverlayEnabled;
  withoutMs := Time(False);
  withMs := Time(True);
  TyChromeOverlayEnabled := keep;
  RedrawAll;
  LblMeasure.Caption := Format(rsMeasureFmt, [withMs, withoutMs]);
end;

end.
