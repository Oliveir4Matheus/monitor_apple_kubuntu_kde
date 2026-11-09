import QtQuick

Item {
    id: ring

    property real value: 0
    property real thickness: 8
    property string colorA: "#64D2FF"
    property string colorB: "#0A84FF"
    property string trackColor: "rgba(255,255,255,0.09)"

    property real shown: Math.max(0, Math.min(100, Number(value) || 0))
    Behavior on shown {
        NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
    }

    onShownChanged: canvas.requestPaint()
    onColorAChanged: canvas.requestPaint()
    onColorBChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var w = width, h = height;
            var cx = w / 2, cy = h / 2;
            var r = Math.min(w, h) / 2 - ring.thickness / 2 - 1;
            var start = -Math.PI / 2;

            ctx.lineCap = "round";
            ctx.lineWidth = ring.thickness;
            ctx.beginPath();
            ctx.arc(cx, cy, r, 0, Math.PI * 2);
            ctx.strokeStyle = ring.trackColor;
            ctx.stroke();

            if (ring.shown <= 0.4) return;
            var end = start + Math.PI * 2 * (ring.shown / 100);

            ctx.globalAlpha = 0.16;
            ctx.beginPath();
            ctx.arc(cx, cy, r, start, end);
            ctx.lineWidth = ring.thickness + 7;
            ctx.strokeStyle = ring.colorB;
            ctx.stroke();
            ctx.globalAlpha = 1;

            var grad = ctx.createLinearGradient(0, 0, w, h);
            grad.addColorStop(0, ring.colorA);
            grad.addColorStop(1, ring.colorB);

            ctx.beginPath();
            ctx.arc(cx, cy, r, start, end);
            ctx.lineWidth = ring.thickness;
            ctx.strokeStyle = grad;
            ctx.stroke();
        }
    }
}
