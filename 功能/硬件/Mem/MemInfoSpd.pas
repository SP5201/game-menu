unit MemInfoSpd;

{
  内存 SPD：PCI 扫描 SMBus 控制器 + SMBus 读 EEPROM（CPU-Z / HWiNFO 同类路径）。
  经 PawnIO LpcIO 做端口 I/O，不依赖 WMI / 注册表。
}

interface

uses
  MemInfo, Classes;

procedure MemSpdTryEnrich(var AInfo: TMemStaticInfo; ADiag: TStringList = nil);

implementation

uses
  Windows, SysUtils, PawnIo, MemJedecLookup;

const
  cIsaBusMutex = 'Global\Access_ISABUS.HTP.Method';
  cPciConfigAddrPort = $CF8;
  cPciConfigDataPort = $CFC;
  cSmbClassCode = $0C05;
  cSmbHostSts = 0;
  cSmbHostCnt = 2;
  cSmbHostCmd = 3;
  cSmbHostAdd = 4;
  cSmbHostDat = 5;
  cSmbStsBusy = $01;
  cSmbStsError = $04;
  cSpdReadCmd = $48;
  cSpdMaxSlots = 4;
  cSpdBaseAddr: array[0..3] of Byte = ($50, $52, $54, $56);
  cCommonSmbusBases: array[0..9] of Word = (
    $0B00, $0B10, $0B20, $0400, $0500, $F040, $F0C0, $1000, $E000, $EFA0);

var
  GIsaBusMutex: THandle = 0;

procedure MemSpdReleaseIsaBus;
begin
  if GIsaBusMutex <> 0 then
  begin
    ReleaseMutex(GIsaBusMutex);
    GIsaBusMutex := 0;
  end;
end;

procedure MemSpdAcquireIsaBus;
begin
  if GIsaBusMutex <> 0 then
    Exit;
  GIsaBusMutex := CreateMutexW(nil, False, PWideChar(cIsaBusMutex));
  if GIsaBusMutex = 0 then
    Exit;
  case WaitForSingleObject(GIsaBusMutex, 500) of
    WAIT_OBJECT_0, WAIT_ABANDONED:
      ;
  else
    begin
      CloseHandle(GIsaBusMutex);
      GIsaBusMutex := 0;
    end;
  end;
end;

type
  TMemSpdModule = record
    Present: Boolean;
    DeviceSize: UInt64;
    DeviceType: string;
    SpeedMts: Cardinal;
    CasLatency: Integer;
    VoltageV: Double;
    Manufacturer: string;
    PartNumber: string;
  end;

function MemSpdPioOutB(APort: Word; AValue: Byte): Boolean;
begin
  Result := PawnIoLpcExecute2('ioctl_pio_outb', UInt64(APort), AValue);
end;

function MemSpdPioInB(APort: Word; out AValue: Byte): Boolean;
begin
  Result := PawnIoLpcPioInB(APort, AValue);
end;

function MemSpdPciReadDword(const Bus, Dev, Func, Offset: Byte): DWORD;
var
  addr: DWORD;
  i: Integer;
  b: Byte;
begin
  Result := 0;
  if not PawnIoLpcAvailable then
    Exit;
  addr := $80000000 or (DWORD(Bus) shl 16) or (DWORD(Dev) shl 11) or
    (DWORD(Func) shl 8) or (DWORD(Offset) and $FC);
  if not MemSpdPioOutB(cPciConfigAddrPort + 0, Byte(addr and $FF)) then Exit;
  if not MemSpdPioOutB(cPciConfigAddrPort + 1, Byte((addr shr 8) and $FF)) then Exit;
  if not MemSpdPioOutB(cPciConfigAddrPort + 2, Byte((addr shr 16) and $FF)) then Exit;
  if not MemSpdPioOutB(cPciConfigAddrPort + 3, Byte((addr shr 24) and $FF)) then Exit;
  for i := 0 to 3 do
  begin
    if not MemSpdPioInB(Word(cPciConfigDataPort + i), b) then
      Exit;
    Result := Result or (DWORD(b) shl (i * 8));
  end;
end;

function MemSpdPciClassMatches(const AClassDword: DWORD): Boolean;
var
  classSub, baseClass: Word;
