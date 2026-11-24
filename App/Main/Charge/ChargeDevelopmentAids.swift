import Foundation
import ToolsmithKit

#if TOOLSMITH_DEV
extension ChargeModule {
    /// Development flags this module answers (see CLAUDE.md, 빌드와 확인).
    func runDevelopmentAid(_ arguments: [String]) {
        if arguments.contains("--print-charge-status"), let charge {
            // Development aid: what battery charge control reports on this Mac and build, and quit.
            charge.refresh()
            print("charge state: \(charge.state) signedByTeam: \(ChargeController.isSignedByTeam)")
            charge.install()
            print("after install: \(charge.state)")
            exit(0)
        }
    }
}
#endif
