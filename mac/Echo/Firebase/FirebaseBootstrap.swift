import FirebaseCore

enum FirebaseBootstrap {
    private static var didConfigure = false

    static func configure() {
        guard !didConfigure, FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
        didConfigure = true
    }
}
