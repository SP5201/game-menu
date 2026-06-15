unit GpuInfoVendor;

{
  GPU 传感器：经显卡驱动 DLL 读取（AMD ADL2 / NVIDIA NVML），不读注册表/WMI。
}

interface

uses
  GpuInfo;

function GpuVendorApplySensors(var AInfo: TGpuSensorInfo): Boolean;

implementation

uses
  Windows, SysUtils, Math;

const
  ADL_OK = 0;
  ADL_MAX_PATH = 256;
  ADL_PMLOG_MAX_SENSORS = 256;
  ADL_DL_FANCTRL_SPEED_TYPE_RPM = 2;
  ADL_ODN_TEMP_EDGE = 1;
  ADL_ODN_POWER_TOTAL = 0;
  ADL_PMLOG_CLK_GFXCLK = 1;
  ADL_PMLOG_CLK_MEMCLK = 2;
  ADL_PMLOG_TEMPERATURE_EDGE = 8;
  ADL_PMLOG_FAN_RPM = 14;
  ADL_PMLOG_FAN_PERCENTAGE = 15;
  ADL_PMLOG_GFX_VOLTAGE = 21;
  ADL_PMLOG_ASIC_POWER = 23;
  ADL_PMLOG_BOARD_POWER = 73;
  NVML_SUCCESS = 0;
  NVML_TEMPERATURE_GPU = 0;
  NVML_CLOCK_GRAPHICS = 0;
  NVML_CLOCK_MEM = 2;
  AMD_VENDOR_ID = 1002;

