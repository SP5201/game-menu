unit CpuInfo;

{
  CPU 悬停提示：静态信息优先 NwInfoRunner（--cpu），失败回退 CpuInfoNative；
  温度/电压按 TTL 缓存刷新（--sensors=CPU）；实时当前频率由 Native 刷新。
}

interface

uses
  SysUtils, CpuInfoTypes;

function CpuQueryStaticInfo: TCpuStaticInfo;
function CpuPeekStaticInfo(out ALoaded: Boolean): TCpuStaticInfo;
procedure CpuPreloadHintData;
function CpuFormatTooltip(const AUsageText: string): string;

implementation

uses
  Windows, CpuInfoNative, CpuInfoNwInfo;

const
  cCpuSensorRefreshMs = 3000;
  cCpuSensorRetryMs = 30000;

var
  GStaticLoaded: Boolean;
  GStaticInfo: TCpuStaticInfo;
  GStaticLoadLock: TRTLCriticalSection;
  GStaticLoading: Boolean;
  GSensorsInfo: TCpuSensorInfo;
  GSensorsValid: Boolean;
  GSensorsHasData: Boolean;
  GSensorsLastTick: DWORD;
  GSensorsLock: TRTLCriticalSection;
  GSensorsLoading: Boolean;

function CpuSensorHasData(const AInfo: TCpuSensorInfo): Boolean;
begin
  Result := AInfo.HasCoreTemp or AInfo.HasPackageTemp or AInfo.HasVoltage;
end;

function CpuSensorsTickElapsed(ANowTick, ALastTick: DWORD): Integer;
begin
  if ANowTick >= ALastTick then
    Result := ANowTick - ALastTick
  else
    Result := (High(DWORD) - ALastTick) + ANowTick + 1;
end;

procedure CpuRefreshSensorsIfStale;
var
  nowTick: DWORD;
  elapsed, retryMs: Integer;
  fresh: TCpuSensorInfo;
  hasData: Boolean;
begin
  nowTick := GetTickCount;
  EnterCriticalSection(GSensorsLock);
  try
    if GSensorsLoading then
      Exit;
    if GSensorsValid then
    begin
      elapsed := CpuSensorsTickElapsed(nowTick, GSensorsLastTick);
      if GSensorsHasData then
        retryMs := cCpuSensorRefreshMs
      else
        retryMs := cCpuSensorRetryMs;
      if elapsed < retryMs then
        Exit;
    end;
    GSensorsLoading := True;
  finally
    LeaveCriticalSection(GSensorsLock);
  end;

  CpuInitSensorInfo(fresh);
  hasData := False;
  if CpuTryQuerySensorsFromNwInfo(fresh) then
    hasData := CpuSensorHasData(fresh);

  EnterCriticalSection(GSensorsLock);
  try
    GSensorsInfo := fresh;
    GSensorsHasData := hasData;
    GSensorsValid := True;
    GSensorsLastTick := GetTickCount;
    GSensorsLoading := False;
  finally
    LeaveCriticalSection(GSensorsLock);
  end;
end;

function CpuQuerySensorInfo: TCpuSensorInfo;
begin
  CpuRefreshSensorsIfStale;
  EnterCriticalSection(GSensorsLock);
  try
    Result := GSensorsInfo;
  finally
    LeaveCriticalSection(GSensorsLock);
  end;
end;

function CpuPeekSensorInfo: TCpuSensorInfo;
begin
  EnterCriticalSection(GSensorsLock);
  try
    Result := GSensorsInfo;
  finally
    LeaveCriticalSection(GSensorsLock);
  end;
end;

procedure CpuInitStaticLoadLock;
begin
  InitializeCriticalSection(GStaticLoadLock);
end;

procedure CpuDoneStaticLoadLock;
begin
  DeleteCriticalSection(GStaticLoadLock);
end;

procedure CpuMergeMissingFields(var ATarget, ANative: TCpuStaticInfo);
begin
  if ATarget.Brand = '' then
    ATarget.Brand := ANative.Brand;
  if ATarget.Vendor = '' then
    ATarget.Vendor := ANative.Vendor;
  if ATarget.PhysicalCores <= 0 then
    ATarget.PhysicalCores := ANative.PhysicalCores;
  if ATarget.LogicalProcessors <= 0 then
    ATarget.LogicalProcessors := ANative.LogicalProcessors;
  if ATarget.BaseSpeedMhz = 0 then
    ATarget.BaseSpeedMhz := ANative.BaseSpeedMhz;
  if ATarget.L1CacheBytes = 0 then
    ATarget.L1CacheBytes := ANative.L1CacheBytes;
  if ATarget.L2CacheBytes = 0 then
    ATarget.L2CacheBytes := ANative.L2CacheBytes;
  if ATarget.L3CacheBytes = 0 then
    ATarget.L3CacheBytes := ANative.L3CacheBytes;
  ATarget.CurrentSpeedMhz := ANative.CurrentSpeedMhz;
end;

procedure CpuLoadStaticInfo;
var
  nwInfo, nativeInfo: TCpuStaticInfo;