begin
  baseClass := (AClassDword shr 24) and $FF;
  classSub := (AClassDword shr 16) and $FFFF;
  Result := (classSub = cSmbClassCode) or (classSub = $0C09) or
    ((baseClass = $0C) and ((classSub and $FF) in [$05, $09, $00]));
end;

function MemSpdReadBarIoPort(const Bus, Dev, Func: Byte): Word;
var
  bar: DWORD;
begin
  Result := 0;
  bar := MemSpdPciReadDword(Bus, Dev, Func, $10);
  if (bar <> 0) and (bar <> $FFFFFFFF) and ((bar and $FFFC) <> 0) then
    Exit(Word(bar and $FFFC));
  bar := MemSpdPciReadDword(Bus, Dev, Func, $20);
  if (bar <> 0) and (bar <> $FFFFFFFF) and ((bar and $FFFC) <> 0) then
    Exit(Word(bar and $FFFC));
end;

function MemSpdSmbusReadByteQuick(const ABase: Word; const ASlave: Byte;
  const AOffset: Byte; out AData: Byte): Boolean;
var
  i: Integer;
  sts: Byte;
begin
  AData := 0;
  Result := False;
  for i := 0 to 9 do
  begin
    if not MemSpdPioInB(ABase + cSmbHostSts, sts) then
      Exit;
    if (sts and cSmbStsBusy) = 0 then
      Break;
    Sleep(1);
  end;
  MemSpdPioOutB(ABase + cSmbHostSts, $FF);
  if not MemSpdPioOutB(ABase + cSmbHostAdd, (ASlave shl 1) or 1) then
    Exit;
  if not MemSpdPioOutB(ABase + cSmbHostCmd, AOffset) then
    Exit;
  if not MemSpdPioOutB(ABase + cSmbHostCnt, cSpdReadCmd) then
    Exit;
  for i := 0 to 9 do
  begin
    if not MemSpdPioInB(ABase + cSmbHostSts, sts) then
      Exit;
    if (sts and cSmbStsBusy) = 0 then
      Break;
    Sleep(1);
  end;
  if not MemSpdPioInB(ABase + cSmbHostSts, sts) then
    Exit;
  if (sts and cSmbStsError) <> 0 then
    Exit;
  Result := MemSpdPioInB(ABase + cSmbHostDat, AData);
end;

function MemSpdQuickProbeBase(const ABase: Word): Boolean;
var
  i: Integer;
  memType: Byte;
begin
  Result := False;
  if ABase = 0 then
    Exit;
  for i := 0 to High(cSpdBaseAddr) do
  begin
    if MemSpdSmbusReadByteQuick(ABase, cSpdBaseAddr[i], 2, memType) and
      (memType in [$0B, $0C, $12, $23]) then
      Exit(True);
  end;
end;

function MemSpdProbeCommonBases: Word;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(cCommonSmbusBases) do
    if MemSpdQuickProbeBase(cCommonSmbusBases[i]) then
      Exit(cCommonSmbusBases[i]);
end;

function MemSpdTryAmdFchSmbusPort(const ADev: Byte): Word;
var
  id, cfgA0: DWORD;
begin
  Result := 0;
  id := MemSpdPciReadDword(0, ADev, 0, 0);
  if (id = $FFFFFFFF) or (id = 0) then
    Exit;
  cfgA0 := MemSpdPciReadDword(0, ADev, 0, $A0);
  if ((cfgA0 shr 16) and $FFFE) <> 0 then
    Result := Word((cfgA0 shr 16) and $FFFE);
end;

function MemSpdTryAmdFchSmbus: Word;
begin
  Result := MemSpdTryAmdFchSmbusPort($14);
  if Result = 0 then
    Result := MemSpdTryAmdFchSmbusPort($20);
end;

function MemSpdTryIntelPiix4Smbus: Word;
var
  id, cfgD0: DWORD;
  enableByte: Byte;
begin
  Result := 0;
  id := MemSpdPciReadDword(0, $1F, 3, 0);
  if (id = $FFFFFFFF) or (id = 0) then
    Exit;
  cfgD0 := MemSpdPciReadDword(0, $1F, 3, $D0);
  enableByte := Byte((cfgD0 shr 16) and $FF);
  if (enableByte and $01) = 0 then
    Exit;
  if (cfgD0 and $FFFE) <> 0 then
    Result := Word(cfgD0 and $FFFE);
