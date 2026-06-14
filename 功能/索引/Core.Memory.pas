unit Core.Memory;

interface

uses
  Windows, SysUtils, Core.Model;

const
  cGrowChunkFolders = 4096;
  cGrowChunkFiles = 8192;
  cGrowChunkNamePool = 256 * 1024;

function Utf8ToLowerAnsi(const AUtf8: PAnsiChar): AnsiString;
function AnsiCharLower(ACh: AnsiChar): AnsiChar;
function AnsiStrLen(const S: PAnsiChar): Integer;
function AnsiStrComp(L, R: PAnsiChar): Integer;
function ExtEntryNameToString(const AEntry: TExtEntry): string;
procedure GrowFolders(var ADB: TEverythingDB);
procedure GrowFiles(var ADB: TEverythingDB);
procedure GrowNamePool(var ADB: TEverythingDB; AExtraBytes: Cardinal);
function WideToUtf8(const AName: PWideChar; ACharLen: Integer): AnsiString;
function AppendUtf8Name(var ADB: TEverythingDB; const AUtf8: PAnsiChar; ALen: Integer = -1): Cardinal;
function AppendWideName(var ADB: TEverythingDB; const AName: PWideChar; ACharLen: Integer): Cardinal;
function FindOrAddExt(var ADB: TEverythingDB; const AExtUtf8: PAnsiChar): Word;
function NamePoolOffsetIsValid(const ADB: TEverythingDB; AOffset: Cardinal): Boolean;
function NamePoolPtrAt(const ADB: TEverythingDB; AOffset: Cardinal): PAnsiChar;
function CompareAnsiPtrTextCI(L, R: PAnsiChar): Integer;
function NamePoolCompareText(const ADB: TEverythingDB; ALeftOff, ARightOff: Cardinal): Integer;
function NamePoolToString(const ADB: TEverythingDB; AOffset: Cardinal): string;
function NamePoolToAnsi(const ADB: TEverythingDB; AOffset: Cardinal): AnsiString;
function ExtractExtUtf8(const ANameUtf8: PAnsiChar): PAnsiChar;
function FileTimeToUnixDate(const AFileTime: Int64): Cardinal;
function UnixDateToDelta(const ABaseDate, ADate: Cardinal): Word;

implementation

function AnsiStrLen(const S: PAnsiChar): Integer;
var
  p: PAnsiChar;
begin
  Result := 0;
  if S = nil then
    Exit;
  p := S;
  while p^ <> #0 do
  begin
    Inc(p);
    Inc(Result);
  end;
end;

function AnsiCharLower(ACh: AnsiChar): AnsiChar;
begin
  if (ACh >= 'A') and (ACh <= 'Z') then
    Result := AnsiChar(Ord(ACh) + 32)
  else
    Result := ACh;
end;

function AnsiStrComp(L, R: PAnsiChar): Integer;
begin
  if L = nil then
    L := '';
  if R = nil then
    R := '';
  while True do
  begin
    if L^ <> R^ then
      Exit(Ord(L^) - Ord(R^));
    if L^ = #0 then
      Exit(0);
    Inc(L);
    Inc(R);
  end;
end;

function AnsiStrPas(const S: PAnsiChar): AnsiString;
var
  len: Integer;
begin
  if S = nil then
    Exit('');
  len := AnsiStrLen(S);
  SetLength(Result, len);
  if len > 0 then
    Move(S^, Result[1], len);
end;

function ExtEntryNameToString(const AEntry: TExtEntry): string;
begin
  Result := string(AnsiStrPas(@AEntry.ExtName[0]));
end;

function Utf8ToLowerAnsi(const AUtf8: PAnsiChar): AnsiString;
var
  i, len: Integer;
  p: PAnsiChar;
begin
  if AUtf8 = nil then
    Exit('');
  len := AnsiStrLen(AUtf8);
  SetLength(Result, len);
  if len = 0 then
    Exit;
  p := AUtf8;
  for i := 1 to len do
  begin
    Result[i] := AnsiCharLower(p^);
    Inc(p);
  end;
end;

procedure GrowFolders(var ADB: TEverythingDB);
var
  newCap: Integer;
begin
  if ADB.FolderCount < Length(ADB.Folders) then
    Exit;
  if Length(ADB.Folders) = 0 then
    newCap := cGrowChunkFolders
  else
    newCap := Length(ADB.Folders) + cGrowChunkFolders;
  SetLength(ADB.Folders, newCap);
