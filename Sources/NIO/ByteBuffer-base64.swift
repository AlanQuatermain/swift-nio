//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Shamelessly nicked from Foundation/NSData.swift

/// The ranges of ASCII characters that are used to encode data in Base64.
fileprivate let base64ByteMappings: [Range<UInt8>] = [
    65 ..< 91,      // A-Z
    97 ..< 123,     // a-z
    48 ..< 58,      // 0-9
    43 ..< 44,      // +
    47 ..< 48,      // /
]
/**
 Padding character used when the number of bytes to encode is not divisible by 3
 */
fileprivate let base64Padding : UInt8 = 61 // =

/**
 This method takes a byte with a character from Base64-encoded string
 and gets the binary value that the character corresponds to.
 
 - parameter byte:       The byte with the Base64 character.
 - returns:              Base64DecodedByte value containing the result (Valid , Invalid, Padding)
 */
fileprivate enum Base64DecodedByte {
    case valid(UInt8)
    case invalid
    case padding
}

fileprivate func base64DecodeByte(_ byte: UInt8) -> Base64DecodedByte {
    guard byte != base64Padding else {return .padding}
    var decodedStart: UInt8 = 0
    for range in base64ByteMappings {
        if range.contains(byte) {
            let result = decodedStart + (byte - range.lowerBound)
            return .valid(result)
        }
        decodedStart += range.upperBound - range.lowerBound
    }
    return .invalid
}

/**
 This method takes six bits of binary data and encodes it as a character
 in Base64.
 
 The value in the byte must be less than 64, because a Base64 character
 can only represent 6 bits.
 
 - parameter byte:       The byte to encode
 - returns:              The ASCII value for the encoded character.
 */
fileprivate func base64EncodeByte(_ byte: UInt8) -> UInt8 {
    assert(byte < 64)
    var decodedStart: UInt8 = 0
    for range in base64ByteMappings {
        let decodedRange = decodedStart ..< decodedStart + (range.upperBound - range.lowerBound)
        if decodedRange.contains(byte) {
            return range.lowerBound + (byte - decodedStart)
        }
        decodedStart += range.upperBound - range.lowerBound
    }
    return 0
}

extension ByteBuffer {
    /// Encodes a given sequence of bytes in base64 representation and appends the
    /// encoded bytes to this buffer.
    ///
    /// The encoded data uses a 64-character line length and uses CRLF as a line break.
    ///
    /// - Parameter bytes: A sequence of bytes to encode using base-64.
    /// - Returns: The number of encoded bytes written to the buffer.
    @discardableResult
    mutating func write<S : Sequence>(bytesAsBase64 bytes: S) -> Int where S.Element == UInt8 {
        self.reserveCapacity(self.readableBytes + (bytes.underestimatedCount/3)*4)
        let start = self.writerIndex
        
        var currentByte : UInt8 = 0
        var realCount = 0
        
        for (index,value) in bytes.enumerated() {
            realCount = index+1 // ensure we get the actual count of items in the sequence
            switch index%3 {
            case 0:
                currentByte = (value >> 2)
                self.write(integer: base64EncodeByte(currentByte))
                currentByte = ((value << 6) >> 2)
            case 1:
                currentByte |= (value >> 4)
                self.write(integer: base64EncodeByte(currentByte))
                currentByte = ((value << 4) >> 2)
            case 2:
                currentByte |= (value >> 6)
                self.write(integer: base64EncodeByte(currentByte))
                currentByte = ((value << 2) >> 2)
                self.write(integer: base64EncodeByte(currentByte))
            default:
                fatalError()
            }
        }
        
        //add padding
        switch realCount%3 {
        case 0: break //no padding needed
        case 1:
            self.write(integer: base64EncodeByte(currentByte))
            self.write(integer: base64Padding)
            self.write(integer: base64Padding)
        case 2:
            self.write(integer: base64EncodeByte(currentByte))
            self.write(integer: base64Padding)
        default:
            fatalError()
        }
        
        return self.writerIndex - start
    }
    
    
    /// Decodes a sequence of base64-encoded bytes, writing the decoded bytes into the buffer.
    ///
    /// - Parameter bytes: A series of characters representing base64-encoded data.
    /// - Returns: The number of bytes decoded and written to the buffer.
    @discardableResult
    mutating func write<S : Sequence>(base64EncodedBytes bytes: S) -> Int where S.Element == UInt8 {
        self.reserveCapacity(self.readableBytes + (bytes.underestimatedCount/3)*2)
        
        var currentByte : UInt8 = 0
        var validCharacterCount = 0
        var paddingCount = 0
        var index = 0
        
        let start = self.writerIndex
        
        for base64Char in bytes {
            let value : UInt8
            
            switch base64DecodeByte(base64Char) {
            case .valid(let v):
                value = v
                validCharacterCount += 1
            case .invalid:
                return 0
            case .padding:
                paddingCount += 1
                continue
            }
            
            //padding found in the middle of the sequence is invalid
            if paddingCount > 0 {
                return 0
            }
            
            switch index%4 {
            case 0:
                currentByte = (value << 2)
            case 1:
                currentByte |= (value >> 4)
                self.write(integer: currentByte)
                currentByte = (value << 4)
            case 2:
                currentByte |= (value >> 2)
                self.write(integer: currentByte)
                currentByte = (value << 6)
            case 3:
                currentByte |= value
                self.write(integer: currentByte)
            default:
                fatalError()
            }
            
            index += 1
        }
        
        guard (validCharacterCount + paddingCount)%4 == 0 else {
            //invalid character count
            self.moveWriterIndex(to: start)
            return 0
        }
        
        return self.writerIndex - start
    }
}
