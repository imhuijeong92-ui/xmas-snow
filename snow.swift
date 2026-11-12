// 크리스마스 눈 — 모든 모니터 위쪽 띠(눈 높이 메뉴)에 픽셀 눈꽃을 내린다.
// 창은 투명하고 클릭이 통과한다. 메뉴 막대 ❄︎ 에서 눈 양 조절·끄기.
// 빌드: ./build.sh
import Cocoa
import QuartzCore

enum Amount: Int, CaseIterable {
    case light = 0, normal, heavy
    var title: String { ["Light", "Normal", "Heavy"][rawValue] }
    var rate: Float { [0.002, 0.005, 0.03][rawValue] }  // 화면 폭 1pt 당 초당 눈송이 수
}

// 눈 내리는 높이 = 화면 위에서부터 이 비율까지 (아래쪽은 서서히 사라진다). 메뉴에서 고른다.
let bandChoices: [(title: String, ratio: CGFloat)] = [("1/8", 0.125), ("1/5", 0.2), ("1/3", 0.33), ("1/2", 0.5), ("Full screen", 1.0)]
// 1/8 이 맨 앞에 생기면서 저장 키를 "height" 로 바꿨다. 예전 "band" 값은 한 칸 밀어서 이어 쓴다 (기본 1/3)
var bandIndex = UserDefaults.standard.object(forKey: "height") as? Int ?? ((UserDefaults.standard.object(forKey: "band") as? Int).map { $0 + 1 } ?? 2)
// 산타 속도(pt/초). 메뉴에서 고른다.
let santaSpeeds: [(title: String, speed: CGFloat)] = [("Slow", 110), ("Normal", 170), ("Fast", 260)]
var santaSpeedIndex = UserDefaults.standard.object(forKey: "santaSpeed") as? Int ?? 1
var santaSpeed: CGFloat { santaSpeeds[min(max(santaSpeedIndex, 0), santaSpeeds.count - 1)].speed }
// --stage = README 미리보기 녹화용. 밤하늘 배경을 깔고(뒤 화면이 안 찍히게) 모든 친구를 차례로 보여 준다. 설정은 저장하지 않는다
let stageMode = CommandLine.arguments.contains("--stage")
// --stage-desk <그림> = README 두 번째 미리보기. 가짜 업무 화면 그림을 깔고 눈 높이 1/8 로 '일하면서 쓰는 모습'을 보여 준다
let deskBackdrop: String? = CommandLine.arguments.firstIndex(of: "--stage-desk").flatMap { i in
    i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil
}
let recording = stageMode || deskBackdrop != nil  // 녹화 중: 맨 위 층에 띄우고, 쌓인 눈은 저장하지 않는다

// 내리는 속도(눈·간식 모두). 메뉴에서 고른다.
let fallSpeeds: [(title: String, mul: CGFloat)] = [("Slow", 0.6), ("Normal", 1), ("Fast", 1.6)]
var fallSpeedIndex = UserDefaults.standard.object(forKey: "fallSpeed") as? Int ?? 1
var fallMul: CGFloat { fallSpeeds[min(max(fallSpeedIndex, 0), fallSpeeds.count - 1)].mul }
// 같이 내릴 것 중 끈 것(번호). 기본은 전부 켬
var treatsOff = Set(UserDefaults.standard.array(forKey: "treatsOff") as? [Int] ?? [])
var bandRatio: CGFloat { bandChoices[min(max(bandIndex, 0), bandChoices.count - 1)].ratio }

// 픽셀 눈꽃: X = 흰 칸. 둘레에 회청색 테두리를 둘러 밝은 창 위에서도 보이게 (Clawd 테마와 같은 톤)
let flakeBig = ["...X...", ".X.X.X.", "..XXX..", "XXXXXXX", "..XXX..", ".X.X.X.", "...X..."]
let flakeMid = ["X.X.X", ".XXX.", "XXXXX", ".XXX.", "X.X.X"]
let flakeDot = ["XX", "XX"]

func flakeImage(_ pattern: [String]) -> CGImage {
    let h = pattern.count, w = pattern[0].count, size = max(w, h) + 2
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let on = { (x: Int, y: Int) -> Bool in
        guard y >= 0, y < h, x >= 0, x < w else { return false }
        return Array(pattern[y])[x] == "X"
    }
    for y in -1...h { for x in -1...w where !on(x, y) {
        if on(x + 1, y) || on(x - 1, y) || on(x, y + 1) || on(x, y - 1) {
            ctx.setFillColor(CGColor(red: 0.56, green: 0.64, blue: 0.72, alpha: 0.85))
            ctx.fill(CGRect(x: x + 1, y: size - (y + 2), width: 1, height: 1))
        }
    } }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    for y in 0..<h { for x in 0..<w where on(x, y) { ctx.fill(CGRect(x: x + 1, y: size - (y + 2), width: 1, height: 1)) } }
    return ctx.makeImage()!
}

let flakeImages = [flakeImage(flakeDot), flakeImage(flakeMid), flakeImage(flakeBig)]

// 산타 위에서만 클릭을 받는 뷰 — 앱을 앞으로 끌어오지 않고 첫 클릭부터 받는다
final class ClickView: NSView {
    var onClick: (CGPoint) -> Void = { _ in }
    // 길게 누르기를 받는 뷰(쌓인 눈)는 손을 뗄 때 클릭으로 친다. 0.55초 누르고 있으면 onHold — true 면 클릭은 없던 걸로.
    // 그 뒤 손을 떼거나 끌어서 벗어나면 onHoldEnd (눈사람은 누르는 동안 자라다가 이때 멈춘다)
    var onHold: ((CGPoint) -> Bool)?
    var onHoldEnd: (() -> Void)?
    private var downAt: CGPoint?
    var isPressed: Bool { downAt != nil }
    private var holdTimer: Timer?
    private var held = false       // onHold 가 받아 줬다 → 손 뗄 때 클릭 아님
    private var holding = false    // 아직 onHoldEnd 를 안 불렀다
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func endHold() {
        guard holding else { return }
        holding = false
        onHoldEnd?()
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hold = onHold else { onClick(p); return }
        downAt = p
        held = false
        holding = false
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
            guard let self = self, let d = self.downAt else { return }
            self.held = hold(d)
            self.holding = self.held
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let d = downAt else { return }
        let p = convert(event.locationInWindow, from: nil)
        if hypot(p.x - d.x, p.y - d.y) > 6 { holdTimer?.invalidate(); downAt = nil; endHold() }
    }
    override func mouseUp(with event: NSEvent) {
        guard onHold != nil else { return }
        holdTimer?.invalidate()
        let p = downAt
        downAt = nil
        if held { endHold() } else if let p = p { onClick(p) }
    }
}

// 평소엔 클릭이 통과하고, 산타가 커서 아래 있을 때만 클릭을 받는다. 포커스는 안 뺏는다.
final class SnowWindow: NSPanel {
    // 눈송이 하나하나가 레이어. 좌우로 흔들리며(왼쪽 대각선 ↔ 오른쪽 대각선) 내려온다.
    let snow = CALayer()
    var rate: CGFloat = 0          // 초당 눈송이 수
    var debt: CGFloat = 0
    var spawnTimer: Timer?
    var actors: [CALayer] = []   // 지나가는 산타·눈사람·펭귄 (클릭하면 말풍선)
    var treatDebt: CGFloat = 0
    var treatLive: [CALayer] = []  // 지금 떨어지는 간식·장식 (클릭하면 터진다)
    var bubble: CALayer?
    var hoverTimer: Timer?
    var paused = false             // 메뉴 Hide for… 로 잠깐 숨기면 멈춘다
    var displayID: UInt32 = 0

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, amount: Amount) {
        let f = screen.frame
        let band = NSRect(x: f.minX, y: f.maxY - f.height * bandRatio, width: f.width, height: f.height * bandRatio)
        super.init(contentRect: band, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hidesOnDeactivate = false
        isOpaque = stageMode
        backgroundColor = stageMode ? NSColor(srgbRed: 0.06, green: 0.09, blue: 0.19, alpha: 1) : .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = recording ? .screenSaver : .statusBar  // 녹화 때는 다른 앱·펫이 안 찍히게 맨 위
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = ClickView(frame: NSRect(origin: .zero, size: band.size))
        view.wantsLayer = true
        view.onClick = { [weak self] p in self?.clicked(at: p) }
        contentView = view
        setFrame(band, display: false)

        snow.frame = view.bounds
        // 아래로 갈수록 투명해지는 마스크 — 띠 끝에서 뚝 끊기지 않게
        let fade = CAGradientLayer()
        fade.frame = view.bounds
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.85, 1]
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        snow.mask = fade
        view.layer?.addSublayer(snow)
        apply(amount, width: band.width)
        displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if lightsOn && !recording { addLights(screen) }

        spawnTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.spawn(0.1) }
        // 평소엔 클릭이 통과하고, 커서가 산타·눈사람·펭귄·간식 위에 있을 때만 클릭을 받는다
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let m = NSEvent.mouseLocation
            let p = CGPoint(x: m.x - self.frame.minX, y: m.y - self.frame.minY)
            self.ignoresMouseEvents = self.paused || (self.actorAt(p) == nil && self.treatAt(p) == nil)
        }
    }

    func setPaused(_ on: Bool, animated: Bool = true) {
        guard on != paused else { return }
        paused = on
        NSAnimationContext.runAnimationGroup { c in c.duration = animated ? 0.4 : 0; animator().alphaValue = on ? 0 : 1 }
    }

    func apply(_ amount: Amount, width: CGFloat) {
        rate = CGFloat(amount.rate) * width
    }

    func stop() {
        spawnTimer?.invalidate()
        hoverTimer?.invalidate()
    }

    func spawn(_ dt: CGFloat) {
        guard !paused else { return }
        debt += rate * dt
        // 펑펑 + 화면 전체에서도 너무 무거워지지 않게. 눈송이 하나가 레이어 하나라 1,500 이면 화면 합성(WindowServer)이 렉 걸린다
        let cap = 500
        while debt >= 1 {
            debt -= 1
            if (snow.sublayers?.count ?? 0) < cap { addFlake() }
        }
        // 눈 양과 상관없이 모니터마다 평균 6초에 하나씩 캔디케인·쿠키·별·선물 등이 섞여 내려온다
        treatDebt = min(max(treatDebt, 2), treatDebt + dt / (stageMode ? 1.2 : 6))  // 다 꺼 둔 동안 쌓이지 않게
        if treatDebt >= 1 {
            treatDebt -= CGFloat.random(in: 0.6...1.4)
            let on = treatGroups.indices.filter { !treatsOff.contains($0) }
            // 아주 가끔(약 600번에 한 번) 황금 눈송이 — 잡으면 Rare finds 에 모인다
            if Int.random(in: 0..<600) == 0 {
                addFaller(goldenFlake, px: 2.5, speed: 30, twinkle: true, group: -1)
            } else if let gi = on.randomElement() {
                let g = treatGroups[gi]
                addFaller(g.imgs.randomElement()!, px: 2.5, speed: CGFloat.random(in: 28...40), tilt: true, twinkle: g.twinkle, group: gi)
            }
        }
    }

    private func addFlake() {
        // 점·중간·큰 눈꽃 = 0.5 : 0.35 : 0.15, 큰 눈송이일수록 빠르다
        let r = CGFloat.random(in: 0..<1)
        let k = r < 0.5 ? 0 : (r < 0.85 ? 1 : 2)
        addFaller(flakeImages[k], px: k == 0 ? 1.5 : 2, speed: [30, 40, 50][k] * CGFloat.random(in: 0.7...1.3))
    }

    // tilt = 흔들릴 때 몸도 살짝 기울기(나뭇잎처럼), twinkle = 반짝반짝
    private func addFaller(_ img: CGImage, px: CGFloat, speed baseSpeed: CGFloat, tilt: Bool = false, twinkle: Bool = false, group: Int? = nil) {
        let w = snow.bounds.width, h = snow.bounds.height
        let speed = baseSpeed * fallMul
        let flake = CALayer()
        flake.contents = img
        flake.magnificationFilter = .nearest
        flake.bounds = CGRect(x: 0, y: 0, width: CGFloat(img.width) * px, height: CGFloat(img.height) * px)
        flake.opacity = tilt ? 1 : Float.random(in: 0.75...1)

        // 흔들림: 폭 10–24pt, 한 번 왕복 4–8초, 시작 위치는 제각각
        let x0 = CGFloat.random(in: -0.03...1.03) * w
        let amp = CGFloat.random(in: 10...24)
        let period = Double.random(in: 4...8)
        let phase = Double.random(in: 0..<(2 * .pi))
        let top = h + flake.bounds.height, fall = h + flake.bounds.height * 2
        let duration = Double(fall / speed)
        let n = max(8, Int(duration * 6))
        let path = (0...n).map { i -> NSValue in
            let t = duration * Double(i) / Double(n)
            return NSValue(point: CGPoint(x: x0 + amp * CGFloat(sin(phase + 2 * .pi * t / period)),
                                          y: top - speed * CGFloat(t)))
        }
        flake.position = path[0].pointValue
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = path
        move.duration = duration
        move.calculationMode = .cubic
        move.isRemovedOnCompletion = false
        move.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            flake.removeFromSuperlayer()
            self?.treatLive.removeAll { $0 === flake }
        }
        if let g = group {
            flake.name = g < 0 ? "golden" : "treat\(g)"
            treatLive.append(flake)
        }
        snow.addSublayer(flake)
        flake.add(move, forKey: "fall")
        if tilt {  // 오른쪽으로 갈 때 오른쪽으로, 왼쪽으로 갈 때 왼쪽으로 기운다
            let rot = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            rot.values = (0...n).map { i in -0.3 * cos(phase + 2 * .pi * duration * Double(i) / Double(n) / period) }
            rot.duration = duration
            rot.calculationMode = .cubic
            flake.add(rot, forKey: "tilt")
        }
        if twinkle {
            let tw = CABasicAnimation(keyPath: "opacity")
            tw.fromValue = 1; tw.toValue = 0.45; tw.duration = 0.5
            tw.autoreverses = true; tw.repeatCount = .infinity
            flake.add(tw, forKey: "twinkle")
        }
        CATransaction.commit()
    }
}

// ── 산타 썰매 + 루돌프 (오른쪽을 보고 왼→오로 난다) ──────────────
let spritePalette: [Character: (CGFloat, CGFloat, CGFloat)] = [
    "R": (0.84, 0.15, 0.24), "r": (0.62, 0.11, 0.17), "W": (0.97, 0.98, 1.0), "F": (0.95, 0.79, 0.63),
    "K": (0.17, 0.17, 0.17), "Y": (0.95, 0.76, 0.31), "y": (0.72, 0.56, 0.16), "B": (0.61, 0.40, 0.27),
    "b": (0.42, 0.26, 0.15), "N": (0.90, 0.22, 0.27), "T": (0.85, 0.70, 0.55), "G": (0.18, 0.62, 0.36),
    "L": (0.30, 0.52, 0.86), "O": (0.98, 0.60, 0.15), "g": (0.10, 0.42, 0.24),
    "S": (0.72, 0.80, 0.90),   // 흰 털 그늘 (북극곰·북극여우가 밝은 창 위에서도 보이게)
]
let sleigh = [
    "...W.RR.........",
    "....RRRR........",
    "...WWWWWW.......",
    "....FFKFF.......",
    "...WWWWWWW......",
    "...RWWWWWRG.....",
    "R..RRRRRRRRRR..R",
    "RRRRRRRRRRRRRRRR",
    "RRRRRYYYRRRRRRRR",
    ".rrrrrrrrrrrrrr.",
    "..y.........y...",
    ".yyyyyyyyyyyyyyy",
]
let reins = ["......", "......", "......", "......", "......", "......",
             "yyyyyy", "......", "......", "......", "......", "......"]
let reindeer = [
    "..........b.b...",
    "..........bbb.b.",
    "...........bbb..",
    "............BBB.",
    "............BKBN",
    "............BTT.",
    "...BBBBBBBBBB...",
    "..BBBBYBBBBBB...",
    ".bBBBBBBBBBB....",
    "...B.B...B.B....",
    "..B...B.B...B...",
    "................",
]

func spriteImage(_ rows: [String], outline: Bool = true) -> CGImage {
    let h = rows.count, w = rows[0].count, W = w + 2, H = h + 2
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let cells = rows.map { Array($0) }
    let at = { (x: Int, y: Int) -> Character in
        guard y >= 0, y < h, x >= 0, x < w else { return "." }
        return cells[y][x]
    }
    if outline { for y in -1...h { for x in -1...w where at(x, y) == "." {
        if at(x + 1, y) != "." || at(x - 1, y) != "." || at(x, y + 1) != "." || at(x, y - 1) != "." {
            ctx.setFillColor(CGColor(red: 0.2, green: 0.16, blue: 0.16, alpha: 0.45))  // 밝은 창 위에서도 보이게
            ctx.fill(CGRect(x: x + 1, y: H - (y + 2), width: 1, height: 1))
        }
    } } }
    for y in 0..<h { for x in 0..<w {
        guard let c = spritePalette[cells[y][x]] else { continue }
        ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
        ctx.fill(CGRect(x: x + 1, y: H - (y + 2), width: 1, height: 1))
    } }
    return ctx.makeImage()!
}

// 선물상자: # = 상자, + = 리본 → (빨강·금), (초록·빨강), (파랑·흰)
let giftRows = ["..+.+..", "...+...", "###+###", "###+###", "+++++++", "###+###", "###+###"]
let giftSprites: [CGImage] = [("R", "Y"), ("G", "R"), ("L", "W")].map { box, ribbon in
    spriteImage(giftRows.map { $0.replacingOccurrences(of: "#", with: box).replacingOccurrences(of: "+", with: ribbon) })
}

