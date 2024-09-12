# This script is provided "as is" by Eldermark Software to assist with diagnosing network issues. 
# It is not a definitive test and results should be used alongside other tools.

# Description: This script is intended for Eldermark Support to use to test network connectivity when troubleshooting possible network issues.  
# Requirements: Windows 10 or later, PowerShell 5.1 or later
# Usage: Run the script in PowerShell. Follow the prompts to test network connectivity.Results will be displayed at the end of the test.

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
$logFileFolder = "C:\Temp\EldermarkNetworkTest"
$logFileName = "NetworkTestResults$logDate.txt"
$logFilePath = "$logFileFolder\$logFileName"
$tracertLogFileName = "TracertLog$logDate.txt"
$tracertLogFilePath = "$logFileFolder\$tracertLogFileName"
$transcriptPath = "$logFileFolder\NetworkTestTranscript$logDate.log"
$resultsFilePath = "$logFileFolder\Eldermark-NetworkTestResults-$env:computername-$logDate.txt" # Full result filepath

# create log file folder if it doesn't exist
if (-not (Test-Path $logFileFolder)) {
    New-Item -Path $logFileFolder -ItemType "directory" -Force | Out-Null
}

##########################################################
#### FUNCTIONS ####
##########################################################

function Test-ConnectionAndReport {
    param (
        [string]$serverName,
        [ref]$totalPing,
        [ref]$packetLoss
    )

    # Check if log file exists, if not create it
    if (-not (Test-Path $logFilePath)) {
        New-Item -Path $logFileFolder -Name $logFileName -ItemType "file" -Force | Out-Null
        "`nNetwork Test Results - $(Get-Date)`n" | Out-File -Append $logFilePath
    }

    Write-Host "=============================="
    Write-Host "Testing connection to $serverName"
    Write-Host "=============================="

    $progress_counter ++
    Write-Progress -Activity "Testing network connectivity" -Status "Testing $serverName - Step $progress_counter" -PercentComplete (($progress_counter / $progress_total) * 100)

    # Run the ping command
    $pingResult = Test-Connection -Count $ping_count -ComputerName $serverName -ErrorAction SilentlyContinue 
    $pingResult | Out-File -Append $logFilePath

    if ($pingResult) {
        # Aggregate ping times
        $averagePing = [math]::round(($pingResult | Measure-Object -Property ResponseTime -Average).Average, 2)
        $totalPing.Value = $averagePing

        Write-Host "Average ping to ${ServerName}: $($totalPing.Value)ms"
        
        # Calculate packet loss
        $pingResultCount = $pingResult.Count
        $PacketsLost = $ping_count - $pingResultCount
        $PacketsLostPercentage = ($PacketsLost / $ping_count) * 100
        $packetLoss.Value = $PacketsLostPercentage

        Write-Host "Packet loss to ${ServerName}: ${PacketsLostPercentage}%"
    } 
    else {
        Write-Host "Could not reach $serverName. Assuming 100% packet loss." -ForegroundColor Red
        $totalPing.Value = "ERROR"
        $packetLoss.Value = 100
    }

    # Check if tracert should be run based on ping time
    if ($totalPing.Value -ge $run_tracert_threshold) {
        Write-Host "Running tracert to $serverName due to high ping time." -ForegroundColor Yellow
        Test-Tracert -ServerName $serverName
    }
    elseif ($packetLoss.Value -ge $ping_loss_threshold) {
        Write-Host "Running tracert to $serverName due to packet loss." -ForegroundColor Yellow
        $forceWriteFile = $true
        Test-Tracert -ServerName $serverName
    }
    else {
        Write-Host "Skipping tracert. Connection to $serverName appears to be GOOD." -ForegroundColor Green
        $progress_counter ++
    }
}

