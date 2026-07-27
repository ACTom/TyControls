unit umain;

{ Phase-4 rich-input & picker demo. Grows as each control lands; showcases the rich edits
  (numeric / currency / mask / URL / combo-edit / track), the colour & font pickers, the
  grouped and rich list/combo boxes, the value-list editor and the calculator edits. The
  window, every control and the live theme switcher are designed in umain.lfm (a TTyForm +
  TTyTitleBar); the code here is theme setup, runtime item/value population and event handlers. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, BGRABitmap,
  tyControls.Controller, tyControls.Form, tyControls.BuiltinThemes,
  tyControls.IconFont, tyControls.ImageCollection, tyControls.ColorMath,
  tyControls.NumericEdit, tyControls.CurrencyEdit, tyControls.MaskEdit,
  tyControls.URLEdit, tyControls.ComboEdit, tyControls.TrackEdit,
  tyControls.ColorBox, tyControls.ColorListBox, tyControls.FontComboBox,
  tyControls.FontListBox, tyControls.FontSizeComboBox, tyControls.CheckListBox,
  tyControls.ColorComboBox, tyControls.MRUComboBox, tyControls.ComboBoxEx,
  tyControls.OfficeListBox, tyControls.OfficeComboBox, tyControls.ColorGrid,
  tyControls.LColorPicker, tyControls.HSColorPicker, tyControls.CheckComboBox,
  tyControls.AdvancedListBox, tyControls.AdvancedComboBox, tyControls.ValueListEditor,
  tyControls.CalcEdit, tyControls.CalcCurrencyEdit, tyControls.TyLabel,
  tyControls.ComboBox, tyControls.CheckBox, tyControls.Shape, tyControls.Popup,
  tyControls.ToggleSwitch, tyControls.Dialogs.SelectPath, tyControls.Dialogs.About, tyControls.Types;

type
  TMainForm = class(TTyForm)
    Bar: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    Surface: TTyFormSurface;
    ThemeCombo: TTyComboBox;
    L1: TTyLabel;
    L2: TTyLabel;
    L3: TTyLabel;
    L4: TTyLabel;
    L5: TTyLabel;
    L6: TTyLabel;
    L7: TTyLabel;
    L8: TTyLabel;
    L9: TTyLabel;
    L10: TTyLabel;
    L11: TTyLabel;
    L12: TTyLabel;
    L13: TTyLabel;
    L14: TTyLabel;
    L15: TTyLabel;
    L16: TTyLabel;
    L17: TTyLabel;
    L18: TTyLabel;
    L19: TTyLabel;
    L20: TTyLabel;
    L21: TTyLabel;
    L22: TTyLabel;
    L23: TTyLabel;
    L24: TTyLabel;
    L25: TTyLabel;
    L26: TTyLabel;
    L27: TTyLabel;
    L28: TTyLabel;
    L29: TTyLabel;
    LHint: TTyLabel;
    FQty: TTyNumericEdit;
    FPrice: TTyNumericEdit;
    FRanged: TTyNumericEdit;
    FMoney: TTyCurrencyEdit;
    FDate: TTyMaskEdit;
    FUrl: TTyURLEdit;
    FCombo: TTyComboEdit;
    FTrack: TTyTrackEdit;
    FColor: TTyColorBox;
    FFont: TTyFontComboBox;
    FSize: TTyFontSizeComboBox;
    FColorList: TTyColorListBox;
    FFontList: TTyFontListBox;
    FCheckList: TTyCheckListBox;
    FColorCombo: TTyColorComboBox;
    FCheckCombo: TTyCheckComboBox;
    FMRU: TTyMRUComboBox;
    FComboEx: TTyComboBoxEx;
    FOfficeCombo: TTyOfficeComboBox;
    FOfficeList: TTyOfficeListBox;
    FColorGrid: TTyColorGrid;
    FLColor: TTyLColorPicker;
    FHS: TTyHSColorPicker;
    FAdvList: TTyAdvancedListBox;
    FAdvCombo: TTyAdvancedComboBox;
    FVLE: TTyValueListEditor;
    FCalcEdit: TTyCalcEdit;
    FCalcCurr: TTyCalcCurrencyEdit;
    FEcho: TTyLabel;
    PickPreview: TTyShape;        // swatch that echoes the last colour pick
    LblPick: TTyLabel;
    LblFontPreview: TTyLabel;     // drawn with the picked family + size
    LblFontEcho: TTyLabel;
    LblChecks: TTyLabel;
    ChkSheetLock: TTyCheckBox;    // drives FVLE.ReadOnly (whole-sheet lock)
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure RangedChange(Sender: TObject);
    procedure ComboDrop(Sender: TObject);
    procedure LumChange(Sender: TObject);
    procedure VleChange(Sender: TObject; ARow: TTyValueRow);
    procedure VleEditDialog(Sender: TObject; ARow: TTyValueRow);
    procedure ShowPick(Sender: TObject);
    procedure FontPickChange(Sender: TObject);
    procedure ChecksChanged(Sender: TObject);
    procedure SheetLockChange(Sender: TObject);
  private
    { The popup FCombo (TTyComboEdit) drops. The control itself only FIRES OnDropDown —
      the HOST owns the window and writes the picked value back into the field. }
    FDropPopup: TTyDropdownPopup;
    FDropGrid: TTyColorGrid;      // its content; owned by the form, only parented by the popup
    procedure DropGridPick(Sender: TObject);
  public
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
  Icf: TTyIconFont;
  Coll: TTyImageCollection;
  Imgs: TTyVirtualImageList;
  VR, VS: TTyValueRow;

  { Rasterise one system-symbol glyph into the collection + register it in the image list.
    (No .ttf shipped, so this uses a Unicode symbol via the system font — same placeholder
    convention as the buttons example; on a real machine point IconFont at an icon .ttf.) }
  procedure AddGlyph(const AName: string; ACodepoint: Cardinal; AColor: TColor);
  var B: TBGRABitmap;
  begin
    Icf.MapGlyph(AName, ACodepoint);
    B := Icf.RenderGlyph(AName, 32, TyColorFromLCL(AColor, 255));
    try
      Coll.AddBitmap(AName, B);   // takes a copy — free ours
    finally
      B.Free;
    end;
    Imgs.Names.Add(AName);
  end;

begin
  // Built-in themes are compiled in, so the switcher works without locating a themes/ folder.
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');
  TyDefaultController.ThemeName := 'default';
  ApplyChromeTheme(TyDefaultController);   // theme the window chrome + background

  // ---- Runtime setup that can't be a .lfm property ----

  // Value is a public (not published) property on the numeric edits → set it here.
  FQty.Value := 1250;
  FPrice.Value := 1234567.5;
  FRanged.Value := 42;
  FRanged.OnChange := @RangedChange;   // wire AFTER Value so the initial set doesn't fire it
  FMoney.Value := 1234.5;
  FTrack.Value := 128;
  FSize.FontSize := 14;   // FontSize is a public (not published) property → set it here.

  // Check list (CheckListBox: click the box / Space to toggle; checked state stored in Objects)
  FCheckList.Items.Add('Bold');
  FCheckList.Items.Add('Italic');
  FCheckList.Items.Add('Underline');
  FCheckList.Items.Add('Strikeout');
  FCheckList.Items.Add('Word wrap');
  FCheckList.Items.Add('Line numbers');
  FCheckList.Checked[0] := True;
  FCheckList.Checked[2] := True;

  // Check dropdown (CheckComboBox: multi-select, popup stays open, field shows a summary of the checks)
  FCheckCombo.Items.Add('Bold');
  FCheckCombo.Items.Add('Italic');
  FCheckCombo.Items.Add('Underline');
  FCheckCombo.Items.Add('Strikethrough');
  FCheckCombo.Checked[0] := True;
  FCheckCombo.Checked[2] := True;

  // Most-recently-used combo (MRUComboBox: editable; selecting/typing auto-dedupes and moves to top)
  FMRU.AddToHistory('First search');
  FMRU.AddToHistory('Second search');
  FMRU.AddToHistory('Most recent (on top)');

  // Combo with icons (ComboBoxEx: every item carries an icon). Icon source = 3 symbols rendered from the icon font → image collection → virtual image list.
  Icf := TTyIconFont.Create(Self);
  Icf.FontFamily := 'Segoe UI Symbol';   // system symbol font (without it RenderGlyph returns a transparent bitmap = no icon)
  Coll := TTyImageCollection.Create(Self);
  Imgs := TTyVirtualImageList.Create(Self);
  Imgs.Collection := Coll;
  AddGlyph('save',  $2B07, clNavy);    // ⬇ save
  AddGlyph('open',  $25B6, clGreen);   // ▶ open
  AddGlyph('print', $2699, clMaroon);  // ⚙ print

  FComboEx.Images := Imgs;
  FComboEx.AddItem('Save', 0);
  FComboEx.AddItem('Open', 1);
  FComboEx.AddItem('Print', 2);
  FComboEx.ItemIndex := 0;

  // Grouped combo (OfficeComboBox: dropdown split into sections by group, header rows not selectable)
  FOfficeCombo.AddHeader('Fruit');
  FOfficeCombo.AddItem('Apple');
  FOfficeCombo.AddItem('Mango');
  FOfficeCombo.AddHeader('Vegetables');
  FOfficeCombo.AddItem('Carrot');
  FOfficeCombo.ItemIndex := 1;

  // Grouped list (OfficeListBox: header rows bold and not selectable)
  FOfficeList.AddHeader('Inbox');
  FOfficeList.AddItem('Meeting minutes');
  FOfficeList.AddItem('Weekly report');
  FOfficeList.AddHeader('Sent');
  FOfficeList.AddItem('Quote for the customer');
  FOfficeList.AddItem('Receipt confirmation');

  // Luminance bar drives the HS square's brightness (classic HSL linkage); wire after all controls exist.
  FLColor.OnChange := @LumChange;

  // Rich-row list (AdvancedListBox: each row has icon + bold title + dimmed subtitle; reuses the Imgs above)
  FAdvList.Images := Imgs;
  FAdvList.AddItem('Save draft', 'Not synced · 2 minutes ago', 0);
  FAdvList.AddItem('Open project', 'D:\work\ty-controls', 1);
  FAdvList.AddItem('Print report', 'Default printer', 2);
  FAdvList.AddItem('Item with no icon', 'Subtitle may be left blank', -1);

  // Rich-row combo (AdvancedComboBox: two-line rich items in the dropdown, field shows icon + title)
  FAdvCombo.Images := Imgs;
  FAdvCombo.AddItem('Save', 'Write to disk', 0);
  FAdvCombo.AddItem('Open', 'Choose file', 1);
  FAdvCombo.AddItem('Print', 'Send to printer', 2);
  FAdvCombo.ItemIndex := 0;

  // Name/value editor (ValueListEditor: property sheet, inline editing in the value column)
  FVLE.Images := Imgs;                             // row images come from the same virtual image list
  VR := FVLE.AddRow('Width', '1280');
  VR.EditorKind := vekInteger;
  VR.Bold := True;                                 // per-row value styling: bold + colour
  VR.TextColor := clNavy;
  FVLE.AddRow('Opacity', '0.85').EditorKind := vekFloat;   // float: digits, one '.', a leading '-'
  FVLE.AddRow('Title', 'Rich Inputs example');         // plain text
  VR := FVLE.AddRow('Align', 'taCenter');           // enum → dropdown
  VR.EditorKind := vekEnum;
  VR.EnumValues := 'taLeftJustify'#10'taCenter'#10'taRightJustify';
  FVLE.AddRow('Foreground colour', 'clNavy').EditorKind := vekColor;    // color → swatch dropdown (last "More…" row opens the dialog)
  FVLE.AddRow('Font', 'Segoe UI, 9').EditorKind := vekFont;  // leaf font → text + "…" opens the font dialog
  VR := FVLE.AddRow('Data path', 'D:\data');         // text + "…" → the library's own path dialog (OnEditRow)
  VR.EditorKind := vekDialog;
  VR.ImageIndex := 1;                              // a row image (index into FVLE.Images)
  FVLE.AddRow('Licence key', 'ABCD-1234-EFGH').DisplayValue := '(hidden)';   // DisplayValue masks the real Value
  VR := FVLE.AddRow('About', 'TyControls ' + TyVersion);   // user-side custom: "…" opens a read-only About dialog, no write-back
  VR.EditorKind := vekDialog;
  VR := FVLE.AddRow('Theme', 'light.tycss');        // read-only + display-name override (i18n)
  VR.DisplayKey := 'Theme (read-only)';
  VR.ReadOnly := True;
  VR := FVLE.AddRow('Font', 'Segoe UI, 9');        // expandable multi-level + vekFont: "…" opens the font dialog and writes back the child properties
  VR.EditorKind := vekFont;
  VR.AddChild('Name', 'Segoe UI');
  VR.AddChild('Size', '9').EditorKind := vekInteger;
  VR.AddChild('Color', 'clWindowText').EditorKind := vekColor;
  VS := VR.AddChild('Style', 'Regular');           // second-level child (unlimited nesting: Font→Style→Bold)
  VS.AddChild('Bold', 'False').EditorKind := vekBoolean;
  VS.AddChild('Italic', 'False').EditorKind := vekBoolean;
  VS.AddChild('Underline', 'False').EditorKind := vekBoolean;
  VS.AddChild('StrikeOut', 'False').EditorKind := vekBoolean;
  FVLE.UpdateRows;                                 // refresh after adding child rows
  FVLE.OnValueChanged := @VleChange;
  FVLE.OnEditRow := @VleEditDialog;

  // Calculator dropdown (CalcEdit / CalcCurrencyEdit): Value is public, set here.
  FCalcEdit.Value := 1000;
  FCalcCurr.Value := 1234.5;   // SymbolBefore=False in the .lfm -> "1,234.50 €"

  // Seed the three echo panels so the reader sees the shape of each report before clicking.
  ShowPick(FColorGrid);
  FontPickChange(FFont);
  ChecksChanged(FCheckList);
end;

destructor TMainForm.Destroy;
begin
  { The popup only PARENTS its content (LCL never frees a control it does not own), so
    freeing the popup is enough — FDropGrid is owned by this form. }
  FreeAndNil(FDropPopup);
  inherited Destroy;
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

procedure TMainForm.RangedChange(Sender: TObject);
begin
  FEcho.Caption := Format('Clamped value = %.2f  (clamped to 0..100 on blur)', [FRanged.Value]);
end;

procedure TMainForm.ComboDrop(Sender: TObject);
var
  w, h: Integer;
begin
  { TTyComboEdit supplies the field and the chevron and NOTHING else — the host decides what
    drops out of it. Here: a colour grid in a TTyDropdownPopup anchored to the edit. Swap the
    content for a calculator / date picker / tree and the pattern is unchanged. }
  if (FDropPopup <> nil) and FDropPopup.IsOpen then
  begin
    FDropPopup.Close;
    Exit;
  end;
  { Clicking the chevron to CLOSE deactivates the popup first, so this runs with IsOpen
    already False — suppress the immediate re-open (same guard the library's own uses). }
  if (FDropPopup <> nil) and (GetTickCount64 - FDropPopup.CloseUpTick <= 200) then Exit;
  if FDropPopup = nil then
  begin
    FDropPopup := TTyDropdownPopup.Create;
    FDropPopup.Controller := TyDefaultController;   // theme the popup window like everything else
    FDropGrid := TTyColorGrid.Create(Self);         // ships with the 16-colour VGA palette
    FDropGrid.Columns := 8;
    FDropGrid.OnChange := @DropGridPick;
    FDropPopup.SetContent(FDropGrid);
  end;
  w := (180 * FCombo.Font.PixelsPerInch) div 96;
  h := (96 * FCombo.Font.PixelsPerInch) div 96;
  FDropPopup.Popup(FCombo, w, h);
end;

procedure TMainForm.DropGridPick(Sender: TObject);
begin
  // The host writes the popup's result back into the edit, then closes it.
  FCombo.Text := ColorToString(FDropGrid.Selected);
  FDropPopup.Close;
end;

procedure TMainForm.LumChange(Sender: TObject);
begin
  // The luminance bar drives the HS square's brightness: the two controls together form a classic HSL color picker.
  FHS.Value := FLColor.Position;
  ShowPick(FLColor);   // ...and it is a picker in its own right, so it reports too
end;

procedure TMainForm.VleChange(Sender: TObject; ARow: TTyValueRow);
begin
  FEcho.Caption := Format('Changed "%s" = %s', [ARow.Key, ARow.Value]);
end;

procedure TMainForm.VleEditDialog(Sender: TObject; ARow: TTyValueRow);
var dir: string;
begin
  // vekDialog = fully user-side custom: clicking "…" fires this event; each row decides what to pop up and whether to write the value back.
  if SameText(ARow.Key, 'About') then
    // Informational only (read-only content): pop the library's own read-only About dialog; leave ARow.Value unchanged.
    TyShowAbout('About', 'TyControls Rich Inputs example', 'v' + TyVersion,
      'ValueListEditor host-side custom row-handling demo', '© 2026 ACTom', 'MIT License',
      'https://github.com/ACTom/TyControls')
  else
  begin
    // Pop the [library's own] path dialog (not the native one), then write the result back into ARow.Value (which updates the display).
    dir := ARow.Value;
    if TySelectDirectory('Choose data path', '', dir) then
    begin
      ARow.Value := dir;
      FEcho.Caption := Format('Changed "%s" = %s', [ARow.Key, ARow.Value]);
    end;
  end;
end;

procedure TMainForm.ShowPick(Sender: TObject);
var
  c: TColor;
  src: string;
begin
  { Every picker in the library reports the SAME way: it fires OnChange, and the host then
    reads the control's own output property — Selected (TColor) on the swatch pickers,
    SelectedColor (TTyColor, alpha included) on the HSV ones. }
  c := clNone;
  src := '';
  if Sender = FColor then
  begin c := FColor.Selected;                      src := 'ColorBox'; end
  else if Sender = FColorList then
  begin c := FColorList.Selected;                  src := 'ColorListBox'; end
  else if Sender = FColorCombo then
  begin c := FColorCombo.Selected;                 src := 'ColorComboBox'; end
  else if Sender = FColorGrid then
  begin c := FColorGrid.Selected;                  src := 'ColorGrid'; end
  else if Sender = FHS then
  begin c := TyColorToLCL(FHS.SelectedColor);      src := 'HSColorPicker'; end
  else if Sender = FLColor then
  begin c := TyColorToLCL(FLColor.SelectedColor);  src := 'LColorPicker'; end;

  if c = clNone then
  begin
    PickPreview.StyleOverride := '';
    LblPick.Caption := 'Picked: (none)';
    Exit;
  end;
  { TTyShape has no Color property on purpose — its fill is a theme token. To tint ONE
    instance, push a per-instance CSS declaration block through StyleOverride. }
  PickPreview.StyleOverride := 'background: ' + TyColorToHex(TyColorFromLCL(c), False) + ';';
  LblPick.Caption := Format('Picked: %s = %s', [src, ColorToString(c)]);
end;

procedure TMainForm.FontPickChange(Sender: TObject);
var
  fname: string;
  sz: Integer;
begin
  { SelectedFont (combo AND list box) + FontSize are the output half of the WYSIWYG pickers.
    TTyLabel takes its face and size from the THEME rather than from Font.*, so the picked
    values reach the preview through the per-instance StyleOverride. }
  if Sender = FFontList then
    fname := FFontList.SelectedFont
  else
    fname := FFont.SelectedFont;
  sz := FSize.FontSize;                       // FontSize parses the editable field, so a typed size counts too
  if sz < 6 then sz := 6;
  if sz > 28 then sz := 28;                   // capped: the preview label is only 56px tall
  if fname = '' then
    LblFontPreview.StyleOverride := Format('font-size: %dpx;', [sz])
  else
    LblFontPreview.StyleOverride := Format('font-family: %s; font-size: %dpx;', [fname, sz]);
  LblFontEcho.Caption := Format('SelectedFont = %s · FontSize = %d', [fname, FSize.FontSize]);
end;

procedure TMainForm.ChecksChanged(Sender: TObject);
begin
  { Neither check control commits through ItemIndex: TTyCheckListBox reports via OnClickCheck
    and TTyCheckComboBox via OnChange, and the host then reads CheckedCount / Checked[].
    (The dropdown's own field already spells out CheckedText, so the counts suffice here.) }
  LblChecks.Caption := Format('CheckListBox: %d · CheckComboBox: %d',
    [FCheckList.CheckedCount, FCheckCombo.CheckedCount]);
end;

procedure TMainForm.SheetLockChange(Sender: TObject);
begin
  { Grid-level lock: no value cell can be edited at all. (A single row locks itself with its
    own ReadOnly — the 'Theme' row above does exactly that.) }
  FVLE.ReadOnly := ChkSheetLock.Checked;
end;

end.
