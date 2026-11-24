import Foundation

// The app ships English (the development language) and Korean. Text lives in string catalogs:
// App/Kit/Localizable.xcstrings for this framework, App/Main/Localizable.xcstrings for the app and
// App/Main/InfoPlist.xcstrings for the permission prompts. `scripts/localization.py` keeps them in
// step with the code (see CONTRIBUTING.md, "Text and languages").

private final class KitBundleMarker {}

extension Bundle {
    /// ToolsmithKit's own bundle, which holds its string catalog.
    public static let kit = Bundle(for: KitBundleMarker.self)
}

extension LocalizedStringResource.BundleDescription {
    /// ToolsmithKit's bundle, for text a framework type builds as a `LocalizedStringResource`.
    public static var kit: Self { .forClass(KitBundleMarker.self) }
}

extension Locale {
    /// The language the app's text is shown in, with the user's region for number and date formats.
    /// macOS picks the language at launch (System Settings or the app's own choice, `AppLanguage`);
    /// formatters use this so a date reads in the same language as the words around it.
    public static let app: Locale = {
        let language = Bundle.kit.preferredLocalizations.first ?? AppLanguage.developmentLanguage
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(identifier: language)
        return Locale(components: components)
    }()
}

/// Text from ToolsmithKit's string catalog in `locale`'s language (the app's by default).
/// Literals passed here are extracted into the catalog like `String(localized:)`.
func localized(_ value: String.LocalizationValue, locale: Locale = .app) -> String {
    String(localized: LocalizedStringResource(value, locale: locale, bundle: .kit))
}

public enum Localized {
    /// `resource` in every language the app ships. The launcher searches these, so a command is
    /// found by its English and its Korean name whichever language the app is shown in.
    public static func everyLanguage(_ resource: LocalizedStringResource) -> [String] {
        var seen = Set<String>()
        return AppLanguage.shipped.compactMap { language in
            var resource = resource
            resource.locale = Locale(identifier: language)
            let text = String(localized: resource)
            return seen.insert(text).inserted ? text : nil
        }
    }
}

/// The language the user chose for the app in Settings → General. macOS applies it at launch, so
/// a change takes effect after the app is reopened.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system, english, korean

    public static let developmentLanguage = "en"
    /// The languages the string catalogs carry.
    public static let shipped = ["en", "ko"]

    /// The language code macOS is asked to use, or nil to follow the system's list.
    public var code: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .korean: return "ko"
        }
    }

    /// A language's name in that language, as macOS lists them; "System" in the app's language.
    public func label(locale: Locale = .app) -> String {
        switch self {
        case .system: return localized("System Default", locale: locale)
        case .english: return "English"
        case .korean: return "한국어" // not localized: a language is listed by its own name
        }
    }

    /// The choice the app's own `AppleLanguages` preference stands for (nil or empty: follow the system).
    public init(preferredLanguages: [String]?) {
        let first = preferredLanguages?.first.map { Locale.Language(identifier: $0).languageCode?.identifier ?? $0 }
        self = Self.allCases.first { $0.code != nil && $0.code == first } ?? .system
    }

    /// The `AppleLanguages` value that makes macOS use this language, or nil to remove the app's own.
    public var preferredLanguages: [String]? { code.map { [$0] } }
}
