unit MemInfoNative;

{
  内存静态信息：GlobalMemoryStatusEx + SMBIOS Type 16/17（GetSystemFirmwareTable，含 3.x volatile_size / configured speed）。
}

interface

uses
  MemInfo;

function MemNativeQueryStaticInfo: TMemStaticInfo;

implementation

uses
  Windows, Classes, Math, SysUtils, MemInfoSpd, MemJedecLookup, SafeLog, DateUtils;

function GetSystemFirmwareTable(
  FirmwareTableProviderSignature: DWORD;
  FirmwareTableID: DWORD;
  pFirmwareTableBuffer: Pointer;
  BufferSize: DWORD): UINT; stdcall;
  external kernel32 name 'GetSystemFirmwareTable';

type
  TType17Rec = record
    BankLocator: string;
    DeviceLocator: string;
    DeviceSize: UInt64;
    DeviceType: string;
    SpeedMts: Cardinal;
    VoltageV: Double;
    Manufacturer: string;
    PartNumber: string;
  end;

  TType17ModuleList = array of TType17Rec;

procedure MemSmbClearType17(var ARec: TType17Rec);
begin
  ARec.BankLocator := '';
  ARec.DeviceLocator := '';
  ARec.DeviceSize := 0;
  ARec.DeviceType := '';
  ARec.SpeedMts := 0;
  ARec.VoltageV := 0;
  ARec.Manufacturer := '';
  ARec.PartNumber := '';
end;

function MemSmbParseChannelIndex(const ABankLocator: string): Integer;
var
  s, token: string;
  i, p: Integer;
begin
  Result := -1;
  s := UpperCase(Trim(ABankLocator));
  if s = '' then
    Exit;
  p := Pos('CHANNEL', s);
  if p > 0 then
  begin
    token := Trim(Copy(s, p + Length('CHANNEL'), MaxInt));
    if token = '' then
      Exit;
    if Length(token) = 1 then
    begin
      Result := Ord(token[1]) - Ord('A');
      if (Result >= 0) and (Result <= 25) then
        Exit;
    end;
    if TryStrToInt(token, Result) then
      Exit;
  end;
  for i := Length(s) downto 1 do
  begin
    if (s[i] >= 'A') and (s[i] <= 'Z') then
    begin
      Result := Ord(s[i]) - Ord('A');
      Exit;
    end;
  end;
end;

function MemSmbParseDimmIndex(const ADeviceLocator: string): Integer;
var
  s: string;
  i, n: Integer;
begin
  Result := -1;
  s := UpperCase(Trim(ADeviceLocator));
  if s = '' then
    Exit;
  if TryStrToInt(Trim(StringReplace(s, 'DIMM', '', [rfIgnoreCase])), n) then
  begin
    Result := Max(0, n - 1);
    Exit;
  end;
  i := Pos('DIMM', s);
  if i > 0 then
  begin
    s := Trim(Copy(s, i + 4, MaxInt));
    if TryStrToInt(s, n) then
    begin
      Result := Max(0, n - 1);
      Exit;
    end;
    if (s <> '') and (s[1] >= 'A') and (s[1] <= 'Z') and (Length(s) >= 2) then
    begin
      if TryStrToInt(Copy(s, 2, MaxInt), n) then
        Result := Max(0, n - 1);
    end;
  end;
end;

function MemSmbCountDistinctChannels(const AType17List: TType17ModuleList): Integer;
var
  channels: TStringList;
  i, chIdx: Integer;
begin
  channels := TStringList.Create;
  try
    channels.Sorted := True;
    channels.Duplicates := dupIgnore;
    for i := 0 to High(AType17List) do
    begin
      chIdx := MemSmbParseChannelIndex(AType17List[i].BankLocator);
      if chIdx >= 0 then
        channels.Add(IntToStr(chIdx));
    end;
    Result := channels.Count;
    if Result = 0 then
      Result := 1;
  finally
    channels.Free;
  end;
end;

function MemSmbResolvePhysicalSlotIndex(const ARec: TType17Rec; ASlotCount, ADimmsPerChannel: Integer): Integer;
var
  channelIdx, dimmIdx: Integer;
