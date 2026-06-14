unit GpuInfoNative;

{
  GPU 静态信息（EnumDisplayDevicesW）与传感器（HardwarePdh 利用率 + D3DKMT 显存，无 COM/DXGI）。
}

interface

uses
  GpuInfo;

function GpuNativeQueryStaticInfo: TGpuStaticInfo;
function GpuNativeQuerySensors: TGpuSensorInfo;

implementation

uses
  Windows, SysUtils, HardwarePdh;

const
  cDisplayDeviceAttachedToDesktop = $00000001;
  cDisplayDevicePrimaryDevice = $00000004;
  cVideoClassRegPath =
    'SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}';
  STATUS_SUCCESS = Longint(0);
  STATUS_BUFFER_TOO_SMALL = Longint($C0000023);
  KMTQAITYPE_GETSEGMENTSIZE = 3;
  REG_QWORD_LOCAL = 11;

type
  TRegKeyHandle = NativeUInt;
  D3DKMT_HANDLE = UINT;
  TD3DKMT_SEGMENTSIZEINFO = record
    DedicatedVideoMemorySize: UInt64;
    DedicatedSystemMemorySize: UInt64;
    SharedSystemMemorySize: UInt64;
  end;
  TD3DKMT_QUERYADAPTERINFO = record
    hAdapter: D3DKMT_HANDLE;
    Type_: UINT;
    pPrivateDriverData: Pointer;
    PrivateDriverDataSize: UINT;
  end;
  TD3DKMT_ADAPTERINFO = record
    hAdapter: D3DKMT_HANDLE;
    AdapterLuid: TLUID;
    NumOfSources: ULONG;
    bPrecisePresentRegionsPreferred: BOOL;
  end;
  PD3DKMT_ADAPTERINFO = ^TD3DKMT_ADAPTERINFO;
  TD3DKMT_ENUMADAPTERS2 = record
    NumAdapters: ULONG;
    pAdapters: PD3DKMT_ADAPTERINFO;
  end;
  TD3DKMT_OPENADAPTERFROMLUID = record
    AdapterLuid: TLUID;
    hAdapter: D3DKMT_HANDLE;
  end;
  TUnicodeString = record
    Length: USHORT;
    MaximumLength: USHORT;
    Buffer: PWideChar;
  end;
  TD3DKMT_OPENADAPTERFROMGDIDISPLAYNAME = record
    DeviceName: TUnicodeString;
    hAdapter: D3DKMT_HANDLE;
    AdapterLuid: TLUID;
    NumOfSources: ULONG;
  end;
  TD3DKMT_CLOSEADAPTER = record
    hAdapter: D3DKMT_HANDLE;
  end;

function D3DKMTEnumAdapters2(var pEnumAdapters: TD3DKMT_ENUMADAPTERS2): Longint; stdcall; external 'gdi32.dll';
function D3DKMTOpenAdapterFromLuid(var pOpenAdapter: TD3DKMT_OPENADAPTERFROMLUID): Longint; stdcall; external 'gdi32.dll';
function D3DKMTOpenAdapterFromGdiDisplayName(var pOpenAdapter: TD3DKMT_OPENADAPTERFROMGDIDISPLAYNAME): Longint; stdcall; external 'gdi32.dll';
function D3DKMTQueryAdapterInfo(var pQueryAdapterInfo: TD3DKMT_QUERYADAPTERINFO): Longint; stdcall; external 'gdi32.dll';
function D3DKMTCloseAdapter(const pCloseAdapter: TD3DKMT_CLOSEADAPTER): Longint; stdcall; external 'gdi32.dll';

function GpuRegOpenKeyExW(AKey: TRegKeyHandle; ASubKey: PWideChar; AOptions: DWORD;
  ASamDesired: LongWord; var AResultKey: TRegKeyHandle): Longint; stdcall;
  external 'advapi32.dll' name 'RegOpenKeyExW';
function GpuRegCloseKey(AKey: TRegKeyHandle): Longint; stdcall; external 'advapi32.dll' name 'RegCloseKey';
function GpuRegQueryValueExW(AKey: TRegKeyHandle; AValueName: PWideChar; AReserved: Pointer;
  var AType: DWORD; AData: PByte; var ADataSize: DWORD): Longint; stdcall;
  external 'advapi32.dll' name 'RegQueryValueExW';

