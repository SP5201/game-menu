unit CpuInfoNative;

{
  CPU 静态信息（CPUID + NT API），作为 NwInfo 不可用时的回退实现。
}

interface

uses
  Windows, SysUtils, CpuInfoTypes;

function CpuNativeQueryStaticInfo: TCpuStaticInfo;
function CpuNativeFormatModelName(const ARawBrand: string): string;

implementation

type
  TCpuIdRegs = record
    Eax, Ebx, Ecx, Edx: Cardinal;
  end;

  { Win32 SYSTEM_LOGICAL_PROCESSOR_INFORMATION = 24 字节；仅解析 Relationship 字段 }
  SYSTEM_LOGICAL_PROCESSOR_INFORMATION = record
    ProcessorMask: ULONG_PTR;
    Relationship: DWORD;
    Reserved: array[0..15] of Byte;
  end;
  PSYSTEM_LOGICAL_PROCESSOR_INFORMATION = ^SYSTEM_LOGICAL_PROCESSOR_INFORMATION;

const
  RelationProcessorCore = 0;
  RelationCache = 2;
  CLogProcInfoSize = 24;
  CLogProcCacheLevelOff = 8;
  CLogProcCacheSizeOff = 12;
  CLogProcCacheTypeOff = 16;
  CLogProcL1TypeSlots = 16;
  { ntexapi.h：Hits(8) + PercentFrequency(1) + 对齐填充 = 16，不可用 packed 9 字节 }
  CLogProcHitCountSize = 16;

function GetLogicalProcessorInformation(
  Buffer: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION; var ReturnedLength: DWORD): BOOL; stdcall;
  external kernel32 name 'GetLogicalProcessorInformation';

type
  NTSTATUS = LongInt;

  PROCESSOR_POWER_INFORMATION = record
    Number: DWORD;
    MaxMhz: ULONG;
    CurrentMhz: ULONG;
    MhzLimit: ULONG;
    MaxIdleState: ULONG;
    CurrentIdleState: ULONG;
  end;
  PPROCESSOR_POWER_INFORMATION = ^PROCESSOR_POWER_INFORMATION;

  TCallNtPowerInformation = function(
    InformationLevel: DWORD;
    InputBuffer: Pointer;
    InputBufferLength: ULONG;
    OutputBuffer: Pointer;
    OutputBufferLength: ULONG): NTSTATUS; stdcall;

  TNtQuerySystemInformation = function(
    SystemInformationClass: DWORD;
    SystemInformation: Pointer;
    SystemInformationLength: ULONG;
    ReturnLength: PULONG): NTSTATUS; stdcall;

  SYSTEM_PROCESSOR_PERFORMANCE_HITCOUNT = record
    Hits: UInt64;
    PercentFrequency: Byte;
    _Padding: array[0..6] of Byte;
  end;
  PSYSTEM_PROCESSOR_PERFORMANCE_HITCOUNT = ^SYSTEM_PROCESSOR_PERFORMANCE_HITCOUNT;

  SYSTEM_PROCESSOR_PERFORMANCE_STATE_DISTRIBUTION = record
    ProcessorNumber: ULONG;
    StateCount: ULONG;
  end;
  PSYSTEM_PROCESSOR_PERFORMANCE_STATE_DISTRIBUTION = ^SYSTEM_PROCESSOR_PERFORMANCE_STATE_DISTRIBUTION;

  SYSTEM_PROCESSOR_PERFORMANCE_DISTRIBUTION = record
    ProcessorCount: ULONG;
  end;
  PSYSTEM_PROCESSOR_PERFORMANCE_DISTRIBUTION = ^SYSTEM_PROCESSOR_PERFORMANCE_DISTRIBUTION;

const
  STATUS_SUCCESS = NTSTATUS(0);
  SystemProcessorPowerInformation = 11;
  SystemProcessorPerformanceDistribution = 100;

  cSpeedSampleMinMs = 900;

var
  GCallNtPowerInformation: TCallNtPowerInformation = nil;
  GCallNtPowerInformationTried: Boolean = False;
  GNtQuerySystemInformation: TNtQuerySystemInformation = nil;
  GNtQuerySystemInformationTried: Boolean = False;
  GSavedPerfDistBuf: Pointer = nil;
  GSavedPerfDistLen: ULONG = 0;
  GLastCurrentSpeedMhz: DWORD = 0;
  GSpeedLastSampleTick: DWORD = 0;

