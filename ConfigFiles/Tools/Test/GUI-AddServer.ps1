<#
.SYNOPSIS

.DESCRIPTION

.NOTES

.EXAMPLE

#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing


$MasterJSON = Get-Content ".\MasterServerConfig.json" -Raw | ConvertFrom-Json
$loadTemplate = {
    Write-Host $ServerTemplate.SelectedIndex
    $JSON.Roles

    if ($ServerTemplate.SelectedIndex -eq 0) {
        $ServerName.Parent.Controls | Foreach {
            if ($_ -like "System.Windows.Forms.TextBox*") {
                $_.clear()
            }
            if ($_ -like "System.Windows.Forms.ListBox*") {
                $_.Items.Clear()
            }
            if ($_ -like "System.Windows.Forms.ComboBox*") {
                $_.SelectedIndex = 0
            }
            if ($_ -like "System.Windows.Forms.NumericUpDown*") {
                $_.Value = 1
            }
        }

    } else {
        $Script:JSON = $MasterJSON[$($ServerTemplate.SelectedIndex -1)]

        # Populate form controls
        $ServerName.Text         = $JSON.Name
        $Description.Text        = $JSON.Description
        $DomainName.Text         = $(if ($null -eq $JSON.DomainName) { "" } else { $JSON.DomainName })

        # Join options
        $UserDomain.Text         = $JSON.JoinOptions.UserDomain
        $UserDNSDomain.Text      = $JSON.JoinOptions.UserDNSDomain
        $OrganizationalUnit.Text = $(if ($null -eq $JSON.JoinOptions.OrganizationalUnit) { "" } else { $JSON.JoinOptions.OrganizationalUnit })
        $UserName.Text           = $JSON.JoinOptions.Username
        $Password.Text           = $JSON.JoinOptions.Password

        # Network
        $MACAddress.Text         = $JSON.Network.PhysicalAddress
        $IPAddress.Text          = $JSON.Network.IPv4Address
        $SubnetMask.Text         = $JSON.Network.SubnetMask
        $DefaultGateway.Text     = $JSON.Network.DefaultGateway
        $DNSServers.Text         = ($JSON.Network.DNSServers -join ", ")

        # Hardware
        $CPUSockets.Value        = $JSON.Hardware.CPUSockets
        $CPUCores.Value          = $JSON.Hardware.CPUCores
        $MaxMemory.SelectedItem  = $JSON.Hardware.MaxMemory
        $OSDisk.SelectedItem     = $JSON.Hardware.Disks.System

        # Data Disks
        for ($i=0; $i -lt $ComboDataDisks.Count; $i++) {
            if ($i -lt $JSON.Hardware.Disks.Data.Count) {
                $ComboDataDisks[$i].SelectedItem = [int]$JSON.Hardware.Disks.Data[$i]
            }
            else {
                $ComboDataDisks[$i].SelectedItem = 0
            }
        }
    }
}

$UpdateMac = {
    if ([System.Net.IPAddress]::TryParse(($IPAddress.Text), [ref]$null)) {
        $ip = ($IPAddress.Text) -split("\.")
        $MACAddress.Text = "BC-24-{0:X2}-{1:X2}-{2:X2}-{3:X2}" -f [int]$ip[0], [int]$ip[1], [int]$ip[2], [int]$ip[3]
    } else {
        $MACAddress.Text = "Err"
    }
}

