#Requires AutoHotkey v2.0+
#SingleInstance Force
Persistent(true)
SetWorkingDir(A_InitialWorkingDir)
SetTitleMatchMode(2) ; Mode 2: Match anywhere in window title

; ==============================================================================
; AUTO-ELEVATE KE ADMINISTRATOR (Wajib agar tembus ke VMware & UIPI Windows)
; ==============================================================================
if !A_IsAdmin {
    try {
        if A_IsCompiled
            Run '*RunAs "' . A_ScriptFullPath . '" /restart'
        else
            Run '*RunAs "' . A_AhkPath . '" /restart "' . A_ScriptFullPath . '"'
    }
    ExitApp()
}

; Bersihkan instance script lama (.ahk maupun .exe) yang masih berjalan di background
CloseOldInstances()
CloseOldInstances() {
    myPid := ProcessExist()
    for procName in ["AutoHotkey64.exe", "AutoHotkey32.exe", "cheat_assistant.exe", "cheat_assistant_old.exe"] {
        try {
            for proc in ComObjGet("winmgmts:").ExecQuery("Select ProcessId from Win32_Process where Name='" . procName . "'") {
                if (proc.ProcessId != myPid) {
                    try ProcessClose(proc.ProcessId)
                }
            }
        }
    }
    try FileDelete(A_ScriptDir . "\cheat_assistant_old.exe")
}

; Pasang keyboard & mouse hook permanen dengan prioritas tinggi
InstallKeybdHook(true, false)
InstallMouseHook(true, false)
A_HotkeyModifierTimeout := 100
CoordMode("Mouse", "Screen")

; Matikan fitur Aero Snap Windows (kotak abu-abu maximize saat geser ke pinggir layar)
; SPI_SETWINARRANGING = 0x0083
DllCall("SystemParametersInfo", "uint", 0x0083, "uint", 0, "ptr", 0, "uint", 0)
OnExit(CleanupOnExit)

CleanupOnExit(*) {
    SetCrosshairCursor(false)
    ; Kembalikan Aero Snap Windows ke normal saat aplikasi ditutup
    DllCall("SystemParametersInfo", "uint", 0x0083, "uint", 1, "ptr", 0, "uint", 0)
}

; ==============================================================================
; AHK2EXE COMPILER DIRECTIVES
; ==============================================================================
;@Ahk2Exe-SetName Cheat & Window Assistant
;@Ahk2Exe-SetDescription Assistant Lock Input & Window Manager (Gemini + VMware)
;@Ahk2Exe-SetVersion 1.0.0.0
;@Ahk2Exe-SetCopyright Copyright (c) 2026

; ==============================================================================
; GLOBAL STATE & CONFIGURATION
; ==============================================================================
global isLocked        := false
global isShiftDown     := false
global isSelectingOcr  := false
global isAutoDetecting := false
global lastLockTime    := 0
global lastGuiTime     := 0
global lastOcrTime     := 0
global lastAutoOcrTime := 0

; User Settings (persisted to config.ini)
global iniFile         := A_ScriptDir . "\config.ini"
global geminiOpacity   := 190  ; Default ~75% opacity (Range 50 - 255)
global optPinVMware    := false
global optOpenGemini   := true
global optAutoEnterOcr := true

; GUI & Hook Handles
global mainGui         := unset
global sliderGemini    := unset
global txtOpacityVal   := unset
global chkPinVMware    := unset
global chkOpenGemini   := unset
global chkAutoEnterOcr := unset
global txtLockStatus   := unset
global lockHook        := unset
global ocrBoxGui       := unset
global ocrOverlayGui   := unset

; ==============================================================================
; INITIALIZATION
; ==============================================================================
LoadConfig()
InitLockHook()
SetupTrayMenu()
SetTimer(CheckVMwareTimer, 3000)      ; Auto-check VMware every 3 seconds if enabled
SetTimer(KeepGeminiPinnedTimer, 250)  ; Pin Gemini agresif agar tetap tampil di atas VMware Fullscreen & SEB
SetTimer(VMwareWatchdogTimer, 60)     ; Jaga hook selalu di atas VMware & deteksi tombol fisik saat di dalam OS VMware

; ==============================================================================
; HOTKEYS UTAMA
; Shift + F : Toggle Lock ON / OFF
; Shift + A : Buka GUI Pengaturan / Control Panel
; Shift + Z : Manual Drag Select (OCR) -> Tempel ke Gemini
; Shift + X : Auto-Detect Soal (OpenCV) -> Tempel ke Gemini
; ==============================================================================
; Hotkeys khusus saat Lock AKTIF (Menjamin Shift+F, Shift+A, Shift+Z, Shift+X tidak akan pernah mati)
#HotIf isLocked
*f:: {
    if (GetKeyState("Shift", "P") || GetKeyState("Shift"))
        ToggleLock()
}
*a:: {
    if (GetKeyState("Shift", "P") || GetKeyState("Shift"))
        ShowControlPanel()
}
*z:: {
    if (GetKeyState("Shift", "P") || GetKeyState("Shift"))
        StartOcrSelection()
}
*x:: {
    if (GetKeyState("Shift", "P") || GetKeyState("Shift"))
        StartAutoDetectOcr()
}
F12::ToggleLock() ; Tombol darurat (Fail-safe) untuk membuka kunci
#HotIf

; Hotkeys normal saat Lock NONAKTIF
*+f::ToggleLock()
*+a::ShowControlPanel()
*+z::StartOcrSelection()
*+x::StartAutoDetectOcr()

