import 'dart:async';

import 'package:drawlite_dart/drawlite.dart'
    show Drawlite, Event, KeyboardEvent, MouseEvent, QuitEvent, KeyState;
import 'package:drawlite_dart/dl.dart';
import 'package:drawlite_dart/drawlite-touch.dart';

import 'package:dcanvas/dcanvas.dart';
import 'package:dcanvas/backend/Window.dart';
import 'package:dcanvas/backend/Backend.dart' show sdl;

import './icons.dart';
import './document.dart';
import './file-actions.dart';
import './menu.dart';

import './welcome-menu.dart';
import './brushes.dart';
import './sidebar.dart';

import './app-state.dart';

late SDLWindow window;

// smallest logical window size before the layout starts overlapping
const MIN_WIDTH = 960;
const MIN_HEIGHT = 680;

void onWindowResized(int newWidth, int newHeight) {
    width = newWidth;
    height = newHeight;
    dl.size(width, height);
    window.width = width;
    window.height = height;

    lWidth = width / appScale;
    lHeight = height / appScale;

    sidebarCacheImg = null;

    // keep the color picker inside the window
    final picker = colorPicker;
    if (picker != null) {
        picker.x = constrain(picker.x, 0, lWidth - picker.width).toInt();
        picker.y = constrain(picker.y, 0, lHeight - picker.height).toInt();
    }
}

void renderTopRowButtons() {
    final mouseX = get.mouseX;
    final mouseY = get.mouseY;

    font("Open Sans", 11);
    noStroke();
    var touching = point_rect(mouseX / appScale, mouseY / appScale, 0, 0, 68, 48);
    if (touching) {
        fill(255, 255, 255, 25);
    } else {
        noFill();
    }
    rect(0, 0, 68, 48);
    strokeWeight(2);
    renderIcon(Icon.menu, 29, 16, 0.5, 0, 255);
    fill(255, 255, 255);
    textAlign(CENTER);
    text("Menu", 34, 40);
    
    List<Icon> labelsIcons = [
        Icon.brushes,
        Icon.shapes2d,
        Icon.shapes3d,
        Icon.stickers,
        Icon.text,
        Icon.effects,
        Icon.canvas,
        Icon.library3d
    ];
    var btnX = (68 + (lWidth - (4*68 + 48 + 8*68))) / 2;
    textAlign(CENTER);
    for (var i = 0; i < sidebarPageLabels.length; i++) {
        final touching2 = point_rect(mouseX / appScale, mouseY / appScale, btnX, 0, 68, 48);
        if (i == sidebarPage) {
            fill(30, 100, 190);
        } else if (touching2) {
            fill(255, 255, 255, 25);
        } else {
            noFill();
        }
        noStroke();
        rectMode(CORNER);
        rect(btnX, 0, 68, 48);
        
        fill(255, 255, 255);
        text(sidebarPageLabels[i], btnX + 68/2, 40);

        strokeWeight(2);
        renderIcon(labelsIcons[i], btnX + 34, 16, 0.45, 0, 255);
        
        btnX += 68;
    }
    
    List<String> labels2 = [
        "Paste",
        "Undo",
        "History",
        "Redo"
    ];
    List<Icon> labels2Icons = [
        Icon.OPpaste,
        Icon.undo,
        Icon.history,
        Icon.redo
    ];
    for (var i = 0; i < labels2.length; i++) {
        var rx = topRightButtonX(i);
        // gray out undo/redo when there's nothing to undo/redo
        final enabled = (i != UNDO_BUTTON || doc.canUndo) && (i != REDO_BUTTON || doc.canRedo);
        noStroke();
        rectMode(CORNER);
        var touching2 = point_rect(mouseX / appScale, mouseY / appScale, rx, 0, 68, 48);
        if (touching2 && enabled) {
            fill(255, 255, 255, 25);
        } else {
            noFill();
        }
        rect(rx, 0, 68, 48);
        
        final textClr = enabled ? 255 : 110;
        fill(textClr);
        text(labels2[3-i], rx + 68/2, 40);

        strokeWeight(2);
        rectMode(CENTER);
        renderIcon(labels2Icons[3-i], rx + 34, 16, 0.5, 0, textClr);
        rectMode(CORNER);
    }

    var touching3 = point_rect(mouseX / appScale, mouseY / appScale, lWidth - 48, 0, 48, 48);
    if (touching3) {
        fill(255, 255, 255, 25);
    } else {
        noFill();
    }
    noStroke();
    rect(lWidth - 48, 0, 48, 48);
    stroke(255, 255, 255);
    strokeWeight(2);
    arrow(lWidth - 26, 24, 0.7, 0);
}