function CpuSpeedSampleTickElapsed(ANowTick, ALastTick: DWORD): Integer;
begin
  if ANowTick >= ALastTick then
    Result := ANowTick - ALastTick
  else
    Result := (High(DWORD) - ALastTick) + ANowTick + 1;
end;

procedure CpuCommitCurrentSpeedSample(const ASpeedMhz: DWORD);
begin
  if ASpeedMhz = 0 then
    Exit;
  GLastCurrentSpeedMhz := ASpeedMhz;
  GSpeedLastSampleTick := GetTickCount;
end;

function NT_SUCCESS(AStatus: NTSTATUS): Boolean;
begin
  Result := AStatus >= 0;
end;

function CpuTryLoadNtQuerySystemInformation: Boolean;
var
  modNtdll: HMODULE;
begin
  Result := Assigned(GNtQuerySystemInformation);
  if GNtQuerySystemInformationTried then
    Exit(Result);
  GNtQuerySystemInformationTried := True;
  modNtdll := GetModuleHandle('ntdll.dll');
  if modNtdll = 0 then
    modNtdll := LoadLibrary('ntdll.dll');
  if modNtdll <> 0 then
    @GNtQuerySystemInformation := GetProcAddress(modNtdll, PAnsiChar('NtQuerySystemInformation'));
  Result := Assigned(GNtQuerySystemInformation);
end;

function CpuNtQuerySystemInformation(
  SystemInformationClass: DWORD;
  SystemInformation: Pointer;
  SystemInformationLength: ULONG;
  ReturnLength: PULONG): NTSTATUS;
begin
  if not CpuTryLoadNtQuerySystemInformation then
    Result := NTSTATUS(-1)
  else
    Result := GNtQuerySystemInformation(
      SystemInformationClass, SystemInformation, SystemInformationLength, ReturnLength);
end;

function CpuTryLoadNtPowerInformation: Boolean;
var
  modNtdll, modPowrProf: HMODULE;
begin
  Result := Assigned(GCallNtPowerInformation);
  if GCallNtPowerInformationTried then
    Exit(Result);
  GCallNtPowerInformationTried := True;
  modNtdll := GetModuleHandle('ntdll.dll');
  if modNtdll = 0 then
    modNtdll := LoadLibrary('ntdll.dll');
  if modNtdll <> 0 then
    @GCallNtPowerInformation := GetProcAddress(modNtdll, PAnsiChar('NtPowerInformation'));
  if not Assigned(GCallNtPowerInformation) and (modNtdll <> 0) then
    @GCallNtPowerInformation := GetProcAddress(modNtdll, PAnsiChar('CallNtPowerInformation'));
  if not Assigned(GCallNtPowerInformation) then
  begin
    modPowrProf := LoadLibrary('powrprof.dll');
    if modPowrProf <> 0 then
      @GCallNtPowerInformation := GetProcAddress(modPowrProf, PAnsiChar('CallNtPowerInformation'));
  end;
  Result := Assigned(GCallNtPowerInformation);
end;

function CpuNtPowerInformation(
  InformationLevel: DWORD;
  InputBuffer: Pointer;
  InputBufferLength: ULONG;
  OutputBuffer: Pointer;
  OutputBufferLength: ULONG): NTSTATUS;
begin
  if not CpuTryLoadNtPowerInformation then
    Result := NTSTATUS(-1)
  else
    Result := GCallNtPowerInformation(
      InformationLevel, InputBuffer, InputBufferLength, OutputBuffer, OutputBufferLength);
end;

function CpuGetOsMajorVersion: DWORD;
type
  TRtlGetVersion = function(var AInfo: TOSVersionInfoEx): NTSTATUS; stdcall;
var
  modNtdll: HMODULE;
  rtlGetVersion: TRtlGetVersion;
  osInfo: TOSVersionInfoEx;
begin
  Result := 0;
  modNtdll := GetModuleHandle('ntdll.dll');
  if modNtdll = 0 then
    Exit;
  @rtlGetVersion := GetProcAddress(modNtdll, PAnsiChar('RtlGetVersion'));
  if not Assigned(rtlGetVersion) then
    Exit;
  FillChar(osInfo, SizeOf(osInfo), 0);
  osInfo.dwOSVersionInfoSize := SizeOf(osInfo);
  if NT_SUCCESS(rtlGetVersion(osInfo)) then
    Result := osInfo.dwMajorVersion;
end;

function CpuQueryProcessorPowerInfo(out ABuf: PPROCESSOR_POWER_INFORMATION; out ACpuCount: Integer): Boolean;
var
  sysInfo: TSystemInfo;
  bufLen: ULONG;
  status: NTSTATUS;
  entrySize: LongWord;
