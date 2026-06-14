unit GpuInfo;

{
  GPU 悬停提示：静态信息由 GpuInfoNative（EnumDisplayDevicesW）提供；
  传感器按 TTL 缓存刷新（HardwarePdh 利用率 + D3DKMT 显存 + ADL2/NVML 驱动传感器，无 COM）。
}

interface

uses
  SysUtils, Windows;

const
  cGpuDash = '--';

type
  TGpuStaticInfo = record
    Device: string;
    Location: string;
    PnpId: string;
    VendorName: string;
    DriverVersion: string;
    HasIntegrated: Boolean;
    Integrated: Boolean;
    PcieLink: string;
  end;

  TGpuSensorInfo = record
    HasUtilization: Boolean;
    UtilizationPct: Double;
    HasTemperature: Boolean;
    TemperatureC: Double;
    HasTotalMem: Boolean;
    TotalMemBytes: UInt64;
    HasFreeMem: Boolean;
    FreeMemBytes: UInt64;
    HasMemUsage: Boolean;
    MemUsagePct: Integer;
    HasPower: Boolean;
    PowerW: Double;
    HasFrequency: Boolean;
    FrequencyMhz: Double;
    HasMemFrequency: Boolean;
    MemFrequencyMhz: Double;
    HasVoltage: Boolean;
    VoltageV: Double;
    HasFanSpeed: Boolean;
    FanSpeedRpm: Integer;
  end;

procedure GpuInitStaticInfo(out AInfo: TGpuStaticInfo);
procedure GpuInitSensorInfo(out AInfo: TGpuSensorInfo);
function GpuFormatTemperatureText(const AInfo: TGpuSensorInfo): string;
function GpuFormatPowerText(const AInfo: TGpuSensorInfo): string;
function GpuFormatFrequencyText(const AHas: Boolean; const AMhz: Double): string;
function GpuFormatVoltageText(const AInfo: TGpuSensorInfo): string;
function GpuFormatFanSpeedText(const AInfo: TGpuSensorInfo): string;
function GpuFormatMemoryText(const AInfo: TGpuSensorInfo): string;

procedure GpuPreloadHintData;
procedure GpuPreloadSensors;
function GpuPeekStaticInfo(out ALoaded: Boolean): TGpuStaticInfo;
function GpuFormatTooltip(const AUsageText: string): string;

implementation

uses
  Math, GpuInfoNative, GpuInfoVendor, MemInfo;

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

procedure GpuLoadStaticInfo;
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
      GStaticInfo := GpuNativeQueryStaticInfo;
      GStaticLoaded := True;
    finally
      GStaticLoading := False;
    end;
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

  fresh := GpuNativeQuerySensors;
  GpuVendorApplySensors(fresh);
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
end;

procedure GpuPreloadSensors;
begin
  GpuRefreshSensorsIfStale;
end;

function GpuFormatTooltip(const AUsageText: string): string;
var
  info: TGpuStaticInfo;
  sensors: TGpuSensorInfo;
  deviceLine, usageText: string;
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

  if info.VendorName <> '' then
    Result := '厂商：' + info.VendorName
  else
    Result := '';
  Result := AppendLine(Result, '型号：' + deviceLine);
  if info.DriverVersion <> '' then
    Result := AppendLine(Result, '驱动：' + info.DriverVersion);
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
end;

procedure GpuInitStaticInfo(out AInfo: TGpuStaticInfo);
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
end;

procedure GpuInitSensorInfo(out AInfo: TGpuSensorInfo);
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
end;

function GpuFormatTemperatureText(const AInfo: TGpuSensorInfo): string;
begin
  if not AInfo.HasTemperature then
    Result := cGpuDash
  else
    Result := IntToStr(Round(AInfo.TemperatureC)) + '°C';
end;

function GpuFormatPowerText(const AInfo: TGpuSensorInfo): string;
begin
  if not AInfo.HasPower then
    Result := cGpuDash
  else
    Result := StringReplace(Format('%.0f', [AInfo.PowerW]), ',', '.', [rfReplaceAll]) + ' W';
end;

function GpuFormatFrequencyText(const AHas: Boolean; const AMhz: Double): string;
begin
  if not AHas then
    Result := cGpuDash
  else
    Result := IntToStr(Round(AMhz)) + ' MHz';
end;

function GpuFormatVoltageText(const AInfo: TGpuSensorInfo): string;
begin
  if not AInfo.HasVoltage then
    Result := cGpuDash
  else
    Result := StringReplace(Format('%.2f', [AInfo.VoltageV]), ',', '.', [rfReplaceAll]) + ' V';
end;

function GpuFormatFanSpeedText(const AInfo: TGpuSensorInfo): string;
begin
  if not AInfo.HasFanSpeed then
    Result := cGpuDash
  else
    Result := IntToStr(AInfo.FanSpeedRpm) + ' RPM';
end;

function GpuFormatMemoryText(const AInfo: TGpuSensorInfo): string;
var
  usedBytes: UInt64;
  pctText: string;
begin
  if AInfo.HasTotalMem and AInfo.HasFreeMem then
  begin
    if AInfo.FreeMemBytes > AInfo.TotalMemBytes then
      usedBytes := AInfo.TotalMemBytes
    else
      usedBytes := AInfo.TotalMemBytes - AInfo.FreeMemBytes;
    if AInfo.HasMemUsage then
      pctText := ' (' + IntToStr(AInfo.MemUsagePct) + '%)'
    else
      pctText := '';
    Result := MemFormatBytes(usedBytes) + ' / ' + MemFormatBytes(AInfo.TotalMemBytes) + pctText;
  end
  else if AInfo.HasTotalMem then
    Result := MemFormatBytes(AInfo.TotalMemBytes)
  else if AInfo.HasMemUsage then
    Result := IntToStr(AInfo.MemUsagePct) + '%'
  else
    Result := cGpuDash;
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
