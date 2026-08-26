import QtQuick
import qs.Commons

Rectangle {
  id: root

  property string key: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  color: Style.hoverFillFor(root.foreground, Color.accent)
  border.color: Qt.darker(root.foreground, 1.7)
  border.width: Style.spacing.hairline
  radius: Math.max(2, Style.space(3))
  implicitWidth: Math.max(label.implicitWidth + Style.space(8), implicitHeight)
  implicitHeight: label.implicitHeight + Style.space(4)

  Text {
    id: label
    anchors.centerIn: parent
    text: root.key
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    textFormat: Text.PlainText
  }
}
