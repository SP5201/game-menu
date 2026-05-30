unit ExternalIpFetcher;

interface

uses
  SysUtils, Classes, SyncObjs, ExternalIpParser;

type
  TExternalIpUpdateProc = procedure(const AInfo: TExternalIpInfo);

  TExternalIpFetcherThread = class;

  { 监听系统地址/路由变化，触发外网 IP 提前刷新。 }
  TExternalIpNetWatchThread = class(TThread)
  private
    FWakeTarget: TExternalIpFetcherThread;
    FNotifyEvent: THandle;
    FStopEvent: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AWakeTarget: TExternalIpFetcherThread);
    destructor Destroy; override;
  end;

  TExternalIpFetcherThread = class(TThread)
  private
    FWakeEvent: TEvent;
    FNetWatchThread: TExternalIpNetWatchThread;
    FOnUpdate: TExternalIpUpdateProc;
    FLastLogTick: Cardinal;
    FLastLogDisplay: string;
    procedure NotifyUi(const AInfo: TExternalIpInfo);
    procedure SettleNetChangeSignals;
    procedure DrainWakeEvent;
    function ShouldLogFetch(const AInfo: TExternalIpInfo; AOk: Boolean;
      AIsFirstLoop, AIsScheduledRefresh: Boolean): Boolean;
    function FetchLogSignature(const AInfo: TExternalIpInfo; AOk: Boolean): string;
    function InterruptibleDelay(AMs: Cardinal): Boolean;
    function WaitUntilNetworkReady: Boolean;
    function FetchExternalIpWithRetries(out AInfo: TExternalIpInfo): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RequestRefresh;
    property OnUpdate: TExternalIpUpdateProc read FOnUpdate write FOnUpdate;
  end;

function FetchExternalIpInfo: TExternalIpInfo; overload;
function FetchExternalIpInfo(ALogResult: Boolean): TExternalIpInfo; overload;
function GetLocalIpAddress: string;
function ExternalIpFormatDisplay(const AInfo: TExternalIpInfo): string;
function ExternalIpFormatTooltip: string; overload;
function ExternalIpFormatTooltip(const AInfo: TExternalIpInfo): string; overload;

implementation

uses
  Windows, Winapi.Winsock2, NetHttpWorker, SafeLog, NetIfTable2;

const
  cRefreshIntervalMs = 2 * 60 * 60 * 1000; { 2 小时 }
  { 断网/重连/DHCP 会连续触发多次 NotifyAddrChange，静默窗口内合并为一次拉取。 }
  cNetChangeSettleMs = 3000;
  { 轮询间隔：检测本地 IP 是否连续稳定，就绪即继续（非固定等待）。 }
  cSettlePollMs = 300;
  cSettleStableHits = 2;
  cSettleMaxWaitMs = 15000;
  { 单轮内失败时的重试次数与间隔。 }
  cFetchRetryCount = 4;
  cFetchRetryDelayMs = 1500;
  { 首轮失败或尚未联网时，短间隔再次尝试（避免等 2 小时）。 }
  cFetchRetryWaitMs = 12000;
  { 同内容成功结果在联网抖动期内不重复写日志。 }
  cFetchLogDebounceMs = 60000;

function FetchExternalIpWithRetries(out AInfo: TExternalIpInfo): Boolean; forward;

function NotifyAddrChange(lpHandle: PHANDLE; lpOverlapped: POverlapped): DWORD; stdcall;
  external 'iphlpapi.dll' name 'NotifyAddrChange';

function CanFetchExternalIp: Boolean;
begin
  Result := NetIfHasPhysActiveAdapter and (GetLocalIpAddress <> cExternalIpDash);
end;

function GetLocalIpAddress: string;
const
  cProbeHost = '8.8.8.8';
  cProbePort: Word = 80;
var
  wsa: TWSAData;
  sock: TSocket;
  remote, local: TSockAddrIn;
  len: Integer;
  addrStr: PAnsiChar;
begin
  Result := cExternalIpDash;
  if WSAStartup(MAKEWORD(2, 2), wsa) <> 0 then
    Exit;
  try
    sock := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if sock = INVALID_SOCKET then
      Exit;
    try
      FillChar(remote, SizeOf(remote), 0);
      remote.sin_family := AF_INET;
      remote.sin_port := htons(cProbePort);
      remote.sin_addr.S_addr := inet_addr(PAnsiChar(AnsiString(cProbeHost)));
      if connect(sock, PSockAddr(@remote)^, SizeOf(remote)) = SOCKET_ERROR then
        Exit;
      len := SizeOf(local);
      FillChar(local, SizeOf(local), 0);
      if getsockname(sock, PSockAddr(@local)^, len) <> 0 then
        Exit;
      addrStr := inet_ntoa(local.sin_addr);
      if addrStr <> nil then
        Result := string(AnsiString(addrStr));
    finally
      closesocket(sock);
    end;
  finally
    WSACleanup;
  end;
  if (Result = '') or (Result = '0.0.0.0') then
    Result := cExternalIpDash;
