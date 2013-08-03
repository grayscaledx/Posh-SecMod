﻿ 
 Function Get-WebFile
 {
     Param(
        [Parameter(Mandatory = $true)]
        [uri]$URL,

        [Parameter(Mandatory = $true)]
        $LocalFile
     )
  
    Begin
    {
        Write-Verbose "Creating new web client object to download $URL"
        $WebClient = New-Object System.Net.WebClient
        # Used GUID generation to create unique SourceIdentifiers; Readded original identifiers and instead unregistered previously created events by this function.
        #$Guid = [guid]::NewGuid()
    }
    
    Process
    {
        try 
        {
            Write-Verbose "Attempting to download $URL using WebClient object"
            Register-ObjectEvent $WebClient DownloadProgressChanged -action {     

                Write-Progress -Activity "Downloading" -Status `
                    ("{0} of {1}" -f $eventargs.BytesReceived, $eventargs.TotalBytesToReceive) `
                    -PercentComplete $eventargs.ProgressPercentage    
            } | Out-Null

            Register-ObjectEvent $WebClient DownloadFileCompleted -SourceIdentifier Finished #-SourceIdentifier $Guid
            $WebClient.DownloadFileAsync($URL, $LocalFile) | Out-Null

            # optionally wait, but you can break out and it will still write progress
            Wait-Event -SourceIdentifier Finished | Out-Null #guid

            

        } 
        finally 
        { 
            $WebClient.dispose()
            Get-EventSubscriber | Unregister-Event
            #Get-Event | Unregister-Event
            Write-Progress -Activity "$URL download complete..." -Completed
        }
    }
    End
    {
        if (Test-Path $LocalFile) {Get-ChildItem $LocalFile}
    }
}




function New-Zip
{
	[CmdletBinding()]
    Param
    (
	[Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
	$ZipFile
	)
	set-content $ZipFile ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18))
	(dir $ZipFile).IsReadOnly = $false
}


function Add-Zip
{
	[CmdletBinding()]
    Param
    (
	[Parameter(Mandatory=$true)]
		$ZipFile,
		
		[Parameter(Mandatory=$true,
                  ValueFromPipeline=$true,
                   Position=1)]
        [ValidateScript({Test-Path $_})]
		$File
		
	)
	if(-not (test-path($ZipFile)))
	{
		set-content $ZipFile ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18))
		(dir $ZipFile).IsReadOnly = $false	
	}
	Write-Verbose $File
	$shellApplication = new-object -com shell.application
	$zipPackage = (new-object -com shell.application).NameSpace(((get-item $ZipFile).fullname))
	$zipPackage.CopyHere((get-item $File).FullName)
}


function Get-ZipChildItems_Recurse 
{
    [CmdletBinding()]
	param(
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [object]$items
    )
     
    foreach($si in $items) 
    { 
        if($si.getfolder -ne $null) 
        { 
            Get-ZipChildItems_Recurse $si.getfolder.items() 
        } 
      $si | select path
      } 
}


