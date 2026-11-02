import SwiftUI
import CoreLocation

// MARK: formatting

/// German when the Mac's first language is German, English otherwise.
let german = Locale.preferredLanguages.first?.hasPrefix("de") ?? false
func L(_ en: String, _ de: String) -> String { german ? de : en }

enum Fmt {
    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    /// "now", "4 min", or a clock time once it is more than an hour away.
    static func countdown(_ date: Date, now: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.down))
        if minutes < 1 { return L("now", "jetzt") }
        if minutes < 60 { return "\(minutes) min" }
        return clock.string(from: date)
    }

    /// CVAG platform codes like "TO" (tram, east side) become "east side".
    /// Track numbers and anything else are shown as they come.
    static func platform(_ code: String) -> String {
        let sides: [Character: String] = german
            ? ["N": "Nordseite", "O": "Ostseite", "S": "Südseite", "W": "Westseite"]
            : ["N": "north side", "O": "east side", "S": "south side", "W": "west side"]
        guard code.count <= 2, let last = code.last, let side = sides[last],
              code.count == 1 || code.first!.isUppercase else { return code }
        return side
    }

    static func symbol(_ kind: EFA.Kind) -> String {
        switch kind {
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        case .train: return "train.side.front.car"
        case .other: return "figure.walk"
        }
    }
}

struct DelayBadge: View {
    let minutes: Int
    let realtime: Bool
    var body: some View {
        if minutes > 0 {
            Text("+\(minutes)").foregroundStyle(.red).fontWeight(.semibold)
        } else if realtime {
            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green).font(.caption2)
                .help("Live")
        }
    }
}

// MARK: menu bar label

struct MenuBarLabel: View {
    @ObservedObject var store: Store
    var body: some View {
        Image(systemName: store.menuSymbol)
        if let title = store.menuTitle { Text(title) }
    }
}

// MARK: panel

