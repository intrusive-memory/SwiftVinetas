// VinetasPromptInspectorPreview.swift
// VinetasUI
//
// The inspector open beside a placeholder document, on macOS.

#if os(macOS)
  import SwiftUI
  import VinetasVocabulary

  #Preview("Inspector (macOS)", traits: .fixedLayout(width: 1280, height: 800)) {
    @Previewable @State var isPresented = true
    @Previewable @State var draft = VinetasPromptDraft(
      prompt:
        "Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer down an empty two-lane road, a low plume of dust behind it; a small-town water tower reading GRANVILLE and a cluster of grain silos on the far horizon; the road bending toward a tree-lined gravel driveway; long shadows across the fields, deep blue dusk gathering at the tree line. No people visible anywhere in the frame.",
      caption: "EST. SOMEWHERE IN THE MIDDLE OF THE COUNTRY - SUNSET",
      stylePrompt:
        "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light",
      negativePrompt:
        "text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry",
      modelID: "flux2-klein-4b",
      aspectRatio: .wide,
      steps: 8,
      guidance: 3.5,
      seed: 22
    )
    Text("Document")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .vinetasPromptInspector(
        isPresented: $isPresented, draft: $draft, showsCaption: true
      ) {
        HStack {
          Spacer()
          Button("Save") {}
        }
        .padding()
      }
  }
#endif
