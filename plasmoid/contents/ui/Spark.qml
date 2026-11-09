import QtQuick

Canvas {
    id: spark

    property var values: []
    property int maxPoints: 60
    property string strokeColor: "#0A84FF"
    property string fillTop: "rgba(10,132,255,0.26)"
    property string fillBottom: "rgba(10,132,255,0)"

    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();

        var n = values.length;
        if (n < 2 || width <= 0 || height <= 0) return;

        var w = width;
        var h = height;
        var pad = 2;
        var step = w / (maxPoints - 1);
        var x0 = w - (n - 1) * step;
        var pts = [];

        for (var i = 0; i < n; i++) {
            var v = Math.max(0, Math.min(100, Number(values[i]) || 0));
            pts.push([x0 + i * step, pad + (1 - v / 100) * (h - pad * 2)]);
        }

        var first = pts[0];
        var last = pts[pts.length - 1];

        ctx.beginPath();
        ctx.moveTo(first[0], first[1]);
        for (var j = 1; j < pts.length - 1; j++) {
            var xc = (pts[j][0] + pts[j + 1][0]) / 2;
            var yc = (pts[j][1] + pts[j + 1][1]) / 2;
            ctx.quadraticCurveTo(pts[j][0], pts[j][1], xc, yc);
        }
        ctx.lineTo(last[0], last[1]);
        ctx.lineTo(last[0], h);
        ctx.lineTo(first[0], h);
        ctx.closePath();

        var grad = ctx.createLinearGradient(0, 0, 0, h);
        grad.addColorStop(0, fillTop);
        grad.addColorStop(1, fillBottom);
        ctx.fillStyle = grad;
        ctx.fill();

        ctx.beginPath();
        ctx.moveTo(first[0], first[1]);
        for (var k = 1; k < pts.length - 1; k++) {
            var xc2 = (pts[k][0] + pts[k + 1][0]) / 2;
            var yc2 = (pts[k][1] + pts[k + 1][1]) / 2;
            ctx.quadraticCurveTo(pts[k][0], pts[k][1], xc2, yc2);
        }
        ctx.lineTo(last[0], last[1]);
        ctx.strokeStyle = strokeColor;
        ctx.lineWidth = 1.6;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.stroke();
    }
}
