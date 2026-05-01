 # PixArt Storyboard Failure Triage and Hardening

  ## Summary

  - Treat the active user-facing bug as a wide/panel/strip PixArt storyboard failure, not as a general “PixArt is broken everywhere” claim.
  - Use square 1024x1024 as the control and compare it against real storyboard shapes (wide, panel, ultrawide, strip) through the same
    VinetasClient path the app uses.
  - Until that matrix proves otherwise, treat PixArt’s advertised multi-aspect storyboard support as incorrect and harden the engine to fail
    fast instead of returning randomized-color garbage.

  ## Key Changes

  - Extend the existing PixArt diagnostic coverage in Tests/SwiftVinetasGPUTests/PixArtGarbageReproTests.swift to run a fixed prompt/seed
    across:
      - 1024x1024 square
      - 1344x768 wide
      - 1216x832 panel
      - 1536x640 ultrawide
      - 2048x512 strip
  - Save PNG + JSON sidecars for each run outside repo-tracked files, using the existing debug-output pattern, and record width/height/aspect/
    seed/model/metrics per sample.
  - Keep the investigation decision tree explicit:
      - If 1024x1024 square is visually acceptable but wide/panel/strip are garbage, lock the root cause as unsupported non-square PixArt
        operation in the current stack.
      - If square 1024x1024 is also garbage, escalate to a dependency-level audit of the pinned pixart-swift-mlx 0.4.3 / SwiftTuberia 0.3.6
        behavior before changing local caller logic further.
  - Harden the local engine in Sources/SwiftVinetas/Engine/PixArtEngine.swift:
      - Reduce PixArtModelDescriptor.sigmaXL.supportedAspectRatios from AspectRatio.allCases to the proven-safe set.
      - Default the safe set to square only until the diagnostic matrix proves more.
      - Add request validation in PixArtEngine.generate so unsupported PixArt shapes fail with a clear VinetasError.generationFailed(...)
        message instead of silently generating unusable output.
  - Tighten the test guardrail in Tests/SwiftVinetasGPUTests/IntegrationTestHelpers.swift:
      - Keep the current black/white/low-diversity checks.
      - Add stronger PixArt-oriented failure heuristics so clearly broken images no longer pass as “non-garbage”.
      - Make failed-image preservation part of the PixArt repro flow so human inspection is always available for borderline cases.
  - Update the local expectations around PixArt:
      - Unit tests should stop asserting that PixArt supports all aspect ratios.
      - Example/integration coverage should stop treating square-only checks as proof that storyboard mode works.

  ## Test Plan

  - Run the new PixArt aspect-ratio repro matrix through VinetasClient.shared.generate.
  - Confirm that square 1024x1024 acts as the control and that wide/panel/strip behavior is explicitly classified, not inferred.
  - Add one integration test that expects PixArt to reject unsupported storyboard shapes once fail-fast validation is in place.
  - Re-run the existing PixArtIntegrationTests after hardening to ensure square PixArt still loads, generates, and writes output successfully.

  ## Public API / Behavior Changes

  - PixArtModelDescriptor.sigmaXL.supportedAspectRatios will no longer claim universal aspect-ratio support.
  - PixArtEngine.generate will reject unsupported PixArt dimensions early with a deterministic error message.
  - No new public types are required; reuse VinetasError.generationFailed for the fail-fast path.

  ## Assumptions And Defaults

  - Primary failing path is wide/strip storyboard generation, per user confirmation.
  - The current square PixArt integration tests are not sufficient evidence of storyboard correctness because they use weak image-quality
    gates.
  - Default safe policy is restrict PixArt to square 1024x1024 until proven otherwise, rather than continuing to advertise unsupported
    storyboard layouts.
  - Dependency-level PixArt backbone changes are out of scope for the first pass unless the square 1024x1024 control also fails.
  
  