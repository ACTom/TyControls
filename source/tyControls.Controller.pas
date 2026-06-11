unit tyControls.Controller;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls,
  tyControls.Types, tyControls.StyleModel;
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
