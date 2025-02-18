import Foundation
import Flutter
import HaishinKit
import AVFoundation
import VideoToolbox

class RTMPStreamHandler: NSObject, MethodCallHandler, RTMPStreamDelegate {
    func rtmpStream(_ stream: HaishinKit.RTMPStream, publishInsufficientBWOccured connection: HaishinKit.RTMPConnection) {
        
    }
    
    func rtmpStream(_ stream: HaishinKit.RTMPStream, publishSufficientBWOccured connection: HaishinKit.RTMPConnection) {
        
    }
    
    func rtmpStream(_ stream: HaishinKit.RTMPStream, didOutput audio: AVAudioBuffer, presentationTimeStamp: CMTime) {
        
    }
    
    func rtmpStream(_ stream: HaishinKit.RTMPStream, didOutput video: CMSampleBuffer) {
        
    }
    
    func rtmpStream(_ stream: HaishinKit.RTMPStream, updatedStats connection: HaishinKit.RTMPConnection) {
        let result = Double(stream.info.currentBytesPerSecond) / 125_000        
        var map: [String: Any?] = [:]
        map["type"] = "updatedStats"
        map["data"] = ["fps": stream.currentFPS, "mbps" : String(format: "%.1f", result)] as [String : Any]
        eventSink?(map)
    }
    
    func rtmpStream(_ stream: HaishinKit.RTMPStream, videoCodecErrorOccurred error: HaishinKit.VideoCodec.Error) {
        
    }
    
    func rtmpStreamDidClear(_ stream: HaishinKit.RTMPStream) {
        
    }
    
    private let plugin: SwiftHaishinKitPlugin
    private var instance: RTMPStream?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    init(plugin: SwiftHaishinKitPlugin, handler: RTMPConnectionHandler) {
        self.plugin = plugin
        super.init()
        let id = Int(bitPattern: ObjectIdentifier(self))
        if let registrar = plugin.registrar {
            self.eventChannel = FlutterEventChannel(name: "com.haishinkit.eventchannel/\(id)", binaryMessenger: registrar.messenger())
            self.eventChannel?.setStreamHandler(self)
        } else {
            self.eventChannel = nil
        }
        if let connection = handler.instance {
            let instance = RTMPStream(connection: connection)
            instance.captureSettings = [
                        .fps: 30,
                        .sessionPreset: AVCaptureSession.Preset.hd1280x720,
                        .continuousAutofocus: false,
                        .continuousExposure: false,
                        .preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode.standard
                    ]

            instance.videoSettings[.profileLevel] = kVTProfileLevel_H264_Main_5_0
            instance.delegate = self
            instance.addEventListener(.rtmpStatus, selector: #selector(RTMPStreamHandler.handler), observer: self)
            if let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) {
                instance.orientation = orientation
            }
            NotificationCenter.default.addObserver(self, selector: #selector(on(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
            self.instance = instance
        }        
        self.eventSink = handler.eventSink
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard
            let arguments = call.arguments as? [String: Any?] else {
            return
        }
        switch call.method {
        case "RtmpStream#setAudioSettings":
            guard
                let settings = arguments["settings"] as? [String: Any?] else {
                return
            }
            if let muted = settings["muted"] as? Bool {
                instance?.audioSettings[.muted] = muted
            }
            if let bitrate = settings["bitrate"] as? NSNumber {
                instance?.audioSettings[.bitrate] = bitrate.intValue
            }
            result(nil)
        case "RtmpStream#setVideoSettings":
            guard
                let settings = arguments["settings"] as? [String: Any?] else {
                return
            }
            if let muted = settings["muted"] as? Bool {
                instance?.videoSettings[.muted] = muted
            }
            if let bitrate = settings["bitrate"] as? NSNumber {
                instance?.videoSettings[.bitrate] = bitrate.intValue
            }
            if let width = settings["width"] as? NSNumber {
                instance?.videoSettings[.width] = width.intValue
            }
            if let height = settings["height"] as? NSNumber {
                instance?.videoSettings[.height] = height.intValue
            }
            if let frameInterval = settings["frameInterval"] as? NSNumber {
                instance?.videoSettings[.maxKeyFrameIntervalDuration] = frameInterval.intValue
            }
            
            result(nil)
        case "RtmpStream#setCaptureSettings":
            guard
                let settings = arguments["settings"] as? [String: Any?] else {
                return
            }
            if let fps = settings["fps"] as? NSNumber {
                instance?.captureSettings[.fps] = fps.intValue
            }
            if let continuousAutofocus = settings["continuousAutofocus"] as? Bool {
                instance?.captureSettings[.continuousAutofocus] = continuousAutofocus
            }
            if let continuousExposure = settings["continuousExposure"] as? Bool {
                instance?.captureSettings[.continuousExposure] = continuousExposure
            }
            if let isVideoMirrored = settings["isVideoMirrored"] as? Bool {
                instance?.captureSettings[.isVideoMirrored] = isVideoMirrored
            }
            result(nil)
        case "RtmpStream#attachAudio":
            let source = arguments["source"] as? [String: Any?]
            if source == nil {
                instance?.attachAudio(nil)
            } else {
                instance?.attachAudio(AVCaptureDevice.default(for: .audio))
            }
            result(nil)
        case "RtmpStream#attachVideo":
            let source = arguments["source"] as? [String: Any?]
            if source == nil {
                instance?.attachCamera(nil)
            } else {
                var devicePosition = AVCaptureDevice.Position.back
                if let position = source?["position"] as? String {
                    switch position {
                    case "front":
                        devicePosition = .front
                    case "back":
                        devicePosition = .back
                    default:
                        break
                    }
                }
                instance?.attachCamera(DeviceUtil.device(withPosition: devicePosition))
            }
            result(nil)
        case "RtmpStream#setZoom":
            if let zoom = arguments["zoomLevel"] as? Double {
                instance?.setZoomFactor(CGFloat(zoom))
            }
            result(nil)
        case "RtmpStream#play":
            instance?.play(arguments["name"] as? String)
            result(nil)
        case "RtmpStream#publish":
            instance?.publish(arguments["name"] as? String)
            result(nil)
        case "RtmpStream#registerTexture":
            guard
                let registry = plugin.registrar?.textures() else {
                return
            }
            if instance?.mixer.drawable == nil {
                let texture = NetStreamDrawableTexture(registry: registry)
                if let instance = instance {
                    texture.attachStream(instance)
                }
                result(texture.id)
            } else {
                if let texture = instance?.mixer.drawable as? NetStreamDrawableTexture {
                    if let width = arguments["width"] as? NSNumber,
                       let height = arguments["height"] as? NSNumber {
                        texture.bounds = CGSize(width: width.doubleValue, height: height.doubleValue)
                    }
                }
                result(nil)
            }
        case "RtmpStream#close":
            instance?.close()
        case "RtmpStream#dispose":
            instance?.removeEventListener(.rtmpStatus, selector: #selector(handler))
            instance?.close()
            instance = nil
            plugin.onDispose(id: Int(bitPattern: ObjectIdentifier(self)))
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @objc
    private func handler(_ notification: Notification) {
        let event = Event.from(notification)
        var map: [String: Any?] = [:]
        map["type"] = event.type.rawValue
        map["data"] = ASObjectUtil.removeEmpty(event.data)
        eventSink?(map)
    }

    @objc
    private func on(_ notification: Notification) {
        guard let orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation) else {
            return
        }
        instance?.orientation = orientation
    }
}

extension RTMPStreamHandler: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}