end;

function ExternalIpFormatDisplay(const AInfo: TExternalIpInfo): string;
var
  suffix: string;
begin
  Result := AInfo.Ip;
  suffix := '';
  if (AInfo.City <> '') and (AInfo.City <> cExternalIpDash) then
    suffix := AInfo.City;
  if (AInfo.Isp <> '') and (AInfo.Isp <> cExternalIpDash) then
    suffix := suffix + AInfo.Isp;
  if suffix <> '' then
    Result := Result + ' (' + suffix + ')';
end;

function ExternalIpFormatLogParsed(const AInfo: TExternalIpInfo): string;
var
  ip, place, coords: string;
begin
  ip := AInfo.Ip;
  if (ip = '') or (ip = cExternalIpDash) then
    ip := cExternalIpDash;
  place := '';
  if (AInfo.City <> '') and (AInfo.City <> cExternalIpDash) then
    place := AInfo.City;
  if (AInfo.Isp <> '') and (AInfo.Isp <> cExternalIpDash) then
    place := place + AInfo.Isp;
  if place = '' then
    place := cExternalIpDash;
  if (AInfo.Longitude <> '') and (AInfo.Longitude <> cExternalIpDash) and
    (AInfo.Latitude <> '') and (AInfo.Latitude <> cExternalIpDash) then
    coords := AInfo.Longitude + ',' + AInfo.Latitude
  else
    coords := cExternalIpDash;
  Result := ip + ' >>> ' + place + ' >>> ' + coords;
end;

function ExternalIpFormatTooltip: string;
begin
  Result := ExternalIpFormatTooltip(EmptyExternalIpInfo);
end;

function ExternalIpFormatTooltip(const AInfo: TExternalIpInfo): string;
var
  loc, isp, lon, lat: string;
begin
  Result := '本地IP：' + GetLocalIpAddress + sLineBreak +
    '外部IP：' + AInfo.Ip + sLineBreak;
  loc := ExternalIpJoinLocation(AInfo);
  if (AInfo.Isp <> '') and (AInfo.Isp <> cExternalIpDash) then
    isp := AInfo.Isp
  else
    isp := cExternalIpDash;
  if (AInfo.Longitude <> '') and (AInfo.Longitude <> cExternalIpDash) then
    lon := AInfo.Longitude
  else
    lon := cExternalIpDash;
  if (AInfo.Latitude <> '') and (AInfo.Latitude <> cExternalIpDash) then
    lat := AInfo.Latitude
  else
    lat := cExternalIpDash;
  Result := Result + sLineBreak + '归属地：' + loc + sLineBreak + '运营商：' + isp + sLineBreak +
    '经度：' + lon + sLineBreak + '纬度：' + lat;
end;

function ExternalIpFetchSucceeded(const AInfo: TExternalIpInfo): Boolean;
begin
  Result := (AInfo.Ip <> '') and (AInfo.Ip <> cExternalIpDash);
end;

procedure LogExternalIpFetch(const AInfo: TExternalIpInfo; AStart: TDateTime;
  AElapsedMs: Cardinal; AOk: Boolean);
begin
  SafeLogFetch('get', '公网 IP', '解析公网IP', AStart, AElapsedMs, AOk,
    ExternalIpFormatLogParsed(AInfo));
end;

function FetchExternalIpInfo(ALogResult: Boolean): TExternalIpInfo; overload;
var
  startTime: TDateTime;
  t0, elapsed: Cardinal;
  ok: Boolean;
begin
  Result := EmptyExternalIpInfo;
  ok := False;
  startTime := Now;
  t0 := GetTickCount;
  try
    ok := FetchExternalIpWithRetries(Result);
  finally
    if Cardinal(GetTickCount) >= t0 then
      elapsed := Cardinal(GetTickCount) - t0
    else
      elapsed := (High(Cardinal) - t0) + Cardinal(GetTickCount) + 1;
    if ALogResult then
      LogExternalIpFetch(Result, startTime, elapsed, ok);
  end;
end;

function FetchExternalIpInfo: TExternalIpInfo; overload;
begin
  Result := FetchExternalIpInfo(True);
end;

