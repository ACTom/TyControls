unit tyControls.TabControl;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType,
  tyControls.Types, tyControls.Painter, tyControls.Base,
  tyControls.Panel;

type
  TTyTabControl = class(TTyCustomControl)
  private
    FCaptions: TStringList;   // parallel arrays
    FPages:    array of TTyPanel;
    FTabIndex: Integer;       // -1 = none
    FTabHeight: Integer;      // logical px, default 28
    FHoverTab: Integer;       // -1 = none
    FOnChange: TNotifyEvent;

    procedure SetTabIndex(AValue: Integer);
    procedure SetTabHeight(AValue: Integer);
    function  TabHPx(APPI: Integer): Integer;
    function  GetPage(AIndex: Integer): TTyPanel;
    function  TabCaptionWidth(const ACaption: string;
                              const AStyle: TTyStyleSet; APPI: Integer): Integer;
    procedure ShowOnlyPage(AIndex: Integer);
  protected
    function GetStyleTypeKey: string; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
                        X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function AddTab(const ACaption: string): TTyPanel;
    function TabCount: Integer;
    function TabCaption(AIndex: Integer): string;
    { Public pure-ish geometry for tests: device px, (0,0)-local }
    function TyTabHeaderRect(AIndex: Integer): TRect;

    property TabIndex: Integer read FTabIndex write SetTabIndex;
    property Pages[AIndex: Integer]: TTyPanel read GetPage;
  published
    property TabHeight: Integer read FTabHeight write SetTabHeight default 28;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property TabStop default True;
    property Align;
    property Anchors;
    property StyleClass;
    property Controller;
  end;

implementation

{ TTyTabControl }

constructor TTyTabControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaptions := TStringList.Create;
  FTabIndex  := -1;
  FTabHeight := 28;
  FHoverTab  := -1;
  TabStop    := True;
  Width      := 300;
  Height     := 200;
end;

destructor TTyTabControl.Destroy;
begin
  FCaptions.Free;
  { Pages are owned components (Owner=Self) so freed by TComponent.Destroy }
  inherited Destroy;
end;

function TTyTabControl.GetStyleTypeKey: string;
begin
  Result := 'TyTabControl';
end;

