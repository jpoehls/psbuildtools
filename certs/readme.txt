These certs are used for signing ClickOnce deployments.

They were created by running the following commands.

  makecert.exe -sv COMPANY_Key.pvk -n "CN=COMPANY" c:\COMPANY_Key.cer
  pvk2pfx.exe -pvk COMPANY_Key.pvk -spc COMPANY_Key.cer -pfx COMPANY_Key.pfx

makecert.exe and pvk2pfx.exe are tools in the Windows SDK folder.

You should end up with these files:
  * COMPANY_Key.cer
  * COMPANY_Key.pfx
  * COMPANY_Key.pvk