function Get-Zip
{
	[CmdletBinding()]
    Param
    (
	    [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [ValidateScript({Test-Path $_})]
		$ZipFile,
		$Recurse = $true
	)

	$shellApplication = new-object -com shell.application
	$zipPackage = $shellApplication.NameSpace(((get-item $ZipFile).fullname))
	if ($Recurse -eq $false)
	{
		$zipPackage.Items() | select path
	}
	else
	{
		Get-ZipChildItems_Recurse $zipPackage.Items()
	}
}


function Expand-Zip
{
	[CmdletBinding()]
    Param
    (
	    [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [ValidateScript({Test-Path $_})]
		$ZipFile,
		
	    [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=1)]
		$Destination
	)
	
	if (Test-Path -PathType Container $Destination)
	{
		$destinationFolder = $shellApplication.NameSpace(((get-item $Destination).fullname))
	}
	else
	{
		New-Item -ItemType container -Path $Destination | Out-Null
		$destinationFolder = $shellApplication.NameSpace(((get-item $Destination).fullname))
	}

	$shellApplication = new-object -com shell.application
	$zipPackage = $shellApplication.NameSpace(((get-item $ZipFile).fullname))
	$destinationFolder = $shellApplication.NameSpace(((get-item $Destination).fullname))
	$destinationFolder.CopyHere($zipPackage.Items())
}


<#
	.SYNOPSIS
		cmdlet for calculatingt the hash of a given file.

	.DESCRIPTION
		Calculates either the MD5, SHA1, SHA256, SHA384 or SHA512 checksum of a given file.

	.PARAMETER  File
		The description of the ParameterA parameter.

	.PARAMETER  HashAlgorithm
		The description of the ParameterB parameter.

	.EXAMPLE
		PS C:\> Get-Something -ParameterA 'One value' -ParameterB 32
#>
function Get-FileHash 
{
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [ValidateScript({Test-Path $_})] 
        $File,

		[ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512")]
    	$HashAlgorithm = "MD5"
	)
	 Begin
    {
		$hashType = [Type] "System.Security.Cryptography.$HashAlgorithm"
		$hasher = $hashType::Create()
	}
	
	Process
	{
		$inputStream = New-Object IO.StreamReader $File
    	$hashBytes = $hasher.ComputeHash($inputStream.BaseStream)
    	$inputStream.Close()

   		 # Convert the result to hexadecimal
    	$builder = New-Object System.Text.StringBuilder
    	Foreach-Object -Process { [void] $builder.Append($_.ToString("X2")) } -InputObject $hashBytes
		# Create Object
    	$output = New-Object PsObject -Property @{
        		Path = ([IO.Path]::GetFileName($file));
        		HashAlgorithm = $hashAlgorithm;
        		HashValue = $builder.ToString()
			}
	}
	End
	{
		$output
	}
}


<#
.Synopsis
   Updateds to the latest version the Sysinternals Tool Suite
.DESCRIPTION
   Updates to the latest version the Sysinternals Tool Suite the files
   located in a given path using WebDav to connect to the Microsoft Servers.
   If the Path does not exists it will create the folder and download  
   the tools if the force parameter is used.
.EXAMPLE
   PS C:\> Update-SysinternalsTools -Path C:\SysinternalsSuite -Verbose

   Updates the to the latest version the tools in a given path

.EXAMPLE
   PS C:\> Update-SysinternalsTools -Path C:\SysinternalsSuite -Verbose -Force

   Updates the to the latest version the tools in a given path and if the path
   does not exists it will create it.
#>
function Update-SysinternalsTools
{
    [CmdletBinding()]
    [OutputType([int])]
    Param
    (
        # Path to where update the tools
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [string]$Path,

        # Creates the directory for the tools if it does not exist.
        [Parameter(Mandatory=$false)]
        [switch]$Force

    )

    Begin
    {
        $WebPath = "\\live.sysinternals.com\Tools"
        # Check if the folder exists and if we should create it before starting.
        if ((Test-Path $Path) -eq $false)
        {
            if ($Force -eq $true)
            {   
                Write-Verbose "Creating folder $($Path)"
                New-Item $Path -type directory | out-null
            }
            else
            {
                Write-Error "Path $($Path) does not exist."
                return
            }
        }
        $files = Get-ChildItem -Path $WebPath -File 
    }
    Process
    {
        if (Test-Path $Path)
        {
            Write-Verbose "Folder exists, collecting information of files on host."
            $filesonhost = @{}
            foreach ($tool in (Get-ChildItem -Path $Path -File))
            {
                $filesonhost += @{$tool.name = $tool.CreationTime}
            }

            foreach ($file in $files)
            {
                if ($file.CreationTime -gt $filesonhost[$file.Name])
                {
                    Write-Verbose "$($file.Name) is newer."
                    Write-Verbose "Downloading $($file.Name)"
                    Copy-Item -Path $file.FullName -Destination "$($Path)\$($file.Name)"
                }
                else
                {
                    write-verbose "$($file.name) is up to date."
                }
            }
        }
        else
        {
            
            foreach ($file in $files)
            {
                Write-Verbose "Downloading $($file.Name)"
                Copy-Item -Path $file.FullName -Destination  "$($Path)\$($file.Name)"
            }
            
        }
    }
    End
    {
    }
}


<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.NOTES
    http://www.powershellmagazine.com/2013/06/27/pstip-get-a-list-of-all-com-objects-available/
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>

function Get-ComObject {

    param(
        [Parameter(Position=0)]
        [string]$Filter = "*"
    )

    $ListofObjects = Get-ChildItem HKLM:\Software\Classes -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match '^\w+\.\w+$' -and (Test-Path -Path "$($_.PSPath)\CLSID")
    } | Select-Object -ExpandProperty PSChildName

    $ListofObjects | Where-Object {$_ -like $Filter}
}
 