constructor TExternalIpFetcherThread.Create;
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FWakeEvent := TEvent.Create(nil, False, False, '');
  FNetWatchThread := TExternalIpNetWatchThread.Create(Self);
  FOnUpdate := nil;
  FLastLogTick := 0;
  FLastLogDisplay := '';
end;

destructor TExternalIpFetcherThread.Destroy;
begin
  Terminate;
  FreeAndNil(FNetWatchThread);
  FWakeEvent.SetEvent;
  WaitFor;
  FWakeEvent.Free;
  inherited;
end;

procedure TExternalIpFetcherThread.RequestRefresh;
begin
  FWakeEvent.SetEvent;
end;

procedure TExternalIpFetcherThread.NotifyUi(const AInfo: TExternalIpInfo);
begin
  if Assigned(FOnUpdate) then
    FOnUpdate(AInfo);
end;

procedure TExternalIpFetcherThread.SettleNetChangeSignals;
var
  waitResult: TWaitResult;
  i, maxSteps: Integer;
begin
  maxSteps := cNetChangeSettleMs div 100;
  if maxSteps < 1 then
    maxSteps := 1;
  for i := 1 to maxSteps do
  begin
    if Terminated then
      Exit;
    Sleep(100);
    waitResult := FWakeEvent.WaitFor(0);
    if waitResult <> wrSignaled then
      Exit;
  end;
end;

procedure TExternalIpFetcherThread.DrainWakeEvent;
begin
  while FWakeEvent.WaitFor(0) = wrSignaled do ;
end;

function TExternalIpFetcherThread.InterruptibleDelay(AMs: Cardinal): Boolean;
var
  waitResult: TWaitResult;
  remaining, step: Cardinal;
begin
  Result := False;
  remaining := AMs;
  while (remaining > 0) and not Terminated do
  begin
    if remaining > 200 then
      step := 200
    else
      step := remaining;
    waitResult := FWakeEvent.WaitFor(step);
    if waitResult = wrSignaled then
      Exit(True);
    Dec(remaining, step);
  end;
end;

function TExternalIpFetcherThread.WaitUntilNetworkReady: Boolean;
var
  startTick, nowTick, elapsed: Cardinal;
  lastIp, curIp: string;
  stableHits: Integer;
begin
  Result := False;
  stableHits := 0;
  lastIp := '';
  startTick := GetTickCount;
  while not Terminated do
  begin
    if CanFetchExternalIp then
    begin
      curIp := GetLocalIpAddress;
      if curIp <> cExternalIpDash then
      begin
        if (lastIp <> '') and (curIp = lastIp) then
          Inc(stableHits)
        else
          stableHits := 1;
        lastIp := curIp;
        if stableHits >= cSettleStableHits then
          Exit(True);
      end
      else
      begin
        stableHits := 0;
        lastIp := '';
      end;
    end
    else
    begin
      stableHits := 0;
      lastIp := '';
    end;
    nowTick := GetTickCount;
    if nowTick >= startTick then
      elapsed := nowTick - startTick
    else
      elapsed := (High(Cardinal) - startTick) + nowTick + 1;
    if elapsed >= cSettleMaxWaitMs then
      Exit(CanFetchExternalIp);
    if InterruptibleDelay(cSettlePollMs) then
    begin
      SettleNetChangeSignals;
      stableHits := 0;
      lastIp := '';
    end;
  end;
end;

function TExternalIpFetcherThread.FetchExternalIpWithRetries(out AInfo: TExternalIpInfo): Boolean;
var
  attempt: Integer;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  for attempt := 1 to cFetchRetryCount do
  begin
    if Terminated then
      Exit;
    try
      if ResolveExternalIpInfo(AInfo) and ExternalIpFetchSucceeded(AInfo) then
        Exit(True);
    except
      on E: Exception do
        AInfo := EmptyExternalIpInfo;
    end;
    if attempt < cFetchRetryCount then
      InterruptibleDelay(cFetchRetryDelayMs);
  end;
end;

function FetchExternalIpWithRetries(out AInfo: TExternalIpInfo): Boolean;
var
  attempt: Integer;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  for attempt := 1 to cFetchRetryCount do
  begin
    try
      if ResolveExternalIpInfo(AInfo) and ExternalIpFetchSucceeded(AInfo) then
        Exit(True);
    except
      on E: Exception do
        AInfo := EmptyExternalIpInfo;
    end;
    if attempt < cFetchRetryCount then
      Sleep(cFetchRetryDelayMs);
  end;
end;

function TExternalIpFetcherThread.FetchLogSignature(const AInfo: TExternalIpInfo; AOk: Boolean): string;
begin
  if AOk then
    Result := 'ok:' + ExternalIpFormatDisplay(AInfo)
  else
    Result := 'fail';