// set when something happened that may change what's on screen
var needsRedraw = true;
var lastRedraw = 0;
// how often to redraw when idle, e.g. for blinking text cursors
const IDLE_REDRAW_MS = 250;

// padding between the canvas and the edges of the canvas area
const CANVAS_PADDING = 24;

// where the document is shown on screen, in logical coordinates
double viewX = 0;
double viewY = 0;
double viewZoom = 1;

void updateView() {
    final areaW = sidebarX - CANVAS_PADDING * 2;
    final areaH = lHeight - canvasAreaY - CANVAS_PADDING * 2;
    // shrink large images to fit, but never enlarge small ones
    viewZoom = [1.0, areaW / doc.width, areaH / doc.height].reduce((a, b) => a < b ? a : b);
    if (viewZoom <= 0) viewZoom = 1;
    viewX = ((sidebarX - doc.width * viewZoom) / 2).roundToDouble();
    viewY = (canvasAreaY + (lHeight - canvasAreaY - doc.height * viewZoom) / 2).roundToDouble();
}

double toDocX(num screenX) => (screenX / appScale - viewX) / viewZoom;
double toDocY(num screenY) => (screenY / appScale - viewY) / viewZoom;

bool isOverCanvasArea(num screenX, num screenY) {
    return screenX / appScale < sidebarX && screenY / appScale > canvasAreaY;
}

var _lastTitle = "";
void updateTitle() {
    final title = "${doc.modified ? "*" : ""}${doc.displayName} - LibrePaint 3D";
    if (title != _lastTitle) {
        window.setTitle(title);
        _lastTitle = title;
    }
}

void draw() {
    // check for events
    window.pollInput();

    if (!running) {
        noLoop();
        window.free();
        return;
    }

    // skip rendering when nothing changed to save CPU
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!needsRedraw && now - lastRedraw < IDLE_REDRAW_MS) {
        return;
    }
    needsRedraw = false;
    lastRedraw = now;

    final mouseX = get.mouseX;
    final mouseY = get.mouseY;

    pushMatrix();
        scale(appScale);

        // canvas area
        noStroke();
        fill(190, 190, 190);
        rect(0, canvasAreaY, lWidth - SIDEBAR_WIDTH, lHeight - canvasAreaY);

        // canvas
        updateView();
        final viewW = doc.width * viewZoom;
        final viewH = doc.height * viewZoom;
        image(doc.canvas, viewX, viewY, viewW, viewH);
        if (currDrawStroke != null) {
            dl.ctx.save();
            dl.ctx.translate(viewX, viewY);
            dl.ctx.scale(viewZoom, viewZoom);
            currDrawStroke!.render(dl.ctx);
            dl.ctx.restore();

            // cover the parts of the stroke outside the canvas
            noStroke();
            fill(190, 190, 190);
            rect(0, canvasAreaY, viewX, lHeight - canvasAreaY);
            rect(viewX + viewW, canvasAreaY, sidebarX - viewX - viewW, lHeight - canvasAreaY);
            rect(viewX, canvasAreaY, viewW, viewY - canvasAreaY);
            rect(viewX, viewY + viewH, viewW, lHeight - viewY - viewH);
        }

        fill(255, 0, 0, 100);
        noStroke();
        // top bar
        fill(45, 50, 55);
        rect(0, 0, lWidth, 48);

        // 2nd row of top bar
        fill(221, 221, 223);
        rect(0, 48, lWidth - SIDEBAR_WIDTH, 48);

        // gradient
        for (var i = 0; i <= 10; i++) {
            var m = map(i, 0, 10, 30, 0);
            fill(0, 0, 0, m);
            rect(0, 48 + 48 + i, sidebarX - i, 1);
            rect(sidebarX - 1 - i, 48 + 48 + i, 1, lHeight - 48*2 - i);
        }

        renderTopRowButtons();

        // 2nd row labels
        {
            font("Open Sans", 12);
            
            List<String> labels = [
                "Select",
                "Crop",
                "Magic Select"
            ];
            List<Icon> labelsIcons = [
                Icon.select,
                Icon.crop,
                Icon.magicSelect
            ];
            var btnX = 0.0;
            textAlign(CENTER);
            for (var i = 0; i < labels.length; i++) {
                var txtWidth = textWidth(labels[i]) + 71;
                
                var touching3 = point_rect(mouseX / appScale, mouseY / appScale, btnX, 48, txtWidth, 48);
                if (touching3) {
                    fill(0, 0, 0, 20);
                } else {
                    noFill();
                }
                noStroke();
                rectMode(CORNER);
                rect(btnX, 48, txtWidth, 48);
                
                fill(0, 0, 0);
                text(labels[i], btnX + txtWidth/2 + 12, 76);

                renderIcon(labelsIcons[i], btnX + 23, 70, 0.65, 0, 0);
                
                btnX += txtWidth;
            }
            rectMode(CORNER);
        }

        if (mouseX >= sidebarX || sidebarPage.isActive) {
            renderSideBar();
            sidebarCacheImg = null;
        } else if (sidebarCacheImg == null) {
            renderSideBar();
            sidebarCacheImg = snip(sidebarX, sidebarY, SIDEBAR_WIDTH, lHeight - 48);
        } else {
            image(sidebarCacheImg!, sidebarX, sidebarY);
        }

        renderMenu();

        // welcome
        if (scene == Scene.Welcome) {
            welcomeMenu();
        }
    popMatrix();

    if (colorPicker != null) {
        colorPicker!.render();
    }

    window.render();
}