struct Panel: View {
    @ObservedObject var store: Store
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if editing {
                EditView(store: store).padding(12)
            } else {
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        content(now: context.date).padding(12)
                    }
                }
                .frame(maxHeight: 560)
            }
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack {
            Text(editing ? L("Edit stops & routes", "Haltestellen & Strecken bearbeiten") : L("Departures", "Abfahrten")).font(.headline)
            Spacer()
            if !editing, let t = store.lastUpdate {
                Text(L("updated", "aktualisiert") + " \(Fmt.clock.string(from: t))").font(.caption).foregroundStyle(.secondary)
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(L("Refresh now", "Jetzt aktualisieren"))
            }
            Button(editing ? L("Done", "Fertig") : L("Edit", "Bearbeiten")) { editing.toggle() }.buttonStyle(.borderless)
            Menu {
                Toggle(L("Open at login", "Beim Anmelden öffnen"), isOn: Binding(get: { store.launchAtLogin }, set: { store.launchAtLogin = $0 }))
                Divider()
                Button(L("Quit TramBar", "TramBar beenden")) { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = store.error {
                Label(error, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange)
            }
            ForEach(store.settings.items) { item in
                switch item {
                case .route(let route):
                    RouteCard(route: route, journeys: store.journeys[route.id] ?? [], now: now)
                case .stop(let stop):
                    StopCard(title: stop.name, subtitle: nil, departures: store.departures[stop.id], now: now)
                }
            }
            if store.settings.showNearby { nearbySection(now: now) }
            if store.settings.stops.isEmpty && store.settings.routes.isEmpty && !store.settings.showNearby {
                Text(L("Nothing saved yet. Press Edit to add a stop or a route.", "Noch nichts gespeichert. Mit „Bearbeiten“ fügst du eine Haltestelle oder Strecke hinzu.")).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func nearbySection(now: Date) -> some View {
        let saved = Set(store.settings.stops.map(\.id))
        let stops = store.nearby.filter { !saved.contains($0.id) }.prefix(3)
        Text(L("NEAR YOU", "IN DER NÄHE")).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
        switch store.locationStatus {
        case .denied, .restricted:
            Text(L("Location is off for TramBar. Turn it on in System Settings → Privacy & Security → Location Services.", "Ortungsdienste sind für TramBar aus. Schalte sie ein unter Systemeinstellungen → Datenschutz & Sicherheit → Ortungsdienste."))
                .font(.caption).foregroundStyle(.secondary)
        default:
            if stops.isEmpty {
                Text(L("Finding stops near you…", "Suche Haltestellen in der Nähe…")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(stops)) { stop in
                StopCard(title: stop.name, subtitle: stop.distance.map { "\($0) m" },
                         departures: store.departures[stop.id].map { Array($0.prefix(4)) }, now: now)
            }
        }
    }
}

struct StopCard: View {
    let title: String
    let subtitle: String?
    let departures: [EFA.Departure]?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            if let departures {
                let upcoming = departures.filter { $0.when > now.addingTimeInterval(-30) }.prefix(5)
                if upcoming.isEmpty { Text(L("No departures soon", "Keine Abfahrten in Kürze")).font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(upcoming)) { d in DepartureRow(d: d, now: now) }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DepartureRow: View {
    let d: EFA.Departure
    let now: Date
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: Fmt.symbol(d.kind)).frame(width: 16).foregroundStyle(.secondary)
            Text(d.line).font(.system(.body, design: .rounded)).fontWeight(.bold).frame(minWidth: 28, alignment: .leading)
            Text(d.destination).lineLimit(1).truncationMode(.tail)
            if let p = d.platform { Text(Fmt.platform(p)).font(.caption2).foregroundStyle(.secondary).help(L("Platform", "Steig") + " \(p)") }
            Spacer(minLength: 4)
            if d.cancelled {
                Text(L("cancelled", "fällt aus")).foregroundStyle(.red).font(.caption)
            } else {
                DelayBadge(minutes: d.delayMinutes, realtime: d.isRealtime)
                Text(Fmt.countdown(d.when, now: now)).monospacedDigit().fontWeight(.semibold)
                    .frame(minWidth: 48, alignment: .trailing)
            }
        }
        .strikethrough(d.cancelled)
        .help("\(d.line) → \(d.destination), \(L("planned", "planmäßig")) \(Fmt.clock.string(from: d.planned))")
    }
}

struct RouteCard: View {
    let route: Route
    let journeys: [EFA.Journey]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(route.from.name); Image(systemName: "arrow.right").font(.caption); Text(route.to.name)
            }
            .font(.subheadline).fontWeight(.semibold)
            let upcoming = journeys.filter { $0.departs > now.addingTimeInterval(-30) }.prefix(2)
            if upcoming.isEmpty { Text(L("Loading…", "Lädt…")).font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(upcoming)) { j in
                HStack(spacing: 8) {
                    Text(j.lines.joined(separator: " › ")).fontWeight(.bold).lineLimit(1)
                    if let p = j.platform { Text(Fmt.platform(p) == p ? "Gl. \(p)" : Fmt.platform(p)).font(.caption2).foregroundStyle(.secondary) }
                    Spacer(minLength: 4)
                    if j.cancelled {
                        Text(L("cancelled", "fällt aus")).foregroundStyle(.red).font(.caption)
                    } else {
                        Text("\(Fmt.clock.string(from: j.departs)) → \(Fmt.clock.string(from: j.arrives))")
                            .monospacedDigit().foregroundStyle(.secondary)
                        DelayBadge(minutes: j.departureDelay, realtime: j.departureEstimated != nil)
                        Text(Fmt.countdown(j.departs, now: now)).monospacedDigit().fontWeight(.semibold)
                            .frame(minWidth: 48, alignment: .trailing)
                    }
                }
                .strikethrough(j.cancelled)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: editing

struct EditView: View {
    @ObservedObject var store: Store
    @State private var routeFrom: EFA.Stop?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("SAVED · TOP TO BOTTOM", "GESPEICHERT · VON OBEN NACH UNTEN")).font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
            let items = store.settings.items
            if items.isEmpty {
                Text(L("Nothing saved yet.", "Noch nichts gespeichert.")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack {
                    switch item {
                    case .stop(let stop):
                        Text(stop.fullName)
                    case .route(let route):
                        Text("\(route.from.name) → \(route.to.name)")
                    }
                    Spacer()
                    let pinned = store.settings.pinned == item.id
                    Button { store.togglePin(item) } label: {
                        Image(systemName: item.id == store.menuItem?.id ? (pinned ? "pin.fill" : "menubar.rectangle") : "pin")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(item.id == store.menuItem?.id ? Color.accentColor : Color.secondary)
                    .help(pinned ? L("Pinned to the menu bar. Click to unpin.", "In der Menüleiste angeheftet. Klicken zum Lösen.")
                          : item.id == store.menuItem?.id ? L("Shown in the menu bar because it is on top. Click to pin.", "In der Menüleiste, weil ganz oben. Klicken zum Anheften.")
                          : L("Pin to the menu bar", "In der Menüleiste anheften"))
                    Button { store.move(item, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(index == 0).help(L("Move up", "Nach oben"))
                    Button { store.move(item, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).disabled(index == items.count - 1).help(L("Move down", "Nach unten"))
                    Button {
                        switch item {
                        case .stop(let stop): store.removeStop(stop)
                        case .route(let route): store.removeRoute(route)
                        }
                    } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }

            Divider()
            StopSearch(placeholder: L("Add a stop…", "Haltestelle hinzufügen…")) { store.addStop($0) }
            if let from = routeFrom {
                HStack {
                    Text(L("From", "Von") + " \(from.name)").font(.caption)
                    Spacer()
                    Button(L("Cancel", "Abbrechen")) { routeFrom = nil }.buttonStyle(.borderless).font(.caption)
                }
                StopSearch(placeholder: L("To…", "Nach…")) { to in store.addRoute(from: from, to: to); routeFrom = nil }
            } else {
                StopSearch(placeholder: L("Add a route: from…", "Strecke hinzufügen: von…")) { routeFrom = $0 }
            }

            Divider()
            Toggle(L("Show stops near my location", "Haltestellen in meiner Nähe zeigen"), isOn: Binding(get: { store.settings.showNearby }, set: { store.setShowNearby($0) }))
        }
    }
}

struct StopSearch: View {
    let placeholder: String
    let pick: (EFA.Stop) -> Void
    @State private var text = ""
    @State private var results: [EFA.Stop] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _, value in
                    searchTask?.cancel()
                    guard value.count >= 3 else { results = []; return }
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        results = (try? await EFA.searchStops(value)) ?? []
                    }
                }
            ForEach(results.prefix(6)) { stop in
                Button {
                    pick(stop); text = ""; results = []
                } label: {
                    Text(stop.fullName).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
