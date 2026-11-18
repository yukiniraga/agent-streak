// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Base64
/// @notice Compact RFC 4648 base64 encoder used to build `data:` URIs for
///         badge metadata entirely on-chain. Implemented from the spec:
///         the input is consumed three bytes at a time and each group is
///         mapped to four characters of the standard alphabet, with "="
///         padding when the final group is short.
library Base64 {
    bytes internal constant ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @notice Encode raw bytes as a base64 string.
    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        bytes memory out = new bytes(encodedLen);
        uint256 i;
        uint256 j;
        while (i + 3 <= data.length) {
            uint256 chunk = (uint256(uint8(data[i])) << 16) | (uint256(uint8(data[i + 1])) << 8)
                | uint256(uint8(data[i + 2]));
            out[j++] = ALPHABET[(chunk >> 18) & 63];
            out[j++] = ALPHABET[(chunk >> 12) & 63];
            out[j++] = ALPHABET[(chunk >> 6) & 63];
            out[j++] = ALPHABET[chunk & 63];
            i += 3;
        }
        uint256 remaining = data.length - i;
        if (remaining == 1) {
            uint256 chunk = uint256(uint8(data[i])) << 16;
            out[j++] = ALPHABET[(chunk >> 18) & 63];
            out[j++] = ALPHABET[(chunk >> 12) & 63];
            out[j++] = "=";
            out[j++] = "=";
        } else if (remaining == 2) {
            uint256 chunk = (uint256(uint8(data[i])) << 16) | (uint256(uint8(data[i + 1])) << 8);
            out[j++] = ALPHABET[(chunk >> 18) & 63];
            out[j++] = ALPHABET[(chunk >> 12) & 63];
            out[j++] = ALPHABET[(chunk >> 6) & 63];
            out[j++] = "=";
        }
        return string(out);
    }
}
