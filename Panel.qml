import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "yuler.omaports"
  ipcTarget: "yuler.omaports"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var collector: null
  property var names: ({})
  property string namesPath: ""
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool confirmOpen: false
  property var pendingRow: null
  property string statusText: ""

  readonly property var barIdentity: hostWidget || root
  readonly property var rows: Model.filterListeners(collector ? collector.listeners : [], filterText)
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int uid: collector ? collector.uid : 0
  readonly property string killSig: Model.killSignal(collector && collector.parsedSettings ? collector.parsedSettings.killSignal : "TERM")

  function open() {
    root.filterText = ""
    root.selectedIndex = 0
    root.confirmOpen = false
    root.statusText = ""
    if (collector) collector.refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.confirmOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function clampSelection() {
    if (rows.length === 0) {
      selectedIndex = 0
      cursorActive = false
      return
    }
    if (selectedIndex >= rows.length) selectedIndex = rows.length - 1
    if (selectedIndex < 0) selectedIndex = 0
    cursorActive = true
  }

  function setFilter(next) {
    filterText = next
    selectedIndex = 0
    clampSelection()
  }

  function move(delta) {
    if (rows.length === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? rows.length - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + rows.length) % rows.length
    }
  }

  function currentRow() {
    if (selectedIndex < 0 || selectedIndex >= rows.length) return null
    return rows[selectedIndex]
  }

  function openRow(row) {
    if (!row) return
    var url = Model.openUrl(row, collector.parsedSettings.httpsPorts)
    if (url) Quickshell.execDetached(["xdg-open", url])
  }

  function copyRow(row) {
    if (!row) return
    var url = Model.openUrl(row, collector.parsedSettings.httpsPorts)
    if (url) Quickshell.execDetached(["wl-copy", url])
    root.statusText = "Copied"
  }

  function terminalRow(row) {
    if (!row || !row.cwd) {
      root.statusText = "No working directory"
      return
    }
    termProc.workingDirectory = row.cwd
    termProc.running = false
    termProc.running = true
  }

  function askKill(row) {
    if (!row) return
    if (row.kind !== "container" && !Model.canKillRow(row, uid)) {
      root.statusText = "Can only stop processes you own"
      return
    }
    pendingRow = row
    confirmOpen = true
  }

  function cancelKill() {
    confirmOpen = false
    pendingRow = null
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
    if (!Model.canSignalProcess(row, uid, row.startTime)) {
      root.statusText = "Refusing to signal this process"
      return
    }
    killProc.command = ["kill", "-" + killSig, String(row.pid)]
    killProc.running = false
    killProc.running = true
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
      if (collector) collector.refresh()
    }
  }

  Process {
    id: stopProc
    running: false
    onExited: function(code) {
      root.statusText = code === 0 ? "Container stopped" : "docker stop failed"
      if (collector) collector.refresh()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(Style.space(360))

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
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
          event.accepted = true
        } else if (event.modifiers & Qt.ControlModifier) {
          if (event.key === Qt.Key_Y) { root.copyRow(root.currentRow()); event.accepted = true }
          else if (event.key === Qt.Key_X) { root.askKill(root.currentRow()); event.accepted = true }
          else if (event.key === Qt.Key_T) { root.terminalRow(root.currentRow()); event.accepted = true }
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
          root.openRow(root.currentRow())
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
        message: root.pendingRow ? Model.confirmMessage(root.pendingRow, root.killSig) : ""
        confirmText: root.pendingRow && root.pendingRow.kind === "container" ? "Stop" : "Kill"
        background: Color.menu.background
        foreground: Color.menu.text
        scrim: Color.menu.scrim
        selectedBackground: Color.menu.selectedBackground
        selectedText: Color.menu.selectedText
        fontFamily: root.contentFontFamily
        cornerRadius: Style.cornerRadius
        onCanceled: root.cancelKill()
        onConfirmed: root.confirmKill()
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: root.filterText || "Search ports…"
          color: root.contentForeground
          opacity: root.filterText ? 1 : 0.58
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }

        Text {
          width: parent.width
          visible: !!(collector && collector.errorText)
          text: collector ? collector.errorText : ""
          color: Color.urgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          textFormat: Text.PlainText
        }

        ListView {
          id: list
          width: parent.width
          height: parent.height - Style.space(64)
          clip: true
          model: root.rows
          currentIndex: root.selectedIndex
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            required property var modelData
            required property int index
            width: list.width
            height: Style.space(52)
            radius: Style.cornerRadius
            color: index === root.selectedIndex
              ? Style.hoverFillFor(root.contentForeground, Color.accent)
              : "transparent"

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: Model.titleFor(modelData) + "  :" + modelData.port
                color: modelData.exposed ? Color.urgent : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                textFormat: Text.PlainText
              }

              Text {
                width: parent.width
                text: Model.subtitleFor(modelData)
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
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
                root.openRow(modelData)
              }
            }
          }

          Text {
            visible: list.count === 0
            anchors.centerIn: parent
            text: "No listening TCP ports"
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
        }

        Text {
          width: parent.width
          text: root.statusText || "Enter open · Ctrl+Y copy · Ctrl+T terminal · Ctrl+X kill"
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
      }
    }
  }
}
