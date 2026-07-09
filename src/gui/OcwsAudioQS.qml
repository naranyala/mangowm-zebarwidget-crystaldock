// OcwsAudioQS.qml — Quickshell widget for ocws-speaker-qs
//
// Polls $XDG_RUNTIME_DIR/ocws-speaker-qs.json (written by the C backend
// `ocws-speaker-qs`) and renders two speaker-like visuals that pulse with
// the left/right audio levels, plus the active playback stream name.
//
// Usage: drop this file into your Quickshell config dir (e.g.
// ~/.config/quickshell/) and instantiate it in your bar, e.g.
//   Quickshell.Widgets.Bar { children: [ OcwsAudioQS {} ] }

import QtQuick 2.15
import QtQuick.Layouts 1.15
import Qt.labs.platform 1.1

Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    property real lvlL: 0
    property real lvlR: 0
    property string active: ""

    readonly property string statePath:
        StandardPaths.writableLocation(StandardPaths.RuntimeLocation)
        + "/ocws-speaker-qs.json"

    function loadState() {
        var x = new XMLHttpRequest();
        x.open("GET", "file://" + root.statePath, false);
        x.send();
        if (x.status === 200) {
            try {
                var j = JSON.parse(x.responseText);
                root.lvlL = j.l || 0;
                root.lvlR = j.r || 0;
                root.active = j.active || "";
            } catch (e) { }
        }
    }

    Timer {
        id: timer
        interval: 33
        running: true
        repeat: true
        onTriggered: { loadState(); canvas.requestPaint(); }
    }

    RowLayout {
        id: row
        spacing: 6

        Canvas {
            id: canvas
            implicitWidth: 84
            implicitHeight: 30
            width: implicitWidth
            height: implicitHeight
            onPaint: {
                var ctx = canvas.getContext("2d");
                var w = canvas.width, h = canvas.height;
                ctx.clearRect(0, 0, w, h);
                var R = Math.min(w, h) * 0.34;
                var t = Date.now() / 1000;
                drawSpeaker(ctx, w * 0.28, h * 0.5, R, root.lvlL, t);
                drawSpeaker(ctx, w * 0.72, h * 0.5, R, root.lvlR, t + 1.7);
            }
        }

        Text {
            id: label
            text: root.active
            color: "#cfd8e6"
            font.pixelSize: 12
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.maximumWidth: 220
            visible: root.active !== ""
        }
    }

    function drawSpeaker(ctx, cx, cy, R, lvl, t) {
        var idle = 0.12 * (0.5 + 0.5 * Math.sin(t * 1.5));
        var a = lvl < idle ? idle : lvl;

        // hue-shifting tint (blue -> magenta)
        var hue = (t * 40) % 360;
        var ring = Qt.hsla((hue % 360) / 360, 0.7, 0.6, 1);
        var cone = Qt.hsla((hue + 180) % 360 / 360, 0.3, 0.95, 1);

        ctx.lineWidth = Math.max(1, R * 0.06);
        ctx.strokeStyle = ring;
        ctx.globalAlpha = 0.4 + a;
        ctx.beginPath();
        ctx.arc(cx, cy, R * 0.95, 0, 2 * Math.PI);
        ctx.stroke();

        ctx.globalAlpha = 0.5 + a;
        ctx.fillStyle = cone;
        ctx.beginPath();
        ctx.arc(cx, cy, R * (0.25 + 0.55 * a), 0, 2 * Math.PI);
        ctx.fill();

        ctx.globalAlpha = 1;
        ctx.fillStyle = cone;
        ctx.beginPath();
        ctx.arc(cx, cy, R * 0.10, 0, 2 * Math.PI);
        ctx.fill();

        for (var i = 0; i < 3; i++) {
            var ph = (t * 0.6 + i * 0.33) % 1;
            var rr = R * (0.4 + ph * (0.8 + a * 1.6));
            ctx.globalAlpha = (1 - ph) * 0.6 * (0.3 + a);
            ctx.strokeStyle = ring;
            ctx.beginPath();
            ctx.arc(cx, cy, rr, 0, 2 * Math.PI);
            ctx.stroke();
        }
        ctx.globalAlpha = 1;
    }
}
