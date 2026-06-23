unit JsonUtil;

interface

uses
  SysUtils, superobject;

function JsonParseText(const AText: string): ISuperObject;
function JsonParseFile(const APath: string): ISuperObject;
function JsonObjField(const AObj: ISuperObject; const AField: string): ISuperObject;
function JsonDoubleField(const AObj: ISuperObject; const AField: string;
  const ADefault: Double): Double;
function JsonIntField(const AObj: ISuperObject; const AField: string;
  const ADefault: Integer): Integer;
function JsonStringField(const AObj: ISuperObject; const AField: string): string;
function JsonArrayFirstDouble(const AObj: ISuperObject; const AField: string;
  const ADefault: Double): Double;
function JsonArrayFirstString(const AObj: ISuperObject; const AField: string): string;

implementation

uses
  Classes;

function ReadFileBytes(const APath: string): TBytes;
var
  fs: TFileStream;
begin
  SetLength(Result, 0);
  fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    if fs.Size <= 0 then
      Exit;
    SetLength(Result, fs.Size);
    fs.ReadBuffer(Result[0], fs.Size);
  finally
    fs.Free;
  end;
end;

function IsValidUtf8(const Data: TBytes; Offset: Integer): Boolean;
var
  i, n, b, need: Integer;
begin
  Result := True;
  n := Length(Data);
  i := Offset;
  while i < n do
  begin
    b := Data[i];
    if b <= $7F then
      Inc(i)
    else if (b and $E0) = $C0 then
    begin
      need := 1;
      if (b < $C2) or (i + need >= n) then
        Exit(False);
      while need > 0 do
      begin
        Inc(i);
        if (Data[i] and $C0) <> $80 then
          Exit(False);
        Dec(need);
      end;
      Inc(i);
    end
    else if (b and $F0) = $E0 then
    begin
      need := 2;
      if i + need >= n then
        Exit(False);
      while need > 0 do
      begin
        Inc(i);
        if (Data[i] and $C0) <> $80 then
          Exit(False);
        Dec(need);
      end;
      Inc(i);
    end
    else if (b and $F8) = $F0 then
    begin
      need := 3;
      if (b > $F4) or (i + need >= n) then
        Exit(False);
      while need > 0 do
      begin
        Inc(i);
        if (Data[i] and $C0) <> $80 then
          Exit(False);
        Dec(need);
      end;
      Inc(i);
    end
    else
      Exit(False);
  end;
end;

function LooksLikeUtf16LE(const Data: TBytes): Boolean;
var
  i, sample, zerosEven, zerosOdd: Integer;
begin
  Result := False;
  if Length(Data) < 4 then
    Exit;
  sample := Length(Data);
  if sample > 256 then
    sample := 256;
  zerosEven := 0;
  zerosOdd := 0;
  for i := 0 to sample - 1 do
    if Data[i] = 0 then
      if Odd(i) then
        Inc(zerosOdd)
      else
        Inc(zerosEven);
  Result := (zerosOdd >= 2) and (zerosOdd > zerosEven * 2);
end;

function LooksLikeUtf16BE(const Data: TBytes): Boolean;
var
  i, sample, zerosEven, zerosOdd: Integer;
begin
  Result := False;
  if Length(Data) < 4 then
    Exit;
  sample := Length(Data);
  if sample > 256 then
    sample := 256;
  zerosEven := 0;
  zerosOdd := 0;
  for i := 0 to sample - 1 do
    if Data[i] = 0 then
      if Odd(i) then
        Inc(zerosOdd)
      else
        Inc(zerosEven);
  Result := (zerosEven >= 2) and (zerosEven > zerosOdd * 2);
end;

function DecodeTextFileBytes(const Data: TBytes): string;
var
  n: Integer;
