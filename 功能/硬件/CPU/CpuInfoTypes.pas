unit CpuInfoTypes;

interface

uses
  Windows, SysUtils;

const
  cCpuDash = '--';

type
  TCpuStaticInfo = record
    Brand: string;
    Vendor: string;
    PhysicalCores: Integer;
    LogicalProcessors: Integer;
    BaseSpeedMhz: DWORD;
    CurrentSpeedMhz: DWORD;
    L1CacheBytes: DWORD;
    L2CacheBytes: DWORD;
    L3CacheBytes: DWORD;
  end;

  TCpuSensorInfo = record
    HasCoreTemp: Boolean;
    CoreTempC: Double;
    HasPackageTemp: Boolean;
    PackageTempC: Double;
    HasVoltage: Boolean;
    VoltageV: Double;
  end;

procedure CpuInitSensorInfo(out AInfo: TCpuSensorInfo);
function CpuFormatSensorTemperatureText(const AInfo: TCpuSensorInfo): string;
function CpuFormatSensorVoltageText(const AInfo: TCpuSensorInfo): string;

implementation

procedure CpuInitSensorInfo(out AInfo: TCpuSensorInfo);
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
end;

function CpuFormatSensorTemperatureText(const AInfo: TCpuSensorInfo): string;
var
  tempC: Double;
begin
  if AInfo.HasPackageTemp then
    tempC := AInfo.PackageTempC
  else if AInfo.HasCoreTemp then
    tempC := AInfo.CoreTempC
  else
  begin
    Result := cCpuDash;
    Exit;
  end;
  Result := IntToStr(Round(tempC)) + '°C';
end;

function CpuFormatSensorVoltageText(const AInfo: TCpuSensorInfo): string;
begin
  if not AInfo.HasVoltage then
    Result := cCpuDash
  else
    Result := StringReplace(Format('%.2f', [AInfo.VoltageV]), ',', '.', [rfReplaceAll]) + ' V';
end;

end.
