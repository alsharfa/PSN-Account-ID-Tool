//go:build windows

package main

import (
    "embed"
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
    "syscall"
    "unsafe"
)

//go:embed PSNAccountIDTool.ps1 Launch.vbs README.txt PSNAccountIDTool_Uninstall.exe
var payload embed.FS

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

func writeEmbedded(name, dst string) error {
    data, err := payload.ReadFile(name)
    if err != nil {
        return err
    }
    return os.WriteFile(dst, data, 0644)
}

func psQuote(s string) string {
    return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}

func createShortcut(linkPath, installDir string) error {
    target := filepath.Join(os.Getenv("WINDIR"), "System32", "wscript.exe")
    launcher := filepath.Join(installDir, "Launch.vbs")
    iconPath := filepath.Join(os.Getenv("WINDIR"), "System32", "shell32.dll")
    script := "$ws=New-Object -ComObject WScript.Shell;" +
        "$s=$ws.CreateShortcut(" + psQuote(linkPath) + ");" +
        "$s.TargetPath=" + psQuote(target) + ";" +
        "$s.Arguments=" + psQuote(`"`+launcher+`"`) + ";" +
        "$s.WorkingDirectory=" + psQuote(installDir) + ";" +
        "$s.IconLocation=" + psQuote(iconPath+",14") + ";" +
        "$s.Description='Retrieve and encode PSN account IDs for Remote Play clients';" +
        "$s.Save()"

    cmd := exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script)
    cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
    return cmd.Run()
}

func regAdd(key, name, typ, value string) {
    args := []string{"add", key, "/v", name, "/t", typ, "/d", value, "/f"}
    cmd := exec.Command("reg.exe", args...)
    cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
    _ = cmd.Run()
}

func install() (string, error) {
    local := os.Getenv("LOCALAPPDATA")
    if local == "" {
        return "", fmt.Errorf("LOCALAPPDATA is unavailable")
    }
    installDir := filepath.Join(local, "PSN Account ID Tool")
    if err := os.MkdirAll(installDir, 0755); err != nil {
        return "", err
    }

    files := []string{"PSNAccountIDTool.ps1", "Launch.vbs", "README.txt", "PSNAccountIDTool_Uninstall.exe"}
    for _, name := range files {
        if err := writeEmbedded(name, filepath.Join(installDir, name)); err != nil {
            return "", fmt.Errorf("write %s: %w", name, err)
        }
    }

    appData := os.Getenv("APPDATA")
    if appData != "" {
        startMenu := filepath.Join(appData, "Microsoft", "Windows", "Start Menu", "Programs")
        _ = os.MkdirAll(startMenu, 0755)
        if err := createShortcut(filepath.Join(startMenu, "PSN Account ID Tool.lnk"), installDir); err != nil {
            return "", fmt.Errorf("create Start Menu shortcut: %w", err)
        }
    }

    userProfile := os.Getenv("USERPROFILE")
    if userProfile != "" {
        desktop := filepath.Join(userProfile, "Desktop")
        if stat, err := os.Stat(desktop); err == nil && stat.IsDir() {
            _ = createShortcut(filepath.Join(desktop, "PSN Account ID Tool.lnk"), installDir)
        }
    }

    key := `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\PSNAccountIDTool`
    uninstallExe := filepath.Join(installDir, "PSNAccountIDTool_Uninstall.exe")
    regAdd(key, "DisplayName", "REG_SZ", "PSN Account ID Tool")
    regAdd(key, "DisplayVersion", "REG_SZ", "1.0.0")
    regAdd(key, "Publisher", "REG_SZ", "PSN Account ID Tool")
    regAdd(key, "InstallLocation", "REG_SZ", installDir)
    regAdd(key, "UninstallString", "REG_SZ", `"`+uninstallExe+`"`)
    regAdd(key, "NoModify", "REG_DWORD", "1")
    regAdd(key, "NoRepair", "REG_DWORD", "1")

    return installDir, nil
}

func launch(installDir string) {
    launcher := filepath.Join(installDir, "Launch.vbs")
    cmd := exec.Command("wscript.exe", launcher)
    cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
    _ = cmd.Start()
}

func main() {
    const MB_YESNO = 0x00000004
    const MB_ICONINFORMATION = 0x00000040
    const MB_ICONERROR = 0x00000010
    const IDYES = 6

    installDir, err := install()
    if err != nil {
        messageBox("PSN Account ID Tool Setup", "Installation failed:\n\n"+err.Error(), MB_ICONERROR)
        return
    }

    response := messageBox(
        "PSN Account ID Tool Setup",
        "PSN Account ID Tool v1.0 was installed successfully.\n\nIt is installed for the current Windows user and added to the Start Menu.\n\nLaunch the application now?",
        MB_YESNO|MB_ICONINFORMATION,
    )
    if response == IDYES {
        launch(installDir)
    }
}
