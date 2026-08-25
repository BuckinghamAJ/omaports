import QtQuick
import qs.Commons
import qs.Ui

// Ethernet jack glyph at the same optical sizes as omarchy.network,
// plus a thin slash. Bar uses iconFont (slightly larger); panel hero
// uses display, matching bluetooth/network headers.
Item {
  id: root

  property real iconSize: Style.bar.iconCanvas
  property real fontSize: Style.bar.iconFont
  property color color: Color.foreground
  property string fontFamily: Style.font.family

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  OpticalGlyph {
    anchors.fill: parent
    text: "󰈀"
    fontFamily: root.fontFamily
    fontSize: root.fontSize
    color: root.color
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.max(8, root.iconSize * 0.82)
    height: Math.max(1, Math.round(root.fontSize * 0.09))
    radius: height / 2
    color: root.color
    rotation: -42
  }
}
