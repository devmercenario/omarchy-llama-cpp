import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// llama.cpp dropdown: one row per configured model, click to start or stop.
// Only one server runs at a time, so starting a model stops the current one.
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

  function actionLabel(model) {
    if (model.state === "running") return "stop"
    if (model.state === "starting") return "starting…"
    return "start"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
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
        spacing: Style.spacing.md

        Row {
          width: parent.width
          spacing: Style.spacing.sm

          Text {
            text: "llama.cpp"
            color: root.contentFg
            font.family: root.contentFont
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            visible: root.runState !== "stopped"
            text: root.runState === "starting" ? "starting…" : "running"
            color: Util.alpha(root.contentFg, root.runState === "running" ? 0.9 : 0.6)
            font.family: root.contentFont
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Text {
          visible: root.loaded && root.models.length === 0
          width: parent.width
          text: "No models configured."
          color: Util.alpha(root.contentFg, 0.7)
          font.family: root.contentFont
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.models

          delegate: Rectangle {
            required property var modelData
            required property int index

            width: content.width
            height: Style.spacing.popupRowHeight
            radius: Style.space(6)
            color: modelData.active
              ? Color.menu.selectedBackground
              : (index === root.cursor ? Util.alpha(root.contentFg, 0.06) : "transparent")
            border.width: modelData.active ? 1 : 0
            border.color: Util.alpha(root.contentFg, 0.25)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.sm
              anchors.rightMargin: Style.spacing.sm
              spacing: Style.spacing.sm

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
                width: parent.width - Style.space(8) - actionText.width - Style.spacing.sm * 3

                Text {
                  width: parent.width
                  text: modelData.name
                  color: root.contentFg
                  font.family: root.contentFont
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  text: "port " + modelData.port
                  color: Util.alpha(root.contentFg, 0.5)
                  font.family: root.contentFont
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                id: actionText
                anchors.verticalCenter: parent.verticalCenter
                text: root.actionLabel(modelData)
                color: Util.alpha(root.contentFg, modelData.state === "stopped" ? 0.6 : 0.95)
                font.family: root.contentFont
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: root.activate(modelData.id)
              onEntered: root.cursor = index
            }
          }
        }

        Text {
          width: parent.width
          text: root.configSource === "bundled"
            ? "No models.json yet — create one at " + root.userConfig
            : root.configPath
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
