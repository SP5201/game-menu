program SensorDiag;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  Windows,
  AppPaths,
  PawnIoClient,
  PawnIoDriver,
  CpuInfoSensors,
  CpuInfoFan,
  CpuInfo,
  HardwarePdh;

procedure WriteRawSmn(const AName: string; AOffset: DWORD);
var
  raw: DWORD;
begin
  if PawnIoReadSmn(AOffset, raw) then
    WriteLn(Format('  SMN $%x %s = $%x', [AOffset, AName, raw]))
  else
    WriteLn(Format('  SMN $%x %s = READ FAIL', [AOffset, AName]));
end;

procedure WriteRawMsr(const AName: string; AIndex: DWORD);
var
  eax, edx: DWORD;
begin
  if PawnIoReadMsr(AIndex, eax, edx) then
    WriteLn(Format('  MSR $%x %s = EAX=$%x EDX=$%x', [AIndex, AName, eax, edx]))
  else
    WriteLn(Format('  MSR $%x %s = READ FAIL', [AIndex, AName]));
end;

var
  info: TCpuSensorInfo;
  fanRpm: Integer;
  pdhTemp: Double;
begin
  ConfigureNativeDllSearchPath;
  WriteLn('=== QDesktop SensorDiag ===');
  WriteLn('PawnIO MSR: ', BoolToStr(PawnIoAvailable, True));
  WriteLn('PawnIO LPC: ', BoolToStr(PawnIoLpcAvailable, True));
  if not PawnIoAvailable then
    WriteLn('PawnIO detail: ', PawnIoLoadFailureDetail);
  WriteLn('ExeDir: ', AppExeDirectory);
  WriteLn('BinDir: ', AppBinDirectory);
  WriteLn('PawnIO.sys: ', AppBinDllPath('PawnIO.sys'));
  WriteLn('Backend: ', Ord(PawnIoBackend));
  if PawnIoDriverServiceExists then
  begin
    WriteLn('Service running: ', BoolToStr(PawnIoDriverServiceIsRunning, True));
    WriteLn('Delete pending: ', BoolToStr(PawnIoDriverServiceDeletePending, True));
  end;
  WriteLn;

  if PawnIoAvailable then
  begin
    WriteLn('--- Raw MSR/SMN ---');
    WriteRawSmn('THM_TCON_CUR_TMP', $00059800);
    WriteRawSmn('SVI TFN', $0005A008);
    WriteRawSmn('SVI Plane0', $0005A010);
    WriteRawSmn('SVI Plane1', $0005A00C);
    WriteRawSmn('CCD1', $00059954);
    WriteRawMsr('Zen Tctl', $C0010058);
    WriteLn;
  end;

  if CpuSensorsQuery(info) then
  begin
    WriteLn('--- CpuSensorsQuery ---');
    if info.HasCoreTemp then
      WriteLn('  CoreTemp: ', Format('%.1f', [info.CoreTempC]), ' C');
    if info.HasPackageTemp then
      WriteLn('  PackageTemp: ', Format('%.1f', [info.PackageTempC]), ' C');
    if info.HasVoltage then
      WriteLn('  Voltage: ', Format('%.3f', [info.VoltageV]), ' V');
    if info.HasPower then
      WriteLn('  Power: ', Format('%.1f', [info.PowerW]), ' W');
  end
  else
    WriteLn('CpuSensorsQuery: no data');

  pdhTemp := HardwarePdhSampleCpuPackageTempC;
  if pdhTemp >= 0 then
    WriteLn('PDH ACPI fallback temp: ', Format('%.1f', [pdhTemp]), ' C');

  if CpuFanQueryRpm(fanRpm) then
    WriteLn('CPU Fan RPM: ', fanRpm)
  else
  begin
    WriteLn('CPU Fan RPM: --');
    if CpuFanLastDiag <> '' then
      WriteLn('Fan diag: ', CpuFanLastDiag);
  end;

  WriteLn;
  WriteLn('Tooltip sensors:');
  WriteLn('  ', CpuFormatSensorTemperatureText(info));
  WriteLn('  ', CpuFormatSensorVoltageText(info));
  WriteLn('  ', CpuFormatSensorFanSpeedText(info));
  WriteLn('  ', CpuFormatSensorPowerText(info));
end.
