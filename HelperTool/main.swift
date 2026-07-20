import Foundation

let delegate = HDLDumpHelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HDLDumpHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
