import QtQuick
import qs.Commons
import qs.Ui

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

  readonly property var barIdentity: hostWidget || root

  function open() {
    view.prepareOpen()
    root.controller.show()
  }

  function close() {
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: view.searchInput
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(Style.space(380))

    PortManagerView {
      id: view
      anchors.fill: parent
      collector: root.collector
      names: root.names
      bar: root.bar
      barIdentity: root.barIdentity
      allowPanelSwitch: true
      contentForeground: root.bar ? root.bar.foreground : Color.foreground
      contentFontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      onCloseRequested: root.close()
      onSwitchPanelRequested: function(direction) { root.switchPanel(direction) }
    }
  }
}
