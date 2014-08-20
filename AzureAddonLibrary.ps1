function New-AzureVNet {
  <#
  .SYNOPSIS
  New-AzureVNet provisions new Azure Virtual Networks in an existing Azure Subscription
  .DESCRIPTION
  New-AzureVNet defines new Azure Virtual Network and DNS Server information, 
  merges with an existing Azure Virtual Network configuration, 
  and then provisions the resulting final configuration in an existing Azure subscription.
  For demonstration purposes only. 
  No support or warranty is supplied or inferred. 
  Use at your own risk.
  .PARAMETER NewDnsServerName
  The name of a new DNS Server to provision
  .PARAMETER newDnsServerIP
  The IPv4 address for the new DNS Server
  .PARAMETER NewVNetName
  The name of a new Azure Virtual Network to provision
  .PARAMETER NewVNetLocation
  The name of the Azure datacenter region in which to provision the new Azure Virtual Network
  .PARAMETER NewVNetAddressRange
  The IPv4 address range for the new Azure Virtual Network in CIDR format. Ex) 10.1.0.0/16
  .PARAMETER NewSubnetName
  The name of a new subnet within the Azure Virtual Network
  .PARAMETER NewSubnetAddressRange
  The IPv4 address range for the subnet in the new Azure Virtual Network in CIDR format. Ex) 10.1.0.0/24
  .PARAMETER ConfigFile
  Specify file location for writing finalized Azure Virtual Network configuration in XML format.
  .INPUTS
  Parameters above.
  .OUTPUTS
  Final Azure Virtual Network XML configuration that was successfully provisioned.
  .NOTES
  Version: 1.0
  Creation Date: Aug 1, 2014
  Author: Keith Mayer ( http://KeithMayer.com )
  Change: Initial function development
  Provision a new Azure Virtual Network using default values.
  .EXAMPLE
  New-AzureVNet -NewDnsServerName dc1 -NewDnsServerIP 10.0.10.4 -NewVNetName domainvlan -NewVNetLocation "West Europe" -ConfigFile 'C:\Temp\AzureVNetConfig.XML'
  #>
  [CmdletBinding()]
  param 
  (
  [Parameter(Mandatory=$true)]
  [string]$NewDnsServerName,
  [Parameter(Mandatory=$true)]
  [string]$NewDnsServerIP,
  [Parameter(Mandatory=$true)]
  [string]$NewVNetName,
  [Parameter(Mandatory=$true)]
  [string]$NewVNetLocation,
  [Parameter(Mandatory=$true)]
  [string]$NewVNetAddressRange,
  [Parameter(Mandatory=$true)]
  [string]$NewSubnetName,
  [Parameter(Mandatory=$true)]
  [string]$NewSubnetAddressRange,
  [Parameter(Mandatory=$true)]
  [string]$ConfigFile
  )

  begin {
    Write-Verbose "Deleting $ConfigFile if it exists"
    Del $ConfigFile -ErrorAction:SilentlyContinue
  }

  process {
    Write-Verbose "Build generic XML template for new Virtual Network"
    $NewVNetConfig = [xml] '
<NetworkConfiguration xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration">
  <VirtualNetworkConfiguration>
    <Dns>
      <DnsServers>
        <DnsServer name="" IPAddress="" />
      </DnsServers>
    </Dns>
    <VirtualNetworkSites>
      <VirtualNetworkSite name="" Location="">
        <AddressSpace>
          <AddressPrefix></AddressPrefix>
        </AddressSpace>
        <Subnets>
          <Subnet name="">
            <AddressPrefix></AddressPrefix>
          </Subnet>
        </Subnets>
        <DnsServersRef>
          <DnsServerRef name="" />
        </DnsServersRef>
      </VirtualNetworkSite>
    </VirtualNetworkSites>
  </VirtualNetworkConfiguration>
</NetworkConfiguration>
'

    Write-Verbose "Add DNS attribute values to XML template"
    $NewDnsElements = $NewVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers.DnsServer
    $NewDnsElements.SetAttribute('name', $NewDnsServerName)
    $NewDnsElements.SetAttribute('IPAddress', $NewDnsServerIP)

    Write-Verbose "Add VNet attribute values to XML template"
    $NewVNetElements = $NewVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.VirtualNetworkSite
    $NewVNetElements.SetAttribute('name', $NewVNetName)
    $NewVNetElements.SetAttribute('Location', $NewVNetLocation)
    $NewVNetElements.AddressSpace.AddressPrefix = $NewVNetAddressRange
    $NewVNetElements.Subnets.Subnet.SetAttribute('name', $NewSubNetName)
    $NewVNetElements.Subnets.Subnet.AddressPrefix = $NewSubnetAddressRange
    $NewVNetElements.DnsServersRef.DnsServerRef.SetAttribute('name', $NewDnsServerName)

    Write-Verbose "Get existing VNet configuration from Azure subscription"
    $ExistingVNetConfig = [xml] (Get-AzureVnetConfig).XMLConfiguration

    Write-Verbose "Merge existing DNS servers into new VNet XML configuration"
    $ExistingDnsServers = $ExistingVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers
    if ($ExistingDnsServers.HasChildNodes) {
      ForEach ($ExistingDnsServer in $ExistingDnsServers.ChildNodes) { 
        if ($ExistingDnsServer.name -ne $NewDnsServerName) {
          $ImportedDnsServer = $NewVNetConfig.ImportNode($ExistingDnsServer,$True)
          $NewVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers.AppendChild($ImportedDnsServer) | Out-Null
        }
      }
    }

    Write-Verbose "Merge existing VNets into new VNet XML configuration"
    $ExistingVNets = $ExistingVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites
    if ($ExistingVNets.HasChildNodes) {
      ForEach ($ExistingVNet in $ExistingVNets.ChildNodes) { 
        if ($ExistingVNet.name -ne $NewVNetName) {
          $importedVNet = $NewVNetConfig.ImportNode($ExistingVNet,$True)
          $NewVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.AppendChild($ImportedVNet) | Out-Null
        }
      }
    }

    Write-Verbose "Merge existing Local Networks into new VNet XML configuration"
    $ExistingLocalNets = $ExistingVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.LocalNetworkSites
    if ($ExistingLocalNets.HasChildNodes) {
      $DnsNode = $NewVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns
      $ImportedLocalNets = $NewVNetConfig.ImportNode($ExistingLocalNets,$True)
      $NewVnetConfig.NetworkConfiguration.VirtualNetworkConfiguration.InsertAfter($ImportedLocalNets,$DnsNode) | Out-Null
    }

    Write-Verbose "Saving new VNet XML configuration to $configFile"
    $newVNetConfig.Save($ConfigFile)

    Write-Verbose "Provisioning new VNet configuration from $configFile"
    Set-AzureVNetConfig -ConfigurationPath $ConfigFile | Out-Null

  end {
    Write-Verbose "Deleting $ConfigFile if it exists"
    Del $ConfigFile -ErrorAction:SilentlyContinue

    Write-Verbose "Returning the final VNet XML Configuration"
    (Get-AzureVnetConfig).XMLConfiguration
  }
}
