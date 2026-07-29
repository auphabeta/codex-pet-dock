# Native UI shell fixture

`NativeWinFormsShell.cs` is a controlled Windows Forms baseline used to decide
whether moving the long-lived PowerShell UI host into C# is worth the migration
risk. It creates a real tray icon, message loop, and timer, then exits after the
requested number of seconds.

On the reference Windows 11 machine, three samples at 3, 8, and 13 seconds were
stable at:

| Metric | Result |
|---|---:|
| Working set | 19.1 MB |
| Private memory | 20.4 MB |
| CPU time after 13 seconds | 0.078 s |
| Threads | 6 |
| Handles | 242 |

This is a framework baseline, not a promise for the finished product. Pet
tracking, UI Automation, images, themes, the detail card, localization, and
configuration will add memory. The fixture exists to make the native-UI
migration decision measurable instead of speculative.
