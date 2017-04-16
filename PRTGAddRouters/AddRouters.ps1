#################################
# AddRouters.ps1
# By Jeremy Gibbons, April 2017
# Inspired by https://thedomainiown.wordpress.com/prtg-related/prtg-script-powershell-admin-module/
#################################

#######################
#
# This script expects to find a CSV file in c:\temp\arg.csv
# The CSV file should contain a header line with columns
# - RouterName => US1234-RT01
# - SiteName => US1234 - New York City
# - SubGroup => Midwest
# - IPAddr => 10.5.34.1
# - IfIndex => 3 (this is the snmp index)
# - IfAlias => optional, this is the fixed name of the interface in snmp (while the index may change)
#
#######################

############################
# INSTANCE SPECIFIC VARIABLES
# MUST BE UPDATED PRIOR TO EXECUTING THIS SCRIPT
############################
$user = "ADM_jeremy.gibbons"
$passhash = "1144530515"

# PRTG server, either IP or hostname (do not include http:// or https://)
$PRTGHost = "172.31.230.79"

# The PRTG id of an empty group for a new site
$siteTemplateID = "10019";
# The PRTG id of an empty device for a new router
$routerTemplateID = "10020";
# The PRTG id of an existing ping sensor
$pingSensorTemplateID = "2578";
# The PRTG id of an existing snmptraffic sensor
$snmpSensorTemplateID = "2579";

# The PRTG ID of the group into which all new sites should be placed
$StartingID=10023

#############################
# END INSTANCE SPECIFIC VARIABLES
#############################


# This part is necessary to avoid certificate validation errors when connecting to https servers
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# The auth string used in the REST calls
$auth = "username=$user&passhash=$passhash"

$csvlines = import-csv c:\temp\arg.csv;
foreach($line in $csvlines)
{
	$routerName=$line.RouterName;
	$siteName=$line.SiteName;
	$subgroup=$line.SubGroup;
	$routerIP=$line.IPAddr;
	$ifIndex=$line.IfIndex;
	$ifAlias=$line.IfAlias;

	# Retrieve list of groups in the airgas group
	$url = "https://$PRTGHost/api/table.xml?content=groups&output=xml&columns=objid,group,name,parentid&count=2500&id=$StartingID&$auth"
	$restresp = Invoke-RestMethod -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
	$argGroups = $restresp.groups.item

	# Retrieve list of devices in the airgas group
	$url = "https://$PRTGHost/api/table.xml?content=devices&output=xml&columns=objid,group,device,host&count=2500&id=$StartingID&$auth"
	$restresp = Invoke-RestMethod -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
	$argDevices = $restresp.devices.item

	# Find the Group ID for the given Airgas region
	$subGroupId = ($argGroups | Where {$_.name -eq $subgroup}).objid;

	# Check if site group already exists.
	$siteID = "0";
	if(($argGroups | Where {$_.name -eq $siteName}) -eq $null)
	{
		# If not create it by duplicating the site group template
		$siteNameEncoded = [uri]::EscapeDataString($siteName)
		$url = "https://$PRTGHost/api/duplicateobject.htm?id=$siteTemplateID&name=$siteNameEncoded&targetid=$subGroupID&$auth"
		$request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore;
		$siteID = $request.Headers.Location.Split("=")[1]
	}
	else
	{
		# If so get its ID
		$siteID = ($argGroups | Where {$_.name -eq $siteName}).objid;
	}	

	# Check if device already exists.
	$deviceID = "0";
	if(($argDevices | Where {$_.device -eq $routerName}) -eq $null)
	{
		# If not create it by duplicating the device template
		$routerNameEncoded =  [uri]::EscapeDataString($routerName)
		$url = "https://$PRTGHost/api/duplicateobject.htm?id=$routerTemplateID&name=$routerNameEncoded&targetid=$siteID&$auth"
		$request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore;
		$deviceID = $request.Headers.Location.Split("=")[1]

		# Set the router's IP
		$url = "https://$PRTGHost/api/setobjectproperty.htm?id=$deviceID&name=host&value=$routerIP&$auth" 
		$request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore

		# Add the ping sensor
		$url = "https://$PRTGHost/api/duplicateobject.htm?id=$pingSensorTemplateID&targetid=$deviceID&name=Ping&$auth"
		$request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
		$pingID = $request.Headers.Location.Split("=")[1]

		# Add the snmp sensor
        $url = "https://$PRTGHost/api/duplicateobject.htm?id=$snmpSensorTemplateID&targetid=$deviceID&name=WAN&$auth"
		$request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
		$snmpID = $request.Headers.Location.Split("=")[1]

		# Update the SNMP sensor interface ID
		# Note: PRTG's interfacenumber field has the format number:ifAlias
		# The ifAlias allows PRTG to keep up with interface number changes following a device reboot.
		# It is best to supply both, if not the field should be assigned as number:, e.g. "100:"
		$interfacenumber="";
		if($ifAlias -eq $null)
		{
			$interfacenumber = "$ifIndex`:"
	    }
		else
		{
			$ifAliasEncoded =  [uri]::EscapeDataString($ifAlias)
			$interfacenumber = "$ifIndex`:$ifAliasEncoded"
		}

		$url = "https://$PRTGHost/api/setobjectproperty.htm?id=$snmpID&name=interfacenumber&value=$interfacenumber&$auth" 
        $request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore

		# Resume the group (it is created paused)
		$url = "https://$PRTGHost/api/pause.htm?id=$siteID&action=1&$auth"
        $request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
		
		# Resume the device (it is created paused)
		$url = "https://$PRTGHost/api/pause.htm?id=$deviceID&action=1&$auth"
        $request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore

		# Resume the ping sensor (it is created paused)
		$url = "https://$PRTGHost/api/pause.htm?id=$pingID&action=1&$auth"
        $request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore

		# Resume the snmp sensor (it is created paused)
		$url = "https://$PRTGHost/api/pause.htm?id=$snmpID&action=1&$auth"
        $request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
	}
}