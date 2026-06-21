unit HardwarePdh;

{
  硬件 PDH 单例：GPU 利用率 + CPU ACPI 热区温度（开尔文→摄氏度）。
  供 HardwareMonitor / GpuInfoNative / CpuInfo 共用，线程安全。
}

interface

function HardwarePdhSampleGpuUtilization: Double;
function HardwarePdhSampleCpuPackageTempC: Double;
procedure HardwarePdhShutdown;

implementation

uses
  Windows, SysUtils, Classes, Math;

const
  PDH_FMT_DOUBLE = $00000200;
  ERROR_SUCCESS = 0;
  PDH_MORE_DATA = DWORD($800007D2);
  cKelvinToCelsius = 273.15;
  cGpuCounterPath = '\GPU Engine(*)\Utilization Percentage';
  cCpuThermalCounterPath = '\Thermal Zone Information(*)\Temperature';
  cGpuUtilCacheMs = 2500;

type
  PDH_STATUS = Longint;
  PPDH_FMT_COUNTERVALUE_ITEM_W = ^TPDH_FMT_COUNTERVALUE_ITEM_W;
  TPDH_FMT_COUNTERVALUE = record
    CStatus: DWORD;
    doubleValue: Double;
  end;
  TPDH_FMT_COUNTERVALUE_ITEM_W = record
    szName: PWideChar;
    FmtValue: TPDH_FMT_COUNTERVALUE;
  end;

  THardwarePdhSlot = record
    Query: THandle;
    Counter: THandle;
    Ready: Boolean;
  end;

function PdhOpenQueryW(szDataSource: PWideChar; dwUserData: ULONG_PTR;
  out phQuery: THandle): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhAddEnglishCounterW(hQuery: THandle; szFullCounterPath: PWideChar;
  dwUserData: ULONG_PTR; out phCounter: THandle): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhAddCounterW(hQuery: THandle; szFullCounterPath: PWideChar;
  dwUserData: ULONG_PTR; out phCounter: THandle): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhCollectQueryData(hQuery: THandle): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhGetFormattedCounterArrayW(hCounter: THandle; dwFormat: DWORD;
  lpdwBufferSize: PDWORD; lpdwItemCount: PDWORD;
  ItemBuffer: PPDH_FMT_COUNTERVALUE_ITEM_W): PDH_STATUS; stdcall; external 'pdh.dll';
function PdhCloseQuery(hQuery: THandle): PDH_STATUS; stdcall; external 'pdh.dll';

var
  GGpuSlot: THardwarePdhSlot;
  GCpuSlot: THardwarePdhSlot;
  GPdhLock: TRTLCriticalSection;
  GGpuUtilCached: Double;
  GGpuUtilCacheTick: DWORD;
  GGpuUtilCacheValid: Boolean;

function PdhTickElapsed(ANowTick, ALastTick: DWORD): Integer;
begin
  if ANowTick >= ALastTick then
    Result := ANowTick - ALastTick
  else
    Result := (High(DWORD) - ALastTick) + ANowTick + 1;
end;

procedure HardwarePdhCloseSlot(var ASlot: THardwarePdhSlot);
begin
  ASlot.Ready := False;
  if ASlot.Query <> 0 then
    PdhCloseQuery(ASlot.Query);
  ASlot.Query := 0;
  ASlot.Counter := 0;
end;

function HardwarePdhInitSlot(var ASlot: THardwarePdhSlot; const APath: PWideChar): Boolean;
var
  status: PDH_STATUS;
begin
  Result := False;
  if ASlot.Ready then
    Exit(True);
  status := PdhOpenQueryW(nil, 0, ASlot.Query);
  if status <> ERROR_SUCCESS then
    Exit;
  status := PdhAddEnglishCounterW(ASlot.Query, APath, 0, ASlot.Counter);
  if status <> ERROR_SUCCESS then
    status := PdhAddCounterW(ASlot.Query, APath, 0, ASlot.Counter);
  if status <> ERROR_SUCCESS then
  begin
    HardwarePdhCloseSlot(ASlot);
    Exit;
  end;
  status := PdhCollectQueryData(ASlot.Query);
  if status <> ERROR_SUCCESS then
  begin
    HardwarePdhCloseSlot(ASlot);
    Exit;
  end;
  ASlot.Ready := True;
  Result := True;
end;

function HardwarePdhCollectCounterArray(var ASlot: THardwarePdhSlot;
  out ABuffer: Pointer; out AItemCount: DWORD): Boolean;
var
  status: PDH_STATUS;
  bufferSize: DWORD;
begin
  Result := False;
  ABuffer := nil;
  AItemCount := 0;
  if not ASlot.Ready then
    Exit;
  status := PdhCollectQueryData(ASlot.Query);
  if status <> ERROR_SUCCESS then
    Exit;
  bufferSize := 0;
  status := PdhGetFormattedCounterArrayW(ASlot.Counter, PDH_FMT_DOUBLE,
    @bufferSize, @AItemCount, nil);
  if (DWORD(status) <> PDH_MORE_DATA) and (status <> ERROR_SUCCESS) then
    Exit;
  if bufferSize = 0 then
    Exit;
  GetMem(ABuffer, bufferSize);
  status := PdhGetFormattedCounterArrayW(ASlot.Counter, PDH_FMT_DOUBLE,
    @bufferSize, @AItemCount, PPDH_FMT_COUNTERVALUE_ITEM_W(ABuffer));
  Result := status = ERROR_SUCCESS;
  if not Result then
  begin
    FreeMem(ABuffer);
    ABuffer := nil;
    AItemCount := 0;
  end;
