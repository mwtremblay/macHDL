import Foundation
import Security

final class HDLDumpHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard Self.isConnectionFromOurApp(connection) else {
            return false
        }

        let service = HDLDumpHelperService()

        connection.exportedInterface = NSXPCInterface(with: HDLDumpHelperProtocol.self)
        connection.exportedObject = service
        connection.remoteObjectInterface = NSXPCInterface(with: HDLDumpHelperProgressProtocol.self)

        // Per-connection state (the tracked install process for cancellation)
        // lives on `service`, which is unique to this connection -- clear its
        // progress delegate on invalidation so it can't call back into a dead
        // connection.
        connection.invalidationHandler = { [weak service] in
            service?.progressDelegate = nil
        }

        connection.resume()

        service.progressDelegate = connection.remoteObjectProxyWithErrorHandler { _ in
            // Progress delivery is best-effort -- a broken progress channel
            // doesn't need to fail the underlying disk operation.
        } as? HDLDumpHelperProgressProtocol

        return true
    }

    /// Validates the connecting client's code signature using its PID (public
    /// API) rather than NSXPCConnection's private/unsupported `auditToken`
    /// property. The audit-token approach would be immune to PID-reuse races,
    /// but requires an unsupported KVC workaround to access; this is an
    /// explicitly accepted v1 tradeoff for a personal single-user utility --
    /// the exploit window here is effectively nil since this check runs
    /// synchronously, before any request is serviced.
    /// TODO: revisit with audit-token-based validation if this app is ever
    /// distributed beyond this one Mac.
    private static func isConnectionFromOurApp(_ connection: NSXPCConnection) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: connection.processIdentifier] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code
        else {
            return false
        }

        // Team ID 7QW68VQ33R ("Michael Tremblay (Personal Team)") matches
        // this Mac's sole codesigning identity ("Apple Development:
        // michaelwtremblay@outlook.com (UH26446637)" -- note UH26446637 is
        // NOT the team ID, it's a different identifier embedded in the
        // certificate's Common Name; the real team ID is in the cert's OU
        // field, confirmed via `security find-certificate` + openssl and
        // cross-checked against Xcode's own cached account info), used to
        // sign both the app and this daemon. Verify this exact
        // requirement-string syntax against `codesign -d -r-` on the real
        // built app before trusting it -- see the plan's verification steps.
        let requirementString = "identifier \"\(HDLDumpHelperConstants.appBundleIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"7QW68VQ33R\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else {
            return false
        }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
