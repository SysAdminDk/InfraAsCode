# Tools GUI...
# ------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms

$Form = New-Object System.Windows.Forms.Form
if (-NOT($psISE)) {
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
}
$Form.Text = "PVE Script Launcher"
$form.Font = New-Object System.Drawing.Font("Tahoma", 9)
$Form.UseWaitCursor = $false
$Form.AutoScaleMode = "Dpi"
$Form.StartPosition = "CenterScreen"

$Form.TopMost = $true

$Tools = @("New-PVEVMTemplate.ps1","Create-VMDomain.ps1","Add-VM2Domain.ps1","Create-PVEVMs.ps1")
$Files = $Tools | Foreach { Get-ChildItem -Path "C:\Scripts" -Filter $_ -Recurse }

$y = 10

$Files | Foreach {

    $Button = New-Object System.Windows.Forms.Button
    $Button.Text = $_.Name
    $Button.Size = New-Object System.Drawing.Size(350,30)
    $Button.Location = New-Object System.Drawing.Point(10,$y)
    $Button.Tag = $_.FullName
    $Button.Add_Click({
        Start-Process PowerShell.exe -ArgumentList "-File `"$($this.Tag)`"" -WorkingDirectory "C:\Scripts"
    })

    $Form.Controls.Add($Button)
    $y += 35
}
$y += 45
$Form.Size = New-Object System.Drawing.Size(385,$y)
$Form.ShowDialog()
