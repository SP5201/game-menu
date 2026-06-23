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
  Classes, AppConfig, NetHttpWorker, JsonUtil, superobject;

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
  req.Options := NetHttpDefaultOptions;
  req.UserData := 0;
  resp := NetHttpExecuteSync(req);
  if not resp.Ok then
    Exit;
  body := Trim(resp.BodyText);
  if (body = '') or (JsonParseText(body) = nil) then
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

procedure RegisterObjectKeys(const Obj: ISuperObject; ALat, ALon: Double; ALevel: Integer);
var
  nameVal, shortName, provinceVal, cityVal: string;
begin
  if Obj = nil then
    Exit;
  nameVal := JsonStringField(Obj, 'name');
  shortName := JsonStringField(Obj, 'shortName');
  provinceVal := JsonStringField(Obj, 'province');
  cityVal := JsonStringField(Obj, 'city');
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

procedure LoadCityCoordsFile(const APath: string; AUserOverride: Boolean);
var
  root: ISuperObject;
  arr: TSuperArray;
  i, level, useLevel: Integer;
  obj: ISuperObject;
  lat, lon: Double;
begin
  if not FileExists(APath) then
    Exit;
  root := JsonParseFile(APath);
  if (root = nil) or (root.DataType <> stArray) then
    Exit;
  arr := root.AsArray;
  for i := 0 to arr.Length - 1 do
  begin
    obj := arr.O[i];
    if obj = nil then
      Continue;
    level := JsonIntField(obj, 'level', 0);
    useLevel := level;
    if AUserOverride then
      useLevel := cUserOverrideLevel
    else if (level < 1) or (level > 2) then
      Continue;
    lat := JsonDoubleField(obj, 'latitude', 0);
    lon := JsonDoubleField(obj, 'longitude', 0);
    if (lat <> 0) or (lon <> 0) then
      RegisterObjectKeys(obj, lat, lon, useLevel);
  end;
end;

function BuildUserCityObject(const ACity: string; ALat, ALon: Double): ISuperObject;
var
  cityName, shortName: string;
begin
  Result := TSuperObject.Create(stObject);
  cityName := Trim(ACity);
  shortName := NormalizePlaceName(cityName);
  if shortName = '' then
    shortName := cityName;
  Result.S['name'] := cityName;
  Result.S['shortName'] := shortName;
  Result.S['province'] := '';
  Result.S['city'] := cityName;
  Result.S['latitude'] := FloatToStrF(ALat, ffFixed, 15, 6);
  Result.S['longitude'] := FloatToStrF(ALon, ffFixed, 15, 6);
  Result.I['level'] := 2;
end;

function SaveUserCityEntry(const ACity: string; ALat, ALon: Double): Boolean;
var
  path: string;
  root: ISuperObject;
  arr: TSuperArray;
  key, entryKey: string;
  i, idx: Integer;
begin
  Result := False;
  key := NormalizePlaceName(ACity);
  if key = '' then
    Exit;
  path := IpCityCoordsUserPath;
  root := JsonParseFile(path);
  if (root = nil) or (root.DataType <> stArray) then
    root := TSuperObject.Create(stArray);
  arr := root.AsArray;
  idx := -1;
  for i := 0 to arr.Length - 1 do
  begin
    entryKey := NormalizePlaceName(JsonStringField(arr.O[i], 'shortName'));
    if entryKey = '' then
      entryKey := NormalizePlaceName(JsonStringField(arr.O[i], 'name'));
    if entryKey = key then
    begin
      idx := i;
      Break;
    end;
  end;
  if idx >= 0 then
    arr.O[idx] := BuildUserCityObject(ACity, ALat, ALon)
  else
    arr.Add(BuildUserCityObject(ACity, ALat, ALon));
  ForceDirectories(TAppConfig.DataDirectory);
  Result := root.SaveTo(path, True) > 0;
end;

procedure IpCityCoordsReload;
begin
  SetLength(GEntries, 0);
  GLoaded := False;
end;

procedure IpCityCoordsEnsureLoaded;
begin
  if GLoaded then
    Exit;
  if (not FileExists(IpCityCoordsPath)) and TAppConfig.IsCityCoordsUpdateEnabled then
    IpCityCoordsDownloadFromUrl(TAppConfig.GetCityCoordsUrl);
  LoadBuiltinEntries;
  LoadCityCoordsFile(IpCityCoordsPath, False);
  LoadCityCoordsFile(IpCityCoordsUserPath, True);
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
