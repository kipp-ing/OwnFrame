import Foundation
import Testing

@testable import OnboardingKit

@Test func shareLinkExtractionReturnsURLAttachment() async {
    let item = NSExtensionItem()
    let url = URL(string: "https://demo.example.com/s/abc")!
    item.attachments = [NSItemProvider(object: url as NSURL)]

    let extracted = await ShareLinkExtraction.url(from: [item])

    #expect(extracted == url)
}

@Test func shareLinkExtractionReturnsHTTPSURLFromTextAttachment() async {
    let item = NSExtensionItem()
    let url = URL(string: "https://demo.example.com/s/abc")!
    item.attachments = [NSItemProvider(object: url.absoluteString as NSString)]

    let extracted = await ShareLinkExtraction.url(from: [item])

    #expect(extracted == url)
}

@Test func shareLinkExtractionReturnsNilForNonURLTextAndEmptyAttachments() async {
    let textItem = NSExtensionItem()
    textItem.attachments = [NSItemProvider(object: "just text" as NSString)]
    let emptyItem = NSExtensionItem()

    #expect(await ShareLinkExtraction.url(from: [textItem]) == nil)
    #expect(await ShareLinkExtraction.url(from: [emptyItem]) == nil)
}
