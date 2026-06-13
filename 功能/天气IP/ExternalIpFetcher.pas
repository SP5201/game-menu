unit ExternalIpFetcher;

interface

uses
  SysUtils, Classes, SyncObjs;

type
  TExternalIpInfo = record
    Ip: string;
    Country: string;
    Region: string;
    City: string;
    Area: string;
    Isp: string;
    Longitude: string;
    Latitude: string;
  end;

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
      const AFailReason: string; AIsFirstLoop, AIsScheduledRefresh: Boolean): Boolean;
    function FetchLogSignature(const AInfo: TExternalIpInfo; AOk: Boolean;
      const AFailReason: string): string;
    function InterruptibleDelay(AMs: Cardinal): Boolean;
    function WaitUntilNetworkReady: Boolean;
    function FetchExternalIpWithRetries(out AInfo: TExternalIpInfo;
      out AFailReason: string): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RequestRefresh;
    procedure RequestStop;
    property OnUpdate: TExternalIpUpdateProc read FOnUpdate write FOnUpdate;
  end;

function FetchExternalIpInfo: TExternalIpInfo; overload;
function FetchExternalIpInfo(ALogResult: Boolean): TExternalIpInfo; overload;
function GetLocalIpAddress: string;
function ExternalIpFormatDisplay(const AInfo: TExternalIpInfo): string;
function ExternalIpFormatTooltip: string; overload;
function ExternalIpFormatTooltip(const AInfo: TExternalIpInfo): string; overload;


const
  cIpipMyIpUrl = 'https://myip.ipip.net/';
  cOrayIpv4Url = 'https://ddns.oray.com/checkip';
  cExternalIpDash = '--';


function EmptyExternalIpInfo: TExternalIpInfo;
function ResolveExternalIpInfo(out AInfo: TExternalIpInfo; out AFailReason: string): Boolean;
function ExternalIpJoinLocation(const AInfo: TExternalIpInfo): string;
procedure FillExternalIpGeoDefaults(var AInfo: TExternalIpInfo);

implementation

uses
  Windows, Winapi.Winsock2, NetHttpWorker, SafeLog, NetIfTable2, IpCityCoords,
  WeatherParser;

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
  { 尚未联网时，短间隔再次尝试（避免等 2 小时）。 }
  cFetchRetryWaitMs = 12000;
  { 公网 IP 解析失败后重试间隔。 }
  cFetchFailRetryWaitMs = 5 * 60 * 1000;
  { 同内容成功结果在联网抖动期内不重复写日志。 }
  cFetchLogDebounceMs = 60000;

function FetchExternalIpWithRetries(out AInfo: TExternalIpInfo;
  out AFailReason: string): Boolean; forward;

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

function BuildExternalIpLogParsed(const AOk: Boolean; const AInfo: TExternalIpInfo;
  const AFailReason: string): string;
begin
  if AOk then
    Result := ExternalIpFormatLogParsed(AInfo)
  else
  begin
    Result := Trim(AFailReason);
    if Result = '' then
      Result := '解析公网IP失败';
  end;
end;

procedure LogExternalIpFetch(const AInfo: TExternalIpInfo; AStart: TDateTime;
  AElapsedMs: Cardinal; AOk: Boolean; const AFailReason: string);
var
  logSummary, logParsed: string;
begin
  if AOk then
    logSummary := '解析公网IP'
  else if Trim(AFailReason) <> '' then
    logSummary := Trim(AFailReason)
  else
    logSummary := '解析公网IP失败';
  logParsed := BuildExternalIpLogParsed(AOk, AInfo, AFailReason);
  SafeLogFetch('get', '公网 IP', logSummary, AStart, AElapsedMs, AOk, logParsed);
end;

function FetchExternalIpInfo(ALogResult: Boolean): TExternalIpInfo; overload;
var
  startTime: TDateTime;
  t0, elapsed: Cardinal;
  ok: Boolean;
  failReason: string;
begin
  Result := EmptyExternalIpInfo;
  ok := False;
  failReason := '';
  startTime := Now;
  t0 := GetTickCount;
  try
    ok := FetchExternalIpWithRetries(Result, failReason);
  finally
    if Cardinal(GetTickCount) >= t0 then
      elapsed := Cardinal(GetTickCount) - t0
    else
      elapsed := (High(Cardinal) - t0) + Cardinal(GetTickCount) + 1;
    if ALogResult and (not NetHttpIsAbortPending) then
      LogExternalIpFetch(Result, startTime, elapsed, ok, failReason);
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
  RequestStop;
  FreeAndNil(FNetWatchThread);
  WaitFor;
  FWakeEvent.Free;
  inherited;
end;

procedure TExternalIpFetcherThread.RequestRefresh;
begin
  FWakeEvent.SetEvent;
end;

