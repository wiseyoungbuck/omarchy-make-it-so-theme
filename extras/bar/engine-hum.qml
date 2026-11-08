// Make It So: the engine hum's bar control, a one-colour TNG delta.
//   left click   open the panel: on/off switch and volume slider
//   right click  toggle the hum
//   scroll       volume up/down
// Icon: the bar's text colour while on, dimmed while off, like Omarchy's own.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "engine-hum"
  ipcTarget: "engine-hum"   // omarchy-shell engine-hum open|close|toggle

  property bool running: false
  property int volume: 75
  property int pendingVolume: -1
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color panelFg: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string script: Quickshell.env("HOME") + "/.local/bin/engine-hum"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!probe.running) probe.running = true
    if (!volumeReader.running) volumeReader.running = true
  }
  function toggleHum() {
    if (toggler.running) return
    root.running = !root.running        // flip the icon now; the probe confirms
    toggler.running = true
  }
  function setVolume(v) {
    root.volume = Math.max(0, Math.min(100, Math.round(v)))
    root.pendingVolume = root.volume
    volumeWriter.restart()               // coalesce slider drags
  }

  Process {
    id: probe
    command: ["pgrep", "-f", "^mpv .*--title=engine-hum( |$)"]
    onExited: function(exitCode) { root.running = exitCode === 0 }
  }

  Process {
    id: toggler
    command: [root.script, "toggle"]
    onExited: root.refresh()
  }

  Process {
    id: volumeReader
    command: [root.script, "volume"]
    stdout: StdioCollector {
      onStreamFinished: {
        var v = parseInt(text, 10)
        if (!isNaN(v) && root.pendingVolume < 0) root.volume = v
      }
    }
  }

  Process {
    id: volumeSetter
    property int target: 75
    command: [root.script, "volume", String(target)]
    onExited: if (root.pendingVolume === target) root.pendingVolume = -1
  }

  Timer {
    id: volumeWriter
    interval: 60
    onTriggered: {
      if (volumeSetter.running) { restart(); return }
      volumeSetter.target = root.pendingVolume
      volumeSetter.running = true
    }
  }

  Timer {
    interval: 2000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.opened ? "" : (root.running ? "Engine hum: on" : "Engine hum: off")
                 + " — " + root.volume + "%"
    iconComponent: Component {
      Item {
        Delta {
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          iconSize: button.iconSize
          color: root.running ? root.fg : Qt.darker(root.fg, 1.55)
        }
      }
    }
    onPressed: function(code) {
      if (code === Qt.RightButton) root.toggleHum()
      else if (code === Qt.LeftButton) { root.refresh(); root.toggle() }
    }
    onWheelMoved: function(delta) { root.setVolume(root.volume + (delta > 0 ? 5 : -5)) }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: Style.space(300)
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(240))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.toggleHum()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.setVolume(root.volume + dx * 5) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        PanelHero {
          id: hero
          width: parent.width
          title: "Engine hum"
          meta: root.running ? "Engaged" : "Disengaged"
          foreground: root.panelFg
          fontFamily: root.fontFamily
          iconOpacity: root.running ? 1.0 : 0.5
          iconComponent: Component {
            Delta {
              iconSize: Style.font.display
              color: root.panelFg
            }
          }
          trailingControl: Component {
            ToggleSwitch {
              checked: root.running
              foreground: hero.foreground
              onToggled: root.toggleHum()
            }
          }
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(volumeSlider.implicitHeight, volumeLabel.implicitHeight)

          PanelSlider {
            id: volumeSlider
            bar: root.bar
            anchors.left: parent.left
            anchors.right: volumeLabel.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0; maximum: 100; step: 5; integer: true
            value: root.volume
            onMoved: function(v) { root.setVolume(v) }
            onReleased: function(v) { root.setVolume(v) }
          }

          Text {
            id: volumeLabel
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(40)
            horizontalAlignment: Text.AlignRight
            text: Commons.I18n.formatNumber(Math.round(volumeSlider.dragging ? volumeSlider.liveValue : root.volume)) + "%"
            color: root.panelFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }

  // The delta alone, traced from the Simple Icons TNG combadge (CC0): 15.6 x 24 units.
  component Delta: Item {
    id: d
    property real iconSize: 12
    property color color
    width: iconSize * 15.6 / 24
    height: iconSize
    implicitWidth: width
    implicitHeight: height

    Shape {
      anchors.fill: parent
      // Drawn straight at screen resolution with analytic anti-aliasing, like a font glyph.
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: d.color
        strokeWidth: -1
        fillRule: ShapePath.WindingFill
        scale: Qt.size(d.height / 24, d.height / 24)
        PathSvg { path: "M7.81 0.09C6.25 1.9 4.95 3.8 3.98 5.94C2.35 9.6 0.95 14.0 0.4 19.7C0.2 21.0 0.1 22.4 0.05 23.71L0.31 23.91C1.05 22.8 1.95 21.7 2.85 20.71C4.95 18.6 7.35 16.3 9.65 14.8Q10.29 14.45 10.87 15.06C11.65 16.1 12.35 17.2 13.03 18.29C13.95 19.9 14.85 21.8 15.6 23.85C15.35 18.5 14.35 12.0 12.72 8.39C12.05 6.6 10.35 3.5 7.99 0.09Q7.9 0.0 7.81 0.09Z" }
      }
    }
  }
}
