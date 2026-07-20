import Foundation
import ServiceManagement

/// Owns the privileged helper daemon's SMAppService registration/approval
/// state. "Needs approval" is deliberately surfaced as its own dedicated
/// published flag driving a dedicated sheet (HelperApprovalSheet) rather than
/// threaded through the generic IdentifiableError alert plumbing -- it's a
/// one-time setup step with its own actionable UI (an "Open System Settings"
/// button), not really an "error."
@MainActor
final class HelperRegistrationViewModel: ObservableObject {
    @Published var needsApproval = false
    @Published var registrationFailure: IdentifiableError?

    private let helper: HDLDumpHelperClient

    init(helper: HDLDumpHelperClient) {
        self.helper = helper
    }

    /// Called once at launch. Front-loads the one-time approval prompt rather
    /// than surprising the user mid-workflow the first time they try a
    /// privileged action.
    ///
    /// `SMAppService.register()` is observed to throw ("Operation not
    /// permitted") even when it successfully reaches the expected
    /// `.requiresApproval` state -- Apple's own docs describe that state as
    /// "successfully registered, but the user needs to take action in System
    /// Settings," which doesn't sound like a thrown-error condition, but in
    /// practice it can throw anyway. So: don't treat every throw as fatal --
    /// always re-check `.status` afterward and only surface a blocking error
    /// if registration didn't actually reach a sane state (`.enabled` or
    /// `.requiresApproval`).
    func registerIfNeeded() {
        var caughtError: Error?
        do {
            try helper.register()
        } catch {
            caughtError = error
        }

        refreshStatus()

        switch helper.registrationStatus {
        case .enabled, .requiresApproval:
            break
        default:
            registrationFailure = IdentifiableError(
                underlying: caughtError ?? NSError(
                    domain: "HelperRegistration",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "The privileged helper could not be registered."]
                )
            )
        }
    }

    /// Re-checked defensively before each privileged call, in case approval
    /// was revoked mid-session via System Settings -- if so this re-surfaces
    /// the same approval sheet rather than a generic error.
    func refreshStatus() {
        needsApproval = (helper.registrationStatus == .requiresApproval)
    }

    func openSystemSettings() {
        helper.openSystemSettingsLoginItems()
    }
}
