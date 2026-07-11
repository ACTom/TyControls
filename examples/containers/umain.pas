unit umain;

{ Phase-5 container & layout demo. Every control is placed in the designer (umain.lfm) and
  streamed in at run time by TTyForm; the code only does the "structural assembly" -- the parts
  that can't be expressed as .lfm properties: grid cells (SetCell), relative-layout rules
  (SetRules), header sections (AddSection), grouped lists (AddGroup/AddItem), Rebar band widths
  (SetBandWidth), the check-group's initial checks, and theme loading. Theming goes through the
  global TyDefaultController. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Forms, Controls, BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Controller, tyControls.Form, tyControls.Types, tyControls.Painter,
  tyControls.ColorMath, tyControls.TyLabel, tyControls.Bevel, tyControls.Divider,
  tyControls.PaintPanel, tyControls.SizeBox,
  tyControls.RadioGroup, tyControls.CheckGroup, tyControls.ToolGroupPanel,
  tyControls.ScrollBox, tyControls.ExPanel, tyControls.Button, tyControls.CheckBox,
  tyControls.GridPanel, tyControls.RelativePanel, tyControls.Edit,
  tyControls.ToolBarEx, tyControls.ControlBar, tyControls.CoolBar, tyControls.Panel,
  tyControls.HeaderControl, tyControls.ListGroupPanel;

type
  TMainForm = class(TTyForm)
    TitleBar1: TTyTitleBar;
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
    Band1: TTyPanel;
    Band2: TTyPanel;
    LblGrip: TTyLabel;
    Grip: TTySizeBox;
    procedure FormCreate(Sender: TObject);
    procedure PaintSurface(Sender: TObject; APainter: TTyPainter; const AContent: TRect);
  private
    procedure WireGrid;
    procedure WireRelative;
    procedure WireBands;
    procedure WireLists;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

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
begin
  // Global default controller: once the theme is loaded, every control with Controller=nil uses it
  // (the ActiveController fallback).
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // Initial checks for the check-group (Items were streamed in from the .lfm, so the child controls
  // already exist by FormCreate time).
  CheckFeatures.Checked[0] := True;   // Auto-save
  CheckFeatures.Checked[2] := True;   // Dark mode

  WireGrid;       // grid cells + track sizes
  WireRelative;   // relative-layout rules
  WireLists;      // header sections + grouped lists
  WireBands;      // Rebar band widths

  // Scroll viewport: the content children stream in from the .lfm (after the Resize that Width/Height
  // trigger), so recompute the scroll range once more here.
  ScrollDemo.UpdateScrollRange;

  // Apply the window chrome theme (title bar + rounded corners/shadow), equivalent to building it in code.
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.WireGrid;
begin
  // Left column fixed at 56px for labels, right column star-sized for the edits; 3 rows.
  GridForm.SetColumnStyle(0, tgtAbsolute, 56);
  GridForm.SetColumnStyle(1, tgtStar);
  GridForm.SetCell(LblUser, 0, 0);   GridForm.SetCell(EditUser, 1, 0);
  GridForm.SetCell(LblMail, 0, 1);   GridForm.SetCell(EditMail, 1, 1);
  GridForm.SetCell(LblPhone, 0, 2);  GridForm.SetCell(EditPhone, 1, 2);
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
var g: Integer;
begin
  // Header bar: click a title to toggle sorting, drag a section boundary to resize.
  HeaderCols.AddSection('名称', 96);
  HeaderCols.AddSection('大小', 60);
  HeaderCols.AddSection('修改日期', 64);

  // Outlook-style collapsible grouped list (accordion).
  g := ListGroups.AddGroup('联系人');
  ListGroups.AddItem(g, 'Alice');
  ListGroups.AddItem(g, 'Bob');
  ListGroups.AddItem(g, 'Carol');
  ListGroups.Expanded[g] := True;
  g := ListGroups.AddGroup('任务');
  ListGroups.AddItem(g, '写报告');
  ListGroups.AddItem(g, '发布版本');
end;

procedure TMainForm.WireBands;
begin
  // Rebar: two bands resizable via drag grips (band width / min width are code-level, not .lfm properties).
  Rebar.SetBandWidth(Band1, 220);   Rebar.SetBandMinWidth(Band1, 90);
  Rebar.SetBandWidth(Band2, 260);   Rebar.SetBandMinWidth(Band2, 90);
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
  APainter.DrawText(AContent, 'OnPaintSurface — 应用用 TTyPainter 自绘', 'Segoe UI', 12, 500,
    TyColorFromLCL(clWhite, 255), taCenter, tlBottom, True);
end;

end.
