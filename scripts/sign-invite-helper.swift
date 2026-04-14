#!/usr/bin/env swift
// scripts/sign-invite-helper.swift
// Usage:
//   swift scripts/sign-invite-helper.swift --pubkey [instanceName]
//   swift scripts/sign-invite-helper.swift --sign [instanceName]    <- reads stdin
//
// --pubkey: prints base64url-encoded Ed25519 public key to stdout
// --sign:   reads canonical JSON from stdin, prints base64 signature to stdout
// Generates the keypair and stores it in Keychain if not present.

import Foundation
import CryptoKit
import Security

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: swift sign-invite-helper.swift --pubkey|--sign [instanceName]\n", stderr)
    exit(1)
}
let mode = args[1]
let instanceName = args.count >= 3 ? args[2] : "default"
let keychainService = "com.odyssey.app"
let keychainKey = "odyssey.identity.\(instanceName)"

func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: keychainService as CFString,
        kSecAttrAccount: keychainKey as CFString,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecSuccess, let rawBytes = result as? Data {
        return try Curve25519.Signing.PrivateKey(rawRepresentation: rawBytes)
    }
    if status == errSecItemNotFound {
        let privateKey = Curve25519.Signing.PrivateKey()
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService as CFString,
            kSecAttrAccount: keychainKey as CFString,
            kSecValueData: Data(privateKey.rawRepresentation),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(addStatus),
                          userInfo: [NSLocalizedDescriptionKey: "SecItemAdd failed: \(addStatus)"])
        }
        fputs("Generated new Ed25519 keypair for '\(instanceName)'\n", stderr)
        return privateKey
    }
    throw NSError(domain: "Keychain", code: Int(status),
                  userInfo: [NSLocalizedDescriptionKey: "SecItemCopyMatching failed: \(status)"])
}

do {
    let privateKey = try loadOrCreatePrivateKey()
    let pubKeyData = Data(privateKey.publicKey.rawRepresentation)
    let pubKeyBase64url = pubKeyData.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")

    switch mode {
    case "--pubkey":
        print(pubKeyBase64url)
    case "--sign":
        let inputData = FileHandle.standardInput.readDataToEndOfFile()
        let signature = try Data(privateKey.signature(for: inputData))
        print(signature.base64EncodedString())
    default:
        fputs("Unknown mode: \(mode). Use --pubkey or --sign\n", stderr)
        exit(1)
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