begin
  if GStaticLoaded then
    Exit;
  EnterCriticalSection(GStaticLoadLock);
  try
    if GStaticLoaded then
      Exit;
    if GStaticLoading then
      Exit;
    GStaticLoading := True;
    try
      nativeInfo := CpuNativeQueryStaticInfo;
      FillChar(nwInfo, SizeOf(nwInfo), 0);
      if CpuTryQueryFromNwInfo(nwInfo) then
      begin
        if nwInfo.Brand <> '' then
          nwInfo.Brand := CpuNativeFormatModelName(nwInfo.Brand);
        CpuMergeMissingFields(nwInfo, nativeInfo);
        GStaticInfo := nwInfo;
      end
      else
        GStaticInfo := nativeInfo;
      GStaticLoaded := True;
    finally
      GStaticLoading := False;
    end;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
end;

procedure CpuPreloadHintData;
begin
  CpuLoadStaticInfo;
  CpuRefreshSensorsIfStale;
end;

function CpuQueryStaticInfo: TCpuStaticInfo;
var
  nativeInfo: TCpuStaticInfo;
begin
  CpuLoadStaticInfo;
  EnterCriticalSection(GStaticLoadLock);
  try
    Result := GStaticInfo;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
  nativeInfo := CpuNativeQueryStaticInfo;
  Result.CurrentSpeedMhz := nativeInfo.CurrentSpeedMhz;
end;

function CpuPeekStaticInfo(out ALoaded: Boolean): TCpuStaticInfo;
begin
  ALoaded := GStaticLoaded;
  if not ALoaded then
  begin
    FillChar(Result, SizeOf(Result), 0);
    Exit;
  end;
  EnterCriticalSection(GStaticLoadLock);
  try
    Result := GStaticInfo;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
end;

function CpuFormatCoreThreadText(ACores, AThreads: Integer): string;
begin
  if (ACores <= 0) and (AThreads <= 0) then
    Result := cCpuDash
  else if (ACores > 0) and (AThreads > ACores) then
    Result := IntToStr(ACores) + '核 ' + IntToStr(AThreads) + '线程'
  else if ACores > 0 then
    Result := IntToStr(ACores) + '核'
  else
    Result := IntToStr(AThreads) + '核';
end;

function CpuFormatSpeedMhz(AMhz: DWORD): string;
begin
  if AMhz = 0 then
    Result := cCpuDash
  else
    Result := IntToStr(AMhz) + ' MHz';
end;

function CpuFormatCacheSizeText(ABytes: DWORD): string;
var
  kb, mb: Int64;
begin
  if ABytes = 0 then
    Result := cCpuDash
  else if ABytes >= 1024 * 1024 then
  begin
    mb := (Int64(ABytes) + (1024 * 1024) - 1) div (1024 * 1024);
    Result := IntToStr(mb) + ' MB';
  end
  else
  begin
    kb := (Int64(ABytes) + 1023) div 1024;
    Result := IntToStr(kb) + ' KB';
  end;
end;

function CpuFormatTooltip(const AUsageText: string): string;
var
  info: TCpuStaticInfo;
  sensors: TCpuSensorInfo;
  brandLine, usageText, coreThreadText: string;
  staticLoaded: Boolean;
begin
  info := CpuPeekStaticInfo(staticLoaded);
  if not staticLoaded then
  begin
    if (AUsageText <> '') and (AUsageText <> cCpuDash) then
      usageText := AUsageText
    else
      usageText := cCpuDash;
    Exit('使用率：' + usageText + sLineBreak + '（详细信息加载中…）');
  end;
  sensors := CpuPeekSensorInfo;

  brandLine := info.Brand;
  if brandLine = '' then
    brandLine := cCpuDash;
  coreThreadText := CpuFormatCoreThreadText(info.PhysicalCores, info.LogicalProcessors);

  if (AUsageText <> '') and (AUsageText <> cCpuDash) then
    usageText := AUsageText
  else
    usageText := cCpuDash;

  Result := '型号：' + brandLine + sLineBreak +
    '规格：' + coreThreadText + sLineBreak +
    'L1缓存：' + CpuFormatCacheSizeText(info.L1CacheBytes) + sLineBreak +
    'L2缓存：' + CpuFormatCacheSizeText(info.L2CacheBytes) + sLineBreak +
    'L3缓存：' + CpuFormatCacheSizeText(info.L3CacheBytes) + sLineBreak +
    '基准速度：' + CpuFormatSpeedMhz(info.BaseSpeedMhz) + sLineBreak +
    '速度：' + CpuFormatSpeedMhz(info.CurrentSpeedMhz) + sLineBreak +
    '温度：' + CpuFormatSensorTemperatureText(sensors) + sLineBreak +
    '电压：' + CpuFormatSensorVoltageText(sensors) + sLineBreak +
    '使用率：' + usageText;
end;

initialization
  CpuInitStaticLoadLock;
  InitializeCriticalSection(GSensorsLock);
  FillChar(GStaticInfo, SizeOf(GStaticInfo), 0);
  CpuInitSensorInfo(GSensorsInfo);

finalization
  DeleteCriticalSection(GSensorsLock);
  CpuDoneStaticLoadLock;

end.
