unit MemInfo;

{
  内存悬停提示：优先 NwInfoRunner（--sys --smbios=16,17），失败或缺字段时回退 MemInfoNative。
}

interface

uses
  SysUtils;

procedure MemPreloadHintData;
function MemFormatTooltip(const AUsagePctText: string): string;

implementation

uses
  Windows, Classes, MemInfoTypes, MemInfoNative, MemInfoNwInfo, NwInfoRunner;

var
  GStaticLoaded: Boolean;
  GStaticInfo: TMemStaticInfo;
  GStaticLoadLock: TRTLCriticalSection;
  GStaticLoading: Boolean;

procedure MemInitStaticLoadLock;
begin
  InitializeCriticalSection(GStaticLoadLock);
end;

procedure MemDoneStaticLoadLock;
begin
  DeleteCriticalSection(GStaticLoadLock);
end;

function AppendLine(const ALines, ALine: string): string;
begin
  if ALine = '' then
    Result := ALines
  else if ALines = '' then
    Result := ALine
  else
    Result := ALines + sLineBreak + ALine;
end;

procedure MemMergeMissingFields(var ATarget, ANative: TMemStaticInfo);
begin
  if ATarget.PhysTotal = 0 then
    ATarget.PhysTotal := ANative.PhysTotal;
  if ATarget.PhysFree = 0 then
    ATarget.PhysFree := ANative.PhysFree;
  if ATarget.UsagePct < 0 then
    ATarget.UsagePct := ANative.UsagePct;
  if ATarget.SpecText = '' then
    ATarget.SpecText := ANative.SpecText;
  if ATarget.SlotCount = 0 then
    ATarget.SlotCount := ANative.SlotCount;
end;

procedure MemTakeStaticInfo(var AInfo: TMemStaticInfo);
begin
  MemFreeStaticInfo(GStaticInfo);
  GStaticInfo := AInfo;
  AInfo.Modules := nil;
  AInfo.SpecText := '';
  AInfo.UsagePct := -1;
  AInfo.PhysTotal := 0;
  AInfo.PhysFree := 0;
  AInfo.SlotCount := 0;
end;

procedure MemLoadStaticInfo;
var
  nwInfo, nativeInfo: TMemStaticInfo;
begin
  if GStaticLoaded then
  begin
    Exit;
  end;
  EnterCriticalSection(GStaticLoadLock);
  try
    if GStaticLoaded then
    begin
      Exit;
    end;
    if GStaticLoading then
    begin
      Exit;
    end;
    GStaticLoading := True;
    try
      MemInitStaticInfo(nwInfo);
      nativeInfo := MemNativeQueryStaticInfo;
      if MemTryLoadFromNwInfo(nwInfo) then
      begin
        MemMergeMissingFields(nwInfo, nativeInfo);
        MemFreeStaticInfo(nativeInfo);
        MemTakeStaticInfo(nwInfo);
        GStaticLoaded := True;
        Exit;
      end;
      MemFreeStaticInfo(nwInfo);
      if (nativeInfo.PhysTotal > 0) or (nativeInfo.UsagePct >= 0) then
      begin
        MemTakeStaticInfo(nativeInfo);
        GStaticLoaded := True;
      end
      else
      begin
        MemFreeStaticInfo(nativeInfo);
        MemFreeStaticInfo(GStaticInfo);
        MemInitStaticInfo(GStaticInfo);
      end;
    finally
      GStaticLoading := False;
    end;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
end;

procedure MemPreloadHintData;
begin
  MemLoadStaticInfo;
end;

function MemFormatTooltip(const AUsagePctText: string): string;
var
  usageText: string;
  memTotal, memInUse: UInt64;
  i: Integer;
  nwExe, nwDir: string;
  moduleLines: TStringList;
  info: TMemStaticInfo;
  usagePct: Integer;
  physTotal, physFree: UInt64;
  specText: string;
  slotCount: Cardinal;
begin
  if not GStaticLoaded then
  begin
    if (AUsagePctText <> '') and (AUsagePctText <> cMemDash) then
      usageText := AUsagePctText
    else
      usageText := cMemDash;
    Exit('使用率：' + usageText + sLineBreak + '（详细信息加载中…）');
  end;
  EnterCriticalSection(GStaticLoadLock);
  try
    usagePct := GStaticInfo.UsagePct;
    physTotal := GStaticInfo.PhysTotal;
    physFree := GStaticInfo.PhysFree;
    specText := GStaticInfo.SpecText;
    slotCount := GStaticInfo.SlotCount;
    moduleLines := nil;
    if GStaticInfo.Modules <> nil then
    begin
      moduleLines := TStringList.Create;
      moduleLines.Assign(GStaticInfo.Modules);
    end;
  finally
    LeaveCriticalSection(GStaticLoadLock);
  end;
  MemInitStaticInfo(info);
  info.UsagePct := usagePct;
  info.PhysTotal := physTotal;
  info.PhysFree := physFree;
  info.SpecText := specText;
  info.SlotCount := slotCount;
  info.Modules := moduleLines;
  try
    if (AUsagePctText <> '') and (AUsagePctText <> cMemDash) then
      usageText := AUsagePctText
    else if info.UsagePct >= 0 then
      usageText := IntToStr(info.UsagePct) + '%'
    else
      usageText := cMemDash;

    Result := '使用率：' + usageText;

    memTotal := info.PhysTotal;
    if memTotal > 0 then
    begin
      if info.PhysFree > memTotal then
        memInUse := memTotal
      else
        memInUse := memTotal - info.PhysFree;
      Result := AppendLine(Result, '总内存：' + MemFormatBytes(memTotal));
      Result := AppendLine(Result, '使用：' + MemFormatBytes(memInUse));
    end
    else
    begin
      Result := AppendLine(Result, '总内存：' + cMemDash);
      Result := AppendLine(Result, '使用：' + cMemDash);
    end;

    if info.SpecText <> '' then
      Result := AppendLine(Result, '最大可用：' + info.SpecText);
    if info.SlotCount > 0 then
      Result := AppendLine(Result, '插槽数：' + IntToStr(info.SlotCount));
    if info.Modules <> nil then
      for i := 0 to info.Modules.Count - 1 do
        Result := AppendLine(Result, string(info.Modules[i]));
    if (info.SlotCount = 0) and ((info.Modules = nil) or (info.Modules.Count = 0)) and
      not NwInfoResolveExe(nwExe, nwDir) then
      Result := AppendLine(Result, string('（未找到 NwInfo\nwinfox86.exe，请运行 scripts\copy_nwinfo_runtime.ps1）'));
  finally
    FreeAndNil(info.Modules);
  end;
end;

initialization
  MemInitStaticLoadLock;
  MemInitStaticInfo(GStaticInfo);

finalization
  MemFreeStaticInfo(GStaticInfo);
  MemDoneStaticLoadLock;

end.
