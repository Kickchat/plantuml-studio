import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
  fputs(message + "\n", stderr)
  exit(1)
}

// Validate the exact public key embedded in the app against the protected seed.
// No key material is printed or passed on the command line.
let text = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
guard let seed = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
  seed.count == 32,
  let publicKey = Data(
    base64Encoded: ProcessInfo.processInfo.environment["SPARKLE_PUBLIC_KEY"] ?? "")
else { fail("Use a 32-byte Sparkle key exported by generate_keys 2.10 or later") }
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
guard key.publicKey.rawRepresentation == publicKey else {
  fail("Sparkle signing seed and configured public key do not match")
}
print("Sparkle key pair matches the application public key")
