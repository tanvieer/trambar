import Foundation
import CoreLocation
import ServiceManagement

struct Route: Codable, Hashable, Identifiable {
    var from: EFA.Stop
    var to: EFA.Stop
    var id: String { from.id + ">" + to.id }
}

struct Settings: Codable {
    var stops: [EFA.Stop] = []
    var routes: [Route] = []
    var showNearby = true
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
        let symbol = Fmt.symbol(d?.kind ?? .tram)
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
        error = failed ? "Some data could not be loaded — showing the last known times." : nil
        if !failed { lastUpdate = Date() }
        updateMenu()
        if settings.showNearby { location.requestLocation() }
    }

    /// What the menu bar shows: the next departure from the first saved stop,
    /// or from the nearest stop if nothing is saved.
    var headline: EFA.Departure? {
        let id = settings.stops.first?.id ?? (settings.showNearby ? nearby.first?.id : nil)
        return id.flatMap { departures[$0] }?.first { !$0.cancelled && $0.when > Date().addingTimeInterval(-30) }
    }

    // MARK: editing

    func addStop(_ stop: EFA.Stop) {
        guard !settings.stops.contains(where: { $0.id == stop.id }) else { return }
        var s = stop; s.distance = nil
        settings.stops.append(s)
    }

    func removeStop(_ stop: EFA.Stop) { settings.stops.removeAll { $0.id == stop.id } }
    func moveStopToTop(_ stop: EFA.Stop) {
        settings.stops.removeAll { $0.id == stop.id }
        settings.stops.insert(stop, at: 0)
    }

    func addRoute(from: EFA.Stop, to: EFA.Stop) {
        let route = Route(from: from, to: to)
        guard !settings.routes.contains(route) else { return }
        settings.routes.append(route)
    }

    func removeRoute(_ route: Route) { settings.routes.removeAll { $0 == route } }

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
