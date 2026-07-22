import Foundation

/// Centralizes FreeHDBoot's on-disk partition/file layout. Every partition
/// name and file mapping here is read directly from the vendored
/// FreeMcBoot-Installer source (`installer/system.c`'s `HDDBaseFiles[]` and
/// `PS2SysHDDFiles[]` tables, for a PS2/CEX-console install), not guessed or
/// inferred from tutorials -- see FreeHDBootService's doc comments for the
/// exact reasoning, since getting this wrong risks writing corrupt data onto
/// a real HDD's partition table.
enum FreeHDBootDestinationPaths {
    /// `__net`/`__system`/`__sysconf`/`__common` are all created and
    /// PFS-formatted automatically by `pfsshell initialize yes` in one shot
    /// (see FreeHDBootService.initializeAPA) -- nothing here creates them
    /// individually.
    static let netPartitionName = "__net"
    static let systemPartitionName = "__system"
    static let sysconfPartitionName = "__sysconf"
    static let commonPartitionName = "__common"

    /// FreeHDBoot's own dedicated apps partition -- not part of the fixed
    /// set `pfsshell initialize yes` auto-creates, so FreeHDBootService
    /// creates it explicitly (see PS1GameService.createFHDBAppsPartitionIfNeeded)
    /// before writing into it. Named `PP.FHDB.APPS` to match exactly what
    /// this app's own forked `FREEHDB.CNF` (see the `FREEHDB`/`CNF` payload
    /// entry below) points its OSD menu paths at for OPL/SMS -- confirmed
    /// against the vendored stock FREEHDB.CNF's own `LK_L1_E3`/
    /// `path3_OSDSYS_ITEM_3` entries, not invented by this app.
    static let fhdbAppsPartitionName = "PP.FHDB.APPS"

    static let fmcbSysconfSubdirectory = "FMCB"
    static let fsckSubdirectory = "fsck"
    static let fsckLangSubdirectory = "fsck/lang"
    static let osdSubdirectory = "osd"
    static let fhdbAppsOPLSubdirectory = "OPL"
    static let fhdbAppsSMSSubdirectory = "SMS"

    /// The bundled resource (by `Bundle.main.url(forResource:withExtension:)`
    /// name) that must be installed via `hdl_dump inject_mbr`, never as a
    /// plain PFS file copy like everything in `payloadFiles` below -- see
    /// `installer/system.c`'s `PS2SysHDDFiles[]`: `SYSTEM/MBR.XLF` is the
    /// only entry targeting `hdd0:__mbr` directly, routed through a
    /// dedicated `InstallMBRToHDD` function on-console, not the plain
    /// `fopen`/`fread`/`fwrite` copy every other HDD-bound file goes through.
    static let mbrKelfResourceName = "MBR"
    static let mbrKelfResourceExtension = "XLF"

    /// One entry per file `installer/system.c` copies onto the HDD, keyed by
    /// the bundled resource's name/extension (see project.yml's FreeHDBoot
    /// resource entries, all sourced from
    /// `Vendor/FreeMcBoot-Installer/installer_res/1966/INSTALL/`), plus the
    /// three "core" homebrew apps (uLaunchELF, OPL, SMS) this app's forked
    /// `FREEHDB.CNF` OSD menu expects to find already installed -- see
    /// Resources/FreeHDBoot/ and this file's `FREEHDB`/`CNF` entry, whose
    /// `resourceName`/`resourceExtension` now resolve to the project-owned
    /// fork rather than the vendored stock file.
    struct PayloadFile {
        let resourceName: String
        let resourceExtension: String
        let partitionName: String
        let pfsPath: String
    }

