import Foundation
import ToolsmithKit

// The app's administrator helper. launchd runs it as root (registered by the app through
// SMAppService, approved by the user in System Settings → General → Login Items). It controls
// battery charging and nothing else, and only for the app signed by the same team.

guard geteuid() == 0 else {
    FileHandle.standardError.write(Data("ToolsmithHelper runs only from launchd, as root.\n".utf8))
    exit(64)
}

let service = ChargeService()
service.start()

let listener = NSXPCListener(machServiceName: ChargeHelperIdentity.machService)
// The system checks the caller's signature before a connection reaches the delegate.
listener.setConnectionCodeSigningRequirement(ChargeHelperIdentity.requirement(identifier: ChargeHelperIdentity.appBundleID))
let delegate = ListenerDelegate(service: service)
listener.delegate = delegate
listener.resume()

// Leaving (unregistered, updated, or stopped) gives charging back first.
for name in [SIGTERM, SIGINT, SIGHUP] {
    signal(name, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: name, queue: .main)
    source.setEventHandler {
        service.giveBack()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

RunLoop.main.run()
