' Launch start.ps1 with no console window.
'
' The watchdog scheduled task used to run powershell.exe directly, so Windows
' created a console window that flashed on the desktop every 15 minutes even
' with -WindowStyle Hidden. wscript.exe has no console of its own, and
' WshShell.Run with window style 0 hides the PowerShell host it starts.
'
' Called by the GrokLedgerWatchdog task as: wscript.exe //B run-hidden.vbs

Dim fso, sh, here
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
here = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & here & "\start.ps1""", 0, False
