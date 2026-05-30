unit GpuInfoNative;

{
  GPU 信息 Native 回退：EnumDisplayDevicesW 获取活动显示适配器名称。
  显存/传感器需 NwInfo；Native 不提供传感器字段。
}

interface

uses
  SysUtils, GpuInfoTypes;

function GpuNativeQueryStaticInfo: TGpuStaticInfo;

implementation

uses
  Windows;

const
  cDisplayDeviceAttachedToDesktop = $00000001;
  cDisplayDevicePrimaryDevice = $00000004;

function GpuNativeTryPickDevice(const ADevInfo: TDisplayDeviceW; out AInfo: TGpuStaticInfo): Boolean;
var
  name: string;
begin
  Result := False;
  if (ADevInfo.StateFlags and cDisplayDeviceAttachedToDesktop) = 0 then
    Exit;
  name := Trim(string(ADevInfo.DeviceString));
  if name = '' then
    Exit;
  if SameText(name, 'Microsoft Basic Display Driver') then
    Exit;
  AInfo.Device := name;
  Result := True;
end;

function GpuNativeQueryStaticInfo: TGpuStaticInfo;
var
  devInfo: TDisplayDeviceW;
  i: Integer;
  fallback: TGpuStaticInfo;
  hasFallback: Boolean;
begin
  GpuInitStaticInfo(Result);
  GpuInitStaticInfo(fallback);
  hasFallback := False;
  for i := 0 to 31 do
  begin
    FillChar(devInfo, SizeOf(devInfo), 0);
    devInfo.cb := SizeOf(devInfo);
    if not EnumDisplayDevicesW(nil, DWORD(i), devInfo, 0) then
      Break;
    if not GpuNativeTryPickDevice(devInfo, Result) then
      Continue;
    if (devInfo.StateFlags and cDisplayDevicePrimaryDevice) <> 0 then
      Exit;
    if not hasFallback then
    begin
      fallback := Result;
      hasFallback := True;
    end;
  end;
  if hasFallback then
    Result := fallback;
end;

end.
