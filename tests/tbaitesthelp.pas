unit tbaitesthelp;
{ A scripted model for the AI tests (spec §8: "a fake model answering from a script"): it
  answers each request with the next answer of its list (the last one repeats), as pieces
  of text and then a result, inside Start -- synchronously, so a whole generation with its
  feedback rounds runs in one call. Or it holds the request (Hold) until the test releases
  it, to see Stop, a busy session, a window closed in the middle. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, tbaiformat, tbaiclient, tbaisession;

type
  TScriptedAnswer = record
    Pieces: TStringArray;
    Thinking: Boolean;
    Kind: TTbAiErrorKind;
    Status: Integer;
  end;

  TScriptedBackend = class(TTbChatBackend)
  public
    class var Cancelled: Integer;   { every instance's Cancel calls, for windows freed with it }
    class var Freed: Integer;
  public
    Answers: array of TScriptedAnswer;
    Next: Integer;
    Hold: Boolean;
    Held: Boolean;
    Starts, Cancels: Integer;
    Systems: TStringList;
    Sent: array of TTbChatMessages;
    constructor Create;
    destructor Destroy; override;
    procedure Start(const ASystem: string; const AMessages: TTbChatMessages); override;
    procedure Cancel; override;
    { one more answer: the text in one piece (or in APieces pieces), then this result }
    procedure Add(const AText: string; AKind: TTbAiErrorKind = aekNone; AStatus: Integer = 200;
      APieces: Integer = 1; AThinking: Boolean = False);
    { answer the held request with the next answer }
    procedure Release;
    { end the held request with AKind and no text }
    procedure ReleaseWith(AKind: TTbAiErrorKind; AStatus: Integer = 0);
    function AllSent(AIndex: Integer): string;   { request AIndex's messages joined }
  end;

{ '... sentence'#10'```tycss'#10 + ABody + #10'```' }
function TbAnswerWith(const ABody: string; const ALead: string = 'Here it is.'): string;

implementation

function TbAnswerWith(const ABody, ALead: string): string;
begin
  Result := ALead + #10'```tycss'#10 + ABody;
  if (Result <> '') and (Result[Length(Result)] <> #10) then
    Result := Result + #10;
  Result := Result + '```';
end;

constructor TScriptedBackend.Create;
begin
  inherited Create;
  Systems := TStringList.Create;
  FProfile := Default(TTbAiProfile);
  FProfile.Name := 'scripted';
  FProfile.BaseUrl := 'http://127.0.0.1:1/v1';
  FProfile.Model := 'scripted';
end;

destructor TScriptedBackend.Destroy;
begin
  Inc(Freed);
  Systems.Free;
  inherited Destroy;
end;

procedure TScriptedBackend.Add(const AText: string; AKind: TTbAiErrorKind; AStatus: Integer;
  APieces: Integer; AThinking: Boolean);
var
  a: TScriptedAnswer;
  i, size, from: Integer;
begin
  a := Default(TScriptedAnswer);
  a.Kind := AKind;
  a.Status := AStatus;
  a.Thinking := AThinking;
  if APieces < 1 then APieces := 1;
  SetLength(a.Pieces, APieces);
  size := (Length(AText) + APieces - 1) div APieces;
  from := 1;
  for i := 0 to APieces - 1 do
  begin
    a.Pieces[i] := Copy(AText, from, size);
    Inc(from, size);
  end;
  SetLength(Answers, Length(Answers) + 1);
  Answers[High(Answers)] := a;
end;

procedure TScriptedBackend.Start(const ASystem: string; const AMessages: TTbChatMessages);
begin
  Inc(Starts);
  Systems.Add(ASystem);
  SetLength(Sent, Length(Sent) + 1);
  Sent[High(Sent)] := Copy(AMessages);
  if Hold then
  begin
    Held := True;
    Exit;
  end;
  Release;
end;

procedure TScriptedBackend.Cancel;
begin
  Inc(Cancels);
  Inc(Cancelled);
end;

procedure TScriptedBackend.Release;
var
  a: TScriptedAnswer;
  r: TTbAiResult;
  i: Integer;
begin
  Held := False;
  if Length(Answers) = 0 then
  begin
    ReleaseWith(aekBadFormat);
    Exit;
  end;
  if Next <= High(Answers) then
    a := Answers[Next]
  else
    a := Answers[High(Answers)];
  Inc(Next);
  r := Default(TTbAiResult);
  r.Kind := a.Kind;
  r.Status := a.Status;
  if a.Thinking and Assigned(OnDelta) then
    OnDelta(Self, tspThinking, '');
  for i := 0 to High(a.Pieces) do
  begin
    r.Text := r.Text + a.Pieces[i];
    if (a.Pieces[i] <> '') and Assigned(OnDelta) then
      OnDelta(Self, tspText, a.Pieces[i]);
  end;
  if Assigned(OnDone) then
    OnDone(Self, r);
end;

procedure TScriptedBackend.ReleaseWith(AKind: TTbAiErrorKind; AStatus: Integer);
var
  r: TTbAiResult;
begin
  Held := False;
  r := Default(TTbAiResult);
  r.Kind := AKind;
  r.Status := AStatus;
  if Assigned(OnDone) then
    OnDone(Self, r);
end;

function TScriptedBackend.AllSent(AIndex: Integer): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(Sent[AIndex]) do
    Result := Result + Sent[AIndex][i].Text + #1;
end;

end.
