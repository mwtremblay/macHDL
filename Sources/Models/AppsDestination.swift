import Foundation

/// Where installed "apps" live for a given AppsService instance -- lets the
/// same generic list/install/delete stack manage two different directories:
/// the user-driven `+OPL/APPS/` folder (arbitrary homebrew installs) and the
/// bundled `PP.FHDB.APPS` folder ("Core Apps" -- OPL/SMS, shipped inside this
/// app and auto-installed by FreeHDBoot setup, but user-replaceable like any
/// other app). See FreeHDBootDestinationPaths.fhdbAppsPartitionName's doc
/// comment for why PP.FHDB.APPS's apps sit directly at the partition root
/// (no `APPS/` subdirectory the way `+OPL` has).
struct AppsDestination {
    let partitionName: String
    /// Subdirectory apps live under within the partition, or "" if apps sit
    /// directly at the partition root -- pfsutil's build_pfs_path already
    /// treats an empty subpath as the partition root (Scripts/pfsutil-src/
    /// pfsutil.c's build_pfs_path/cmd_put), so no daemon-side change is
    /// needed to support this.
    let appsSubdirectory: String
    let ensurePartitionExists: (PS1GameService, Disk) async throws -> Void

    func appFolderPFSPath(appFolderName: String) -> String {
        appsSubdirectory.isEmpty ? appFolderName : "\(appsSubdirectory)/\(appFolderName)"
    }

    func appPFSPath(appFolderName: String, relativePath: String) -> String {
        "\(appFolderPFSPath(appFolderName: appFolderName))/\(relativePath)"
    }

    static let oplApps = AppsDestination(
        partitionName: PFSDestinationPaths.oplPartitionName,
        appsSubdirectory: PFSDestinationPaths.oplAppsSubdirectory,
        ensurePartitionExists: { ps1Service, disk in try await ps1Service.createOPLPartitionIfNeeded(on: disk) }
    )

    static let fhdbApps = AppsDestination(
        partitionName: FreeHDBootDestinationPaths.fhdbAppsPartitionName,
        appsSubdirectory: "",
        ensurePartitionExists: { ps1Service, disk in try await ps1Service.createFHDBAppsPartitionIfNeeded(on: disk) }
    )
}
