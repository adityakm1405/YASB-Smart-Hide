#NoTrayIcon
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
#Warn

; ============================================================
; YASB Smart Touch Hide
;
; Hides YASB when the active window reaches/touches the bottom
; edge of the top YASB bar, even when the window is NOT maximized.
;
; Your YASB config uses:
;   position: top
;   height: 34
;   always_on_top: true
;   windows_app_bar: false
;
; Hotkeys:
;   F8 = enable/disable Smart Touch Hide
;   F9 = force YASB visible
;   Mouse at physical top edge of monitor = reveal YASB
; ============================================================

global BarHeight := 34
global TouchTolerance := 2
global CheckInterval := 80
global MouseRevealHeight := 3   ; Top 3 pixels of the physical monitor edge

global Yasbc := ""
global BarHidden := false
global SmartHideEnabled := true
global MouseRevealActive := false
global MouseOnYasbBar := false
global LastWindowState := -99
global LastWindowHwnd := 0
global LastAppHwnd := 0
global LastAppMonitor := 0
global LastYasbCommandTick := 0
global ReconcileInterval := 250

; ------------------------------------------------------------
; Find yasbc.exe
; ------------------------------------------------------------

localAppData := EnvGet("LOCALAPPDATA")

yasbcCandidates := [
    "C:\Program Files\YASB\yasbc.exe",
    "C:\Program Files (x86)\YASB\yasbc.exe",
    localAppData "\Programs\YASB\yasbc.exe",
    localAppData "\YASB\yasbc.exe"
]

for path in yasbcCandidates {
    if FileExist(path) {
        Yasbc := path
        break
    }
}

; If it isn't in the usual locations, ask Windows PATH.
if !Yasbc {
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec(A_ComSpec ' /c where yasbc.exe 2^>nul')
        result := Trim(exec.StdOut.Read())
        if result != "" {
            firstLine := StrSplit(result, "`n")[1]
            firstLine := StrReplace(firstLine, "`r", "")
            if FileExist(firstLine)
                Yasbc := firstLine
        }
    }
}

if !Yasbc {
    MsgBox(
        "Could not find yasbc.exe.`n`n" .
        "Expected location:`nC:\Program Files\YASB\yasbc.exe`n`n" .
        "If YASB is installed somewhere else, edit the paths in this script.",
        "YASB Smart Touch Hide"
    )
    ExitApp
}

; ------------------------------------------------------------
; Start monitoring
; ------------------------------------------------------------

CoordMode("Mouse", "Screen")

SetTimer(CheckActiveWindow, CheckInterval)

; Dedicated mouse watcher. This runs independently from the
; active-window detection, so hovering at the physical monitor
; edge does NOT require clicking or changing the active window.
SetTimer(CheckMouseAtMonitorTop, 10)

OnExit(ShowBarOnExit)

; F8 = temporarily enable/disable smart hiding.
F8::ToggleSmartHide()

; F9 = force YASB visible.
F9::ForceShowBar()

; ------------------------------------------------------------
; Dedicated mouse hover reveal
; ------------------------------------------------------------

