# Hostnames and IP addresses to test connectivity to
$DNS_SERVER1 = "8.8.8.8"
$DNS_SERVER2 = "1.1.1.1"
$MSPDB_SERVER = "mspdb.eldermark.com"
$NCDB_SERVER = "ncdb.eldermark.com"
$VIADB_SERVER = "viadb.eldermark.com"

# Tunable thresholds for network tests
$ping_threshold = 100 # Ping time in milliseconds for a good connection
$ping_loss_threshold = 10 # Packet loss percentage for a good connection
$run_tracert_threshold = 50 # Threshold for running tracert based on ping time
$tracert_latency_threshold = 150 # Threshold for high latency in tracert hops, indicating a potential issue
$ping_count = 6 # Number of ping packets to send


# Variables to hold total ping times and packet loss
$gateway_total = 0
$gateway_loss = 0
$dns1_total = 0
$dns2_total = 0
$dns1_loss = 0
$dns2_loss = 0
$mspdb_total = 0
$ncdb_total = 0
$viadb_total = 0
$mspdb_loss = 0
$ncdb_loss = 0
$viadb_loss = 0

# Variables for progress counter
$progress_counter = 1
$progress_total = 12

$forceWriteFile = $false # Set to true to automatically save results to a file

# Create temp log file for tracerts
$logDate = Get-Date -Format "MM-dd-yy-HH-mm"

# Log file path
$LogFileFolder = "C:\Temp"
$logFileName = "NetworkTestResults$logDate.txt"
$logFilePath = "$LogFileFolder\$logFileName"
$tracertLogFileName = "TracertLog$logDate.txt"
$tracertLogFilePath = "$LogFileFolder\$tracertLogFileName"
$transcriptPath = "$LogFileFolder\NetworkTestTranscript$logDate.log"

##########################################################
#### FUNCTIONS ####
##########################################################

function Test-ConnectionAndReport {
    param (
        [string]$ServerName,
        [ref]$TotalPing,
        [ref]$PacketLoss
    )

    # Check if log file exists, if not create it
    if (-not (Test-Path $logFilePath)) {
        New-Item -Path $LogFileFolder -Name $logFileName -ItemType "file" -Force | Out-Null
        "`nNetwork Test Results - $(Get-Date)`n" | Out-File -Append $logFilePath
    }

    Write-Host "=============================="
    Write-Host "Testing connection to $ServerName"
    Write-Host "=============================="

    $progress_counter ++
    Write-Progress -Activity "Testing network connectivity" -Status "Testing $ServerName - Step $progress_counter" -PercentComplete (($progress_counter / $progress_total) * 100)

    # Run the ping command
    $pingResult = Test-Connection -Count $ping_count -ComputerName $ServerName -ErrorAction SilentlyContinue 
    $pingResult | Out-File -Append $logFilePath

    if ($pingResult) {
        # Aggregate ping times
        $averagePing = [math]::round(($pingResult | Measure-Object -Property ResponseTime -Average).Average, 2)
        $TotalPing.Value = $averagePing

        Write-Host "Average ping to ${ServerName}: $($TotalPing.Value)ms"
        
        # Calculate packet loss
        $pingResultCount = $pingResult.Count
        $PacketsLost = $ping_count - $pingResultCount
        $PacketsLostPercentage = ($PacketsLost / $ping_count) * 100
        $PacketLoss.Value = $PacketsLostPercentage

        Write-Host "Packet loss to ${ServerName}: ${PacketsLostPercentage}%"
    } else {
        Write-Host "Could not reach $ServerName. Assuming 100% packet loss." -ForegroundColor Red
        $TotalPing.Value = "ERROR"
        $PacketLoss.Value = 100
    }

    # Check if tracert should be run based on ping time
    if ($TotalPing.Value -ge $run_tracert_threshold) {
        Write-Host "Running tracert to $ServerName due to high ping time." -ForegroundColor Yellow
        Test-Tracert -ServerName $ServerName
    }
    else {
        Write-Host "Skipping tracert. Connection to $ServerName appears to be GOOD." -ForegroundColor Green
        $progress_counter ++
    }
}