end;

function TExternalIpFetcherThread.ShouldLogFetch(const AInfo: TExternalIpInfo; AOk: Boolean;
  AIsFirstLoop, AIsScheduledRefresh: Boolean): Boolean;
var
  signature: string;
  elapsed: Cardinal;
  nowTick: Cardinal;
begin
  Result := False;
  signature := FetchLogSignature(AInfo, AOk);
  if AIsFirstLoop or AIsScheduledRefresh then
  begin
    FLastLogDisplay := signature;
    FLastLogTick := GetTickCount;
    Exit(True);
  end;
  if signature <> FLastLogDisplay then
  begin
    FLastLogDisplay := signature;
    FLastLogTick := GetTickCount;
    Exit(True);
  end;
  nowTick := GetTickCount;
  if nowTick >= FLastLogTick then
    elapsed := nowTick - FLastLogTick
  else
    elapsed := (High(Cardinal) - FLastLogTick) + nowTick + 1;
  if elapsed >= cFetchLogDebounceMs then
  begin
    FLastLogTick := nowTick;
    Exit(True);
  end;
end;

procedure TExternalIpFetcherThread.Execute;
var
  info: TExternalIpInfo;
  waitResult: TWaitResult;
  isFirstLoop: Boolean;
  isScheduledRefresh: Boolean;
  ok: Boolean;
  startTime: TDateTime;
  t0, elapsed, waitMs: Cardinal;
begin
  FNetWatchThread.Start;
  isFirstLoop := True;
  isScheduledRefresh := True;
  while not Terminated do
  begin
    waitMs := cRefreshIntervalMs;
    if CanFetchExternalIp and not Terminated then
    begin
      if isFirstLoop or not isScheduledRefresh then
        WaitUntilNetworkReady;
      if CanFetchExternalIp and not Terminated then
      begin
        startTime := Now;
        t0 := GetTickCount;
        info := EmptyExternalIpInfo;
        ok := FetchExternalIpWithRetries(info);
        if Cardinal(GetTickCount) >= t0 then
          elapsed := Cardinal(GetTickCount) - t0
        else
          elapsed := (High(Cardinal) - t0) + Cardinal(GetTickCount) + 1;
        if ShouldLogFetch(info, ok, isFirstLoop, isScheduledRefresh) then
          LogExternalIpFetch(info, startTime, elapsed, ok);
        if not Terminated then
          NotifyUi(info);
        if not ok then
          waitMs := cFetchRetryWaitMs
        else if not isScheduledRefresh then
          DrainWakeEvent;
      end;
    end
    else if isFirstLoop or not isScheduledRefresh then
      waitMs := cFetchRetryWaitMs;
    isFirstLoop := False;
    if Terminated then
      Break;
    waitResult := FWakeEvent.WaitFor(waitMs);
    isScheduledRefresh := waitResult = wrTimeout;
    if Terminated then
      Break;
    if waitResult = wrSignaled then
      SettleNetChangeSignals;
  end;
end;

constructor TExternalIpNetWatchThread.Create(AWakeTarget: TExternalIpFetcherThread);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FWakeTarget := AWakeTarget;
  FNotifyEvent := CreateEvent(nil, True, False, nil);
  FStopEvent := TEvent.Create(nil, False, False, '');
end;

destructor TExternalIpNetWatchThread.Destroy;
begin
  Terminate;
  FStopEvent.SetEvent;
  WaitFor;
  CloseHandle(FNotifyEvent);
  FStopEvent.Free;
  inherited;
end;

procedure TExternalIpNetWatchThread.Execute;
var
  hChange: THandle;
  ov: TOverlapped;
  handles: array[0..1] of THandle;
  waitResult: DWORD;
begin
  hChange := INVALID_HANDLE_VALUE;
  handles[0] := FNotifyEvent;
  handles[1] := FStopEvent.Handle;
  while not Terminated do
  begin
    ResetEvent(FNotifyEvent);
    FillChar(ov, SizeOf(ov), 0);
    ov.hEvent := FNotifyEvent;
    if NotifyAddrChange(@hChange, @ov) = ERROR_IO_PENDING then
    begin
      repeat
        waitResult := WaitForMultipleObjects(2, @handles[0], False, 1000);
        if waitResult = WAIT_OBJECT_0 + 1 then
          Exit;
      until (waitResult = WAIT_OBJECT_0) or Terminated;
      if Terminated then
        Break;
      if Assigned(FWakeTarget) then
        FWakeTarget.RequestRefresh;
    end
    else if FStopEvent.WaitFor(1000) = wrSignaled then
      Exit;
  end;
end;

end.