; ==============================================================================
; TOGGLE LOCK FUNCTIONALITY (Shift + F)
; ==============================================================================
ToggleLock(*) {
    global isLocked, lastLockTime, lockHook
    
    ; Debounce: Prevent rapid accidental double-firing
    now := A_TickCount
    if (now - lastLockTime < 350)
        return
    lastLockTime := now
    
    isLocked := !isLocked
    
    if (isLocked) {
        ; -----------------------------
        ; LOCK AKTIF
        ; -----------------------------
        lockHook.Start()
        SoundBeep(1200, 150)
        TrayTip("Klik mouse & ketikan keyboard dinonaktifkan.`nTekan Shift + F (atau F12) untuk membuka kembali.", "Lock Input: AKTIF", 1)
    } else {
        ; -----------------------------
        ; LOCK NONAKTIF
        ; -----------------------------
        lockHook.Stop()
        SoundBeep(700, 150)
        TrayTip("Fungsi mouse dan keyboard telah kembali normal.", "Lock Input: NONAKTIF", 1)
    }
    
    ; Otomatis sembunyikan TrayTip setelah 2.5 detik
    SetTimer(() => TrayTip(), -2500)
    
    ; Sinkronisasi status di GUI jika GUI sedang terbuka
    UpdateLockStatusGui()
}

; Inisialisasi Hook Keyboard untuk memblokir input saat Lock AKTIF
InitLockHook() {
    global lockHook
    lockHook := InputHook("I")
    lockHook.KeyOpt("{All}", "+S") ; Suppress seluruh input keyboard
    lockHook.KeyOpt("{LShift}{RShift}{F12}fazx", "-S +N") ; JANGAN blokir Shift, F, A, Z, X, F12 dan aktifkan notifikasi
    lockHook.OnKeyDown := HandleLockedKeyDown
    lockHook.OnKeyUp   := HandleLockedKeyUp
}

; Callback saat tombol ditekan ketika Lock AKTIF
HandleLockedKeyDown(ih, vk, sc) {
    global isShiftDown, isSelectingOcr
    
    ; LShift (0xA0), RShift (0xA1), VK_SHIFT (0x10)
    if (vk == 0x10 || vk == 0xA0 || vk == 0xA1) {
        isShiftDown := true
        return
    }
    
    ; Tombol Darurat Fail-safe: F12 (VK 0x7B) -> Buka Kunci
    if (vk == 0x7B) {
        ToggleLock()
        return
    }
    
    ; Evaluasi kondisi Shift fisik atau logical
    isShiftPressed := isShiftDown || GetKeyState("Shift", "P")
    
    ; Kombinasi KECUALI 1: Shift + F (VK 0x46) -> Toggle Lock
    if (isShiftPressed && vk == 0x46) {
        ToggleLock()
        return
    }
    
    ; Kombinasi KECUALI 2: Shift + A (VK 0x41) -> Buka GUI Pengaturan
    if (isShiftPressed && vk == 0x41) {
        ShowControlPanel()
        return
    }
    
    ; Kombinasi KECUALI 3: Shift + Z (VK 0x5A) -> Manual Drag OCR Teks Layar ke Gemini
    if (isShiftPressed && vk == 0x5A) {
        StartOcrSelection()
        return
    }
    
    ; Kombinasi KECUALI 4: Shift + X (VK 0x58) -> Auto-Detect Soal (OpenCV) ke Gemini
    if (isShiftPressed && vk == 0x58) {
        StartAutoDetectOcr()
        return
    }
    
    ; Tombol Esc untuk batal OCR atau menutup GUI
    if (vk == 0x1B) {
        if (isSelectingOcr) {
            CancelOcrSelection()
            return
        }
        if (IsMouseOverGui() && IsSet(mainGui) && mainGui is Gui) {
            mainGui.Hide()
            return
        }
    }
}

; Callback saat tombol dilepas ketika Lock AKTIF
HandleLockedKeyUp(ih, vk, sc) {
    global isShiftDown
    if (vk == 0x10 || vk == 0xA0 || vk == 0xA1) {
        isShiftDown := false
    }
}

; Fungsi helper untuk mendeteksi apakah kursor berada di atas GUI
IsMouseOverGui() {
    global mainGui
    if (!IsSet(mainGui) || !(mainGui is Gui))
        return false
    try {
        MouseGetPos(,, &mHwnd)
        return (mHwnd == mainGui.Hwnd)
    }
    return false
}

; ==============================================================================
; ANTI-SNAP DRAG UNTUK WINDOW GEMINI
; Mencegah munculnya kotak abu-abu Aero Snap / Snap Layouts saat menggeser Gemini ke pinggir layar
; ==============================================================================
IsMouseOverGeminiTitleBar() {
    MouseGetPos(&mx, &my, &mHwnd)
    geminiHwnd := WinExist("Gemini ahk_exe chrome.exe")
    if (!geminiHwnd || mHwnd != geminiHwnd)
        return false
    try {
        if (WinGetMinMax(geminiHwnd) == 1)
            return false
        WinGetPos(&gx, &gy, &gw, &gh, geminiHwnd)
        ; Area title bar atas Gemini (di luar border resize dan tombol minimize/maximize/close di kanan)
        if (mx >= gx + 8 && mx <= gx + gw - 140 && my >= gy + 6 && my <= gy + 38)
            return true
    }
    return false
}

DragGeminiWindow(*) {
    geminiHwnd := WinExist("Gemini ahk_exe chrome.exe")
    if (!geminiHwnd)
        return
    try {
        MouseGetPos(&startMx, &startMy)
        WinGetPos(&startWx, &startWy,,, geminiHwnd)
        WinActivate(geminiHwnd)
        while GetKeyState("LButton", "P") {
            MouseGetPos(&curMx, &curMy)
            newX := startWx + (curMx - startMx)
            newY := startWy + (curMy - startMy)
            ; SWP_NOSIZE(0x1) | SWP_NOZORDER(0x4) | SWP_NOACTIVATE(0x10) = 0x15
            DllCall("SetWindowPos", "ptr", geminiHwnd, "ptr", 0, "int", newX, "int", newY, "int", 0, "int", 0, "uint", 0x0015)
            Sleep(10)
        }
    }
}

#HotIf !isLocked && !isSelectingOcr && IsMouseOverGeminiTitleBar()
LButton::DragGeminiWindow()
#HotIf

; ==============================================================================
; OCR SELECTION MOUSE HOOK (Saat Mode Blok Teks Shift + Z Aktif)
; ==============================================================================
#HotIf isSelectingOcr
*LButton::DoOcrDrag()
*RButton::CancelOcrSelection()
*Escape::CancelOcrSelection()
#HotIf

