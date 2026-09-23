import AtelierParser
import Testing

@testable import AtelierScanners

struct BundledScannersTests {
    @Test
    func `every bundled scanner names at least one external and names none twice`() {
        for (name, scanner) in BundledScanners.byGrammarName {
            let externals = scanner.externalNames
            #expect(!externals.isEmpty, "\(name) declares no externals")
            #expect(Set(externals).count == externals.count, "\(name) declares an external twice")
        }
    }
}
