unit MemJedecLookup;

{
  JEDEC JEP106 内存模组厂商 ID 映射。
  运行时从 Bin\jep106.inc 加载（JEP106BO May 2026）。
}

interface

function MemJedecManufacturerText(AId: Word): string;

implementation

uses
  Classes, SysUtils, SyncObjs, AppPaths;

const
  cJep106FileName = 'jep106.inc';
  cJedecBankCount = 18;
  cJedecCodeMax = 127;

var
  GJedecNames: array[0..cJedecBankCount - 1, 1..cJedecCodeMax] of string;
  GJedecLoaded: Boolean;
  GJedecLoadLock: TCriticalSection;

function TryParseJep106Entry(const ALine: string; out ABank, ACode: Byte;
  out AName: string): Boolean;
var
  s, bankStr, hexStr: string;
  i, pBracket, pHex, pQuote1, pQuote2, bankIdx: Integer;
begin
  Result := False;
  AName := '';
  s := Trim(ALine);
  if (Length(s) < 10) or (s[1] <> '[') then
    Exit;

  pBracket := Pos(']', s);
  if pBracket < 3 then
    Exit;
  bankStr := Copy(s, 2, pBracket - 2);
  if not TryStrToInt(bankStr, bankIdx) then
    Exit;
  if (bankIdx < 0) or (bankIdx >= cJedecBankCount) then
    Exit;
  ABank := Byte(bankIdx);

  pHex := Pos('0x', LowerCase(s));
  if pHex = 0 then
    Exit;
  i := pHex + 2;
  hexStr := '';
  while (i <= Length(s)) and CharInSet(s[i], ['0'..'9', 'a'..'f', 'A'..'F']) do
  begin
    hexStr := hexStr + s[i];
    Inc(i);
  end;
  if hexStr = '' then
    Exit;
  ACode := StrToInt('$' + hexStr);
  if (ACode < 1) or (ACode > cJedecCodeMax) then
    Exit;

  pQuote1 := pHex + Pos('"', Copy(s, pHex, MaxInt)) - 1;
  if pQuote1 < pHex then
    Exit;
  pQuote2 := pQuote1 + Pos('"', Copy(s, pQuote1 + 1, MaxInt));
  if pQuote2 <= pQuote1 then
    Exit;
  AName := Copy(s, pQuote1 + 1, pQuote2 - pQuote1 - 1);
  Result := AName <> '';
end;

procedure LoadJedecTableFromFile;
var
  path: string;
  sl: TStringList;
  i: Integer;
  bank, code: Byte;
  name: string;
begin
  path := AppBinDirectory + cJep106FileName;
  if not FileExists(path) then
    Exit;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(path);
    for i := 0 to sl.Count - 1 do
      if TryParseJep106Entry(sl[i], bank, code, name) then
        GJedecNames[bank, code] := name;
  finally
    sl.Free;
  end;
end;

procedure EnsureJedecTableLoaded;
begin
  if GJedecLoaded then
    Exit;
  GJedecLoadLock.Enter;
  try
    if GJedecLoaded then
      Exit;
    LoadJedecTableFromFile;
    GJedecLoaded := True;
  finally
    GJedecLoadLock.Leave;
  end;
end;

function MemJedecNormalizeId(AId: Word): Word;
var
  hi, lo: Byte;
begin
  hi := AId shr 8;
  lo := AId and $FF;
  if lo = $7F then
    Result := Word(1 shl 8) or (hi and $7F)
  else if hi = 0 then
  begin
    if lo >= $80 then
      Result := lo and $7F
    else
      Result := AId;
  end
  else
    Result := Word(hi shl 8) or (lo and $7F);
end;

function MemJedecLookupEntry(ABank, ACode: Byte): string;
begin
  EnsureJedecTableLoaded;
  if (ABank < cJedecBankCount) and (ACode >= 1) and (ACode <= cJedecCodeMax) then
    Result := GJedecNames[ABank, ACode]
  else
    Result := '';
end;

function MemJedecManufacturerText(AId: Word): string;
var
  norm: Word;
  bank, code: Byte;
begin
  norm := MemJedecNormalizeId(AId);
  bank := norm shr 8;
  code := norm and $7F;
  Result := MemJedecLookupEntry(bank, code);
  if Result = '' then
    Result := '未知';
end;

initialization
  GJedecLoadLock := TCriticalSection.Create;

finalization
  GJedecLoadLock.Free;

end.