procedure TExternalIpFetcherThread.RequestStop;
begin
  if Terminated then
    Exit;
  Terminate;
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

function TExternalIpFetcherThread.FetchExternalIpWithRetries(out AInfo: TExternalIpInfo;
  out AFailReason: string): Boolean;
var
  attempt: Integer;
  reason: string;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  AFailReason := '';
  for attempt := 1 to cFetchRetryCount do
  begin
    if Terminated or NetHttpIsAbortPending then
    begin
      if AFailReason = '' then
        AFailReason := '请求已中止';
      Exit;
    end;
    reason := '';
    try
      if ResolveExternalIpInfo(AInfo, reason) and ExternalIpFetchSucceeded(AInfo) then
        Exit(True);
      if reason <> '' then
        AFailReason := reason;
    except
      on E: Exception do
      begin
        AInfo := EmptyExternalIpInfo;
        AFailReason := '异常：' + E.Message;
      end;
    end;
    if attempt < cFetchRetryCount then
      InterruptibleDelay(cFetchRetryDelayMs);
  end;
  if AFailReason = '' then
    AFailReason := '解析公网IP失败';
end;

function FetchExternalIpWithRetries(out AInfo: TExternalIpInfo;
  out AFailReason: string): Boolean;
var
  attempt: Integer;
  reason: string;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  AFailReason := '';
  for attempt := 1 to cFetchRetryCount do
  begin
    if NetHttpIsAbortPending then
    begin
      if AFailReason = '' then
        AFailReason := '请求已中止';
      Exit;
    end;
    reason := '';
    try
      if ResolveExternalIpInfo(AInfo, reason) and ExternalIpFetchSucceeded(AInfo) then
        Exit(True);
      if reason <> '' then
        AFailReason := reason;
    except
      on E: Exception do
      begin
        AInfo := EmptyExternalIpInfo;
        AFailReason := '异常：' + E.Message;
      end;
    end;
    if attempt < cFetchRetryCount then
      Sleep(cFetchRetryDelayMs);
  end;
  if AFailReason = '' then
    AFailReason := '解析公网IP失败';
end;

function TExternalIpFetcherThread.FetchLogSignature(const AInfo: TExternalIpInfo; AOk: Boolean;
  const AFailReason: string): string;
begin
  if AOk then
    Result := 'ok:' + ExternalIpFormatDisplay(AInfo)
  else
    Result := 'fail:' + Trim(AFailReason);
end;

function TExternalIpFetcherThread.ShouldLogFetch(const AInfo: TExternalIpInfo; AOk: Boolean;
  const AFailReason: string; AIsFirstLoop, AIsScheduledRefresh: Boolean): Boolean;
var
  signature: string;
  elapsed: Cardinal;
  nowTick: Cardinal;
begin
  Result := False;
  signature := FetchLogSignature(AInfo, AOk, AFailReason);
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
  failReason: string;
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
        failReason := '';
        ok := FetchExternalIpWithRetries(info, failReason);
        if Cardinal(GetTickCount) >= t0 then
          elapsed := Cardinal(GetTickCount) - t0
        else
          elapsed := (High(Cardinal) - t0) + Cardinal(GetTickCount) + 1;
        if (not ok) and NetHttpIsAbortPending then
          failReason := '请求已中止';
        if ShouldLogFetch(info, ok, failReason, isFirstLoop, isScheduledRefresh) and
          (ok or not NetHttpIsAbortPending) then
          LogExternalIpFetch(info, startTime, elapsed, ok, failReason);
        if not Terminated then
          NotifyUi(info);
        if not ok then
          waitMs := cFetchFailRetryWaitMs
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


function EmptyExternalIpInfo: TExternalIpInfo;
begin
  Result.Ip := cExternalIpDash;
  Result.Country := cExternalIpDash;
  Result.Region := cExternalIpDash;
  Result.City := cExternalIpDash;
  Result.Area := cExternalIpDash;
  Result.Isp := cExternalIpDash;
  Result.Longitude := cExternalIpDash;
  Result.Latitude := cExternalIpDash;
end;

function IsValidPublicIpv4(const AIp: string): Boolean;
var
  parts: TStringList;
  i, n: Integer;
begin
  Result := False;
  parts := TStringList.Create;
  try
    parts.Delimiter := '.';
    parts.StrictDelimiter := True;
    parts.DelimitedText := Trim(AIp);
    if parts.Count <> 4 then
      Exit;
    for i := 0 to 3 do
    begin
      n := StrToIntDef(Trim(parts[i]), -1);
      if (n < 0) or (n > 255) then
        Exit;
    end;
    Result := True;
  finally
    parts.Free;
  end;
end;

function ExtractFirstIpv4FromText(const AText: string): string;
var
  i, start, n, dots: Integer;
  ch: Char;
  part: string;
