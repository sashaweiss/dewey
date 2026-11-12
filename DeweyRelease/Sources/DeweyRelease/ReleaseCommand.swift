import ArgumentParser
import Foundation

/// A problem that stops the release.
struct ReleaseError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

@main
struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dewey-release",
        abstract: "Builds, signs, notarizes, and publishes a release of dewey.",
        discussion: """
        The version is the project's MARKETING_VERSION. The release is tagged \
        v<version>, and published to GitHub. Builds and artifacts go in \
        release/.
        """,
    )

    /// Credentials saved to the keychain under a profile name with `xcrun
    /// notarytool store-credentials <profile> --apple-id <email> --team-id
    /// <team>`, which asks for an app-specific password. Check one with `xcrun
    /// notarytool history --keychain-profile <profile>`.
    @Option(help: ArgumentHelp(
        "the notarytool keychain profile to notarize with",
        valueName: "profile",
    ))
    var notaryProfile: String

    @Option(help: ArgumentHelp(
        "the git remote to release to, if the repository has more than one",
        valueName: "remote",
    ))
    var remote: String?

    @Flag(help: "do everything but tag and publish")
    var dryRun = false

    @Flag(help: "show the output of each step's commands")
    var verbose = false

    func run() async throws {
        let repository = URL(
            filePath: try await outputOf(command: [
                "git",
                "rev-parse",
                "--show-toplevel",
            ]),
        )
        let project = repository.appending(path: "dewey.xcodeproj")

        log("Checking tools")
        try checkTools()

        let settings = try await readBuildSettings(project: project)
        let version = settings.version
        let tag = "v\(version)"
        let releaseDirectory = repository.appending(path: "release")
        print("Releasing dewey \(version)")

        log("Checking the repository")
        let remote = try await findRemote(repository: repository)
        try await checkRepository(
            repository: repository,
            remote: remote,
            tag: tag,
        )

        let artifact = try await makeArtifact(
            project: project,
            teamID: settings.teamID,
            version: version,
            releaseDirectory: releaseDirectory,
        )

        guard !dryRun else {
            print("Dry run: made \(artifact.zip.path); not publishing.")
            return
        }
        try await publish(
            artifact: artifact,
            version: version,
            tag: tag,
            repository: repository,
            remote: remote,
        )
        print("Published the release, \(tag), on GitHub.")
    }

    /// A signed, notarized, stapled build of dewey, as published.
    struct Artifact {
        var zip: URL
        var checksum: URL
    }

    /// The release build settings the release depends on.
    struct BuildSettings {
        var version: String
        var teamID: String
    }

    /// Archives dewey, exports it for Developer ID, and notarizes and staples
    /// it, in `releaseDirectory`.
    func makeArtifact(
        project: URL,
        teamID: String,
        version: String,
        releaseDirectory: URL,
    ) async throws -> Artifact {
        try? FileManager.default.removeItem(at: releaseDirectory)
        try FileManager.default.createDirectory(
            at: releaseDirectory,
            withIntermediateDirectories: true,
        )
        let buildDirectory = releaseDirectory.appending(path: "build")
        let archive = buildDirectory.appending(path: "dewey.xcarchive")

        log("Archiving")
        try await runCommand([
            "xcodebuild",
            "archive",
            "-project",
            project.path,
            "-scheme",
            "dewey",
            "-configuration",
            "Release",
            "-destination",
            "generic/platform=macOS",
            "-archivePath",
            archive.path,
            "-derivedDataPath",
            buildDirectory.appending(path: "DerivedData").path,
            "-allowProvisioningUpdates",
        ], verbose: verbose)

        // Automatic signing picks the Developer ID identity from the export
        // method, and -allowProvisioningUpdates fetches the profile that
        // carries the enhanced-security entitlements.
        log("Exporting for Developer ID")
        let exportOptions = buildDirectory.appending(
            path: "ExportOptions.plist",
        )
        let options: [String: String] = [
            "method": "developer-id",
            "teamID": teamID,
            "signingStyle": "automatic",
            "destination": "export",
        ]
        try PropertyListSerialization
            .data(fromPropertyList: options, format: .xml, options: 0)
            .write(to: exportOptions)
        let exportDirectory = buildDirectory.appending(path: "export")
        try await runCommand([
            "xcodebuild",
            "-exportArchive",
            "-archivePath",
            archive.path,
            "-exportOptionsPlist",
            exportOptions.path,
            "-exportPath",
            exportDirectory.path,
            "-allowProvisioningUpdates",
        ], verbose: verbose)
        let app = releaseDirectory.appending(path: "dewey.app")
        try FileManager.default.moveItem(
            at: exportDirectory.appending(path: "dewey.app"),
            to: app,
        )

        log("Notarizing")
        let zip = releaseDirectory.appending(
            path: "dewey-\(version)-macos.zip",
        )
        try await zipApp(app: app, zip: zip)
        try await notarize(zip: zip)

        // Zip again once stapled, so what ships carries the ticket.
        log("Stapling")
        try await runCommand(
            ["xcrun", "stapler", "staple", app.path],
            verbose: verbose,
        )
        try await zipApp(app: app, zip: zip)

        return Artifact(zip: zip, checksum: try await writeChecksum(zip: zip))
    }

    /// Tags the release `tag`, pushes the tag to `remote`, and creates a
    /// GitHub release of `artifact`.
    func publish(
        artifact: Artifact,
        version: String,
        tag: String,
        repository: URL,
        remote: String,
    ) async throws {
        log("Tagging \(tag)")
        try await runCommand(
            ["git", "tag", "-a", tag, "-m", "dewey \(version)"],
            directory: repository,
            verbose: verbose,
        )
        try await runCommand(
            ["git", "push", remote, tag],
            directory: repository,
            verbose: verbose,
        )

        log("Creating a GitHub release")
        try await runCommand(
            [
                "gh",
                "release",
                "create",
                tag,
                artifact.zip.path,
                artifact.checksum.path,
                "--title",
                "\(tag)",
                "--generate-notes",
            ],
            directory: repository,
            verbose: verbose,
        )
    }

    /// Returns the `MARKETING_VERSION` and `DEVELOPMENT_TEAM` of `project`'s
    /// Release configuration.
    func readBuildSettings(project: URL) async throws -> BuildSettings {
        let json = try await outputOf(command: [
            "xcodebuild",
            "-showBuildSettings",
            "-json",
            "-project",
            project.path,
            "-target",
            "dewey",
            "-configuration",
            "Release",
        ])
        struct Target: Decodable {
            var buildSettings: [String: String]
        }
        let targets = try JSONDecoder().decode(
            [Target].self,
            from: Data(json.utf8),
        )
        let settings = targets.first?.buildSettings ?? [:]
        guard let version = settings["MARKETING_VERSION"] else {
            throw ReleaseError("The project has no MARKETING_VERSION.")
        }
        guard let teamID = settings["DEVELOPMENT_TEAM"] else {
            throw ReleaseError("The project has no DEVELOPMENT_TEAM.")
        }
        return BuildSettings(version: version, teamID: teamID)
    }

    /// Checks that the tools the release runs are on `PATH`.
    func checkTools() throws {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = path.split(separator: ":").map(String.init)
        let tools = [
            "git",
            "xcodebuild",
            "ditto",
            "xcrun",
            "shasum",
            "gh",
        ]
        for tool in tools {
            let isOnPath = directories.contains { directory in
                FileManager.default.isExecutableFile(
                    atPath: "\(directory)/\(tool)",
                )
            }
            guard isOnPath else {
                throw ReleaseError("Couldn't find \(tool) on PATH.")
            }
        }
    }

    /// Returns `remote`, if it was given and exists, or else the repository's
    /// only remote.
    func findRemote(repository: URL) async throws -> String {
        let remotes = try await outputOf(
            command: ["git", "remote"],
            directory: repository,
        )
        .split(separator: "\n")
        .map(String.init)

        if let remote {
            guard remotes.contains(remote) else {
                throw ReleaseError("There's no remote named \(remote).")
            }
            return remote
        }
        guard remotes.count == 1 else {
            throw ReleaseError(
                "The repository has \(remotes.count) remotes; pass --remote.",
            )
        }
        return remotes[0]
    }

    /// Checks that the repository is on a clean `main` matching `remote`'s,
    /// and that `tag` hasn't been used, by a tag or a GitHub release.
    func checkRepository(
        repository: URL,
        remote: String,
        tag: String,
    ) async throws {
        let git = { (arguments: [String]) in
            try await outputOf(command: ["git"] + arguments, directory: repository)
        }

        guard try await git(["rev-parse", "--abbrev-ref", "HEAD"]) == "main" else {
            throw ReleaseError("Releases must come from main.")
        }

        guard try await git(["status", "--porcelain"]).isEmpty else {
            throw ReleaseError("The working tree has uncommitted changes.")
        }

        _ = try await git(["fetch", remote, "main", "--tags"])
        let head = try await git(["rev-parse", "HEAD"])
        let remoteMain = try await git(["rev-parse", "\(remote)/main"])
        guard head == remoteMain else {
            throw ReleaseError("main doesn't match \(remote)/main.")
        }

        guard try await git(["tag", "--list", tag]).isEmpty else {
            throw ReleaseError(
                "The tag \(tag) already exists; bump MARKETING_VERSION.",
            )
        }

        let releaseTags = try await outputOf(
            command: [
                "gh",
                "release",
                "list",
                "--limit",
                "1000",
                "--json",
                "tagName",
                "--jq",
                ".[].tagName",
            ],
            directory: repository,
        )
        guard !releaseTags.split(separator: "\n").contains(Substring(tag)) else {
            throw ReleaseError(
                "A GitHub release for \(tag) already exists; bump "
                    + "MARKETING_VERSION.",
            )
        }
    }

    /// Zips `app` to `zip`, replacing any zip already there.
    func zipApp(app: URL, zip: URL) async throws {
        try? FileManager.default.removeItem(at: zip)
        try await runCommand(
            ["ditto", "-c", "-k", "--keepParent", app.path, zip.path],
            verbose: verbose,
        )
    }

    /// Submits `zip` for notarization, and waits for it to be accepted.
    func notarize(zip: URL) async throws {
        let submission = try await withProgressDots {
            try await outputOf(command: [
                "xcrun",
                "notarytool",
                "submit",
                zip.path,
                "--keychain-profile",
                notaryProfile,
                "--wait",
                "--output-format",
                "json",
            ])
        }
        struct Submission: Decodable {
            var id: String
            var status: String
        }
        let result = try JSONDecoder().decode(
            Submission.self,
            from: Data(submission.utf8),
        )
        guard result.status == "Accepted" else {
            try? await runCommand([
                "xcrun",
                "notarytool",
                "log",
                result.id,
                "--keychain-profile",
                notaryProfile,
            ], verbose: verbose)
            throw ReleaseError("Notarization ended as \(result.status).")
        }
    }

    /// Writes a SHA-256 checksum file for `zip`, and returns it.
    func writeChecksum(zip: URL) async throws -> URL {
        let checksum = try await outputOf(
            command: ["shasum", "-a", "256", zip.lastPathComponent],
            directory: zip.deletingLastPathComponent(),
        )
        let checksumFile = zip.appendingPathExtension("sha256")
        try (checksum + "\n").write(
            to: checksumFile,
            atomically: true,
            encoding: .utf8,
        )
        return checksumFile
    }
}