void mousePressed(MouseEvent event) {
    final mouseX = get.mouseX;
    final mouseY = get.mouseY;

    if (colorPicker != null && colorPicker!.isMouseOver()) {
        colorPicker!.mousePressed();
        return;
    }

    if (menuMousePressed()) {
        return;
    }
    
    if (mouseX / appScale > sidebarX && mouseY / appScale > sidebarY) {
        sidebarPage.mousePressed();
        return;
    }

    // clicking outside the sidebar finishes editing its number boxes
    if (brushesPage.initialized) {
        brushesPage.blurInputs();
    }
    
    var btnX = (68 + (lWidth - (4*68 + 48 + 8*68))) / 2;
    for (var i = 0; i < sidebarPageLabels.length; i++) {
        if (point_rect(mouseX / appScale, mouseY / appScale, btnX, 0, 68, 48)) {
            setSidebarPage(i);
            return;
        }
        btnX += 68;
    }

    if (point_rect(mouseX / appScale, mouseY / appScale, topRightButtonX(UNDO_BUTTON), 0, 68, 48)) {
        undo();
        return;
    }
    if (point_rect(mouseX / appScale, mouseY / appScale, topRightButtonX(REDO_BUTTON), 0, 68, 48)) {
        redo();
        return;
    }

    if (isOverCanvasArea(mouseX, mouseY) && selectedMarker == FILL_BUCKET) {
        final x = toDocX(mouseX).floor(), y = toDocY(mouseY).floor();
        if (x >= 0 && y >= 0 && x < doc.width && y < doc.height) {
            doc.beginChange();
            final pixels = doc.getPixels();
            floodFill(pixels, x, y, currColor, brushesPage.opacitySlider.value);
            doc.ctx.putImageData(pixels, 0, 0);
            updateTitle();
        }
    } else if (isOverCanvasArea(mouseX, mouseY)) {
        currDrawStroke = new BrushStroke(currColor, brushesPage.thicknessSlider.value, brushesPage.opacitySlider.value, selectedMarker);
        currDrawStroke!.addPoint(toDocX(mouseX), toDocY(mouseY));
    }
}

void mouseDragged(MouseEvent event) {
    final mouseX = get.mouseX;
    final mouseY = get.mouseY;

    if (colorPicker != null && colorPicker!.isMouseOver()) {
        colorPicker!.mouseDragged();
        return;
    }

    if (mouseX / appScale > sidebarX && mouseY / appScale > sidebarY) {
        sidebarPage.mouseDragged();
        return;
    }

    if (currDrawStroke != null) {
        currDrawStroke!.addPoint(toDocX(mouseX), toDocY(mouseY));
    }
}

void mouseReleased(MouseEvent event) {
    if (colorPicker != null) {
        colorPicker!.onMouseReleased();
    }

    final mouseX = get.mouseX;
    final mouseY = get.mouseY;

    if (scene == Scene.Welcome) {
        for (var i = 0; i < 3; i++) {
            var rx = lWidth / 2 - 101;
            var ry = 165 + i * 169;
            var touching = point_rect(mouseX / appScale, mouseY / appScale, rx, ry, 202, 144);
            if (touching) {
                scene = Scene.Draw;
                if (i == 0) {

                }
            }
        }
    }

    if (currDrawStroke != null) {
        doc.beginChange();
        currDrawStroke!.render(doc.ctx);
        currDrawStroke = null;
        updateTitle();
    }

    brushesPage.thicknessSlider.setPressed(false);
    brushesPage.opacitySlider.setPressed(false);
}

