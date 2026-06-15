unit CpuInfo;

{
  CPU 悬停提示：静态信息由 CpuInfoNative（CPUID + NT API）提供；
  温度/功耗由 CpuInfoSensors（PawnIO MSR RAPL）按 TTL 缓存刷新；PawnIO 无温度时回退 HardwarePdh（ACPI 热区）。
  当前频率由 Native 实时采样。
}

interface

uses
  SysUtils, Classes, Windows;

const
  cCpuDash = '--';

type
  TCpuStaticInfo = record
    Brand: string;
    Vendor: string;
    Stepping: Integer;
    Virtualization: string;
    PhysicalCores: Integer;
    LogicalProcessors: Integer;
    BaseSpeedMhz: DWORD;
    CurrentSpeedMhz: DWORD;
    L1CacheBytes: DWORD;
    L2CacheBytes: DWORD;
    L3CacheBytes: DWORD;
    Instructions: string;
  end;

  TCpuSensorInfo = record
    HasCoreTemp: Boolean;
    CoreTempC: Double;
    HasPackageTemp: Boolean;
    PackageTempC: Double;
    HasPower: Boolean;
    PowerW: Double;
    HasVoltage: Boolean;
    VoltageV: Double;
    HasFanSpeed: Boolean;
    FanSpeedRpm: Integer;
  end;

procedure CpuInitSensorInfo(out AInfo: TCpuSensorInfo);
function CpuFormatSensorTemperatureText(const AInfo: TCpuSensorInfo): string;
function CpuFormatSensorPowerText(const AInfo: TCpuSensorInfo): string;
function CpuFormatSensorVoltageText(const AInfo: TCpuSensorInfo): string;
function CpuFormatSensorFanSpeedText(const AInfo: TCpuSensorInfo): string;

function CpuQueryStaticInfo: TCpuStaticInfo;
function CpuPeekStaticInfo(out ALoaded: Boolean): TCpuStaticInfo;
procedure CpuPreloadHintData;
procedure CpuPreloadSensors;
function CpuFormatTooltip(const AUsageText: string): string;

implementation

uses
  AppPaths, CpuInfoNative, CpuInfoSensors, CpuInfoFan, HardwarePdh;

const
  cCpuSensorRefreshMs = 3000;
  cCpuSensorRetryMs = 30000;
  cCpuPowerRetryMs = 1000;
  cCpuInstrPerLine = 5;
  cCpuTooltipSvgPrefix = '#svg:';

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
  Result := AInfo.HasCoreTemp or AInfo.HasPackageTemp or AInfo.HasPower or
    AInfo.HasVoltage or AInfo.HasFanSpeed;
end;

function CpuSensorsTickElapsed(ANowTick, ALastTick: DWORD): Integer;
begin
  if ANowTick >= ALastTick then
    Result := ANowTick - ALastTick
  else
    Result := (High(DWORD) - ALastTick) + ANowTick + 1;
end;

procedure CpuRefreshSensorsIfStale(AForce: Boolean = False);
var
  nowTick: DWORD;
  elapsed, retryMs: Integer;
  fresh: TCpuSensorInfo;
  hasData: Boolean;
  tempC: Double;
begin
  nowTick := GetTickCount;
  EnterCriticalSection(GSensorsLock);
  try
    if GSensorsLoading then
      Exit;
    if GSensorsValid and not AForce then
    begin
      elapsed := CpuSensorsTickElapsed(nowTick, GSensorsLastTick);
      if GSensorsHasData then
      begin
        if GSensorsInfo.HasPower then
          retryMs := cCpuSensorRefreshMs
        else
          retryMs := cCpuPowerRetryMs;
      end
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
  CpuSensorsQuery(fresh);
  if not fresh.HasCoreTemp and not fresh.HasPackageTemp then
  begin
    tempC := HardwarePdhSampleCpuPackageTempC;
    if tempC >= 0 then
    begin
      fresh.HasPackageTemp := True;
      fresh.PackageTempC := tempC;
    end;
  end;
  if CpuFanQueryRpm(fresh.FanSpeedRpm) then
    fresh.HasFanSpeed := True;
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

procedure CpuLoadStaticInfo;
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
      GStaticInfo := CpuNativeQueryStaticInfo;
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
end;

