unit EverythingIndex;

interface

uses
  Windows, SysUtils, Classes, Contnrs, Generics.Collections, LibraryStore, Core.Model, SearchVM;

type
  TEverythingIndexError = (eieOk, eieNoNtfsVolume, eieVolumeAccess, eieBuildFailed);
  TEverythingIndexPumpProc = reference to procedure;
  TEverythingIndexCancelledFunc = TSearchCancelledFunc;
  TEverythingHitArray = TSearchHitIndexArray;
  TExtFilterKindMap = array of Byte;

function EverythingIndexFileCount: Integer;
function EverythingIndexGetFullPath(AFileIndex: Integer): string;
function EverythingIndexGetFileName(AFileIndex: Integer): string;
function EverythingIndexGetExtension(AFileIndex: Integer): string;
function EverythingIndexGetModifiedUtc(AFileIndex: Integer): Int64;
procedure EverythingIndexStartupAsync;
procedure EverythingIndexStartBuild;
procedure EverythingIndexStopBuild;
procedure EverythingIndexShutdown;
function EverythingIndexIsReady: Boolean;
function EverythingIndexIsBuilding: Boolean;
function EverythingIndexGetBuildStatusText: string;
function EverythingIndexWaitUntilReady(ATimeoutMs: Cardinal; APump: TEverythingIndexPumpProc): Boolean;
function EverythingIndexGetLastError: TEverythingIndexError;
function EverythingIndexSearch(const ANeedle: string; const ASortKind: TLibraryListSortKind;
  const ASortAsc: Boolean; const AIsCancelled: TEverythingIndexCancelledFunc;
  out AHitIndices: TEverythingHitArray; out ATotalCount: Cardinal;
  var ATiming: TSearchTiming; ASkipSort: Boolean = True): Boolean;
procedure EverythingIndexSortHitIndices(var AHitIndices: TEverythingHitArray;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean);
function EverythingIndexGetHitFileName(AHitIndex: Integer): string;
function EverythingIndexGetHitPath(AHitIndex: Integer): string;
function EverythingIndexGetHitExtension(AHitIndex: Integer): string;
function EverythingIndexHitIsFolder(AHitIndex: Integer): Boolean;
function EverythingIndexGetExtCount: Integer;
function EverythingIndexGetExtNameById(AExtId: Word): string;
function EverythingIndexGetHitFilterKind(AHitIndex: Integer; const AExtIdToKind: TExtFilterKindMap;
  AFolderKindIndex, AOtherKindIndex: Integer): Integer;
procedure EverythingIndexCountHitFilterKinds(const AHits: TEverythingHitArray;
  AFolderKindIndex, AOtherKindIndex: Integer; const AExtIdToKind: TExtFilterKindMap;
  var ACounts: array of Integer);
procedure EverythingIndexBuildSearchFilterRowMap(const AHits: TEverythingHitArray;
  AFilterIndex, AFolderKindIndex, AOtherKindIndex: Integer;
  const AExtIdToKind: TExtFilterKindMap; out ARowMap: TSearchHitIndexArray);
procedure EverythingIndexSetNotifyHwnd(AWnd: Windows.HWND);
procedure EverythingIndexPatchSearchHits(var AHits: TEverythingHitArray; const ANeedle: string;
  const AChanges: TIndexHitChangeArray);
procedure EverythingIndexDisposeHitChangesMsg(AData: PIndexHitChangesMsg);

implementation

uses
  Messages, Core.Memory, MftReader, EverythingDb, UsnMonitor, SafeLog;

procedure StartBuildThread(ATryCacheFirst: Boolean); forward;

type
  TUsnChangedHandler = class
    procedure OnUsnRecords(const ADriveLetter: Char; ADriveIndex: Byte;
      const ARecords: TUsnJournalRecordArray);
  end;

  TEverythingBuildThread = class(TThread)
  private
    FTryCacheFirst: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ATryCacheFirst: Boolean);
  end;

var
  GDB: TEverythingDB;
  GIndexLock: TRTLCriticalSection;
  GBuildThread: TThread;
  GUsnThreads: TObjectList;
  GReady: Boolean;
  GBuilding: Boolean;
  GLastError: TEverythingIndexError;
  GBuildStatusText: string;
  GFrnToFolder: TDictionary<UInt64, Cardinal>;
  GSegToFolder: TDictionary<UInt64, Cardinal>;
  GFrnToFile: TDictionary<UInt64, Cardinal>;
  GFileFrnKeys: TFileFrnKeyArray;
  GExcludedFrn: TDictionary<UInt64, Byte>;
  GDriveLetters: TDriveLetterMap;
  GDriveCount: Integer;
  GUsnChangedHandler: TUsnChangedHandler;
  GBuildFailureDetail: string;
  GNotifyHwnd: Windows.HWND;
  GUsnCheckpoints: TUsnCheckpointArray;
  GCatchUpInProgress: Boolean;
  GCatchUpApplyStats: TMftApplyUsnStats;
  GFileLookup: TDictionary<AnsiString, Integer>;
  GIndexShuttingDown: Boolean;

function TickElapsed(AStartTick: Cardinal): Cardinal;
begin
  if GetTickCount >= AStartTick then
    Result := GetTickCount - AStartTick
  else
    Result := (High(Cardinal) - AStartTick) + GetTickCount + 1;
end;

function CountMountedLocalNtfsVolumes: Integer;
var
  mask: DWORD;
  drive: Char;
begin
  Result := 0;
  mask := GetLogicalDrives;
  for drive := 'C' to 'Z' do
  begin
    if (mask and (1 shl (Ord(drive) - Ord('A')))) = 0 then
      Continue;
    if MftShouldMonitorDrive(drive) then
      Inc(Result);
  end;
end;

function CountDistinctIndexedDrives(const ADB: TEverythingDB): Integer;
var
  i: Integer;
  seen: array[0..25] of Boolean;
  driveIdx: Byte;