// ── 눈 사이에 가끔 섞여 내려오는 것들 ──────────────
let candyCane = ["..RWWR..", ".W....R.", "R......W", "W......R", ".......W", "......RR", "......WW", "......RR", "......WW", "......RR", "......WW", "......RR"]
let gingerbread = ["...bbb...", "..bBBBb..", "..BKBKB..", "..BBBBB..", "..BWWWB..", "bBBBBBBBb", "BWBBRBBWB", "...BWB...", "...BRB...", "..BB.BB..", ".BWB.BWB."]
let star = ["....Y....", "...YYY...", "YYYYYYYYY", ".YYYyYYY.", "..YYYYY..", "..YYYYY..", ".YYY.YYY.", ".YY...YY."]
let ornament = ["...yy...", "..YYYY..", ".RRRRRR.", "RWRRRRRR", "RWRRRRRR", "RRRRRRRR", ".RRRRRR.", "..RRRR.."]
let mistletoe = [".GG...GG.", "GGGG.GGGG", "GgGGRGGgG", ".GGGRGGG.", "...RgR...", "....R...."]
let bell = ["...RRR...", "..RR.RR..", "....y....", "...YYY...", "..YYYYY..", "..YWYYY..", "..YWYYY..", ".YYYYYYY.", "yyyyyyyyy", "....b...."]
// 메뉴 '같이 내릴 것' 의 한 줄 = 한 묶음 (이름, 그림들, 반짝이는지, 클릭해 터질 때 조각 색)
let treatGroups: [(title: String, imgs: [CGImage], twinkle: Bool, pieces: String)] = [
    ("Candy cane 🍬", [spriteImage(candyCane)], false, "RWRW"),
    ("Gingerbread 🍪", [spriteImage(gingerbread)], false, "BbWR"),
    ("Star ⭐", [spriteImage(star)], true, "YyYW"),
    ("Ornament 🔴", [spriteImage(ornament), spriteImage(ornament.map { $0.replacingOccurrences(of: "R", with: "L") })], true, "RLYW"),
    ("Mistletoe 🌿", [spriteImage(mistletoe)], false, "GgGR"),
    ("Bell 🔔", [spriteImage(bell)], false, "YyYR"),
    ("Gift box 🎁", giftSprites, false, "RGLYW"),
]
// 터질 때 조각 = 테두리 없는 한 칸짜리 색 픽셀
let pieceImages: [Character: CGImage] = Dictionary(uniqueKeysWithValues: "RWBbYyLGg".uniqued().map { ch in
    let c = spritePalette[ch]!
    let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    return (ch, ctx.makeImage()!)
})

extension String {
    func uniqued() -> [Character] { var seen = Set<Character>(); return filter { seen.insert($0).inserted } }
}

// ── 가끔 지나가는 친구들 ──────────────
let snowmanRows = ["....KKKK....", "....KKKK....", "...KKKKKK...", "...WWWWWW...", "..WWKWWKWW..", "..WOOOWWWW..", "...WWWWWW...", "..RRRRRRRR..", "B.RWWWWWWW.B", ".BWWWKWWWWB.", "..WWWWWWWW..", ".WWWWKWWWWW.", ".WWWWWWWWWW.", "..WWWWWWWW.."]
let snowmanSprite = spriteImage(snowmanRows)
let penguinSprite = spriteImage(["..........KKK..", ".........KKKKK.", "...KKKKKKKKWKKO", "..KKKKKKKKRRKOO", ".KKWWWWWWWRRKK.", "OKWWWWWWWWWWK..", "O.WWWWWWWWWW..."])

let shootingStarSprite = spriteImage(["...W...", "..WYW..", ".WYYYW.", "WYYYYYW", ".WYYYW.", "..WYW..", "...W..."])

let santaSprite: CGImage = spriteImage((0..<sleigh.count).map { sleigh[$0] + reins[$0] + reindeer[$0] })

extension SnowWindow {
    // 별똥별: 위쪽에서 대각선으로 2.2초 만에 휙. 반짝이 꼬리를 남긴다
    func shootStar(fromX: CGFloat? = nil, rightward: Bool? = nil) {
        guard let root = contentView?.layer else { return }
        let w = root.bounds.width, h = root.bounds.height
        let px: CGFloat = 3
        let size = CGSize(width: CGFloat(shootingStarSprite.width) * px, height: CGFloat(shootingStarSprite.height) * px)
        let toRight = rightward ?? Bool.random()
        let dx = min(w * 0.45, 700) * (toRight ? 1 : -1)
        let dy = min(h * 0.6, abs(dx) * 0.45)
        let start = CGPoint(x: fromX ?? (toRight ? CGFloat.random(in: 0.05...0.5) * w : CGFloat.random(in: 0.5...0.95) * w),
                            y: h - CGFloat.random(in: 10...max(11, h * 0.25)))
        let end = CGPoint(x: start.x + dx, y: start.y - dy)
        let duration = 2.2

        let star = CALayer()
        star.name = "shootingStar"
        star.contents = shootingStarSprite
        star.magnificationFilter = .nearest
        star.bounds = CGRect(origin: .zero, size: size)
        star.position = start
        root.addSublayer(star)

        let trail = CAEmitterLayer()
        trail.frame = root.bounds
        trail.emitterShape = .point
        trail.emitterPosition = start
        trail.emitterCells = ["Y", "W", "y"].compactMap { pieceImages[$0] }.map { img in
            let c = CAEmitterCell()
            c.contents = img
            c.magnificationFilter = CALayerContentsFilter.nearest.rawValue
            c.scale = 3; c.birthRate = 40; c.lifetime = 0.6; c.lifetimeRange = 0.3
            c.velocity = 15; c.emissionRange = .pi * 2; c.alphaSpeed = -1.6
            return c
        }
        root.insertSublayer(trail, below: star)
        star.setValue(trail, forKey: "trail")  // 잡으면 꼬리도 멈춘다

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: start); move.toValue = NSValue(point: end)
        move.duration = duration; move.timingFunction = CAMediaTimingFunction(name: .easeIn)
        move.isRemovedOnCompletion = false; move.fillMode = .forwards
        let tail = CABasicAnimation(keyPath: "emitterPosition")
        tail.fromValue = NSValue(point: start); tail.toValue = NSValue(point: end)
        tail.duration = duration; tail.timingFunction = move.timingFunction
        tail.isRemovedOnCompletion = false; tail.fillMode = .forwards
        let fadeOut = CAKeyframeAnimation(keyPath: "opacity")
        fadeOut.values = [0, 1, 1, 0]; fadeOut.keyTimes = [0, 0.1, 0.8, 1]; fadeOut.duration = duration
        fadeOut.isRemovedOnCompletion = false; fadeOut.fillMode = .forwards

        addActor(star)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.removeActor(star)
            star.removeFromSuperlayer()
            trail.birthRate = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { trail.removeFromSuperlayer() }
        }
        star.add(move, forKey: "move")
        star.add(fadeOut, forKey: "fade")
        trail.add(tail, forKey: "move")
        CATransaction.commit()
    }

    // 화면(눈 높이 범위) 아래쪽을 따라 지나간다. 눈사람 = 오른→왼 통통, 펭귄 = 왼→오 배썰매
    func walk(_ who: String) {
        guard let root = contentView?.layer else { return }
        let snowman = who == "snowman"
        let img = snowman ? snowmanSprite : penguinSprite
        let px: CGFloat = 3
        let size = CGSize(width: CGFloat(img.width) * px, height: CGFloat(img.height) * px)
        let w = root.bounds.width, h = root.bounds.height
        let base = max(size.height / 2 + 8, h * 0.12)
        let speed: CGFloat = snowman ? 80 : 150
        let duration = Double((w + size.width * 2) / speed)

        let sprite = CALayer()
        sprite.name = who
        sprite.contents = img
        sprite.magnificationFilter = .nearest
        sprite.bounds = CGRect(origin: .zero, size: size)
        sprite.position = CGPoint(x: snowman ? w + size.width : -size.width, y: base)
        root.addSublayer(sprite)

        let n = max(20, Int(duration * 20))
        let path = (0...n).map { i -> NSValue in
            let t = Double(i) / Double(n), sec = duration * t
            let x = -size.width + CGFloat(t) * (w + size.width * 2)
            let y = snowman ? base + abs(CGFloat(sin(.pi * sec * 1.6))) * 14   // 통통
                            : base + CGFloat(sin(sec * 5)) * 2                // 미끄러지며 살짝 흔들
            return NSValue(point: CGPoint(x: snowman ? w - x : x, y: y))
        }
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = path; move.duration = duration; move.calculationMode = .linear
        move.isRemovedOnCompletion = false; move.fillMode = .forwards

        // 펭귄 뒤로 눈가루가 튄다
        var spray: CAEmitterLayer?
        if !snowman {
            let e = CAEmitterLayer()
            e.frame = root.bounds
            e.emitterShape = .point
            let c = CAEmitterCell()
            c.contents = flakeImages[0]
            c.magnificationFilter = CALayerContentsFilter.nearest.rawValue
            c.scale = 1.5; c.birthRate = 30; c.lifetime = 0.8
            c.velocity = 50; c.velocityRange = 20
            c.emissionLongitude = .pi * 0.8; c.emissionRange = .pi / 4
            c.yAcceleration = -120; c.alphaSpeed = -1.2
            e.emitterCells = [c]
            let tail = CAKeyframeAnimation(keyPath: "emitterPosition")
            tail.values = path.map { NSValue(point: CGPoint(x: $0.pointValue.x - size.width / 2, y: $0.pointValue.y - size.height / 2)) }
            tail.duration = duration; tail.isRemovedOnCompletion = false; tail.fillMode = .forwards
            e.add(tail, forKey: "move")
            root.insertSublayer(e, below: sprite)
            spray = e
        }

        addActor(sprite)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.removeActor(sprite)
            sprite.removeFromSuperlayer()
            spray?.birthRate = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { spray?.removeFromSuperlayer() }
        }
        sprite.add(move, forKey: "walk")
        CATransaction.commit()
    }

    func flySanta(talk: Bool = false, then done: @escaping () -> Void = {}) {
        guard let root = contentView?.layer else { done(); return }
        let px: CGFloat = 3
        let santaSprite = monthDay() == (12, 24) ? santaTeamSprite : santaSprite   // 크리스마스이브엔 순록 셋이 끈다
        let size = CGSize(width: CGFloat(santaSprite.width) * px, height: CGFloat(santaSprite.height) * px)
        let w = root.bounds.width, h = root.bounds.height
        let y = h * CGFloat.random(in: 0.45...0.7)
        let duration = Double((w + size.width * 2) / santaSpeed)

        let sprite = CALayer()
        sprite.contents = santaSprite
        sprite.magnificationFilter = .nearest
        sprite.bounds = CGRect(origin: .zero, size: size)
        sprite.position = CGPoint(x: -size.width, y: y)
        root.addSublayer(sprite)

        // 루돌프 코 반짝
        let glow = CALayer()
        glow.backgroundColor = CGColor(red: 1, green: 0.45, blue: 0.45, alpha: 1)
        glow.bounds = CGRect(x: 0, y: 0, width: px * 3, height: px * 3)
        glow.position = CGPoint(x: size.width - px * 1.5, y: size.height - px * 5.5)
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 0.1; blink.toValue = 0.8; blink.duration = 0.35
        blink.autoreverses = true; blink.repeatCount = .infinity
        glow.add(blink, forKey: "blink")
        sprite.addSublayer(glow)

        // 반짝이 꼬리
        let trail = CAEmitterLayer()
        trail.frame = root.bounds
        trail.emitterShape = .point
        let spark = CAEmitterCell()
        spark.contents = spriteImage(["Y"])
        spark.magnificationFilter = CALayerContentsFilter.nearest.rawValue
        spark.scale = 3; spark.birthRate = 25; spark.lifetime = 1.4
        spark.velocity = 12; spark.emissionRange = .pi * 2; spark.alphaSpeed = -0.7
        trail.emitterCells = [spark]
        root.insertSublayer(trail, below: sprite)

        // 오르락내리락하며 가로지르기
        let steps = 40
        let path = (0...steps).map { i -> NSValue in
            let t = CGFloat(i) / CGFloat(steps)
            return NSValue(point: CGPoint(x: -size.width + t * (w + size.width * 2), y: y + sin(t * .pi * 6) * 10))
        }
        let fly = CAKeyframeAnimation(keyPath: "position")
        fly.values = path; fly.duration = duration; fly.calculationMode = .linear
        fly.isRemovedOnCompletion = false; fly.fillMode = .forwards
        let tail = CAKeyframeAnimation(keyPath: "emitterPosition")
        tail.values = path.map { NSValue(point: CGPoint(x: $0.pointValue.x - size.width / 2, y: $0.pointValue.y - size.height / 4)) }
        tail.duration = duration; tail.isRemovedOnCompletion = false; tail.fillMode = .forwards

        sprite.name = "santa"
        addActor(sprite)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.removeActor(sprite)
            sprite.removeFromSuperlayer()
            trail.birthRate = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { trail.removeFromSuperlayer() }
        }
        sprite.add(fly, forKey: "fly")
        trail.add(tail, forKey: "fly")
        CATransaction.commit()
        // 화면의 3분의 1쯤 왔을 때 크리스마스까지 며칠 남았는지 말해 준다 (말풍선은 산타를 따라간다)
        if talk {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.3) { [weak self, weak sprite] in
                guard let self = self, let sprite = sprite, sprite.superlayer != nil else { return }
                makeBubble(christmasCountdown(), on: sprite, root: root, scale: self.backingScaleFactor, stay: 3.5)
            }
        }

        // 루돌프 코끝이 화면 오른쪽 끝에 닿으면 다음 모니터에서 출발
        let edgeAt = duration * Double((w + size.width / 2) / (w + size.width * 2))
        DispatchQueue.main.asyncAfter(deadline: .now() + edgeAt, execute: done)
    }

    // ── 산타·눈사람·펭귄 클릭 → "Merry Christmas!" 말풍선 ──────────────
    // 창 전체가 클릭을 막지 않도록, 커서가 지나가는 친구 위에 있을 때만 클릭을 받는다
    func addActor(_ a: CALayer) {
        actors.append(a)
    }

    func removeActor(_ a: CALayer) {
        actors.removeAll { $0 === a }
        if let b = bubble, b.superlayer === a { bubble = nil }
    }

    func treatAt(_ p: CGPoint) -> CALayer? {
        treatLive.last { ($0.presentation()?.frame ?? $0.frame).insetBy(dx: -6, dy: -6).contains(p) }
    }

    func actorAt(_ p: CGPoint) -> CALayer? {
        // 별똥별은 빠르니 넉넉하게 잡는다
        actors.last { ($0.presentation()?.frame ?? $0.frame).insetBy(dx: $0.name == "shootingStar" ? -24 : -6,
                                                                       dy: $0.name == "shootingStar" ? -24 : -6).contains(p) }
    }

    // 별똥별을 잡으면 그 자리에서 반짝 터지고 "Your wish will come true!" 말풍선이 머문다
    func catchStar(_ star: CALayer) {
        guard let root = contentView?.layer else { return }
        let f = star.presentation()?.frame ?? star.frame
        removeActor(star)
        star.isHidden = true
        (star.value(forKey: "trail") as? CAEmitterLayer)?.birthRate = 0
        let spot = CALayer()
        spot.frame = f
        spot.name = "starSpot"
        root.addSublayer(spot)
        burst(at: CGPoint(x: f.midX, y: f.midY), colors: "YyWY")
        showBubble(on: spot, text: "Your wish will come true! ✨")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { spot.removeFromSuperlayer() }
    }

    func clicked(at p: CGPoint) {
        if let a = actorAt(p), a.name == "shootingStar" { catchStar(a) }
        else if let a = actorAt(p), let id = a.name, id.hasPrefix("rare-") { catchRare(a, id: String(id.dropFirst(5))) }
        else if let a = actorAt(p) { showBubble(on: a); dropGifts(from: a) }
        else if let t = treatAt(p), t.name == "golden" { catchGolden(t) }
        else if let t = treatAt(p) { pop(t) }
    }

    // 떨어지던 간식·장식을 클릭하면 '퐁' — 하얀 고리가 퍼지고 그 색깔 픽셀 조각으로 터져 사라진다
    func pop(_ t: CALayer) {
        guard let root = contentView?.layer else { return }
        let f = t.presentation()?.frame ?? t.frame
        let c = CGPoint(x: f.midX, y: f.midY)
        let gi = Int(t.name?.dropFirst(5) ?? "") ?? 0
        treatLive.removeAll { $0 === t }
        t.removeFromSuperlayer()

        let ring = CALayer()
        ring.bounds = CGRect(x: 0, y: 0, width: f.width * 1.2, height: f.width * 1.2)
        ring.position = c
        ring.cornerRadius = ring.bounds.width / 2
        ring.borderColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ring.borderWidth = 3
        ring.opacity = 0
        root.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3; grow.toValue = 1.8
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 0.9; fadeOut.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [grow, fadeOut]; g.duration = 0.35
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(g, forKey: "pop")
        CATransaction.commit()

        burst(at: c, colors: treatGroups[gi].pieces)
    }

    func burst(at c: CGPoint, colors: String) {
        guard let root = contentView?.layer else { return }
        let burst = CAEmitterLayer()
        burst.frame = root.bounds
        burst.emitterPosition = c
        burst.emitterShape = .point
        burst.emitterCells = colors.compactMap { pieceImages[$0] }.map { img in
            let e = CAEmitterCell()
            e.contents = img
            e.magnificationFilter = CALayerContentsFilter.nearest.rawValue
            e.scale = 4; e.scaleRange = 1.5
            e.birthRate = 90; e.lifetime = 0.9; e.lifetimeRange = 0.3
            e.velocity = 150; e.velocityRange = 70
            e.emissionRange = .pi * 2
            e.yAcceleration = -380
            e.spinRange = 6
            e.alphaSpeed = -1
            return e
        }
        burst.beginTime = CACurrentMediaTime()
        root.addSublayer(burst)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { burst.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { burst.removeFromSuperlayer() }
    }

    // 썰매에서 선물상자가 톡 튀어 올랐다가 우르르 떨어진다 (눈처럼 아래로 갈수록 흐려짐)
    func dropGifts(from sprite: CALayer) {
        guard let root = contentView?.layer else { return }
        let f = sprite.presentation()?.frame ?? sprite.frame
        let isSanta = sprite.name == "santa"
        let fall: CGFloat = 520
        let rain = CAEmitterLayer()
        rain.frame = root.bounds
        rain.emitterShape = .line
        rain.emitterPosition = isSanta ? CGPoint(x: f.minX + f.width * 0.22, y: f.minY + f.height * 0.3)  // 썰매 자리
                                       : CGPoint(x: f.midX, y: f.midY)
        rain.emitterSize = CGSize(width: f.width * (isSanta ? 0.35 : 0.5), height: 1)
        let life = Float(sqrt(2 * (f.minY + 40) / fall) + 0.6)
        rain.emitterCells = giftSprites.map { img in
            let c = CAEmitterCell()
            c.contents = img
            c.magnificationFilter = CALayerContentsFilter.nearest.rawValue
            c.scale = 3
            c.birthRate = 12
            c.lifetime = life
            c.velocity = 110; c.velocityRange = 70
            c.emissionLongitude = .pi / 2; c.emissionRange = .pi / 2.5  // 위로 톡 튀어 오른 뒤
            c.yAcceleration = -fall                                     // 떨어진다
            c.spinRange = 2.5
            return c
        }
        let fade = CAGradientLayer()
        fade.frame = root.bounds
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.6, 1]
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        rain.mask = fade
        rain.beginTime = CACurrentMediaTime()
        root.insertSublayer(rain, below: sprite)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rain.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(life) + 0.5) { rain.removeFromSuperlayer() }
    }

    func showBubble(on sprite: CALayer, text message: String = "Merry Christmas! 🎄") {
        guard let root = contentView?.layer else { return }
        bubble?.removeFromSuperlayer()
        let box = makeBubble(message, on: sprite, root: root, scale: backingScaleFactor)
        bubble = box
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self, weak box] in
            if let box = box, self?.bubble === box { self?.bubble = nil }
        }
    }
}

