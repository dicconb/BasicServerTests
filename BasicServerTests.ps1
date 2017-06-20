$tests = @()

# Test definitions
$tests += New-Object PsObject -property @{
    Name="Windows_Service_Running"
    Description="Windws service ""Jenkins"" should be running"
    TestScript={
        $servicename = "Jenkins"
        Try {$service = Get-Service -Name $servicename -ea Stop}
        Catch {"FAIL: Could not find Windows service $($servicename)";Return}
        if ($service.Status -eq "Running") {"PASS";Return}
        Else {"FAIL: Service is in state $($service.Status)";Return}
    }
}
$tests += New-Object PsObject -property @{
    Name="TCP_8080_open_loopback"
    Description="TCP port 8080 should be open on local loopback interface"
    TestScript={
        $TCPclient = New-object System.Net.Sockets.TcpClient
        $loopback = [System.Net.IPAddress]::Loopback.IPAddressToString
        Try {
            $TCPclient.Connect($loopback,"8080")
            "PASS";Return
        }
        Catch {
            "FAIL: $_";Return
        }        
    }
}
$tests += New-Object PsObject -property @{
    Name="TCP_8080_closed_primaryIP"
    Description="TCP port 8080 should not be open on primary interface"
    TestScript={
        $DNSaddress = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) | ?{$_.Addressfamily -eq "InterNetwork"} | %{$_.IPAddressToString} | select -first 1
        $TCPclient = New-object System.Net.Sockets.TcpClient
        Try {
            $port = 8080
            $TCPclient.Connect($DNSaddress,$port)
            "FAIL: Connected successfully on port ""$($DNSaddress):$($port)""";Return
        }
        Catch {
            "PASS";Return    
        }        
    }
}
$tests += New-Object PsObject -property @{
    Name="SSL_Certificate_Valid"
    Description="When connecting to https://server.fqdn/login should receive a trusted SSL certificate"
    TestScript={
        $url = "https://$($env:computername).$($env:USERDNSDOMAIN)/login"
        #$url = "https://127.0.0.1/login"
        Try {
            $result = invoke-webrequest -Uri $url -Method HEAD
            if ($result.StatusCode -eq 200) {
                "PASS";Return
            }
        }
        Catch {
            if ($_.Exception.message -match "Could not establish trust relationship") {"FAIL: $($_.exception.message)";Return}
            Else {Throw $_}
        }
    }
}
$tests += New-Object PsObject -property @{
    Name="Login_Page_Redirect"
    Description="When browsing to https://localhost/ should be redirected to login page"
    TestScript={
        $url = "https://$($env:computername).$($env:USERDNSDOMAIN)/"
        $request = [System.Net.WebRequest]::Create($url)
        Try {
            [System.Net.WebResponse]$response = $request.GetResponse()
        } Catch [System.Net.WebException] {
            $sr = New-Object System.IO.Streamreader($_.Exception.response.GetResponseStream())
            $content = $sr.ReadToEnd()
            if ($content -match "<html><head><meta http-equiv='refresh' content='1;url=/login\?") {
                "PASS";Return
            }
            Else {
                "FAIL: No meta refresh tag in 403 response`n$($content)";Return
            }
        }
    }
}
$tests += New-Object PsObject -property @{
    Name="Login_Page_Content"
    Description="Login page should include expected HTML content"
    TestScript={
        $url = "https://$($env:computername).$($env:USERDNSDOMAIN)/login"
        Try {
            $result = invoke-webrequest -Uri $url -Method GET
            if ($result.Content -match "(?smi)<title>Jenkins</title>.*<td>User:") {
                "PASS";Return
            }
            Else {
                "FAIL: Unexpected content in response`n`n$([string]::join('',$result.content[0..256]))";Return
            }
        }
        Catch {
            if ($_.Exception.message -match "Could not establish trust relationship") {"FAIL: $($_.exception.message)";Return}
            Else {Throw $_}
        }
    }
}

# Test runner

$testsrun = @()
$testspassed = @()
$testsfailed = @()
$starttime = get-date

Write-Host "Beinning test run...`n"
foreach ($test in $tests) {
    $testsrun += $testname
    Try {
        $teststart = get-date
        $result = & $test.testscript
        $testtime = (get-date) - $teststart
        if ($result -match "^PASS") {
            $testspassed += $test
            Write-Host -foregroundcolor Green "PASS: $($test.name) ($($testsrun.count)/$($tests.count)) ($($testtime.totalseconds) seconds)"
        }
        elseif ($result -match "^FAIL") {
            $testsfailed += $test
            Write-Host -Foregroundcolor Red "FAILED!: $($test.name) ($($testsrun.count)/$($tests.count))"
            Write-Host -ForegroundColor Red "`tTest description: $($test.Description)"
            Write-Host -ForegroundColor Red "`tTest result:`n`t$($result)"
        }
        else {
            Write-host -ForegroundColor Red "Unexpected result from test $($test.Name) ($($testsrun.count)/$($tests.count)):"
            Write-Host $result
        }
    }
    Catch {
        Throw "Unhandled error running test $($test.Name)!`n$_"
    }

}
$runtime = (get-date) - ($starttime)
Write-host "`nRan $($testsrun.count) of $($tests.count) tests in $($runtime.TotalSeconds) seconds"
if ($testspassed.count -eq $tests.Count) {Write-Host -ForegroundColor Green "All tests passed!"}
Elseif ($testsfailed.count -gt 0) {Write-Host -ForegroundColor Red "$($testsfailed.count) of $($tests.count) tests failed!"}
Else {$unknowncount = $tests.count - ($testspassed.count + $testsfailed.count);Write-Warning "$($unknowncount) tests returned an unknown result"}

Read-Host -Prompt "Press enter to exit.." | Out-Null
