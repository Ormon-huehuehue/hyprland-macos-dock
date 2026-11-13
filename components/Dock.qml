pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
  id: root

  required property var settings
  signal reorderRequested(int from, int to)
  signal pinRequested(string desktopId)
  signal unpinRequested(string desktopId)
  signal autoHideRequested(bool enabled)

  property int dragSource: -1
  property int dragTarget: -1
  property int openMenuCount: 0
  property bool autoHideRevealed: false

  readonly property int iconSize: settings.iconSize || 52
  readonly property real magnification: settings.magnification || 1.65
  readonly property real magnificationRadius: settings.magnificationRadius || 110
  readonly property int edgeMargin: settings.margin === undefined ? 10 : settings.margin
  readonly property real backgroundOpacity: {
    var value = Number(settings.backgroundOpacity)
    return settings.backgroundOpacity === undefined || isNaN(value)
      ? 0.88
      : Math.max(0, Math.min(1, value))
  }
  readonly property bool reserveSpace: settings.reserveSpace === undefined ? true : settings.reserveSpace
  readonly property bool autoHide: settings.autoHide === undefined ? false : settings.autoHide
  readonly property string clickAction: settings.clickAction || "focus-or-launch"
  readonly property string requestedPosition: settings.position || "bottom"
  readonly property string position: ["top", "bottom", "left", "right"].indexOf(requestedPosition) >= 0
    ? requestedPosition
    : "bottom"
  readonly property bool vertical: position === "left" || position === "right"
  readonly property bool fullLength: settings.fullLength === undefined ? false : settings.fullLength
  readonly property var pinned: settings.pinned || []
  readonly property int itemSize: iconSize + 14
  readonly property int reservedSize: iconSize + 24 + edgeMargin
  readonly property int mainPadding: 10
  readonly property int revealThickness: 3
  readonly property int crossExtent: vertical
    ? Math.ceil(iconSize * magnification + 80) + edgeMargin
    : Math.ceil(iconSize * magnification + 48) + edgeMargin
  readonly property bool keepAutoHideOpen: windowPointer.hovered
    || appPicker.visible || openMenuCount > 0 || dragSource >= 0
  // Keep the dock up while this screen's workspace has no windows.
  readonly property bool showOnEmptyWorkspace: settings.showOnEmptyWorkspace === undefined ? true : settings.showOnEmptyWorkspace
  readonly property var hyprMonitor: Hyprland.monitorFor(root.screen)
  readonly property bool screenEmpty: {
    var ws = hyprMonitor ? hyprMonitor.activeWorkspace : null
    return !ws || (ws.toplevels.values || []).length === 0
  }
  readonly property bool dockShown: !autoHide || autoHideRevealed || (showOnEmptyWorkspace && screenEmpty)
  readonly property real pointerPosition: !pointer.hovered
    ? -10000
    : vertical
      ? pointer.point.position.y - dockLayout.y
      : pointer.point.position.x - dockLayout.x

  function reorderOffset(index) {
    if (dragSource < dragTarget && index > dragSource && index <= dragTarget)
      return -itemSize
    if (dragSource > dragTarget && index >= dragTarget && index < dragSource)
      return itemSize
    return 0
  }

  function updateDragTarget(position) {
    dragTarget = Math.max(0, Math.min(pinned.length - 1, Math.floor(position / itemSize)))
  }

  function finishDrag() {
    var from = dragSource
    var to = dragTarget
    dragSource = -1
    dragTarget = -1
    if (from >= 0 && to >= 0 && from !== to)
      reorderRequested(from, to)
  }

  function updateAutoHideState() {
    if (!autoHide) {
      hideTimer.stop()
      autoHideRevealed = false
    } else if (keepAutoHideOpen) {
      hideTimer.stop()
      autoHideRevealed = true
    } else if (autoHideRevealed) {
      hideTimer.restart()
    }
  }

  onAutoHideChanged: updateAutoHideState()
  onKeepAutoHideOpenChanged: updateAutoHideState()

  anchors {
    top: position === "top" || (vertical && fullLength)
    bottom: position === "bottom" || (vertical && fullLength)
    left: position === "left" || (!vertical && fullLength)
    right: position === "right" || (!vertical && fullLength)
  }
  implicitWidth: vertical
    ? crossExtent
    : fullLength ? 0 : dockLayout.implicitWidth + mainPadding * 2
  implicitHeight: vertical
    ? fullLength ? 0 : dockLayout.implicitHeight + mainPadding * 2
    : crossExtent
  color: "transparent"
  exclusionMode: reserveSpace && !autoHide ? ExclusionMode.Normal : ExclusionMode.Ignore
  WlrLayershell.exclusiveZone: reserveSpace && !autoHide ? reservedSize : 0
  WlrLayershell.namespace: "hyprland-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  mask: Region {
    item: root.dockShown ? interactionArea : revealStrip
  }

  Timer {
    id: hideTimer

    interval: 150
    onTriggered: if (root.autoHide && !root.keepAutoHideOpen)
      root.autoHideRevealed = false
  }

  Item {
    id: interactionArea

    anchors.fill: parent
  }

  Item {
    id: revealStrip

    x: root.position === "right" ? parent.width - width : 0
    y: root.position === "bottom" ? parent.height - height : 0
    width: root.vertical ? root.revealThickness : parent.width
    height: root.vertical ? parent.height : root.revealThickness
  }

  Rectangle {
    id: dockBackground

    x: root.vertical
      ? root.position === "left" ? root.edgeMargin : parent.width - width - root.edgeMargin
      : 0
    y: root.vertical
      ? 0
      : root.position === "top" ? root.edgeMargin : parent.height - height - root.edgeMargin
    width: root.vertical ? root.iconSize + 24 : parent.width
    height: root.vertical ? parent.height : root.iconSize + 24
    radius: 22
    // macOS-style glass: a thin, slightly light tint over Hyprland's blur (layer rule in
    // see README), a soft top sheen, a bright hairline rim and a dark outer edge.
    color: Qt.rgba(0.22, 0.23, 0.26, root.backgroundOpacity)
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.35)
    // One 0..1 "reveal" value drives slide + scale + fade together, so the
    // motion stays coherent even if the pointer flicks in and out mid-animation.
    // Show: long smooth deceleration (no bounce). Hide: short ease-in, gets out of the way.
    property real reveal: !root.autoHide || root.dockShown ? 1 : 0
    // Subtle: short 16px rise + fade, no scaling. Raise `travel` for a full pull-up.
    Behavior on reveal {
      NumberAnimation {
        duration: root.dockShown ? 200 : 140
        easing.type: root.dockShown ? Easing.OutCubic : Easing.InQuad
      }
    }
    readonly property real travel: 16
    readonly property real hiddenShift: (1 - reveal) * travel

    opacity: reveal
    transform: [
      Translate {
        x: root.position === "left" ? -dockBackground.hiddenShift : root.position === "right" ? dockBackground.hiddenShift : 0
        y: root.position === "top" ? -dockBackground.hiddenShift : root.position === "bottom" ? dockBackground.hiddenShift : 0
      }
    ]

    // bottom sheen: light catches the lower half of the glass
    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: parent.radius - 1
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.0) }
        GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.03) }
        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.14) }
      }
    }

    // faint bright inner rim
    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: parent.radius - 1
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.12)
    }

    Grid {
      id: dockLayout

      // Offset the layout toward the screen edge so the icon itself, rather
      // than the icon-plus-indicator slot, is centered in the background.
      x: root.vertical
        ? root.position === "left" ? 6 : parent.width - implicitWidth - 6
        : (parent.width - implicitWidth) / 2
      y: root.vertical
        ? (parent.height - implicitHeight) / 2
        : root.position === "top" ? 6 : parent.height - implicitHeight - 6

      // Keep one spare cell so a settings reload cannot transiently reduce the
      // grid capacity before the repeater updates its delegates.
      columns: root.vertical ? 1 : Math.max(1, root.pinned.length + 1)
      rows: root.vertical ? Math.max(1, root.pinned.length + 1) : 1

      Repeater {
        model: root.pinned

        DockItem {
          required property string modelData
          required property int index

          desktopId: modelData
          itemIndex: index
          slotSize: root.itemSize
          iconSize: root.iconSize
          magnification: root.magnification
          magnificationRadius: root.magnificationRadius
          pointerPosition: root.pointerPosition
          clickAction: root.clickAction
          autoHide: root.autoHide
          position: root.position
          vertical: root.vertical
          reorderOffset: root.reorderOffset(index)
          onDragStarted: itemIndex => {
            root.dragSource = itemIndex
            root.dragTarget = itemIndex
          }
          onDragMoved: mainPosition => root.updateDragTarget(mainPosition)
          onDragFinished: root.finishDrag()
          onAddApplicationRequested: appPicker.open()
          onRemoveRequested: desktopId => root.unpinRequested(desktopId)
          onAutoHideToggled: enabled => root.autoHideRequested(enabled)
          onContextMenuVisibilityChanged: visible => {
            root.openMenuCount = Math.max(0, root.openMenuCount + (visible ? 1 : -1))
          }
        }
      }
    }

    HoverHandler {
      id: pointer
    }
  }

  DockAppPicker {
    id: appPicker

    anchorItem: dockBackground
    position: root.position
    pinned: root.pinned
    onApplicationSelected: desktopId => root.pinRequested(desktopId)
  }

  HoverHandler {
    id: windowPointer
  }
}