$ShowRoles = {

    $RolesJSON = Get-Content ".\MasterRoles.json" -Raw | ConvertFrom-Json

    # Roles list Window
    # ------------------------------------------------------------
    $Rolesform = New-Object System.Windows.Forms.Form
    $Rolesform.Text = 'Select Server Roles'
    $Rolesform.Size = New-Object System.Drawing.Size(300,525)
    #$Rolesform.StartPosition = 'CenterScreen'
    $Rolesform.StartPosition = "CenterParent"
    $Rolesform.FormBorderStyle = 'FixedDialog'
    $Rolesform.MaximizeBox = $false
    $Rolesform.MinimizeBox = $false

    # Roles Check List Box
    $Rolesclb = New-Object System.Windows.Forms.CheckedListBox
    $Rolesclb.Location = New-Object System.Drawing.Point(10,15)
    $Rolesclb.Size = New-Object System.Drawing.Size(270,450)
    $Rolesclb.CheckOnClick = $true

    for ($i=0; $i -lt $Rolesclb.Items.Count; $i++) {
        $Rolesclb.SetItemChecked($i, $false)
    }

    foreach ($Feature in $RolesJSON) {
        $Item = [PSCustomObject]@{
            Name        = $Feature.Name
            DisplayName = $Feature.DisplayName
        }
        [void]$Rolesclb.Items.Add($item)

        if ($JSON.Roles.Name -contains $Feature.Name) {
            $Rolesclb.SetItemChecked($Rolesclb.Items.Count - 1, $true)
        }
    }

    # Show DisplayName in UI
    $Rolesclb.DisplayMember = "DisplayName"
    $Rolesform.Controls.Add($Rolesclb)

    # Update Botton
    $updateButton = New-Object System.Windows.Forms.Button
    $updateButton.Location = New-Object System.Drawing.Point(120,465)
    $updateButton.Size = New-Object System.Drawing.Size(73,22)
    $updateButton.Text = 'Update'
    $updateButton.Add_Click({

        $json.Roles = $Rolesclb.CheckedItems
        $Rolesform.Close()

    })
    $Rolesform.Controls.Add($updateButton)

    # Exit Button
    $exitButton = New-Object System.Windows.Forms.Button
    $exitButton.Location = New-Object System.Drawing.Point(205,465)
    $exitButton.Size = New-Object System.Drawing.Size(73,22)
    $exitButton.Text = 'Exit'
    $Rolesform.CancelButton = $exitButton
    $Rolesform.Controls.Add($exitButton)

    $Rolesform.ShowDialog() | Out-Null
}

$ShowTasks = {

    $TasksJSON = Get-Content ".\MasterTasks.json" -Raw | ConvertFrom-Json

    # Roles list Window
    # ------------------------------------------------------------
    $Tasksform = New-Object System.Windows.Forms.Form
    $Tasksform.Text = 'Select RunOnce'
    $Tasksform.Size = New-Object System.Drawing.Size(400,525)
    $Tasksform.StartPosition = "CenterParent"
    $Tasksform.FormBorderStyle = 'FixedDialog'
    $Tasksform.MaximizeBox = $false
    $Tasksform.MinimizeBox = $false

    # Roles List Box
    $Tasksclb = New-Object System.Windows.Forms.CheckedListBox
    $Tasksclb.Location = New-Object System.Drawing.Point(10,15)
    $Tasksclb.Size = New-Object System.Drawing.Size(370,450)
    $Tasksclb.CheckOnClick = $true

    foreach ($Task in $($TasksJSON | Sort-Object -Property Priority)) {
        # Store object instead of just string
        [void]$Tasksclb.Items.Add([PSCustomObject]@{
            Name        = $Task.Name
            DisplayName = "($($Task.Priority)) $($Task.DisplayName)"
            Priority    = $Task.Priority
        })
        if ($JSON.Tasks.Name -contains $Task.name) {
            $Tasksclb.SetItemChecked($Tasksclb.Items.Count - 1, $true)
        }
    }

    $Tasksclb.DisplayMember = "DisplayName"

    $Tasksclb.Add_ItemCheck({

        # Only act when checking (not unchecking)
        if ($_.NewValue -eq [System.Windows.Forms.CheckState]::Checked) {

            $selectedItem = $Tasksclb.Items[$_.Index]
            $priority = $selectedItem.Priority

            for ($i = 0; $i -lt $Tasksclb.Items.Count; $i++) {

                if ($i -ne $_.Index) {

                    $item = $Tasksclb.Items[$i]

                    # Same priority → uncheck
                    if ($item.Priority -eq $priority -and $Tasksclb.GetItemChecked($i)) {
                        $Tasksclb.SetItemChecked($i, $false)
                    }
                }
            }
        }
    })

    $Tasksform.Controls.Add($Tasksclb)

    $updateButton = New-Object System.Windows.Forms.Button
    $updateButton.Location = New-Object System.Drawing.Point(120,465)
    $updateButton.Size = New-Object System.Drawing.Size(73,22)
    $updateButton.Text = 'Update'
    $updateButton.Add_Click({

        #$listRoles.Items.Clear()
        foreach ($role in $clb.CheckedItems) {
                [void]$listRoles.Items.Add($role.Name)
        }
        $Tasksform.Close()
    
    })
    $Tasksform.Controls.Add($updateButton)

    $exitButton = New-Object System.Windows.Forms.Button
    $exitButton.Location = New-Object System.Drawing.Point(205,465)
    $exitButton.Size = New-Object System.Drawing.Size(73,22)
    $exitButton.Text = 'Exit'
    $Tasksform.CancelButton = $exitButton
    $Tasksform.Controls.Add($exitButton)

    $Tasksform.ShowDialog() | Out-Null
}