// ── 1.3: 전구 줄 · 잠깐 숨기기 · 어드벤트 캘린더 · 특별한 날 · 드문 손님 · 눈사람 만들기 ──────────────
var lightsOn = UserDefaults.standard.object(forKey: "lights") as? Bool ?? true
// 메뉴 'Hide for…' 로 30분·1시간 숨긴다 — 앱을 다시 켜도 그 시각까지는 숨긴 채로
var hideUntil: Date? = (UserDefaults.standard.object(forKey: "hideUntil") as? Double).map { Date(timeIntervalSince1970: $0) }

// 시험용: XMASSNOW_DATE="2026-12-24 19:00" 으로 켜면 그 시각부터 시간이 흐르는 것처럼 동작한다
let launchedAt = Date()
let fakeStart: Date? = ProcessInfo.processInfo.environment["XMASSNOW_DATE"].flatMap { s in
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)
}
let store = fakeStart == nil ? UserDefaults.standard : UserDefaults(suiteName: "io.github.imhuijeong92-ui.xmas-snow.test")!
func appNow() -> Date { fakeStart.map { $0.addingTimeInterval(Date().timeIntervalSince(launchedAt)) } ?? Date() }
func monthDay(_ d: Date = appNow()) -> (Int, Int) {
    let c = Calendar.current.dateComponents([.month, .day], from: d)
    return (c.month ?? 0, c.day ?? 0)
}

// 메뉴 막대 아래 전구: 줄이 늘어진 곡선마다 전구 3개, 색은 빨·금·파·초·주황 차례
let bulbColors: [Character] = ["R", "Y", "L", "G", "O"]
let bulbSprites = bulbColors.map { c in
    spriteImage([".g.", "XXX", "XXX", ".X."].map { $0.replacingOccurrences(of: "X", with: String(c)) }, outline: false)
}

// 크리스마스이브 산타 = 썰매 + 순록 셋
let santaTeamSprite: CGImage = spriteImage((0..<sleigh.count).map { i -> String in
    let deer: String = reins[i] + reindeer[i]
    return sleigh[i] + deer + deer + deer
})

// 드문 손님 — 만나서 누르면 ❄︎ 메뉴 Rare finds 에 모인다
let rareFinds: [(id: String, name: String, a: String, emoji: String)] = [
    ("golden", "Golden snowflake", "a golden snowflake", "✨"),
    ("bear", "Polar bear", "a polar bear", "🐻‍❄️"),
    ("owl", "Little owl", "a little owl", "🦉"),
    ("fox", "Arctic fox", "an Arctic fox", "🦊"),
    ("elf", "Little elf", "a little elf", "🧝"),
    // 특별한 눈사람 — 꾹 눌러 3단까지 키우면 가끔 나온다
    ("man-santa", "Santa snowman", "a snowman in a Santa hat", "🎅"),
    ("man-cat", "Kitty snowman", "a kitty snowman", "🐱"),
    ("man-gold", "Golden snowman", "a golden snowman", "🌟"),
]
var collected = Set(store.stringArray(forKey: "collected") ?? [])
let collectedChanged = Notification.Name("collectedChanged")

// 처음 찾으면 "You found …! (2/5)", 이미 찾은 거면 "… again!"
func collect(_ id: String) -> String {
    guard let r = rareFinds.first(where: { $0.id == id }) else { return "Merry Christmas! 🎄" }
    guard collected.insert(id).inserted else { return "\(r.name) again! \(r.emoji)" }
    store.set(Array(collected), forKey: "collected")
    NotificationCenter.default.post(name: collectedChanged, object: nil)
    return "You found \(r.a)! \(r.emoji) (\(collected.count)/\(rareFinds.count))"
}

let goldenFlake = spriteImage(flakeBig.map { $0.replacingOccurrences(of: "X", with: "Y") })
let polarBearSprite = spriteImage([
    "...........WW.W.",
    "..........WWWWW.",
    "..WWWWWWWWWWKWWK",
    ".WWWWWWWWWWWWWW.",
    "WWWWWWWWWWWWS...",
    ".SWWWWWWWWWWS...",
    ".SS.SS...SS.SS..",
    ".SS.SS...SS.SS..",
])
let owlSprite = spriteImage([
    ".B.....B.",
    ".BBBBBBB.",
    "BWWBBBWWB",
    "BWKBYBKWB",
    "BWWBYBWWB",
    ".BBTTTBB.",
    ".BTTBTTB.",
    ".BBTTTBB.",
    "..BB.BB..",
    "..Y...Y..",
])
let foxSprite = spriteImage([
    "W.W.............",
    "WWWW............",
    "WKWWW...........",
    "KWWWWWWWWWWW..WW",
    "..WWWWWWWWWWWWWS",
    "..SWWWWWWWWWS.SS",
    "..S.S....S.S....",
    "..S.S....S.S....",
])
let elfSprite = spriteImage([
    "......Y..",
    ".....GG..",
    "....GGG..",
    "..GGGGG..",
    ".GGGGGGG.",
    ".WWWWWWW.",
    ".FFFFFFF.",
    ".FKFFFKF.",
    ".FFFRFFF.",
    "..GGGGG..",
    "FGGGYGGGF",
    "..GGGGG..",
    "..R...R..",
    "..RR..RR.",
])

// 어드벤트 캘린더 12/1–12/25: 하루에 하나씩 짧은 말 + 작은 선물
let adventDays: [(text: String, gift: String)] = [
    ("The first door is open! 24 more little surprises to go. 🎄", "santa"),
    ("A snowman is coming over to say hello. ⛄", "snowman"),
    ("Today's treat: a sweet shower of candy canes and cookies. 🍬", "treats"),
    ("Make a wish — a shooting star is on its way. 🌠", "star"),
    ("Penguin says: slide into the weekend… or at least into tea time. 🐧", "penguin"),
    ("Someone rare is wandering by today. Keep an eye out! ⭐", "rare"),
    ("Hot cocoa rule: one marshmallow for you, one for a friend. ☕", "gifts"),
    ("Rudolph polished his nose just for you. ❤️", "santa"),
    ("Press and hold on the snow pile — you might build a friend. ⛄", "snowman"),
    ("Ten days in! Here's a little gift rain. 🎁", "gifts"),
    ("Even the smallest snowflake makes the world a bit softer. ❄️", "star"),
    ("A rare visitor heard you've been kind this year. ⭐", "rare"),
    ("Penguin practice day: belly slides only. 🐧", "penguin"),
    ("Two weeks of surprises! Santa is doing a test flight. 🎅", "santa"),
    ("Take a deep breath. You're doing great. 🌟", "treats"),
    ("Snowman found a new scarf and wants to show it off. 🧣", "snowman"),
    ("Shooting star delivery — wish carefully! 🌠", "star"),
    ("Someone fluffy is out exploring today. ⭐", "rare"),
    ("Treat yourself: cookies are falling from the sky. 🍪", "treats"),
    ("Five more doors! The elves are working overtime. 🎁", "gifts"),
    ("The longest night of the year — perfect for twinkling lights. 💡", "star"),
    ("Santa's sleigh is getting a last-minute polish. 🛷", "santa"),
    ("Another rare friend is passing by. Can you catch them? ⭐", "rare"),
    ("It's Christmas Eve! Santa brings the whole team tonight. 🎅", "santa"),
    ("Merry Christmas! Look at the bottom of your screen… 🎁", "xmas"),
]

extension SnowWindow {
    // 메뉴 막대 바로 아래로 늘어진 전구 줄. 전구마다 제각각 깜빡인다
    func addLights(_ scr: NSScreen) {
        guard let root = contentView?.layer else { return }
        let top = root.bounds.height - (scr.frame.maxY - scr.visibleFrame.maxY)
        let w = root.bounds.width, span: CGFloat = 72, sag: CGFloat = 9, px: CGFloat = 2.5
        let lights = CALayer()
        lights.name = "lights"
        lights.frame = root.bounds
        let wire = CAShapeLayer()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: top - 1))
        var x: CGFloat = 0
        while x < w {
            path.addQuadCurve(to: CGPoint(x: x + span, y: top - 1), control: CGPoint(x: x + span / 2, y: top - 1 - sag * 2))
            x += span
        }
        wire.path = path
        wire.strokeColor = CGColor(red: 0.10, green: 0.42, blue: 0.24, alpha: 1)
        wire.fillColor = nil
        wire.lineWidth = 1.5
        lights.addSublayer(wire)
        var i = 0
        x = 0
        while x < w {
            for t in [0.2, 0.5, 0.8] as [CGFloat] {
                let k = i % bulbSprites.count
                let img = bulbSprites[k]
                let b = CALayer()
                b.contents = img
                b.magnificationFilter = .nearest
                b.bounds = CGRect(x: 0, y: 0, width: CGFloat(img.width) * px, height: CGFloat(img.height) * px)
                b.anchorPoint = CGPoint(x: 0.5, y: 1)
                b.position = CGPoint(x: x + t * span, y: top - 1 - 4 * sag * t * (1 - t) + px)   // 곡선 위 점에 매단다
                let c = spritePalette[bulbColors[k]]!
                b.shadowColor = CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
                b.shadowOpacity = 0.9
                b.shadowRadius = 5
                b.shadowOffset = .zero
                b.shadowPath = CGPath(ellipseIn: b.bounds.insetBy(dx: px, dy: px * 1.5), transform: nil)
                let tw = CAKeyframeAnimation(keyPath: "opacity")
                tw.values = [1, 1, 0.3, 1]
                tw.keyTimes = [0, 0.55, 0.75, 1]
                tw.duration = Double.random(in: 1.8...3.2)
                tw.repeatCount = .infinity
                tw.beginTime = CACurrentMediaTime() + Double.random(in: 0...3)
                b.add(tw, forKey: "twinkle")
                lights.addSublayer(b)
                i += 1
            }
            x += span
        }
        root.addSublayer(lights)
    }

    // 드문 손님: 북극곰(왼→오 느릿느릿) · 부엉이(날아서) · 북극여우(오→왼 깡충) · 꼬마 요정(왼→오 통통)
    func wander(_ id: String) {
        guard let root = contentView?.layer else { return }
        let img = ["bear": polarBearSprite, "owl": owlSprite, "fox": foxSprite, "elf": elfSprite][id] ?? elfSprite
        let px: CGFloat = 3
        let size = CGSize(width: CGFloat(img.width) * px, height: CGFloat(img.height) * px)
        let w = root.bounds.width, h = root.bounds.height
        let leftward = id == "fox"
        let speed: CGFloat = ["bear": 60, "owl": 120, "fox": 140, "elf": 90][id] ?? 90
        let base = id == "owl" ? h * CGFloat.random(in: 0.45...0.7) : max(size.height / 2 + 8, h * 0.12)
        let duration = Double((w + size.width * 2) / speed)
        let sprite = CALayer()
        sprite.name = "rare-\(id)"
        sprite.contents = img
        sprite.magnificationFilter = .nearest
        sprite.bounds = CGRect(origin: .zero, size: size)
        sprite.position = CGPoint(x: leftward ? w + size.width : -size.width, y: base)
        root.addSublayer(sprite)
        let n = max(20, Int(duration * 20))
        let path = (0...n).map { i -> NSValue in
            let t = Double(i) / Double(n), sec = duration * t
            let x = -size.width + CGFloat(t) * (w + size.width * 2)
            let y: CGFloat
            switch id {
            case "owl": y = base + CGFloat(sin(sec * 4)) * 12
            case "fox": y = base + abs(CGFloat(sin(.pi * sec * 2.5))) * 8
            case "elf": y = base + abs(CGFloat(sin(.pi * sec * 2))) * 12
            default: y = base + CGFloat(sin(sec * 6)) * 1.5
            }
            return NSValue(point: CGPoint(x: leftward ? w - x : x, y: y))
        }
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = path; move.duration = duration; move.calculationMode = .linear
        move.isRemovedOnCompletion = false; move.fillMode = .forwards
        addActor(sprite)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.removeActor(sprite)
            sprite.removeFromSuperlayer()
        }
        sprite.add(move, forKey: "walk")
        CATransaction.commit()
    }

    func catchRare(_ a: CALayer, id: String) {
        let f = a.presentation()?.frame ?? a.frame
        burst(at: CGPoint(x: f.midX, y: f.midY), colors: "YyWY")
        showBubble(on: a, text: collect(id))
    }

    func catchGolden(_ t: CALayer) {
        guard let root = contentView?.layer else { return }
        let f = t.presentation()?.frame ?? t.frame
        treatLive.removeAll { $0 === t }
        t.removeFromSuperlayer()
        let spot = CALayer()
        spot.frame = f
        root.addSublayer(spot)
        burst(at: CGPoint(x: f.midX, y: f.midY), colors: "YyWY")
        showBubble(on: spot, text: collect("golden"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { spot.removeFromSuperlayer() }
    }

    // 선물 비: 화면 위쪽 넓게 선물상자가 우르르 (어드벤트 캘린더)
    func giftRain() {
        guard let root = contentView?.layer else { return }
        let spot = CALayer()
        spot.frame = CGRect(x: root.bounds.width * 0.1, y: root.bounds.height - 12, width: root.bounds.width * 0.8, height: 10)
        root.addSublayer(spot)
        dropGifts(from: spot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { spot.removeFromSuperlayer() }
    }

    // 새해 불꽃놀이: 띠 아래에서 쏘아 올려 여러 색으로 터진다
    func fireworks(seconds: Double) {
        guard let root = contentView?.layer else { return }
        let w = root.bounds.width, h = root.bounds.height
        let banner = CALayer()
        banner.frame = CGRect(x: w / 2 - 60, y: h * 0.35, width: 120, height: 10)
        root.addSublayer(banner)
        _ = makeBubble("Happy New Year! 🎆", on: banner, root: root, scale: backingScaleFactor, stay: 6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { banner.removeFromSuperlayer() }
        let end = CACurrentMediaTime() + seconds
        Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] timer in
            guard let self = self, CACurrentMediaTime() < end else { timer.invalidate(); return }
            let x = CGFloat.random(in: 0.08...0.92) * w, top = h * CGFloat.random(in: 0.45...0.9)
            let rocket = CALayer()
            rocket.contents = pieceImages["Y"]
            rocket.magnificationFilter = .nearest
            rocket.bounds = CGRect(x: 0, y: 0, width: 4, height: 8)
            rocket.position = CGPoint(x: x, y: top)
            root.addSublayer(rocket)
            let up = CABasicAnimation(keyPath: "position.y")
            up.fromValue = 0; up.toValue = top; up.duration = 0.7
            up.timingFunction = CAMediaTimingFunction(name: .easeOut)
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                rocket.removeFromSuperlayer()
                self?.burst(at: CGPoint(x: x, y: top), colors: ["RRYW", "LLWY", "GGYW", "OOYR", "YYWy"].randomElement()!)
            }
            rocket.add(up, forKey: "up")
            CATransaction.commit()
        }
    }
}

