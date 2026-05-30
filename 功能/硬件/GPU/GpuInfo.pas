unit GpuInfo;

{
  GPU 悬停提示：静态信息优先 NwInfoRunner（--gpu），失败回退 GpuInfoNative；
  传感器按 TTL 缓存刷新（--sensors=GPU）。
}

interface

uses
  SysUtils, GpuInfoTypes;

procedure GpuPreloadHintData;
function GpuPeekStaticInfo(out ALoaded: Boolean): TGpuStaticInfo;
function GpuFormatTooltip(const AUsageText: string): string;

implementation

uses
  Windows, Math, GpuInfoNative, GpuInfoNwInfo, NwInfoRunner;

const
  cGpuSensorRefreshMs = 3000;
  cGpuSensorRetryMs = 30000;

var
  GStaticLoaded: Boolean;
  GStaticInfo: TGpuStaticInfo;
  GStaticLoadLock: TRTLCriticalSection;
  GStaticLoading: Boolean;
  GSensorsInfo: TGpuSensorInfo;
  GSensorsValid: Boolean;
  GSensorsHasData: Boolean;
  GSensorsLastTick: DWORD;
  GSensorsLock: TRTLCriticalSection;
  GSensorsLoading: Boolean;

function AppendLine(const ALines, ALine: string): string;
begin
  if ALine = '' then
    Result := ALines
  else if ALines = '' then
    Result := ALine
  else
    Result := ALines + sLineBreak + ALine;
end;

function GpuSensorHasData(const AInfo: TGpuSensorInfo): Boolean;
begin
  Result := AInfo.HasUtilization or AInfo.HasTemperature or AInfo.HasTotalMem or
    AInfo.HasMemUsage or AInfo.HasPower or AInfo.HasFrequency or AInfo.HasMemFrequency or
    AInfo.HasVoltage or AInfo.HasFanSpeed;
end;

function GpuSensorsTickElapsed(ANowTick, ALastTick: DWORD): Integer;
begin
  if ANowTick >= ALastTick then
    Result := ANowTick - ALastTick
  else
    Result := (High(DWORD) - ALastTick) + ANowTick + 1;
end;

procedure GpuMergeMissingFields(var ATarget, ANative: TGpuStaticInfo);
begin
  if ATarget.Device = '' then
    ATarget.Device := ANative.Device;
  if ATarget.Location = '' then
    ATarget.Location := ANative.Location;
  if ATarget.PnpId = '' then
    ATarget.PnpId := ANative.PnpId;
  if not ATarget.HasIntegrated and ANative.HasIntegrated then
  begin
    ATarget.HasIntegrated := True;
    ATarget.Integrated := ANative.Integrated;
  end;
  if ATarget.PcieLink = '' then
    ATarget.PcieLink := ANative.PcieLink;
end;

procedure GpuLoadStaticInfo;
var
  nwInfo, nativeInfo: TGpuStaticInfo;
  nwSensors: TGpuSensorInfo;
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
      nativeInfo := GpuNativeQueryStaticInfo;
      GpuInitStaticInfo(nwInfo);
      GpuInitSensorInfo(nwSensors);
      if GpuTryQueryStaticFromNwInfo(nwInfo, nwSensors) then
      begin
        GpuMergeMissingFields(nwInfo, nativeInfo);
        GStaticInfo := nwInfo;
        if GpuSensorHasData(nwSensors) then
        begin
          EnterCriticalSection(GSensorsLock);
          try
            GSensorsInfo := nwSensors;
            GSensorsHasData := True;
            GSensorsValid := True;
            GSensorsLastTick := GetTickCount;
          finally
            LeaveCriticalSection(GSensorsLock);
          end;
        end;
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

function GpuQueryStaticInfo: TGpuStaticInfo;
begin
  GpuLoadStaticInfo;
  EnterCriticalSection(GStaticLoadLock);
  try
    Result := GStaticInfo;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
end;

function GpuPeekStaticInfo(out ALoaded: Boolean): TGpuStaticInfo;
begin
  ALoaded := GStaticLoaded;
  if not ALoaded then
  begin
    GpuInitStaticInfo(Result);
    Exit;
  end;
  EnterCriticalSection(GStaticLoadLock);
  try
    Result := GStaticInfo;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
end;

procedure GpuRefreshSensorsIfStale;
var
  nowTick: DWORD;
  elapsed, retryMs: Integer;
  fresh: TGpuSensorInfo;
  hasData: Boolean;