# Function to analyze tracert output for high latency or timeouts
function Test-Tracert {
    param (
        [string]$ServerName
    )

    # Check if log file exists, if not create it
    if (-not (Test-Path $tracertLogFilePath)) {
        New-Item -Path $LogFileFolder -Name $tracertLogFileName -ItemType "file" -Force | Out-Null
    }

    # Update progress bar
    $progress_counter ++
    Write-Progress -Activity "Testing network connectivity" -Status "Tracing route to $ServerName - Step $progress_counter" -PercentComplete (($progress_counter / $progress_total) * 100)

    # Run tracert command and capture output
    Write-Host "Tracing route to $ServerName"
    $tracertContent = tracert $ServerName

    # Add tracert output to full log, adding new lines for each line
    "`nTracert to $ServerName`n" | Add-Content -Path $tracertLogFilePath
    $tracertContent | Add-Content -Path $tracertLogFilePath

    # Parse tracert output for latency values
    $tracertResults = $tracertContent | Select-String -Pattern "\d{1,3} ms" -AllMatches

    $highLatencyDetected = $false
    $timeoutsDetected = $false

    foreach ($match in $tracertResults.Matches) {
        $latency = $match.Value -replace 'ms', ''
        $latency = [int]$latency

        if ($latency -ge $tracert_latency_threshold) {
            Write-Host "Warning: High latency detected at a hop ($latency ms) Please check logs for more details." -ForegroundColor Yellow
            $highLatencyDetected = $true
        }
    }

    if ($tracertResults.Count -eq 0) {
        Write-Host "Warning: Timeouts or unreachable hops detected." -ForegroundColor Yellow
        $timeoutsDetected = $true
    }

    if (-not $highLatencyDetected -and -not $timeoutsDetected) {
        Write-Host "Traceroute completed without significant issues. Hops: $($tracertResults.Count)" -ForegroundColor Green
    }
}

# # Function for basic speed test
# function Test-SpeedTest {
#     $testFile = "http://speedtest.ftp.otenet.gr/files/test100Mb.db"
#     $duration = Measure-Command { Invoke-WebRequest -Uri $testFile -OutFile "C:\Temp\speedtest.bin" }
#     $speed = (10 / $duration.TotalSeconds) * 8
#     Write-Host "Download speed: $speed Mbps"
# }

# Function to test connectivity to Google DNS and Cloudflare DNS
function Test-DNSConnection {
    param (
        [string]$DNS1,
        [string]$DNS2
    )

    # Test connection to DNS1
    Test-ConnectionAndReport -ServerName $DNS1 -TotalPing ([ref]$dns1_total) -PacketLoss ([ref]$dns1_loss)

    # Test connection to DNS2
    Test-ConnectionAndReport -ServerName $DNS2 -TotalPing ([ref]$dns2_total) -PacketLoss ([ref]$dns2_loss)
    # Check if any of the connections failed
    if ($dns1_total -eq "ERROR" -or $dns2_total -eq "ERROR") {
        Write-Host "DNS connection test failed. Check if the device can connect to the internet. Skipping further tests." -ForegroundColor Red
        return
    elseif ($dns1_total -ge $ping_threshold -and $dns2_total -ge $ping_threshold) {
        Write-Host "DNS connection test failed. Both DNS servers have high latency." -ForegroundColor Red
    }
    }
}

# Function to create log file with network test results

function LogFileRoundup {
    # Get public IP address
    $publicIP = (Invoke-RestMethod -Uri "http://ipinfo.io/json").ip

    # Get content of the tracert log file if it exists
    if (Test-Path $tracertLogFilePath) {
        $Tracert_Full_Log = Get-Content $tracertLogFilePath -Raw
    } else {
        $Tracert_Full_Log = "No tracert logs found."
    }
    # Get content of the network test log file
    $logContent = Get-Content $logFilePath -Raw
    $transcriptContent = Get-Content $transcriptPath -Raw

    $resultsFilePath = "NetworkTestResults.txt"
    $results = @"
Network Test Results - $(Get-Date)
==============================
PC Name: $env:COMPUTERNAME
Username: $env:USERNAME
Public IP: $publicIP
==============================
Gateway: $gateway
Average Ping: $gateway_total ms
Packet Loss: $gateway_loss%

DNS1: $DNS_SERVER1
Average Ping: $dns1_total ms
Packet Loss: $dns1_loss%

DNS2: $DNS_SERVER2
Average Ping: $dns2_total ms
Packet Loss: $dns2_loss%

MSPDB Server: $MSPDB_SERVER
Average Ping: $mspdb_total ms
Packet Loss: $mspdb_loss%
MSPDB OK: $mspdb_ok

NCDB Server: $NCDB_SERVER
Average Ping: $ncdb_total ms
Packet Loss: $ncdb_loss%
NCDB OK: $ncdb_ok

VIADB Server: $VIADB_SERVER
Average Ping: $viadb_total ms
Packet Loss: $viadb_loss%
VIADB OK: $viadb_ok

==============================
Speed Test:
$speedTestResult

==============================
Parameters:
Ping Threshold: $ping_threshold ms
Ping Loss Threshold: $ping_loss_threshold%
Run Tracert Threshold: $run_tracert_threshold ms
Tracert Latency Threshold: $tracert_latency_threshold ms
Ping Count: $ping_count
==============================
Tracert Logs:
==============================

$Tracert_Full_Log

==============================
Network Test Logs:
==============================

$logContent

==============================
Transcript:
==============================
$transcriptContent

"@
        $results | Out-File $resultsFilePath
        Write-Host "Results saved to $resultsFilePath"
        Invoke-Item $resultsFilePath
}

