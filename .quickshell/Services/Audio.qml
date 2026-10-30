pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// The default speaker and microphone, plus the volume keys' IPC:
//   qs ipc -p <this folder> call audio increment 5 | decrement 5 | mute | micmute
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    // Capped at 100% (no over-amplification).
    function changeVolume(delta) {
        const audio = sink?.audio;
        if (!audio)
            return;
        audio.muted = false;
        audio.volume = Math.max(0, Math.min(1, Math.round((audio.volume + delta) * 100) / 100));
    }

    function toggleMute() {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function toggleMicMute() {
        if (source?.audio)
            source.audio.muted = !source.audio.muted;
    }

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    IpcHandler {
        target: "audio"

        function increment(step: int): void {
            root.changeVolume((step > 0 ? step : 5) / 100);
        }
        function decrement(step: int): void {
            root.changeVolume(-(step > 0 ? step : 5) / 100);
        }
        function mute(): void {
            root.toggleMute();
        }
        function micmute(): void {
            root.toggleMicMute();
        }
    }
}
