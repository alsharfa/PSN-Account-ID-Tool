Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Web

[System.Windows.Forms.Application]::EnableVisualStyles()

function New-HttpClient([bool]$AllowRedirect = $true) {
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $AllowRedirect
    $handler.UseCookies = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    return $client
}

function Get-PsnAccessCode([string]$Npsso) {
    if ([string]::IsNullOrWhiteSpace($Npsso)) { throw 'Enter your NPSSO token.' }

    $query = [System.Web.HttpUtility]::ParseQueryString('')
    $query['access_type'] = 'offline'
    $query['client_id'] = '09515159-7237-4370-9b40-3806e67c0891'
    $query['redirect_uri'] = 'com.scee.psxandroid.scecompcall://redirect'
    $query['response_type'] = 'code'
    $query['scope'] = 'psn:mobile.v2.core psn:clientapp'
    $url = 'https://ca.account.sony.com/api/authz/v3/oauth/authorize?' + $query.ToString()

    $client = New-HttpClient $false
    try {
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $url)
        [void]$request.Headers.TryAddWithoutValidation('Cookie', 'npsso=' + $Npsso.Trim())
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $location = $null
        if ($response.Headers.Location) { $location = $response.Headers.Location.OriginalString }
        if ([string]::IsNullOrWhiteSpace($location) -or $location -notmatch '\?code=') {
            throw 'Sony did not return an access code. The NPSSO token may be invalid or expired.'
        }
        $uri = New-Object System.Uri($location)
        $params = [System.Web.HttpUtility]::ParseQueryString($uri.Query)
        $code = $params['code']
        if ([string]::IsNullOrWhiteSpace($code)) { throw 'Sony response did not contain an access code.' }
        return $code
    }
    finally {
        if ($client) { $client.Dispose() }
    }
}

function Get-PsnAccessToken([string]$AccessCode) {
    $client = New-HttpClient $true
    try {
        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://ca.account.sony.com/api/authz/v3/oauth/token')
        $request.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Basic', 'MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A=')
        $form = New-Object 'System.Collections.Generic.Dictionary[string,string]'
        $form.Add('code', $AccessCode)
        $form.Add('redirect_uri', 'com.scee.psxandroid.scecompcall://redirect')
        $form.Add('grant_type', 'authorization_code')
        $form.Add('token_format', 'jwt')
        $request.Content = New-Object System.Net.Http.FormUrlEncodedContent($form)
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) { throw ('PSN token request failed: ' + [int]$response.StatusCode + ' ' + $text) }
        $json = $text | ConvertFrom-Json
        if ([string]::IsNullOrWhiteSpace($json.access_token)) { throw 'PSN token response did not include an access token.' }
        return [string]$json.access_token
    }
    finally {
        if ($client) { $client.Dispose() }
    }
}

function Find-PsnAccount([string]$AccessToken, [string]$OnlineId) {
    if ([string]::IsNullOrWhiteSpace($OnlineId)) { throw 'Enter a PSN Online ID.' }

    $client = New-HttpClient $true
    try {
        $payload = @{
            searchTerm = $OnlineId.Trim()
            domainRequests = @(@{ domain = 'SocialAllAccounts' })
        } | ConvertTo-Json -Depth 5 -Compress

        $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'https://m.np.playstation.com/api/search/v1/universalSearch')
        $request.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $AccessToken)
        $request.Content = New-Object System.Net.Http.StringContent($payload, [System.Text.Encoding]::UTF8, 'application/json')
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) { throw ('PSN search failed: ' + [int]$response.StatusCode + ' ' + $text) }
        $json = $text | ConvertFrom-Json

        foreach ($domain in @($json.domainResponses)) {
            foreach ($result in @($domain.results)) {
                $meta = $result.socialMetadata
                if ($meta -and $meta.accountId -and ([string]$meta.onlineId -ieq $OnlineId.Trim())) {
                    return [pscustomobject]@{
                        OnlineId = [string]$meta.onlineId
                        AccountId = [string]$meta.accountId
                        AvatarUrl = [string]$meta.avatarUrl
                    }
                }
            }
        }
        throw 'No exact PSN account match was found. Check the Online ID and PSN privacy/search settings.'
    }
    finally {
        if ($client) { $client.Dispose() }
    }
}

