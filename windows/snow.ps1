# 크리스마스 눈 (윈도우용) — 맥 앱 snow.swift 와 같은 동작
# 모든 모니터 위쪽에 픽셀 눈꽃·간식이 내리고 가끔 산타·눈사람·펭귄·별똥별이 지나간다. 트레이 ❄ 아이콘에서 조절·종료.
# 윈도우 10/11 기본 PowerShell 5.1 + .NET Framework 로 실행 시 컴파일한다(C# 5 문법만 쓸 것).
# ⚠ 이 파일은 UTF-8 BOM 으로 저장해야 한글이 안 깨진다.

# 창 없이 실행되므로, 시작하다 실패하면 이유를 창으로 띄우고 같은 폴더 error.txt 에 남긴다 (친구 PC 문제 확인용)
try {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

public static class XmasSnow
{
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    public static void Run(string folder, bool updated)
    {
        Updater.Folder = folder;
        bool fresh;
        Mutex m = new Mutex(true, "XmasSnow.SingleInstance", out fresh);
        // 업데이트로 다시 켜진 거면 이전 인스턴스가 끝날 때까지 30초 기다린다
        if (!fresh && updated)
        {
            try { fresh = m.WaitOne(30000); }
            catch (AbandonedMutexException) { fresh = true; }  // 이전 인스턴스가 놓지 않고 끝났어도 넘겨받는다
        }
        if (!fresh) return;  // 이미 켜져 있으면 하나 더 띄우지 않는다
        SetProcessDPIAware();
        Application.EnableVisualStyles();
        Controller c = new Controller();
        Application.Run();
        m.ReleaseMutex();  // debug 실행기(-NoExit)처럼 PowerShell 이 남아 있어도 다음 실행을 막지 않게
        GC.KeepAlive(c);
        GC.KeepAlive(m);
    }
}

static class Art
{
    public static readonly Color Key = Color.FromArgb(255, 0, 255);  // 투명 처리할 바탕색
    public static readonly Color FlakeEdge = Color.FromArgb(143, 163, 184);
    public static readonly Color SpriteEdge = Color.FromArgb(110, 88, 88);

    public static readonly string[] FlakeBig = { "...X...", ".X.X.X.", "..XXX..", "XXXXXXX", "..XXX..", ".X.X.X.", "...X..." };
    public static readonly string[] FlakeMid = { "X.X.X", ".XXX.", "XXXXX", ".XXX.", "X.X.X" };
    public static readonly string[] FlakeDot = { "XX", "XX" };

    static readonly string[] Sleigh = {
        "...W.RR.........", "....RRRR........", "...WWWWWW.......", "....FFKFF.......",
        "...WWWWWWW......", "...RWWWWWRG.....", "R..RRRRRRRRRR..R", "RRRRRRRRRRRRRRRR",
        "RRRRRYYYRRRRRRRR", ".rrrrrrrrrrrrrr.", "..y.........y...", ".yyyyyyyyyyyyyyy" };
    static readonly string[] Reins = {
        "......", "......", "......", "......", "......", "......",
        "yyyyyy", "......", "......", "......", "......", "......" };
    static readonly string[] Reindeer = {
        "..........b.b...", "..........bbb.b.", "...........bbb..", "............BBB.",
        "............BKBN", "............BTT.", "...BBBBBBBBBB...", "..BBBBYBBBBBB...",
        ".bBBBBBBBBBB....", "...B.B...B.B....", "..B...B.B...B...", "................" };

    public static string[] Santa()
    {
        string[] rows = new string[Sleigh.Length];
        for (int i = 0; i < rows.Length; i++) rows[i] = Sleigh[i] + Reins[i] + Reindeer[i];
        return rows;
    }

    public static Color Pal(char c)
    {
        switch (c)
        {
            case 'X': case 'W': return Color.FromArgb(248, 251, 255);
            case 'R': return Color.FromArgb(214, 38, 61);
            case 'r': return Color.FromArgb(158, 28, 43);
            case 'F': return Color.FromArgb(242, 201, 160);
            case 'K': return Color.FromArgb(43, 43, 43);
            case 'Y': return Color.FromArgb(242, 193, 78);
            case 'y': return Color.FromArgb(184, 143, 41);
            case 'B': return Color.FromArgb(156, 102, 68);
            case 'b': return Color.FromArgb(107, 66, 38);
            case 'N': return Color.FromArgb(230, 57, 70);
            case 'T': return Color.FromArgb(217, 179, 140);
            case 'G': return Color.FromArgb(46, 158, 91);
            case 'L': return Color.FromArgb(77, 133, 219);
            case 'O': return Color.FromArgb(250, 153, 38);
            case 'g': return Color.FromArgb(26, 107, 61);
        }
        return Key;
    }

    // 문자 그리드 → 칸 크기 cell 의 비트맵. 바깥 둘레에 테두리를 둘러 어떤 창 위에서도 보이게.
    public static Bitmap Sprite(string[] rows, int cell, Color edge)
    {
        int h = rows.Length, w = rows[0].Length;
        Bitmap bmp = new Bitmap((w + 2) * cell, (h + 2) * cell);
        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.Clear(Key);
            using (SolidBrush eb = new SolidBrush(edge))
            {
                for (int y = -1; y <= h; y++)
                    for (int x = -1; x <= w; x++)
                        if (!On(rows, x, y) && (On(rows, x + 1, y) || On(rows, x - 1, y) || On(rows, x, y + 1) || On(rows, x, y - 1)))
                            g.FillRectangle(eb, (x + 1) * cell, (y + 1) * cell, cell, cell);
            }
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    if (On(rows, x, y))
                        using (SolidBrush b = new SolidBrush(Pal(rows[y][x])))
                            g.FillRectangle(b, (x + 1) * cell, (y + 1) * cell, cell, cell);
        }
        return bmp;
    }

    static bool On(string[] rows, int x, int y)
    {
        return y >= 0 && y < rows.Length && x >= 0 && x < rows[y].Length && rows[y][x] != '.';
    }
}

// ── 메뉴에서 바로 업데이트 ──────────────
// 깃허브 최신 릴리스(태그 vX.Y.Z)가 이 버전보다 높으면 ❄ 메뉴 맨 위에 'Update to …' 가 뜬다.
// ⚠ 릴리스를 낼 때마다 이 값과 태그를 같이 올릴 것 (같은 태그에 파일만 바꾸면 업데이트로 안 잡힌다)
static class Updater
{
    public const string Version = "1.2.2";
    const string Feed = "https://api.github.com/repos/imhuijeong92-ui/xmas-snow/releases/latest";
    public const string Page = "https://github.com/imhuijeong92-ui/xmas-snow/releases/latest";
    const string RepoPath = "/imhuijeong92-ui/xmas-snow/releases/download/";
    public static string Folder;                  // snow.ps1 이 있는 폴더 (여기 파일을 바꿔 넣는다)
    public static volatile string NewVersion, NewUrl;
    public static volatile bool Checked, CheckFailed;  // 확인이 끝나면 Controller 가 다음 틱에 메뉴를 다시 만든다

    static WebClient Client()
    {
        ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;  // TLS 1.2 (PowerShell 5.1 기본값이 낮다)
        WebClient wc = new WebClient();
        wc.Headers.Add("User-Agent", "XmasSnow/" + Version);  // 깃허브 API 는 User-Agent 가 없으면 거절한다
        return wc;
    }

    // 이 저장소 릴리스 파일만 받는다 (호스트·경로를 따로, 문화권 무관하게 비교)
    static bool IsOurs(string url)
    {
        Uri u;
        if (!Uri.TryCreate(url, UriKind.Absolute, out u)) return false;
        return u.Scheme == "https" && string.Equals(u.Host, "github.com", StringComparison.OrdinalIgnoreCase)
            && u.AbsolutePath.StartsWith(RepoPath, StringComparison.Ordinal) && !u.AbsolutePath.Contains("..");
    }

    // snow.ps1 위치를 모르면(붙여넣어 실행 등) 바꿔 넣을 수 없으니 업데이트를 내밀지 않는다
    static bool CanInstall()
    {
        return !string.IsNullOrEmpty(Folder) && File.Exists(Path.Combine(Folder, "snow.ps1"));
    }

    // "1.10.0" > "1.9.2" 처럼 숫자 단위로 비교
    public static bool IsNewer(string a, string b)
    {
        string[] x = a.Split('.'), y = b.Split('.');
        for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
        {
            int p = 0, q = 0;
            if (i < x.Length) int.TryParse(x[i], out p);
            if (i < y.Length) int.TryParse(y[i], out q);
            if (p != q) return p > q;
        }
        return false;
    }

    // 깃허브에 최신 버전만 묻는다 (백그라운드)
    public static void CheckAsync()
    {
        ThreadPool.QueueUserWorkItem(delegate
        {
            string v = null, url = null;
            bool failed = false;
            try
            {
                string json;
                using (WebClient wc = Client()) json = wc.DownloadString(Feed);
                Match tag = Regex.Match(json, "\"tag_name\"\\s*:\\s*\"[vV]?([0-9.]+)\"");
                Match zip = Regex.Match(json, "\"browser_download_url\"\\s*:\\s*\"([^\"]*/XmasSnow-windows\\.zip)\"");
                if (tag.Success && zip.Success && IsNewer(tag.Groups[1].Value, Version) && IsOurs(zip.Groups[1].Value) && CanInstall())
                {
                    v = tag.Groups[1].Value;
                    url = zip.Groups[1].Value;
                }
            }
            catch { failed = true; }
            // 확인에 실패했을 때(오프라인·요청 제한)는 이미 떠 있던 업데이트 항목을 지우지 않는다
            if (!failed) { NewVersion = v; NewUrl = url; }
            CheckFailed = failed; Checked = true;
        });
    }