end;

function MemSpdTryIntelSmbus: Word;
begin
  Result := MemSpdReadBarIoPort(0, $1F, 4);
  if Result = 0 then
    Result := MemSpdTryIntelPiix4Smbus;
end;

function MemSpdFindSmbusBase: Word;
var
  bus, dev, func: Byte;
  id, classDword: DWORD;
  barPort: Word;
begin
  Result := 0;
  if not PawnIoLpcAvailable then
    Exit;
  for bus := 0 to 3 do
    for dev := 0 to $1F do
      for func := 0 to 7 do
      begin
        id := MemSpdPciReadDword(bus, dev, func, 0);
        if (id = $FFFFFFFF) or (id = 0) then
          Continue;
        classDword := MemSpdPciReadDword(bus, dev, func, $08);
        if not MemSpdPciClassMatches(classDword) then
          Continue;
        barPort := MemSpdReadBarIoPort(bus, dev, func);
        if barPort > 0 then
          Exit(barPort);
      end;
  Result := MemSpdTryIntelSmbus;
  if Result = 0 then
    Result := MemSpdTryAmdFchSmbus;
  if Result = 0 then
    Result := MemSpdProbeCommonBases;
end;

function MemSpdSmbusWaitReady(const ABase: Word): Boolean;
var
  i: Integer;
  sts: Byte;
begin
  Result := False;
  for i := 0 to 199 do
  begin
    if not MemSpdPioInB(ABase + cSmbHostSts, sts) then
      Exit;
    if (sts and cSmbStsBusy) = 0 then
      Exit(True);
    Sleep(1);
  end;
end;

function MemSpdSmbusReadByte(const ABase: Word; const ASlave: Byte;
  const AOffset: Byte; out AData: Byte): Boolean;
var
  sts: Byte;
begin
  AData := 0;
  Result := False;
  if not MemSpdSmbusWaitReady(ABase) then
    Exit;
  MemSpdPioOutB(ABase + cSmbHostSts, $FF);
  if not MemSpdPioOutB(ABase + cSmbHostAdd, (ASlave shl 1) or 1) then
    Exit;
  if not MemSpdPioOutB(ABase + cSmbHostCmd, AOffset) then
    Exit;
  if not MemSpdPioOutB(ABase + cSmbHostCnt, cSpdReadCmd) then
    Exit;
  if not MemSpdSmbusWaitReady(ABase) then
    Exit;
  if not MemSpdPioInB(ABase + cSmbHostSts, sts) then
    Exit;
  if (sts and cSmbStsError) <> 0 then
    Exit;
  Result := MemSpdPioInB(ABase + cSmbHostDat, AData);
end;

function MemSpdReadBlock(const ABase: Word; const ASlave: Byte;
  var AData: array of Byte): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(AData) do
    if not MemSpdSmbusReadByte(ABase, ASlave, Byte(i), AData[i]) then
      Exit;
  Result := True;
end;

function MemSpdAnsiField(const AData: array of Byte; AStart, ALen: Integer): string;
var
  i: Integer;
  s: AnsiString;
begin
  SetLength(s, ALen);
  for i := 0 to ALen - 1 do
    if AStart + i > High(AData) then
      s[i + 1] := #0
    else
      s[i + 1] := AnsiChar(AData[AStart + i]);
  Result := Trim(string(s));
end;

function MemSpdDecodeDdr4Capacity(const AData: array of Byte): UInt64;
var
  density, rows, cols, bankGroups, banks, busWidth, dieCount: Integer;
begin
  Result := 0;
  if High(AData) < 12 then
    Exit;
  case AData[4] and $0F of
    0: density := 256;
    1: density := 512;
    2: density := 1024;
    3: density := 2048;
    4: density := 4096;
    5: density := 8192;
    6: density := 16384;
  else
    Exit;
  end;
  rows := (AData[5] and $7) + 12;
  cols := ((AData[5] shr 3) and $7) + 9;
  bankGroups := 1 shl (AData[4] shr 6);
  banks := 1 shl (AData[4] shr 4 and 3);
  busWidth := 4 shl (AData[13] and $7);
  dieCount := (AData[6] and $7) + 1;
  if busWidth = 0 then
    busWidth := 64;
  Result := UInt64(density) * UInt64(1 shl rows) * UInt64(1 shl cols) *
    UInt64(banks) * UInt64(bankGroups) * UInt64(busWidth) * UInt64(dieCount) div 8;
