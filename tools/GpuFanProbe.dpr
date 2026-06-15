program GpuFanProbe;
{$APPTYPE CONSOLE}
uses
  SysUtils,
  GpuInfo;

var
  sensors: TGpuSensorInfo;
begin
  GpuPreloadSensors;
  sensors := GpuQuerySensorInfo;
  if sensors.HasFanSpeed then
    Writeln('OK ', sensors.FanSpeedRpm)
  else
    Writeln('FAIL no fan data');
end.