    // 새 zip 을 받아 두고, 이 앱이 꺼진 뒤 PowerShell 이 풀어서 이 폴더에 덮어쓰고 다시 켠다
    public static void Install(Action<bool> done)
    {
        string url = NewUrl;
        ThreadPool.QueueUserWorkItem(delegate
        {
            bool ok = false;
            try
            {
                string zip = Path.Combine(Path.GetTempPath(), "XmasSnow-update-" + Guid.NewGuid().ToString("N") + ".zip");
                using (WebClient wc = Client()) wc.DownloadFile(url, zip);
                // 명령은 파일로 써서 -File 로 돌린다 (-EncodedCommand 는 백신·회사 보안 프로그램이 막기 쉽다)
                string ps1 = Path.Combine(Path.GetTempPath(), "XmasSnow-update-" + Guid.NewGuid().ToString("N") + ".ps1");
                File.WriteAllText(ps1, Script(Process.GetCurrentProcess().Id, zip, ps1), new UTF8Encoding(true));
                ProcessStartInfo psi = new ProcessStartInfo(PowerShell(),
                    "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ps1 + "\"");
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                Process child = Process.Start(psi);
                // 바로 막혀 꺼졌으면 실패로 보고 앱을 끄지 않는다
                ok = child != null && !child.WaitForExit(1500);
            }
            catch { }
            done(ok);
        });
    }

    // 이 앱(pid)이 꺼지길 기다렸다가 zip 을 풀어 이 폴더에 덮어쓰고 다시 켜는 PowerShell 명령
    public static string Script(int pid, string zip, string self)
    {
        return
            "Wait-Process -Id " + pid + " -Timeout 30 -ErrorAction SilentlyContinue;" +
            "try {" +
            "$t = Join-Path $env:TEMP ('XmasSnow-update-' + [guid]::NewGuid());" +
            "Expand-Archive -LiteralPath " + Quote(zip) + " -DestinationPath $t -Force -ErrorAction Stop;" +
            "Get-ChildItem -LiteralPath (Join-Path $t 'XmasSnow') | Copy-Item -Destination " + Quote(Folder) + " -Force -ErrorAction Stop;" +
            "Remove-Item -LiteralPath $t, " + Quote(zip) + ", " + Quote(self) + " -Recurse -Force -ErrorAction SilentlyContinue;" +
            "} finally {" +  // 바꿔 넣다 실패해도 (예전 파일로라도) 다시 켠다
            "Start-Process " + Quote(PowerShell()) + " -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File'," + Quote("\"" + Path.Combine(Folder, "snow.ps1") + "\"") + ",'-updated'}";
    }

    static string PowerShell()
    {
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
    }

    // PowerShell 작은따옴표 문자열 ('' 로 이스케이프)
    static string Quote(string s) { return "'" + s.Replace("'", "''") + "'"; }
}

// ── 이스터에그 ──────────────
static class Story
{
    // 빼꼼 나온 루돌프를 5번 연달아 누르면 한 줄씩 들려주는 비밀 이야기 (누를 때마다 다음 이야기)
    public static readonly string[][] Deer = {
        new string[] { "Psst… my nose isn't a light bulb.", "It glows when someone I love is near.", "…it's glowing right now. ❤️" },
        new string[] { "I practice landing on your roof every year.", "Santa says I'm getting better.", "Last year I only bumped one chimney." },
        new string[] { "I keep one snowflake from every Christmas.", "This year's is going to be yours. ❄️" },
        new string[] { "Santa reads every letter twice.", "Once for the wish.", "Once for the person who wrote it. 💌" },
    };
    // ❄ 메뉴의 'A little story' — 고를 때마다 다음 이야기 (처음 켰을 때 한 번은 저절로 뜬다)
    public static readonly string[] LittleTitle = { "The Smallest Snowflake", "The Snowman's Scarf", "Santa's Last Cookie" };
    public static readonly string[] LittleText = {
        "The smallest snowflake was scared to fall.\n\"What if no one ever sees me?\"\n\nIt took a deep breath and let go…\nand landed right on your screen.\n\nYou saw it. ✨",
        "A snowman saw a little penguin shivering in the wind.\nHe took off his red scarf and wrapped it around her.\n\n\"Won't you be cold?\" asked the penguin.\n\"I'm a snowman,\" he laughed.\n\"But my heart feels warm now.\" 🧣",
        "After the very last chimney, Santa sat down on a quiet rooftop.\nHe took out one cookie he had saved all night.\n\n\"This one,\" he told Rudolph, \"is for me.\"\n\nResting is a gift, too. 🍪",
    };

    // 다음 차례 번호를 레지스트리에 저장해 두고 하나씩 넘긴다
    public static int Next(string name, int count)
    {
        try
        {
            using (RegistryKey k = Registry.CurrentUser.CreateSubKey(@"Software\XmasSnow"))
            {
                int i = ((int)k.GetValue(name, 0) % count + count) % count;
                k.SetValue(name, (i + 1) % count, RegistryValueKind.DWord);
                return i;
            }
        }
        catch { return 0; }
    }

    // 지나가는 산타가 알려 주는 크리스마스 디데이 (12/26 부터는 다음 해 크리스마스까지)
    public static string Countdown()
    {
        DateTime today = DateTime.Today;
        DateTime xmas = new DateTime(today.Year, 12, 25);
        if (xmas < today) xmas = xmas.AddYears(1);
        int days = (int)(xmas - today).TotalDays;
        if (days == 0) return "Merry Christmas! 🎄";
        if (days == 1) return "It's Christmas Eve! Big night tonight 🎅";
        return days + " days until Christmas!";
    }
}

class Flake
{
    public float X, Y, VY, MeltY;
    public float BaseX, Amp, Freq, Phase, Age;  // 좌우 흔들림(왼쪽 대각선 ↔ 오른쪽 대각선)
    public int Kind;
    public bool Treat;    // 캔디케인·쿠키·별 등 (Kind = treatBmp 번호)
    public bool Twinkle;  // 별·오너먼트는 반짝
}

class Walker  // 가끔 지나가는 눈사람(0)·펭귄(1)·별똥별(2)
{
    public int Kind;
    public float T, Dur, BaseY;
    public float SX, SY, EX, EY;  // 별똥별 출발·도착
    public bool Caught;           // 별똥별을 잡았으면 멈추고 말풍선만 남긴다
    public float CaughtT;
}

class Gift
{
    public float X, Y, VX, VY, Life;
    public int Kind;
}

class Spark
{
    public float X, Y, VX, VY, Life;
    public bool White;  // 펭귄 눈가루
    public Color Col;   // 터진 조각 색 (Empty 면 일반 반짝이)
    public int Size;
}

class SnowForm : Form
{
    public static readonly string[] BandName = { "1/8", "1/5", "1/3", "1/2", "Full screen" };
    public static readonly float[] BandRatio = { 0.125f, 0.2f, 0.33f, 0.5f, 1f };  // 화면 위에서부터 이 비율까지만 내린다
    static readonly float[] Rate = { 0.002f, 0.005f, 0.03f };    // 화면 폭 1pt 당 초당 눈송이 수
    static readonly float[] Weight = { 0.5f, 0.35f, 0.15f };     // 점·중간·큰 눈꽃 비율
    static readonly float[] Speed = { 30f, 40f, 50f };           // pt/초

    readonly List<Flake> flakes = new List<Flake>();
    readonly List<Spark> sparks = new List<Spark>();
    readonly List<Gift> gifts = new List<Gift>();
    readonly Bitmap[] giftBmp = new Bitmap[3];
    // 선물상자: # = 상자, + = 리본 → (빨강·금), (초록·빨강), (파랑·흰)
    static readonly string[] GiftRows = { "..+.+..", "...+...", "###+###", "###+###", "+++++++", "###+###", "###+###" };
    static readonly string[] GiftColors = { "RY", "GR", "LW" };
    readonly Bitmap[] flakeBmp = new Bitmap[3];

    // 눈 사이에 가끔 섞여 내려오는 것들 (마지막 칸 = 반짝이는지)
    static readonly string[][] TreatRows = {
        new string[] { "..RWWR..", ".W....R.", "R......W", "W......R", ".......W", "......RR", "......WW", "......RR", "......WW", "......RR", "......WW", "......RR" },
        new string[] { "...bbb...", "..bBBBb..", "..BKBKB..", "..BBBBB..", "..BWWWB..", "bBBBBBBBb", "BWBBRBBWB", "...BWB...", "...BRB...", "..BB.BB..", ".BWB.BWB." },
        new string[] { "....Y....", "...YYY...", "YYYYYYYYY", ".YYYyYYY.", "..YYYYY..", "..YYYYY..", ".YYY.YYY.", ".YY...YY." },
        new string[] { "...yy...", "..YYYY..", ".RRRRRR.", "RWRRRRRR", "RWRRRRRR", "RRRRRRRR", ".RRRRRR.", "..RRRR.." },
        new string[] { "...yy...", "..YYYY..", ".LLLLLL.", "LWLLLLLL", "LWLLLLLL", "LLLLLLLL", ".LLLLLL.", "..LLLL.." },
        new string[] { ".GG...GG.", "GGGG.GGGG", "GgGGRGGgG", ".GGGRGGG.", "...RgR...", "....R...." },
        new string[] { "...RRR...", "..RR.RR..", "....y....", "...YYY...", "..YYYYY..", "..YWYYY..", "..YWYYY..", ".YYYYYYY.", "yyyyyyyyy", "....b...." },
    };
    static readonly bool[] TreatTwinkle = { false, false, true, true, true, false, false };
    readonly List<Bitmap> treatBmp = new List<Bitmap>();  // 위 7종 + 선물상자 3종
    float treatDebt;

