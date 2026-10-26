import AVFoundation
import AudioToolbox
import Foundation

struct CaptureState {
    var recording = false
    var status = "Ready"
    var input = "Not queried"
    var sampleRate = 0.0
    var bufferMS = 0.0
    var hardwareChannels = 0
    var deviceFormat = "Not queried"
    var frames: UInt64 = 0
    var droppedFrames: UInt64 = 0
    var queueBlocks: UInt64 = 0
    var highWater: UInt64 = 0
    var callbacks: UInt64 = 0
    var renderErrors: UInt64 = 0
    var discontinuities: UInt64 = 0
    var maxCallbackMS = 0.0
    var rmsDB = -120.0
    var peakDB = -120.0
    var files: [URL] = []
}

private struct CaptureFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// All mutable state belongs to worker. Only the C callback touches the producer.
final class CaptureService {
    private let worker = DispatchQueue(label: "phonemic.capture.writer", qos: .userInitiated)
    private var unit: AudioUnit?
    private var capture: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private var file: AVAudioFile?
    private var buffer: AVAudioPCMBuffer?
    private var timeline: FileHandle?
    private var recordingURL: URL?
    private var reportURL: URL?
    private var timelineURL: URL?
    private var state = CaptureState()
    private var publish: ((CaptureState) -> Void)?
    private var expectedPosition: UInt64 = 0
    private var expectedSampleTime: Double?
    private var lastHostTime: UInt64?
    private var lastPublish = Date.distantPast
    private var events: [String] = []
    private var startedAt: Date?
    private var routeSignature = ""
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var lastFrames: UInt64 = 0
    private var streamer: AudioStreamer?

    func routeChanged() {
        worker.async { [self] in
            guard state.recording else { return }
            if currentRouteSignature() != routeSignature {
                finish(reason: "Audio route changed. Start a new recording.")
            }
        }
    }

    private func currentRouteSignature() -> String {
        let session = AVAudioSession.sharedInstance()
        return (session.currentRoute.inputs + session.currentRoute.outputs).map { $0.uid }.joined(separator: "/")
            + "/\(session.sampleRate)/\(session.ioBufferDuration)/\(session.inputNumberOfChannels)"
    }

    func start(streamer: AudioStreamer? = nil, update: @escaping (CaptureState) -> Void) {
        worker.async { [self] in
            publish = update
            guard unit == nil else {
                state.status = "Audio cleanup failed. Restart the app."
                emit()
                return
            }
            state = CaptureState()
            self.streamer = streamer
            events = []
            expectedPosition = 0
            expectedSampleTime = nil
            lastHostTime = nil
            recordingURL = nil
            reportURL = nil
            timelineURL = nil
            startedAt = nil
            do {
                try configureAndStart()
            } catch {
                finish(reason: "Start failed: \(error.localizedDescription)")
            }
        }
    }

    func stop(reason: String = "Stopped") {
        worker.async { [self] in
            guard state.recording || unit != nil else { return }
            finish(reason: reason)
        }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        if status != noErr { throw CaptureFailure(message: "\(operation): OSStatus \(status)") }
    }

    private func configureAndStart() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        guard session.isInputAvailable else { throw CaptureFailure(message: "No audio input available") }
        guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else {
            throw CaptureFailure(message: "Built-in microphone unavailable. Disconnect external audio inputs.")
        }
        try session.setPreferredInput(builtIn)
        try session.setPreferredInputNumberOfChannels(1)

        // Read actual values after activation and routing, never display preferences as actual.
        state.sampleRate = session.sampleRate
        state.bufferMS = session.ioBufferDuration * 1000
        state.hardwareChannels = session.inputNumberOfChannels
        state.input = session.currentRoute.inputs.map { $0.portName }.joined(separator: ", ")
        guard state.sampleRate > 0, state.hardwareChannels == 1 else {
            throw CaptureFailure(message: "M1 requires a mono input route")
        }

