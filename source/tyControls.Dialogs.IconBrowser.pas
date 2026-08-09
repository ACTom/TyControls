unit tyControls.Dialogs.IconBrowser;
{$mode objfpc}{$H+}

{ Pick a glyph out of an icon font, by eye.

  WHY IT EXISTS. A bundled pack ships around two thousand glyphs and the only way to use one was
  to already know its name. The Object Inspector's GlyphName dropdown is a two-thousand-entry
  combo box -- technically complete, practically useless: nobody scrolls it looking for the icon
  that means "save". So: a grid you can look at, and a search box that filters it.

  IT IS NOT LUCIDE-SPECIFIC, and must not become so. It asks a TTyIconFont for GlyphNames and
  renders whatever comes back, so it serves a hand-mapped font, a bundled pack, or two packs at
  once, and tests/test.lucide's NoCoreUnitReferencesTheBundledFont stays green (a `uses` of the
  pack from here would link 833KB of font into every application that opened any dialog).

  THE GRID IS VIRTUALISED and that is not premature: two thousand cells at 32px is a 64,000px
  tall surface, and rendering a glyph is a font rasterisation, not a blit. Only the visible rows
  are drawn, and each drawn glyph is cached for the size and colour it was drawn at. }

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, Forms,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Component,
  tyControls.Dialogs, tyControls.Edit, tyControls.TyLabel, tyControls.Button,
  tyControls.ScrollBar, tyControls.IconFont, tyControls.Controller, tyControls.StrConsts;

type
  { The glyph grid. Deliberately a private-ish control of this unit rather than a palette
    component: it exists to serve the browser, and a general-purpose icon grid would have to
    answer questions (multi-select, drag, in-place rename) the browser never asks.

    TYPE KEYS ARE BORROWED, on purpose: 'TyListBox' for the surface and 'TyListItem' for the
    selected cell. This is a list of things you pick one of, it should look like every other
    list in the library, and borrowing means all seventeen themes style it correctly on day one
    instead of a brand-new key falling back to the base layer everywhere. The same trade
    TTyColorGrid already makes. }
  TTyIconGrid = class(TTyCustomControl)
  private
    FFont: TTyIconFont;
    FNames: TStringList;          // the FILTERED names, in display order
    FSelected: Integer;           // index into FNames; -1 = none
    FTopRow: Integer;
    FCellSize: Integer;           // logical px, square
    FScroll: TTyScrollBar;
    FOnChange: TNotifyEvent;
    FOnPick: TNotifyEvent;        // double-click / Enter: "this one, and I am done"
    { One rendered glyph, kept for the size+colour it was rendered at. The grid asks for the
      same cell many times (hover, selection, scroll) and a rasterisation per repaint per cell
      would be visible. }
    FCache: array of TBGRABitmap;
    FCacheName: array of string;
    FCacheSize: Integer;
    FCacheColor: TTyColor;
    procedure SetFont(AValue: TTyIconFont);
    procedure SetCellSize(AValue: Integer);
    procedure SetSelected(AValue: Integer);
    procedure ScrollChanged(Sender: TObject);
    procedure DropCache;
    { The cell edge in DEVICE px. Paint can use TTyPainter.Scale, but the hit test and the
      scroll arithmetic run outside a paint and have to do it themselves -- the same
      MulDiv(_, Font.PixelsPerInch, 96) every other control here uses. }
    function CellPx: Integer;
    function CellsPerRow: Integer;
    function RowCount: Integer;
    function VisibleRows: Integer;
    procedure SyncScrollBar;
    procedure EnsureVisible(AIndex: Integer);
    function GlyphFor(AIndex, ASizePx: Integer; AColor: TTyColor): TBGRABitmap;
  protected
    function GetStyleTypeKey: string; override;   // 'TyListBox' -- see the class comment
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Replace the displayed set. The caller owns ANames' contents; they are copied. }
    procedure SetNames(ANames: TStrings);
    function Count: Integer;
    function NameAt(AIndex: Integer): string;
    function IndexOfName(const AName: string): Integer;
    { Cell index at a device point, or -1 outside every cell (the trailing gap of a partly
      filled last row included). Test seam. }
    function CellAt(AX, AY: Integer): Integer;
    property IconFont: TTyIconFont read FFont write SetFont;
    property SelectedIndex: Integer read FSelected write SetSelected;
    property CellSize: Integer read FCellSize write SetCellSize;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnPick: TNotifyEvent read FOnPick write FOnPick;
  end;

  { The dialog. Resizable, because "how many icons can I see at once" is the whole experience
    and 2022 of them do not fit a fixed box. }
  TTyIconBrowserForm = class(TTyDialog)
  private
    FSearch: TTyEdit;
    FGrid: TTyIconGrid;
    FStatus: TTyLabel;
    FFont: TTyIconFont;
    FAll: TStringList;            // every name the font offers, unfiltered
    procedure SearchChanged(Sender: TObject);
    procedure GridChanged(Sender: TObject);
    procedure GridPick(Sender: TObject);
    procedure UpdateStatus;
  protected
    procedure LayoutContent; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
    { The font whose glyphs are shown. Setting it reloads the list. }
    procedure SetIconFont(AValue: TTyIconFont);
    { Narrow the grid to the names containing AText (case-insensitively); '' shows everything.
      Public so the filter is assertable without a window or a keystroke. }
    procedure ApplyFilter(const AText: string);
    { How many names the grid is currently showing (i.e. after the filter). Test seam. }
    function GlyphCount: Integer;
    function GlyphNameAt(AIndex: Integer): string;
    function SelectedGlyphName: string;
    procedure SelectGlyph(const AName: string);
    { In/out, mirroring TTySelectPathForm.Directory: seed it before ShowModal, read it after. }
    property GlyphName: string read SelectedGlyphName write SelectGlyph;
  end;

