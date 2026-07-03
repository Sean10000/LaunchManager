import Darwin
import Foundation

enum ProcessPathResolver {
    static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return FilePathNormalizer.normalize(String(cString: buffer))
    }

    static func currentWorkingDirectory(for pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let cString = base.assumingMemoryBound(to: CChar.self)
            guard let path = String(validatingUTF8: cString) else { return nil }
            return FilePathNormalizer.normalize(path)
        }
    }
}
