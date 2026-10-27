import CryptoKit
import AudioToolbox
import Darwin
import Foundation
import Network
import Security

struct StreamState {
    var receiver = "Not paired"
    var transport = "Not connected"
    var sessionSeconds = 0.0
    var connected = false
    var streaming = false
    var status = "Disconnected"
    var packets: UInt64 = 0
    var bytes: UInt64 = 0
    var protectionEnabled = true
    var redundantPackets: UInt64 = 0
    var skippedCopies: UInt64 = 0
    var droppedFrames: UInt64 = 0
    var sendErrors: UInt64 = 0
    var reconnects: UInt64 = 0
    var completedStreams: UInt64 = 0
    var identityRejected = false
    var rttMS: Double?
    var captureAgeBlocks: UInt64 = 0
    var captureAgeSumMS = 0.0
    var captureAgeMaxMS = 0.0
}

/// Network work runs on queue, never on RemoteIO. PCM enters through a C SPSC queue.
final class AudioStreamer {
    private let queue = DispatchQueue(label: "covoo.network", qos: .userInitiated)
    private let pcmQueue: OpaquePointer
    private let samples: UnsafeMutablePointer<Float>
    private let pairing: PairingDetails
    private let update: (StreamState) -> Void
    private var state = StreamState()
    private var control: NWConnection?
    private var udp: NWConnection?
    private var timer: DispatchSourceTimer?
    private var controlBuffer = Data()
    private var retryAt = 0.0
    private var retryDelay = 1.0
    private var generation: UInt64 = 0
    private var connectionDeadline = 0.0
    private var lastControl = 0.0
    private var lastPing = 0.0
    private var pingID: UInt64 = 0
    private var pendingPing: (UInt64, Double)?
    private var lastPublish = 0.0
    private var enabled = false
    private var rate: UInt32?
    private var preparing: ((Result<Void, Error>) -> Void)?
    private var preparingDeadline = 0.0
    private var streamID: UInt64 = 0
    private var key: SymmetricKey?
    private var counter: UInt64 = 0
    private var inflight = 0
    private var pendingInfo: PMBlockInfo?
    private var pendingOffset = 0
    private var expectedPosition: UInt64?
    private var firstPosition: UInt64 = 0
    private var lastPosition: UInt64 = 0
    private var ending = false
    private var endDeadline = 0.0
    private var lastSendProgress = 0.0
    private var connectedAt: Double?
    private var endingCompletion: ((Result<StreamState, Error>) -> Void)?
    private var queueDropBaseline: UInt64 = 0
    private var protection = PacketProtection()
    private let lowLatency: Bool

    init(pairing: PairingDetails, packetProtection: Bool = true, lowLatency: Bool = false, update: @escaping (StreamState) -> Void) throws {
        guard let storage = pm_queue_create() else { throw WireFailure.invalid("Cannot allocate network queue") }
        pcmQueue = storage
        samples = .allocate(capacity: Int(PM_MAX_FRAMES))
        samples.initialize(repeating: 0, count: Int(PM_MAX_FRAMES))
        self.pairing = pairing
        self.update = update
        self.lowLatency = lowLatency
        state.receiver = "\(pairing.host):\(pairing.port)"
        state.protectionEnabled = packetProtection
    }

    deinit {
        timer?.cancel()
        control?.cancel()
        udp?.cancel()
        pm_queue_destroy(pcmQueue)
        samples.deinitialize(count: Int(PM_MAX_FRAMES))
        samples.deallocate()
    }