{ Construct-only builder (no ShowModal), so a test can assert the finished dialog. }
function TyBuildIconBrowserDialog(const ACaption: string;
  AFont: TTyIconFont): TTyIconBrowserForm;

{ The one-liner. LCL-parity var-param shape: AGlyphName is both the initial selection and the
  result, and it is left untouched when the user cancels. }
function TyBrowseIcons(const ACaption: string; AFont: TTyIconFont;
  var AGlyphName: string): Boolean;

type
  { The droppable wrapper, like every other dialog in this library. }
  TTyIconBrowserDialog = class(TTyComponent)
  private
    FCaption: TCaption;
    FIconFont: TTyIconFont;
    FGlyphName: string;
    FOnShow: TNotifyEvent;
    FOnClose: TCloseEvent;
    FOnCanClose: TCloseQueryEvent;
    procedure SetIconFont(AValue: TTyIconFont);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    function Execute: Boolean;
  published
    property Caption: TCaption read FCaption write FCaption;
    { The font to browse. Without one the dialog opens empty and says so, rather than
      pretending the font has no icons. }
    property IconFont: TTyIconFont read FIconFont write SetIconFont;
    { Seeded into the dialog on Execute and written back when the user accepts. }
    property GlyphName: string read FGlyphName write FGlyphName;
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnClose: TCloseEvent read FOnClose write FOnClose;
    property OnCanClose: TCloseQueryEvent read FOnCanClose write FOnCanClose;
  end;

implementation

const
  TyIconCellDefault = 44;   // logical px per cell -- a 24px glyph plus breathing room
  TyIconGlyphInset  = 10;   // logical px of padding inside a cell, total across the axis

{ ============================================================ TTyIconGrid ============= }

constructor TTyIconGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNames := TStringList.Create;
  FSelected := -1;
  FCellSize := TyIconCellDefault;
  TabStop := True;
  FScroll := TTyScrollBar.Create(Self);
  FScroll.Parent := Self;
  FScroll.Kind := sbVertical;
  FScroll.Align := alRight;
  FScroll.OnChange := @ScrollChanged;
end;

destructor TTyIconGrid.Destroy;
begin
  DropCache;
  FNames.Free;
  inherited Destroy;
end;

procedure TTyIconGrid.DropCache;
var i: Integer;
begin
  for i := 0 to High(FCache) do FCache[i].Free;
  SetLength(FCache, 0);
  SetLength(FCacheName, 0);
end;

function TTyIconGrid.GetStyleTypeKey: string;
begin
  Result := 'TyListBox';
end;