    static readonly string[] SnowmanRows = { "....KKKK....", "....KKKK....", "...KKKKKK...", "...WWWWWW...", "..WWKWWKWW..", "..WOOOWWWW..", "...WWWWWW...", "..RRRRRRRR..", "B.RWWWWWWW.B", ".BWWWKWWWWB.", "..WWWWWWWW..", ".WWWWKWWWWW.", ".WWWWWWWWWW.", "..WWWWWWWW.." };
    static readonly string[] PenguinRows = { "..........KKK..", ".........KKKKK.", "...KKKKKKKKWKKO", "..KKKKKKKKRRKOO", ".KKWWWWWWWRRKK.", "OKWWWWWWWWWWK..", "O.WWWWWWWWWW..." };
    readonly Bitmap[] walkerBmp = new Bitmap[3];
    static readonly string[] ShootingStarRows = { "...W...", "..WYW..", ".WYYYW.", "WYYYYYW", ".WYYYW.", "..WYW..", "...W..." };
    readonly List<Walker> walkers = new List<Walker>();
    object bubbleOwner;  // 말풍선을 단 친구 (산타 = this, 아니면 Walker)
    readonly Bitmap santaBmp;
    readonly Bitmap sparkBmp;
    readonly float scale;
    readonly Random rnd;
    float spawnDebt;
    bool santa;
    float santaT, santaY, santaDur, clock;
    float bubbleT;   // 산타를 클릭하면 이 시간(초) 동안 "메리 크리스마스!" 말풍선
    string santaText = "Merry Christmas!";
    bool santaTalk;  // 이번 비행에서 크리스마스 디데이를 말할 차례
    bool wasDown;

    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);

    public int Amount;
    public static readonly string[] SantaSpeedName = { "Slow", "Normal", "Fast" };
    static readonly float[] SantaSpeedPt = { 110f, 170f, 260f };  // pt/초
    public static int SantaSpeed = 1;
    public static readonly string[] FallSpeedName = { "Slow", "Normal", "Fast" };
    static readonly float[] FallMul = { 0.6f, 1f, 1.6f };
    public static int FallSpeed = 1;
    // '같이 내릴 것' 메뉴 한 줄 = 한 묶음. treatBmp 번호 → 묶음 번호
    public static readonly string[] TreatGroupName = { "Candy cane", "Gingerbread", "Star", "Ornament", "Mistletoe", "Bell", "Gift box" };
    public static readonly bool[] TreatOn = { true, true, true, true, true, true, true };
    static readonly int[] GroupOf = { 0, 1, 2, 3, 3, 4, 5, 6, 6, 6 };
    static readonly string[] PieceColors = { "RW", "BbWR", "YyW", "RLYW", "GgR", "YyR", "RGLYW" };  // 터질 때 조각 색

    public SnowForm(Screen screen, int amount, int band, Random rnd)
    {
        this.rnd = rnd;
        Amount = amount;
        using (Graphics g = CreateGraphics()) scale = g.DpiX / 96f;

        Rectangle b = screen.Bounds;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(b.X, b.Y, b.Width, (int)(b.Height * BandRatio[band]));
        BackColor = Art.Key;
        TransparencyKey = Art.Key;
        DoubleBuffered = true;

        int c = Math.Max(1, (int)Math.Round(2 * scale));
        flakeBmp[0] = Art.Sprite(Art.FlakeDot, Math.Max(1, (int)Math.Round(1.5f * scale)), Art.FlakeEdge);
        flakeBmp[1] = Art.Sprite(Art.FlakeMid, c, Art.FlakeEdge);
        flakeBmp[2] = Art.Sprite(Art.FlakeBig, c, Art.FlakeEdge);
        santaBmp = Art.Sprite(Art.Santa(), Math.Max(1, (int)Math.Round(3 * scale)), Art.SpriteEdge);
        sparkBmp = Art.Sprite(new string[] { "Y" }, Math.Max(1, (int)Math.Round(3 * scale)), Art.Key);
        for (int k = 0; k < 3; k++)
        {
            string[] rows = new string[GiftRows.Length];
            for (int r = 0; r < rows.Length; r++)
                rows[r] = GiftRows[r].Replace('#', GiftColors[k][0]).Replace('+', GiftColors[k][1]);
            giftBmp[k] = Art.Sprite(rows, Math.Max(1, (int)Math.Round(3 * scale)), Art.SpriteEdge);
        }
        int tpx = Math.Max(1, (int)Math.Round(2.5f * scale));
        foreach (string[] rows in TreatRows) treatBmp.Add(Art.Sprite(rows, tpx, Art.SpriteEdge));
        for (int k = 0; k < 3; k++)
        {
            string[] rows = new string[GiftRows.Length];
            for (int r = 0; r < rows.Length; r++)
                rows[r] = GiftRows[r].Replace('#', GiftColors[k][0]).Replace('+', GiftColors[k][1]);
            treatBmp.Add(Art.Sprite(rows, tpx, Art.SpriteEdge));
        }
        walkerBmp[0] = Art.Sprite(SnowmanRows, Math.Max(1, (int)Math.Round(3 * scale)), Art.SpriteEdge);
        walkerBmp[1] = Art.Sprite(PenguinRows, Math.Max(1, (int)Math.Round(3 * scale)), Art.SpriteEdge);
        walkerBmp[2] = Art.Sprite(ShootingStarRows, Math.Max(1, (int)Math.Round(3 * scale)), Art.SpriteEdge);
    }

    // 클릭 통과 · 포커스 안 뺏음 · Alt+Tab 에 안 뜸
    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x80000 | 0x20 | 0x80 | 0x08000000;  // LAYERED | TRANSPARENT | TOOLWINDOW | NOACTIVATE
            return cp;
        }
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    Action onEdge;  // 루돌프 코끝이 오른쪽 끝에 닿으면 부른다 → 다음 모니터 출발

    public void CallSanta(Action reachedEdge, bool talk)
    {
        if (santa) { if (reachedEdge != null) reachedEdge(); return; }
        onEdge = reachedEdge;
        santaTalk = talk;
        santa = true;
        santaT = 0;
        santaY = Height * (0.3f + (float)rnd.NextDouble() * 0.25f);
        santaDur = (Width + santaBmp.Width * 2) / (SantaSpeedPt[SantaSpeed] * scale);
    }

    public void Step(float dt)
    {
        clock += dt;
        float W = Width, H = Height;

        // 눈 만들기
        spawnDebt += Rate[Amount] * (W / scale) * dt;
        while (spawnDebt >= 1)
        {
            spawnDebt -= 1;
            double r = rnd.NextDouble();
            int k = r < Weight[0] ? 0 : (r < Weight[0] + Weight[1] ? 1 : 2);
            Flake f = new Flake();
            f.Kind = k;
            f.BaseX = (float)rnd.NextDouble() * W * 1.06f - W * 0.03f;
            f.Amp = (10 + (float)rnd.NextDouble() * 14) * scale;                     // 폭 10–24pt
            f.Freq = (float)(2 * Math.PI / (4 + rnd.NextDouble() * 4));             // 한 번 왕복 4–8초
            f.Phase = (float)(rnd.NextDouble() * 2 * Math.PI);                       // 시작 위치는 제각각
            f.X = f.BaseX + f.Amp * (float)Math.Sin(f.Phase);
            f.Y = -flakeBmp[k].Height;
            f.VY = Speed[k] * scale * (0.7f + (float)rnd.NextDouble() * 0.6f) * FallMul[FallSpeed];
            f.MeltY = H * (0.85f + (float)rnd.NextDouble() * 0.15f);  // 띠 아래쪽에서 하나씩 녹아 사라진다
            flakes.Add(f);
        }
        // 눈 양과 상관없이 모니터마다 평균 6초에 하나씩 캔디케인·쿠키·별·선물 등이 섞여 내려온다
        treatDebt = Math.Min(2, treatDebt + dt / 6);  // 다 꺼 둔 동안 쌓이지 않게
        List<int> onKinds = new List<int>();
        for (int i = 0; i < treatBmp.Count; i++) if (TreatOn[GroupOf[i]]) onKinds.Add(i);
        if (treatDebt >= 1 && onKinds.Count > 0)
        {
            treatDebt -= 0.6f + (float)rnd.NextDouble() * 0.8f;
            Flake f = new Flake();
            f.Treat = true;
            f.Kind = onKinds[rnd.Next(onKinds.Count)];
            f.Twinkle = f.Kind < TreatTwinkle.Length && TreatTwinkle[f.Kind];
            f.BaseX = (float)rnd.NextDouble() * W;
            f.Amp = (10 + (float)rnd.NextDouble() * 14) * scale;
            f.Freq = (float)(2 * Math.PI / (4 + rnd.NextDouble() * 4));
            f.Phase = (float)(rnd.NextDouble() * 2 * Math.PI);
            f.X = f.BaseX + f.Amp * (float)Math.Sin(f.Phase);
            f.Y = -treatBmp[f.Kind].Height;
            f.VY = (28 + (float)rnd.NextDouble() * 12) * scale * FallMul[FallSpeed];
            f.MeltY = H * (0.85f + (float)rnd.NextDouble() * 0.15f);
            flakes.Add(f);
        }
        for (int i = flakes.Count - 1; i >= 0; i--)
        {
            Flake f = flakes[i];
            f.Y += f.VY * dt;
            f.Age += dt;
            f.X = f.BaseX + f.Amp * (float)Math.Sin(f.Phase + f.Freq * f.Age);
            if (f.Y > f.MeltY) flakes.RemoveAt(i);
        }

        // 산타
        if (santa)
        {
            santaT += dt;
            if (onEdge != null && SantaPos().X + santaBmp.Width >= Width)
            {
                Action a = onEdge;
                onEdge = null;
                a();
            }
            // 화면의 3분의 1쯤 왔을 때 크리스마스까지 며칠 남았는지 말해 준다
            if (santaTalk && santaT >= santaDur * 0.3f) { santaTalk = false; santaText = Story.Countdown(); bubbleOwner = this; bubbleT = 3.5f; }
            if (santaT >= santaDur) { santa = false; if (bubbleOwner == this) bubbleT = 0; }
            else
            {
                PointF p = SantaPos();
                for (int n = 0; n < 1 + (rnd.NextDouble() < 0.4 ? 1 : 0); n++)
                {
                    Spark s = new Spark();
                    s.X = p.X + santaBmp.Width * 0.08f;
                    s.Y = p.Y + santaBmp.Height * 0.6f;
                    s.VX = ((float)rnd.NextDouble() - 0.5f) * 24 * scale;
                    s.VY = ((float)rnd.NextDouble() - 0.5f) * 24 * scale;
                    s.Life = 1.4f;
                    sparks.Add(s);
                }
            }
        }
        // 눈사람·펭귄
        for (int i = walkers.Count - 1; i >= 0; i--)
        {
            Walker wk = walkers[i];
            if (wk.Caught)
            {
                wk.CaughtT -= dt;
                if (wk.CaughtT <= 0) walkers.RemoveAt(i);
                continue;
            }
            wk.T += dt;
            if (wk.T >= wk.Dur) { walkers.RemoveAt(i); if (bubbleOwner == wk) bubbleT = 0; continue; }
            if (wk.Kind == 2)  // 별똥별 반짝이 꼬리
            {
                PointF p = WalkerPos(wk);
                for (int n = 0; n < 3; n++)
                {
                    Spark s = new Spark();
                    s.Col = Art.Pal("YWy"[rnd.Next(3)]);
                    s.Size = Math.Max(1, (int)Math.Round(3 * scale));
                    s.X = p.X + walkerBmp[2].Width / 2f;
                    s.Y = p.Y + walkerBmp[2].Height / 2f;
                    s.VX = ((float)rnd.NextDouble() - 0.5f) * 30 * scale;
                    s.VY = -((float)rnd.NextDouble()) * 30 * scale;  // 떠 있다가 천천히 떨어지게
                    s.Life = 0.3f + (float)rnd.NextDouble() * 0.3f;
                    sparks.Add(s);
                }
            }
            if (wk.Kind == 1)  // 펭귄 뒤로 눈가루
            {
                PointF p = WalkerPos(wk);
                for (int n = 0; n < 2; n++)
                {
                    Spark s = new Spark();
                    s.White = true;
                    s.X = p.X;
                    s.Y = p.Y + walkerBmp[1].Height * 0.8f;
                    s.VX = -(30 + (float)rnd.NextDouble() * 40) * scale;
                    s.VY = -(20 + (float)rnd.NextDouble() * 40) * scale;
                    s.Life = 0.8f;
                    sparks.Add(s);
                }
            }
        }

        // 창은 클릭을 통과시키므로, 왼쪽 버튼이 눌린 순간 커서가 산타·눈사람·펭귄 위였는지 직접 본다
        bool down = (GetAsyncKeyState(0x01) & 0x8000) != 0;
        if (down && !wasDown)
        {
            Point c = Cursor.Position;
            if (santa && Hit(SantaPos(), santaBmp, c)) { santaText = "Merry Christmas!"; bubbleOwner = this; bubbleT = 2.5f; DropGifts(SantaPos(), santaBmp.Width, true); }
            foreach (Walker wk in walkers)
            {
                if (wk.Caught) continue;
                PointF wp = WalkerPos(wk);
                if (wk.Kind == 2)
                {
                    // 별똥별은 빠르니 넉넉하게 잡는다. 잡으면 그 자리에서 반짝 터지고 소원 말풍선
                    float m = 24 * scale;
                    Bitmap sb = walkerBmp[2];
                    if (new RectangleF(Left + wp.X - m, Top + wp.Y - m, sb.Width + m * 2, sb.Height + m * 2).Contains(c))
                    {
                        wk.Caught = true; wk.CaughtT = 3.2f;
                        bubbleOwner = wk; bubbleT = 3.2f;
                        Burst(wp.X + sb.Width / 2f, wp.Y + sb.Height / 2f, "YyWY");
                    }
                }
                else if (Hit(wp, walkerBmp[wk.Kind], c)) { bubbleOwner = wk; bubbleT = 2.5f; DropGifts(wp, walkerBmp[wk.Kind].Width, false); }
            }
            for (int i = flakes.Count - 1; i >= 0; i--)
                if (flakes[i].Treat && Hit(new PointF(flakes[i].X, flakes[i].Y), treatBmp[flakes[i].Kind], c)) { Pop(flakes[i]); flakes.RemoveAt(i); break; }
        }
        wasDown = down;
        if (bubbleT > 0) bubbleT -= dt;

        for (int i = gifts.Count - 1; i >= 0; i--)
        {
            Gift gf = gifts[i];
            gf.VY += 520 * scale * dt;  // 중력
            gf.X += gf.VX * dt;
            gf.Y += gf.VY * dt;
            gf.Life -= dt;
            if (gf.Y > H || gf.Life <= 0) gifts.RemoveAt(i);
        }
        for (int i = sparks.Count - 1; i >= 0; i--)
        {
            Spark s = sparks[i];
            s.Life -= dt;
            if (s.White) s.VY += 150 * scale * dt;
            if (s.Size > 0) s.VY += 380 * scale * dt;
            s.X += s.VX * dt;
            s.Y += s.VY * dt;
            if (s.Life <= 0) sparks.RemoveAt(i);
        }
        Invalidate();
    }

    // 떨어지던 간식·장식을 클릭하면 '퐁' — 그 색깔 픽셀 조각으로 터져 사라진다
    void Pop(Flake f)
    {
        Bitmap b = treatBmp[f.Kind];
        Burst(f.X + b.Width / 2f, f.Y + b.Height / 2f, PieceColors[GroupOf[f.Kind]]);
    }

    void Burst(float cx, float cy, string cols)
    {
        for (int n = 0; n < 40; n++)
        {
            Spark s = new Spark();
            s.Col = Art.Pal(cols[rnd.Next(cols.Length)]);
            s.Size = Math.Max(1, (int)Math.Round((3 + rnd.Next(3)) * scale));
            double a = rnd.NextDouble() * Math.PI * 2;
            float v = (80 + (float)rnd.NextDouble() * 140) * scale;
            s.X = cx; s.Y = cy;
            s.VX = (float)Math.Cos(a) * v;
            s.VY = (float)Math.Sin(a) * v;
            s.Life = 0.6f + (float)rnd.NextDouble() * 0.4f;
            sparks.Add(s);
        }
    }

    bool Hit(PointF p, Bitmap b, Point screenPt)
    {
        float m = 6 * scale;
        return new RectangleF(Left + p.X - m, Top + p.Y - m, b.Width + m * 2, b.Height + m * 2).Contains(screenPt);
    }

    // 지금 눈사람(오른→왼, 통통) / 펭귄(왼→오, 배썰매)을 이 화면 아래쪽으로 지나가게
    public void Walk(int kind)
    {
        Walker wk = new Walker();
        wk.Kind = kind;
        Bitmap b = walkerBmp[kind];
        if (kind == 2)  // 별똥별: 위쪽에서 대각선으로 2.2초 만에 휙
        {
            bool toRight = rnd.Next(2) == 0;
            float dx = Math.Min(Width * 0.45f, 700 * scale) * (toRight ? 1 : -1);
            float dy = Math.Min(Height * 0.6f, Math.Abs(dx) * 0.45f);
            wk.SX = (toRight ? 0.05f + (float)rnd.NextDouble() * 0.45f : 0.5f + (float)rnd.NextDouble() * 0.45f) * Width;
            wk.SY = 10 * scale + (float)rnd.NextDouble() * Height * 0.25f;
            wk.EX = wk.SX + dx;
            wk.EY = wk.SY + dy;
            wk.Dur = 2.2f;
            walkers.Add(wk);
            return;
        }
        wk.Dur = (Width + b.Width * 2) / ((kind == 0 ? 80f : 150f) * scale);
        wk.BaseY = Height - Math.Max(b.Height / 2f + 8 * scale, Height * 0.12f) - b.Height / 2f;
        walkers.Add(wk);
    }

    PointF WalkerPos(Walker wk)
    {
        Bitmap b = walkerBmp[wk.Kind];
        float t = wk.T / wk.Dur;
        if (wk.Kind == 2)
        {
            float e = t * t;  // 점점 빨라지게
            return new PointF(wk.SX + (wk.EX - wk.SX) * e - b.Width / 2f, wk.SY + (wk.EY - wk.SY) * e - b.Height / 2f);
        }
        float x = -b.Width + t * (Width + b.Width * 2);
        if (wk.Kind == 0)
            return new PointF(Width - x - b.Width, wk.BaseY - Math.Abs((float)Math.Sin(Math.PI * wk.T * 1.6)) * 14 * scale);
        return new PointF(x, wk.BaseY + (float)Math.Sin(wk.T * 5) * 2 * scale);
    }

    // 썰매(또는 눈사람·펭귄)에서 선물상자가 톡 튀어 올랐다가 우르르 떨어진다
    void DropGifts(PointF p, int width, bool sleigh)
    {
        for (int n = 0; n < 12; n++)
        {
            Gift gf = new Gift();
            gf.Kind = rnd.Next(3);
            gf.X = p.X + width * (sleigh ? 0.05f + (float)rnd.NextDouble() * 0.35f : 0.25f + (float)rnd.NextDouble() * 0.5f);
            gf.Y = p.Y + 10 * scale;
            double a = Math.PI / 2 + ((float)rnd.NextDouble() - 0.5f) * Math.PI / 1.25;  // 위쪽 부채꼴
            float v = (110 + (float)rnd.NextDouble() * 70) * scale;
            gf.VX = (float)Math.Cos(a) * v;
            gf.VY = -(float)Math.Sin(a) * v;
            gf.Life = 0.35f * (float)rnd.NextDouble() + 3f;  // 띠 아래 끝에 닿거나 시간이 다 되면 사라진다
            gifts.Add(gf);
        }
    }

    PointF SantaPos()
    {
        float t = santaT / santaDur;
        float x = -santaBmp.Width + t * (Width + santaBmp.Width * 2);
        float y = santaY + (float)Math.Sin(t * Math.PI * 6) * 10 * scale - santaBmp.Height / 2f;
        return new PointF(x, y);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        g.SmoothingMode = SmoothingMode.None;
        foreach (Flake f in flakes)
        {
            Bitmap b = f.Treat ? treatBmp[f.Kind] : flakeBmp[f.Kind];
            g.DrawImageUnscaled(b, (int)f.X, (int)f.Y);
            if (f.Twinkle && ((clock + f.Phase) % 0.8f) < 0.4f)  // 반짝: 오른쪽 위에 작은 흰 십자
            {
                int c = Math.Max(1, (int)Math.Round(2 * scale));
                int sx = (int)f.X + b.Width - c, sy = (int)f.Y + c;
                g.FillRectangle(Brushes.White, sx - c, sy, c * 3, c);
                g.FillRectangle(Brushes.White, sx, sy - c, c, c * 3);
            }
        }
        foreach (Walker wk in walkers)
        {
            PointF p = WalkerPos(wk);
            if (!wk.Caught) g.DrawImageUnscaled(walkerBmp[wk.Kind], (int)p.X, (int)p.Y);
            if (bubbleT > 0 && bubbleOwner == wk)
            {
                if (wk.Kind == 2) DrawBubble(g, p, walkerBmp[2].Height, "Your wish will come true!", ShootingStarRows, "Segoe UI", walkerBmp[2].Width);
                else DrawBubble(g, p, walkerBmp[wk.Kind].Height, walkerBmp[wk.Kind].Width);
            }
        }
        foreach (Gift gf in gifts) g.DrawImageUnscaled(giftBmp[gf.Kind], (int)gf.X, (int)gf.Y);
        foreach (Spark s in sparks)
            if (s.Life > 0.5f || ((int)(s.Life * 20)) % 2 == 0)  // 꺼지기 전엔 깜빡깜빡
            {
                if (s.Size > 0)
                    using (SolidBrush pb = new SolidBrush(s.Col)) g.FillRectangle(pb, (int)s.X, (int)s.Y, s.Size, s.Size);
                else
                    g.DrawImageUnscaled(s.White ? flakeBmp[0] : sparkBmp, (int)s.X, (int)s.Y);
            }
        if (santa)
        {
            PointF p = SantaPos();
            g.DrawImageUnscaled(santaBmp, (int)p.X, (int)p.Y);
            if ((clock % 0.7f) < 0.35f)  // 루돌프 코 반짝
            {
                int c = Math.Max(1, (int)Math.Round(3 * scale));
                using (SolidBrush b = new SolidBrush(Color.FromArgb(255, 120, 120)))
                    g.FillRectangle(b, (int)p.X + santaBmp.Width - c * 2, (int)p.Y + c * 5 - c / 2, c * 2, c * 2);
            }
            if (bubbleT > 0 && bubbleOwner == this) DrawBubble(g, p, santaBmp.Height, santaText, Tree, "Segoe UI", santaBmp.Width);
        }
    }

    public static readonly string[] Tree = { "...Y...", "..GGG..", ".GGGGG.", "..GGG..", ".GGGGG.", "GGGGGGG", "...b..." };

    // 흰 둥근 말풍선 — 산타·눈사람·펭귄을 따라다닌다. 위에 자리가 없으면 아래에 띄운다.
    // 투명 처리 바탕색(자홍)과 섞이지 않게 도형은 안티앨리어싱 없이 그린다.
    void DrawBubble(Graphics g, PointF p, int spriteH, int spriteW)
    {
        DrawBubble(g, p, spriteH, "Merry Christmas!", Tree, "Segoe UI", spriteW);
    }

    void DrawBubble(Graphics g, PointF p, int spriteH, string text, string[] Tree, string fontName, int spriteW)
    {
        DrawBubbleAt(g, p, spriteH, text, Tree, fontName, scale, Width, Height, spriteW);
    }

    // 쌓인 눈 창의 루돌프 말풍선도 같은 모양으로 쓰도록 static
    public static void DrawBubbleAt(Graphics g, PointF p, int spriteH, string text, string[] Tree, string fontName, float scale, int Width, int Height, int spriteW)
    {
        int tc = Math.Max(1, (int)Math.Round(2 * scale));  // 트리 픽셀 한 칸
        int treeW = Tree[0].Length * tc, treeH = Tree.Length * tc;
        using (Font font = new Font(fontName, 11f, FontStyle.Bold))
        {
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            SizeF ts = g.MeasureString(text, font);
            int padX = (int)(12 * scale), padY = (int)(5 * scale), gap = (int)(14 * scale), sp = (int)(5 * scale);
            int bw = (int)ts.Width + sp + treeW + padX * 2, bh = (int)Math.Max(ts.Height, treeH) + padY * 2;
            int x = (int)(p.X + 6 * scale);
            x = Math.Max((int)(8 * scale), Math.Min(x, Width - bw - (int)(8 * scale)));  // 화면 끝에서도 잘리지 않게
            int y = (int)p.Y - gap - bh;
            bool above = y >= 0;
            if (!above) y = (int)p.Y + spriteH + gap;
            // 위·아래 다 자리가 없으면(눈 높이 1/8 등) 캐릭터 옆에 띄운다
            bool side = !above && y + bh > Height;
            if (side)
            {
                x = Math.Max((int)(8 * scale), Math.Min((int)p.X + spriteW + (int)(12 * scale), Width - bw - (int)(8 * scale)));
                y = Math.Max((int)(4 * scale), Math.Min((int)p.Y + (spriteH - bh) / 2, Height - bh - (int)(4 * scale)));
            }

            g.SmoothingMode = SmoothingMode.None;
            Color edge = Color.FromArgb(214, 214, 220);  // 흰 창 위에서도 보이는 옅은 테두리
            using (GraphicsPath path = Pill(x, y, bw, bh))
            using (SolidBrush fill = new SolidBrush(Color.White))
            using (Pen pen = new Pen(edge, Math.Max(1, (int)scale)))
            {
                // 말꼬리 = 산타 쪽 모서리에 붙은 흰 삼각형
                int t = (int)(6 * scale), tx = Math.Max(x + 2 * t, Math.Min((int)p.X + (int)(20 * scale), x + bw - 2 * t));  // 말풍선이 밀려나도 캐릭터 쪽을 가리키게
                bool leftOfBubble = x > (int)p.X;  // 옆 말풍선: 캐릭터가 말풍선 왼쪽에 있으면 꼬리도 왼쪽
                int my = y + bh / 2;
                Point[] tail = side
                    ? (leftOfBubble ? new Point[] { new Point(x + 2, my - t), new Point(x + 2, my + t), new Point(x - t, my) }
                                    : new Point[] { new Point(x + bw - 2, my - t), new Point(x + bw - 2, my + t), new Point(x + bw + t, my) })
                    : above
                    ? new Point[] { new Point(tx - t, y + bh - 2), new Point(tx + t, y + bh - 2), new Point(tx - t / 2, y + bh + t) }
                    : new Point[] { new Point(tx - t, y + 2), new Point(tx + t, y + 2), new Point(tx - t / 2, y - t) };
                g.FillPolygon(fill, tail);
                g.DrawPolygon(pen, tail);
                g.FillPath(fill, path);
                g.DrawPath(pen, path);
                g.FillPolygon(fill, new Point[] { new Point(tail[0].X + 1, tail[0].Y), new Point(tail[1].X - 1, tail[1].Y), tail[2] });  // 꼬리와 말풍선 사이 선 지우기
            }
            using (SolidBrush red = new SolidBrush(Color.FromArgb(191, 31, 51)))
                g.DrawString(text, font, red, x + padX, y + (bh - ts.Height) / 2);
            // 트리는 칸마다 직접 칠한다(스프라이트의 투명 바탕이 말풍선에 구멍을 내지 않게)
            int ox = x + padX + (int)ts.Width + sp, oy = y + (bh - treeH) / 2;
            for (int r = 0; r < Tree.Length; r++)
                for (int c = 0; c < Tree[r].Length; c++)
                {
                    if (Tree[r][c] == '.') continue;
                    using (SolidBrush b = new SolidBrush(Art.Pal(Tree[r][c])))
                        g.FillRectangle(b, ox + c * tc, oy + r * tc, tc, tc);
                }
        }
    }

    static GraphicsPath Pill(int x, int y, int w, int h)
    {
        GraphicsPath gp = new GraphicsPath();
        gp.AddArc(x, y, h, h, 90, 180);
        gp.AddArc(x + w - h, y, h, h, 270, 180);
        gp.CloseFigure();
        return gp;
    }
}

