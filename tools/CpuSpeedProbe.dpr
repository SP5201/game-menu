program CpuSpeedProbe;
{$APPTYPE CONSOLE}
uses
  SysUtils,
  CpuInfo,
  CpuInfoNative;

var
  info: TCpuStaticInfo;
  loaded: Boolean;
  speed: DWORD;
begin
  CpuPreloadHintData;
  info := CpuPeekStaticInfo(loaded);
  Writeln('BaseSpeedMhz=', info.BaseSpeedMhz);
  Writeln('CachedCurrentSpeedMhz=', info.CurrentSpeedMhz);
  speed := CpuNativeQueryCurrentSpeedMhz;
  Writeln('Query1=', speed);
  Sleep(1000);
  speed := CpuNativeQueryCurrentSpeedMhz;
  Writeln('Query2=', speed);
  Writeln('--- Tooltip preview ---');
  Writeln(CpuFormatTooltip('12%'));
end.
