import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// llama.cpp dropdown: one row per configured model, click to start or stop.
// Only one server runs at a time, so starting a model stops the current one.
//
// The panel is divided by hairlines: a header rule, one rule between rows, and
// a footer rule above the config path. Rows carry no fill, so the switch and
// the status dot are what communicate state.
Panel {
  id: root
  moduleName: "devmercenario.llama-cpp"
  ipcTarget: "devmercenario.llama-cpp"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string helper: ""

  property var models: []
  property string configPath: ""
  property string configSource: ""
  property string userConfig: ""
  property string runState: "stopped"
  property string currentId: ""
  property bool loaded: false
  property bool busy: false
  property int cursor: 0

  readonly property color contentFg: bar ? bar.foreground : Color.foreground
  readonly property string contentFont: bar ? bar.fontFamily : Style.font.family
  readonly property int rowHeight: Style.space(42)
  readonly property int hairline: Math.max(1, Style.space(1))

  function open() {
    refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function refresh() {
    if (helper === "" || listProc.running) return
    listProc.running = true
  }

  function applyList(output) {
    try {
      var s = JSON.parse(String(output || "").trim())
      models = s.models || []
      configPath = s.config || ""
      configSource = s.configSource || ""
      userConfig = s.userConfig || ""
      runState = s.state || "stopped"
      currentId = s.current || ""
    } catch (e) {
      models = []
    }
    loaded = true
    busy = false
    if (cursor >= models.length) cursor = 0
  }

  function activate(id) {
    if (busy || helper === "") return
    busy = true
    actionProc.command = [helper, "toggle", id]
    actionProc.running = true
  }

  function moveCursor(dy) {
    if (models.length === 0) return
    cursor = (cursor + dy + models.length) % models.length
  }

  function activateCursor() {
    if (cursor >= 0 && cursor < models.length) activate(models[cursor].id)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.activateCursor()
      onMoveRequested: function (dx, dy) { root.moveCursor(dy) }
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) { if (t === "r") root.refresh() }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.lg

        // --- header: name, with the live state pinned to the right ---------
        Item {
          width: parent.width
          height: title.implicitHeight

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "llama.cpp"
            color: root.contentFg
            font.family: root.contentFont
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.runState !== "stopped"
            text: root.runState === "starting" ? "starting…" : "running"
            color: Util.alpha(root.contentFg, root.runState === "running" ? 0.9 : 0.6)
            font.family: root.contentFont
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          width: parent.width
          height: root.hairline
          color: Util.alpha(root.contentFg, 0.12)
        }

        Text {
          visible: root.loaded && root.models.length === 0
          width: parent.width
          text: "No models configured."
          color: Util.alpha(root.contentFg, 0.7)
          font.family: root.contentFont
          font.pixelSize: Style.font.body
        }

        // --- the models, one per row, divided by hairlines -----------------
        Column {
          width: parent.width
          spacing: 0

          Repeater {
            model: root.models

            delegate: Rectangle {
              required property var modelData
              required property int index

              width: content.width
              height: root.rowHeight
              color: "transparent"

              Row {
                anchors.fill: parent
                spacing: Style.spacing.md

                Rectangle {
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.contentFg
                  opacity: modelData.state === "running" ? 1.0
                    : (modelData.state === "starting" ? 0.7 : 0.3)
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs
                  width: parent.width - Style.space(8) - modelToggle.width - Style.spacing.md * 2

                  Text {
                    width: parent.width
                    text: modelData.name
                    color: (modelData.active || index === root.cursor)
                      ? root.contentFg
                      : Util.alpha(root.contentFg, 0.88)
                    font.family: root.contentFont
                    font.pixelSize: Style.font.body
                    font.bold: modelData.active
                    elide: Text.ElideRight
                  }

                  Text {
                    text: "port " + modelData.port
                    color: Util.alpha(root.contentFg, 0.5)
                    font.family: root.contentFont
                    font.pixelSize: Style.font.caption
                  }
                }

                ToggleSwitch {
                  id: modelToggle
                  anchors.verticalCenter: parent.verticalCenter
                  checked: modelData.active
                  busy: root.busy
                  interactive: false
                  foreground: root.contentFg
                  accent: Color.accent
                }
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.hairline
                visible: index < root.models.length - 1
                color: Util.alpha(root.contentFg, 0.12)
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.activate(modelData.id)
                onEntered: root.cursor = index
              }
            }
          }
        }

        // --- footer: where the models come from ----------------------------
        Rectangle {
          width: parent.width
          height: root.hairline
          color: Util.alpha(root.contentFg, 0.12)
        }

        Text {
          width: parent.width
          text: root.configSource === "bundled"
            ? "No models.json yet — create one at " + root.userConfig
            : "config · " + root.configPath
          color: Util.alpha(root.contentFg, 0.45)
          font.family: root.contentFont
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }

  Process {
    id: listProc
    command: [root.helper, "list", "--json"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyList(text)
    }
  }

  Process {
    id: actionProc
    onExited: function (code) {
      root.refresh()
      if (root.hostWidget && typeof root.hostWidget.refreshStatus === "function")
        root.hostWidget.refreshStatus()
    }
  }
}