##########################################################
#### MAIN SCRIPT ####
##########################################################

##########################################################
### Intro Screen ###

Write-Host "Eldermark Network Test Script"
Write-Host "=============================="
Write-Host "=============================="
Write-Host "=============================="
Write-Host "=============================="
Write-Host " "
Write-Host " "
Write-Host " ______ _     _                                _      _   _      _                      _      _______        _   "
Write-Host "|  ____| |   | |                              | |    | \ | |    | |                    | |    |__   __|      | |  "
Write-Host "| |__  | | __| | ___ _ __ _ __ ___   __ _ _ __| | __ |  \| | ___| |___      _____  _ __| | __    | | ___  ___| |_ "
Write-Host "|  __| | |/ _  |/ _ \ '__| '_   _ \ / _  | '__| |/ / | .   |/ _ \ __\ \ /\ / / _ \| '__| |/ /    | |/ _ \/ __| __|"
Write-Host "| |____| | (_| |  __/ |  | | | | | | (_| | |  |   <  | |\  |  __/ |_ \ V  V / (_) | |  |   <     | |  __/\__ \ |_ "
Write-Host "|______|_|\__,_|\___|_|  |_| |_| |_|\__,_|_|  |_|\_\ |_| \_|\___|\__| \_/\_/ \___/|_|  |_|\_\    |_|\___||___/\__|"
Write-Host "                                                                                                                  "
Write-Host "                                                                                                                  "
Write-Host " "
Write-Host " "
Write-Host " "
Write-Host "This script is intended for Eldermark Support to use to test network connectivity when troubleshooting possible network issues."
Write-Host "This script will test network connectivity to local network, DNS servers, and Eldermark servers."
Write-Host "Results will be displayed at the end of the test."
Write-Host "=============================="


# Start transcript
Start-Transcript -Path $transcriptPath -Append | Out-Null



# Test gateway connection, get the gateway IP address and test it (wifi or ethernet)
$gateway = (Get-NetIPConfiguration | Where-Object { $_.InterfaceAlias -eq "Wi-Fi" -or $_.InterfaceAlias -eq "Ethernet" }).IPv4DefaultGateway | Select-Object -ExpandProperty NextHop

if ($gateway) {
    Test-ConnectionAndReport -ServerName "$gateway" -TotalPing ([ref]$gateway_total) -PacketLoss ([ref]$gateway_loss)
} else {
    Write-Host "Could not determine the default gateway. Skipping gateway test." -ForegroundColor Red
    $progress_counter ++
    Write-Progress -Activity "Testing network connectivity" -Status "Skipping gateway test - Step $progress_counter" -PercentComplete (($progress_counter / $progress_total) * 100)
}

# Test DNS connections
Test-DNSConnection -DNS1 "$DNS_SERVER1" -DNS2 "$DNS_SERVER2"
# Test MSPDB server
Test-ConnectionAndReport -ServerName "$MSPDB_SERVER" -TotalPing ([ref]$mspdb_total) -PacketLoss ([ref]$mspdb_loss)
$progress_counter ++
# Test NCDB server
Test-ConnectionAndReport -ServerName "$NCDB_SERVER" -TotalPing ([ref]$ncdb_total) -PacketLoss ([ref]$ncdb_loss)
$progress_counter ++
# Test viadb server
Test-ConnectionAndReport -ServerName "$VIADB_SERVER" -TotalPing ([ref]$viadb_total) -PacketLoss ([ref]$viadb_loss)
$progress_counter ++
# Clear the progress bar
Write-Progress -Activity "Testing network connectivity" -Status "Complete" -Completed


##########################################################
#### RESULTS ####
##########################################################

# Report results
Write-Host "==============================" 
Write-Host "Network Test Results"
Write-Host "=============================="

