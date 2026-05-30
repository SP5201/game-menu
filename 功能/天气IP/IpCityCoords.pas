unit IpCityCoords;

interface

uses
  SysUtils;

function IpCityCoordsPath: string;
function IpCityCoordsUserPath: string;
procedure IpCityCoordsEnsureLoaded;
procedure IpCityCoordsReload;
function IpCityCoordsLookup(const ACity, ARegion: string; out ALat, ALon: Double): Boolean;
function IpCityCoordsUpdate(const ACity: string; ALat, ALon: Double): Boolean;
function IpCityCoordsDownloadFromUrl(const AUrl: string): Boolean;

implementation

uses
  Classes, AppConfig, NetHttpWorker;

function NormalizeCityJsonDownloadUrl(const AUrl: string): string;
var
  u: string;
begin
  u := Trim(AUrl);
  if u = '' then
    Exit('');
  if Pos('github.com/', LowerCase(u)) > 0 then
  begin
    u := StringReplace(u, 'https://github.com/', 'https://raw.githubusercontent.com/', [rfIgnoreCase]);
    u := StringReplace(u, 'http://github.com/', 'http://raw.githubusercontent.com/', [rfIgnoreCase]);
    u := StringReplace(u, '/blob/', '/', [rfIgnoreCase]);
  end;
  Result := u;
end;

function IpCityCoordsDownloadFromUrl(const AUrl: string): Boolean;
var
  req: TNetHttpRequest;
  resp: TNetHttpResponse;
  downloadUrl, body: string;
  fs: TFileStream;
  raw: UTF8String;
begin
  Result := False;
  downloadUrl := NormalizeCityJsonDownloadUrl(AUrl);
  if downloadUrl = '' then
    Exit;
  req.Url := downloadUrl;
  req.Kind := hkText;
  req.SaveToFile := '';
  req.Options := TNetHttpWorker.DefaultOptions;
  req.UserData := 0;
  resp := TNetHttpWorker.ExecuteSync(req);
  if not resp.Ok then
    Exit;
  body := Trim(resp.BodyText);
  if (body = '') or (body[1] <> '[') then
    Exit;
  ForceDirectories(TAppConfig.DataDirectory);
  raw := UTF8String(body);
  fs := TFileStream.Create(IpCityCoordsPath, fmCreate);
  try
    if Length(raw) > 0 then
      fs.WriteBuffer(raw[1], Length(raw));
  finally
    fs.Free;
  end;
  IpCityCoordsReload;
  Result := True;
end;

const
  cCityCoordsFileName = 'city.json';
  cCityUserCoordsFileName = 'city_user.json';
  cUserOverrideLevel = 99;

type
  TCityCoordEntry = record
    Name: string;
    Lat: Double;
    Lon: Double;
    Level: Integer;
  end;

var
  GEntries: array of TCityCoordEntry;
  GLoaded: Boolean;

function IpCityCoordsPath: string;
begin
  Result := IncludeTrailingPathDelimiter(TAppConfig.DataDirectory) + cCityCoordsFileName;
end;

function IpCityCoordsUserPath: string;
begin
  Result := IncludeTrailingPathDelimiter(TAppConfig.DataDirectory) + cCityUserCoordsFileName;
end;

function FindCharFrom(const S: string; ACh: Char; StartPos: Integer): Integer;
var
  i: Integer;
begin
  for i := StartPos to Length(S) do
    if S[i] = ACh then
      Exit(i);
  Result := 0;
end;

function ExtractBalancedJsonObject(const Json: string; ObjStart: Integer): string;
var
  i, depth: Integer;
begin
  Result := '';
  if (ObjStart < 1) or (ObjStart > Length(Json)) or (Json[ObjStart] <> '{') then
    Exit;
  depth := 0;
  for i := ObjStart to Length(Json) do
  begin
    if Json[i] = '{' then
      Inc(depth)
    else if Json[i] = '}' then
    begin
      Dec(depth);
      if depth = 0 then
      begin
        Result := Copy(Json, ObjStart, i - ObjStart + 1);
        Exit;
      end;
    end;
  end;
