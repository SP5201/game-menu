unit Core.Model;

interface

uses
  Windows;

const
  cRootParentOffset = Cardinal($FFFFFFFF);
  cMaxExtTable = 2048;
  cExtNameMaxLen = 15;

type
  PExtEntry = ^TExtEntry;
  TExtEntry = packed record
    ExtID: Word;
    ExtName: array[0..cExtNameMaxLen] of AnsiChar;
  end;

  PFolderEntry = ^TFolderEntry;
  TFolderEntry = packed record
    FRN: UInt64;
    ParentOffset: Cardinal;
    NamePoolOffset: Cardinal;
    DateModified: Cardinal;
    Attributes: Word;
    DriveIndex: Byte;
    Padding: Byte;
  end;

  PFileEntry = ^TFileEntry;
  TFileEntry = packed record
    ParentOffset: Cardinal;
    NamePoolOffset: Cardinal;
    SizeLow: Cardinal;
    DateModifiedDelta: Word;
    ExtID: Word;
  end;

  TEverythingDB = record
    Folders: array of TFolderEntry;
    FolderCount: Integer;
    Files: array of TFileEntry;
    FileCount: Integer;
    NamePool: array of Byte;
    NamePoolUsed: Cardinal;
    ExtTable: array[0..cMaxExtTable - 1] of TExtEntry;
    ExtCount: Integer;
    VolumeBaseDate: Cardinal;
  end;

  TMftRawItem = record
    FRN: UInt64;
    ParentFRN: UInt64;
    NamePoolOffset: Cardinal;
    DateModified: Cardinal;
    Attributes: Word;
    SizeLow: Cardinal;
    IsDirectory: Boolean;
    DriveIndex: Byte;
    Excluded: Boolean;
  end;

  TUsnJournalRecord = record
    FRN: UInt64;
    ParentFRN: UInt64;
    Reason: DWORD;
    TimeStamp: Int64;
    FileAttributes: DWORD;
    FileName: string;
  end;

  TUsnJournalRecordArray = array of TUsnJournalRecord;

  TUsnCheckpoint = packed record
    JournalId: Int64;
    LastUsn: Int64;
  end;

  TUsnCheckpointArray = array[0..25] of TUsnCheckpoint;

  TDriveLetterMap = array[0..25] of Char;

  TFileFrnKeyArray = array of UInt64;

  TIndexHitChangeKind = (
    ihckFileRemoved,
    ihckFileRemapped,
    ihckFileAdded,
    ihckFileUpdated,
    ihckFolderRemoved,
    ihckFolderAdded,
    ihckFolderUpdated);

  TIndexHitChange = record
    Kind: TIndexHitChangeKind;
    HitIndex: Integer;
    NewHitIndex: Integer;
  end;

  TIndexHitChangeArray = array of TIndexHitChange;

  PIndexHitChangesMsg = ^TIndexHitChangesMsg;
  TIndexHitChangesMsg = record
    Changes: TIndexHitChangeArray;
  end;

implementation

end.
