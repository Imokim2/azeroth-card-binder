; Match the companion executable by name, including copies moved to another folder.
; electron-builder's default path-prefix check can mistake unrelated programs for the app.
; Never kill a process automatically: the companion exits itself for an update, and manual
; installs ask the player to quit it. This also keeps sync writes from being interrupted.
!macro customCheckAppRunning
  Push $R0
  Push $R1
  StrCpy $R1 0
  warcards_check_running:
    ${nsProcess::FindProcess} "${APP_EXECUTABLE_FILENAME}" $R0
    ${If} $R0 == 603
      Goto warcards_not_running
    ${EndIf}
    ${If} $R0 == 0
      ; Give the old companion up to ten seconds to finish exiting after launching setup.
      ${If} $R1 < 20
        Sleep 500
        IntOp $R1 $R1 + 1
        Goto warcards_check_running
      ${EndIf}
      IfSilent warcards_check_failed
      MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "World of Warcards is still running. Choose Quit from its tray menu, then click Retry. If you moved the app, close that copy too." IDRETRY warcards_check_running
      Goto warcards_check_failed
    ${EndIf}
    IfSilent warcards_check_failed
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Setup could not check whether World of Warcards is running (error $R0). Restart Windows and try again. No collection data has been removed." IDRETRY warcards_check_running
  warcards_check_failed:
    SetErrorLevel 2
    Quit
  warcards_not_running:
    Pop $R1
    Pop $R0
!macroend