procedure TTyIconGrid.SetFont(AValue: TTyIconFont);
begin
  if FFont = AValue then Exit;
  if FFont <> nil then FFont.RemoveFreeNotification(Self);
  FFont := AValue;
  if FFont <> nil then FFont.FreeNotification(Self);
  DropCache;
  Invalidate;
end;

procedure TTyIconGrid.SetCellSize(AValue: Integer);
begin
  if AValue < 16 then AValue := 16;
  if FCellSize = AValue then Exit;
  FCellSize := AValue;
  DropCache;
  SyncScrollBar;
  Invalidate;
end;

procedure TTyIconGrid.SetNames(ANames: TStrings);
begin
  FNames.Assign(ANames);
  { The cache is keyed by INDEX, so a new list invalidates all of it. }
  DropCache;
  SetLength(FCache, FNames.Count);
  SetLength(FCacheName, FNames.Count);
  FSelected := -1;
  FTopRow := 0;
  SyncScrollBar;
  Invalidate;
end;

function TTyIconGrid.Count: Integer;
begin
  Result := FNames.Count;
end;

function TTyIconGrid.NameAt(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= FNames.Count) then Exit('');
  Result := FNames[AIndex];
end;

function TTyIconGrid.IndexOfName(const AName: string): Integer;
var i: Integer;
begin
  for i := 0 to FNames.Count - 1 do
    if SameText(FNames[i], AName) then Exit(i);
  Result := -1;
end;

procedure TTyIconGrid.SetSelected(AValue: Integer);
begin
  if AValue < -1 then AValue := -1;
  if AValue >= FNames.Count then AValue := FNames.Count - 1;
  if FSelected = AValue then Exit;
  FSelected := AValue;
  EnsureVisible(FSelected);
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

function TTyIconGrid.CellPx: Integer;
begin
  Result := MulDiv(FCellSize, Font.PixelsPerInch, 96);
  if Result < 8 then Result := 8;
end;

function TTyIconGrid.CellsPerRow: Integer;
var usable, cell: Integer;
begin
  cell := CellPx;
  usable := ClientWidth;
  if FScroll <> nil then Dec(usable, FScroll.Width);
  if (cell <= 0) or (usable <= 0) then Exit(1);
  Result := Math.Max(1, usable div cell);
end;

function TTyIconGrid.RowCount: Integer;
begin
  if FNames.Count = 0 then Exit(0);
  Result := (FNames.Count + CellsPerRow - 1) div CellsPerRow;
end;

function TTyIconGrid.VisibleRows: Integer;
var cell: Integer;
begin
  cell := CellPx;
  if cell <= 0 then Exit(1);
  Result := Math.Max(1, ClientHeight div cell);
end;

procedure TTyIconGrid.SyncScrollBar;
var rows, vis: Integer;
begin
  if FScroll = nil then Exit;
  rows := RowCount;
  vis := VisibleRows;
  FScroll.Min := 0;
  FScroll.Max := Math.Max(0, rows - vis);
  FScroll.PageSize := 1;             { Max is already "last legal top row", so a page is a row }
  FScroll.LargeChange := Math.Max(1, vis - 1);
  FScroll.Visible := rows > vis;
  if FTopRow > FScroll.Max then FTopRow := FScroll.Max;
  FScroll.Position := FTopRow;
end;

procedure TTyIconGrid.ScrollChanged(Sender: TObject);
begin
  if FScroll = nil then Exit;
  if FTopRow = FScroll.Position then Exit;
  FTopRow := FScroll.Position;
  Invalidate;
end;

procedure TTyIconGrid.EnsureVisible(AIndex: Integer);
var row, per, vis: Integer;
begin
  if AIndex < 0 then Exit;
  per := CellsPerRow;
  if per <= 0 then Exit;
  row := AIndex div per;
  vis := VisibleRows;
  if row < FTopRow then FTopRow := row
  else if row >= FTopRow + vis then FTopRow := row - vis + 1;
  if FTopRow < 0 then FTopRow := 0;
  SyncScrollBar;
end;

