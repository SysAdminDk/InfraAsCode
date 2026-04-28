<# 

    Create GPO to apply Arc Agent Hardening
    Ref : https://learn.microsoft.com/en-us/azure/azure-arc/servers/security-overview#disable-unnecessary-management-features

#>

<#

# Compress & encode GPO Scheduled Task.
# ------------------------------------------------------------
$RefGPO = Get-GPO -Name "Ref GPO Schedule"
$temp = Get-Content "\\$($DomainInfo.DNSRoot)\SYSVOL\$($DomainInfo.DNSRoot)\Policies\{$($GPO.Id.Guid)}\Machine\Preferences\ScheduledTasks\ScheduledTasks.xml"
$temp = $temp -replace("FABRIC","DOMAIN")
$Bytes = [Text.Encoding]::Unicode.GetBytes($temp)
$Ms = New-Object IO.MemoryStream
$Gzip = New-Object IO.Compression.GzipStream($Ms, [IO.Compression.CompressionMode]::Compress)
$Gzip.Write($Bytes, 0, $Bytes.Length)
$Gzip.Close()
$Encoded = [Convert]::ToBase64String($Ms.ToArray())

[regex]::Matches($Encoded, ".{1,200}") | ForEach-Object { Write-Host "`$Chunks += `"$($_.Value)`"" }

#>


# Set Variables
# ------------------------------------------------------------
$DomainInfo = Get-ADDomain


# Create GPO
# ------------------------------------------------------------
$GPOName =  "MSFT Azure Arc Server hardening - Domain Controllers"
New-GPO -Name $GPOName | Out-Null
$GPO = Get-GPO -Name $GPOName


# Create Directory in GPO sysvol folder
# ------------------------------------------------------------
$GPOPath = "\\$($DomainInfo.DNSRoot)\SYSVOL\$($DomainInfo.DNSRoot)\Policies\{$($GPO.Id.Guid)}\Machine\Preferences\ScheduledTasks"
if (-Not (Test-Path -Path $GPOPath)) {
    New-Item -Path $GPOPath -ItemType Directory | Out-Null
}


# Compressed Task.
# ------------------------------------------------------------
$Chunks += "H4sIAAAAAAAEAOVXW08bRxj9fsqK52IMBptUG0fgDcUSJCiYRJV42dpmsepLZC8JSdT/3nPOzOLZtU1N+1CpleXdmfnu1/k2tjf2aBMbW2RfbGhzW9jIZja117Zj+1azOt4RIFPr43wA6NQyQR8stzvbtWOs31jbYrsGzj1wB4CN9e5ZCo6/4x8BNhb3gah/WAe/pjXs"
$Chunks += "zA4gpQ5OLezq9gqrQ/sNlDw7hRZH2O/aCeD7oEnw3IfUBDDy+APcKL2Q9RH8VqUloDgG76Zk7otzC3xbktYCbUu2HEJOE6uO5B4BtwHIGZ6UdixpEXyQwmtD8T6x77B3jl2E9RyS+c7ksxzre+DOoQf3pB2BMhXc+XhH2hJrqlOnMX1yAPm7wKAfuI+k089YNfFs+Ng8"
$Chunks += "BFbSImJ2YGkd2pKuidO6rEx0TsvJOcGqIX8e4N+Azm+BWwfklbfyAR5kTnSUETnWj3hSkpNMmyeAMXOu8B5Dk759e7KLUbkC1sw+i08O+FC5kAIvDzLtwz/26hzYU2AsRP0O2UD8G7zP7T34d7H61W6Ro9+Ak0tz0o2hQyY9eoB89tKv4a2bSl5tqpADj/cB0Awwcp+D"
$Chunks += "prCvi/8dVsQ5UdXcYzfHPoFmlzjrQt9bvAfQifUV8iBmbHsVyhi09GQfuxG0LmS1hfscbBstr0TJiid9qkpafx495V6on/PHjc+eLjDaW0aEGpbpYrtYiVDbx4fY66CMBbPhAjvGbIwzrlPJcVZ8wX8sXwy9X6oUPF21eNP5wnfAISTkvku6M9pBSetgiXI8DWJ0BTtY"
$Chunks += "8Zc+klV4bJ+wH+Gkp04yxDk9X1Cei24TDjXMVY/vFXOn2Vus6etcVeT88Ryey3X6MlVVhzhtZJHzx/Ap3zZhEv6cdy51j+TyMXGYo44XPU++YddpA54BMlPXeIf/V0l4KRdGhfVBK9gdvsoXTv8urKMNp4pJrjx1Pa3svb/HYRkdYv2ClfPGNhJfRslOVOh27jtpTxiu"
$Chunks += "A6XCL0vYjiLkfF2Ke6IKT9fk2nYUsfIvxWTgZosyjyoshpbsTe6GqGZlGUbOj1j3VSUj301c5VzoPVqpsO0oip450zNXfrWCDhKeuyiuVkFPOJk61dyfberiZdyX+2zp/1P1DHqee+q3biKhP1qaSA7x5ORQ5OImLs/dQavak36mPvZv2XXkrdvGrs3a7q2N4kkwBXEq"
$Chunks += "Wp2zVm/VIu+4Jv4kqJAOdL31E1cmz07A9czfdAvNGMVU5WRNxSuXny41ld0r94bBrHWL8++AFFMrz2rS0Xm7qkWseS2DnInHprV9ybuTDyLVYa7pwX1XTHzG90taFZ6pic8yolGlmtfJC2v0v+e3TLnO+gnh5Vnh/+y1HfAfaQKeYT+D5eSy1KcG+EyTtpuw9wJYGfJJ"
$Chunks += "Gg50Oy0CPX/6SwnLNe+xO9ENVP1n4nytdfFNwTklgb9rFYk7W8dqr9JPir7jvl6Wc2v1a6yMx6/n4i7a/DXftj8BHYdoTzoQAAA="


# Decode & Decompress the Chunks.
# ------------------------------------------------------------
$CBytes = [Convert]::FromBase64String($Chunks)
$Ms = New-Object IO.MemoryStream(,$CBytes)
$Gzip = New-Object IO.Compression.GzipStream($Ms, [IO.Compression.CompressionMode]::Decompress)
$Reader = New-Object IO.StreamReader($Gzip, [Text.Encoding]::Unicode)
$DecodedXml = $Reader.ReadToEnd()


# Save the ScheduledTasks.xml
# ------------------------------------------------------------
$DecodedXml | Out-File "$GPOPath\ScheduledTasks.xml" -Encoding utf8 -Force


# Update GPO to support ScheduledTasks by adding gPCMachineExtensionNames
# ------------------------------------------------------------
$Guids  = "[{00000000-0000-0000-0000-000000000000}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]" # Group Policy Preferences
$Guids += "[{AADCED64-746C-4633-A97C-D61349046527}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]" # Group Policy Preferences Scheduled Tasks extension

Get-ADObject -Identity $($(Get-GPO -Name $GPO.DisplayName).Path) -ErrorAction SilentlyContinue | Set-ADObject -Replace @{gPCMachineExtensionNames="$Guids"}


# Assign the GPO to Domain Controllers.
# ------------------------------------------------------------
New-GPLink -Name $GPOName -Target $DomainInfo.DomainControllersContainer | Out-Null
