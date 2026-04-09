import Foundation
import UIKit

// 使用条件编译，只在iOS 16+编译AppIntents代码
#if canImport(AppIntents)
import AppIntents

/// 蜜蜂记账 - 截图自动记账 AppIntent
/// 通过iOS快捷指令触发，实现截图后自动识别并记账
/// 仅iOS 16+可用，但App可在iOS 15+运行
@available(iOS 16.0, *)
struct AutoBillingAppIntent: AppIntent {
    static var title: LocalizedStringResource = "截图自动记账"
    static var description: LocalizedStringResource = "自动识别截图中的支付信息并创建账单"
    static var openAppWhenRun: Bool = true

    // 接收截图参数
    @Parameter(title: "截图")
    var screenshot: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult {
        // 如果快捷指令传递了图片，保存到临时目录
        if let screenshot = screenshot {
            print("[AppIntent] 收到截图参数，文件名: \(screenshot.filename)")

            // 尝试获取图片数据
            var imageData: Data?

            // 优先使用fileURL
            if let fileURL = screenshot.fileURL {
                print("[AppIntent] 从fileURL读取: \(fileURL.path)")
                imageData = try? Data(contentsOf: fileURL)
            }

            // 如果没有fileURL，尝试直接获取data
            if imageData == nil {
                print("[AppIntent] 尝试直接获取data属性")
                imageData = screenshot.data
            }

            // 如果都没有，尝试从filename构造路径
            if imageData == nil {
                print("[AppIntent] 尝试从filename读取: \(screenshot.filename)")
                let fileURL = URL(fileURLWithPath: screenshot.filename)
                imageData = try? Data(contentsOf: fileURL)
            }

            if let imageData = imageData, let image = UIImage(data: imageData) {
                print("[AppIntent] 成功加载图片，尺寸: \(image.size)")

                // 保存到临时目录
                let tempDir = FileManager.default.temporaryDirectory
                let imagePath = tempDir.appendingPathComponent("shortcut_screenshot_\(Date().timeIntervalSince1970).jpg")

                if let jpegData = image.jpegData(compressionQuality: 0.85) {
                    do {
                        try jpegData.write(to: imagePath)
                        print("[AppIntent] 图片已保存到: \(imagePath.path)")

                        // 使用JSON格式传递，避免路径中的冒号问题
                        let event = "{\"action\":\"auto-billing\",\"imagePath\":\"\(imagePath.path)\"}"
                        AppIntentsBridge.sendEvent(event)
                        return .result()
                    } catch {
                        print("[AppIntent] 保存图片失败: \(error)")
                    }
                }
            } else {
                print("[AppIntent] 无法加载图片数据")
            }
        } else {
            print("[AppIntent] 未收到截图参数")
        }

        // 如果没有图片参数或处理失败，只发送事件（让Flutter端处理）
        let event = "{\"action\":\"auto-billing\"}"
        AppIntentsBridge.sendEvent(event)
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("识别\(\.$screenshot)中的支付信息")
    }
}

/// Siri快捷语音指令配置（可选）
/// 用户可以对Siri说："在蜜蜂记账中截图记账"来触发
@available(iOS 16.0, *)
struct AutoBillingShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AutoBillingAppIntent(),
            phrases: [
                "在\(.applicationName)中截图记账",
                "用\(.applicationName)记账",
                "打开\(.applicationName)自动记账"
            ]
        )
    }
}
#endif
