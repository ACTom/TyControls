unit umain;

{ TTyToolBar + TTyToolButton + TTyToolSeparator demo:
  - alTop top toolbar holding several TTyButton tool buttons (the toolbar rewrites Flat buttons into the ghost variant)
  - TTyToolSeparator inserts a vertical divider between button groups
  - ButtonHeight / ButtonSpacing / Indent control button size and layout
  - Flat (flat/ghost) . Wrapable (auto-wrap when too wide; toolbar grows taller as the row count changes)
  - third bar: real TTyToolButtons — all six Style values, an adjacent Grouped check group,
    Wrap = True forcing a row break, a tbsDropDown with a DropdownMenu, a menu-less tbsDropDown
    whose arrow fires OnArrowClick, and a tbsButtonDrop whose whole face pops its menu
  - fourth and fifth bars: the SAME three tbsCheck buttons drawn twice — the fourth by the
    theme, the fifth by OnPaintButton, the bar-level owner-draw hook that replaces the themed
    paint of every tool button on that bar (LCL's signature: Sender + the AState integer).
    They are two bars and not one because the hook is a property of the BAR: it is all or
    nothing per bar, so adjacency is as close as a handled and an unhandled button can get.
  - each tool button's OnClick / OnArrowClick / menu pick reports to the bottom TTyLabel status label
  The window, the toolbars, every tool button, both popup menus and the live theme switcher are
  designed in umain.lfm (a TTyForm + TTyTitleBar); the code here is event handlers + theme setup only. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, Menus,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.ToolBar, tyControls.Button, tyControls.TyLabel, tyControls.ComboBox, tyControls.ToggleSwitch,
  tyControls.GlyphButtons, tyControls.IconFont, tyControls.Menu;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    Icons: TTyIconFont;
    ToolBar: TTyToolBar;
    BtnNew: TTyGlyphButton;
    BtnOpen: TTyGlyphButton;
    BtnSave: TTyGlyphButton;
    Sep1: TTyToolSeparator;
    BtnCut: TTyButton;
    BtnCopy: TTyButton;
    BtnPaste: TTyButton;
    Sep2: TTyToolSeparator;
    BtnFind: TTyButton;
    BtnReplace: TTyButton;
    BtnSelectAll: TTyButton;
    Sep3: TTyToolSeparator;
    { Toggling tools: Down is the resting :selected state (TyButton.ghost:selected). }
    BtnBold: TTyButton;
    BtnItalic: TTyButton;
    BtnUnderline: TTyButton;
    { Second bar: Flat = False, Wrapable = False, ButtonHeight left unset. }
    ToolBarFramed: TTyToolBar;
    BtnAlignLeft: TTyButton;
    BtnAlignCenter: TTyButton;
    BtnAlignRight: TTyButton;
    BtnJustify: TTyButton;
    Sep4: TTyToolSeparator;
    BtnBullets: TTyButton;
    BtnNumbers: TTyButton;
    BtnQuote: TTyButton;
    { Third bar: real TTyToolButtons — the six styles, Grouped, Wrap, DropdownMenu, OnArrowClick. }
    ToolButtons: TTyToolBar;
    BtnTbRun: TTyToolButton;
    BtnTbPin: TTyToolButton;
    SepTb1: TTyToolButton;
    BtnViewDay: TTyToolButton;
    BtnViewWeek: TTyToolButton;
    BtnViewMonth: TTyToolButton;
    BtnTbSave: TTyToolButton;
    BtnTbExport: TTyToolButton;
    DivTb1: TTyToolButton;
    BtnTbShare: TTyToolButton;
    SaveMenu: TTyPopupMenu;
    MnuSaveAs: TMenuItem;
    MnuSaveCopy: TMenuItem;
    MnuSaveAll: TMenuItem;
    ShareMenu: TTyPopupMenu;
    MnuShareLink: TMenuItem;
    MnuShareMail: TMenuItem;
    { Fourth and fifth bars: the SAME three tbsCheck buttons twice, so the owner-draw hook can
      be read against the themed default it replaces. OnPaintButton is a property of the BAR
      and replaces the paint of every tool button on it, so a handled and an unhandled button
      cannot share one bar — two adjacent bars is the closest an example can put them. }
    ToolBarThemed: TTyToolBar;
    BtnThCrimson: TTyToolButton;
    BtnThTeal: TTyToolButton;
    BtnThAmber: TTyToolButton;
    ToolBarPainted: TTyToolBar;
    BtnSwCrimson: TTyToolButton;
    BtnSwTeal: TTyToolButton;
    BtnSwAmber: TTyToolButton;
    LblWrapHint: TTyLabel;
    LblDownHint: TTyLabel;
    LblGlyphHint: TTyLabel;
    LblFramedHint: TTyLabel;
    LblToolBtnHint: TTyLabel;
    LblDropHint: TTyLabel;
    LblPaintHint: TTyLabel;
    LblLendHint: TTyLabel;
    LblStatus: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ToolClicked(Sender: TObject);
    procedure ToolToggle(Sender: TObject);
    procedure ToolButtonChecked(Sender: TObject);
    procedure ToolArrowClicked(Sender: TObject);
    procedure MenuPicked(Sender: TObject);
    procedure PaintedBarPaintButton(Sender: TTyToolButton; AState: Integer);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  rsFiredFmt  = 'Fired tool: %s';
  rsToggleFmt = '%s: Down = %s';
  rsArrowFmt  = 'Arrow zone clicked: %s';
  rsMenuFmt   = 'Menu item picked: %s';

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

procedure TMainForm.ToolClicked(Sender: TObject);
begin
  LblStatus.Caption := Format(rsFiredFmt, [(Sender as TTyButton).Caption]);
end;

procedure TMainForm.ToolToggle(Sender: TObject);
var
  B: TTyButton;
begin
  // A toggling tool built from a PLAIN TTyButton: Down is the resting :selected state, so
  // the tool keeps the pressed look after the mouse leaves. There is no built-in grouping —
  // the app owns the state, which is why this flips it by hand.
  B := Sender as TTyButton;
  B.Down := not B.Down;
  LblStatus.Caption := Format(rsToggleFmt, [B.Caption, BoolToStr(B.Down, True)]);
end;

procedure TMainForm.ToolButtonChecked(Sender: TObject);
var
  B: TTyToolButton;
begin
  // A tbsCheck TTyToolButton flips Down ITSELF before OnClick fires (and Grouped keeps an
  // adjacent run exclusive) — so unlike ToolToggle above, this handler only reports.
  B := Sender as TTyToolButton;
  LblStatus.Caption := Format(rsToggleFmt, [B.Caption, BoolToStr(B.Down, True)]);
end;

procedure TMainForm.ToolArrowClicked(Sender: TObject);
begin
  // Fires for a tbsDropDown's arrow zone ONLY when no DropdownMenu is assigned — an
  // assigned menu suppresses the event (LCL's rule: the event is the menu's alternative).
  LblStatus.Caption := Format(rsArrowFmt, [(Sender as TTyToolButton).Caption]);
end;

{ OBSERVED, REPORTED, NOT WORKED AROUND HERE (2026-08-08, real-machine run of this example).

  On THIS bar (Flat = True, the library default) the 1px split divider that a tbsDropDown is
  supposed to draw between its main area and its arrow zone is INVISIBLE, so Save/Export
  (tbsDropDown) look identical to Share (tbsButtonDrop) — even though a click on the BODY of
  the first two fires OnClick while a click anywhere on Share drops the menu. The divider is
  the only thing that distinguishes the two styles, and TTyToolButton.DrawContent's own
  comment calls it "the visible half of the hit test".

  Cause: DrawContent paints that rule with TyToolRuleFill(AStyle.BorderColor), and the flat
  bar hands every tool the `ghost` StyleClass, whose token is
      TyButton.ghost { border-color: alpha(var(--border), 0) }   (themes/light.tycss:247)
  i.e. fully transparent. Setting Flat = False on this bar makes both dividers appear at once
  — that experiment was run and reverted; it is the proof, not the fix.

  This bar deliberately stays on the DEFAULT Flat = True: switching it would hide the defect
  behind a non-default setting while every real flat toolbar still has it. The fix belongs in
  source/ (a rule colour that does not come from a transparent border token — e.g. resolve the
  'TyToolSeparator' key's border, which is what the standalone tbsDivider already uses and
  which IS visible two buttons to the right), and changing source/ is out of scope here. }

procedure TMainForm.MenuPicked(Sender: TObject);
begin
  LblStatus.Caption := Format(rsMenuFmt, [(Sender as TMenuItem).Caption]);
end;

procedure TMainForm.PaintedBarPaintButton(Sender: TTyToolButton; AState: Integer);
const
  // Swatch data, indexed by the button's position on the bar (Buttons[] order).
  // TColor is $00BBGGRR: crimson / teal / amber, with an ink that stays readable on each.
  SwatchFill: array[0..2] of TColor = ($3C14DC, $808000, $00BFFF);
  SwatchInk:  array[0..2] of TColor = (clWhite, clWhite, clBlack);
var
  C: TCanvas;
  R: TRect;
  i: Integer;
  ts: TSize;
begin
  { While this handler is assigned to the BAR, it replaces the themed paint of EVERY
    TTyToolButton on it — same contract as LCL's TToolBar.OnPaintButton, same AState
    integer: 1 normal / 2 hot / 3 pressed / 4 disabled / 5 checked / 6 checked-hot.
    The canvas is Sender.Canvas, already clipped to the button. }
  C := Sender.Canvas;
  R := Sender.ClientRect;
  { Index is the button's position in its bar's Buttons[]. It is never -1 in here — this hook
    only fires for a button that IS on a bar — but -1 mod 3 is -1 in FPC, so a copy of this
    handler called from anywhere else would read off the front of the array. Clamp and say why. }
  i := Sender.Index;
  if i < 0 then i := 0;
  i := i mod Length(SwatchFill);
  C.Brush.Style := bsSolid;
  if AState = 4 then
    C.Brush.Color := clGray            // disabled: a flat grey swatch
  else
    C.Brush.Color := SwatchFill[i];
  C.FillRect(R);
  // State feedback, drawn by hand — square corners on purpose, so the custom paint is
  // unmistakably not the themed one: thin frame on hover, inset frame while pressed,
  // heavy frame while checked (these are tbsCheck buttons, so clicking toggles it).
  C.Pen.Color := SwatchInk[i];
  C.Pen.Width := 1;
  case AState of
    2: InflateRect(R, -1, -1);
    3: InflateRect(R, -3, -3);
    5, 6: begin C.Pen.Width := 3; InflateRect(R, -2, -2); end;
  end;
  if AState in [2, 3, 5, 6] then
  begin
    C.Brush.Style := bsClear;
    C.Rectangle(R);
  end;
  C.Font.Color := SwatchInk[i];
  if AState = 4 then C.Font.Color := clSilver;
  ts := C.TextExtent(Sender.Caption);
  C.Brush.Style := bsClear;
  C.TextOut((Sender.ClientWidth - ts.cx) div 2, (Sender.ClientHeight - ts.cy) div 2,
    Sender.Caption);
end;

end.