begin
  Result := False;
  ABuf := nil;
  ACpuCount := 0;
  if not CpuTryLoadNtPowerInformation then
    Exit;
  GetSystemInfo(sysInfo);
  ACpuCount := sysInfo.dwNumberOfProcessors;
  if ACpuCount <= 0 then
    Exit;
  entrySize := SizeOf(PROCESSOR_POWER_INFORMATION);
  bufLen := ULONG(ACpuCount) * entrySize;
  GetMem(ABuf, bufLen);
  status := CpuNtPowerInformation(SystemProcessorPowerInformation, nil, 0, ABuf, bufLen);
  Result := NT_SUCCESS(status);
  if not Result then
  begin
    FreeMem(ABuf);
    ABuf := nil;
    ACpuCount := 0;
  end;
end;

function CpuGetProcessorPerfDistribution(out ABuf: Pointer; out ALen: ULONG): Boolean;
var
  status: NTSTATUS;
  retLen: ULONG;
begin
  Result := False;
  ABuf := nil;
  ALen := 0;
  if not CpuTryLoadNtQuerySystemInformation then
    Exit;
  retLen := 0;
  status := CpuNtQuerySystemInformation(SystemProcessorPerformanceDistribution, nil, 0, @retLen);
  if (not NT_SUCCESS(status)) and (retLen = 0) then
    Exit;
  if retLen = 0 then
    Exit;
  GetMem(ABuf, retLen);
  status := CpuNtQuerySystemInformation(SystemProcessorPerformanceDistribution, ABuf, retLen, @retLen);
  if not NT_SUCCESS(status) then
  begin
    FreeMem(ABuf);
    ABuf := nil;
    Exit;
  end;
  ALen := retLen;
  Result := True;
end;

procedure CpuSavePerfDistribution(const ABuf: Pointer; const ALen: ULONG);
begin
  if GSavedPerfDistBuf <> nil then
    FreeMem(GSavedPerfDistBuf);
  GSavedPerfDistBuf := nil;
  GSavedPerfDistLen := 0;
  if (ABuf = nil) or (ALen = 0) then
    Exit;
  GetMem(GSavedPerfDistBuf, ALen);
  Move(ABuf^, GSavedPerfDistBuf^, ALen);
  GSavedPerfDistLen := ALen;
end;

function CpuCalcSpeedFromPerfDistribution(
  const ACurBuf, ASavedBuf: Pointer;
  const ABufLen: ULONG;
  const APower: PPROCESSOR_POWER_INFORMATION;
  const ACpuCount: Integer): DWORD;
var
  curDist, savedDist: PSYSTEM_PROCESSOR_PERFORMANCE_DISTRIBUTION;
  procIdx, stateIdx: Integer;
  curState, savedState: PSYSTEM_PROCESSOR_PERFORMANCE_STATE_DISTRIBUTION;
  curOff, savedOff: ULONG;
  stateCount: ULONG;
  totalHits, totalFreq: UInt64;
  hitsDelta: UInt64;
  maxMhz: ULONG;