end;

function MemSpdDecodeDdr5Capacity(const AData: array of Byte): UInt64;
var
  densityGb, diePerPackage, busWidth, channels: Integer;
begin
  Result := 0;
  if High(AData) < 234 then
    Exit;
  case AData[4] and $1F of
    0: densityGb := 0;
    1: densityGb := 4;
    2: densityGb := 8;
    3: densityGb := 12;
    4: densityGb := 16;
    5: densityGb := 24;
    6: densityGb := 32;
    7: densityGb := 48;
    8: densityGb := 64;
  else
    Exit;
  end;
  if densityGb = 0 then
    Exit;
  diePerPackage := (AData[6] and $7) + 1;
  busWidth := 4 shl (AData[229] and $7);
  if busWidth = 0 then
    busWidth := 64;
  channels := 1;
  Result := UInt64(densityGb) * 1024 * 1024 * 1024 * UInt64(diePerPackage) *
    UInt64(channels) * UInt64(busWidth) div 64;
end;

function MemSpdDecodeSpeedMts(const AData: array of Byte): Cardinal;
var
  tck256: Integer;
begin
  Result := 0;
  if AData[2] = $0C then
  begin
    if (High(AData) < 18) or (AData[18] = 0) then
      Exit;
    tck256 := AData[18] * 256;
    if High(AData) >= 125 then
      tck256 := tck256 + ShortInt(AData[125]);
    if tck256 > 0 then
      Result := Cardinal((16000 * 256 + tck256 - 1) div tck256);
  end
  else if AData[2] = $23 then
  begin
    if (High(AData) < 21) or (AData[21] = 0) then
      Exit;
    tck256 := AData[21] * 256;
    if High(AData) >= 123 then
      tck256 := tck256 + ShortInt(AData[123]);
    if tck256 > 0 then
      Result := Cardinal((16000 * 256 + tck256 - 1) div tck256);
  end
  else if AData[2] = $0B then
  begin
    if (High(AData) >= 12) and (AData[12] > 0) then
      Result := Cardinal((16000 + AData[12] - 1) div AData[12]);
  end;
end;

function MemSpdDecodeVoltageV(const AData: array of Byte): Double;
var
  code: Integer;
begin
  Result := 0;
  if High(AData) < 21 then
    Exit;
  case AData[2] of
    $0B:
      begin
        code := (AData[21] shr 5) and 7;
        case code of
          4: Result := 1.25;
          6: Result := 1.35;
        else
          Result := 1.50;
        end;
      end;
    $0C:
      Result := 1.20;
    $23:
      begin
        if High(AData) >= 192 then
          Result := (1100 + Integer(AData[192]) * 5) / 1000.0;
        if Result <= 0 then
          Result := 1.10;
      end;
  end;
end;

function MemSpdDataLooksValid(const AData: array of Byte): Boolean;
begin
  Result := AData[2] in [$0B, $0C, $12, $23];
  if Result then
    Exit;
  Result := (AData[0] <> $FF) and (AData[0] >= 128) and (AData[0] <> 0);
end;

procedure MemSpdClearModule(var AMod: TMemSpdModule);
begin
  AMod.Present := False;
  AMod.DeviceSize := 0;
  AMod.DeviceType := '';
  AMod.SpeedMts := 0;
  AMod.CasLatency := 0;
  AMod.VoltageV := 0;
  AMod.Manufacturer := '';
  AMod.PartNumber := '';
end;

function MemSpdDecodeCasFromBitmap(const AData: array of Byte; AStart, AByteCount,
  ABaseCL: Integer): Integer;
var
  clBitmap: Cardinal;
  i, b: Integer;
begin
  Result := 0;
  clBitmap := 0;
  for b := 0 to AByteCount - 1 do
    if AStart + b <= High(AData) then
      clBitmap := clBitmap or (Cardinal(AData[AStart + b]) shl (b * 8));
  for i := (AByteCount * 8) - 1 downto 0 do
    if (clBitmap and (Cardinal(1) shl i)) <> 0 then
      Exit(ABaseCL + i);
