unit GpuInfoTypes;

interface

uses
  SysUtils;

const
  cGpuDash = '--';

type
  TGpuStaticInfo = record
    Device: string;
    Location: string;
    PnpId: string;
    HasIntegrated: Boolean;
    Integrated: Boolean;
    PcieLink: string;
  end;

  TGpuSensorInfo = record
    HasUtilization: Boolean;
    UtilizationPct: Double;
    HasTemperature: Boolean;
    TemperatureC: Double;
    HasTotalMem: Boolean;
    TotalMemBytes: UInt64;
    HasFreeMem: Boolean;
    FreeMemBytes: UInt64;
    HasMemUsage: Boolean;
    MemUsagePct: Integer;
    HasPower: Boolean;
    PowerW: Double;
    HasFrequency: Boolean;
    FrequencyMhz: Double;
    HasMemFrequency: Boolean;
    MemFrequencyMhz: Double;
    HasVoltage: Boolean;
    VoltageV: Double;
    HasFanSpeed: Boolean;
    FanSpeedRpm: Integer;
  end;

procedure GpuInitStaticInfo(out AInfo: TGpuStaticInfo);
procedure GpuInitSensorInfo(out AInfo: TGpuSensorInfo);
function GpuFormatTemperatureText(const AInfo: TGpuSensorInfo): string;
function GpuFormatPowerText(const AInfo: TGpuSensorInfo): string;
function GpuFormatFrequencyText(const AHas: Boolean; const AMhz: Double): string;
function GpuFormatVoltageText(const AInfo: TGpuSensorInfo): string;
function GpuFormatFanSpeedText(const AInfo: TGpuSensorInfo): string;
function GpuFormatMemoryText(const AInfo: TGpuSensorInfo): string;

implementation

uses
  MemInfoTypes;

procedure GpuInitStaticInfo(out AInfo: TGpuStaticInfo);
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
end;

procedure GpuInitSensorInfo(out AInfo: TGpuSensorInfo);
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
end;

function GpuFormatTemperatureText(const AInfo: TGpuSensorInfo): string;
begin
  if not AInfo.HasTemperature then
    Result := cGpuDash
  else
    Result := IntToStr(Round(AInfo.TemperatureC)) + '°C';
end;

function GpuFormatPowerText(const AInfo: TGpuSensorInfo): string;
begin
  if not AInfo.HasPower then
    Result := cGpuDash
  else
    Result := StringReplace(Format('%.0f', [AInfo.PowerW]), ',', '.', [rfReplaceAll]) + ' W';
end;

function GpuFormatFrequencyText(const AHas: Boolean; const AMhz: Double): string;
begin
  if not AHas then
    Result := cGpuDash
  else
    Result := IntToStr(Round(AMhz)) + ' MHz';
end;

function GpuFormatVoltageText(const AInfo: TGpuSensorInfo): string;
begin
  if not AInfo.HasVoltage then
    Result := cGpuDash
  else
    Result := StringReplace(Format('%.2f', [AInfo.VoltageV]), ',', '.', [rfReplaceAll]) + ' V';
end;

function GpuFormatFanSpeedText(const AInfo: TGpuSensorInfo): string;
begin
  if not AInfo.HasFanSpeed then
    Result := cGpuDash
  else
    Result := IntToStr(AInfo.FanSpeedRpm) + ' RPM';
end;

function GpuFormatMemoryText(const AInfo: TGpuSensorInfo): string;
var
  usedBytes: UInt64;
  pctText: string;
begin
  if AInfo.HasTotalMem and AInfo.HasFreeMem then
  begin
    if AInfo.FreeMemBytes > AInfo.TotalMemBytes then
      usedBytes := AInfo.TotalMemBytes
    else
      usedBytes := AInfo.TotalMemBytes - AInfo.FreeMemBytes;
    if AInfo.HasMemUsage then
      pctText := ' (' + IntToStr(AInfo.MemUsagePct) + '%)'
    else
      pctText := '';
    Result := MemFormatBytes(usedBytes) + ' / ' + MemFormatBytes(AInfo.TotalMemBytes) + pctText;
  end
  else if AInfo.HasTotalMem then
    Result := MemFormatBytes(AInfo.TotalMemBytes)
  else if AInfo.HasMemUsage then
    Result := IntToStr(AInfo.MemUsagePct) + '%'
  else
    Result := cGpuDash;
end;

end.