begin
  Result := 0;
  if (ACurBuf = nil) or (ASavedBuf = nil) or (APower = nil) or (ACpuCount <= 0) then
    Exit;
  curDist := PSYSTEM_PROCESSOR_PERFORMANCE_DISTRIBUTION(ACurBuf);
  savedDist := PSYSTEM_PROCESSOR_PERFORMANCE_DISTRIBUTION(ASavedBuf);
  if (curDist^.ProcessorCount = 0) or (curDist^.ProcessorCount <> savedDist^.ProcessorCount) then
    Exit;
  if curDist^.ProcessorCount > ULONG(ACpuCount) then
    Exit;
  totalHits := 0;
  totalFreq := 0;
  for procIdx := 0 to Integer(curDist^.ProcessorCount) - 1 do
  begin
    curOff := PULONG(LongWord(ACurBuf) + SizeOf(ULONG) + LongWord(procIdx) * SizeOf(ULONG))^;
    savedOff := PULONG(LongWord(ASavedBuf) + SizeOf(ULONG) + LongWord(procIdx) * SizeOf(ULONG))^;
    curState := PSYSTEM_PROCESSOR_PERFORMANCE_STATE_DISTRIBUTION(LongWord(ACurBuf) + curOff);
    savedState := PSYSTEM_PROCESSOR_PERFORMANCE_STATE_DISTRIBUTION(LongWord(ASavedBuf) + savedOff);
    if curState^.StateCount <> savedState^.StateCount then
      Continue;
    stateCount := curState^.StateCount;
    maxMhz := PPROCESSOR_POWER_INFORMATION(
      Pointer(LongWord(APower) + LongWord(procIdx) * SizeOf(PROCESSOR_POWER_INFORMATION)))^.MaxMhz;
    if maxMhz = 0 then
      maxMhz := APower^.MaxMhz;
    for stateIdx := 0 to Integer(stateCount) - 1 do
    begin
      hitsDelta := PSYSTEM_PROCESSOR_PERFORMANCE_HITCOUNT(
        LongWord(curState) + SizeOf(SYSTEM_PROCESSOR_PERFORMANCE_STATE_DISTRIBUTION) +
        LongWord(stateIdx) * CLogProcHitCountSize)^.Hits -
        PSYSTEM_PROCESSOR_PERFORMANCE_HITCOUNT(
        LongWord(savedState) + SizeOf(SYSTEM_PROCESSOR_PERFORMANCE_STATE_DISTRIBUTION) +
        LongWord(stateIdx) * CLogProcHitCountSize)^.Hits;
      if hitsDelta > 0 then
      begin
        Inc(totalHits, hitsDelta);
        Inc(totalFreq, hitsDelta *
          PSYSTEM_PROCESSOR_PERFORMANCE_HITCOUNT(
            LongWord(curState) + SizeOf(SYSTEM_PROCESSOR_PERFORMANCE_STATE_DISTRIBUTION) +
            LongWord(stateIdx) * CLogProcHitCountSize)^.PercentFrequency * maxMhz);
      end;
    end;
  end;
  if totalHits > 0 then
    Result := DWORD(totalFreq div totalHits div 100);
end;

function CpuQueryCurrentSpeedLegacyAvg(const APower: PPROCESSOR_POWER_INFORMATION; const ACpuCount: Integer): DWORD;
var
  i: Integer;
  sum, cnt: UInt64;
  maxCur: ULONG;
  entry: PPROCESSOR_POWER_INFORMATION;
  entrySize: LongWord;
begin
  Result := 0;
  maxCur := 0;
  sum := 0;
  cnt := 0;
  entrySize := SizeOf(PROCESSOR_POWER_INFORMATION);
  for i := 0 to ACpuCount - 1 do
  begin
    entry := PPROCESSOR_POWER_INFORMATION(Pointer(LongWord(APower) + LongWord(i) * entrySize));
    if entry^.CurrentMhz > 0 then
    begin
      Inc(sum, entry^.CurrentMhz);
      Inc(cnt);
    end;
    if entry^.CurrentMhz > maxCur then
      maxCur := entry^.CurrentMhz;
  end;
  if maxCur > 0 then
    Result := maxCur
  else if cnt > 0 then
    Result := DWORD(sum div cnt);
end;

procedure CpuIdLeaf(const AFunc: Cardinal; out ARegs: TCpuIdRegs); assembler;
asm
  push ebx
  push edi
  mov edi, edx
  cpuid
  mov dword ptr [edi], eax
  mov dword ptr [edi + 4], ebx
  mov dword ptr [edi + 8], ecx
  mov dword ptr [edi + 12], edx
  pop edi
  pop ebx
end;

function CpuIdBrandString: string;
var
  regs: TCpuIdRegs;
  brand: array[0..47] of AnsiChar;
  i: Integer;
begin
  Result := '';
  CpuIdLeaf($80000000, regs);
  if regs.Eax < $80000004 then
    Exit;
  FillChar(brand, SizeOf(brand), 0);
  for i := 0 to 2 do
  begin
    CpuIdLeaf($80000002 + Cardinal(i), regs);
    Move(regs.Eax, brand[i * 16], 4);
    Move(regs.Ebx, brand[i * 16 + 4], 4);
    Move(regs.Ecx, brand[i * 16 + 8], 4);
    Move(regs.Edx, brand[i * 16 + 12], 4);
  end;
  Result := Trim(string(brand));
end;

function CpuIdVendorString: string;
var
  regs: TCpuIdRegs;
  raw: array[0..12] of AnsiChar;
begin
  Result := '';
  CpuIdLeaf(0, regs);
  FillChar(raw, SizeOf(raw), 0);
  Move(regs.Ebx, raw[0], 4);
  Move(regs.Edx, raw[4], 4);
  Move(regs.Ecx, raw[8], 4);
  Result := Trim(string(raw));
