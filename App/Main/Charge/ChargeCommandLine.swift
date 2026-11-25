import Foundation
import ServiceManagement
import ToolsmithKit

/// `toolsmith charge …`: the screens' actions through the same controller, for scripts and for
/// working on a Mac remotely. The one step left to a person is allowing the helper in System
/// Settings → General → Login Items: macOS lets no program give that approval.
extension ChargeModule {
    var commandLine: ModuleCommandLine? {
        ModuleCommandLine(name: "charge", usage: ChargeCommand.usage) { [weak self] request in
            guard let charge = self?.charge else { return .failure("Battery charging is not running.") }
            let command: ChargeCommand
            do {
                command = try ChargeCommand.parse(request.words)
            } catch ChargeCommand.ParseError.usage(let reason) {
                return .usage("\(reason)\n\n\(ChargeCommand.usage)")
            } catch {
                return .usage(ChargeCommand.usage)
            }
            return await ChargeCommandRunner(charge: charge).run(command, json: request.wantsJSON)
        }
    }
}

@MainActor struct ChargeCommandRunner {
    let charge: ChargeController

    func run(_ command: ChargeCommand, json: Bool) async -> CLIResponse {
        switch command {
        case .status, .helperStatus:
            await charge.refreshed()
            return report(json: json)
        case .limit(let percent):
            return await control(json: json) { charge.setLimit(percent, then: $0) }
        case .sailing(let points):
            return await control(json: json) { charge.setSailing(points, then: $0) }
        case .discharge(let on):
            return await control(json: json) { charge.setDischarging(on, then: $0) }
        case .topUp(let on):
            return await control(json: json) { charge.setToppingUp(on, then: $0) }
        case .helperInstall(let wait):
            return await install(wait: wait, json: json)
        case .helperUninstall:
            await charge.refreshed()
            guard charge.helperEnabled || charge.state == .needsApproval else { return report(json: json) }
            await withCheckedContinuation { continuation in charge.uninstall { continuation.resume() } }
            return finished(report(json: json))
        }
    }

    /// A change goes only to a running helper; the answer is the state after it.
    private func control(json: Bool, _ send: (@escaping @MainActor () -> Void) -> Void) async -> CLIResponse {
        await charge.refreshed()
        guard charge.state == .running else {
            return .failure("The helper is not running (\(Self.helperName(charge.state))). Run: toolsmith charge helper install --wait")
        }
        await withCheckedContinuation { continuation in send { continuation.resume() } }
        return finished(report(json: json))
    }

    private func install(wait: Bool, json: Bool) async -> CLIResponse {
        await charge.refreshed()
        if !charge.helperEnabled {
            charge.install()
            await charge.refreshed()
        }
        if wait {
            let deadline = Date().addingTimeInterval(ChargeCommand.approvalTimeout)
            while charge.state == .needsApproval, Date() < deadline {
                try? await Task.sleep(for: .seconds(2))
                await charge.refreshed()
            }
        }
        if charge.state == .needsApproval {
            return CLIResponse(exitCode: 1, output: "Approval needed: System Settings → General → Login Items → Allow in the Background → \(AppIdentity.name). macOS leaves this step to a person."
                                   + (wait ? " Gave up waiting after \(Int(ChargeCommand.approvalTimeout / 60)) minutes." : " Run with --wait to wait for it."))
        }
        return finished(report(json: json))
    }

    /// The report, failing when the controller reports an error.
    private func finished(_ response: CLIResponse) -> CLIResponse {
        if case .failed = charge.state { return CLIResponse(exitCode: 1, output: response.output) }
        return response
    }

    private func report(json: Bool) -> CLIResponse {
        let english = Locale(identifier: "en_US")
        let snapshot = charge.snapshot
        let status = charge.status
        var detail: String?
        if case .failed(let message) = charge.state { detail = message }
        if case .outdated(let version) = charge.state { detail = "installed version \(version), this app needs \(ChargeHelperIdentity.version)" }
        let report = ChargeReport(activity: snapshot?.activity.rawValue, summary: snapshot.map { ChargeSummary.headline($0, locale: english) },
                                  level: snapshot?.percent, onAdapter: snapshot?.onAdapter, limit: snapshot?.limit, sailing: snapshot?.sailing,
                                  helper: Self.helperName(charge.state), helperDetail: detail, method: status?.method?.rawValue,
                                  systemLimit: status?.systemLimit, conflicts: snapshot?.conflicts ?? [], error: charge.error)
        return json ? .json(report) : CLIResponse(output: report.text)
    }

    static func helperName(_ state: ChargeController.State) -> String {
        switch state {
        case .unsupportedBuild: return "unsupportedBuild"
        case .noBattery: return "noBattery"
        case .notInstalled: return "notInstalled"
        case .needsApproval: return "needsApproval"
        case .running: return "running"
        case .outdated: return "outdated"
        case .unsupportedMac: return "unsupportedMac"
        case .failed: return "failed"
        }
    }
}
