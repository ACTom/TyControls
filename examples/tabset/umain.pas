unit umain;

{ TTyTabSet demo: a pure tab-strip control (no page container); selection = TabIndex + OnChange.
  - Tabs: a TStrings list of tab captions
  - TabIndex: the currently selected tab; initialized to 0 (the first)
  - OnChange: fires after a switch; the status label at the bottom shows the current tab live
  - OnChanging: pre-switch veto hook; demonstrates blocking a jump to a "locked" tab
  - TabsClosable + OnTabClose: the tab header shows a close (×) glyph; veto via AllowClose:=False
  - OnReorder: fires after a drag-reorder is committed; the status label reports from->to
  - TabHeight: height of the tab strip -- pinned to 32 on the top strip; left UNSET on the
    second one, where it follows the theme's --control-height (28 classic / 38 modern)
  - Tabs at runtime: "+ Add tab" appends to the live TStrings, which is also the way back
    after TabsClosable has let the user close tabs away
  - Mnemonics: the captions carry '&', so holding Alt underlines a letter and Alt+letter jumps
  - Header overflow: the narrow 200px strip cannot fit its eight tabs, so the prev/next arrows
    appear and the mouse wheel scrolls the strip
  The window, both tab strips, the labels and the live theme switcher are designed in
  umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes, tyControls.Accel,
  tyControls.TabSet, tyControls.TyLabel, tyControls.Button, tyControls.Divider,
  tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    TabStrip: TTyTabSet;
    LblKeys: TTyLabel;
    BtnAdd: TTyButton;
    LblAdd: TTyLabel;
    LblStatus: TTyLabel;
    Div1: TTyDivider;
    NarrowStrip: TTyTabSet;
    LblNarrow: TTyLabel;
    LblDensity: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure TabChanged(Sender: TObject);
    procedure TabChanging(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean);
    procedure TabClosing(Sender: TObject; AIndex: Integer; var AllowClose: Boolean);
    procedure TabReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
    procedure BtnAddClick(Sender: TObject);
    procedure NarrowTabChanged(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

{ Everything the LFM translator cannot reach.

  Tabs is a TStrings, not a TCaption property, so SetDefaultLang walks straight past it --
  LCL's LFM translator only rewrites TTranslateString-typed properties, and a TStrings
  collection is neither. The same goes for every status line built here with Format(). Both
  come from resourcestrings instead, which SetDefaultLang DOES translate, and FormCreate
  pushes the tab lists back into the two strips once. (antdesign_pro does the same thing for
  its code-built Sider and breadcrumb.) }
resourcestring
  rsTabOverview   = '&Overview';
  rsTabDetail     = '&Detail';
  rsTabNotice     = '&Notice (locked)';
  rsTabSettings   = '&Settings';
  rsTabAbout      = '&About';
  rsNTabOverview  = 'Overview';
  rsNTabDetail    = 'Detail';
  rsNTabNotice    = 'Notice';
  rsNTabSettings  = 'Settings';
  rsNTabAbout     = 'About';
  rsNTabHistory   = 'History';
  rsNTabExport    = 'Export';
  rsNTabAdvanced  = 'Advanced';

  rsCurrentTab    = 'Current tab: %s (TabIndex=%d)';
  rsVetoedSelect  = 'The "Notice (locked)" tab was vetoed by OnChanging and cannot be selected.';
  rsVetoedClose   = 'The "Overview" tab was vetoed by OnTabClose and will not close.';
  rsClosingTab    = 'Closing tab: %s';
  rsReordered     = 'Tabs reordered: %d → %d (current: %s)';
  rsNewTabName    = 'Tab %d';
  rsAddedTab      = 'Added a tab through Tabs.Add — Tabs.Count is now %d. '
                  + 'Keep going and the top strip overflows too.';
  rsOverflowStrip = 'Overflow strip: %s (TabIndex=%d) — selecting a tab scrolls it into view.';

{ Tab captions carry '&' mnemonics, which the strip strips before drawing. Do the same before
  quoting one back in a message, so the status line reads "Overview", not "&Overview". }
function PlainCaption(const ACaption: string): string;
var
  disp: string;
  mpos: Integer;
begin
  TyParseMnemonic(ACaption, disp, mpos);
  Result := disp;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  tip: string;
begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  { Refill both strips from the resourcestrings above: the .lfm's Tabs.Strings is what the
    designer shows, but it arrives untranslated because it is a TStrings. Assigning the whole
    list at once keeps TabIndex handling in one place -- the re-selection just below. }
  TabStrip.Tabs.Text := rsTabOverview + LineEnding + rsTabDetail + LineEnding +
    rsTabNotice + LineEnding + rsTabSettings + LineEnding + rsTabAbout;
  NarrowStrip.Tabs.Text := rsNTabOverview + LineEnding + rsNTabDetail + LineEnding +
    rsNTabNotice + LineEnding + rsNTabSettings + LineEnding + rsNTabAbout + LineEnding +
    rsNTabHistory + LineEnding + rsNTabExport + LineEnding + rsNTabAdvanced;

  { A TabIndex set in the .lfm is parked while the form streams, so re-apply the designed
    selection now that loading is done -- otherwise both strips open with nothing active.
    This fires OnChange on each strip, so the designed tip text is saved and put back. }
  tip := LblStatus.Caption;
  TabStrip.TabIndex := 0;
  NarrowStrip.TabIndex := 0;
  LblStatus.Caption := tip;
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

{ Tab-switch callback: update the status label to show the current tab caption }
procedure TMainForm.TabChanged(Sender: TObject);
begin
  LblStatus.Caption := Format(rsCurrentTab,
    [PlainCaption(TabStrip.TabCaption(TabStrip.TabIndex)), TabStrip.TabIndex]);
end;

{ Pre-switch veto hook: ANewIndex is the target index of the intended switch; clearing AllowChange aborts it.
  Here we block selecting the 3rd tab (the "locked" one) to demonstrate the veto. }
procedure TMainForm.TabChanging(Sender: TObject; ANewIndex: Integer;
  var AllowChange: Boolean);
begin
  if ANewIndex = 2 then
  begin
    AllowChange := False;
    LblStatus.Caption := rsVetoedSelect;
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
    LblStatus.Caption := rsVetoedClose;
  end
  else
    LblStatus.Caption := Format(rsClosingTab, [PlainCaption(TabStrip.TabCaption(AIndex))]);
end;

{ Drag-reorder commit callback: fires once after a clean drag gesture completes }
procedure TMainForm.TabReordered(Sender: TObject; AFromIndex, AToIndex: Integer);
begin
  LblStatus.Caption := Format(rsReordered,
    [AFromIndex, AToIndex, PlainCaption(TabStrip.TabCaption(TabStrip.TabIndex))]);
end;

{ Tabs is a LIVE TStrings, not a design-time-only list: its OnChange repaints the strip and
  clamps TabIndex, so Add/Insert/Delete at runtime need nothing else. This is also the way
  back once TabsClosable has let the user close tabs away. }
procedure TMainForm.BtnAddClick(Sender: TObject);
begin
  TabStrip.Tabs.Add(Format(rsNewTabName, [TabStrip.Tabs.Count + 1]));
  LblStatus.Caption := Format(rsAddedTab, [TabStrip.Tabs.Count]);
end;

{ The narrow strip: eight tabs in 200px, so the header overflows and the prev/next arrows and
  the mouse wheel come into play. Selecting a tab also runs ScrollTabIntoView, so a tab picked
  with Ctrl+Tab / End while it is off-screen scrolls itself back into the visible band. }
procedure TMainForm.NarrowTabChanged(Sender: TObject);
begin
  LblStatus.Caption := Format(rsOverflowStrip,
    [NarrowStrip.TabCaption(NarrowStrip.TabIndex), NarrowStrip.TabIndex]);
end;

end.
