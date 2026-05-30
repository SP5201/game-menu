unit NwInfoParse;

{
  NwInfo stdout 键值行解析公共辅助（Cpu/Mem/Gpu/Net 模块共用）。
}

interface

uses
  Windows, SysUtils;

function NwInfoUnquoteValue(const ARaw: string): string;
function NwInfoParseLineKey(const ALine: string): string;
function NwInfoParseLineValue(const ALine: string): string;
function NwInfoTryParseDouble(const S: string; out AValue: Double): Boolean;
function NwInfoTryParseInt(const S: string; out AValue: Integer): Boolean;
function NwInfoTryParseDword(const S: string; out AValue: DWORD): Boolean;
function NwInfoTryParseUInt64(const S: string; out AValue: UInt64): Boolean;
function NwInfoTryParseCardinal(const S: string; out AValue: Cardinal): Boolean;
function NwInfoTryParsePercent(const S: string; out AValue: Double): Boolean;
function NwInfoTryParseBool(const S: string; out AValue: Boolean): Boolean;
function NwInfoParseHumanSizeBytes(const AText: string): DWORD;
procedure NwInfoUpdateMaxDouble(AHas: Boolean; AValue: Double; var ATargetHas: Boolean; var ATarget: Double);
procedure NwInfoUpdateFirstDouble(AHas: Boolean; AValue: Double; var ATargetHas: Boolean; var ATarget: Double);

implementation

function NwInfoUnquoteValue(const ARaw: string): string;
var
  textVal: string;
begin
  textVal := Trim(ARaw);
  if (Length(textVal) >= 2) and (textVal[1] = '''') and (textVal[Length(textVal)] = '''') then
    textVal := Copy(textVal, 2, Length(textVal) - 2);
  if SameText(textVal, 'NULL') or SameText(textVal, 'Unknown') then
    Result := ''
  else
    Result := textVal;
end;

function NwInfoParseLineKey(const ALine: string): string;
var
  sepPos: Integer;
begin
  sepPos := Pos(':', ALine);
  if sepPos = 0 then
    Result := ''
  else
    Result := Trim(Copy(ALine, 1, sepPos - 1));
end;

function NwInfoParseLineValue(const ALine: string): string;
var
  sepPos: Integer;
begin
  sepPos := Pos(':', ALine);
  if sepPos = 0 then
    Exit('');
  Result := NwInfoUnquoteValue(Copy(ALine, sepPos + 1, MaxInt));
end;

function NwInfoTryParseDouble(const S: string; out AValue: Double): Boolean;
begin
  Result := TryStrToFloat(StringReplace(Trim(S), ',', '.', [rfReplaceAll]), AValue);
end;

function NwInfoTryParseInt(const S: string; out AValue: Integer): Boolean;
begin
  Result := TryStrToInt(Trim(S), AValue);
end;

function NwInfoTryParseDword(const S: string; out AValue: DWORD): Boolean;
var
  n: Integer;
begin
  Result := TryStrToInt(Trim(S), n) and (n >= 0);
  if Result then
    AValue := DWORD(n);
end;

function NwInfoTryParseUInt64(const S: string; out AValue: UInt64): Boolean;
var
  i64: Int64;
begin
  Result := TryStrToInt64(Trim(S), i64) and (i64 >= 0);
  if Result then
    AValue := UInt64(i64);
end;

function NwInfoTryParseCardinal(const S: string; out AValue: Cardinal): Boolean;
var
  n: Integer;
begin
  Result := TryStrToInt(Trim(S), n) and (n >= 0);
  if Result then
    AValue := Cardinal(n);
end;

function NwInfoTryParsePercent(const S: string; out AValue: Double): Boolean;
var
  pctText: string;
begin
  pctText := Trim(StringReplace(S, '%', '', [rfReplaceAll]));
  Result := NwInfoTryParseDouble(pctText, AValue);
end;

function NwInfoTryParseBool(const S: string; out AValue: Boolean): Boolean;
var
  boolText: string;
begin
  boolText := LowerCase(Trim(S));
  if (boolText = 'true') or (boolText = '1') or (boolText = 'yes') then
  begin
    AValue := True;
    Exit(True);
  end;
  if (boolText = 'false') or (boolText = '0') or (boolText = 'no') then
  begin
    AValue := False;
    Exit(True);
  end;
  Result := False;
end;

function NwInfoParseHumanSizeBytes(const AText: string): DWORD;
var
  textVal, numPart, unitPart: string;
  sepPos: Integer;
  num: Double;
begin
  Result := 0;
  textVal := Trim(AText);
  if textVal = '' then
    Exit;
  sepPos := LastDelimiter(' ', textVal);
  if sepPos <= 0 then
    Exit;
  numPart := Trim(Copy(textVal, 1, sepPos - 1));
  unitPart := AnsiUpperCase(Trim(Copy(textVal, sepPos + 1, MaxInt)));
  if not TryStrToFloat(StringReplace(numPart, ',', '.', [rfReplaceAll]), num) then
    Exit;
  if unitPart = 'B' then
    Result := DWORD(Round(num))
  else if unitPart = 'KB' then
    Result := DWORD(Round(num * 1024))
  else if unitPart = 'MB' then
    Result := DWORD(Round(num * 1024 * 1024))
  else if unitPart = 'GB' then
    Result := DWORD(Round(num * 1024 * 1024 * 1024));
end;

procedure NwInfoUpdateMaxDouble(AHas: Boolean; AValue: Double; var ATargetHas: Boolean; var ATarget: Double);
begin
  if not AHas then
    Exit;
  if (not ATargetHas) or (AValue > ATarget) then
  begin
    ATargetHas := True;
    ATarget := AValue;
  end;
end;

procedure NwInfoUpdateFirstDouble(AHas: Boolean; AValue: Double; var ATargetHas: Boolean; var ATarget: Double);
begin
  if AHas and (not ATargetHas) then
  begin
    ATargetHas := True;
    ATarget := AValue;
  end;
end;

end.