end;

function MemSpdDecodeDdr3CasLatency(const AData: array of Byte): Integer;
var
  mtb, ftb, tckPs, taaPs: Integer;
begin
  Result := 0;
  if High(AData) < 19 then
    Exit;
  mtb := AData[10];
  ftb := AData[9];
  if mtb = 0 then
    Exit(MemSpdDecodeCasFromBitmap(AData, 15, 3, 4));
  tckPs := AData[14] * mtb + ShortInt(AData[15]) * ftb;
  taaPs := AData[18] * mtb + ShortInt(AData[19]) * ftb;
  if tckPs > 0 then
    Result := (taaPs + tckPs - 1) div tckPs;
  if Result <= 0 then
    Result := MemSpdDecodeCasFromBitmap(AData, 15, 3, 4);
end;

function MemSpdDecodeDdr4CasLatency(const AData: array of Byte): Integer;
var
  mtb, ftb, tckPs, taaPs: Integer;
begin
  Result := 0;
  if High(AData) < 23 then
    Exit;
  mtb := AData[15];
  ftb := AData[14];
  if mtb = 0 then
    Exit(MemSpdDecodeCasFromBitmap(AData, 18, 4, 7));
  tckPs := AData[16] * mtb + ShortInt(AData[17]) * ftb;
  taaPs := AData[22] * mtb + ShortInt(AData[23]) * ftb;
  if tckPs > 0 then
    Result := (taaPs + tckPs - 1) div tckPs;
  if Result <= 0 then
    Result := MemSpdDecodeCasFromBitmap(AData, 18, 4, 7);
end;

function MemSpdDecodeDdr5CasLatency(const AData: array of Byte): Integer;
var
  mtb, ftb, tckPs, taaPs: Integer;
begin
  Result := 0;
  if High(AData) < 234 then
    Exit;
  mtb := AData[15];
  ftb := AData[14];
  if mtb = 0 then
    Exit(MemSpdDecodeCasFromBitmap(AData, 123, 5, 22));
  tckPs := AData[21] * mtb + ShortInt(AData[22]) * ftb;
  taaPs := AData[30] * mtb + ShortInt(AData[31]) * ftb;
  if tckPs > 0 then
    Result := (taaPs + tckPs - 1) div tckPs;
  if Result <= 0 then
    Result := MemSpdDecodeCasFromBitmap(AData, 123, 5, 22);
end;

function MemSpdDecodeCasLatency(const AData: array of Byte): Integer;
begin
  case AData[2] of
    $0B: Result := MemSpdDecodeDdr3CasLatency(AData);
    $0C: Result := MemSpdDecodeDdr4CasLatency(AData);
    $23: Result := MemSpdDecodeDdr5CasLatency(AData);
  else
    Result := 0;
  end;
end;

procedure MemSpdParseModule(const AData: array of Byte; var AMod: TMemSpdModule);
var
  mfgOff, pnOff, pnLen: Integer;
begin
  MemSpdClearModule(AMod);
  if not MemSpdDataLooksValid(AData) then
    Exit;
  AMod.Present := True;
  mfgOff := 117;
  pnOff := 128;
  pnLen := 18;
  case AData[2] of
    $0B: AMod.DeviceType := 'DDR3';
    $0C:
      begin
        AMod.DeviceType := 'DDR4';
        AMod.DeviceSize := MemSpdDecodeDdr4Capacity(AData);
        mfgOff := 320;
        pnOff := 329;
        pnLen := 20;
      end;
    $23:
      begin
        AMod.DeviceType := 'DDR5';
        AMod.DeviceSize := MemSpdDecodeDdr5Capacity(AData);
        mfgOff := 512;
        pnOff := 521;
        pnLen := 29;
      end;
  end;
  AMod.Manufacturer := MemJedecManufacturerText(Word(AData[mfgOff + 1]) shl 8 or AData[mfgOff]);
  AMod.PartNumber := MemSpdAnsiField(AData, pnOff, pnLen);
  AMod.SpeedMts := MemSpdDecodeSpeedMts(AData);
  AMod.CasLatency := MemSpdDecodeCasLatency(AData);
  AMod.VoltageV := MemSpdDecodeVoltageV(AData);
  if AMod.DeviceType = '' then
    AMod.DeviceType := MemInferDramTypeFromText(AMod.PartNumber);
  if AMod.SpeedMts = 0 then
    AMod.SpeedMts := MemInferSpeedMtsFromText(AMod.PartNumber);
  if AMod.CasLatency = 0 then
    AMod.CasLatency := MemInferCasFromText(AMod.PartNumber);
  AMod.Manufacturer := MemResolveManufacturerName(AMod.Manufacturer, AMod.PartNumber);