function GpuNativeReadRegString(AKey: TRegKeyHandle; const AValueName: string): string;
var
  dataType, dataSize: DWORD;
  buf: array[0..511] of WideChar;
begin
  Result := '';
  dataSize := SizeOf(buf);
  if GpuRegQueryValueExW(AKey, PWideChar(AValueName), nil, dataType,
    PByte(@buf[0]), dataSize) <> ERROR_SUCCESS then
    Exit;
  if dataType = REG_SZ then
    Result := Trim(string(buf));
end;

function GpuNativeReadRegQword(AKey: TRegKeyHandle; const AValueName: string; out AValue: UInt64): Boolean;
var
  dataType, dataSize: DWORD;
  value: UInt64;
begin
  Result := False;
  AValue := 0;
  dataSize := SizeOf(value);
  if GpuRegQueryValueExW(AKey, PWideChar(AValueName), nil, dataType,
    PByte(@value), dataSize) <> ERROR_SUCCESS then
    Exit;
  if (dataType = REG_QWORD_LOCAL) and (dataSize >= SizeOf(UInt64)) and (value > 0) then
  begin
    AValue := value;
    Result := True;
  end;
end;

function GpuNativeTryPickDevice(const ADevInfo: TDisplayDeviceW; var AInfo: TGpuStaticInfo): Boolean;
var
  name: string;
begin
  Result := False;
  if (ADevInfo.StateFlags and cDisplayDeviceAttachedToDesktop) = 0 then
    Exit;
  name := Trim(string(ADevInfo.DeviceString));
  if name = '' then
    Exit;
  if SameText(name, 'Microsoft Basic Display Driver') then
    Exit;
  AInfo.Device := name;
  Result := True;
end;

function GpuNativeParseVendorFromPnpId(const APnpId: string): string;
var
  s, venToken: string;
  p, venVal: Integer;
begin
  Result := '';
  s := UpperCase(Trim(APnpId));
  p := Pos('VEN_', s);
  if p = 0 then
    Exit;
  venToken := Copy(s, p + 4, 4);
  if not TryStrToInt('$' + venToken, venVal) then
    Exit;
  case venVal of
    $10DE: Result := 'NVIDIA';
    $1002: Result := 'AMD';
    $8086: Result := 'Intel';
    $1414: Result := 'Microsoft';
    $1A03: Result := 'ASPEED';
  else
    Result := 'PCI\' + venToken;
  end;
end;

function GpuNativeInferIntegratedGpu(const AVendorName, ADeviceName: string): Boolean;
var
  deviceUpper: string;
begin
  if not SameText(AVendorName, 'Intel') then
    Exit(False);
  deviceUpper := UpperCase(ADeviceName);
  if Pos('ARC', deviceUpper) > 0 then
    Exit(False);
  Result := (Pos('UHD', deviceUpper) > 0) or (Pos('IRIS', deviceUpper) > 0) or
    (Pos('HD GRAPHICS', deviceUpper) > 0);
end;

function GpuNativeRegPathFromDeviceKey(const ADeviceKey: string): string;
var
  s: string;
