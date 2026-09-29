// GoldMenuBar — PanelView.swift
// 弹出面板 UI：三张价格卡片 + 持仓收益卡

import SwiftUI

/// 价格预警行：红点状态 + 名称 + 方向切换 + 目标价 + 开关
struct AlertRow: View {
    let label: String
    let unit: String
    @Binding var setting: AlertSetting
    let active: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(active ? Color(red: 0.90, green: 0.22, blue: 0.20) : Color(NSColor.separatorColor))
                .frame(width: 7, height: 7)
            Text(label).font(.system(size: 11.5))
            Button(action: {
                setting.direction = setting.direction == .above ? .below : .above
            }) {
                Text(setting.direction == .above ? "≥" : "≤")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .frame(width: 22, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.quaternaryLabelColor).opacity(0.35)))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.primary)
            TextField("目标价", text: Binding(
                get: { setting.target == 0 ? "" : String(format: "%.2f", setting.target) },
                set: { setting.target = Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .font(.system(size: 11).monospacedDigit())
            .frame(maxWidth: 76)
            Toggle("", isOn: $setting.enabled)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle())
                .controlSize(.small)
        }
    }
}

/// 涨红跌绿（国内习惯）
private func chgColor(_ v: Double?) -> Color {
    guard let v = v else { return .secondary }
    if v > 0 { return Color(red: 0.90, green: 0.22, blue: 0.20) }
    if v < 0 { return Color(red: 0.05, green: 0.60, blue: 0.35) }
    return .secondary
}
private func chgText(_ v: Double?) -> String {
    guard let v = v else { return "--" }
    let sign = v > 0 ? "+" : ""
    return "\(sign)\(String(format: "%.2f", v))%"
}

struct PriceCard: View {
    let title: String
    let subtitle: String
    let value: String
    let chg: Double?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                RoundedRectangle(cornerRadius: 2.5).fill(accent).frame(width: 4, height: 13)
                Text(title).font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(chgText(chg))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(chgColor(chg))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(
                        Capsule().fill(chgColor(chg).opacity(0.12))
                    )
            }
            Text(value)
                .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)
            Text(subtitle).font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.07), radius: 5, y: 2)
        )
    }
}

struct PanelView: View {
    @ObservedObject var store: PriceStore
    @State private var savedFlash = false

    /// 保存持仓并释放输入框焦点
    private func saveHoldings() {
        store.sharesText = store.sharesText.trimmingCharacters(in: .whitespaces)
        store.costText = store.costText.trimmingCharacters(in: .whitespaces)
        NSApp.keyWindow?.makeFirstResponder(nil)
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
    }

    var body: some View {
        VStack(spacing: 10) {
            // 标题栏
            HStack {
                Text("黄金价格").font(.system(size: 14, weight: .heavy))
                Spacer()
                if store.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: { store.fetchAll() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if let err = store.errorText, store.usdPerOz == nil, store.nav == nil {
                Text(err).font(.system(size: 11)).foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 1. 国际金价
            PriceCard(
                title: "国际金价 · COMEX",
                subtitle: "美元 / 盎司 · 实时",
                value: store.usdPerOz.map { String(format: "$%.2f", $0) } ?? "--",
                chg: store.usdChgPct,
                accent: Color(red: 0.95, green: 0.72, blue: 0.20)
            )

            // 2. 国内金价
            PriceCard(
                title: "国内金价 · 上海金交所",
                subtitle: "人民币 / 克 · Au(T+D)" + (store.cnyPerGramTime.map { " · \($0)" } ?? ""),
                value: store.cnyPerGram.map { String(format: "¥%.2f", $0) } ?? "--",
                chg: nil,
                accent: Color(red: 0.85, green: 0.55, blue: 0.10)
            )

            // 3. ETF 净值
            PriceCard(
                title: "易方达黄金ETF联接C · 002963",
                subtitle: "官方净值" + (store.navDate.map { " · \($0)" } ?? "（T-1 更新）"),
                value: store.nav.map { String(format: "¥%.4f", $0) } ?? "--",
                chg: store.navChgPct,
                accent: Color(red: 0.55, green: 0.40, blue: 0.95)
            )

            // 盘中估算
            if let est = store.estNav {
                HStack {
                    Text("盘中估算净值").font(.system(size: 11)).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.4f", est))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
            }

            Divider()

            // 4. 价格预警
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RoundedRectangle(cornerRadius: 2.5).fill(Color(red: 0.90, green: 0.30, blue: 0.25)).frame(width: 4, height: 13)
                    Text("价格预警").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    Spacer()
                    Text("达到目标价后系统通知")
                        .font(.system(size: 9.5)).foregroundColor(.secondary)
                }
                AlertRow(label: "国际金价", unit: "$",
                         setting: $store.alertUsd, active: store.usdAlertActive)
                AlertRow(label: "国内金价", unit: "¥",
                         setting: $store.alertCny, active: store.cnyAlertActive)
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.07), radius: 5, y: 2)
            )

            // 5. 持仓收益
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RoundedRectangle(cornerRadius: 2.5).fill(Color(NSColor.systemGray)).frame(width: 4, height: 13)
                    Text("我的持仓").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    Spacer()
                    if let p = store.profit {
                        Text(String(format: "¥%+.2f", p))
                            .font(.system(size: 15, weight: .bold).monospacedDigit())
                            .foregroundColor(chgColor(p))
                    }
                    if let pp = store.profitPct {
                        Text(chgText(pp))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundColor(chgColor(pp))
                    }
                }
                HStack(spacing: 8) {
                    TextField("持有份额", text: $store.sharesText)
                    TextField("成本净值", text: $store.costText)
                }
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.system(size: 12).monospacedDigit())
                HStack {
                    Text("收益 = (最新净值 − 成本) × 份额 · 数据保存在本机")
                        .font(.system(size: 9.5)).foregroundColor(.secondary)
                    Spacer()
                    Button(action: saveHoldings) {
                        Text(savedFlash ? "已保存 ✓" : "保存")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(Color(red: 0.72, green: 0.50, blue: 0.05))
                            .padding(.horizontal, 11).padding(.vertical, 4)
                            .background(
                                Capsule().fill(savedFlash ?
                                    Color(red: 1.0, green: 0.93, blue: 0.72) :
                                    Color(red: 0.98, green: 0.85, blue: 0.45))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.07), radius: 5, y: 2)
            )

            // 底部
            HStack {
                if let t = store.lastUpdate {
                    Text("更新于 " + Self.fmt(t)).font(.system(size: 10)).foregroundColor(.secondary)
                } else if store.loading {
                    Text("获取中…").font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { store.fetchAll() }
    }

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}