procedure CpuPreloadSensors;
const
  cCpuRaplWarmupMs = 250;
  cCpuSpeedPrimeGapMs = 700;
begin
  CpuRefreshSensorsIfStale;
  CpuNativeQueryCurrentSpeedMhz;
  Sleep(cCpuRaplWarmupMs);
  CpuRefreshSensorsIfStale(True);
  Sleep(cCpuSpeedPrimeGapMs);
  CpuNativeQueryCurrentSpeedMhz;
end;

function CpuQueryStaticInfo: TCpuStaticInfo;
begin
  CpuLoadStaticInfo;
  EnterCriticalSection(GStaticLoadLock);
  try
    Result := GStaticInfo;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
  Result.CurrentSpeedMhz := CpuNativeQueryCurrentSpeedMhz;
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

procedure CpuSplitInstructionTokens(const AInstructions: string; ATokens: TStrings);
var
  s, token: string;
  sepPos: Integer;
begin
  ATokens.Clear;
  s := Trim(AInstructions);
  if s = '' then
    Exit;
  while s <> '' do
  begin
    sepPos := Pos(', ', s);
    if sepPos > 0 then
    begin
      token := Trim(Copy(s, 1, sepPos - 1));
      Delete(s, 1, sepPos + 1);
    end
    else
    begin
      token := Trim(s);
      s := '';
    end;
    if token <> '' then
      ATokens.Add(token);
  end;
end;

function CpuVendorSvgRelPath(const AVendor: string): string;
begin
  Result := '';
  if SameText(AVendor, 'Intel') or SameText(AVendor, 'GenuineIntel') then
    Result := 'Resource\CpuVendor\intel.svg'
  else if SameText(AVendor, 'AMD') or SameText(AVendor, 'AuthenticAMD') then
    Result := 'Resource\CpuVendor\amd.svg'
  else if SameText(AVendor, 'Apple') then
    Result := 'Resource\CpuVendor\apple.svg'
  else if SameText(AVendor, 'Qualcomm') then
    Result := 'Resource\CpuVendor\qualcomm.svg';
end;

function CpuVendorTooltipSize(const AVendor: string): string;
begin
  if SameText(AVendor, 'Intel') or SameText(AVendor, 'GenuineIntel') then
    Result := '@96x38'
  else if SameText(AVendor, 'AMD') or SameText(AVendor, 'AuthenticAMD') then
    Result := '@72x38'
  else if SameText(AVendor, 'Apple') then
    Result := '@64x38'
  else if SameText(AVendor, 'Qualcomm') then
    Result := '@88x38'
  else
    Result := '';
end;

function CpuVendorTooltipValue(const AVendor: string): string;
var
  svgPath: string;
begin
  svgPath := CpuVendorSvgRelPath(AVendor);
  if (svgPath <> '') and FileExists(AppExeDirectory + svgPath) then
    Result := cCpuTooltipSvgPrefix + svgPath + CpuVendorTooltipSize(AVendor)
  else if AVendor <> '' then
    Result := AVendor
  else
    Result := cCpuDash;
end;

function CpuFormatInstructionsLines(const AInstructions: string): string;
var
  tokens: TStringList;
  i, tokenCount: Integer;
  line: string;
begin
  if (AInstructions = '') or (AInstructions = cCpuDash) then
    Exit('指令集：' + cCpuDash + sLineBreak);
  tokens := TStringList.Create;
  try
    CpuSplitInstructionTokens(AInstructions, tokens);
    tokenCount := tokens.Count;
    if tokenCount = 0 then
      Exit('指令集：' + cCpuDash + sLineBreak);
    line := '';
    for i := 0 to tokenCount - 1 do
    begin
      if (i mod cCpuInstrPerLine) = 0 then
      begin
        if line <> '' then
        begin
          if Result <> '' then
            Result := Result + sLineBreak;
          Result := Result + line;
        end;
        if i = 0 then
          line := '指令集：' + tokens[i]
        else
          line := tokens[i];
      end
      else
        line := line + ', ' + tokens[i];
    end;
    if line <> '' then
    begin
      if Result <> '' then
        Result := Result + sLineBreak;
      Result := Result + line;
    end;
    if Result <> '' then
      Result := Result + sLineBreak;
  finally
    tokens.Free;
  end;
