unit UsnMonitor;

interface

uses
  Windows, SysUtils, Classes, Contnrs, Generics.Collections, Core.Model, Core.Memory;

type
  TUsnRecordsProc = procedure(const ADriveLetter: Char; ADriveIndex: Byte;
    const ARecords: TUsnJournalRecordArray) of object;

  TUsnCatchUpResult = (ucrOk, ucrJournalReset, ucrOpenFailed);

  TUsnCatchUpStats = record
    RecordsRead: Integer;
    CreateCount: Integer;
    DeleteCount: Integer;
    RenameCount: Integer;
    ModifyCount: Integer;
    StartUsn: Int64;
    EndUsn: Int64;
    CurrentNextUsn: Int64;
    GapUsn: Int64;
    UsnAdvanced: Boolean;
    LastReadError: DWORD;
    AlreadyCurrent: Boolean;
    ForceVerifyMode: Boolean;
    VerifySinceFileTime: Int64;
  end;

  TUsnMonitorThread = class(TThread)
  private
    FDriveLetter: Char;
    FDriveIndex: Byte;
    FVolumeHandle: THandle;
    FNextUsn: Int64;
    FJournalId: Int64;
    FOnRecords: TUsnRecordsProc;
    function PollJournalBatch(out ARecords: TUsnJournalRecordArray; ABlockForChanges: Boolean): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const ADriveLetter: Char; ADriveIndex: Byte; AOnRecords: TUsnRecordsProc;
      const AInitialCheckpoint: TUsnCheckpoint);
    destructor Destroy; override;
  end;

function UsnQueryCurrentCheckpoint(const ADriveLetter: Char; out ACheckpoint: TUsnCheckpoint): Boolean;
function UsnCatchUpDrive(const ADriveLetter: Char; ADriveIndex: Byte;
  var ACheckpoint: TUsnCheckpoint; const AOnRecords: TUsnRecordsProc;
  AVerifySinceFileTime: Int64; out AStats: TUsnCatchUpStats): TUsnCatchUpResult;
procedure UsnMonitorStart(var AThreads: TObjectList; const ADriveLetters: TDriveLetterMap;
  const AOnRecords: TUsnRecordsProc; const AInitialCheckpoints: TUsnCheckpointArray);
procedure UsnMonitorStop(var AThreads: TObjectList);

implementation

uses
  MftReader, SafeLog;

const
  FILE_DEVICE_FILE_SYSTEM = $00000009;
  METHOD_BUFFERED = 0;
  METHOD_NEITHER = 3;
  FILE_ANY_ACCESS = 0;
  FSCTL_QUERY_USN_JOURNAL = (FILE_DEVICE_FILE_SYSTEM shl 16) or
    (FILE_ANY_ACCESS shl 14) or (61 shl 2) or METHOD_BUFFERED;
  FSCTL_READ_USN_JOURNAL = (FILE_DEVICE_FILE_SYSTEM shl 16) or
    (FILE_ANY_ACCESS shl 14) or (46 shl 2) or METHOD_NEITHER;

  cUsnBufferSize = 256 * 1024;
  cUsnBlockWaitMs = 2000;

type
  TUsnJournalData = packed record
    UsnJournalID: Int64;
    FirstUsn: Int64;
    NextUsn: Int64;
    LowestValidUsn: Int64;
    MaxUsn: Int64;
    MaximumSize: Int64;
    AllocationDelta: Int64;
  end;

  TReadUsnJournalData = packed record
    StartUsn: Int64;
    ReasonMask: DWORD;
    ReturnOnlyOnClose: DWORD;
    Timeout: UInt64;
    BytesToWaitFor: UInt64;
    UsnJournalID: Int64;
  end;

  TUsnRecordHeader = packed record
    RecordLength: DWORD;
    MajorVersion: Word;
    MinorVersion: Word;
    FileReferenceNumber: Int64;
    ParentFileReferenceNumber: Int64;
    Usn: Int64;
    TimeStamp: Int64;
    Reason: DWORD;
    SourceInfo: DWORD;
    SecurityId: DWORD;
    FileAttributes: DWORD;
    FileNameLength: Word;
    FileNameOffset: Word;
  end;
  PUsnRecordHeader = ^TUsnRecordHeader;

function UsnReasonIsIndexed(AReason: DWORD): Boolean;
begin
  Result := (AReason and cUsnReasonMask) <> 0;
end;