CheckMouseAtMonitorTop() {
    global MouseRevealHeight, BarHidden, MouseRevealActive, MouseOnYasbBar, BarHeight, LastAppHwnd

    MouseGetPos(&mouseX, &mouseY)

    atTop := false
    monitorCount := MonitorGetCount()

    Loop monitorCount {
        try {
            MonitorGet(
                A_Index,
                &monLeft,
                &monTop,
                &monRight,
                &monBottom
            )

            ; Physical top edge of this monitor.
            if (
                mouseX >= monLeft &&
                mouseX < monRight &&
                mouseY >= monTop &&
                mouseY <= monTop + MouseRevealHeight
            ) {
                atTop := true
                break
            }
        } catch {
            continue
        }
    }

    ; --------------------------------------------------------
    ; Keep YASB "revealed" while the mouse is actually over the
    ; visible YASB bar.
    ;
    ; This is what allows:
    ;
    ;   top edge -> move onto YASB -> click clock/widget
    ;
    ; Without this, leaving the physical top edge immediately
    ; released MouseRevealActive and the touch-hide logic hid
    ; YASB before the user could click anything.
    ; --------------------------------------------------------
    onBar := false

    if !BarHidden {
        Loop monitorCount {
            try {
                MonitorGet(
                    A_Index,
                    &monLeft,
                    &monTop,
                    &monRight,
                    &monBottom
                )

                if (
                    mouseX >= monLeft &&
                    mouseX < monRight &&
                    mouseY >= monTop &&
                    mouseY <= monTop + BarHeight
                ) {
                    onBar := true
                    break
                }
            } catch {
                continue
            }
        }
    }

    MouseOnYasbBar := onBar

    if atTop || onBar {
        MouseRevealActive := true

        if BarHidden {
            ShowYasb()
            BarHidden := false
        }
    } else {
        MouseRevealActive := false

        ; ----------------------------------------------------
        ; The mouse has LEFT the YASB bar.
        ;
        ; If YASB was revealed only so the user could interact
        ; with it, do not wait for another application click.
        ; Immediately check the last real application underneath.
        ;
        ; If that app is maximized or still touching YASB,
        ; hide the bar now.
        ; ----------------------------------------------------
        if !BarHidden && LastAppHwnd {
            try {
                if WinExist("ahk_id " LastAppHwnd) {
                    appState := WinGetMinMax("ahk_id " LastAppHwnd)

                    if appState = 1 {
                        HideYasb()
                        BarHidden := true
                    } else if appState = 0 {
                        WinGetPos(
                            &appX,
                            &appY,
                            &appW,
                            &appH,
                            "ahk_id " LastAppHwnd
                        )

                        centerX := appX + (appW / 2)
                        centerY := appY + (appH / 2)

                        monitorIndex := 0

                        Loop monitorCount {
                            try {
                                MonitorGet(
                                    A_Index,
                                    &monLeft,
                                    &monTop,
                                    &monRight,
                                    &monBottom
                                )

                                if (
                                    centerX >= monLeft &&
                                    centerX < monRight &&
                                    centerY >= monTop &&
                                    centerY < monBottom
                                ) {
                                    monitorIndex := A_Index
                                    break
                                }
                            }
                        }

                        if !monitorIndex
                            monitorIndex := MonitorGetPrimary()

                        MonitorGet(
                            monitorIndex,
                            &monLeft,
                            &monTop,
                            &monRight,
                            &monBottom
                        )

                        barBottom := monTop + BarHeight

                        if appY <= barBottom + 2 {
                            HideYasb()
                            BarHidden := true
                        }
                    }
                }
            } catch {
                ; If the old application no longer exists, leave
                ; YASB visible until normal window processing handles it.
            }
        }
    }
}
; ------------------------------------------------------------
; Main detection
; ------------------------------------------------------------

