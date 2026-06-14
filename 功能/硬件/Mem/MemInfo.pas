unit MemInfo;

{
  内存悬停提示：MemInfoNative（GlobalMemoryStatusEx + SMBIOS Type 16/17）。
}

interface

uses
  SysUtils, Windows;

const
  cMemDash = '--';
  cMem16GB = UInt64(16) * 1024 * 1024 * 1024;

type
  TMemModuleInfo = record
    DramType: string;
    SpeedMts: Cardinal;
    CasLatency: Integer;
    SizeBytes: UInt64;
    Manufacturer: string;
    PartNumber: string;
  end;

  TMemModuleArray = array of TMemModuleInfo;

  TMemStaticInfo = record
    UsagePct: Integer;
    PhysTotal: UInt64;
    InstalledTotal: UInt64;
    PhysFree: UInt64;
    PageFileTotal: UInt64;
    PageFileAvail: UInt64;
    SpecText: string;
    DramType: string;
    DramSpeedMts: Cardinal;
    DramVoltageV: Double;
    ChannelCount: Integer;
    SlotCount: Cardinal;
    Modules: TMemModuleArray;
  end;

  { 0-based 物理卡槽下标，按双通道推荐顺序排列（4 槽板 2 条：槽2→槽4） }
  TMemSlotOrder = array of Integer;

function MemIsUnknownLabel(const AText: string): Boolean;
function MemGuessSlotCount(APhysTotal: UInt64): Integer;
function MemEstimateInstalledCount(ASlotCount: Integer; APhysTotal: UInt64): Integer;
function MemDualChannelSlotOrder(ASlotCount, AInstalledCount: Integer): TMemSlotOrder;
procedure MemModuleClear(out AModule: TMemModuleInfo);
function MemModuleIsPopulated(const AModule: TMemModuleInfo): Boolean;
function MemModuleHasSpec(const AModule: TMemModuleInfo): Boolean;
function MemModuleHasTiming(const AModule: TMemModuleInfo): Boolean;
procedure MemEnsureModuleSlots(var AModules: TMemModuleArray; ATargetSlots: Integer);
procedure MemUpdateDramSpec(var AInfo: TMemStaticInfo; const AType: string; ASpeedMts: Cardinal);
procedure MemUpdateDramVoltage(var AInfo: TMemStaticInfo; AVoltageV: Double);
function MemFormatSpecPrefix(const ADramType: string; ASpeedMts: Cardinal): string;
function MemFormatModuleDetail(const ADramType: string; ASpeedMts: Cardinal;
  ACas: Integer; ASizeBytes: UInt64; const AMfgName: string): string;
function MemFormatModuleLine(ASlotIndex: Integer; const AModule: TMemModuleInfo): string;
function MemFormatVoltageText(AVoltageV: Double): string;
function MemCountInstalledModules(const AModules: TMemModuleArray): Integer;
function MemFormatDualChannelText(AChannelCount, AInstalledCount: Integer): string;
function MemInferDramTypeFromText(const AText: string): string;
function MemInferSpeedMtsFromText(const AText: string): Cardinal;
function MemResolveManufacturerName(const AManufacturer, APartNumber: string): string;
function MemInferCasFromText(const AText: string): Integer;
procedure MemApplyDramSpecToModules(var AInfo: TMemStaticInfo);

procedure MemInitStaticInfo(out AInfo: TMemStaticInfo);
procedure MemFreeStaticInfo(var AInfo: TMemStaticInfo);
function MemFormatBytes(const ABytes: UInt64): string;

procedure MemPreloadHintData;
procedure MemEnrichStaticInfo;
function MemFormatTooltip(const AUsagePctText: string): string;

implementation

uses
  MemInfoNative, MemPartNumberLookup;

var
  GStaticLoaded: Boolean;
  GStaticInfo: TMemStaticInfo;
  GStaticLoadLock: TRTLCriticalSection;
  GStaticLoading: Boolean;
  GSpdEnriched: Boolean;

function MemGuessSlotCount(APhysTotal: UInt64): Integer;
begin
  if APhysTotal >= cMem16GB then
    Result := 4
  else if APhysTotal > 0 then
    Result := 2
  else
    Result := 0;
end;

function MemEstimateInstalledCount(ASlotCount: Integer; APhysTotal: UInt64): Integer;
var
  gb: UInt64;