end;

function VendorDisplayName(const AVendor: string): string;
begin
  if SameText(AVendor, 'GenuineIntel') then
    Result := 'Intel'
  else if SameText(AVendor, 'AuthenticAMD') then
    Result := 'AMD'
  else if AVendor <> '' then
    Result := AVendor
  else
    Result := cCpuDash;
end;

function FindTextInsensitive(const AText, ASub: string): Integer;
begin
  Result := Pos(AnsiUpperCase(ASub), AnsiUpperCase(AText));
end;

function StripFromMarkerInsensitive(const AText, AMarker: string): string;
var
  p: Integer;
begin
  Result := Trim(AText);
  if Result = '' then
    Exit;
  p := FindTextInsensitive(Result, AMarker);
  if p > 0 then
    Result := Trim(Copy(Result, 1, p - 1));
end;

function CpuNativeFormatModelName(const ARawBrand: string): string;
var
  s: string;
  p, i, suffixLen: Integer;
begin
  s := Trim(ARawBrand);
  if s = '' then
  begin
    Result := s;
    Exit;
  end;
  s := StringReplace(s, '(R)', '', [rfReplaceAll, rfIgnoreCase]);
  s := StringReplace(s, '(TM)', '', [rfReplaceAll, rfIgnoreCase]);
  while Pos('  ', s) > 0 do
    s := StringReplace(s, '  ', ' ', [rfReplaceAll]);

  suffixLen := Length('-Core Processor');
  p := FindTextInsensitive(s, '-Core Processor');
  if (p > 0) and (Trim(Copy(s, p + suffixLen, MaxInt)) = '') then
  begin
    i := p - 1;
    while (i >= 1) and CharInSet(s[i], ['0'..'9']) do
      Dec(i);
    s := Trim(Copy(s, 1, i));
  end;

  s := StripFromMarkerInsensitive(s, ' CPU @');
  s := StripFromMarkerInsensitive(s, ' with Radeon Graphics');
  s := StripFromMarkerInsensitive(s, ' w/ Radeon Graphics');
  Result := Trim(s);
end;

function LogProcInfoCacheLevel(const AEntry: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION): Byte;
begin
  Result := PByte(LongWord(AEntry) + CLogProcCacheLevelOff)^;
end;

function LogProcInfoCacheSize(const AEntry: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION): DWORD;
begin
  Result := PDWORD(LongWord(AEntry) + CLogProcCacheSizeOff)^;
end;

function LogProcInfoCacheType(const AEntry: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION): Word;
begin
  Result := PWord(LongWord(AEntry) + CLogProcCacheTypeOff)^;
end;

function CpuQueryCurrentSpeedMhz: DWORD;
var
  cpuCount: Integer;
  powerBuf: PPROCESSOR_POWER_INFORMATION;
  curBuf: Pointer;
  curLen: ULONG;
  nowTick: DWORD;
  elapsed: Integer;
begin
  Result := 0;
  nowTick := GetTickCount;
  if (GLastCurrentSpeedMhz > 0) and (GSpeedLastSampleTick <> 0) then
  begin
    elapsed := CpuSpeedSampleTickElapsed(nowTick, GSpeedLastSampleTick);
    if elapsed < cSpeedSampleMinMs then
    begin
      Result := GLastCurrentSpeedMhz;
      Exit;
    end;
  end;
  if not CpuQueryProcessorPowerInfo(powerBuf, cpuCount) then
    Exit;
  try
    if CpuGetOsMajorVersion < 10 then
    begin
      Result := CpuQueryCurrentSpeedLegacyAvg(powerBuf, cpuCount);
      CpuCommitCurrentSpeedSample(Result);
      Exit;
    end;

    if not CpuGetProcessorPerfDistribution(curBuf, curLen) then
    begin
      Result := CpuQueryCurrentSpeedLegacyAvg(powerBuf, cpuCount);
      CpuCommitCurrentSpeedSample(Result);
      Exit;
    end;
    try
      if GSavedPerfDistBuf = nil then
      begin
        CpuSavePerfDistribution(curBuf, curLen);
        Result := CpuQueryCurrentSpeedLegacyAvg(powerBuf, cpuCount);
        if Result = 0 then
          Result := GLastCurrentSpeedMhz;
        CpuCommitCurrentSpeedSample(Result);
        Exit;
      end;
      Result := CpuCalcSpeedFromPerfDistribution(
        curBuf, GSavedPerfDistBuf, curLen, powerBuf, cpuCount);
      CpuSavePerfDistribution(curBuf, curLen);
      if Result = 0 then
        Result := GLastCurrentSpeedMhz;
      CpuCommitCurrentSpeedSample(Result);
    finally
      FreeMem(curBuf);
    end;
  finally
    FreeMem(powerBuf);
  end;