    static let payloadFiles: [PayloadFile] = [
        PayloadFile(resourceName: "FHDB", resourceExtension: "XLF", partitionName: systemPartitionName, pfsPath: "\(osdSubdirectory)/osdmain.elf"),
        PayloadFile(resourceName: "ENDVDPL", resourceExtension: "XRX", partitionName: sysconfPartitionName, pfsPath: "\(fmcbSysconfSubdirectory)/endvdpl.irx"),
        PayloadFile(resourceName: "FSCK", resourceExtension: "XLF", partitionName: systemPartitionName, pfsPath: "\(fsckSubdirectory)/fsck.elf"),
        PayloadFile(resourceName: "NotoSans-Bold", resourceExtension: "ttf", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/NotoSans-Bold.ttf"),
        PayloadFile(resourceName: "NotoSansJP-Bold", resourceExtension: "otf", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/NotoSansJP-Bold.otf"),
        PayloadFile(resourceName: "fonts", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/fonts.txt"),
        PayloadFile(resourceName: "strings_JA", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/strings_JA.txt"),
        PayloadFile(resourceName: "labels_JA", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/labels_JA.txt"),
        PayloadFile(resourceName: "strings_FR", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/strings_FR.txt"),
        PayloadFile(resourceName: "labels_FR", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/labels_FR.txt"),
        PayloadFile(resourceName: "strings_SP", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/strings_SP.txt"),
        PayloadFile(resourceName: "labels_SP", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/labels_SP.txt"),
        PayloadFile(resourceName: "strings_GE", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/strings_GE.txt"),
        PayloadFile(resourceName: "labels_GE", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/labels_GE.txt"),
        PayloadFile(resourceName: "strings_IT", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/strings_IT.txt"),
        PayloadFile(resourceName: "labels_IT", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/labels_IT.txt"),
        PayloadFile(resourceName: "strings_DU", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/strings_DU.txt"),
        PayloadFile(resourceName: "labels_DU", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/labels_DU.txt"),
        PayloadFile(resourceName: "strings_PO", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/strings_PO.txt"),
        PayloadFile(resourceName: "labels_PO", resourceExtension: "txt", partitionName: systemPartitionName, pfsPath: "\(fsckLangSubdirectory)/labels_PO.txt"),
        PayloadFile(resourceName: "FREEHDB", resourceExtension: "CNF", partitionName: sysconfPartitionName, pfsPath: "\(fmcbSysconfSubdirectory)/FREEHDB.CNF"),
        PayloadFile(resourceName: "FMCB_CFG", resourceExtension: "ELF", partitionName: sysconfPartitionName, pfsPath: "\(fmcbSysconfSubdirectory)/FMCB_CFG.ELF"),
        PayloadFile(resourceName: "USBD", resourceExtension: "IRX", partitionName: sysconfPartitionName, pfsPath: "\(fmcbSysconfSubdirectory)/USBD.IRX"),
        PayloadFile(resourceName: "USBHDFSD", resourceExtension: "IRX", partitionName: sysconfPartitionName, pfsPath: "\(fmcbSysconfSubdirectory)/USBHDFSD.IRX"),

        // "Core" apps the forked FREEHDB.CNF's OSD menu expects -- see
        // fhdbAppsPartitionName's doc comment. uLaunchELF's paths (item 1)
        // are unchanged from FreeMcBoot's own stock config, so it goes into
        // __sysconf/FMCB/ alongside FreeHDBoot's own files, not the new
        // partition; OPL and SMS (items 2 and 4) go into PP.FHDB.APPS.
        PayloadFile(resourceName: "ULE_ISR", resourceExtension: "ELF", partitionName: sysconfPartitionName, pfsPath: "\(fmcbSysconfSubdirectory)/BOOT.ELF"),
        PayloadFile(resourceName: "OPL110", resourceExtension: "ELF", partitionName: fhdbAppsPartitionName, pfsPath: "\(fhdbAppsOPLSubdirectory)/OPNPS2LD.ELF"),
        PayloadFile(resourceName: "SMS", resourceExtension: "ELF", partitionName: fhdbAppsPartitionName, pfsPath: "\(fhdbAppsSMSSubdirectory)/SMS.ELF"),
    ]
}
