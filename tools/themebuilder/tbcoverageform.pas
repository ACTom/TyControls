unit tbcoverageform;
{ "View > Coverage check...": the two lists of tbcoverage in a dialog. A double click on an
  entry closes it with that typeKey (Chosen) and the window goes to its rule, or adds one.
  An entry that is not a catalogue typeKey says so -- in list 1 that is most often a typo. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form, tyControls.FormSurface, tyControls.TyLabel,
  tyControls.ListBox, tyControls.Button;

resourcestring
  rsTbCovUnknownKey = '(not a known typeKey)';

type
  TTbCoverageForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    LblNotShown: TTyLabel;
    LstNotShown: TTyListBox;
    LblDefault: TTyLabel;
    LstDefault: TTyListBox;
    LblHint: TTyLabel;
    BtnClose: TTyButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure LstNotShownDblClick(Sender: TObject);
    procedure LstDefaultDblClick(Sender: TObject);
  private
    FNotShownKeys: TStringList;
    FDefaultKeys: TStringList;
    FChosen: string;
    procedure Choose(AList: TTyListBox; AKeys: TStrings);
  public
    procedure Fill(ANotShown, ADefaultLook: TStrings);
    property Chosen: string read FChosen;    { the typeKey double-clicked; '' = none }
  end;

implementation

{$R *.lfm}

uses
  tyControls.Css.Catalog;

function IsCatalogKey(const AKey: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(TyCatalogTypeKeys) do
    if SameText(TyCatalogTypeKeys[i], AKey) then
      Exit(True);
  Result := False;
end;

procedure TTbCoverageForm.FormCreate(Sender: TObject);
begin
  FNotShownKeys := TStringList.Create;
  FDefaultKeys := TStringList.Create;
  ApplyChromeTheme(TyDefaultController);
end;

procedure TTbCoverageForm.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FNotShownKeys);
  FreeAndNil(FDefaultKeys);
end;

procedure TTbCoverageForm.Fill(ANotShown, ADefaultLook: TStrings);

  procedure FillOne(AList: TTyListBox; AKeys, ASource: TStrings);
  var
    i: Integer;
    caption: string;
  begin
    AKeys.Assign(ASource);
    AList.Items.BeginUpdate;
    try
      AList.Items.Clear;
      for i := 0 to ASource.Count - 1 do
      begin
        caption := ASource[i];
        if not IsCatalogKey(ASource[i]) then
          caption := caption + '  ' + rsTbCovUnknownKey;
        AList.Items.Add(caption);
      end;
    finally
      AList.Items.EndUpdate;
    end;
  end;

begin
  FillOne(LstNotShown, FNotShownKeys, ANotShown);
  FillOne(LstDefault, FDefaultKeys, ADefaultLook);
end;

procedure TTbCoverageForm.Choose(AList: TTyListBox; AKeys: TStrings);
var
  i: Integer;
begin
  i := AList.ItemIndex;
  if (i < 0) or (i >= AKeys.Count) then Exit;
  FChosen := AKeys[i];      { the key, not the caption with its note }
  ModalResult := mrOk;
end;

procedure TTbCoverageForm.LstNotShownDblClick(Sender: TObject);
begin
  Choose(LstNotShown, FNotShownKeys);
end;

procedure TTbCoverageForm.LstDefaultDblClick(Sender: TObject);
begin
  Choose(LstDefault, FDefaultKeys);
end;

end.
