unit umain;

{ TTyScrollBar example:
  - a vertical scroll bar (Kind=sbVertical) and a horizontal one (Kind=sbHorizontal)
  - demonstrates Min / Max / Position / PageSize / SmallChange
  - OnChange live-aggregates both bars' Position into a TTyLabel status line
  - OnScroll names the GESTURE behind each change and vetoes one of them through its
    var parameter (Home is forced to 10 instead of Min)
  - the vertical bar actually scrolls a block of text inside a TTyPanel viewport, so the
    two ways of moving the thumb can be compared: Position (eased) vs SetPositionSnapped
    (immediate -- the "my host already scrolled, just mirror it" path)
  - AnimationsEnabled can be switched off live, and a third bar shows the degenerate
    Max = Min case where the thumb fills the whole track
  - AUTO-HIDE (the right-hand column): a bar nobody is using fades out. The radio group
    switches AutoHide between sbahDefault / sbahNever / sbahAuto on both bars and on the
    list box (which forwards it to its own embedded bar as ScrollBarAutoHide), and the
    label under it prints the theme token beside the delay the bar actually resolved --
    the one thing on screen that proves --scrollbar-auto-hide reaches the control
  The window, all three scroll bars, the viewport, the hint/status labels and the live theme
  switcher are designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event
  handlers + theme setup only. }