end;

function CpuFormatTooltip(const AUsageText: string): string;
var
  info: TCpuStaticInfo;
  sensors: TCpuSensorInfo;
  vendorLine, brandLine, usageText, coreThreadText, steppingLine, virtLine: string;
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
  info.CurrentSpeedMhz := CpuNativeQueryCurrentSpeedMhz;
  sensors := CpuQuerySensorInfo;

  vendorLine := CpuVendorTooltipValue(info.Vendor);
  brandLine := info.Brand;
  if brandLine = '' then
    brandLine := cCpuDash;
  coreThreadText := CpuFormatCoreThreadText(info.PhysicalCores, info.LogicalProcessors);
  if info.Stepping >= 0 then
    steppingLine := IntToStr(info.Stepping)
  else
    steppingLine := cCpuDash;
  virtLine := info.Virtualization;
  if virtLine = '' then
    virtLine := cCpuDash;

  if (AUsageText <> '') and (AUsageText <> cCpuDash) then
    usageText := AUsageText
  else
    usageText := cCpuDash;

  Result := '厂商：' + vendorLine + sLineBreak +
    '型号：' + brandLine + sLineBreak +
    '步进：' + steppingLine + sLineBreak +
    '虚拟化：' + virtLine + sLineBreak +
    '规格：' + coreThreadText + sLineBreak +
    CpuFormatInstructionsLines(info.Instructions) +
    'L1缓存：' + CpuFormatCacheSizeText(info.L1CacheBytes) + sLineBreak +
    'L2缓存：' + CpuFormatCacheSizeText(info.L2CacheBytes) + sLineBreak +
    'L3缓存：' + CpuFormatCacheSizeText(info.L3CacheBytes) + sLineBreak +
    '基准速度：' + CpuFormatSpeedMhz(info.BaseSpeedMhz) + sLineBreak +
    '速度：' + CpuFormatSpeedMhz(info.CurrentSpeedMhz) + sLineBreak +
    '温度：' + CpuFormatSensorTemperatureText(sensors) + sLineBreak +
    '功耗：' + CpuFormatSensorPowerText(sensors) + sLineBreak +
    '电压：' + CpuFormatSensorVoltageText(sensors) + sLineBreak +
    '风扇：' + CpuFormatSensorFanSpeedText(sensors) + sLineBreak +
    '使用率：' + usageText;
end;

procedure CpuInitSensorInfo(out AInfo: TCpuSensorInfo);
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
end;

function CpuFormatSensorTemperatureText(const AInfo: TCpuSensorInfo): string;
var
  tempC: Double;
begin
  if AInfo.HasPackageTemp then
    tempC := AInfo.PackageTempC
  else if AInfo.HasCoreTemp then
    tempC := AInfo.CoreTempC
  else
  begin
    Result := cCpuDash;
    Exit;
  end;
  Result := IntToStr(Round(tempC)) + '°C';
end;

function CpuFormatSensorPowerText(const AInfo: TCpuSensorInfo): string;
begin
  if not AInfo.HasPower then
    Result := cCpuDash
  else
    Result := StringReplace(Format('%.0f', [AInfo.PowerW]), ',', '.', [rfReplaceAll]) + ' W';
end;

function CpuFormatSensorVoltageText(const AInfo: TCpuSensorInfo): string;
begin
  if not AInfo.HasVoltage then
    Result := cCpuDash
  else
    Result := StringReplace(Format('%.2f', [AInfo.VoltageV]), ',', '.', [rfReplaceAll]) + ' V';
end;

function CpuFormatSensorFanSpeedText(const AInfo: TCpuSensorInfo): string;
begin
  if not AInfo.HasFanSpeed then
    Result := cCpuDash
  else
    Result := IntToStr(AInfo.FanSpeedRpm) + ' RPM';
end;

initialization
  InitializeCriticalSection(GStaticLoadLock);
  InitializeCriticalSection(GSensorsLock);
  FillChar(GStaticInfo, SizeOf(GStaticInfo), 0);
  CpuInitSensorInfo(GSensorsInfo);

finalization
  DeleteCriticalSection(GSensorsLock);
  DeleteCriticalSection(GStaticLoadLock);

end.