begin
  Result := 0;
  channelIdx := MemSmbParseChannelIndex(ARec.BankLocator);
  dimmIdx := MemSmbParseDimmIndex(ARec.DeviceLocator);
  if (channelIdx < 0) or (dimmIdx < 0) then
    Exit;
  if ADimmsPerChannel <= 0 then
    ADimmsPerChannel := 1;
  Result := dimmIdx + channelIdx * ADimmsPerChannel + 1;
  if (ASlotCount > 0) and (Result > Integer(ASlotCount)) then
    Result := 0;
end;

procedure MemSmbStoreType17(const ARec: TType17Rec; var AList: TType17ModuleList);
begin
  SetLength(AList, Length(AList) + 1);
  AList[High(AList)] := ARec;
end;

function MemSmbSumType17Bytes(const AList: TType17ModuleList): UInt64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(AList) do
    if AList[i].DeviceSize > 0 then
      Inc(Result, AList[i].DeviceSize);
end;

procedure MemSmbCollectDramSpec(const AList: TType17ModuleList; var AInfo: TMemStaticInfo);
var
  i: Integer;
  infType: string;
  infSpeed: Cardinal;
begin
  for i := 0 to High(AList) do
  begin
    if not MemIsUnknownLabel(AList[i].DeviceType) then
      MemUpdateDramSpec(AInfo, AList[i].DeviceType, 0);
    if AList[i].SpeedMts > 0 then
      MemUpdateDramSpec(AInfo, AList[i].DeviceType, AList[i].SpeedMts);
    MemUpdateDramVoltage(AInfo, AList[i].VoltageV);
    infType := MemInferDramTypeFromText(AList[i].PartNumber);
    if infType <> '' then
      MemUpdateDramSpec(AInfo, infType, 0);
    infSpeed := MemInferSpeedMtsFromText(AList[i].PartNumber);
    if infSpeed > 0 then
      MemUpdateDramSpec(AInfo, infType, infSpeed);
  end;
end;

procedure MemSmbType17ToModule(const ARec: TType17Rec; const AFallbackType: string;
  AFallbackSpeed: Cardinal; out AModule: TMemModuleInfo);
begin
  MemModuleClear(AModule);
  if ARec.DeviceSize = 0 then
    Exit;
  AModule.SizeBytes := ARec.DeviceSize;
  AModule.PartNumber := ARec.PartNumber;
  AModule.Manufacturer := ARec.Manufacturer;
  if not MemIsUnknownLabel(ARec.DeviceType) then
    AModule.DramType := ARec.DeviceType
  else if not MemIsUnknownLabel(AFallbackType) then
    AModule.DramType := AFallbackType;
  AModule.SpeedMts := ARec.SpeedMts;
  if AModule.SpeedMts = 0 then
    AModule.SpeedMts := AFallbackSpeed;
  AModule.CasLatency := MemInferCasFromText(ARec.PartNumber);
end;

function MemSmbResolveDisplaySlotCount(const AType17List: TType17ModuleList;
  const AInfo: TMemStaticInfo): Integer;
begin
  Result := AInfo.SlotCount;
  if Length(AType17List) > Result then
    Result := Length(AType17List);
  if Result <= 1 then
    Result := MemGuessSlotCount(AInfo.PhysTotal);
end;

procedure MemSmbBuildSlotModules(const AType17List: TType17ModuleList; var AInfo: TMemStaticInfo);
var
  i, j, slotCount, channelCount, dimmsPerChannel, slotIdx, popCount: Integer;
  slotRecs: array of TType17Rec;
  popOrder: TMemSlotOrder;
  modInfo: TMemModuleInfo;
  populated: TType17ModuleList;

  procedure AppendPopulated(const ARec: TType17Rec);
  begin
    SetLength(populated, Length(populated) + 1);
    populated[High(populated)] := ARec;
  end;

