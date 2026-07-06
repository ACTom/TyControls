unit tyControls.RibbonBackstage;
{$mode objfpc}{$H+}

{ TTyRibbonBackstage — the Office "File" backstage: a full-window overlay (covering
  everything BELOW the title bar) with an accent command sidebar on the left and a
  content area on the right. Shown by TTyRibbonAppMenu when a Backstage is assigned
  (instead of a small dropdown). A back arrow (or Escape) closes it.

  Colours are token-driven (no new .tycss rule): the sidebar uses the accent 'TyButton'
  'primary' style, the content uses the 'TyRibbon' surface — so it follows the theme.
  Pure geometry (sidebar/row rects, row-at-Y) is unit-tested headlessly; the on-screen
  look + the show-over-form interaction need a real machine. }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.IconFont,
  tyControls.ImageCollection;

const
  TyBackstageSidebarW = 180;   // logical px, sidebar width
  TyBackstageBackH    = 44;     // logical px, the back-arrow band height at the top
  TyBackstageRowH     = 34;     // logical px, a command row height
  TyBackstageBackRow  = -2;     // TyBackstageRowAt sentinel: the back-arrow band
  TyBackstageNoRow    = -1;     // TyBackstageRowAt sentinel: neither back nor a row
  TyBackstageIconX    = 14;     // logical px, left x of a row's icon (when present)
  TyBackstageIconSize = 18;     // logical px, row icon edge length
  TyBackstageTextInset = 40;    // logical px, left inset of a row's text (reserves the icon column)

type
  TTyBackstageSelectEvent = procedure(Sender: TObject; AIndex: Integer) of object;

  TTyRibbonBackstage = class(TTyCustomControl)
  private
    FCommands: TStrings;
    FCommandGlyphs: TStrings;
    FIconFont: TTyIconFont;
    FImages: TTyImageCollection;
    FItemIndex: Integer;
    FHoverIndex: Integer;
    FSidebarWidth: Integer;
    FOnCommandSelect: TTyBackstageSelectEvent;
    FOnClose: TNotifyEvent;
    procedure SetCommands(AValue: TStrings);
    procedure SetCommandGlyphs(AValue: TStrings);
    procedure SetIconFont(AValue: TTyIconFont);
    procedure SetImages(AValue: TTyImageCollection);
    procedure SetItemIndex(AValue: Integer);
    procedure CommandsChanged(Sender: TObject);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Cover AHost (a form) below its top ATopPx px (the title-bar height), show + focus,
      and bring to front. Anchored so it tracks the host's size. }
    procedure ShowOver(AHost: TWinControl; ATopPx: Integer);
    procedure Close;
    { The content area (device px, client-local) to the RIGHT of the sidebar — where an
      app can place its own content control for the selected command (a recent-files list,
      document info, …). Anchor it [akLeft,akTop,akRight,akBottom] so it tracks resizes. }
    function ContentRect: TRect;
  published
    property Commands: TStrings read FCommands write SetCommands;
    { Optional per-command glyph names (index-matched to Commands; an empty or missing
      entry = no icon), rendered from IconFont at the left of each row. }
    property CommandGlyphs: TStrings read FCommandGlyphs write SetCommandGlyphs;
    { Icon-font source for the CommandGlyphs (font glyphs; Windows-only fonts like MDL2). }
    property IconFont: TTyIconFont read FIconFont write SetIconFont;
    { Cross-platform IMAGE source for the CommandGlyphs (BGRA icons). When set it WINS over
      IconFont — the named icon is drawn tinted to the row text color, identically on every OS. }
    property Images: TTyImageCollection read FImages write SetImages;
    property ItemIndex: Integer read FItemIndex write SetItemIndex default -1;
    property SidebarWidth: Integer read FSidebarWidth write FSidebarWidth default TyBackstageSidebarW;
    property OnCommandSelect: TTyBackstageSelectEvent read FOnCommandSelect write FOnCommandSelect;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

{ Pure geometry (device px, (0,0)-local). }
function TyBackstageRowRect(AIndex, ASidebarWpx, ABackHpx, ARowHpx: Integer): TRect;
{ Which sidebar element a click Y falls on: TyBackstageBackRow (back band),
  a 0-based command index, or TyBackstageNoRow. AX must be inside the sidebar. }
function TyBackstageRowAt(AY, ABackHpx, ARowHpx, ACount: Integer): Integer;

implementation

// ---------------------------------------------------------------------------
// Pure geometry
// ---------------------------------------------------------------------------
function TyBackstageRowRect(AIndex, ASidebarWpx, ABackHpx, ARowHpx: Integer): TRect;
begin
  Result := Rect(0, ABackHpx + AIndex * ARowHpx, ASidebarWpx, ABackHpx + (AIndex + 1) * ARowHpx);
end;

