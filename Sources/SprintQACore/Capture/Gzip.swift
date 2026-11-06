import Compression
import Foundation

/// Gzip with Apple's raw DEFLATE, a gzip header and a CRC32; no dependency.
public enum Gzip {
    public static func compress(_ data: Data) -> Data? {
        let capacity = data.count + data.count / 100 + 1024
        var deflated = Data(count: capacity)
        let written = deflated.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 || data.isEmpty else { return nil }
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        out.append(deflated.prefix(written))
        out.append(contentsOf: littleEndian(crc32(data)))
        out.append(contentsOf: littleEndian(UInt32(truncatingIfNeeded: data.count)))
        return out
    }

    private static func littleEndian(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24 & 0xff)]
    }

    private static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xffff_ffff
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffff_ffff
    }
}
