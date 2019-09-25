//
//  main.swift
//  w3xplorer
//
//  MIT License
//
//  Copyright (c) 2019 Maxime CHAPELET
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.


import Foundation

struct ChunkHeader {
    var offset:UInt32 = 0
    var unknown:UInt32 = 0
    var length:UInt32 = 0
}

var chunkHeaders:Array<ChunkHeader> = Array<ChunkHeader>()

if CommandLine.arguments.count < 2 {
    exit(EXIT_FAILURE)
}

let path = CommandLine.arguments[1]

guard let fileHandle = FileHandle(forReadingAtPath: path) else {
    exit(EXIT_FAILURE)
}

let fileSize:UInt64 = fileHandle.seekToEndOfFile();
fileHandle.seek(toFileOffset: 0)
var chunkCount:Int64 = 0
while fileHandle.offsetInFile < fileSize {
    if chunkCount == 0 {
        let data:Data = fileHandle.readData(ofLength: MemoryLayout.size(ofValue: chunkCount))
        data.withUnsafeBytes { (ptr) -> Void in
            let buffer = ptr.bindMemory(to: type(of: chunkCount))
            chunkCount = buffer[0]
        }
    } else if chunkHeaders.count < chunkCount {
        let data:Data = fileHandle.readData(ofLength: MemoryLayout<ChunkHeader>.size * Int(chunkCount))
        data.withUnsafeBytes { (ptr) -> Void in
            let buffer = ptr.bindMemory(to: ChunkHeader.self)
            chunkHeaders = Array(buffer)
        }
    } else {
        break
    }
}
for chunkHeader in chunkHeaders {
    fileHandle.seek(toFileOffset: UInt64(chunkHeader.offset))
    var data:Data = fileHandle.readData(ofLength: Int(chunkHeader.length))
    var fileURL = URL(fileURLWithPath: path)
    fileURL.appendPathExtension("\(chunkHeader.offset)")
    do {
        try data.write(to: fileURL)
    } catch {
        print(error)
    }
    
    var index:Int = 0
    var mask:UInt8 = 0x80
    var byte:UInt8 = 0
    
    var window = UnsafeMutableRawBufferPointer.allocate(byteCount: 0x2000, alignment: MemoryLayout<UInt8>.alignment)
    var winIdx:Int = 1
    var unpacked = UnsafeMutableRawBufferPointer.allocate(byteCount: Int(chunkHeader.unknown), alignment: MemoryLayout<UInt8>.alignment)
    var unpackedIdx:Int = 0
    
    data.withUnsafeBytes { (ptr) -> Void in
        
        func readBits(bitFields:Int) -> Int {
            var value:Int = 0
            var size:Int = bitFields
            while size > 0 {
                if mask == 0x80 {
                    byte = ptr[index]
                    index += 1
                }
                
                if byte & mask > 0 {
                    value |= size
                }
                
                mask >>= 1
                size >>= 1
                if mask == 0 {
                    mask = 0x80
                }
            }
            return value
        }
        
        while true {
            if index > ptr.count {
                break
            }
            if mask == 0x80 {
                byte = ptr[index]
                index += 1
            }
            let bit = byte & mask
            mask >>= 1
            if mask == 0 {
                mask = 0x80
            }
            if bit > 0 {
                let value = readBits(bitFields: 0x80)
                unpacked[unpackedIdx] = UnsafeMutableRawBufferPointer.Element(value)
                window[winIdx & 0x1FFF] = UInt8(value)
                print("\(unpackedIdx): \(value)")
                unpackedIdx += 1
                winIdx += 1
            } else {
                let position = readBits(bitFields: 0x1000)
                if position == 0 {break}
                let length = readBits(bitFields: 0x08) + 2
                print("\(unpackedIdx): {\(position),\(length)}")
                for i in 0...length {
                    print("\(i)")
                    let value = window[(position + i) & 0x1FFF]
                    unpacked[unpackedIdx] = UnsafeMutableRawBufferPointer.Element(value)
                    window[winIdx & 0x1FFF] = UInt8(value)
                    unpackedIdx += 1
                    winIdx += 1
                }
            }
        }
    }
    let output = Data(buffer: unpacked.bindMemory(to: UInt8.self))
    fileURL.appendPathExtension("unpack")
    do {
        try output.write(to: fileURL)
    } catch {
        print(error)
    }
}
fileHandle.closeFile()

exit(EXIT_SUCCESS)
