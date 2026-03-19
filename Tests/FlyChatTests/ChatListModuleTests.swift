import XCTest
@testable import FlyChat

final class FCLChatListModuleTests: XCTestCase {

    // MARK: - ChatListPresenter

    @MainActor
    func testChatListPresenterRoutesSelectedChat() {
        let router = FCLChatListRouterSpy()
        let chat = FCLChatSummary(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            senderID: "test-sender",
            title: "Support",
            lastMessage: "How can we help?",
            updatedAt: Date(),
            unreadCount: 1
        )
        let presenter = FCLChatListPresenter(chats: [chat], router: router)

        presenter.didTapChat(chat)

        XCTAssertEqual(router.openedChatIDs, [chat.id])
    }

    // MARK: - ChatSummary

    func testChatSummaryStoresProvidedValues() {
        let date = Date(timeIntervalSince1970: 1_716_000_000)
        let chat = FCLChatSummary(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            senderID: "test-sender",
            title: "General",
            lastMessage: "Hello, FlyChat!",
            updatedAt: date,
            unreadCount: 3
        )

        XCTAssertEqual(chat.title, "General")
        XCTAssertEqual(chat.lastMessage, "Hello, FlyChat!")
        XCTAssertEqual(chat.updatedAt, date)
        XCTAssertEqual(chat.unreadCount, 3)
    }

    func testChatSummaryStoresSenderID() {
        let chat = FCLChatSummary(senderID: "sender-1", title: "General", lastMessage: "Hi", updatedAt: Date())
        XCTAssertEqual(chat.senderID, "sender-1")
    }
}
