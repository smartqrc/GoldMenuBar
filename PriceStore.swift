// GoldMenuBar — PriceStore.swift
// 数据拉取与持仓管理

import Foundation
import Combine
import UserNotifications

// MARK: - 价格预警设置
enum AlertDirection: String, Codable {
    case above, below
}

struct AlertSetting: Codable {
    var enabled: Bool = false
    var direction: AlertDirection = .above
    var target: Double = 0
}

final class PriceStore: ObservableObject {
    // 三项核心数据
    @Published var usdPerOz: Double?          // 伦敦金（现货）美元/盎司
    @Published var usdChgPct: Double?         // 纽约金日涨跌 %
    @Published var cnyPerGram: Double?        // 上海金 元/克
    @Published var cnyChgPct: Double?         // 上海金日涨跌 %
    @Published var cnyPerGramTime: String?    // 国内行情时间
    @Published var nav: Double?               // 002963 官方净值 (T-1)
    @Published var navDate: String?           // 净值日期
    @Published var navChgPct: Double?         // 净值日涨跌 %
    @Published var estNav: Double?            // 盘中估算净值
    @Published var lastUpdate: Date?
    @Published var loading = false
    @Published var errorText: String?

    // 持仓（本地持久化）
    @Published var sharesText: String { didSet { defaults.set(sharesText, forKey: "gold.shares") } }
    @Published var costText: String { didSet { defaults.set(costText, forKey: "gold.cost") } }

    // 价格预警（本地持久化）
    @Published var alertUsd: AlertSetting {
        didSet { if let d = try? JSONEncoder().encode(alertUsd) { defaults.set(d, forKey: "gold.alertUsd") } }
    }
    @Published var alertCny: AlertSetting {
        didSet { if let d = try? JSONEncoder().encode(alertCny) { defaults.set(d, forKey: "gold.alertCny") } }
    }
    @Published var usdAlertActive = false   // 当前是否处于触发状态
    @Published var cnyAlertActive = false