$update= {
    Write-Host $($JSON | Convertto-Json)
}


# Query window
# ------------------------------------------------------------
$Queryform = New-Object System.Windows.Forms.Form
$Queryform.Text = 'Create VM'
$Queryform.Size = New-Object System.Drawing.Size(530,760)
$Queryform.StartPosition = 'CenterScreen'
$Queryform.FormBorderStyle = 'Fixed3D'
$Queryform.MaximizeBox = $false
$Queryform.MinimizeBox = $false

# ------------------------------------------------------------
# Server Name and Description
# ------------------------------------------------------------

# Server Information Label
$JoinOptionsLabel = New-Object System.Windows.Forms.Label
$JoinOptionsLabel.Location = New-Object System.Drawing.Point(10,15)
$JoinOptionsLabel.Size = New-Object System.Drawing.Size(150,15)
$JoinOptionsLabel.Text = 'Server Information:'
$Queryform.Controls.Add($JoinOptionsLabel)

$line = New-Object System.Windows.Forms.Panel
$line.Location = New-Object System.Drawing.Point(12, 30)
$line.Size = New-Object System.Drawing.Size(135, 1)
$line.BackColor = [System.Drawing.Color]::Gray
$Queryform.Controls.Add($line)

# ------------------------------------------------------------

# Server Template Label
$ServerTemplateLabel = New-Object System.Windows.Forms.Label
$ServerTemplateLabel.Location = New-Object System.Drawing.Point(10,40)
$ServerTemplateLabel.Size = New-Object System.Drawing.Size(120,20)
$ServerTemplateLabel.Text = 'Select Template:'
$Queryform.Controls.Add($ServerTemplateLabel)

# Server Name
$ServerTemplate = New-Object System.Windows.Forms.ComboBox
$ServerTemplate.Location = New-Object System.Drawing.Point(160,40)
$ServerTemplate.Size = New-Object System.Drawing.Size(110,20)
$ServerTemplate.DropDownStyle = 'DropDownList'

[void]$ServerTemplate.Items.AddRange(@("Select template") + $MasterJSON.name)

$ServerTemplate.SelectedIndex = 0
$ServerTemplate.Add_SelectedIndexChanged({ & $loadTemplate })
$Queryform.Controls.Add($ServerTemplate)


# Server Name Label
$ServerNameLabel = New-Object System.Windows.Forms.Label
$ServerNameLabel.Location = New-Object System.Drawing.Point(10,65)
$ServerNameLabel.Size = New-Object System.Drawing.Size(120,20)
$ServerNameLabel.Text = 'Server Name:'
$Queryform.Controls.Add($ServerNameLabel)

# Server Name
$ServerName = New-Object System.Windows.Forms.TextBox
$ServerName.Location = New-Object System.Drawing.Point(160,65)
$ServerName.Size = New-Object System.Drawing.Size(110,20)
$Queryform.Controls.Add($ServerName)

