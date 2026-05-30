unit LibraryStore;

interface

uses
  SysUtils, SQLite3Wrap;

const
  /// <summary>groups.list_sort_flags：按名称（与 LIST_SORT_BY_FILE_TYPE 互斥；二者皆无表示按添加时间）。</summary>
  LIST_SORT_BY_NAME = $00000001;
  /// <summary>groups.list_sort_flags：递增（清除则为递减）。</summary>
  LIST_SORT_ASC = $00000002;
  /// <summary>groups.list_sort_flags：按文件扩展名 / 类型（与 LIST_SORT_BY_NAME 互斥）。</summary>
  LIST_SORT_BY_FILE_TYPE = $00000004;
  /// <summary>默认：按添加时间、递增（仅 LIST_SORT_ASC，无名称/类型位）。</summary>
  LIST_SORT_DEFAULT = LIST_SORT_ASC;

type
  /// <summary>主列表排序维度（与 list_sort_flags 编码一致）。</summary>
  TLibraryListSortKind = (llskName, llskAddTime, llskFileType);
  TLibraryGroup = record
    GroupIndex: Integer;
    GroupName: WideString;
    IconFile: WideString;
    ItemWidth: Integer;
    /// <summary>列表排序选项位或（LIST_SORT_BY_NAME、LIST_SORT_BY_FILE_TYPE、LIST_SORT_ASC 等）。</summary>
    ListSortFlags: Integer;
  end;

  TLibraryGroupArray = array of TLibraryGroup;
  TLibraryItem = record
    FilePath: WideString;
    FileName: WideString;
    IconCachePath: WideString;
    FileParams: WideString;
    WorkingDir: WideString;
  end;

  TLibraryItemArray = array of TLibraryItem;
  TLibraryInsertResultArray = array of Boolean;

  TLibrarySearchHit = record
    GroupIndex: Integer;
    Item: TLibraryItem;
  end;
  TLibrarySearchHitArray = array of TLibrarySearchHit;

type
  TLibraryStore = class
  private
    FDB: TSQLite3Database;
    procedure EnsureSchema;
    function ColumnExists(const ATableName, AColumnName: WideString): Boolean;
    procedure EnsureGroupExists(const AGroupIndex: Integer; const AGroupName: WideString = '');
    function NextGroupIndex: Integer;
  public
    constructor Create(const ADatabasePath: string);
    destructor Destroy; override;
    function CreateGroup(const AGroupName: WideString; const AIconFile: WideString = ''): Integer;
    function RenameGroup(const AGroupIndex: Integer; const AGroupName: WideString): Boolean;
    function UpdateGroup(const AGroupIndex: Integer; const AGroupName, AIconFile: WideString): Boolean;
    function UpdateGroupItemWidth(const AGroupIndex, AItemWidth: Integer): Boolean;
    procedure GetGroupListSort(const AGroupIndex: Integer; out AKind: TLibraryListSortKind; out AAscending: Boolean);
    procedure UpdateGroupListSort(const AGroupIndex: Integer; const AKind: TLibraryListSortKind; const AAscending: Boolean);
    function GetGroupItemWidth(const AGroupIndex, ADefaultWidth: Integer): Integer;
    function DeleteGroup(const AGroupIndex: Integer): Boolean;
    function DeleteItem(const AGroupIndex: Integer; const AFilePath: WideString): Boolean;
    function TryInsertItem(const AGroupIndex: Integer; const AFilePath, ATitle, AIconPath, AParams, AWorkingDir: WideString): Boolean;
    function TryInsertItemsBatch(const AGroupIndex: Integer; const AItems: TLibraryItemArray;
      out AInsertedFlags: TLibraryInsertResultArray): Integer;
    function UpdateItem(const AGroupIndex: Integer; const AFilePath, ATitle, AParams, AWorkingDir: WideString): Boolean;
    function LoadGroups: TLibraryGroupArray;
    function LoadItemsByGroup(const AGroupIndex: Integer): TLibraryItemArray;
    function SearchLibraryGlobal(const ANeedle: WideString): TLibrarySearchHitArray;
  end;

implementation

uses
  SQLite3;