end;

procedure QueryCpuCacheSizes(out AL1Bytes, AL2Bytes, AL3Bytes: DWORD);
var
  bufLen: DWORD;
  buf, entry: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION;
  remain, i: Integer;
  level: Byte;
  cacheType: Word;
  cacheSize: DWORD;
  maxL2, maxL3: DWORD;
  l1ByType: array[0..CLogProcL1TypeSlots - 1] of DWORD;
begin
  AL1Bytes := 0;
  AL2Bytes := 0;
  AL3Bytes := 0;
  maxL2 := 0;
  maxL3 := 0;
  FillChar(l1ByType, SizeOf(l1ByType), 0);
  bufLen := 0;
  GetLogicalProcessorInformation(nil, bufLen);
  if bufLen = 0 then
    Exit;
  GetMem(buf, bufLen);
  try
    if not GetLogicalProcessorInformation(buf, bufLen) then
      Exit;
    entry := buf;
    remain := bufLen;
    while remain >= CLogProcInfoSize do
    begin
      if entry^.Relationship = RelationCache then
      begin
        level := LogProcInfoCacheLevel(entry);
        cacheSize := LogProcInfoCacheSize(entry);
        if cacheSize > 0 then
        begin
          case level of
            1:
              begin
                cacheType := LogProcInfoCacheType(entry);
                if cacheType < CLogProcL1TypeSlots then
                begin
                  if cacheSize > l1ByType[cacheType] then
                    l1ByType[cacheType] := cacheSize;
                end;
              end;
            2:
              if cacheSize > maxL2 then
                maxL2 := cacheSize;
            3:
              if cacheSize > maxL3 then
                maxL3 := cacheSize;
          end;
        end;
      end;
      entry := PSYSTEM_LOGICAL_PROCESSOR_INFORMATION(
        Pointer(LongWord(entry) + CLogProcInfoSize));
      Dec(remain, CLogProcInfoSize);
    end;
  finally
    FreeMem(buf);
  end;

  for i := 0 to CLogProcL1TypeSlots - 1 do
    Inc(AL1Bytes, l1ByType[i]);
  AL2Bytes := maxL2;
  AL3Bytes := maxL3;
end;

function CountPhysicalCores: Integer;
var
  bufLen: DWORD;
  buf, entry: PSYSTEM_LOGICAL_PROCESSOR_INFORMATION;
  remain: Integer;
begin
  Result := 0;
  bufLen := 0;
  GetLogicalProcessorInformation(nil, bufLen);
  if bufLen = 0 then
    Exit;
  GetMem(buf, bufLen);
  try
    if not GetLogicalProcessorInformation(buf, bufLen) then
      Exit;
    entry := buf;
    remain := bufLen;
    while remain >= CLogProcInfoSize do
    begin
      if entry^.Relationship = RelationProcessorCore then
        Inc(Result);
      entry := PSYSTEM_LOGICAL_PROCESSOR_INFORMATION(
        Pointer(LongWord(entry) + CLogProcInfoSize));
      Dec(remain, CLogProcInfoSize);
    end;
  finally
    FreeMem(buf);
  end;
end;

function CpuNativeQueryStaticInfo: TCpuStaticInfo;
var
  sysInfo: TSystemInfo;
  cores: Integer;
  rawBrand: string;
begin
  rawBrand := CpuIdBrandString;
  if rawBrand = '' then
    Result.Brand := cCpuDash
  else
    Result.Brand := CpuNativeFormatModelName(rawBrand);

  Result.Vendor := VendorDisplayName(CpuIdVendorString);

  cores := CountPhysicalCores;
  Result.PhysicalCores := cores;

  GetSystemInfo(sysInfo);
  Result.LogicalProcessors := sysInfo.dwNumberOfProcessors;
  if Result.LogicalProcessors <= 0 then
    Result.LogicalProcessors := Result.PhysicalCores;

  Result.BaseSpeedMhz := 0;
  Result.CurrentSpeedMhz := CpuQueryCurrentSpeedMhz;

  QueryCpuCacheSizes(Result.L1CacheBytes, Result.L2CacheBytes, Result.L3CacheBytes);
end;

end.
