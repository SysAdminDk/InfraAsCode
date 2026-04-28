<#

    Create the required JSON configuration file,
    only used is GIT repo is private

#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Query window
# ------------------------------------------------------------
$Queryform = New-Object System.Windows.Forms.Form
$Queryform.Text = 'Update GIT Secret'
$Queryform.Size = New-Object System.Drawing.Size(500,130)
$Queryform.StartPosition = 'CenterScreen'
$Queryform.FormBorderStyle = 'Fixed3D'
$Queryform.MaximizeBox = $false
$Queryform.MinimizeBox = $false


# Repo Url Label
$RepoUrlLabel = New-Object System.Windows.Forms.Label
$RepoUrlLabel.Location = New-Object System.Drawing.Point(10,10)
$RepoUrlLabel.Size = New-Object System.Drawing.Size(60,20)
$RepoUrlLabel.Text = 'Repo Url:'
$Queryform.Controls.Add($RepoUrlLabel)

# Repo Url
$RepoUrl = New-Object System.Windows.Forms.TextBox
$RepoUrl.Location = New-Object System.Drawing.Point(80,10)
$RepoUrl.Size = New-Object System.Drawing.Size(400,20)
$RepoUrl.Text = "https://api.github.com/repos/<RepoName>"
$Queryform.Controls.Add($RepoUrl)


# Repo Token Label
$RepoTokenLabel = New-Object System.Windows.Forms.Label
$RepoTokenLabel.Location = New-Object System.Drawing.Point(10,35)
$RepoTokenLabel.Size = New-Object System.Drawing.Size(60,20)
$RepoTokenLabel.Text = 'Token:'
$Queryform.Controls.Add($RepoTokenLabel)

# Repo Token
$RepoToken = New-Object System.Windows.Forms.TextBox
$RepoToken.Location = New-Object System.Drawing.Point(80,35)
$RepoToken.Size = New-Object System.Drawing.Size(400,20)
$RepoToken.Text = "github_pat_<Token>"
$Queryform.Controls.Add($RepoToken)


# ------------------------------------------------------------
# Buttons
# ------------------------------------------------------------

# Add / Update button
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Location = New-Object System.Drawing.Point(330,65)
$updateButton.Size = New-Object System.Drawing.Size(73,22)
$updateButton.Text = 'Save'
$updateButton.Add_Click({
    
    # Create SaveAs Dialog
    $SaveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveDialog.Title  = "Save configuration file"
    $SaveDialog.Filter = "Config files (*.json)|*.json|All files (*.*)|*.*"
    $SaveDialog.FileName = "GitHub-Connection.json"
    $SaveDialog.InitialDirectory = "$([Environment]::GetFolderPath("UserProfile"))\Downloads"

    $SaveDialog.ShowDialog()

    # Create JSON file.
    [pscustomobject]@{
        Url = $RepoUrl.Text
        Token = $RepoToken.Text
    } | Convertto-Json | Out-File -FilePath $SaveDialog.FileName -Encoding utf8
    
    # Close form.
    $Queryform.Close()
})
$Queryform.Controls.Add($updateButton)

# Exit Button
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Location = New-Object System.Drawing.Point(405,65)
$exitButton.Size = New-Object System.Drawing.Size(73,22)
$exitButton.Text = 'Exit'
$Queryform.CancelButton = $exitButton
$Queryform.Controls.Add($exitButton)

$Queryform.ShowDialog() | Out-Null