type
  TADLContext = Pointer;
  TADLODNPerformanceStatus = record
    iCoreClock: Integer;
    iMemoryClock: Integer;
    iDCEFClock: Integer;
    iGFXClock: Integer;
    iUVDClock: Integer;
    iVCEClock: Integer;
    iGPUActivityPercent: Integer;
    iCurrentCorePerformanceLevel: Integer;
    iCurrentMemoryPerformanceLevel: Integer;
    iCurrentDCEFPerformanceLevel: Integer;
    iCurrentGFXPerformanceLevel: Integer;
    iUVDPerformanceLevel: Integer;
    iVCEPerformanceLevel: Integer;
    iCurrentBusSpeed: Integer;
    iCurrentBusLanes: Integer;
    iMaximumBusLanes: Integer;
    iVDDC: Integer;
    iVDDCI: Integer;
  end;
  TADLTemperature = record
    iSize: Integer;
    iTemperature: Integer;
  end;
  TADLFanSpeedValue = record
    iSize: Integer;
    iSpeedType: Integer;
    iFanSpeed: Integer;
    iFlags: Integer;
  end;
  TADLPMActivity = record
    iSize: Integer;
    iEngineClock: Integer;
    iMemoryClock: Integer;
    iVddc: Integer;
    iActivityPercent: Integer;
    iCurrentPerformanceLevel: Integer;
    iCurrentBusSpeed: Integer;
    iCurrentBusLanes: Integer;
    iMaximumBusLanes: Integer;
    iReserved: Integer;
  end;
  TADLSingleSensorData = record
    supported: Integer;
    value: Integer;
  end;
  TADLPMLogDataOutput = record
    size: Integer;
    sensors: array[0..ADL_PMLOG_MAX_SENSORS - 1] of TADLSingleSensorData;
  end;
  TADLMemoryInfoX2 = record
    iSize: Integer;
    iMemoryBusWidth: Int64;
    iMemorySize: Int64;
    iHyperMemorySize: Int64;
    iVisibleMemorySize: Int64;
    iInvisibleMemorySize: Int64;
    iVisibleMemorySizeInMB: Int64;
    iInvisibleMemorySizeInMB: Int64;
  end;
  TADLAdapterInfo = record
    iSize: Integer;
    iAdapterIndex: Integer;
    strUDID: array[0..ADL_MAX_PATH - 1] of AnsiChar;
    iBusNumber: Integer;
    iDeviceNumber: Integer;
    iFunctionNumber: Integer;
    iVendorID: Integer;
    strAdapterName: array[0..ADL_MAX_PATH - 1] of AnsiChar;
    strDisplayName: array[0..ADL_MAX_PATH - 1] of AnsiChar;
    iPresent: Integer;
    iExist: Integer;
    strDriverPath: array[0..ADL_MAX_PATH - 1] of AnsiChar;
    strDriverPathExt: array[0..ADL_MAX_PATH - 1] of AnsiChar;
    strPNPString: array[0..ADL_MAX_PATH - 1] of AnsiChar;
    iOSDisplayIndex: Integer;
  end;
  TNvmlDevice = Pointer;
  TNvmlReturn = Integer;
  TADLMainMemoryAlloc = function(size: Integer): Pointer; cdecl;
  TADL2MainControlCreate = function(callback: TADLMainMemoryAlloc; connectedAdapters: Integer;
    var context: TADLContext): Integer; cdecl;
  TADL2MainControlDestroy = function(context: TADLContext): Integer; cdecl;
  TADL2AdapterNumberOfAdaptersGet = function(context: TADLContext; var numAdapters: Integer): Integer; cdecl;
  TADL2AdapterAdapterInfoGet = function(context: TADLContext; info: Pointer; size: Integer): Integer; cdecl;
  TADL2OverdriveNTemperatureGet = function(context: TADLContext; adapterIndex, tempType: Integer;
    var temperature: Integer): Integer; cdecl;
  TADL2OverdriveNPerformanceStatusGet = function(context: TADLContext; adapterIndex: Integer;
    out perfStatus: TADLODNPerformanceStatus): Integer; cdecl;
  TADL2Overdrive6CurrentPowerGet = function(context: TADLContext; adapterIndex, powerType: Integer;
    var currentValue: Integer): Integer; cdecl;
  TADL2Overdrive5TemperatureGet = function(context: TADLContext; adapterIndex, thermalIndex: Integer;
    var temperature: TADLTemperature): Integer; cdecl;
  TADL2Overdrive5FanSpeedGet = function(context: TADLContext; adapterIndex, thermalIndex: Integer;
    var fanSpeed: TADLFanSpeedValue): Integer; cdecl;
  TADL2Overdrive5CurrentActivityGet = function(context: TADLContext; adapterIndex: Integer;
    var activity: TADLPMActivity): Integer; cdecl;
  TADL2NewQueryPMLogDataGet = function(context: TADLContext; adapterIndex: Integer;
    var logOutput: TADLPMLogDataOutput): Integer; cdecl;
  TADL2AdapterMemoryInfoX2Get = function(context: TADLContext; adapterIndex: Integer;
    var memoryInfo: TADLMemoryInfoX2): Integer; cdecl;
  TADL2AdapterDedicatedVRAMUsageGet = function(context: TADLContext; adapterIndex: Integer;
    var vramUsageMb: Integer): Integer; cdecl;
  TNvmlInit = function: TNvmlReturn; cdecl;
  TNvmlShutdown = function: TNvmlReturn; cdecl;
  TNvmlDeviceGetCount = function(var deviceCount: Cardinal): TNvmlReturn; cdecl;
  TNvmlDeviceGetHandleByIndex = function(index: Cardinal; out device: TNvmlDevice): TNvmlReturn; cdecl;
  TNvmlDeviceGetTemperature = function(device: TNvmlDevice; sensorType: Integer;
    var temp: Cardinal): TNvmlReturn; cdecl;
  TNvmlDeviceGetPowerUsage = function(device: TNvmlDevice; var powerMw: Cardinal): TNvmlReturn; cdecl;
  TNvmlDeviceGetClockInfo = function(device: TNvmlDevice; clockType: Integer;
    var clockMhz: Cardinal): TNvmlReturn; cdecl;
  TNvmlDeviceGetFanSpeed = function(device: TNvmlDevice; var speed: Cardinal): TNvmlReturn; cdecl;
  TNvmlMemory = record
    total: UInt64;
    free: UInt64;
    used: UInt64;
  end;
  TNvmlDeviceGetMemoryInfo = function(device: TNvmlDevice; var memory: TNvmlMemory): TNvmlReturn; cdecl;

