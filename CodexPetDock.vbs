Option Explicit

Dim shell, fileSystem, applicationRoot, scriptPath, powershellPath, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

applicationRoot = fileSystem.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fileSystem.BuildPath( _
  applicationRoot, _
  "src\Start-CodexPetQuota.ps1" _
)
powershellPath = shell.ExpandEnvironmentStrings( _
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" _
)

If Not fileSystem.FileExists(scriptPath) Then
  MsgBox _
    "Codex Pet Dock is incomplete. Please reinstall the application.", _
    vbCritical, _
    "Codex Pet Dock"
  WScript.Quit 2
End If

shell.CurrentDirectory = applicationRoot
command = _
  """" & powershellPath & """" & _
  " -NoProfile -NonInteractive -WindowStyle Hidden" & _
  " -ExecutionPolicy RemoteSigned -File " & _
  """" & scriptPath & """"
shell.Run command, 0, False

