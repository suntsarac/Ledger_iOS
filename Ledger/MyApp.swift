import SwiftData
import SwiftUI

#if canImport(UIKit)
import UIKit

func configureNavigationBarAppearance() {
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()

    let largeTitleAttributes: [NSAttributedString.Key: Any] = [
        .font: serifNavigationFont(textStyle: .largeTitle, weight: .bold)
    ]
    let inlineTitleAttributes: [NSAttributedString.Key: Any] = [
        .font: serifNavigationFont(textStyle: .headline, weight: .semibold)
    ]

    appearance.largeTitleTextAttributes = largeTitleAttributes
    appearance.titleTextAttributes = inlineTitleAttributes

    let navigationBar = UINavigationBar.appearance()
    navigationBar.largeTitleTextAttributes = largeTitleAttributes
    navigationBar.titleTextAttributes = inlineTitleAttributes
    navigationBar.standardAppearance = appearance
    navigationBar.compactAppearance = appearance
    navigationBar.scrollEdgeAppearance = appearance
    navigationBar.compactScrollEdgeAppearance = appearance
}

func serifNavigationFont(
    textStyle: UIFont.TextStyle,
    weight: UIFont.Weight
) -> UIFont {
    let preferredSize = UIFont.preferredFont(forTextStyle: textStyle).pointSize
    let descriptor = UIFont.systemFont(
        ofSize: preferredSize,
        weight: weight
    ).fontDescriptor.withDesign(.serif)

    return UIFont(
        descriptor: descriptor ?? UIFont.systemFont(
            ofSize: preferredSize,
            weight: weight
        ).fontDescriptor,
        size: preferredSize
    )
}
#endif

@main
struct MyApp: App {
    init() {
        #if canImport(UIKit)
        configureNavigationBarAppearance()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(ExpensePersistence.container)
    }
}