CheckActiveWindow() {
    global LastAppMonitor
    global BarHeight, TouchTolerance
    global BarHidden, SmartHideEnabled
    global LastWindowHwnd, LastAppHwnd

    if !SmartHideEnabled
        return

    hwnd := WinExist("A")
    if !hwnd
        return

    ; --------------------------------------------------------
    ; Detect CLOSE of the last real application.
    ;
    ; If an unmaximized application was touching YASB, YASB may
    ; have been hidden. When that application is closed there is
    ; no new active-window event that represents the old window,
    ; so LastAppHwnd can otherwise remain a dead HWND and the bar
    ; stays hidden forever.
    ;
    ; Show YASB again when that tracked application disappears,
    ; unless another maximized application is still occupying the
    ; same monitor.
    ; --------------------------------------------------------
    if LastAppHwnd {
        try {
            if !WinExist("ahk_id " LastAppHwnd) {
                if LastAppMonitor {
                    if !HasMaximizedAppOnMonitor(LastAppMonitor) {
                        if BarHidden {
                            ShowYasb()
                            BarHidden := false
                        }
                    }
                } else {
                    if BarHidden {
                        ShowYasb()
                        BarHidden := false
                    }
                }

                LastAppHwnd := 0
                LastAppMonitor := 0
            }
        } catch {
            ; If the old HWND cannot be queried, treat it as closed.
            if BarHidden {
                ShowYasb()
                BarHidden := false
            }

            LastAppHwnd := 0
            LastAppMonitor := 0
        }
    }

    ; --------------------------------------------------------
    ; Detect MINIMIZE of the window we were monitoring.
    ;
    ; This must happen BEFORE LastWindowHwnd is replaced with
    ; the new active window. When the old app is minimized,
    ; Windows activates another window, so WinExist("A") points
    ; at the NEW window.
    ;
    ; We remember the previous HWND on every monitoring pass.
    ; If that exact HWND has become minimized, YASB must be
    ; shown because the minimized window can no longer touch it.
    ; --------------------------------------------------------
    if LastWindowHwnd && (LastWindowHwnd != hwnd) {
        try {
            if WinExist("ahk_id " LastWindowHwnd) {
                previousState := WinGetMinMax("ahk_id " LastWindowHwnd)

                if previousState = -1 {
                    if BarHidden {
                        ShowYasb()
                        BarHidden := false
                    }
                }
            }
        } catch {
            ; The previous window may already be gone.
        }
    }

    ; IMPORTANT: remember the current active window EVERY pass.
    LastWindowHwnd := hwnd

    try {
        processName := WinGetProcessName("ahk_id " hwnd)
        className := WinGetClass("ahk_id " hwnd)
    } catch {
        return
    }

    if IsIgnoredWindow(processName, className)
        return

    ; Remember the last real application separately from the
    ; active HWND. Clicking YASB can make YASB the active window,
    ; but we still need to know which application is underneath.
    LastAppHwnd := hwnd

    try {
        WinGetPos(&lastAppX, &lastAppY, &lastAppW, &lastAppH, "ahk_id " hwnd)

        if (lastAppW > 0 && lastAppH > 0) {
            lastAppCenterX := lastAppX + (lastAppW / 2)
            lastAppCenterY := lastAppY + (lastAppH / 2)
            LastAppMonitor := GetMonitorForPoint(lastAppCenterX, lastAppCenterY)
        }
    } catch {
        LastAppMonitor := 0
    }

    ; --------------------------------------------------------
    ; IMPORTANT:
    ; While the mouse is being held at the physical top edge,
    ; the user is explicitly asking to reveal YASB.
    ;
    ; Do NOT let the app-touch detector immediately hide it
    ; again. This prevents the hide/show/hide/show loop.
    ;
    ; As soon as the mouse leaves the top-edge zone,
    ; normal touch-hide behavior resumes.
    ; --------------------------------------------------------
    if MouseRevealActive || MouseOnYasbBar
        return

    ; --------------------------------------------------------
    ; If ANY normal application on this monitor is maximized,
    ; YASB must remain hidden even when another unmaximized
    ; application is currently in the foreground.
    ;
    ; Example:
    ;   maximized browser behind
    ;   unmaximized File Explorer in front
    ;
    ; The maximized browser still occupies the monitor's
    ; maximized work area, so keep YASB hidden.
    ; --------------------------------------------------------
    try {
        activeState := WinGetMinMax("ahk_id " hwnd)

        if activeState != -1 {
            WinGetPos(&activeX, &activeY, &activeW, &activeH, "ahk_id " hwnd)

            activeCenterX := activeX + (activeW / 2)
            activeCenterY := activeY + (activeH / 2)

            activeMonitor := GetMonitorForPoint(activeCenterX, activeCenterY)

            if HasMaximizedAppOnMonitor(activeMonitor) {
                if !BarHidden {
                    HideYasb()
                    BarHidden := true
                }
                return
            }
        }
    } catch {
        ; Fall through to the normal active-window logic.
    }

    ; Do not interfere with YASB's own maximized/fullscreen handling.
    try {
        windowState := WinGetMinMax("ahk_id " hwnd)

        ; Minimized.
        if windowState = -1
            return

        ; Maximized.
        if windowState = 1 {
            if !BarHidden {
                HideYasb()
                BarHidden := true
            }
            return
        }
    } catch {
        return
    }

    ; Get active window position.
    try {
        WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)
    } catch {
        return
    }

    if (winW <= 0 || winH <= 0)
        return

    ; Find the monitor containing the center of the active window.
    centerX := winX + (winW / 2)
    centerY := winY + (winH / 2)

    monitorIndex := 0
    monitorCount := MonitorGetCount()

    Loop monitorCount {
        try {
            MonitorGet(A_Index, &monLeft, &monTop, &monRight, &monBottom)

            if (centerX >= monLeft && centerX < monRight &&
                centerY >= monTop && centerY < monBottom) {
                monitorIndex := A_Index
                break
            }
        }
    }

    ; Fall back to the primary monitor.
    if !monitorIndex
        monitorIndex := MonitorGetPrimary()

    try {
        MonitorGet(monitorIndex, &monLeft, &monTop, &monRight, &monBottom)
    } catch {
        return
    }

    ; YASB is at the top of the monitor.
    barBottom := monTop + BarHeight

    ; --------------------------------------------------------
    ; The important part:
    ;
    ; Window begins below the bar:
    ;   winY > barBottom + tolerance
    ;   -> YASB remains visible.
    ;
    ; Window reaches/touches the bar:
    ;   winY <= barBottom + tolerance
    ;   -> YASB hides.
    ; --------------------------------------------------------

    touchingBar := (winY <= barBottom + TouchTolerance)

    if touchingBar {
        ; Windows/YASB can automatically show the bar when a
        ; window changes from maximized back to unmaximized.
        ;
        ; Do not rely only on our BarHidden variable. While the
        ; app is physically touching the YASB area, periodically
        ; re-assert the hidden state so the bar cannot remain
        ; visible after maximize -> unmaximize.
        ;
        ; We only send hide-bar every 250 ms at most.
        if (
            !BarHidden ||
            (A_TickCount - LastYasbCommandTick >= ReconcileInterval)
        ) {
            HideYasb()
            BarHidden := true
        }
    } else {
        if BarHidden {
            ShowYasb()
            BarHidden := false
        }
    }
}

