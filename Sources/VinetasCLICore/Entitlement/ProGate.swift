import ArgumentParser
import Foundation
import SwiftAcervo
import SwiftVinetas

/// Decides whether this machine may generate with the Pro-gated FLUX.2 models.
///
/// The Vinetas app gates FLUX.2 behind a one-time non-consumable purchase and
/// enforces it through StoreKit in the UI. The CLI ships inside the same app
/// bundle and reaches the same models, so without this it would be a documented
/// way around the purchase — which is both unfair to people who paid and a
/// plausible App Review problem, since the CLI is advertised in the app's Help
/// menu.
///
/// The app writes its verified `Transaction.jwsRepresentation` to
/// ``markerURL``; the CLI verifies that JWS against the pinned Apple root (see
/// ``SignedTransaction``) and checks it is the right product, for the right
/// bundle, and not revoked.
public enum ProGate {

  /// The non-consumable that unlocks FLUX.2. Must match `ProEntitlement`
  /// in the app and the IAP product in App Store Connect.
  public static let proProductID = "io.intrusive_memory.vinetas.pro"

  /// The bundle the purchase belongs to. macOS and iOS share one bundle ID
  /// under Universal Purchase, so a single value covers both.
  public static let expectedBundleID = "io.intrusive-memory.Vinetas"

  /// Where the app deposits its verified transaction.
  ///
  /// Sits beside `SharedModels` in the App Group container — the one place both
  /// the sandboxed app and the sandboxed CLI can always reach.
  public static var markerURL: URL {
    Acervo.sharedModelsDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("entitlement.jws")
  }

  /// The outcome of checking the marker.
  public enum Status: Sendable, Equatable {
    case unlocked
    /// No entitlement, with a human-readable reason.
    case locked(String)

    public var isUnlocked: Bool { self == .unlocked }
  }

  /// Whether `model` needs the Pro unlock. FLUX.2 does; PixArt is free.
  public static func requiresPro(_ model: VinetasModel) -> Bool {
    model.descriptor.engineID == "flux2"
  }

  /// Read and verify the marker.
  ///
  /// Never throws: any failure — absent, unreadable, malformed, forged, wrong
  /// product, revoked — is a `locked` with the reason, because every one of them
  /// means the same thing operationally and the caller should say so plainly
  /// rather than crash.
  public static func status(now: Date = Date()) async -> Status {
    let url = markerURL
    guard let jws = try? String(contentsOf: url, encoding: .utf8) else {
      return .locked("no Vinetas Pro purchase found on this machine")
    }

    let trimmed = jws.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .locked("no Vinetas Pro purchase found on this machine")
    }

    let transaction: SignedTransaction
    do {
      transaction = try await SignedTransaction.verify(jws: trimmed, now: now)
    } catch let error as SignedTransaction.VerificationError {
      if let local = localTestingTransaction(jws: trimmed) {
        transaction = local
      } else {
        return .locked("the stored Vinetas Pro entitlement is not valid — \(error)")
      }
    } catch {
      return .locked("the stored Vinetas Pro entitlement could not be verified")
    }

    guard transaction.bundleID == expectedBundleID else {
      return .locked("the stored entitlement belongs to a different app")
    }
    guard transaction.productID == proProductID else {
      return .locked("the stored entitlement is not the Vinetas Pro unlock")
    }
    if let revoked = transaction.revocationDate, revoked <= now {
      return .locked("the Vinetas Pro purchase was refunded or revoked")
    }
    return .unlocked
  }

  /// Accept an Xcode local-StoreKit transaction — **DEBUG builds only**.
  ///
  /// Transactions minted by Xcode's StoreKit testing are signed by a
  /// per-machine test root, so they cannot pass validation against Apple's
  /// root. Without this carve-out the unlocked path would be untestable
  /// anywhere except a real purchase, and the predictable "fix" for that is
  /// someone quietly loosening the production check.
  ///
  /// In a release build this function does not exist: the `#if DEBUG` compiles
  /// the body away and it always returns `nil`. The CLI that ships inside
  /// Vinetas.app is a release build, so shipping users get chain validation and
  /// nothing else.
  private static func localTestingTransaction(jws: String) -> SignedTransaction? {
    #if DEBUG
      guard let candidate = SignedTransaction.parseUnverifiedPayload(jws: jws),
        candidate.environment == SignedTransaction.xcodeTestEnvironment
      else { return nil }
      FileHandle.standardError.write(
        Data(
          """
          [vinetas] WARNING: honouring an UNVERIFIED Xcode StoreKit test \
          entitlement. This only happens in a debug build; release builds \
          require a transaction signed by Apple.

          """.utf8))
      return candidate
    #else
      return nil
    #endif
  }

  /// Throw unless `model` may be used on this machine.
  ///
  /// Call at the top of any command that loads or downloads weights.
  public static func requireAccess(to model: VinetasModel) async throws {
    guard requiresPro(model) else { return }
    if case .locked(let reason) = await status() {
      throw ValidationError(
        """
        '\(model.rawValue)' requires the Vinetas Pro unlock — \(reason).

        FLUX.2 models are a one-time in-app purchase. Open Vinetas and buy the \
        unlock there, then re-run this command; the CLI picks it up \
        automatically.

        PixArt-Sigma is free and needs no unlock:
            --model pixart-sigma
        """
      )
    }
  }
}
