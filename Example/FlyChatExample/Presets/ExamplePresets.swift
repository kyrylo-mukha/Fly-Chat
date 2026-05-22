import FlyChat

/// `ExamplePresets` — builds a fully-configured ``ExampleChatDelegate`` for a given ``ExampleStyle``.
enum ExamplePresets {
    @MainActor
    static func delegate(for style: ExampleStyle) -> ExampleChatDelegate {
        switch style {
        case .liquidGlass: liquidGlass()
        case .solid: solid()
        }
    }

    @MainActor
    private static func liquidGlass() -> ExampleChatDelegate {
        ExampleChatDelegate(
            appearance: ExampleAppearance(
                senderBubbleColor: FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0),
                receiverBubbleColor: FCLChatColorToken(red: 0.90, green: 0.91, blue: 0.94),
                senderTextColor: FCLChatColorToken(red: 1.0, green: 1.0, blue: 1.0),
                receiverTextColor: FCLChatColorToken(red: 0.05, green: 0.05, blue: 0.08),
                tailStyle: .edged(.bottom)
            ),
            layout: ExampleLayout(incomingSide: .left, outgoingSide: .right),
            input: ExampleInput(placeholderText: "Message"),
            visualStyle: ExampleVisualStyle(style: .liquidGlass)
        )
    }

    @MainActor
    private static func solid() -> ExampleChatDelegate {
        ExampleChatDelegate(
            appearance: ExampleAppearance(
                senderBubbleColor: FCLChatColorToken(red: 0.13, green: 0.55, blue: 0.45),
                receiverBubbleColor: FCLChatColorToken(red: 0.95, green: 0.95, blue: 0.97),
                senderTextColor: FCLChatColorToken(red: 1.0, green: 1.0, blue: 1.0),
                receiverTextColor: FCLChatColorToken(red: 0.10, green: 0.10, blue: 0.12),
                tailStyle: .edged(.bottom)
            ),
            layout: ExampleLayout(incomingSide: .left, outgoingSide: .right),
            input: ExampleInput(placeholderText: "Message"),
            visualStyle: ExampleVisualStyle(style: .default)
        )
    }
}
