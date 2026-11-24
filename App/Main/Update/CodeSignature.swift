import Foundation
import Security
import ToolsmithKit

/// What this copy of the app is signed with.
enum CodeSignature {
    /// Whether the running app carries the team's Developer ID signature (`AppIdentity.teamID`).
    /// Released builds do; development builds (ad-hoc or a local certificate) do not, so they
    /// neither update themselves nor install the charge helper.
    static var isSignedByTeam: Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return false }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String == AppIdentity.teamID
    }
}

