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

  readonly property var parsedSettings: {
    var docker = settings && settings.includeDocker
    var udp = settings && settings.includeUdp
    return {
      killSignal: Model.killSignal(settings && settings.killSignal),
      includeUdp: udp === true || udp === "On",
      includeDocker: docker !== false && docker !== "Off",
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
    root.loading = true
    root.errorText = ""
    root.rawProcess = []
    root.rawDocker = []
    ssProc.running = false
    ssProc.command = root.cappedStdout(root.parsedSettings.includeUdp ? "ss -ltunpH" : "ss -ltnpH")
    ssProc.running = true
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
    root.loading = false
  }

  function startEnrich(rows) {
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
        root.startEnrich(root.rawProcess)
        if (root.parsedSettings.includeDocker) {
          root.dockerPending = true
          dockerProc.running = false
          dockerProc.command = root.cappedStdout("docker ps --format '{{.ID}}\\t{{.Names}}\\t{{.Ports}}'")
          dockerProc.running = true
        } else {
          root.rawDocker = []
        }
      }
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code !== 0 && code !== 141) {
        root.errorText = "Could not read listening sockets"
        root.rawProcess = []
        root.loading = false
      }
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
    onExited: {
      cmdProc.running = false
      cmdProc.command = ["cat", "/proc/" + root.enrichPid + "/cmdline"]
      cmdProc.running = true
    }
  }

  Process {
    id: cmdProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.storeMeta(root.enrichPid, { command: Model.parseCmdline(text) })
    }
    onExited: {
      cwdProc.running = false
      cwdProc.command = ["readlink", "/proc/" + root.enrichPid + "/cwd"]
      cwdProc.running = true
    }
  }

  Process {
    id: cwdProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.storeMeta(root.enrichPid, { cwd: String(text || "").trim() })
    }
    onExited: {
      exeProc.running = false
      exeProc.command = ["readlink", "/proc/" + root.enrichPid + "/exe"]
      exeProc.running = true
    }
  }

  Process {
    id: exeProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.storeMeta(root.enrichPid, { exe: String(text || "").trim() })
    }
    onExited: root.enrichNext()
  }
}
