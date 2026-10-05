unit tbaisettingsform;
{ "AI settings" (spec §7.1): the services set up, one of them current -- added from a preset
  (OpenAI, DeepSeek, Anthropic, a local Ollama, or blank), each with its format, address,
  model, key, maximum output and idle timeout; "Test connection" sends the smallest request
  and says what came back; a note says what is sent where and how the keys are kept.

  The dialog works on a copy (Prepare): nothing reaches the settings or the disk until OK
  (Commit), so Cancel leaves everything as it was. OK checks everything before it changes
  anything; a save that fails puts the settings back as the disk has them and keeps the
  window open. A key is cleaned as it is typed or pasted (tabs, line breaks). The test runs on the service's own client
  thread (TTbClientBackend); the first piece of an answer is proof enough -- the request is
  stopped there -- and closing the window stops a test still running.
  Under the fields, the http warning and the Ollama hint (never both) size to their text and
  "Test connection" is anchored below whichever shows (LCL follows an anchor past a hidden
  control to that control's own anchor). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Menus, Dialogs,
  tyControls.Controller, tyControls.Form, tyControls.FormSurface, tyControls.TyLabel,
  tyControls.Edit, tyControls.ComboBox, tyControls.SpinEdit, tyControls.ListBox,
  tyControls.Button, tyControls.DropButtons, tyControls.Panel, tyControls.Menu,
  tyControls.Alert,
  tbaiformat, tbaiclient, tbaisettings, tbaisession, tbseedsframe;

resourcestring
  rsTbAiFormatOpenAI = 'OpenAI-compatible';
  rsTbAiFormatAnthropic = 'Anthropic';
  rsTbAiPrivacy = 'The theme text and your descriptions are sent to the service set here. A local model (an address on localhost) keeps them on this computer.';
  rsTbAiKeyStoreWin = 'Keys are stored encrypted for your Windows user.';
  rsTbAiKeyStoreUnix = 'Keys are stored in a file only you can read.';
  rsTbAiOllamaHint = 'Ollama keeps only a short context by default and cuts the start of a long request without saying so. Set OLLAMA_CONTEXT_LENGTH=32768 (or more) before starting Ollama.';
  rsTbAiTesting = 'Testing...';
  rsTbAiTestOk = 'Connected: %s is answering.';
  rsTbAiNeedMaxOutput = 'Anthropic needs a maximum output length above 0.';
  rsTbAiRemoveAsk = 'Remove the service "%s" and its key?';
  rsTbAiSaveFailed = 'The settings could not be saved (%s). Nothing was changed.';

type
  TTbAiSettingsForm = class(TTyForm)
    Surface: TTyFormSurface;
    Bar: TTyTitleBar;
    BottomBar: TTyPanel;
    BtnCancel: TTyButton;
    BtnOk: TTyButton;
    LeftPane: TTyPanel;
    PaneButtons: TTyPanel;
    BtnAdd: TTyMenuButton;            { the whole button opens the presets }
    BtnRemove: TTyButton;
    ProfileList: TTyListBox;
    Fields: TTyPanel;
    LblName: TTyLabel;
    EdtName: TTyEdit;
    LblFormat: TTyLabel;
    CmbFormat: TTyComboBox;
    LblUrl: TTyLabel;
    EdtUrl: TTyEdit;
    LblModel: TTyLabel;
    EdtModel: TTyEdit;
    LblKey: TTyLabel;
    EdtKey: TTyEdit;
    LblMaxOutput: TTyLabel;
    SpnMaxOutput: TTySpinEdit;
    LblTimeout: TTyLabel;
    SpnTimeout: TTySpinEdit;
    LblHint: TTyLabel;
    PlainHttpAlert: TTyAlert;
    BtnTest: TTyButton;
    LblTest: TTyLabel;
    LblPrivacy: TTyLabel;
    PresetMenu: TTyPopupMenu;
    MiOpenAI: TMenuItem;
    MiDeepSeek: TMenuItem;
    MiAnthropic: TMenuItem;
    MiOllama: TMenuItem;
    MiCustom: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure ProfileListClick(Sender: TObject);
    procedure PresetClick(Sender: TObject);
    procedure BtnRemoveClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure FormatChange(Sender: TObject);
    procedure UrlChange(Sender: TObject);
    procedure KeyChange(Sender: TObject);
    procedure BtnTestClick(Sender: TObject);
    procedure BtnOkClick(Sender: TObject);
  private
    FSettings: TTbAiSettings;
    FWork: array of TTbAiProfile;
    FKeys: TStringList;           { id=key, the copy being edited }
    FSel: Integer;
    FUpdating: Boolean;
    FTest: TTbClientBackend;
    FTestRunning: Boolean;
    FTestProfile: TTbAiProfile;
    FTestText: string;
    FAvailable: Boolean;          { this platform can do HTTP (libcurl found) }
    FUnavailable: string;
    FOnAsk: TTbAskEvent;
    function KeyOf(const AId: string): string;
    function IndexOfWork(const AId: string): Integer;
    procedure SetKeyOf(const AId, AKey: string);
    procedure FillList;
    procedure ShowProfile;
    procedure UpdateHint;
    procedure UpdateButtons;
    procedure SetTestText(const AText: string);
    procedure StopTest;
    procedure TestDelta(Sender: TObject; APiece: TTbStreamPiece; const AText: string);
    procedure TestDone(Sender: TObject; const AResult: TTbAiResult);
    function GetTesting: Boolean;
  public
    procedure Prepare(ASettings: TTbAiSettings);     { works on a copy }
    procedure AddPreset(APreset: TTbAiPreset);
    procedure SelectProfile(AIndex: Integer);
    function StartTest: Boolean;                     { False: nothing to test }
    { the copy back into the settings, and Save; False (and why, in the test line) when a
      profile cannot be kept as it is }
    function Commit: Boolean;
    property Testing: Boolean read GetTesting;
    property TestText: string read FTestText;        { FOR THE TESTS }
    property OnAsk: TTbAskEvent read FOnAsk write FOnAsk;
  end;

implementation

{$R *.lfm}

uses
  tbhttp;

procedure TTbAiSettingsForm.FormCreate(Sender: TObject);
begin
  ApplyChromeTheme(TyDefaultController);
  FKeys := TStringList.Create;
  FSel := -1;
  EdtKey.PasswordChar := #$E2#$80#$A2;   { a bullet }
  CmbFormat.Items.Clear;
  CmbFormat.Items.Add(rsTbAiFormatOpenAI);
  CmbFormat.Items.Add(rsTbAiFormatAnthropic);
  LblPrivacy.Caption := rsTbAiPrivacy + ' ' +
    {$IFDEF MSWINDOWS}rsTbAiKeyStoreWin{$ELSE}rsTbAiKeyStoreUnix{$ENDIF};
  PlainHttpAlert.Message := rsTbAiPlainHttp;
  PlainHttpAlert.Description := rsTbAiPlainHttpMore;
  { without libcurl (Linux, macOS) there is nothing to test with: say so, grey the button }
  FAvailable := TbTransportAvailable(FUnavailable);
  if not FAvailable then
    SetTestText(Format(rsTbAiNoTransport, [FUnavailable]));
end;

procedure TTbAiSettingsForm.FormDestroy(Sender: TObject);
begin
  StopTest;
  FreeAndNil(FKeys);
end;

procedure TTbAiSettingsForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  StopTest;
end;

function TTbAiSettingsForm.KeyOf(const AId: string): string;
var
  k: Integer;
begin
  k := FKeys.IndexOfName(AId);
  if k < 0 then Result := '' else Result := FKeys.ValueFromIndex[k];
end;

function TTbAiSettingsForm.IndexOfWork(const AId: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FWork) do
    if FWork[i].Id = AId then
      Exit(i);
  Result := -1;
end;

procedure TTbAiSettingsForm.SetKeyOf(const AId, AKey: string);
var
  k: Integer;
begin
  k := FKeys.IndexOfName(AId);
  if AKey = '' then
  begin
    if k >= 0 then FKeys.Delete(k);
  end
  else if k >= 0 then
    FKeys[k] := AId + '=' + AKey
  else
    FKeys.Add(AId + '=' + AKey);
end;

procedure TTbAiSettingsForm.Prepare(ASettings: TTbAiSettings);
var
  i: Integer;
  cur: TTbAiProfile;
begin
  FSettings := ASettings;
  SetLength(FWork, ASettings.Count);
  FKeys.Clear;
  for i := 0 to ASettings.Count - 1 do
  begin
    FWork[i] := ASettings.Profile(i);
    SetKeyOf(FWork[i].Id, ASettings.GetKey(FWork[i].Id));
  end;
  FSel := -1;
  if ASettings.Current(cur) then
    FSel := ASettings.IndexOfId(cur.Id);
  if (FSel < 0) and (Length(FWork) > 0) then
    FSel := 0;
  FillList;
  ShowProfile;
end;

procedure TTbAiSettingsForm.FillList;
var
  i: Integer;
begin
  FUpdating := True;
  try
    ProfileList.Items.BeginUpdate;
    try
      ProfileList.Items.Clear;
      for i := 0 to High(FWork) do
        ProfileList.Items.Add(FWork[i].Name);
    finally
      ProfileList.Items.EndUpdate;
    end;
    ProfileList.ItemIndex := FSel;
  finally
    FUpdating := False;
  end;
end;

procedure TTbAiSettingsForm.UpdateButtons;
var
  has: Boolean;
begin
  has := (FSel >= 0) and (FSel <= High(FWork));
  BtnRemove.Enabled := has;
  BtnTest.Enabled := has and FAvailable;
  EdtName.Enabled := has;
  CmbFormat.Enabled := has;
  EdtUrl.Enabled := has;
  EdtModel.Enabled := has;
  EdtKey.Enabled := has;
  SpnMaxOutput.Enabled := has;
  SpnTimeout.Enabled := has;
end;

procedure TTbAiSettingsForm.ShowProfile;
var
  p: TTbAiProfile;
begin
  FUpdating := True;
  try
    if (FSel >= 0) and (FSel <= High(FWork)) then
    begin
      p := FWork[FSel];
      EdtName.Text := p.Name;
      CmbFormat.ItemIndex := Ord(p.Format);
      EdtUrl.Text := p.BaseUrl;
      EdtModel.Text := p.Model;
      EdtKey.Text := KeyOf(p.Id);
      SpnMaxOutput.Value := p.MaxOutput;
      SpnTimeout.Value := p.TimeoutSec;
    end
    else
    begin
      EdtName.Text := '';
      CmbFormat.ItemIndex := -1;
      EdtUrl.Text := '';
      EdtModel.Text := '';
      EdtKey.Text := '';
      SpnMaxOutput.Value := 0;
      SpnTimeout.Value := 120;
    end;
  finally
    FUpdating := False;
  end;
  UpdateHint;
  UpdateButtons;
end;

procedure TTbAiSettingsForm.UpdateHint;
var
  parts: TTbUrlParts;
begin
  if TbSplitUrl(EdtUrl.Text, parts) and TbIsLoopbackHost(parts.Host) then
  begin
    LblHint.Caption := rsTbAiOllamaHint;
    LblHint.Visible := True;
  end
  else
    LblHint.Visible := False;
  { http:// to another computer: allowed, key and all (inside a company network http is
    common -- acceptance feedback; OK used to refuse a key), and said out loud }
  PlainHttpAlert.Visible := TbIsPlainRemote(EdtUrl.Text);
end;

procedure TTbAiSettingsForm.SelectProfile(AIndex: Integer);
begin
  if (AIndex < -1) or (AIndex > High(FWork)) then Exit;
  FSel := AIndex;
  FUpdating := True;
  try
    ProfileList.ItemIndex := AIndex;
  finally
    FUpdating := False;
  end;
  ShowProfile;
  if FAvailable then
    SetTestText('');
end;

procedure TTbAiSettingsForm.ProfileListClick(Sender: TObject);
begin
  if FUpdating then Exit;
  SelectProfile(ProfileList.ItemIndex);
end;

procedure TTbAiSettingsForm.AddPreset(APreset: TTbAiPreset);
var
  n: Integer;
begin
  n := Length(FWork);
  SetLength(FWork, n + 1);
  FWork[n] := TbPresetProfile(APreset);
  FSel := n;
  FillList;
  ShowProfile;
  if FAvailable then
    SetTestText('');
  if EdtKey.CanSetFocus then
    EdtKey.SetFocus;
end;

procedure TTbAiSettingsForm.PresetClick(Sender: TObject);
var
  t: Integer;
begin
  t := (Sender as TMenuItem).Tag;
  if (t < Ord(Low(TTbAiPreset))) or (t > Ord(High(TTbAiPreset))) then Exit;
  AddPreset(TTbAiPreset(t));
end;

procedure TTbAiSettingsForm.BtnRemoveClick(Sender: TObject);
var
  k: Integer;
begin
  if (FSel < 0) or (FSel > High(FWork)) then Exit;
  if Assigned(FOnAsk) and
     (FOnAsk(Format(rsTbAiRemoveAsk, [FWork[FSel].Name]), [mbYes, mbNo]) <> mrYes) then
    Exit;
  SetKeyOf(FWork[FSel].Id, '');
  for k := FSel to High(FWork) - 1 do
    FWork[k] := FWork[k + 1];
  SetLength(FWork, Length(FWork) - 1);
  if FSel > High(FWork) then
    FSel := High(FWork);
  FillList;
  ShowProfile;
end;

{ every field written straight back into the copy (code filling them in does not count) }
procedure TTbAiSettingsForm.FieldChange(Sender: TObject);
begin
  if FUpdating or (FSel < 0) or (FSel > High(FWork)) then Exit;
  FWork[FSel].Name := EdtName.Text;
  FWork[FSel].Model := EdtModel.Text;
  FWork[FSel].MaxOutput := SpnMaxOutput.Value;
  FWork[FSel].TimeoutSec := SpnTimeout.Value;
  if (Sender = EdtName) and (FSel < ProfileList.Items.Count) then
  begin
    FUpdating := True;
    try
      ProfileList.Items[FSel] := EdtName.Text;
      ProfileList.ItemIndex := FSel;
    finally
      FUpdating := False;
    end;
  end;
end;

procedure TTbAiSettingsForm.FormatChange(Sender: TObject);
begin
  if FUpdating or (FSel < 0) or (FSel > High(FWork)) then Exit;
  if CmbFormat.ItemIndex = Ord(tafAnthropic) then
  begin
    FWork[FSel].Format := tafAnthropic;
    { Anthropic will not answer without a maximum }
    if FWork[FSel].MaxOutput <= 0 then
    begin
      FWork[FSel].MaxOutput := TbAnthropicDefaultMaxOutput;
      FUpdating := True;
      try
        SpnMaxOutput.Value := TbAnthropicDefaultMaxOutput;
      finally
        FUpdating := False;
      end;
    end;
  end
  else
    FWork[FSel].Format := tafOpenAI;
end;

procedure TTbAiSettingsForm.UrlChange(Sender: TObject);
begin
  UpdateHint;
  if FUpdating or (FSel < 0) or (FSel > High(FWork)) then Exit;
  FWork[FSel].BaseUrl := Trim(EdtUrl.Text);
end;

{ a key with no line breaks, tabs or other control characters: what a paste brings along
  (a key copied from a table, a line with its break) goes }
function CleanKey(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
    if S[i] >= ' ' then
      Result := Result + S[i];
  Result := Trim(Result);
end;

procedure TTbAiSettingsForm.KeyChange(Sender: TObject);
var
  clean: string;
begin
  if FUpdating or (FSel < 0) or (FSel > High(FWork)) then Exit;
  clean := CleanKey(EdtKey.Text);
  if clean <> Trim(EdtKey.Text) then
  begin
    FUpdating := True;
    try
      EdtKey.Text := clean;
    finally
      FUpdating := False;
    end;
  end;
  SetKeyOf(FWork[FSel].Id, clean);
end;

procedure TTbAiSettingsForm.SetTestText(const AText: string);
begin
  FTestText := AText;
  LblTest.Caption := AText;
end;

procedure TTbAiSettingsForm.StopTest;
begin
  FTestRunning := False;
  if FTest <> nil then
  begin
    FTest.OnDelta := nil;
    FTest.OnDone := nil;
    FreeAndNil(FTest);      { cancels, waits for its thread, drops what it queued }
  end;
end;

function TTbAiSettingsForm.GetTesting: Boolean;
begin
  Result := FTestRunning;
end;

function TTbAiSettingsForm.StartTest: Boolean;
var
  msgs: TTbChatMessages;
begin
  Result := False;
  if (FSel < 0) or (FSel > High(FWork)) or not FAvailable then Exit;
  StopTest;
  FTestProfile := FWork[FSel];
  FTest := TTbClientBackend.Create(FTestProfile, KeyOf(FTestProfile.Id));
  FTest.OnDelta := @TestDelta;
  FTest.OnDone := @TestDone;
  FTestRunning := True;
  SetTestText(rsTbAiTesting);
  SetLength(msgs, 1);
  msgs[0] := TbChatMessage(tcrUser, 'ping');
  FTest.Start('Reply with the single word OK.', msgs);
  Result := True;
end;

procedure TTbAiSettingsForm.TestDelta(Sender: TObject; APiece: TTbStreamPiece; const AText: string);
begin
  if not FTestRunning then Exit;
  if (APiece = tspText) or (APiece = tspThinking) then
  begin
    { an answer has started: connected; no need to wait for the rest }
    FTestRunning := False;
    FTest.Cancel;
    SetTestText(Format(rsTbAiTestOk, [FTestProfile.Model]));
  end;
end;

procedure TTbAiSettingsForm.TestDone(Sender: TObject; const AResult: TTbAiResult);
begin
  if not FTestRunning then Exit;
  FTestRunning := False;
  if AResult.Kind = aekNone then
    SetTestText(Format(rsTbAiTestOk, [FTestProfile.Model]))
  else
    SetTestText(TbAiErrorSentence(AResult, FTestProfile));
end;

procedure TTbAiSettingsForm.BtnTestClick(Sender: TObject);
begin
  StartTest;
end;

function TTbAiSettingsForm.Commit: Boolean;
var
  i: Integer;
  keep: Boolean;
  existing: TStringArray;
begin
  Result := False;
  for i := 0 to High(FWork) do
    if (FWork[i].Format = tafAnthropic) and (FWork[i].MaxOutput <= 0) then
    begin
      SelectProfile(i);
      SetTestText(rsTbAiNeedMaxOutput);
      ModalResult := mrNone;
      Exit;
    end;
  { everything checked -- and the keys are clean (KeyChange takes out what the settings
    would refuse): only now do the settings change }
  { the ones taken out of the list go, keys and all }
  SetLength(existing, FSettings.Count);
  for i := 0 to FSettings.Count - 1 do
    existing[i] := FSettings.Profile(i).Id;
  for i := 0 to High(existing) do
  begin
    keep := IndexOfWork(existing[i]) >= 0;
    if not keep then
      FSettings.Delete(existing[i]);
  end;
  for i := 0 to High(FWork) do
  begin
    FSettings.Put(FWork[i]);
    FSettings.SetKey(FWork[i].Id, KeyOf(FWork[i].Id));
  end;
  if (FSel >= 0) and (FSel <= High(FWork)) then
    FSettings.CurrentId := FWork[FSel].Id;
  if not FSettings.Save then
  begin
    { not on disk: the settings go back to what is there, the window stays with the
      changes in it -- OK again, or Cancel }
    FSettings.Load;
    SetTestText(Format(rsTbAiSaveFailed, [FSettings.IniFile]));
    ModalResult := mrNone;
    Exit;
  end;
  Result := True;
end;

procedure TTbAiSettingsForm.BtnOkClick(Sender: TObject);
begin
  Commit;      { refused: ModalResult goes back to none and the window stays }
end;

end.
