function RunRuntimeSync(Mode, LogName: String): Boolean;
var
  PowerShellPath, Parameters: String;
  ExitCode: Integer;
begin
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  if IsWin64 then
    PowerShellPath := ExpandConstant('{sysnative}\WindowsPowerShell\v1.0\powershell.exe');
  Parameters := '-NoProfile -ExecutionPolicy Bypass -File ' +
    AddQuotes(ExpandConstant('{app}\runtime_sync.ps1')) + ' -Mode ' + Mode +
    ' -InstallDir ' + AddQuotes(ExpandConstant('{app}')) + ' -LogPath ' +
    AddQuotes(ExpandConstant('{app}\OptiScaler\RuntimeSync\') + LogName);
  Result := Exec(PowerShellPath, Parameters, '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
  if Result then Result := ExitCode = 0;
  if not Result then Log('Runtime sync failed; inspect OptiScaler\RuntimeSync\' + LogName);
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  if FileExists(ExpandConstant('{app}\runtime_sync.ps1')) then
  begin
    Result := RunRuntimeSync('Restore', 'last-restore.log');
    if not Result then
      MsgBox('Close the game and run Restore again before uninstalling. See OptiScaler\RuntimeSync\last-restore.log.', mbError, MB_OK);
  end;
end;
