<#
CMIT-dRMM-Deploy-Check-Windows-Chrome-and-Edge.ps1
pellis@cmitsolutions.com
2025.12.02.003

Please read the notes.

Two config options: Managed and Unmanaged
Unmanaged:
For using the plugin as is, you can just deploy it without changing any variables.
You will have to control the deployment process, if you have non-Microsoft clients,
you probably don't need to deploy this so determine how you want to control for that.

Managed (Reporting to CIPP): 
We manually populated the M365TenantID site variable on each site with active Microsoft 365 services.
Script can be applied globally, it has a self-check to avoid deploying to any site that lacks the site variable when reporting is enabled.
You may want to target this to All Windows Desktops and All Server Desktops to make a widespread deploy.

You will need to set the variables for your own CIPP site also.

No warranty, use at your own risk, always test first.

Changelog: Fixing Boolean Vars added var debug section

#>

#Adapted from sample script and documentation here: https://docs.check.tech/

# Define extension details
# Chrome
$chromeExtensionId = "benimdeioplgkhanklclahllklceahbe"
$chromeUpdateUrl = "https://clients2.google.com/service/update2/crx"
$chromeManagedStorageKey = "HKLM:\SOFTWARE\Policies\Google\Chrome\3rdparty\extensions\$chromeExtensionId\policy"
$chromeExtensionSettingsKey = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionSettings\$chromeExtensionId"

#Edge
$edgeExtensionId = "knepjpocdagponkonnbggpcnhnaikajg"
$edgeUpdateUrl = "https://edge.microsoft.com/extensionwebstorebase/v1/crx"
$edgeManagedStorageKey = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\3rdparty\extensions\$edgeExtensionId\policy"
$edgeExtensionSettingsKey = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionSettings\$edgeExtensionId"

# Extension Configuration Settings
$showNotifications = 1 # 0 = Unchecked, 1 = Checked (Enabled); default is 1; This will set the "Show Notifications" option in the extension settings.
$enableValidPageBadge = 0 # 0 = Unchecked, 1 = Checked (Enabled); default is 0; This will set the "Show Valid Page Badge" option in the extension settings.
$enablePageBlocking = 1 # 0 = Unchecked, 1 = Checked (Enabled); default is 1; This will set the "Enable Page Blocking" option in the extension settings.
$forceToolbarPin = 1 # 0 = Not pinned, 1 = Force pinned to toolbar; default is 1
if ($env:Reporting -match 'true') { $enableCippReporting = 1 } else { $enableCippReporting = 0 } # 0 = Unchecked, 1 = Checked (Enabled); default is 0; This will set the "Enable CIPP Reporting" option in the extension settings.
$cippServerUrl = "$env:CIPPServerURL" # This will set the "CIPP Server URL" option in the extension settings; default is blank; if you set $enableCippReporting to 1, you must set this to a valid URL including the protocol (e.g., https://cipp.cyberdrain.com). Can be vanity URL or the default azurestaticapps.net domain.
$cippTenantId = "$env:M365TenantID" # This will set the "Tenant ID/Domain" option in the extension settings; default is blank; if you set $enableCippReporting to 1, you must set this to a valid Tenant ID.
$customRulesUrl = "$env:customRulesUrl" # This will set the "Config URL" option in the Detection Configuration settings; default is blank.
$updateInterval = 24 # This will set the "Update Interval" option in the Detection Configuration settings; default is 24 (hours). Range: 1-168 hours (1 hour to 1 week).
$urlAllowlist = @("$env:urlAllowlist") # This will set the "URL Allowlist" option in the Detection Configuration settings; default is blank; if you want to add multiple URLs, add them as a comma-separated list within the brackets (e.g., @("https://example1.com", "https://example2.com")). Supports simple URLs with * wildcard (e.g., https://*.example.com) or advanced regex patterns (e.g., ^https:\/\/(www\.)?example\.com\/.*$).
$enableDebugLogging = 0 # 0 = Unchecked, 1 = Checked (Enabled); default is 0; This will set the "Enable Debug Logging" option in the Activity Log settings.

# Custom Branding Settings
$companyName = "$env:companyName" # This will set the "Company Name" option in the Custom Branding settings; default is "CyberDrain".
$companyURL = "$env:companyURL" # This will set the Company URL option in the Custom Branding settings; default is "https://cyberdrain.com"; Must include the protocol (e.g., https://).
$productName = "$env:productName" # This will set the "Product Name" option in the Custom Branding settings; default is "Check - Phishing Protection".
$supportEmail = "$env:supportEmail" # This will set the "Support Email" option in the Custom Branding settings; default is blank.
$primaryColor = "$env:primaryColor" # This will set the "Primary Color" option in the Custom Branding settings; default is "#F77F00"; must be a valid hex color code (e.g., #FFFFFF).
$logoUrl = "$env:logoUrl" # This will set the "Logo URL" option in the Custom Branding settings; default is blank. Must be a valid URL including the protocol (e.g., https://example.com/logo.png); protocol must be https; recommended size is 48x48 pixels with a maximum of 128x128.

# Extension Settings
# These settings control how the extension is installed and what permissions it has. It is recommended to leave these at their default values unless you have a specific need to change them.
$installationMode = "force_installed"

#<# Debug Vars