function TyBackstageRowAt(AY, ABackHpx, ARowHpx, ACount: Integer): Integer;
var
  idx: Integer;
begin
  if AY < ABackHpx then Exit(TyBackstageBackRow);
  if ARowHpx <= 0 then Exit(TyBackstageNoRow);
  idx := (AY - ABackHpx) div ARowHpx;
  if (idx >= 0) and (idx < ACount) then
    Result := idx
  else
    Result := TyBackstageNoRow;
end;

// ---------------------------------------------------------------------------
// TTyRibbonBackstage
// ---------------------------------------------------------------------------
constructor TTyRibbonBackstage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csNoDesignVisible, csAcceptsControls];
  FCommands := TStringList.Create;
  TStringList(FCommands).OnChange := @CommandsChanged;
  FCommandGlyphs := TStringList.Create;
  FItemIndex := -1;
  FHoverIndex := TyBackstageNoRow;
  FSidebarWidth := TyBackstageSidebarW;
  TabStop := True;
  Visible := False;
end;

destructor TTyRibbonBackstage.Destroy;
begin
  FCommands.Free;
  FCommandGlyphs.Free;
  inherited Destroy;
end;

function TTyRibbonBackstage.ContentRect: TRect;
var
  sbW: Integer;
begin
  sbW := MulDiv(FSidebarWidth, Font.PixelsPerInch, 96);
  Result := Rect(sbW, 0, ClientWidth, ClientHeight);
end;

procedure TTyRibbonBackstage.SetCommandGlyphs(AValue: TStrings);
begin
  if AValue = nil then FCommandGlyphs.Clear else FCommandGlyphs.Assign(AValue);
  Invalidate;
end;

procedure TTyRibbonBackstage.SetIconFont(AValue: TTyIconFont);
begin
  if FIconFont = AValue then Exit;
  if FIconFont <> nil then FIconFont.RemoveFreeNotification(Self);
  FIconFont := AValue;
  if FIconFont <> nil then FIconFont.FreeNotification(Self);
  Invalidate;
end;

procedure TTyRibbonBackstage.SetImages(AValue: TTyImageCollection);
begin
  if FImages = AValue then Exit;
  if FImages <> nil then FImages.RemoveFreeNotification(Self);
  FImages := AValue;
  if FImages <> nil then FImages.FreeNotification(Self);
  Invalidate;
end;

procedure TTyRibbonBackstage.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FIconFont) then
    FIconFont := nil;
  if (Operation = opRemove) and (AComponent = FImages) then
    FImages := nil;
end;

function TTyRibbonBackstage.GetStyleTypeKey: string;
begin
  Result := 'TyRibbon';   // content surface; the sidebar resolves the accent separately
end;

procedure TTyRibbonBackstage.SetCommands(AValue: TStrings);
begin
  if AValue = nil then FCommands.Clear else FCommands.Assign(AValue);
end;

procedure TTyRibbonBackstage.CommandsChanged(Sender: TObject);
begin
  if FItemIndex >= FCommands.Count then FItemIndex := -1;
  if FHoverIndex >= FCommands.Count then FHoverIndex := TyBackstageNoRow;
  Invalidate;
end;

procedure TTyRibbonBackstage.SetItemIndex(AValue: Integer);
begin
  if AValue < -1 then AValue := -1;
  if AValue >= FCommands.Count then AValue := FCommands.Count - 1;
  if FItemIndex = AValue then Exit;
  FItemIndex := AValue;
  Invalidate;
  if Assigned(FOnCommandSelect) then FOnCommandSelect(Self, FItemIndex);
end;

procedure TTyRibbonBackstage.ShowOver(AHost: TWinControl; ATopPx: Integer);
begin
  if AHost = nil then Exit;
  Parent := AHost;
  Align := alNone;
  Anchors := [akLeft, akTop, akRight, akBottom];
  SetBounds(0, ATopPx, AHost.ClientWidth, AHost.ClientHeight - ATopPx);
  Visible := True;
  BringToFront;
  if CanFocus then
    try SetFocus except end;
end;

procedure TTyRibbonBackstage.Close;
begin
  if not Visible then Exit;
  Visible := False;
  if Assigned(FOnClose) then FOnClose(Self);
end;

