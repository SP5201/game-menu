unit MemInfoTypes;

interface

uses
  SysUtils, Classes;

const
  cMemDash = '--';

type
  TMemStaticInfo = record
    UsagePct: Integer;
    PhysTotal: UInt64;
    PhysFree: UInt64;
    SpecText: string;
    SlotCount: Cardinal;
    Modules: TStringList;
  end;

procedure MemInitStaticInfo(out AInfo: TMemStaticInfo);
procedure MemFreeStaticInfo(var AInfo: TMemStaticInfo);
function MemFormatBytes(const ABytes: UInt64): string;

implementation

uses
  Math;

procedure MemInitStaticInfo(out AInfo: TMemStaticInfo);
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  AInfo.UsagePct := -1;
  AInfo.Modules := nil;
end;

procedure MemFreeStaticInfo(var AInfo: TMemStaticInfo);
begin
  FreeAndNil(AInfo.Modules);
end;

function MemFormatBytes(const ABytes: UInt64): string;
var
  gb, mb, kb: Double;
begin
  if ABytes = 0 then
    Result := '0B'
  else if ABytes >= 1024 * 1024 * 1024 then
  begin
    gb := ABytes / (1024 * 1024 * 1024);
    if Abs(gb - Round(gb)) < 0.05 then
      Result := IntToStr(Round(gb)) + 'GB'
    else
      Result := StringReplace(Format('%.1f', [gb]), ',', '.', [rfReplaceAll]) + 'GB';
  end
  else if ABytes >= 1024 * 1024 then
  begin
    mb := ABytes / (1024 * 1024);
    if Abs(mb - Round(mb)) < 0.05 then
      Result := IntToStr(Round(mb)) + 'MB'
    else
      Result := StringReplace(Format('%.1f', [mb]), ',', '.', [rfReplaceAll]) + 'MB';
  end
  else
  begin
    kb := ABytes / 1024;
    if kb < 1 then
      Result := IntToStr(ABytes) + 'B'
    else if Abs(kb - Round(kb)) < 0.05 then
      Result := IntToStr(Round(kb)) + 'KB'
    else
      Result := StringReplace(Format('%.1f', [kb]), ',', '.', [rfReplaceAll]) + 'KB';
  end;
end;

end.
