# PSN Account ID Tool

A Windows utility that retrieves the numeric account ID for most PlayStation Network accounts and converts it to formats used by third-party Remote Play clients such as **Chiaki / chiaki-ng** and **PSPlay / PXPlay**.

## Features

- Look up a PSN account by **Online ID**
- Display the **decimal PSN Account ID** used by PSPlay/PXPlay
- Generate the **8-byte little-endian Base64 Account ID** used by Chiaki/chiaki-ng
- Show numeric hexadecimal and raw little-endian hexadecimal forms
- Convert IDs offline between decimal, Base64 and hexadecimal formats
- Native Windows installer with Start Menu/Desktop shortcuts and uninstall support
- No Node.js or npm required to run the installed application

## Download

Open the repository's **Releases** section and download:

`PSN_Account_ID_Tool_Setup_v1.0.exe`

The release is built automatically from the source in this repository by GitHub Actions.

## PSN lookup

1. Sign in to PlayStation in your normal web browser.
2. Open `https://ca.account.sony.com/api/v1/ssocookie` in the same signed-in browser.
3. Copy the `npsso` value.
4. Paste it into PSN Account ID Tool.
5. Enter the PSN Online ID and choose **Lookup**.

## Security

An **NPSSO token is an authenticated PSN session credential**. Treat it like a password and never share it publicly.

This tool does not ask for your PSN email/password and does not intentionally save the NPSSO token to disk. The token is used in memory to authenticate the PSN lookup request.

## Chiaki encoding

Chiaki uses the numeric 64-bit PSN account ID as **8 little-endian bytes**, then Base64-encodes those bytes.

Example:

| Format | Value |
|---|---|
| Decimal | `962157895908076652` |
| Chiaki Base64 | `bCxwM4JFWg0=` |
| Numeric hex | `0d5a458233702c6c` |
| Little-endian hex | `6c2c703382455a0d` |

## Build from source

The Windows application is implemented with PowerShell WinForms. The installer and uninstaller are small Go programs using only the Go standard library.

GitHub Actions builds the installer automatically. To build locally on Windows with Go installed, use the same commands shown in `.github/workflows/release.yml`.

## Disclaimer

This is an unofficial utility. It is not affiliated with or endorsed by Sony Interactive Entertainment, PlayStation, Chiaki, chiaki-ng, PSPlay, or PXPlay.

## License

MIT License. See [LICENSE](LICENSE).
