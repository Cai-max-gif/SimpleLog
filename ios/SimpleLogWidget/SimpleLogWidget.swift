//
//  SimpleLogWidget.swift
//  SimpleLogWidget
//
//  Created by matrix on 2025/11/5.
//

import WidgetKit
import SwiftUI

struct SimpleLogEntry: TimelineEntry {
    let date: Date
    let widgetImagePath: String
}

struct SimpleLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleLogEntry {
        SimpleLogEntry(
            date: Date(),
            widgetImagePath: ""
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleLogEntry) -> ()) {
        let userDefaults = UserDefaults(suiteName: "group.com.tntlikely.simplelog")
        let imagePath = userDefaults?.string(forKey: "widgetImage") ?? ""
        let entry = SimpleLogEntry(date: Date(), widgetImagePath: imagePath)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let userDefaults = UserDefaults(suiteName: "group.com.tntlikely.simplelog")
        let imagePath = userDefaults?.string(forKey: "widgetImage") ?? ""
        let entry = SimpleLogEntry(date: Date(), widgetImagePath: imagePath)

        // 设置30分钟后刷新
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SimpleLogWidgetEntryView : View {
    var entry: SimpleLogProvider.Entry
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        if let uiImage = UIImage(contentsOfFile: entry.widgetImagePath) {
            print("📱 iOS Widget - Image size: \(uiImage.size.width)x\(uiImage.size.height), Scale: \(uiImage.scale)")
            return AnyView(
                GeometryReader { geometry in
                    let _ = print("📱 iOS Widget - Container size: \(geometry.size.width)x\(geometry.size.height)")
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            )
        } else {
            return AnyView(
                // Placeholder view when image is not available
                ZStack {
                    Color(red: 1.0, green: 0.76, blue: 0.03)
                    VStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                        Text("简单记账")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            )
        }
    }
}

struct SimpleLogWidget: Widget {
    let kind: String = "SimpleLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SimpleLogProvider()) { entry in
            if #available(iOS 17.0, *) {
                SimpleLogWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        Color.clear
                    }
            } else {
                SimpleLogWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("简单记账")
        .description("显示今日和本月的收支情况")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()  // Remove default padding/margins in iOS 17+
    }
}
