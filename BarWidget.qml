import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// llama.cpp bar widget.
//
// Left click opens the dropdown of configured models; right click opens the
// running server in the browser. The icon is full color while a server runs
// and dimmed while it is stopped.
BarWidget {
  id: root
  moduleName: "devmercenario.llama-cpp"

  readonly property string pluginDir: Qt.resolvedUrl(".").toString()
    .replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helper: pluginDir + "/bin/omarchy-llama-cpp"

  readonly property int refreshMs: Math.max(2, Number(root.setting("refreshIntervalSec", 4))) * 1000
  readonly property real idleOpacity: Number(root.setting("idleOpacity", 0.35))
  readonly property string glyph: root.setting("glyph", "")

  property string serverState: "stopped"
  property string modelId: ""
  property string modelName: ""
  property string serverUrl: ""
  property bool busy: false

  // Panel lifecycle contract expected by the bar (findPanelWidget looks for
  // open/close/opened on the widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.helper = root.helper
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  function applyStatus(output) {
    try {
      var s = JSON.parse(String(output || "").trim())
      serverState = s.state || "stopped"
      modelId = s.id || ""
      modelName = s.name || s.id || ""
      serverUrl = s.url || ""
    } catch (e) {
      serverState = "stopped"
      modelId = ""
      modelName = ""
      serverUrl = ""
    }
    busy = false
  }

  function tooltip() {
    if (serverState === "running")
      return "llama.cpp: " + (modelName || modelId) + (serverUrl ? " — " + serverUrl : "")
    if (serverState === "starting")
      return "llama.cpp: starting " + (modelName || modelId)
    return "llama.cpp: stopped"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Timer {
    interval: root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Process {
    id: statusProc
    command: [root.helper, "status", "--json"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "devmercenario.llama-cpp"

    function refresh(): void {
      root.refreshStatus()
    }

    function open(): void {
      root.open()
    }

    function close(): void {
      root.close()
    }

    function toggle(): void {
      root.toggle()
    }
  }

  Component {
    id: llamaIcon

    Image {
      anchors.fill: parent
      source: root.pluginDir + "/assets/llama.svg"
      sourceSize.width: 64
      sourceSize.height: 64
      fillMode: Image.PreserveAspectFit
      smooth: true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    iconComponent: root.glyph === "" ? llamaIcon : null
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    opacity: root.busy ? 0.6
      : (root.serverState === "running" ? 1.0
        : (root.serverState === "starting" ? 0.75 : root.idleOpacity))
    tooltipText: root.tooltip()

    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton && root.serverUrl !== "" && root.bar)
        root.bar.run("xdg-open " + root.bar.shellQuote(root.serverUrl))
      else
        root.toggle()
    }
  }
}
