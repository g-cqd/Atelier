private func c(_ value: Unicode.Scalar) -> UInt32 { value.value }

extension YAMLExternalScanner {
    // State 34 aborts upstream. Decline the token if it is ever reached.
    // Keep the pinned core schema's transition table in its original order.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func advanceSchema(_ state: Int, _ char: UInt32, result: inout ResultSchema) -> Int? {
        switch state {
            case -1:
                break
            case 0:
                if char == c(".") {
                    result = .string
                    return 6
                }
                if char == c("0") {
                    result = .integer
                    return 37
                }
                if char == c("F") {
                    result = .string
                    return 2
                }
                if char == c("N") {
                    result = .string
                    return 16
                }
                if char == c("T") {
                    result = .string
                    return 13
                }
                if char == c("f") {
                    result = .string
                    return 17
                }
                if char == c("n") {
                    result = .string
                    return 29
                }
                if char == c("t") {
                    result = .string
                    return 26
                }
                if char == c("~") {
                    result = .null
                    return 35
                }
                if char == c("+") {
                    result = .string
                    return 1
                }
                if char == c("-") {
                    result = .string
                    return 1
                }
                if c("1") <= char && char <= c("9") {
                    result = .integer
                    return 38
                }
                break
            case 1:
                if char == c(".") {
                    result = .string
                    return 7
                }
                if c("0") <= char && char <= c("9") {
                    result = .integer
                    return 38
                }
                break
            case 2:
                if char == c("A") {
                    result = .string
                    return 9
                }
                if char == c("a") {
                    result = .string
                    return 22
                }
                break
            case 3:
                if char == c("A") {
                    result = .string
                    return 12
                }
                if char == c("a") {
                    result = .string
                    return 12
                }
                break
            case 4:
                if char == c("E") {
                    result = .boolean
                    return 36
                }
                break
            case 5:
                if char == c("F") {
                    result = .float
                    return 41
                }
                break
            case 6:
                if char == c("I") {
                    result = .string
                    return 11
                }
                if char == c("N") {
                    result = .string
                    return 3
                }
                if char == c("i") {
                    result = .string
                    return 24
                }
                if char == c("n") {
                    result = .string
                    return 18
                }
                if c("0") <= char && char <= c("9") {
                    result = .float
                    return 42
                }
                break
            case 7:
                if char == c("I") {
                    result = .string
                    return 11
                }
                if char == c("i") {
                    result = .string
                    return 24
                }
                if c("0") <= char && char <= c("9") {
                    result = .float
                    return 42
                }
                break
            case 8:
                if char == c("L") {
                    result = .null
                    return 35
                }
                break
            case 9:
                if char == c("L") {
                    result = .string
                    return 14
                }
                break
            case 10:
                if char == c("L") {
                    result = .string
                    return 8
                }
                break
            case 11:
                if char == c("N") {
                    result = .string
                    return 5
                }
                if char == c("n") {
                    result = .string
                    return 20
                }
                break
            case 12:
                if char == c("N") {
                    result = .float
                    return 41
                }
                break
            case 13:
                if char == c("R") {
                    result = .string
                    return 15
                }
                if char == c("r") {
                    result = .string
                    return 28
                }
                break
            case 14:
                if char == c("S") {
                    result = .string
                    return 4
                }
                break
            case 15:
                if char == c("U") {
                    result = .string
                    return 4
                }
                break
            case 16:
                if char == c("U") {
                    result = .string
                    return 10
                }
                if char == c("u") {
                    result = .string
                    return 23
                }
                break
            case 17:
                if char == c("a") {
                    result = .string
                    return 22
                }
                break
            case 18:
                if char == c("a") {
                    result = .string
                    return 25
                }
                break
            case 19:
                if char == c("e") {
                    result = .boolean
                    return 36
                }
                break
            case 20:
                if char == c("f") {
                    result = .float
                    return 41
                }
                break
            case 21:
                if char == c("l") {
                    result = .null
                    return 35
                }
                break
            case 22:
                if char == c("l") {
                    result = .string
                    return 27
                }
                break
            case 23:
                if char == c("l") {
                    result = .string
                    return 21
                }
                break
            case 24:
                if char == c("n") {
                    result = .string
                    return 20
                }
                break
            case 25:
                if char == c("n") {
                    result = .float
                    return 41
                }
                break
            case 26:
                if char == c("r") {
                    result = .string
                    return 28
                }
                break
            case 27:
                if char == c("s") {
                    result = .string
                    return 19
                }
                break
            case 28:
                if char == c("u") {
                    result = .string
                    return 19
                }
                break
            case 29:
                if char == c("u") {
                    result = .string
                    return 23
                }
                break
            case 30:
                if char == c("+") || char == c("-") {
                    result = .string
                    return 32
                }
                if c("0") <= char && char <= c("9") {
                    result = .float
                    return 43
                }
                break
            case 31:
                if c("0") <= char && char <= c("7") {
                    result = .integer
                    return 39
                }
                break
            case 32:
                if c("0") <= char && char <= c("9") {
                    result = .float
                    return 43
                }
                break
            case 33:
                if (c("0") <= char && char <= c("9")) || (c("A") <= char && char <= c("F"))
                    || (c("a") <= char && char <= c("f"))
                {
                    result = .integer
                    return 40
                }
                break
            case 34:
                return nil
            case 35:
                result = .null
                break
            case 36:
                result = .boolean
                break
            case 37:
                result = .integer
                if char == c(".") {
                    result = .float
                    return 42
                }
                if char == c("o") {
                    result = .string
                    return 31
                }
                if char == c("x") {
                    result = .string
                    return 33
                }
                if char == c("E") || char == c("e") {
                    result = .string
                    return 30
                }
                if c("0") <= char && char <= c("9") {
                    result = .integer
                    return 38
                }
                break
            case 38:
                result = .integer
                if char == c(".") {
                    result = .float
                    return 42
                }
                if char == c("E") || char == c("e") {
                    result = .string
                    return 30
                }
                if c("0") <= char && char <= c("9") {
                    result = .integer
                    return 38
                }
                break
            case 39:
                result = .integer
                if c("0") <= char && char <= c("7") {
                    result = .integer
                    return 39
                }
                break
            case 40:
                result = .integer
                if (c("0") <= char && char <= c("9")) || (c("A") <= char && char <= c("F"))
                    || (c("a") <= char && char <= c("f"))
                {
                    result = .integer
                    return 40
                }
                break
            case 41:
                result = .float
                break
            case 42:
                result = .float
                if char == c("E") || char == c("e") {
                    result = .string
                    return 30
                }
                if c("0") <= char && char <= c("9") {
                    result = .float
                    return 42
                }
                break
            case 43:
                result = .float
                if c("0") <= char && char <= c("9") {
                    result = .float
                    return 43
                }
                break
            default:
                result = .string
                return -1
        }
        if char != c("\r") && char != c("\n") && char != c(" ") && char != 0 { result = .string }
        return -1
    }
}