var
  GAmdModule: HMODULE;
  GAmdContext: TADLContext;
  GAmdAdapterIndex: Integer;
  GAmdInitFailed: Boolean;
  GAmdFnsReady: Boolean;
  GAmdMainControlCreate: TADL2MainControlCreate;
  GAmdMainControlDestroy: TADL2MainControlDestroy;
  GAmdAdapterNumberOfAdaptersGet: TADL2AdapterNumberOfAdaptersGet;
  GAmdAdapterAdapterInfoGet: TADL2AdapterAdapterInfoGet;
  GAmdOverdriveNTemperatureGet: TADL2OverdriveNTemperatureGet;
  GAmdOverdriveNPerformanceStatusGet: TADL2OverdriveNPerformanceStatusGet;
  GAmdOverdrive6CurrentPowerGet: TADL2Overdrive6CurrentPowerGet;
  GAmdOverdrive5TemperatureGet: TADL2Overdrive5TemperatureGet;
  GAmdOverdrive5FanSpeedGet: TADL2Overdrive5FanSpeedGet;
  GAmdOverdrive5CurrentActivityGet: TADL2Overdrive5CurrentActivityGet;
  GAmdNewQueryPMLogDataGet: TADL2NewQueryPMLogDataGet;
  GAmdAdapterMemoryInfoX2Get: TADL2AdapterMemoryInfoX2Get;
  GAmdAdapterDedicatedVRAMUsageGet: TADL2AdapterDedicatedVRAMUsageGet;
  GNvmlModule: HMODULE;
  GNvmlInitFailed: Boolean;
  GNvmlFnsReady: Boolean;
  GNvmlInit: TNvmlInit;
  GNvmlShutdown: TNvmlShutdown;
  GNvmlDeviceGetCount: TNvmlDeviceGetCount;
  GNvmlDeviceGetHandleByIndex: TNvmlDeviceGetHandleByIndex;
  GNvmlDeviceGetTemperature: TNvmlDeviceGetTemperature;
  GNvmlDeviceGetPowerUsage: TNvmlDeviceGetPowerUsage;
  GNvmlDeviceGetClockInfo: TNvmlDeviceGetClockInfo;
  GNvmlDeviceGetFanSpeed: TNvmlDeviceGetFanSpeed;
  GNvmlDeviceGetMemoryInfo: TNvmlDeviceGetMemoryInfo;

function AdlMainMemoryAlloc(size: Integer): Pointer; cdecl;
begin
  Result := AllocMem(size);
end;

function GpuVendorLoadProc(const AModule: HMODULE; const AName: AnsiString): Pointer;
begin
  Result := GetProcAddress(AModule, PAnsiChar(AName));
end;

function GpuVendorIsPlausibleTempC(const AValue: Double): Boolean;
begin
  Result := (not IsNan(AValue)) and (not IsInfinite(AValue)) and (AValue >= -40) and (AValue <= 150);
end;

function GpuVendorIsPlausiblePowerW(const AValue: Double): Boolean;
begin
  Result := (not IsNan(AValue)) and (not IsInfinite(AValue)) and (AValue >= 0) and (AValue <= 1000);
end;

function GpuVendorIsPlausibleClockMhz(const AValue: Double): Boolean;
begin
  Result := (not IsNan(AValue)) and (not IsInfinite(AValue)) and (AValue > 0) and (AValue <= 5000);
end;

function GpuVendorIsPlausibleVoltageV(const AValue: Double): Boolean;
begin
  Result := (not IsNan(AValue)) and (not IsInfinite(AValue)) and (AValue > 0) and (AValue <= 2.5);
end;

function GpuVendorIsPlausibleFanRpm(const AValue: Integer): Boolean;
begin
  Result := (AValue >= 0) and (AValue <= 10000);
end;

function GpuVendorNormalizeClockMhz(const ARaw: Integer): Double;
begin
  if ARaw <= 0 then
    Exit(0);
  if ARaw > 10000 then
    Result := ARaw * 0.01
  else
    Result := ARaw;
end;

procedure GpuVendorSetTemp(var AInfo: TGpuSensorInfo; const AValue: Double);
begin
  if not GpuVendorIsPlausibleTempC(AValue) then
    Exit;
  AInfo.HasTemperature := True;
  AInfo.TemperatureC := AValue;
end;

procedure GpuVendorSetPower(var AInfo: TGpuSensorInfo; const AValue: Double);
begin
  if not GpuVendorIsPlausiblePowerW(AValue) then
    Exit;
  AInfo.HasPower := True;
  AInfo.PowerW := AValue;
end;

procedure GpuVendorSetCoreClock(var AInfo: TGpuSensorInfo; const AValue: Double);
begin
  if not GpuVendorIsPlausibleClockMhz(AValue) then
    Exit;
  AInfo.HasFrequency := True;
  AInfo.FrequencyMhz := AValue;
end;

procedure GpuVendorSetMemClock(var AInfo: TGpuSensorInfo; const AValue: Double);
begin
  if not GpuVendorIsPlausibleClockMhz(AValue) then
    Exit;
  AInfo.HasMemFrequency := True;
  AInfo.MemFrequencyMhz := AValue;
end;

