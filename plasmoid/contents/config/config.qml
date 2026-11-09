import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_endpoint: endpointField.text
    property alias cfg_interval: intervalSpin.value

    QQC2.TextField {
        id: endpointField
        Kirigami.FormData.label: "Servidor:"
        placeholderText: "http://127.0.0.1:8787"
        Layout.fillWidth: true
    }

    QQC2.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: "Atualizar a cada (ms):"
        from: 500
        to: 10000
        stepSize: 250
        editable: true
    }

    QQC2.Label {
        Layout.fillWidth: true
        Layout.maximumWidth: 320
        wrapMode: Text.WordWrap
        opacity: 0.65
        font: Kirigami.Theme.smallFont
        text: "O widget consulta o server.py em execução. Clique nele para abrir o painel completo."
    }
}
