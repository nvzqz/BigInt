//
//  Digits.swift
//  BigInt
//
//  Created by Károly Lőrentey on 2015-12-27.
//  Copyright © 2015 Károly Lőrentey. All rights reserved.
//

import Foundation

#if TinyDigits
public typealias Digit = UInt8
#else
public typealias Digit = UIntMax
#endif

//MARK: Digit multiplication

extension Digit {
    /// Return a tuple with the high and low digits of the product of `x` and `y`.
    @warn_unused_result
    internal static func fullMultiply(x: Digit, _ y: Digit) -> (high: Digit, low: Digit) {
        let (a, b) = x.split
        let (c, d) = y.split

        // We don't have a full-width multiplication, so we build it out of four half-width multiplications.
        // x * y = ac * HH + (ad + bc) * H + bd where H = 2^(n/2)
        let (mv, mo) = Digit.addWithOverflow(a * d, b * c)
        let (low, lo) = Digit.addWithOverflow(b * d, mv.low << halfShift)
        let high = a * c + mv.high + (mo ? 1 << halfShift : 0) + (lo ? 1 : 0)
        return (high, low)
    }

    @warn_unused_result
    internal static func divmod(x: Digit, _ y: Digit) -> (div: Digit, mod: Digit) {
        return (x / y, x % y)
    }

    private init(high: Digit, low: Digit) {
        assert(low.high == 0 && high.high == 0)
        self = (high << Digit.halfShift) | low
    }

    /// Divide the two-digit number `(u1, u0)` by `v` and return the quotient and remainder.
    /// - Requires: `u1 < v`, so that the result will fit in a single digit.
    /// - Complexity: O(1) with 2 divisions, 6 multiplications and ~12 or so additions/subtractions.
    @warn_unused_result
    public static func fullDivide(u1: Digit, _ u0: Digit, _ v: Digit) -> (div: Digit, mod: Digit) {
        // Division is complicated.
        // This is a Swift adaptation for "divlu2" in Hacker's Delight,
        // which is in turn a C adaptation of Knuth Algorithm D (TAOCP vol 2, 4.3.1).
        precondition(u1 < v)

        /// Find the half-digit quotient in `(uh, ul) / vn`, which must be normalized.
        /// - Requires: uh < vn && ul.high == 0 && vn.rank = width(Digit)
        func quotient(uh: Digit, _ ul: Digit, _ vn: Digit) -> Digit {
            let (vn1, vn0) = vn.split
            let q = uh / vn1 // Approximated quotient.
            let r = uh - q * vn1 // Remainder, less than vn1
            let p = q * vn0
            // q is often already correct, but sometimes the approximation overshoots by at most 2.
            // The code that follows checks for this while being careful not to need double-digit operations.
            if q.high == 0 && p <= (r << halfShift) | ul { return q }
            if (r + vn1).high != 0 { return q - 1 }
            if (q - 1).high == 0 && (p - vn0) <= ((r + vn1) << halfShift) | ul { return q - 1 }
            assert((r + 2 * vn1).high != 0 || p - 2 * vn0 <= (r + 2 * vn1) << halfShift | ul)
            return q - 2
        }
        /// Divide 3 half-digits by 2 half-digits to get a half-digit quotient and a full-digit remainder.
        /// - Requires: uh < vn && ul.high == 0 && vn.rank = width(Digit)
        func divmod(uh: Digit, _ ul: Digit, _ v: Digit) -> (div: Digit, mod: Digit) {
            let q = quotient(uh, ul, v)
            // Note that `uh << halfShift` will shift off a couple of bits, and `q * v` and the
            // subtraction are likely to overflow. Despite this, the end result (remainder) will
            // still be correct and it will fit inside a single (full) Digit.
            let r = ((uh << halfShift) | ul) &- q &* v
            assert(r < v)
            return (q, r)
        }

        // Normalize u and v such that v has no leading zeroes.
        let w = v.rank // width of v
        let z = (2 * halfShift - w) // number of leading zeroes in v
        let vn = v << z

        let un32 = (z == 0 ? u1 : (u1 << z) | (u0 >> w))
        let un10 = u0 << z
        let (un1, un0) = un10.split

        // We are dividing `(un32,un10)` with `vn`.

        // We split the full 4/2 division into two 3/2 ones.
        let (q1, un21) = divmod(un32, un1, vn)
        let (q0, rn) = divmod(un21, un0, vn)

        // Undo normalization of remainder and combine the two halves of the quotient.
        let mod = rn >> z
        let div = Digit(high: q1, low: q0)
        return (div, mod)
    }
}