// 작업 영역 맨 아래에 눈송이가 하나씩 내려앉아 쌓이고, 가득 차면 루돌프가 오른쪽에서 빼꼼 내다본다.
// 쌓인 눈이나 루돌프를 클릭하면 제설차가 왼쪽→오른쪽으로 밀고 간다.
// 모니터마다 아래쪽 띠 창 하나(클릭 통과 · 최상단). 눈은 영구 비트맵에 눈송이를 찍어 쌓고, 열별 높이 지도를 따로 둔다.
class PileForm : Form
{
    const int Cap = 22;  // 최대 높이 = 캔버스 22px (2px 기준 44px)
    static readonly float[] AmountFactor = { 0.25f, 1f, 2f };
    static readonly Color PileEdge = Color.FromArgb(143, 163, 184);
    static readonly string[] PlowA = {
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
        "..KKK........KKK.......W" };
    const string PlowRowB = "RGRYRGRYRGRYRGRYRR..RW..";  // 반짝이 전구 줄 반대 순서
    static readonly string[] RudolphRows = {  // Clawd 크리스마스 테마의 루돌프와 같은 그림
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
        "....bb....bb...." };

    readonly Random rnd;
    readonly float scale;
    readonly int u, cols, bmpH;       // u = 캔버스 1px 의 실제 픽셀(2px×배율)
    readonly int[] h;                 // 열별 높이(캔버스 px)
    readonly int[] cap;               // 열별 상한 — 가득 차도 윗면이 평평하지 않게 물결 모양
    // 쌓인 높이·물결 모양을 모니터마다 레지스트리에 저장 → 다시 켜거나 화면이 바뀌어도 이어서 쌓인다
    readonly double[] wave = new double[4];
    readonly string saveName;
    float saveClock;
    readonly Bitmap pileBmp;          // 쌓인 눈 (바탕 = 투명색)
    readonly Graphics pg;
    readonly ImageAttributes keyAttr = new ImageAttributes();
    readonly Bitmap[] plowBmp = new Bitmap[2];  // 0 = 전구 줄 A, 1 = B
    readonly Bitmap rudBmp;
    readonly List<Spark> sparks = new List<Spark>();
    float debt, clock, plowX, rudT, lastPeek;
    bool dirty = true, wasDown, plowing, rud, peeked;
    // 루돌프를 한 번 누르면 제설차, 연달아 5번 누르면 제설차 대신 비밀 이야기 (이스터에그)
    int deerTaps;
    float tapWait, storyT;
    string[] story;
    int cleared;                      // 제설날 뒤로 이미 비운 열 수

    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);

    public int Amount;
    readonly int band;

    public PileForm(Screen screen, int amount, int band, Random rnd)
    {
        this.rnd = rnd;
        Amount = amount;
        this.band = band;
        using (Graphics g = CreateGraphics()) scale = g.DpiX / 96f;
        u = Math.Max(1, (int)Math.Round(2 * scale));
        Rectangle wa = screen.WorkingArea;
        cols = (wa.Width + u - 1) / u;
        h = new int[cols];
        bmpH = (Cap + 20) * u;
        cap = new int[cols];
        saveName = "pile-" + screen.DeviceName.Replace("\\", "").Replace(".", "");
        int[] savedH = LoadPile();
        if (savedH == null) for (int i = 0; i < 4; i++) wave[i] = rnd.NextDouble() * 2 * Math.PI;
        double p0 = wave[0], p1 = wave[1], p2 = wave[2], p3 = wave[3];
        for (int i = 0; i < cols; i++)
            cap[i] = Cap + (int)Math.Round(6 * Math.Sin(i * 0.016 + p0) + 3 * Math.Sin(i * 0.047 + p1) + 1.5 * Math.Sin(i * 0.12 + p2) + 3.5 * Math.Abs(Math.Sin(i * 0.1 + p3)));  // 마지막 항 = 동글동글한 혹
        // 저장해 둔 눈 더미 이어 붙이기 (해상도가 바뀌었으면 칸 수에 맞춰 늘이거나 줄인다)
        if (savedH != null && savedH.Length > 0)
            for (int i = 0; i < cols; i++) h[i] = Math.Min(cap[i], savedH[(int)((long)i * savedH.Length / cols)]);
        pileBmp = new Bitmap(cols * u, bmpH);
        pg = Graphics.FromImage(pileBmp);
        pg.Clear(Art.Key);
        pg.InterpolationMode = InterpolationMode.NearestNeighbor;
        pg.PixelOffsetMode = PixelOffsetMode.Half;
        pg.SmoothingMode = SmoothingMode.None;
        keyAttr.SetColorKey(Art.Key, Art.Key);

        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        int ph = (int)(160 * scale);  // 눈 + 루돌프 + 말풍선이 들어갈 높이
        Bounds = new Rectangle(wa.X, wa.Bottom - ph, wa.Width, ph);
        BackColor = Art.Key;
        TransparencyKey = Art.Key;
        DoubleBuffered = true;

        int pc = Math.Max(1, (int)Math.Round(3 * scale));
        string[] b = (string[])PlowA.Clone();
        b[8] = PlowRowB;
        plowBmp[0] = Art.Sprite(PlowA, pc, Art.SpriteEdge);
        plowBmp[1] = Art.Sprite(b, pc, Art.SpriteEdge);
        rudBmp = Art.Sprite(RudolphRows, Math.Max(1, (int)Math.Round(4 * scale)), Art.Key);  // 루돌프는 회색 테두리 없이
        if (savedH != null) RenderPile();
    }

    // 저장 형식 = "물결4개;높이,높이,…" (HKCU\Software\XmasSnow\Pile). 없거나 깨졌으면 null → 새로 쌓는다
    int[] LoadPile()
    {
        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(@"Software\XmasSnow\Pile"))
            {
                string s = k == null ? null : k.GetValue(saveName) as string;
                if (s == null) return null;
                string[] parts = s.Split(';');
                string[] w = parts[0].Split(',');
                for (int i = 0; i < 4; i++) wave[i] = double.Parse(w[i], CultureInfo.InvariantCulture);
                string[] hs = parts[1].Split(',');
                int[] r = new int[hs.Length];
                for (int i = 0; i < hs.Length; i++) r[i] = int.Parse(hs[i], CultureInfo.InvariantCulture);
                return r;
            }
        }
        catch { return null; }
    }

    public void Save()
    {
        try
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 4; i++) sb.Append(i == 0 ? "" : ",").Append(wave[i].ToString("R", CultureInfo.InvariantCulture));
            sb.Append(';');
            for (int i = 0; i < cols; i++) sb.Append(i == 0 ? "" : ",").Append(h[i]);
            using (RegistryKey k = Registry.CurrentUser.CreateSubKey(@"Software\XmasSnow\Pile")) k.SetValue(saveName, sb.ToString());
        }
        catch { }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { Save(); pg.Dispose(); pileBmp.Dispose(); }
        base.Dispose(disposing);
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x80000 | 0x20 | 0x80 | 0x08000000;  // LAYERED | TRANSPARENT | TOOLWINDOW | NOACTIVATE
            return cp;
        }
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    // 제설차 출발 (이미 달리는 중이면 무시). 루돌프는 들어간다.
    public void StartPlow()
    {
        if (plowing) return;
        rud = false;
        story = null;
        deerTaps = 0;
        plowing = true;
        plowX = -plowBmp[0].Width;
        cleared = 0;
    }

    // 둥근 눈 뭉텅이(반지름 3–8칸)를 하나씩 얹어 울퉁불퉁하게 쌓는다. 테두리 없이 흰색으로만 칠한다. 열별 상한(cap)을 넘으면 안 올라간다
    void Land()
    {
        for (int tries = 0; tries < 6; tries++)
        {
            int x = rnd.Next(cols), r = 3 + rnd.Next(6);
            int bse = h[x] - r / 3;
            int lo = Math.Max(0, x - r), hi = Math.Min(cols - 1, x + r);
            bool grew = false;
            for (int i = lo; i <= hi; i++)
            {
                int dx = i - x;
                int v = Math.Min(cap[i], bse + (int)Math.Round(Math.Sqrt(r * r - dx * dx) * 0.7));
                if (v > h[i]) { h[i] = v; grew = true; }
            }
            if (grew) return;
        }
    }

    // 눈 더미를 다시 그린다: 이웃 5칸 평균으로 계단을 펴서 매끈한 윤곽을 만들고, 위는 흰색 → 아래로 옅은 하늘색.
    // 투명색(마젠타)과 섞여 분홍 테두리가 생기지 않게 안티앨리어싱은 끈다
    void RenderPile()
    {
        pg.Clear(Art.Key);
        Point[] pts = new Point[cols + 2];
        for (int i = 0; i < cols; i++)
        {
            int a = Math.Max(0, i - 2), b = Math.Min(cols - 1, i + 2), sum = 0;
            for (int j = a; j <= b; j++) sum += h[j];
            pts[i] = new Point(i * u + u / 2, bmpH - (int)Math.Round((float)sum / (b - a + 1) * u));
        }
        pts[cols] = new Point(cols * u, bmpH);
        pts[cols + 1] = new Point(0, bmpH);
        Rectangle area = new Rectangle(0, bmpH - (Cap + 14) * u, cols * u, (Cap + 14) * u);
        using (LinearGradientBrush br = new LinearGradientBrush(area, Color.White, Color.White, LinearGradientMode.Vertical))
        {
            ColorBlend cb = new ColorBlend();
            cb.Colors = new Color[] { Color.White, Color.FromArgb(237, 245, 255), Color.FromArgb(204, 222, 242) };
            cb.Positions = new float[] { 0f, 0.65f, 1f };
            br.InterpolationColors = cb;
            pg.FillPolygon(br, pts);
        }
    }

    bool IsFull()
    {
        int n = 0;
        for (int i = 0; i < cols; i++) if (h[i] >= cap[i] - 3) n++;
        return n >= cols * 0.85f;
    }

    public void Step(float dt)
    {
        clock += dt;
        saveClock += dt;
        if (saveClock >= 10f) { saveClock = 0; Save(); }  // 10초마다

        // 눈이 덜 내리면(낮은 띠·적은 양) 그만큼 느리게 쌓인다. 가득 차면 더는 안 자란다.
        float ratio = SnowForm.BandRatio[band];
        float fillSeconds = 360f / (AmountFactor[Amount] * ratio);
        debt += dt * cols * Cap / (fillSeconds * 30f);
        if (debt > 50f) debt = 50f;
        bool landed = false;
        while (debt >= 1f) { debt -= 1f; Land(); landed = true; }
        if (landed) { RenderPile(); dirty = true; }

        // 가득 찼고 제설차·루돌프가 없고 마지막 방문이 10분 넘었으면 루돌프가 빼꼼
        if (!plowing && !rud && landed && (!peeked || clock - lastPeek > 600f) && IsFull())
        {
            rud = true; rudT = 0; peeked = true; lastPeek = clock;
        }
        if (rud)
        {
            rudT += dt;
            if (story != null)
            {
                rudT = Math.Min(rudT, 4f);  // 이야기하는 동안은 들어가지 않는다
                storyT += dt;
                if (storyT >= story.Length * 3f + 0.5f) { story = null; rudT = 8f; }  // 다 말하면 쏙
                dirty = true;
            }
            if (rudT >= 8.5f) rud = false;
        }
        if (deerTaps > 0)
        {
            tapWait -= dt;
            if (tapWait <= 0) { deerTaps = 0; StartPlow(); }
        }

        // 창은 클릭을 통과시키므로, 왼쪽 버튼이 눌린 순간 커서가 쌓인 눈이나 루돌프 위였는지 직접 본다
        bool down = (GetAsyncKeyState(0x01) & 0x8000) != 0;
        if (down && !wasDown && !plowing)
        {
            Point c = Cursor.Position;
            bool onDeer = false, onPile = false;
            if (rud)
            {
                PointF rp = RudPos();
                float m = 6 * scale;
                if (new RectangleF(Left + rp.X - m, Top + rp.Y - m, rudBmp.Width + m * 2, rudBmp.Height + m * 2).Contains(c)) onDeer = true;
            }
            int ci = (c.X - Left) / u;
            if (!onDeer && c.X >= Left && ci >= 0 && ci < cols && h[ci] >= 3)
            {
                float top = Top + Height - h[ci] * u - 6 * scale;  // 눈 높이 + 여유 6px
                if (c.Y >= top && c.Y <= Top + Height) onPile = true;
            }
            if (onDeer && story == null)
            {
                // 루돌프: 0.6초 안에 다시 안 누르면 제설차, 5번 연달아 누르면 이야기
                Puff(c.X - Left, c.Y - Top);
                deerTaps++;
                tapWait = 0.6f;
                if (deerTaps >= 5) { deerTaps = 0; story = Story.Deer[Story.Next("deerStory", Story.Deer.Length)]; storyT = 0; rudT = Math.Max(rudT, 0.5f); }
            }
            else if (onPile) { Puff(c.X - Left, c.Y - Top); StartPlow(); }
        }
        wasDown = down;

        if (plowing)
        {
            plowX += 220f * scale * dt;
            int front = (int)((plowX + plowBmp[0].Width - 3) / u);  // 날 앞 열
            if (front > cols) front = cols;
            if (front > cleared)
            {
                for (int i = cleared; i < front; i++)
                {
                    for (int k = 0; k < h[i]; k += 3)
                        if (sparks.Count < 400 && rnd.NextDouble() < 0.5) AddSpray(i, k);
                    h[i] = 0;
                }
                RenderPile();
                cleared = front;
                dirty = true;
            }
            if (plowX >= Width) { plowing = false; Save(); }
        }

        for (int i = sparks.Count - 1; i >= 0; i--)
        {
            Spark s = sparks[i];
            s.Life -= dt;
            s.VY += 500 * scale * dt;
            s.X += s.VX * dt;
            s.Y += s.VY * dt;
            if (s.Life <= 0 || s.Y > Height) sparks.RemoveAt(i);
        }

        if (dirty || plowing || rud || sparks.Count > 0) { dirty = false; Invalidate(); }
    }

    // 누른 자리에서 바로 '퐁' — 눈가루가 위로 튀어 올라 눌렸다는 걸 바로 알게 한다
    void Puff(int x, int y)
    {
        for (int n = 0; n < 40 && sparks.Count < 400; n++)
        {
            Spark s = new Spark();
            s.Col = rnd.Next(3) == 0 ? PileEdge : Color.White;
            s.Size = Math.Max(1, (int)Math.Round((2 + rnd.Next(2)) * scale));
            s.X = x; s.Y = y;
            double a = -Math.PI / 2 + (rnd.NextDouble() - 0.5) * Math.PI * 0.9;  // 위쪽으로 부채꼴
            float v = (100 + (float)rnd.NextDouble() * 160) * scale;
            s.VX = (float)Math.Cos(a) * v;
            s.VY = (float)Math.Sin(a) * v;
            s.Life = 0.6f + (float)rnd.NextDouble() * 0.4f;
            sparks.Add(s);
        }
        dirty = true;
    }

    // 날 앞에서 위·앞쪽으로 튀는 작은 눈가루
    void AddSpray(int col, int hgt)
    {
        Spark s = new Spark();
        s.Col = rnd.Next(2) == 0 ? Color.White : PileEdge;
        s.Size = Math.Max(1, (int)Math.Round((1 + rnd.Next(2)) * scale));
        s.X = col * u;
        s.Y = Height - hgt * u;
        s.VX = (60 + (float)rnd.NextDouble() * 180) * scale;
        s.VY = -(60 + (float)rnd.NextDouble() * 160) * scale;
        s.Life = 0.5f + (float)rnd.NextDouble() * 0.5f;
        sparks.Add(s);
    }

    // 루돌프: 오른쪽 가장자리에서 0.5초 동안 들어오고, 8초에 다시 나간다. 위아래로 3px 둥실.
    PointF RudPos()
    {
        float s = 1f;
        if (rudT < 0.5f) s = rudT / 0.5f;
        else if (rudT > 8f) s = 1f - (rudT - 8f) / 0.5f;
        s = Math.Max(0f, Math.Min(1f, s));
        s = 1f - (1f - s) * (1f - s);
        float cxEnd = Width - rudBmp.Width * 0.32f;
        float cx = (Width + rudBmp.Width / 2f) + (cxEnd - (Width + rudBmp.Width / 2f)) * s;
        float y = Height - Cap * 2 * 0.6f * scale - rudBmp.Height + (float)Math.Sin(rudT * 3) * 3 * scale;
        return new PointF(cx - rudBmp.Width / 2f, y);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        g.SmoothingMode = SmoothingMode.None;
        PointF rp = new PointF();
        if (rud)
        {
            rp = RudPos();
            g.DrawImageUnscaled(rudBmp, (int)rp.X, (int)rp.Y);  // 눈더미 뒤에서 내다본다
        }
        g.DrawImageUnscaled(pileBmp, 0, Height - bmpH);
        foreach (Spark s in sparks)
            using (SolidBrush pb = new SolidBrush(s.Col)) g.FillRectangle(pb, (int)s.X, (int)s.Y, s.Size, s.Size);
        if (plowing)
        {
            Bitmap b = plowBmp[((clock % 0.6f) < 0.3f) ? 0 : 1];  // 전구 줄 0.3초마다 번갈아
            int bounce = ((int)(clock / 0.12f) % 2) * (int)Math.Round(2 * scale);  // 덜컹덜컹
            g.DrawImageUnscaled(b, (int)plowX, Height - b.Height - bounce);
        }
        if (rud && story != null)
        {
            int line = (int)(storyT / 3f);
            if (line < story.Length && storyT - line * 3f < 2.8f)
                SnowForm.DrawBubbleAt(g, rp, rudBmp.Height, story[line], SnowForm.Tree, "Segoe UI", scale, Width, Height, rudBmp.Width);
        }
        else if (rud && rudT >= 0.5f && rudT < 7.5f)
            SnowForm.DrawBubbleAt(g, rp, rudBmp.Height, "Time to clear the snow? ❄️", SnowForm.Tree, "Segoe UI", scale, Width, Height, rudBmp.Width);
    }
}

