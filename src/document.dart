import 'dart:io';
import 'dart:typed_data';

import 'package:dcanvas/dcanvas.dart' show Canvas;
import 'package:dcanvas/CanvasRenderingContext.dart' show Context2D, CSSColor, ImageData;
import 'package:image/image.dart' as img;

const DEFAULT_DOC_WIDTH = 500;
const DEFAULT_DOC_HEIGHT = 400;

// file extensions LibrePaint 3D can save to
const SAVE_EXTENSIONS = ["png", "jpg", "jpeg", "bmp", "gif", "tif", "tiff", "tga"];

// the image being painted, kept off screen so it isn't limited by the window
class PaintDocument {
    late Canvas canvas;
    late Context2D ctx;

    // where the image was opened from or last saved to
    String? filePath;
    // true when there are changes since the last save
    bool modified = false;

    int get width => canvas.width;
    int get height => canvas.height;

    PaintDocument.blank([int width = DEFAULT_DOC_WIDTH, int height = DEFAULT_DOC_HEIGHT]) {
        _init(width, height);
    }

    PaintDocument._sized(int width, int height) {
        _init(width, height);
    }

    void _init(int width, int height) {
        canvas = Canvas(width, height);
        ctx = canvas.getContext("2d");
        ctx.fillStyle = CSSColor(255, 255, 255, 1);
        ctx.fillRect(0, 0, width, height);
    }

    String get displayName {
        final path = filePath;
        if (path == null) return "Untitled";
        return path.split(Platform.pathSeparator).last;
    }

    // returns null if the file can't be read or isn't a supported image
    static PaintDocument? open(String path) {
        final Uint8List bytes;
        try {
            bytes = File(path).readAsBytesSync();
        } catch (e) {
            return null;
        }

        final decoded = img.decodeNamedImage(path, bytes) ?? img.decodeImage(bytes);
        if (decoded == null) return null;

        final rgba = decoded.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
        final data = rgba.getBytes(order: img.ChannelOrder.rgba);

        final doc = PaintDocument._sized(rgba.width, rgba.height);
        // composite onto the white background so transparent areas don't turn black
        final layer = Canvas(rgba.width, rgba.height);
        layer.getContext("2d").putImageData(ImageData(data, rgba.width, rgba.height), 0, 0);
        doc.ctx.drawImage(layer, 0, 0);

        doc.filePath = path;
        return doc;
    }

    ImageData getPixels() {
        return ctx.getImageData(0, 0, width, height);
    }

    // returns an error message, or null on success
    String? save(String path) {
        final ext = path.split(".").last.toLowerCase();
        if (!SAVE_EXTENSIONS.contains(ext)) {
            return "Unsupported file type: .$ext";
        }

        final pixels = Uint8List.fromList(getPixels().data);
        final image = img.Image.fromBytes(
            width: width,
            height: height,
            bytes: pixels.buffer,
            numChannels: 4,
            order: img.ChannelOrder.rgba
        );

        final encoded = img.encodeNamedImage(path, image);
        if (encoded == null) {
            return "Unable to encode image as .$ext";
        }

        try {
            File(path).writeAsBytesSync(encoded);
        } catch (e) {
            return "Unable to write $path: $e";
        }

        filePath = path;
        modified = false;
        return null;
    }
}