procedure GpuVendorSetVoltage(var AInfo: TGpuSensorInfo; const AValue: Double);
begin
  if not GpuVendorIsPlausibleVoltageV(AValue) then
    Exit;
  AInfo.HasVoltage := True;
  AInfo.VoltageV := AValue;
end;

procedure GpuVendorSetFan(var AInfo: TGpuSensorInfo; const ARpm: Integer);
begin
  if not GpuVendorIsPlausibleFanRpm(ARpm) then
    Exit;
  AInfo.HasFanSpeed := True;
  AInfo.FanSpeedRpm := ARpm;
end;

procedure GpuVendorApplyMemUsage(var AInfo: TGpuSensorInfo; const ATotalBytes, AUsedBytes: UInt64);
var
  freeBytes, usedBytes: UInt64;
  usagePct: Integer;
begin
  if ATotalBytes = 0 then
    Exit;
  if AUsedBytes > ATotalBytes then
    usedBytes := ATotalBytes
  else
    usedBytes := AUsedBytes;
  freeBytes := ATotalBytes - usedBytes;
  AInfo.HasTotalMem := True;
  AInfo.TotalMemBytes := ATotalBytes;
  AInfo.HasFreeMem := True;
  AInfo.FreeMemBytes := freeBytes;
  usagePct := Round((usedBytes * 100) / ATotalBytes);
  if usagePct < 0 then
    usagePct := 0
  else if usagePct > 100 then
    usagePct := 100;
  AInfo.HasMemUsage := True;
  AInfo.MemUsagePct := usagePct;
end;

function GpuVendorAmdLoadLibrary: Boolean;
begin
  if GAmdModule <> 0 then
    Exit(True);
  GAmdModule := LoadLibrary('atiadlxx.dll');
  if GAmdModule = 0 then
    GAmdModule := LoadLibrary('atiadlxy.dll');
  Result := GAmdModule <> 0;
end;

function GpuVendorAmdLoadFunctions: Boolean;
begin
  if GAmdFnsReady then
    Exit(True);
  if not GpuVendorAmdLoadLibrary then
    Exit(False);
  GAmdMainControlCreate := GpuVendorLoadProc(GAmdModule, 'ADL2_Main_Control_Create');
  GAmdMainControlDestroy := GpuVendorLoadProc(GAmdModule, 'ADL2_Main_Control_Destroy');
  GAmdAdapterNumberOfAdaptersGet := GpuVendorLoadProc(GAmdModule, 'ADL2_Adapter_NumberOfAdapters_Get');
  GAmdAdapterAdapterInfoGet := GpuVendorLoadProc(GAmdModule, 'ADL2_Adapter_AdapterInfo_Get');
  GAmdOverdriveNTemperatureGet := GpuVendorLoadProc(GAmdModule, 'ADL2_OverdriveN_Temperature_Get');
  GAmdOverdriveNPerformanceStatusGet := GpuVendorLoadProc(GAmdModule, 'ADL2_OverdriveN_PerformanceStatus_Get');
  GAmdOverdrive6CurrentPowerGet := GpuVendorLoadProc(GAmdModule, 'ADL2_Overdrive6_CurrentPower_Get');
  GAmdOverdrive5TemperatureGet := GpuVendorLoadProc(GAmdModule, 'ADL2_Overdrive5_Temperature_Get');
  GAmdOverdrive5FanSpeedGet := GpuVendorLoadProc(GAmdModule, 'ADL2_Overdrive5_FanSpeed_Get');
  GAmdOverdrive5CurrentActivityGet := GpuVendorLoadProc(GAmdModule, 'ADL2_Overdrive5_CurrentActivity_Get');
  GAmdNewQueryPMLogDataGet := GpuVendorLoadProc(GAmdModule, 'ADL2_New_QueryPMLogData_Get');
  GAmdAdapterMemoryInfoX2Get := GpuVendorLoadProc(GAmdModule, 'ADL2_Adapter_MemoryInfoX2_Get');
  GAmdAdapterDedicatedVRAMUsageGet := GpuVendorLoadProc(GAmdModule,
    'ADL2_Adapter_DedicatedVRAMUsage_Get');
  GAmdFnsReady := Assigned(GAmdMainControlCreate) and Assigned(GAmdMainControlDestroy) and
    Assigned(GAmdAdapterNumberOfAdaptersGet) and Assigned(GAmdAdapterAdapterInfoGet);
  Result := GAmdFnsReady;
end;

function GpuVendorAmdEnsureContext: Boolean;
var
  numAdapters, bufSize, i: Integer;
  adapters: array of TADLAdapterInfo;
