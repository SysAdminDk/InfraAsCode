# Tools GUI...
# ------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms

$Form = New-Object System.Windows.Forms.Form
$Form.Text = "PVE Script Launcher"
$Form.StartPosition = "CenterScreen"
$Form.TopMost = $true

$y = 10

$Tools = @("New-PVEVMTemplate.ps1","Create-VMDomain.ps1","Add-VM2Domain.ps1","Create-PVEVMs.ps1")
$Files = Get-ChildItem -Path "C:\Scripts" -Recurse | Where {$_.name -in $Tools}


$Files | Foreach {

    $Button = New-Object System.Windows.Forms.Button
    $Button.Text = $_.Name
    $Button.Size = New-Object System.Drawing.Size(350,30)
    $Button.Location = New-Object System.Drawing.Point(10,$y)
    $Button.Tag = $_.FullName
    $Button.Add_Click({
        Start-Process powershell.exe -ArgumentList "-File `"$($this.Tag)`""
    })

    $Form.Controls.Add($Button)
    $y += 35
}
$y += 45
$Form.Size = New-Object System.Drawing.Size(400,$y)
$Form.ShowDialog()