// ── 화면 맨 아래(독 뒤)에 눈꽃이 하나씩 쌓이고, 클릭하면 산타 제설차가 지나가며 치운다 ──────────────
let pilePx: CGFloat = 2        // 쌓인 눈 그림 한 칸 = 2pt (내리는 눈꽃과 같은 크기)
let pileCapPx = 22             // 다 찬 높이 평균(44pt). 실제 한도는 자리마다 물결처럼 오르내린다(capMap)
var pileOn = UserDefaults.standard.object(forKey: "pile") as? Bool ?? true
// 산타가 탄 빨간 제설차 (오른쪽을 보고 왼→오로 간다). 지붕 꼬마전구가 깜빡이고 앞날은 캔디케인 줄무늬
let plowRows = [
    "....W...................",
    "....RR..................",
    "....RRR.................",
    "...WWWWW................",
    "...FFKFF................",
    "...WWWWW...............W",
    "..RRWWWRRG............RW",
    "..GGGGGGGG...........RW.",
    "RYRGRYRGRYRGRYRGRR..RW..",
    "RRRRRRRRRRRRRRRYRR.RW...",
    "RRRRRRRRRRRRRRYGYRWR....",
    "RRRRRRRRRRRRRRRYRR.RW...",
    "GGGGGGGGGGGGGGGGGG..RW..",
    "..KKK........KKK.....RW.",
    ".KKYKK......KKYKK.....RW",
    "..KKK........KKK.......W",
]
let plowSprites = [spriteImage(plowRows),
                   spriteImage(plowRows.enumerated().map { $0.offset == 8 ? "RGRYRGRYRGRYRGRYRR" + $0.element.dropFirst(18) : $0.element })]
// 눈이 다 차면 오른쪽 끝에서 빼꼼 나와 "치울까?" 하고 묻는 루돌프 (Clawd 크리스마스 테마의 루돌프와 같은 그림, 다른 친구들처럼 테두리)
let peekDeer = spriteImage([
    ".b.b........b.b.",
    ".bbb........bbb.",
    "..b..........b..",
    "...bb......bb...",
    "....BBBBBBBB....",
    "BB.BBBBBBBBBB.BB",
    ".BBBBKBBBBKBBBB.",
    "...BBKBBBBKBB...",  // 눈을 한 칸 아래로 길게
    "...BBTTTTTTBB...",
    "...BTTTNNTTTB...",
    "...BTTTNNTTTB...",
    "....BTTTTTTB....",
    "...GGGGGGGGGG...",
    "...BBBBYYBBBB...",
    "...BBTTTTTTBB...",
    "...BBTTTTTTBB...",
    "...BBBBBBBBBB...",
    "....bb....bb....",
])

final class PileWindow: NSPanel {
    let pile = CAGradientLayer()   // 위는 흰색 → 아래로 옅은 하늘색 (픽셀 눈 더미 그림들의 흰색+하늘색 그늘 방식)
    let pileShape = CAShapeLayer() // 눈 더미 윤곽 = 쌓인 높이를 부드럽게 이은 곡선 (테두리 없음)
    var heights: [Int] = []        // 칸마다 쌓인 눈 꼭대기 (그림 칸 단위)
    var capMap: [Int] = []         // 칸마다 더 쌓이지 않는 한도 — 다 차도 윗면이 일자가 아니라 둔덕지게
    var carry: CGFloat = 0
    var amountFactor: CGFloat = 1  // Light 0.25 · Normal 1 · Heavy 2
    var plow: CALayer?
    var deer: CALayer?
    var lastPeek: Date?
    var growTimer: Timer?
    var hoverTimer: Timer?
    var dockUp = false             // 커서가 화면 아래 끝에 닿아 독이 올라온 상태 — 이때 독 자리 안의 클릭은 독 몫
    let dockBand: CGFloat
    let dockIcon: CGFloat
    var dockHalf: CGFloat = 0      // 올라온 독의 가로 반폭(가운데 기준) — 독 양옆에 쌓인 눈은 그대로 누를 수 있게
    // 쌓인 높이·물결 모양을 화면마다 저장 → 앱을 다시 켜거나 화면이 바뀌어도 이어서 쌓인다
    let saveKey: String
    var ph: [CGFloat] = []
    var saveTick = 0
    let front: NSPanel            // 제설차·루돌프·말풍선은 독 앞에 보이도록 위층 창에
    var standers: [CALayer] = []  // 쌓인 눈 위에 선 것 — 만든 눈사람, 크리스마스 아침 선물상자
    var building: CALayer?        // 지금 꾹 눌러 키우는 눈사람
    var buildSpan = 0...0
    var buildTimer: Timer?
    var nextCarrot = 0.0           // 코 없는 눈사람이 생기면 그때부터 잰다
    var lifeTimer: Timer?         // 눈사람 깜빡임·쳐다보기·손 흔들기·수다
    var nextChat = CACurrentMediaTime() + Double.random(in: 60...150)
    var paused = false
    let displayID: UInt32
    var frontRoot: CALayer { front.contentView!.layer! }
    // 다 차는 데 걸리는 시간 = 6분 ÷ (눈 양 × 눈 높이 비율) → 눈이 적게 내리면 그만큼 천천히 쌓인다
    var fillSeconds: CGFloat { 360 / (amountFactor * bandRatio) }
    var isFull: Bool { heights.indices.filter { heights[$0] >= capMap[$0] - 3 }.count >= heights.count * 85 / 100 }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, amountFactor: CGFloat) {
        // 화면 맨 아래, 독보다 한 층 아래 → 독 뒤에 쌓이고 독 양옆으로 보인다 (일반 창보다는 위)
        let f = screen.frame
        let rect = NSRect(x: f.minX, y: f.minY, width: f.width, height: 160)
        front = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // 독 높이 = 아이콘 크기(확대 켜면 확대 크기) + 위아래 여백. 독이 옆에 붙어 있으면 아래 클릭과 겹치지 않는다
        let dock = UserDefaults(suiteName: "com.apple.dock")
        let side = (dock?.string(forKey: "orientation") ?? "bottom") != "bottom"
        let tile = CGFloat(dock?.object(forKey: "tilesize") as? Double ?? 48)
        let big = dock?.bool(forKey: "magnification") == true ? CGFloat(dock?.object(forKey: "largesize") as? Double ?? 64) : 0
        dockBand = side ? 0 : max(tile, big) + 28
        dockIcon = max(tile, big)
        let display = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        displayID = display
        saveKey = "pile-\(display)"
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.amountFactor = amountFactor
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = recording ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
                          : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = ClickView(frame: NSRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        view.onClick = { [weak self] p in self?.clicked(at: p) }
        view.onHold = { [weak self] p in self?.holdPile(at: p) ?? false }
        view.onHoldEnd = { [weak self] in self?.finishBuild() }
        contentView = view
        setFrame(rect, display: false)

        front.hidesOnDeactivate = false
        front.isOpaque = false
        front.backgroundColor = .clear
        front.hasShadow = false
        front.ignoresMouseEvents = true
        front.isReleasedWhenClosed = false
        front.level = recording ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2) : .statusBar
        front.collectionBehavior = collectionBehavior
        let fv = ClickView(frame: NSRect(origin: .zero, size: rect.size))
        fv.wantsLayer = true
        fv.onClick = { [weak self] p in self?.clicked(at: p) }
        front.contentView = fv
        front.setFrame(rect, display: false)

        let cols = Int(ceil(rect.width / pilePx))
        heights = Array(repeating: 0, count: cols)
        let saved = recording ? nil : UserDefaults.standard.dictionary(forKey: saveKey)
        // 큰 둔덕 + 작은 굴곡 + 동글한 혹을 겹친 물결 (모니터마다 모양이 다르다)
        let savedPh = (saved?["ph"] as? [Double])?.map { CGFloat($0) }
        ph = savedPh?.count == 4 ? savedPh! : (0..<4).map { _ in CGFloat.random(in: 0..<(2 * .pi)) }
        let ph = self.ph
        capMap = (0..<cols).map { i in
            let x = CGFloat(i)
            let wave: CGFloat = 6 * sin(x * 0.016 + ph[0]) + 3 * sin(x * 0.047 + ph[1]) + 1.5 * sin(x * 0.12 + ph[2])
            let lump: CGFloat = 3.5 * abs(sin(x * 0.1 + ph[3]))  // 동글동글한 혹
            return pileCapPx + Int((wave + lump).rounded())
        }
        pile.anchorPoint = .zero
        pile.frame = CGRect(x: 0, y: 0, width: CGFloat(cols) * pilePx, height: CGFloat(pileCapPx + 14) * pilePx)
        pile.colors = [CGColor(red: 0.80, green: 0.87, blue: 0.95, alpha: 1), CGColor(red: 0.93, green: 0.96, blue: 1, alpha: 1),
                       CGColor(red: 1, green: 1, blue: 1, alpha: 1)]
        pile.locations = [0, 0.35, 0.7]
        pile.startPoint = CGPoint(x: 0.5, y: 0)
        pile.endPoint = CGPoint(x: 0.5, y: 1)
        pileShape.frame = pile.bounds
        pile.mask = pileShape
        view.layer?.addSublayer(pile)
        // 저장해 둔 눈 더미 이어 붙이기 (해상도가 바뀌었으면 칸 수에 맞춰 늘이거나 줄인다)
        if let h = saved?["h"] as? [Int], !h.isEmpty {
            heights = (0..<cols).map { i in min(capMap[i], h[i * h.count / cols]) }
            redraw()
        }
        // 눈사람 = [x, 크기, 모양] (1.2.x 의 "men" 은 x 만 있었다 → 모자 쓴 보통 눈사람)
        let men = saved?["men2"] as? [[Double]] ?? (saved?["men"] as? [Double] ?? []).map { [$0, 3, 0] }
        for m in men where m.count >= 3 && m.allSatisfy({ $0.isFinite }) && m[0] < Double(rect.width) {
            _ = addMan(at: CGFloat(m[0]), tier: min(max(Int(m[1]), 1), 3), kind: min(max(Int(m[2]), 0), 3),
                       nose: m.count < 4 || m[3] != 0)
        }

        growTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.grow(1); self?.autosave() }
        lifeTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.lifeTick() }
        // 평소엔 클릭이 통과하고, 커서가 쌓인 눈이나 루돌프 위에 있을 때만 클릭을 받는다
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let m = NSEvent.mouseLocation
            let p = CGPoint(x: m.x - self.frame.minX, y: m.y - self.frame.minY)
            // 독처럼 판단: 아래 끝에 닿으면 독이 올라오고, 독 높이 위로 벗어나거나 다른 화면으로 가면 내려간다
            let here = p.x >= 0 && p.x < self.frame.width
            if here && p.y <= 1 && self.dockBand > 0 && !self.dockUp { self.dockUp = true; self.dockHalf = self.dockWidth() / 2 }
            if !here || p.y > self.dockBand { self.dockUp = false }
            self.front.ignoresMouseEvents = self.paused || !self.onDeer(p)
            if (self.contentView as? ClickView)?.isPressed == true { return }   // 누르는 중엔 손 뗄 때까지 받는다
            self.ignoresMouseEvents = self.paused || (!self.onPile(p) && self.standerAt(p) == nil)
        }
    }

    func save() {
        guard !recording else { return }  // 녹화용 눈 더미가 진짜 쌓인 눈을 덮어쓰지 않게
        let men = standers.filter { $0.name == "snowman" }.map { [Double($0.position.x), Double(manTier($0)), Double(manKind($0)), manNose($0) ? 1 : 0] }
        UserDefaults.standard.set(["h": heights, "ph": ph.map { Double($0) }, "men2": men, "men": men.map { $0[0] }], forKey: saveKey)
    }

    func autosave() {
        saveTick += 1
        if saveTick % 10 == 0 { save() }  // 10초마다
    }

    func stop() {
        save()
        growTimer?.invalidate()
        hoverTimer?.invalidate()
        lifeTimer?.invalidate()
        buildTimer?.invalidate()
        front.orderOut(nil)
    }

    func show() {
        orderFrontRegardless()
        front.orderFrontRegardless()
    }

    // 독 너비 어림 = (고정 앱 + 고정 안 된 실행 중 앱 + 폴더·휴지통) × 아이콘 + 구분선·여백. 넉넉히 잡되 화면 전체를 막지는 않는다
    func dockWidth() -> CGFloat {
        let dock = UserDefaults(suiteName: "com.apple.dock")
        let apps = dock?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        let pinned = Set(apps.compactMap { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String })
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !pinned.contains($0.bundleIdentifier ?? "")
        }.count
        let recents = dock?.object(forKey: "show-recents") as? Bool ?? true ? 3 : 0
        let others = dock?.array(forKey: "persistent-others")?.count ?? 0
        let items = CGFloat(apps.count + running + recents + others + 1)
        return items * dockIcon + 2 * 14 + 2 * dockIcon
    }

    func onPile(_ p: CGPoint) -> Bool {
        let i = Int(p.x / pilePx)
        let underDock = dockUp && p.y <= dockBand && abs(p.x - frame.width / 2) <= dockHalf
        guard plow == nil, i >= 0, i < heights.count, heights[i] >= 3, !underDock else { return false }
        return p.y >= 0 && p.y <= CGFloat(heights[i]) * pilePx + 6
    }

    func onDeer(_ p: CGPoint) -> Bool {
        guard let d = deer else { return false }
        return (d.presentation()?.frame ?? d.frame).insetBy(dx: -6, dy: -6).contains(p)
    }

    func clicked(at p: CGPoint) {
        if onDeer(p) { tapDeer(at: p) }
        else if let s = standerAt(p) { s.name == "gift" ? openGift(s) : s.name == "carrot" ? pickCarrot(s) : greet(s) }
        else if onPile(p) { puff(at: p); hideDeer(); sendPlow() }
    }

    // 루돌프를 한 번 누르면 제설차, 연달아 5번 누르면 제설차 대신 비밀 이야기 (이스터에그)
    var deerTaps = 0
    var deerTapTimer: Timer?
    var telling = false

    func tapDeer(at p: CGPoint) {
        guard !telling else { return }
        puff(at: p)
        deerTaps += 1
        deerTapTimer?.invalidate()
        if deerTaps >= 5 { deerTaps = 0; tellStory(); return }
        deerTapTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.deerTaps = 0
            self.hideDeer()
            self.sendPlow()
        }
    }

    func tellStory() {
        guard let d = deer else { return }
        telling = true
        d.sublayers?.forEach { $0.removeFromSuperlayer() }  // "Time to clear the snow?" 말풍선 치우기
        let lines = deerStories[nextIndex("deerStory", count: deerStories.count)]
        for (i, line) in lines.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(i) * 3) { [weak self, weak d] in
                guard let self = self, let d = d, self.deer === d else { return }
                d.sublayers?.forEach { $0.removeFromSuperlayer() }
                makeBubble(line, on: d, root: self.frontRoot, scale: self.backingScaleFactor, stay: 2.8)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(lines.count) * 3 + 0.5) { [weak self] in
            self?.telling = false
            self?.hideDeer()
        }
    }

    // 누른 자리에서 바로 '퐁' — 하얀 고리가 퍼지고 눈꽃이 위로 튀어 오른다 (눌렸다는 걸 바로 알게)
    func puff(at c: CGPoint) {
        let root = frontRoot
        let ring = CALayer()
        ring.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
        ring.position = c
        ring.cornerRadius = 18
        ring.borderColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ring.borderWidth = 3
        ring.opacity = 0
        root.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3; grow.toValue = 1.8
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 0.9; fadeOut.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [grow, fadeOut]; g.duration = 0.35
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(g, forKey: "pop")
        CATransaction.commit()

        let burst = CAEmitterLayer()
        burst.frame = root.bounds
        burst.emitterPosition = c
        burst.emitterShape = .point
        burst.emitterCells = [flakeImages[0], flakeImages[1], flakeImages[2]].map { img in
            let e = CAEmitterCell()
            e.contents = img
            e.magnificationFilter = CALayerContentsFilter.nearest.rawValue
            e.scale = 1.8; e.scaleRange = 0.5
            e.birthRate = 60; e.lifetime = 0.9; e.lifetimeRange = 0.3
            e.velocity = 170; e.velocityRange = 70
            e.emissionLongitude = .pi / 2; e.emissionRange = .pi / 2.2   // 위쪽으로 퍼진다
            e.yAcceleration = -420; e.spinRange = 5; e.alphaSpeed = -1
            return e
        }
        burst.beginTime = CACurrentMediaTime()
        root.addSublayer(burst)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { burst.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { burst.removeFromSuperlayer() }
    }

    // 둥근 눈 뭉텅이(반지름 3–8칸)를 하나씩 얹어 울퉁불퉁하게 쌓는다. 자리마다 한도(capMap)를 넘으면 안 올라간다
    func grow(_ dt: CGFloat) {
        let n = heights.count
        carry += CGFloat(n * pileCapPx) / (fillSeconds * 30) * dt
        var changed = false
        while carry >= 1 {
            carry -= 1
            for _ in 0..<6 {
                let x = Int.random(in: 0..<n), r = Int.random(in: 3...8)
                let base = heights[x] - r / 3
                var grew = false
                for i in max(0, x - r)...min(n - 1, x + r) {
                    let dx = CGFloat(i - x)
                    let v = min(capMap[i], base + Int((sqrt(CGFloat(r * r) - dx * dx) * 0.7).rounded()))
                    if v > heights[i] { heights[i] = v; grew = true }
                }
                if grew { changed = true; break }
            }
        }
        if changed { redraw() }
        if plow == nil, deer == nil, isFull, lastPeek.map({ Date().timeIntervalSince($0) > 600 }) ?? true { peek() }
    }

    func redraw() {
        // 이웃 5칸 평균으로 계단을 펴고, 점 사이를 2차 곡선으로 이어 매끈한 윤곽을 만든다
        let n = heights.count
        let smooth: [CGFloat] = (0..<n).map { i in
            let r = max(0, i - 2)...min(n - 1, i + 2)
            return CGFloat(r.reduce(0) { $0 + heights[$1] }) / CGFloat(r.count) * pilePx
        }
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 0, y: smooth.first ?? 0))
        for i in 1..<n {
            let p0 = CGPoint(x: CGFloat(i - 1) * pilePx, y: smooth[i - 1]), p1 = CGPoint(x: CGFloat(i) * pilePx, y: smooth[i])
            path.addQuadCurve(to: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2), control: p0)
        }
        path.addLine(to: CGPoint(x: CGFloat(n) * pilePx, y: smooth.last ?? 0))
        path.addLine(to: CGPoint(x: CGFloat(n) * pilePx, y: 0))
        path.closeSubpath()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pileShape.path = path
        for st in standers { st.position.y = surfaceY(st.position.x) + st.bounds.height / 2 - 3 }  // 눈이 줄면 같이 내려앉는다
        CATransaction.commit()
    }

    // 루돌프가 오른쪽 끝에서 빼꼼 → "Time to clear the snow?" → 8초 뒤 쏙 들어간다. 루돌프를 눌러도 제설차가 온다
    func peek() {
        let root = frontRoot
        lastPeek = Date()
        let px: CGFloat = 3   // 다른 친구들과 같은 한 칸 크기
        let size = CGSize(width: CGFloat(peekDeer.width) * px, height: CGFloat(peekDeer.height) * px)
        let w = root.bounds.width
        let d = CALayer()
        d.contents = peekDeer
        d.magnificationFilter = .nearest
        d.bounds = CGRect(origin: .zero, size: size)
        let y = CGFloat(pileCapPx) * pilePx * 0.6 + size.height / 2
        d.position = CGPoint(x: w - size.width * 0.32, y: y)
        root.addSublayer(d)
        deer = d
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = w + size.width / 2; slide.toValue = w - size.width * 0.32
        slide.duration = 0.5; slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        d.add(slide, forKey: "in")
        let bob = CABasicAnimation(keyPath: "position.y")
        bob.fromValue = y; bob.toValue = y + 3; bob.duration = 0.45
        bob.autoreverses = true; bob.repeatCount = .infinity; bob.beginTime = CACurrentMediaTime() + 0.5
        d.add(bob, forKey: "bob")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self, weak d] in
            guard let self = self, let d = d, self.deer === d else { return }
            _ = makeBubble("Time to clear the snow? ❄️", on: d, root: root, scale: self.backingScaleFactor, stay: 7)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak d] in
            guard let self = self, let d = d, self.deer === d, !self.telling, self.deerTaps == 0 else { return }
            self.hideDeer()
        }
    }

    func hideDeer() {
        guard let d = deer else { return }
        let root = frontRoot
        deer = nil
        let x = (d.presentation() ?? d).position.x
        CATransaction.begin()
        CATransaction.setCompletionBlock { d.removeFromSuperlayer() }
        let out = CABasicAnimation(keyPath: "position.x")
        out.fromValue = x; out.toValue = root.bounds.width + d.bounds.width
        out.duration = 0.35; out.timingFunction = CAMediaTimingFunction(name: .easeIn)
        out.isRemovedOnCompletion = false; out.fillMode = .forwards
        d.add(out, forKey: "out")
        CATransaction.commit()
    }

    func clear() {
        heights = Array(repeating: 0, count: heights.count)
        redraw()
    }

    // 왼쪽 끝에서 오른쪽 끝까지 달리며 앞날 뒤쪽 눈을 전부 치우고, 앞으로 눈가루를 튀긴다
    func sendPlow() {
        guard plow == nil else { return }
        let root = frontRoot
        let px: CGFloat = 3
        let size = CGSize(width: CGFloat(plowSprites[0].width) * px, height: CGFloat(plowSprites[0].height) * px)
        let w = root.bounds.width, speed: CGFloat = 220
        let startX = -size.width / 2, endX = w + size.width / 2
        let duration = Double((endX - startX) / speed)

        let truck = CALayer()
        truck.contents = plowSprites[0]
        truck.magnificationFilter = .nearest
        truck.bounds = CGRect(origin: .zero, size: size)
        truck.position = CGPoint(x: startX, y: size.height / 2)
        root.addSublayer(truck)
        plow = truck
        let blink = CAKeyframeAnimation(keyPath: "contents")
        blink.values = plowSprites; blink.calculationMode = .discrete
        blink.duration = 0.6; blink.repeatCount = .infinity
        truck.add(blink, forKey: "blink")
        let bump = CABasicAnimation(keyPath: "position.y")   // 덜컹덜컹
        bump.fromValue = size.height / 2; bump.toValue = size.height / 2 + 2
        bump.duration = 0.12; bump.autoreverses = true; bump.repeatCount = .infinity
        truck.add(bump, forKey: "bump")

        let spray = CAEmitterLayer()
        spray.frame = root.bounds
        spray.emitterShape = .point
        spray.emitterCells = [flakeImages[0], flakeImages[1]].map { img in
            let c = CAEmitterCell()
            c.contents = img
            c.magnificationFilter = CALayerContentsFilter.nearest.rawValue
            c.scale = 1.5; c.birthRate = 30; c.lifetime = 0.9; c.lifetimeRange = 0.3
            c.velocity = 170; c.velocityRange = 60
            c.emissionLongitude = .pi / 3; c.emissionRange = .pi / 4   // 앞쪽 위로
            c.yAcceleration = -420; c.alphaSpeed = -1; c.spinRange = 4
            return c
        }
        spray.birthRate = 0
        root.insertSublayer(spray, below: truck)

        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = startX; move.toValue = endX; move.duration = duration
        move.isRemovedOnCompletion = false; move.fillMode = .forwards
        truck.add(move, forKey: "drive")

        let t0 = CACurrentMediaTime()
        var jumped = Set<ObjectIdentifier>()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - t0
            let front = startX + speed * CGFloat(elapsed) + size.width / 2 - px   // 앞날 끝
            // 제설차가 다가오면 눈사람이 "Not me!!" 하고 폴짝 뛰어 넘긴다
            for l in self.standers.filter({ $0.name == "snowman" })
            where !jumped.contains(ObjectIdentifier(l)) && front >= l.position.x - l.bounds.width / 2 - 75 {
                jumped.insert(ObjectIdentifier(l))
                self.dodge(l, truck: size, speed: speed)
            }
            let upTo = min(self.heights.count, max(0, Int(front / pilePx)))
            let ahead = upTo < self.heights.count ? self.heights[upTo] : 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            spray.emitterPosition = CGPoint(x: front, y: max(CGFloat(ahead) * pilePx, px * 4))
            spray.birthRate = ahead > 0 ? 1 : 0
            CATransaction.commit()
            if self.heights[0..<upTo].contains(where: { $0 > 0 }) {
                for i in 0..<upTo { self.heights[i] = 0 }
                self.redraw()
            }
            if elapsed >= duration {
                timer.invalidate()
                truck.removeFromSuperlayer()
                spray.birthRate = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { spray.removeFromSuperlayer() }
                self.plow = nil
                self.save()
            }
        }
    }
}

