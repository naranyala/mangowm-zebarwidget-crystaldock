import QtQuick 2.15
import QtQuick.Window 2.15
import "src/gui"

Window {
    width: 300
    height: 80
    color: "#202020"
    visible: true
    title: "Waveform QS Test"

    OcwsWaveformQS {
        anchors.fill: parent
        anchors.margins: 10
    }
}