begin
  Result := False;
  if GAmdInitFailed then
    Exit;
  if GAmdContext <> nil then
    Exit(GAmdAdapterIndex >= 0);
  if not GpuVendorAmdLoadFunctions then
  begin
    GAmdInitFailed := True;
    Exit;
  end;
  if GAmdMainControlCreate(AdlMainMemoryAlloc, 1, GAmdContext) <> ADL_OK then
  begin
    GAmdInitFailed := True;
    Exit;
  end;
  numAdapters := 0;
  if GAmdAdapterNumberOfAdaptersGet(GAmdContext, numAdapters) <> ADL_OK then
  begin
    GAmdMainControlDestroy(GAmdContext);
    GAmdContext := nil;
    GAmdInitFailed := True;
    Exit;
  end;
  if numAdapters <= 0 then
  begin
    GAmdMainControlDestroy(GAmdContext);
    GAmdContext := nil;
    GAmdInitFailed := True;
    Exit;
  end;
  SetLength(adapters, numAdapters);
  FillChar(adapters[0], SizeOf(TADLAdapterInfo) * numAdapters, 0);
  for i := 0 to numAdapters - 1 do
    adapters[i].iSize := SizeOf(TADLAdapterInfo);
  bufSize := SizeOf(TADLAdapterInfo) * numAdapters;
  if GAmdAdapterAdapterInfoGet(GAmdContext, @adapters[0], bufSize) <> ADL_OK then
  begin
    GAmdMainControlDestroy(GAmdContext);
    GAmdContext := nil;
    GAmdInitFailed := True;
    Exit;
  end;
  GAmdAdapterIndex := -1;
  for i := 0 to numAdapters - 1 do
  begin
    if (adapters[i].iPresent <> 0) and (adapters[i].iVendorID = AMD_VENDOR_ID) then
    begin
      GAmdAdapterIndex := adapters[i].iAdapterIndex;
      Break;
    end;
  end;
  if GAmdAdapterIndex < 0 then
  begin
    for i := 0 to numAdapters - 1 do
    begin
      if adapters[i].iVendorID = AMD_VENDOR_ID then
      begin
        GAmdAdapterIndex := adapters[i].iAdapterIndex;
        Break;
      end;
    end;
  end;
  if GAmdAdapterIndex < 0 then
  begin
    for i := 0 to numAdapters - 1 do
    begin
      if adapters[i].iPresent <> 0 then
      begin
        GAmdAdapterIndex := adapters[i].iAdapterIndex;
        Break;
      end;
    end;
  end;
  if GAmdAdapterIndex < 0 then
  begin
    GAmdMainControlDestroy(GAmdContext);
    GAmdContext := nil;
    GAmdInitFailed := True;
    Exit;
  end;
  Result := True;
end;

function GpuVendorAmdPmLogValue(const ALog: TADLPMLogDataOutput; const ASensorId: Integer): Integer;
begin
  if (ASensorId < 0) or (ASensorId >= ADL_PMLOG_MAX_SENSORS) then
    Exit(0);
  if ALog.sensors[ASensorId].supported = 0 then
    Exit(0);
  Result := ALog.sensors[ASensorId].value;
end;

function GpuVendorAmdPmLogSupported(const ALog: TADLPMLogDataOutput; const ASensorId: Integer): Boolean;
begin
  Result := (ASensorId >= 0) and (ASensorId < ADL_PMLOG_MAX_SENSORS) and
    (ALog.sensors[ASensorId].supported <> 0);
end;

procedure GpuVendorAmdApplyPmLog(const ALog: TADLPMLogDataOutput; var AInfo: TGpuSensorInfo);
var
  raw: Integer;