end;

function ExtractJsonStringField(const Obj, FieldName: string): string;
var
  marker: string;
  p, q: Integer;
begin
  Result := '';
  marker := '"' + FieldName + '":';
  p := Pos(marker, Obj);
  if p = 0 then
    Exit;
  p := p + Length(marker);
  while (p <= Length(Obj)) and CharInSet(Obj[p], [' ', #9]) do
    Inc(p);
  if (p + 3 <= Length(Obj)) and SameText(Copy(Obj, p, 4), 'null') then
    Exit;
  if (p > Length(Obj)) or (Obj[p] <> '"') then
    Exit;
  Inc(p);
  q := p;
  while (q <= Length(Obj)) and (Obj[q] <> '"') do
    Inc(q);
  Result := Copy(Obj, p, q - p);
end;

function ExtractJsonIntegerField(const Obj, FieldName: string): Integer;
var
  marker, numText: string;
  p: Integer;
begin
  Result := 0;
  marker := '"' + FieldName + '":';
  p := Pos(marker, Obj);
  if p = 0 then
    Exit;
  p := p + Length(marker);
  while (p <= Length(Obj)) and CharInSet(Obj[p], [' ', #9]) do
    Inc(p);
  numText := '';
  while (p <= Length(Obj)) and CharInSet(Obj[p], ['0'..'9', '-']) do
  begin
    numText := numText + Obj[p];
    Inc(p);
  end;
  Result := StrToIntDef(numText, 0);
end;

function JsonCoordToFloat(const Obj, FieldName: string): Double;
var
  fs: TFormatSettings;
  s: string;
begin
  s := ExtractJsonStringField(Obj, FieldName);
  if s = '' then
    Exit(0);
  fs := TFormatSettings.Create('en-US');
  Result := StrToFloatDef(StringReplace(s, ',', '.', [rfReplaceAll]), 0, fs);
end;

function LoadTextFileUtf8(const APath: string): string;
var
  fs: TFileStream;
  raw: UTF8String;
  n: Integer;
begin
  Result := '';
  fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    n := fs.Size;
    if n <= 0 then
      Exit;
    SetLength(raw, n);
    fs.ReadBuffer(raw[1], n);
    if (n >= 3) and (Ord(raw[1]) = $EF) and (Ord(raw[2]) = $BB) and (Ord(raw[3]) = $BF) then
      Result := UTF8ToString(Copy(raw, 4, MaxInt))
    else
      Result := UTF8ToString(raw);
  finally
    fs.Free;
  end;
end;

function LookupPlaceName(const S: string): string;
begin
  Result := Trim(S);
  if (Result = '') or (Result = '--') then
    Result := '';
end;

function NormalizePlaceName(const S: string): string;
var
  r: string;
begin
  r := Trim(S);
  if r = '' then
    Exit('');
  if (Length(r) >= 3) and (Copy(r, Length(r) - 1, 2) = '市') then
    Delete(r, Length(r) - 1, 2);
  if (Length(r) >= 3) and (Copy(r, Length(r) - 1, 2) = '省') then
    Delete(r, Length(r) - 1, 2);
  if (Length(r) >= 6) and (Copy(r, Length(r) - 2, 3) = '自治区') then
    Delete(r, Length(r) - 2, 3);
  Result := r;
end;

function FindEntry(const AName: string): Integer;
var
  i: Integer;
  key: string;
begin
  Result := -1;
  key := NormalizePlaceName(AName);
  if key = '' then
    Exit;
  for i := 0 to High(GEntries) do
    if GEntries[i].Name = key then
      Exit(i);
end;

procedure MergeEntry(const AName: string; ALat, ALon: Double; ALevel: Integer);
var
  idx, n: Integer;
  key: string;
begin
  key := NormalizePlaceName(AName);
  if key = '' then
    Exit;
  idx := FindEntry(key);
  if idx >= 0 then
  begin
    if ALevel < GEntries[idx].Level then
      Exit;
    GEntries[idx].Lat := ALat;
    GEntries[idx].Lon := ALon;
    GEntries[idx].Level := ALevel;
    Exit;
  end;
  n := Length(GEntries);
  SetLength(GEntries, n + 1);
  GEntries[n].Name := key;
  GEntries[n].Lat := ALat;
  GEntries[n].Lon := ALon;
  GEntries[n].Level := ALevel;
end;

procedure RegisterObjectKeys(const Obj: string; ALat, ALon: Double; ALevel: Integer);
var
  nameVal, shortName, provinceVal, cityVal: string;
begin
  nameVal := ExtractJsonStringField(Obj, 'name');
  shortName := ExtractJsonStringField(Obj, 'shortName');
  provinceVal := ExtractJsonStringField(Obj, 'province');
  cityVal := ExtractJsonStringField(Obj, 'city');
  if shortName <> '' then
    MergeEntry(shortName, ALat, ALon, ALevel);
  if nameVal <> '' then
    MergeEntry(nameVal, ALat, ALon, ALevel);
  if (ALevel = 1) and (provinceVal <> '') then
    MergeEntry(provinceVal, ALat, ALon, ALevel)
  else if (ALevel = 2) and (cityVal <> '') then
    MergeEntry(cityVal, ALat, ALon, ALevel);
end;

procedure LoadBuiltinEntries;
begin
  SetLength(GEntries, 0);
  MergeEntry('北京', 39.9042, 116.4074, 1);
  MergeEntry('上海', 31.2304, 121.4737, 1);
  MergeEntry('广州', 23.1291, 113.2644, 2);
  MergeEntry('深圳', 22.5431, 114.0579, 2);
  MergeEntry('东莞', 23.0207, 113.7518, 2);
end;

procedure LoadOverrideFromJsonFile(const APath: string);
var
  json, objText: string;
  lat, lon: Double;
  p, objStart: Integer;
begin
  if not FileExists(APath) then
    Exit;
  json := LoadTextFileUtf8(APath);
  if json = '' then
    Exit;
  p := 1;
  while p <= Length(json) do
  begin
    objStart := FindCharFrom(json, '{', p);
    if objStart = 0 then
      Break;
    objText := ExtractBalancedJsonObject(json, objStart);
    if objText = '' then
      Break;
    lat := JsonCoordToFloat(objText, 'latitude');
    lon := JsonCoordToFloat(objText, 'longitude');
    if (lat <> 0) or (lon <> 0) then
      RegisterObjectKeys(objText, lat, lon, cUserOverrideLevel);
    p := objStart + Length(objText);
  end;
end;

function JsonEscapeString(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    if S[i] = '\' then
      Result := Result + '\\'
    else if S[i] = '"' then
      Result := Result + '\"'
    else
      Result := Result + S[i];
  end;
end;

function BuildUserCityObject(const ACity: string; ALat, ALon: Double): string;
var
  cityName, shortName: string;
  latText, lonText: string;
begin
  cityName := Trim(ACity);
  shortName := NormalizePlaceName(cityName);
  if shortName = '' then
    shortName := cityName;
  latText := FloatToStrF(ALat, ffFixed, 15, 6);
  lonText := FloatToStrF(ALon, ffFixed, 15, 6);
  Result :=
    '{' +
    '"name":"' + JsonEscapeString(cityName) + '",' +
    '"shortName":"' + JsonEscapeString(shortName) + '",' +
    '"province":"",' +
    '"city":"' + JsonEscapeString(cityName) + '",' +
    '"latitude":"' + latText + '",' +
    '"longitude":"' + lonText + '",' +
    '"level":2' +
    '}';
end;

function SaveUserCityEntry(const ACity: string; ALat, ALon: Double): Boolean;
var
  path, json, objText, newObj, key, entryKey: string;
  objects: TStringList;
  p, objStart, i, idx: Integer;
  fs: TFileStream;
  raw: UTF8String;
begin
  Result := False;
  key := NormalizePlaceName(ACity);
  if key = '' then
    Exit;
  newObj := BuildUserCityObject(ACity, ALat, ALon);
  path := IpCityCoordsUserPath;
  objects := TStringList.Create;
  try
    if FileExists(path) then
    begin
      json := LoadTextFileUtf8(path);
      p := 1;
      while p <= Length(json) do
      begin
        objStart := FindCharFrom(json, '{', p);
        if objStart = 0 then
          Break;
        objText := ExtractBalancedJsonObject(json, objStart);
        if objText = '' then
          Break;
        objects.Add(objText);
        p := objStart + Length(objText);
      end;
    end;
    idx := -1;
    for i := 0 to objects.Count - 1 do
    begin
      entryKey := NormalizePlaceName(ExtractJsonStringField(objects[i], 'shortName'));
      if entryKey = '' then
        entryKey := NormalizePlaceName(ExtractJsonStringField(objects[i], 'name'));
      if entryKey = key then
      begin
        idx := i;
        Break;
      end;
    end;
    if idx >= 0 then
      objects[idx] := newObj
    else
      objects.Add(newObj);
    json := '[' + sLineBreak;
    for i := 0 to objects.Count - 1 do
    begin
      json := json + '  ' + objects[i];
      if i < objects.Count - 1 then
        json := json + ',' + sLineBreak
      else
        json := json + sLineBreak;
    end;
    json := json + ']' + sLineBreak;
    ForceDirectories(TAppConfig.DataDirectory);
    raw := UTF8String(json);
    fs := TFileStream.Create(path, fmCreate);
    try
      if Length(raw) > 0 then
        fs.WriteBuffer(raw[1], Length(raw));
    finally
      fs.Free;
    end;
    Result := True;
  finally
    objects.Free;
  end;
end;

procedure IpCityCoordsReload;
begin
  SetLength(GEntries, 0);
  GLoaded := False;
end;

procedure LoadFromJsonFile(const APath: string);
var
  json, objText: string;
  level: Integer;
  lat, lon: Double;
  p, objStart: Integer;
begin
  if not FileExists(APath) then
    Exit;
  json := LoadTextFileUtf8(APath);
  if json = '' then
    Exit;
  p := 1;
  while p <= Length(json) do
  begin
    objStart := FindCharFrom(json, '{', p);
    if objStart = 0 then
      Break;
    objText := ExtractBalancedJsonObject(json, objStart);
    if objText = '' then
      Break;
    level := ExtractJsonIntegerField(objText, 'level');
    if (level >= 1) and (level <= 2) then
    begin
      lat := JsonCoordToFloat(objText, 'latitude');
      lon := JsonCoordToFloat(objText, 'longitude');
      if (lat <> 0) or (lon <> 0) then
        RegisterObjectKeys(objText, lat, lon, level);
    end;
    p := objStart + Length(objText);
  end;
end;

procedure IpCityCoordsEnsureLoaded;
begin
  if GLoaded then
    Exit;
  LoadBuiltinEntries;
  LoadFromJsonFile(IpCityCoordsPath);
  LoadOverrideFromJsonFile(IpCityCoordsUserPath);
  GLoaded := True;
end;

function IpCityCoordsUpdate(const ACity: string; ALat, ALon: Double): Boolean;
begin
  Result := SaveUserCityEntry(ACity, ALat, ALon);
  if Result then
    IpCityCoordsReload;
end;

function IpCityCoordsLookup(const ACity, ARegion: string; out ALat, ALon: Double): Boolean;
var
  idx: Integer;
begin
  Result := False;
  ALat := 0;
  ALon := 0;
  IpCityCoordsEnsureLoaded;
  idx := FindEntry(LookupPlaceName(ACity));
  if idx < 0 then
    idx := FindEntry(LookupPlaceName(ARegion));
  if idx < 0 then
    Exit;
  ALat := GEntries[idx].Lat;
  ALon := GEntries[idx].Lon;
  Result := True;
end;

end.
