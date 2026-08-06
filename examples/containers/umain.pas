unit umain;

{ Phase-5 container & layout demo. Every control is placed in the designer (umain.lfm) and
  streamed in at run time by TTyForm; the code only does the "structural assembly" -- the parts
  that can't be expressed as .lfm properties: relative-layout rules
  (SetRules), header sections (AddSection) with their sort/alignment seed, grouped lists
  (AddGroup/AddItem) and the icon bitmaps they draw, Rebar band widths (SetBandWidth), the
  check-group's initial checks, the host side of TTyScrollPanel's edge auto-pan, and theme
  loading. Theming goes through the global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Controller, tyControls.Form, tyControls.Types, tyControls.Painter,
  tyControls.ColorMath, tyControls.TyLabel, tyControls.Bevel, tyControls.Divider,
  tyControls.PaintPanel, tyControls.SizeBox,
  tyControls.RadioGroup, tyControls.CheckGroup, tyControls.ToolGroupPanel,
  tyControls.ScrollBox, tyControls.ScrollContent, tyControls.ScrollPanel, tyControls.ExPanel, tyControls.Button,
  tyControls.CheckBox,
  tyControls.GridPanel, tyControls.GridCell, tyControls.RelativePanel, tyControls.Edit,
  tyControls.ToolBarEx, tyControls.ControlBar, tyControls.CoolBar,
  tyControls.HeaderControl, tyControls.ListGroupPanel, tyControls.ImageCollection,
  tyControls.BuiltinThemes, tyControls.ComboBox, tyControls.ToggleSwitch;

type
  TMainForm = class(TTyForm)
    Surface: TTyFormSurface;
    TitleBar1: TTyTitleBar;
    DarkSwitch: TTyToggleSwitch;
    ThemeCombo: TTyComboBox;
    DivLeft: TTyDivider;
    DivCenter: TTyDivider;
    DivRight: TTyDivider;
    DivBevel: TTyDivider;
    LblBox: TTyLabel;
    BevelBox: TTyBevel;
    BevelFrameLo: TTyBevel;
    BevelFrameHi: TTyBevel;
    LblLines: TTyLabel;
    BevelTopLine: TTyBevel;
    BevelBottomLine: TTyBevel;
    DivPaint: TTyDivider;
    PaintSurface1: TTyPaintPanel;
    DivGroups: TTyDivider;
    RadioSize: TTyRadioGroup;
    CheckFeatures: TTyCheckGroup;
    ToolClip: TTyToolGroupPanel;
    BtnCut: TTyButton;
    BtnCopy: TTyButton;
    BtnPaste: TTyButton;
    BtnFormat: TTyButton;
    DivScroll: TTyDivider;
    ExAdvanced: TTyExPanel;
    ChkWrap: TTyCheckBox;
    ChkMinimap: TTyCheckBox;
    ChkWhitespace: TTyCheckBox;
    ScrollDemo: TTyScrollBox;
    SbView: TTyScrollContent;
    { The same viewport, but with ALIGNED children — the case where a scroll box has to
      behave like a real container: the rows must stop at the scrollbar instead of running
      under it, and dragging the bar must actually move them. }
    LblAlignScroll: TTyLabel;
    AlignScrollDemo: TTyScrollBox;
    AsBtn1: TTyButton;
    AsBtn2: TTyButton;
    AsBtn3: TTyButton;
    AsBtn4: TTyButton;
    SbBtn1: TTyButton;
    SbBtn2: TTyButton;
    SbBtn3: TTyButton;
    SbBtn4: TTyButton;
    SbBtn5: TTyButton;
    SbBtn6: TTyButton;
    SbBtn7: TTyButton;
    SbBtn8: TTyButton;
    SbBtn9: TTyButton;
    SbBtn10: TTyButton;
    DivLayout: TTyDivider;
    GridForm: TTyGridPanel;
    GfLabelCell0: TTyGridCell;
    GfEditCell0: TTyGridCell;
    GfLabelCell1: TTyGridCell;
    GfEditCell1: TTyGridCell;
    GfLabelCell2: TTyGridCell;
    GfEditCell2: TTyGridCell;
    LblUser: TTyLabel;
    LblMail: TTyLabel;
    LblPhone: TTyLabel;
    EditUser: TTyEdit;
    EditMail: TTyEdit;
    EditPhone: TTyEdit;
    RelForm: TTyRelativePanel;
    BtnTitle: TTyButton;
    BtnCancel: TTyButton;
    BtnOK: TTyButton;
    ListGroups: TTyListGroupPanel;
    HeaderCols: TTyHeaderControl;
    LblHeader: TTyLabel;
    DivBands: TTyDivider;
    BarTools: TTyToolBarEx;
    BarBtn1: TTyButton;
    BarBtn2: TTyButton;
    BarBtn3: TTyButton;
    BarBtn4: TTyButton;
    BarBtn5: TTyButton;
    BarBtn6: TTyButton;
    BarBtn7: TTyButton;
    BarBtn8: TTyButton;
    BarBtn9: TTyButton;
    BarBtn10: TTyButton;
    BarBtn11: TTyButton;
    BarBtn12: TTyButton;
    Rebar: TTyCoolBar;
    Band1: TTyToolBarEx;   { band 1 hosts a real toolbar }
    Band2: TTyEdit;        { band 2 hosts a real search field }
    LblGrip: TTyLabel;
    Grip: TTySizeBox;
    DivMore: TTyDivider;
    LblWrap: TTyLabel;
    BarWrap: TTyToolBarEx;
    WrapBtn1: TTyButton;
    WrapBtn2: TTyButton;
    WrapBtn3: TTyButton;
    WrapBtn4: TTyButton;
    WrapBtn5: TTyButton;
    WrapBtn6: TTyButton;
    WrapBtn7: TTyButton;
    WrapBtn8: TTyButton;
    WrapBtn9: TTyButton;
    WrapBtn10: TTyButton;
    WrapBtn11: TTyButton;
    WrapBtn12: TTyButton;
    LblVLines: TTyLabel;
    BevelLeftLine: TTyBevel;
    BevelRightLine: TTyBevel;
    LblSpacer: TTyLabel;
    BevelSpacerA: TTyBevel;
    BevelSpacer: TTyBevel;     // Shape = tbsSpacer: a real control that paints nothing
    BevelSpacerB: TTyBevel;
    LblPan: TTyLabel;
    PanDemo: TTyScrollPanel;
    PanView: TTyScrollContent;
    PanBtn1: TTyButton;
    PanBtn2: TTyButton;
    PanBtn3: TTyButton;
    PanBtn4: TTyButton;
    PanBtn5: TTyButton;
    PanBtn6: TTyButton;
    PanBtn7: TTyButton;
    PanBtn8: TTyButton;
    PanBtn9: TTyButton;
    PanBtn10: TTyButton;
    LblEx2: TTyLabel;
    ExDisplay: TTyExPanel;
    ChkRuler: TTyCheckBox;
    ChkGuides: TTyCheckBox;
    LblLog: TTyLabel;
    procedure FormCreate(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure DarkSwitchChange(Sender: TObject);
    procedure PaintSurface(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
    { Container events — every one of them just reports into LblLog, which is the point:
      these containers are not decorative, they notify. }
    procedure RadioSizeSelectionChanged(Sender: TObject);
    procedure CheckFeaturesItemChange(Sender: TObject; AIndex: Integer);
    procedure ListGroupsItemClick(Sender: TObject; AGroupIndex, AItemIndex: Integer);
    procedure ListGroupsGroupToggle(Sender: TObject; AGroupIndex: Integer);
    procedure HeaderColsSectionClick(AHeader: TTyHeaderControl; AIndex: Integer);
    procedure HeaderColsSectionResize(AHeader: TTyHeaderControl; AIndex, AWidth: Integer);
    procedure ExPanelExpand(Sender: TObject);
    procedure ExPanelCollapse(Sender: TObject);
    { TTyScrollPanel's edge auto-pan is driven by the HOST: the panel exposes AutoPanTo /
      StopAutoPan and the app feeds it live pointer positions from a drag. }
    procedure PanDemoMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PanDemoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PanDemoMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  private
    FPanDragging: Boolean;            // a left-drag is arming PanDemo's auto-pan
    FListIcons: TTyImageCollection;   // per-row icon masters for ListGroups
    FListImages: TTyVirtualImageList;
    procedure WireRelative;
    procedure WireBands;
    procedure WireLists;
    procedure BuildListIcons;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

resourcestring
  { Every status line the container events compose at run time. English source values, so a
    .po can translate them the same way the .lfm captions are translated. }
  rsLogSize      = 'Size = %s';
  rsLogSizeNone  = 'Size = (nothing selected)';
  rsLogFeature   = 'Feature %s = %s';
  rsOn           = 'on';
  rsOff          = 'off';
  rsLogSelected  = 'Selected: %s';
  rsLogGroup     = 'Group %s %s';
  rsExpanded     = 'expanded';
  rsCollapsed    = 'collapsed';
  rsLogSort      = 'Sort by %s';
  rsLogColWidth  = 'Column %s width = %d';
  rsLogPanel     = 'Panel %s: %s';

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

procedure TMainForm.FormCreate(Sender: TObject);
var
  names: TStringArray;
  i: Integer;
begin
  // Global default controller: once the theme is loaded, every control with Controller=nil uses it
  // (the ActiveController fallback). Built-in themes are compiled in, so the switcher works without
  // locating a themes/ folder.
  TyRegisterBuiltinThemes;
  TyDefaultController.ThemeName := 'default';
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do
    ThemeCombo.Items.Add(names[i]);
  ThemeCombo.ItemIndex := ThemeCombo.Items.IndexOf('default');

  // Initial checks for the check-group (Items were streamed in from the .lfm, so the child controls
  // already exist by FormCreate time).
  CheckFeatures.Checked[0] := True;   // Auto-save
  CheckFeatures.Checked[2] := True;   // Dark mode

  BuildListIcons; // the grouped list's icon column (bitmaps can't live in a .lfm)
  WireRelative;   // relative-layout rules
  WireLists;      // header sections + grouped lists
  WireBands;      // Rebar band widths

  // Scroll viewports: no longer required (the box re-measures itself on Loaded and after every
  // child-layout pass), kept only as an explicit demonstration of the public method.
  ScrollDemo.UpdateScrollRange;
  PanDemo.UpdateScrollRange;

  // Apply the window chrome theme (title bar + rounded corners/shadow), equivalent to building it in code.
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.ThemeComboChange(Sender: TObject);
begin
  if ThemeCombo.ItemIndex < 0 then Exit;
  TyDefaultController.ThemeName := ThemeCombo.Items[ThemeCombo.ItemIndex];
  ApplyChromeTheme(TyDefaultController);   // re-theme the shell on every skin change
  BuildListIcons;                          // re-tint the list icons with the new skin's text colour
end;

procedure TMainForm.DarkSwitchChange(Sender: TObject);
begin
  // Flip the light/dark @mode axis (independent of which theme ThemeCombo picked).
  if DarkSwitch.Checked then
    TyDefaultController.Mode := 'dark'
  else
    TyDefaultController.Mode := 'light';
  ApplyChromeTheme(TyDefaultController);
  BuildListIcons;                          // dark/light flips the icon tint too
end;

procedure TMainForm.WireRelative;
begin
  // Title centered against the top; Cancel pinned bottom-right; OK to the left of Cancel, bottom-aligned to it.
  RelForm.SetRules(BtnTitle, [traCenterHorizontal, traAlignParentTop]);
  RelForm.SetRules(BtnCancel, [traAlignParentRight, traAlignParentBottom]);
  RelForm.SetRules(BtnOK, [trLeftOf, traAlignBottomOf], BtnCancel);
  RelForm.PerformLayout;
end;

procedure TMainForm.WireLists;
var
  g: Integer;
  sec: TTyHeaderSection;
begin
  // Header bar: click a title to toggle sorting, drag a section boundary to resize.
  HeaderCols.AddSection('Name', 96);
  HeaderCols.AddSection('Size', 60);
  HeaderCols.AddSection('Modified date', 64);
  // Open already sorted on 'Name' so the sort triangle is visible without a click, and
  // right-align the numeric 'Size' column (per-section Alignment lives in the record).
  HeaderCols.Sort[0] := hsdAscending;
  sec := HeaderCols.Sections[1];
  sec.Alignment := taRightJustify;
  HeaderCols.Sections[1] := sec;

  // Outlook-style collapsible grouped list (accordion). The trailing index picks an icon
  // out of ListGroups.Images (built in BuildListIcons) -- that icon column IS the Outlook look.
  g := ListGroups.AddGroup('Contact', 0);
  ListGroups.AddItem(g, 'Alice', 1);
  ListGroups.AddItem(g, 'Bob', 1);
  ListGroups.AddItem(g, 'Carol', 1);
  ListGroups.Expanded[g] := True;
  g := ListGroups.AddGroup('Task', 2);
  ListGroups.AddItem(g, 'Write report', 3);
  ListGroups.AddItem(g, 'Publish version', 3);
end;

{ The grouped list's icon set. Bitmaps are runtime data (a .lfm cannot carry them), so the
  four glyphs are drawn here with BGRA and handed to a TTyImageCollection that a
  TTyVirtualImageList exposes to ListGroups.Images -- no external file, so the exe still
  finds its icons when it runs out of lib/<target>/.

  The tint is READ FROM THE THEME (the resolved TyListGroupItem text colour), never
  hard-coded, so every skin and the dark/light switch re-colour the whole set. }
procedure TMainForm.BuildListIcons;
const
  G = 64;   // master edge: larger than any size a row asks for, so every use downsamples
var
  tint: TBGRAPixel;
  itemStyle: TTyStyleSet;

  procedure Emit(const AName: string; AKind: Integer);
  var
    bmp: TBGRABitmap;
    ctx: TBGRACanvas2D;
    i: Integer;
  begin
    bmp := TBGRABitmap.Create(G, G, BGRAPixelTransparent);
    try
      ctx := bmp.Canvas2D;
      ctx.lineCap := 'round';
      ctx.lineJoin := 'round';
      ctx.lineWidth := 7;
      ctx.strokeStyle(tint);
      case AKind of
        0:  // group of people (the 'Contact' group header)
          begin
            bmp.FillEllipseAntialias(23, 24, 11, 11, tint);
            bmp.FillEllipseAntialias(44, 28, 8, 8, tint);
            bmp.FillRoundRectAntialias(6, 40, 40, 58, 8, 8, tint);
            bmp.FillRoundRectAntialias(38, 44, 58, 58, 6, 6, tint);
          end;
        1:  // one person (a contact row)
          begin
            bmp.FillEllipseAntialias(32, 22, 12, 12, tint);
            bmp.FillRoundRectAntialias(13, 40, 51, 58, 9, 9, tint);
          end;
        2:  // a list (the 'Task' group header)
          for i := 0 to 2 do
            bmp.FillRoundRectAntialias(11, 17 + i * 15, 53, 25 + i * 15, 3, 3, tint);
      else  // 3: a tick (a task row)
        begin
          ctx.beginPath;
          ctx.moveTo(13, 33);
          ctx.lineTo(26, 47);
          ctx.lineTo(51, 17);
          ctx.stroke;
        end;
      end;
      FListIcons.AddBitmap(AName, bmp);
    finally
      bmp.Free;
    end;
  end;

begin
  if FListIcons = nil then
  begin
    FListIcons := TTyImageCollection.Create(Self);
    FListImages := TTyVirtualImageList.Create(Self);
    FListImages.Collection := FListIcons;
    // Name order == the ImageIndex values WireLists passes to AddGroup / AddItem.
    FListImages.Names.Text := 'people' + LineEnding + 'person' + LineEnding +
                              'list' + LineEnding + 'check';
    ListGroups.Images := FListImages;
  end;

  itemStyle := TyDefaultController.Model.ResolveStyle('TyListGroupItem', '', [tysNormal]);
  tint := TyColorToBGRA(itemStyle.TextColor);
  tint.alpha := 255;

  Emit('people', 0);
  Emit('person', 1);
  Emit('list',   2);
  Emit('check',  3);
  ListGroups.Invalidate;
end;

{ ---- container events: each one narrates itself into LblLog ---- }

procedure TMainForm.RadioSizeSelectionChanged(Sender: TObject);
begin
  if RadioSize.ItemIndex < 0 then
    LblLog.Caption := rsLogSizeNone
  else
    LblLog.Caption := Format(rsLogSize, [RadioSize.Items[RadioSize.ItemIndex]]);
end;

procedure TMainForm.CheckFeaturesItemChange(Sender: TObject; AIndex: Integer);
var
  state: string;
begin
  // The event carries only the index; the new state is read back off the group.
  if CheckFeatures.Checked[AIndex] then state := rsOn else state := rsOff;
  LblLog.Caption := Format(rsLogFeature, [CheckFeatures.Items[AIndex], state]);
end;

procedure TMainForm.ListGroupsItemClick(Sender: TObject; AGroupIndex, AItemIndex: Integer);
begin
  LblLog.Caption := Format(rsLogSelected, [ListGroups.ItemCaption(AGroupIndex, AItemIndex)]);
end;

procedure TMainForm.ListGroupsGroupToggle(Sender: TObject; AGroupIndex: Integer);
var
  state: string;
begin
  if ListGroups.Expanded[AGroupIndex] then state := rsExpanded else state := rsCollapsed;
  LblLog.Caption := Format(rsLogGroup, [ListGroups.GroupCaption[AGroupIndex], state]);
end;

procedure TMainForm.HeaderColsSectionClick(AHeader: TTyHeaderControl; AIndex: Integer);
begin
  // The strip has already cycled the section's sort by the time this fires.
  LblLog.Caption := Format(rsLogSort, [HeaderCols.SectionText[AIndex]]);
end;

procedure TMainForm.HeaderColsSectionResize(AHeader: TTyHeaderControl; AIndex, AWidth: Integer);
begin
  // Fires ONCE, on release, with the settled width (OnSectionTrack is the live one).
  LblLog.Caption := Format(rsLogColWidth, [HeaderCols.SectionText[AIndex], AWidth]);
end;

procedure TMainForm.ExPanelExpand(Sender: TObject);
begin
  if LblLog <> nil then
    LblLog.Caption := Format(rsLogPanel, [TComponent(Sender).Name, rsExpanded]);
end;

procedure TMainForm.ExPanelCollapse(Sender: TObject);
begin
  // Guarded: ExDisplay collapses while the .lfm is still streaming, before LblLog exists.
  if LblLog <> nil then
    LblLog.Caption := Format(rsLogPanel, [TComponent(Sender).Name, rsCollapsed]);
end;

{ ---- TTyScrollPanel edge auto-pan -------------------------------------------------
  The panel does not invent a drag of its own: the HOST decides what a drag is and feeds
  AutoPanTo the live pointer. Press in the empty strip to the right of the rows, drag
  toward the top or bottom edge, and the panel keeps scrolling (faster the closer to the
  edge) even if the pointer stops moving. }

procedure TMainForm.PanDemoMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  pt: TPoint;
begin
  if Button <> mbLeft then Exit;
  FPanDragging := True;
  pt.X := X; pt.Y := Y;
  PanDemo.AutoPanTo(pt);
end;

procedure TMainForm.PanDemoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  pt: TPoint;
begin
  if not FPanDragging then Exit;
  pt.X := X; pt.Y := Y;
  PanDemo.AutoPanTo(pt);
end;

procedure TMainForm.PanDemoMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FPanDragging := False;
  PanDemo.StopAutoPan;
end;

procedure TMainForm.WireBands;
begin
  // Rebar: two bands resizable via drag grips (band width / min width are code-level, not .lfm properties).
  // The floors are low on purpose: squeeze the toolbar band and its buttons fold into the » chevron.
  Rebar.SetBandWidth(Band1, 170);   Rebar.SetBandMinWidth(Band1, 60);
  Rebar.SetBandWidth(Band2, 140);   Rebar.SetBandMinWidth(Band2, 60);
end;

procedure TMainForm.PaintSurface(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
var ctx: TBGRACanvas2D;
begin
  // Draw straight onto the panel surface with the library painter, composited in the same pass as the panel (owner-draw).
  ctx := APainter.Bitmap.Canvas2D;
  ctx.fillStyle(BGRA(59, 130, 246));
  ctx.fillRect(AContent.Left + 14, AContent.Top + 14, 44, 44);
  ctx.fillStyle(BGRA(16, 185, 129));
  ctx.beginPath;
  ctx.arc(AContent.Left + 96, AContent.Top + 36, 22, 0, 2 * Pi, False);
  ctx.fill;
  APainter.DrawText(AContent, 'OnPaintSurface — the app draws it itself with TTyPainter', 'Segoe UI', 12, 500,
    TyColorFromLCL(clWhite, 255), taCenter, tlBottom, True);
end;

end.