class Controller
{
    static readonly string[] AmountName = { "Light", "Normal", "Heavy" };
    const string RegPath = @"Software\XmasSnow";

    readonly List<SnowForm> forms = new List<SnowForm>();
    readonly List<PileForm> piles = new List<PileForm>();
    readonly Random rnd = new Random();
    readonly NotifyIcon tray = new NotifyIcon();
    readonly System.Windows.Forms.Timer tick = new System.Windows.Forms.Timer();
    readonly System.Windows.Forms.Timer santaTimer = new System.Windows.Forms.Timer();
    readonly System.Windows.Forms.Timer visitorTimer = new System.Windows.Forms.Timer();
    DateTime last = DateTime.Now;
    int amount;
    int band;
    bool santaOn, snowmanOn, penguinOn, starOn, pileOn;
    readonly System.Windows.Forms.Timer starTimer = new System.Windows.Forms.Timer();
    readonly System.Windows.Forms.Timer updateTimer = new System.Windows.Forms.Timer();
    readonly System.Windows.Forms.Timer storyTimer = new System.Windows.Forms.Timer();

    void TellStory(bool hint)
    {
        int i = Story.Next("littleStory", Story.LittleTitle.Length);
        string text = Story.LittleText[i] + (hint ? "\n\n📖 More stories: right-click ❄ in the tray → A little story" : "");
        MessageBox.Show(text, Story.LittleTitle[i], MessageBoxButtons.OK, MessageBoxIcon.None);
    }
    bool manualCheck, updating;
    volatile int installResult;  // 설치 스레드 결과: 1 = 준비됨, -1 = 실패

