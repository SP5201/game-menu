unit CpuInfoPawnIo;

{
  CPU 温度/电压/功耗传感器：通过 PawnIO + MSR 读取。
  Intel：IA32_THERM_STATUS / IA32_PACKAGE_THERM_STATUS（bit31 有效位 + 每核 TjMax）；
        IA32_PERF_STATUS VID；RAPL 0x606/0x611 算封装功耗（Atom 用微焦耳单位）。
  AMD：MSR_K7_THERM_STATUS（Family 0Fh）或 Zen Tctl；Zen RAPL 0xC0010299/0xC001029B。
}

interface

uses
  CpuInfo;

function CpuPawnIoQuerySensors(out AInfo: TCpuSensorInfo): Boolean;

implementation

uses
  Windows, SysUtils, Math, PawnIo;

const
  cMsrIa32ThermStatus = $19C;
  cMsrIa32PackageThermStatus = $1B1;
  cMsrIa32TemperatureTarget = $1A2;
  cMsrAmdK7ThermStatus = $C0010004;
  cMsrAmdZenTctl = $C0010058;
  cSmnZenCurTemp = $00059800;
  cSmnZenSviBase = $0005A000;
  cZenTempRangeSelMask = $80000;
  cZenTempTjSelMask = $30000;
  cMsrIa32PerfStatus = $198;
  cMsrRaplPowerUnit = $606;
  cMsrPkgEnergyStatus = $611;
  cMsrAmdPwrUnit = $C0010299;
  cMsrAmdPkgEnergyStat = $C001029B;
  cAmdSviVidBase = 1.550;
  cAmdSviVidStep = 0.00625;
  cCpuPowerMinW = 0.5;
  cCpuPowerMaxW = 500.0;
  cCpuEnergyMinElapsedMs = 200;
  cIntelThermReadingValid = $80000000;
  cIntelThermDeltaMask = $007F0000;

type
  TCpuPawnIoEnergySample = record
    HasLast: Boolean;
    UnitReady: Boolean;
    EnergyUnitJ: Double;
    LastEnergy: UInt32;
    LastTick: DWORD;
  end;

  TCpuIdRegs = record
    Eax, Ebx, Ecx, Edx: Cardinal;
  end;

var
  GIntelEnergySample: TCpuPawnIoEnergySample;
  GAmdEnergySample: TCpuPawnIoEnergySample;

function CpuPawnIoEnergyTickElapsed(ANowTick, ALastTick: DWORD): Integer;
begin
  if ANowTick >= ALastTick then
    Result := ANowTick - ALastTick
  else
    Result := (High(DWORD) - ALastTick) + ANowTick + 1;
end;

function CpuPawnIoIsPlausiblePowerW(APowerW: Double): Boolean;
begin
  Result := (not IsNan(APowerW)) and (not IsInfinite(APowerW)) and
    (APowerW >= cCpuPowerMinW) and (APowerW <= cCpuPowerMaxW);
end;

function CpuPawnIoEnergyUnitFromEsu(AEsu: Integer; AMicroWattUnit: Boolean): Double;
begin
  if AMicroWattUnit then
    Result := 1.0e-6 * (1 shl AEsu)
  else
    Result := Power(0.5, AEsu);
end;

function CpuPawnIoSamplePackagePowerW(
  const APwrUnitMsr, AEnergyMsr: DWORD; var ASample: TCpuPawnIoEnergySample;
  AMicroWattUnit: Boolean): Double;
var
  eax, edx: DWORD;
  energyNow: UInt32;
  nowTick: DWORD;
  elapsedMs: Integer;
  energyDelta: UInt64;
  esu: Integer;