end;

procedure GrowFiles(var ADB: TEverythingDB);
var
  newCap: Integer;
begin
  if ADB.FileCount < Length(ADB.Files) then
    Exit;
  if Length(ADB.Files) = 0 then
    newCap := cGrowChunkFiles
  else
    newCap := Length(ADB.Files) + cGrowChunkFiles;
  SetLength(ADB.Files, newCap);
end;

procedure GrowNamePool(var ADB: TEverythingDB; AExtraBytes: Cardinal);
var
  need, newCap: Cardinal;
begin
  need := ADB.NamePoolUsed + AExtraBytes + 1;
  if need <= Cardinal(Length(ADB.NamePool)) then
    Exit;
  if Length(ADB.NamePool) = 0 then
    newCap := cGrowChunkNamePool
  else
  begin
    newCap := Cardinal(Length(ADB.NamePool));
    while newCap < need do
      newCap := newCap + cGrowChunkNamePool;
  end;
  SetLength(ADB.NamePool, newCap);
end;

function WideToUtf8(const AName: PWideChar; ACharLen: Integer): AnsiString;
var
  n: Integer;
begin
  if (AName = nil) or (ACharLen <= 0) then
    Exit('');
  n := WideCharToMultiByte(CP_UTF8, 0, AName, ACharLen, nil, 0, nil, nil);
  if n <= 0 then
    Exit('');
  SetLength(Result, n);
  WideCharToMultiByte(CP_UTF8, 0, AName, ACharLen, PAnsiChar(Result), n, nil, nil);
end;

function AppendUtf8Name(var ADB: TEverythingDB; const AUtf8: PAnsiChar; ALen: Integer): Cardinal;
var
  len: Integer;
