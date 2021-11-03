using namespace System.Management.Automation

class ValidQueries : IValidateSetValuesGenerator {
    [string[]] GetValidValues() {   
        return (_getQueries).Name
    }
}

function Invoke-AzureSqlCmd {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ArgumentCompleter( {
                param(
                    $commandName,
                    $parameterName,
                    $wordToComplete,
                    $commandAst,
                    $fakeBoundParameters
                )
                return (Get-AzResource -ResourceType "Microsoft.Sql/servers").Name | Where-Object { "$_" -like "$wordToComplete*" }
            })]
        [string]$Server,

        [ArgumentCompleter( {
                param(
                    $commandName,
                    $parameterName,
                    $wordToComplete,
                    $commandAst,
                    $fakeBoundParameters
                )

                $databases = Get-AzResource -ResourceType "Microsoft.Sql/servers/databases"
                $matchingDbs = $databases | Where-Object { "$($_.Name)" -like "*$wordToComplete*" }
        
                if ($fakeBoundParameters["Server"]) {
                    $matchingDbs = $matchingDbs | Where-Object { $_.ParentResource -eq "servers/$($fakeBoundParameters["Server"])" }
                }
                return ($matchingDbs.Name -split '/')[1]
            } )]
        [string]$Database,

        [Parameter(Mandatory)]
        [ValidateSet([ValidQueries])]
        [string]$QueryName
    )
    # this reads the file and demands you provide the parameters required to execute
    # ref - https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters?view=powershell-7.1#dynamic-parameters
    DynamicParam {
        $queryFile = _getQueries | Where-Object { $_.Name -eq $QueryName }
        $queryParameters = _getQueryParameters -QueryFile $queryFile

        if ($null -ne $queryParameters) {
            $attributes = New-Object -Type System.Management.Automation.ParameterAttribute
            $attributes.ParameterSetName = "QueryParameters"
            $attributes.Mandatory = $true
            $attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
            $attributeCollection.Add($attributes)
            $paramDictionary = New-Object -Type System.Management.Automation.RuntimeDefinedParameterDictionary

            foreach ($queryParameter in $queryParameters) {
                $dynParam = New-Object -Type System.Management.Automation.RuntimeDefinedParameter($queryParameter, [string], $attributeCollection)
                $paramDictionary.Add($queryParameter, $dynParam)
            }
      
            return $paramDictionary
        }
    }
    # think of begin as your constructor or init method
    begin {

        # retrieves the query file
        $queryFile = _getQueries | Where-Object { $_.Name -eq $QueryName }
        $accessToken = (Get-AzAccessToken -ResourceUrl "https://database.windows.net").Token  
        
        $invokeSqlCmdParams = @{
            ServerInstance = "$Server.database.windows.net"
            Database       = $Database
            InputFile      = $queryFile
            AccessToken    = $accessToken
        }

        # only adds the variable argument to the splat if there are arguments
        if ($null -ne $paramDictionary.Values) {
            [string[]]$queryParametersValues = $paramDictionary.Values | ForEach-Object { "$($_.Name)=$($_.Value)" }
            $invokeSqlCmdParams.Add("Variable", $queryParametersValues)
        }
    }
    # process is where the looping work is done
    process {
        $result = Invoke-Sqlcmd @invokeSqlCmdParams 
    }
    # end is where you return or write csv files etc
    end {
        return $result
    } 
}

# returns all query files [System.IO.FileInfo[]]
function _getQueries {
    return Get-ChildItem "$PSScriptRoot\Queries\*.sql"
}

# this finds all the parameters in your sql files that are Invoke-SqlCmd friendly
function _getQueryParameters {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$QueryFile
    )
    $group = "parameters"
    $result = Get-Content $QueryFile.FullName `
    | Select-String "\'\$\((?<$group>(\w+))\)\'"

    return ($result.Matches.Groups | Where-Object { $_.Name -eq $group }).Value
}