begin
  Result := '';
  i := 1;
  while i <= Length(AText) do
  begin
    while (i <= Length(AText)) and not CharInSet(AText[i], ['0'..'9']) do
      Inc(i);
    if i > Length(AText) then
      Break;
    start := i;
    dots := 0;
    part := '';
    while i <= Length(AText) do
    begin
      ch := AText[i];
      if CharInSet(ch, ['0'..'9']) then
        part := part + ch
      else if ch = '.' then
      begin
        n := StrToIntDef(part, -1);
        if (n < 0) or (n > 255) then
          Break;
        part := '';
        Inc(dots);
        if dots > 3 then
          Break;
      end
      else
        Break;
      Inc(i);
    end;
    if (dots = 3) and (part <> '') then
    begin
      n := StrToIntDef(part, -1);
      if (n >= 0) and (n <= 255) then
      begin
        Result := Copy(AText, start, i - start);
        if IsValidPublicIpv4(Result) then
          Exit;
      end;
    end;
    Inc(i);
  end;
  Result := '';
end;

function RegionFieldValid(const S: string): Boolean;
begin
  Result := (S <> '') and (S <> '0') and (S <> cExternalIpDash);
end;

function NormalizeIspName(const S: string): string;
begin
  if Pos('移动', S) > 0 then
    Exit('移动');
  if Pos('联通', S) > 0 then
    Exit('联通');
  if Pos('电信', S) > 0 then
    Exit('电信');
  Result := Trim(S);
end;

procedure AppendLocationPart(var ADest: string; const APart: string);
begin
  if not RegionFieldValid(APart) then
    Exit;
  if ADest <> '' then
    ADest := ADest + ' ';
  ADest := ADest + APart;
end;

function ExternalIpJoinLocation(const AInfo: TExternalIpInfo): string;
begin
  Result := '';
  if RegionFieldValid(AInfo.Country) and (AInfo.Country <> '中国') then
    AppendLocationPart(Result, AInfo.Country);
  AppendLocationPart(Result, AInfo.Region);
  AppendLocationPart(Result, AInfo.City);
  AppendLocationPart(Result, AInfo.Area);
  if Result = '' then
    Result := cExternalIpDash;
end;

procedure FillExternalIpGeoDefaults(var AInfo: TExternalIpInfo);
begin
  if AInfo.Ip = '' then
    AInfo.Ip := cExternalIpDash;
  if AInfo.Country = '' then
    AInfo.Country := cExternalIpDash;
  if AInfo.Region = '' then
    AInfo.Region := cExternalIpDash;
  if AInfo.City = '' then
    AInfo.City := cExternalIpDash;
  if AInfo.Area = '' then
    AInfo.Area := cExternalIpDash;
  if AInfo.Isp = '' then
    AInfo.Isp := cExternalIpDash;
  if AInfo.Longitude = '' then
    AInfo.Longitude := cExternalIpDash;
  if AInfo.Latitude = '' then
    AInfo.Latitude := cExternalIpDash;
end;