end;

procedure MemSpdCollectFromModule(const AMod: TMemSpdModule; var AInfo: TMemStaticInfo);
var
  dramType: string;
  speedMts: Cardinal;
begin
  if not AMod.Present then
    Exit;
  dramType := AMod.DeviceType;
  if dramType = '' then
    dramType := MemInferDramTypeFromText(AMod.PartNumber);
  speedMts := AMod.SpeedMts;
  if speedMts = 0 then
    speedMts := MemInferSpeedMtsFromText(AMod.PartNumber);
  MemUpdateDramSpec(AInfo, dramType, speedMts);
  MemUpdateDramVoltage(AInfo, AMod.VoltageV);
end;

procedure MemSpdDiagAdd(ADiag: TStringList; const AText: string);
begin
  if ADiag <> nil then
    ADiag.Add(AText);
end;

procedure MemSpdDiagSlotNoTiming(ADiag: TStringList; ASlotIndex: Integer;
  const AMod: TMemSpdModule);
var
  pn: string;
begin
  if ADiag = nil then
    Exit;
  pn := Trim(AMod.PartNumber);
  if pn = '' then
    MemSpdDiagAdd(ADiag, Format('卡槽%d：SPD 已识别但无时序字段，且无型号文本可推断 CL', [ASlotIndex]))
  else if MemInferCasFromText(pn) > 0 then
    MemSpdDiagAdd(ADiag, Format('卡槽%d：SPD CAS 解码失败，型号「%s」含 CL 信息但未能合并到显示行',
      [ASlotIndex, pn]))
  else
    MemSpdDiagAdd(ADiag, Format('卡槽%d：SPD 无时序字段，型号「%s」不含 CL 模式', [ASlotIndex, pn]));
end;

function MemSpdProbeSlot(const ABase: Word; const ASlave: Byte; ASlotIndex: Integer;
  var AMod: TMemSpdModule; ADiag: TStringList): Boolean;
var
  spd: array[0..511] of Byte;
  i: Integer;
begin
  FillChar(spd, SizeOf(spd), $FF);
  Result := False;
  for i := 0 to 127 do
    if not MemSpdSmbusReadByte(ABase, ASlave, Byte(i), spd[i]) then
    begin
      MemSpdDiagAdd(ADiag, Format('卡槽%d：SPD 逐字节读取失败（偏移 %d，SMBus 无应答或校验错误）',
        [ASlotIndex, i]));
      Exit;
    end;
  if not MemSpdDataLooksValid(spd) then
  begin
    MemSpdDiagAdd(ADiag, Format('卡槽%d：SPD 数据无效（非 DDR 模组或 EEPROM 为空）', [ASlotIndex]));
    Exit;
  end;
  MemSpdParseModule(spd, AMod);
  Result := AMod.Present;
  if Result and (AMod.CasLatency <= 0) then
    MemSpdDiagSlotNoTiming(ADiag, ASlotIndex, AMod);
end;

function MemSpdReadSlots(const ABase: Word; var AMods: array of TMemSpdModule;
  ADiag: TStringList): Integer;
var
  i: Integer;
  spd: array[0..511] of Byte;
  blockOk: Boolean;
begin
  Result := 0;
  for i := 0 to High(AMods) do
  begin
    MemSpdClearModule(AMods[i]);
    FillChar(spd, SizeOf(spd), $FF);
    blockOk := MemSpdReadBlock(ABase, cSpdBaseAddr[i], spd);
    if blockOk then
      MemSpdParseModule(spd, AMods[i])
    else if not MemSpdProbeSlot(ABase, cSpdBaseAddr[i], i + 1, AMods[i], ADiag) then
      MemSpdDiagAdd(ADiag, Format('卡槽%d：SPD EEPROM 整块读取失败（SMBus 错误）', [i + 1]));
    if AMods[i].Present then
    begin
      Inc(Result);
      if blockOk and (AMods[i].CasLatency <= 0) then
        MemSpdDiagSlotNoTiming(ADiag, i + 1, AMods[i]);
    end;
  end;