procedure UsnAccumulateStats(const ARecords: TUsnJournalRecordArray; var AStats: TUsnCatchUpStats);
var
  i: Integer;
  rec: TUsnJournalRecord;
begin
  for i := 0 to High(ARecords) do
  begin
    rec := ARecords[i];
    Inc(AStats.RecordsRead);
    if (rec.Reason and (USN_REASON_FILE_DELETE or USN_REASON_RENAME_OLD_NAME)) <> 0 then
      Inc(AStats.DeleteCount)
    else if (rec.Reason and (USN_REASON_FILE_CREATE or USN_REASON_RENAME_NEW_NAME)) <> 0 then
      Inc(AStats.CreateCount);
    if (rec.Reason and (USN_REASON_RENAME_OLD_NAME or USN_REASON_RENAME_NEW_NAME)) <> 0 then
      Inc(AStats.RenameCount);
    if (rec.Reason and USN_REASON_BASIC_INFO_CHANGE) <> 0 then
      Inc(AStats.ModifyCount);
  end;
end;

function QueryUsnJournal(AHandle: THandle; out AJournal: TUsnJournalData): Boolean;
var
  bytesReturned: DWORD;
begin
  FillChar(AJournal, SizeOf(AJournal), 0);
  Result := DeviceIoControl(AHandle, FSCTL_QUERY_USN_JOURNAL, nil, 0,
    @AJournal, SizeOf(AJournal), bytesReturned, nil);
end;

function ReadUsnJournalBatch(AHandle: THandle; var ANextUsn: Int64; AJournalId: Int64;
  ABlockForChanges: Boolean; out ARecords: TUsnJournalRecordArray;
  out AJournal: TUsnJournalData; out ALastReadError: DWORD): Boolean;
var
  readData: TReadUsnJournalData;
  buf: array of Byte;
  bytesReturned: DWORD;
  offset: DWORD;
  rec: PUsnRecordHeader;
  namePtr: PWideChar;
  nameChars: Integer;
  item: TUsnJournalRecord;
  n: Integer;
begin
  Result := False;
  ALastReadError := 0;
  SetLength(ARecords, 0);
  if AHandle = INVALID_HANDLE_VALUE then
    Exit;
  if not QueryUsnJournal(AHandle, AJournal) then
  begin
    ALastReadError := GetLastError;
    Exit;
  end;
  if ANextUsn < AJournal.LowestValidUsn then
    ANextUsn := AJournal.LowestValidUsn;
  if ANextUsn >= AJournal.NextUsn then
  begin
    if not ABlockForChanges then
      Exit;
  end;

  SetLength(buf, cUsnBufferSize);
  repeat
    if ANextUsn >= AJournal.NextUsn then
    begin
      if not QueryUsnJournal(AHandle, AJournal) then
      begin
        ALastReadError := GetLastError;
        Exit;
      end;
      if ANextUsn >= AJournal.NextUsn then
        Break;
    end;
    FillChar(readData, SizeOf(readData), 0);
    readData.StartUsn := ANextUsn;
    readData.ReasonMask := $FFFFFFFF;
    readData.UsnJournalID := AJournalId;
    if (ANextUsn >= AJournal.NextUsn) and ABlockForChanges then
    begin
      readData.BytesToWaitFor := 1;
      readData.Timeout := cUsnBlockWaitMs;
    end;
    if not DeviceIoControl(AHandle, FSCTL_READ_USN_JOURNAL, @readData, SizeOf(readData),
      @buf[0], Length(buf), bytesReturned, nil) then
    begin
      ALastReadError := GetLastError;
      Exit;
    end;
    if bytesReturned < SizeOf(Int64) then
      Break;
    ANextUsn := PInt64(@buf[0])^;
    if bytesReturned = SizeOf(Int64) then
      Break;
    n := Length(ARecords);
    offset := SizeOf(Int64);
    while offset + SizeOf(TUsnRecordHeader) <= bytesReturned do
    begin
      rec := PUsnRecordHeader(@buf[offset]);
      if rec.RecordLength = 0 then
        Break;
      if UsnReasonIsIndexed(rec.Reason) then
      begin
        item.FRN := UInt64(rec.FileReferenceNumber);
        item.ParentFRN := UInt64(rec.ParentFileReferenceNumber);
        item.Reason := rec.Reason;
        item.TimeStamp := rec.TimeStamp;
        item.FileAttributes := rec.FileAttributes;
        item.FileName := '';
        if rec.FileNameLength > 0 then
        begin
          namePtr := PWideChar(NativeUInt(rec) + rec.FileNameOffset);
          nameChars := rec.FileNameLength div SizeOf(WideChar);
          if nameChars > 0 then
            SetString(item.FileName, namePtr, nameChars);
        end;
        if Length(ARecords) <= n then
          SetLength(ARecords, n + 64);
        ARecords[n] := item;
        Inc(n);
        Result := True;
      end;
      Inc(offset, rec.RecordLength);
    end;
    SetLength(ARecords, n);
  until False;