begin
  Result := 1;
  if APhysTotal = 0 then
    Exit;
  gb := (APhysTotal + (1024 * 1024 * 1024 - 1)) div (1024 * 1024 * 1024);
  if gb >= 48 then
    Result := 4
  else if gb >= 20 then
    Result := 2
  else
    Result := 1;
  if Result > ASlotCount then
    Result := ASlotCount;
  if Result < 1 then
    Result := 1;
end;

function MemDualChannelSlotOrder(ASlotCount, AInstalledCount: Integer): TMemSlotOrder;
var
  i, n: Integer;
begin
  SetLength(Result, 0);
  if (AInstalledCount <= 0) or (ASlotCount <= 0) then
    Exit;
  n := AInstalledCount;
  if n > ASlotCount then
    n := ASlotCount;
  SetLength(Result, n);
  if (ASlotCount = 4) and (n = 1) then
  begin
    Result[0] := 1;
    Exit;
  end;
  if (ASlotCount = 4) and (n = 2) then
  begin
    Result[0] := 1;
    Result[1] := 3;
    Exit;
  end;
  if (ASlotCount = 4) and (n = 3) then
  begin
    Result[0] := 1;
    Result[1] := 3;
    Result[2] := 0;
    Exit;
  end;
  for i := 0 to n - 1 do
    Result[i] := i;
end;

function MemIsUnknownLabel(const AText: string): Boolean;
var
  s: string;
begin
  s := UpperCase(Trim(AText));
  Result := (s = '') or (s = 'UNKNOWN') or (s = '未知') or (s = 'N/A') or (s = 'NOT SPECIFIED') or
    (s = 'NONE') or (s = '0000') or (s = 'TO BE FILLED BY O.E.M.');
end;

procedure MemModuleClear(out AModule: TMemModuleInfo);
begin
  AModule.DramType := '';
  AModule.SpeedMts := 0;
  AModule.CasLatency := 0;
  AModule.SizeBytes := 0;
  AModule.Manufacturer := '';
  AModule.PartNumber := '';
end;

function MemModuleIsPopulated(const AModule: TMemModuleInfo): Boolean;
begin
  Result := AModule.SizeBytes > 0;
end;

function MemModuleHasSpec(const AModule: TMemModuleInfo): Boolean;
begin
  Result := (not MemIsUnknownLabel(AModule.DramType)) or (AModule.SpeedMts > 0);
end;

function MemModuleHasTiming(const AModule: TMemModuleInfo): Boolean;
begin
  Result := AModule.CasLatency > 0;
end;

procedure MemEnsureModuleSlots(var AModules: TMemModuleArray; ATargetSlots: Integer);
var
  i, oldLen: Integer;
begin
  if ATargetSlots <= 0 then
    Exit;
  oldLen := Length(AModules);
  if oldLen >= ATargetSlots then
    Exit;
  SetLength(AModules, ATargetSlots);
  for i := oldLen to ATargetSlots - 1 do
    MemModuleClear(AModules[i]);
end;

procedure MemUpdateDramSpec(var AInfo: TMemStaticInfo; const AType: string; ASpeedMts: Cardinal);
var
  t: string;
begin
  t := Trim(AType);
  if (t <> '') and not MemIsUnknownLabel(t) then
  begin
    if (AInfo.DramType = '') or
      ((Pos('DDR', UpperCase(t)) > 0) and (Pos('DDR', UpperCase(AInfo.DramType)) = 0)) then
      AInfo.DramType := t;
  end;
  if ASpeedMts > AInfo.DramSpeedMts then
    AInfo.DramSpeedMts := ASpeedMts;
end;

procedure MemUpdateDramVoltage(var AInfo: TMemStaticInfo; AVoltageV: Double);
begin
  if AVoltageV <= 0 then
    Exit;
  if (AInfo.DramVoltageV <= 0) or (Abs(AInfo.DramVoltageV - AVoltageV) < 0.001) then
    AInfo.DramVoltageV := AVoltageV
  else if AVoltageV > AInfo.DramVoltageV then
    AInfo.DramVoltageV := AVoltageV;
end;

