@echo off

echo This script will download and run the NetworkTest.ps1 script from the RobertPuffeEldermark GitHub repository.
echo Downloading the networktest.ps1 file
powershell -Command "Invoke-WebRequest 'https://raw.githubusercontent.com/RobertPuffeEldermark/support-tools-crispy-octo-palm-tree/main/NetworkTest/NetworkTest.ps1' -OutFile EldermarkNetworkTest.ps1

REM Run the networktest.ps1 file
powershell -NoProfile -ExecutionPolicy Bypass -File EldermarkNetworkTest.ps1

pause
