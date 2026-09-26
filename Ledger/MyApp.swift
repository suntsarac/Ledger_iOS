import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@main
struct MyApp: App {
    init() {
        #if canImport(UIKit)
        let largeBase = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        let largeDescriptor = largeBase.withDesign(.serif) ?? largeBase
        let inlineBase = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline)
        let inlineDescriptor = inlineBase.withDesign(.serif) ?? inlineBase

        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = [
            .font: UIFont(descriptor: largeDescriptor, size: 0)
        ]
        navigationBar.titleTextAttributes = [
            .font: UIFont(descriptor: inlineDescriptor, size: 0)
        ]
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ExpensePersistence.container)
    }
}
