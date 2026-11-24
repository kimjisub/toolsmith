import Foundation
import ObjectiveC
import ToolsmithKit

/// Talks to macOS's own charge limit through PowerUI's `PowerUISmartChargeClient` (a private
/// framework: the same client System Settings and the Shortcuts action use). Every call is looked
/// up at run time, so a macOS without it simply reports `nil` instead of crashing.
final class SystemChargeLimitClient {
    private let client: NSObject

    private typealias Flag = @convention(c) (AnyObject, Selector) -> Bool
    private typealias Action = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
    private typealias Number = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt64
    private typealias Percent = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
    private typealias SetPercent = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool
    private typealias List = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> AnyObject?

    private static let required = ["isMCLSupported", "getMCLLimitWithError:", "setMCLLimit:error:", "isMCLCurrentlyEnabled:",
                                   "enableMCL:", "temporarilyDisableMCL:", "availableChargeLimitsWithError:"]

    /// nil when this macOS or this Mac has no charge limit of its own.
    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else { return nil }
        let allocated = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
        guard let made = allocated?.perform(NSSelectorFromString("initWithClientName:"), with: ChargeHelperIdentity.appBundleID)?
            .takeUnretainedValue() as? NSObject,
            Self.required.allSatisfy({ made.responds(to: NSSelectorFromString($0)) }) else { return nil }
        client = made
        guard call("isMCLSupported", Flag.self)(client, NSSelectorFromString("isMCLSupported")) else { return nil }
    }

    func read() -> SystemChargeLimitState? {
        var error: NSError?
        let limit = call("getMCLLimitWithError:", Percent.self)(client, NSSelectorFromString("getMCLLimitWithError:"), &error)
        guard error == nil else { return nil }
        let raw = call("isMCLCurrentlyEnabled:", Number.self)(client, NSSelectorFromString("isMCLCurrentlyEnabled:"), &error)
        let list = call("availableChargeLimitsWithError:", List.self)(client, NSSelectorFromString("availableChargeLimitsWithError:"), &error)
        let choices = (list as? [NSNumber])?.map(\.intValue) ?? []
        return SystemChargeLimitState(limit: Int(limit), mode: SystemChargeLimitState.mode(raw: raw), choices: choices)
    }

    /// Sets the limit (80…100) and turns it on. Returns why it failed, or nil.
    func set(limit: Int) -> String? {
        var error: NSError?
        // PowerUI crashes below 80, so the value never goes there.
        let value = UInt8(clamping: min(max(limit, 80), 100))
        guard call("setMCLLimit:error:", SetPercent.self)(client, NSSelectorFromString("setMCLLimit:error:"), value, &error) else {
            return error?.localizedDescription ?? "충전 제한을 바꾸지 못했습니다"
        }
        return perform("enableMCL:")
    }

    /// Suspends the limit until the battery is full or the adapter comes off.
    func topUp() -> String? { perform("temporarilyDisableMCL:") }

    /// Brings a suspended limit back now.
    func resume() -> String? { perform("enableMCL:") }

    private func perform(_ selector: String) -> String? {
        var error: NSError?
        guard call(selector, Action.self)(client, NSSelectorFromString(selector), &error) else {
            return error?.localizedDescription ?? "충전 제한을 바꾸지 못했습니다"
        }
        return nil
    }

    private func call<T>(_ selector: String, _ type: T.Type) -> T {
        unsafeBitCast(client.method(for: NSSelectorFromString(selector)), to: type)
    }
}
