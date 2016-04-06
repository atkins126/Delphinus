{
#########################################################
# Copyright by Alexander Benikowski                     #
# This unit is part of the Delphinus project hosted on  #
# https://github.com/Memnarch/Delphinus                 #
#########################################################
}
unit DN.Uninstaller;

interface

uses
  Classes,
  Types,
  SysUtils,
  DN.Types,
  DN.Uninstaller.Intf,
  DN.JSonFile.Uninstallation,
  DN.Progress.Intf;

type
  TDNUninstaller = class(TInterfacedObject, IDNUninstaller, IDNProgress)
  private
    FOnMessage: TMessageEvent;
    FProgress: IDNProgress;
    function ProcessPackages(const APackages: TArray<TPackage>): Boolean;
    function DeleteRawFiles(const ARawFiles: TArray<string>): Boolean;
    function DeleteFiles(const ADirectory: string): Boolean;
    function DeleteComponentFile(const AFile: string; const AWarningWhenMissing: Boolean = True): Boolean;
    function RemovePathes(const ASearchPathes: string; APathType: TPathType): Boolean;
    function GetOnMessage: TMessageEvent;
    procedure SetOnMessage(const Value: TMessageEvent);
  protected
    function UninstallPackage(const ABPLFile: string): Boolean; virtual;
    function RemoveSearchPath(const ASearchPath: string): Boolean; virtual;
    function RemoveBrowsingPath(const ABrowsingPath: string): Boolean; virtual;
    procedure DoMessage(AType: TMessageType; const AMessage: string);
    //properties for interfaceredirection
    property Progress: IDNProgress read FProgress implements IDNProgress;
  public
    constructor Create;
    destructor Destroy; override;
    function Uninstall(const ADirectory: string): Boolean; virtual;
    property OnMessage: TMessageEvent read GetOnMessage write SetOnMessage;
  end;

implementation

uses
  IOUtils,
  StrUtils,
  DN.Progress;

{ TDNUninstaller }

constructor TDNUninstaller.Create;
begin
  inherited;
  FProgress := TDNProgress.Create();
end;

function TDNUninstaller.DeleteComponentFile(const AFile: string; const AWarningWhenMissing: Boolean): Boolean;
begin
  Result := True;
  if TFile.Exists(AFile) then
  begin
    DoMessage(mtNotification, 'deleting ' + ExtractFileName(AFile));
    Result := DeleteFile(AFile);
    if TFile.Exists(AFile) then
      DoMessage(mtError, 'failed to delete');
  end
  else
  begin
    if AWarningWhenMissing then
      DoMessage(mtWarning, 'file did not exist ' + AFile);
  end;
end;

function TDNUninstaller.DeleteFiles(const ADirectory: string): Boolean;
begin
  DoMessage(mtNotification, 'Deleting Directory ' + ADirectory);
  TDirectory.Delete(ADirectory, True);
  Result := not TDirectory.Exists(ADirectory);
  if not Result then
    DoMessage(mtError, 'failed to delete directory');
end;

function TDNUninstaller.DeleteRawFiles(
  const ARawFiles: TArray<string>): Boolean;
var
  LFile: string;
begin
  Result := True;
  if Length(ARawFiles) > 0 then
    DoMessage(mtNotification, 'Deleting Rawfiles');

  for LFile in ARawFiles do
    if TFile.Exists(LFile) then
      TFile.Delete(LFile)
    else
      DoMessage(mtWarning, 'File not found: ' + LFile);
end;

destructor TDNUninstaller.Destroy;
begin
  FProgress := nil;
  inherited;
end;