procedure TTyIconGrid.Resize;
begin
  inherited Resize;
  SyncScrollBar;
  { Re-run it here, not just on selection: a dialog seeds its selection BEFORE LayoutContent
    gives this control a size, and CellsPerRow/VisibleRows on a zero-sized control put the
    selected cell on an imaginary row. Without this the browser opened at the top of the list
    with the pre-selected glyph scrolled out of sight -- and, because nothing was highlighted
    on screen, looking like it had ignored the seed entirely. }
  EnsureVisible(FSelected);
  Invalidate;
end;

function TTyIconGrid.GlyphFor(AIndex, ASizePx: Integer; AColor: TTyColor): TBGRABitmap;
begin
  Result := nil;
  if (FFont = nil) or (AIndex < 0) or (AIndex >= FNames.Count) then Exit;
  { One cache for the whole grid, dropped wholesale when the size or the ink changes. Keying
    per cell would mean 2022 keys to compare; the grid only ever draws at one size at a time. }
  if (FCacheSize <> ASizePx) or (FCacheColor <> AColor) then
  begin
    DropCache;
    SetLength(FCache, FNames.Count);
    SetLength(FCacheName, FNames.Count);
    FCacheSize := ASizePx;
    FCacheColor := AColor;
  end;
  if AIndex > High(FCache) then Exit;
  if (FCache[AIndex] = nil) or (FCacheName[AIndex] <> FNames[AIndex]) then
  begin
    FreeAndNil(FCache[AIndex]);
    FCache[AIndex] := FFont.RenderGlyph(FNames[AIndex], ASizePx, AColor);
    FCacheName[AIndex] := FNames[AIndex];
  end;
  Result := FCache[AIndex];
end;

function TTyIconGrid.CellAt(AX, AY: Integer): Integer;
var per, cell, col, row, usable: Integer;
begin
  Result := -1;
  cell := CellPx;
  if cell <= 0 then Exit;
  usable := ClientWidth;
  if (FScroll <> nil) and FScroll.Visible then Dec(usable, FScroll.Width);
  if (AX < 0) or (AX >= usable) or (AY < 0) or (AY >= ClientHeight) then Exit;
  per := CellsPerRow;
  col := AX div cell;
  if col >= per then Exit;                 { the trailing gap at the right edge }
  row := FTopRow + (AY div cell);
  Result := row * per + col;
  if (Result < 0) or (Result >= FNames.Count) then Result := -1;
end;

procedure TTyIconGrid.Paint;
var
  P: TTyPainter;
  st, selSt: TTyStyleSet;
  R, cellR: TRect;
  cell, per, vis, idx, row, col, gsz, x, y: Integer;
  ink, selInk: TTyColor;
  bmp: TBGRABitmap;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ClientWidth, ClientHeight);
    P.BeginPaint(Canvas, ClientRect, Font.PixelsPerInch);
    st := CurrentStyle;
    { The selected cell is painted as a list ITEM in its active state, so selection matches
      every other list in the library and follows a skin without a rule of its own. }
    selSt := ActiveController.Model.ResolveStyle('TyListItem', StyleClass, [tysActive]);
    ink := st.TextColor;
    selInk := selSt.TextColor;
    if TyAlphaOf(selInk) = 0 then selInk := ink;

    P.FillBackground(R, st.Background, 0);

    cell := CellPx;
    per := CellsPerRow;
    vis := VisibleRows;
    gsz := Math.Max(8, cell - P.Scale(TyIconGlyphInset));
    if (cell > 0) and (FNames.Count > 0) then
      for row := 0 to vis do            { one past, so a partly visible last row still draws }
        for col := 0 to per - 1 do
        begin
          idx := (FTopRow + row) * per + col;
          if (idx < 0) or (idx >= FNames.Count) then Continue;
          x := col * cell;
          y := row * cell;
          cellR := Rect(x, y, x + cell, y + cell);
          if idx = FSelected then
            P.FillBackground(cellR, selSt.Background, 4);
          bmp := GlyphFor(idx, gsz, IfThen(idx = FSelected, Int64(selInk), Int64(ink)));
          if bmp <> nil then
            P.DrawGlyphBitmap(Rect(x + (cell - bmp.Width) div 2, y + (cell - bmp.Height) div 2,
              x + (cell - bmp.Width) div 2 + bmp.Width,
              y + (cell - bmp.Height) div 2 + bmp.Height), bmp);
        end;
    { Nothing to show is a STATE, not a blank panel: an empty grid with no message reads as
      "the dialog is broken". }
    if FNames.Count = 0 then
      P.DrawText(R, rsDlgIconNoMatches, st.FontName, st.FontSize,
        st.FontWeight, ink, taCenter, tlCenter, False);
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyIconGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var idx: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  idx := CellAt(X, Y);
  if idx >= 0 then SetSelected(idx);