void undo() {
    if (currDrawStroke != null) return;
    doc.undo();
    updateTitle();
}

void redo() {
    if (currDrawStroke != null) return;
    doc.redo();
    updateTitle();
}

// x of a top right button, counting from the right starting at 0
double topRightButtonX(int i) => lWidth - 48 - 68 * (i + 1);
const REDO_BUTTON = 0;
const UNDO_BUTTON = 2;

// returns true if the key was a shortcut
bool handleShortcut(KeyboardEvent event) {
    if (!KeyState.isCtrlPressed()) return false;

    final key = event.keyCode;
    final shift = KeyState.isShiftPressed();
    if (key == 110) { // n
        newDocument();
    } else if (key == 111) { // o
        openDocument();
    } else if (key == 115 && shift) { // s
        saveDocumentAs();
    } else if (key == 115) {
        saveDocument();
    } else if (key == 113) { // q
        quit();
    } else if ((key == 122 && shift) || key == 121) { // ctrl+shift+z, ctrl+y
        redo();
    } else if (key == 122) { // z
        undo();
    } else {
        return false;
    }
    menuOpen = false;
    return true;
}

void keyPressed(KeyboardEvent event) {
    if (handleShortcut(event)) {
        return;
    }
    if (colorPicker != null) {
        colorPicker!.keyPressed(event);
        return;
    }
    sidebarPage.keyPressed(event);
}

var running = true;
void myEventHandler(Event event) {
    if (event.type != EventType.Unknown) {
        needsRedraw = true;
    }
    if (event is MouseEvent) {
        if (event.type == EventType.MouseDown) {
            dl.eventCallbacks.mousedown(event);
        } else if (event.type == EventType.MouseUp) {
            dl.eventCallbacks.mouseup(event);
        } else if (event.type == EventType.MouseMove) {
            dl.eventCallbacks.mousemove(event);
        }
    } else if (event is KeyboardEvent) {
        if (event.type == EventType.KeyDown) {
            dl.eventCallbacks.keydown(event);
        } else if (event.type == EventType.KeyUp) {
            dl.eventCallbacks.keyup(event);
        }
        
        // Escape cancels the color picker and menu instead of quitting the app
        if (event.keyCode == Key.Escape && event.type == EventType.KeyDown) {
            colorPicker = null;
            menuOpen = false;
        }
    } else if (event is WindowEvent) {
        if (event.type == EventType.WindowResized) {
            onWindowResized(event.width, event.height);
        }
    } else if (event is QuitEvent) {
        // ask about unsaved changes before closing
        quit();
    }
}

Future<void> main(List<String> args) async {
    width = (1241 * appScale).round();
    height = (804 * appScale).round();
    // width = (1023 * appScale).round();
    // height = (768 * appScale).round();

    var canvas = Canvas(width, height);
    dl = Drawlite(canvas);

    initSDL(SDL_INIT_EVERYTHING);
    window = SDLWindow(
        title: "Untitled - LibrePaint 3D",
        width: canvas.width,
        height: canvas.height,
        flagsList: [SDL_WindowFlags.SDL_WINDOW_SHOWN, SDL_WindowFlags.SDL_WINDOW_RESIZABLE]
    );
    window.setCanvas(canvas);
    window.eventHandler = myEventHandler;
    // SDL starts in text input mode, which lets input methods (e.g. Korean IME)
    // swallow letter keys before they reach us as key events
    sdl.SDL_StopTextInput();
    sdl.SDL_SetWindowMinimumSize(window.sdlWindow, (MIN_WIDTH * appScale).round(), (MIN_HEIGHT * appScale).round());

    globalizeDL(dl);
    
    initBrushColors();

    doc = PaintDocument.blank();
    onDocumentChanged = () {
        updateTitle();
        needsRedraw = true;
    };
    onQuit = () {
        running = false;
    };
    updateTitle();
    if (args.isNotEmpty) {
        // the .desktop file passes files as URIs
        final arg = args.first;
        openDocumentPath(arg.startsWith("file://") ? Uri.parse(arg).toFilePath() : arg);
    }

    lWidth = width / appScale;
    lHeight = height / appScale;

    loadMenuImage();
    loadOPpasteGradient();
    loadMagicSelectGradient();

    frameRate(60);
    dl.draw = draw;  
    dl.mousePressed = mousePressed;
    dl.mouseDragged = mouseDragged;
    dl.mouseReleased = mouseReleased;
    dl.keyPressed = keyPressed;
}
