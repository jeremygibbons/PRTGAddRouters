#
# AddRouters.ps1
#
# Inspired by https://thedomainiown.wordpress.com/prtg-related/prtg-script-powershell-admin-module/
#

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

############################
# INSTANCE SPECIFIC VARIABLES
# MUST BE UPDATED PRIOR TO EXECUTING THIS SCRIPT
############################
$auth = "username=ADM_jeremy.gibbons&passhash=1144530515"
$PRTGHost = "172.31.230.79"

$siteTemplateID = "10019";
$routerTemplateID = "10020";
$pingSensorTemplateID = "2579";
$snmpSensorTemplateID = "2578";

#Parent group id for Airgas sites
$StartingID=10023

#############################
# END INSTANCE SPECIFIC VARIABLES
#############################

#Retrieve list of groups in the airgas group
$url = "https://$PRTGHost/api/table.xml?content=groups&output=xml&columns=objid,group,name,parentid&count=2500&id=$StartingID&$auth"
$restresp = Invoke-RestMethod -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
$argGroups = $restresp.groups.item

#Retrieve list of devices in the airgas group
$url = "https://$PRTGHost/api/table.xml?content=devices&output=xml&columns=objid,group,device,host&count=2500&id=$StartingID&$auth"
$restresp = Invoke-RestMethod -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
$argDevices = $restresp.devices.item

#Find the group id for a given airgas region
($argGroups | Where {$_.name -eq "East"}).objid

$csvlines = import-csv c:\temp\arg.csv;
foreach($line in $csvlines)
{
	$routerName=$line.RouterName;
	$siteName=$line.SiteName;
	$subgroup=$line.SubGroup;
	$routerIP=$line.IPAddr;
	$ifIndex=$line.IfIndex;
	$ifAlias=$line.IfAlias;

	#Find the Group ID for a given Airgas region
	$subGroupId = ($argGroups | Where {$_.name -eq $subgroup}).objid;

	# Check if site group already exists.
	$siteID = "0";
	if(($argGroups | Where {$_.name -eq $siteName}) -eq $null)
	{
		# If not create it by duplicating the site group template
		$url = "http://$PRTGHost/api/duplicateobject.htm?id=$siteTemplateID&name=$siteName&targetid=$subGroupID&$auth"
		$request = Invoke-RestMethod -Uri $url -MaximumRedirection 0 -ErrorAction Ignore;
		$siteID = $request.Headers.Location.Split("=")[1]
	}
	else
	{
		# If so get its ID
		$siteID = ($argGroups | Where {$_.name -eq $siteName}).objid;
	}	

	#Check if device already exists.
	$deviceID = "0";
	if(($argDevices | Where {$_.device -eq $routerName}) -eq $null)
	{
		# If not create it by duplicating the device template
		$url = "http://$PRTGHost/api/duplicateobject.htm?id=$routerTemplateID&name=$routerName&targetid=$siteID&$auth"
		$request = Invoke-RestMethod -Uri $url -MaximumRedirection 0 -ErrorAction Ignore;
		$deviceID = $request.Headers.Location.Split("=")[1]

		#Set the router's IP
		$url = "http://$PRTGHost/api/setobjectproperty.htm?id=$deviceID&name=host&value=$routerIP&$auth" 
		$request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore

		# Add the ping sensor
		$url = "http://$PRTGHost/api/duplicateobject.htm?id=$pingSensorTemplateID&targetid=$deviceID&$auth"
		$request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
		$pingID = $request.Headers.Location.Split("=")[1]

		#Resume the ping sensor (it is created paused)
		$url = "http://$PRTGHost/api/pause.htm?id=$pingID&action=1&$auth"
        $request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore

		# Add the snmp sensor
        $url = "http://$PRTGHost/api/duplicateobject.htm?id=$snmpSensorTemplateID&targetid=$deviceID&$auth"
		$request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
		$snmpID = $request.Headers.Location.Split("=")[1]

		# Update the SNMP sensor interface ID
		# Note: PRTG's interfacenumber field has the format number:ifAlias
		# The ifAlias allows PRTG to keep up with interface number changes following a device reboot.
		# It is best to supply both, if not the field should be assigned as number:, e.g. "100:"
		$interfacenumber="";
		if($ifAlias -eq $null)
		{
			$interfacenumber = "$IfIndex`:"
	    }
		else
		{
			$interfacenumber = "$IfIndex`:$IfAlias"
		}
		$url = "http://$PRTGHost/api/setobjectproperty.htm?id=$snmpID&name=interfacenumber&value=$interfacenumber&$auth" 
        $request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore

		#Resume the snmp sensor (it is created paused)
		$url = "http://$PRTGHost/api/pause.htm?id=$snmpID&action=1&$auth"
        $request = Invoke-WebRequest -Uri $url -MaximumRedirection 0 -ErrorAction Ignore
	}
}