# YASB-Smart-Hide

An AutoHotkey script that automatically hides and restores the YASB bar under specific conditions.

## How To Use

### 1. Configure YASB

Write this in your `YASB config.yaml` and save it:

```yaml
window_flags:
  always_on_top: true
  windows_app_bar: false
  hide_on_fullscreen: true
  hide_on_maximized: false
```
             
3) double click YASB_SmartHide.exe to run it, it will run in the background and will automatically detect if YASB is running or not.

#AutoRunAtStartup
1) Press Win+R and write shell:startup then press enter key.
2) This will open the personal Startup folder in Windows, where you can add or remove shortcuts to programs that run automatically when you sign in.
3) copy/paste the YASB_SmartHide.exe there.