function Convert-DecimalId([string]$Text) {
    $value = [UInt64]::Parse($Text.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
    $bytes = [BitConverter]::GetBytes($value)
    return [pscustomobject]@{
        Decimal = $value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        Base64 = [Convert]::ToBase64String($bytes)
        NumericHex = $value.ToString('x16')
        LittleEndianHex = (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
    }
}

function Convert-AnyId([string]$Text, [string]$Type) {
    $t = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { throw 'Enter an ID to convert.' }
    switch ($Type) {
        'Decimal' { return Convert-DecimalId $t }
        'Chiaki Base64' {
            $bytes = [Convert]::FromBase64String($t)
            if ($bytes.Length -ne 8) { throw 'Chiaki Base64 must decode to exactly 8 bytes.' }
            $value = [BitConverter]::ToUInt64($bytes, 0)
            return Convert-DecimalId $value.ToString()
        }
        'Numeric Hex' {
            $clean = $t -replace '^0x',''
            $value = [Convert]::ToUInt64($clean, 16)
            return Convert-DecimalId $value.ToString()
        }
        'Little-Endian Hex' {
            $clean = ($t -replace '\s','') -replace '^0x',''
            if ($clean -notmatch '^[0-9a-fA-F]{16}$') { throw 'Little-endian hex must be exactly 16 hexadecimal characters.' }
            $bytes = New-Object byte[] 8
            for ($i = 0; $i -lt 8; $i++) { $bytes[$i] = [Convert]::ToByte($clean.Substring($i * 2, 2), 16) }
            $value = [BitConverter]::ToUInt64($bytes, 0)
            return Convert-DecimalId $value.ToString()
        }
    }
    throw 'Unknown input type.'
}

function Set-Output($Result) {
    $txtDecimal.Text = $Result.Decimal
    $txtBase64.Text = $Result.Base64
    $txtHex.Text = $Result.NumericHex
    $txtHexLe.Text = $Result.LittleEndianHex
}

$bg = [System.Drawing.Color]::FromArgb(11, 16, 32)
$panel = [System.Drawing.Color]::FromArgb(18, 26, 45)
$panel2 = [System.Drawing.Color]::FromArgb(12, 19, 34)
$text = [System.Drawing.Color]::FromArgb(240, 244, 252)
$muted = [System.Drawing.Color]::FromArgb(158, 171, 194)
$accent = [System.Drawing.Color]::FromArgb(67, 112, 230)
$line = [System.Drawing.Color]::FromArgb(48, 63, 91)
$success = [System.Drawing.Color]::FromArgb(99, 214, 155)
$errorColor = [System.Drawing.Color]::FromArgb(255, 122, 136)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'PSN Account ID Tool'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(920, 760)
$form.MinimumSize = New-Object System.Drawing.Size(820, 700)
$form.BackColor = $bg
$form.ForeColor = $text
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'PSN Account ID Tool'
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 24)
$title.ForeColor = $text
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(28, 22)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'Retrieve and encode PSN account IDs for Chiaki, chiaki-ng, PSPlay and PXPlay.'
$subtitle.ForeColor = $muted
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(31, 66)
$form.Controls.Add($subtitle)

$lookupGroup = New-Object System.Windows.Forms.GroupBox
$lookupGroup.Text = ' PSN Username Lookup '
$lookupGroup.ForeColor = $text
$lookupGroup.BackColor = $panel
$lookupGroup.Location = New-Object System.Drawing.Point(28, 100)
$lookupGroup.Size = New-Object System.Drawing.Size(846, 215)
$form.Controls.Add($lookupGroup)

$lblSecurity = New-Object System.Windows.Forms.Label
$lblSecurity.Text = 'Uses your NPSSO session token locally. The app does not ask for or save your PSN password.'
$lblSecurity.ForeColor = $muted
$lblSecurity.AutoSize = $true
$lblSecurity.Location = New-Object System.Drawing.Point(18, 28)
$lookupGroup.Controls.Add($lblSecurity)

$btnSignIn = New-Object System.Windows.Forms.Button
$btnSignIn.Text = '1. Sign in to PlayStation'
$btnSignIn.Location = New-Object System.Drawing.Point(20, 56)
$btnSignIn.Size = New-Object System.Drawing.Size(180, 31)
$lookupGroup.Controls.Add($btnSignIn)

$btnNpssoPage = New-Object System.Windows.Forms.Button
$btnNpssoPage.Text = '2. Open NPSSO page'
$btnNpssoPage.Location = New-Object System.Drawing.Point(208, 56)
$btnNpssoPage.Size = New-Object System.Drawing.Size(170, 31)
$lookupGroup.Controls.Add($btnNpssoPage)

$lblNpsso = New-Object System.Windows.Forms.Label
$lblNpsso.Text = 'NPSSO token'
$lblNpsso.AutoSize = $true
$lblNpsso.Location = New-Object System.Drawing.Point(20, 101)
$lookupGroup.Controls.Add($lblNpsso)

$txtNpsso = New-Object System.Windows.Forms.TextBox
$txtNpsso.Location = New-Object System.Drawing.Point(20, 121)
$txtNpsso.Size = New-Object System.Drawing.Size(616, 25)
$txtNpsso.UseSystemPasswordChar = $true
$lookupGroup.Controls.Add($txtNpsso)

$btnShow = New-Object System.Windows.Forms.Button
$btnShow.Text = 'Show'
$btnShow.Location = New-Object System.Drawing.Point(645, 119)
$btnShow.Size = New-Object System.Drawing.Size(72, 29)
$lookupGroup.Controls.Add($btnShow)

$lblOnlineId = New-Object System.Windows.Forms.Label
$lblOnlineId.Text = 'PSN Online ID'
$lblOnlineId.AutoSize = $true
$lblOnlineId.Location = New-Object System.Drawing.Point(20, 156)
$lookupGroup.Controls.Add($lblOnlineId)

$txtOnlineId = New-Object System.Windows.Forms.TextBox
$txtOnlineId.Location = New-Object System.Drawing.Point(20, 176)
$txtOnlineId.Size = New-Object System.Drawing.Size(616, 25)
$lookupGroup.Controls.Add($txtOnlineId)

$btnLookup = New-Object System.Windows.Forms.Button
$btnLookup.Text = 'Lookup'
$btnLookup.BackColor = $accent
$btnLookup.ForeColor = [System.Drawing.Color]::White
$btnLookup.FlatStyle = 'Flat'
$btnLookup.Location = New-Object System.Drawing.Point(645, 173)
$btnLookup.Size = New-Object System.Drawing.Size(175, 31)
$lookupGroup.Controls.Add($btnLookup)

$outputGroup = New-Object System.Windows.Forms.GroupBox
$outputGroup.Text = ' Output '
$outputGroup.ForeColor = $text
$outputGroup.BackColor = $panel
$outputGroup.Location = New-Object System.Drawing.Point(28, 327)
$outputGroup.Size = New-Object System.Drawing.Size(846, 238)
$form.Controls.Add($outputGroup)

function Add-OutputRow($parent, [string]$labelText, [int]$y) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $labelText
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(20, $y)
    $parent.Controls.Add($label)
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(210, ($y - 3))
    $box.Size = New-Object System.Drawing.Size(515, 25)
    $box.ReadOnly = $true
    $box.Font = New-Object System.Drawing.Font('Consolas', 9)
    $parent.Controls.Add($box)
    $copy = New-Object System.Windows.Forms.Button
    $copy.Text = 'Copy'
    $copy.Location = New-Object System.Drawing.Point(736, ($y - 5))
    $copy.Size = New-Object System.Drawing.Size(78, 28)
    $copy.Add_Click({ if (-not [string]::IsNullOrWhiteSpace($this.Tag.Text)) { [System.Windows.Forms.Clipboard]::SetText($this.Tag.Text) } })
    $copy.Tag = $box
    $parent.Controls.Add($copy)
    return $box
}

