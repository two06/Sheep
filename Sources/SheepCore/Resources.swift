import Foundation
public enum SheepResources {
    public static var definitionURL: URL {
        if let url = Bundle.main.url(forResource: "animations", withExtension: "xml") { return url }
        return Bundle.module.url(forResource: "animations", withExtension: "xml")!
    }
}