// ── 눈사람 그림: 크기 1(눈덩이)·2(두 단)·3(모자 쓴 세 단) × 모양 0 보통·1 산타 모자·2 고양이 귀·3 황금 ──
// 눈동자를 한 칸 옮겨 커서 쪽을 보고(look −1·0·1), 눈을 감고(blink), 3단은 오른팔을 든다(wave)
let manBodies: [(rows: [String], eyeRow: Int, eyes: [Int])] = [
    (["..WWWW..", ".WWWWWW.", "WWKWWKWW", "WWWOOWWW", "WWWWWWWW", ".WWWWWW.", "..WWWW.."], 2, [2, 5]),
    (["...WWWW...", "..WWWWWW..", "..WKWWKW..", "..WWOOWW..", "...WWWW...", "..RRRRRR..", ".WWWWWWWW.", ".WWWKWWWW.",
      ".WWWWWWWW.", "..WWWWWW.."], 2, [3, 6]),
    (snowmanRows, 4, [4, 7]),
]
var manCache: [String: CGImage] = [:]
func manImage(tier: Int, kind: Int, look: Int, blink: Bool, wave: Bool, nose: Bool = true) -> CGImage {
    let key = "\(tier)\(kind)\(look)\(blink)\(wave)\(nose)"
    if let img = manCache[key] { return img }
    let body = manBodies[min(max(tier, 1), 3) - 1]
    var rows = body.rows.map { Array($0) }
    if tier >= 3 {
        switch kind {
        case 1: rows[0] = Array(".......W...."); rows[1] = Array("....RRRRR..."); rows[2] = Array("...RRRRRR...")
        case 2: rows[0] = Array("...W....W..."); rows[1] = Array("...WW..WW..."); rows[2] = Array("...WWWWWW...")
        default: break
        }
        if wave { rows[7] = Array("..RRRRRRRR.B"); rows[8] = Array("B.RWWWWWWWB."); rows[9] = Array(".BWWWKWWWW..") }
    }
    for c in body.eyes { rows[body.eyeRow][c] = "W" }
    if !blink { for c in body.eyes { rows[body.eyeRow][c + look] = "K" } }
    var out = rows.map { String($0) }
    if !nose { out = out.map { $0.replacingOccurrences(of: "O", with: "W") } }   // 당근 코 없는 눈사람
    if kind == 3 { out = out.map { $0.replacingOccurrences(of: "W", with: "Y") } }
    let img = spriteImage(out)
    manCache[key] = img
    return img
}
// 바닥에 떨어진 당근 — 주우면 코 없는 눈사람의 코가 된다
let carrotSprite = spriteImage(["......g.g", ".OOOOOOgg", "OOOOOOOg.", ".OOOO...."])
let manChats = [("Nice day, isn't it? ❄️", "Perfect snowman weather! ⛄"), ("Is Santa coming tonight? 🎅", "I hope so! 🎁"),
                ("I think I'm melting… 😰", "Relax, it's freezing! 😄"), ("Do you like my scarf? 🧣", "Very stylish! ✨"),
                ("Snowball fight? ⚪", "Not with our heads! 😆"), ("Can you see the Dock from there? 👀", "Only the top of it! 😄")]

// ── 쌓인 눈 위에 서는 것: 길게 눌러 만든 눈사람 · 크리스마스 아침 선물상자 ──────────────
extension PileWindow {
    func setPaused(_ on: Bool, animated: Bool = true) {
        guard on != paused else { return }
        paused = on
        NSAnimationContext.runAnimationGroup { c in
            c.duration = animated ? 0.4 : 0
            animator().alphaValue = on ? 0 : 1
            front.animator().alphaValue = on ? 0 : 1
        }
    }

    // 그 자리 눈 윗면 높이 (이웃 5칸 평균 = 그림 윤곽과 같은 높이)
    func surfaceY(_ x: CGFloat) -> CGFloat {
        let n = heights.count
        guard n > 0 else { return 0 }
        let i = min(max(Int(x / pilePx), 0), n - 1)
        let r = max(0, i - 2)...min(n - 1, i + 2)
        return CGFloat(r.reduce(0) { $0 + heights[$1] }) / CGFloat(r.count) * pilePx
    }

    func standerAt(_ p: CGPoint) -> CALayer? {
        let underDock = dockUp && p.y <= dockBand && abs(p.x - frame.width / 2) <= dockHalf
        guard !underDock, plow == nil else { return nil }
        return standers.last { $0.frame.insetBy(dx: -4, dy: -4).contains(p) }
    }

    func stand(_ img: CGImage, px: CGFloat, at x: CGFloat, name: String) -> CALayer {
        let l = CALayer()
        l.name = name
        l.contents = img
        l.magnificationFilter = .nearest
        l.bounds = CGRect(x: 0, y: 0, width: CGFloat(img.width) * px, height: CGFloat(img.height) * px)
        l.position = CGPoint(x: x, y: surfaceY(x) + l.bounds.height / 2 - 3)
        contentView?.layer?.addSublayer(l)
        standers.append(l)
        return l
    }

    func say(_ text: String, on l: CALayer) {
        guard let root = contentView?.layer else { return }
        l.sublayers?.forEach { $0.removeFromSuperlayer() }   // 말풍선이 겹쳐 쌓이지 않게
        _ = makeBubble(text, on: l, root: root, scale: backingScaleFactor, stay: 2.5)
    }

