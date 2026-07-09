// OcwsWaveformQS.qml — Quickshell widget for ocws-waveform-qs
//
// Polls $XDG_RUNTIME_DIR/ocws-waveform-qs.json (written by the C backend
// `ocws-waveform-qs`) and renders an animated line strip representing the
// system's current audio stream buffer.
//
// Usage: drop this file into your Quickshell config dir (e.g.
// ~/.config/quickshell/) and instantiate it in your bar, e.g.
//   Quickshell.Widgets.Bar { children: [ OcwsWaveformQS {} ] }

import QtQuick 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1

Rectangle {
    id: root
    width: 200
    height: 40

    property var waveform: []
    property string waveformStyle: "line"
    property string themeColor: "#89b4fa" // Fallback color
    property string themeBgColor: "#1e1e2e" // Fallback bg
    property real themeBgAlpha: 0.85 // Dynamic transparency

    color: Qt.rgba(
        parseInt(themeBgColor.substring(1, 3), 16) / 255,
        parseInt(themeBgColor.substring(3, 5), 16) / 255,
        parseInt(themeBgColor.substring(5, 7), 16) / 255,
        themeBgAlpha
    )

    readonly property string statePath:
        StandardPaths.writableLocation(StandardPaths.RuntimeLocation)
        + "/ocws-waveform-qs.json"

    // Load adaptive color from OCWS CSS
    function loadAdaptiveColor() {
        var cssPath = StandardPaths.writableLocation(StandardPaths.HomeLocation) 
                      + "/.config/ocws/css/theme.css";
        var x = new XMLHttpRequest();
        x.open("GET", "file://" + cssPath, false);
        x.send();
        if (x.status === 200) {
            var txt = x.responseText;
            var matchAccent = txt.match(/@define-color\s+accent\s+(#[0-9a-fA-F]+)/);
            if (matchAccent && matchAccent[1]) root.themeColor = matchAccent[1];
            
            var matchBg = txt.match(/@define-color\s+theme_bg_color\s+(#[0-9a-fA-F]+)/);
            if (matchBg && matchBg[1]) root.themeBgColor = matchBg[1];

            var matchAlpha = txt.match(/@define-color\s+widget_alpha\s+([0-9.]+)/);
            if (matchAlpha && matchAlpha[1]) root.themeBgAlpha = parseFloat(matchAlpha[1]);
        }
    }

    Component.onCompleted: {
        loadAdaptiveColor();
    }

    function loadState() {
        var x = new XMLHttpRequest();
        x.open("GET", "file://" + root.statePath, false);
        x.send();
        if (x.status === 200) {
            try {
                var j = JSON.parse(x.responseText);
                if (j.data) {
                    if (j.style) root.waveformStyle = j.style;
                    root.waveform = j.data;
                    canvas.requestPaint();
                }
            } catch (e) { }
        }
    }

    // ~60 FPS update timer
    Timer {
        id: timer
        interval: 16
        running: true
        repeat: true
        onTriggered: loadState()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            
            if (root.waveform.length === 0) return;
            
            ctx.strokeStyle = root.themeColor;
            ctx.fillStyle = root.themeColor;
            ctx.lineWidth = 2;
            ctx.lineJoin = "round";
            ctx.beginPath();
            
            var step = width / (root.waveform.length - 1);
            var mid = height / 2;
            
            if (root.waveformStyle === "line") {
                for (var i = 0; i < root.waveform.length; i++) {
                    var x = i * step;
                    var y = mid - (root.waveform[i] * mid * 1.5); 
                    if (i === 0) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                }
                ctx.stroke();
            } 
            else if (root.waveformStyle === "filled") {
                ctx.moveTo(0, height);
                for (var i = 0; i < root.waveform.length; i++) {
                    var x = i * step;
                    var y = mid - (root.waveform[i] * mid * 1.5); 
                    ctx.lineTo(x, y);
                }
                ctx.lineTo(width, height);
                ctx.closePath();
                ctx.fill();
            }
            else if (root.waveformStyle === "mirrored") {
                for (var i = 0; i < root.waveform.length; i++) {
                    var x = i * step;
                    var amp = root.waveform[i] * mid * 1.5;
                    ctx.moveTo(x, mid + amp);
                    ctx.lineTo(x, mid - amp);
                }
                ctx.stroke();
            }
            else if (root.waveformStyle === "dots") {
                for (var i = 0; i < root.waveform.length; i++) {
                    var x = i * step;
                    var y = mid - (root.waveform[i] * mid * 1.5); 
                    ctx.moveTo(x, y);
                    ctx.arc(x, y, 2, 0, 2 * Math.PI);
                }
                ctx.fill();
            }
        }
    }
}
