import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property string mode: "commands"
  property var names: ({})
  property bool confirmOpen: false
  property var pendingRow: null
  property string statusText: ""

  readonly property string pluginId: (manifest && manifest.id) || "yuler.omaports"
  readonly property string namesPath: Quickshell.env("HOME") + "/.local/state/omarchy/omaports/names.json"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/omaports"

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(640), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(520), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(52), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)

  readonly property var commands: Model.filterCommands(filterText)
  readonly property var portRows: {
    if (mode === "kill-port") {
      var port = Model.parsePortQuery(filterText)
      if (port) return Model.listenersOnPort(collector.listeners, port)
      return Model.filterListeners(collector.listeners, filterText)
    }
    return Model.filterListeners(collector.listeners, filterText)
  }
  readonly property var namedRows: {
    var rows = Model.namedPortRows(names)
    var q = String(filterText || "").toLowerCase()
    if (!q) return rows
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var blob = (rows[i].port + " " + rows[i].label).toLowerCase()
      if (blob.indexOf(q) !== -1) out.push(rows[i])
    }
    return out
  }
  readonly property var activeRows: mode === "commands" ? commands : (mode === "named-ports" ? namedRows : portRows)
  readonly property string placeholder: {
    if (mode === "commands") return "Search commands…"
    if (mode === "kill-port") return "Port number…"
    if (mode === "named-ports") return "3000=Next.js"
    return "Search ports…"
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.mode = "commands"
    root.confirmOpen = false
    root.statusText = ""
    mkdirProc.running = true
    collector.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.confirmOpen = false
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setFilter(next) {
    filterText = next
    selectedIndex = 0
    cursorActive = activeRows.length > 0
  }

  function move(delta) {
    var n = activeRows.length
    if (n === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? n - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + n) % n
    }
    resultList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function goBack() {
    if (filterText) setFilter("")
    else if (mode !== "commands") {
      mode = "commands"
      setFilter("")
    } else {
      dismiss()
    }
  }

  function saveNames(next) {
    names = next || {}
    namesFile.setText(JSON.stringify(names, null, 2) + "\n")
    collector.names = names
    collector.rebuild()
  }

  function currentItem() {
    if (selectedIndex < 0 || selectedIndex >= activeRows.length) return null
    return activeRows[selectedIndex]
  }

  function activate() {
    var item = currentItem()
    if (mode === "commands") {
      if (!item) return
      mode = item.id
      setFilter("")
      if (mode !== "named-ports") collector.refresh()
      return
    }
    if (mode === "named-ports") {
      var parsed = Model.parseNamedInput(filterText)
      if (parsed) {
        saveNames(Model.upsertName(names, parsed.port, parsed.label))
        setFilter("")
        statusText = "Saved " + parsed.port
        return
      }
      return
    }
    if (mode === "kill-port") {
      askKill(item)
      return
    }
    openRow(item)
  }

  function openRow(row) {
    if (!row || row.port === undefined) return
    var url = Model.openUrl(row, collector.parsedSettings.httpsPorts)
    if (url) Quickshell.execDetached(["xdg-open", url])
  }

  function copyRow(row) {
    if (!row || row.port === undefined) return
    var url = Model.openUrl(row, collector.parsedSettings.httpsPorts)
    if (url) Quickshell.execDetached(["wl-copy", url])
    statusText = "Copied"
  }

  function terminalRow(row) {
    if (!row || !row.cwd) {
      statusText = "No working directory"
      return
    }
    termProc.workingDirectory = row.cwd
    termProc.running = false
    termProc.running = true
  }

  function revealRow(row) {
    if (!row || !row.exe) {
      statusText = "No executable path"
      return
    }
    Quickshell.execDetached(["xdg-open", row.exe])
  }

  function askKill(row) {
    if (!row) return
    if (row.kind !== "container" && !Model.canKillRow(row, collector.uid)) {
      statusText = "Can only stop processes you own"
      return
    }
    pendingRow = row
    confirmOpen = true
  }

  function deleteNamed() {
    var item = currentItem()
    if (!item || item.port === undefined) return
    saveNames(Model.removeName(names, item.port))
    statusText = "Removed name"
  }

  function confirmKill() {
    var row = pendingRow
    confirmOpen = false
    pendingRow = null
    if (!row) return
    if (row.kind === "container") {
      stopProc.command = ["docker", "stop", row.containerId]
      stopProc.running = false
      stopProc.running = true
      return
    }
    if (!Model.canSignalProcess(row, collector.uid, row.startTime)) {
      statusText = "Refusing to signal this process"
      return
    }
    killProc.command = ["kill", "-" + Model.killSignal(collector.parsedSettings.killSignal), String(row.pid)]
    killProc.running = false
    killProc.running = true
  }

  PortCollector {
    id: collector
    settings: ({
      killSignal: "TERM",
      includeDocker: "On",
      includeUdp: "Off",
      ignoredPorts: "53,631,5353",
      httpsPorts: "443,8443",
      refreshIntervalSec: 5
    })
    names: root.names
  }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root.stateDir]
    running: false
  }

  Process {
    id: termProc
    command: ["xdg-terminal-exec"]
    running: false
  }

  Process {
    id: killProc
    running: false
    onExited: function(code) {
      root.statusText = code === 0 ? "Signaled" : "Kill failed"
      collector.refresh()
    }
  }

  Process {
    id: stopProc
    running: false
    onExited: function(code) {
      root.statusText = code === 0 ? "Container stopped" : "docker stop failed"
      collector.refresh()
    }
  }

  FileView {
    id: namesFile
    path: root.namesPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var parsed = Model.parseNames(text())
      root.names = parsed || {}
      collector.names = root.names
    }
    onLoadFailed: root.names = ({})
    onFileChanged: reload()
  }

  FileView {
    id: settingsFile
    path: root.stateDir + "/settings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var parsed = Model.parseSettings(text())
      collector.settings = {
        killSignal: parsed.killSignal,
        includeDocker: parsed.includeDocker ? "On" : "Off",
        includeUdp: parsed.includeUdp ? "On" : "Off",
        ignoredPorts: parsed.ignoredPorts,
        httpsPorts: parsed.httpsPorts,
        refreshIntervalSec: parsed.refreshIntervalSec
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-omaports"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.confirmOpen) {
            if (confirmDialog.handleKey(event)) event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            root.goBack()
            event.accepted = true
          } else if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_Y) { root.copyRow(root.currentItem()); event.accepted = true }
            else if (event.key === Qt.Key_X) {
              if (root.mode === "named-ports") root.deleteNamed()
              else root.askKill(root.currentItem())
              event.accepted = true
            } else if (event.key === Qt.Key_T) { root.terminalRow(root.currentItem()); event.accepted = true }
            else if (event.key === Qt.Key_R) { root.revealRow(root.currentItem()); event.accepted = true }
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.move(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.move(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: confirmDialog
          anchors.fill: parent
          opened: root.confirmOpen
          z: 10
          message: root.pendingRow ? Model.confirmMessage(root.pendingRow, collector.parsedSettings.killSignal) : ""
          confirmText: root.pendingRow && root.pendingRow.kind === "container" ? "Stop" : "Kill"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: { root.confirmOpen = false; root.pendingRow = null }
          onConfirmed: root.confirmKill()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Text {
          width: parent.width
          height: root.headerHeight
          verticalAlignment: Text.AlignVCenter
          text: root.filterText || root.placeholder
          color: root.foreground
          opacity: root.filterText ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        ListView {
          id: resultList
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing - Style.space(28)
          clip: true
          model: root.activeRows
          currentIndex: root.selectedIndex
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            required property var modelData
            required property int index
            width: resultList.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: index === root.selectedIndex ? root.selectedBackground : "transparent"

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.mode === "commands"
                  ? modelData.name
                  : (root.mode === "named-ports"
                    ? (modelData.port + "  " + modelData.label)
                    : (Model.titleFor(modelData) + "  :" + modelData.port))
                color: (root.mode !== "commands" && root.mode !== "named-ports" && modelData.exposed) ? Color.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                textFormat: Text.PlainText
              }

              Text {
                width: parent.width
                text: root.mode === "commands"
                  ? modelData.description
                  : (root.mode === "named-ports" ? "Named port" : Model.subtitleFor(modelData))
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                textFormat: Text.PlainText
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                root.selectedIndex = index
                root.cursorActive = true
                root.activate()
              }
            }
          }

          Text {
            visible: resultList.count === 0
            anchors.centerIn: parent
            text: root.mode === "commands" ? "No commands" : (root.mode === "named-ports" ? "No named ports" : "No listening TCP ports")
            color: Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
        }

        Text {
          width: parent.width
          text: root.statusText || (root.mode === "commands"
            ? "Enter to run"
            : (root.mode === "named-ports"
              ? "Enter save · Ctrl+X delete"
              : "Enter open · Ctrl+Y copy · Ctrl+T terminal · Ctrl+X kill · Ctrl+R reveal"))
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }
    }
  }
}