# Description Label
$DescriptionLabel = New-Object System.Windows.Forms.Label
$DescriptionLabel.Location = New-Object System.Drawing.Point(10,90)
$DescriptionLabel.Size = New-Object System.Drawing.Size(120,20)
$DescriptionLabel.Text = 'Description:'
$Queryform.Controls.Add($DescriptionLabel)

# Description
$Description = New-Object System.Windows.Forms.TextBox
$Description.Location = New-Object System.Drawing.Point(160,90)
$Description.Size = New-Object System.Drawing.Size(350,20)
$Queryform.Controls.Add($Description)

# Domain Name Label
$DomainNameLabel = New-Object System.Windows.Forms.Label
$DomainNameLabel.Location = New-Object System.Drawing.Point(10,115)
$DomainNameLabel.Size = New-Object System.Drawing.Size(120,20)
$DomainNameLabel.Text = 'Domain Name:'
$Queryform.Controls.Add($DomainNameLabel)

# Domain Name
$DomainName = New-Object System.Windows.Forms.TextBox
$DomainName.Location = New-Object System.Drawing.Point(160,115)
$DomainName.Size = New-Object System.Drawing.Size(200,20)
$Queryform.Controls.Add($DomainName)


# ------------------------------------------------------------
# Domain Join Options.
# ------------------------------------------------------------

# Join Options Label
$JoinOptionsLabel = New-Object System.Windows.Forms.Label
$JoinOptionsLabel.Location = New-Object System.Drawing.Point(10,150)
$JoinOptionsLabel.Size = New-Object System.Drawing.Size(145,15)
$JoinOptionsLabel.Text = 'Domain Join:'
$Queryform.Controls.Add($JoinOptionsLabel)

$line = New-Object System.Windows.Forms.Panel
$line.Location = New-Object System.Drawing.Point(12, 165)
$line.Size = New-Object System.Drawing.Size(135, 1)
$line.BackColor = [System.Drawing.Color]::Gray
$Queryform.Controls.Add($line)

# ------------------------------------------------------------

# User Domain Label
$UserDomainLabel = New-Object System.Windows.Forms.Label
$UserDomainLabel.Location = New-Object System.Drawing.Point(10,175)
$UserDomainLabel.Size = New-Object System.Drawing.Size(120,20)
$UserDomainLabel.Text = 'UserDomain:'
$Queryform.Controls.Add($UserDomainLabel)

# User Domain
$UserDomain = New-Object System.Windows.Forms.TextBox
$UserDomain.Location = New-Object System.Drawing.Point(160,175)
$UserDomain.Size = New-Object System.Drawing.Size(110,20)
$Queryform.Controls.Add($UserDomain)

# User DNS Domain Label
$UserDNSDomainLabel = New-Object System.Windows.Forms.Label
$UserDNSDomainLabel.Location = New-Object System.Drawing.Point(10,200)
$UserDNSDomainLabel.Size = New-Object System.Drawing.Size(120,15)
$UserDNSDomainLabel.Text = 'UserDNSDomain:'
$Queryform.Controls.Add($UserDNSDomainLabel)

# User DNS Domain
$UserDNSDomain = New-Object System.Windows.Forms.TextBox
$UserDNSDomain.Location = New-Object System.Drawing.Point(160,200)
$UserDNSDomain.Size = New-Object System.Drawing.Size(200,20)
$Queryform.Controls.Add($UserDNSDomain)

# Organizational Unit Label
$OrganizationalUnitLabel = New-Object System.Windows.Forms.Label
$OrganizationalUnitLabel.Location = New-Object System.Drawing.Point(10,225)
$OrganizationalUnitLabel.Size = New-Object System.Drawing.Size(153,20)
$OrganizationalUnitLabel.Text = 'Organizational Unit:'
$Queryform.Controls.Add($OrganizationalUnitLabel)

# Organizational Unit
$OrganizationalUnit = New-Object System.Windows.Forms.TextBox
$OrganizationalUnit.Location = New-Object System.Drawing.Point(160,225)
$OrganizationalUnit.Size = New-Object System.Drawing.Size(350,20)
$Queryform.Controls.Add($OrganizationalUnit)