begin
  Result := '';
  n := Length(Data);
  if n <= 0 then
    Exit;
  if (n >= 3) and (Data[0] = $EF) and (Data[1] = $BB) and (Data[2] = $BF) then
    Exit(TEncoding.UTF8.GetString(Data, 3, n - 3));
  if (n >= 2) and (Data[0] = $FF) and (Data[1] = $FE) then
    Exit(TEncoding.Unicode.GetString(Data, 2, n - 2));
  if (n >= 2) and (Data[0] = $FE) and (Data[1] = $FF) then
    Exit(TEncoding.BigEndianUnicode.GetString(Data, 2, n - 2));
  if LooksLikeUtf16LE(Data) then
    Exit(TEncoding.Unicode.GetString(Data, 0, n));
  if LooksLikeUtf16BE(Data) then
    Exit(TEncoding.BigEndianUnicode.GetString(Data, 0, n));
  if IsValidUtf8(Data, 0) then
    Exit(TEncoding.UTF8.GetString(Data, 0, n));
  Result := TEncoding.Default.GetString(Data, 0, n);
end;

function LoadEncodedTextFile(const APath: string): string;
var
  raw: TBytes;
begin
  Result := '';
  if not FileExists(APath) then
    Exit;
  raw := ReadFileBytes(APath);
  Result := DecodeTextFileBytes(raw);
end;

function JsonParseText(const AText: string): ISuperObject;
begin
  Result := nil;
  if Trim(AText) = '' then
    Exit;
  Result := TSuperObject.ParseString(PChar(AText), False);
end;

function JsonParseFile(const APath: string): ISuperObject;
var
  text: string;
begin
  Result := nil;
  if not FileExists(APath) then
    Exit;
  text := LoadEncodedTextFile(APath);
  if Trim(text) = '' then
    Exit;
  Result := JsonParseText(text);
end;

function JsonObjField(const AObj: ISuperObject; const AField: string): ISuperObject;
begin
  Result := nil;
  if AObj = nil then
    Exit;
  Result := AObj.O[AField];
end;

function JsonDoubleField(const AObj: ISuperObject; const AField: string;
  const ADefault: Double): Double;
var
  sub: ISuperObject;
begin
  Result := ADefault;
  sub := JsonObjField(AObj, AField);
  if sub = nil then
    Exit;
  if sub.DataType in [stDouble, stInt, stCurrency] then
    Result := sub.AsDouble
  else
    Result := StrToFloatDef(
      StringReplace(sub.AsString, ',', '.', [rfReplaceAll]), ADefault);
end;

function JsonIntField(const AObj: ISuperObject; const AField: string;
  const ADefault: Integer): Integer;
var
  sub: ISuperObject;
begin
  Result := ADefault;
  sub := JsonObjField(AObj, AField);
  if sub = nil then
    Exit;
  if sub.DataType in [stInt, stDouble, stCurrency] then
    Result := sub.AsInteger
  else
    Result := StrToIntDef(sub.AsString, ADefault);
end;

function JsonStringField(const AObj: ISuperObject; const AField: string): string;
var
  sub: ISuperObject;
begin
  Result := '';
  sub := JsonObjField(AObj, AField);
  if sub = nil then
    Exit;
  Result := sub.AsString;
end;

function JsonArrayFirstDouble(const AObj: ISuperObject; const AField: string;
  const ADefault: Double): Double;
var
  sub: ISuperObject;
  arr: TSuperArray;
begin
  Result := ADefault;
  sub := JsonObjField(AObj, AField);
  if (sub = nil) or (sub.DataType <> stArray) then
    Exit;
  arr := sub.AsArray;
  if (arr = nil) or (arr.Length <= 0) then
    Exit;
  if arr.O[0].DataType in [stDouble, stInt, stCurrency] then
    Result := arr.O[0].AsDouble
  else
    Result := StrToFloatDef(
      StringReplace(arr.O[0].AsString, ',', '.', [rfReplaceAll]), ADefault);
end;

function JsonArrayFirstString(const AObj: ISuperObject; const AField: string): string;
var
  sub: ISuperObject;
  arr: TSuperArray;
begin
  Result := '';
  sub := JsonObjField(AObj, AField);
  if (sub = nil) or (sub.DataType <> stArray) then
    Exit;
  arr := sub.AsArray;
  if (arr = nil) or (arr.Length <= 0) then
    Exit;
  Result := arr.O[0].AsString;
end;

end.