begin
  Result := '';
  s := Trim(ADeviceKey);
  if s = '' then
    Exit;
  s := StringReplace(s, '\Registry\Machine\', '', [rfIgnoreCase]);
  s := StringReplace(s, '\\', '\', [rfReplaceAll]);
  if Copy(s, 1, 1) = '\' then
    Delete(s, 1, 1);
  Result := s;
end;

procedure GpuNativeApplyClassKeyDetails(const ARegPath: string; var AInfo: TGpuStaticInfo);
var
  regHandle: TRegKeyHandle;
begin
  if ARegPath = '' then
    Exit;
  if GpuRegOpenKeyExW(HKEY_LOCAL_MACHINE, PWideChar(ARegPath), 0, KEY_READ, regHandle) <> ERROR_SUCCESS then
    Exit;
  try
    if AInfo.DriverVersion = '' then
      AInfo.DriverVersion := GpuNativeReadRegString(regHandle, 'DriverVersion');
  finally
    GpuRegCloseKey(regHandle);
  end;
end;

function GpuNativeFormatPcieGenText(ASpeedCode: Cardinal): string;
begin
  case ASpeedCode of
    1: Result := 'Gen1';
    2: Result := 'Gen2';
    3: Result := 'Gen3';
    4: Result := 'Gen4';
    5: Result := 'Gen5';
    6: Result := 'Gen6';
  else
    Result := '';
  end;
end;

type
  TDevPropKey = record
    FmtId: TGUID;
    Pid: DWORD;
  end;
  PSPDevInfoData = ^SPDevInfoData;
  SPDevInfoData = record
    cbSize: DWORD;
    ClassGuid: TGUID;
    DevInst: DWORD;
    Reserved: ULONG_PTR;
  end;

const
  DIGCF_PRESENT = $00000002;
  DIGCF_ALLCLASSES = $00000004;
  SPDRP_HARDWAREID = 1;
  DEVPROP_TYPE_UINT32 = 7;
  DEVPKEY_PciDevice_CurrentLinkWidth: TDevPropKey =
    (FmtId: '{1A3D8496-3267-4D69-843E-998A8701F2E9}'; Pid: 10);
  DEVPKEY_PciDevice_CurrentLinkSpeed: TDevPropKey =
    (FmtId: '{1A3D8496-3267-4D69-843E-998A8701F2E9}'; Pid: 11);

function SetupDiGetClassDevsW(ClassGuid: PGUID; Enumerator: PWideChar; hwndParent: Windows.HWND;
  Flags: DWORD): THandle; stdcall; external 'setupapi.dll';
function SetupDiEnumDeviceInfo(DeviceInfoSet: THandle; MemberIndex: DWORD;
  DeviceInfoData: PSPDevInfoData): BOOL; stdcall; external 'setupapi.dll';
function SetupDiGetDeviceRegistryPropertyW(DeviceInfoSet: THandle;
  DeviceInfoData: PSPDevInfoData; Property_: DWORD; PropertyRegDataType: PDWORD;
  PropertyBuffer: PByte; PropertyBufferSize: DWORD; RequiredSize: PDWORD): BOOL;
  stdcall; external 'setupapi.dll';
function SetupDiGetDevicePropertyW(DeviceInfoSet: THandle; DeviceInfoData: PSPDevInfoData;
  const PropertyKey: TDevPropKey; PropertyType: PDWORD; PropertyBuffer: PByte;
  PropertyBufferSize: DWORD; RequiredSize: PDWORD; Flags: DWORD): BOOL;
  stdcall; external 'setupapi.dll';
function SetupDiDestroyDeviceInfoList(DeviceInfoSet: THandle): BOOL; stdcall;
  external 'setupapi.dll';

function GpuNativeHardwareIdMatches(const AHardwareId, ATargetPnpId: string): Boolean;
var
  hwUpper, targetUpper: string;
begin
  hwUpper := UpperCase(Trim(AHardwareId));
  targetUpper := UpperCase(Trim(ATargetPnpId));
  if (hwUpper = '') or (targetUpper = '') then
    Exit(False);
  Result := SameText(hwUpper, targetUpper) or (Pos(hwUpper, targetUpper) = 1) or
    (Pos(Copy(targetUpper, 1, Length(hwUpper)), hwUpper) = 1);
end;

function GpuNativeTryReadPcieLink(const APnpId: string; out ALink: string): Boolean;
var
  devSet: THandle;
  devInfo: SPDevInfoData;
  idx: Integer;
  regType, reqSize, propType: DWORD;
  buf: array[0..1023] of WideChar;
  hwId: string;
  p: PWideChar;
  linkWidth, linkSpeed: Cardinal;
begin
  Result := False;
  ALink := '';
  if Trim(APnpId) = '' then
    Exit;
  devSet := SetupDiGetClassDevsW(nil, nil, 0, DIGCF_PRESENT or DIGCF_ALLCLASSES);
  if devSet = INVALID_HANDLE_VALUE then
    Exit;
  try
    idx := 0;
    while True do
    begin
      FillChar(devInfo, SizeOf(devInfo), 0);
      devInfo.cbSize := SizeOf(devInfo);
      if not SetupDiEnumDeviceInfo(devSet, DWORD(idx), @devInfo) then
        Break;
      Inc(idx);
      reqSize := 0;
      FillChar(buf, SizeOf(buf), 0);
      if not SetupDiGetDeviceRegistryPropertyW(devSet, @devInfo, SPDRP_HARDWAREID,
        @regType, PByte(@buf[0]), SizeOf(buf), @reqSize) then
        Continue;
      p := @buf[0];
      while (p <> nil) and (p^ <> #0) do
      begin
        hwId := Trim(string(p));
        if GpuNativeHardwareIdMatches(hwId, APnpId) then
        begin
          linkWidth := 0;
          linkSpeed := 0;
          reqSize := 0;
          if SetupDiGetDevicePropertyW(devSet, @devInfo, DEVPKEY_PciDevice_CurrentLinkWidth,
            @propType, PByte(@linkWidth), SizeOf(linkWidth), @reqSize, 0) and
            (propType = DEVPROP_TYPE_UINT32) and (linkWidth > 0) then
          begin
            reqSize := 0;
            if SetupDiGetDevicePropertyW(devSet, @devInfo, DEVPKEY_PciDevice_CurrentLinkSpeed,
              @propType, PByte(@linkSpeed), SizeOf(linkSpeed), @reqSize, 0) and
              (propType = DEVPROP_TYPE_UINT32) and (linkSpeed > 0) then
            begin
              ALink := GpuNativeFormatPcieGenText(linkSpeed) + ' x' + IntToStr(linkWidth);
              Exit(True);
            end;
            ALink := 'x' + IntToStr(linkWidth);
            Exit(True);
          end;
        end;
        Inc(p, Length(p) + 1);
      end;
    end;
  finally
    SetupDiDestroyDeviceInfoList(devSet);
  end;
end;

procedure GpuNativeApplyStaticDetails(const ADeviceKey, ADeviceId: string; var AInfo: TGpuStaticInfo);
var
  regPath, pcieLink: string;
begin
  if AInfo.PnpId = '' then
    AInfo.PnpId := Trim(ADeviceId);
  if AInfo.VendorName = '' then
    AInfo.VendorName := GpuNativeParseVendorFromPnpId(AInfo.PnpId);
  regPath := GpuNativeRegPathFromDeviceKey(ADeviceKey);
  GpuNativeApplyClassKeyDetails(regPath, AInfo);
  AInfo.HasIntegrated := True;
  AInfo.Integrated := GpuNativeInferIntegratedGpu(AInfo.VendorName, AInfo.Device);
  if GpuNativeTryReadPcieLink(AInfo.PnpId, pcieLink) then
    AInfo.PcieLink := pcieLink;
end;

function GpuNativeGpuNamesMatch(const ALeft, ARight: string): Boolean;
var
  leftName, rightName: string;
begin
  leftName := LowerCase(Trim(ALeft));
  rightName := LowerCase(Trim(ARight));
  if (leftName = '') or (rightName = '') then
    Exit(False);
  Result := SameText(leftName, rightName) or
    (Pos(leftName, rightName) > 0) or
    (Pos(rightName, leftName) > 0);
end;

function GpuNativeReadRegistryRamBytes(const ATargetName: string): UInt64;
var
  classHandle, subHandle: TRegKeyHandle;
  i: Integer;
  subKey, driverDesc: string;
  ramBytes, bestRam, matchedRam: UInt64;
begin
  Result := 0;
  bestRam := 0;
  matchedRam := 0;
  if GpuRegOpenKeyExW(HKEY_LOCAL_MACHINE, PWideChar(cVideoClassRegPath), 0,
    KEY_READ, classHandle) <> ERROR_SUCCESS then
    Exit;
  try
    for i := 0 to 31 do
    begin
      subKey := IntToStr(i);
      if GpuRegOpenKeyExW(classHandle, PWideChar(subKey), 0, KEY_READ, subHandle) <> ERROR_SUCCESS then
        Continue;
      try
        if not GpuNativeReadRegQword(subHandle, 'HardwareInformation.qwMemorySize', ramBytes) then
          Continue;
        driverDesc := GpuNativeReadRegString(subHandle, 'DriverDesc');
        if SameText(driverDesc, 'Microsoft Basic Display Driver') then
          Continue;
        if (ATargetName <> '') and (driverDesc <> '') and
          GpuNativeGpuNamesMatch(ATargetName, driverDesc) then
        begin
          if ramBytes > matchedRam then
            matchedRam := ramBytes;
        end
        else if ramBytes > bestRam then
          bestRam := ramBytes;
      finally
        GpuRegCloseKey(subHandle);
      end;
    end;
  finally
    GpuRegCloseKey(classHandle);
  end;
  if matchedRam > 0 then
    Result := matchedRam
  else
    Result := bestRam;
end;

procedure GpuNativeCloseD3dkmtAdapter(AHandle: D3DKMT_HANDLE);
var
  closeAdapter: TD3DKMT_CLOSEADAPTER;
begin
  if AHandle = 0 then
    Exit;
  closeAdapter.hAdapter := AHandle;
  D3DKMTCloseAdapter(closeAdapter);
end;

function GpuNativePickSegmentRamBytes(const ASeg: TD3DKMT_SEGMENTSIZEINFO): UInt64;
begin
  if ASeg.DedicatedVideoMemorySize > 0 then
    Exit(ASeg.DedicatedVideoMemorySize);
  if ASeg.DedicatedSystemMemorySize > 0 then
    Exit(ASeg.DedicatedSystemMemorySize);
  Result := 0;
end;

function GpuNativeQueryD3dkmtSegmentBytes(AAdapter: D3DKMT_HANDLE): UInt64;
var
  query: TD3DKMT_QUERYADAPTERINFO;
  seg: TD3DKMT_SEGMENTSIZEINFO;
begin
  Result := 0;
  if AAdapter = 0 then
    Exit;
  FillChar(seg, SizeOf(seg), 0);
  FillChar(query, SizeOf(query), 0);
  query.hAdapter := AAdapter;
  query.Type_ := KMTQAITYPE_GETSEGMENTSIZE;
  query.pPrivateDriverData := @seg;
  query.PrivateDriverDataSize := SizeOf(seg);
  if D3DKMTQueryAdapterInfo(query) <> STATUS_SUCCESS then
    Exit;
  Result := GpuNativePickSegmentRamBytes(seg);
end;

function GpuNativeReadD3dkmtRamByLuid(const ALuid: TLUID): UInt64;
var
  openAdapter: TD3DKMT_OPENADAPTERFROMLUID;
begin
  Result := 0;
  FillChar(openAdapter, SizeOf(openAdapter), 0);
  openAdapter.AdapterLuid := ALuid;
  if D3DKMTOpenAdapterFromLuid(openAdapter) <> STATUS_SUCCESS then
    Exit;
  try
    Result := GpuNativeQueryD3dkmtSegmentBytes(openAdapter.hAdapter);
  finally
    GpuNativeCloseD3dkmtAdapter(openAdapter.hAdapter);
  end;
end;

function GpuNativeReadD3dkmtRamByDisplayName(const AGdiDisplayName: string;
  out AAdapterLuid: TLUID; out AHasLuid: Boolean): UInt64;
var
  openAdapter: TD3DKMT_OPENADAPTERFROMGDIDISPLAYNAME;
  deviceName: UnicodeString;
  nameLen: Integer;
begin
  Result := 0;
  AHasLuid := False;
  FillChar(AAdapterLuid, SizeOf(AAdapterLuid), 0);
  deviceName := Trim(AGdiDisplayName);
  if deviceName = '' then
    Exit;
  nameLen := Length(deviceName) * SizeOf(WideChar);
  FillChar(openAdapter, SizeOf(openAdapter), 0);
  openAdapter.DeviceName.Length := nameLen;
  openAdapter.DeviceName.MaximumLength := nameLen + SizeOf(WideChar);
  openAdapter.DeviceName.Buffer := PWideChar(PWideChar(deviceName));
  if D3DKMTOpenAdapterFromGdiDisplayName(openAdapter) <> STATUS_SUCCESS then
    Exit;
  AAdapterLuid := openAdapter.AdapterLuid;
  AHasLuid := True;
  try
    Result := GpuNativeQueryD3dkmtSegmentBytes(openAdapter.hAdapter);
  finally
    GpuNativeCloseD3dkmtAdapter(openAdapter.hAdapter);
  end;
end;

function GpuNativeReadD3dkmtRamFallback(const APreferredLuid: TLUID;
  const AHasPreferredLuid: Boolean): UInt64;
var
  enumAdapters: TD3DKMT_ENUMADAPTERS2;
  adapters: array of TD3DKMT_ADAPTERINFO;
  status: Longint;
  i: Integer;
  ramBytes, bestRam: UInt64;
begin
  Result := 0;
  if AHasPreferredLuid then
  begin
    Result := GpuNativeReadD3dkmtRamByLuid(APreferredLuid);
    if Result > 0 then
      Exit;
  end;
  FillChar(enumAdapters, SizeOf(enumAdapters), 0);
  status := D3DKMTEnumAdapters2(enumAdapters);
  if (status <> STATUS_SUCCESS) and (status <> STATUS_BUFFER_TOO_SMALL) then
    Exit;
  if enumAdapters.NumAdapters = 0 then
    Exit;
  SetLength(adapters, enumAdapters.NumAdapters);
  FillChar(adapters[0], SizeOf(TD3DKMT_ADAPTERINFO) * Length(adapters), 0);
  enumAdapters.pAdapters := @adapters[0];
  if D3DKMTEnumAdapters2(enumAdapters) <> STATUS_SUCCESS then
    Exit;
  bestRam := 0;
  for i := 0 to Integer(enumAdapters.NumAdapters) - 1 do
  begin
    ramBytes := GpuNativeQueryD3dkmtSegmentBytes(adapters[i].hAdapter);
    if ramBytes > bestRam then
      bestRam := ramBytes;
    GpuNativeCloseD3dkmtAdapter(adapters[i].hAdapter);
  end;
  Result := bestRam;
end;

function GpuNativeReadAdapterRamBytes: UInt64;
var
  staticInfo: TGpuStaticInfo;
  adapterLuid: TLUID;
  hasLuid: Boolean;
begin
  staticInfo := GpuNativeQueryStaticInfo;
  hasLuid := False;
  FillChar(adapterLuid, SizeOf(adapterLuid), 0);
  if staticInfo.Location <> '' then
  begin
    Result := GpuNativeReadD3dkmtRamByDisplayName(staticInfo.Location, adapterLuid, hasLuid);
    if Result > 0 then
      Exit;
  end;
  Result := GpuNativeReadD3dkmtRamFallback(adapterLuid, hasLuid);
  if Result > 0 then
    Exit;
  Result := GpuNativeReadRegistryRamBytes(staticInfo.Device);
end;

function GpuNativeQueryStaticInfo: TGpuStaticInfo;
var
  devInfo: TDisplayDeviceW;
  i: Integer;
  fallback: TGpuStaticInfo;
  hasFallback: Boolean;
begin
  GpuInitStaticInfo(Result);
  GpuInitStaticInfo(fallback);
  hasFallback := False;
  for i := 0 to 31 do
  begin
    FillChar(devInfo, SizeOf(devInfo), 0);
    devInfo.cb := SizeOf(devInfo);
    if not EnumDisplayDevicesW(nil, DWORD(i), devInfo, 0) then
      Break;
    if not GpuNativeTryPickDevice(devInfo, Result) then
      Continue;
    Result.Location := Trim(string(devInfo.DeviceName));
    GpuNativeApplyStaticDetails(string(devInfo.DeviceKey), string(devInfo.DeviceID), Result);
    if (devInfo.StateFlags and cDisplayDevicePrimaryDevice) <> 0 then
      Exit;
    if not hasFallback then
    begin
      fallback := Result;
      hasFallback := True;
    end;
  end;
  if hasFallback then
    Result := fallback;
end;

function GpuNativeQuerySensors: TGpuSensorInfo;
var
  usage: Double;
  totalRam: UInt64;
begin
  GpuInitSensorInfo(Result);
  usage := HardwarePdhSampleGpuUtilization;
  if usage >= 0 then
  begin
    Result.HasUtilization := True;
    Result.UtilizationPct := usage;
  end;
  totalRam := GpuNativeReadAdapterRamBytes;
  if totalRam > 0 then
  begin
    Result.HasTotalMem := True;
    Result.TotalMemBytes := totalRam;
  end;
end;

end.