{ Shared tab-header-band height: TabHeight logical px → device px at APPI. }
function TTyTabControl.TabHPx(APPI: Integer): Integer;
begin
  Result := MulDiv(FTabHeight, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyTabControl.GetPage(AIndex: Integer): TTyPanel;
begin
  if (AIndex < 0) or (AIndex >= Length(FPages)) then
    Result := nil
  else
    Result := FPages[AIndex];
end;

function TTyTabControl.TabCount: Integer;
begin
  Result := FCaptions.Count;
end;

function TTyTabControl.TabCaption(AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex >= FCaptions.Count) then
    Result := ''
  else
    Result := FCaptions[AIndex];
end;

{ Measure the rendered caption width using a scratch TBitmap canvas so CJK and
  variable-width fonts are handled correctly (same pattern as TTyGroupBox). }
function TTyTabControl.TabCaptionWidth(const ACaption: string;
  const AStyle: TTyStyleSet; APPI: Integer): Integer;
var
  MeasBmp: TBitmap;
begin
  MeasBmp := TBitmap.Create;
  try
    MeasBmp.SetSize(1, 1);
    MeasBmp.Canvas.Font.Name := AStyle.FontName;
    MeasBmp.Canvas.Font.Size := MulDiv(AStyle.FontSize, APPI, 96);
    Result := MeasBmp.Canvas.TextWidth(ACaption);
  finally
    MeasBmp.Free;
  end;
  if Result < 1 then Result := 1;
end;

{ Geometry: device px, (0,0)-local.
  Headers laid left-to-right; width = text width + 2×Scale(12), minimum Scale(48). }
function TTyTabControl.TyTabHeaderRect(AIndex: Integer): TRect;
var
  PPI, TabH, MinW, Pad, TW, X, I: Integer;
  TabStyle: TTyStyleSet;
begin
  PPI   := Font.PixelsPerInch;
  TabH  := TabHPx(PPI);
  Pad   := MulDiv(12, PPI, 96);    // padding each side
  MinW  := MulDiv(48, PPI, 96);    // minimum width

  TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', [tysNormal]);

  X := 0;
  for I := 0 to AIndex do
  begin
    TW := TabCaptionWidth(FCaptions[I], TabStyle, PPI);
    TW := TW + 2 * Pad;
    if TW < MinW then TW := MinW;
    if I = AIndex then
    begin
      Result := Rect(X, 0, X + TW, TabH);
      Exit;
    end;
    Inc(X, TW);
  end;
  Result := Rect(0, 0, 0, 0); // should not reach here
end;

procedure TTyTabControl.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  Inc(ARect.Top, TabHPx(Font.PixelsPerInch));
end;

{ Show only the page at AIndex (or none when AIndex=-1). }
procedure TTyTabControl.ShowOnlyPage(AIndex: Integer);
var
  I: Integer;
begin
  for I := 0 to Length(FPages) - 1 do
    FPages[I].Visible := (I = AIndex);
end;

procedure TTyTabControl.SetTabIndex(AValue: Integer);
var
  Clamped: Integer;
begin
  if AValue < -1 then
    Clamped := -1
  else if AValue >= FCaptions.Count then
    Clamped := FCaptions.Count - 1
  else
    Clamped := AValue;
  if Clamped = FTabIndex then Exit;
  FTabIndex := Clamped;
  ShowOnlyPage(FTabIndex);
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TTyTabControl.SetTabHeight(AValue: Integer);
begin
  if FTabHeight = AValue then Exit;
  FTabHeight := AValue;
  if FTabHeight < 1 then FTabHeight := 1;
  Invalidate;
end;

function TTyTabControl.AddTab(const ACaption: string): TTyPanel;
var
  Page: TTyPanel;
  IsFirst: Boolean;
begin
  IsFirst := (FCaptions.Count = 0);
  FCaptions.Add(ACaption);

  Page := TTyPanel.Create(Self);
  Page.Parent := Self;
  Page.Align  := alClient;
  Page.Visible := False;

  SetLength(FPages, Length(FPages) + 1);
  FPages[High(FPages)] := Page;

  if IsFirst then
  begin
    { Auto-select: bypass setter's clamping by setting FTabIndex directly,
      then manually show the first page and fire nothing (first add, no real
      "change" from a previous selection). }
    FTabIndex := 0;
    Page.Visible := True;
    Invalidate;
  end;

  Result := Page;
end;

procedure TTyTabControl.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  BoxStyle, TabStyle: TTyStyleSet;
  R: TRect;
  W, H, TabH, I: Integer;
  HdrRect: TRect;
  TabStates: TTyStateSet;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    W := R.Right;
    H := R.Bottom;
    P.BeginPaint(ACanvas, ARect, APPI);

    BoxStyle := CurrentStyle;
    TabH := TabHPx(APPI);

    { Draw content area frame below header strip.
      Overlap by 1px so the active tab can visually merge with the content panel. }
    DrawFrame(P, Rect(0, TabH - MulDiv(1, APPI, 96), W, H), BoxStyle);

    { Draw each tab header }
    for I := 0 to FCaptions.Count - 1 do
    begin
      { Build local rect for this header (reuse geometry logic inline) }
      HdrRect := TyTabHeaderRect(I);

      { Determine state }
      TabStates := [];
      if I = FTabIndex then
        Include(TabStates, tysActive)
      else if I = FHoverTab then
        Include(TabStates, tysHover)
      else
        Include(TabStates, tysNormal);

      TabStyle := ActiveController.Model.ResolveStyle('TyTab', '', TabStates);

      { Fill header background }
      if tpBackground in TabStyle.Present then
        P.FillBackground(HdrRect, TabStyle.Background, 0);

      { Draw caption centered in header }
      P.DrawText(HdrRect,
        FCaptions[I],
        TabStyle.FontName, TabStyle.FontSize, TabStyle.FontWeight,
        TabStyle.TextColor,
        taCenter, tlCenter, True);
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyTabControl.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ Mouse: hit-test headers on left-click }
procedure TTyTabControl.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  PPI, TabH, I: Integer;
  HdrRect: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    PPI  := Font.PixelsPerInch;
    TabH := TabHPx(PPI);
    if Y < TabH then
    begin
      for I := 0 to FCaptions.Count - 1 do
      begin
        HdrRect := TyTabHeaderRect(I);
        if (X >= HdrRect.Left) and (X < HdrRect.Right) then
        begin
          TabIndex := I;
          Break;
        end;
      end;
    end;
    try
      if CanFocus then SetFocus;
    except
      { Ignore focus errors in headless/test environments }
    end;
  end;
end;

procedure TTyTabControl.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  PPI, TabH, NewHover, I: Integer;
  HdrRect: TRect;
begin
  inherited MouseMove(Shift, X, Y);
  PPI  := Font.PixelsPerInch;
  TabH := TabHPx(PPI);
  NewHover := -1;
  if Y < TabH then
  begin
    for I := 0 to FCaptions.Count - 1 do
    begin
      HdrRect := TyTabHeaderRect(I);
      if (X >= HdrRect.Left) and (X < HdrRect.Right) then
      begin
        NewHover := I;
        Break;
      end;
    end;
  end;
  if NewHover <> FHoverTab then
  begin
    FHoverTab := NewHover;
    Invalidate;
  end;
end;

procedure TTyTabControl.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverTab <> -1 then
  begin
    FHoverTab := -1;
    Invalidate;
  end;
end;

{ Keyboard: VK_LEFT/VK_RIGHT move TabIndex; clamp at ends; consume key }
procedure TTyTabControl.KeyDown(var Key: Word; Shift: TShiftState);
var
  NewIndex: Integer;
begin
  inherited KeyDown(Key, Shift);
  if FCaptions.Count = 0 then Exit;
  case Key of
    VK_RIGHT:
    begin
      NewIndex := FTabIndex + 1;
      if NewIndex >= FCaptions.Count then
        NewIndex := FCaptions.Count - 1;
      TabIndex := NewIndex;
      Key := 0;
    end;
    VK_LEFT:
    begin
      NewIndex := FTabIndex - 1;
      if NewIndex < 0 then NewIndex := 0;
      TabIndex := NewIndex;
      Key := 0;
    end;
  end;
end;

end.
