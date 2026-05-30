unit MemInfoNative;

{
  内存信息 Native 回退：GlobalMemoryStatusEx 获取物理内存总量/可用/使用率。
  SMBIOS 插槽与条子信息需 NwInfo；Native 不提供 Modules/Spec/SlotCount。
}

interface

uses
  SysUtils, MemInfoTypes;

function MemNativeQueryStaticInfo: TMemStaticInfo;

implementation

uses
  Windows;

function MemNativeQueryStaticInfo: TMemStaticInfo;
var
  memStatus: TMemoryStatusEx;
begin
  MemInitStaticInfo(Result);
  memStatus.dwLength := SizeOf(memStatus);
  if not GlobalMemoryStatusEx(memStatus) then
    Exit;
  Result.PhysTotal := memStatus.ullTotalPhys;
  Result.PhysFree := memStatus.ullAvailPhys;
  if memStatus.dwMemoryLoad <= 100 then
    Result.UsagePct := memStatus.dwMemoryLoad;
end;

end.
