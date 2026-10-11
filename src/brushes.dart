import 'dart:math' show pi;

import 'package:dcanvas/CanvasRenderingContext.dart' show Context2D, CSSColor;
import 'package:drawlite_dart/drawlite.dart'
    show Color;

import './app-state.dart';

List<String> brushNames = [
    "Marker",
    "Calligraphy pen",
    "Oil brush",
    "Watercolor",
    "Pixel pen",
    "Pencil",
    "Eraser",
    "Crayon",
    "Spray can",
    "Fill bucket"
];

List<Color> brushColors = [];
void initBrushColors() {
    brushColors = [
        dl.color(255),
        dl.color(195),
        dl.color(88),
        dl.color(0),
        dl.color(136, 0, 27),
        dl.color(236, 28, 36),
        dl.color(255, 127, 39),
        dl.color(255, 202, 24),
        dl.color(253, 236, 166),
        dl.color(255, 242, 0),
        dl.color(196, 255, 14),
        dl.color(14, 209, 69),
        dl.color(140, 255, 251),
        dl.color(0, 168, 243),
        dl.color(63, 72, 204),
        dl.color(184, 61, 186),
        dl.color(255, 174, 200),
        dl.color(185, 122, 86)
    ];
}

class BrushStroke {
    late Color color;
    late double weight;
    // 0-100
    late double opacity;
    late int brushId;
    List<double> points = [];
    // spray can dots are generated once per point so they don't flicker every frame
    List<double> sprayDots = [];

    BrushStroke(this.color, this.weight, this.opacity, this.brushId);

    void addPoint(double x, double y) {
        points.add(x);
        points.add(y);

        if (brushId == 8) {
            final r = weight / 2;
            for (int i = 0; i < 10; i++) {
                sprayDots.add(x + dl.random(-r, r));
                sprayDots.add(y + dl.random(-r, r));
            }
        }
    }

    CSSColor cssColor() {
        return CSSColor(color.r, color.g, color.b, color.a / 255 * opacity / 100);
    }

    void render(Context2D ctx) {
        ctx.save();
        switch (this.brushId) {
            case 0:
                Marker.render(this, ctx);
            case 8:
                SprayCan.render(this, ctx);
        }
        ctx.restore();
    }
}

class Marker {
    static void render(BrushStroke strokeInfo, Context2D ctx) {
        final path = strokeInfo.points;
        if (path.isEmpty) return;

        if (path.length == 2) {
            ctx.fillStyle = strokeInfo.cssColor();
            ctx.beginPath();
            ctx.arc(path[0], path[1], strokeInfo.weight / 2, 0, 2 * pi);
            ctx.fill();
        } else {
            // draw as a single path so overlapping segments don't darken translucent strokes
            ctx.strokeStyle = strokeInfo.cssColor();
            ctx.lineWidth = strokeInfo.weight;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.beginPath();
            ctx.moveTo(path[0], path[1]);
            for (var i = 2; i < path.length; i += 2) {
                ctx.lineTo(path[i], path[i+1]);
            }
            ctx.stroke();
        }
    }
}

class SprayCan {
    static void render(BrushStroke strokeInfo, Context2D ctx) {
        final dots = strokeInfo.sprayDots;
        ctx.fillStyle = strokeInfo.cssColor();
        for (var i = 0; i < dots.length; i += 2) {
            ctx.fillRect(dots[i], dots[i+1], 1, 1);
        }
    }
}