; ==============================================================================
; MOUSE CLICK BLOCKING (Saat Lock AKTIF)
; Kursor mouse TETAP BISA DIGERAKKAN BEBAS di layar.
; Semua klik mouse diblokir KECUALI saat berinteraksi di atas Control Panel GUI.
; ==============================================================================
#HotIf isLocked && !IsMouseOverGui() && !isSelectingOcr
*LButton::return
*RButton::return
*MButton::return
*XButton1::return
*XButton2::return
*WheelUp::return
*WheelDown::return
*WheelLeft::return
*WheelRight::return
#HotIf

; ==============================================================================
; GUI PENGATURAN / CONTROL PANEL (Shift + A)
; ==============================================================================
ShowControlPanel(*) {
    global mainGui, lastGuiTime
    
    now := A_TickCount
    if (now - lastGuiTime < 350)
        return
    lastGuiTime := now
    
    if (!IsSet(mainGui) || !(mainGui is Gui)) {
        CreateGUI()
    }
    
    UpdateLockStatusGui()
    mainGui.Show("Center")
    ForceActivateWindow(mainGui.Hwnd)
}

CreateGUI() {
    global mainGui, sliderGemini, txtOpacityVal, chkPinVMware, chkOpenGemini, chkAutoEnterOcr, txtLockStatus
    global geminiOpacity, optPinVMware, optOpenGemini, optAutoEnterOcr
    
    ; Buat window GUI dengan style AlwaysOnTop
    mainGui := Gui("+AlwaysOnTop +ToolWindow -DPIScale", "Control Panel - Assistant")
    mainGui.SetFont("s9", "Segoe UI")
    mainGui.BackColor := "F7F8FA"
    
    ; -------------------------------------------------------------
    ; GROUP 1: GEMINI & DUAL OCR STEALTH
    ; -------------------------------------------------------------
    mainGui.SetFont("s10 Bold", "Segoe UI")
    mainGui.Add("GroupBox", "x15 y10 w365 h162", " Google Gemini & Dual OCR (Shift+Z / Shift+X) ")
    mainGui.SetFont("s9 Norm", "Segoe UI")
    
    chkOpenGemini := mainGui.Add("Checkbox", "x30 y35 Checked" . (optOpenGemini ? 1 : 0), "Buka Gemini Transparan (Chrome App Mode)")
    chkAutoEnterOcr := mainGui.Add("Checkbox", "x30 y60 Checked" . (optAutoEnterOcr ? 1 : 0), "Otomatis Tekan Enter setelah Tempel Teks (Shift+Z/X)")
    
    mainGui.Add("Text", "x30 y90", "Tingkat Transparansi:")
    pct := Round((geminiOpacity / 255) * 100)
    txtOpacityVal := mainGui.Add("Text", "x185 y90 w175 Right c0055AA", geminiOpacity . " / 255 (" . pct . "%)")
    txtOpacityVal.SetFont("Bold")
    
    sliderGemini := mainGui.Add("Slider", "x25 y114 w345 Range50-255 ToolTipBottom TickInterval25", geminiOpacity)
    sliderGemini.OnEvent("Change", OnSliderChange)
    
    ; -------------------------------------------------------------
    ; GROUP 2: VMWARE
    ; -------------------------------------------------------------
    mainGui.SetFont("s10 Bold", "Segoe UI")
    mainGui.Add("GroupBox", "x15 y180 w365 h80", " VMware Workstation ")
    mainGui.SetFont("s9 Norm", "Segoe UI")
    
    chkPinVMware := mainGui.Add("Checkbox", "x30 y207 Checked" . (optPinVMware ? 1 : 0), "Pin VMware (Always on Top)")
    mainGui.Add("Text", "x48 y232 c666666", "Otomatis menjaga jendela 'ahk_exe vmware.exe' di depan")
    
    ; -------------------------------------------------------------
    ; GROUP 3: STATUS & HOTKEYS
    ; -------------------------------------------------------------
    mainGui.SetFont("s10 Bold", "Segoe UI")
    mainGui.Add("GroupBox", "x15 y268 w365 h125", " Status & Shortcut ")
    mainGui.SetFont("s9 Norm", "Segoe UI")
    
    txtLockStatus := mainGui.Add("Text", "x30 y292 w335 c228822", "Status Lock: NONAKTIF")
    txtLockStatus.SetFont("Bold")
    mainGui.Add("Text", "x30 y315 c555555", "• Shift + Z : Manual Drag Select (OCR) -> Tempel ke Gemini`n• Shift + X : Auto-Detect Soal (OpenCV) -> Tempel ke Gemini`n• Shift + F (atau F12) : Toggle Lock Mouse & Keyboard`n• Shift + A : Buka Control Panel ini")
    
    ; -------------------------------------------------------------
    ; TOMBOL AKSI
    ; -------------------------------------------------------------
    mainGui.SetFont("s9 Bold", "Segoe UI")
    btnApply := mainGui.Add("Button", "x15 y402 w240 h35 Default", "✔ Simpan & Terapkan")
    btnApply.OnEvent("Click", OnApplyClick)
    
    mainGui.SetFont("s9 Norm", "Segoe UI")
    btnClose := mainGui.Add("Button", "x265 y402 w115 h35", "Tutup")
    btnClose.OnEvent("Click", (*) => mainGui.Hide())
    
    mainGui.OnEvent("Close", (*) => mainGui.Hide())
    mainGui.OnEvent("Escape", (*) => mainGui.Hide())
}

; Realtime slider update
OnSliderChange(ctrl, *) {
    global geminiOpacity, txtOpacityVal
    geminiOpacity := ctrl.Value
    pct := Round((geminiOpacity / 255) * 100)
    txtOpacityVal.Value := geminiOpacity . " / 255 (" . pct . "%)"
    
    ; Update live jika Gemini sedang terbuka
    if (hwnd := WinExist("Gemini ahk_exe chrome.exe")) {
        try WinSetTransparent(geminiOpacity, hwnd)
    }
}

; Update visual status lock di GUI
UpdateLockStatusGui() {
    global txtLockStatus, isLocked
    if (!IsSet(txtLockStatus))
        return
        
    if (isLocked) {
        txtLockStatus.Value := "Status Lock: AKTIF (Terkunci)"
        txtLockStatus.SetFont("cCC0000") ; Merah
    } else {
        txtLockStatus.Value := "Status Lock: NONAKTIF (Normal)"
        txtLockStatus.SetFont("c228822") ; Hijau
    }
}

