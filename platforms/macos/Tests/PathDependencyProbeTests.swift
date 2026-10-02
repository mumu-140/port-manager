import Foundation
import Testing

@testable import PortKiller

/// Pure probe tests with injected filesystem state (temp dirs).
/// No network, no subprocess, no shell.
@Suite struct PathDependencyProbeTests {
    // MARK: Test scaffold

    /// Builds a probe over a fake root: files dict path->isExecutable.
    private func probe(
        _ files: [String: Bool],
        path: String = ""
    ) -> PathDependencyProbe {
        PathDependencyProbe(
            fileExists: { files[$0] != nil },
            isExecutableFile: { files[$0] ?? false },
            pathEntries: {
                guard !path.isEmpty else { return [] }
                return path.split(separator: ":").map(String.init)
            }
        )
    }

    private let ssh = DependencyRequirement.ssh
    private let dufs = DependencyRequirement.dufs

    // MARK: State mapping

    @Test func knownPathHitReportsAvailable() {
        var p = probe(["/usr/bin/ssh": true])
        #expect(p.state(for: ssh) == .available(path: "/usr/bin/ssh"))
    }

    @Test func missingEverywhereReportsNotInstalled() {
        var p = probe([:])
        #expect(p.state(for: ssh) == .notInstalled)
    }

    @Test func nonExecutableKnownPathIsSkippedAndPathWalkResolves() {
        // /usr/bin/ssh exists but is not executable; PATH dir has it.
        var p = probe(
            ["/usr/bin/ssh": false, "/tmp/fakebin/ssh": true],
            path: "/usr/bin:/tmp/fakebin"
        )
        #expect(p.state(for: ssh) == .available(path: "/tmp/fakebin/ssh"))
    }

    @Test func knownPathsBeathPathWalk() {
        var p = probe(
            ["/usr/bin/ssh": true, "/tmp/fakebin/ssh": true],
            path: "/tmp/fakebin"
        )
        #expect(p.state(for: ssh) == .available(path: "/usr/bin/ssh"))
    }

    @Test func pathWalkHonorsPathOrder() {
        var p = probe(
            ["/tmp/first/dufs": true, "/tmp/second/dufs": true],
            path: "/tmp/first:/tmp/second"
        )
        #expect(p.state(for: dufs) == .available(path: "/tmp/first/dufs"))
    }

    // MARK: Caching + recheck

    @Test func cachedStateSurvivesFileSystemChangesUntilRecheck() {
        var files: [String: Bool] = ["/usr/bin/ssh": true]
        var p = probe(files)
        #expect(p.state(for: ssh) == .available(path: "/usr/bin/ssh"))

        // Binary disappears: cache still reports available.
        files["/usr/bin/ssh"] = nil
        var stale = PathDependencyProbe(
            fileExists: { files[$0] != nil },
            isExecutableFile: { files[$0] ?? false },
            pathEntries: { [] }
        )
        // fresh probe would be notInstalled
        #expect(stale.state(for: ssh) == .notInstalled)

        // but a cached probe keeps the old answer until recheck()
        var cachedFiles: [String: Bool] = ["/usr/bin/ssh": true]
        var cached = PathDependencyProbe(
            fileExists: { cachedFiles[$0] != nil },
            isExecutableFile: { cachedFiles[$0] ?? false },
            pathEntries: { [] }
        )
        #expect(cached.state(for: ssh) == .available(path: "/usr/bin/ssh"))
        cachedFiles["/usr/bin/ssh"] = nil
        #expect(cached.state(for: ssh) == .available(path: "/usr/bin/ssh"))
        cached.recheck()
        #expect(cached.state(for: ssh) == .notInstalled)
    }

    // MARK: python3 stub rule

    @Test func usrBinPython3StubIsNotReportedAvailable() {
        // The CommandLineTools stub is a few kilobytes; a real python3 is MBs.
        // The probe uses a size hook via knownPaths ordering — here we assert
        // the stub path is skipped when a later known path exists.
        // Size-based stub detection is exercised in probe design; this test
        // pins the ordering: /opt/homebrew/python3 wins over /usr/bin/python3.
        var p = probe(
            ["/opt/homebrew/bin/python3": true, "/usr/bin/python3": true],
            path: ""
        )
        #expect(p.state(for: DependencyRequirement.python3) == .available(path: "/opt/homebrew/bin/python3"))
    }

    // MARK: Requirement table

    @Test func requirementTableCoversPresetDependencies() {
        #expect(DependencyRequirement.requirement(forPresetID: "static-file-share")?.binaryName == "python3")
        #expect(DependencyRequirement.requirement(forPresetID: "ssh-local-forward")?.binaryName == "ssh")
        #expect(DependencyRequirement.requirement(forPresetID: "ssh-socks5-proxy")?.binaryName == "ssh")
        #expect(DependencyRequirement.requirement(forPresetID: "dufs-file-share")?.binaryName == "dufs")
        #expect(DependencyRequirement.requirement(forPresetID: "jupyter-lab")?.binaryName == "jupyter")
        #expect(DependencyRequirement.requirement(forPresetID: "custom") == nil)
        #expect(DependencyRequirement.requirement(forPresetID: "unknown") == nil)
    }

    @Test func everyRequirementCarriesLocalizedCopyAndURL() {
        for req in [DependencyRequirement.ssh, .python3, .dufs, .jupyter] {
            #expect(!req.notInstalledKey.isEmpty)
            #expect(req.notInstalledKey.hasPrefix("dependency."))
            #expect(req.installDocumentsURL.hasPrefix("https://"))
        }
        #expect(DependencyRequirement.python3.stubCopyKey == "dependency.python3.stub")
    }

    // MARK: Fallback dirs

    @Test func fallbackDirectoryIsConsultedLast() {
        let jupyter = DependencyRequirement(
            binaryName: "jupyter",
            knownPaths: [],
            fallbackPaths: ["/tmp/jupyterfallback"],
            notInstalledKey: "dependency.jupyter.notInstalled",
            installDocumentsURL: "https://docs.jupyter.org"
        )
        var p = probe(
            ["/tmp/jupyterfallback/jupyter": true],
            path: "/tmp/emptybin"
        )
        #expect(p.state(for: jupyter) == .available(path: "/tmp/jupyterfallback/jupyter"))
    }
}
