
############################# INFORMATION ####################################
# Backup Active Directory GPOs for maintenance ops
# Author :ennebet.othmane@gmail.com
# Cloud & Security Architect
# Update history : 
# 11/01/2025 : GPO Backup script
# 12/19/2025 : Added Html report

<#
.COPYRIGHT .
THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys` fees, that arise or result
from the use or distribution of the Sample Code..

.DESCRIPTION 
The script systematically :

- Backs up all GPOs in the domain to a timestamped folder, ensuring a restore point before maintenance operations on Domain Controllers
- Creates a detailed HTML report listing all GPOs, their status, modification times, owners, and backup results.

.REQUIREMENTS 
- Run on a Any Domain Controller OR domain-joined machine with RSAT installed

# EXAMPLE 
# .\GPO_Report_v1.ps1
#> 


cls
Write-Host Loading...

# Variables
$exportPath = "C:\temp\GPOReport"  # Path to export HTML files
$outputHTMLFile = "C:\temp\GPOReport\GPOReport_Summary.html"  # Output file to consolidate GPOs
$GPOexportBkpPath = "C:\temp\GPOReport\bkpGPO" # Path to create random folders and backup GPOs
$rand  = Get-Random
$logo = "logo.png"
$ImgButton = "logo.png"
$DateFormat = Get-Date | Sort-Object -Property Name
$idx = 0



# Remove GPOReport_Summary.html if the file exists
If (Test-Path $outputHTMLFile){
    Remove-Item $outputHTMLFile
}

# Module check
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw "Module ActiveDirectory not found. Install RSAT or run from a host with AD tools."
}
Import-Module ActiveDirectory -ErrorAction Stop

# Create export directory if it doesn't exist
if (-not (Test-Path -Path $exportPath)) {
    New-Item -ItemType Directory -Path $exportPath | Out-Null
}

#Create a date-based folder to save Group Policy backups
$Date = Get-Date -UFormat "%Y-%m-%d"
$UpdatedPath = $GPOexportBkpPath+"\"+$date+"_"+$rand
New-item $UpdatedPath -ItemType directory | Out-Null

# Get All GPOs in descending order
$DSroot = $env:USERDNSDOMAIN
$gpos = Get-GPO -All | Sort-Object -Property ModificationTime -Descending #| Select-Object -First 5
$gposTotal = (Get-GPO -All).count
$gposSettingsEnabled = (Get-GPO -All |? {$_.gpostatus -like "*enabled*" }).count
$gposSettingsDisabled = (Get-GPO -All |? {$_.gpostatus -like "*Disabled*"}).count

# HEADER

$HTMLHeader="<table class='header' width='60%' align='center'>
        <tr bgcolor='#FAFAFA'>
        <td style='text-align: center; text-shadow: 2px 2px 2px #ff0000;'>
        <img src='$logo' height=100 width=200>
        </td>
        <td class='header' width='650' align='center' valign='middle' style='background-image: url('ekg_wide.jpg'); background-repeat: no-repeat; background-position: center; '>
        <p class='shadow'>  Group Policy referential 
       </table>
       <table width='60%' align='center'>
        <tr bgcolor='#FAFAFA'>
                <td style='text-align: center;'>Started $DateFormat </td>
        </table><table width='60%' align='center'>
        <tr bgcolor='#FAFAFA'>
                <td style='text-align: center;'>Domain : $DSroot</td><td style='text-align: center;'>Total of GPOs : $gposTotal</td><td style='text-align: center;'> Enabled : $gposSettingsEnabled</td><td style='text-align: center;'>Disabled GPO settings : $gposSettingsDisabled</td>
        </table>
       "
$HTMLFooter = "Backup location : $UpdatedPath <tr><br><img src='$ImgButton' height=50 width=50>"


# Initialize an empty string for HTML content
$htmlContent = ""

# Generate the index table
$indexTable += ""
$indexTable += ""
$indexTable += ""
$indexTable += "<table width='80%' align='center'>"
$indexTable += "<tr><td>GPO Name</td><td>ID</td><td>Modified on</td><td>GPO Status</td><td>Owner</td><td>GPO backup</td><td>GPOHtmlName</td></tr>"
Write-Host "[+] Group Policy objects maintenance..." -ForegroundColor Blue
Write-Host "[+] Started at $DateFormat" -ForegroundColor Blue 
Write-Host "[+] Processing Group Policy Objects Backup - Total GPOs = $gposTotal ..." -ForegroundColor Blue

foreach ($gpo in $gpos) {

$idx++
Write-Progress -Activity "[+] Processing Group Policy Objects Backup..." -Status "$idx / $gposTotal" -PercentComplete (($idx/$gposTotal)*100)


$gpoName = $gpo.DisplayName
$cleanGpoName = $gpoName -replace '[^a-zA-Z0-9\s_-]', ''
$gpoPath = Join-Path -Path $UpdatedPath -ChildPath $cleanGpoName
$gpoDescription = $gpo.Description
$gpoModificationTime = $gpo.ModificationTime
$gpoStatus = $gpo.GpoStatus
$gpoOwner = $gpo.Owner
$gpoID = $gpo.id
$gponame = $cleanGpoName
   

# Backup GPOs
# Assign temp variables for various parts of GPO data
Write-Host "[+] Backing up GPO [$idx] named: " $GPO.Displayname -ForegroundColor Yellow


$gpoPath = Join-Path -Path $UpdatedPath -ChildPath "$gpoName"
   
    if (-not (Test-Path -Path $gpoPath)) {
        New-Item -ItemType Directory -Path $gpoPath | Out-Null
    }

try {

# Processing GPO Backup
$backupPS = Backup-GPO -Name $gpo.DisplayName -Path $gpoPath -ErrorAction Stop
Write-Host " => [$idx] - Backup GPO : " $GPO.Displayname " Is OK !" -ForegroundColor Green
# Export GPO report as HTML
Get-GPOReport -Name $gpo.DisplayName -ReportType Html -Path "$gpoPath\$gponame.html" -ErrorAction Stop
Write-Host " ==> GPO exported as HTML to $gponame.html" -ForegroundColor DarkGreen
$gpobkp = "<font color=#20d235>backup OK - $date</font>"

#sleep 1
}
catch
{
$gpobkp = "<font color=#FF0000> backup Failed</font>"
Write-Host " => [$idx] - Backup Failed GPO : " $GPO.Displayname -ForegroundColor Red
$gponame = ""
}

$indexTable += "<tr><td>$gpoName<td>$gpoId<td>$gpoModificationTime<td>$gpoStatus<td>$gpoOwner<td>$gpobkp<td>$gponame.html</tr>"      
}
$indexTable +=  "</table>"
$htmlContent += $indexTable

# Get all HTML content in one variable
$HTMLPage =  $HTMLHeader + $htmlContent + $HTMLFooter

# Create the output file and write the HTML content

$HTMLmessage = @"
<font color=""black"" face=""Arial"" size=""2"">
<STYLE TYPE="text/css">
    <!--
    td {
        font-family: Lao UI;
        font-size: 12px;
        border-top: 1px solid #999999;
        border-right: 1px solid #999999;
        border-bottom: 1px solid #999999;
        border-left: 1px solid #999999;
        padding-top: 0px;
        padding-right: 0px;
        padding-bottom: 0px;
        padding-left: 0px;
        overflow: hidden;}
.h1 {
   font-family: Tahoma;
font-size: 8px;
font-weight:bold;
border-top: 0px solid #999999;
border-right: 0px solid #999999;
border-bottom: 0px solid #999999;
border-left: 0px solid #999999;
padding-top: 0px;
padding-right: 0px;
padding-bottom: 0px;
padding-left: 0px;
        overflow: hidden;
color:#387C44;
}

.h2 {
   font-family: Tahoma;
font-size: 8px;
font-weight:bold;
border-top: 0px solid #999999;
border-right: 0px solid #999999;
border-bottom: 0px solid #999999;
border-left: 0px solid #999999;
padding-top: 0px;
padding-right: 0px;
padding-bottom: 0px;
padding-left: 0px;
        overflow: hidden;
color:#FF0000;

}
    .header {
   font-family: Tahoma;
font-size: 20px;
font-weight:bold;
border-top: 1px solid #999999;
border-right: 1px solid #999999;
border-bottom: 1px solid #999999;
border-left: 1px solid #999999;
padding-top: 0px;
padding-right: 0px;
padding-bottom: 0px;
padding-left: 0px;
        overflow: hidden;
color:#000000;
text-shadow:2px 2px 10px #000000;

        }
 
    body {
        margin-left: 5px;
        margin-top: 5px;
        margin-right: 0px;
        margin-bottom: 10px;
        table {Â²
            table-layout:fixed;
            border: thin solid #FFFFFF;}
.shadow {
height: 1em;
filter: Glow(Color=#000000,
Direction=135,
Strength=5);}
        -->
    </style>
<body BGCOLOR=""white"">
$HTMLPage
</body>
"@



ConvertTo-Html -head $head -body $HTMLmessage  | Out-File $outputHTMLFile

Write-Host "[+] GPO Backup location : $UpdatedPath" -ForegroundColor Blue 
Write-Host "[+] GPO Summary export completed. The output file is located at: $outputHTMLFile" -ForegroundColor Blue
Write-Host "Bye !" -ForegroundColor Blue