; Handler tombol "Simpan & Terapkan"
OnApplyClick(*) {
    global chkOpenGemini, chkPinVMware, chkAutoEnterOcr, sliderGemini
    global optOpenGemini, optPinVMware, optAutoEnterOcr, geminiOpacity
    
    ; Simpan nilai form ke variabel
    optOpenGemini   := chkOpenGemini.Value
    optPinVMware    := chkPinVMware.Value
    optAutoEnterOcr := chkAutoEnterOcr.Value
    geminiOpacity   := sliderGemini.Value
    
    ; Simpan ke file konfigurasi
    SaveConfig()
    
    ; Terapkan ke Gemini
    if (optOpenGemini) {
        ApplyGeminiSettings(geminiOpacity)
    }
    
    ; Terapkan ke VMware
    vmwareFound := ApplyVMwareSettings(optPinVMware)
    
    ; Feedback notifikasi
    msg := "Pengaturan berhasil diterapkan!"
    if (optPinVMware) {
        if (vmwareFound) {
            msg .= "`nVMware berhasil di-pin (Always on Top)."
        } else {
            msg .= "`nCatatan: Proses vmware.exe belum terdeteksi aktif."
        }
    }
    
    TrayTip(msg, "Cheat Assistant", 1)
    SetTimer(() => TrayTip(), -3000)
}

; ==============================================================================
; VMWARE WATCHDOG & UNGRAB HELPER
; Memastikan kursor & hotkey selalu keluar ke Windows Host meski sedang di dalam OS VMware
; ==============================================================================
VMwareWatchdogTimer() {
    global isSelectingOcr
    if WinActive("ahk_exe vmware.exe") || WinActive("ahk_exe vmware-vmx.exe") || WinActive("ahk_exe vmware-remotemks.exe") {
        ; Pasang ulang hook di urutan teratas rantai Windows agar tidak ditelan VMware
        InstallKeybdHook(true, true)
        InstallMouseHook(true, true)
        
        ; Deteksi level-hardware (GetAsyncKeyState) jika input sedang di-grab penuh oleh OS VMware
        if (DllCall("GetAsyncKeyState", "int", 0x10, "short") < 0) { ; Shift ditahan
            if (DllCall("GetAsyncKeyState", "int", 0x5A, "short") < 0) { ; Shift + Z
                StartOcrSelection()
            } else if (DllCall("GetAsyncKeyState", "int", 0x58, "short") < 0) { ; Shift + X
                StartAutoDetectOcr()
            } else if (DllCall("GetAsyncKeyState", "int", 0x41, "short") < 0) { ; Shift + A
                ShowControlPanel()
            } else if (DllCall("GetAsyncKeyState", "int", 0x46, "short") < 0) { ; Shift + F
                ToggleLock()
            }
        } else if (DllCall("GetAsyncKeyState", "int", 0x7B, "short") < 0) { ; F12
            ToggleLock()
        }
    }
}

ForceActivateWindow(hwnd) {
    if (!hwnd || !WinExist(hwnd))
        return
    try {
        ; 1. Jika sedang di dalam OS VMware, kirim sinyal ungrab Ctrl+Alt agar kursor keluar ke Windows Host
        if WinActive("ahk_exe vmware.exe") || WinActive("ahk_exe vmware-vmx.exe") || WinActive("ahk_exe vmware-remotemks.exe") {
            SendInput("{LCtrl down}{LAlt down}{LAlt up}{LCtrl up}")
            Sleep(35)
        }
        ; 2. Lepaskan kurungan kursor (ClipCursor) dari VMware
        DllCall("ClipCursor", "ptr", 0)
        
        ; 3. Paksa Windows memindahkan fokus dari VMware ke jendela Host kita
        fgHwnd := DllCall("GetForegroundWindow", "ptr")
        if (fgHwnd != hwnd) {
            fgThread := DllCall("GetWindowThreadProcessId", "ptr", fgHwnd, "ptr", 0, "uint")
            myThread := DllCall("GetCurrentThreadId", "uint")
            if (fgThread && fgThread != myThread) {
                DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 1)
                DllCall("BringWindowToTop", "ptr", hwnd)
                DllCall("SetForegroundWindow", "ptr", hwnd)
                DllCall("AttachThreadInput", "uint", myThread, "uint", fgThread, "int", 0)
            } else {
                DllCall("SetForegroundWindow", "ptr", hwnd)
            }
        }
        WinActivate(hwnd)
    }
}

; ==============================================================================
; STEALTH OCR SCREEN TEXT EXTRACTOR & AUTO-PASTE KE GEMINI (Shift + Z)
; Tanpa efek gelap (dimming) di layar! Otomatis mengeluarkan kursor dari OS VMware ke Windows.
; ==============================================================================
StartOcrSelection(*) {
    global isSelectingOcr, lastOcrTime, ocrOverlayGui
    
    now := A_TickCount
    if (now - lastOcrTime < 400)
        return
    lastOcrTime := now
    
    if (isSelectingOcr)
        return
        
    isSelectingOcr := true
    
    ; Buat lapisan kaca transparan tak terlihat (Alpha = 1/255, 99.6% bening tanpa gelap!)
    ; +E0x08000000 (WS_EX_NOACTIVATE) menjaga agar jendela ujian TIDAK kehilangan fokus (Zero Window Blur)
    if (!IsSet(ocrOverlayGui) || !(ocrOverlayGui is Gui)) {
        ocrOverlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000")
        ocrOverlayGui.BackColor := "000000"
    }
    
    ocrOverlayGui.Show("x0 y0 w" . A_ScreenWidth . " h" . A_ScreenHeight . " NoActivate")
    try WinSetTransparent(1, ocrOverlayGui.Hwnd)
    
    ; Jika sedang di dalam OS VMware, lepaskan grab kursor ke Windows Host
    if WinActive("ahk_exe vmware.exe") || WinActive("ahk_exe vmware-vmx.exe") || WinActive("ahk_exe vmware-remotemks.exe") {
        SendInput("{LCtrl down}{LAlt down}{LAlt up}{LCtrl up}")
        Sleep(30)
        DllCall("ClipCursor", "ptr", 0)
    }
    InstallKeybdHook(true, true)
    InstallMouseHook(true, true)
    SetCrosshairCursor(true)
}

