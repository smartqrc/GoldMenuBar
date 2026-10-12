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
    @Published var nav: Double?               // 159934 场内实时价
    @Published var navDate: String?           // 行情时间
    @Published var navChgPct: Double?         // 日涨跌 %
    @Published var histUsd: [Double] = []     // 近6小时走势（5分钟收盘）
    @Published var histCny: [Double] = []     // 国内金：国际金走势 × 当前比价映射
    @Published var histEtf: [Double] = []     // 近6小时走势
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
        fetchSinaGold { usd, chg, cny, cnyChg, etf, etfChg, etfT, t, err in
            if let usd = usd { self.usdPerOz = usd }
            if let chg = chg { self.usdChgPct = chg }
            if let cny = cny {
                self.cnyPerGram = cny
                self.cnyPerGramTime = t
            }
            if let cnyChg = cnyChg { self.cnyChgPct = cnyChg }
            if let etf = etf { self.nav = etf }
            if let etfChg = etfChg { self.navChgPct = etfChg }
            if let etfT = etfT { self.navDate = etfT }
            if usd == nil && cny == nil && etf == nil { fetchError = err ?? "新浪行情获取失败" }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.loading = false
            if fetchError != nil && self.usdPerOz == nil && self.nav == nil {
                self.errorText = fetchError
            } else {
                self.lastUpdate = Date()
            }
            self.checkAlerts()
            self.fetchHistories()
        }
    }

    // MARK: - 近6小时历史曲线
    func fetchHistories() {
        fetchXauHistory { xs in
            DispatchQueue.main.async {
                guard let xs = xs else { return }
                self.histUsd = xs
                // SGE 无公开分钟级历史：按当前国际/国内比价映射国际金走势
                if let u = self.usdPerOz, let c = self.cnyPerGram, u > 0 {
                    self.histCny = xs.map { $0 * c / u }
                }
            }
        }
        fetchEtfHistory { ys in
            DispatchQueue.main.async { if let ys = ys { self.histEtf = ys } }
        }
    }

    /// 伦敦金现 5 分钟 K 线（GlobalService.getMinK 返回全部近期数据，取最后 72 根 = 6 小时）
    private func fetchXauHistory(_ completion: @escaping ([Double]?) -> Void) {
        guard let url = URL(string: "https://gu.sina.cn/ft/api/jsonp.php/var%20x=/GlobalService.getMinK?symbol=XAU&type=5") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var result: [Double]?
            if let data = data {
                let raw = String(decoding: data, as: UTF8.self)
                if let a = raw.range(of: "var x=("), let b = raw.range(of: ");", options: .backwards) {
                    let jsonStr = String(raw[a.upperBound..<b.lowerBound])
                    if let arr = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [[String: Any]] {
                        let closes = arr.compactMap { ($0["c"] as? String).flatMap { Double($0) } }
                        result = closes.count > 72 ? Array(closes.suffix(72)) : closes
                    }
                }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// 159934 5 分钟 K 线（datalen=72 即 6 小时）
    private func fetchEtfHistory(_ completion: @escaping ([Double]?) -> Void) {
        guard let url = URL(string: "https://quotes.sina.cn/cn/api/json_v2.php/CN_MarketDataService.getKLineData?symbol=sz159934&scale=5&ma=no&datalen=72") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var result: [Double]?
            if let data = data,
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let closes = arr.compactMap { ($0["close"] as? String).flatMap { Double($0) } }
                result = closes.count >= 2 ? closes : nil
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
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
    private func fetchSinaGold(_ completion: @escaping (Double?, Double?, Double?, Double?, Double?, Double?, String?, String?, String?) -> Void) {
        guard let url = URL(string: "https://hq.sinajs.cn/list=hf_XAU,gds_AUTD,sz159934") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, error in
            var usd: Double?, chg: Double?, cny: Double?, cnyChg: Double?, etf: Double?, etfChg: Double?, etfT: String?, t: String?
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
                    guard let v = Self.sinaValue(line: line, key: "sz159934") else { continue }
                    let f = v.components(separatedBy: ",")
                    if f.count > 31, let last = Double(f[3]), let prev = Double(f[2]), prev > 0 {
                        etf = last
                        etfChg = (last - prev) / prev * 100
                        etfT = f[31] // 行情时间 HH:mm:ss
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
            DispatchQueue.main.async { completion(usd, chg, cny, cnyChg, etf, etfChg, etfT, t, err) }
        }.resume()
    }

    private static func sinaValue(line: String, key: String) -> String? {
        guard let range = line.range(of: "hq_str_\(key)=\"") else { return nil }
        let s = line[range.upperBound...]
        guard let end = s.range(of: "\"") else { return nil }
        return String(s[..<end.lowerBound])
    }

}
