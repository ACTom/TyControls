unit tbaiframe;
{ The side bar's AI page (spec §7): pick a service, describe the theme or the change, and
  Generate; the answer streams into the box below as it comes, Stop ends it, and when a
  version comes out of the checks the comparison window opens by itself (OnCandidate --
  the main window owns it). "New conversation" forgets the earlier requests; so does a new
  or another opened document (DocumentChanged). "Include the problem list" follows the
  document -- ticked while it has errors -- until the user sets it by hand.

  The status line always holds one sentence: what is happening, or what went wrong
  (tbaiclient, tbaisession). On Linux and macOS without libcurl the page stays, says what
  is missing, and Generate is greyed (Available). The text streams in through a 150 ms
  timer, not on every piece, as one change to the box per tick: a long answer does not keep
  the window busy. The box does not wrap lines: laying out a wrapped memo again costs far
  more (600 lines: 12 s against 0.7 s, measured headless) and the answer is code. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, ExtCtrls,
  tyControls.Panel, tyControls.TyLabel, tyControls.Memo, tyControls.CheckBox,
  tyControls.Button, tyControls.GlyphButtons, tyControls.ComboBox, tyControls.Icons.Lucide,
  tbaiformat, tbaiclient, tbaisettings, tbaisession;

resourcestring
  rsTbAiNoProfile = 'Add a service in the AI settings first.';
  rsTbAiSentTo = 'Sent to: %s';
  rsTbAiDescribe = 'Describe the theme or the change first.';
  rsTbAiRound = 'Round %d';
  rsTbAiConversation = 'This conversation: %d requests.';

type
  TTbAiDocEvent = function: TTbAiDocument of object;

  TTbAiFrame = class(TFrame)
    TopRow: TTyPanel;
    BtnSettings: TTySpeedButton;
    ProfileCombo: TTyComboBox;
    LblDescribe: TTyLabel;
    EdtPrompt: TTyMemo;
    ChkProblems: TTyCheckBox;
    ButtonRow: TTyPanel;
    BtnGenerate: TTyButton;
    BtnStop: TTyButton;
    BtnNewChat: TTyButton;
    LblStatus: TTyLabel;
    LblConversation: TTyLabel;
    BottomRow: TTyPanel;
    LblSentTo: TTyLabel;
    BtnShowCompare: TTyButton;
    OutputMemo: TTyMemo;
    AiIconFont: TTyLucideIconFont;
    FlushTimer: TTimer;
    procedure ProfileComboChange(Sender: TObject);
    procedure ChkProblemsChange(Sender: TObject);
    procedure BtnSettingsClick(Sender: TObject);
    procedure BtnNewChatClick(Sender: TObject);
    procedure BtnShowCompareClick(Sender: TObject);
    procedure FlushTimerTimer(Sender: TObject);
  private
    FSession: TTbAiSession;
    FSettings: TTbAiSettings;
    FAvailable: Boolean;
    FUnavailable: string;
    FUpdating: Boolean;
    FProblemsTouched: Boolean;
    FShown: Integer;              { how much of Session.Streamed the box shows }
    FShownRound: Integer;
    FLineOpen: Boolean;           { the box's last line is still being written }
    FOnGetDocument: TTbAiDocEvent;
    FOnCandidate: TNotifyEvent;
    FOnSettings: TNotifyEvent;
    procedure SessionStage(Sender: TObject);
    procedure SessionStreamed(Sender: TObject);
    procedure SessionFinished(Sender: TObject);
    procedure UpdateButtons;
    procedure UpdateConversation;
    procedure SetStatus(const AText: string);
    function HostNow: string;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Setup(ASettings: TTbAiSettings; ABaseVars: TStrings);
    procedure RefreshProfiles;
    procedure DocumentChanged(AHasErrors: Boolean);  { new / open: forget; and the problems box }
    procedure ProblemsChanged(AHasErrors: Boolean);  { the problems box, unless the user set it }
    procedure FlushOutput;                           { what the timer does }
  published
    procedure GenerateClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
  public
    property Session: TTbAiSession read FSession;
    property Available: Boolean read FAvailable;
    property OnGetDocument: TTbAiDocEvent read FOnGetDocument write FOnGetDocument;
    property OnCandidate: TNotifyEvent read FOnCandidate write FOnCandidate;
    property OnSettings: TNotifyEvent read FOnSettings write FOnSettings;
  end;

implementation

{$R *.lfm}

uses
  tbhttp;

constructor TTbAiFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSession := TTbAiSession.Create;
  FSession.OnStage := @SessionStage;
  FSession.OnStreamed := @SessionStreamed;
  FSession.OnFinished := @SessionFinished;
  FAvailable := True;
end;

destructor TTbAiFrame.Destroy;
begin
  FlushTimer.Enabled := False;
  FOnGetDocument := nil;
  FOnCandidate := nil;
  FOnSettings := nil;
  if FSession <> nil then
  begin
    FSession.OnStage := nil;
    FSession.OnStreamed := nil;
    FSession.OnFinished := nil;
  end;
  FreeAndNil(FSession);     { stops the backend and waits for its thread }
  inherited Destroy;
end;

procedure TTbAiFrame.Setup(ASettings: TTbAiSettings; ABaseVars: TStrings);
begin
  FSettings := ASettings;
  FSession.BaseVars := ABaseVars;
  FAvailable := TbTransportAvailable(FUnavailable);
  RefreshProfiles;
end;

procedure TTbAiFrame.SetStatus(const AText: string);
begin
  LblStatus.Caption := AText;
end;

function TTbAiFrame.HostNow: string;
begin
  if FSession.Backend <> nil then
    Result := TbHostOf(FSession.Backend.Profile.BaseUrl)
  else
    Result := '';
end;

procedure TTbAiFrame.RefreshProfiles;
var
  i: Integer;
  cur: TTbAiProfile;
  has: Boolean;
begin
  if FSettings = nil then Exit;
  has := FSettings.Current(cur);
  FUpdating := True;
  try
    ProfileCombo.Items.Clear;
    for i := 0 to FSettings.Count - 1 do
      ProfileCombo.Items.Add(FSettings.Profile(i).Name);
    if has then
      ProfileCombo.ItemIndex := FSettings.IndexOfId(cur.Id)
    else
      ProfileCombo.ItemIndex := -1;
  finally
    FUpdating := False;
  end;
  if not FAvailable then
    SetStatus(Format(rsTbAiNoTransport, [FUnavailable]))
  else if not has then
    SetStatus(rsTbAiNoProfile)
  else if not FSession.Busy then
    SetStatus('');
  if has then
  begin
    { the session's backend follows the chosen service (a running request stops) }
    FSession.Backend := TTbClientBackend.Create(cur, FSettings.GetKey(cur.Id));
    LblSentTo.Caption := Format(rsTbAiSentTo, [TbHostOf(cur.BaseUrl)]);
  end
  else
  begin
    FSession.Backend := nil;
    LblSentTo.Caption := '';
  end;
  UpdateButtons;
end;

procedure TTbAiFrame.ProfileComboChange(Sender: TObject);
var
  i: Integer;
begin
  if FUpdating or (FSettings = nil) then Exit;
  i := ProfileCombo.ItemIndex;
  if (i < 0) or (i >= FSettings.Count) then Exit;
  FSettings.CurrentId := FSettings.Profile(i).Id;
  FSettings.Save;
  RefreshProfiles;
end;

procedure TTbAiFrame.UpdateButtons;
begin
  BtnGenerate.Enabled := FAvailable and (FSession.Backend <> nil) and not FSession.Busy;
  BtnStop.Enabled := FSession.Busy;
  BtnNewChat.Enabled := not FSession.Busy;
end;

procedure TTbAiFrame.UpdateConversation;
begin
  if FSession.History.Count = 0 then
    LblConversation.Caption := ''
  else
    LblConversation.Caption := Format(rsTbAiConversation, [FSession.History.Count]);
end;

procedure TTbAiFrame.GenerateClick(Sender: TObject);
var
  doc: TTbAiDocument;
begin
  if not FAvailable then
  begin
    SetStatus(Format(rsTbAiNoTransport, [FUnavailable]));
    Exit;
  end;
  if FSession.Backend = nil then
  begin
    SetStatus(rsTbAiNoProfile);
    Exit;
  end;
  if Trim(EdtPrompt.Text) = '' then
  begin
    SetStatus(rsTbAiDescribe);
    Exit;
  end;
  if Assigned(FOnGetDocument) then
    doc := FOnGetDocument()
  else
    doc := Default(TTbAiDocument);
  OutputMemo.Clear;
  FShown := 0;
  FShownRound := 1;
  FLineOpen := False;
  BtnShowCompare.Enabled := False;
  if FSession.Generate(EdtPrompt.Text, doc, ChkProblems.Checked) then
  begin
    UpdateConversation;
    UpdateButtons;
  end;
end;

procedure TTbAiFrame.StopClick(Sender: TObject);
begin
  FSession.Stop;
end;

procedure TTbAiFrame.BtnNewChatClick(Sender: TObject);
begin
  FSession.ResetConversation;
  BtnShowCompare.Enabled := False;
  UpdateConversation;
end;

procedure TTbAiFrame.BtnSettingsClick(Sender: TObject);
begin
  if Assigned(FOnSettings) then
    FOnSettings(Self);
end;

procedure TTbAiFrame.BtnShowCompareClick(Sender: TObject);
begin
  if Assigned(FOnCandidate) and FSession.Outcome.HasCandidate then
    FOnCandidate(Self);
end;

procedure TTbAiFrame.ChkProblemsChange(Sender: TObject);
begin
  if FUpdating then Exit;
  FProblemsTouched := True;      { the user's choice holds for this document }
end;

procedure TTbAiFrame.DocumentChanged(AHasErrors: Boolean);
begin
  FSession.ResetConversation;
  BtnShowCompare.Enabled := False;
  UpdateConversation;
  FProblemsTouched := False;
  FUpdating := True;
  try
    ChkProblems.Checked := AHasErrors;
  finally
    FUpdating := False;
  end;
end;

procedure TTbAiFrame.ProblemsChanged(AHasErrors: Boolean);
begin
  if FProblemsTouched then Exit;
  FUpdating := True;
  try
    ChkProblems.Checked := AHasErrors;
  finally
    FUpdating := False;
  end;
end;

function LineCount(const S: string): Integer;
var
  i: Integer;
begin
  if S = '' then Exit(0);
  Result := 1;
  for i := 1 to Length(S) do
    if S[i] = #10 then
      Inc(Result);
end;

procedure TTbAiFrame.SessionStage(Sender: TObject);
begin
  case FSession.Stage of
    tasSending: SetStatus(Format(rsTbAiSending, [HostNow]));
    tasThinking: SetStatus(rsTbAiThinking);
    tasReceiving: SetStatus(Format(rsTbAiReceiving, [LineCount(FSession.Streamed)]));
    tasChecking: SetStatus(rsTbAiChecking);
  else
    SetStatus(FSession.Outcome.Sentence);     { retrying, done, failed, stopped }
  end;
  UpdateButtons;
end;

procedure TTbAiFrame.SessionStreamed(Sender: TObject);
begin
  if not FlushTimer.Enabled then
    FlushTimer.Enabled := True;
end;

procedure TTbAiFrame.FlushTimerTimer(Sender: TObject);
begin
  FlushTimer.Enabled := False;
  FlushOutput;
end;

procedure TTbAiFrame.FlushOutput;
var
  s, fresh: string;
  parts: TStringList;
  i, p, start: Integer;
begin
  { a feedback round starts its answer afresh: a line says so }
  if FSession.Round > FShownRound then
  begin
    FShownRound := FSession.Round;
    OutputMemo.Append(#$E2#$80#$94' ' + Format(rsTbAiRound, [FShownRound]) + ' '#$E2#$80#$94);
    FShown := 0;
    FLineOpen := False;
  end;
  s := FSession.Streamed;
  if Length(s) <= FShown then Exit;
  fresh := Copy(s, FShown + 1, MaxInt);
  FShown := Length(s);
  parts := TStringList.Create;
  try
    start := 1;
    for p := 1 to Length(fresh) do
      if fresh[p] = #10 then
      begin
        parts.Add(Copy(fresh, start, p - start));
        start := p + 1;
      end;
    parts.Add(Copy(fresh, start, MaxInt));   { the open end (maybe empty) }
    { one change for the memo, not one per line: it lays out its rows again on each }
    OutputMemo.Lines.BeginUpdate;
    try
      for i := 0 to parts.Count - 1 do
        if (i = 0) and FLineOpen and (OutputMemo.Lines.Count > 0) then
          OutputMemo.Lines[OutputMemo.Lines.Count - 1] :=
            OutputMemo.Lines[OutputMemo.Lines.Count - 1] + StringReplace(parts[0], #13, '', [rfReplaceAll])
        else
          OutputMemo.Lines.Add(StringReplace(parts[i], #13, '', [rfReplaceAll]));
    finally
      OutputMemo.Lines.EndUpdate;
    end;
    FLineOpen := True;
  finally
    parts.Free;
  end;
  if OutputMemo.Lines.Count > 0 then
    OutputMemo.SetCaret(OutputMemo.Lines.Count - 1, 0);
  if FSession.Stage = tasReceiving then
    SetStatus(Format(rsTbAiReceiving, [LineCount(s)]));
end;

procedure TTbAiFrame.SessionFinished(Sender: TObject);
begin
  FlushTimer.Enabled := False;
  FlushOutput;
  if (FSession.Stage = tasFailed) and (FSession.Outcome.Raw <> '') and (FShown = 0) then
    { an answer without a code block: the text itself is all there is to show }
    OutputMemo.Lines.Text := FSession.Outcome.Raw;
  SetStatus(FSession.Outcome.Sentence);
  UpdateButtons;
  UpdateConversation;
  if FSession.Outcome.HasCandidate then
  begin
    BtnShowCompare.Enabled := True;
    if Assigned(FOnCandidate) then
      FOnCandidate(Self);     { the comparison opens by itself }
  end;
end;

end.
