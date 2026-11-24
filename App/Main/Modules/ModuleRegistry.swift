/// Every feature module the app is built with. Adding a feature is one line here; the order is
/// the order of the features page, the settings sidebar and a new install's menu bar.
@MainActor enum ModuleRegistry {
    static func make(host: ModuleHost) -> [AppModule] {
        [
            LauncherModule(host: host),
            AppsModule(host: host),
            ClipboardModule(host: host),
            SnippetsModule(host: host),
            WindowsModule(host: host),
            CaptureModule(host: host),
            AIModule(host: host),
            MonitorModule(host: host),
            AudioModule(host: host),
            ChargeModule(host: host),
            ScreenTimeModule(host: host),
        ]
    }
}
