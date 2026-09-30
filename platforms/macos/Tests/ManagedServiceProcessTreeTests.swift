import Testing
@testable import PortKiller

/**
 * Pure process-tree parsing tests for managed service termination.
 */
struct ManagedServiceProcessTreeTests {

    private let sample = """
      100   1
      200 100
      300 200
      400 100
      500   1
      600 999
    """

    @Test func parentMapParsesPIDAndParent() {
        let map = ManagedServiceProcessTree.parentMap(fromPSOutput: sample)
        #expect(map[100] == 1)
        #expect(map[200] == 100)
        #expect(map[600] == 999)
        #expect(map.count == 6)
    }

    @Test func descendantsAreOrderedNearestFirst() {
        let descendants = ManagedServiceProcessTree.descendants(of: 100, inPSOutput: sample)
        #expect(Set(descendants) == Set([200, 300, 400]))
        #expect(descendants.first == 200 || descendants.first == 400)
        #expect(descendants.last == 300)
    }

    @Test func leafHasNoDescendants() {
        #expect(ManagedServiceProcessTree.descendants(of: 300, inPSOutput: sample).isEmpty)
    }

    @Test func unknownRootHasNoDescendants() {
        #expect(ManagedServiceProcessTree.descendants(of: 424242, inPSOutput: sample).isEmpty)
    }

    @Test func malformedLinesAreIgnored() {
        let messy = "garbage\n  \n42\n\n7 1"
        let map = ManagedServiceProcessTree.parentMap(fromPSOutput: messy)
        #expect(map == [7: 1])
    }
}
