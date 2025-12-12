<############################# INFORMATION ####################################
# Default Domain password settings and PSOs v1.0
# Created 12/12/2025
# Author : ennebet.othmane@gmail.com
# Cloud & Security Architect

.SYNOPSIS
    Lists AD users with their effective password settings AND all applicable PSOs
    (directly linked or via groups), including each PSO's Precedence.

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

.PARAMETER SearchBase
    DN of the OU to scope the search.

.PARAMETER EnabledOnly
    Return enabled users only.

.PARAMETER Server
    Target domain controller.

.PARAMETER OutCsv
    Optional CSV export path.

.PARAMETER UseTokenGroups
    Use tokenGroups to resolve transitive group memberships (slower, but exhaustive).

.PARAMETER ExpandPerPSO
    Output one row per (User, PSO) pair instead of one row per user.

.NOTES
    - Effective PSO (winner) is still taken from msDS-ResultantPSO.
    - All applicable PSOs are discovered by mapping msDS-PSOAppliesTo
      to the user object and all of the user's groups.

.EXAMPLES
    .\Get-AdUsers-AllPSO-WithPrecedence.ps1
    .\Get-AdUsers-AllPSO-WithPrecedence.ps1 -ExpandPerPSO -OutCsv .\Users_PSO_Expanded.csv
    .\Get-AdUsers-AllPSO-WithPrecedence.ps1 -UseTokenGroups -EnabledOnly -SearchBase "OU=Users,OU=Tier 2,OU=0_Tier Model Administration,DC=contoso,DC=com"
#>

[CmdletBinding()]
param(
    [string]$SearchBase,
    [switch]$EnabledOnly,
    [string]$Server,
    [string]$OutCsv,
    [switch]$UseTokenGroups,
    [switch]$ExpandPerPSO
)

# --- Module check
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw "Module ActiveDirectory not found. Install RSAT or run from a host with AD tools."
}
Import-Module ActiveDirectory -ErrorAction Stop

# --- Default Domain Password Policy
$ddppParams = @{}
if ($Server) { $ddppParams.Server = $Server }
try {
    $defaultMin = (Get-ADDefaultDomainPasswordPolicy @ddppParams).MinPasswordLength
} catch {
    throw "Failed to read Default Domain Password Policy. Details: $($_.Exception.Message)"
}

# --- Load ALL PSOs and build index DN -> [PSO]
$psoGetParams = @{
    Filter     = '*'
    Properties = @('msDS-PSOAppliesTo','Precedence','MinPasswordLength','PasswordHistoryCount','ComplexityEnabled')
}
if ($Server) { $psoGetParams.Server = $Server }

$psoList = Get-ADFineGrainedPasswordPolicy @psoGetParams

# Index: anchor DN (user or group) -> list of PSOs that apply to it
$applyIndex = @{}
foreach ($pso in $psoList) {
    foreach ($dn in @($pso.'msDS-PSOAppliesTo')) {
        if (-not $dn) { continue }
        if (-not $applyIndex.ContainsKey($dn)) {
            $applyIndex[$dn] = New-Object System.Collections.Generic.List[object]
        }
        $applyIndex[$dn].Add($pso)
    }
}

# Cache for PSO DN -> PSO
$psoCache = @{}
function Get-PsoByDn {
    param([Parameter(Mandatory)][string]$PsoDn)
    if ($psoCache.ContainsKey($PsoDn)) { return $psoCache[$PsoDn] }
    $p = @{}
    if ($Server) { $p.Server = $Server }
    try {
        $pso = Get-ADFineGrainedPasswordPolicy -Identity $PsoDn @p -ErrorAction Stop
        $psoCache[$PsoDn] = $pso
        return $pso
    } catch {
        $psoCache[$PsoDn] = $null
        return $null
    }
}

# Utility: resolve groups of a user
function Get-UserGroupDNs {
    param([Microsoft.ActiveDirectory.Management.ADUser]$User)
    $p = @{}
    if ($Server) { $p.Server = $Server }

    if ($UseTokenGroups) {
        $u = Get-ADUser -Identity $User.DistinguishedName -Properties tokenGroups @p
        $dns = @()
        foreach ($sid in @($u.tokenGroups)) {
            try {
                $obj = Get-ADObject -Filter "objectSid -eq '$sid'" -Properties distinguishedName @p -ErrorAction Stop
                if ($obj.DistinguishedName) { $dns += $obj.DistinguishedName }
            } catch { }
        }
        return $dns | Select-Object -Unique
    } else {
        try {
            (Get-ADPrincipalGroupMembership -Identity $User @p -ErrorAction Stop |
                Select-Object -ExpandProperty DistinguishedName)
        } catch {
            @()
        }
    }
}

# --- Users
$userParams = @{
    Filter     = '*'
    Properties = @('displayName','samAccountName','userPrincipalName','enabled','msDS-ResultantPSO','distinguishedName')
}
if ($SearchBase) { $userParams.SearchBase = $SearchBase }
if ($Server)     { $userParams.Server     = $Server }

$users = Get-ADUser @userParams
if ($EnabledOnly) { $users = $users | Where-Object { $_.Enabled -eq $true } }

$rows = New-Object System.Collections.Generic.List[object]