begin
  SetLength(AInfo.Modules, 0);
  slotCount := MemSmbResolveDisplaySlotCount(AType17List, AInfo);
  AInfo.SlotCount := slotCount;
  if slotCount = 0 then
    Exit;
  SetLength(slotRecs, slotCount);
  for i := 0 to slotCount - 1 do
    MemSmbClearType17(slotRecs[i]);
  SetLength(populated, 0);
  for i := 0 to High(AType17List) do
    if AType17List[i].DeviceSize > 0 then
      AppendPopulated(AType17List[i]);
  popCount := Length(populated);
  if popCount > 0 then
  begin
    popOrder := MemDualChannelSlotOrder(slotCount, popCount);
    for i := 0 to popCount - 1 do
      if i < Length(popOrder) then
        slotRecs[popOrder[i]] := populated[i];
  end;
  channelCount := MemSmbCountDistinctChannels(AType17List);
  AInfo.ChannelCount := channelCount;
  dimmsPerChannel := slotCount div channelCount;
  if dimmsPerChannel <= 0 then
    dimmsPerChannel := 1;
  for i := 0 to High(AType17List) do
  begin
    if AType17List[i].DeviceSize > 0 then
      Continue;
    slotIdx := MemSmbResolvePhysicalSlotIndex(AType17List[i], slotCount, dimmsPerChannel);
    if slotIdx <= 0 then
    begin
      for j := 0 to slotCount - 1 do
        if slotRecs[j].DeviceSize = 0 then
        begin
          slotRecs[j] := AType17List[i];
          Break;
        end;
      Continue;
    end;
    Dec(slotIdx);
    if slotRecs[slotIdx].DeviceSize = 0 then
      slotRecs[slotIdx] := AType17List[i];
  end;
  SetLength(AInfo.Modules, slotCount);
  for i := 0 to slotCount - 1 do
  begin
    MemSmbType17ToModule(slotRecs[i], AInfo.DramType, AInfo.DramSpeedMts, modInfo);
    MemUpdateDramSpec(AInfo, modInfo.DramType, modInfo.SpeedMts);
    AInfo.Modules[i] := modInfo;
  end;
end;

function MemSmbGetString(const AData: PByte; const ALength: Integer;
  const AStringIndex: Byte): string;
var
  p: PAnsiChar;
  i: Integer;
begin
  Result := '';
  if (AStringIndex = 0) or (AData = nil) or (ALength <= 0) then
    Exit;
  p := PAnsiChar(@AData[ALength]);
  for i := 1 to AStringIndex - 1 do
  begin
    while p^ <> #0 do
      Inc(p);
    Inc(p);
  end;
  Result := Trim(string(p));
end;

function MemSmbMemoryTypeText(const AType: Byte): string;
begin
  case AType of
    $03: Result := 'DRAM';
    $04: Result := 'EDRAM';
    $07: Result := 'VRAM';
    $08: Result := 'SRAM';
    $12: Result := 'DDR';
    $13: Result := 'DDR2';
    $18: Result := 'DDR3';
    $1A: Result := 'DDR4';
    $22: Result := 'DDR5';
    $1B: Result := 'LPDDR';
    $1C: Result := 'LPDDR2';
    $1D: Result := 'LPDDR3';
    $1E: Result := 'LPDDR4';
    $23: Result := 'LPDDR5';
  else
    Result := '';
  end;
end;

function MemSmbMemoryTypeFromDetail(const ADetail: Word): string;
begin
  if (ADetail and (1 shl 13)) <> 0 then
    Result := 'DDR5'
  else if (ADetail and (1 shl 12)) <> 0 then
    Result := 'DDR4'
  else if (ADetail and (1 shl 11)) <> 0 then
    Result := 'DDR3'
  else if (ADetail and (1 shl 10)) <> 0 then
    Result := 'DDR2'
  else if (ADetail and (1 shl 7)) <> 0 then
    Result := 'DDR'
  else
    Result := '';
end;

function MemSmbResolveType17DeviceSize(const AData: PByte; const ALength: Integer): UInt64;
var
  sizeWord: Word;
  extSize: DWORD;
  qSize: UInt64;
