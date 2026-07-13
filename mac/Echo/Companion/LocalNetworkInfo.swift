import Darwin
import Foundation
import Network

enum LocalNetworkInfo {
    /// Best-effort primary LAN IPv4 (skips loopback / link-local when possible).
    static func primaryIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferred: String?
        var fallback: String?

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: hostname)
            if ip.hasPrefix("169.254.") {
                fallback = fallback ?? ip
                continue
            }
            let name = String(cString: interface.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("wlan") {
                preferred = ip
                break
            }
            fallback = fallback ?? ip
        }
        address = preferred ?? fallback
        return address
    }

    static var hostDisplayName: String {
        Host.current().localizedName ?? "Mac"
    }
}