# UserName Label
$UserNameLabel = New-Object System.Windows.Forms.Label
$UserNameLabel.Location = New-Object System.Drawing.Point(10,250)
$UserNameLabel.Size = New-Object System.Drawing.Size(130,20)
$UserNameLabel.Text = 'Username:'
$Queryform.Controls.Add($UserNameLabel)

# UserName
$UserName = New-Object System.Windows.Forms.TextBox
$UserName.Location = New-Object System.Drawing.Point(160,250)
$UserName.Size = New-Object System.Drawing.Size(150,20)
$Queryform.Controls.Add($UserName)

# Password Label
$PasswordLabel = New-Object System.Windows.Forms.Label
$PasswordLabel.Location = New-Object System.Drawing.Point(10,275)
$PasswordLabel.Size = New-Object System.Drawing.Size(130,20)
$PasswordLabel.Text = 'Password:'
$Queryform.Controls.Add($PasswordLabel)

# Password
$Password = New-Object System.Windows.Forms.TextBox
$Password.Location = New-Object System.Drawing.Point(160,275)
$Password.Size = New-Object System.Drawing.Size(150,20)
$Queryform.Controls.Add($Password)


# ------------------------------------------------------------
# Network Options.
# ------------------------------------------------------------

# Join Options Label
$JoinOptionsLabel = New-Object System.Windows.Forms.Label
$JoinOptionsLabel.Location = New-Object System.Drawing.Point(10,310)
$JoinOptionsLabel.Size = New-Object System.Drawing.Size(145,15)
$JoinOptionsLabel.Text = 'Network Configuration:'
$Queryform.Controls.Add($JoinOptionsLabel)

$line = New-Object System.Windows.Forms.Panel
$line.Location = New-Object System.Drawing.Point(12, 325)
$line.Size = New-Object System.Drawing.Size(135, 1)
$line.BackColor = [System.Drawing.Color]::Gray
$Queryform.Controls.Add($line)

# ------------------------------------------------------------

# Mac Address Label
$MacAddressLabel = New-Object System.Windows.Forms.Label
$MacAddressLabel.Location = New-Object System.Drawing.Point(10,335)
$MacAddressLabel.Size = New-Object System.Drawing.Size(120,20)
$MacAddressLabel.Text = 'Mac Address:'
$Queryform.Controls.Add($MacAddressLabel)

# Mac Address
$MacAddress = New-Object System.Windows.Forms.TextBox
$MacAddress.Location = New-Object System.Drawing.Point(160,335)
$MacAddress.Size = New-Object System.Drawing.Size(110,20)
$MacAddress.readonly = $true
$Queryform.Controls.Add($MacAddress)

# IPv4Address Label
$IPAddressLabel = New-Object System.Windows.Forms.Label
$IPAddressLabel.Location = New-Object System.Drawing.Point(10,360)
$IPAddressLabel.Size = New-Object System.Drawing.Size(120,20)
$IPAddressLabel.Text = 'IP Address:'
$Queryform.Controls.Add($IPAddressLabel)

# IPv4Address
$IPAddress = New-Object System.Windows.Forms.TextBox
$IPAddress.Location = New-Object System.Drawing.Point(160,360)
$IPAddress.Size = New-Object System.Drawing.Size(110,20)
#$IPAddress.Click
$IPAddress.Add_TextChanged({ & $UpdateMac })
$Queryform.Controls.Add($IPAddress)

# SubnetMask Label
$SubnetMaskLabel = New-Object System.Windows.Forms.Label
$SubnetMaskLabel.Location = New-Object System.Drawing.Point(10,385)
$SubnetMaskLabel.Size = New-Object System.Drawing.Size(120,20)
$SubnetMaskLabel.Text = 'Subnet Mask:'
$Queryform.Controls.Add($SubnetMaskLabel)

# SubnetMask
$SubnetMask = New-Object System.Windows.Forms.TextBox
$SubnetMask.Location = New-Object System.Drawing.Point(160,385)
$SubnetMask.Size = New-Object System.Drawing.Size(110,20)
$Queryform.Controls.Add($SubnetMask)