    private static func loadAlert(_ key: String) -> AlertSetting {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AlertSetting.self, from: d) else { return AlertSetting() }
        return s
    }

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private let refreshInterval: TimeInterval = 300 // 5 分钟

    init() {
        sharesText = defaults.string(forKey: "gold.shares") ?? ""
        costText = defaults.string(forKey: "gold.cost") ?? ""
        alertUsd = Self.loadAlert("gold.alertUsd")
        alertCny = Self.loadAlert("gold.alertCny")
        startTimer()
    }

    var shares: Double? { Double(sharesText.replacingOccurrences(of: ",", with: "")) }
    var cost: Double? { Double(costText.replacingOccurrences(of: ",", with: "")) }

    /// 持仓收益
    var profit: Double? {
        guard let s = shares, let c = cost, let n = nav else { return nil }
        return (n - c) * s
    }
    var profitPct: Double? {
        guard let c = cost, c > 0, let n = nav else { return nil }
        return (n - c) / c * 100
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.fetchAll()
        }
    }

    func fetchAll() {
        loading = true
        errorText = nil
        let group = DispatchGroup()
        var fetchError: String?

        group.enter()
        fetchSinaGold { usd, chg, cny, cnyChg, t, err in
            if let usd = usd { self.usdPerOz = usd }
            if let chg = chg { self.usdChgPct = chg }
            if let cny = cny {
                self.cnyPerGram = cny
                self.cnyPerGramTime = t
            }
            if let cnyChg = cnyChg { self.cnyChgPct = cnyChg }
            if usd == nil && cny == nil { fetchError = err ?? "新浪行情获取失败" }
            group.leave()
        }

        group.enter()
        fetchFundNAV { nav, date, chg, err in
            if let nav = nav { self.nav = nav }
            if let date = date { self.navDate = date }
            if let chg = chg { self.navChgPct = chg }
            if nav == nil { fetchError = (fetchError.map { $0 + "；" } ?? "") + (err ?? "基金净值获取失败") }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.loading = false
            // 盘中估算净值：官方净值 × (1 + 纽约金日内涨跌幅)
            if let n = self.nav, let chg = self.usdChgPct {
                self.estNav = n * (1 + chg / 100)
            } else {
                self.estNav = nil
            }
            if fetchError != nil && self.usdPerOz == nil && self.nav == nil {
                self.errorText = fetchError
            } else {
                self.lastUpdate = Date()
            }
            self.checkAlerts()
        }
    }

    // MARK: - 价格预警检查
    private func checkAlerts() {
        usdAlertActive = evaluate(alertUsd, price: usdPerOz,
                                  stateKey: "gold.alertUsd.active",
                                  name: "国际金价", unit: "美元/盎司")
        cnyAlertActive = evaluate(alertCny, price: cnyPerGram,
                                  stateKey: "gold.alertCny.active",
                                  name: "国内金价", unit: "元/克")
        // 通知菜单栏图标显示/移除红点
        let anyActive = usdAlertActive || cnyAlertActive
        NotificationCenter.default.post(name: Notification.Name("gold.alertBadge"),
                                        object: anyActive)
    }

    /// 返回当前是否处于触发状态；仅在「未触发 → 触发」跨越时发一次通知（回落复归后自动重新布防）
    private func evaluate(_ s: AlertSetting, price: Double?, stateKey: String, name: String, unit: String) -> Bool {
        guard s.enabled, s.target > 0, let p = price else {
            defaults.set(false, forKey: stateKey)
            return false
        }
        let hit = s.direction == .above ? p >= s.target : p <= s.target
        let wasActive = defaults.bool(forKey: stateKey)
        if hit && !wasActive {
            sendAlertNotification(name: name, price: p, setting: s, unit: unit)
        }
        defaults.set(hit, forKey: stateKey)
        return hit
    }

    private func sendAlertNotification(name: String, price: Double, setting: AlertSetting, unit: String) {
        let content = UNMutableNotificationContent()
        content.title = "🔔 金价预警 · \(name)"
        content.body = String(format: "当前 %.2f %@，已达预警线（%@ %.2f）",
                              price, unit,
                              setting.direction == .above ? "≥" : "≤",
                              setting.target)
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - 新浪行情（伦敦金现 XAU + 上海金交所 Au(T+D)）
    private func fetchSinaGold(_ completion: @escaping (Double?, Double?, Double?, Double?, String?, String?) -> Void) {
        guard let url = URL(string: "https://hq.sinajs.cn/list=hf_XAU,gds_AUTD") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, error in
            var usd: Double?, chg: Double?, cny: Double?, cnyChg: Double?, t: String?
            var err: String?
            if let error = error {
                err = "网络错误: \(error.localizedDescription)"
            } else if let data = data {
                // 新浪响应为 GBK 编码，UTF-8 解码会失败；GBK 优先，UTF-8/lossy 兜底
                let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
                let raw = String(data: data, encoding: gbk)
                    ?? String(data: data, encoding: .utf8)
                    ?? String(decoding: data, as: UTF8.self)
                for line in raw.components(separatedBy: "\n") {
                    guard let v = Self.sinaValue(line: line, key: "hf_XAU") else { continue }
                    let f = v.components(separatedBy: ",")
                    if f.count > 7, let last = Double(f[0]), let prev = Double(f[7]), prev > 0 {
                        usd = last
                        chg = (last - prev) / prev * 100
                    }
                }
                for line in raw.components(separatedBy: "\n") {
                    guard let v = Self.sinaValue(line: line, key: "gds_AUTD") else { continue }
                    let f = v.components(separatedBy: ",")
                    if f.count > 12, let p = Double(f[0]) {
                        cny = p
                        t = f[12] // 日期
                        if let prev = Double(f[7]), prev > 0 {
                            cnyChg = (p - prev) / prev * 100
                        }
                    }
                }
            } else {
                err = "新浪行情解析失败"
            }
            DispatchQueue.main.async { completion(usd, chg, cny, cnyChg, t, err) }
        }.resume()
    }

    private static func sinaValue(line: String, key: String) -> String? {
        guard let range = line.range(of: "hq_str_\(key)=\"") else { return nil }
        let s = line[range.upperBound...]
        guard let end = s.range(of: "\"") else { return nil }
        return String(s[..<end.lowerBound])
    }

    // MARK: - 天天基金 002963 官方净值
    private func fetchFundNAV(_ completion: @escaping (Double?, String?, Double?, String?) -> Void) {
        guard let url = URL(string: "https://api.fund.eastmoney.com/f10/lsjz?fundCode=002963&pageIndex=1&pageSize=2") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("https://fundf10.eastmoney.com/jjjz_002963.html", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, error in
            var nav: Double?, date: String?, chg: Double?
            var err: String?
            if let error = error {
                err = "网络错误: \(error.localizedDescription)"
            } else if let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let list = (obj["Data"] as? [String: Any])?["LSJZList"] as? [[String: Any]],
                      let first = list.first {
                date = first["FSRQ"] as? String
                nav = Double(first["DWJZ"] as? String ?? "")
                chg = Double(first["JZZZL"] as? String ?? "")
            } else {
                err = "基金净值解析失败"
            }
            DispatchQueue.main.async { completion(nav, date, chg, err) }
        }.resume()
    }
}