    void OnChecked()
    {
        if (!updating) BuildMenu();
        if (!manualCheck) return;
        manualCheck = false;
        if (Updater.NewVersion != null) AskInstall();
        else if (Updater.CheckFailed) MessageBox.Show("Couldn't check for updates.\nPlease check your internet connection and try again.", "Xmas Snow");
        else MessageBox.Show("Xmas Snow v" + Updater.Version + " is the latest version. ✨", "You're up to date");
    }

    void AskInstall()
    {
        if (MessageBox.Show("Xmas Snow v" + Updater.NewVersion + " is available.\nYou have v" + Updater.Version + ". Update now? The snow will restart in a few seconds.",
                "Xmas Snow update", MessageBoxButtons.YesNo) == DialogResult.Yes) StartInstall();
    }

    void StartInstall()
    {
        if (updating || Updater.NewUrl == null) return;
        updating = true;
        BuildMenu();
        Updater.Install(delegate (bool ok) { installResult = ok ? 1 : -1; });
    }

    // 준비됐으면 쌓인 눈을 저장하고 끈다 → 뒤에서 PowerShell 이 파일을 바꾸고 다시 켠다. 실패하면 릴리스 페이지
    void OnInstalled(bool ok)
    {
        if (ok)
        {
            foreach (PileForm p in piles) p.Save();
            tray.Visible = false;
            Application.Exit();
            return;
        }
        updating = false;
        BuildMenu();
        MessageBox.Show("Couldn't update automatically.\nThe download page will open. Please replace the XmasSnow folder with the new one.", "Xmas Snow");
        try { Process.Start(Updater.Page); } catch { }
    }