begin
  raw := GpuVendorAmdPmLogValue(ALog, ADL_PMLOG_TEMPERATURE_EDGE);
  if raw <> 0 then
  begin
    if Abs(raw) > 1000 then
      GpuVendorSetTemp(AInfo, raw * 0.001)
    else
      GpuVendorSetTemp(AInfo, raw);
  end;

  raw := GpuVendorAmdPmLogValue(ALog, ADL_PMLOG_CLK_GFXCLK);
  if raw <> 0 then
    GpuVendorSetCoreClock(AInfo, GpuVendorNormalizeClockMhz(raw));

  raw := GpuVendorAmdPmLogValue(ALog, ADL_PMLOG_CLK_MEMCLK);
  if raw <> 0 then
    GpuVendorSetMemClock(AInfo, GpuVendorNormalizeClockMhz(raw));

  raw := GpuVendorAmdPmLogValue(ALog, ADL_PMLOG_FAN_RPM);
  if GpuVendorAmdPmLogSupported(ALog, ADL_PMLOG_FAN_RPM) then
    GpuVendorSetFan(AInfo, raw)
  else
  begin
    raw := GpuVendorAmdPmLogValue(ALog, ADL_PMLOG_FAN_PERCENTAGE);
    if GpuVendorAmdPmLogSupported(ALog, ADL_PMLOG_FAN_PERCENTAGE) then
      GpuVendorSetFan(AInfo, raw);
  end;

  raw := GpuVendorAmdPmLogValue(ALog, ADL_PMLOG_GFX_VOLTAGE);
  if raw <> 0 then
    GpuVendorSetVoltage(AInfo, raw * 0.001);

  raw := GpuVendorAmdPmLogValue(ALog, ADL_PMLOG_BOARD_POWER);
  if raw = 0 then
    raw := GpuVendorAmdPmLogValue(ALog, ADL_PMLOG_ASIC_POWER);
  if raw <> 0 then
    GpuVendorSetPower(AInfo, raw);
end;

procedure GpuVendorAmdApplyOverdriveFallback(var AInfo: TGpuSensorInfo);
var
  tempRaw, powerRaw: Integer;
  perf: TADLODNPerformanceStatus;
  odTemp: TADLTemperature;
  fan: TADLFanSpeedValue;
  activity: TADLPMActivity;
begin
  if Assigned(GAmdOverdriveNTemperatureGet) then
  begin
    tempRaw := 0;
    if GAmdOverdriveNTemperatureGet(GAmdContext, GAmdAdapterIndex, ADL_ODN_TEMP_EDGE, tempRaw) = ADL_OK then
      GpuVendorSetTemp(AInfo, tempRaw * 0.001);
  end;

  if Assigned(GAmdOverdriveNPerformanceStatusGet) and
    (GAmdOverdriveNPerformanceStatusGet(GAmdContext, GAmdAdapterIndex, perf) = ADL_OK) then
  begin
    if not AInfo.HasFrequency then
    begin
      if perf.iGFXClock > 0 then
        GpuVendorSetCoreClock(AInfo, perf.iGFXClock)
      else if perf.iCoreClock > 0 then
        GpuVendorSetCoreClock(AInfo, perf.iCoreClock);
    end;
    if not AInfo.HasMemFrequency and (perf.iMemoryClock > 0) then
      GpuVendorSetMemClock(AInfo, perf.iMemoryClock);
    if not AInfo.HasVoltage and (perf.iVDDC > 0) then
      GpuVendorSetVoltage(AInfo, perf.iVDDC * 0.001);
  end;

  if Assigned(GAmdOverdrive6CurrentPowerGet) and not AInfo.HasPower then
  begin
    powerRaw := 0;
    if GAmdOverdrive6CurrentPowerGet(GAmdContext, GAmdAdapterIndex, ADL_ODN_POWER_TOTAL, powerRaw) = ADL_OK then
      GpuVendorSetPower(AInfo, powerRaw shr 8);
  end;

  if Assigned(GAmdOverdrive5TemperatureGet) and not AInfo.HasTemperature then
  begin
    FillChar(odTemp, SizeOf(odTemp), 0);
    odTemp.iSize := SizeOf(odTemp);
    if GAmdOverdrive5TemperatureGet(GAmdContext, GAmdAdapterIndex, 0, odTemp) = ADL_OK then
      GpuVendorSetTemp(AInfo, odTemp.iTemperature * 0.001);
  end;

  if Assigned(GAmdOverdrive5FanSpeedGet) and not AInfo.HasFanSpeed then
  begin
    FillChar(fan, SizeOf(fan), 0);
    fan.iSize := SizeOf(fan);
    fan.iSpeedType := ADL_DL_FANCTRL_SPEED_TYPE_RPM;
    if GAmdOverdrive5FanSpeedGet(GAmdContext, GAmdAdapterIndex, 0, fan) = ADL_OK then
      GpuVendorSetFan(AInfo, fan.iFanSpeed);
  end;

  if Assigned(GAmdOverdrive5CurrentActivityGet) then
  begin
    FillChar(activity, SizeOf(activity), 0);
    activity.iSize := SizeOf(activity);
    if GAmdOverdrive5CurrentActivityGet(GAmdContext, GAmdAdapterIndex, activity) = ADL_OK then
    begin
      if not AInfo.HasFrequency and (activity.iEngineClock > 0) then
        GpuVendorSetCoreClock(AInfo, activity.iEngineClock * 0.01);
      if not AInfo.HasMemFrequency and (activity.iMemoryClock > 0) then
        GpuVendorSetMemClock(AInfo, activity.iMemoryClock * 0.01);
      if not AInfo.HasVoltage and (activity.iVddc > 0) then
        GpuVendorSetVoltage(AInfo, activity.iVddc * 0.001);
    end;
  end;