end;

function UsnCatchUpDrive(const ADriveLetter: Char; ADriveIndex: Byte;
  var ACheckpoint: TUsnCheckpoint; const AOnRecords: TUsnRecordsProc;
  AVerifySinceFileTime: Int64; out AStats: TUsnCatchUpStats): TUsnCatchUpResult;
var
  hVol: THandle;
  journal: TUsnJournalData;
  startUsn, nextUsn, prevUsn: Int64;
  records: TUsnJournalRecordArray;
begin
  FillChar(AStats, SizeOf(AStats), 0);
  EnableVolumeScanPrivileges;
  hVol := MftOpenVolumeForJournal(ADriveLetter);
  if hVol = INVALID_HANDLE_VALUE then
    Exit(ucrOpenFailed);
  try
    if not QueryUsnJournal(hVol, journal) then
      Exit(ucrOpenFailed);
    AStats.CurrentNextUsn := journal.NextUsn;
    if (ACheckpoint.JournalId <> 0) and (ACheckpoint.JournalId <> journal.UsnJournalID) then
      Exit(ucrJournalReset);
    if (ACheckpoint.JournalId <> 0) and (ACheckpoint.LastUsn < journal.LowestValidUsn) then
      Exit(ucrJournalReset);
    if (ACheckpoint.JournalId = 0) and (ACheckpoint.LastUsn = 0) then
      startUsn := journal.LowestValidUsn
    else
      startUsn := ACheckpoint.LastUsn;
    AStats.StartUsn := startUsn;
    if journal.NextUsn > startUsn then
      AStats.GapUsn := journal.NextUsn - startUsn
    else
      AStats.GapUsn := 0;
    if startUsn >= journal.NextUsn then
    begin
      AStats.AlreadyCurrent := True;
      ACheckpoint.JournalId := journal.UsnJournalID;
      ACheckpoint.LastUsn := journal.NextUsn;
      AStats.EndUsn := journal.NextUsn;
      Exit(ucrOk);
    end;
    nextUsn := startUsn;
    while nextUsn < journal.NextUsn do
    begin
      prevUsn := nextUsn;
      ReadUsnJournalBatch(hVol, nextUsn, journal.UsnJournalID, False, records, journal,
        AStats.LastReadError);
      if nextUsn > prevUsn then
        AStats.UsnAdvanced := True;
      if Length(records) > 0 then
      begin
        UsnAccumulateStats(records, AStats);
        if Assigned(AOnRecords) then
          AOnRecords(ADriveLetter, ADriveIndex, records);
      end;
      if nextUsn <= prevUsn then
        Break;
      if not QueryUsnJournal(hVol, journal) then
      begin
        AStats.LastReadError := GetLastError;
        Exit(ucrOpenFailed);
      end;
    end;
    ACheckpoint.JournalId := journal.UsnJournalID;
    ACheckpoint.LastUsn := journal.NextUsn;
    AStats.EndUsn := journal.NextUsn;
    Result := ucrOk;
  finally
    CloseHandle(hVol);
  end;
end;

function UsnQueryCurrentCheckpoint(const ADriveLetter: Char; out ACheckpoint: TUsnCheckpoint): Boolean;
var
  hVol: THandle;
  journal: TUsnJournalData;
begin
  FillChar(ACheckpoint, SizeOf(ACheckpoint), 0);
  EnableVolumeScanPrivileges;
  hVol := MftOpenVolumeForJournal(ADriveLetter);
  if hVol = INVALID_HANDLE_VALUE then
    Exit(False);
  try
    Result := QueryUsnJournal(hVol, journal);
    if Result then
    begin
      ACheckpoint.JournalId := journal.UsnJournalID;
      ACheckpoint.LastUsn := journal.NextUsn;
    end;
  finally
    CloseHandle(hVol);
  end;
end;

