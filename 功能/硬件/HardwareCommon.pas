unit HardwareCommon;

{
  硬件 Info 模块共享工具：静态加载门闩、文本拼接、Tick 差值。
}

interface

uses
  Windows, SysUtils;

type
  THwStaticLoadGate = record
    Loaded: Boolean;
    Loading: Boolean;
    Lock: TRTLCriticalSection;
  end;

function HwAppendLine(const ALines, ALine: string): string;
function HwTickElapsed(ANowTick, ALastTick: DWORD): Integer;

procedure HwStaticGateInit(var AGate: THwStaticLoadGate);
procedure HwStaticGateDone(var AGate: THwStaticLoadGate);
function HwStaticGateTryEnter(var AGate: THwStaticLoadGate): Boolean;
procedure HwStaticGateLeaveLoaded(var AGate: THwStaticLoadGate);
procedure HwStaticGateLeaveFailed(var AGate: THwStaticLoadGate);

implementation

function HwAppendLine(const ALines, ALine: string): string;
begin
  if ALine = '' then
    Result := ALines
  else if ALines = '' then
    Result := ALine
  else
    Result := ALines + sLineBreak + ALine;
end;

function HwTickElapsed(ANowTick, ALastTick: DWORD): Integer;
begin
  if ANowTick >= ALastTick then
    Result := ANowTick - ALastTick
  else
    Result := (High(DWORD) - ALastTick) + ANowTick + 1;
end;

procedure HwStaticGateInit(var AGate: THwStaticLoadGate);
begin
  AGate.Loaded := False;
  AGate.Loading := False;
  InitializeCriticalSection(AGate.Lock);
end;

procedure HwStaticGateDone(var AGate: THwStaticLoadGate);
begin
  DeleteCriticalSection(AGate.Lock);
end;

function HwStaticGateTryEnter(var AGate: THwStaticLoadGate): Boolean;
begin
  Result := False;
  if AGate.Loaded then
    Exit;
  EnterCriticalSection(AGate.Lock);
  try
    if AGate.Loaded then
      Exit;
    if AGate.Loading then
      Exit;
    AGate.Loading := True;
    Result := True;
  finally
    if not Result then
      LeaveCriticalSection(AGate.Lock);
  end;
end;

procedure HwStaticGateLeaveLoaded(var AGate: THwStaticLoadGate);
begin
  try
    AGate.Loaded := True;
    AGate.Loading := False;
  finally
    LeaveCriticalSection(AGate.Lock);
  end;
end;

procedure HwStaticGateLeaveFailed(var AGate: THwStaticLoadGate);
begin
  try
    AGate.Loading := False;
  finally
    LeaveCriticalSection(AGate.Lock);
  end;
end;

end.