function MemFormatSpecPrefix(const ADramType: string; ASpeedMts: Cardinal): string;
begin
  Result := '';
  if (ADramType <> '') and (ASpeedMts > 0) then
    Result := ADramType + '-' + IntToStr(ASpeedMts) + 'MT/s '
  else if ADramType <> '' then
    Result := ADramType + ' '
  else if ASpeedMts > 0 then
    Result := IntToStr(ASpeedMts) + 'MT/s ';
end;

function MemFormatModuleDetail(const ADramType: string; ASpeedMts: Cardinal;
  ACas: Integer; ASizeBytes: UInt64; const AMfgName: string): string;
var
  dramType, detail: string;
begin
  dramType := ADramType;
  if MemIsUnknownLabel(dramType) then
    dramType := '';
  detail := MemFormatSpecPrefix(dramType, ASpeedMts);
  if ACas > 0 then
    detail := detail + 'CL' + IntToStr(ACas) + ' ';
  if ASizeBytes > 0 then
    detail := detail + MemFormatBytes(ASizeBytes);
  detail := Trim(detail);
  if AMfgName <> '' then
    detail := Trim(detail + ' ' + AMfgName);
  Result := detail;
end;

function MemFormatModuleLine(ASlotIndex: Integer; const AModule: TMemModuleInfo): string;
var
  mfgName: string;
begin
  if not MemModuleIsPopulated(AModule) then
    Result := '卡槽' + IntToStr(ASlotIndex) + '：' + cMemDash
  else
  begin
    mfgName := MemResolveManufacturerName(AModule.Manufacturer, AModule.PartNumber);
    Result := '卡槽' + IntToStr(ASlotIndex) + '：' +
      MemFormatModuleDetail(AModule.DramType, AModule.SpeedMts, AModule.CasLatency,
        AModule.SizeBytes, mfgName);
  end;
end;

function MemInferDramTypeFromText(const AText: string): string;
var
  s: string;
begin
  Result := '';
  s := UpperCase(AText);
  if Pos('DDR5', s) > 0 then
    Result := 'DDR5'
  else if Pos('DDR4', s) > 0 then
    Result := 'DDR4'
  else if Pos('DDR3', s) > 0 then
    Result := 'DDR3'
  else if Pos('DDR2', s) > 0 then
    Result := 'DDR2'
  else if Pos('LPDDR5', s) > 0 then
    Result := 'LPDDR5'
  else if Pos('LPDDR4', s) > 0 then
    Result := 'LPDDR4';
end;

function MemInferSpeedMtsFromText(const AText: string): Cardinal;
var
  s, token: string;
  i, p, n, best: Integer;
begin
  Result := 0;
  best := 0;
  s := UpperCase(AText);
  p := Pos('PC4-', s);
  if p > 0 then
  begin
    token := Copy(s, p + 4, MaxInt);
    i := 1;
    while (i <= Length(token)) and CharInSet(token[i], ['0'..'9']) do
      Inc(i);
    if TryStrToInt(Copy(token, 1, i - 1), n) and (n >= 800) and (n <= 10000) then
      Exit(Cardinal(n));
  end;
  p := Pos('PC5-', s);
  if p > 0 then
  begin
    token := Copy(s, p + 4, MaxInt);
    i := 1;
    while (i <= Length(token)) and CharInSet(token[i], ['0'..'9']) do
      Inc(i);
    if TryStrToInt(Copy(token, 1, i - 1), n) and (n >= 800) and (n <= 12000) then
      Exit(Cardinal(n));
  end;
  i := 1;
  while i <= Length(s) do
  begin
    if CharInSet(s[i], ['0'..'9']) then
    begin
      p := i;
      while (i <= Length(s)) and CharInSet(s[i], ['0'..'9']) do
        Inc(i);
      if TryStrToInt(Copy(s, p, i - p), n) and (n >= 1600) and (n <= 12000) then
        if n > best then
          best := n;
      Continue;
    end;
    Inc(i);
  end;
  if best > 0 then
    Result := Cardinal(best);
end;

function MemTextHasCjk(const AText: string): Boolean;
var
  i: Integer;
  c: Word;
begin
  for i := 1 to Length(AText) do
  begin
    c := Word(Ord(AText[i]));
    if (c >= $4E00) and (c <= $9FFF) then
      Exit(True);
  end;
  Result := False;
end;

function MemResolveManufacturerName(const AManufacturer, APartNumber: string): string;
var
  localized: string;