begin
  Result := 0;
  if (AData = nil) or (ALength < 14) then
    Exit;
  sizeWord := PWord(@AData[12])^;
  case sizeWord of
    0, $FFFF:
      ;
    $7FFF:
      begin
        if ALength >= 32 then
        begin
          extSize := PDWORD(@AData[28])^;
          if (extSize and $7FFFFFFF) > 0 then
            Result := UInt64(extSize and $7FFFFFFF) shl 20;
        end;
      end;
  else
    if (sizeWord and $8000) <> 0 then
      Result := UInt64(sizeWord and $7FFF) shl 10
    else
      Result := UInt64(sizeWord) shl 20;
  end;
  if (Result = 0) and (ALength >= 68) then
  begin
    qSize := PUInt64(@AData[60])^;
    if (qSize > 0) and (qSize <> UInt64($FFFFFFFFFFFFFFFF)) then
      Result := qSize;
  end;
end;

function MemSmbResolveType17SpeedMts(const AData: PByte; const ALength: Integer): Cardinal;
var
  speedWord, cfgWord: Word;
  extVal: DWORD;
begin
  Result := 0;
  if (AData = nil) or (ALength < 23) then
    Exit;
  speedWord := PWord(@AData[21])^;
  if ALength >= 34 then
    cfgWord := PWord(@AData[32])^
  else
    cfgWord := 0;
  if (cfgWord > 0) and (cfgWord <> $FFFF) then
    Result := cfgWord
  else if (speedWord > 0) and (speedWord <> $FFFF) then
    Result := speedWord;
  if (Result = 0) and (ALength >= 92) then
  begin
    if cfgWord = $FFFF then
    begin
      extVal := PDWORD(@AData[88])^;
      if (extVal and $7FFFFFFF) > 0 then
        Result := extVal and $7FFFFFFF;
    end
    else if speedWord = $FFFF then
    begin
      extVal := PDWORD(@AData[84])^;
      if (extVal and $7FFFFFFF) > 0 then
        Result := extVal and $7FFFFFFF;
    end
    else
    begin
      extVal := PDWORD(@AData[88])^;
      if (extVal and $7FFFFFFF) > 0 then
        Result := extVal and $7FFFFFFF;
      if Result = 0 then
      begin
        extVal := PDWORD(@AData[84])^;
        if (extVal and $7FFFFFFF) > 0 then
          Result := extVal and $7FFFFFFF;
      end;
    end;
  end;
end;

function MemSmbParseType17Voltage(const AData: PByte; const ALength: Integer): Double;
var
  cfgMv, minMv: Word;
begin
  Result := 0;
  if (AData = nil) or (ALength < 48) then
    Exit;
  cfgMv := PWord(@AData[46])^;
  if cfgMv > 0 then
    Exit(cfgMv / 1000.0);
  minMv := PWord(@AData[42])^;
  if minMv > 0 then
    Result := minMv / 1000.0;
end;

procedure MemSmbParseType16(const AData: PByte; const ALength: Integer; var AInfo: TMemStaticInfo);
var
  maxCap: DWORD;
  extCap: UInt64;
begin
  if (AData = nil) or (ALength < 15) then
    Exit;
  if PWord(@AData[13])^ > AInfo.SlotCount then
    AInfo.SlotCount := PWord(@AData[13])^;
  maxCap := PDWORD(@AData[7])^;
  if maxCap = $80000000 then
  begin
    if ALength >= 23 then
    begin
      extCap := PUInt64(@AData[15])^;
      if extCap > 0 then
        AInfo.SpecText := MemFormatBytes(extCap);
    end;
  end
  else if (maxCap > 0) and ((maxCap and $80000000) = 0) then
    AInfo.SpecText := MemFormatBytes(UInt64(maxCap) * 1024);
end;

procedure MemSmbParseType17(const AData: PByte; const ALength: Integer;
  var ARec: TType17Rec);
var
  typeDetail: Word;
  jedecId: Word;
