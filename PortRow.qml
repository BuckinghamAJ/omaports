import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

CursorSurface {
  id: root

  property var row: null
  property int rowIndex: -1
  property int selectedIndex: -1
  property color contentForeground: Color.foreground
  property string contentFontFamily: Style.font.family
  property string titleText: row ? Model.titleFor(row) : ""
  property string subtitleText: row ? Model.subtitleFor(row) : ""
  property bool showPort: !!(row && row.port !== undefined)

  signal rowHovered()
  signal rowActivated()

  hasCursor: rowIndex === selectedIndex
  current: false
  foreground: contentForeground
  fill: Style.hoverFillFor(contentForeground, Color.accent)
  currentFill: Style.selectedFillFor(contentForeground, Color.accent)

  width: parent ? parent.width : implicitWidth
  implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: if (containsMouse) root.rowHovered()
    onClicked: root.rowActivated()
  }

  Item {
    id: rowContent
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    implicitHeight: info.implicitHeight

    Column {
      id: info
      spacing: Style.space(1)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter

      Text {
        width: parent.width
        text: root.showPort ? (String(root.row.port) + "  " + root.titleText) : root.titleText
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }

      Text {
        width: parent.width
        visible: root.subtitleText !== ""
        text: root.subtitleText
        color: Qt.darker(root.contentForeground, 1.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
    }
  }
}
