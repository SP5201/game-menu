unit CpuInfoSensors;

{
  CPU 温度/电压/功耗传感器：通过 PawnIO + MSR 读取。
  Intel：IA32_THERM_STATUS / IA32_PACKAGE_THERM_STATUS；IA32_PERF_STATUS VID；RAPL 封装功耗。
  AMD：Zen SMN/MSR 温度；SVI 电压；Zen RAPL 功耗。
}

interface

uses
  CpuInfo;

function CpuSensorsQuery(out AInfo: TCpuSensorInfo): Boolean;

implementation

uses
  Windows, SysUtils, Math, PawnIoClient, CpuIdHelper;

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
  TCpuEnergySample = record
    HasLast: Boolean;
    UnitReady: Boolean;
    EnergyUnitJ: Double;
    LastEnergy: UInt32;
    LastTick: DWORD;
  end;

var
  GIntelEnergySample: TCpuEnergySample;
  GAmdEnergySample: TCpuEnergySample;

function CpuSensorsEnergyTickElapsed(ANowTick, ALastTick: DWORD): Integer;
begin
  if ANowTick >= ALastTick then
    Result := ANowTick - ALastTick
  else
    Result := (High(DWORD) - ALastTick) + ANowTick + 1;
end;

function CpuSensorsIsPlausiblePowerW(APowerW: Double): Boolean;
begin
  Result := (not IsNan(APowerW)) and (not IsInfinite(APowerW)) and
    (APowerW >= cCpuPowerMinW) and (APowerW <= cCpuPowerMaxW);
end;

function CpuSensorsEnergyUnitFromEsu(AEsu: Integer; AMicroWattUnit: Boolean): Double;
begin
  if AMicroWattUnit then
    Result := 1.0e-6 * (1 shl AEsu)
  else
    Result := Power(0.5, AEsu);
end;