end;

procedure MemSpdEnsureSlotLayout(var AInfo: TMemStaticInfo; ATargetSlots: Integer);
begin
  MemEnsureModuleSlots(AInfo.Modules, ATargetSlots);
  if AInfo.SlotCount < Cardinal(ATargetSlots) then
    AInfo.SlotCount := Cardinal(ATargetSlots);
end;

function MemSpdModulesNeedEnrich(const AInfo: TMemStaticInfo): Boolean;
var
  i: Integer;
begin
  Result := False;
  if Length(AInfo.Modules) = 0 then
    Exit(True);
  for i := 0 to High(AInfo.Modules) do
  begin
    if not MemModuleIsPopulated(AInfo.Modules[i]) then
      Exit(True);
    if not MemModuleHasSpec(AInfo.Modules[i]) then
      Exit(True);
    if not MemModuleHasTiming(AInfo.Modules[i]) then
      Exit(True);
  end;
end;

procedure MemSpdModuleToInfo(const AMod: TMemSpdModule; APerSize: UInt64; out M: TMemModuleInfo);
begin
  MemModuleClear(M);
  if not AMod.Present then
    Exit;
  M.DramType := AMod.DeviceType;
  M.SpeedMts := AMod.SpeedMts;
  M.CasLatency := AMod.CasLatency;
  if AMod.DeviceSize > 0 then
    M.SizeBytes := AMod.DeviceSize
  else if APerSize > 0 then
    M.SizeBytes := APerSize;
  M.Manufacturer := AMod.Manufacturer;
  M.PartNumber := AMod.PartNumber;
end;

function MemSpdModuleMatchesInfo(const M: TMemModuleInfo; const AMod: TMemSpdModule): Boolean;
var
  mfg: string;
begin
  Result := False;
  if AMod.DeviceSize > 0 then
  begin
    if M.SizeBytes <> AMod.DeviceSize then
      Exit;
  end;
  mfg := MemResolveManufacturerName(AMod.Manufacturer, AMod.PartNumber);
  if mfg <> '' then
    Exit(MemResolveManufacturerName(M.Manufacturer, M.PartNumber) = mfg);
  Result := True;
end;

procedure MemSmbDistributePhysTotal(var AInfo: TMemStaticInfo);
var
  i, slotIdx, installedCount: Integer;
  perSize: UInt64;
  order: TMemSlotOrder;
begin
  if (AInfo.PhysTotal = 0) or (Length(AInfo.Modules) = 0) then
    Exit;
  installedCount := MemEstimateInstalledCount(Length(AInfo.Modules), AInfo.PhysTotal);
  perSize := AInfo.PhysTotal div installedCount;
  order := MemDualChannelSlotOrder(Length(AInfo.Modules), installedCount);
  for i := 0 to High(order) do
  begin
    slotIdx := order[i];
    if (slotIdx < 0) or (slotIdx > High(AInfo.Modules)) then
      Continue;
    if MemModuleIsPopulated(AInfo.Modules[slotIdx]) then
      Continue;
    AInfo.Modules[slotIdx].SizeBytes := perSize;
    if MemIsUnknownLabel(AInfo.Modules[slotIdx].DramType) and (AInfo.DramType <> '') then
      AInfo.Modules[slotIdx].DramType := AInfo.DramType;
    if (AInfo.Modules[slotIdx].SpeedMts = 0) and (AInfo.DramSpeedMts > 0) then
      AInfo.Modules[slotIdx].SpeedMts := AInfo.DramSpeedMts;
  end;
end;

procedure MemSpdApplyModules(const AMods: array of TMemSpdModule; var AInfo: TMemStaticInfo);
var
  i, slotCount, installedCount: Integer;
  modInfo: TMemModuleInfo;
  perSize: UInt64;