        var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO, componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw CaptureFailure(message: "RemoteIO component unavailable")
        }
        var instance: AudioUnit?
        try check(AudioComponentInstanceNew(component, &instance), "Create RemoteIO")
        guard let instance else { throw CaptureFailure(message: "RemoteIO instance missing") }
        unit = instance
        var enabled: UInt32 = 1
        var disabled: UInt32 = 0
        try check(AudioUnitSetProperty(instance, kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input, 1, &enabled, UInt32(MemoryLayout<UInt32>.size)), "Enable input")
        try check(AudioUnitSetProperty(instance, kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output, 0, &disabled, UInt32(MemoryLayout<UInt32>.size)), "Disable output")
        var format = AudioStreamBasicDescription(mSampleRate: state.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        try check(AudioUnitSetProperty(instance, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output, 1, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)), "Set client format")
        var maximum: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioUnitGetProperty(instance, kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global, 0, &maximum, &size), "Query maximum callback size")
        guard maximum > 0, maximum <= UInt32(PM_MAX_FRAMES) else {
            throw CaptureFailure(message: "Unsupported maximum callback size: \(maximum)")
        }
        guard let context = pm_capture_create(instance) else {
            throw CaptureFailure(message: "Cannot allocate lock-free capture buffers")
        }
        capture = context
        var callback = pm_capture_callback(context)
        try check(AudioUnitSetProperty(instance, kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global, 1, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "Set input callback")
        try check(AudioUnitSetProperty(instance, kAudioUnitProperty_ShouldAllocateBuffer,
            kAudioUnitScope_Output, 1, &disabled, UInt32(MemoryLayout<UInt32>.size)), "Use preallocated render buffer")
        try check(AudioUnitInitialize(instance), "Initialize RemoteIO")
        var actualClient = AudioStreamBasicDescription()
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(instance, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output, 1, &actualClient, &size), "Read client format")
        guard actualClient.mSampleRate == state.sampleRate, actualClient.mChannelsPerFrame == 1,
            actualClient.mFormatID == kAudioFormatLinearPCM, actualClient.mBytesPerFrame == 4,
            actualClient.mBitsPerChannel == 32,
            actualClient.mFormatFlags & kAudioFormatFlagIsFloat != 0,
            actualClient.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 else {
            throw CaptureFailure(message: "RemoteIO did not grant the requested client format")
        }
        var device = AudioStreamBasicDescription()
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(instance, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input, 1, &device, &size), "Read device-side format")
        state.deviceFormat = "\(device.mSampleRate) Hz, \(device.mChannelsPerFrame) ch, \(device.mBitsPerChannel) bits, flags \(device.mFormatFlags)"
        routeSignature = currentRouteSignature()

        let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let base = directory.appendingPathComponent("capture-\(UUID().uuidString)")
        let wav = base.appendingPathExtension("wav")
        recordingURL = wav
        reportURL = base.appendingPathExtension("json")
        timelineURL = base.appendingPathExtension("csv")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: state.sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        file = try AVAudioFile(forWriting: wav, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let file, let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(PM_MAX_FRAMES)), pcm.floatChannelData != nil else {
            throw CaptureFailure(message: "Cannot allocate writer buffer")
        }
        buffer = pcm
        guard let timelineURL, FileManager.default.createFile(atPath: timelineURL.path, contents: nil) else {
            throw CaptureFailure(message: "Cannot create timestamp log")
        }
        timeline = try FileHandle(forWritingTo: timelineURL)
        try timeline?.write(contentsOf: Data("sequence,sample_position,host_ticks,sample_time,time_flags,frames,render_ticks\n".utf8))
        events.append("RemoteIO mono Float32 client format, measurement mode, no voice processing unit")
        events.append("maximum_frames_per_slice=\(maximum)")
        if let streamer {
            state.status = "Starting stream"
            streamer.begin(sampleRate: UInt32(state.sampleRate)) { [weak self] result in
                guard let self else { return }
                self.worker.async {
                    guard self.unit != nil, self.file != nil else { return }
                    do { try result.get(); try self.startInput() }
                    catch { self.finish(reason: "Stream start failed: \(error.localizedDescription)") }
                }
            }
        } else { try startInput() }
    }

    private func startInput() throws {
        guard let unit else { throw CaptureFailure(message: "Capture was cancelled") }
        guard currentRouteSignature() == routeSignature else { throw CaptureFailure(message: "Audio route changed during startup. Start again.") }
        startedAt = Date()
        lastProgress = ProcessInfo.processInfo.systemUptime
        lastFrames = 0
        try check(AudioOutputUnitStart(unit), "Start input")
        state.recording = true
        state.status = "Recording"
        let timer = DispatchSource.makeTimerSource(queue: worker)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
        emit()
    }

    private func drain() throws {
        guard let capture, let buffer, let samples = buffer.floatChannelData?[0], let file else { return }
        var info = PMBlockInfo()
        // Bound work per timer firing even if the producer remains active.
        for _ in 0..<PM_QUEUE_SLOTS {
            guard pm_capture_pop(capture, samples, UInt32(PM_MAX_FRAMES), &info) else { break }
            if info.sample_position != expectedPosition { state.discontinuities += 1 }
            expectedPosition = info.sample_position + UInt64(info.frames)
            if info.time_flags & AudioTimeStampFlags.sampleTimeValid.rawValue != 0 {
                if let expectedSampleTime, abs(info.sample_time - expectedSampleTime) > 0.5 {
                    state.discontinuities += 1
                }
                expectedSampleTime = info.sample_time + Double(info.frames)
            } else { expectedSampleTime = nil }
            if info.time_flags & AudioTimeStampFlags.hostTimeValid.rawValue != 0 {
                if let lastHostTime, info.host_time <= lastHostTime { state.discontinuities += 1 }
                lastHostTime = info.host_time
            }
            var sum = 0.0
            var peak = 0.0
            for index in 0..<Int(info.frames) {
                let value = Double(samples[index])
                guard value.isFinite else { throw CaptureFailure(message: "Nonfinite PCM sample") }
                sum += value * value
                peak = max(peak, abs(value))
            }
            state.rmsDB = 20 * log10(max(1e-6, sqrt(sum / Double(info.frames))))
            state.peakDB = 20 * log10(max(1e-6, peak))
            buffer.frameLength = info.frames
            streamer?.submit(samples, info: info)
            try file.write(from: buffer)
            state.frames += UInt64(info.frames)
            let row = "\(info.sequence),\(info.sample_position),\(info.host_time),\(info.sample_time),\(info.time_flags),\(info.frames),\(info.callback_ticks)\n"
            try timeline?.write(contentsOf: Data(row.utf8))
        }
    }

    private func tick() {
        do {
            try drain()
            updateCounters()
            if state.frames != lastFrames {
                lastFrames = state.frames
                lastProgress = ProcessInfo.processInfo.systemUptime
            } else if ProcessInfo.processInfo.systemUptime - lastProgress > 3 {
                finish(reason: "No microphone frames for 3 seconds. Start again.")
                return
            }
            if state.renderErrors > 0 {
                finish(reason: "Capture error. See report.")
                return
            }
            if Date().timeIntervalSince(lastPublish) >= 0.25 { emit() }
        } catch { finish(reason: "Recording failed: \(error.localizedDescription)", drainRemaining: false) }
    }

    private func updateCounters() {
        guard let capture else { return }
        let stats = pm_capture_stats(capture)
        state.callbacks = stats.callbacks
        state.droppedFrames = stats.queue.dropped_frames
        state.queueBlocks = stats.queue.occupancy
        state.highWater = stats.queue.high_water
        state.renderErrors = stats.render_errors + stats.oversized_callbacks
        state.maxCallbackMS = pm_ticks_to_seconds(stats.max_callback_ticks) * 1000
    }

    private func finish(reason: String, drainRemaining: Bool = true) {
        timer?.cancel()
        timer = nil
        events.append(reason)
        var disposed = true
        if let unit {
            let stopped = AudioOutputUnitStop(unit)
            if stopped != noErr { events.append("Stop OSStatus \(stopped)") }
            let uninitialized = AudioUnitUninitialize(unit)
            if uninitialized != noErr { events.append("Uninitialize OSStatus \(uninitialized)") }
            let result = AudioComponentInstanceDispose(unit)
            disposed = result == noErr
            if !disposed { events.append("Dispose OSStatus \(result); context retained, restart required") }
        }
        if disposed { unit = nil }
        if drainRemaining {
            do { try drain() } catch { events.append("Final drain failed: \(error.localizedDescription)") }
        }
        updateCounters()
        streamer?.end()
        let finalStats = capture.map { pm_capture_stats($0) }
        // Releasing the last AVAudioFile reference finalizes the WAV header.
        file = nil
        buffer = nil
        do { try timeline?.close() } catch { events.append("Timestamp log close failed: \(error.localizedDescription)") }
        timeline = nil
        if disposed, let capture { pm_capture_destroy(capture); self.capture = nil }
        state.recording = false
        state.status = reason
        if !disposed { state.status = "Audio cleanup failed. Restart the app." }
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { events.append("Session deactivate failed: \(error.localizedDescription)") }

        state.files = []
        var validWAV = false
        if let recordingURL, state.frames > 0 {
            do {
                let check = try AVAudioFile(forReading: recordingURL)
                validWAV = UInt64(check.length) == state.frames && check.fileFormat.channelCount == 1
                    && check.fileFormat.sampleRate == state.sampleRate
                if validWAV { state.files.append(recordingURL) }
                else { events.append("WAV structural validation failed") }
            } catch { events.append("WAV reopen failed: \(error.localizedDescription)") }
        }
        if !validWAV, state.frames > 0 { state.status = "Recording file validation failed. See report." }
        let renderedFrames = finalStats?.rendered_frames ?? 0
        if let reportURL {
            let report: [String: Any] = ["sample_rate_hz": state.sampleRate,
                "actual_io_buffer_ms": state.bufferMS, "actual_input_channels": state.hardwareChannels,
                "input": state.input, "device_side_format": state.deviceFormat,
                "client_format": "mono Float32", "wire_transport": streamer == nil ? "off" : "TLS control + encrypted UDP",
                "frames_written": state.frames, "duration_from_written_frames_seconds": state.sampleRate > 0 ? Double(state.frames) / state.sampleRate : 0,
                "wall_duration_seconds": startedAt.map { Date().timeIntervalSince($0) } ?? 0,
                "callbacks": state.callbacks, "render_errors": state.renderErrors,
                "rendered_frames": renderedFrames,
                "unwritten_rendered_frames": renderedFrames > state.frames ? renderedFrames - state.frames : 0,
                "queue_blocks_at_stop": state.queueBlocks,
                "dropped_blocks": finalStats?.queue.dropped_blocks ?? 0,
                "oversized_callbacks": finalStats?.oversized_callbacks ?? 0,
                "last_render_status": finalStats?.last_status ?? 0,
                "dropped_frames": state.droppedFrames, "queue_high_water_blocks": state.highWater,
                "discontinuities": state.discontinuities, "max_successful_callback_ms": state.maxCallbackMS,
                "wav_structurally_valid": validWAV, "events": events,
                "end_to_end_latency": "not measured", "ios_version": ProcessInfo.processInfo.operatingSystemVersionString]
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: reportURL, options: .atomic)
                state.files.append(reportURL)
            } catch { state.status += "; report failed: \(error.localizedDescription)" }
        }
        if let timelineURL, FileManager.default.fileExists(atPath: timelineURL.path) { state.files.append(timelineURL) }
        emit()
    }

    private func emit() {
        lastPublish = Date()
        publish?(state)
    }
}
