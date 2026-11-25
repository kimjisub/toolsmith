import Foundation
import ObjectiveC

/// Talks to macOS's own charge limit through PowerUI's `PowerUISmartChargeClient` (a private
/// framework: the client System Settings uses). Every call is looked up at run time, so a macOS
/// without it simply reports `nil` instead of crashing. The helper reads the limit through it and
/// releases the limit through it; targets are written as preferences (`NativeChargeLimit`).
public final class SystemChargeLimitClient {
    private let client: NSObject

    private typealias Flag = @convention(c) (AnyObject, Selector) -> Bool
    private typealias Action = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
    private typealias Number = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt64
    private typealias Percent = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
    private typealias List = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?

    private static let required = ["isMCLSupported", "getMCLLimitWithError:", "isMCLCurrentlyEnabled:",
                                   "enableMCL:", "disableMCL:", "availableChargeLimitsWithError:"]

    /// nil when this macOS or this Mac has no charge limit of its own.
    public init?(clientName: String = ChargeHelperIdentity.helperBundleID) {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else { return nil }
        let allocated = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
        guard let made = allocated?.perform(NSSelectorFromString("initWithClientName:"), with: clientName)?
            .takeUnretainedValue() as? NSObject,
            Self.required.allSatisfy({ made.responds(to: NSSelectorFromString($0)) }) else { return nil }
        client = made
        guard call("isMCLSupported", Flag.self)(client, NSSelectorFromString("isMCLSupported")) else { return nil }
    }

    public func read() -> SystemChargeLimitState? {
        var error: NSError?
        let limit = call("getMCLLimitWithError:", Percent.self)(client, NSSelectorFromString("getMCLLimitWithError:"), &error)
        guard error == nil else { return nil }
        let raw = call("isMCLCurrentlyEnabled:", Number.self)(client, NSSelectorFromString("isMCLCurrentlyEnabled:"), &error)
        let list = call("availableChargeLimitsWithError:", List.self)(client, NSSelectorFromString("availableChargeLimitsWithError:"), &error)
        let choices = (list as? [NSNumber])?.map(\.intValue) ?? []
        return SystemChargeLimitState(limit: Int(limit), mode: SystemChargeLimitState.mode(raw: raw), choices: choices)
    }

    /// Switches the limit off through the agent, the only way it also clears what it registered with
    /// powerd. The agent ignores this while it thinks the limit is off, so it is switched on first.
    public func disable() -> String? {
        if read()?.mode == .off, let failure = perform("enableMCL:") { return failure }
        return perform("disableMCL:")
    }

    private func perform(_ selector: String) -> String? {
        var error: NSError?
        guard call(selector, Action.self)(client, NSSelectorFromString(selector), &error) else {
            return error?.localizedDescription ?? "PowerUI refused \(selector)"
        }
        return nil
    }

    private func call<T>(_ selector: String, _ type: T.Type) -> T {
        unsafeBitCast(client.method(for: NSSelectorFromString(selector)), to: type)
    }
}