begin
  nowTick := GetTickCount;
  EnterCriticalSection(GSensorsLock);
  try
    if GSensorsLoading then
      Exit;
    if GSensorsValid then
    begin
      elapsed := GpuSensorsTickElapsed(nowTick, GSensorsLastTick);
      if GSensorsHasData then
        retryMs := cGpuSensorRefreshMs
      else
        retryMs := cGpuSensorRetryMs;
      if elapsed < retryMs then
        Exit;
    end;
    GSensorsLoading := True;
  finally
    LeaveCriticalSection(GSensorsLock);
  end;

  GpuInitSensorInfo(fresh);
  hasData := False;
  if GpuTryQuerySensorsFromNwInfo(fresh) then
    hasData := GpuSensorHasData(fresh);

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

function GpuQuerySensorInfo: TGpuSensorInfo;
begin
  GpuRefreshSensorsIfStale;
  EnterCriticalSection(GSensorsLock);
  try
    Result := GSensorsInfo;
  finally
    LeaveCriticalSection(GSensorsLock);
  end;
end;

function GpuPeekSensorInfo: TGpuSensorInfo;
begin
  EnterCriticalSection(GSensorsLock);
  try
    Result := GSensorsInfo;
  finally
    LeaveCriticalSection(GSensorsLock);
  end;
end;

procedure GpuPreloadHintData;
begin
  GpuLoadStaticInfo;
  GpuRefreshSensorsIfStale;
end;

function GpuFormatTooltip(const AUsageText: string): string;
var
  info: TGpuStaticInfo;
  sensors: TGpuSensorInfo;
  deviceLine, usageText, nwExe, nwDir: string;
  staticLoaded: Boolean;
begin
  info := GpuPeekStaticInfo(staticLoaded);
  if not staticLoaded then
  begin
    if (AUsageText <> '') and (AUsageText <> cGpuDash) then
      usageText := AUsageText
    else
      usageText := cGpuDash;
    Exit('使用率：' + usageText + sLineBreak + '（详细信息加载中…）');
  end;
  sensors := GpuPeekSensorInfo;

  deviceLine := info.Device;
  if deviceLine = '' then
    deviceLine := cGpuDash;

  if (AUsageText <> '') and (AUsageText <> cGpuDash) then
    usageText := AUsageText
  else if sensors.HasUtilization then
    usageText := IntToStr(EnsureRange(Round(sensors.UtilizationPct), 0, 100)) + '%'
  else
    usageText := cGpuDash;

  Result := '型号：' + deviceLine;
  if info.Location <> '' then
    Result := AppendLine(Result, '位置：' + info.Location);
  if info.PcieLink <> '' then
    Result := AppendLine(Result, 'PCIe：' + info.PcieLink);
  if info.HasIntegrated and info.Integrated then
    Result := AppendLine(Result, '集成显卡：是');
  Result := AppendLine(Result, '显存：' + GpuFormatMemoryText(sensors));
  Result := AppendLine(Result, '温度：' + GpuFormatTemperatureText(sensors));
  Result := AppendLine(Result, '功耗：' + GpuFormatPowerText(sensors));
  Result := AppendLine(Result, '核心频率：' + GpuFormatFrequencyText(sensors.HasFrequency, sensors.FrequencyMhz));
  Result := AppendLine(Result, '显存频率：' + GpuFormatFrequencyText(sensors.HasMemFrequency, sensors.MemFrequencyMhz));
  Result := AppendLine(Result, '电压：' + GpuFormatVoltageText(sensors));
  Result := AppendLine(Result, '风扇：' + GpuFormatFanSpeedText(sensors));
  Result := AppendLine(Result, '使用率：' + usageText);

  if (info.Device = '') and not NwInfoResolveExe(nwExe, nwDir) then
    Result := AppendLine(Result, string('（未找到 NwInfo\nwinfox86.exe，请运行 scripts\copy_nwinfo_runtime.ps1）'));
end;

initialization
  InitializeCriticalSection(GStaticLoadLock);
  InitializeCriticalSection(GSensorsLock);
  GpuInitStaticInfo(GStaticInfo);
  GpuInitSensorInfo(GSensorsInfo);

finalization
  DeleteCriticalSection(GSensorsLock);
  DeleteCriticalSection(GStaticLoadLock);

end.
