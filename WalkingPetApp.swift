import SwiftUI
import AppKit

// MARK: - Pet model
struct Pet: Identifiable {
    let id: String
    let displayName: String
    let frames: [String] // asset names for animation frames
    var iconName: String { frames.first ?? "" }
}

// MARK: - App entry
@main
struct WalkingPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    let pets: [Pet] = [
        Pet(id: "cat", displayName: "Cat", frames: ["cat1","cat2","cat3","cat4"]),
        Pet(id: "dino", displayName: "Dino", frames: ["dino1","dino2","dino3","dino4"]),
        Pet(id: "dog", displayName: "Dog", frames: ["dog1","dog2","dog3","dog4"]),
        Pet(id: "fish", displayName: "Fish", frames: ["fish"]) // single fish image
    ]

    var statusItem: NSStatusItem!
    var popover: NSPopover?
    var globalMouseMonitor: Any?

    var selectedPetIndex = 0 {
        didSet { UserDefaults.standard.set(selectedPetIndex, forKey: "SelectedPetIndex") }
    }

    var frameIndex = 0
    var timer: Timer?
    var idleTimer: Timer?
    var isWalking = false

    // Fish-specific state
    var fishDirection: CGFloat = 1 // 1 = right, -1 = left
    var fishOffset: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        selectedPetIndex = UserDefaults.standard.integer(forKey: "SelectedPetIndex")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            updateStatusImage(toFrameNamed: currentPet.frames.first)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.toolTip = "Click to choose pet"
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.startWalking()
                self.resetIdleTimer()
            }
        }

        popover = makePopover()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = globalMouseMonitor { NSEvent.removeMonitor(monitor) }
        timer?.invalidate()
        idleTimer?.invalidate()
    }

    var currentPet: Pet { pets[safe: selectedPetIndex] ?? pets[0] }

    func updateStatusImage(toFrameNamed name: String?, yOffset: CGFloat = 0, xOffset: CGFloat = 0) {
        guard let name = name,
              let button = statusItem.button,
              let image = NSImage(named: name)
        else { return }

        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = false

        // Create transformed image (hop or float effect)
        let transformed = NSImage(size: image.size)
        transformed.lockFocus()
        let drawRect = NSRect(x: xOffset, y: yOffset, width: image.size.width, height: image.size.height)
        image.draw(in: drawRect)
        transformed.unlockFocus()

        DispatchQueue.main.async {
            button.image = transformed
        }
    }

    // MARK: - Popover
    @objc func statusItemClicked(_ sender: Any?) { togglePopover() }

    func togglePopover() {
        guard let button = statusItem.button, let popover = popover else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    func makePopover() -> NSPopover {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        let contentView = PetSelectionView(
            pets: pets,
            selectedIndex: selectedPetIndex,
            onSelect: { [weak self] index in
                self?.selectPet(at: index)
                self?.popover?.performClose(nil)
            },
            onClose: { [weak self] in self?.popover?.performClose(nil) }
        )
        pop.contentSize = NSSize(width: 240, height: 260)
        pop.contentViewController = NSHostingController(rootView: contentView)
        return pop
    }

    func selectPet(at index: Int) {
        guard index >= 0 && index < pets.count else { return }
        selectedPetIndex = index
        frameIndex = 0
        updateStatusImage(toFrameNamed: currentPet.frames.first)
    }

    // MARK: - Walking animation
    func startWalking() {
        guard !isWalking else { return }
        isWalking = true
        timer?.invalidate()
        frameIndex = 0
        fishOffset = 0
        fishDirection = 1

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let pet = self.currentPet

            switch pet.id {
            case "dino":
                // Dino hopping animation
                let frames = pet.frames
                let frameName = frames[self.frameIndex % frames.count]
                let hopHeights: [CGFloat] = [0, 2, 4, 2] // up & down motion
                let yOffset = hopHeights[self.frameIndex % hopHeights.count]
                self.updateStatusImage(toFrameNamed: frameName, yOffset: yOffset)

                self.frameIndex = (self.frameIndex + 1) % frames.count

            case "fish":
                // Fish floating left-right
                let name = pet.frames.first
                self.fishOffset += self.fishDirection * 1.5
                if abs(self.fishOffset) > 6 { self.fishDirection *= -1 } // bounce
                self.updateStatusImage(toFrameNamed: name, xOffset: self.fishOffset)

            default:
                // Normal walking animation
                let frames = pet.frames
                let frameName = frames[self.frameIndex % frames.count]
                self.updateStatusImage(toFrameNamed: frameName)
                self.frameIndex = (self.frameIndex + 1) % frames.count
            }
        }
    }

    func stopWalking() {
        timer?.invalidate()
        timer = nil
        isWalking = false
        updateStatusImage(toFrameNamed: currentPet.frames.first)
    }

    // MARK: - Idle detection
    func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.stopWalking()
        }
    }
}

// MARK: - SwiftUI Pet Selection
// MARK: - SwiftUI pet selection view (grid style)
struct PetSelectionView: View {
    let pets: [Pet]
    @State private var selectedIndex: Int
    var onSelect: (Int) -> Void
    var onClose: () -> Void

    init(pets: [Pet], selectedIndex: Int, onSelect: @escaping (Int)->Void, onClose: @escaping ()->Void) {
        self.pets = pets
        _selectedIndex = State(initialValue: selectedIndex)
        self.onSelect = onSelect
        self.onClose = onClose
    }

    // Define a responsive 2x2 grid layout
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 10) {
            Text("Choose Your Walking Pet")
                .font(.headline)
                .padding(.top, 10)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(pets.enumerated()), id: \.offset) { idx, pet in
                    Button(action: {
                        selectedIndex = idx
                        onSelect(idx)
                    }) {
                        VStack(spacing: 6) {
                            Image(pet.iconName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                                .padding(.horizontal, 4)
                                .background(Color.clear)
                                .clipped() // ensures no cropping
                                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)

                            Text(pet.displayName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .frame(width: 90, height: 90)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(selectedIndex == idx ? Color.accentColor.opacity(0.15) : Color(NSColor.windowBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selectedIndex == idx ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: selectedIndex == idx ? 2 : 1)
                        )
                        .shadow(color: selectedIndex == idx ? Color.accentColor.opacity(0.3) : .clear, radius: 4, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            Spacer()

            HStack {
                Button("Close") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding([.horizontal, .bottom], 10)
        }
        .frame(width: 280, height: 280)
        .padding(.horizontal, 6)
    }
}


// MARK: - Safe Subscript Helper
extension Collection {
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