# MSPDB Server Results
if ($mspdb_total -eq "ERROR") {
    Write-Host "MSPDB: Connection is BAD due to an error. $mspdb_total - $mspdb_loss " -ForegroundColor Red
    $mspdb_ok = $false
} elseif ($mspdb_loss -ge $ping_loss_threshold) {
    Write-Host "MSPDB: Connection is BAD due to packet loss ($mspdb_loss%) - (Average ping: $mspdb_total ms) " -ForegroundColor Red
    $mspdb_ok = $false
} elseif ($mspdb_total -le $ping_threshold) {
    Write-Host "MSPDB: Connection is GOOD (Average ping: $mspdb_total ms - Packet loss: ${mspdb_loss}%)" -ForegroundColor Green
    $mspdb_ok = $true
} else {
    Write-Host "MSPDB: Connection is BAD (Average ping: $mspdb_total ms - Packet loss: ${mspdb_loss}%) " -ForegroundColor Red
    $mspdb_ok = $false
}

# NCDB Server Results
if ($ncdb_total -eq "ERROR") {
    Write-Host "NCDB: Connection is BAD due to an error. $ncdb_total - $ncdb_loss " -ForegroundColor Red
    $ncdb_ok = $false
} elseif ($ncdb_loss -ge $ping_loss_threshold) {
    Write-Host "NCDB: Connection is BAD due to packet loss ($ncdb_loss%) - (Average ping: $ncdb_total ms)" -ForegroundColor Red
    $ncdb_ok = $false
} elseif ($ncdb_total -le $ping_threshold) {
    Write-Host "NCDB: Connection is GOOD (Average ping: $ncdb_total ms - Packet loss: ${ncdb_loss}%)" -ForegroundColor Green
    $ncdb_ok = $true
} else {
    Write-Host "NCDB: Connection is BAD (Average ping: $ncdb_total ms - Packet loss: ${ncdb_loss}%) " -ForegroundColor Red
    $ncdb_ok = $false
}

# viadb Server Results
if ($viadb_total -eq "ERROR") {
    Write-Host "VIADB: Connection is BAD due to an error. $viadb_total - $viadb_loss " -ForegroundColor Red
    $viadb_ok = $false
} elseif ($viadb_loss -ge $ping_loss_threshold) {
    Write-Host "VIADB: Connection is BAD due to packet loss ($viadb_loss%) - (Average ping: $viadb_total ms)" -ForegroundColor Red
    $viadb_ok = $false
} elseif ($viadb_total -le $ping_threshold) {
    Write-Host "VIADB: Connection is GOOD (Average ping: $viadb_total ms - Packet loss: ${viadb_loss}%)" -ForegroundColor Green
    $viadb_ok = $true
} else {
    Write-Host "VIADB: Connection is BAD (Average ping: $viadb_total ms - Packet loss: ${viadb_loss}%) " -ForegroundColor Red
    $viadb_ok = $false
}

Write-Host "=============================="
Write-Host "Speed Test"
Write-Host "=============================="

# # Ask to run speed test
# Write-Host "Would you like to run a speed test? (Y/N)"
# $speedTest = Read-Host
# if ($speedTest -eq "Y" -or $speedTest -eq "y") {
#     Test-SpeedTest
#     $speedTestResult = "Download speed: $speed Mbps"
# } else {
#     Write-Host "Skipping speed test."
#     $speedTestResult = "Speed test skipped."
# }
$speedTestResult = "Speed test skipped. - not implemented"

Write-Host "=============================="
Write-Host "Network test completed."
Write-Host "=============================="


# Ask to save the results to a file, if yes then save and open the file

if ($forceWriteFile) {
    Write-Host "Saving results to file..."
    LogFileRoundup
} else {
    Write-Host "Would you like to save the results to a file? (Y/N)"

    $saveResults = Read-Host
    if ($saveResults -eq "Y" -or $saveResults -eq "y") {
        LogFileRoundup
    } 
    else {
        Write-Host "Results not saved."

    }
}

##########################################################
### Cleanup ###
##########################################################
Write-Host "cleaning up..."

# Stop transcript
Stop-Transcript | Out-Null

# cleanup log files
if (Test-Path $tracertLogFilePath) {
    Remove-Item $tracertLogFilePath
}
if (Test-Path $logFilePath) {
    Remove-Item $logFilePath
}
if (Test-Path $transcriptPath) {
    Remove-Item $transcriptPath
}


# Press any key to exit
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
