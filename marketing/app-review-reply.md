# Draft reply to App Review (Submission 0974a4af-7c5d-4e66-8b5f-76d082435a1e)

Review every answer before sending: they have to be true for you. Lines marked **[CHECK]** depend on facts only you know.

---

Hello App Review team,

Thank you for the feedback. We agreed the first version was too close to existing cleaner apps, so we did not argue the point. We rebuilt the app around a different purpose and are resubmitting it as **Shotfile: Screenshot Organizer** (build 3). These are the main changes since the rejected build:

- **New core feature, reading screenshots on the device.** Shotfile uses Vision text recognition to read every screenshot, sorts it by what it contains (codes and logins, tickets and passes, receipts, chats, directions, posts, notes, pictures), and makes the library searchable by text.
- **Out-of-date detection.** It reads dates written in tickets and passes, and finds one-time codes, so it can flag screenshots that are no longer useful: codes older than two days, and tickets whose dates have all passed. Upcoming tickets are left alone.
- **Text tools.** You can view, select, copy and share the text from any screenshot.
- **Live Photo to still conversion.** This keeps the picture (including edits), date, location, favorite flag and album membership, and removes only the video part. The change is atomic: the still is created and the original deleted in a single Photos change.
- **New name, icon and listing.** All "phone cleaner" positioning and keywords are gone. The weekly subscription was replaced by a monthly plan.

Answers to your questions:

**1. What the app does and the problem it solves.**
People take screenshots to remember things: a verification code, a boarding pass, an order number, a chat, directions. They pile up in the photo library and are hard to find again, and many become useless after a few days. Shotfile reads each screenshot on the device, files it by what it is, lets you find it by any word in it, and points out the ones whose purpose has expired so you can remove them in one step. It also offers a few photo-library storage tools, such as converting Live Photos to stills and finding duplicates.

**2. Intended user.**
iPhone users with hundreds or thousands of screenshots, for example frequent travelers with boarding passes and booking confirmations, online shoppers with order and receipt screenshots, and anyone who screenshots codes, addresses and chats to keep them. They want to find a specific screenshot quickly and stop old ones from crowding the library.

**3. Gap in the market.**
The Photos app can find text in images, but it doesn't group screenshots by purpose, can't tell that a code or a ticket has expired, and has no way to review and remove those in bulk. Its "turn off Live" edit keeps the video data, so it doesn't reclaim space. Shotfile is built around the screenshot life cycle: capture, find, use, clear. All processing stays on the device, with no account and no upload, which matters for screenshots that often contain codes and personal details.

**4. Beta testing.**
**[CHECK]** We tested every build ourselves on TestFlight (internal testing) and in the simulator with a test library of screenshots, Live Photos, duplicates and large videos. Issues we found and fixed include a plan period showing as "7 days" instead of "1 week", text recognition results being re-sorted after rule changes, and date detection on boarding passes. We have not yet run an external beta. *(If you run a TestFlight external beta before replying, replace this paragraph with real feedback and the changes it led to. Don't describe feedback that didn't happen.)*

**5. Standalone or suite.**
Shotfile is a standalone product. **[CHECK]** Our other apps are unrelated in purpose: a vehicle history report app (VIN Check), a calorie tracker (Loqma), a private photo vault (My Vault), and utilities submitted recently (a TV remote, a Bluetooth headset finder, a fax and scan app, a coin identifier). None of them reads, sorts or searches screenshots.

**6. Could it be an in-app purchase or feature of another app?**
The closest app on our account is My Vault, which encrypts and hides private photos behind a passcode. Shotfile does the opposite job: it organizes and cleans up screenshots that live in the main library. The two need different permissions, serve different moments, and would confuse each other's users if combined.

**7. Shared code, frameworks or assets with our other apps.**
No. Shotfile's binary contains only its own Swift code and Apple's system frameworks (SwiftUI, Photos, PhotosUI, Vision, StoreKit). **[CHECK]** Some offline build scripts (for drawing the icon and framing store screenshots) follow the same approach as our My Vault project, but they are not part of the app.

**8. Shared codebase, SDK or content library with third-party apps.**
No. There are no third-party SDKs, templates or content libraries.

**9. Built for a client, partner or third party?**
**[CHECK]** No. Shotfile was conceived, built and published by us, the account holder, under our own developer account. It was not created from a commercial template or by an app generation service. We wrote it in Xcode with the help of AI coding tools.

Thank you for reconsidering the app.

Best regards,
Nouhe Tarfas