$txtDecimal = Add-OutputRow $outputGroup 'PSPlay/PXPlay decimal' 40
$txtBase64 = Add-OutputRow $outputGroup 'Chiaki Base64' 86
$txtHex = Add-OutputRow $outputGroup 'Numeric hex' 132
$txtHexLe = Add-OutputRow $outputGroup 'Little-endian hex' 178

$convertGroup = New-Object System.Windows.Forms.GroupBox
$convertGroup.Text = ' Offline Converter '
$convertGroup.ForeColor = $text
$convertGroup.BackColor = $panel
$convertGroup.Location = New-Object System.Drawing.Point(28, 577)
$convertGroup.Size = New-Object System.Drawing.Size(846, 91)
$form.Controls.Add($convertGroup)

$cmbType = New-Object System.Windows.Forms.ComboBox
$cmbType.DropDownStyle = 'DropDownList'
[void]$cmbType.Items.AddRange(@('Decimal','Chiaki Base64','Numeric Hex','Little-Endian Hex'))
$cmbType.SelectedIndex = 0
$cmbType.Location = New-Object System.Drawing.Point(20, 35)
$cmbType.Size = New-Object System.Drawing.Size(175, 25)
$convertGroup.Controls.Add($cmbType)

$txtConvert = New-Object System.Windows.Forms.TextBox
$txtConvert.Location = New-Object System.Drawing.Point(205, 35)
$txtConvert.Size = New-Object System.Drawing.Size(430, 25)
$convertGroup.Controls.Add($txtConvert)

