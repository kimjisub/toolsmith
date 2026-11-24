import AppKit
import SwiftUI
import ToolsmithKit

#if TOOLSMITH_DEV
extension MonitorModule {
    /// Development flags this module answers (see CLAUDE.md, 빌드와 확인).
    func runDevelopmentAid(_ arguments: [String]) {
        // Development aid: print what the system sampler reads on this Mac, twice a second apart, and quit.
        if CommandLine.arguments.contains("--print-system-sample") {
            let sampler = SystemSampler()
            sampler.prepare()
            _ = sampler.sample(full: true)
            Thread.sleep(forTimeInterval: 1)
            let s = sampler.sample(full: true)
            print(String(format: "cpu user %.1f%% system %.1f%% cores %@", s.cpu.user, s.cpu.system, s.cores.map { String(format: "%.0f", $0) }.joined(separator: ",")))
            print("clusters \(s.clusters.map { "\($0.name)×\($0.count)" }) assign \(s.coreCluster) clocks \(s.cpuClusterMHz.mapValues { Int($0) }) gpu \(s.gpuMHz.map { Int($0) } ?? -1)MHz")
            let m = s.memory
            print("memory app \(ByteSize.text(Int(m.app))) wired \(ByteSize.text(Int(m.wired))) compressed \(ByteSize.text(Int(m.compressed))) free \(ByteSize.text(Int(m.free))) pressure \(Int(m.pressure))% swap \(ByteSize.text(Int(m.swapUsed)))")
            print("gpu \(s.gpu.map { String(format: "%.0f%%", $0) } ?? "none") memory \(s.gpuMemory.map { ByteSize.text(Int($0)) } ?? "none")  disk \(s.volume.name) free \(ByteSize.text(Int(s.volume.available)))/\(ByteSize.text(Int(s.volume.total))) read \(MonitorText.rate(s.diskReadRate)) write \(MonitorText.rate(s.diskWriteRate))")
            print("network down \(MonitorText.rate(s.downloadRate)) up \(MonitorText.rate(s.uploadRate))  load \(s.loadAverage) uptime \(UptimeText.text(s.uptime))")
            let p = s.power
            print("power system \(p.system ?? -1) adapter \(p.adapter ?? -1) battery \(p.battery ?? -1) cpu \(p.cpu ?? -1) gpu \(p.gpu ?? -1) dram \(p.memory ?? -1) ane \(p.neuralEngine ?? -1)")
            if let b = s.battery { print("battery \(Int(b.level))% \(b.stateText) cycles \(b.cycleCount ?? -1) design \(b.designCapacity ?? -1) max \(b.maximumCapacity ?? -1) health \(b.health ?? -1) temp \(b.temperature ?? -1) condition \(b.condition ?? "-") adapter \(b.adapterWatts ?? -1)W") }
            print("accessories \(BatteryReader.accessories().map { "\($0.name) \(Int($0.level))%" }) energy mode \(BatteryReader.energyMode()?.label ?? "-")")
            print("fans \(s.fans.map { "#\($0.index) \(Int($0.rpm))rpm (\(Int($0.minimum))-\(Int($0.maximum)))" }.joined(separator: ", "))")
            print("sensors \(s.sensors.count): " + SensorCatalog.summaries(s.sensors).map { "\($0.name)×\($0.readings.count) avg \(Int($0.average)) peak \(Int($0.peak))" }.joined(separator: ", "))
            let addresses = NetworkReader.addresses()
            print("primary \(NetworkReader.primaryInterface() ?? "-") wifi \(NetworkReader.wifiName() ?? "(hidden)") vpn \(VPNDetection.names(tunnelAddresses: addresses)) physical \(VPNDetection.physicalInterface(primary: NetworkReader.primaryInterface(), addresses: addresses) ?? "-") addresses \(addresses.map { "\($0.interface)=\($0.address)" })")
            exit(0)
        }


        // Development aid: draw the power flow for made-up readings (charging, adapter only, on battery) into a picture, and quit.
        if let index = CommandLine.arguments.firstIndex(of: "--render-powerflow-demo"), index + 1 < CommandLine.arguments.count {
            func power(system: Double, adapter: Double?, battery: Double, cpu: Double, gpu: Double) -> PowerBreakdown {
                var power = PowerBreakdown()
                (power.system, power.adapter, power.battery, power.cpu, power.gpu, power.memory) = (system, adapter, battery, cpu, gpu, 0.9)
                return power
            }
            let cases = [power(system: 37.1, adapter: 63, battery: 25.9, cpu: 21.5, gpu: 2.6),
                         power(system: 28, adapter: 28, battery: 0, cpu: 9, gpu: 6),
                         power(system: 19, adapter: nil, battery: -19, cpu: 11, gpu: 1.2)]
            let content = VStack(spacing: Space.xl) { ForEach(cases.indices, id: \.self) { PowerFlow(power: cases[$0]) } }
            let renderer = ImageRenderer(content: content.padding(Space.l).frame(width: 340).background(Surface.menuBarBottom).environment(\.colorScheme, .dark))
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--show-monitor") {
            // Development aid: open the monitor as if its menu bar item was clicked, optionally with a section's details.
            let section = index + 1 < arguments.count ? MonitorSection(rawValue: arguments[index + 1]) : nil
            let topic = arguments.firstIndex(of: "--history").flatMap { $0 + 1 < arguments.count ? HistoryTopic(rawValue: arguments[$0 + 1]) : nil }
            let monitor: MonitorModule? = self
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { monitor?.open(section: section, below: nil) }
            if let topic { DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { monitor?.panels.showHistory(topic, blockFrame: CGRect(x: 0, y: 10, width: 320, height: 100)) } }
        }
    }
}
#endif