    // 쌓인 눈을 0.55초 누르고 있으면 눈덩이가 생기고, 계속 누르면 0.5초마다 한 단씩 굴러 커진다
    // (1단 눈덩이 → 2단 → 모자 쓴 3단). 손을 떼면 그 크기로 선다. 최대 3개, 넘으면 오래된 것부터 녹는다
    func holdPile(at p: CGPoint) -> Bool {
        if building == nil, let s = standerAt(p), s.name == "snowman" { melt(s); return true }   // 눈사람을 꾹 = 녹이기
        guard building == nil, standerAt(p) == nil, onPile(p) else { return false }
        let i = Int(p.x / pilePx), r = 22
        let span = max(0, i - r)...min(heights.count - 1, i + r)
        let avg = CGFloat(span.reduce(0) { $0 + heights[$1] }) / CGFloat(span.count)
        if avg < 12 {   // 24pt 보다 얕으면 아직 못 만든다
            let spot = stand(flakeImages[0], px: 1, at: p.x, name: "hint")
            standers.removeAll { $0 === spot }
            say("Need a bit more snow ⛄", on: spot)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { spot.removeFromSuperlayer() }
            return true
        }
        let snowmen = standers.filter { $0.name == "snowman" }
        if snowmen.count >= 3, let old = snowmen.first {
            melt(old)   // 조용히 없애면 왜 사라졌는지 모른다 → 인사하고 녹는 모습을 보여 준다
        }
        buildSpan = span
        scoop()
        let man = addMan(at: p.x, tier: 1, kind: 0, nose: false)
        building = man
        popIn(man)
        let roll = CAKeyframeAnimation(keyPath: "transform.rotation.z")   // 데굴데굴
        roll.values = [0, -0.22, 0, 0.22, 0]; roll.duration = 0.5; roll.repeatCount = .infinity
        man.add(roll, forKey: "roll")
        buildTimer?.invalidate()
        buildTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.growMan() }
        return true
    }

    func scoop() {
        for j in buildSpan where j < heights.count { heights[j] = Int(CGFloat(heights[j]) * 0.8) }
        redraw()
    }

    func growMan() {
        guard let man = building else { buildTimer?.invalidate(); return }
        let tier = manTier(man) + 1
        var kind = 0
        if tier == 3 {   // 열 번에 한 번쯤 특별한 눈사람: 산타 모자 5% · 고양이 귀 4% · 황금 1%
            let r = Int.random(in: 0..<100)
            kind = r == 0 ? 3 : r <= 4 ? 2 : r <= 9 ? 1 : 0
        }
        scoop()
        man.setValue(tier, forKey: "tier")
        man.setValue(kind, forKey: "kind")
        setMan(man, look: 0, blink: false, wave: false)
        popIn(man)
        puff(at: CGPoint(x: man.position.x, y: man.position.y - man.bounds.height / 2 + 6))
        if tier >= 3 { finishBuild() }
    }

    func finishBuild() {
        guard let man = building else { return }
        building = nil
        buildTimer?.invalidate()
        man.removeAnimation(forKey: "roll")
        let tier = manTier(man), kind = manKind(man)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak man] in
            guard let self = self, let man = man else { return }
            self.wave(man)
            if kind > 0 {
                self.puff(at: man.position)
                self.say(collect(["", "man-santa", "man-cat", "man-gold"][kind]), on: man)
            } else {
                self.say(tier == 1 ? "Hi! I'm a snowball ⚪" : tier == 2 ? "Hi! ⛄ (hold longer for a hat 🎩)" : "Hi! ⛄", on: man)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self, weak man] in
                guard let self = self, let man = man, man.superlayer != nil, !self.manNose(man) else { return }
                man.sublayers?.forEach { $0.removeFromSuperlayer() }
                self.say("Where's my nose? 🥕", on: man)
            }
        }
        save()
    }

    // "Bye! 👋" 하고 스르르 주저앉아 녹고, 하늘색 웅덩이가 잠깐 남았다 사라진다
    func melt(_ l: CALayer, quiet: Bool = false) {
        guard standers.contains(where: { $0 === l }) else { return }
        standers.removeAll { $0 === l }
        save()
        if !quiet { wave(l); say(["Bye! 👋", "See you next snow! ❄️", "Melting… 💧"].randomElement()!, on: l) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (quiet ? 0 : 1.1)) { [weak self] in
            guard let self = self, let root = self.contentView?.layer else { l.removeFromSuperlayer(); return }
            l.sublayers?.forEach { $0.removeFromSuperlayer() }
            let h = l.bounds.height
            let puddle = CALayer()
            puddle.bounds = CGRect(x: 0, y: 0, width: l.bounds.width * 1.3, height: 7)
            puddle.cornerRadius = 3.5
            puddle.backgroundColor = CGColor(red: 0.72, green: 0.84, blue: 0.96, alpha: 0.9)
            puddle.position = CGPoint(x: l.position.x, y: l.position.y - h / 2 + 3)
            puddle.opacity = 0
            root.insertSublayer(puddle, below: l)
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                l.removeFromSuperlayer()
                let dry = CABasicAnimation(keyPath: "opacity")
                dry.fromValue = 0.9; dry.toValue = 0; dry.duration = 1.4
                dry.isRemovedOnCompletion = false; dry.fillMode = .forwards
                CATransaction.begin()
                CATransaction.setCompletionBlock { puddle.removeFromSuperlayer() }
                puddle.add(dry, forKey: "dry")
                CATransaction.commit()
            }
            let squash = CABasicAnimation(keyPath: "transform.scale.y")
            squash.toValue = 0.08
            let sink = CABasicAnimation(keyPath: "position.y")
            sink.byValue = -h * 0.46
            let widen = CABasicAnimation(keyPath: "transform.scale.x")
            widen.toValue = 1.25
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.toValue = 0.3
            let show = CABasicAnimation(keyPath: "opacity")
            show.fromValue = 0; show.toValue = 0.9; show.duration = 0.9
            show.isRemovedOnCompletion = false; show.fillMode = .forwards
            puddle.add(show, forKey: "show")
            let g = CAAnimationGroup()
            g.animations = [squash, sink, widen, fade]
            g.duration = 0.9
            g.timingFunction = CAMediaTimingFunction(name: .easeIn)
            g.isRemovedOnCompletion = false; g.fillMode = .forwards
            l.add(g, forKey: "melt")
            CATransaction.commit()
        }
    }

    // 메뉴 'Melt all snowmen' — 왼쪽부터 차례로 녹는다
    func meltAll() {
        if let b = building { finishBuild(); _ = b }
        let men = standers.filter { $0.name == "snowman" }.sorted { $0.position.x < $1.position.x }
        for (i, m) in men.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) { [weak self] in self?.melt(m) }
        }
    }

    func popIn(_ l: CALayer) {
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.3, 1.15, 1]; pop.keyTimes = [0, 0.7, 1]; pop.duration = 0.35
        l.add(pop, forKey: "pop")
    }

    func addMan(at x: CGFloat, tier: Int, kind: Int, nose: Bool = true) -> CALayer {
        let l = stand(manImage(tier: tier, kind: kind, look: 0, blink: false, wave: false, nose: nose), px: 3, at: x, name: "snowman")
        l.setValue(tier, forKey: "tier")
        l.setValue(kind, forKey: "kind")
        l.setValue(nose, forKey: "nose")
        return l
    }

    func manNose(_ l: CALayer) -> Bool { l.value(forKey: "nose") as? Bool ?? true }

    // 코 없는 눈사람이 있으면 20–60초 뒤 쌓인 눈 위에 당근 하나 (독 앞·다른 것 옆은 피한다)
    func dropCarrot() {
        let w = frame.width
        let half = dockBand > 0 ? dockWidth() / 2 + 20 : 0
        for _ in 0..<12 {
            let x = CGFloat.random(in: 30...(w - 30))
            if abs(x - w / 2) < half { continue }
            if standers.contains(where: { abs($0.position.x - x) < 50 }) { continue }
            let c = stand(carrotSprite, px: 3, at: x, name: "carrot")
            popIn(c)
            return
        }
    }

    // 당근을 누르면 가장 가까운 코 없는 눈사람에게 날아가 코가 된다
    func pickCarrot(_ c: CALayer) {
        standers.removeAll { $0 === c }
        puff(at: c.position)
        let noseless = standers.filter { $0.name == "snowman" && !manNose($0) && $0 !== building }
        guard let man = noseless.min(by: { abs($0.position.x - c.position.x) < abs($1.position.x - c.position.x) }) else {
            say("Crunch! 🥕", on: c)
            c.contents = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { c.removeFromSuperlayer() }
            return
        }
        let from = c.position, to = CGPoint(x: man.position.x, y: man.position.y + man.bounds.height * 0.1)
        let fly = CAKeyframeAnimation(keyPath: "position")
        let path = CGMutablePath()
        path.move(to: from)
        path.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + 70))
        fly.path = path
        fly.duration = 0.55
        fly.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1; shrink.toValue = 0.4; shrink.duration = 0.55
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak man] in
            c.removeFromSuperlayer()
            guard let self = self, let man = man, man.superlayer != nil else { return }
            man.setValue(true, forKey: "nose")
            man.setValue(nil, forKey: "manFrame")
            self.setMan(man, look: 0, blink: false, wave: false)
            self.popIn(man)
            self.wave(man)
            man.sublayers?.forEach { $0.removeFromSuperlayer() }
            self.say(["Thank you! 🥕", "My nose! 😆", "Now I can smell the snow! 👃"].randomElement()!, on: man)
            self.save()
        }
        c.position = to
        c.transform = CATransform3DMakeScale(0.4, 0.4, 1)
        c.add(fly, forKey: "fly")
        c.add(shrink, forKey: "shrink")
        CATransaction.commit()
    }

    func manTier(_ l: CALayer) -> Int { l.value(forKey: "tier") as? Int ?? 3 }
    func manKind(_ l: CALayer) -> Int { l.value(forKey: "kind") as? Int ?? 0 }

    // 그림 바꾸기 — 크기가 바뀌면 발이 눈 위에 붙어 있게 높이도 다시 잡는다
    func setMan(_ l: CALayer, look: Int, blink: Bool, wave: Bool) {
        let tier = manTier(l), kind = manKind(l), nose = manNose(l)
        let key = "\(tier)\(kind)\(look)\(blink)\(wave)\(nose)"
        guard l.value(forKey: "manFrame") as? String != key else { return }
        l.setValue(key, forKey: "manFrame")
        let img = manImage(tier: tier, kind: kind, look: look, blink: blink, wave: wave, nose: nose)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        l.contents = img
        let size = CGSize(width: CGFloat(img.width) * 3, height: CGFloat(img.height) * 3)
        if l.bounds.size != size {
            l.bounds = CGRect(origin: .zero, size: size)
            l.position.y = surfaceY(l.position.x) + size.height / 2 - 3
        }
        CATransaction.commit()
    }

    // 손 흔들기 (3단은 오른팔을 흔들고, 작은 눈사람은 통통 뛴다)
    func wave(_ l: CALayer) {
        l.setValue(CACurrentMediaTime() + 1.6, forKey: "waveUntil")
        if manTier(l) < 3 && l.name == "snowman" && l !== building {
            let hop = CAKeyframeAnimation(keyPath: "position.y")
            hop.values = [0, 9, 0, 6, 0]; hop.isAdditive = true; hop.duration = 0.7
            l.add(hop, forKey: "hop")
        }
    }

    // 0.15초마다: 커서 쪽을 쳐다보고, 가끔 깜빡이고, 커서가 처음 다가오면 손을 흔든다. 가끔 눈사람끼리 수다
    func lifeTick() {
        guard !paused else { return }
        let men = standers.filter { $0.name == "snowman" }
        guard !men.isEmpty else { return }
        let now = CACurrentMediaTime()
        let m = NSEvent.mouseLocation
        let c = CGPoint(x: m.x - frame.minX, y: m.y - frame.minY)
        for l in men {
            let dx = c.x - l.position.x
            let near = abs(dx) < 260 && c.y > -10 && c.y < 280
            let look = near ? (dx < -14 ? -1 : dx > 14 ? 1 : 0) : 0
            if near, l.value(forKey: "near") as? Bool != true, now > (l.value(forKey: "waveCool") as? Double ?? 0), l !== building {
                wave(l)
                l.setValue(now + 25, forKey: "waveCool")
            }
            l.setValue(near, forKey: "near")
            var blinkUntil = l.value(forKey: "blinkUntil") as? Double ?? 0
            if now > blinkUntil + 0.6 && Double.random(in: 0..<1) < 0.03 {
                blinkUntil = now + 0.14
                l.setValue(blinkUntil, forKey: "blinkUntil")
            }
            if Double.random(in: 0..<1) < 0.0015 { wave(l) }   // 가끔 혼자서도
            let waving = now < (l.value(forKey: "waveUntil") as? Double ?? 0)
            setMan(l, look: look, blink: now < blinkUntil, wave: waving && manTier(l) == 3 && Int(now * 4) % 2 == 0)
        }
        guard building == nil, plow == nil else { return }
        let wantsCarrot = men.contains { !manNose($0) } && !standers.contains { $0.name == "carrot" }
        if !wantsCarrot { nextCarrot = 0 }
        else if nextCarrot == 0 { nextCarrot = now + Double.random(in: 20...60) }
        else if now > nextCarrot { nextCarrot = 0; dropCarrot() }
        if now > nextChat {
            nextChat = now + Double.random(in: 90...200)
            if men.count >= 2 { chat(men) }
        }
    }

    // 눈사람끼리 수다: 하나가 말하면 2.6초 뒤 다른 하나가 받는다
    func chat(_ men: [CALayer]) {
        var two = Array(men.shuffled().prefix(2))
        guard two.count == 2 else { return }
        // 스카프 얘기는 스카프를 한 눈사람(2·3단)만 꺼낸다 — 1단 눈덩이는 목이 없다
        var lines = manChats
        if manTier(two[0]) < 2 {
            if manTier(two[1]) >= 2 { two.swapAt(0, 1) } else { lines = lines.filter { !$0.0.contains("scarf") } }
        }
        let line = lines.randomElement()!
        wave(two[0]); say(line.0, on: two[0])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self, weak b = two[1]] in
            guard let self = self, let b = b, self.standers.contains(where: { $0 === b }) else { return }
            self.wave(b); self.say(line.1, on: b)
        }
    }

    // 제설차를 폴짝 뛰어 넘긴다: 올라가 있는 동안 차가 밑으로 지나간다
    func dodge(_ l: CALayer, truck: CGSize, speed: CGFloat) {
        let rise = 0.28, fall = 0.3
        let hold = Double((75 + l.bounds.width + truck.width + 10) / speed) - rise
        let total = rise + hold + fall
        let h = truck.height + 12
        let jump = CAKeyframeAnimation(keyPath: "position.y")
        jump.values = [0, h, h + 4, h, 0]
        jump.keyTimes = [0, NSNumber(value: rise / total), NSNumber(value: (rise + hold / 2) / total), NSNumber(value: (rise + hold) / total), 1]
        jump.isAdditive = true
        jump.duration = total
        l.add(jump, forKey: "dodge")
        l.setValue(CACurrentMediaTime() + total, forKey: "waveUntil")
        if l.frame.maxY + h + 44 <= frame.height {   // 뛰어오른 높이에서도 말풍선이 창 안에 들어갈 때만
            say(["Not me!! 😱", "Whoa! 🙀", "Hop! 🦘"].randomElement()!, on: l)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.2) { [weak self, weak l] in
            guard let self = self, let l = l, l.superlayer != nil else { return }
            l.sublayers?.forEach { $0.removeFromSuperlayer() }
            self.say(["Phew! 😅", "That was close! 😮‍💨", "Still here! ⛄"].randomElement()!, on: l)
        }
    }

    func greet(_ l: CALayer) {
        wave(l)
        let lines: [String]
        if !manNose(l) {
            say(["Have you seen a carrot? 🥕", "I lost my nose… 👃", "Find me a carrot? 🥕"].randomElement()!, on: l)
            return
        }
        switch (manTier(l), manKind(l)) {
        case (_, 1): lines = ["Ho ho ho! 🎅", "I borrowed Santa's hat 🎅", "Been good this year? 🎁"]
        case (_, 2): lines = ["Meow! 🐱", "Purr… it's cold 🐾", "Got any fish? 🐟"]
        case (_, 3): lines = ["I'm shiny! ✨", "Solid gold snow 🌟", "Make a wish! 🌟"]
        case (1, _): lines = ["I'm still small! ⚪", "Roll me bigger next time! ⚪"]
        case (2, _): lines = ["Almost tall enough for a hat 🎩", "Hello there! ⛄"]
        default: lines = ["Merry Christmas! 🎄", "Thanks for building me! ⛄", "I like it here ❄️"]
        }
        say(lines.randomElement()!, on: l)
    }

    // 크리스마스 아침: 쌓인 눈 위에 선물상자 여섯 개. 누르면 퐁 열린다
    func placeGifts() {
        guard !standers.contains(where: { $0.name == "gift" }) else { return }
        let w = frame.width
        let half = dockBand > 0 ? dockWidth() / 2 + 20 : 0
        let side = w / 2 - half   // 독 왼쪽·오른쪽에 남는 폭
        for k in 0..<6 {
            let x: CGFloat
            if side >= 90 {       // 왼쪽 3개 · 오른쪽 3개
                let along = side * (CGFloat(k % 3) + CGFloat.random(in: 0.25...0.75)) / 3
                x = k < 3 ? along : w - along
            } else {
                x = w * (CGFloat(k) + CGFloat.random(in: 0.25...0.75)) / 6
            }
            _ = stand(giftSprites[k % giftSprites.count], px: 3.5, at: x, name: "gift")
        }
    }

    func openGift(_ g: CALayer) {
        puff(at: g.position)
        say(["Merry Christmas! 🎁", "A warm hug for you! 🤗", "Cookies! 🍪", "A little joy, just for you ✨",
             "Ho ho ho! 🎅", "You're on the nice list! 📜"].randomElement()!, on: g)
        g.contents = nil   // 상자는 사라지고 말풍선만 잠깐
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self, weak g] in
            guard let self = self, let g = g else { return }
            self.standers.removeAll { $0 === g }
            g.removeFromSuperlayer()
        }
    }
}

// ── 메뉴에서 바로 업데이트 ──────────────
// 깃허브 최신 릴리스(태그 vX.Y.Z)가 이 버전보다 높으면 ❄︎ 메뉴 맨 위에 'Update to …' 가 뜬다.
// ⚠ 릴리스를 낼 때마다 이 값과 태그를 같이 올릴 것 (같은 태그에 파일만 바꾸면 업데이트로 안 잡힌다)
let appVersion = "1.3.2"
// 업데이트한 사람이 처음 켤 때 한 번 보여 주는 안내 (릴리스마다 새로 쓴다. 작은 수정이면 "" 로 비워 두면 아무것도 안 뜬다)
let whatsNew = ""
let whatsNew130 = """
💡 Christmas lights twinkle along the top of your screen

⛄ Press and hold the snow pile to build a snowman — keep holding and it grows taller. Once in a while you'll get a special one!

🥕 New snowmen have no nose. Watch for a carrot in the snow and click it

💧 Press and hold a snowman to melt it, or use Melt all snowmen in the ❄︎ menu

⭐ Rare visitors: a golden snowflake, a polar bear, an owl, an Arctic fox and an elf. Click them to collect (❄︎ → Rare finds)

🎁 An advent calendar opens in the ❄︎ menu on December 1, with surprises on Christmas Eve, Christmas Day and New Year's

🙈 Need a break? ❄︎ → Hide for… 30 minutes or 1 hour
"""
// 확인용: XMASSNOW_FEED 로 가짜 릴리스 정보를 줄 수 있다 (그때는 그 주소에서 받는 것도 허용)
let testFeed = ProcessInfo.processInfo.environment["XMASSNOW_FEED"]
let releaseFeed = URL(string: testFeed ?? "https://api.github.com/repos/imhuijeong92-ui/xmas-snow/releases/latest")!
let releasePage = URL(string: "https://github.com/imhuijeong92-ui/xmas-snow/releases/latest")!
// 이 저장소 릴리스 파일만 받는다 (호스트·경로를 따로 확인 — 접두어만 보면 다른 주소가 끼어들 수 있다)
func isOurDownload(_ u: URL) -> Bool {
    guard !u.path.contains("..") else { return false }
    if testFeed != nil { return u.scheme == "http" && u.host == "127.0.0.1" }
    return u.scheme == "https" && u.host == "github.com" && u.path.hasPrefix("/imhuijeong92-ui/xmas-snow/releases/download/")
}

// "1.10.0" > "1.9.2" 처럼 숫자 단위로 비교
func isNewer(_ a: String, than b: String) -> Bool {
    let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
    for i in 0..<max(x.count, y.count) {
        let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
        if p != q { return p > q }
    }
    return false
}

// ── 이스터에그 ──────────────
// 빼꼼 나온 루돌프를 5번 연달아 누르면 한 줄씩 들려주는 비밀 이야기 (누를 때마다 다음 이야기)
let deerStories: [[String]] = [
    ["Psst… my nose isn't a light bulb.", "It glows when someone I love is near.", "…it's glowing right now. ❤️"],
    ["I practice landing on your roof every year.", "Santa says I'm getting better.", "Last year I only bumped one chimney."],
    ["I keep one snowflake from every Christmas.", "This year's is going to be yours. ❄️"],
    ["Santa reads every letter twice.", "Once for the wish.", "Once for the person who wrote it. 💌"],
]
// ❄︎ 메뉴의 'A little story' — 고를 때마다 다음 이야기 (처음 켰을 때 한 번은 저절로 뜬다)
let littleStories: [(title: String, text: String)] = [
    ("The Smallest Snowflake", "The smallest snowflake was scared to fall.\n\"What if no one ever sees me?\"\n\nIt took a deep breath and let go…\nand landed right on your screen.\n\nYou saw it. ✨"),
    ("The Snowman's Scarf", "A snowman saw a little penguin shivering in the wind.\nHe took off his red scarf and wrapped it around her.\n\n\"Won't you be cold?\" asked the penguin.\n\"I'm a snowman,\" he laughed.\n\"But my heart feels warm now.\" 🧣"),
    ("Santa's Last Cookie", "After the very last chimney, Santa sat down on a quiet rooftop.\nHe took out one cookie he had saved all night.\n\n\"This one,\" he told Rudolph, \"is for me.\"\n\nResting is a gift, too. 🍪"),
]
// 다음 차례 번호를 저장해 두고 하나씩 넘긴다
func nextIndex(_ key: String, count: Int) -> Int {
    let i = UserDefaults.standard.integer(forKey: key) % count
    UserDefaults.standard.set((i + 1) % count, forKey: key)
    return i
}