$btnConvert = New-Object System.Windows.Forms.Button
$btnConvert.Text = 'Convert'
$btnConvert.BackColor = $accent
$btnConvert.ForeColor = [System.Drawing.Color]::White
$btnConvert.FlatStyle = 'Flat'
$btnConvert.Location = New-Object System.Drawing.Point(645, 32)
$btnConvert.Size = New-Object System.Drawing.Size(175, 31)
$convertGroup.Controls.Add($btnConvert)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Ready.'
$status.ForeColor = $muted
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(31, 686)
$form.Controls.Add($status)

$btnSignIn.Add_Click({ Start-Process 'https://www.playstation.com/' })
$btnNpssoPage.Add_Click({ Start-Process 'https://ca.account.sony.com/api/v1/ssocookie' })
$btnShow.Add_Click({
    $txtNpsso.UseSystemPasswordChar = -not $txtNpsso.UseSystemPasswordChar
    if ($txtNpsso.UseSystemPasswordChar) { $btnShow.Text = 'Show' } else { $btnShow.Text = 'Hide' }
})

$btnLookup.Add_Click({
    try {
        $btnLookup.Enabled = $false
        $status.ForeColor = $muted
        $status.Text = 'Authenticating and searching PSN...'
        [System.Windows.Forms.Application]::DoEvents()
        $code = Get-PsnAccessCode $txtNpsso.Text
        $token = Get-PsnAccessToken $code
        $account = Find-PsnAccount $token $txtOnlineId.Text
        $result = Convert-DecimalId $account.AccountId
        Set-Output $result
        $status.ForeColor = $success
        $status.Text = ('Found ' + $account.OnlineId + ' — Account ID ' + $account.AccountId)
    }
    catch {
        $status.ForeColor = $errorColor
        $status.Text = $_.Exception.Message
    }
    finally {
        $btnLookup.Enabled = $true
    }
})

$btnConvert.Add_Click({
    try {
        $result = Convert-AnyId $txtConvert.Text ([string]$cmbType.SelectedItem)
        Set-Output $result
        $status.ForeColor = $success
        $status.Text = 'Converted successfully.'
    }
    catch {
        $status.ForeColor = $errorColor
        $status.Text = $_.Exception.Message
    }
})

$txtOnlineId.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $btnLookup.PerformClick() } })
$txtConvert.Add_KeyDown({ if ($_.KeyCode -eq 'Enter') { $btnConvert.PerformClick() } })

[void]$form.ShowDialog()
