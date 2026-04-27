<#

    Create PVE Connection JSON configuration file.

#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Query window
# ------------------------------------------------------------
$Queryform = New-Object System.Windows.Forms.Form
$Queryform.Text = 'Update GIT Secret'
$Queryform.Size = New-Object System.Drawing.Size(500,230)
$Queryform.StartPosition = 'CenterScreen'
$Queryform.FormBorderStyle = 'Fixed3D'
$Queryform.MaximizeBox = $false
$Queryform.MinimizeBox = $false


# DisplayName Label
$DisplayNameLabel = New-Object System.Windows.Forms.Label
$DisplayNameLabel.Location = New-Object System.Drawing.Point(10,10)
$DisplayNameLabel.Size = New-Object System.Drawing.Size(80,20)
$DisplayNameLabel.Text = 'Display Name:'
$Queryform.Controls.Add($DisplayNameLabel)

# DisplayName
$DisplayName = New-Object System.Windows.Forms.TextBox
$DisplayName.Location = New-Object System.Drawing.Point(100,10)
$DisplayName.Size = New-Object System.Drawing.Size(300,20)             # Size = 300 = 48 chars
$DisplayName.Text = "PVE Standalone Node"
$Queryform.Controls.Add($DisplayName)


# HostName Label
$HostNameLabel = New-Object System.Windows.Forms.Label
$HostNameLabel.Location = New-Object System.Drawing.Point(10,35)
$HostNameLabel.Size = New-Object System.Drawing.Size(80,20)
$HostNameLabel.Text = 'Host Name:'
$Queryform.Controls.Add($HostNameLabel)

# HostName
$HostName = New-Object System.Windows.Forms.TextBox
$HostName.Location = New-Object System.Drawing.Point(100,35)
$HostName.Size = New-Object System.Drawing.Size(100,20)
$HostName.Text = "PVE-01"
$Queryform.Controls.Add($HostName)


# UserName Label
$UserNameLabel = New-Object System.Windows.Forms.Label
$UserNameLabel.Location = New-Object System.Drawing.Point(10,60)
$UserNameLabel.Size = New-Object System.Drawing.Size(80,20)
$UserNameLabel.Text = 'User Name:'
$Queryform.Controls.Add($UserNameLabel)

# UserName
$UserName = New-Object System.Windows.Forms.TextBox
$UserName.Location = New-Object System.Drawing.Point(100,60)
$UserName.Size = New-Object System.Drawing.Size(100,20)
$UserName.Text = "root@pam"
$Queryform.Controls.Add($UserName)

# TokenID Label
$TokenIDLabel = New-Object System.Windows.Forms.Label
$TokenIDLabel.Location = New-Object System.Drawing.Point(10,85)
$TokenIDLabel.Size = New-Object System.Drawing.Size(80,20)
$TokenIDLabel.Text = 'Token ID:'
$Queryform.Controls.Add($TokenIDLabel)

# TokenID
$TokenID = New-Object System.Windows.Forms.TextBox
$TokenID.Location = New-Object System.Drawing.Point(100,85)
$TokenID.Size = New-Object System.Drawing.Size(300,20)
$TokenID.Text = "PowerShell"
$Queryform.Controls.Add($TokenID)

# PVEToken Label
$PVETokenLabel = New-Object System.Windows.Forms.Label
$PVETokenLabel.Location = New-Object System.Drawing.Point(10,110)
$PVETokenLabel.Size = New-Object System.Drawing.Size(80,20)
$PVETokenLabel.Text = 'Token:'
$Queryform.Controls.Add($PVETokenLabel)

# Token
$PVEToken = New-Object System.Windows.Forms.TextBox
$PVEToken.Location = New-Object System.Drawing.Point(100,110)
$PVEToken.Size = New-Object System.Drawing.Size(300,20)
$PVEToken.Text = ""
$Queryform.Controls.Add($PVEToken)

# PVE Host Label
$PVEHostLabel = New-Object System.Windows.Forms.Label
$PVEHostLabel.Location = New-Object System.Drawing.Point(10,135)
$PVEHostLabel.Size = New-Object System.Drawing.Size(80,20)
$PVEHostLabel.Text = 'Host Address:'
$Queryform.Controls.Add($PVEHostLabel)

# Token
$PVEHost = New-Object System.Windows.Forms.TextBox
$PVEHost.Location = New-Object System.Drawing.Point(100,135)
$PVEHost.Size = New-Object System.Drawing.Size(300,20)
$PVEHost.Text = ""
$Queryform.Controls.Add($PVEHost)

# ------------------------------------------------------------
# Buttons
# ------------------------------------------------------------

# Add / Update button
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Location = New-Object System.Drawing.Point(330,165)
$updateButton.Size = New-Object System.Drawing.Size(73,22)
$updateButton.Text = 'Update'
$updateButton.Add_Click({

    # Create SaveAs Dialog
    $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveDialog.Title  = "Save configuration file"
    $SaveDialog.Filter = "Config files (*.json)|*.json|All files (*.*)|*.*"
    $SaveDialog.FileName = "Proxmox-Connection.json"
    $SaveDialog.InitialDirectory = "$([Environment]::GetFolderPath("UserProfile"))\Downloads"

    $SaveDialog.ShowDialog()

    # Create JSON file.
    [pscustomobject]@{
        DisplayName = $DisplayName.Text
        HostName = $HostName.Text
        User = $UserName.Text
        TokenID = $TokenID.Text
        Token = $PVEToken.Text
        Host = $PVEHost.Text

    } | Convertto-Json | Out-File -FilePath $SaveDialog.FileName -Encoding utf8

    # Close form.
    $Queryform.Close()
})
$Queryform.Controls.Add($updateButton)

# Exit Button
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Location = New-Object System.Drawing.Point(405,165)
$exitButton.Size = New-Object System.Drawing.Size(73,22)
$exitButton.Text = 'Exit'
$Queryform.CancelButton = $exitButton
$Queryform.Controls.Add($exitButton)

$Queryform.ShowDialog() | Out-Null