{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ScrollBar, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.Panel, tyControls.Button, tyControls.RadioGroup, tyControls.ListBox;
type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    LblTip: TTyLabel;
    VBar: TTyScrollBar;
    HBar: TTyScrollBar;
    LblStatus: TTyLabel;

    LblCodeTitle: TTyLabel;
    LblCode: TTyLabel;

    LblViewTitle: TTyLabel;
    Viewport: TTyPanel;
    LblContent: TTyLabel;
    BtnSnap: TTyButton;
    BtnEase: TTyButton;
    LblSnapHint: TTyLabel;

    SwAnim: TTyToggleSwitch;
    LblAnim: TTyLabel;

    LblFull: TTyLabel;
    FullBar: TTyScrollBar;

    LblAutoTitle: TTyLabel;
    RgAutoHide: TTyRadioGroup;
    LblAutoMs: TTyLabel;
    AutoList: TTyListBox;
    LblAutoHint: TTyLabel;

    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure BarChange(Sender: TObject);
    procedure BarScroll(Sender: TObject; ScrollCode: TScrollCode;
      var ScrollPos: Integer);
    procedure BtnSnapClick(Sender: TObject);
    procedure BtnEaseClick(Sender: TObject);
    procedure SwAnimChange(Sender: TObject);
    procedure RgAutoHideSelectionChanged(Sender: TObject);
  private
    procedure UpdateStatus;
    procedure BuildContent;
    procedure BuildAutoList;
    procedure UpdateAutoHideMs;
  end;
var
  MainForm: TMainForm;
implementation
{$R *.lfm}

resourcestring
  { Status texts composed at run time. TScrollCode spellings and the VBar/HBar
    component names are identifiers, not prose -- they stay literals. }
  rsLineFmt   = 'Line %.2d - scrollable content';
  rsBarsFmt   = 'Vertical:  Position = %d   (Min %d / Max %d / PageSize %d / SmallChange %d)';
  rsBarsFmt2  = 'Horizontal:  Position = %d   (Min %d / Max %d / PageSize %d / SmallChange %d)';
  rsVetoedFmt = '%s OnScroll: scTop vetoed - Home clamps to 10, not Min';
  rsScrollFmt = '%s OnScroll: %s -> %d';
  rsThemeTokenFmt = 'Theme --scrollbar-auto-hide: %s';
  rsEffectiveFmt  = 'Bar EffectiveAutoHideMs: %s';
  rsAutoHideOff   = '-1, never fades';
  rsAutoHideMsFmt = '%d ms';

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

  BuildContent;                            // the block of text the vertical bar scrolls
  BuildAutoList;                           // enough rows that the list grows a bar of its own
  UpdateStatus;                            // initial readout
  UpdateAutoHideMs;                        // what the theme says vs what the bar resolved
end;

{ The viewport is a plain TTyPanel (a windowed control, so it CLIPS what sticks out) with
  one over-tall label inside it. The label's Top is the scroll offset: BarChange sets it to
  -VBar.Position, so the bar really is scrolling content rather than a number. The content
  is 360px tall in a 160px viewport -- exactly VBar's Min..Max travel of 200. }
procedure TMainForm.BuildContent;
var
  s: string;
  i: Integer;
begin
  s := '';
  for i := 1 to 20 do
  begin
    if s <> '' then s := s + LineEnding;
    s := s + Format(rsLineFmt, [i]);
  end;
  LblContent.Caption := s;
  LblContent.Top := -VBar.Position;
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
  UpdateAutoHideMs;                        // the new skin's --scrollbar-auto-hide, live
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
  UpdateAutoHideMs;                        // a mode can carry its own auto-hide delay
end;

procedure TMainForm.UpdateStatus;
begin
  LblStatus.Caption := Format(
    rsBarsFmt + LineEnding + LineEnding + rsBarsFmt2,
    [VBar.Position, VBar.Min, VBar.Max, VBar.PageSize, VBar.SmallChange,
     HBar.Position, HBar.Min, HBar.Max, HBar.PageSize, HBar.SmallChange]);
end;

procedure TMainForm.BarChange(Sender: TObject);
begin
  UpdateStatus;   // refresh the status line whenever either bar changes
  // The vertical bar is a real scroller: its Position IS the viewport's scroll offset.
  LblContent.Top := -VBar.Position;
end;

{ TScrollCode -> its own spelling, so the read-out names the gesture the user made. }
function ScrollCodeName(ACode: TScrollCode): string;
begin
  case ACode of
    scLineUp:    Result := 'scLineUp';
    scLineDown:  Result := 'scLineDown';
    scPageUp:    Result := 'scPageUp';
    scPageDown:  Result := 'scPageDown';
    scPosition:  Result := 'scPosition';
    scTrack:     Result := 'scTrack';
    scTop:       Result := 'scTop';
    scBottom:    Result := 'scBottom';
    scEndScroll: Result := 'scEndScroll';
  else
    Result := 'sc?';
  end;
end;

{ OnScroll fires BEFORE the new value is committed, and ScrollPos is a VAR parameter -- a
  handler can rewrite the proposed position and the bar commits whatever it is left holding.
  OnChange, by contrast, only ever reports the value after the fact.

  Note which gestures reach here: the arrow buttons, a track click, the arrow keys,
  PageUp/PageDown, Home/End and a thumb drag (scTrack, then scPosition + scEndScroll on
  release). The mouse wheel writes Position directly, so it fires OnChange only. }
procedure TMainForm.BarScroll(Sender: TObject; ScrollCode: TScrollCode;
  var ScrollPos: Integer);
var
  who: string;
begin
  if Sender = VBar then who := 'VBar' else who := 'HBar';
  if ScrollCode = scTop then
  begin
    // The veto: Home proposes Min, we overrule it to 10 and that is what gets committed.
    ScrollPos := 10;
    LblCode.Caption := Format(rsVetoedFmt, [who]);
    Exit;
  end;
  LblCode.Caption := Format(rsScrollFmt, [who, ScrollCodeName(ScrollCode), ScrollPos]);
end;

procedure TMainForm.BtnSnapClick(Sender: TObject);
begin
  { SetPositionSnapped lands immediately and kills any ease already running -- the mirroring
    path: a host that has ALREADY scrolled its own content pushes the result in here, and a
    thumb easing its way there would just look half a beat behind. }
  VBar.SetPositionSnapped(VBar.Min);
end;

procedure TMainForm.BtnEaseClick(Sender: TObject);
begin
  { The ordinary Position write: with AnimationsEnabled on (and a real window handle) the
    painted thumb glides to the new value over ~120ms instead of teleporting. }
  VBar.Position := (VBar.Min + VBar.Max) div 2;
end;

procedure TMainForm.SwAnimChange(Sender: TObject);
begin
  VBar.AnimationsEnabled := SwAnim.Checked;
  HBar.AnimationsEnabled := SwAnim.Checked;
end;

{ Rows enough to overflow the box, so the list grows a vertical bar of its own -- the bar
  the LIST owns, not one dropped on the form. That is the point of having it here: what is
  set on the list is ScrollBarAutoHide, and the only way to see whether the host really
  forwards it is to watch that embedded bar fade. }
procedure TMainForm.BuildAutoList;
var
  i: Integer;
begin
  AutoList.Items.BeginUpdate;
  try
    for i := 1 to 24 do
      AutoList.Items.Add(Format(rsLineFmt, [i]));
  finally
    AutoList.Items.EndUpdate;
  end;
end;

{ ASK THE BAR, EVERY TIME. This label is the whole instrument: it puts the theme's own
  --scrollbar-auto-hide next to the delay VBar actually resolved, so "the token reaches the
  control" stops being something to take on faith. Caching either number -- or worse,
  printing the 1200 the skins happen to ship -- would leave a label that only proves it can
  copy a number out of a document. }
procedure TMainForm.UpdateAutoHideMs;

  function MsText(AMs: Integer): string;
  begin
    if AMs < 0 then
      Result := rsAutoHideOff              // the one "off" value, spelled out
    else
      Result := Format(rsAutoHideMsFmt, [AMs]);
  end;

begin
  LblAutoMs.Caption :=
    Format(rsThemeTokenFmt,
      [MsText(TyDefaultController.Metric(TyScrollBarAutoHideVar, TyScrollBarAutoHideDef))])
    + LineEnding + LineEnding +
    Format(rsEffectiveFmt, [MsText(VBar.EffectiveAutoHideMs)]);
end;

{ sbahDefault follows the theme; sbahNever and sbahAuto overrule it. The two numbers in the
  label come apart the moment they disagree: a skin that ships -1 with sbahAuto selected
  reads "-1, never fades" on top and "1200 ms" underneath -- the property winning, and the
  fallback it falls back to. }
procedure TMainForm.RgAutoHideSelectionChanged(Sender: TObject);
var
  v: TTyScrollBarAutoHide;
begin
  case RgAutoHide.ItemIndex of
    1: v := sbahNever;
    2: v := sbahAuto;
  else
    v := sbahDefault;
  end;
  VBar.AutoHide := v;
  HBar.AutoHide := v;
  AutoList.ScrollBarAutoHide := v;   // the host forwards it to the bar it owns
  UpdateAutoHideMs;
end;

end.