end;

procedure TTyIconGrid.DblClick;
begin
  inherited DblClick;
  if (FSelected >= 0) and Assigned(FOnPick) then FOnPick(Self);
end;

procedure TTyIconGrid.KeyDown(var Key: Word; Shift: TShiftState);
var per, vis, n: Integer;
begin
  per := CellsPerRow;
  vis := VisibleRows;
  n := FSelected;
  case Key of
    VK_LEFT:   if n > 0 then n := n - 1 else n := 0;
    VK_RIGHT:  n := n + 1;
    VK_UP:     n := n - per;
    VK_DOWN:   n := n + per;
    VK_PRIOR:  n := n - per * vis;
    VK_NEXT:   n := n + per * vis;
    VK_HOME:   n := 0;
    VK_END:    n := FNames.Count - 1;
    VK_RETURN:
      begin
        if (FSelected >= 0) and Assigned(FOnPick) then FOnPick(Self);
        Key := 0;
        Exit;
      end;
  else
    inherited KeyDown(Key, Shift);
    Exit;
  end;
  if n < 0 then n := 0;
  if n >= FNames.Count then n := FNames.Count - 1;
  SetSelected(n);
  Key := 0;
end;

function TTyIconGrid.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var step: Integer;
begin
  step := 3;
  if WheelDelta > 0 then Dec(FTopRow, step) else Inc(FTopRow, step);
  if FTopRow < 0 then FTopRow := 0;
  SyncScrollBar;
  Invalidate;
  Result := True;
end;

{ ======================================================= TTyIconBrowserForm ========== }

constructor TTyIconBrowserForm.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Caption := rsDlgIconBrowserTitle;
  Resizable := True;
  Constraints.MinWidth := 420;
  Constraints.MinHeight := 320;
  FAll := TStringList.Create;

  FSearch := TTyEdit.Create(Self);
  FSearch.Parent := Self;
  FSearch.TextHint := rsDlgIconSearchHint;

  FGrid := TTyIconGrid.Create(Self);
  FGrid.Parent := Self;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;

  { Handlers only after every child exists, so nothing fires into a half-built form. }
  FSearch.OnChange := @SearchChanged;
  FGrid.OnChange := @GridChanged;
  FGrid.OnPick := @GridPick;

  AddButton(rsMsgBtnOK, mrOK, True, False);
  AddButton(rsMsgBtnCancel, mrCancel, False, True);
  AutoSizeToContent(560, 420);
  LayoutContent;
  UpdateStatus;
end;

destructor TTyIconBrowserForm.Destroy;
begin
  FAll.Free;
  inherited Destroy;
end;

procedure TTyIconBrowserForm.SetIconFont(AValue: TTyIconFont);
begin
  FFont := AValue;
  FGrid.IconFont := AValue;
  FAll.Clear;
  if FFont <> nil then FFont.GetGlyphNamesInto(FAll);
  ApplyFilter(FSearch.Text);
end;

procedure TTyIconBrowserForm.ApplyFilter(const AText: string);
var
  shown: TStringList;
  i: Integer;
  needle, keep: string;
begin
  needle := LowerCase(Trim(AText));
  shown := TStringList.Create;
  try
    for i := 0 to FAll.Count - 1 do
    begin
      if needle = '' then
        shown.Add(FAll[i])
      else
      begin
        keep := LowerCase(FAll[i]);
        if Pos(needle, keep) > 0 then shown.Add(FAll[i]);
      end;
    end;
    { Substring, not prefix: icon names are hyphenated compounds ('arrow-down-left'), and a
      user hunting for "down" would find nothing under a prefix match. }
    FGrid.SetNames(shown);
  finally
    shown.Free;
  end;
  UpdateStatus;
end;

procedure TTyIconBrowserForm.SearchChanged(Sender: TObject);
begin
  ApplyFilter(FSearch.Text);