begin
  Result := Trim(AManufacturer);
  if (Result <> '') and not MemIsUnknownLabel(Result) then
  begin
    if not MemTextHasCjk(Result) then
    begin
      localized := MemPartNumberManufacturerText(Result);
      if localized <> '' then
        Result := localized;
    end;
    Exit;
  end;
  Result := MemPartNumberManufacturerText(APartNumber);
end;

function MemInferCasFromText(const AText: string): Integer;
var
  s: string;
  i, p, n: Integer;
begin
  Result := 0;
  s := UpperCase(Trim(AText));
  if s = '' then
    Exit;
  p := Pos('CL', s);
  if p > 0 then
  begin
    i := p + 2;
    while (i <= Length(s)) and CharInSet(s[i], ['-', ' ']) do
      Inc(i);
    if TryStrToInt(Copy(s, i, 2), n) and (n >= 2) and (n <= 80) then
      Exit(n);
  end;
  for i := 1 to Length(s) - 2 do
    if (s[i] = 'C') and CharInSet(s[i + 1], ['0'..'9']) and CharInSet(s[i + 2], ['0'..'9']) then
    begin
      if (i > 1) and CharInSet(s[i - 1], ['0'..'9']) and
        TryStrToInt(Copy(s, i + 1, 2), n) and (n >= 5) and (n <= 80) then
        Exit(n);
    end;
end;

function MemFormatVoltageText(AVoltageV: Double): string;
begin
  if AVoltageV <= 0 then
    Result := cMemDash
  else
    Result := StringReplace(Format('%.2f', [AVoltageV]), ',', '.', [rfReplaceAll]) + ' V';
end;

function MemCountInstalledModules(const AModules: TMemModuleArray): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(AModules) do
    if MemModuleIsPopulated(AModules[i]) then
      Inc(Result);
end;

function MemFormatDualChannelText(AChannelCount, AInstalledCount: Integer): string;
begin
  if AInstalledCount <= 0 then
    Result := cMemDash
  else if AInstalledCount = 1 then
    Result := '单通道'
  else if AChannelCount >= 2 then
    Result := '双通道'
  else
    Result := '多通道';
end;

function MemInferVoltageFromDramType(const ADramType: string): Double;
var
  s: string;
begin
  Result := 0;
  s := UpperCase(Trim(ADramType));
  if s = '' then
    Exit;
  if Pos('DDR5', s) > 0 then
    Result := 1.10
  else if Pos('LPDDR5', s) > 0 then
    Result := 1.05
  else if Pos('DDR4', s) > 0 then
    Result := 1.20
  else if Pos('LPDDR4', s) > 0 then
    Result := 1.10
  else if Pos('DDR3', s) > 0 then
    Result := 1.50
  else if Pos('LPDDR3', s) > 0 then
    Result := 1.20
  else if Pos('DDR2', s) > 0 then
    Result := 1.80;
end;

procedure MemApplyDramSpecToModules(var AInfo: TMemStaticInfo);
var
  i: Integer;
begin
  for i := 0 to High(AInfo.Modules) do
  begin
    if not MemModuleIsPopulated(AInfo.Modules[i]) then
      Continue;
    if MemIsUnknownLabel(AInfo.Modules[i].DramType) and (AInfo.DramType <> '') then
      AInfo.Modules[i].DramType := AInfo.DramType;
    if (AInfo.Modules[i].SpeedMts = 0) and (AInfo.DramSpeedMts > 0) then
      AInfo.Modules[i].SpeedMts := AInfo.DramSpeedMts;
    if AInfo.Modules[i].CasLatency = 0 then
      AInfo.Modules[i].CasLatency := MemInferCasFromText(AInfo.Modules[i].PartNumber);
  end;
end;

procedure MemInitStaticLoadLock;
begin
  InitializeCriticalSection(GStaticLoadLock);
end;

procedure MemDoneStaticLoadLock;
begin
  DeleteCriticalSection(GStaticLoadLock);
end;

