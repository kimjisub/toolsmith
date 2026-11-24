import SwiftUI
import ToolsmithKit

extension SettingsStore {
    /// A two-way binding to one setting, saved on every change.
    func binding<Value>(_ keyPath: WritableKeyPath<ToolsmithKit.Settings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in self.update { $0[keyPath: keyPath] = value } })
    }

    /// A module's switch, as the user left it. The module starts or stops when it changes (ModuleManager).
    func moduleBinding(_ module: ModuleDescriptor) -> Binding<Bool> {
        Binding(get: { self.settings.modules.isOn(module) }, set: { on in self.update { $0.modules.set(module, on: on) } })
    }
}