# Default Gateway Label
$DefaultGatewayLabel = New-Object System.Windows.Forms.Label
$DefaultGatewayLabel.Location = New-Object System.Drawing.Point(10,410)
$DefaultGatewayLabel.Size = New-Object System.Drawing.Size(120,20)
$DefaultGatewayLabel.Text = 'Default Gateway:'
$Queryform.Controls.Add($DefaultGatewayLabel)

# Default Gateway
$DefaultGateway = New-Object System.Windows.Forms.TextBox
$DefaultGateway.Location = New-Object System.Drawing.Point(160,410)
$DefaultGateway.Size = New-Object System.Drawing.Size(110,20)
$Queryform.Controls.Add($DefaultGateway)

# DNS Servers Label
$DNSServersLabel = New-Object System.Windows.Forms.Label
$DNSServersLabel.Location = New-Object System.Drawing.Point(10,435)
$DNSServersLabel.Size = New-Object System.Drawing.Size(120,20)
$DNSServersLabel.Text = 'DNS Servers:'
$Queryform.Controls.Add($DNSServersLabel)

# DNS Servers
$DNSServers = New-Object System.Windows.Forms.TextBox
$DNSServers.Location = New-Object System.Drawing.Point(160,435)
$DNSServers.Size = New-Object System.Drawing.Size(250,20)
$Queryform.Controls.Add($DNSServers)

# ------------------------------------------------------------
# Hardware Options.
# ------------------------------------------------------------

# Hardware Options Label
$HardwareOptionsLabel = New-Object System.Windows.Forms.Label
$HardwareOptionsLabel.Location = New-Object System.Drawing.Point(10,470)
$HardwareOptionsLabel.Size = New-Object System.Drawing.Size(145,15)
$HardwareOptionsLabel.Text = 'Hardware:'
$Queryform.Controls.Add($HardwareOptionsLabel)

$line = New-Object System.Windows.Forms.Panel
$line.Location = New-Object System.Drawing.Point(12, 485)
$line.Size = New-Object System.Drawing.Size(135, 1)
$line.BackColor = [System.Drawing.Color]::Gray
$Queryform.Controls.Add($line)

# ------------------------------------------------------------

# CPU Sockets Label
$CPUSocketsLabel = New-Object System.Windows.Forms.Label
$CPUSocketsLabel.Location = New-Object System.Drawing.Point(10,495)
$CPUSocketsLabel.Size = New-Object System.Drawing.Size(120,20)
$CPUSocketsLabel.Text = 'CPU Sockets:'
$Queryform.Controls.Add($CPUSocketsLabel)

$CPUSockets = New-Object System.Windows.Forms.NumericUpDown
$CPUSockets.Location = New-Object System.Drawing.Point(150, 495)
$CPUSockets.Size = New-Object System.Drawing.Size(60, 20)
$CPUSockets.Minimum = 1
$CPUSockets.Maximum = 2
$CPUSockets.Value = 1
$Queryform.Controls.Add($CPUSockets)

# CPU Cores Label
$CPUCoresLabel = New-Object System.Windows.Forms.Label
$CPUCoresLabel.Location = New-Object System.Drawing.Point(10,520)
$CPUCoresLabel.Size = New-Object System.Drawing.Size(120,20)
$CPUCoresLabel.Text = 'CPU Cores:'
$Queryform.Controls.Add($CPUCoresLabel)

$CPUCores = New-Object System.Windows.Forms.NumericUpDown
$CPUCores.Location = New-Object System.Drawing.Point(150, 520)
$CPUCores.Size = New-Object System.Drawing.Size(60, 20)
$CPUCores.Minimum = 1
$CPUCores.Maximum = 20
$CPUCores.Value = 1
$Queryform.Controls.Add($CPUCores)

# Max Memory Label
$MaxMemoryLabel = New-Object System.Windows.Forms.Label
$MaxMemoryLabel.Location = New-Object System.Drawing.Point(10,545)
$MaxMemoryLabel.Size = New-Object System.Drawing.Size(120,20)
$MaxMemoryLabel.Text = 'Memory:'
$Queryform.Controls.Add($MaxMemoryLabel)