    public Controller()
    {
        RegistryKey k = Registry.CurrentUser.CreateSubKey(RegPath);
        amount = Math.Min(2, Math.Max(0, (int)k.GetValue("amount", 0)));
        // 1/8 이 맨 앞에 생기면서 저장 값을 "height" 로 바꿨다. 예전 "band" 값은 한 칸 밀어서 이어 쓴다 (기본 1/3)
        band = Math.Min(4, Math.Max(0, (int)k.GetValue("height", (int)k.GetValue("band", 1) + 1)));
        santaOn = (int)k.GetValue("santa", 1) == 1;
        snowmanOn = (int)k.GetValue("snowman", 1) == 1;
        penguinOn = (int)k.GetValue("penguin", 1) == 1;
        starOn = (int)k.GetValue("shootingStar", 1) == 1;
        pileOn = (int)k.GetValue("pile", 1) == 1;
        SnowForm.SantaSpeed = Math.Min(2, Math.Max(0, (int)k.GetValue("santaSpeed", 1)));
        SnowForm.FallSpeed = Math.Min(2, Math.Max(0, (int)k.GetValue("fallSpeed", 1)));
        int off = (int)k.GetValue("treatsOff", 0);  // 끈 묶음 = 비트
        for (int i = 0; i < SnowForm.TreatOn.Length; i++) SnowForm.TreatOn[i] = (off & (1 << i)) == 0;
        k.Close();

        Bitmap ib = Art.Sprite(Art.FlakeBig, 2, Art.FlakeEdge);
        tray.Icon = Icon.FromHandle(ib.GetHicon());
        tray.Text = "Christmas Snow";
        tray.Visible = true;
        // 실행할 때 검은 창이 잠깐 떴다 닫히고 몇 초 뒤에 눈이 와서, 안 켜진 줄 알기 쉽다 → 켜졌다고 알림을 띄운다
        tray.ShowBalloonTip(5000, "Xmas Snow is running ❄", "Snow is falling! Right-click the ❄ icon in the taskbar tray for options.", ToolTipIcon.Info);
        BuildMenu();

        Rebuild();
        SystemEvents.DisplaySettingsChanged += delegate { Rebuild(); };

        tick.Interval = 33;
        tick.Tick += delegate
        {
            DateTime now = DateTime.Now;
            float dt = (float)Math.Min(0.1, (now - last).TotalSeconds);
            last = now;
            foreach (SnowForm f in forms) f.Step(dt);
            foreach (PileForm p in piles) p.Step(dt);
            if (Updater.Checked) { Updater.Checked = false; OnChecked(); }
            if (installResult != 0) { bool ok = installResult > 0; installResult = 0; OnInstalled(ok); }
        };
        tick.Start();

        santaTimer.Tick += delegate { CallSanta(); ScheduleSanta(false); };
        // 눈사람·펭귄(켠 것만) = 켜고 1분 뒤, 그 뒤로 3–7분마다 아무 모니터에서
        visitorTimer.Tick += delegate
        {
            List<int> on = new List<int>();
            if (snowmanOn) on.Add(0);
            if (penguinOn) on.Add(1);
            if (on.Count > 0) CallVisitor(on[rnd.Next(on.Count)]);
            visitorTimer.Interval = rnd.Next(180000, 420000);
        };
        visitorTimer.Interval = 60000;
        visitorTimer.Start();
        // 처음 켰을 때(새 버전으로 처음 켜졌을 때 포함) 한 번만 짧은 동화를 보여 준다 — 메뉴에 이야기책이 있다는 걸 알게
        using (RegistryKey sk = Registry.CurrentUser.CreateSubKey(RegPath))
        {
            if ((sk.GetValue("storyShownVersion") as string) != Updater.Version)
            {
                sk.SetValue("storyShownVersion", Updater.Version);
                storyTimer.Interval = 5000;
                storyTimer.Tick += delegate { storyTimer.Stop(); TellStory(true); };
                storyTimer.Start();
            }
        }
        // 새 버전 확인 = 켜고 1분 뒤, 그 뒤로 12시간마다 (깃허브에 버전만 묻는다)
        updateTimer.Tick += delegate { updateTimer.Interval = 12 * 3600 * 1000; Updater.CheckAsync(); };
        updateTimer.Interval = 60000;
        updateTimer.Start();
        // 별똥별 = 켜고 40초 뒤, 그 뒤로 1–3분마다 (짧아서 자주)
        starTimer.Tick += delegate { if (starOn) CallVisitor(2); starTimer.Interval = rnd.Next(60000, 180000); };
        starTimer.Interval = 40000;
        starTimer.Start();
        ScheduleSanta(true);
    }

