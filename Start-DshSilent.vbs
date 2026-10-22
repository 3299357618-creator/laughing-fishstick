Option Explicit
' Runs Start-DshSilent.ps1 with no console window.
' Used as the scheduled-task action so logon stays silent.
Dim fso, shell, baseDir, scriptPath, command

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
scriptPath = fso.BuildPath(baseDir, "Start-DshSilent.ps1")

If Not fso.FileExists(scriptPath) Then
    WScript.Quit 2
End If

command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptPath & """"
shell.Run command, 0, False