; ------------------------------------------------------------
; Return the monitor containing a point.
; ------------------------------------------------------------

GetMonitorForPoint(x, y) {
    monitorCount := MonitorGetCount()

    Loop monitorCount {
        try {
            MonitorGet(A_Index, &monLeft, &monTop, &monRight, &monBottom)

            if (
                x >= monLeft && x < monRight &&
                y >= monTop && y < monBottom
            )
                return A_Index
        } catch {
            continue
        }
    }

    return MonitorGetPrimary()
}

; ------------------------------------------------------------
; Check whether a normal application window is maximized on
; the specified monitor.
;
; This intentionally uses the SAME IsIgnoredWindow() filter
; as the normal active-window logic, so Windows shell surfaces,
; YASB, Action Center, Notification Center, etc. are not treated
; as applications.
; ------------------------------------------------------------

HasMaximizedAppOnMonitor(monitorIndex) {
    windows := WinGetList()

    for candidateHwnd in windows {
        try {
            if !WinExist("ahk_id " candidateHwnd)
                continue

            ; Do not inspect our own YASB/AutoHotkey windows.
            processName := WinGetProcessName("ahk_id " candidateHwnd)
            className := WinGetClass("ahk_id " candidateHwnd)

            if IsIgnoredWindow(processName, className)
                continue

            ; Minimized windows cannot require the bar to be hidden.
            state := WinGetMinMax("ahk_id " candidateHwnd)

            if state != 1
                continue

            WinGetPos(
                &candidateX,
                &candidateY,
                &candidateW,
                &candidateH,
                "ahk_id " candidateHwnd
            )

            if candidateW <= 0 || candidateH <= 0
                continue

            centerX := candidateX + (candidateW / 2)
            centerY := candidateY + (candidateH / 2)

            candidateMonitor := GetMonitorForPoint(centerX, centerY)

            if candidateMonitor = monitorIndex
                return true
        } catch {
            continue
        }
    }

    return false
}