procedure MemInitStaticInfo(out AInfo: TMemStaticInfo);
begin
  AInfo.UsagePct := -1;
  AInfo.PhysTotal := 0;
  AInfo.InstalledTotal := 0;
  AInfo.PhysFree := 0;
  AInfo.PageFileTotal := 0;
  AInfo.PageFileAvail := 0;
  AInfo.SpecText := '';
  AInfo.DramType := '';
  AInfo.DramSpeedMts := 0;
  AInfo.DramVoltageV := 0;
  AInfo.ChannelCount := 0;
  AInfo.SlotCount := 0;
  SetLength(AInfo.Modules, 0);
end;

procedure MemFreeStaticInfo(var AInfo: TMemStaticInfo);
begin
  SetLength(AInfo.Modules, 0);
  AInfo.SpecText := '';
  AInfo.DramType := '';
  AInfo.DramSpeedMts := 0;
  AInfo.DramVoltageV := 0;
  AInfo.ChannelCount := 0;
end;

function MemFormatBytes(const ABytes: UInt64): string;
var
  gb, mb, kb: Double;
begin
  if ABytes = 0 then
    Result := '0B'
  else if ABytes >= 1024 * 1024 * 1024 then
  begin
    gb := ABytes / (1024 * 1024 * 1024);
    if Abs(gb - Round(gb)) < 0.05 then
      Result := IntToStr(Round(gb)) + 'GB'
    else
      Result := StringReplace(Format('%.1f', [gb]), ',', '.', [rfReplaceAll]) + 'GB';
  end
  else if ABytes >= 1024 * 1024 then
  begin
    mb := ABytes / (1024 * 1024);
    if Abs(mb - Round(mb)) < 0.05 then
      Result := IntToStr(Round(mb)) + 'MB'
    else
      Result := StringReplace(Format('%.1f', [mb]), ',', '.', [rfReplaceAll]) + 'MB';
  end
  else
  begin
    kb := ABytes / 1024;
    if kb < 1 then
      Result := IntToStr(ABytes) + 'B'
    else if Abs(kb - Round(kb)) < 0.05 then
      Result := IntToStr(Round(kb)) + 'KB'
    else
      Result := StringReplace(Format('%.1f', [kb]), ',', '.', [rfReplaceAll]) + 'KB';
  end;
end;

function AppendLine(const ALines, ALine: string): string;
begin
  if ALine = '' then
    Result := ALines
  else if ALines = '' then
    Result := ALine
  else
    Result := ALines + sLineBreak + ALine;
end;

procedure MemTakeStaticInfo(var AInfo: TMemStaticInfo);
begin
  MemFreeStaticInfo(GStaticInfo);
  GStaticInfo := AInfo;
  SetLength(AInfo.Modules, 0);
  AInfo.SpecText := '';
  AInfo.UsagePct := -1;
  AInfo.PhysTotal := 0;
  AInfo.InstalledTotal := 0;
  AInfo.PhysFree := 0;
  AInfo.SlotCount := 0;
end;

procedure MemLoadStaticInfo;
var
  nativeInfo: TMemStaticInfo;
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
      nativeInfo := MemNativeQueryStaticInfo;
      if (nativeInfo.PhysTotal > 0) or (nativeInfo.UsagePct >= 0) or
        (nativeInfo.SlotCount > 0) or (Length(nativeInfo.Modules) > 0) then
        MemTakeStaticInfo(nativeInfo)
      else
      begin
        MemFreeStaticInfo(nativeInfo);
        MemFreeStaticInfo(GStaticInfo);
        MemInitStaticInfo(GStaticInfo);
      end;
      GStaticLoaded := True;
    finally
      GStaticLoading := False;
    end;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
end;

procedure MemPreloadHintData;
begin
  MemLoadStaticInfo;
end;

procedure MemEnrichStaticInfo;
begin
  if GSpdEnriched then
    Exit;
  MemLoadStaticInfo;
  if not GStaticLoaded then
    Exit;
  EnterCriticalSection(GStaticLoadLock);
  try
    if GSpdEnriched then
      Exit;
    MemNativeEnrichSpdInfo(GStaticInfo);
    GSpdEnriched := True;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
end;

function MemFormatTooltip(const AUsagePctText: string): string;
var
  usageText, voltageText, channelText, slotSummaryText: string;
  memTotal, memInUse, memAvail: UInt64;
  i, installedCount, channelCount: Integer;
  modules: TMemModuleArray;
  info: TMemStaticInfo;
  usagePct: Integer;
  physTotal, installedTotal, physFree: UInt64;
  specText: string;
  dramType: string;
  dramVoltage: Double;
  slotCount: Cardinal;
