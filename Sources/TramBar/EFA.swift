import Foundation

/// Client for the VMS (Verkehrsverbund Mittelsachsen) EFA server, which VVO hosts.
/// Free, no key. Covers CVAG trams and buses plus DB regional trains, with realtime.
enum EFA {
    static let base = URL(string: "https://efa.vvo-online.de/VMSSL3/")!

    struct Stop: Codable, Hashable, Identifiable {
        var id: String          // global id, e.g. de:14511:30058
        var name: String        // "Gutenbergstr"
        var place: String?      // "Chemnitz"
        var distance: Int?      // metres, only from a nearby search

        var fullName: String { place.map { "\(name), \($0)" } ?? name }
    }

    enum Kind { case tram, bus, train, other }

    struct Departure: Identifiable, Hashable {
        var id: String { "\(line)|\(destination)|\(planned.timeIntervalSince1970)" }
        var line: String
        var kind: Kind
        var destination: String
        var planned: Date
        var estimated: Date?
        var platform: String?
        var cancelled: Bool

        var when: Date { estimated ?? planned }
        var delayMinutes: Int { estimated.map { Int(($0.timeIntervalSince(planned) / 60).rounded()) } ?? 0 }
        var isRealtime: Bool { estimated != nil }
    }

    struct Journey: Identifiable, Hashable {
        var id: String { "\(departurePlanned.timeIntervalSince1970)|\(lines.joined())" }
        var departurePlanned: Date
        var departureEstimated: Date?
        var arrivalPlanned: Date
        var arrivalEstimated: Date?
        var lines: [String]
        var platform: String?
        var cancelled: Bool

        var departs: Date { departureEstimated ?? departurePlanned }
        var arrives: Date { arrivalEstimated ?? arrivalPlanned }
        var departureDelay: Int { departureEstimated.map { Int(($0.timeIntervalSince(departurePlanned) / 60).rounded()) } ?? 0 }
        var arrivalDelay: Int { arrivalEstimated.map { Int(($0.timeIntervalSince(arrivalPlanned) / 60).rounded()) } ?? 0 }
    }

    // MARK: requests

    static func searchStops(_ text: String) async throws -> [Stop] {
        let json = try await get("XML_STOPFINDER_REQUEST", [
            "type_sf": "any", "name_sf": text, "anyObjFilter_sf": "2",
        ])
        return (json["locations"] as? [[String: Any]] ?? []).compactMap(stop)
    }

    static func nearbyStops(lat: Double, lon: Double, radius: Int = 1000, max: Int = 5) async throws -> [Stop] {
        let json = try await get("XML_COORD_REQUEST", [
            "coord": String(format: "%.6f:%.6f:WGS84[DD.DDDDD]", lon, lat),
            "coordOutputFormat": "WGS84[DD.DDDDD]",
            "type_1": "STOP", "radius_1": String(radius), "inclFilter": "1", "max": String(max),
        ])
        return (json["locations"] as? [[String: Any]] ?? []).compactMap(stop)
            .sorted { ($0.distance ?? .max) < ($1.distance ?? .max) }
    }

    static func departures(stopID: String, limit: Int = 8) async throws -> [Departure] {
        let json = try await get("XML_DM_REQUEST", [
            "type_dm": "stop", "name_dm": stopID, "mode": "direct", "useRealtime": "1", "limit": String(limit),
        ])
        return (json["stopEvents"] as? [[String: Any]] ?? []).compactMap { event in
            guard let t = event["transportation"] as? [String: Any],
                  let planned = date(event["departureTimePlanned"]) else { return nil }
            let product = t["product"] as? [String: Any]
            let destination = (t["destination"] as? [String: Any])?["name"] as? String ?? ""
            let location = event["location"] as? [String: Any]
            let platform = (location?["properties"] as? [String: Any])?["platform"] as? String
            return Departure(
                line: t["number"] as? String ?? t["disassembledName"] as? String ?? "?",
                kind: kind(product?["class"] as? Int),
                destination: shortPlace(destination),
                planned: planned,
                estimated: date(event["departureTimeEstimated"]),
                platform: platform?.isEmpty == false ? platform : nil,
                cancelled: isCancelled(event)
            )
        }
    }

    static func journeys(from: String, to: String, count: Int = 4) async throws -> [Journey] {
        let json = try await get("XML_TRIP_REQUEST2", [
            "type_origin": "stop", "name_origin": from,
            "type_destination": "stop", "name_destination": to,
            "useRealtime": "1", "calcNumberOfTrips": String(count),
        ])
        return (json["journeys"] as? [[String: Any]] ?? []).compactMap { journey in
            guard let legs = journey["legs"] as? [[String: Any]],
                  let origin = legs.first?["origin"] as? [String: Any],
                  let destination = legs.last?["destination"] as? [String: Any],
                  let depPlanned = date(origin["departureTimePlanned"]),
                  let arrPlanned = date(destination["arrivalTimePlanned"]) else { return nil }
            // Footpaths have no line number; leave them out of the summary.
            let lines = legs.compactMap { leg -> String? in
                let t = leg["transportation"] as? [String: Any]
                let name = t?["disassembledName"] as? String ?? t?["number"] as? String
                return (name?.isEmpty == false) ? name : nil
            }
            let platform = (origin["properties"] as? [String: Any])?["platform"] as? String
            return Journey(
                departurePlanned: depPlanned,
                departureEstimated: date(origin["departureTimeEstimated"]),
                arrivalPlanned: arrPlanned,
                arrivalEstimated: date(destination["arrivalTimeEstimated"]),
                lines: lines,
                platform: platform?.isEmpty == false ? platform : nil,
                cancelled: legs.contains(where: isCancelled)
            )
        }
    }

    // MARK: plumbing

    private static func get(_ endpoint: String, _ params: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(url: base.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = ([("outputFormat", "rapidJSON"), ("language", "de")] + params.map { ($0.key, $0.value) })
            .map { URLQueryItem(name: $0.0, value: $0.1) }
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue("TramBar/1.0 (macOS menu bar)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private static func stop(_ l: [String: Any]) -> Stop? {
        guard let id = l["id"] as? String else { return nil }
        let parent = l["parent"] as? [String: Any]
        let props = l["properties"] as? [String: Any]
        let name = l["disassembledName"] as? String ?? shortPlace(l["name"] as? String ?? id)
        return Stop(id: id, name: name, place: parent?["name"] as? String,
                    distance: props?["distance"] as? Int ?? (props?["distance"] as? String).flatMap(Int.init))
    }

    /// "Chemnitz, Bernsdorf" -> "Bernsdorf": every stop here is in Chemnitz anyway.
    private static func shortPlace(_ name: String) -> String {
        name.hasPrefix("Chemnitz, ") ? String(name.dropFirst("Chemnitz, ".count)) : name
    }

    private static func isCancelled(_ item: [String: Any]) -> Bool {
        (item["realtimeStatus"] as? [String] ?? []).contains { $0.contains("CANCEL") }
            || (item["isCancelled"] as? Bool ?? false)
    }

    private static func kind(_ productClass: Int?) -> Kind {
        switch productClass {
        case 4: return .tram
        case 5, 6, 7, 10, 11: return .bus
        case 0, 1, 2, 3, 13, 14, 15, 16: return .train
        default: return .other
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func date(_ value: Any?) -> Date? {
        (value as? String).flatMap(iso.date(from:))
    }
}