; ------------------------------------------------------------
; Windows that should not trigger the hide/show logic
; ------------------------------------------------------------

IsIgnoredWindow(processName, className) {
    processLower := StrLower(processName)
    classLower := StrLower(className)

    ; YASB / YASBC.
    if InStr(processLower, "yasb")
        return true

    ; AutoHotkey.
    if InStr(processLower, "autohotkey")
        return true

    ; Windows shell / desktop windows.
    ;
    ; IMPORTANT:
    ; Keep these exclusions exactly as in the previously working
    ; SHELL_FIX file. Do NOT broadly exclude ApplicationFrameHost
    ; or generic XAML windows, because normal applications such as
    ; Notepad must still reach the normal maximize/touch detection.
    ignoredClasses := [
        "Progman",
        "WorkerW",
        "SHELLDLL_DefView",
        "Shell_TrayWnd",
        "Shell_SecondaryTrayWnd",
        "SearchHost",
        "StartMenuExperienceHost",

        ; Windows 11 shell/XAML surfaces used by:
        ; Action Center / Quick Settings / Notification Center /
        ; calendar and other flyouts.
        "Windows.UI.Core.CoreWindow",
        "XamlExplorerHostIslandWindow",
        "TopLevelWindowForOverflowXamlIsland"
    ]

    ignoredProcesses := [
        "ShellExperienceHost.exe",
        "SearchHost.exe",
        "StartMenuExperienceHost.exe",
        "TextInputHost.exe"
    ]

    for ignoredProcess in ignoredProcesses {
        if (processLower = StrLower(ignoredProcess))
            return true
    }

    for ignored in ignoredClasses {
        if (classLower = StrLower(ignored))
            return true
    }

    ; --------------------------------------------------------
    ; Windows 11 newer Quick Settings / Action Center host.
    ;
    ; These are the ONLY additions from the later
    ; SHELLHOST_FIX. Everything else above is preserved from
    ; the user's previously working file.
    ; --------------------------------------------------------
    if processLower = "shellhost.exe"
        return true

    if classLower = "controlcenterwindow"
        return true

    return false
}

; ------------------------------------------------------------
; YASB CLI
; ------------------------------------------------------------

HideYasb() {
    global Yasbc, LastYasbCommandTick

    try {
        Run('"' Yasbc '" hide-bar', , "Hide")
        LastYasbCommandTick := A_TickCount
    }
}

ShowYasb() {
    global Yasbc, LastYasbCommandTick

    try {
        Run('"' Yasbc '" show-bar', , "Hide")
        LastYasbCommandTick := A_TickCount
    }
}

; ------------------------------------------------------------
; Hotkeys
; ------------------------------------------------------------

ToggleSmartHide() {
    global SmartHideEnabled, BarHidden

    SmartHideEnabled := !SmartHideEnabled

    if !SmartHideEnabled {
        if BarHidden {
            ShowYasb()
            BarHidden := false
        }

        TrayTip("YASB Smart Touch Hide", "Disabled", 1)
    } else {
        TrayTip("YASB Smart Touch Hide", "Enabled", 1)
    }
}

ForceShowBar() {
    global BarHidden

    ShowYasb()
    BarHidden := false
}

; ------------------------------------------------------------
; Never leave YASB hidden if this script is closed.
; ------------------------------------------------------------

ShowBarOnExit(*) {
    global BarHidden

    if BarHidden
        ShowYasb()
}
