import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property string endpoint: (Plasmoid.configuration.endpoint || "http://127.0.0.1:8787").replace(/\/+$/, "")
    readonly property int refreshInterval: Math.max(500, Plasmoid.configuration.interval || 1000)

    property bool online: false
    property bool hasData: false
    property bool busy: false

    property string host: ""
    property real cpu: 0
    property real cpuTemp: -1
    property real ram: 0
    property real ramUsed: 0
    property real ramTotal: 0
    property bool hasGpu: false
    property real gpu: 0
    property real gpuTemp: -1
    property real vramUsed: 0
    property real vramTotal: 0
    property var cpuHistory: []

    function gb(bytes) {
        var b = Number(bytes);
        if (!b || b <= 0) {
            return "—";
        }
        var g = b / 1073741824;
        return g >= 10
            ? Math.round(g) + " GB"
            : g.toFixed(1).replace(".", ",") + " GB";
    }

    function apply(data) {
        if (!data || !data.cpu) {
            online = false;
            return;
        }

        online = true;
        hasData = true;
        host = data.host || "";

        cpu = Number(data.cpu.usage) || 0;
        cpuTemp = (typeof data.cpu.temp === "number") ? data.cpu.temp : -1;

        ramTotal = Number(data.ram && data.ram.total) || 0;
        ramUsed = (data.ram && typeof data.ram.used === "number")
            ? data.ram.used
            : Math.max(0, ramTotal - (Number(data.ram && data.ram.available) || 0));
        ram = (data.ram && typeof data.ram.percent === "number")
            ? data.ram.percent
            : (ramTotal > 0 ? (ramUsed / ramTotal) * 100 : 0);

        var gpuData = data.gpu;
        hasGpu = !!(gpuData && typeof gpuData.usage === "number");
        gpu = hasGpu ? gpuData.usage : 0;
        gpuTemp = (hasGpu && typeof gpuData.temp === "number") ? gpuData.temp : -1;
        vramTotal = hasGpu ? (Number(gpuData.vram_total) || 0) : 0;
        vramUsed = hasGpu ? (Number(gpuData.vram_used) || 0) : 0;

        var history = cpuHistory.slice();
        if (history.length === 0) {
            for (var i = 0; i < 59; i++) {
                history.push(cpu);
            }
        }
        history.push(cpu);
        while (history.length > 60) {
            history.shift();
        }
        cpuHistory = history;
    }

    function poll() {
        if (busy) {
            return;
        }
        busy = true;

        var xhr = new XMLHttpRequest();
        xhr.open("GET", endpoint + "/api/stats?t=" + Date.now());
        xhr.timeout = 4000;

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            root.busy = false;
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    root.apply(JSON.parse(xhr.responseText));
                } catch (error) {
                    root.online = false;
                }
            } else {
                root.online = false;
            }
        };
        xhr.ontimeout = function () {
            root.busy = false;
            root.online = false;
        };
        xhr.onerror = function () {
            root.busy = false;
            root.online = false;
        };

        xhr.send();
    }

    function openDashboard() {
        Qt.openUrlExternally(endpoint);
    }

    Timer {
        interval: root.refreshInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    fullRepresentation: Item {
        id: content

        implicitWidth: 352
        implicitHeight: 204
        Layout.preferredWidth: 352
        Layout.preferredHeight: 204
        Layout.minimumWidth: 340
        Layout.minimumHeight: 196

        property bool hovered: false
        property bool dark: {
            var c = Kirigami.Theme.backgroundColor;
            return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
        }

        readonly property string uiFont: "Inter"
        readonly property color fg: Kirigami.Theme.textColor
        readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.42)
        readonly property color track: Qt.rgba(fg.r, fg.g, fg.b, 0.11)
        readonly property string trackCss: dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.09)"
        readonly property color ramColor: dark ? "#BF5AF2" : "#AF52DE"
        readonly property color gpuColor: dark ? "#30D158" : "#248A3D"
        readonly property color borderColor: hovered
            ? (dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16))
            : (dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.07))

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: content.dark ? "#E6111114" : "#F2F6F6F8"
            border.width: 1
            border.color: content.borderColor
        }

        Rectangle {
            anchors.fill: parent
            radius: 20
            color: "transparent"
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.rgba(1, 1, 1, content.dark ? 0.07 : 0.75)
                }
                GradientStop {
                    position: 0.65
                    color: Qt.rgba(1, 1, 1, 0)
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    width: 6
                    height: 6
                    radius: 3
                    color: root.online ? "#30D158" : "#FF9F0A"
                    opacity: root.online ? 1 : 0.9
                }

                Text {
                    text: "Monitor"
                    color: content.fg
                    font.family: content.uiFont
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                Text {
                    Layout.maximumWidth: 170
                    text: root.online
                        ? root.host + (root.cpuTemp >= 0 ? " · " + Math.round(root.cpuTemp) + " °C" : "")
                        : (root.hasData ? root.host + " · offline" : "sem conexão")
                    color: root.online ? content.faint : "#FF9F0A"
                    font.family: content.uiFont
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                Item {
                    Layout.preferredWidth: 92
                    Layout.preferredHeight: 92
                    Layout.alignment: Qt.AlignVCenter

                    Ring {
                        anchors.fill: parent
                        value: root.hasData ? root.cpu : 0
                        thickness: 8
                        trackColor: content.trackCss
                        colorA: root.cpu >= 88 ? "#FFD60A" : "#64D2FF"
                        colorB: root.cpu >= 88 ? "#FF453A" : "#0A84FF"
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 0

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.hasData ? Math.round(root.cpu) : "—"
                            color: content.fg
                            font.family: content.uiFont
                            font.pixelSize: 26
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "CPU"
                            color: content.faint
                            font.family: content.uiFont
                            font.pixelSize: 9
                            font.letterSpacing: 0.4
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "RAM"
                                color: content.faint
                                font.family: content.uiFont
                                font.pixelSize: 10
                                font.letterSpacing: 0.3
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.hasData ? Math.round(root.ram) + "%" : "—"
                                color: content.fg
                                font.family: content.uiFont
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                        }

                        Meter {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            value: root.hasData ? root.ram : 0
                            color: content.ramColor
                            trackColor: content.track
                        }

                        Text {
                            text: root.hasData
                                ? root.gb(root.ramUsed) + " de " + root.gb(root.ramTotal)
                                : "aguardando"
                            color: content.faint
                            font.family: content.uiFont
                            font.pixelSize: 9
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: "GPU"
                                color: content.faint
                                font.family: content.uiFont
                                font.pixelSize: 10
                                font.letterSpacing: 0.3
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.hasData ? (root.hasGpu ? Math.round(root.gpu) + "%" : "—") : "—"
                                color: content.fg
                                font.family: content.uiFont
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                        }

                        Meter {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            value: root.hasGpu ? root.gpu : 0
                            color: content.gpuColor
                            trackColor: content.track
                        }

                        Text {
                            text: !root.hasData
                                ? "aguardando"
                                : (root.hasGpu
                                    ? root.gb(root.vramUsed) + " de " + root.gb(root.vramTotal)
                                      + (root.gpuTemp >= 0 ? " · " + Math.round(root.gpuTemp) + " °C" : "")
                                    : "não detectada")
                            color: content.faint
                            font.family: content.uiFont
                            font.pixelSize: 9
                        }
                    }
                }
            }

            Spark {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                values: root.cpuHistory
                strokeColor: "#0A84FF"
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: content.hovered = true
            onExited: content.hovered = false
            onClicked: root.openDashboard()
        }
    }
}