begin
  if not GStaticLoaded then
  begin
    if (AUsagePctText <> '') and (AUsagePctText <> cMemDash) then
      usageText := AUsagePctText
    else
      usageText := cMemDash;
    Exit('使用率：' + usageText + sLineBreak +
      '（详细信息加载中…）');
  end;
  EnterCriticalSection(GStaticLoadLock);
  try
    usagePct := GStaticInfo.UsagePct;
    physTotal := GStaticInfo.PhysTotal;
    installedTotal := GStaticInfo.InstalledTotal;
    physFree := GStaticInfo.PhysFree;
    specText := GStaticInfo.SpecText;
    dramType := GStaticInfo.DramType;
    dramVoltage := GStaticInfo.DramVoltageV;
    channelCount := GStaticInfo.ChannelCount;
    slotCount := GStaticInfo.SlotCount;
    modules := GStaticInfo.Modules;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
  MemInitStaticInfo(info);
  info.UsagePct := usagePct;
  info.PhysTotal := physTotal;
  info.InstalledTotal := installedTotal;
  info.PhysFree := physFree;
  info.SpecText := specText;
  info.DramType := dramType;
  info.DramVoltageV := dramVoltage;
  info.ChannelCount := channelCount;
  info.SlotCount := slotCount;
  info.Modules := modules;
  if (AUsagePctText <> '') and (AUsagePctText <> cMemDash) then
    usageText := AUsagePctText
  else if info.UsagePct >= 0 then
    usageText := IntToStr(info.UsagePct) + '%'
  else
    usageText := cMemDash;

  Result := '使用率：' + usageText;

  if info.InstalledTotal > 0 then
    memTotal := info.InstalledTotal
  else
    memTotal := info.PhysTotal;

  if info.PhysTotal > 0 then
  begin
    if info.PhysFree > info.PhysTotal then
      memInUse := info.PhysTotal
    else
      memInUse := info.PhysTotal - info.PhysFree;
  end
  else
    memInUse := 0;

  if memTotal > 0 then
  begin
    if memInUse > memTotal then
      memAvail := 0
    else
      memAvail := memTotal - memInUse;
    Result := AppendLine(Result, '已用：' + MemFormatBytes(memInUse) + ' / ' + MemFormatBytes(memTotal));
    Result := AppendLine(Result, '可用：' + MemFormatBytes(memAvail));
  end
  else
  begin
    Result := AppendLine(Result, '已用：' + cMemDash);
    Result := AppendLine(Result, '可用：' + cMemDash);
  end;

  Result := AppendLine(Result, '');
  if dramVoltage <= 0 then
    dramVoltage := MemInferVoltageFromDramType(dramType);
  voltageText := MemFormatVoltageText(dramVoltage);
  Result := AppendLine(Result, '工作电压：' + voltageText);

  installedCount := MemCountInstalledModules(info.Modules);
  if channelCount <= 0 then
  begin
    if installedCount >= 2 then
      channelCount := 2
    else if installedCount = 1 then
      channelCount := 1;
  end;
  channelText := MemFormatDualChannelText(channelCount, installedCount);
  Result := AppendLine(Result, '通道：' + channelText);

  if info.SpecText <> '' then
    Result := AppendLine(Result, '最大可扩展：' + info.SpecText);

  if info.SlotCount > 0 then
  begin
    if installedCount > 0 then
      slotSummaryText := IntToStr(installedCount) + ' / ' + IntToStr(info.SlotCount) + ' 槽'
    else
      slotSummaryText := '0 / ' + IntToStr(info.SlotCount) + ' 槽';
    Result := AppendLine(Result, '已装：' + slotSummaryText);
  end;

  Result := AppendLine(Result, '');
  if Length(info.Modules) = 0 then
    Result := AppendLine(Result, cMemDash)
  else
    for i := 0 to High(info.Modules) do
      Result := AppendLine(Result, MemFormatModuleLine(i + 1, info.Modules[i]));
end;

initialization
  MemInitStaticLoadLock;
  MemInitStaticInfo(GStaticInfo);

finalization
  MemFreeStaticInfo(GStaticInfo);
  MemDoneStaticLoadLock;

end.
