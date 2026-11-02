import Foundation
import CoreLocation
import ServiceManagement

struct Route: Codable, Hashable, Identifiable {
    var from: EFA.Stop
    var to: EFA.Stop
    var id: String { from.id + ">" + to.id }
}

/// One card in the panel: a saved stop or a saved route.
enum Item: Identifiable {
    case stop(EFA.Stop)
    case route(Route)
    var id: String {
        switch self {
        case .stop(let s): return "stop:" + s.id
        case .route(let r): return "route:" + r.id
        }
    }
}

struct Settings: Codable {
    var stops: [EFA.Stop] = []
    var routes: [Route] = []
    var showNearby = true
    /// Item ids in the order the panel shows them. Items not listed go last.
    var order: [String] = []
    /// The item the menu bar shows, if pinned. Otherwise it shows the top item.
    var pinned: String?

    init() {}

    // Older settings files have no `order`, so every field is optional when reading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stops = try c.decodeIfPresent([EFA.Stop].self, forKey: .stops) ?? []
        routes = try c.decodeIfPresent([Route].self, forKey: .routes) ?? []
        showNearby = try c.decodeIfPresent(Bool.self, forKey: .showNearby) ?? true
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
        pinned = try c.decodeIfPresent(String.self, forKey: .pinned)
    }

    /// Saved stops and routes in panel order. Without an order, routes come first as before.
    var items: [Item] {
        let all = routes.map(Item.route) + stops.map(Item.stop)
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return all.enumerated()
            .sorted { (rank[$0.element.id] ?? order.count + $0.offset) < (rank[$1.element.id] ?? order.count + $1.offset) }
            .map(\.element)
    }
}

/// Everything the menu shows, refreshed every 30 seconds.
@MainActor
final class Store: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var settings: Settings { didSet { save(); Task { await refresh() } } }
    @Published private(set) var departures: [String: [EFA.Departure]] = [:]
    @Published private(set) var journeys: [String: [EFA.Journey]] = [:]
    @Published private(set) var nearby: [EFA.Stop] = []
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var error: String?
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined
    /// The menu bar text, e.g. "2 · 4 min". Kept here and set only when it changes:
    /// a TimelineView in a MenuBarExtra label locks up launch on macOS 27.
    @Published private(set) var menuTitle: String?
    @Published private(set) var menuSymbol = Fmt.symbol(.tram)

    static let refreshInterval: TimeInterval = 30
    private let location = CLLocationManager()
    private var lastFix: CLLocation?
    private var timer: Timer?
    private var clock: Timer?

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TramBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }()

    override init() {
        settings = (try? JSONDecoder().decode(Settings.self, from: Data(contentsOf: Store.fileURL))) ?? Settings()
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationStatus = location.authorizationStatus
        if settings.showNearby { startLocation() }
        timer = Timer.scheduledTimer(withTimeInterval: Store.refreshInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        clock = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMenu() }
        }
        Task { await refresh() }
    }

    private func updateMenu() {
        let d = headline
        let title = d.map { "\($0.line) · \(Fmt.countdown($0.when, now: Date()))" }
        let symbol = d?.symbol ?? Fmt.symbol(.tram)
        if title != menuTitle { menuTitle = title }
        if symbol != menuSymbol { menuSymbol = symbol }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: Store.fileURL, options: .atomic)
        }
    }

    // MARK: refresh

    func refresh() async {
        let stopIDs = Set(settings.stops.map(\.id) + (settings.showNearby ? nearby.prefix(3).map(\.id) : []))
        var failed = false

        await withTaskGroup(of: (String, [EFA.Departure]?).self) { group in
            for id in stopIDs {
                group.addTask { (id, try? await EFA.departures(stopID: id)) }
            }
            for await (id, result) in group {
                if let result { departures[id] = result } else { failed = true }
            }
        }
        await withTaskGroup(of: (String, [EFA.Journey]?).self) { group in
            for route in settings.routes {
                group.addTask { (route.id, try? await EFA.journeys(from: route.from.id, to: route.to.id)) }
            }
            for await (id, result) in group {
                if let result { journeys[id] = result } else { failed = true }
            }
        }
        error = failed ? L("Some data could not be loaded — showing the last known times.", "Einige Daten konnten nicht geladen werden – es werden die letzten bekannten Zeiten angezeigt.") : nil
        if !failed { lastUpdate = Date() }
        updateMenu()
        if settings.showNearby { location.requestLocation() }
    }

    /// The saved item the menu bar follows: the pinned one, else the top of the list.
    var menuItem: Item? {
        let items = settings.items
        return items.first { $0.id == settings.pinned } ?? items.first
    }

    /// What the menu bar shows: the next departure of the menu item,
    /// or from the nearest stop if nothing is saved.
    private var headline: (line: String, when: Date, symbol: String)? {
        let soon = Date().addingTimeInterval(-30)
        let stopID: String?
        switch menuItem {
        case .route(let route):
            return journeys[route.id]?.first { !$0.cancelled && $0.departs > soon }
                .map { ($0.lines.first ?? "", $0.departs, "point.topleft.down.to.point.bottomright.curvepath") }
        case .stop(let stop): stopID = stop.id
        case nil: stopID = settings.showNearby ? nearby.first?.id : nil
        }
        return stopID.flatMap { departures[$0] }?.first { !$0.cancelled && $0.when > soon }
            .map { ($0.line, $0.when, Fmt.symbol($0.kind)) }
    }

    // MARK: editing

    func addStop(_ stop: EFA.Stop) {
        guard !settings.stops.contains(where: { $0.id == stop.id }) else { return }
        var s = stop; s.distance = nil
        settings.stops.append(s)
    }

    func removeStop(_ stop: EFA.Stop) { settings.stops.removeAll { $0.id == stop.id } }

    func addRoute(from: EFA.Stop, to: EFA.Stop) {
        let route = Route(from: from, to: to)
        guard !settings.routes.contains(route) else { return }
        settings.routes.append(route)
    }

    func removeRoute(_ route: Route) { settings.routes.removeAll { $0 == route } }

    func togglePin(_ item: Item) {
        settings.pinned = settings.pinned == item.id ? nil : item.id
    }

    /// Moves a card one place up (-1) or down (+1) in the panel.
    func move(_ item: Item, by offset: Int) {
        var ids = settings.items.map(\.id)
        guard let i = ids.firstIndex(of: item.id), ids.indices.contains(i + offset) else { return }
        ids.swapAt(i, i + offset)
        settings.order = ids
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            objectWillChange.send()
        }
    }

    // MARK: location

    func setShowNearby(_ on: Bool) {
        settings.showNearby = on
        if on { startLocation() } else { nearby = [] }
    }

    private func startLocation() {
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        } else {
            location.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            locationStatus = status
            if status == .authorizedAlways || status == .authorized { location.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }
        Task { @MainActor in await updateNearby(fix) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func updateNearby(_ fix: CLLocation) async {
        // Only look stops up again once we have moved; Wi-Fi fixes jitter a little.
        if let last = lastFix, fix.distance(from: last) < 75, !nearby.isEmpty { return }
        lastFix = fix
        guard let stops = try? await EFA.nearbyStops(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude) else { return }
        nearby = stops
        await refresh()
    }
}