procedure StripLeadingLocNoise(var S: string);
begin
  S := Trim(S);
  while (S <> '') and (CharInSet(S[1], [' ', #9]) or (S[1] = ':') or (S[1] = WideChar($FF1A))) do
    Delete(S, 1, 1);
end;

procedure SplitLocationTokens(const AText: string; ATokens: TStringList);
var
  i: Integer;
  ch: Char;
  token: string;
begin
  ATokens.Clear;
  token := '';
  i := 1;
  while i <= Length(AText) do
  begin
    ch := AText[i];
    if CharInSet(ch, [' ', #9, #13, #10]) then
    begin
      if token <> '' then
      begin
        ATokens.Add(token);
        token := '';
      end;
    end
    else
      token := token + ch;
    Inc(i);
  end;
  if token <> '' then
    ATokens.Add(token);
end;

procedure ParseIpipLocationTokens(const ATokens: TStringList; var AInfo: TExternalIpInfo);
var
  n: Integer;
begin
  n := ATokens.Count;
  if n <= 0 then
    Exit;
  AInfo.Country := ATokens[0];
  if n = 1 then
    Exit;
  if n = 2 then
  begin
    AInfo.Isp := NormalizeIspName(ATokens[1]);
    Exit;
  end;
  if n = 3 then
  begin
    AInfo.Region := ATokens[1];
    AInfo.Isp := NormalizeIspName(ATokens[2]);
    Exit;
  end;
  AInfo.Region := ATokens[1];
  AInfo.City := ATokens[2];
  AInfo.Isp := NormalizeIspName(ATokens[n - 1]);
  if n > 4 then
    AInfo.Area := ATokens[3];
end;

function ParseIpipMyIpBody(const ABody: string; out AInfo: TExternalIpInfo): Boolean;
var
  body, locPart: string;
  pFrom: Integer;
  tokens: TStringList;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  body := Trim(ABody);
  if body = '' then
    Exit;
  AInfo.Ip := ExtractFirstIpv4FromText(body);
  pFrom := Pos('来自于', body);
  if pFrom = 0 then
    Exit;
  locPart := Copy(body, pFrom + Length('来自于'), MaxInt);
  StripLeadingLocNoise(locPart);
  if locPart = '' then
    Exit;
  tokens := TStringList.Create;
  try
    SplitLocationTokens(locPart, tokens);
    ParseIpipLocationTokens(tokens, AInfo);
  finally
    tokens.Free;
  end;
  Result := RegionFieldValid(AInfo.Region) or RegionFieldValid(AInfo.City);
end;

function DescribeIpipParseError(const ABody: string): string;
var
  body: string;
begin
  body := Trim(ABody);
  if body = '' then
    Exit('响应解析失败：内容为空');
  if Pos('来自于', body) = 0 then
    Exit('响应解析失败：未找到归属地');
  Result := '响应解析失败：页面格式异常';
end;

function ParseIpipMyIpResponse(const AResponse: TNetHttpResponse;
  out AInfo: TExternalIpInfo; out AErrorReason: string): Boolean;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  AErrorReason := '';
  if (not AResponse.Ok) or (AResponse.StatusCode <> 200) or
    (Trim(AResponse.BodyText) = '') then
  begin
    AErrorReason := DescribeHttpResponseError(AResponse);
    Exit;
  end;
  Result := ParseIpipMyIpBody(AResponse.BodyText, AInfo);
  if not Result then
    AErrorReason := DescribeIpipParseError(AResponse.BodyText);
end;

function ParseOrayIpv4Body(const ABody: string; out AIp: string): Boolean;
begin
  AIp := ExtractFirstIpv4FromText(ABody);
  Result := IsValidPublicIpv4(AIp);
end;

function FetchPublicIpv4(out AIp: string; out AFailReason: string): Boolean;
var
  req: TNetHttpRequest;
  resp: TNetHttpResponse;
begin
  Result := False;
  AIp := '';
  AFailReason := '';
  if NetHttpIsAbortPending then
  begin
    AFailReason := '请求已中止';
    Exit;
  end;
  req.Url := cOrayIpv4Url;
  req.Kind := hkText;
  req.SaveToFile := '';
  req.Options := NetHttpDefaultOptions;
  req.UserData := 0;
  resp := NetHttpExecuteSync(req);
  if NetHttpIsAbortPending then
  begin
    AFailReason := '请求已中止';
    Exit;
  end;
  if (not resp.Ok) or (resp.StatusCode <> 200) or (Trim(resp.BodyText) = '') then
  begin
    AFailReason := DescribeHttpResponseError(resp);
    Exit;
  end;
  Result := ParseOrayIpv4Body(resp.BodyText, AIp);
  if not Result then
    AFailReason := '响应解析失败：未找到有效公网 IP';
end;

procedure ApplyCityCoords(var AInfo: TExternalIpInfo);
var
  lat, lon: Double;
begin
  if not IpCityCoordsLookup(AInfo.City, AInfo.Region, lat, lon) then
    Exit;
  AInfo.Latitude := FloatToStrF(lat, ffFixed, 15, 4);
  AInfo.Longitude := FloatToStrF(lon, ffFixed, 15, 4);
end;

function ResolveExternalIpInfo(out AInfo: TExternalIpInfo; out AFailReason: string): Boolean;
var
  req: TNetHttpRequest;
  resp: TNetHttpResponse;
  ipv4: string;
  reason: string;
begin
  Result := False;
  AInfo := EmptyExternalIpInfo;
  AFailReason := '';
  if NetHttpIsAbortPending then
  begin
    AFailReason := '请求已中止';
    Exit;
  end;
  req.Url := cIpipMyIpUrl;
  req.Kind := hkText;
  req.SaveToFile := '';
  req.Options := NetHttpDefaultOptions;
  req.UserData := 0;
  resp := NetHttpExecuteSync(req);
  if NetHttpIsAbortPending then
  begin
    AFailReason := '请求已中止';
    Exit;
  end;
  if not ParseIpipMyIpResponse(resp, AInfo, AFailReason) then
    Exit;
  if not IsValidPublicIpv4(AInfo.Ip) then
  begin
    reason := '';
    if not FetchPublicIpv4(ipv4, reason) then
    begin
      if reason <> '' then
        AFailReason := reason
      else
        AFailReason := '获取公网 IP 失败';
      Exit;
    end;
    AInfo.Ip := ipv4;
  end;
  ApplyCityCoords(AInfo);
  FillExternalIpGeoDefaults(AInfo);
  Result := True;
end;

end.