begin
  if (AUtf8 = nil) or (AUtf8^ = #0) then
    Exit(0);
  if ALen < 0 then
    len := AnsiStrLen(AUtf8)
  else
    len := ALen;
  GrowNamePool(ADB, Cardinal(len));
  Result := ADB.NamePoolUsed;
  if len > 0 then
    Move(AUtf8^, ADB.NamePool[Result], len);
  ADB.NamePool[Result + Cardinal(len)] := 0;
  Inc(ADB.NamePoolUsed, Cardinal(len) + 1);
end;

function AppendWideName(var ADB: TEverythingDB; const AName: PWideChar; ACharLen: Integer): Cardinal;
var
  utf8: AnsiString;
begin
  utf8 := WideToUtf8(AName, ACharLen);
  Result := AppendUtf8Name(ADB, PAnsiChar(utf8), Length(utf8));
end;

function FindOrAddExt(var ADB: TEverythingDB; const AExtUtf8: PAnsiChar): Word;
var
  i, n: Integer;
  ext: AnsiString;
begin
  Result := 0;
  if (AExtUtf8 = nil) or (AExtUtf8^ = #0) then
    Exit;
  ext := Utf8ToLowerAnsi(AExtUtf8);
  for i := 0 to ADB.ExtCount - 1 do
    if AnsiStrComp(@ADB.ExtTable[i].ExtName[0], PAnsiChar(ext)) = 0 then
      Exit(ADB.ExtTable[i].ExtID);
  if ADB.ExtCount >= cMaxExtTable then
    Exit;
  n := Length(ext);
  if n > cExtNameMaxLen then
    n := cExtNameMaxLen;
  FillChar(ADB.ExtTable[ADB.ExtCount].ExtName, SizeOf(ADB.ExtTable[ADB.ExtCount].ExtName), 0);
  if n > 0 then
    Move(ext[1], ADB.ExtTable[ADB.ExtCount].ExtName[0], n);
  ADB.ExtTable[ADB.ExtCount].ExtID := Word(ADB.ExtCount + 1);
  Inc(ADB.ExtCount);
  Result := Word(ADB.ExtCount);
end;

function NamePoolOffsetIsValid(const ADB: TEverythingDB; AOffset: Cardinal): Boolean;
begin
  Result := (AOffset < ADB.NamePoolUsed) and (Cardinal(AOffset) < Cardinal(Length(ADB.NamePool)));
end;

function NamePoolPtrAt(const ADB: TEverythingDB; AOffset: Cardinal): PAnsiChar;
begin
  if not NamePoolOffsetIsValid(ADB, AOffset) then
    Exit(nil);
  Result := PAnsiChar(@ADB.NamePool[AOffset]);
end;

function CompareAnsiPtrTextCI(L, R: PAnsiChar): Integer;
var
  lc, rc: AnsiChar;
begin
  if L = nil then
    L := '';
  if R = nil then
    R := '';
  while True do
  begin
    lc := AnsiCharLower(L^);
    rc := AnsiCharLower(R^);
    if lc <> rc then
      Exit(Ord(lc) - Ord(rc));
    if lc = #0 then
      Exit(0);
    Inc(L);
    Inc(R);
  end;
end;

function NamePoolCompareText(const ADB: TEverythingDB; ALeftOff, ARightOff: Cardinal): Integer;
begin
  Result := CompareAnsiPtrTextCI(NamePoolPtrAt(ADB, ALeftOff), NamePoolPtrAt(ADB, ARightOff));
end;

function NamePoolToAnsi(const ADB: TEverythingDB; AOffset: Cardinal): AnsiString;
var
  p: PAnsiChar;
  len, maxLen: Integer;
begin
  if not NamePoolOffsetIsValid(ADB, AOffset) then
    Exit('');
  maxLen := Integer(ADB.NamePoolUsed) - Integer(AOffset);
  p := PAnsiChar(@ADB.NamePool[AOffset]);
  len := AnsiStrLen(p);
  if len > maxLen then
    len := maxLen;
  SetLength(Result, len);
  if len > 0 then
    Move(p^, Result[1], len);
end;

function AnsiBytesToDisplayString(const ABytes: AnsiString): string;
var
  wlen, i: Integer;
begin
  if Length(ABytes) = 0 then
    Exit('');
  wlen := MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(ABytes), Length(ABytes), nil, 0);
  if wlen > 0 then
  begin
    SetLength(Result, wlen);
    if MultiByteToWideChar(CP_UTF8, 0, PAnsiChar(ABytes), Length(ABytes), PWideChar(Result), wlen) > 0 then
      Exit;
  end;
  wlen := MultiByteToWideChar(CP_ACP, 0, PAnsiChar(ABytes), Length(ABytes), nil, 0);
  if wlen > 0 then
  begin
    SetLength(Result, wlen);
    if MultiByteToWideChar(CP_ACP, 0, PAnsiChar(ABytes), Length(ABytes), PWideChar(Result), wlen) > 0 then
      Exit;
  end;
  SetLength(Result, Length(ABytes));
  for i := 1 to Length(ABytes) do
    Result[i] := Char(Byte(ABytes[i]));
end;

function NamePoolToString(const ADB: TEverythingDB; AOffset: Cardinal): string;
var
  ansi: AnsiString;
begin
  ansi := NamePoolToAnsi(ADB, AOffset);
  Result := AnsiBytesToDisplayString(ansi);
end;

function ExtractExtUtf8(const ANameUtf8: PAnsiChar): PAnsiChar;
var
  p: PAnsiChar;
begin
  Result := nil;
  if ANameUtf8 = nil then
    Exit;
  p := ANameUtf8 + AnsiStrLen(ANameUtf8);
  while p > ANameUtf8 do
  begin
    if p^ = '.' then
    begin
      Result := p + 1;
      Exit;
    end;
    Dec(p);
  end;
end;

function FileTimeToUnixDate(const AFileTime: Int64): Cardinal;
const
  cUnixEpochDiff = 116444736000000000;
var
  ft: TFileTime;
  st: TSystemTime;
begin
  if AFileTime <= 0 then
    Exit(0);
  ft.dwLowDateTime := DWORD(AFileTime);
  ft.dwHighDateTime := DWORD(AFileTime shr 32);
  if not FileTimeToSystemTime(ft, st) then
    Exit(0);
  Result := Cardinal(DateTimeToTimeStamp(
    EncodeDate(st.wYear, st.wMonth, st.wDay) +
    EncodeTime(st.wHour, st.wMinute, st.wSecond, st.wMilliseconds div 1000)
  ).Time);
end;

function UnixDateToDelta(const ABaseDate, ADate: Cardinal): Word;
var
  delta: Integer;
begin
  delta := Integer(ADate) - Integer(ABaseDate);
  if delta < 0 then
    delta := 0;
  if delta > High(Word) then
    delta := High(Word);
  Result := Word(delta);
end;

end.
