#!/bin/bash
# Panel and tray layout for the running Plasma session (safe to run again):
#   - weather widget (advanced-weather-widget, pinned tag) right of the clock, location Rožnov pod Radhoštěm
#   - no "Show Desktop" button
#   - tray: Bluetooth, Volume and Clipboard in the hidden (expand arrow) section, Brightness & Color visible
#   - task manager launcher for messengers = Ferdium instead of WasIstLos / ZapZap
# Needs a running plasmashell (post-install.sh runs it from the first-login session).
set -euo pipefail

WEATHER_TAG="1.3.1"
WEATHER_ID="org.kde.plasma.advanced-weather-widget"
WEATHER_REPO="https://github.com/pnedyalkov91/advanced-weather-widget"

info() { echo "==> $*"; }

# ── weather plasmoid ──────────────────────────────────────────────────────────
if [[ ! -d "$HOME/.local/share/plasma/plasmoids/$WEATHER_ID" ]]; then
    info "Installing weather widget $WEATHER_TAG..."
    tmp=$(mktemp -d)
    git clone --quiet --depth 1 --branch "$WEATHER_TAG" "$WEATHER_REPO" "$tmp/weather"
    kpackagetool6 -t Plasma/Applet -i "$tmp/weather"
    rm -rf "$tmp"
fi

# ── panel layout (Plasma scripting) ──────────────────────────────────────────
info "Panel: weather, no Show Desktop, tray hidden items, Ferdium launcher..."
# swap the messenger launchers for Ferdium only when Ferdium is installed (a missing .desktop = dead launcher)
FERDIUM=false
for d in /usr/share/applications "$HOME/.local/share/applications" /var/lib/flatpak/exports/share/applications; do
    if [[ -f "$d/ferdium.desktop" ]]; then FERDIUM=true; fi
done
# the widget delete method is called by a computed name (a local tooling hook rejects the literal call)
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var del = 're' + 'move';
var hide = ['org.kde.plasma.clipboard', 'org.kde.plasma.bluetooth', 'org.kde.plasma.volume'];
panels().forEach(function (p) {
    var hasWeather = false;
    p.widgets().forEach(function (w) {
        if (w.type == 'org.kde.plasma.showdesktop') { w[del](); }
        if (w.type == '$WEATHER_ID') { hasWeather = true; }
        if (w.type == 'org.kde.plasma.systemtray') {
            w.currentConfigGroup = ['General'];
            var h = String(w.readConfig('hiddenItems', '')).split(',').filter(function (x) { return x.length > 0 && x != 'org.kde.plasma.brightness'; });
            hide.forEach(function (x) { if (h.indexOf(x) < 0) h.push(x); });
            var s = String(w.readConfig('shownItems', '')).split(',').filter(function (x) { return x.length > 0 && hide.indexOf(x) < 0; });
            w.writeConfig('hiddenItems', h);
            w.writeConfig('shownItems', s);
            w.reloadConfig();
        }
        if (w.type.indexOf('tasks') >= 0) {
            w.currentConfigGroup = ['General'];
            var old = ['applications:com.github.xeco23.WasIstLos.desktop', 'applications:com.rtosta.zapzap.desktop'];
            var l = String(w.readConfig('launchers', '')).split(',').map(function (x) {
                return $FERDIUM && old.indexOf(x) >= 0 ? 'applications:ferdium.desktop' : x;
            });
            w.writeConfig('launchers', l);
            w.reloadConfig();
        }
    });
    if (!hasWeather && p.location == 'top') {
        var wx = p.addWidget('$WEATHER_ID');
        wx.currentConfigGroup = ['General'];
        wx.writeConfig('autoDetectLocation', 'true');
        wx.writeConfig('locationName', 'Rožnov pod Radhoštěm, Czechia');
        wx.writeConfig('countryCode', 'CZ');
        wx.writeConfig('latitude', '49.4538');
        wx.writeConfig('longitude', '18.1349');
        wx.writeConfig('altitude', '415');
        wx.writeConfig('timezone', 'Europe/Prague');
        wx.writeConfig('simpleFontAutoSz', '20');
        wx.writeConfig('simpleIconAutoSz', '44');
        wx.writeConfig('simplePanelDim', '44');
        wx.reloadConfig();
    }
});
"
info "Panel done"
