import Foundation

/// Other apps that control charging. Two controllers fight over the same limit (AlDente, for one,
/// sets macOS's limit when it quits), so while one runs Toolsmith writes nothing and says so.
public enum ChargeConflicts {
    public struct Known: Equatable, Sendable {
        public let name: String
        /// Lowercased pieces of an executable path that identify it.
        public let markers: [String]
    }

    public static let known: [Known] = [
        Known(name: "AlDente", markers: ["/aldente", "com.apphousekitchen.aldente"]),
        Known(name: "batt", markers: ["/batt", "cc.chlc.batt"]),
        Known(name: "battery", markers: ["/battery.sh", "/usr/local/bin/battery", "/smc_battery"]),
        Known(name: "Battery Toolkit", markers: ["me.mhaeuser.batterytoolkitd", "me.mhaeuser.batterytoolkit", "/battery toolkit.app/"]),
        Known(name: "Ampere", markers: ["/ampere.app/", "ampere-smcwriter"]),
    ]

    /// The names of known charge apps among these executable paths (and command lines), in the
    /// order of `known`. A path ends a marker that names a file only at a path boundary, so
    /// `/usr/bin/batteryd` is not `/batt`.
    public static func detect(_ paths: [String]) -> [String] {
        let lowered = paths.map { $0.lowercased() }
        return known.filter { app in
            lowered.contains { path in app.markers.contains { marker in matches(path, marker) } }
        }.map(\.name)
    }

    static func matches(_ path: String, _ marker: String) -> Bool {
        var start = path.startIndex
        while let found = path.range(of: marker, range: start..<path.endIndex) {
            let after = found.upperBound
            if marker.hasSuffix("/") || after == path.endIndex { return true }
            let next = path[after]
            if !(next.isLetter || next.isNumber) { return true }
            start = path.index(after: found.lowerBound)
        }
        return false
    }
}