    void Rebuild()
    {
        foreach (SnowForm f in forms) f.Close();
        forms.Clear();
        foreach (Screen s in Screen.AllScreens)
        {
            SnowForm f = new SnowForm(s, amount, band, rnd);
            f.Show();
            forms.Add(f);
        }
        RebuildPiles();
    }

    // 쌓인 눈 창 = 모니터마다 하나(눈 쌓기를 끄면 치워서 숨긴다). 쌓인 높이는 저장해 두었다가 이어 붙인다.
    void RebuildPiles()
    {
        foreach (PileForm p in piles) p.Close();
        piles.Clear();
        if (!pileOn) return;
        foreach (Screen s in Screen.AllScreens)
        {
            PileForm p = new PileForm(s, amount, band, rnd);
            p.Show();
            piles.Add(p);
        }
    }

    // 산타 = 켜고 20초 뒤 한 번, 그 뒤로는 5–12분마다
    void ScheduleSanta(bool first)
    {
        santaTimer.Stop();
        if (!santaOn) return;
        santaTimer.Interval = first ? 20000 : rnd.Next(300000, 720000);
        santaTimer.Start();
    }

    // 왼쪽 모니터부터 오른쪽 모니터로 이어서 가로지른다
    void CallSanta()
    {
        List<SnowForm> order = new List<SnowForm>(forms);
        order.Sort(delegate (SnowForm a, SnowForm b) { return a.Left.CompareTo(b.Left); });
        Fly(order, 0);
    }

    // 아무 모니터 하나에 눈사람(0)·펭귄(1)·별똥별(2)
    void CallVisitor(int kind)
    {
        if (forms.Count > 0) forms[rnd.Next(forms.Count)].Walk(kind);
    }

    void Fly(List<SnowForm> order, int i)
    {
        if (i >= order.Count || order[i].IsDisposed) return;
        // 디데이는 한 번만 — 커서가 있는 모니터(지금 보고 있을 화면)를 지날 때
        Point c = Cursor.Position;
        bool any = false;
        foreach (SnowForm f in order) if (Screen.FromControl(f).Bounds.Contains(c)) any = true;
        bool talk = any ? Screen.FromControl(order[i]).Bounds.Contains(c) : i == 0;
        order[i].CallSanta(delegate { Fly(order, i + 1); }, talk);
    }

    void Save()
    {
        RegistryKey k = Registry.CurrentUser.CreateSubKey(RegPath);
        k.SetValue("amount", amount, RegistryValueKind.DWord);
        k.SetValue("height", band, RegistryValueKind.DWord);
        k.SetValue("santa", santaOn ? 1 : 0, RegistryValueKind.DWord);
        k.SetValue("snowman", snowmanOn ? 1 : 0, RegistryValueKind.DWord);
        k.SetValue("penguin", penguinOn ? 1 : 0, RegistryValueKind.DWord);
        k.SetValue("shootingStar", starOn ? 1 : 0, RegistryValueKind.DWord);
        k.SetValue("pile", pileOn ? 1 : 0, RegistryValueKind.DWord);
        k.SetValue("santaSpeed", SnowForm.SantaSpeed, RegistryValueKind.DWord);
        k.SetValue("fallSpeed", SnowForm.FallSpeed, RegistryValueKind.DWord);
        int off = 0;
        for (int i = 0; i < SnowForm.TreatOn.Length; i++) if (!SnowForm.TreatOn[i]) off |= 1 << i;
        k.SetValue("treatsOff", off, RegistryValueKind.DWord);
        k.Close();
    }

    static ToolStripMenuItem Item(string text, bool check, EventHandler click)
    {
        ToolStripMenuItem it = new ToolStripMenuItem(text);
        it.Checked = check;
        it.Click += click;
        return it;
    }

    // 메뉴: 항목이 많아 하위 메뉴로 묶는다
    void BuildMenu()
    {
        ContextMenuStrip m = new ContextMenuStrip();
        if (Updater.NewVersion != null)
        {
            ToolStripMenuItem up = Item(updating ? "Updating to v" + Updater.NewVersion + "…" : "⬆ Update to v" + Updater.NewVersion, false, delegate { StartInstall(); });
            up.Enabled = !updating;
            m.Items.Add(up);
            m.Items.Add(new ToolStripSeparator());
        }

        ToolStripMenuItem amt = new ToolStripMenuItem("Snow amount");
        for (int i = 0; i < 3; i++)
        {
            int a = i;
            amt.DropDownItems.Add(Item(AmountName[i], a == amount, delegate
            {
                amount = a;
                foreach (SnowForm f in forms) f.Amount = a;
                foreach (PileForm p in piles) p.Amount = a;
                Save(); BuildMenu();
            }));
        }
        m.Items.Add(amt);

        ToolStripMenuItem hgt = new ToolStripMenuItem("Snow height");
        for (int i = 0; i < SnowForm.BandName.Length; i++)
        {
            int b = i;
            hgt.DropDownItems.Add(Item(SnowForm.BandName[i], b == band, delegate { band = b; Save(); Rebuild(); BuildMenu(); }));
        }
        m.Items.Add(hgt);

        ToolStripMenuItem fall = new ToolStripMenuItem("Fall speed");
        for (int i = 0; i < SnowForm.FallSpeedName.Length; i++)
        {
            int v = i;
            fall.DropDownItems.Add(Item(SnowForm.FallSpeedName[i], v == SnowForm.FallSpeed, delegate { SnowForm.FallSpeed = v; Save(); BuildMenu(); }));
        }
        m.Items.Add(fall);

        ToolStripMenuItem treats = new ToolStripMenuItem("Falling treats");
        for (int i = 0; i < SnowForm.TreatGroupName.Length; i++)
        {
            int t = i;
            treats.DropDownItems.Add(Item(SnowForm.TreatGroupName[i], SnowForm.TreatOn[t], delegate { SnowForm.TreatOn[t] = !SnowForm.TreatOn[t]; Save(); BuildMenu(); }));
        }
        m.Items.Add(treats);
        m.Items.Add(Item("🏔 Snow piles up", pileOn, delegate { pileOn = !pileOn; Save(); RebuildPiles(); BuildMenu(); }));
        ToolStripMenuItem tip = new ToolStripMenuItem("    Tip: click the pile to clear it");
        tip.Enabled = false;  // 회색 안내 한 줄 — 쌓인 눈을 누르면 치울 수 있다는 걸 알려 준다
        m.Items.Add(tip);
        m.Items.Add(new ToolStripSeparator());

        ToolStripMenuItem pals = new ToolStripMenuItem("Visitors");
        pals.DropDownItems.Add(Item("Santa", santaOn, delegate { santaOn = !santaOn; Save(); ScheduleSanta(false); BuildMenu(); }));
        pals.DropDownItems.Add(Item("Snowman", snowmanOn, delegate { snowmanOn = !snowmanOn; Save(); BuildMenu(); }));
        pals.DropDownItems.Add(Item("Penguin", penguinOn, delegate { penguinOn = !penguinOn; Save(); BuildMenu(); }));
        pals.DropDownItems.Add(Item("Shooting star", starOn, delegate { starOn = !starOn; Save(); BuildMenu(); }));
        m.Items.Add(pals);

        ToolStripMenuItem sp = new ToolStripMenuItem("Santa speed");
        for (int i = 0; i < SnowForm.SantaSpeedName.Length; i++)
        {
            int v = i;
            sp.DropDownItems.Add(Item(SnowForm.SantaSpeedName[i], v == SnowForm.SantaSpeed, delegate { SnowForm.SantaSpeed = v; Save(); BuildMenu(); }));
        }
        m.Items.Add(sp);

        ToolStripMenuItem call = new ToolStripMenuItem("Call now");
        call.DropDownItems.Add(Item("Santa", false, delegate { CallSanta(); }));
        call.DropDownItems.Add(Item("Snowman", false, delegate { CallVisitor(0); }));
        call.DropDownItems.Add(Item("Penguin", false, delegate { CallVisitor(1); }));
        call.DropDownItems.Add(Item("Shooting star", false, delegate { CallVisitor(2); }));
        call.DropDownItems.Add(Item("Snowplow 🚜", false, delegate { foreach (PileForm p in piles) p.StartPlow(); }));
        m.Items.Add(call);

        m.Items.Add(new ToolStripSeparator());
        m.Items.Add(Item("📖 A little story", false, delegate { TellStory(false); }));  // 고를 때마다 다음 짧은 동화
        m.Items.Add(Item("Check for updates… (v" + Updater.Version + ")", false, delegate { manualCheck = true; Updater.CheckAsync(); }));
        m.Items.Add(Item("Stop snow (Quit)", false, delegate { tray.Visible = false; Application.Exit(); }));
        tray.ContextMenuStrip = m;
    }
}
'@

[XmasSnow]::Run($PSScriptRoot, ($args -contains '-updated'))
} catch {
    $msg = ($_ | Out-String)
    $log = Join-Path $PSScriptRoot 'error.txt'
    $msg | Out-File -Encoding utf8 $log
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("Xmas Snow couldn't start.`n`n$msg`nSaved to: $log", 'Xmas Snow') | Out-Null
}