procedure TTyRibbonBackstage.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  ContentS, SideS, RowS: TTyStyleSet;
  W, H, sbW, backH, rowH, i, cy, fs, gsz: Integer;
  rr: TRect;
  arrowCx, arrowCy: Integer;
  glyph: TBGRABitmap;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    W := ARect.Right - ARect.Left;
    H := ARect.Bottom - ARect.Top;
    sbW := P.Scale(FSidebarWidth);
    backH := P.Scale(TyBackstageBackH);
    rowH := P.Scale(TyBackstageRowH);

    // Content surface (right of the sidebar) via the TyRibbon token.
    ContentS := CurrentStyle;
    if tpBackground in ContentS.Present then
      P.FillBackground(Rect(0, 0, W, H), ContentS.Background, 0);

    // Sidebar accent panel via the 'TyButton' primary style.
    SideS := ActiveController.Model.ResolveStyle('TyButton', 'primary', []);
    if tpBackground in SideS.Present then
      P.FillBackground(Rect(0, 0, sbW, H), SideS.Background, 0);
    fs := SideS.FontSize; if fs <= 0 then fs := 10;

    // Back arrow (a left chevron) in the top band.
    arrowCx := P.Scale(22);
    arrowCy := backH div 2;
    P.DrawGlyph(Rect(arrowCx - P.Scale(9), arrowCy - P.Scale(9),
      arrowCx + P.Scale(9), arrowCy + P.Scale(9)), tgArrowLeft, SideS.TextColor, 2);

    // Command rows.
    for i := 0 to FCommands.Count - 1 do
    begin
      rr := Rect(0, backH + i * rowH, sbW, backH + (i + 1) * rowH);
      if i = FItemIndex then
        RowS := ActiveController.Model.ResolveStyle('TyButton', 'primary', [tysActive])
      else if i = FHoverIndex then
        RowS := ActiveController.Model.ResolveStyle('TyButton', 'primary', [tysHover])
      else
        RowS := SideS;
      if (i = FItemIndex) or (i = FHoverIndex) then
        if tpBackground in RowS.Present then
          P.FillBackground(rr, RowS.Background, 0);
      // Optional per-command icon at the left; text starts past the icon column. A
      // cross-platform image (tinted) wins over the icon font.
      if (i < FCommandGlyphs.Count) and (FCommandGlyphs[i] <> '') then
      begin
        gsz := P.Scale(TyBackstageIconSize);
        if FImages <> nil then
        begin
          glyph := FImages.GetBitmap(FCommandGlyphs[i], gsz);
          TyTintBitmapAlpha(glyph, RowS.TextColor);
        end
        else if FIconFont <> nil then
          glyph := FIconFont.RenderGlyph(FCommandGlyphs[i], gsz, RowS.TextColor)
        else
          glyph := nil;
        if glyph <> nil then
        try
          P.Bitmap.PutImage(P.Scale(TyBackstageIconX),
            rr.Top + (rowH - glyph.Height) div 2, glyph, dmDrawWithTransparency);
        finally
          glyph.Free;
        end;
      end;
      cy := rr.Left + P.Scale(TyBackstageTextInset);
      P.DrawText(Rect(cy, rr.Top, rr.Right - P.Scale(8), rr.Bottom),
        FCommands[i], SideS.FontName, fs, SideS.FontWeight, RowS.TextColor,
        taLeftJustify, tlCenter, True);
    end;

    // Content: the selected command's caption, large, in the content area.
    if (FItemIndex >= 0) and (FItemIndex < FCommands.Count) then
      P.DrawText(Rect(sbW + P.Scale(40), P.Scale(30), W - P.Scale(20), P.Scale(70)),
        FCommands[FItemIndex], ContentS.FontName, fs + 8, 600, ContentS.TextColor,
        taLeftJustify, tlTop, True);

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyRibbonBackstage.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyRibbonBackstage.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  sbW, backH, rowH, r: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  sbW := MulDiv(FSidebarWidth, Font.PixelsPerInch, 96);
  if X >= sbW then Exit;   // clicks in the content area do nothing here
  backH := MulDiv(TyBackstageBackH, Font.PixelsPerInch, 96);
  rowH := MulDiv(TyBackstageRowH, Font.PixelsPerInch, 96);
  r := TyBackstageRowAt(Y, backH, rowH, FCommands.Count);
  if r = TyBackstageBackRow then
    Close
  else if r >= 0 then
    ItemIndex := r;
end;

procedure TTyRibbonBackstage.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  sbW, backH, rowH, r: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  sbW := MulDiv(FSidebarWidth, Font.PixelsPerInch, 96);
  r := TyBackstageNoRow;
  if X < sbW then
  begin
    backH := MulDiv(TyBackstageBackH, Font.PixelsPerInch, 96);
    rowH := MulDiv(TyBackstageRowH, Font.PixelsPerInch, 96);
    r := TyBackstageRowAt(Y, backH, rowH, FCommands.Count);
    if r < 0 then r := TyBackstageNoRow;   // back band / none -> no row hover
  end;
  if r <> FHoverIndex then
  begin
    FHoverIndex := r;
    Invalidate;
  end;
end;

procedure TTyRibbonBackstage.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverIndex <> TyBackstageNoRow then
  begin
    FHoverIndex := TyBackstageNoRow;
    Invalidate;
  end;
end;

procedure TTyRibbonBackstage.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if Key = VK_ESCAPE then
  begin
    Close;
    Key := 0;
  end;
end;

end.