begin
  Result := -1;
  if not PawnIoIsMsrSupported then
    Exit;
  if not ASample.UnitReady then
  begin
    if not PawnIoReadMsr(APwrUnitMsr, eax, edx) then
      Exit;
    esu := Integer((eax shr 8) and $1F);
    ASample.EnergyUnitJ := CpuPawnIoEnergyUnitFromEsu(esu, AMicroWattUnit);
    if ASample.EnergyUnitJ <= 0 then
      Exit;
    ASample.UnitReady := True;
  end;
  if not PawnIoReadMsr(AEnergyMsr, eax, edx) then
    Exit;
  energyNow := UInt32(eax);
  nowTick := GetTickCount;
  if not ASample.HasLast then
  begin
    ASample.LastEnergy := energyNow;
    ASample.LastTick := nowTick;
    ASample.HasLast := True;
    Exit;
  end;
  elapsedMs := CpuPawnIoEnergyTickElapsed(nowTick, ASample.LastTick);
  if elapsedMs < cCpuEnergyMinElapsedMs then
    Exit;
  if energyNow >= ASample.LastEnergy then
    energyDelta := energyNow - ASample.LastEnergy
  else
    energyDelta := (UInt64($100000000) - ASample.LastEnergy) + energyNow;
  Result := ASample.EnergyUnitJ * energyDelta / (elapsedMs / 1000.0);
  ASample.LastEnergy := energyNow;
  ASample.LastTick := nowTick;
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

function CpuPawnIoVendorId: string;
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
  Result := string(raw);
end;

function CpuPawnIoFamilyModel: Cardinal;
var
  regs: TCpuIdRegs;
begin
  CpuIdLeaf(1, regs);
  Result := (regs.Eax shr 8) and $FF0F;
end;

function CpuPawnIoIntelUsesMicroWattRapl: Boolean;
var
  model: Cardinal;
begin
  model := CpuPawnIoFamilyModel and $FF;
  Result := model in [$37, $4A, $4D, $5A, $5D, $4C];
end;

function CpuPawnIoIntelPackagePowerW: Double;
begin
  Result := CpuPawnIoSamplePackagePowerW(
    cMsrRaplPowerUnit, cMsrPkgEnergyStatus, GIntelEnergySample,
    CpuPawnIoIntelUsesMicroWattRapl);
end;

function CpuPawnIoAmdPackagePowerW: Double;
var
  family: Cardinal;
begin
  Result := -1;
  family := CpuPawnIoFamilyModel shr 4;
  if family < $17 then
    Exit;
  Result := CpuPawnIoSamplePackagePowerW(
    cMsrAmdPwrUnit, cMsrAmdPkgEnergyStat, GAmdEnergySample, False);
end;

function CpuPawnIoAmdModel: Cardinal;
var
  regs: TCpuIdRegs;
  family, extFamily, model, extModel: Cardinal;
begin
  CpuIdLeaf(1, regs);
  family := (regs.Eax shr 8) and $F;
  extFamily := (regs.Eax shr 20) and $FF;
  model := (regs.Eax shr 4) and $F;
  extModel := (regs.Eax shr 16) and $F;
  if family = $F then
    family := extFamily + family;
  if family >= $F then
    model := (extModel shl 4) + model;
  Result := model;
end;

function CpuPawnIoIsIntel: Boolean;
begin
  Result := SameText(CpuPawnIoVendorId, 'GenuineIntel');
end;

function CpuPawnIoIsAmd: Boolean;
begin
  Result := SameText(CpuPawnIoVendorId, 'AuthenticAMD');
end;

function CpuPawnIoIntelHasDts: Boolean;
var
  regs: TCpuIdRegs;
begin
  Result := False;
  CpuIdLeaf(0, regs);
  if regs.Eax < 6 then
    Exit;
  CpuIdLeaf(6, regs);
  Result := (regs.Eax and $01) <> 0;
end;

function CpuPawnIoIntelThermReadingValid(AEax: DWORD): Boolean;
begin
  Result := (AEax and cIntelThermReadingValid) <> 0;
end;

function CpuPawnIoIntelDeltaFromTjMax(AEax: DWORD): Integer;
begin
  Result := Integer((AEax and cIntelThermDeltaMask) shr 16);
end;

function CpuPawnIoIntelTjMaxForCore(ACoreIndex: Integer): Integer;
var
  mask: ULONG_PTR;
  eax, edx: DWORD;
  tjMax: Integer;
begin
  Result := 100;
  mask := ULONG_PTR(1) shl ACoreIndex;
  if PawnIoReadMsrTx(cMsrIa32TemperatureTarget, mask, eax, edx) then
  begin
    tjMax := (eax shr 16) and $FF;
    if tjMax > 0 then
      Result := tjMax;
  end;
end;

function CpuPawnIoIntelCoreIndexFromMask(AMask: ULONG_PTR): Integer;
var
  idx: Integer;
