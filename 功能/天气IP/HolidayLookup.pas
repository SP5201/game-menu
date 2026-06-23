unit HolidayLookup;

{
  中国法定节假日与调休：内置 Resource\Holidays\YYYY.json（holiday-cn 格式），离线查询。
}

interface

uses
  SysUtils;

function HolidayFormatTooltipLines: string;

implementation

uses
  Windows, DateUtils, Generics.Collections, JsonUtil, superobject, AppPaths;

const
  cHolidayScanMaxDays = 400;

type
  THolidayEntry = record
    Name: string;
    IsOffDay: Boolean;
  end;

var
  GHolidayLock: TRTLCriticalSection;
  GHolidayMap: TDictionary<string, THolidayEntry>;
  GHolidayLoadedFrom: Integer;
  GHolidayLoadedTo: Integer;

function HolidayJsonPath(AYear: Integer): string;
begin
  Result := AppExeDirectory + 'Resource\Holidays\' + IntToStr(AYear) + '.json';
end;

function JsonIsOffDay(const AObj: ISuperObject): Boolean;
var
  sub: ISuperObject;
begin
  Result := False;
  sub := JsonObjField(AObj, 'isOffDay');
  if sub = nil then
    Exit;
  if sub.DataType = stBoolean then
    Result := sub.AsBoolean
  else
    Result := JsonIntField(AObj, 'isOffDay', 0) <> 0;
end;

procedure LoadHolidayYear(AYear: Integer);
var
  root, daysArr, dayObj: ISuperObject;
  arr: TSuperArray;
  i: Integer;
  dateStr, name: string;
  entry: THolidayEntry;
begin
  if not FileExists(HolidayJsonPath(AYear)) then
    Exit;
  root := JsonParseFile(HolidayJsonPath(AYear));
  if root = nil then
    Exit;
  daysArr := JsonObjField(root, 'days');
  if (daysArr = nil) or (daysArr.DataType <> stArray) then
    Exit;
  arr := daysArr.AsArray;
  if arr = nil then
    Exit;
  for i := 0 to arr.Length - 1 do
  begin
    dayObj := arr.O[i];
    if dayObj = nil then
      Continue;
    dateStr := Trim(JsonStringField(dayObj, 'date'));
    name := Trim(JsonStringField(dayObj, 'name'));
    if (dateStr = '') or (name = '') then
      Continue;
    entry.Name := name;
    entry.IsOffDay := JsonIsOffDay(dayObj);
    GHolidayMap.AddOrSetValue(dateStr, entry);
  end;
end;

procedure EnsureHolidayLoaded;
var
  st: TSystemTime;
  curYear, nextYear: Integer;
begin
  GetLocalTime(st);
  curYear := st.wYear;
  nextYear := curYear + 1;
  EnterCriticalSection(GHolidayLock);
  try
    if (GHolidayLoadedFrom = curYear) and (GHolidayLoadedTo = nextYear) then
      Exit;
    if GHolidayMap = nil then
      GHolidayMap := TDictionary<string, THolidayEntry>.Create
    else
      GHolidayMap.Clear;
    LoadHolidayYear(curYear);
    LoadHolidayYear(nextYear);
    GHolidayLoadedFrom := curYear;
    GHolidayLoadedTo := nextYear;
  finally
    LeaveCriticalSection(GHolidayLock);
  end;
end;

function DateToKey(ADate: TDateTime): string;
var
  y, m, d: Word;
begin
  DecodeDate(ADate, y, m, d);
  Result := Format('%.4d-%.2d-%.2d', [y, m, d]);
end;

function LocalToday: TDateTime;
var
  st: TSystemTime;
begin
  GetLocalTime(st);
  Result := EncodeDate(st.wYear, st.wMonth, st.wDay);
end;

function TryGetHoliday(const ADateKey: string; out AEntry: THolidayEntry): Boolean;
begin
  Result := False;
  FillChar(AEntry, SizeOf(AEntry), 0);
  if GHolidayMap = nil then
    Exit;
  Result := GHolidayMap.TryGetValue(ADateKey, AEntry);
end;

function IsOffDayClusterStart(ADate: TDateTime): Boolean;
var
  entry, prevEntry: THolidayEntry;
begin
  Result := False;
  if not TryGetHoliday(DateToKey(ADate), entry) or not entry.IsOffDay then
    Exit;
  if not TryGetHoliday(DateToKey(IncDay(ADate, -1)), prevEntry) then
    Exit(True);
  Result := not (prevEntry.IsOffDay and SameText(prevEntry.Name, entry.Name));
end;

procedure AdvancePastCurrentOffBlock(var ADate: TDateTime);
var
  entry: THolidayEntry;
  blockName: string;
begin
  if not TryGetHoliday(DateToKey(ADate), entry) or not entry.IsOffDay then
    Exit;
  blockName := entry.Name;
  repeat
    ADate := IncDay(ADate, 1);
    if not TryGetHoliday(DateToKey(ADate), entry) then
      Break;
  until not entry.IsOffDay or not SameText(entry.Name, blockName);
end;

function FindNextOffHolidayStart(const AFromDate: TDateTime; out AName: string;
  out AStartDate: TDateTime): Boolean;
var
  probe: TDateTime;
  entry, prevEntry: THolidayEntry;
  delta: Integer;
begin
  Result := False;
  AName := '';
  for delta := 0 to cHolidayScanMaxDays do
  begin
    probe := IncDay(AFromDate, delta);
    if not TryGetHoliday(DateToKey(probe), entry) or not entry.IsOffDay then
      Continue;
    if delta > 0 then
    begin
      if TryGetHoliday(DateToKey(IncDay(probe, -1)), prevEntry) and prevEntry.IsOffDay and
         SameText(prevEntry.Name, entry.Name) then
        Continue;
    end;
    AName := entry.Name;
    AStartDate := probe;
    Exit(True);
  end;
end;

function HolidayFormatTooltipLines: string;
var
  today, searchFrom, startDate: TDateTime;
  name: string;
  daysLeft: Integer;
  entry: THolidayEntry;
begin
  Result := '';
  EnsureHolidayLoaded;
  if (GHolidayMap = nil) or (GHolidayMap.Count = 0) then
    Exit;

  today := LocalToday;
  if IsOffDayClusterStart(today) and TryGetHoliday(DateToKey(today), entry) then
  begin
    name := entry.Name;
    daysLeft := 0;
  end
  else
  begin
    searchFrom := today;
    if TryGetHoliday(DateToKey(today), entry) and entry.IsOffDay then
      AdvancePastCurrentOffBlock(searchFrom);
    if not FindNextOffHolidayStart(searchFrom, name, startDate) then
      Exit;
    daysLeft := Trunc(startDate - today);
    if daysLeft < 0 then
      daysLeft := 0;
  end;
  Result := '节假日：' + name + '(休)，还剩#hl:' + IntToStr(daysLeft) + '#天';
end;

initialization
  InitializeCriticalSection(GHolidayLock);
  GHolidayLoadedFrom := 0;
  GHolidayLoadedTo := 0;

finalization
  FreeAndNil(GHolidayMap);
  DeleteCriticalSection(GHolidayLock);

end.