end;

function GpuVendorApplyAmdMemory(var AInfo: TGpuSensorInfo): Boolean;
var
  memInfo: TADLMemoryInfoX2;
  vramUsageMb: Integer;
  totalBytes, usedBytes: UInt64;
begin
  Result := False;
  if not Assigned(GAmdAdapterMemoryInfoX2Get) then
    Exit;
  FillChar(memInfo, SizeOf(memInfo), 0);
  memInfo.iSize := SizeOf(memInfo);
  if GAmdAdapterMemoryInfoX2Get(GAmdContext, GAmdAdapterIndex, memInfo) <> ADL_OK then
    Exit;
  if memInfo.iMemorySize <= 0 then
    Exit;
  totalBytes := UInt64(memInfo.iMemorySize);
  usedBytes := 0;
  if Assigned(GAmdAdapterDedicatedVRAMUsageGet) then
  begin
    vramUsageMb := 0;
    if GAmdAdapterDedicatedVRAMUsageGet(GAmdContext, GAmdAdapterIndex, vramUsageMb) = ADL_OK then
    begin
      if vramUsageMb > 0 then
        usedBytes := UInt64(vramUsageMb) * 1024 * 1024;
    end;
  end;
  GpuVendorApplyMemUsage(AInfo, totalBytes, usedBytes);
  Result := AInfo.HasTotalMem;
end;

function GpuVendorApplyAmdSensors(var AInfo: TGpuSensorInfo): Boolean;
var
  pmLog: TADLPMLogDataOutput;
  hasSensorData, hasMemData: Boolean;
begin
  Result := False;
  if not GpuVendorAmdEnsureContext then
    Exit;
  FillChar(pmLog, SizeOf(pmLog), 0);
  pmLog.size := SizeOf(pmLog);
  if Assigned(GAmdNewQueryPMLogDataGet) and
    (GAmdNewQueryPMLogDataGet(GAmdContext, GAmdAdapterIndex, pmLog) = ADL_OK) then
    GpuVendorAmdApplyPmLog(pmLog, AInfo);
  GpuVendorAmdApplyOverdriveFallback(AInfo);
  hasMemData := GpuVendorApplyAmdMemory(AInfo);
  hasSensorData := AInfo.HasTemperature or AInfo.HasPower or AInfo.HasFrequency or
    AInfo.HasMemFrequency or AInfo.HasVoltage or AInfo.HasFanSpeed;
  Result := hasSensorData or hasMemData;
end;

function GpuVendorNvmlLoadLibrary: Boolean;
begin
  if GNvmlModule <> 0 then
    Exit(True);
  GNvmlModule := LoadLibrary('nvml.dll');
  Result := GNvmlModule <> 0;
end;

function GpuVendorNvmlLoadFunctions: Boolean;
begin
  if GNvmlFnsReady then
    Exit(True);
  if not GpuVendorNvmlLoadLibrary then
    Exit(False);
  GNvmlInit := GpuVendorLoadProc(GNvmlModule, 'nvmlInit_v2');
  if not Assigned(GNvmlInit) then
    GNvmlInit := GpuVendorLoadProc(GNvmlModule, 'nvmlInit');
  GNvmlShutdown := GpuVendorLoadProc(GNvmlModule, 'nvmlShutdown');
  GNvmlDeviceGetCount := GpuVendorLoadProc(GNvmlModule, 'nvmlDeviceGetCount');
  GNvmlDeviceGetHandleByIndex := GpuVendorLoadProc(GNvmlModule, 'nvmlDeviceGetHandleByIndex');
  GNvmlDeviceGetTemperature := GpuVendorLoadProc(GNvmlModule, 'nvmlDeviceGetTemperature');
  GNvmlDeviceGetPowerUsage := GpuVendorLoadProc(GNvmlModule, 'nvmlDeviceGetPowerUsage');
  GNvmlDeviceGetClockInfo := GpuVendorLoadProc(GNvmlModule, 'nvmlDeviceGetClockInfo');
  GNvmlDeviceGetFanSpeed := GpuVendorLoadProc(GNvmlModule, 'nvmlDeviceGetFanSpeed');
  GNvmlDeviceGetMemoryInfo := GpuVendorLoadProc(GNvmlModule, 'nvmlDeviceGetMemoryInfo');
  GNvmlFnsReady := Assigned(GNvmlInit) and Assigned(GNvmlShutdown) and
    Assigned(GNvmlDeviceGetCount) and Assigned(GNvmlDeviceGetHandleByIndex) and
    Assigned(GNvmlDeviceGetTemperature) and Assigned(GNvmlDeviceGetPowerUsage) and
    Assigned(GNvmlDeviceGetClockInfo);
  Result := GNvmlFnsReady;
