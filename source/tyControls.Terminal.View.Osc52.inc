{ tyControls.Terminal 的一部分(被 include,不是单元):OSC 52——三种策略下程序读写剪贴板。
  只为好读从单元里搬出来;控件是什么、参照上游哪里,见单元头。 }

{ ---- OSC 52 ------------------------------------------------------------------------ }

{ ClipboardAddon.ts:32-66,外加三种策略与宿主的同意。上游读剪贴板是 Promise、解析器停住等
  它;这里同步问宿主,应答的顺序同样不乱。应答不是用户输入(不清选区、不滚到底)。
  这里在解析中间:宿主的事件、剪贴板(别的程序占着时 LCL 会抛)抛出来的异常一律吞在这里——
  冒出 Parse 会丢掉这一块剩下的字节。宿主可以在事件里弹模态框,不能释放控件。 }
function TTyCustomTerminalView.HandleOsc52(const AData: string): Boolean;
var
  pc, pd, txt: string;
  allow: Boolean;
begin
  Result := True;
  if FOsc52 = to52Off then
    Exit;
  if not TyTermOsc52Split(AData, pc, pd) then
    Exit;
  try
    if pd = '?' then
    begin
      if FOsc52 <> to52ReadWrite then
        Exit;
      txt := ReadClipboardText;
      allow := False;
      if Assigned(FOnOsc52) then
        FOnOsc52(Self, False, pc, txt, allow);
      if allow then
        FCore.Input(TyTermOsc52Reply(pc, txt), False);
    end
    else
    begin
      txt := TyTermOsc52Decode(pd);
      allow := True;
      if Assigned(FOnOsc52) then
        FOnOsc52(Self, True, pc, txt, allow);
      if allow then
        WriteClipboardText(txt);
    end;
  except
    { 这一条 OSC 52 作罢;解析接着往下走 }
  end;
end;
