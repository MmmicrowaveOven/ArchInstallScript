In order to use this script, you will need to do 1 simple step prior to downloading the script and running. Connect to the internet. This can be done by:

Connecting to ethernet. Verify connectivity with `ping www.linux.com` to verify DNS and routing.
Connecting to wi-fi. This can be done using `iwctl`.
`iwctl`
From iwctl interactive prompt:
`station list`
`station [station name] scan`
`station [station name] connect [ssid]`
Enter wireless password.
Verify connectivity with `ping www.linux.com` to verify DNS and routing.

After this run the script.

Download script and output to "script.sh" in current directory:
`curl -sL https://raw.githubusercontent.com/MmmicrowaveOven/ArchInstallScript/main/archinstallscript.sh -o script.sh`
Allow execute permissions for the script:
`chmod +x script.sh`
Run the script:
`./script.sh`

One liner command:
`curl -sL https://raw.githubusercontent.com/MmmicrowaveOven/ArchInstallScript/main/archinstallscript.sh -o script.sh && chmod +x script.sh && ./script.sh`