    func connect() {
        queue.async { [self] in
            enabled = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(lowLatency ? 1 : 5),
                leeway: .microseconds(lowLatency ? 100 : 1000))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer = timer
            timer.resume()
            attempt()
        }
    }

    /// Only CaptureService's worker is the producer. Object ownership must cover this call.
    func submit(_ samples: UnsafePointer<Float>, info: PMBlockInfo) {
        _ = pm_queue_push(pcmQueue, samples, info)
    }

    func begin(sampleRate: UInt32, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            guard state.connected, rate == nil, !ending else {
                completion(.failure(WireFailure.invalid("Connect to the receiver before streaming.")))
                return
            }
            rate = sampleRate
            clearPCM()
            state.packets = 0; state.bytes = 0; state.droppedFrames = 0
            state.redundantPackets = 0; state.skippedCopies = 0
            state.captureAgeBlocks = 0; state.captureAgeSumMS = 0; state.captureAgeMaxMS = 0
            protection = PacketProtection()
            state.sendErrors = 0; state.reconnects = 0
            queueDropBaseline = pm_queue_stats(pcmQueue).dropped_frames
            preparing = completion
            preparingDeadline = now + 5
            sendStart()
        }
    }

    func end(completion: ((Result<StreamState, Error>) -> Void)? = nil) {
        queue.async { [self] in
            endingCompletion = completion
            preparing = nil
            if rate != nil, state.streaming {
                ending = true
                endDeadline = now + 2
                pump()
            } else {
                rate = nil; clearPCM()
                finishEnding(.failure(WireFailure.invalid("No active network stream at stop; receiver summary unavailable.")))
            }
        }
    }

    func disconnect() {
        queue.async { [self] in
            enabled = false
            generation &+= 1
            control?.cancel(); control = nil
            udp?.cancel(); udp = nil
            timer?.cancel(); timer = nil
            key = nil; rate = nil
            clearCopies()
            failPreparation("Disconnected")
            finishEnding(.failure(WireFailure.invalid("Disconnected before receiver finalized recording")))
            clearPCM()
            state.connected = false; state.streaming = false; state.status = "Disconnected"
            publish()
        }
    }

    private var now: Double { pm_ticks_to_seconds(mach_absolute_time()) }

    private func attempt() {
        guard enabled else { return }
        generation &+= 1
        let attempt = generation
        state.identityRejected = false
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        let pin = pairing.fingerprint
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { [weak self] _, trust, complete in
            let reference = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let chain = SecTrustCopyCertificateChain(reference) as? [SecCertificate], let leaf = chain.first else { complete(false); return }
            let certificate = SecCertificateCopyData(leaf) as Data
            // The full certificate fingerprint was supplied out of band. Discovery never supplies trust.
            let matches = Data(SHA256.hash(data: certificate)) == pin
            if !matches { self?.state.identityRejected = true }
            complete(matches)
        }, queue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.prohibitedInterfaceTypes = [.cellular]
        let connection = NWConnection(host: NWEndpoint.Host(pairing.host), port: NWEndpoint.Port(rawValue: pairing.port)!, using: parameters)
        control = connection
        controlBuffer = Data()
        connectionDeadline = now + 8
        state.status = "Connecting"
        state.connected = false
        connection.stateUpdateHandler = { [weak self] status in
            guard let self, self.generation == attempt else { return }
            switch status {
            case .ready:
                self.lastControl = self.now
                self.sendControl(["type":"hello", "version":1, "token":self.pairing.token, "device":"iPhone"])
                self.receiveControl(connection, generation: attempt)
            case .waiting(let error), .failed(let error):
                self.fail(self.state.identityRejected ? "Receiver certificate fingerprint mismatch." : "Connection: \(error.localizedDescription). Check receiver and Local Network permission.")
            default: break
            }
        }
        connection.start(queue: queue)
        publish()
    }

    private func receiveControl(_ connection: NWConnection, generation: UInt64) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self, generation == self.generation else { return }
            if let data { self.controlBuffer.append(data) }
            do {
                while self.controlBuffer.count >= 4 {
                    let length = self.controlBuffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    guard length > 0, length <= 4096 else { throw WireFailure.invalid("Control size limit") }
                    guard self.controlBuffer.count >= 4 + Int(length) else { break }
                    let body = self.controlBuffer.subdata(in: 4..<4+Int(length))
                    self.controlBuffer = Data(self.controlBuffer.dropFirst(4+Int(length)))
                    guard let message = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw WireFailure.invalid("Invalid control response") }
                    try self.handle(message)
                }
                guard self.controlBuffer.count <= 8192 else { throw WireFailure.invalid("Control buffer limit") }
            } catch { self.fail(error.localizedDescription); return }
            if let error { self.fail(error.localizedDescription) }
            else if complete { self.fail("Receiver disconnected") }
            else { self.receiveControl(connection, generation: generation) }
        }
    }

    private func handle(_ message: [String: Any]) throws {
        lastControl = now
        guard let type = message["type"] as? String else { throw WireFailure.invalid("Missing response type") }
        switch type {
        case "ready":
            guard (message["version"] as? Int) == 1, (message["max_frames"] as? Int) == 240,
                (message["format"] as? String) == "f32le" else { throw WireFailure.invalid("Receiver capabilities incompatible") }
            state.connected = true
            connectedAt = now
            state.transport = control?.currentPath?.usesInterfaceType(.wifi) == true ? "Wi-Fi UDP / TLS control" : "LAN UDP / TLS control"
            state.status = "Connected"
            retryDelay = 1
            if rate != nil { sendStart() }
            publish()
        case "started":
            guard rate != nil, let id = message["session_id"] as? String, id.count == 16,
                let session = UInt64(id, radix: 16), let hex = message["key"] as? String,
                let secret = Data(strictHex: hex), secret.count == 32,
                let port = message["udp_port"] as? Int, port > 0, port <= 65535,
                (message["frames"] as? Int) == 240 else { throw WireFailure.invalid("Invalid stream negotiation") }
            streamID = session
            key = SymmetricKey(data: secret)
            counter = 0; firstPosition = 0; lastPosition = 0
            clearCopies()
            lastSendProgress = now
            expectedPosition = nil; inflight = 0
            let udpParameters = NWParameters.udp
            udpParameters.prohibitedInterfaceTypes = [.cellular]
            let connection = NWConnection(host: NWEndpoint.Host(pairing.host), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: udpParameters)
            udp = connection
            let epoch = generation
            connection.stateUpdateHandler = { [weak self] status in
                guard let self, self.generation == epoch else { return }
                switch status {
                case .ready:
                    self.state.streaming = true; self.state.status = "Streaming"
                    let completion = self.preparing; self.preparing = nil
                    completion?(.success(()))
                    self.publish(); self.pump()
                case .failed(let error), .waiting(let error): self.fail("UDP: \(error.localizedDescription)")
                default: break
                }
            }
            connection.start(queue: queue)
        case "pong":
            if let id = (message["id"] as? NSNumber)?.uint64Value, let pendingPing, id == pendingPing.0 {
                state.rttMS = (now - pendingPing.1)*1000
                self.pendingPing = nil
            }
        case "stopped":
            state.completedStreams += 1
            state.streaming = false; state.status = "Connected; receiver recording saved"
            udp?.cancel(); udp = nil; key = nil
            finishEnding(.success(snapshot()))
            publish()
        case "error": throw WireFailure.invalid(message["message"] as? String ?? "Receiver rejected request")
        default: throw WireFailure.invalid("Unexpected receiver response")
        }
    }

    private func sendControl(_ message: [String: Any]) {
        guard let control else { return }
        do {
            let body = try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
            guard body.count <= 4096 else { throw WireFailure.invalid("Control size limit") }
            var length = UInt32(body.count).bigEndian
            var packet = Swift.withUnsafeBytes(of: &length) { Data($0) }
            packet.append(body)
            let epoch = generation
            control.send(content: packet, completion: .contentProcessed { [weak self] error in
                guard let self, self.generation == epoch else { return }
                if let error { self.fail(error.localizedDescription) }
            })
        } catch { fail(error.localizedDescription) }
    }

    private func sendStart() {
        if let rate { sendControl(["type":"start", "sample_rate":rate, "channels":1, "format":"f32le"]) }
    }

    private func pump() {
        guard state.streaming, udp != nil, let key, let rate else { return }
        // Reserve half the in-flight budget for new audio. Expire old copies
        // instead of adding latency when the network worker stalls.
        while inflight < 4, let packet = protection.takeDue(at: now) {
            sendAudio(packet, redundant: true)
        }
        while inflight < 8 {
            if pendingInfo == nil {
                var info = PMBlockInfo()
                guard pm_queue_pop(pcmQueue, samples, UInt32(PM_MAX_FRAMES), &info) else { break }
                let age = now - pm_ticks_to_seconds(info.host_time)
                if info.time_flags & AudioTimeStampFlags.hostTimeValid.rawValue != 0, age >= 0 {
                    state.captureAgeBlocks += 1
                    state.captureAgeSumMS += age * 1000
                    state.captureAgeMaxMS = max(state.captureAgeMaxMS, age * 1000)
                }
                if info.time_flags & AudioTimeStampFlags.hostTimeValid.rawValue == 0 || age > 0.1 {
                    state.droppedFrames += UInt64(info.frames)
                    continue
                }
                pendingInfo = info; pendingOffset = 0
            }
            guard let info = pendingInfo else { break }
            if now - pm_ticks_to_seconds(info.host_time) > 0.1 {
                state.droppedFrames += UInt64(info.frames) - UInt64(pendingOffset)
                pendingInfo = nil
                continue
            }
            let count = min(240, Int(info.frames) - pendingOffset)
            let position = info.sample_position + UInt64(pendingOffset)
            let timestamp = UInt64(max(0, pm_ticks_to_seconds(info.host_time)*1e9)) + UInt64(pendingOffset)*1_000_000_000/UInt64(rate)
            let discontinuity = expectedPosition.map { $0 != position } ?? false
            do {
                guard counter < UInt64.max else { throw WireFailure.invalid("Stream nonce exhausted") }
                let plain = try WireProtocol.encodePCM(session: streamID, sequence: UInt32(truncatingIfNeeded: counter),
                    position: position, captureNS: timestamp, rate: rate,
                    samples: UnsafeBufferPointer(start: samples.advanced(by: pendingOffset), count: count), discontinuity: discontinuity)
                let reserved = counter
                counter += 1
                let packet = try WireProtocol.seal(plain, session: streamID, counter: reserved, key: key)
                if reserved == 0 { firstPosition = position }
                lastPosition = position + UInt64(count)
                expectedPosition = lastPosition
                state.packets += 1
                sendAudio(packet, redundant: false)
                if state.protectionEnabled { protection.schedule(packet, at: now) }
            } catch { fail(error.localizedDescription); return }
            pendingOffset += count
            if pendingOffset == Int(info.frames) { pendingInfo = nil }
        }
        if ending, pendingInfo == nil, pm_queue_stats(pcmQueue).occupancy == 0, protection.count == 0, inflight == 0 {
            sendStop()
        }
    }

    private func sendAudio(_ packet: Data, redundant: Bool) {
        guard let udp else { return }
        state.bytes += UInt64(packet.count)
        if redundant { state.redundantPackets += 1 }
        inflight += 1
        let epoch = generation
        udp.send(content: packet, completion: .contentProcessed { [weak self] error in
            guard let self, self.generation == epoch else { return }
            self.inflight -= 1
            self.lastSendProgress = self.now
            if let error { self.state.sendErrors += 1; self.fail(error.localizedDescription) }
            else { self.pump() }
        })
    }

    private func clearCopies() {
        state.skippedCopies += protection.skipped + UInt64(protection.count)
        protection = PacketProtection()
    }

    private func sendStop() {
        ending = false
        rate = nil
        sendControl(["type":"stop", "packets":counter, "first_position":firstPosition, "last_position":lastPosition])
    }

    private func clearPCM() {
        var info = PMBlockInfo()
        if let pendingInfo { state.droppedFrames += UInt64(pendingInfo.frames) - UInt64(pendingOffset) }
        pendingInfo = nil
        while pm_queue_pop(pcmQueue, samples, UInt32(PM_MAX_FRAMES), &info) { state.droppedFrames += UInt64(info.frames) }
    }

    private func failPreparation(_ message: String) {
        let completion = preparing; preparing = nil
        completion?(.failure(WireFailure.invalid(message)))
    }

    private func finishEnding(_ result: Result<StreamState, Error>) {
        let completion = endingCompletion
        endingCompletion = nil
        completion?(result)
    }

    private func fail(_ message: String) {
        guard enabled else { return }
        let wasConnected = state.connected
        generation &+= 1
        control?.cancel(); control = nil
        udp?.cancel(); udp = nil
        key = nil; inflight = 0
        clearCopies()
        state.connected = false; state.streaming = false; state.rttMS = nil
        state.transport = "Not connected"
        if preparing != nil { failPreparation(message); rate = nil }
        if ending { ending = false; rate = nil }
        finishEnding(.failure(WireFailure.invalid(message)))
        clearPCM()
        if wasConnected { state.reconnects += 1 }
        enabled = !state.identityRejected
        state.status = message + (enabled ? " Retrying." : " Scan a fresh pairing QR.")
        retryAt = now + retryDelay
        retryDelay = min(5, retryDelay*2)
        publish()
    }

    private func tick() {
        if control == nil, enabled, now >= retryAt { attempt() }
        if control != nil, !state.connected, now > connectionDeadline { fail("Pairing timed out") }
        if state.connected {
            if now - lastControl > 5 { fail("Receiver heartbeat timed out"); return }
            if now - lastPing >= 1 {
                lastPing = now; pingID &+= 1; pendingPing = (pingID, now)
                sendControl(["type":"ping", "id":pingID])
            }
        }
        if preparing != nil, now > preparingDeadline { fail("Stream start timed out"); return }
        if state.streaming, inflight > 0, now - lastSendProgress > 0.5 { fail("UDP sends stalled"); return }
        if ending, now > endDeadline {
            clearPCM()
            clearCopies()
            if inflight == 0 { sendStop() } else { fail("Stream stop timed out") }
        }
        if endingCompletion != nil, !ending, now > endDeadline + 5 { fail("Receiver finalization timed out"); return }
        if state.streaming { pump() }
        else if preparing == nil { clearPCM() }
        if now - lastPublish >= 0.25 { publish() }
    }

    private func snapshot() -> StreamState {
        var snapshot = state
        snapshot.skippedCopies += protection.skipped
        snapshot.sessionSeconds = state.connected ? now - (connectedAt ?? now) : 0
        snapshot.droppedFrames += pm_queue_stats(pcmQueue).dropped_frames - queueDropBaseline
        return snapshot
    }

    private func publish() {
        lastPublish = now
        update(snapshot())
    }
}
