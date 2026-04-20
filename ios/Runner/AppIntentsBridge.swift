import Foundation
import Flutter

/// AppIntents桥接插件
/// 使用弱链接支持iOS 15.0+，AppIntents功能仅在iOS 16+可用
@available(iOS 13.0, *)
class AppIntentsBridge: NSObject, FlutterPlugin {
    static let channelName = "com.simplelog.app_intents"
    private static var eventChannel: FlutterEventChannel?
    private static var eventSink: FlutterEventSink?

    // 事件缓存队列（解决冷启动时序问题）
    private static var pendingEvents: [String] = []
    private static let maxPendingEvents = 5

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )

        let instance = AppIntentsBridge()
        registrar.addMethodCallDelegate(instance, channel: channel)

        // 创建事件通道用于发送AppIntent事件
        eventChannel = FlutterEventChannel(
            name: "\(channelName)/events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel?.setStreamHandler(instance)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            // 检查是否支持AppIntents（iOS 16+）
            if #available(iOS 16.0, *) {
                result(true)
            } else {
                result(false)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// 从AppIntent发送事件到Flutter
    /// 如果Flutter还未订阅，事件会被缓存，等待订阅后发送
    static func sendEvent(_ event: String) {
        DispatchQueue.main.async {
            if let sink = eventSink {
                // 如果已连接，立即发送
                sink(event)
                print("[AppIntentsBridge] ✅ 事件已发送: \(event)")
            } else {
                // 如果未连接，缓存事件（解决冷启动时序问题）
                pendingEvents.append(event)
                if pendingEvents.count > maxPendingEvents {
                    pendingEvents.removeFirst()
                }
                print("[AppIntentsBridge] 📦 事件已缓存（共\(pendingEvents.count)个）: \(event)")
            }
        }
    }
}

// MARK: - FlutterStreamHandler
@available(iOS 13.0, *)
extension AppIntentsBridge: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        AppIntentsBridge.eventSink = events

        // 发送缓存的事件（解决冷启动时序问题）
        DispatchQueue.main.async {
            for event in AppIntentsBridge.pendingEvents {
                events(event)
                print("[AppIntentsBridge] 📤 发送缓存事件: \(event)")
            }
            if !AppIntentsBridge.pendingEvents.isEmpty {
                print("[AppIntentsBridge] ✅ 已发送 \(AppIntentsBridge.pendingEvents.count) 个缓存事件")
            }
            AppIntentsBridge.pendingEvents.removeAll()
        }

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        AppIntentsBridge.eventSink = nil
        return nil
    }
}