CancelOcrSelection(*) {
    global isSelectingOcr, ocrOverlayGui
    isSelectingOcr := false
    SetCrosshairCursor(false)
    if (IsSet(ocrOverlayGui) && ocrOverlayGui is Gui) {
        try ocrOverlayGui.Hide()
    }
}

DoOcrDrag(*) {
    global isSelectingOcr, ocrOverlayGui
    if (!isSelectingOcr)
        return
        
    MouseGetPos(&startX, &startY)
    rx := startX, ry := startY, rw := 1, rh := 1
    
    ; Drag 100% siluman (stealth) tanpa kotak biru sama sekali!
    while GetKeyState("LButton", "P") {
        if (!isSelectingOcr)
            return
        MouseGetPos(&curX, &curY)
        rx := Min(startX, curX)
        ry := Min(startY, curY)
        rw := Max(1, Abs(curX - startX))
        rh := Max(1, Abs(curY - startY))
        Sleep(15)
    }
    
    if (IsSet(ocrOverlayGui) && ocrOverlayGui is Gui) {
        try ocrOverlayGui.Hide()
    }
    SetCrosshairCursor(false)
    isSelectingOcr := false
    
    ; Abaikan jika area terlalu kecil (tidak sengaja klik)
    if (rw < 12 || rh < 10)
        return
        
    try {
        extractedText := OcrScreenRect(rx, ry, rw, rh)
        PasteToGemini(extractedText)
    } catch as err {
        TrayTip("Gagal membaca teks: " . err.Message, "OCR Error", 2)
        SetTimer(() => TrayTip(), -2500)
    }
}

SetCrosshairCursor(enable) {
    if (enable) {
        ; Ganti kursor standar, I-Beam, dan Hand menjadi Crosshair (+)
        for id in [32512, 32513, 32549] {
            hCross := DllCall("CopyImage", "ptr", DllCall("LoadCursor", "ptr", 0, "ptr", 32515, "ptr"), "uint", 2, "int", 0, "int", 0, "uint", 0, "ptr")
            DllCall("SetSystemCursor", "ptr", hCross, "uint", id)
        }
    } else {
        ; SPI_SETCURSORS (0x0057) mengembalikan kursor bawaan Windows
        DllCall("SystemParametersInfo", "uint", 0x0057, "uint", 0, "ptr", 0, "uint", 0)
    }
}

; ==============================================================================
; AUTO-DETECT SOAL OPENCV & AUTO-PASTE KE GEMINI (Shift + X)
; Berjalan 100% silent via pythonw.exe di background tanpa interaksi mouse & tanpa window blur!
; ==============================================================================
StartAutoDetectOcr(*) {
    global isAutoDetecting, lastAutoOcrTime, mainGui
    
    now := A_TickCount
    if (now - lastAutoOcrTime < 600 || isAutoDetecting)
        return
    lastAutoOcrTime := now
    isAutoDetecting := true
    
    try {
        pyScript := A_ScriptDir . "\auto_detect_soal.py"
        resultFile := A_ScriptDir . "\ocr_auto_result.json"
        
        if !FileExist(pyScript) {
            ShowSubtleFallback("File auto_detect_soal.py tidak ditemukan. Gunakan Shift + Z (Manual).")
            return
        }
        
        try FileDelete(resultFile)
        
        ; Kumpulkan koordinat jendela Gemini & Control Panel agar diabaikan oleh OpenCV
        excludeArgs := ""
        if (gHwnd := WinExist("Gemini ahk_exe chrome.exe")) {
            try {
                if (WinGetMinMax(gHwnd) != -1) {
                    WinGetPos(&gx, &gy, &gw, &gh, gHwnd)
                    excludeArgs .= ' --exclude "' . gx . ',' . gy . ',' . gw . ',' . gh . '"'
                }
            }
        }
        if (IsSet(mainGui) && mainGui is Gui && WinExist(mainGui.Hwnd)) {
            try {
                WinGetPos(&mx, &my, &mw, &mh, mainGui.Hwnd)
                excludeArgs .= ' --exclude "' . mx . ',' . my . ',' . mw . ',' . mh . '"'
            }
        }
        
        pythonwExe := GetPythonwPath()
        cmd := '"' . pythonwExe . '" "' . pyScript . '"' . excludeArgs . ' --out "' . resultFile . '"'
        
        ; Eksekusi silent di background tanpa memunculkan jendela & tanpa mencuri fokus (Zero Window Blur)
        RunWait(cmd, A_ScriptDir, "Hide")
        
        if !FileExist(resultFile) {
            ShowSubtleFallback("Area soal tidak terdeteksi. Silakan gunakan Shift + Z (Manual Drag).")
            return
        }
        
        jsonText := FileRead(resultFile, "UTF-8")
        if !InStr(jsonText, '"status": "ok"') && !InStr(jsonText, '"status":"ok"') {
            ShowSubtleFallback("Area teks soal tidak ditemukan. Silakan gunakan Shift + Z (Manual Drag).")
            return
        }
        
        bx := ParseJsonInt(jsonText, "x")
        by := ParseJsonInt(jsonText, "y")
        bw := ParseJsonInt(jsonText, "w")
        bh := ParseJsonInt(jsonText, "h")
        
        if (bw < 20 || bh < 12) {
            ShowSubtleFallback("Area soal terlalu kecil/kosong. Silakan gunakan Shift + Z (Manual Drag).")
            return
        }
        
        extractedText := OcrScreenRect(bx, by, bw, bh)
        if (Trim(extractedText, " `t`r`n") == "") {
            ShowSubtleFallback("Teks soal gagal dibaca otomatis. Silakan gunakan Shift + Z (Manual Drag).")
            return
        }
        
        PasteToGemini(extractedText)
    } catch as err {
        ShowSubtleFallback("Auto-Detect gagal (" . err.Message . "). Gunakan Shift + Z.")
    } finally {
        isAutoDetecting := false
    }
}

