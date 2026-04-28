<#
    .SYNOPSIS
    Resolves Azure Local operating system software.

    .DESCRIPTION
    Resolves Azure Local operating system software along with download details.

    .PARAMETER ReleaseTrain
    Specifies the release train (calendar versioning).

    .PARAMETER Search
    Specifies to search for the latest software.
    The cmdlet will start from the current month and search at most 3 months back.

    .EXAMPLE
    Resolve-AzureLocalSoftware

    .EXAMPLE
    Resolve-AzureLocalSoftware -ReleaseTrain 2505

    .EXAMPLE
    Resolve-AzureLocalSoftware -Search

    .OUTPUTS
    [PSCustomObject].

    .LINK
    https://azure.microsoft.com/en-us/products/local
#>

function Resolve-AzureLocalSoftware {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('2\d{3,3}')]
        [string]$ReleaseTrain,

        [Parameter(Mandatory = $false)]
        [switch]$Search
    )

    begin {
        # Valid as of 05.23.2025
        [System.Uri]$Uri = 'https://aka.ms/HCIReleaseImage'

        $searchLimit = 3

        $currentCalendarVersion = Get-Date -Format 'yyMM'

        if ($ReleaseTrain -gt $currentCalendarVersion) {
            throw 'Cannot specify a future release train'
        }

        if (-not($PSBoundParameters.ContainsKey('ReleaseTrain'))) {
            $ReleaseTrain = $currentCalendarVersion
        }

        $searchUri = ('{0}/{1}' -f $uri, $ReleaseTrain)
    }

    process {
        try {
            $request = Invoke-WebRequest -Uri $searchUri -Method Head

            if ($null -ne $request.Headers.'Content-Disposition') {
                $fileName = (Select-String -InputObject $request.Headers.'Content-Disposition' -Pattern 'filename=(.+);').Matches.Groups[-1].Value

                New-Object -TypeName PSCustomObject -Property @{
                    'FileName' = $fileName
                    'ReleaseTrain' = $ReleaseTrain
                    'Uri' = $searchUri
                }
            }
            elseif ($Search) {
                if (-not($PSBoundParameters.ContainsKey('ReleaseTrain'))) {
                    $testReleaseTrain = $currentCalendarVersion-1
                }
                else {
                    $testReleaseTrain = $ReleaseTrain-1
                }

                if ($currentCalendarVersion-$searchLimit -le $testReleaseTrain) {
                    Write-Verbose ("Recursively testing for earlier releases than current month's calendar version {0} within the limit of {1} months back" -f $currentCalendarVersion, $searchLimit)

                    Resolve-AzureLocalSoftware -ReleaseTrain $testReleaseTrain -Search
                }
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    end { }
}

$software = Resolve-AzureLocalSoftware -Search