begin
  if (AData = nil) or (ALength < 22) then
    Exit;
  ARec.DeviceSize := MemSmbResolveType17DeviceSize(AData, ALength);
  if ALength >= 16 then
    ARec.DeviceLocator := MemSmbGetString(AData, ALength, AData[16]);
  if ALength >= 17 then
    ARec.BankLocator := MemSmbGetString(AData, ALength, AData[17]);
  if ALength >= 19 then
    ARec.DeviceType := MemSmbMemoryTypeText(AData[18]);
  if MemIsUnknownLabel(ARec.DeviceType) and (ALength >= 21) then
  begin
    typeDetail := PWord(@AData[19])^;
    ARec.DeviceType := MemSmbMemoryTypeFromDetail(typeDetail);
  end;
  ARec.SpeedMts := MemSmbResolveType17SpeedMts(AData, ALength);
  ARec.VoltageV := MemSmbParseType17Voltage(AData, ALength);
  if ALength >= 24 then
    ARec.Manufacturer := MemSmbGetString(AData, ALength, AData[23]);
  if ALength >= 27 then
    ARec.PartNumber := MemSmbGetString(AData, ALength, AData[26]);
  if MemIsUnknownLabel(ARec.Manufacturer) and (ALength >= 46) then
  begin
    jedecId := PWord(@AData[44])^;
    ARec.Manufacturer := MemJedecManufacturerText(jedecId);
  end;
  ARec.Manufacturer := MemResolveManufacturerName(ARec.Manufacturer, ARec.PartNumber);
end;

procedure MemSmbSkipStringTable(var AOffset: DWORD; const ATable: PByte; const ATableLen: DWORD);
begin
  while AOffset < ATableLen do
  begin
    while (AOffset < ATableLen) and (ATable[AOffset] <> 0) do
      Inc(AOffset);
    if AOffset >= ATableLen then
      Break;
    Inc(AOffset);
    if (AOffset < ATableLen) and (ATable[AOffset] = 0) then
    begin
      Inc(AOffset);
      Break;
    end;
  end;
end;

procedure MemSmbApplyTables(const ATable: PByte; const ATableLen: DWORD; var AInfo: TMemStaticInfo);
var
  offset: DWORD;
  structType, structLen: Byte;
  cur: TType17Rec;
  type17List: TType17ModuleList;
begin
  SetLength(type17List, 0);
  MemSmbClearType17(cur);
  offset := 0;
  while offset + 4 <= ATableLen do
  begin
    structType := ATable[offset];
    structLen := ATable[offset + 1];
    if structLen < 4 then
      Break;
    if offset + structLen > ATableLen then
      Break;
    case structType of
      16:
        MemSmbParseType16(@ATable[offset], structLen, AInfo);
      17:
        begin
          MemSmbClearType17(cur);
          MemSmbParseType17(@ATable[offset], structLen, cur);
          if not MemIsUnknownLabel(cur.DeviceType) or (cur.SpeedMts > 0) then
            MemUpdateDramSpec(AInfo, cur.DeviceType, cur.SpeedMts);
          MemUpdateDramVoltage(AInfo, cur.VoltageV);
          MemSmbStoreType17(cur, type17List);
        end;
    end;
    Inc(offset, structLen);
    MemSmbSkipStringTable(offset, ATable, ATableLen);
    if structType = 127 then
      Break;
  end;
  MemSmbCollectDramSpec(type17List, AInfo);
  MemSmbBuildSlotModules(type17List, AInfo);
  AInfo.InstalledTotal := MemSmbSumType17Bytes(type17List);
end;

procedure MemSmbLoadFromFirmware(var AInfo: TMemStaticInfo);
var
  size: DWORD;
  buf: Pointer;
  tableLen: DWORD;
begin
  size := GetSystemFirmwareTable(DWORD($52534D42), 0, nil, 0);
  if size = 0 then
    Exit;
  GetMem(buf, size);
  try
    if GetSystemFirmwareTable(DWORD($52534D42), 0, buf, size) <> size then
      Exit;
    if size < 8 then
      Exit;
    tableLen := PDWORD(Pointer(LongWord(buf) + 4))^;
    if (tableLen = 0) or (8 + tableLen > size) then
      Exit;
    MemSmbApplyTables(Pointer(LongWord(buf) + 8), tableLen, AInfo);
  finally
    FreeMem(buf);
  end;
