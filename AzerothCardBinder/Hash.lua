local _, ACB = ...

-- SHA-256 (FIPS 180-4) in plain Lua, written with the `bit` library the game provides. It is used to chain the
-- ledger of changes to the binder (see docs/LEDGER-SPEC.md). Only band, bor, bxor, bnot, lshift and rshift are
-- used, always with two arguments, because those are the ones WoW's `bit` has; every result is brought back to
-- an unsigned 32-bit number.

local band, bor, bxor, bnot, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.lshift, bit.rshift
local floor, char, format, concat = math.floor, string.char, string.format, table.concat

local MODULUS = 4294967296

local function unsigned(value)
    return value % MODULUS
end

local function rotateRight(value, count)
    return unsigned(bor(rshift(value, count), lshift(value, 32 - count)))
end

-- The first 32 bits of the fractional parts of the cube roots of the first 64 primes.
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- The first 32 bits of the fractional parts of the square roots of the first 8 primes.
local START = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }

-- Pad the text: a 1 bit, zeros, then the length in bits as 64 bits, so the total is a multiple of 64 bytes.
local function padded(text)
    local length = #text
    local zeros = (55 - length) % 64
    local bits = length * 8
    local high, low = floor(bits / MODULUS), bits % MODULUS
    local tail = {}
    for shift = 24, 0, -8 do tail[#tail + 1] = char(floor(high / 2 ^ shift) % 256) end
    for shift = 24, 0, -8 do tail[#tail + 1] = char(floor(low / 2 ^ shift) % 256) end
    return text .. "\128" .. string.rep("\0", zeros) .. concat(tail)
end

-- The 64 rounds for one 64-byte block, updating the running state h in place.
local function processBlock(data, offset, h, w)
    for index = 0, 15 do
        local a, b, c, d = data:byte(offset + index * 4, offset + index * 4 + 3)
        w[index] = ((a * 256 + b) * 256 + c) * 256 + d
    end
    for index = 16, 63 do
        local x, y = w[index - 15], w[index - 2]
        local s0 = bxor(bxor(rotateRight(x, 7), rotateRight(x, 18)), rshift(x, 3))
        local s1 = bxor(bxor(rotateRight(y, 17), rotateRight(y, 19)), rshift(y, 10))
        w[index] = unsigned(w[index - 16] + unsigned(s0) + w[index - 7] + unsigned(s1))
    end
    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for index = 0, 63 do
        local sigma1 = unsigned(bxor(bxor(rotateRight(e, 6), rotateRight(e, 11)), rotateRight(e, 25)))
        local choice = unsigned(bxor(band(e, f), band(bnot(e), g)))
        local temp1 = unsigned(hh + sigma1 + choice + K[index + 1] + w[index])
        local sigma0 = unsigned(bxor(bxor(rotateRight(a, 2), rotateRight(a, 13)), rotateRight(a, 22)))
        local majority = unsigned(bxor(bxor(band(a, b), band(a, c)), band(b, c)))
        local temp2 = unsigned(sigma0 + majority)
        hh, g, f, e, d, c, b, a = g, f, unsigned(e), unsigned(d + temp1), c, unsigned(b), unsigned(a), unsigned(temp1 + temp2)
    end
    h[1], h[2], h[3], h[4] = unsigned(h[1] + a), unsigned(h[2] + b), unsigned(h[3] + c), unsigned(h[4] + d)
    h[5], h[6], h[7], h[8] = unsigned(h[5] + e), unsigned(h[6] + f), unsigned(h[7] + g), unsigned(h[8] + hh)
end

-- The SHA-256 of a string (its bytes as they are), as 64 lowercase hex characters.
function ACB.sha256(text)
    local data = padded(text)
    local h, w = { unpack(START) }, {}
    for offset = 1, #data, 64 do processBlock(data, offset, h, w) end
    local parts = {}
    for index = 1, 8 do parts[index] = format("%08x", h[index]) end
    return concat(parts)
end