procedure TDNUninstaller.DoMessage(AType: TMessageType; const AMessage: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(AType, AMessage);
end;

function TDNUninstaller.GetOnMessage: TMessageEvent;
begin
  Result := FOnMessage;
end;

function TDNUninstaller.ProcessPackages(const APackages: TArray<TPackage>): Boolean;
var
  LPackage: TPackage;
  LBPI, LLib: string;
  i: Integer;
begin
  Result := Length(APackages) = 0;
  for i := High(APackages) downto Low(APackages) do
  begin
    LPackage := APackages[i];
    if SameText(ExtractFileExt(LPackage.BPLFile), CMacPackageExtension) then
    begin
      LBPI := TPath.Combine(ExtractFilePath(LPackage.BPLFile), ChangeFileExt(ExtractFileName(LPackage.DCPFile), '.info.plist'));
      LLib := TPath.Combine(ExtractFilePath(LPackage.BPLFile), ChangeFileExt(ExtractFileName(LPackage.DCPFile), '.entitlements'));
    end
    else
    begin
      LBPI := ChangeFileExt(LPackage.DCPFile, '.bpi');
      LLib := ChangeFileExt(LPackage.DCPFile, '.lib');
    end;
    if LPackage.Installed then
    begin
      DoMessage(mtNotification, 'uninstalling package ' + LPackage.BPLFile);
      if not UninstallPackage(LPackage.BPLFile) then
        break;
    end;

    Result := DeleteComponentFile(LPackage.BPLFile);
    Result := DeleteComponentFile(LPackage.DCPFile) and Result;
    Result := DeleteComponentFile(LBPI, False) and Result;
    Result := DeleteComponentFile(LLib, False) and Result;
  end;
end;

function TDNUninstaller.RemoveBrowsingPath(
  const ABrowsingPath: string): Boolean;
begin
  Result := True;
end;

function TDNUninstaller.RemoveSearchPath(const ASearchPath: string): Boolean;
begin
  Result := True;
end;

function TDNUninstaller.RemovePathes(const ASearchPathes: string;APathType: TPathType): Boolean;
var
  LPathArray: TStringDynArray;
  LPath: string;
begin
  Result := True;
  LPathArray := SplitString(ASearchPathes, ';');
  if Length(LPathArray) > 0 then
  begin
    case APathType of
      tpSearchPath:  DoMessage(mtNotification, 'Removing Searchpathes:');
      tpBrowsingPath:  DoMessage(mtNotification, 'Removing Browsingpathes:');
    else
      DoMessage(mtError, 'Unknown pathtype');
      Exit(False);
    end;
    for LPath in LPathArray do
    begin
      DoMessage(mtNotification, LPath);
      case APathType of
        tpSearchPath: Result := RemoveSearchPath(LPath);
        tpBrowsingPath: Result := RemoveBrowsingPath(LPath);
      else
        Result := False;
      end;
      if not Result then
      begin
        DoMessage(mtError, 'Failed');
        Break;
      end;
    end;
  end;
end;

procedure TDNUninstaller.SetOnMessage(const Value: TMessageEvent);
begin
  FOnMessage := Value;
end;

function TDNUninstaller.Uninstall(const ADirectory: string): Boolean;
var
  LUninstallFile: string;
  LUninstall: TUninstallationFile;
begin
  Result := False;
  LUninstallFile := TPath.Combine(ADirectory, CUninstallFile);
  if TFile.Exists(LUninstallFile) then
  begin
    LUninstall := TUninstallationFile.Create();
    try
      if LUninstall.LoadFromFile(LUninstallFile) then
      begin
        //remove searchpathes first, because it's less criticall
        //in case something goes wrong with uninstalling packages or deleting files, it's simpler to remove
        //them manually from disk, than removing individual searchpathes manually from IDE
        FProgress.SetTasks(['Removing Pathes', 'Remove Packages', 'Delete Files']);
        FProgress.SetTaskProgress('SearchPath', 0, 1);
        Result :=  RemovePathes(LUninstall.SearchPathes, tpSearchPath);
        FProgress.SetTaskProgress('Browsing Path', 1, 1);
        Result := Result and RemovePathes(LUninstall.BrowsingPathes, tpBrowsingPath);
        FProgress.NextTask();
        Result := Result and ProcessPackages(LUninstall.Packages);
        FProgress.NextTask();
        Result := Result and DeleteRawFiles(LUninstall.RawFiles);
        Result := Result and DeleteFiles(ADirectory);
        FProgress.Completed();
      end
      else
      begin
        DoMessage(mtError, 'uninstallation file is corrupt');
      end;
    finally
      LUninstall.Free;
    end;
  end
  else
  begin
    DoMessage(mtError, 'No uninstallation file');
  end;
end;

function TDNUninstaller.UninstallPackage(const ABPLFile: string): Boolean;
begin
  Result := True;
end;

end.
