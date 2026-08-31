import Foundation

public enum IMAADPCM {
    private static let stepTable: [Int32] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
        50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
        253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
        1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
        3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442,
        11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794,
        32767,
    ]

    private static let indexTable: [Int32] = [
        -1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8,
    ]

    public static func decode(_ data: Data, predictor: Int16, stepIndex: UInt8) -> [Int16] {
        var pred = Int32(predictor)
        var index = Int32(min(stepIndex, 88))
        var out = [Int16]()
        out.reserveCapacity(data.count * 2)
        for byte in data {
            for nibble in [Int32(byte & 0x0F), Int32(byte >> 4)] {
                let step = stepTable[Int(index)]
                var diff = step >> 3
                if nibble & 1 != 0 { diff += step >> 2 }
                if nibble & 2 != 0 { diff += step >> 1 }
                if nibble & 4 != 0 { diff += step }
                pred += (nibble & 8 != 0) ? -diff : diff
                pred = max(-32768, min(32767, pred))
                index = max(0, min(88, index + indexTable[Int(nibble)]))
                out.append(Int16(pred))
            }
        }
        return out
    }

    public static func peak(_ pcm: [Int16]) -> Int {
        var p = 0
        for s in pcm {
            let v = s == Int16.min ? 32767 : abs(Int(s))
            if v > p { p = v }
        }
        return p
    }
}