begin
  slotCount := Length(AMods);
  if slotCount = 0 then
    Exit;
  MemSpdEnsureSlotLayout(AInfo, slotCount);
  installedCount := 0;
  for i := 0 to slotCount - 1 do
    if AMods[i].Present then
      Inc(installedCount);
  if installedCount = 0 then
    installedCount := MemEstimateInstalledCount(slotCount, AInfo.PhysTotal);
  if (installedCount > 0) and (AInfo.PhysTotal > 0) then
    perSize := AInfo.PhysTotal div installedCount
  else
    perSize := 0;
  for i := 0 to slotCount - 1 do
  begin
    if not AMods[i].Present then
      Continue;
    MemSpdModuleToInfo(AMods[i], perSize, modInfo);
    MemSpdCollectFromModule(AMods[i], AInfo);
    AInfo.Modules[i] := modInfo;
  end;
end;

procedure MemSpdMergeCasIntoModules(const AMods: array of TMemSpdModule; var AInfo: TMemStaticInfo);
var
  i, j, casLat: Integer;
  used: array of Boolean;
begin
  if Length(AInfo.Modules) = 0 then
    Exit;
  SetLength(used, Length(AInfo.Modules));
  FillChar(used[0], Length(used) * SizeOf(Boolean), 0);
  for i := 0 to High(AMods) do
  begin
    if not AMods[i].Present then
      Continue;
    casLat := AMods[i].CasLatency;
    if casLat <= 0 then
      casLat := MemInferCasFromText(AMods[i].PartNumber);
    if casLat <= 0 then
      Continue;
    for j := 0 to High(AInfo.Modules) do
    begin
      if used[j] then
        Continue;
      if not MemModuleIsPopulated(AInfo.Modules[j]) or MemModuleHasTiming(AInfo.Modules[j]) then
        Continue;
      if not MemSpdModuleMatchesInfo(AInfo.Modules[j], AMods[i]) then
        Continue;
      AInfo.Modules[j].CasLatency := casLat;
      used[j] := True;
      Break;
    end;
  end;
  for j := 0 to High(AInfo.Modules) do
  begin
    if not MemModuleIsPopulated(AInfo.Modules[j]) or MemModuleHasTiming(AInfo.Modules[j]) then
      Continue;
    casLat := MemInferCasFromText(AInfo.Modules[j].PartNumber);
    if casLat > 0 then
      AInfo.Modules[j].CasLatency := casLat;
  end;
end;

procedure MemSpdTryEnrich(var AInfo: TMemStaticInfo; ADiag: TStringList);
var
  smbusBase: Word;
  mods: array[0..cSpdMaxSlots - 1] of TMemSpdModule;
  readCount, targetSlots: Integer;
  pciBarsReady: Boolean;
begin
  targetSlots := AInfo.SlotCount;
  if targetSlots <= 1 then
    targetSlots := MemGuessSlotCount(AInfo.PhysTotal);
  MemSpdEnsureSlotLayout(AInfo, targetSlots);
  if PawnIoLpcAvailable then
  try
    MemSpdAcquireIsaBus;
    if GIsaBusMutex = 0 then
      MemSpdDiagAdd(ADiag, 'SMBus 互斥锁获取失败或超时，跳过 SPD 读取')
    else
    begin
      pciBarsReady := PawnIoLpcExecute0('ioctl_find_bars');
      if not pciBarsReady then
        MemSpdDiagAdd(ADiag, 'PCI 配置空间 BAR 枚举失败，无法定位 SMBus 端口')
      else
      begin
        smbusBase := MemSpdFindSmbusBase;
        if smbusBase = 0 then
          MemSpdDiagAdd(ADiag, '未找到 SMBus 控制器 I/O 端口（PCI 扫描与常见基址探测均失败）')
        else
        begin
          readCount := MemSpdReadSlots(smbusBase, mods, ADiag);
          if readCount > 0 then
            MemSpdApplyModules(mods, AInfo);
          MemSpdMergeCasIntoModules(mods, AInfo);
        end;
      end;
    end;
  finally
    MemSpdReleaseIsaBus;
  end
  else
    MemSpdDiagAdd(ADiag, 'PawnIO LPC 不可用，未尝试 SPD 读取');
  if MemSpdModulesNeedEnrich(AInfo) then
    MemSmbDistributePhysTotal(AInfo);
  if (AInfo.ChannelCount <= 1) and (MemCountInstalledModules(AInfo.Modules) >= 2) then
    AInfo.ChannelCount := 2;
end;

initialization

finalization
  MemSpdReleaseIsaBus;

end.