begin
  Result := 0;
  FillChar(seen, SizeOf(seen), 0);
  for i := 0 to ADB.FolderCount - 1 do
  begin
    driveIdx := ADB.Folders[i].DriveIndex;
    if driveIdx > 25 then
      Continue;
    if seen[driveIdx] then
      Continue;
    seen[driveIdx] := True;
    Inc(Result);
  end;
end;

function IndexCacheRejectReason(const ADB: TEverythingDB): string;
var
  mountedNtfs, indexedDrives: Integer;
begin
  Result := '';
  if ADB.FileCount <= 0 then
    Exit('无有效文件记录');
  mountedNtfs := CountMountedLocalNtfsVolumes;
  if mountedNtfs <= 0 then
    Exit('当前无可用 NTFS 卷');
  indexedDrives := CountDistinctIndexedDrives(ADB);
  if indexedDrives < mountedNtfs then
    Exit('已索引盘数(' + IntToStr(indexedDrives) + ')少于当前 NTFS 盘数(' +
      IntToStr(mountedNtfs) + ')');
end;

function IndexCacheIsUsable(const ADB: TEverythingDB): Boolean;
begin
  Result := IndexCacheRejectReason(ADB) = '';
end;

function IndexErrorToText(const AError: TEverythingIndexError): string;
begin
  case AError of
    eieNoNtfsVolume:
      Result := '未找到可用的 NTFS 卷';
    eieVolumeAccess:
      Result := '无法访问 NTFS 卷（需要管理员权限）';
    eieBuildFailed:
      Result := '索引构建失败';
  else
    Result := '';
  end;
end;

function FormatIndexStatsDetail(const ASource: string; AElapsedMs: Cardinal): string;
begin
  Result := '来源: ' + ASource + sLineBreak +
    '文件: ' + IntToStr(GDB.FileCount) + sLineBreak +
    '文件夹: ' + IntToStr(GDB.FolderCount) + sLineBreak +
    '耗时: ' + SafeLogFormatElapsed(AElapsedMs);
end;

procedure LogIndexBuildResult(ASuccess: Boolean; const ASource: string;
  AElapsedMs: Cardinal; const AExtraDetail: string);
var
  summary, detail: string;
begin
  if ASuccess then
    summary := '索引构建成功'
  else
    summary := '索引构建失败';
  detail := FormatIndexStatsDetail(ASource, AElapsedMs);
  if Trim(AExtraDetail) <> '' then
    detail := detail + sLineBreak + AExtraDetail;
  SafeLogRecord('索引', '全盘索引', summary, ASuccess, detail);
end;

procedure IndexLockEnter;
begin
  EnterCriticalSection(GIndexLock);
end;

procedure IndexLockLeave;
begin
  LeaveCriticalSection(GIndexLock);
end;

function ExtNameFromIdLocked(AExtId: Word): string;
begin
  if (AExtId = 0) or (AExtId > GDB.ExtCount) then
    Result := ''
  else
    Result := ExtEntryNameToString(GDB.ExtTable[AExtId - 1]);
end;

