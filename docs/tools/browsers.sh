echo "=== all packages (browser-ish)"; pm list packages | grep -iE "browser|chrome|firefox|fenix|webview|edge|brave|opera|vivaldi|duckduckgo|kiwi|bromite|cromite"
echo "=== who handles https VIEW"; cmd package resolve-activity --brief -a android.intent.action.VIEW -d https://example.com 2>&1 | head -5
echo "=== webview provider"; dumpsys webviewupdate 2>&1 | grep -iE "Current WebView|package|version" | head -5