constructor TUsnMonitorThread.Create(const ADriveLetter: Char; ADriveIndex: Byte;
  AOnRecords: TUsnRecordsProc; const AInitialCheckpoint: TUsnCheckpoint);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FDriveLetter := ADriveLetter;
  FDriveIndex := ADriveIndex;
  FOnRecords := AOnRecords;
  if (AInitialCheckpoint.JournalId <> 0) or (AInitialCheckpoint.LastUsn <> 0) then
  begin
    FJournalId := AInitialCheckpoint.JournalId;
    FNextUsn := AInitialCheckpoint.LastUsn;
  end
  else
  begin
    FNextUsn := 0;
    FJournalId := 0;
  end;
  FVolumeHandle := MftOpenVolumeForJournal(ADriveLetter);
  if FVolumeHandle = INVALID_HANDLE_VALUE then
    SafeLogRecord('索引', 'USN 监控', FDriveLetter + ': 无法打开卷',
      False, 'GetLastError=' + IntToStr(GetLastError));
end;

destructor TUsnMonitorThread.Destroy;
begin
  if FVolumeHandle <> INVALID_HANDLE_VALUE then
    CloseHandle(FVolumeHandle);
  inherited;
end;

function TUsnMonitorThread.PollJournalBatch(out ARecords: TUsnJournalRecordArray;
  ABlockForChanges: Boolean): Boolean;
var
  journal: TUsnJournalData;
  readErr: DWORD;
begin
  Result := False;
  SetLength(ARecords, 0);
  if FVolumeHandle = INVALID_HANDLE_VALUE then
    Exit;
  if not QueryUsnJournal(FVolumeHandle, journal) then
  begin
    SafeLogRecord('索引', 'USN 监控', FDriveLetter + ': 查询日志失败',
      False, 'GetLastError=' + IntToStr(GetLastError));
    Exit;
  end;
  if FJournalId = 0 then
  begin
    FJournalId := journal.UsnJournalID;
    FNextUsn := journal.NextUsn;
    Exit;
  end;
  if FJournalId <> journal.UsnJournalID then
  begin
    FJournalId := journal.UsnJournalID;
    FNextUsn := journal.FirstUsn;
  end;
  Result := ReadUsnJournalBatch(FVolumeHandle, FNextUsn, FJournalId, ABlockForChanges,
    ARecords, journal, readErr);
end;

procedure TUsnMonitorThread.Execute;
var
  records: TUsnJournalRecordArray;
  hadWork: Boolean;
begin
  while not Terminated do
  begin
    hadWork := PollJournalBatch(records, True);
    if (Length(records) > 0) and Assigned(FOnRecords) then
      FOnRecords(FDriveLetter, FDriveIndex, records);
    if not hadWork then
      Sleep(1);
  end;
end;

function DriveIndexFromMap(const ADriveLetter: Char; const ADriveLetters: TDriveLetterMap): Byte;
var
  i: Integer;
begin
  for i := 0 to 25 do
    if ADriveLetters[i] = ADriveLetter then
      Exit(Byte(i));
  Result := Byte(Ord(UpCase(ADriveLetter)) - Ord('A'));
end;

procedure UsnMonitorStart(var AThreads: TObjectList; const ADriveLetters: TDriveLetterMap;
  const AOnRecords: TUsnRecordsProc; const AInitialCheckpoints: TUsnCheckpointArray);
var
  mask: DWORD;
  drive: Char;
  th: TUsnMonitorThread;
  driveIdx: Byte;
begin
  UsnMonitorStop(AThreads);
  EnableVolumeScanPrivileges;
  AThreads := TObjectList.Create(True);
  mask := GetLogicalDrives;
  for drive := 'C' to 'Z' do
  begin
    if (mask and (1 shl (Ord(drive) - Ord('A')))) = 0 then
      Continue;
    if not MftShouldMonitorDrive(drive) then
      Continue;
    driveIdx := DriveIndexFromMap(drive, ADriveLetters);
    th := TUsnMonitorThread.Create(drive, driveIdx, AOnRecords,
      AInitialCheckpoints[driveIdx]);
    AThreads.Add(th);
    th.Start;
  end;
end;

procedure UsnMonitorStop(var AThreads: TObjectList);
var
  i: Integer;
  th: TUsnMonitorThread;
begin
  if AThreads = nil then
    Exit;
  for i := 0 to AThreads.Count - 1 do
  begin
    th := TUsnMonitorThread(AThreads[i]);
    th.Terminate;
  end;
  for i := 0 to AThreads.Count - 1 do
  begin
    th := TUsnMonitorThread(AThreads[i]);
    th.WaitFor;
  end;
  FreeAndNil(AThreads);
end;

end.