begin
  Result := 0;
  for idx := 0 to 31 do
  begin
    if AMask = (ULONG_PTR(1) shl idx) then
    begin
      Result := idx;
      Break;
    end;
  end;
end;

function CpuPawnIoIntelTempFromMsrTx(
  const AMsrIndex: DWORD; AAffinity: ULONG_PTR): Double;
var
  eax, edx: DWORD;
  delta, tjMax, coreIdx: Integer;
begin
  Result := -1;
  if not PawnIoReadMsrTx(AMsrIndex, AAffinity, eax, edx) then
    Exit;
  if not CpuPawnIoIntelThermReadingValid(eax) then
    Exit;
  delta := CpuPawnIoIntelDeltaFromTjMax(eax);
  coreIdx := CpuPawnIoIntelCoreIndexFromMask(AAffinity);
  tjMax := CpuPawnIoIntelTjMaxForCore(coreIdx);
  Result := tjMax - delta;
end;

function CpuPawnIoIntelCoreMaxTemp: Double;
var
  sysInfo: TSystemInfo;
  i: Integer;
  mask: ULONG_PTR;
  eax, edx: DWORD;
  delta, tjMax: Integer;
  temp, maxTemp: Double;
begin
  Result := -1;
  if not PawnIoIsMsrSupported or not CpuPawnIoIntelHasDts then
    Exit;
  GetSystemInfo(sysInfo);
  maxTemp := -1;
  for i := 0 to sysInfo.dwNumberOfProcessors - 1 do
  begin
    mask := ULONG_PTR(1) shl i;
    if not PawnIoReadMsrTx(cMsrIa32ThermStatus, mask, eax, edx) then
      Continue;
    if not CpuPawnIoIntelThermReadingValid(eax) then
      Continue;
    delta := CpuPawnIoIntelDeltaFromTjMax(eax);
    tjMax := CpuPawnIoIntelTjMaxForCore(i);
    temp := tjMax - delta;
    if temp > maxTemp then
      maxTemp := temp;
  end;
  if maxTemp >= 0 then
    Result := maxTemp;
end;

function CpuPawnIoAmdZenSmnTemp: Double;
var
  raw: DWORD;
  tempMilli: Integer;
  offsetFlag: Boolean;
begin
  Result := -1;
  if not PawnIoReadSmn(cSmnZenCurTemp, raw) or (raw = 0) then
    Exit;
  offsetFlag := ((raw and cZenTempRangeSelMask) <> 0) or
    ((raw and cZenTempTjSelMask) = cZenTempTjSelMask);
  tempMilli := Integer(raw shr 21) * 125;
  if offsetFlag then
    Dec(tempMilli, 49000);
  if tempMilli > 0 then
    Result := tempMilli / 1000.0;
end;

function CpuPawnIoAmdZenSviPlaneOffsets(out APlane0Off, APlane1Off: DWORD): Boolean;
var
  model: Cardinal;
begin
  APlane0Off := 0;
  APlane1Off := 0;
  Result := False;
  if PawnIoBackend <> pbAmdFamily17 then
    Exit;
  model := CpuPawnIoAmdModel;
  case model of
    $31:
      begin
        APlane0Off := cSmnZenSviBase + $14;
        APlane1Off := cSmnZenSviBase + $10;
      end;
    $71, $21, $61, $44:
      begin
        APlane0Off := cSmnZenSviBase + $10;
        APlane1Off := cSmnZenSviBase + $C;
      end;
  else
    begin
      APlane0Off := cSmnZenSviBase + $C;
      APlane1Off := cSmnZenSviBase + $10;
    end;
  end;
  Result := True;
end;

function CpuPawnIoAmdCoreVoltage: Double;
var
  sviTfn, plane0: DWORD;
  plane0Off, plane1Off: DWORD;
  vddCor: Cardinal;
begin
  Result := -1;
  if not CpuPawnIoAmdZenSviPlaneOffsets(plane0Off, plane1Off) then
    Exit;
  if not PawnIoReadSmn(cSmnZenSviBase + $8, sviTfn) then
    Exit;
  if (sviTfn and $01) <> 0 then
    Exit;
  if not PawnIoReadSmn(plane0Off, plane0) then
    Exit;
  vddCor := (plane0 shr 16) and $FF;
  Result := cAmdSviVidBase - (cAmdSviVidStep * vddCor);
