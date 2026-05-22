import CoreGraphics
import FlyChat

/// `ExampleChatDelegate` — composes the four sub-delegates a style preset configures.
@MainActor
final class ExampleChatDelegate: FCLChatDelegate {
    let appearance: (any FCLAppearanceDelegate)?
    let layout: (any FCLLayoutDelegate)?
    let input: (any FCLInputDelegate)?
    let visualStyle: (any FCLVisualStyleDelegate)?

    init(
        appearance: ExampleAppearance,
        layout: ExampleLayout,
        input: ExampleInput,
        visualStyle: ExampleVisualStyle
    ) {
        self.appearance = appearance
        self.layout = layout
        self.input = input
        self.visualStyle = visualStyle
    }
}

@MainActor
final class ExampleAppearance: FCLAppearanceDelegate {
    let senderBubbleColor: FCLChatColorToken
    let receiverBubbleColor: FCLChatColorToken
    let senderTextColor: FCLChatColorToken
    let receiverTextColor: FCLChatColorToken
    let tailStyle: FCLBubbleTailStyle

    init(
        senderBubbleColor: FCLChatColorToken,
        receiverBubbleColor: FCLChatColorToken,
        senderTextColor: FCLChatColorToken,
        receiverTextColor: FCLChatColorToken,
        tailStyle: FCLBubbleTailStyle
    ) {
        self.senderBubbleColor = senderBubbleColor
        self.receiverBubbleColor = receiverBubbleColor
        self.senderTextColor = senderTextColor
        self.receiverTextColor = receiverTextColor
        self.tailStyle = tailStyle
    }
}

@MainActor
final class ExampleLayout: FCLLayoutDelegate {
    let incomingSide: FCLChatBubbleSide
    let outgoingSide: FCLChatBubbleSide

    init(incomingSide: FCLChatBubbleSide, outgoingSide: FCLChatBubbleSide) {
        self.incomingSide = incomingSide
        self.outgoingSide = outgoingSide
    }
}

@MainActor
final class ExampleInput: FCLInputDelegate {
    let placeholderText: String
    let containerMode: FCLInputBarContainerMode
    let fieldBackgroundColor: FCLChatColorToken

    init(
        placeholderText: String,
        containerMode: FCLInputBarContainerMode,
        fieldBackgroundColor: FCLChatColorToken
    ) {
        self.placeholderText = placeholderText
        self.containerMode = containerMode
        self.fieldBackgroundColor = fieldBackgroundColor
    }
}

@MainActor
final class ExampleVisualStyle: FCLVisualStyleDelegate {
    let style: FCLVisualStyle

    init(style: FCLVisualStyle) {
        self.style = style
    }
}