end;

function HardwarePdhSampleGpuUtilizationUnlocked: Double;
var
  buffer: Pointer;
  itemCount: DWORD;
  items: PPDH_FMT_COUNTERVALUE_ITEM_W;
  i, sepIndex: Integer;
  engineGroup: string;
  usage, maxUsage, groupValue: Double;
  groups: TStringList;
begin
  Result := -1;
  if not HardwarePdhInitSlot(GGpuSlot, cGpuCounterPath) then
    Exit;
  buffer := nil;
  itemCount := 0;
  if not HardwarePdhCollectCounterArray(GGpuSlot, buffer, itemCount) then
    Exit;
  groups := TStringList.Create;
  try
    maxUsage := 0;
    items := PPDH_FMT_COUNTERVALUE_ITEM_W(buffer);
    for i := 0 to Integer(itemCount) - 1 do
    begin
      engineGroup := LowerCase(string(items^.szName));
      sepIndex := LastDelimiter('_', engineGroup);
      if sepIndex > 0 then
        engineGroup := Copy(engineGroup, sepIndex + 1, MaxInt);
      groupValue := items^.FmtValue.doubleValue;
      if groupValue < 0 then
        groupValue := 0;
      sepIndex := groups.IndexOfName(engineGroup);
      if sepIndex < 0 then
        groups.Add(engineGroup + '=' + FloatToStr(groupValue))
      else
      begin
        usage := StrToFloatDef(groups.ValueFromIndex[sepIndex], 0);
        groups.ValueFromIndex[sepIndex] := FloatToStr(usage + groupValue);
      end;
      Inc(items);
    end;
    for i := 0 to groups.Count - 1 do
    begin
      usage := StrToFloatDef(groups.ValueFromIndex[i], 0);
      if usage > maxUsage then
        maxUsage := usage;
    end;
    if maxUsage > 100 then
      maxUsage := 100;
    Result := maxUsage;
  finally
    FreeMem(buffer);
    groups.Free;
  end;
end;

function HardwarePdhSampleCpuPackageTempCUnlocked: Double;
var
  buffer: Pointer;
  itemCount: DWORD;
  items: PPDH_FMT_COUNTERVALUE_ITEM_W;
  i: Integer;
  kelvin, maxTemp: Double;
begin
  Result := -1;
  if not HardwarePdhInitSlot(GCpuSlot, cCpuThermalCounterPath) then
    Exit;
  buffer := nil;
  itemCount := 0;
  if not HardwarePdhCollectCounterArray(GCpuSlot, buffer, itemCount) then
    Exit;
  try
    items := PPDH_FMT_COUNTERVALUE_ITEM_W(buffer);
    maxTemp := -1;
    for i := 0 to Integer(itemCount) - 1 do
    begin
      kelvin := items^.FmtValue.doubleValue;
      if (kelvin <= 0) or IsNan(kelvin) or IsInfinite(kelvin) then
      begin
        Inc(items);
        Continue;
      end;
      if (kelvin - cKelvinToCelsius) > maxTemp then
        maxTemp := kelvin - cKelvinToCelsius;
      Inc(items);
    end;
    if maxTemp >= 0 then
      Result := maxTemp;
  finally
    FreeMem(buffer);
  end;
end;

function HardwarePdhSampleGpuUtilization: Double;
var
  nowTick: DWORD;
begin
  EnterCriticalSection(GPdhLock);
  try
    if GGpuUtilCacheValid then
    begin
      nowTick := GetTickCount;
      if PdhTickElapsed(nowTick, GGpuUtilCacheTick) < cGpuUtilCacheMs then
      begin
        Result := GGpuUtilCached;
        Exit;
      end;
    end;
    Result := HardwarePdhSampleGpuUtilizationUnlocked;
    if Result >= 0 then
    begin
      GGpuUtilCached := Result;
      GGpuUtilCacheTick := GetTickCount;
      GGpuUtilCacheValid := True;
    end;
  finally
    LeaveCriticalSection(GPdhLock);
  end;
end;

function HardwarePdhSampleCpuPackageTempC: Double;
begin
  EnterCriticalSection(GPdhLock);
  try
    Result := HardwarePdhSampleCpuPackageTempCUnlocked;
  finally
    LeaveCriticalSection(GPdhLock);
  end;
end;

procedure HardwarePdhShutdown;
begin
  EnterCriticalSection(GPdhLock);
  try
    HardwarePdhCloseSlot(GGpuSlot);
    HardwarePdhCloseSlot(GCpuSlot);
    GGpuUtilCacheValid := False;
  finally
    LeaveCriticalSection(GPdhLock);
  end;
end;

initialization
  InitializeCriticalSection(GPdhLock);

finalization
  HardwarePdhShutdown;
  DeleteCriticalSection(GPdhLock);

end.
