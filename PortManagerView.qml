import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var collector: null
  property var names: ({})
  property var bar: null
  property var barIdentity: null
  property bool allowPanelSwitch: false
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family

  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool confirmOpen: false
  property var pendingRow: null
  property string statusText: ""
  readonly property bool searchFocused: !!(searchField && searchField.activeFocus)
  readonly property bool listFocused: !searchFocused && cursorActive
  readonly property string hintText: {
    if (statusText) return statusText
    if (searchFocused) return "Tab list"
    return "j/k · Enter · y copy · x kill · t terminal"
  }

  readonly property var rows: Model.filterListeners(collector ? collector.listeners : [], filterText)
  readonly property int portCount: collector && collector.listeners ? collector.listeners.length : 0
  readonly property int uid: collector ? collector.uid : 0
  readonly property string killSig: Model.killSignal(collector && collector.parsedSettings ? collector.parsedSettings.killSignal : "TERM")
  readonly property string countLabel: portCount === 1 ? "1 port" : portCount + " ports"

  signal closeRequested()
  signal switchPanelRequested(int direction)

  property alias searchInput: searchField
  property alias listCatcher: keyCatcher

  function prepareOpen() {
    filterText = ""
    selectedIndex = 0
    cursorActive = false
    confirmOpen = false
    statusText = ""
    statusClear.stop()
    if (collector) collector.refresh()
    Qt.callLater(focusSearch)
    searchFocusRetry.restart()
  }

  function focusSearch() {
    cursorActive = false
    if (searchField) searchField.forceActiveFocus()
  }

  function focusList() {
    if (searchField) searchField.focus = false
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function enterList(index) {
    if (rows.length === 0) return
    if (index === undefined || index === null) index = 0
    if (index < 0) index = 0
    if (index >= rows.length) index = rows.length - 1
    selectedIndex = index
    cursorActive = true
    focusList()
  }

  function flashStatus(message) {
    statusText = message || ""
    if (message) statusClear.restart()
    else statusClear.stop()
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
    cursorActive = false
  }

  function move(delta) {
    if (rows.length === 0) return
    if (searchFocused) {
      if (delta > 0) enterList(0)
      return
    }
    if (!cursorActive) {
      enterList(delta < 0 ? rows.length - 1 : 0)
      return
    }
    var next = selectedIndex + delta
    if (next < 0) {
      focusSearch()
      return
    }
    if (next >= rows.length) next = rows.length - 1
    selectedIndex = next
  }

  function togglePane() {
    if (searchFocused) {
      if (rows.length === 0) {
        cursorActive = true
        focusList()
        return
      }
      enterList(selectedIndex)
      return
    }
    focusSearch()
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
    flashStatus("Copied")
  }

  function terminalRow(row) {
    if (!row || !row.cwd) {
      flashStatus("No working directory")
      return
    }
    termProc.workingDirectory = row.cwd
    termProc.running = false
    termProc.running = true
  }

  function askKill(row) {
    if (!row) return
    if (row.kind !== "container" && !Model.canKillRow(row, uid)) {
      flashStatus("Can only stop processes you own")
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
    if (!Model.canSignalProcess(row, collector.uid, row.startTime)) {
      flashStatus("Refusing to signal this process")
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
      flashStatus(code === 0 ? "Signaled" : "Kill failed")
      if (collector) collector.refresh()
    }
  }

  Process {
    id: stopProc
    running: false
    onExited: function(code) {
      flashStatus(code === 0 ? "Container stopped" : "docker stop failed")
      if (collector) collector.refresh()
    }
  }

  Timer {
    id: statusClear
    interval: 2000
    repeat: false
    onTriggered: root.statusText = ""
  }

  Timer {
    id: searchFocusRetry
    interval: 80
    repeat: false
    onTriggered: if (!root.cursorActive) root.focusSearch()
  }

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: root.confirmOpen || (searchField && searchField.activeFocus)

    onMoveRequested: function(dx, dy) {
      if (root.confirmOpen) {
        if (dx !== 0 || dy !== 0) confirmDialog.selectedIndex = confirmDialog.selectedIndex === 0 ? 1 : 0
        return
      }
      if (dy !== 0) root.move(dy)
    }
    onActivateRequested: {
      if (root.confirmOpen) {
        if (confirmDialog.selectedIndex === 0) root.cancelKill()
        else root.confirmKill()
        return
      }
      root.openRow(root.currentRow())
    }
    onCloseRequested: {
      if (root.confirmOpen) root.cancelKill()
      else root.closeRequested()
    }
    onTabRequested: function(direction) {
      if (root.confirmOpen) {
        confirmDialog.selectedIndex = confirmDialog.selectedIndex === 0 ? 1 : 0
        return
      }
      root.togglePane()
    }
    onDeleteRequested: if (!root.confirmOpen && !root.searchFocused) root.askKill(root.currentRow())
    onTextKey: function(t) {
      if (root.confirmOpen || root.searchFocused) return
      var raw = String(t || "")
      var key = raw.toLowerCase()
      if (raw === "K") root.askKill(root.currentRow())
      else if (key === "y" || key === "c") root.copyRow(root.currentRow())
      else if (key === "t") root.terminalRow(root.currentRow())
      else if (key === "r") { if (collector) collector.refresh() }
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
      id: column
      anchors.fill: parent
      spacing: Style.space(12)

      PanelHero {
        id: hero
        width: parent.width
        title: "Port Manager"
        meta: root.countLabel
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        iconComponent: Component {
          PortIcon {
            iconSize: Style.font.display
            fontSize: Style.font.display
            fontFamily: root.contentFontFamily
            color: root.contentForeground
          }
        }
      }

      BorderSurface {
        id: searchPane
        width: parent.width
        implicitHeight: searchField.implicitHeight + Style.space(8)
        color: "transparent"
        radius: Style.cornerRadius
        borderSpec: root.searchFocused
          ? Border.controlSpec("focus", root.contentForeground, Color.accent)
          : Border.none()

        TextField {
          id: searchField
          anchors.fill: parent
          anchors.margins: Style.space(4)
          foreground: root.contentForeground
          font.family: root.contentFontFamily
          placeholderText: "Search ports..."
          text: root.filterText
          onTextChanged: if (text !== root.filterText) root.setFilter(text)
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (root.confirmOpen) {
              if (confirmDialog.handleKey(event)) event.accepted = true
              return
            }
            if (event.key === Qt.Key_Escape) {
              if (root.filterText) root.setFilter("")
              else root.closeRequested()
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.togglePane()
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.enterList(0)
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.enterList(0)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.enterList(0)
              event.accepted = true
            } else if (event.modifiers & Qt.ControlModifier) {
              if (event.key === Qt.Key_U) { root.setFilter(""); event.accepted = true }
            }
          }
        }
      }

      PanelSeparator {
        id: rule
        foreground: root.contentForeground
      }

      Text {
        width: parent.width
        visible: !!(collector && collector.errorText)
        height: visible ? implicitHeight : 0
        text: collector ? collector.errorText : ""
        color: Color.urgent
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
      }

      Item {
        id: listPane
        width: parent.width
        height: Math.max(Style.space(80), column.height - hero.height - searchPane.height - rule.height - hint.height - column.spacing * 4)

        BorderSurface {
          anchors.fill: parent
          color: "transparent"
          radius: Style.cornerRadius
          borderSpec: root.listFocused
            ? Border.controlSpec("focus", root.contentForeground, Color.accent)
            : Border.none()
        }

        ListView {
          id: list
          anchors.fill: parent
          anchors.margins: Style.space(6)
          spacing: Style.space(4)
          clip: true
          model: root.rows
          currentIndex: root.selectedIndex
          boundsBehavior: Flickable.StopAtBounds
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            required property var modelData
            required property int index
            width: list.width
            height: portRow.implicitHeight

            PortRow {
              id: portRow
              width: parent.width
              row: modelData
              rowIndex: index
              selectedIndex: root.listFocused ? root.selectedIndex : -1
              contentForeground: root.contentForeground
              contentFontFamily: root.contentFontFamily
              onRowHovered: root.enterList(index)
              onRowActivated: {
                root.enterList(index)
                root.openRow(modelData)
              }
            }
          }

          Text {
            visible: list.count === 0
            anchors.centerIn: parent
            text: root.filterText ? "No matching ports" : "No listening TCP ports"
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
        }
      }

      Text {
        id: hint
        width: parent.width
        text: root.hintText
        color: Qt.darker(root.contentForeground, 1.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
    }
  }
}