// 지나가는 산타가 알려 주는 크리스마스 디데이 (12/26 부터는 다음 해 크리스마스까지)
func christmasCountdown(_ now: Date = appNow()) -> String {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    var xmas = cal.date(from: DateComponents(year: cal.component(.year, from: today), month: 12, day: 25))!
    if xmas < today { xmas = cal.date(byAdding: .year, value: 1, to: xmas)! }
    let days = cal.dateComponents([.day], from: today, to: xmas).day ?? 0
    switch days {
    case 0: return "Merry Christmas! 🎄"
    case 1: return "It's Christmas Eve! Big night tonight 🎅"
    default: return "\(days) days until Christmas! 🎄"
    }
}

// 테두리 없는 흰 둥근 말풍선을 sprite 위(자리 없으면 아래)에 붙이고 stay 초 뒤 사라지게 한다
@discardableResult
func makeBubble(_ message: String, on sprite: CALayer, root: CALayer, scale: CGFloat, stay: Double = 2.5) -> CALayer {

    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let base = NSFont.systemFont(ofSize: 15, weight: .heavy)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 15) } ?? base
    let text = NSAttributedString(string: message, attributes: [
        .font: font,
        .foregroundColor: NSColor(red: 0.75, green: 0.12, blue: 0.2, alpha: 1)])
    let ts = text.size()
    let padX: CGFloat = 12, padY: CGFloat = 6

    // 테두리 없는 흰 둥근 말풍선 + 옅은 그림자 (밝은 창 위에서도 떠 보이게)
    let box = CALayer()
    box.anchorPoint = CGPoint(x: 0, y: 0)
    box.bounds = CGRect(x: 0, y: 0, width: ceil(ts.width) + padX * 2, height: ceil(ts.height) + padY * 2)
    box.backgroundColor = white
    box.cornerRadius = box.bounds.height / 2
    box.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    box.shadowOpacity = 0.25
    box.shadowRadius = 4
    box.shadowOffset = CGSize(width: 0, height: -1)
    let label = CATextLayer()
    label.string = text
    label.frame = CGRect(x: padX, y: padY - 1, width: ceil(ts.width) + 2, height: ceil(ts.height))
    label.contentsScale = scale
    box.addSublayer(label)

    // 위에 자리가 없으면(눈 높이 1/5 등) 산타 아래에 띄운다
    let s = sprite.bounds.size
    let sf = sprite.presentation()?.frame ?? sprite.frame
    let above = sf.maxY + 14 + box.bounds.height <= root.bounds.height
    // 위·아래 다 자리가 없으면(눈 높이 1/8 등) 캐릭터 옆에 띄운다
    let side = !above && sf.minY - 14 - box.bounds.height < 0
    // 화면 왼쪽·오른쪽 끝에서도 말풍선이 잘리지 않게 안쪽으로 민다
    let bx = min(max(side ? s.width + 12 : 6, 8 - sf.minX), root.bounds.width - 8 - box.bounds.width - sf.minX)
    let by = side ? min(max((s.height - box.bounds.height) / 2, 4 - sf.minY), root.bounds.height - 4 - box.bounds.height - sf.minY)
                  : (above ? s.height + 14 : -14 - box.bounds.height)
    box.position = CGPoint(x: bx, y: by)
    // 말꼬리 = 산타 쪽 모서리에 붙은 흰 마름모
    let tail = CALayer()
    tail.backgroundColor = white
    tail.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
    // 꼬리는 말풍선이 화면 끝에서 밀려나도 캐릭터 쪽을 가리키게
    tail.position = side ? CGPoint(x: bx > 0 ? 1 : box.bounds.width - 1, y: box.bounds.height / 2)
                         : CGPoint(x: min(max(14, min(20, s.width / 2) - bx), box.bounds.width - 14), y: above ? 1 : box.bounds.height - 1)
    tail.setAffineTransform(CGAffineTransform(rotationAngle: .pi / 4))
    box.insertSublayer(tail, below: label)
    sprite.addSublayer(box)

    let pop = CAKeyframeAnimation(keyPath: "transform.scale")
    pop.values = [0.3, 1.15, 1]
    pop.keyTimes = [0, 0.6, 1]
    pop.duration = 0.25
    box.add(pop, forKey: "pop")

    DispatchQueue.main.asyncAfter(deadline: .now() + stay) { [weak box] in
        guard let box = box else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { box.removeFromSuperlayer() }
        box.opacity = 0
        CATransaction.commit()
    }
    return box
}

