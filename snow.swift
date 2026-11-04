// 크리스마스 눈 — 모든 모니터 위쪽 띠(눈 높이 메뉴)에 픽셀 눈꽃을 내린다.
// 창은 투명하고 클릭이 통과한다. 메뉴 막대 ❄︎ 에서 눈 양 조절·끄기.
// 빌드: ./build.sh
import Cocoa
import QuartzCore

enum Amount: Int, CaseIterable {
    case light = 0, normal, heavy
    var title: String { ["Light", "Normal", "Heavy"][rawValue] }
    var rate: Float { [0.004, 0.012, 0.03][rawValue] }  // 화면 폭 1pt 당 초당 눈송이 수
}

// 눈 내리는 높이 = 화면 위에서부터 이 비율까지 (아래쪽은 서서히 사라진다). 메뉴에서 고른다.
let bandChoices: [(title: String, ratio: CGFloat)] = [("1/5", 0.2), ("1/3", 0.33), ("1/2", 0.5), ("Full screen", 1.0)]
var bandIndex = UserDefaults.standard.object(forKey: "band") as? Int ?? 1
// 산타 속도(pt/초). 메뉴에서 고른다.
let santaSpeeds: [(title: String, speed: CGFloat)] = [("Slow", 110), ("Normal", 170), ("Fast", 260)]
var santaSpeedIndex = UserDefaults.standard.object(forKey: "santaSpeed") as? Int ?? 1
var santaSpeed: CGFloat { santaSpeeds[min(max(santaSpeedIndex, 0), santaSpeeds.count - 1)].speed }
// --stage = README 미리보기 녹화용. 밤하늘 배경을 깔고(뒤 화면이 안 찍히게) 모든 친구를 차례로 보여 준다. 설정은 저장하지 않는다
let stageMode = CommandLine.arguments.contains("--stage")

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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick(convert(event.locationInWindow, from: nil)) }
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
        level = .statusBar
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

        spawnTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.spawn(0.1) }
        // 평소엔 클릭이 통과하고, 커서가 산타·눈사람·펭귄·간식 위에 있을 때만 클릭을 받는다
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let m = NSEvent.mouseLocation
            let p = CGPoint(x: m.x - self.frame.minX, y: m.y - self.frame.minY)
            self.ignoresMouseEvents = self.actorAt(p) == nil && self.treatAt(p) == nil
        }
    }

    func apply(_ amount: Amount, width: CGFloat) {
        rate = CGFloat(amount.rate) * width
    }

    func stop() {
        spawnTimer?.invalidate()
        hoverTimer?.invalidate()
    }

    func spawn(_ dt: CGFloat) {
        debt += rate * dt
        let cap = 1500  // 펑펑 + 화면 전체에서도 너무 무거워지지 않게
        while debt >= 1 {
            debt -= 1
            if (snow.sublayers?.count ?? 0) < cap { addFlake() }
        }
        // 눈 양과 상관없이 모니터마다 평균 6초에 하나씩 캔디케인·쿠키·별·선물 등이 섞여 내려온다
        treatDebt = min(max(treatDebt, 2), treatDebt + dt / (stageMode ? 1.2 : 6))  // 다 꺼 둔 동안 쌓이지 않게
        if treatDebt >= 1 {
            treatDebt -= CGFloat.random(in: 0.6...1.4)
            let on = treatGroups.indices.filter { !treatsOff.contains($0) }
            if let gi = on.randomElement() {
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
            flake.name = "treat\(g)"
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

func spriteImage(_ rows: [String]) -> CGImage {
    let h = rows.count, w = rows[0].count, W = w + 2, H = h + 2
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let cells = rows.map { Array($0) }
    let at = { (x: Int, y: Int) -> Character in
        guard y >= 0, y < h, x >= 0, x < w else { return "." }
        return cells[y][x]
    }
    for y in -1...h { for x in -1...w where at(x, y) == "." {
        if at(x + 1, y) != "." || at(x - 1, y) != "." || at(x, y + 1) != "." || at(x, y - 1) != "." {
            ctx.setFillColor(CGColor(red: 0.2, green: 0.16, blue: 0.16, alpha: 0.45))  // 밝은 창 위에서도 보이게
            ctx.fill(CGRect(x: x + 1, y: H - (y + 2), width: 1, height: 1))
        }
    } }
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
let snowmanSprite = spriteImage(["....KKKK....", "....KKKK....", "...KKKKKK...", "...WWWWWW...", "..WWKWWKWW..", "..WOOOWWWW..", "...WWWWWW...", "..RRRRRRRR..", "B.RWWWWWWW.B", ".BWWWKWWWWB.", "..WWWWWWWW..", ".WWWWKWWWWW.", ".WWWWWWWWWW.", "..WWWWWWWW.."])
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

    func flySanta(then done: @escaping () -> Void = {}) {
        guard let root = contentView?.layer else { done(); return }
        let px: CGFloat = 3
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
        else if let a = actorAt(p) { showBubble(on: a); dropGifts(from: a) }
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

// ── 화면 맨 아래(독 뒤)에 눈꽃이 하나씩 쌓이고, 클릭하면 산타 제설차가 지나가며 치운다 ──────────────
let pilePx: CGFloat = 2        // 쌓인 눈 그림 한 칸 = 2pt (내리는 눈꽃과 같은 크기)
let pileTopBand = 8            // 맨 윗켜 두께(칸). 여기는 눈꽃을 띄엄띄엄만 얹는다
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
// 눈이 다 차면 오른쪽 끝에서 빼꼼 나와 "치울까?" 하고 묻는 루돌프 (정면 얼굴)
let peekDeer = spriteImage([
    "b..b......b..b",
    "bbbb......bbbb",
    ".bb........bb.",
    "..BBBBBBBBBB..",
    "TBBBBBBBBBBBBT",
    ".BBKWBBBBKWBB.",
    ".BBKKBBBBKKBB.",
    ".BBBBBBBBBBBB.",
    "..BBTTNNTTBB..",
    "..BTTNNNNTTB..",
    "..BTTNNNNTTB..",
    "...TTTNNTTT...",
    "....TTTTTT....",
])

final class PileWindow: NSPanel {
    let pile = CALayer()
    var canvas: CGContext!
    var heights: [Int] = []        // 칸마다 쌓인 눈 꼭대기 (그림 칸 단위)
    var capMap: [Int] = []         // 칸마다 더 쌓이지 않는 한도 — 다 차도 윗면이 일자가 아니라 둔덕지게
    var carry: CGFloat = 0
    var amountFactor: CGFloat = 1  // Light 0.5 · Normal 1 · Heavy 2
    var plow: CALayer?
    var deer: CALayer?
    var lastPeek: Date?
    var growTimer: Timer?
    var hoverTimer: Timer?
    let front: NSPanel             // 제설차·루돌프·말풍선은 독 앞에 보이도록 위층 창에
    var frontRoot: CALayer { front.contentView!.layer! }
    // 다 차는 데 걸리는 시간 = 6분 ÷ (눈 양 × 눈 높이 비율) → 눈이 적게 내리면 그만큼 천천히 쌓인다
    var fillSeconds: CGFloat { 360 / (amountFactor * bandRatio) }
    var isFull: Bool { heights.indices.filter { heights[$0] >= capMap[$0] - pileTopBand - 2 }.count >= heights.count * 85 / 100 }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, amountFactor: CGFloat) {
        // 화면 맨 아래, 독보다 한 층 아래 → 독 뒤에 쌓이고 독 양옆으로 보인다 (일반 창보다는 위)
        let f = screen.frame
        let rect = NSRect(x: f.minX, y: f.minY, width: f.width, height: 160)
        front = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.amountFactor = amountFactor
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let view = ClickView(frame: NSRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        view.onClick = { [weak self] p in self?.clicked(at: p) }
        contentView = view
        setFrame(rect, display: false)

        front.hidesOnDeactivate = false
        front.isOpaque = false
        front.backgroundColor = .clear
        front.hasShadow = false
        front.ignoresMouseEvents = true
        front.isReleasedWhenClosed = false
        front.level = .statusBar
        front.collectionBehavior = collectionBehavior
        let fv = ClickView(frame: NSRect(origin: .zero, size: rect.size))
        fv.wantsLayer = true
        fv.onClick = { [weak self] p in self?.clicked(at: p) }
        front.contentView = fv
        front.setFrame(rect, display: false)

        let cols = Int(ceil(rect.width / pilePx)), rows = pileCapPx + 20
        heights = Array(repeating: 0, count: cols)
        // 큰 둔덕 + 작은 굴곡을 겹친 물결 (모니터마다 모양이 다르다)
        let ph = (0..<3).map { _ in CGFloat.random(in: 0..<(2 * .pi)) }
        capMap = (0..<cols).map { i in
            let x = CGFloat(i)
            return pileCapPx + Int((6 * sin(x * 0.016 + ph[0]) + 3 * sin(x * 0.047 + ph[1]) + 1.5 * sin(x * 0.12 + ph[2])).rounded())
        }
        canvas = CGContext(data: nil, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        pile.anchorPoint = .zero
        pile.magnificationFilter = .nearest
        pile.frame = CGRect(x: 0, y: 0, width: CGFloat(cols) * pilePx, height: CGFloat(rows) * pilePx)
        view.layer?.addSublayer(pile)

        growTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.grow(1) }
        // 평소엔 클릭이 통과하고, 커서가 쌓인 눈이나 루돌프 위에 있을 때만 클릭을 받는다
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let m = NSEvent.mouseLocation
            let p = CGPoint(x: m.x - self.frame.minX, y: m.y - self.frame.minY)
            self.front.ignoresMouseEvents = !self.onDeer(p)
            self.ignoresMouseEvents = !self.onPile(p)
        }
    }

    func stop() {
        growTimer?.invalidate()
        hoverTimer?.invalidate()
        front.orderOut(nil)
    }

    func show() {
        orderFrontRegardless()
        front.orderFrontRegardless()
    }

    func onPile(_ p: CGPoint) -> Bool {
        let i = Int(p.x / pilePx)
        guard plow == nil, i >= 0, i < heights.count, heights[i] >= 3 else { return false }
        return p.y >= 0 && p.y <= CGFloat(heights[i]) * pilePx + 6
    }

    func onDeer(_ p: CGPoint) -> Bool {
        guard let d = deer else { return false }
        return (d.presentation()?.frame ?? d.frame).insetBy(dx: -6, dy: -6).contains(p)
    }

    func clicked(at p: CGPoint) {
        if onDeer(p) || onPile(p) { hideDeer(); sendPlow() }
    }

    // 눈꽃(점·중간·큰)을 하나씩 떨궈 그 자리 눈 더미 위에 살짝 파묻히게 얹는다. 정해진 높이를 넘으면 안 얹는다
    func grow(_ dt: CGFloat) {
        let n = heights.count
        carry += CGFloat(n * pileCapPx) / (fillSeconds * 18) * dt
        var changed = false
        while carry >= 1 {
            carry -= 1
            let r = CGFloat.random(in: 0..<1)
            let img = flakeImages[r < 0.3 ? 0 : (r < 0.75 ? 1 : 2)]
            let s = img.width
            for _ in 0..<12 {
                let x = Int.random(in: -s / 2..<n - s / 2)
                let span = max(0, x + 1)..<min(n, x + s - 1)
                guard !span.isEmpty else { continue }
                let cap = span.map { capMap[$0] }.min() ?? pileCapPx
                var y = max(0, (span.map { heights[$0] }.max() ?? 0) - s / 3)
                // 맨 윗켜(한도 아래 8칸)는 빽빽하지 않게: 파묻지 않고, 양옆 2칸까지 다른 눈꽃이 없을 때만 띄엄띄엄 얹는다
                if y + s - 2 > cap - pileTopBand {
                    let around = max(0, x - 1)..<min(n, x + s + 1)
                    if around.contains(where: { heights[$0] > cap - pileTopBand }) { continue }
                    y = span.map { heights[$0] }.max() ?? 0
                }
                if y + s - 2 > cap { continue }
                canvas.draw(img, in: CGRect(x: x, y: y, width: s, height: s))
                for c in span { heights[c] = max(heights[c], y + s - 2) }
                changed = true
                break
            }
        }
        if changed { redraw() }
        if plow == nil, deer == nil, isFull, lastPeek.map({ Date().timeIntervalSince($0) > 600 }) ?? true { peek() }
    }

    func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pile.contents = canvas.makeImage()
        CATransaction.commit()
    }

    // 루돌프가 오른쪽 끝에서 빼꼼 → "Time to clear the snow?" → 8초 뒤 쏙 들어간다. 루돌프를 눌러도 제설차가 온다
    func peek() {
        let root = frontRoot
        lastPeek = Date()
        let px: CGFloat = 4
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
            guard let self = self, let d = d, self.deer === d else { return }
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
        canvas.clear(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
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
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let elapsed = CACurrentMediaTime() - t0
            let front = startX + speed * CGFloat(elapsed) + size.width / 2 - px   // 앞날 끝
            let upTo = min(self.heights.count, max(0, Int(front / pilePx)))
            let ahead = upTo < self.heights.count ? self.heights[upTo] : 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            spray.emitterPosition = CGPoint(x: front, y: max(CGFloat(ahead) * pilePx, px * 4))
            spray.birthRate = ahead > 0 ? 1 : 0
            CATransaction.commit()
            if self.heights[0..<upTo].contains(where: { $0 > 0 }) {
                self.canvas.clear(CGRect(x: 0, y: 0, width: upTo, height: self.canvas.height))
                for i in 0..<upTo { self.heights[i] = 0 }
                self.redraw()
            }
            if elapsed >= duration {
                timer.invalidate()
                truck.removeFromSuperlayer()
                spray.birthRate = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { spray.removeFromSuperlayer() }
                self.plow = nil
            }
        }
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
    // 화면 왼쪽·오른쪽 끝에서도 말풍선이 잘리지 않게 안쪽으로 민다
    let bx = min(max(6, 8 - sf.minX), root.bounds.width - 8 - box.bounds.width - sf.minX)
    box.position = CGPoint(x: bx, y: above ? s.height + 14 : -14 - box.bounds.height)
    // 말꼬리 = 산타 쪽 모서리에 붙은 흰 마름모
    let tail = CALayer()
    tail.backgroundColor = white
    tail.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
    tail.position = CGPoint(x: 20, y: above ? 1 : box.bounds.height - 1)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [SnowWindow] = []
    var piles: [PileWindow] = []
    var amountFactor: CGFloat { [0.5, 1, 2][amount.rawValue] }
    var status: NSStatusItem!
    var amount = Amount(rawValue: UserDefaults.standard.integer(forKey: "amount")) ?? .light
    var santaOn = UserDefaults.standard.object(forKey: "santa") as? Bool ?? true
    var snowmanOn = UserDefaults.standard.object(forKey: "snowman") as? Bool ?? true
    var penguinOn = UserDefaults.standard.object(forKey: "penguin") as? Bool ?? true
    var starOn = UserDefaults.standard.object(forKey: "shootingStar") as? Bool ?? true
    var starTimer: Timer?
    var santaTimer: Timer?
    var visitorTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "❄︎"
        buildMenu()
        if stageMode { bandIndex = 2; santaSpeedIndex = 2; amount = .normal }
        rebuild()
        if stageMode { stage(); return }
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        scheduleSanta(first: true)
        scheduleVisitor(first: true)
        scheduleStar(first: true)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.piles.forEach { $0.hideDeer() }; self.callPlow() }
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
        at(1.0) { w.flySanta() }
        at(3.2) { w.actors.filter { $0.name == "santa" }.forEach { w.showBubble(on: $0); w.dropGifts(from: $0) } }
        at(0.3) { w.walk("snowman") }
        at(4.0) { w.walk("penguin") }
        at(6.0) { w.shootStar(fromX: 120, rightward: true) }
        at(7.0) { w.actors.filter { $0.name == "shootingStar" }.forEach { w.catchStar($0) } }
        at(7.6) { w.actors.filter { $0.name == "penguin" }.forEach { w.showBubble(on: $0) } }
        for (i, t) in [5.0, 8.4, 9.3].enumerated() {
            at(t) { if let x = w.treatLive.dropFirst(i % 2).first { w.pop(x) } }
        }
    }

    // 눈사람·펭귄(켠 것만) = 켜고 1분 뒤, 그 뒤로 3–7분마다 아무 모니터에서
    func scheduleVisitor(first: Bool = false) {
        visitorTimer?.invalidate()
        visitorTimer = Timer.scheduledTimer(withTimeInterval: first ? 60 : Double.random(in: 180...420), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let on = [("snowman", self.snowmanOn), ("penguin", self.penguinOn)].filter { $0.1 }.map { $0.0 }
            if let who = on.randomElement() { self.callVisitor(who) }
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
        let wait = first ? 20 : Double.random(in: 300...720)
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
        order[i].flySanta { [weak self] in self?.fly(order, i + 1) }
    }

    func callVisitor(_ who: String) {
        windows.randomElement()?.walk(who)
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
        m.addItem(sub("❄︎ Snow amount", Amount.allCases.map { item($0.title, #selector(pick(_:)), tag: $0.rawValue, on: $0 == amount) }))
        m.addItem(sub("↕︎ Snow height", bandChoices.enumerated().map { item($1.title, #selector(pickBand(_:)), tag: $0, on: $0 == bandIndex) }))
        m.addItem(sub("⏬ Fall speed", fallSpeeds.enumerated().map { item($1.title, #selector(pickFallSpeed(_:)), tag: $0, on: $0 == fallSpeedIndex) }))
        m.addItem(sub("🍬 Falling treats", treatGroups.enumerated().map { item($1.title, #selector(toggleTreat(_:)), tag: $0, on: !treatsOff.contains($0)) }))
        m.addItem(item("🏔 Snow piles up", #selector(togglePile), on: pileOn))
        m.addItem(.separator())
        m.addItem(sub("🛷 Visitors", [item("Santa 🎅", #selector(toggleSanta), on: santaOn),
                                          item("Snowman ⛄", #selector(toggleSnowman), on: snowmanOn),
                                          item("Penguin 🐧", #selector(togglePenguin), on: penguinOn),
                                          item("Shooting star 🌠", #selector(toggleStar), on: starOn)]))
        m.addItem(sub("🎅 Santa speed", santaSpeeds.enumerated().map { item($1.title, #selector(pickSantaSpeed(_:)), tag: $0, on: $0 == santaSpeedIndex) }))
        m.addItem(sub("📣 Call now", [item("Santa 🎅", #selector(callSanta)),
                                       item("Snowman ⛄", #selector(callSnowman)),
                                       item("Penguin 🐧", #selector(callPenguin)),
                                       item("Shooting star 🌠", #selector(callStar)),
                                       item("Snowplow 🚜", #selector(callPlow))]))
        m.addItem(.separator())
        let quit = NSMenuItem(title: "Stop snow (Quit)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.addItem(quit)
        status.menu = m
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
        UserDefaults.standard.set(bandIndex, forKey: "band")
        rebuild()
        buildMenu()
    }

    @objc func rebuild() {
        windows.forEach { $0.stop(); $0.orderOut(nil) }
        windows = NSScreen.screens.map { SnowWindow(screen: $0, amount: amount) }
        windows.forEach { $0.orderFrontRegardless() }
        piles.forEach { $0.stop(); $0.orderOut(nil) }
        piles = pileOn && !stageMode ? NSScreen.screens.map { PileWindow(screen: $0, amountFactor: amountFactor) } : []
        piles.forEach { $0.show() }
    }

    @objc func togglePile() {
        pileOn.toggle()
        UserDefaults.standard.set(pileOn, forKey: "pile")
        rebuild()
        buildMenu()
    }

    @objc func callPlow() { piles.forEach { $0.sendPlow() } }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
