unit tyControls.Controller;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms,
  tyControls.Types, tyControls.StyleModel, tyControls.Painter;

var
  // When True (default), the first TTyStyleController created in a GUI context
  // sets TyFallbackFontName (tyControls.Painter) from the real system font, so
  // text with no themed font-family renders with a concrete name instead of ''
  // (BGRA's empty-name path drops the last glyph / mis-advances in the real GUI).
  // Headless test harnesses set this False BEFORE creating any controller, so
  // TyFallbackFontName stays '' and headless rendering remains deterministic.
  TyAutoSystemFontFallback: Boolean = True;

type
  TTyStyleController = class(TComponent)
  private
    FModel: TTyStyleModel;
    FThemeFile: string;
    FControls: TFPList;
    procedure SetThemeFile(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Model: TTyStyleModel read FModel;
    procedure LoadTheme(const AFileName: string);
    procedure LoadThemeCss(const ASource: string);
    procedure LoadThemeCssAdditive(const ASource: string);   // compose onto current (A6)
    procedure RegisterStyleable(AControl: TControl);
    procedure UnregisterStyleable(AControl: TControl);
    procedure Changed;
  published
    property ThemeFile: string read FThemeFile write SetThemeFile;
  end;

function TyDefaultController: TTyStyleController;

implementation

var
  GDefaultController: TTyStyleController = nil;

constructor TTyStyleController.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FModel := TTyStyleModel.Create;
  FControls := TFPList.Create;
  // One-time: derive a concrete fallback font from the real system font when a
  // GUI app first creates a controller and the theme provides no font-family.
  // Only a FALLBACK (still token-driven: a themed font-family always wins). The
  // try/except keeps headless/widgetset-less contexts safe.
  if TyAutoSystemFontFallback and (TyFallbackFontName = '') then
    try
      if (Screen <> nil) and (Screen.SystemFont <> nil)
         and (Screen.SystemFont.Name <> '') then
        TyFallbackFontName := Screen.SystemFont.Name;
    except
      // ignore: leave fallback empty in non-GUI / unavailable-Screen contexts
    end;
end;

destructor TTyStyleController.Destroy;
begin
  FControls.Free;
  FModel.Free;
  inherited Destroy;
end;

procedure TTyStyleController.SetThemeFile(const AValue: string);
begin
  if FThemeFile = AValue then Exit;
  FThemeFile := AValue;
  if (AValue <> '') and FileExists(AValue) then
    LoadTheme(AValue);
end;

procedure TTyStyleController.LoadTheme(const AFileName: string);
begin
  FModel.LoadFromFile(AFileName);
  FThemeFile := AFileName;
  Changed;
end;

procedure TTyStyleController.LoadThemeCss(const ASource: string);
begin
  FModel.LoadFromCss(ASource);
  Changed;
end;

procedure TTyStyleController.LoadThemeCssAdditive(const ASource: string);
begin
  FModel.LoadFromCssAdditive(ASource);
  Changed;
end;

procedure TTyStyleController.RegisterStyleable(AControl: TControl);
begin
  if (AControl <> nil) and (FControls.IndexOf(AControl) < 0) then
    FControls.Add(AControl);
end;

procedure TTyStyleController.UnregisterStyleable(AControl: TControl);
var
  i: Integer;
begin
  i := FControls.IndexOf(AControl);
  if i >= 0 then
    FControls.Delete(i);
end;

procedure TTyStyleController.Changed;
var
  i: Integer;
begin
  for i := FControls.Count - 1 downto 0 do
    TControl(FControls[i]).Invalidate;
end;

function TyDefaultController: TTyStyleController;
begin
  if GDefaultController = nil then
    GDefaultController := TTyStyleController.Create(nil);
  Result := GDefaultController;
end;

finalization
  FreeAndNil(GDefaultController);
end.