end;

function MemNativeExplainNoTiming(const AModule: TMemModuleInfo; const ASpdDiag: TStringList;
  ASlotIndex: Integer): string;
var
  i: Integer;
  slotPrefix, line: string;
  reasons: TStringList;
begin
  slotPrefix := '卡槽' + IntToStr(ASlotIndex) + '：';
  reasons := TStringList.Create;
  try
    if ASpdDiag <> nil then
      for i := 0 to ASpdDiag.Count - 1 do
      begin
        line := ASpdDiag[i];
        if Pos(slotPrefix, line) = 1 then
          reasons.Add(Trim(Copy(line, Length(slotPrefix) + 1, MaxInt)));
      end;
    if reasons.Count > 0 then
    begin
      Result := reasons[0];
      for i := 1 to reasons.Count - 1 do
        Result := Result + '；' + reasons[i];
      Exit;
    end;
    if MemInferCasFromText(AModule.PartNumber) > 0 then
      Exit('型号含 CL 信息但未能写入显示行（卡槽映射不一致）');
    if not MemModuleHasSpec(AModule) then
      Exit('SMBIOS 仅提供容量，无频率/型号文本；SPD 亦未能补充时序')
    else
      Exit('SMBIOS 不含 CAS 时序，型号「' + Trim(AModule.PartNumber) + '」无法从文本推断 CL');
  finally
    reasons.Free;
  end;
end;

procedure MemNativeLogTimingFailures(const AInfo: TMemStaticInfo; const ASpdDiag: TStringList;
  AStart: TDateTime; AElapsedMs: Cardinal);
var
  i, failCount, slotIndex: Integer;
  sl: TStringList;
begin
  if Length(AInfo.Modules) = 0 then
    Exit;
  sl := TStringList.Create;
  try
    if ASpdDiag <> nil then
      for i := 0 to ASpdDiag.Count - 1 do
        if Pos('卡槽', ASpdDiag[i]) <> 1 then
          sl.Add(ASpdDiag[i]);
    failCount := 0;
    for i := 0 to High(AInfo.Modules) do
    begin
      if not MemModuleIsPopulated(AInfo.Modules[i]) or MemModuleHasTiming(AInfo.Modules[i]) then
        Continue;
      Inc(failCount);
      slotIndex := i + 1;
      sl.Add(MemFormatModuleLine(slotIndex, AInfo.Modules[i]));
      sl.Add('  原因：' + MemNativeExplainNoTiming(AInfo.Modules[i], ASpdDiag, slotIndex));
    end;
    if failCount = 0 then
      Exit;
    SafeLogFetch('get', '内存时序', Format('%d 条内存未获取到时序（CL）', [failCount]),
      AStart, AElapsedMs, False, Trim(sl.Text));
  finally
    sl.Free;
  end;
end;

function MemNativeQueryStaticInfo: TMemStaticInfo;
var
  memStatus: TMemoryStatusEx;
  spdDiag: TStringList;
  startTime: TDateTime;
  elapsedMs: Cardinal;
begin
  startTime := Now;
  MemInitStaticInfo(Result);
  memStatus.dwLength := SizeOf(memStatus);
  if GlobalMemoryStatusEx(memStatus) then
  begin
    Result.PhysTotal := memStatus.ullTotalPhys;
    Result.PhysFree := memStatus.ullAvailPhys;
    Result.PageFileTotal := memStatus.ullTotalPageFile;
    Result.PageFileAvail := memStatus.ullAvailPageFile;
    if memStatus.dwMemoryLoad <= 100 then
      Result.UsagePct := memStatus.dwMemoryLoad;
  end;
  MemSmbLoadFromFirmware(Result);
  spdDiag := TStringList.Create;
  try
    MemSpdTryEnrich(Result, spdDiag);
    MemApplyDramSpecToModules(Result);
    elapsedMs := Cardinal(MilliSecondsBetween(Now, startTime));
    MemNativeLogTimingFailures(Result, spdDiag, startTime, elapsedMs);
  finally
    spdDiag.Free;
  end;
end;

end.