@discardableResult
func run(_ tool: String, _ args: [String]) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [SnowWindow] = []
    var piles: [PileWindow] = []
    var amountFactor: CGFloat { [0.25, 1, 2][amount.rawValue] }
    var status: NSStatusItem!
    var amount = Amount(rawValue: UserDefaults.standard.integer(forKey: "amount")) ?? .light
    var santaOn = UserDefaults.standard.object(forKey: "santa") as? Bool ?? true
    var snowmanOn = UserDefaults.standard.object(forKey: "snowman") as? Bool ?? true
    var penguinOn = UserDefaults.standard.object(forKey: "penguin") as? Bool ?? true
    var starOn = UserDefaults.standard.object(forKey: "shootingStar") as? Bool ?? true
    var starTimer: Timer?
    var santaTimer: Timer?
    var visitorTimer: Timer?
    var hideTimer: Timer?
    var dayTimer: Timer?
    var lastDay = ""

    func applicationWillTerminate(_ n: Notification) { piles.forEach { $0.save() } }

    func applicationDidFinishLaunching(_ n: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "❄︎"
        buildMenu()
        if stageMode { bandIndex = 4; santaSpeedIndex = 2; amount = .normal }
        if deskBackdrop != nil { bandIndex = 0; santaSpeedIndex = 2; amount = .normal }
        rebuild()
        if stageMode { stage(); return }
        if let path = deskBackdrop { deskStage(path); return }
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        scheduleSanta(first: true)
        scheduleVisitor(first: true)
        scheduleStar(first: true)
        NotificationCenter.default.addObserver(forName: collectedChanged, object: nil, queue: .main) { [weak self] _ in self?.buildMenu() }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.applyHide() }
        checkDay()
        dayTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.checkDay() }
        // 처음 켰을 때(새 버전으로 처음 켜졌을 때 포함) 한 번만 짧은 동화를 보여 준다 — 메뉴에 이야기책이 있다는 걸 알게
        // 업데이트해서 처음 켜졌으면 동화 대신 '새로 생긴 것' 안내를 한 번 보여 준다 (1.3.0 전에서 오면 1.3 안내, 작은 수정이면 아무것도)
        let shownVersion = UserDefaults.standard.string(forKey: "storyShownVersion")
        if shownVersion != appVersion {
            UserDefaults.standard.set(appVersion, forKey: "storyShownVersion")
            if let old = shownVersion, isNewer(appVersion, than: old) {
                let note = !whatsNew.isEmpty ? whatsNew : isNewer("1.3.0", than: old) ? whatsNew130 : ""
                if !note.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.say("What's new in Xmas Snow \(appVersion) ✨", note) }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.tellStory(hint: true) }
            }
        }
        // 새 버전 확인 = 켜고 1분 뒤, 그 뒤로 12시간마다 (깃허브에 버전만 묻는다)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.checkForUpdate() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 12 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdate() }
        // 확인용: --demo 로 켜면 바로 산타가 날고 3초 뒤 말풍선·선물을 띄운다
        if CommandLine.arguments.contains("--demo2") {  // 눈사람·펭귄 + 간식 잔뜩
            windows.forEach { w in w.walk("snowman"); w.walk("penguin"); w.treatDebt = 6 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.windows.forEach { w in w.actors.forEach { w.showBubble(on: $0) } } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.windows.forEach { w in w.treatLive.forEach { w.pop($0) } } }
        }
        if CommandLine.arguments.contains("--demo3") {  // 별똥별 잡기
            windows.forEach { $0.shootStar() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.windows.forEach { w in w.actors.forEach { w.catchStar($0) } } }
        }
        if CommandLine.arguments.contains("--demo4") {  // 눈 더미 채워 두고 제설차
            piles.forEach { p in p.carry = 9000; p.grow(0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.piles.forEach { $0.puff(at: CGPoint(x: 300, y: 30)); $0.hideDeer() }; self.callPlow() }
        }
        if CommandLine.arguments.contains("--demo8") {  // 1.3 시험: 드문 손님·황금 눈송이·눈사람·선물·불꽃놀이
            piles.forEach { p in p.carry = 9000; p.grow(0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ["bear", "owl", "fox", "elf"].forEach { self.callRare($0) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.piles.forEach { p in _ = p.holdPile(at: CGPoint(x: p.frame.width * 0.3, y: 10)) } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.piles.forEach { $0.placeGifts() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.windows.forEach { $0.fireworks(seconds: 8) } }
        }
        if CommandLine.arguments.contains("--demo9") {  // 눈사람 놀이: 크기별·특별한 눈사람 · 꾹 눌러 키우기 · 수다 · 제설차 피하기
            piles.forEach { p in p.carry = 9000; p.grow(0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.piles.forEach { p in
                let w = p.frame.width
                for (i, (t, k)) in [(1, 0), (2, 0), (3, 1), (3, 2), (3, 3)].enumerated() {
                    _ = p.addMan(at: i < 3 ? w * (0.06 + 0.08 * CGFloat(i)) : w * (0.72 + 0.08 * CGFloat(i - 3)), tier: t, kind: k, nose: i != 1)
                }
                _ = p.holdPile(at: CGPoint(x: w * 0.94, y: 10))
            } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.piles.forEach { $0.chat($0.standers.filter { $0.name == "snowman" }) } }
            if CommandLine.arguments.contains("--melt") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.piles.forEach { p in
                    if let m = p.standers.first(where: { $0.name == "snowman" }) { _ = p.holdPile(at: m.position) } } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 9) { self.meltSnowmen() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 7) { self.piles.forEach { $0.dropCarrot() } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.piles.forEach { p in
                    if let c = p.standers.first(where: { $0.name == "carrot" }) { p.pickCarrot(c) } } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.piles.forEach { $0.hideDeer() }; self.callPlow() }
            }
        }
        if CommandLine.arguments.contains("--demo6") {  // 업데이트: XMASSNOW_FEED 의 가짜 릴리스로 바로 설치까지
            checkForUpdate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.installUpdate() }
        }
        if CommandLine.arguments.contains("--demo5") {  // 이스터에그: 루돌프 이야기 → 산타 디데이 → 숨은 동화
            piles.forEach { p in p.carry = 9000; p.grow(0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.piles.forEach { $0.tellStory() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { self.callSanta() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 22) { self.showStory() }
        }
        if CommandLine.arguments.contains("--demo") {
            callSanta()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.windows.forEach { w in w.actors.forEach { w.showBubble(on: $0); w.dropGifts(from: $0) } } }
        }
    }

    // README 미리보기: 첫 화면에서 산타 → 클릭 → 눈사람·펭귄 → 별똥별 잡기 → 간식 터뜨리기
    func stage() {
        guard let w = windows.first else { return }
        func at(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }
        w.treatDebt = 4
        // 쌓인 눈은 처음부터 가득 (루돌프는 장면에 맞춰 부른다)
        if let p = piles.first { p.lastPeek = Date(); p.carry = 9000; p.grow(0) }
        at(1.0) { w.flySanta(talk: true) }   // 산타 디데이
        at(0.3) { w.walk("snowman") }
        at(4.6) { w.actors.filter { $0.name == "snowman" }.forEach { w.showBubble(on: $0); w.dropGifts(from: $0) } }
        at(4.0) { w.walk("penguin") }
        at(6.0) { w.shootStar(fromX: 120, rightward: true) }
        at(7.0) { w.actors.filter { $0.name == "shootingStar" }.forEach { w.catchStar($0) } }
        at(7.6) { w.actors.filter { $0.name == "penguin" }.forEach { w.showBubble(on: $0) } }
        for (i, t) in [5.0, 8.4, 9.3].enumerated() {
            at(t) { if let x = w.treatLive.dropFirst(i % 2).first { w.pop(x) } }
        }
        // 루돌프가 빼꼼 → 루돌프를 누르면 퐁 → 산타 제설차가 쌓인 눈을 치운다
        if let p = piles.first {
            at(9.0) { p.peek() }
            at(11.5) {
                if let d = p.deer { p.puff(at: (d.presentation() ?? d).position) }
                p.hideDeer()
                p.sendPlow()
            }
        }
    }

    // 눈사람·펭귄(켠 것만) = 켜고 1분 뒤, 그 뒤로 3–7분마다 아무 모니터에서
    // README 두 번째 미리보기: 가짜 업무 화면 위 1/8 띠에 눈 → 산타 디데이 → 루돌프 빼꼼 → 제설차
    var backdrop: NSWindow?
    func deskStage(_ path: String) {
        guard let img = NSImage(contentsOfFile: path), let s = NSScreen.screens.first, let w = windows.first else { return }
        let b = NSWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
        b.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)  // 눈 창 바로 아래
        let v = NSImageView(frame: NSRect(origin: .zero, size: s.frame.size))
        v.image = img
        v.imageScaling = .scaleAxesIndependently
        b.contentView = v
        b.orderFrontRegardless()
        backdrop = b
        func at(_ t: Double, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: f) }
        w.treatDebt = 3
        if let p = piles.first { p.lastPeek = Date(); p.carry = 9000; p.grow(0) }
        at(1.0) { w.flySanta(talk: true) }
        if let p = piles.first {
            at(6.5) { p.peek() }
            at(9.5) {
                if let d = p.deer { p.puff(at: (d.presentation() ?? d).position) }
                p.hideDeer()
                p.sendPlow()
            }
        }
    }

    func scheduleVisitor(first: Bool = false) {
        visitorTimer?.invalidate()
        visitorTimer = Timer.scheduledTimer(withTimeInterval: first ? 60 : Double.random(in: 180...420), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let on = [("snowman", self.snowmanOn), ("penguin", self.penguinOn)].filter { $0.1 }.map { $0.0 }
            if !on.isEmpty && Int.random(in: 0..<100) < 12 { self.callRare(nil) }   // 가끔 드문 손님
            else if let who = on.randomElement() { self.callVisitor(who) }
            self.scheduleVisitor()
        }
    }

    // 별똥별 = 켜고 40초 뒤, 그 뒤로 1–3분마다 아무 모니터에서 (짧아서 자주)
    func scheduleStar(first: Bool = false) {
        starTimer?.invalidate()
        starTimer = Timer.scheduledTimer(withTimeInterval: first ? 40 : Double.random(in: 60...180), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.starOn { self.callStar() }
            self.scheduleStar()
        }
    }

    @objc func callStar() { windows.randomElement()?.shootStar() }

    @objc func toggleStar() {
        starOn.toggle()
        UserDefaults.standard.set(starOn, forKey: "shootingStar")
        buildMenu()
    }

    // 산타 = 켜고 20초 뒤 한 번, 그 뒤로는 5–12분마다
    func scheduleSanta(first: Bool = false) {
        santaTimer?.invalidate()
        guard santaOn else { return }
        let wait = first ? 20 : monthDay() == (12, 24) ? Double.random(in: 120...300) : Double.random(in: 300...720)  // 이브엔 자주
        santaTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            self?.callSanta()
            self?.scheduleSanta()
        }
    }

    // 왼쪽 모니터부터 오른쪽 모니터로 이어서 가로지른다
    var santaFlying = false
    @objc func callSanta() {
        guard !santaFlying else { return }
        santaFlying = true
        fly(windows.sorted { $0.frame.minX < $1.frame.minX }, 0)
    }

    func fly(_ order: [SnowWindow], _ i: Int) {
        guard i < order.count else { santaFlying = false; return }
        // 디데이는 한 번만 — 커서가 있는 화면(지금 보고 있을 화면)을 지날 때
        let m = NSEvent.mouseLocation
        let talk = order.contains { $0.screen?.frame.contains(m) == true } ? order[i].screen?.frame.contains(m) == true : i == 0
        order[i].flySanta(talk: talk) { [weak self] in self?.fly(order, i + 1) }
    }

    var shownWindows: [SnowWindow] { windows.filter { !$0.paused }.isEmpty ? windows : windows.filter { !$0.paused } }

    func callVisitor(_ who: String) {
        shownWindows.randomElement()?.walk(who)
    }

    @objc func callSnowman() { callVisitor("snowman") }
    @objc func callPenguin() { callVisitor("penguin") }

    @objc func toggleSanta() {
        santaOn.toggle()
        UserDefaults.standard.set(santaOn, forKey: "santa")
        scheduleSanta()
        buildMenu()
    }

    @objc func toggleSnowman() {
        snowmanOn.toggle()
        UserDefaults.standard.set(snowmanOn, forKey: "snowman")
        buildMenu()
    }

    @objc func togglePenguin() {
        penguinOn.toggle()
        UserDefaults.standard.set(penguinOn, forKey: "penguin")
        buildMenu()
    }

    @objc func toggleTreat(_ sender: NSMenuItem) {
        if treatsOff.contains(sender.tag) { treatsOff.remove(sender.tag) } else { treatsOff.insert(sender.tag) }
        UserDefaults.standard.set(Array(treatsOff), forKey: "treatsOff")
        buildMenu()
    }

    @objc func pickFallSpeed(_ sender: NSMenuItem) {
        fallSpeedIndex = sender.tag
        UserDefaults.standard.set(fallSpeedIndex, forKey: "fallSpeed")
        buildMenu()
    }

    // 메뉴: 항목이 많아 하위 메뉴로 묶는다
    func buildMenu() {
        func item(_ title: String, _ action: Selector?, tag: Int = 0, on: Bool = false) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
            it.tag = tag
            it.state = on ? .on : .off
            return it
        }
        func sub(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu()
            items.forEach { m.addItem($0) }
            it.submenu = m
            return it
        }
        let m = NSMenu()
        if let u = update {
            let up = item(updating ? "Updating to v\(u.version)…" : "⬆️ Update to v\(u.version)", updating ? nil : #selector(installUpdate))
            up.isEnabled = !updating
            m.addItem(up)
            m.addItem(.separator())
        }
        m.addItem(sub("❄︎ Snow amount", Amount.allCases.map { item($0.title, #selector(pick(_:)), tag: $0.rawValue, on: $0 == amount) }))
        m.addItem(sub("↕︎ Snow height", bandChoices.enumerated().map { item($1.title, #selector(pickBand(_:)), tag: $0, on: $0 == bandIndex) }))
        m.addItem(sub("⏬ Fall speed", fallSpeeds.enumerated().map { item($1.title, #selector(pickFallSpeed(_:)), tag: $0, on: $0 == fallSpeedIndex) }))
        m.addItem(sub("🍬 Falling treats", treatGroups.enumerated().map { item($1.title, #selector(toggleTreat(_:)), tag: $0, on: !treatsOff.contains($0)) }))
        m.addItem(item("🏔 Snow piles up", #selector(togglePile), on: pileOn))
        // 회색 안내 — 쌓인 눈을 누르면 치우고, 길게 누르면 눈사람, 눈사람을 길게 누르면 녹는다
        for t in ["Tip: click the pile to clear it 🚜", "Tip: press and hold the pile to build a snowman ⛄",
                  "Tip: press and hold a snowman to melt it 💧"] {
            let tip = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            tip.isEnabled = false
            tip.indentationLevel = 1
            m.addItem(tip)
        }
        m.addItem(item("💡 Christmas lights", #selector(toggleLights), on: lightsOn))
        if let until = hideUntil, until > Date() {
            let f = DateFormatter()
            f.timeStyle = .short
            m.addItem(item("▶︎ Show snow now (hidden until \(f.string(from: until)))", #selector(showNow)))
        } else {
            m.addItem(sub("🙈 Hide for…", [item("30 minutes", #selector(hideFor(_:)), tag: 30),
                                          item("1 hour", #selector(hideFor(_:)), tag: 60)]))
        }
        m.addItem(.separator())
        m.addItem(sub("🛷 Visitors", [item("Santa 🎅", #selector(toggleSanta), on: santaOn),
                                          item("Snowman ⛄", #selector(toggleSnowman), on: snowmanOn),
                                          item("Penguin 🐧", #selector(togglePenguin), on: penguinOn),
                                          item("Shooting star 🌠", #selector(toggleStar), on: starOn)]))
        m.addItem(sub("⭐ Rare finds \(collected.count)/\(rareFinds.count)", rareFinds.map { r in
            let it = item(collected.contains(r.id) ? "\(r.emoji) \(r.name)" : "???", nil)
            it.isEnabled = false
            return it
        }))
        m.addItem(item("💧 Melt all snowmen", #selector(meltSnowmen)))
        m.addItem(sub("🎅 Santa speed", santaSpeeds.enumerated().map { item($1.title, #selector(pickSantaSpeed(_:)), tag: $0, on: $0 == santaSpeedIndex) }))
        m.addItem(sub("📣 Call now", [item("Santa 🎅", #selector(callSanta)),
                                       item("Snowman ⛄", #selector(callSnowman)),
                                       item("Penguin 🐧", #selector(callPenguin)),
                                       item("Shooting star 🌠", #selector(callStar)),
                                       item("Snowplow 🚜", #selector(callPlow))]))
        m.addItem(.separator())
        // 어드벤트 캘린더: 11월엔 며칠 뒤 열리는지, 12/1–25 엔 오늘 칸, 그 밖엔 안 보인다
        let (mo, da) = monthDay()
        if mo == 12 && da <= 25 {
            let opened = adventOpened().contains(da)
            m.addItem(item("🎁 Advent calendar — Day \(da)" + (opened ? "" : "  ✨ new"), #selector(openAdvent)))
        } else if mo == 11 {
            let left = 31 - da
            let soon = item("🎁 Advent calendar — opens Dec 1 (\(left) day\(left == 1 ? "" : "s"))", nil)
            soon.isEnabled = false
            m.addItem(soon)
        }
        m.addItem(item("📖 A little story", #selector(showStory)))  // 고를 때마다 다음 짧은 동화
        m.addItem(item("Check for updates… (v\(appVersion))", #selector(checkNow)))
        let quit = NSMenuItem(title: "Stop snow (Quit)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.addItem(quit)
        status.menu = m
    }


    // ── 업데이트 ──
    var update: (version: String, url: URL)?
    var updating = false
    var updateTimer: Timer?

    @objc func checkNow() { checkForUpdate(manual: true) }

    func checkForUpdate(manual: Bool = false) {
        var req = URLRequest(url: releaseFeed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            var found: (version: String, url: URL)?
            var ok = false
            if (resp as? HTTPURLResponse)?.statusCode == 200, let data = data,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = j["tag_name"] as? String, let assets = j["assets"] as? [[String: Any]] {
                ok = true
                let v = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if isNewer(v, than: appVersion),
                   let s = assets.first(where: { ($0["name"] as? String) == "XmasSnow-mac.zip" })?["browser_download_url"] as? String,
                   let u = URL(string: s), isOurDownload(u) { found = (v, u) }
            }
            DispatchQueue.main.async {
                // 확인에 실패했을 때(오프라인·요청 제한)는 이미 떠 있던 업데이트 항목을 지우지 않는다
                if ok && !self.updating { self.update = found; self.buildMenu() }
                guard manual else { return }
                if let f = found { self.askInstall(f.version) }
                else { self.say(ok ? "You're up to date ✨" : "Couldn't check for updates", ok ? "Xmas Snow v\(appVersion) is the latest version." : "Please check your internet connection and try again.") }
            }
        }.resume()
    }

    func say(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    func askInstall(_ v: String) {
        let a = NSAlert()
        a.messageText = "Xmas Snow v\(v) is available"
        a.informativeText = "You have v\(appVersion). Update now? The snow will restart in a few seconds."
        a.addButton(withTitle: "Update")
        a.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { installUpdate() }
    }

    // 새 zip 받기 → 풀기 → 지금 앱 자리에 바꿔 넣기 → 다시 켜기. 안 되면 릴리스 페이지를 연다
    @objc func installUpdate() {
        guard let u = update, !updating else { return }
        updating = true
        buildMenu()
        URLSession.shared.downloadTask(with: u.url) { tmp, resp, _ in
            let fm = FileManager.default
            var installed: URL?
            // zip 을 받아 다운로드 폴더에서 바로 열면 macOS 가 읽기 전용 임시 경로(AppTranslocation)에서 돌린다.
            // 그 자리는 바꿔 넣을 수 없으니, 그럴 땐 응용 프로그램 폴더에 새 앱을 깔고 거기서 다시 연다.
            // 확인용(가짜 피드일 때만): XMASSNOW_TRANSLOCATED 로 격리 실행을 흉내 내고, XMASSNOW_APPS 로 설치 폴더를 바꾼다
            let env = ProcessInfo.processInfo.environment
            let translocated = Bundle.main.bundleURL.path.contains("/AppTranslocation/") || (testFeed != nil && env["XMASSNOW_TRANSLOCATED"] != nil)
            let appsDir = testFeed != nil ? env["XMASSNOW_APPS"] ?? "/Applications" : "/Applications"
            let old = translocated ? URL(fileURLWithPath: appsDir).appendingPathComponent("XmasSnow.app") : Bundle.main.bundleURL
            // 바꿔 넣을 새 앱은 설치할 곳과 같은 볼륨의 임시 폴더에 푼다 (replaceItemAt 요구 사항)
            if let tmp = tmp, (resp as? HTTPURLResponse)?.statusCode == 200,
               let work = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: old.deletingLastPathComponent(), create: true) {
                let zip = work.appendingPathComponent("XmasSnow-mac.zip"), out = work.appendingPathComponent("out")
                let newApp = out.appendingPathComponent("XmasSnow.app")
                if (try? fm.createDirectory(at: out, withIntermediateDirectories: true)) != nil,
                   (try? fm.moveItem(at: tmp, to: zip)) != nil,
                   run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path]),
                   fm.isExecutableFile(atPath: newApp.appendingPathComponent("Contents/MacOS/snowfall").path),
                   // 서명 검사는 진짜임 보증이 아니라(ad-hoc) 풀린 앱이 멀쩡하고 같은 앱인지 확인용. 보안은 HTTPS + 저장소 주소 확인
                   run("/usr/bin/codesign", ["--verify", "-R=identifier \"io.github.imhuijeong92-ui.xmas-snow\"", newApp.path]),
                   // 응용 프로그램 폴더에 같은 이름의 다른 앱이 있으면 덮어쓰지 않는다
                   !fm.fileExists(atPath: old.path) || Bundle(url: old)?.bundleIdentifier == "io.github.imhuijeong92-ui.xmas-snow",
                   fm.isWritableFile(atPath: old.deletingLastPathComponent().path) {
                    do {
                        if fm.fileExists(atPath: old.path) { installed = try fm.replaceItemAt(old, withItemAt: newApp) }
                        else { try fm.moveItem(at: newApp, to: old); installed = old }
                    }
                    catch {
                        // 바꿔 넣다 실패하면서 원래 앱을 다른 곳에 옮겨 둔 경우 제자리로 되돌린다
                        if !fm.fileExists(atPath: old.path),
                           let moved = (error as NSError).userInfo["NSFileOriginalItemLocationKey"] as? URL {
                            try? fm.moveItem(at: moved, to: old)
                        }
                    }
                }
                try? fm.removeItem(at: work)
            }
            DispatchQueue.main.async {
                if let app = installed {
                    self.piles.forEach { $0.save() }
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/bin/sh")
                    // 지금 앱이 완전히 꺼진 뒤에 연다 (아직 살아 있으면 open 이 새로 켜지 않고 이걸 앞으로 가져오기만 한다)
                    p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", app.path, String(getpid())]
                    try? p.run()
                    NSApp.terminate(nil)
                } else {
                    self.updating = false
                    self.buildMenu()
                    self.say("Couldn't update automatically", "The download page will open. Quit Xmas Snow, move the new XmasSnow.app into your Applications folder, and open it from there — then future updates install with one click.")
                    NSWorkspace.shared.open(releasePage)
                }
            }
        }.resume()
    }


    @objc func showStory() { tellStory(hint: false) }

    func tellStory(hint: Bool) {
        let s = littleStories[nextIndex("littleStory", count: littleStories.count)]
        let a = NSAlert()
        a.messageText = s.title
        a.informativeText = s.text + (hint ? "\n\n📖 More stories: ❄︎ menu → A little story" : "")
        a.icon = NSImage(cgImage: peekDeer, size: NSSize(width: peekDeer.width * 4, height: peekDeer.height * 4))
        a.addButton(withTitle: "Merry Christmas 🎄")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    @objc func pick(_ sender: NSMenuItem) {
        amount = Amount(rawValue: sender.tag) ?? .light
        UserDefaults.standard.set(amount.rawValue, forKey: "amount")
        windows.forEach { $0.apply(amount, width: $0.frame.width) }
        piles.forEach { $0.amountFactor = amountFactor }
        buildMenu()
    }

    @objc func pickSantaSpeed(_ sender: NSMenuItem) {
        santaSpeedIndex = sender.tag
        UserDefaults.standard.set(santaSpeedIndex, forKey: "santaSpeed")
        buildMenu()
    }

    @objc func pickBand(_ sender: NSMenuItem) {
        bandIndex = sender.tag
        UserDefaults.standard.set(bandIndex, forKey: "height")
        rebuild()
        buildMenu()
    }

    @objc func rebuild() {
        windows.forEach { $0.stop(); $0.orderOut(nil) }
        windows = NSScreen.screens.map { SnowWindow(screen: $0, amount: amount) }
        windows.forEach { $0.orderFrontRegardless() }
        piles.forEach { $0.stop(); $0.orderOut(nil) }
        piles = recording ? [PileWindow(screen: NSScreen.screens[0], amountFactor: amountFactor)]
              : pileOn ? NSScreen.screens.map { PileWindow(screen: $0, amountFactor: amountFactor) } : []
        piles.forEach { $0.show() }
        if !recording {
            applyHide(animated: false)
            if monthDay() == (12, 25) { piles.forEach { $0.placeGifts() } }
        }
    }

    @objc func togglePile() {
        pileOn.toggle()
        UserDefaults.standard.set(pileOn, forKey: "pile")
        rebuild()
        buildMenu()
    }

    @objc func callPlow() { piles.forEach { $0.sendPlow() } }

    // ── 1.3 ──
    @objc func toggleLights() {
        lightsOn.toggle()
        UserDefaults.standard.set(lightsOn, forKey: "lights")
        for w in windows {
            w.contentView?.layer?.sublayers?.filter { $0.name == "lights" }.forEach { $0.removeFromSuperlayer() }
            if lightsOn, let scr = w.screen { w.addLights(scr) }
        }
        buildMenu()
    }

    @objc func hideFor(_ sender: NSMenuItem) {
        hideUntil = Date().addingTimeInterval(Double(sender.tag) * 60)
        UserDefaults.standard.set(hideUntil!.timeIntervalSince1970, forKey: "hideUntil")
        applyHide()
        buildMenu()
    }

    @objc func showNow() {
        hideUntil = nil
        UserDefaults.standard.removeObject(forKey: "hideUntil")
        applyHide()
        buildMenu()
    }

    // 숨긴 시각이 지났으면 다시 보이고 메뉴도 'Hide for…' 로 돌려놓는다
    func applyHide(animated: Bool = true) {
        let hidden = hideUntil.map { $0 > Date() } ?? false
        if !hidden && hideUntil != nil {
            hideUntil = nil
            UserDefaults.standard.removeObject(forKey: "hideUntil")
            buildMenu()
        }
        windows.forEach { $0.setPaused(hidden, animated: animated) }
        piles.forEach { $0.setPaused(hidden, animated: animated) }
    }

    // 30초마다: 날짜가 바뀌면 메뉴(어드벤트 칸) 새로, 12/25 엔 선물상자, 1/1 0시 10분 안엔 불꽃놀이
    func checkDay() {
        let now = appNow()
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let day = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        if day != lastDay {
            lastDay = day
            buildMenu()
            if c.month == 12 && c.day == 25 { piles.forEach { $0.placeGifts() } }
        }
        let year = c.year ?? 0
        if c.month == 1 && c.day == 1 && c.hour == 0 && (c.minute ?? 99) < 10 && store.integer(forKey: "fireworks") != year,
           windows.contains(where: { !$0.paused }) {   // 다 숨어 있으면 안 쏘고 30초 뒤 다시 본다
            store.set(year, forKey: "fireworks")
            windows.forEach { $0.fireworks(seconds: 40) }
        }
    }

    func adventOpened() -> Set<Int> {
        let c = Calendar.current.dateComponents([.year], from: appNow())
        return Set(store.array(forKey: "advent-\(c.year ?? 0)") as? [Int] ?? [])
    }

    @objc func openAdvent() {
        let (mo, da) = monthDay()
        guard mo == 12, da >= 1, da <= 25 else { return }
        let year = Calendar.current.component(.year, from: appNow())
        store.set(Array(adventOpened().union([da])), forKey: "advent-\(year)")
        let gift = adventDays[da - 1]
        let a = NSAlert()
        a.messageText = "🎁 Day \(da)"
        a.informativeText = gift.text
        let img = giftSprites[da % giftSprites.count]
        a.icon = NSImage(cgImage: img, size: NSSize(width: img.width * 8, height: img.height * 8))
        a.addButton(withTitle: "Open 🎁")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
        buildMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.adventGift(gift.gift) }
    }

    func adventGift(_ g: String) {
        switch g {
        case "santa": callSanta()
        case "snowman", "penguin": callVisitor(g)
        case "star": callStar()
        case "treats": windows.forEach { $0.treatDebt += 8 }
        case "rare": callRare(nil)
        case "xmas":
            if piles.isEmpty { windows.forEach { $0.giftRain() } } else { piles.forEach { $0.placeGifts() } }
        default: windows.forEach { $0.giftRain() }
        }
    }

    @objc func meltSnowmen() { piles.forEach { $0.meltAll() } }

    // 드문 손님 — 아직 못 만난 친구부터
    func callRare(_ id: String?) {
        let walkers = ["bear", "owl", "fox", "elf"]
        let pick = id ?? (walkers.filter { !collected.contains($0) }.randomElement() ?? walkers.randomElement()!)
        shownWindows.randomElement()?.wander(pick)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