# Max Memory
$MaxMemory = New-Object System.Windows.Forms.ComboBox
$MaxMemory.Location = New-Object System.Drawing.Point(150, 545)
$MaxMemory.Size = New-Object System.Drawing.Size(40, 20)
$MaxMemory.DropDownStyle = 'DropDownList'
[void]$MaxMemory.Items.AddRange(@(4,8,16,32,64))
$MaxMemory.SelectedIndex = 0
$Queryform.Controls.Add($MaxMemory)

# OS Disk Label
$OSDiskLabel = New-Object System.Windows.Forms.Label
$OSDiskLabel.Location = New-Object System.Drawing.Point(10,570)
$OSDiskLabel.Size = New-Object System.Drawing.Size(120,20)
$OSDiskLabel.Text = 'OS Drive:'
$Queryform.Controls.Add($OSDiskLabel)

# OS Disk Memory
$OSDisk = New-Object System.Windows.Forms.ComboBox
$OSDisk.Location = New-Object System.Drawing.Point(150, 570)
$OSDisk.Size = New-Object System.Drawing.Size(40, 20)
$OSDisk.DropDownStyle = 'DropDownList'
[void]$OSDisk.Items.AddRange(@(50,80,100,150))
$OSDisk.SelectedIndex = 0
$Queryform.Controls.Add($OSDisk)

# Data Disks Label
$DataDiskLabel = New-Object System.Windows.Forms.Label
$DataDiskLabel.Location = New-Object System.Drawing.Point(10,595)
$DataDiskLabel.Size = New-Object System.Drawing.Size(120,20)
$DataDiskLabel.Text = 'Data Drives:'
$Queryform.Controls.Add($DataDiskLabel)

# Allowed disk sizes (0 = no disk)
$diskSizes = @(0, 50, 100, 200, 300, 400, 500)

# Create Data drives ComboBoxes
$comboDataDisks = @()
for ($i=1; $i -le 6; $i++) {
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point($(150 + ($i-1)*50), 595)
    $combo.Size = New-Object System.Drawing.Size(50, 20)
    $combo.DropDownStyle = 'DropDownList'
    [void]$combo.Items.AddRange($diskSizes)
    $combo.SelectedIndex = 0

    $Queryform.Controls.Add($combo)
    $comboDataDisks += $combo
}

# ------------------------------------------------------------
# Roles..
# ------------------------------------------------------------

$btnAddRoles = New-Object System.Windows.Forms.Button
$btnAddRoles.Text = "Add/Remove Roles and Features"
$btnAddRoles.Location = New-Object System.Drawing.Point(10, 655)
$btnAddRoles.Size = New-Object System.Drawing.Size(190, 25)
$btnAddRoles.Add_Click({ & $ShowRoles })
$Queryform.Controls.Add($btnAddRoles)


# ------------------------------------------------------------
# Tasks..
# ------------------------------------------------------------

$btnAddTasks = New-Object System.Windows.Forms.Button
$btnAddTasks.Text = "Add/Remove RunOnce Tasks/Scripts"
$btnAddTasks.Location = New-Object System.Drawing.Point(210, 655)
$btnAddTasks.Size = New-Object System.Drawing.Size(210, 25)
$btnAddTasks.Add_Click({ & $ShowTasks })
$Queryform.Controls.Add($btnAddTasks)

# ------------------------------------------------------------
# Buttons
# ------------------------------------------------------------

# Add / Update button
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Location = New-Object System.Drawing.Point(320,690)
$updateButton.Size = New-Object System.Drawing.Size(73,22)
$updateButton.Text = 'Add'
$updateButton.Add_Click($update)
$Queryform.Controls.Add($updateButton)

# Exit Button
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Location = New-Object System.Drawing.Point(405,690)
$exitButton.Size = New-Object System.Drawing.Size(73,22)
$exitButton.Text = 'Exit'
$Queryform.CancelButton = $exitButton
$Queryform.Controls.Add($exitButton)

$Queryform.ShowDialog() | Out-Null
