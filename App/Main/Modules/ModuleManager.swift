import Combine
import Foundation
import SwiftUI
import ToolsmithKit

/// Keeps the running modules in step with the switches in the settings: a switch turned anywhere
/// (the features page, the first-run guide, the privacy page) starts or stops its module here.
@MainActor final class ModuleManager: ObservableObject {
    let modules: [AppModule]
    /// Ids of the modules running now.
    @Published private(set) var enabled: Set<String> = []
    private let settings: SettingsStore
    private var subscription: AnyCancellable?
    /// Called after modules started or stopped.
    var onChange: () -> Void = {}

    init(modules: [AppModule], settings: SettingsStore) {
        self.modules = modules
        self.settings = settings
    }

    var descriptors: [ModuleDescriptor] { modules.map(\.descriptor) }
    /// The running modules, in registry order.
    var running: [AppModule] { modules.filter { enabled.contains($0.descriptor.id) } }

    func isEnabled(_ id: String) -> Bool { enabled.contains(id) }

    func module(id: String) -> AppModule? { modules.first { $0.descriptor.id == id } }

    func running<M: AppModule>(_ type: M.Type) -> M? {
        modules.lazy.compactMap { $0 as? M }.first { self.enabled.contains($0.descriptor.id) }
    }

    /// Starts the modules that are on and follows the switches from then on.
    func activate() {
        apply(settings.settings.modules)
        // @Published announces a change before it is stored; the value arrives in the closure.
        subscription = settings.$settings.map(\.modules).removeDuplicates()
            .sink { [weak self] switches in
                DispatchQueue.main.async { self?.apply(switches) }
            }
    }

    /// Stops everything, for the app quitting.
    func deactivate() {
        subscription = nil
        for module in running.reversed() { module.stop() }
        enabled = []
    }

    private func apply(_ switches: ModuleSwitches) {
        let next = ModuleResolver.enabled(descriptors, switches: switches)
        guard next != enabled else { return }
        let previous = enabled
        // Stop dependents before what they depend on; start in the other order.
        for module in modules.reversed() where previous.contains(module.descriptor.id) && !next.contains(module.descriptor.id) {
            module.stop()
        }
        enabled = next
        for module in modules where next.contains(module.descriptor.id) && !previous.contains(module.descriptor.id) {
            module.start()
        }
        NSLog("modules started: %@, stopped: %@", next.subtracting(previous).sorted().joined(separator: ","), previous.subtracting(next).sorted().joined(separator: ","))
        onChange()
    }

    /// The menu bar items of the running modules, with the app icon first.
    func menuBarItems(appIcon: MenuBarItem) -> [MenuBarItem] {
        [appIcon] + running.flatMap(\.menuBarItems)
    }
}
