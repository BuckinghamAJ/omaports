import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property var names: ({})
  property var listeners: []
  property int uid: 0
  property string errorText: ""
  property bool loading: false
  property var pendingMeta: ({})
  property int enrichPid: 0
  property var rawProcess: []
  property var rawDocker: []
  property bool dockerPending: false
  property bool enrichPending: false
  property bool refreshPending: false
  property string dockerEndpoint: ""

  readonly property var parsedSettings: {
    var docker = settings && settings.includeDocker
    var udp = settings && settings.includeUdp
    return {
      killSignal: Model.killSignal(settings && settings.killSignal),
      includeUdp: udp === true || udp === "On",
      includeDocker: docker === true || docker === "On",
      ignoredPorts: String((settings && settings.ignoredPorts) || "53,631,5353"),
      httpsPorts: String((settings && settings.httpsPorts) || "443,8443"),
      refreshIntervalSec: Math.max(2, Math.min(120, parseInt(settings && settings.refreshIntervalSec, 10) || 5))
    }
  }

  readonly property int count: Model.devPortCount(listeners, uid)
  readonly property bool exposed: {
    for (var i = 0; i < listeners.length; i++) if (listeners[i].exposed) return true
    return false
  }

  function refresh() {
    if (root.loading) {
      root.refreshPending = true
      return
    }
    root.loading = true
    root.errorText = ""
    root.rawProcess = []
    root.rawDocker = []
    root.dockerPending = false
    root.enrichPending = false
    ssProc.running = false
    ssProc.command = root.cappedStdout(root.parsedSettings.includeUdp ? "ss -ltunpH" : "ss -ltnpH")
    ssProc.running = true
  }

  function finishCycle() {
    if (root.enrichPending || root.dockerPending) return
    root.loading = false
    if (root.refreshPending) {
      root.refreshPending = false
      Qt.callLater(root.refresh)
    }
  }

  function cappedStdout(producer) {
    return ["sh", "-c", producer + " | head -c " + String(Model.maxOutputBytes())]
  }

  function rebuild() {
    var ignored = Model.parsePortSet(root.parsedSettings.ignoredPorts)
    var rows = Model.dropIgnored(Model.mergeListeners(root.rawProcess, root.rawDocker), ignored)
    rows = Model.applyNames(rows, root.names)
    for (var i = 0; i < rows.length; i++) {
      rows[i] = Model.enrichProcess(rows[i], root.pendingMeta[String(rows[i].pid)] || {})
    }
    root.listeners = rows
    root.finishCycle()
  }

  function startEnrich(rows) {
    root.enrichPending = true
    var pids = []
    var seen = {}
    for (var i = 0; i < rows.length; i++) {
      var pid = rows[i].pid
      if (pid > 1 && !seen[pid]) {
        seen[pid] = true
        pids.push(pid)
      }
    }
    root.enrichQueue = pids
    root.pendingMeta = ({})
    enrichNext()
  }

  property var enrichQueue: []

  function enrichNext() {
    if (!root.enrichQueue.length) {
      root.enrichPending = false
      rebuild()
      return
    }
    root.enrichPid = root.enrichQueue.shift()
    statusProc.running = false
    statusProc.command = ["cat", "/proc/" + root.enrichPid + "/status"]
    statusProc.running = true
  }

  function storeMeta(pid, patch) {
    var next = ({})
    for (var key in root.pendingMeta) next[key] = root.pendingMeta[key]
    var cur = next[String(pid)] || {}
    var merged = {}
    for (var k in cur) merged[k] = cur[k]
    for (var p in patch) merged[p] = patch[p]
    next[String(pid)] = merged
    root.pendingMeta = next
  }

  Process {
    id: uidProc
    command: ["id", "-u"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.uid = parseInt(String(text || "").trim(), 10) || 0
    }
  }

  Process {
    id: ssProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.rawProcess = Model.parseSs(text)
        if (root.parsedSettings.includeDocker) {
          root.dockerPending = true
          root.dockerEndpoint = ""
          var envHost = String(Quickshell.env("DOCKER_HOST") || "")
          if (envHost && envHost.indexOf("unix://") !== 0) {
            root.errorText = "Remote Docker endpoint ignored"
            root.dockerPending = false
          } else {
            dockerContextProc.running = false
            dockerContextProc.command = ["docker", "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"]
            dockerContextProc.running = true
          }
        } else {
          root.rawDocker = []
          root.dockerPending = false
        }
        root.startEnrich(root.rawProcess)
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code !== 0 && code !== 141) {
        root.errorText = "Could not read listening sockets"
        root.rawProcess = []
        root.enrichPending = false
        root.dockerPending = false
        root.finishCycle()
      }
    }
  }

  Process {
    id: dockerContextProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.dockerEndpoint = String(text || "").trim()
    }
    onExited: function(code) {
      if (code !== 0 || root.dockerEndpoint.indexOf("unix://") !== 0) {
        root.rawDocker = []
        root.dockerPending = false
        if (code === 0 && root.dockerEndpoint)
          root.errorText = "Remote Docker context ignored"
        root.rebuild()
        return
      }
      dockerProc.running = false
      dockerProc.command = root.cappedStdout("docker ps --no-trunc --format '{{.ID}}\\t{{.Names}}\\t{{.Ports}}'")
      dockerProc.running = true
    }
  }

  Process {
    id: dockerProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.rawDocker = Model.parseDockerPs(text)
        root.dockerPending = false
        root.rebuild()
      }
    }
    onExited: function(code) {
      if (code !== 0 && code !== 141) {
        root.rawDocker = []
        root.dockerPending = false
        root.rebuild()
      }
    }
  }

  Process {
    id: statusProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.storeMeta(root.enrichPid, { uid: Model.parseStatusUid(text) })
    }
    onExited: {
      statProc.running = false
      statProc.command = ["cat", "/proc/" + root.enrichPid + "/stat"]
      statProc.running = true
    }
  }

  Process {
    id: statProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.storeMeta(root.enrichPid, { startTime: Model.parseStatStartTime(text) })
    }
    onExited: root.enrichNext()
  }
}
