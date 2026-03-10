import Foundation
import YAML

/// A parsed YAML prompt file describing a project with style configuration and panels.
///
/// Supports the v1 prompt file format where panels inherit project-level style
/// settings and can override individual values (dimensions, seed, etc.).
public struct PromptFile: Sendable, Equatable {
    /// File format version.
    public let version: Int

    /// Project metadata.
    public let project: Project

    /// Ordered array of panels to generate.
    public let panels: [Panel]

    /// Project-level metadata including title and default style.
    public struct Project: Sendable, Equatable {
        /// The project title.
        public let title: String

        /// Default style configuration applied to all panels unless overridden.
        public let style: PromptFileStyle?
    }

    /// Style configuration as specified in a prompt file.
    ///
    /// Uses the prompt file key names (`prompt`, `negative`, `guidance`)
    /// which differ slightly from `StyleConfig` property names.
    public struct PromptFileStyle: Sendable, Equatable {
        public var prompt: String?
        public var negative: String?
        public var steps: Int?
        public var guidance: Float?
        public var width: Int?
        public var height: Int?

        public init(
            prompt: String? = nil,
            negative: String? = nil,
            steps: Int? = nil,
            guidance: Float? = nil,
            width: Int? = nil,
            height: Int? = nil
        ) {
            self.prompt = prompt
            self.negative = negative
            self.steps = steps
            self.guidance = guidance
            self.width = width
            self.height = height
        }
    }

    /// A single panel definition, potentially with per-panel overrides.
    public struct Panel: Sendable, Equatable {
        /// Text prompt for this panel.
        public let prompt: String

        /// Optional seed for reproducibility.
        public let seed: UInt64?

        /// Optional per-panel width override.
        public let width: Int?

        /// Optional per-panel height override.
        public let height: Int?
    }

    /// Parse a prompt file from a YAML string.
    ///
    /// - Parameter yamlString: The YAML content to parse.
    /// - Returns: A parsed `PromptFile`.
    /// - Throws: `VinetasError.invalidPromptFile` if the YAML is malformed or missing required fields.
    public static func parse(yaml yamlString: String) throws -> PromptFile {
        let yamlNode: YAML
        do {
            yamlNode = try YAML.parse(yaml: yamlString)
        } catch {
            throw VinetasError.invalidPromptFile(
                URL(fileURLWithPath: "<string>")
            )
        }

        // Version (required)
        guard let version = yamlNode["version"]?.integer else {
            throw VinetasError.invalidPromptFile(
                URL(fileURLWithPath: "<string>")
            )
        }

        // Project (required)
        guard let projectNode = yamlNode["project"] else {
            throw VinetasError.invalidPromptFile(
                URL(fileURLWithPath: "<string>")
            )
        }

        guard let title = projectNode["title"]?.string else {
            throw VinetasError.invalidPromptFile(
                URL(fileURLWithPath: "<string>")
            )
        }

        // Project style (optional)
        let style: PromptFileStyle?
        if let styleNode = projectNode["style"] {
            style = PromptFileStyle(
                prompt: styleNode["prompt"]?.string,
                negative: styleNode["negative"]?.string,
                steps: styleNode["steps"]?.integer,
                guidance: styleNode["guidance"]?.number.map { Float($0) },
                width: styleNode["width"]?.integer,
                height: styleNode["height"]?.integer
            )
        } else {
            style = nil
        }

        let project = Project(title: title, style: style)

        // Panels (required, must be non-empty array)
        guard let panelsArray = yamlNode["panels"]?.array, !panelsArray.isEmpty else {
            throw VinetasError.invalidPromptFile(
                URL(fileURLWithPath: "<string>")
            )
        }

        var panels: [Panel] = []
        for panelNode in panelsArray {
            guard let prompt = panelNode["prompt"]?.string else {
                throw VinetasError.invalidPromptFile(
                    URL(fileURLWithPath: "<string>")
                )
            }

            let seed: UInt64?
            if let seedInt = panelNode["seed"]?.integer {
                seed = UInt64(seedInt)
            } else {
                seed = nil
            }

            let panel = Panel(
                prompt: prompt,
                seed: seed,
                width: panelNode["width"]?.integer,
                height: panelNode["height"]?.integer
            )
            panels.append(panel)
        }

        return PromptFile(
            version: version,
            project: project,
            panels: panels
        )
    }

    /// Parse a prompt file from a URL.
    ///
    /// - Parameter url: The file URL to read and parse.
    /// - Returns: A parsed `PromptFile`.
    /// - Throws: `VinetasError.invalidPromptFile` if the file cannot be read or parsed.
    public static func parse(url: URL) throws -> PromptFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VinetasError.invalidPromptFile(url)
        }

        guard let yamlString = String(data: data, encoding: .utf8) else {
            throw VinetasError.invalidPromptFile(url)
        }

        return try parse(yaml: yamlString)
    }

    /// Resolve a panel's effective style by merging project-level defaults with per-panel overrides.
    ///
    /// The resulting `StyleConfig` uses project-level style values as defaults,
    /// with per-panel values (width, height, seed) taking precedence.
    ///
    /// - Parameter panelIndex: The index of the panel to resolve.
    /// - Returns: A `StyleConfig` with merged values.
    public func resolvedStyle(for panelIndex: Int) -> StyleConfig {
        let panel = panels[panelIndex]
        let projectStyle = project.style

        return StyleConfig(
            stylePrompt: projectStyle?.prompt ?? "",
            negativePrompt: projectStyle?.negative,
            steps: projectStyle?.steps ?? StyleConfig().steps,
            guidanceScale: projectStyle?.guidance ?? StyleConfig().guidanceScale,
            seed: panel.seed,
            width: panel.width ?? projectStyle?.width ?? StyleConfig().width,
            height: panel.height ?? projectStyle?.height ?? StyleConfig().height
        )
    }
}
