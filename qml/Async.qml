pragma Singleton
import QtQuick

// Calls that run in the background and answer later:
//   Async.call(grove, k => grove.info(k, path), r => ...)
// The start function gets a key to pass on; `done` gets the parsed JSON.
QtObject {
    property int seq: 0
    property var waiting: ({})
    property var hooked: []

    function call(controller, start, done) {
        if (!controller) return
        if (hooked.indexOf(controller) < 0) {
            hooked.push(controller)
            controller.asyncReply.connect(reply)
        }
        const k = "a" + (++seq)
        if (done) waiting[k] = done
        start(k)
        return k
    }
    function reply(k, json) {
        const done = waiting[k]
        if (!done) return
        delete waiting[k]
        let v = null
        try { v = JSON.parse(json) } catch (e) { v = json }
        done(v)
    }
}
