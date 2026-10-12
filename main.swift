// GoldMenuBar — main.swift
// macOS 菜单栏黄金价格 App（NSStatusItem + SwiftUI 面板）

import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = PriceStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏图标：小金条
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = Self.goldIngotIcon(alert: false)
            button.toolTip = "黄金价格"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.contentViewController = NSHostingController(rootView: PanelView(store: store))
        popover.behavior = .transient
        popover.animates = true

        store.fetchAll()

        // 请求系统通知权限（价格预警用）
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // 监听预警状态：触发时菜单栏图标右上角叠红点（独立子视图，不受模板染色影响）
        NotificationCenter.default.addObserver(forName: Notification.Name("gold.alertBadge"),
                                               object: nil, queue: .main) { [weak self] note in
            guard let button = self?.statusItem.button else { return }
            let on = (note.object as? Bool) ?? false
            button.subviews.forEach { if $0 is AlertDotView { $0.removeFromSuperview() } }
            if on {
                let dot = AlertDotView(frame: NSRect(x: button.bounds.width - 7, y: 2, width: 6, height: 6))
                dot.autoresizingMask = [.minXMargin, .maxYMargin]
                button.addSubview(dot)
            }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            store.fetchAll()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 菜单栏图标：白色单色元宝（模板模式，自动适配菜单栏深浅色）
    /// 造型：两侧翘角 + 中间圆鼓肚 + 上沿内凹的元宝剪影
    private static func goldIngotIcon(alert: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            // 顶沿：左角尖 → 内凹 → 中间圆鼓 → 内凹 → 右角尖
            path.move(to: NSPoint(x: 1.8, y: 10.6))                       // 左角尖（最高点）
            path.curve(to: NSPoint(x: 6.2, y: 8.2),
                       controlPoint1: NSPoint(x: 3.4, y: 8.6),
                       controlPoint2: NSPoint(x: 4.8, y: 8.2))            // 左肩内凹
            path.curve(to: NSPoint(x: 11.8, y: 8.2),
                       controlPoint1: NSPoint(x: 7.2, y: 9.8),
                       controlPoint2: NSPoint(x: 10.8, y: 9.8))           // 中央圆鼓
            path.curve(to: NSPoint(x: 16.2, y: 10.6),
                       controlPoint1: NSPoint(x: 13.2, y: 8.2),
                       controlPoint2: NSPoint(x: 14.6, y: 8.6))           // 右肩内凹 → 右角尖
            // 底沿：从右角尖沿船底弧线收回左角尖
            path.curve(to: NSPoint(x: 9.0, y: 4.6),
                       controlPoint1: NSPoint(x: 15.4, y: 7.0),
                       controlPoint2: NSPoint(x: 12.6, y: 4.8))
            path.curve(to: NSPoint(x: 1.8, y: 10.6),
                       controlPoint1: NSPoint(x: 5.4, y: 4.8),
                       controlPoint2: NSPoint(x: 2.6, y: 7.0))
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        img.isTemplate = true // 系统自动按菜单栏深浅渲染为黑色/白色
        return img
    }
}

/// 预警红点子视图（叠加在菜单栏按钮上，不参与模板染色）
final class AlertDotView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 不占 Dock
app.run()
