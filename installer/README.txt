PSN Account ID Tool v1.0

Purpose
-------
Retrieve the numeric PSN account ID for a PSN Online ID and convert it to the format used by Chiaki/chiaki-ng, PSPlay and PXPlay.

PSN lookup
----------
1. Sign into PlayStation in your browser.
2. Open https://ca.account.sony.com/api/v1/ssocookie in the same browser.
3. Copy the npsso value.
4. Paste it into the tool, enter a PSN Online ID, and click Lookup.

Security
--------
An NPSSO token is equivalent to an authenticated PSN session credential. Keep it private. This utility keeps it only in memory and does not intentionally save it to disk.

Chiaki format
-------------
The numeric 64-bit PSN account ID is stored as 8 little-endian bytes and then Base64 encoded.

This is an unofficial utility and is not affiliated with Sony Interactive Entertainment, Chiaki, chiaki-ng, PSPlay or PXPlay.