function EscapeSqlLikePattern(const S: WideString): WideString;
var
  i: Integer;
  ch: WideChar;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    ch := S[i];
    if (ch = '%') or (ch = '_') or (ch = '\') then
      Result := Result + '\' + ch
    else
      Result := Result + ch;
  end;
end;

function EncodeListSortFlags(const AKind: TLibraryListSortKind; const AAscending: Boolean): Integer;
begin
  Result := 0;
  case AKind of
    llskName:
      Result := Result or LIST_SORT_BY_NAME;
    llskAddTime:
      ;
    llskFileType:
      Result := Result or LIST_SORT_BY_FILE_TYPE;
  end;
  if AAscending then
    Result := Result or LIST_SORT_ASC;
end;

procedure DecodeListSortFlags(const AFlags: Integer; out AKind: TLibraryListSortKind; out AAscending: Boolean);
begin
  if (AFlags and LIST_SORT_BY_FILE_TYPE) <> 0 then
    AKind := llskFileType
  else if (AFlags and LIST_SORT_BY_NAME) <> 0 then
    AKind := llskName
  else
    AKind := llskAddTime;
  AAscending := (AFlags and LIST_SORT_ASC) <> 0;
end;

function TLibraryStore.ColumnExists(const ATableName, AColumnName: WideString): Boolean;
var
  stmt: TSQLite3Statement;
begin
  Result := False;
  stmt := FDB.Prepare('PRAGMA table_info(' + ATableName + ')');
  try
    while stmt.Step = SQLITE_ROW do
    begin
      if SameText(stmt.ColumnText(1), string(AColumnName)) then
      begin
        Result := True;
        Exit;
      end;
    end;
  finally
    stmt.Free;
  end;
end;

procedure TLibraryStore.EnsureSchema;
begin
  FDB.Execute(
    'CREATE TABLE IF NOT EXISTS groups (' +
    'group_index INTEGER PRIMARY KEY,' +
    'group_name TEXT NOT NULL,' +
    'icon_file TEXT NOT NULL DEFAULT '''',' +
    'item_width INTEGER NOT NULL DEFAULT 130,' +
    'list_sort_flags INTEGER NOT NULL DEFAULT ' + IntToStr(LIST_SORT_DEFAULT) + ');');
  if not ColumnExists('groups', 'icon_file') then
    FDB.Execute('ALTER TABLE groups ADD COLUMN icon_file TEXT NOT NULL DEFAULT '''';');
  if not ColumnExists('groups', 'item_width') then
    FDB.Execute('ALTER TABLE groups ADD COLUMN item_width INTEGER NOT NULL DEFAULT 130;');
  if not ColumnExists('groups', 'list_sort_flags') then
  begin
    FDB.Execute(
      'ALTER TABLE groups ADD COLUMN list_sort_flags INTEGER NOT NULL DEFAULT ' + IntToStr(LIST_SORT_DEFAULT) + ';');
    if ColumnExists('groups', 'list_sort_by_name') and ColumnExists('groups', 'list_sort_asc') then
      FDB.Execute(
        'UPDATE groups SET list_sort_flags = ' +
        '((CASE WHEN list_sort_by_name<>0 THEN ' + IntToStr(LIST_SORT_BY_NAME) + ' ELSE 0 END) | ' +
        '(CASE WHEN list_sort_asc<>0 THEN ' + IntToStr(LIST_SORT_ASC) + ' ELSE 0 END));');
  end;
  FDB.Execute(
    'CREATE TABLE IF NOT EXISTS library_items (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT,' +
    'group_index INTEGER NOT NULL,' +
    'file_path TEXT NOT NULL,' +
    'icon_path TEXT NOT NULL DEFAULT '''',' +
    'title TEXT NOT NULL,' +
    'params TEXT NOT NULL DEFAULT '''',' +
    'working_dir TEXT NOT NULL DEFAULT '''',' +
    'UNIQUE(group_index, file_path));');
  if not ColumnExists('library_items', 'icon_path') then
    FDB.Execute('ALTER TABLE library_items ADD COLUMN icon_path TEXT NOT NULL DEFAULT '''';');
  if not ColumnExists('library_items', 'params') then
    FDB.Execute('ALTER TABLE library_items ADD COLUMN params TEXT NOT NULL DEFAULT '''';');
  if not ColumnExists('library_items', 'working_dir') then
    FDB.Execute('ALTER TABLE library_items ADD COLUMN working_dir TEXT NOT NULL DEFAULT '''';');
  FDB.Execute(
    'INSERT OR IGNORE INTO groups(group_index, group_name) ' +
    'SELECT DISTINCT group_index, ''分组'' || CAST(group_index AS TEXT) FROM library_items;');
end;

procedure TLibraryStore.EnsureGroupExists(const AGroupIndex: Integer; const AGroupName: WideString);
var
  stmt: TSQLite3Statement;
  name: WideString;
begin
  name := Trim(AGroupName);
  if name = '' then
    name := WideString('分组' + IntToStr(AGroupIndex));

  stmt := FDB.Prepare(
    'INSERT OR IGNORE INTO groups(group_index,group_name,icon_file,item_width,list_sort_flags) VALUES(?,?,?,?,?)');
  try
    stmt.BindInt(1, AGroupIndex);
    stmt.BindText(2, name);
    stmt.BindText(3, '');
    stmt.BindInt(4, 130);
    stmt.BindInt(5, LIST_SORT_DEFAULT);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
end;

function TLibraryStore.NextGroupIndex: Integer;
var
  stmt: TSQLite3Statement;
begin
  Result := 0;
  stmt := FDB.Prepare('SELECT IFNULL(MAX(group_index), -1) + 1 FROM groups');
  try
    if stmt.Step = SQLITE_ROW then
      Result := stmt.ColumnInt(0);
  finally
    stmt.Free;
  end;
end;

function TLibraryStore.CreateGroup(const AGroupName: WideString; const AIconFile: WideString): Integer;
var
  trimmedGroupName: WideString;
  iconFile: WideString;
  stmt: TSQLite3Statement;
begin
  trimmedGroupName := Trim(AGroupName);
  iconFile := Trim(AIconFile);
  Result := NextGroupIndex;
  if trimmedGroupName = '' then
    trimmedGroupName := WideString('分组' + IntToStr(Result));
  stmt := FDB.Prepare(
    'INSERT INTO groups(group_index,group_name,icon_file,item_width,list_sort_flags) VALUES(?,?,?,?,?)');
  try
    stmt.BindInt(1, Result);
    stmt.BindText(2, trimmedGroupName);
    stmt.BindText(3, iconFile);
    stmt.BindInt(4, 130);
    stmt.BindInt(5, LIST_SORT_DEFAULT);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
end;

function TLibraryStore.RenameGroup(const AGroupIndex: Integer; const AGroupName: WideString): Boolean;
var
  stmt: TSQLite3Statement;
  groupName: WideString;
begin
  groupName := Trim(AGroupName);
  if groupName = '' then
    Exit(False);

  EnsureGroupExists(AGroupIndex);
  stmt := FDB.Prepare('UPDATE groups SET group_name=? WHERE group_index=?');
  try
    stmt.BindText(1, groupName);
    stmt.BindInt(2, AGroupIndex);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
  Result := sqlite3_changes(FDB.Handle) > 0;
end;

function TLibraryStore.UpdateGroup(const AGroupIndex: Integer; const AGroupName, AIconFile: WideString): Boolean;
var
  stmt: TSQLite3Statement;
  groupName: WideString;
  iconFile: WideString;
begin
  groupName := Trim(AGroupName);
  iconFile := Trim(AIconFile);
  if groupName = '' then
    Exit(False);

  EnsureGroupExists(AGroupIndex);
  stmt := FDB.Prepare('UPDATE groups SET group_name=?, icon_file=? WHERE group_index=?');
  try
    stmt.BindText(1, groupName);
    stmt.BindText(2, iconFile);
    stmt.BindInt(3, AGroupIndex);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
  Result := sqlite3_changes(FDB.Handle) > 0;
end;

function TLibraryStore.UpdateGroupItemWidth(const AGroupIndex, AItemWidth: Integer): Boolean;
var
  stmt: TSQLite3Statement;
begin
  stmt := FDB.Prepare('UPDATE groups SET item_width=? WHERE group_index=?');
  try
    stmt.BindInt(1, AItemWidth);
    stmt.BindInt(2, AGroupIndex);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
  Result := sqlite3_changes(FDB.Handle) > 0;
end;

procedure TLibraryStore.GetGroupListSort(const AGroupIndex: Integer; out AKind: TLibraryListSortKind; out AAscending: Boolean);
var
  stmt: TSQLite3Statement;
  flags: Integer;
begin
  DecodeListSortFlags(LIST_SORT_DEFAULT, AKind, AAscending);
  EnsureGroupExists(AGroupIndex);
  stmt := FDB.Prepare('SELECT list_sort_flags FROM groups WHERE group_index=?');
  try
    stmt.BindInt(1, AGroupIndex);
    if stmt.Step = SQLITE_ROW then
    begin
      flags := stmt.ColumnInt(0);
      DecodeListSortFlags(flags, AKind, AAscending);
    end;
  finally
    stmt.Free;
  end;
end;

procedure TLibraryStore.UpdateGroupListSort(const AGroupIndex: Integer; const AKind: TLibraryListSortKind; const AAscending: Boolean);
var
  stmt: TSQLite3Statement;
begin
  EnsureGroupExists(AGroupIndex);
  stmt := FDB.Prepare('UPDATE groups SET list_sort_flags=? WHERE group_index=?');
  try
    stmt.BindInt(1, EncodeListSortFlags(AKind, AAscending));
    stmt.BindInt(2, AGroupIndex);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
end;

function TLibraryStore.GetGroupItemWidth(const AGroupIndex, ADefaultWidth: Integer): Integer;
var
  stmt: TSQLite3Statement;
begin
  Result := ADefaultWidth;
  stmt := FDB.Prepare('SELECT item_width FROM groups WHERE group_index=?');
  try
    stmt.BindInt(1, AGroupIndex);
    if stmt.Step = SQLITE_ROW then
      Result := stmt.ColumnInt(0);
  finally
    stmt.Free;
  end;
end;

function TLibraryStore.DeleteGroup(const AGroupIndex: Integer): Boolean;
var
  stmt: TSQLite3Statement;
begin
  FDB.Execute('DELETE FROM library_items WHERE group_index=' + IntToStr(AGroupIndex));
  stmt := FDB.Prepare('DELETE FROM groups WHERE group_index=?');
  try
    stmt.BindInt(1, AGroupIndex);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
  Result := sqlite3_changes(FDB.Handle) > 0;
end;

function TLibraryStore.DeleteItem(const AGroupIndex: Integer; const AFilePath: WideString): Boolean;
var
  stmt: TSQLite3Statement;
begin
  stmt := FDB.Prepare('DELETE FROM library_items WHERE group_index=? AND file_path=?');
  try
    stmt.BindInt(1, AGroupIndex);
    stmt.BindText(2, AFilePath);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
  Result := sqlite3_changes(FDB.Handle) > 0;
end;

constructor TLibraryStore.Create(const ADatabasePath: string);
begin
  inherited Create;
  FDB := TSQLite3Database.Create;
  FDB.Open(WideString(ADatabasePath));
  EnsureSchema;
end;

destructor TLibraryStore.Destroy;
begin
  FDB.Free;
  inherited;
end;

function TLibraryStore.TryInsertItem(const AGroupIndex: Integer;
  const AFilePath, ATitle, AIconPath, AParams, AWorkingDir: WideString): Boolean;
var
  stmt: TSQLite3Statement;
begin
  EnsureGroupExists(AGroupIndex);
  stmt := FDB.Prepare('INSERT OR IGNORE INTO library_items(group_index,file_path,title,icon_path,params,working_dir) VALUES(?,?,?,?,?,?)');
  try
    stmt.BindInt(1, AGroupIndex);
    stmt.BindText(2, AFilePath);
    stmt.BindText(3, ATitle);
    stmt.BindText(4, AIconPath);
    stmt.BindText(5, AParams);
    stmt.BindText(6, AWorkingDir);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
  Result := sqlite3_changes(FDB.Handle) > 0;
end;

function TLibraryStore.TryInsertItemsBatch(const AGroupIndex: Integer;
  const AItems: TLibraryItemArray; out AInsertedFlags: TLibraryInsertResultArray): Integer;
var
  stmt: TSQLite3Statement;
  i: Integer;
  stepResult: Integer;
begin
  Result := 0;
  if Length(AItems) = 0 then
  begin
    AInsertedFlags := nil;
    Exit;
  end;
  SetLength(AInsertedFlags, Length(AItems));

  EnsureGroupExists(AGroupIndex);
  FDB.Execute('BEGIN IMMEDIATE TRANSACTION');
  try
    stmt := FDB.Prepare('INSERT OR IGNORE INTO library_items(group_index,file_path,title,icon_path,params,working_dir) VALUES(?,?,?,?,?,?)');
    try
      for i := 0 to High(AItems) do
      begin
        stmt.BindInt(1, AGroupIndex);
        stmt.BindText(2, AItems[i].FilePath);
        stmt.BindText(3, AItems[i].FileName);
        stmt.BindText(4, AItems[i].IconCachePath);
        stmt.BindText(5, AItems[i].FileParams);
        stmt.BindText(6, AItems[i].WorkingDir);
        stepResult := stmt.StepAndReset;
        if stepResult <> SQLITE_DONE then
          raise Exception.Create('批量插入失败');
        AInsertedFlags[i] := sqlite3_changes(FDB.Handle) > 0;
        if AInsertedFlags[i] then
          Inc(Result);
      end;
    finally
      stmt.Free;
    end;
    FDB.Execute('COMMIT');
  except
    FDB.Execute('ROLLBACK');
    raise;
  end;
end;

function TLibraryStore.UpdateItem(const AGroupIndex: Integer; const AFilePath, ATitle,
  AParams, AWorkingDir: WideString): Boolean;
var
  stmt: TSQLite3Statement;
  trimmedTitle, trimmedParams, trimmedWorkDir: WideString;
begin
  trimmedTitle := Trim(ATitle);
  trimmedParams := Trim(AParams);
  trimmedWorkDir := Trim(AWorkingDir);
  if trimmedTitle = '' then
    Exit(False);

  EnsureGroupExists(AGroupIndex);
  stmt := FDB.Prepare('UPDATE library_items SET title=?, params=?, working_dir=? WHERE group_index=? AND file_path=?');
  try
    stmt.BindText(1, trimmedTitle);
    stmt.BindText(2, trimmedParams);
    stmt.BindText(3, trimmedWorkDir);
    stmt.BindInt(4, AGroupIndex);
    stmt.BindText(5, AFilePath);
    stmt.StepAndReset;
  finally
    stmt.Free;
  end;
  Result := sqlite3_changes(FDB.Handle) > 0;
end;

function TLibraryStore.LoadGroups: TLibraryGroupArray;
var
  stmt: TSQLite3Statement;
  n: Integer;
begin
  Result := nil;
  stmt := FDB.Prepare(
    'SELECT group_index, group_name, icon_file, item_width, list_sort_flags FROM groups ORDER BY group_index');
  try
    n := 0;
    while stmt.Step = SQLITE_ROW do
    begin
      SetLength(Result, n + 1);
      Result[n].GroupIndex := stmt.ColumnInt(0);
      Result[n].GroupName := stmt.ColumnText(1);
      Result[n].IconFile := stmt.ColumnText(2);
      Result[n].ItemWidth := stmt.ColumnInt(3);
      Result[n].ListSortFlags := stmt.ColumnInt(4);
      Inc(n);
    end;
  finally
    stmt.Free;
  end;
end;

function TLibraryStore.LoadItemsByGroup(const AGroupIndex: Integer): TLibraryItemArray;
var
  stmt: TSQLite3Statement;
  n: Integer;
begin
  Result := nil;
  stmt := FDB.Prepare('SELECT file_path, title, icon_path, params, working_dir FROM library_items WHERE group_index = ? ORDER BY id');
  try
    stmt.BindInt(1, AGroupIndex);
    n := 0;
    while stmt.Step = SQLITE_ROW do
    begin
      SetLength(Result, n + 1);
      Result[n].FilePath := stmt.ColumnText(0);
      Result[n].FileName := stmt.ColumnText(1);
      Result[n].IconCachePath := stmt.ColumnText(2);
      Result[n].FileParams := stmt.ColumnText(3);
      Result[n].WorkingDir := stmt.ColumnText(4);
      Inc(n);
    end;
  finally
    stmt.Free;
  end;
end;

function TLibraryStore.SearchLibraryGlobal(const ANeedle: WideString): TLibrarySearchHitArray;
var
  stmt: TSQLite3Statement;
  n: Integer;
  esc, pat: WideString;
begin
  SetLength(Result, 0);
  esc := Trim(ANeedle);
  if esc = '' then
    Exit;
  esc := EscapeSqlLikePattern(esc);
  pat := '%' + esc + '%';
  stmt := FDB.Prepare(
    'SELECT li.group_index, li.file_path, li.title, li.icon_path, li.params, li.working_dir ' +
    'FROM library_items li ' +
    'WHERE (li.title LIKE ? ESCAPE ''\'') OR (li.file_path LIKE ? ESCAPE ''\'') ' +
    'ORDER BY li.id');
  try
    stmt.BindText(1, pat);
    stmt.BindText(2, pat);
    n := 0;
    while stmt.Step = SQLITE_ROW do
    begin
      SetLength(Result, n + 1);
      Result[n].GroupIndex := stmt.ColumnInt(0);
      Result[n].Item.FilePath := stmt.ColumnText(1);
      Result[n].Item.FileName := stmt.ColumnText(2);
      Result[n].Item.IconCachePath := stmt.ColumnText(3);
      Result[n].Item.FileParams := stmt.ColumnText(4);
      Result[n].Item.WorkingDir := stmt.ColumnText(5);
      Inc(n);
    end;
  finally
    stmt.Free;
  end;
end;

end.