foreach ($u in $users) {

    # Effective PSO via AD
    $effectiveMin = $defaultMin
    $effectivePsoName = $null
    $effectivePsoDn   = $null
    $effectivePsoPrec = $null
    $source           = 'Default Domain Policy'

    if ($u.'msDS-ResultantPSO') {
        $effectivePsoDn = [string]$u.'msDS-ResultantPSO'
        $effPso = Get-PsoByDn -PsoDn $effectivePsoDn
        if ($effPso) {
            $effectiveMin     = $effPso.MinPasswordLength
            $effectivePsoName = $effPso.Name
            $effectivePsoPrec = $effPso.Precedence
            $source           = 'PSO'
        } else {
            $source           = 'PSO (unresolved)'
            $effectivePsoName = $effectivePsoDn
        }
    }

    # All applicable PSOs (user + groups)
    $applicable = New-Object System.Collections.Generic.List[object]
    $appliedVia = @{} # PSO.Name -> [anchors DNs]

    $userDn = $u.DistinguishedName
    if ($applyIndex.ContainsKey($userDn)) {
        foreach ($pso in $applyIndex[$userDn]) {
            $applicable.Add($pso)
            $appliedVia[$pso.Name] = @($userDn) + @($appliedVia[$pso.Name])
        }
    }

    $groupDns = Get-UserGroupDNs -User $u
    foreach ($gdn in $groupDns) {
        if ($applyIndex.ContainsKey($gdn)) {
            foreach ($pso in $applyIndex[$gdn]) {
                $applicable.Add($pso)
                $appliedVia[$pso.Name] = @($gdn) + @($appliedVia[$pso.Name])
            }
        }
    }

    # De-dup and sort by Precedence asc 
    $applicableUnique = $applicable | Select-Object -Unique
    $applicableSorted = $applicableUnique | Sort-Object Precedence, Name

    if ($ExpandPerPSO) {
        # One row per (User, PSO)
        if ($applicableSorted.Count -eq 0) {
            # Still output a row to show user has no PSO (defaults apply)
            $rows.Add([pscustomobject]@{
                Name                       = $u.DisplayName
                SamAccountName             = $u.SamAccountName
                UPN                        = $u.UserPrincipalName
                Enabled                    = $u.Enabled
                EffectivePSOName           = $effectivePsoName
                EffectivePSOPrecedence     = $effectivePsoPrec
                EffectiveMinPasswordLength = [int]$effectiveMin
                Source                     = $source
                PSOName                    = $null
                PSODN                      = $null
                PSOPrecedence              = $null
                AppliedViaAnchors          = $null
                DefaultDomainMinLength     = [int]$defaultMin
            })
        } else {
            foreach ($pso in $applicableSorted) {
                $anchors = @($appliedVia[$pso.Name] | Sort-Object -Unique)
                $rows.Add([pscustomobject]@{
                    Name                       = $u.DisplayName
                    SamAccountName             = $u.SamAccountName
                    UPN                        = $u.UserPrincipalName
                    Enabled                    = $u.Enabled
                    EffectivePSOName           = $effectivePsoName
                    EffectivePSOPrecedence     = $effectivePsoPrec
                    EffectiveMinPasswordLength = [int]$effectiveMin
                    Source                     = $source
                    PSOName                    = $pso.Name
                    PSODN                      = $pso.DistinguishedName
                    PSOPrecedence              = $pso.Precedence
                    AppliedViaAnchors          = ($anchors -join '; ')
                    DefaultDomainMinLength     = [int]$defaultMin
                })
            }
        }
    } else {
        # Summary row per user with aligned lists (Names / DNs / Precedence)
        $allNames       = ($applicableSorted | ForEach-Object { $_.Name }) -join '; '
        $allDns         = ($applicableSorted | ForEach-Object { $_.DistinguishedName }) -join '; '
        $allPrecedence  = ($applicableSorted | ForEach-Object { $_.Precedence }) -join '; '
        $appliedViaKvp  = foreach ($pso in $applicableSorted) {
            $anchors = @($appliedVia[$pso.Name] | Sort-Object -Unique)
            if ($anchors.Count -gt 0) {
                "{0}:[{1}]" -f $pso.Name, ($anchors -join ',')
            }
        }
        $appliedViaStr = $appliedViaKvp -join ' ; '

        $rows.Add([pscustomobject]@{
            Name                       = $u.DisplayName
            SamAccountName             = $u.SamAccountName
            UPN                        = $u.UserPrincipalName
            Enabled                    = $u.Enabled
            EffectiveMinPasswordLength = [int]$effectiveMin
            Source                     = $source
            PSOName                    = $effectivePsoName
            PSODistinguishedName       = $effectivePsoDn
            EffectivePSOPrecedence     = $effectivePsoPrec
            DefaultDomainMinLength     = [int]$defaultMin

            # New: all PSOs with precedence (aligned by position)
            AllApplicablePSOCount      = ($applicableSorted | Measure-Object).Count
            AllApplicablePSONames      = $allNames
            AllApplicablePSODNs        = $allDns
            AllApplicablePSOPrecedence = $allPrecedence
            AppliedVia                 = $appliedViaStr
        })
    }
}

# ---- Output
if ($ExpandPerPSO) {
    $rows |
        Sort-Object SamAccountName, PSOPrecedence, PSOName |
        Format-Table -AutoSize Name,SamAccountName,Enabled,EffectiveMinPasswordLength,Source,PSOName,EffectivePSOPrecedence
} 

if ($OutCsv) {
    $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutCsv
    Write-Host "CSV exported: $OutCsv" -ForegroundColor Green
}