end;

procedure TTyIconBrowserForm.GridChanged(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TTyIconBrowserForm.GridPick(Sender: TObject);
begin
  { Double-click / Enter on a cell is "this one" -- the same shortcut every file dialog has. }
  ModalResult := mrOK;
end;

procedure TTyIconBrowserForm.UpdateStatus;
begin
  if FStatus = nil then Exit;
  if SelectedGlyphName <> '' then
    FStatus.Caption := SelectedGlyphName
  else
    FStatus.Caption := Format(rsDlgIconCount, [FGrid.Count]);
end;

function TTyIconBrowserForm.GlyphCount: Integer;
begin
  Result := FGrid.Count;
end;

function TTyIconBrowserForm.GlyphNameAt(AIndex: Integer): string;
begin
  Result := FGrid.NameAt(AIndex);
end;

function TTyIconBrowserForm.SelectedGlyphName: string;
begin
  Result := FGrid.NameAt(FGrid.SelectedIndex);
end;

procedure TTyIconBrowserForm.SelectGlyph(const AName: string);
var idx: Integer;
begin
  idx := FGrid.IndexOfName(AName);
  if idx >= 0 then FGrid.SelectedIndex := idx;
  UpdateStatus;
end;

procedure TTyIconBrowserForm.LayoutContent;
const Gap = 8;
var r: TRect; x, w, editH, statusH: Integer;
begin
  if FGrid = nil then Exit;      { Resize can fire before construction finishes }
  r := ContentRect;
  x := r.Left + TyDlgPad;
  w := (r.Right - r.Left) - 2 * TyDlgPad;
  editH := TyDensityHeight(nil, TyDlgEditH);
  statusH := 20;
  FSearch.SetBounds(x, r.Top + TyDlgPad, w, editH);
  FStatus.SetBounds(x, r.Bottom - TyDlgPad - statusH, w, statusH);
  FGrid.SetBounds(x, r.Top + TyDlgPad + editH + Gap, w,
    (r.Bottom - r.Top) - 2 * TyDlgPad - editH - statusH - 2 * Gap);
end;

{ ============================================================ entry points =========== }

function TyBuildIconBrowserDialog(const ACaption: string;
  AFont: TTyIconFont): TTyIconBrowserForm;
begin
  Result := TTyIconBrowserForm.CreateNew(Application);
  if ACaption <> '' then Result.Caption := ACaption
  else Result.Caption := rsDlgIconBrowserTitle;
  Result.SetIconFont(AFont);
  Result.LayoutContent;
end;

function TyBrowseIcons(const ACaption: string; AFont: TTyIconFont;
  var AGlyphName: string): Boolean;
var d: TTyIconBrowserForm;
begin
  d := TyBuildIconBrowserDialog(ACaption, AFont);
  try
    d.GlyphName := AGlyphName;                 // pre-select (in)
    Result := (d.ShowModal = mrOK);
    if Result then AGlyphName := d.GlyphName;  // chosen glyph (out)
  finally
    d.Free;
  end;
end;

{ ======================================================= TTyIconBrowserDialog ======== }

procedure TTyIconBrowserDialog.SetIconFont(AValue: TTyIconFont);
begin
  if FIconFont = AValue then Exit;
  if FIconFont <> nil then FIconFont.RemoveFreeNotification(Self);
  FIconFont := AValue;
  if FIconFont <> nil then FIconFont.FreeNotification(Self);
end;

procedure TTyIconBrowserDialog.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FIconFont) then FIconFont := nil;
end;

function TTyIconBrowserDialog.Execute: Boolean;
var d: TTyIconBrowserForm;
begin
  { Inlined rather than delegated to TyBrowseIcons so the wrapper's OnShow/OnClose/OnCanClose
    can be forwarded to the real form -- the same reason every other dialog wrapper here
    inlines. }
  d := TyBuildIconBrowserDialog(FCaption, FIconFont);
  try
    d.GlyphName := FGlyphName;
    TyForwardDialogEvents(d, FOnShow, FOnClose, FOnCanClose);
    Result := (d.ShowModal = mrOK);
    if Result then FGlyphName := d.GlyphName;
  finally
    d.Free;
  end;
end;

end.