end;

function CpuPawnIoIntelVoltage: Double;
var
  sysInfo: TSystemInfo;
  i: Integer;
  mask: ULONG_PTR;
  eax, edx: DWORD;
  vid, maxVid: Cardinal;
begin
  Result := -1;
  if not PawnIoIsMsrSupported then
    Exit;
  maxVid := 0;
  GetSystemInfo(sysInfo);
  for i := 0 to sysInfo.dwNumberOfProcessors - 1 do
  begin
    mask := ULONG_PTR(1) shl i;
    if not PawnIoReadMsrTx(cMsrIa32PerfStatus, mask, eax, edx) then
      Continue;
    vid := edx and $FFFF;
    if vid = 0 then
      vid := eax and $FFFF;
    if vid > maxVid then
      maxVid := vid;
  end;
  if maxVid > 0 then
    Result := maxVid / 8192.0;
end;

function CpuPawnIoAmdTemp: Double;
var
  eax, edx: DWORD;
  family: Cardinal;
  raw: Integer;
begin
  Result := -1;
  family := CpuPawnIoFamilyModel shr 4;
  if family >= $17 then
  begin
    if PawnIoBackend = pbAmdFamily17 then
      Exit(CpuPawnIoAmdZenSmnTemp);
    if not PawnIoIsMsrSupported then
      Exit;
    if not PawnIoReadMsr(cMsrAmdZenTctl, eax, edx) then
      Exit;
    raw := (eax shr 12) and $FFF;
    if raw > 0 then
      Result := raw * 0.125;
    Exit;
  end;
  if not PawnIoIsMsrSupported then
    Exit;
  if not PawnIoReadMsr(cMsrAmdK7ThermStatus, eax, edx) then
    Exit;
  raw := eax and $FF;
  if raw > 0 then
    Result := raw - 49;
end;

function CpuPawnIoQuerySensors(out AInfo: TCpuSensorInfo): Boolean;
var
  coreTemp, pkgTemp, voltage, powerW: Double;
begin
  CpuInitSensorInfo(AInfo);
  Result := False;
  if not PawnIoAvailable then
    Exit;

  if CpuPawnIoIsIntel then
  begin
    coreTemp := CpuPawnIoIntelCoreMaxTemp;
    if coreTemp >= 0 then
    begin
      AInfo.HasCoreTemp := True;
      AInfo.CoreTempC := coreTemp;
      Result := True;
    end;
    pkgTemp := CpuPawnIoIntelTempFromMsrTx(cMsrIa32PackageThermStatus, 1);
    if pkgTemp < 0 then
      pkgTemp := coreTemp;
    if pkgTemp >= 0 then
    begin
      AInfo.HasPackageTemp := True;
      AInfo.PackageTempC := pkgTemp;
      Result := True;
    end;
    voltage := CpuPawnIoIntelVoltage;
    if voltage > 0 then
    begin
      AInfo.HasVoltage := True;
      AInfo.VoltageV := voltage;
      Result := True;
    end;
    powerW := CpuPawnIoIntelPackagePowerW;
    if CpuPawnIoIsPlausiblePowerW(powerW) then
    begin
      AInfo.HasPower := True;
      AInfo.PowerW := powerW;
      Result := True;
    end;
  end
  else if CpuPawnIoIsAmd then
  begin
    coreTemp := CpuPawnIoAmdTemp;
    if coreTemp >= 0 then
    begin
      AInfo.HasCoreTemp := True;
      AInfo.CoreTempC := coreTemp;
      AInfo.HasPackageTemp := True;
      AInfo.PackageTempC := coreTemp;
      Result := True;
    end;
    voltage := CpuPawnIoAmdCoreVoltage;
    if voltage > 0 then
    begin
      AInfo.HasVoltage := True;
      AInfo.VoltageV := voltage;
      Result := True;
    end;
    powerW := CpuPawnIoAmdPackagePowerW;
    if CpuPawnIoIsPlausiblePowerW(powerW) then
    begin
      AInfo.HasPower := True;
      AInfo.PowerW := powerW;
      Result := True;
    end;
  end;
end;

end.