end;

function GpuVendorApplyNvmlSensors(var AInfo: TGpuSensorInfo): Boolean;
var
  device: TNvmlDevice;
  count, temp, powerMw, clockMhz, fanRpm: Cardinal;
  mem: TNvmlMemory;
  hasSensorData, hasMemData: Boolean;
begin
  Result := False;
  if GNvmlInitFailed then
    Exit;
  if not GpuVendorNvmlLoadFunctions then
  begin
    GNvmlInitFailed := True;
    Exit;
  end;
  if GNvmlInit() <> NVML_SUCCESS then
  begin
    GNvmlInitFailed := True;
    Exit;
  end;
  try
    count := 0;
    if GNvmlDeviceGetCount(count) <> NVML_SUCCESS then
      Exit;
    if count = 0 then
      Exit;
    if GNvmlDeviceGetHandleByIndex(0, device) <> NVML_SUCCESS then
      Exit;
    temp := 0;
    if GNvmlDeviceGetTemperature(device, NVML_TEMPERATURE_GPU, temp) = NVML_SUCCESS then
      GpuVendorSetTemp(AInfo, temp);
    powerMw := 0;
    if GNvmlDeviceGetPowerUsage(device, powerMw) = NVML_SUCCESS then
      GpuVendorSetPower(AInfo, powerMw / 1000.0);
    clockMhz := 0;
    if GNvmlDeviceGetClockInfo(device, NVML_CLOCK_GRAPHICS, clockMhz) = NVML_SUCCESS then
      GpuVendorSetCoreClock(AInfo, clockMhz);
    clockMhz := 0;
    if GNvmlDeviceGetClockInfo(device, NVML_CLOCK_MEM, clockMhz) = NVML_SUCCESS then
      GpuVendorSetMemClock(AInfo, clockMhz);
    if Assigned(GNvmlDeviceGetFanSpeed) then
    begin
      fanRpm := 0;
      if GNvmlDeviceGetFanSpeed(device, fanRpm) = NVML_SUCCESS then
        GpuVendorSetFan(AInfo, fanRpm);
    end;
    hasMemData := False;
    if Assigned(GNvmlDeviceGetMemoryInfo) then
    begin
      FillChar(mem, SizeOf(mem), 0);
      if (GNvmlDeviceGetMemoryInfo(device, mem) = NVML_SUCCESS) and (mem.total > 0) then
      begin
        GpuVendorApplyMemUsage(AInfo, mem.total, mem.used);
        hasMemData := True;
      end;
    end;
    hasSensorData := AInfo.HasTemperature or AInfo.HasPower or AInfo.HasFrequency or
      AInfo.HasMemFrequency or AInfo.HasFanSpeed;
    Result := hasSensorData or hasMemData;
  finally
    GNvmlShutdown();
  end;
end;

function GpuVendorApplySensors(var AInfo: TGpuSensorInfo): Boolean;
begin
  Result := GpuVendorApplyAmdSensors(AInfo);
  if Result then
    Exit;
  Result := GpuVendorApplyNvmlSensors(AInfo);
end;

procedure GpuVendorShutdown;
begin
  if (GAmdContext <> nil) and Assigned(GAmdMainControlDestroy) then
  begin
    GAmdMainControlDestroy(GAmdContext);
    GAmdContext := nil;
  end;
  if GAmdModule <> 0 then
  begin
    FreeLibrary(GAmdModule);
    GAmdModule := 0;
  end;
  GAmdFnsReady := False;
  if GNvmlModule <> 0 then
  begin
    FreeLibrary(GNvmlModule);
    GNvmlModule := 0;
  end;
  GNvmlFnsReady := False;
end;

initialization

finalization
  GpuVendorShutdown;

end.