GetPythonwPath() {
    candidates := [
        "C:\laragon\bin\python\python-3.10\pythonw.exe",
        EnvGet("LocalAppData") . "\Programs\Python\Python312\pythonw.exe",
        EnvGet("LocalAppData") . "\Programs\Python\Python311\pythonw.exe",
        EnvGet("LocalAppData") . "\Programs\Python\Python310\pythonw.exe",
        "C:\Python310\pythonw.exe"
    ]
    for p in candidates {
        if (p != "" && FileExist(p))
            return p
    }
    return "pythonw.exe"
}

ParseJsonInt(jsonStr, key) {
    if RegExMatch(jsonStr, '"' . key . '"\s*:\s*(-?\d+)', &m)
        return Integer(m[1])
    return 0
}

ShowSubtleFallback(msg) {
    ; Fallback notification halus tanpa mengambil fokus jendela ujian
    TrayTip(msg, "Auto-Detect (Shift+X) -> Gunakan Shift+Z", 2)
    SetTimer(() => TrayTip(), -3000)
}

PasteToGemini(text) {
    global isLocked, lockHook, geminiOpacity, optAutoEnterOcr
    
    cleanText := Trim(text, " `t`r`n")
    if (cleanText == "") {
        TrayTip("Tidak ada teks yang terbaca di area tersebut.", "OCR Kosong", 2)
        SetTimer(() => TrayTip(), -2000)
        return
    }
    
    ; 1. Sisipkan instruksi penutup otomatis di akhir string teks sesuai permintaan
    closingNote := "`r`n`r`n(Catatan: Jawab langsung abjad/opsi kunci intinya saja dalam 1 baris tanpa penjelasan)"
    finalPrompt := cleanText . closingNote
    
    ; 2. Salin gabungan teks ke Clipboard
    A_Clipboard := ""
    A_Clipboard := finalPrompt
    ClipWait(1)
    
    ; 3. Cari window Gemini Chrome App Mode (buka otomatis jika belum ada)
    geminiTitle := "Gemini ahk_exe chrome.exe"
    hwnd := WinExist(geminiTitle)
    if (!hwnd) {
        ApplyGeminiSettings(geminiOpacity)
        hwnd := WinExist(geminiTitle)
    }
    
    if (!hwnd) {
        TrayTip("Teks + instruksi disalin ke Clipboard (Window Gemini belum siap).", "OCR Berhasil", 1)
        SetTimer(() => TrayTip(), -2000)
        return
    }
    
    ; 4. Pause sementara lock agar simulasi keystroke ke Gemini berjalan mulus
    wasLocked := isLocked
    if (wasLocked) {
        isLocked := false
        lockHook.Stop()
    }
    
    try {
        if (WinGetMinMax(hwnd) == -1) {
            ; SW_SHOWNOACTIVATE (4) memulihkan jendela tanpa mencuri fokus dari window ujian
            DllCall("ShowWindow", "ptr", hwnd, "int", 4)
            Sleep(60)
        }
        
        WinGetPos(&gx, &gy, &gw, &gh, hwnd)
        ; Koordinat relatif di dalam window Gemini tepat pada kolom input "Minta Gemini"
        relX := Max(85, Min(gw - 65, gw // 2))
        relY := Max(50, gh - 82)
        
        ; 5. Kirim sinyal fokus internal ke Chromium tanpa menggeser fokus Windows (Zero Window Blur)
        try SendMessage(0x0006, 1, 0, , hwnd, , , , 300) ; WM_ACTIVATE (WA_ACTIVE = 1)
        try SendMessage(0x0007, 0, 0, , hwnd, , , , 300) ; WM_SETFOCUS
        try {
            if (renderHwnd := ControlGetHwnd("Chrome_RenderWidgetHostHWND1", hwnd)) {
                SendMessage(0x0007, 0, 0, , renderHwnd, , , , 300)
            }
        }
        
        ; 6. Klik kolom input secara silent di background ("NA") TANPA menggeser kursor mouse utama!
        ControlClick("x" . relX . " y" . relY, hwnd, , "Left", 1, "NA")
        Sleep(65)
        
        ; 7. Kirim simulasi keystroke Ctrl + V dan Enter langsung ke jendela Chrome App Mode
        try SendMessage(0x0006, 1, 0, , hwnd, , , , 300)
        try SendMessage(0x0007, 0, 0, , hwnd, , , , 300)
        SetKeyDelay(25, 25)
        ControlSend("{LCtrl down}v{LCtrl up}", , hwnd)
        
        if (optAutoEnterOcr) {
            Sleep(140)
            try SendMessage(0x0006, 1, 0, , hwnd, , , , 300)
            try SendMessage(0x0007, 0, 0, , hwnd, , , , 300)
            ControlSend("{Enter}", , hwnd)
        }
    } finally {
        if (wasLocked) {
            isLocked := true
            lockHook.Start()
        }
    }
}

; Engine OCR Native Windows (Windows.Media.Ocr) - Cepat (~100ms) & Tanpa Software Tambahan
OcrScreenRect(x, y, w, h) {
    if (w <= 0 || h <= 0)
        return ""
        
    ; Perbesar 2x jika area teks kecil agar akurasi baca huruf kecil maksimal
    scale := (w < 600 || h < 160) ? 2 : 1
    outW := w * scale
    outH := h * scale

    ; 1. Tangkap layar ke HBITMAP via GDI
    hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
    hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", outW, "int", outH, "ptr")
    obm := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")
    
    if (scale == 1) {
        DllCall("BitBlt", "ptr", hdcMem, "int", 0, "int", 0, "int", w, "int", h, "ptr", hdcScreen, "int", x, "int", y, "uint", 0x40CC0020)
    } else {
        DllCall("SetStretchBltMode", "ptr", hdcMem, "int", 4) ; HALFTONE
        DllCall("StretchBlt", "ptr", hdcMem, "int", 0, "int", 0, "int", outW, "int", outH, "ptr", hdcScreen, "int", x, "int", y, "int", w, "int", h, "uint", 0x40CC0020)
    }
    
    DllCall("SelectObject", "ptr", hdcMem, "ptr", obm, "ptr")
    DllCall("DeleteDC", "ptr", hdcMem)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)

    ; 2. Simpan HBITMAP ke InMemoryRandomAccessStream via GDI+
    pInsp := RoActivateInstance("Windows.Storage.Streams.InMemoryRandomAccessStream")
    pRAS := ComObjQuery(pInsp, "{905A0FE1-BC53-11DF-8C49-001E4FC686DA}")
    ObjRelease(pInsp)
    iidStream := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", "{0000000C-0000-0000-C000-000000000046}", "ptr", iidStream)
    pStream := 0
    DllCall("shcore\CreateStreamOverRandomAccessStream", "ptr", pRAS.Ptr, "ptr", iidStream, "ptr*", &pStream)

    DllCall("LoadLibrary", "str", "gdiplus")
    si := Buffer(24, 0), NumPut("uint", 1, si, 0)
    pToken := 0
    DllCall("gdiplus\GdiplusStartup", "ptr*", &pToken, "ptr", si, "ptr", 0)
    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", &pBitmap)
    DllCall("DeleteObject", "ptr", hbm)

    clsidBmp := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", "{557CF400-1A04-11D3-9A73-0000F81EF32E}", "ptr", clsidBmp)
    DllCall("gdiplus\GdipSaveImageToStream", "ptr", pBitmap, "ptr", pStream, "ptr", clsidBmp, "ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
    DllCall("gdiplus\GdiplusShutdown", "ptr", pToken)
    ObjRelease(pStream)

    ; Kembalikan posisi baca stream ke awal (Seek = index 11)
    ComCall(11, pRAS, "uint64", 0)

    ; 3. Decode dengan Windows.Graphics.Imaging.BitmapDecoder
    pDecoderStatics := RoGetActivationFactory("Windows.Graphics.Imaging.BitmapDecoder", "{438CCB26-BCEF-4E95-BAD6-23A822E58D01}")
    pAsyncDecoder := 0
    ComCall(14, pDecoderStatics, "ptr", pRAS.Ptr, "ptr*", &pAsyncDecoder)
    pDecoder := WaitForAsync(pAsyncDecoder)
    ObjRelease(pDecoderStatics)
    pRAS := ""

    pFrameSoft := ComObjQuery(pDecoder, "{FE287C9A-420C-4963-87AD-691436E08383}")
    ObjRelease(pDecoder)
    pAsyncSb := 0
    ComCall(6, pFrameSoft, "ptr*", &pAsyncSb)
    pSoftwareBitmap := WaitForAsync(pAsyncSb)
    pFrameSoft := ""

    ; 4. Jalankan Windows.Media.Ocr.OcrEngine
    pOcrStatics := RoGetActivationFactory("Windows.Media.Ocr.OcrEngine", "{5BFFA85A-3384-3540-9940-699120D428A8}")
    pOcrEngine := 0
    ComCall(10, pOcrStatics, "ptr*", &pOcrEngine) ; TryCreateFromUserProfileLanguages
    ObjRelease(pOcrStatics)

    pAsyncOcr := 0
    ComCall(6, pOcrEngine, "ptr", pSoftwareBitmap, "ptr*", &pAsyncOcr) ; RecognizeAsync
    pOcrResult := WaitForAsync(pAsyncOcr)
    ObjRelease(pOcrEngine)
    ObjRelease(pSoftwareBitmap)

    ; 5. Ambil semua baris teks hasil OCR
    pLines := 0
    ComCall(6, pOcrResult, "ptr*", &pLines)
    ObjRelease(pOcrResult)

    count := 0
    ComCall(7, pLines, "uint*", &count)
    resultText := ""
    Loop count {
        pLine := 0
        ComCall(6, pLines, "uint", A_Index - 1, "ptr*", &pLine)
        hstr := 0
        ComCall(7, pLine, "ptr*", &hstr)
        buf := DllCall("combase\WindowsGetStringRawBuffer", "ptr", hstr, "uint*", &len := 0, "ptr")
        lineStr := StrGet(buf, len, "UTF-16")
        DllCall("combase\WindowsDeleteString", "ptr", hstr)
        ObjRelease(pLine)
        resultText .= (A_Index > 1 ? "`r`n" : "") . lineStr
    }
    ObjRelease(pLines)
    return resultText
}

RoActivateInstance(activatableClassId) {
    hstr := 0
    DllCall("combase\WindowsCreateString", "wstr", activatableClassId, "uint", StrLen(activatableClassId), "ptr*", &hstr)
    pInstance := 0
    DllCall("combase\RoActivateInstance", "ptr", hstr, "ptr*", &pInstance)
    DllCall("combase\WindowsDeleteString", "ptr", hstr)
    return pInstance
}

RoGetActivationFactory(activatableClassId, iid) {
    hstr := 0
    DllCall("combase\WindowsCreateString", "wstr", activatableClassId, "uint", StrLen(activatableClassId), "ptr*", &hstr)
    guid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", iid, "ptr", guid)
    pFactory := 0
    DllCall("combase\RoGetActivationFactory", "ptr", hstr, "ptr", guid, "ptr*", &pFactory)
    DllCall("combase\WindowsDeleteString", "ptr", hstr)
    return pFactory
}

WaitForAsync(pAsync) {
    pAsyncInfo := ComObjQuery(pAsync, "{00000036-0000-0000-C000-000000000046}")
    Loop 300 {
        status := 0
        ComCall(7, pAsyncInfo, "uint*", &status)
        if (status != 0)
            break
        Sleep(10)
    }
    pAsyncInfo := ""
    pResult := 0
    ComCall(8, pAsync, "ptr*", &pResult)
    ObjRelease(pAsync)
    return pResult
}

; ==============================================================================
; PENANGANAN WINDOW GEMINI (Chrome App Mode)
; ==============================================================================
ApplyGeminiSettings(opacity) {
    geminiTitle := "Gemini ahk_exe chrome.exe"
    hwnd := WinExist(geminiTitle)
    
    if (!hwnd) {
        chromeExe := GetChromePath()
        try {
            Run('"' . chromeExe . '" --app=https://gemini.google.com')
        } catch as err {
            MsgBox("Gagal membuka Google Chrome:`n" . err.Message, "Error", "Icon!")
            return
        }
        
        ; Tunggu window Gemini muncul (maksimal 6 detik)
        hwnd := WinWait(geminiTitle,, 6)
        
        ; Fallback jika judul web belum langsung berubah jadi "Gemini"
        if (!hwnd) {
            hwnd := WinExist("ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe")
        }
    }
    
    if (hwnd) {
        Sleep(250)
        try {
            WinSetAlwaysOnTop(1, hwnd)
            WinSetTransparent(opacity, hwnd)
        }
        
        ; Pastikan AlwaysOnTop dan transparansi tetap aktif setelah loading selesai
        SetTimer(() => EnsureGeminiStyle(opacity), -1500)
    }
}

EnsureGeminiStyle(opacity) {
    if (hwnd := WinExist("Gemini ahk_exe chrome.exe")) {
        try {
            WinSetAlwaysOnTop(1, hwnd)
            WinSetTransparent(opacity, hwnd)
        }
    }
}

; Timer agresif menjaga Gemini selalu di atas (bahkan saat VMware Full Screen & SEB aktif)
KeepGeminiPinnedTimer() {
    global optOpenGemini, geminiOpacity
    if (!optOpenGemini)
        return
    
    static geminiTitle := "Gemini ahk_exe chrome.exe"
    if (hwnd := WinExist(geminiTitle)) {
        try {
            ; 1. Pastikan style WS_EX_TOPMOST (0x8) aktif
            exStyle := WinGetExStyle(hwnd)
            if !(exStyle & 0x8) {
                WinSetAlwaysOnTop(1, hwnd)
            }
            
            ; 2. Tarik paksa ke posisi teratas Z-Order (di atas VMware Full Screen & SEB)
            ; HWND_TOPMOST = -1
            ; SWP_NOSIZE(0x1) | SWP_NOMOVE(0x2) | SWP_NOACTIVATE(0x10) | SWP_SHOWWINDOW(0x40) = 0x53
            DllCall("SetWindowPos", "ptr", hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x53)
        }
    }
}

; Mencari path file chrome.exe di registry dan folder instalasi umum
GetChromePath() {
    regKeys := [
        "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe",
        "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe"
    ]
    for key in regKeys {
        try {
            path := RegRead(key)
            if (path != "" && FileExist(path))
                return path
        }
    }
    
    stdPaths := [
        A_ProgramFiles . "\Google\Chrome\Application\chrome.exe",
        EnvGet("ProgramFiles(x86)") . "\Google\Chrome\Application\chrome.exe",
        EnvGet("LocalAppData") . "\Google\Chrome\Application\chrome.exe"
    ]
    for p in stdPaths {
        if (p != "" && FileExist(p))
            return p
    }
    
    return "chrome.exe" ; Fallback sistem
}

; ==============================================================================
; PENANGANAN WINDOW VMWARE WORKSTATION
; ==============================================================================
ApplyVMwareSettings(pinState) {
    vmList := WinGetList("ahk_exe vmware.exe")
    if (vmList.Length == 0)
        return false
    
    for hwnd in vmList {
        try {
            WinSetAlwaysOnTop(pinState ? 1 : 0, hwnd)
        }
    }
    return true
}

; Timer otomatis menjaga VMware tetap AlwaysOnTop jika opsi diaktifkan
CheckVMwareTimer() {
    global optPinVMware
    if (optPinVMware && ProcessExist("vmware.exe")) {
        ApplyVMwareSettings(true)
    }
}

; ==============================================================================
; KONFIGURASI PERSISTEN (INI FILE)
; ==============================================================================
LoadConfig() {
    global geminiOpacity, optPinVMware, optOpenGemini, optAutoEnterOcr, iniFile
    try {
        geminiOpacity := Integer(IniRead(iniFile, "Settings", "GeminiOpacity", "190"))
        if (geminiOpacity < 50)
            geminiOpacity := 50
        if (geminiOpacity > 255)
            geminiOpacity := 255
            
        optPinVMware    := (IniRead(iniFile, "Settings", "PinVMware", "0") = "1")
        optOpenGemini   := (IniRead(iniFile, "Settings", "OpenGemini", "1") = "1")
        optAutoEnterOcr := (IniRead(iniFile, "Settings", "AutoEnterOcr", "1") = "1")
    } catch {
        geminiOpacity   := 190
        optPinVMware    := false
        optOpenGemini   := true
        optAutoEnterOcr := true
    }
}

SaveConfig() {
    global geminiOpacity, optPinVMware, optOpenGemini, optAutoEnterOcr, iniFile
    try {
        IniWrite(String(geminiOpacity), iniFile, "Settings", "GeminiOpacity")
        IniWrite(optPinVMware ? "1" : "0", iniFile, "Settings", "PinVMware")
        IniWrite(optOpenGemini ? "1" : "0", iniFile, "Settings", "OpenGemini")
        IniWrite(optAutoEnterOcr ? "1" : "0", iniFile, "Settings", "AutoEnterOcr")
    }
}

; ==============================================================================
; SYSTEM TRAY MENU
; ==============================================================================
SetupTrayMenu() {
    A_IconTip := "Cheat & Window Assistant`nShift+Z: Manual OCR | Shift+X: Auto OCR | Shift+A: Menu | Shift+F: Lock"
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Manual Drag OCR ke Gemini (Shift+Z)", (*) => StartOcrSelection())
    A_TrayMenu.Add("Auto-Detect Soal OpenCV ke Gemini (Shift+X)", (*) => StartAutoDetectOcr())
    A_TrayMenu.Add("Buka Control Panel (Shift+A)", (*) => ShowControlPanel())
    A_TrayMenu.Add("Toggle Lock (Shift+F)", (*) => ToggleLock())
    A_TrayMenu.Add() ; Separator
    A_TrayMenu.Add("Keluar", (*) => ExitApp())
    A_TrayMenu.Default := "Buka Control Panel (Shift+A)"
    A_TrayMenu.ClickCount := 2
}

