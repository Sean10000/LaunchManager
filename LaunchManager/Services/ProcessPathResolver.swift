import Darwin
import Foundation

enum ProcessPathResolver {
    static func executablePath(for pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let end = buffer.prefix(while: { $0 != 0 })
        guard let path = String(bytes: end, encoding: .utf8) else { return nil }
        return FilePathNormalizer.display(path)
    }

    static func currentWorkingDirectory(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let bytes = UnsafeRawBufferPointer(start: base, count: raw.count).prefix(while: { $0 != 0 })
            guard let path = String(bytes: bytes, encoding: .utf8) else { return nil }
            return FilePathNormalizer.display(path)
        }
    }
}