function CpuSensorsSamplePackagePowerW(
  const APwrUnitMsr, AEnergyMsr: DWORD; var ASample: TCpuEnergySample;
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
    ASample.EnergyUnitJ := CpuSensorsEnergyUnitFromEsu(esu, AMicroWattUnit);
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
  elapsedMs := CpuSensorsEnergyTickElapsed(nowTick, ASample.LastTick);
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

function CpuSensorsVendorId: string;
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

function CpuSensorsFamilyModel: Cardinal;
var
  regs: TCpuIdRegs;
begin
  CpuIdLeaf(1, regs);
  Result := (regs.Eax shr 8) and $FF0F;
end;

function CpuSensorsIntelUsesMicroWattRapl: Boolean;
var
  model: Cardinal;
begin
  model := CpuSensorsFamilyModel and $FF;
  Result := model in [$37, $4A, $4D, $5A, $5D, $4C];
end;

function CpuSensorsIntelPackagePowerW: Double;
begin
  Result := CpuSensorsSamplePackagePowerW(
    cMsrRaplPowerUnit, cMsrPkgEnergyStatus, GIntelEnergySample,
    CpuSensorsIntelUsesMicroWattRapl);
end;

function CpuSensorsAmdPackagePowerW: Double;
var
  family: Cardinal;
begin
  Result := -1;
  family := CpuSensorsFamilyModel shr 4;
  if family < $17 then
    Exit;
  Result := CpuSensorsSamplePackagePowerW(
    cMsrAmdPwrUnit, cMsrAmdPkgEnergyStat, GAmdEnergySample, False);
end;

function CpuSensorsAmdModel: Cardinal;
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

function CpuSensorsIsIntel: Boolean;
begin
  Result := SameText(CpuSensorsVendorId, 'GenuineIntel');
end;

function CpuSensorsIsAmd: Boolean;
begin
  Result := SameText(CpuSensorsVendorId, 'AuthenticAMD');
end;

function CpuSensorsIntelHasDts: Boolean;
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

function CpuSensorsIntelThermReadingValid(AEax: DWORD): Boolean;
begin
  Result := (AEax and cIntelThermReadingValid) <> 0;
end;

function CpuSensorsIntelDeltaFromTjMax(AEax: DWORD): Integer;
begin
  Result := Integer((AEax and cIntelThermDeltaMask) shr 16);
end;

function CpuSensorsAffinityMask(AIndex: Integer): ULONG_PTR;
begin
  if (AIndex < 0) or (AIndex >= SizeOf(ULONG_PTR) * 8) then
    Result := 0
  else
    Result := ULONG_PTR(UInt64(1) shl AIndex);
end;

function CpuSensorsIntelTjMaxForCore(ACoreIndex: Integer): Integer;
var
  mask: ULONG_PTR;
  eax, edx: DWORD;
  tjMax: Integer;
begin
  Result := 100;
  mask := CpuSensorsAffinityMask(ACoreIndex);
  if mask = 0 then
    Exit;
  if PawnIoReadMsrTx(cMsrIa32TemperatureTarget, mask, eax, edx) then
  begin
    tjMax := (eax shr 16) and $FF;
    if tjMax > 0 then
      Result := tjMax;
  end;
end;

function CpuSensorsIntelCoreIndexFromMask(AMask: ULONG_PTR): Integer;
var
  idx: Integer;
begin
  Result := 0;
  for idx := 0 to 31 do
  begin
    if AMask = CpuSensorsAffinityMask(idx) then
    begin
      Result := idx;
      Break;
    end;
  end;
end;

function CpuSensorsIntelTempFromMsrTx(
  const AMsrIndex: DWORD; AAffinity: ULONG_PTR): Double;
var
  eax, edx: DWORD;
  delta, tjMax, coreIdx: Integer;
begin
  Result := -1;
  if not PawnIoReadMsrTx(AMsrIndex, AAffinity, eax, edx) then
    Exit;
  if not CpuSensorsIntelThermReadingValid(eax) then
    Exit;
  delta := CpuSensorsIntelDeltaFromTjMax(eax);
  coreIdx := CpuSensorsIntelCoreIndexFromMask(AAffinity);
  tjMax := CpuSensorsIntelTjMaxForCore(coreIdx);
  Result := tjMax - delta;
end;

function CpuSensorsIntelCoreMaxTemp: Double;
var
  sysInfo: TSystemInfo;
  i: Integer;
  mask: ULONG_PTR;
  eax, edx: DWORD;
  delta, tjMax: Integer;
  temp, maxTemp: Double;
begin
  Result := -1;
  if not PawnIoIsMsrSupported or not CpuSensorsIntelHasDts then
    Exit;
  GetSystemInfo(sysInfo);
  maxTemp := -1;
  for i := 0 to sysInfo.dwNumberOfProcessors - 1 do
  begin
    mask := CpuSensorsAffinityMask(i);
    if mask = 0 then
      Break;
    if not PawnIoReadMsrTx(cMsrIa32ThermStatus, mask, eax, edx) then
      Continue;
    if not CpuSensorsIntelThermReadingValid(eax) then
      Continue;
    delta := CpuSensorsIntelDeltaFromTjMax(eax);
    tjMax := CpuSensorsIntelTjMaxForCore(i);
    temp := tjMax - delta;
    if temp > maxTemp then
      maxTemp := temp;
  end;
  if maxTemp >= 0 then
    Result := maxTemp;
end;

function CpuSensorsAmdZenSmnTemp: Double;
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

function CpuSensorsAmdZenSviPlaneOffsets(out APlane0Off, APlane1Off: DWORD): Boolean;
var
  model: Cardinal;
begin
  APlane0Off := 0;
  APlane1Off := 0;
  Result := False;
  if PawnIoBackend <> pbAmdFamily17 then
    Exit;
  model := CpuSensorsAmdModel;
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

function CpuSensorsAmdCoreVoltage: Double;
var
  sviTfn, plane0: DWORD;
  plane0Off, plane1Off: DWORD;
  vddCor: Cardinal;
begin
  Result := -1;
  if not CpuSensorsAmdZenSviPlaneOffsets(plane0Off, plane1Off) then
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

function CpuSensorsIntelVoltage: Double;
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
    mask := CpuSensorsAffinityMask(i);
    if mask = 0 then
      Break;
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

function CpuSensorsAmdTemp: Double;
var
  eax, edx: DWORD;
  family: Cardinal;
  raw: Integer;
begin
  Result := -1;
  family := CpuSensorsFamilyModel shr 4;
  if family >= $17 then
  begin
    if PawnIoBackend = pbAmdFamily17 then
      Exit(CpuSensorsAmdZenSmnTemp);
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

function CpuSensorsQuery(out AInfo: TCpuSensorInfo): Boolean;
var
  coreTemp, pkgTemp, voltage, powerW: Double;
begin
  CpuInitSensorInfo(AInfo);
  Result := False;
  if not PawnIoAvailable then
    Exit;

  if CpuSensorsIsIntel then
  begin
    coreTemp := CpuSensorsIntelCoreMaxTemp;
    if coreTemp >= 0 then
    begin
      AInfo.HasCoreTemp := True;
      AInfo.CoreTempC := coreTemp;
      Result := True;
    end;
    pkgTemp := CpuSensorsIntelTempFromMsrTx(cMsrIa32PackageThermStatus, 1);
    if pkgTemp < 0 then
      pkgTemp := coreTemp;
    if pkgTemp >= 0 then
    begin
      AInfo.HasPackageTemp := True;
      AInfo.PackageTempC := pkgTemp;
      Result := True;
    end;
    voltage := CpuSensorsIntelVoltage;
    if voltage > 0 then
    begin
      AInfo.HasVoltage := True;
      AInfo.VoltageV := voltage;
      Result := True;
    end;
    powerW := CpuSensorsIntelPackagePowerW;
    if CpuSensorsIsPlausiblePowerW(powerW) then
    begin
      AInfo.HasPower := True;
      AInfo.PowerW := powerW;
      Result := True;
    end;
  end
  else if CpuSensorsIsAmd then
  begin
    coreTemp := CpuSensorsAmdTemp;
    if coreTemp >= 0 then
    begin
      AInfo.HasCoreTemp := True;
      AInfo.CoreTempC := coreTemp;
      AInfo.HasPackageTemp := True;
      AInfo.PackageTempC := coreTemp;
      Result := True;
    end;
    voltage := CpuSensorsAmdCoreVoltage;
    if voltage > 0 then
    begin
      AInfo.HasVoltage := True;
      AInfo.VoltageV := voltage;
      Result := True;
    end;
    powerW := CpuSensorsAmdPackagePowerW;
    if CpuSensorsIsPlausiblePowerW(powerW) then
    begin
      AInfo.HasPower := True;
      AInfo.PowerW := powerW;
      Result := True;
    end;
  end;
end;

end.