write-host $showNotifications
write-host $enableValidPageBadge
write-host $enablePageBlocking
write-host $forceToolbarPin
write-host $enableCippReporting
write-host $cippServerUrl
write-host $cippTenantId
write-host $customRulesUrl
write-host $updateInterval
write-host $urlAllowlist
write-host $enableDebugLogging


#>


# If reporting is disabled, skip the check
if (-not $enableCippReporting) {
    Write-Host "CIPP Reporting disabled. Skipping tenant ID validation."
} else {
    # Check if tenantId variable exists and is not empty
    if (-not (Get-Variable -Name cippTenantId -ErrorAction SilentlyContinue) -or [string]::IsNullOrWhiteSpace($cippTenantId)) {
        Write-Host "Tenant ID variable is missing or empty. Aborting script."
        exit 1
    }

    # Validate if tenantId is a valid GUID
    if (-not [Guid]::TryParse($cippTenantId, [ref]([Guid]::Empty))) {
		Write-Host "Not a valid GUID. Aborting script."
        exit 1
    }

    Write-Host "Tenant ID is valid: $cippTenantId"
}

# Function to check and install extension
function Configure-ExtensionSettings {
    param (
        [string]$ExtensionId,
        [string]$UpdateUrl,
        [string]$ManagedStorageKey,
        [string]$ExtensionSettingsKey
    )

    # Create and configure managed storage key
    if (!(Test-Path $ManagedStorageKey)) {
        New-Item -Path $ManagedStorageKey -Force | Out-Null
    }

    # Set extension configuration settings
    New-ItemProperty -Path $ManagedStorageKey -Name "showNotifications" -PropertyType DWord -Value $showNotifications -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "enableValidPageBadge" -PropertyType DWord -Value $enableValidPageBadge -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "enablePageBlocking" -PropertyType DWord -Value $enablePageBlocking -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "enableCippReporting" -PropertyType DWord -Value $enableCippReporting -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "cippServerUrl" -PropertyType String -Value $cippServerUrl -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "cippTenantId" -PropertyType String -Value $cippTenantId -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "customRulesUrl" -PropertyType String -Value $customRulesUrl -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "updateInterval" -PropertyType DWord -Value $updateInterval -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "enableDebugLogging" -PropertyType DWord -Value $enableDebugLogging -Force | Out-Null

    # Create and configure URL allow list
    $urlAllowlistKey = "$ManagedStorageKey\urlAllowlist"
    if (!(Test-Path $urlAllowlistKey)) {
        New-Item -Path $urlAllowlistKey -Force | Out-Null
    }

    # Clear any existing properties
    Remove-ItemProperty -Path $urlAllowlistKey -Name * -Force | Out-Null

    # Set URL allow list properties with names starting from 1
    for ($i = 0; $i -lt $urlAllowlist.Count; $i++) {
        $propertyName = ($i + 1).ToString()
        $propertyValue = $urlAllowlist[$i]
        New-ItemProperty -Path $urlAllowlistKey -Name $propertyName -PropertyType String -Value $propertyValue -Force | Out-Null
    }

    # Create and configure custom branding
    $customBrandingKey = "$ManagedStorageKey\customBranding"
    if (!(Test-Path $customBrandingKey)) {
        New-Item -Path $customBrandingKey -Force | Out-Null
    }

    # Set custom branding settings
    New-ItemProperty -Path $customBrandingKey -Name "companyName" -PropertyType String -Value $companyName -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "companyURL" -PropertyType String -Value $companyURL -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "productName" -PropertyType String -Value $productName -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "supportEmail" -PropertyType String -Value $supportEmail -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "primaryColor" -PropertyType String -Value $primaryColor -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "logoUrl" -PropertyType String -Value $logoUrl -Force | Out-Null

    # Create and configure extension settings
    if (!(Test-Path $ExtensionSettingsKey)) {
        New-Item -Path $ExtensionSettingsKey -Force | Out-Null
    }

    # Set extension settings
    New-ItemProperty -Path $ExtensionSettingsKey -Name "installation_mode" -PropertyType String -Value $installationMode -Force | Out-Null
    New-ItemProperty -Path $ExtensionSettingsKey -Name "update_url" -PropertyType String -Value $UpdateUrl -Force | Out-Null

    # Add toolbar pinning if enabled
    if ($forceToolbarPin -eq 1) {
        if ($ExtensionId -eq $edgeExtensionId) {
            New-ItemProperty -Path $ExtensionSettingsKey -Name "toolbar_state" -PropertyType String -Value "force_shown" -Force | Out-Null
        } elseif ($ExtensionId -eq $chromeExtensionId) {
            New-ItemProperty -Path $ExtensionSettingsKey -Name "toolbar_pin" -PropertyType String -Value "force_pinned" -Force | Out-Null
        }
    }
 
    Write-Output "Configured extension settings for $ExtensionId"
}

# Configure settings for Chrome and Edge
Configure-ExtensionSettings -ExtensionId $chromeExtensionId -UpdateUrl $chromeUpdateUrl -ManagedStorageKey $chromeManagedStorageKey -ExtensionSettingsKey $chromeExtensionSettingsKey
Configure-ExtensionSettings -ExtensionId $edgeExtensionId -UpdateUrl $edgeUpdateUrl -ManagedStorageKey $edgeManagedStorageKey -ExtensionSettingsKey $edgeExtensionSettingsKey