function DriveLetterFromIndex(AIndex: Byte): Char;
begin
  if (AIndex <= 25) and (GDriveLetters[AIndex] <> #0) then
    Result := GDriveLetters[AIndex]
  else if AIndex <= 25 then
    Result := Char(Ord('A') + AIndex)
  else
    Result := 'C';
end;

function FileParentDriveLetterLocked(AFileIndex: Integer): Char;
var
  parent: Cardinal;
begin
  Result := 'C';
  if (AFileIndex < 0) or (AFileIndex >= GDB.FileCount) or (AFileIndex >= Length(GDB.Files)) then
    Exit;
  parent := GDB.Files[AFileIndex].ParentOffset;
  if (parent <> cRootParentOffset) and (Integer(parent) >= 0) and
    (Integer(parent) < GDB.FolderCount) and (Integer(parent) < Length(GDB.Folders)) then
    Result := DriveLetterFromIndex(GDB.Folders[parent].DriveIndex);
end;

function HitDriveLetterLocked(AHitIndex: Integer): Char;
var
  folderIdx: Integer;
begin
  Result := 'C';
  if AHitIndex < 0 then
  begin
    folderIdx := -(AHitIndex + 1);
    if (folderIdx >= 0) and (folderIdx < GDB.FolderCount) and
      (folderIdx < Length(GDB.Folders)) then
      Result := DriveLetterFromIndex(GDB.Folders[folderIdx].DriveIndex);
  end
  else
    Result := FileParentDriveLetterLocked(AHitIndex);
end;

function BuildFullPathLocked(AFileIndex: Integer): string;
begin
  Result := SearchVMBuildFilePath(GDB, AFileIndex, FileParentDriveLetterLocked(AFileIndex));
end;

function BuildHitPathLocked(AHitIndex: Integer): string;
begin
  Result := SearchVMBuildHitPath(GDB, AHitIndex, HitDriveLetterLocked(AHitIndex));
end;

procedure ResetDriveLetters;
var
  i: Integer;
begin
  GDriveCount := 0;
  for i := 0 to 25 do
    GDriveLetters[i] := #0;
end;

procedure SetDriveLetter(const ADrive: Char; ADriveIndex: Byte);
begin
  if ADriveIndex > 25 then
    Exit;
  GDriveLetters[ADriveIndex] := ADrive;
end;

procedure RestoreDriveLettersFromMap(const ADriveLetterMap: TDriveLetterMap);
var
  i: Integer;
begin
  ResetDriveLetters;
  for i := 0 to 25 do
    if ADriveLetterMap[i] <> #0 then
    begin
      SetDriveLetter(ADriveLetterMap[i], Byte(i));
      Inc(GDriveCount);
    end;
end;

procedure RebuildFrnToFileFromKeys;
var
  i: Integer;
begin
  if GFrnToFile = nil then
    GFrnToFile := TDictionary<UInt64, Cardinal>.Create
  else
    GFrnToFile.Clear;
  for i := 0 to GDB.FileCount - 1 do
    if (i < Length(GFileFrnKeys)) and (GFileFrnKeys[i] <> 0) then
      GFrnToFile.AddOrSetValue(GFileFrnKeys[i], Cardinal(i));
end;

procedure RebuildFileFrnMapsForAllDrives;
var
  i: Integer;
begin
  for i := 0 to 25 do
  begin
    if GDriveLetters[i] = #0 then
      Continue;
    if not MftShouldMonitorDrive(GDriveLetters[i]) then
      Continue;
    MftRebuildFileFrnMapFromUsn(GDriveLetters[i], Byte(i), GDB, GFrnToFolder, GFrnToFile,
      GFileFrnKeys);
  end;
end;

procedure RebuildFileLookupFromDb;
begin
  if GFileLookup = nil then
    GFileLookup := TDictionary<AnsiString, Integer>.Create
  else
    GFileLookup.Clear;
  if GDB.FileCount > 0 then
    MftBuildFileParentNameMap(GDB, GFileLookup);
end;

procedure RebuildSegToFolderFromFrnMap;
begin
  if GSegToFolder = nil then
    GSegToFolder := TDictionary<UInt64, Cardinal>.Create
  else
    GSegToFolder.Clear;
  MftRebuildSegToFolderMap(GFrnToFolder, GSegToFolder);
end;

procedure RestoreFrnMapsAfterLoad(const ALoadedFileFrnKeys: TFileFrnKeyArray);
begin
  if GFrnToFolder = nil then
    GFrnToFolder := TDictionary<UInt64, Cardinal>.Create
  else
    GFrnToFolder.Clear;
  if GFrnToFile = nil then
    GFrnToFile := TDictionary<UInt64, Cardinal>.Create
  else
    GFrnToFile.Clear;
  if GExcludedFrn = nil then
    GExcludedFrn := TDictionary<UInt64, Byte>.Create;
  MftRebuildFolderFrnMap(GDB, GFrnToFolder);
  if Length(ALoadedFileFrnKeys) = GDB.FileCount then
  begin
    GFileFrnKeys := ALoadedFileFrnKeys;
    RebuildFrnToFileFromKeys;
  end
  else
  begin
    SetLength(GFileFrnKeys, GDB.FileCount);
    FillChar(GFileFrnKeys[0], GDB.FileCount * SizeOf(UInt64), 0);
    RebuildFileFrnMapsForAllDrives;
  end;
  RebuildSegToFolderFromFrnMap;
  RebuildFileLookupFromDb;
end;

procedure PostIndexHitChanges(const AChanges: TIndexHitChangeArray);
const
  WM_QD_INDEX_HIT_CHANGES = WM_APP + 116;
var
  msg: PIndexHitChangesMsg;
begin
  if (GNotifyHwnd = 0) or (Length(AChanges) = 0) then
    Exit;
  New(msg);
  msg^.Changes := AChanges;
  if not PostMessageW(GNotifyHwnd, WM_QD_INDEX_HIT_CHANGES, 0, LPARAM(msg)) then
  begin
    SetLength(msg^.Changes, 0);
    Dispose(msg);
  end;
end;

procedure RefreshUsnCheckpoints(var ACheckpoints: TUsnCheckpointArray);
var
  i: Integer;
  drive: Char;
begin
  FillChar(ACheckpoints, SizeOf(ACheckpoints), 0);
  for i := 0 to 25 do
  begin
    drive := GDriveLetters[i];
    if drive = #0 then
      Continue;
    if not MftShouldMonitorDrive(drive) then
      Continue;
    UsnQueryCurrentCheckpoint(drive, ACheckpoints[i]);
  end;
end;

function EverythingDbSavedFileTime: Int64;
var
  path: string;
  hFile: THandle;
  ftWrite: TFileTime;
begin
  Result := 0;
  path := EverythingDbFilePath;
  if not FileExists(path) then
    Exit;
  hFile := CreateFile(PChar(path), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if hFile = INVALID_HANDLE_VALUE then
    Exit;
  try
    if GetFileTime(hFile, nil, nil, @ftWrite) then
      Result := PInt64(@ftWrite)^;
  finally
    CloseHandle(hFile);
  end;
end;

function CatchUpIndexFromUsn(var ACheckpoints: TUsnCheckpointArray; out ACatchUpDetail: string): Boolean;
var
  i: Integer;
  drive: Char;
  catchResult: TUsnCatchUpResult;
  stats: TUsnCatchUpStats;
  savedCheckpoint: TUsnCheckpoint;
  dbFileTime: Int64;
  fileCountBefore, fileCountAfter: Integer;
  totalRecords, totalCreate, totalDelete, totalRename, totalModify: Integer;
  totalAppliedAdd, totalAppliedRemove, totalAppliedUpdate: Integer;
  applyStats: TMftApplyUsnStats;
  detail: TStringList;
  driveLine, verifyTag: string;
  driveStartTick, driveMs: Integer;
begin
  Result := True;
  ACatchUpDetail := '';
  fileCountBefore := GDB.FileCount;
  dbFileTime := EverythingDbSavedFileTime;
  totalRecords := 0;
  totalCreate := 0;
  totalDelete := 0;
  totalRename := 0;
  totalModify := 0;
  totalAppliedAdd := 0;
  totalAppliedRemove := 0;
  totalAppliedUpdate := 0;
  FillChar(GCatchUpApplyStats, SizeOf(GCatchUpApplyStats), 0);
  GCatchUpInProgress := True;
  detail := TStringList.Create;
  try
    detail.Add('【离线同步】');
    detail.Add('缓存保存时间(FILETIME): ' + IntToStr(dbFileTime));
    detail.Add('回放前索引文件数: ' + IntToStr(fileCountBefore));
    detail.Add('');
    for i := 0 to 25 do
    begin
      drive := GDriveLetters[i];
      if drive = #0 then
        Continue;
      if not MftShouldMonitorDrive(drive) then
        Continue;
      savedCheckpoint := ACheckpoints[i];
      FillChar(GCatchUpApplyStats, SizeOf(GCatchUpApplyStats), 0);
      driveStartTick := GetTickCount;
      catchResult := UsnCatchUpDrive(drive, Byte(i), ACheckpoints[i],
        GUsnChangedHandler.OnUsnRecords, stats);
      driveMs := TickElapsed(driveStartTick);
      applyStats := GCatchUpApplyStats;
      totalAppliedAdd := totalAppliedAdd + applyStats.FilesAdded;
      totalAppliedRemove := totalAppliedRemove + applyStats.FilesRemoved;
      totalAppliedUpdate := totalAppliedUpdate + applyStats.FilesUpdated;
      totalRecords := totalRecords + stats.RecordsRead;
      totalCreate := totalCreate + stats.CreateCount;
      totalDelete := totalDelete + stats.DeleteCount;
      totalRename := totalRename + stats.RenameCount;
      totalModify := totalModify + stats.ModifyCount;
      if stats.AlreadyCurrent then
        verifyTag := ' [已同步]'
      else
        verifyTag := '';
      driveLine := drive + ': 保存断点 JournalId=' + IntToStr(savedCheckpoint.JournalId) +
        ' LastUsn=' + IntToStr(savedCheckpoint.LastUsn) +
        ' 当前NextUsn=' + IntToStr(stats.CurrentNextUsn) + verifyTag +
        ' 耗时 ' + SafeLogFormatElapsed(driveMs);
      if stats.RecordsRead > 0 then
        driveLine := driveLine + sLineBreak + '  回放 USN ' + IntToStr(stats.StartUsn) +
          '..' + IntToStr(stats.EndUsn) + ' 变动 ' + IntToStr(stats.RecordsRead) + ' 条' +
          ' (新建' + IntToStr(stats.CreateCount) +
          ' 删除' + IntToStr(stats.DeleteCount) +
          ' 重命名' + IntToStr(stats.RenameCount) +
          ' 修改' + IntToStr(stats.ModifyCount) + ')' + sLineBreak +
          '  实际应用: +' + IntToStr(applyStats.FilesAdded) +
          ' -' + IntToStr(applyStats.FilesRemoved) +
          ' ~' + IntToStr(applyStats.FilesUpdated)
      else if stats.AlreadyCurrent then
        driveLine := driveLine + sLineBreak + '  关闭期间无 USN 变动'
      else if stats.GapUsn > 0 then
      begin
        driveLine := driveLine + sLineBreak + '  USN 区间差距 ' + IntToStr(stats.GapUsn) +
          ' 但读到 0 条';
        if stats.UsnAdvanced then
          driveLine := driveLine + ' (指针已推进，可能仅含非索引类 USN 记录)'
        else
          driveLine := driveLine + ' (指针未推进 Win32=' + IntToStr(stats.LastReadError) + ')';
      end;
      detail.Add(driveLine);
      if catchResult = ucrJournalReset then
      begin
        detail.Add('  -> 日志已截断，需重建');
        Result := False;
      end
      else if catchResult = ucrOpenFailed then
      begin
        detail.Add('  -> 无法打开卷 (Win32=' + IntToStr(stats.LastReadError) + ')');
        Result := False;
      end;
    end;
    IndexLockEnter;
    try
      fileCountAfter := GDB.FileCount;
    finally
      IndexLockLeave;
    end;
    detail.Add('');
    detail.Add('合计关闭期间 USN 变动: ' + IntToStr(totalRecords) + ' 条');
    detail.Add('  新建: ' + IntToStr(totalCreate) +
      '  删除: ' + IntToStr(totalDelete) +
      '  重命名: ' + IntToStr(totalRename) +
      '  修改: ' + IntToStr(totalModify));
    detail.Add('实际写入索引: +' + IntToStr(totalAppliedAdd) +
      ' -' + IntToStr(totalAppliedRemove) +
      ' ~' + IntToStr(totalAppliedUpdate));
    detail.Add('索引文件数: ' + IntToStr(fileCountBefore) + ' -> ' +
      IntToStr(fileCountAfter) + ' (Δ' + IntToStr(fileCountAfter - fileCountBefore) + ')');
    if GFileLookup <> nil then
      detail.Add('文件查找表: ' + IntToStr(GFileLookup.Count) + ' 项（常驻）')
    else
      detail.Add('文件查找表: 未构建（无 USN 变动）');
    ACatchUpDetail := detail.Text;
  finally
    GCatchUpInProgress := False;
    detail.Free;
  end;
end;

procedure TUsnChangedHandler.OnUsnRecords(const ADriveLetter: Char; ADriveIndex: Byte;
  const ARecords: TUsnJournalRecordArray);
var
  applied: Boolean;
  batchStats: TMftApplyUsnStats;
  fileLookup: TDictionary<AnsiString, Integer>;
  indexChanges: TIndexHitChangeArray;
begin
  if GIndexShuttingDown or (Length(ARecords) = 0) or (GBuilding and not GCatchUpInProgress) then
    Exit;
  fileLookup := GFileLookup;
  SetLength(indexChanges, 0);
  IndexLockEnter;
  try
    applied := MftApplyUsnRecords(GDB, ADriveIndex, ARecords, GFrnToFolder, GFrnToFile,
      GSegToFolder, GExcludedFrn, GFileFrnKeys, fileLookup, batchStats, indexChanges);
    if GCatchUpInProgress then
    begin
      GCatchUpApplyStats.FilesAdded := GCatchUpApplyStats.FilesAdded + batchStats.FilesAdded;
      GCatchUpApplyStats.FilesRemoved := GCatchUpApplyStats.FilesRemoved + batchStats.FilesRemoved;
      GCatchUpApplyStats.FilesUpdated := GCatchUpApplyStats.FilesUpdated + batchStats.FilesUpdated;
    end;
  finally
    IndexLockLeave;
  end;
  if applied and GReady and (not GCatchUpInProgress) then
    PostIndexHitChanges(indexChanges);
end;

procedure EverythingIndexSetNotifyHwnd(AWnd: Windows.HWND);
begin
  GNotifyHwnd := AWnd;
end;

function BuildAllVolumes(out AFailDetail: string; ADriveTimings: TStrings = nil): Boolean;
var
  mask: DWORD;
  drive: Char;
  driveIndex, ntfsCount, okCount, failCount: Integer;
  driveFailReason: string;
  failLines: TStringList;
  driveStartTick, driveMs: Cardinal;
begin
  Result := False;
  AFailDetail := '';
  GBuildFailureDetail := '';
  ResetDriveLetters;
  ntfsCount := 0;
  okCount := 0;
  failCount := 0;
  failLines := TStringList.Create;
  try
    mask := GetLogicalDrives;
    driveIndex := 0;
    for drive := 'C' to 'Z' do
    begin
      if (mask and (1 shl (Ord(drive) - Ord('A')))) = 0 then
        Continue;
      if MftIsSubstDrive(drive) then
      begin
        failLines.Add(drive + ': SUBST 映射盘，已跳过');
        Continue;
      end;
      if not MftShouldMonitorDrive(drive) then
        Continue;
      Inc(ntfsCount);
      GBuildStatusText := '正在索引 ' + drive + ':';
      driveStartTick := GetTickCount;
      if MftBuildFromDrive(drive, Byte(driveIndex), GDB, GFrnToFolder, GFrnToFile, GFileFrnKeys,
        GExcludedFrn, procedure(const AStatus: string)
        begin
          GBuildStatusText := AStatus;
        end, driveFailReason) then
      begin
        driveMs := TickElapsed(driveStartTick);
        if ADriveTimings <> nil then
          ADriveTimings.Add(drive + ': ' + SafeLogFormatElapsed(driveMs) + ' (' +
            IntToStr(GDB.FileCount) + ' 文件)');
        SetDriveLetter(drive, Byte(driveIndex));
        Inc(GDriveCount);
        Inc(driveIndex);
        Inc(okCount);
      end
      else
      begin
        Inc(failCount);
        if driveFailReason = '' then
          driveFailReason := '未知错误';
        failLines.Add(drive + ': ' + driveFailReason);
        if (GLastError = eieOk) and (Pos('管理员', driveFailReason) > 0) then
          GLastError := eieVolumeAccess;
      end;
    end;

    if ntfsCount = 0 then
    begin
      GLastError := eieNoNtfsVolume;
      AFailDetail := IndexErrorToText(eieNoNtfsVolume);
      Exit;
    end;
    if okCount = 0 then
    begin
      if GLastError = eieOk then
        GLastError := eieVolumeAccess;
      AFailDetail := IndexErrorToText(GLastError);
      if failLines.Count > 0 then
        AFailDetail := AFailDetail + sLineBreak + '失败卷:' + sLineBreak + failLines.Text;
      GBuildFailureDetail := AFailDetail;
      Exit;
    end;
    if failCount > 0 then
      GBuildFailureDetail := '部分卷索引失败:' + sLineBreak + failLines.Text;
    Result := GDB.FileCount > 0;
    if Result then
      GLastError := eieOk
    else if not Result then
    begin
      GLastError := eieBuildFailed;
      AFailDetail := IndexErrorToText(eieBuildFailed);
      if failLines.Count > 0 then
        AFailDetail := AFailDetail + sLineBreak + failLines.Text;
      GBuildFailureDetail := AFailDetail;
    end;
  finally
    failLines.Free;
  end;
end;

{ TEverythingBuildThread }

constructor TEverythingBuildThread.Create(ATryCacheFirst: Boolean);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FTryCacheFirst := ATryCacheFirst;
end;

procedure TEverythingBuildThread.Execute;
var
  startTick, elapsedMs, loadMs, restoreMs, catchUpMs, buildMs, saveMs: Cardinal;
  cacheLoaded, cacheUsable, buildOk: Boolean;
  failDetail, extraDetail: string;
  loadedDriveMap: TDriveLetterMap;
  loadedFileFrnKeys: TFileFrnKeyArray;
  loadedUsnCheckpoints: TUsnCheckpointArray;
  staleCacheFileCount, staleIndexedDrives, staleMountedNtfs: Integer;
  cacheRejectReason: string;
  catchUpOk: Boolean;
  catchUpDetail, catchUpFailNote, catchUpPhaseTiming: string;
  phaseTick: Cardinal;
  driveTimings: TStringList;
  driveTimingText: string;
begin
  startTick := GetTickCount;
  buildMs := 0;
  saveMs := 0;
  GLastError := eieOk;
  GBuildFailureDetail := '';
  GBuildStatusText := '正在加载索引…';
  staleCacheFileCount := 0;
  staleIndexedDrives := 0;
  staleMountedNtfs := 0;
  cacheRejectReason := '';
  catchUpDetail := '';
  catchUpFailNote := '';
  catchUpPhaseTiming := '';
  phaseTick := GetTickCount;
  cacheLoaded := FTryCacheFirst and EverythingDbLoad(GDB, loadedDriveMap, loadedFileFrnKeys,
    loadedUsnCheckpoints, '');
  loadMs := TickElapsed(phaseTick);
  cacheUsable := cacheLoaded and IndexCacheIsUsable(GDB);
  if cacheLoaded and not cacheUsable then
  begin
    staleCacheFileCount := GDB.FileCount;
    staleIndexedDrives := CountDistinctIndexedDrives(GDB);
    staleMountedNtfs := CountMountedLocalNtfsVolumes;
    cacheRejectReason := IndexCacheRejectReason(GDB);
  end;
  if cacheUsable then
  begin
    RestoreDriveLettersFromMap(loadedDriveMap);
    phaseTick := GetTickCount;
    IndexLockEnter;
    try
      RestoreFrnMapsAfterLoad(loadedFileFrnKeys);
    finally
      IndexLockLeave;
    end;
    restoreMs := TickElapsed(phaseTick);
    GUsnCheckpoints := loadedUsnCheckpoints;
    GBuildStatusText := '正在同步离线变更…';
    phaseTick := GetTickCount;
    catchUpOk := CatchUpIndexFromUsn(GUsnCheckpoints, catchUpDetail);
    catchUpMs := TickElapsed(phaseTick);
    catchUpPhaseTiming := ' / FRN 恢复 ' + SafeLogFormatElapsed(restoreMs) +
      ' / 离线同步 ' + SafeLogFormatElapsed(catchUpMs);
    if catchUpOk then
    begin
      IndexLockEnter;
      try
        GReady := True;
        GBuilding := False;
        GBuildStatusText := '';
      finally
        IndexLockLeave;
      end;
      elapsedMs := TickElapsed(startTick);
      phaseTick := GetTickCount;
      if not GIndexShuttingDown then
        UsnMonitorStart(GUsnThreads, GDriveLetters, GUsnChangedHandler.OnUsnRecords,
          GUsnCheckpoints);
      EverythingDbSave(GDB, GDriveLetters, GFileFrnKeys, GUsnCheckpoints);
      saveMs := TickElapsed(phaseTick);
      extraDetail := '缓存文件: ' + EverythingDbFilePath + sLineBreak +
        '阶段耗时: 加载 ' + SafeLogFormatElapsed(loadMs) + catchUpPhaseTiming +
        ' / 保存 ' + SafeLogFormatElapsed(saveMs);
      if Trim(catchUpDetail) <> '' then
        extraDetail := extraDetail + sLineBreak + sLineBreak + catchUpDetail;
      LogIndexBuildResult(True, 'Everything.db 缓存', elapsedMs, extraDetail);
      Exit;
    end;
    catchUpFailNote := '离线变更回放失败，改从 $MFT 重建';
    if Trim(catchUpDetail) <> '' then
      catchUpFailNote := catchUpFailNote + sLineBreak + sLineBreak + catchUpDetail;
    cacheUsable := False;
  end;

  EverythingDbClear(GDB);
  SetLength(GFileFrnKeys, 0);
  if GFrnToFolder = nil then
    GFrnToFolder := TDictionary<UInt64, Cardinal>.Create
  else
    GFrnToFolder.Clear;
  if GSegToFolder = nil then
    GSegToFolder := TDictionary<UInt64, Cardinal>.Create
  else
    GSegToFolder.Clear;
  if GFrnToFile = nil then
    GFrnToFile := TDictionary<UInt64, Cardinal>.Create
  else
    GFrnToFile.Clear;
  if GExcludedFrn = nil then
    GExcludedFrn := TDictionary<UInt64, Byte>.Create
  else
    GExcludedFrn.Clear;
  if GFileLookup = nil then
    GFileLookup := TDictionary<AnsiString, Integer>.Create
  else
    GFileLookup.Clear;

  failDetail := '';
  driveTimingText := '';
  driveTimings := TStringList.Create;
  try
    phaseTick := GetTickCount;
    buildOk := BuildAllVolumes(failDetail, driveTimings);
    buildMs := TickElapsed(phaseTick);
    driveTimingText := driveTimings.Text;
    if buildOk then
    begin
      RebuildSegToFolderFromFrnMap;
      RebuildFileLookupFromDb;
      RefreshUsnCheckpoints(GUsnCheckpoints);
      phaseTick := GetTickCount;
      EverythingDbSave(GDB, GDriveLetters, GFileFrnKeys, GUsnCheckpoints);
      saveMs := TickElapsed(phaseTick);
      GLastError := eieOk;
    end
    else if GLastError = eieOk then
      GLastError := eieBuildFailed;
  except
    on E: Exception do
    begin
      GLastError := eieBuildFailed;
      failDetail := '异常: ' + E.Message;
      GBuildFailureDetail := failDetail;
    end;
  end;
  driveTimings.Free;

  IndexLockEnter;
  try
    GReady := GDB.FileCount > 0;
    GBuilding := False;
    if GReady then
      GBuildStatusText := ''
    else if GBuildStatusText = '' then
      GBuildStatusText := '索引构建失败';
  finally
    IndexLockLeave;
  end;

  elapsedMs := TickElapsed(startTick);
  if GReady then
  begin
    if catchUpFailNote <> '' then
      extraDetail := '阶段耗时: 加载 ' + SafeLogFormatElapsed(loadMs) + catchUpPhaseTiming +
        ' / $MFT 构建 ' + SafeLogFormatElapsed(buildMs) +
        ' / 保存 ' + SafeLogFormatElapsed(saveMs)
    else
      extraDetail := '阶段耗时: 加载 ' + SafeLogFormatElapsed(loadMs) +
        ' / $MFT 构建 ' + SafeLogFormatElapsed(buildMs) +
        ' / 保存 ' + SafeLogFormatElapsed(saveMs);
    if driveTimingText <> '' then
    begin
      extraDetail := extraDetail + sLineBreak + '各卷 $MFT:';
      extraDetail := extraDetail + sLineBreak + driveTimingText;
    end;
    if catchUpFailNote <> '' then
      extraDetail := catchUpFailNote + sLineBreak + sLineBreak + extraDetail;
    if cacheLoaded and not cacheUsable then
      extraDetail := '缓存不可用（文件数=' + IntToStr(staleCacheFileCount) +
        '，已索引盘=' + IntToStr(staleIndexedDrives) +
        '，NTFS 盘=' + IntToStr(staleMountedNtfs) +
        '，原因：' + cacheRejectReason + '），已改从 $MFT 重建' + sLineBreak + sLineBreak + extraDetail;
    if GBuildFailureDetail <> '' then
      extraDetail := extraDetail + GBuildFailureDetail;
    LogIndexBuildResult(True, 'NTFS USN', elapsedMs, extraDetail);
    if not GIndexShuttingDown then
      UsnMonitorStart(GUsnThreads, GDriveLetters, GUsnChangedHandler.OnUsnRecords,
        GUsnCheckpoints);
  end
  else
  begin
    if failDetail = '' then
    begin
      failDetail := IndexErrorToText(GLastError);
      if GBuildFailureDetail <> '' then
        failDetail := failDetail + sLineBreak + GBuildFailureDetail;
    end;
    if cacheLoaded then
      failDetail := '缓存加载后无有效记录，$MFT 重建失败' + sLineBreak + failDetail;
    if catchUpFailNote <> '' then
      failDetail := catchUpFailNote + sLineBreak + sLineBreak + failDetail;
    LogIndexBuildResult(False, 'NTFS USN', elapsedMs, '失败原因: ' + failDetail);
  end;
end;

procedure StartBuildThread(ATryCacheFirst: Boolean);
begin
  IndexLockEnter;
  try
    if GIndexShuttingDown or GBuilding then
      Exit;
    if GBuildThread <> nil then
    begin
      GBuildThread.Terminate;
      GBuildThread.WaitFor;
      FreeAndNil(GBuildThread);
    end;
    GBuilding := True;
    GReady := False;
    GBuildThread := TEverythingBuildThread.Create(ATryCacheFirst);
    GBuildThread.Start;
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexFileCount: Integer;
begin
  Result := GDB.FileCount;
end;

function EverythingIndexGetFullPath(AFileIndex: Integer): string;
begin
  IndexLockEnter;
  try
    Result := BuildFullPathLocked(AFileIndex);
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexGetFileName(AFileIndex: Integer): string;
begin
  if (AFileIndex < 0) or (AFileIndex >= GDB.FileCount) then
    Exit('');
  Result := NamePoolToString(GDB, GDB.Files[AFileIndex].NamePoolOffset);
end;

function EverythingIndexGetExtension(AFileIndex: Integer): string;
begin
  Result := '';
  if (AFileIndex < 0) or (AFileIndex >= GDB.FileCount) then
    Exit;
  Result := ExtNameFromIdLocked(GDB.Files[AFileIndex].ExtID);
end;

function EverythingIndexGetModifiedUtc(AFileIndex: Integer): Int64;
var
  delta: Cardinal;
begin
  if (AFileIndex < 0) or (AFileIndex >= GDB.FileCount) then
    Exit(0);
  delta := GDB.VolumeBaseDate + GDB.Files[AFileIndex].DateModifiedDelta;
  Result := Int64(delta);
end;

procedure EverythingIndexStartupAsync;
begin
  StartBuildThread(True);
end;

procedure EverythingIndexStartBuild;
begin
  StartBuildThread(False);
end;

procedure EverythingIndexStopBuild;
var
  th: TThread;
begin
  IndexLockEnter;
  try
    th := GBuildThread;
    GBuildThread := nil;
  finally
    IndexLockLeave;
  end;
  if th <> nil then
  begin
    th.Terminate;
    th.WaitFor;
    FreeAndNil(th);
  end;
  IndexLockEnter;
  try
    GBuilding := False;
  finally
    IndexLockLeave;
  end;
end;

procedure EverythingIndexShutdown;
begin
  if GIndexShuttingDown then
    Exit;
  GIndexShuttingDown := True;
  GNotifyHwnd := 0;
  EverythingIndexStopBuild;
  UsnMonitorStop(GUsnThreads);
  IndexLockEnter;
  try
    if GReady and (GDB.FileCount > 0) then
    begin
      RefreshUsnCheckpoints(GUsnCheckpoints);
      EverythingDbSave(GDB, GDriveLetters, GFileFrnKeys, GUsnCheckpoints);
    end;
    EverythingDbClear(GDB);
    GReady := False;
    GBuilding := False;
  finally
    IndexLockLeave;
  end;
  FreeAndNil(GFrnToFolder);
  FreeAndNil(GSegToFolder);
  FreeAndNil(GFrnToFile);
  SetLength(GFileFrnKeys, 0);
  FreeAndNil(GExcludedFrn);
  FreeAndNil(GFileLookup);
end;

function EverythingIndexIsReady: Boolean;
begin
  IndexLockEnter;
  try
    Result := GReady;
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexIsBuilding: Boolean;
begin
  IndexLockEnter;
  try
    Result := GBuilding;
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexGetBuildStatusText: string;
begin
  if not EverythingIndexIsBuilding then
    Exit('');
  Result := GBuildStatusText;
end;

function EverythingIndexGetLastError: TEverythingIndexError;
begin
  IndexLockEnter;
  try
    Result := GLastError;
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexWaitUntilReady(ATimeoutMs: Cardinal; APump: TEverythingIndexPumpProc): Boolean;
var
  startTick: Cardinal;
begin
  if EverythingIndexIsReady then
    Exit(True);
  startTick := GetTickCount;
  while EverythingIndexIsBuilding do
  begin
    if Assigned(APump) then
      APump;
    if (ATimeoutMs > 0) and (GetTickCount - startTick >= ATimeoutMs) then
      Exit(False);
    Sleep(10);
  end;
  Result := EverythingIndexIsReady;
end;

function EverythingIndexHitIsFolder(AHitIndex: Integer): Boolean;
begin
  Result := AHitIndex < 0;
end;

function EverythingIndexGetExtCount: Integer;
begin
  IndexLockEnter;
  try
    Result := GDB.ExtCount;
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexGetExtNameById(AExtId: Word): string;
begin
  IndexLockEnter;
  try
    Result := ExtNameFromIdLocked(AExtId);
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexGetHitFilterKind(AHitIndex: Integer; const AExtIdToKind: TExtFilterKindMap;
  AFolderKindIndex, AOtherKindIndex: Integer): Integer;
var
  extId: Word;
  mapLen: Integer;
begin
  if AHitIndex < 0 then
    Exit(AFolderKindIndex);
  mapLen := Length(AExtIdToKind);
  IndexLockEnter;
  try
    if (AHitIndex < 0) or (AHitIndex >= GDB.FileCount) or (AHitIndex >= Length(GDB.Files)) then
      Exit(AOtherKindIndex);
    extId := GDB.Files[AHitIndex].ExtID;
    if (extId = 0) or (Integer(extId) >= mapLen) then
      Result := AOtherKindIndex
    else
      Result := AExtIdToKind[extId];
  finally
    IndexLockLeave;
  end;
end;

procedure EverythingIndexCountHitFilterKinds(const AHits: TEverythingHitArray;
  AFolderKindIndex, AOtherKindIndex: Integer; const AExtIdToKind: TExtFilterKindMap;
  var ACounts: array of Integer);
var
  i, hit, kind, mapLen: Integer;
  extId: Word;
begin
  FillChar(ACounts, Length(ACounts) * SizeOf(Integer), 0);
  if Length(AHits) = 0 then
    Exit;
  ACounts[0] := Length(AHits);
  mapLen := Length(AExtIdToKind);
  IndexLockEnter;
  try
    for i := 0 to High(AHits) do
    begin
      hit := AHits[i];
      if hit < 0 then
      begin
        Inc(ACounts[AFolderKindIndex]);
        Continue;
      end;
      if (hit >= GDB.FileCount) or (hit >= Length(GDB.Files)) then
      begin
        Inc(ACounts[AOtherKindIndex]);
        Continue;
      end;
      extId := GDB.Files[hit].ExtID;
      if (extId = 0) or (Integer(extId) >= mapLen) then
        kind := AOtherKindIndex
      else
        kind := AExtIdToKind[extId];
      Inc(ACounts[kind]);
    end;
  finally
    IndexLockLeave;
  end;
end;

procedure EverythingIndexBuildSearchFilterRowMap(const AHits: TEverythingHitArray;
  AFilterIndex, AFolderKindIndex, AOtherKindIndex: Integer;
  const AExtIdToKind: TExtFilterKindMap; out ARowMap: TSearchHitIndexArray);
var
  i, hit, m, kind, mapLen: Integer;
  extId: Word;
begin
  SetLength(ARowMap, Length(AHits));
  m := 0;
  mapLen := Length(AExtIdToKind);
  IndexLockEnter;
  try
    for i := 0 to High(AHits) do
    begin
      hit := AHits[i];
      if hit < 0 then
        kind := AFolderKindIndex
      else if (hit >= GDB.FileCount) or (hit >= Length(GDB.Files)) then
        kind := AOtherKindIndex
      else
      begin
        extId := GDB.Files[hit].ExtID;
        if (extId = 0) or (Integer(extId) >= mapLen) then
          kind := AOtherKindIndex
        else
          kind := AExtIdToKind[extId];
      end;
      if AFilterIndex = AOtherKindIndex then
      begin
        if kind = AOtherKindIndex then
        begin
          ARowMap[m] := i;
          Inc(m);
        end;
      end
      else if kind = AFilterIndex then
      begin
        ARowMap[m] := i;
        Inc(m);
      end;
    end;
  finally
    IndexLockLeave;
  end;
  SetLength(ARowMap, m);
end;

function EverythingIndexGetHitFileName(AHitIndex: Integer): string;
var
  folderIdx: Integer;
begin
  Result := '';
  IndexLockEnter;
  try
    if AHitIndex < 0 then
    begin
      folderIdx := -(AHitIndex + 1);
      if (folderIdx >= 0) and (folderIdx < GDB.FolderCount) and (folderIdx < Length(GDB.Folders)) then
        Result := NamePoolToString(GDB, GDB.Folders[folderIdx].NamePoolOffset);
    end
    else if (AHitIndex >= 0) and (AHitIndex < GDB.FileCount) and (AHitIndex < Length(GDB.Files)) then
      Result := NamePoolToString(GDB, GDB.Files[AHitIndex].NamePoolOffset);
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexGetHitExtension(AHitIndex: Integer): string;
begin
  Result := '';
  if EverythingIndexHitIsFolder(AHitIndex) then
    Exit;
  IndexLockEnter;
  try
    if (AHitIndex < 0) or (AHitIndex >= GDB.FileCount) or (AHitIndex >= Length(GDB.Files)) then
      Exit;
    Result := ExtNameFromIdLocked(GDB.Files[AHitIndex].ExtID);
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexGetHitPath(AHitIndex: Integer): string;
begin
  IndexLockEnter;
  try
    Result := BuildHitPathLocked(AHitIndex);
  finally
    IndexLockLeave;
  end;
end;

procedure EverythingIndexSortHitIndices(var AHitIndices: TEverythingHitArray;
  const ASortKind: TLibraryListSortKind; const ASortAsc: Boolean);
begin
  if Length(AHitIndices) < 2 then
    Exit;
  IndexLockEnter;
  try
    SortHitIndices(AHitIndices, GDB, ASortKind, ASortAsc);
  finally
    IndexLockLeave;
  end;
end;

function EverythingIndexSearch(const ANeedle: string; const ASortKind: TLibraryListSortKind;
  const ASortAsc: Boolean; const AIsCancelled: TEverythingIndexCancelledFunc;
  out AHitIndices: TEverythingHitArray; out ATotalCount: Cardinal;
  var ATiming: TSearchTiming; ASkipSort: Boolean): Boolean;
begin
  Result := False;
  SetLength(AHitIndices, 0);
  ATotalCount := 0;
  FillChar(ATiming, SizeOf(TSearchTiming), 0);
  if not EverythingIndexIsReady then
    Exit;
  IndexLockEnter;
  try
    Result := SearchVMExecute(GDB, ANeedle, ASortKind, ASortAsc, AIsCancelled, AHitIndices,
      ATotalCount, ATiming, ASkipSort);
  finally
    IndexLockLeave;
  end;
end;

procedure EverythingIndexPatchSearchHits(var AHits: TEverythingHitArray; const ANeedle: string;
  const AChanges: TIndexHitChangeArray);
begin
  if Length(AChanges) = 0 then
    Exit;
  IndexLockEnter;
  try
    SearchVMPatchHitIndices(AHits, GDB, ANeedle, AChanges);
  finally
    IndexLockLeave;
  end;
end;

procedure EverythingIndexDisposeHitChangesMsg(AData: PIndexHitChangesMsg);
begin
  if AData = nil then
    Exit;
  SetLength(AData^.Changes, 0);
  Dispose(AData);
end;

initialization
  InitializeCriticalSection(GIndexLock);
  GLastError := eieOk;
  GUsnThreads := nil;
  GNotifyHwnd := 0;
  FillChar(GUsnCheckpoints, SizeOf(GUsnCheckpoints), 0);
  GCatchUpInProgress := False;
  GUsnChangedHandler := TUsnChangedHandler.Create;

finalization
  EverythingIndexShutdown;
  FreeAndNil(GUsnChangedHandler);
  DeleteCriticalSection(GIndexLock);

end.
