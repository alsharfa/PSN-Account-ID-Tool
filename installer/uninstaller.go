//go:build windows

package main

import (
    "os"
    "os/exec"
    "path/filepath"
    "syscall"
    "unsafe"
)

var (
    user32          = syscall.NewLazyDLL("user32.dll")
    procMessageBoxW = user32.NewProc("MessageBoxW")
)

func utf16Ptr(s string) *uint16 {
    p, _ := syscall.UTF16PtrFromString(s)
    return p
}

func messageBox(title, text string, flags uintptr) uintptr {
    r, _, _ := procMessageBoxW.Call(0, uintptr(unsafe.Pointer(utf16Ptr(text))), uintptr(unsafe.Pointer(utf16Ptr(title))), flags)
    return r
}

func main() {
    const MB_OKCANCEL = 0x00000001
    const MB_ICONQUESTION = 0x00000020
    const MB_ICONINFORMATION = 0x00000040
    const IDOK = 1

    if messageBox("PSN Account ID Tool", "Remove PSN Account ID Tool from this Windows account?", MB_OKCANCEL|MB_ICONQUESTION) != IDOK {
        return
    }

    exePath, err := os.Executable()
    if err != nil {
        return
    }
    installDir := filepath.Dir(exePath)

    appData := os.Getenv("APPDATA")
    userProfile := os.Getenv("USERPROFILE")
    if appData != "" {
        _ = os.Remove(filepath.Join(appData, "Microsoft", "Windows", "Start Menu", "Programs", "PSN Account ID Tool.lnk"))
    }
    if userProfile != "" {
        _ = os.Remove(filepath.Join(userProfile, "Desktop", "PSN Account ID Tool.lnk"))
    }

    _ = exec.Command("reg.exe", "delete", `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\PSNAccountIDTool`, "/f").Run()

    messageBox("PSN Account ID Tool", "The application will now be removed.", MB_ICONINFORMATION)

    cmd := `ping 127.0.0.1 -n 2 >nul & rmdir /s /q "` + installDir + `"`
    c := exec.Command("cmd.exe", "/C", cmd)
    c.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
    _ = c.Start()
}