# Function to analyze tracert output for high latency or timeouts
function Test-Tracert {
    param (
        [string]$serverName
    )

    # Check if log file exists, if not create it
    if (-not (Test-Path $tracertLogFilePath)) {
        New-Item -Path $logFileFolder -Name $tracertLogFileName -ItemType "file" -Force | Out-Null
    }

    # Update progress bar
    $progress_counter ++
    Write-Progress -Activity "Testing network connectivity" -Status "Tracing route to $serverName - Step $progress_counter" -PercentComplete (($progress_counter / $progress_total) * 100)

    # Run tracert command and capture output
    Write-Host "Tracing route to $serverName"
    $tracertContent = tracert $serverName

    # Add tracert output to full log, adding new lines for each line
    "`nTracert to $serverName`n" | Add-Content -Path $tracertLogFilePath
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
            forceWriteFile = $true
        }
    }

    if ($tracertResults.Count -eq 0) {
        Write-Host "Warning: Timeouts or unreachable hops detected." -ForegroundColor Yellow
        $timeoutsDetected = $true
        forceWriteFile = $true
    }

    if (-not $highLatencyDetected -and -not $timeoutsDetected) {
        Write-Host "Traceroute completed without significant issues. Hops: $($tracertResults.Count)" -ForegroundColor Green
    }
}

# ToDo: Implement speed test
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
        forceWriteFile = $true
        return
    elseif ($dns1_total -ge $ping_threshold -and $dns2_total -ge $ping_threshold) {
        Write-Host "DNS connection test failed. Both DNS servers have high latency." -ForegroundColor Red
        forceWriteFile = $true
    }
    }
}

# Function to create log file with network test results

function LogFileRoundup {
    Write-Host "+++++++++++++++++++++++++++++++++++++++++"
    Write-Host "========================================="
    Write-Host " "
    Write-Host "Results saved to $resultsFilePath"
    Write-Host " "
    Write-Host "Please save this file and send it to Eldermark Support for further analysis."
    Write-Host " "
    Write-Host "Eldermark Support"
    Write-Host "Email: support@eldermark.com"
    write-Host "Phone: 866-833-2270"
    Write-Host " "
    Write-Host "This network test script is provided as is by Eldermark Software to assist with diagnosing network issues. It is not a definitive test and results should be used alongside other tools."
    Write-Host " "
    Write-Host "========================================="
    Write-Host "+++++++++++++++++++++++++++++++++++++++++"
    # Get public IP address
    $publicIP = (Invoke-RestMethod -Uri "http://ipinfo.io/json").ip

    # Get content of the tracert log file if it exists
    if (Test-Path $tracertLogFilePath) {
        $tracertFullLog = Get-Content $tracertLogFilePath -Raw
    } else {
        $tracertFullLog = "No tracert logs found."
    }
    # Get content of the network test log file
    $logContent = Get-Content $logFilePath -Raw
    $transcriptContent = Get-Content $transcriptPath -Raw


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

$tracertFullLog

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
        Invoke-Item $resultsFilePath
        Start-Process explorer.exe -ArgumentList "$logFileFolder"

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
Write-Host " ______ _     _                                _      _   _      _                      _      _______        _   "
Write-Host "|  ____| |   | |                              | |    | \ | |    | |                    | |    |__   __|      | |  "
Write-Host "| |__  | | __| | ___ _ __ _ __ ___   __ _ _ __| | __ |  \| | ___| |___      _____  _ __| | __    | | ___  ___| |_ "
Write-Host "|  __| | |/ _  |/ _ \ '__| '_   _ \ / _  | '__| |/ / | .   |/ _ \ __\ \ /\ / / _ \| '__| |/ /    | |/ _ \/ __| __|"
Write-Host "| |____| | (_| |  __/ |  | | | | | | (_| | |  |   <  | |\  |  __/ |_ \ V  V / (_) | |  |   <     | |  __/\__ \ |_ "
Write-Host "|______|_|\__,_|\___|_|  |_| |_| |_|\__,_|_|  |_|\_\ |_| \_|\___|\__| \_/\_/ \___/|_|  |_|\_\    |_|\___||___/\__|"
Write-Host "                                                                                                                  "
Write-Host "                                                                                                                  "
Write-Host " "
Write-Host "Disclaimer: "
Write-Host "This script is provided as is by Eldermark Software to assist with diagnosing network issues. It is not a definitive test and results should be used alongside other tools."
Write-Host " "
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
