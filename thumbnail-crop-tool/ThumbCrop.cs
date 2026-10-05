// 썸네일 크롭 - 직접 위치/크기를 정해서 자르고, 밝기·대비 같은 보정을 해서 저장하는 작은 에디터.
//
// Windows에 기본으로 들어있는 .NET Framework 4 C# 컴파일러(csc.exe)로 빌드됩니다 (build.bat).
// 그 컴파일러는 C# 5까지만 지원하므로 문자열 보간($""), ?. 같은 최신 문법은 쓰지 않습니다.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ThumbCrop
{
    static class Program
    {
        [DllImport("user32.dll")]
        static extern bool SetProcessDPIAware();

        [STAThread]
        static void Main(string[] args)
        {
            try { SetProcessDPIAware(); } catch { }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                Application.Run(new EditorForm(args));
            }
            catch (Exception ex)
            {
                MessageBox.Show("오류가 발생했습니다:\n\n" + ex, "썸네일 크롭", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }

    // ------------------------------------------------------------------
    // 보정 값
    // ------------------------------------------------------------------
    public class Adjust
    {
        public int Brightness;   // -100..100  (중간톤 기준 밝기)
        public int Contrast;     // -100..100
        public int Shadows;      //    0..100  (어두운 부분 살리기)
        public int Saturation;   // -100..100
        public int Warmth;       // -100..100  (- 차갑게 / + 따뜻하게)
        public int Sharpness;    //    0..100
        public bool AutoLevels;  // 가장 어두운 곳/밝은 곳을 0~255로 펼치기
        public float Black = 0f, White = 1f; // AutoLevels일 때 계산된 값

        public bool IsIdentity
        {
            get
            {
                return Brightness == 0 && Contrast == 0 && Shadows == 0 && Saturation == 0
                    && Warmth == 0 && Sharpness == 0 && (!AutoLevels || (Black <= 0f && White >= 1f));
            }
        }

        public Adjust Clone() { return (Adjust)MemberwiseClone(); }
    }

    public static class Filters
    {
        // 픽셀별(채널별) 연산은 전부 256칸짜리 표(LUT)로 미리 계산해 둡니다.
        public static byte[][] BuildLuts(Adjust a)
        {
            double gamma = Math.Pow(2.0, -a.Brightness / 100.0);
            double k = a.Contrast >= 0 ? 1.0 + a.Contrast / 100.0 : 1.0 + a.Contrast / 100.0 * 0.7;
            double sh = a.Shadows / 100.0;
            double t = a.Warmth / 100.0;
            double[] mult = { 1.0 + 0.12 * t, 1.0 + 0.02 * t, 1.0 - 0.12 * t }; // R, G, B
            double black = a.AutoLevels ? a.Black : 0.0;
            double white = a.AutoLevels ? a.White : 1.0;
            if (white - black < 0.05) { black = 0.0; white = 1.0; }

            byte[][] luts = new byte[3][];
            for (int c = 0; c < 3; c++)
            {
                byte[] lut = new byte[256];
                for (int i = 0; i < 256; i++)
                {
                    double v = i / 255.0;
                    v = (v - black) / (white - black);
                    if (v < 0) v = 0; else if (v > 1) v = 1;
                    v = Math.Pow(v, gamma);
                    v = v + sh * 1.6 * v * (1 - v) * (1 - v);
                    v = (v - 0.5) * k + 0.5;
                    v *= mult[c];
                    int o = (int)Math.Round(v * 255.0);
                    lut[i] = (byte)(o < 0 ? 0 : (o > 255 ? 255 : o));
                }
                luts[c] = lut;
            }
            return luts;
        }

        public static void Apply(Bitmap bmp, Adjust a)
        {
            if (a.IsIdentity) return;
            Rectangle r = new Rectangle(0, 0, bmp.Width, bmp.Height);
            BitmapData d = bmp.LockBits(r, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            try
            {
                int stride = Math.Abs(d.Stride);
                byte[] buf = new byte[stride * bmp.Height];
                Marshal.Copy(d.Scan0, buf, 0, buf.Length);
                ApplyToBuffer(buf, bmp.Width, bmp.Height, stride, a);
                Marshal.Copy(buf, 0, d.Scan0, buf.Length);
            }
            finally { bmp.UnlockBits(d); }
        }

        // buf: 32bpp BGRA
        public static void ApplyToBuffer(byte[] buf, int w, int h, int stride, Adjust a)
        {
            byte[][] luts = BuildLuts(a);
            byte[] lr = luts[0], lg = luts[1], lb = luts[2];
            bool doSat = a.Saturation != 0;
            int sat = 1024 + a.Saturation * 1024 / 100;

            for (int y = 0; y < h; y++)
            {
                int i = y * stride;
                int end = i + w * 4;
                for (; i < end; i += 4)
                {
                    int b = lb[buf[i]], g = lg[buf[i + 1]], r = lr[buf[i + 2]];
                    if (doSat)
                    {
                        int l = (r * 299 + g * 587 + b * 114) / 1000;
                        r = l + (((r - l) * sat) >> 10);
                        g = l + (((g - l) * sat) >> 10);
                        b = l + (((b - l) * sat) >> 10);
                        r = r < 0 ? 0 : (r > 255 ? 255 : r);
                        g = g < 0 ? 0 : (g > 255 ? 255 : g);
                        b = b < 0 ? 0 : (b > 255 ? 255 : b);
                    }
                    buf[i] = (byte)b; buf[i + 1] = (byte)g; buf[i + 2] = (byte)r;
                }
            }
            if (a.Sharpness > 0) Sharpen(buf, w, h, stride, a.Sharpness / 100.0 * 1.5);
        }

        // 언샤프 마스크 (3x3 가우시안 블러와의 차이를 더함)
        static void Sharpen(byte[] buf, int w, int h, int stride, double amount)
        {
            if (w < 3 || h < 3) return;
            byte[] src = (byte[])buf.Clone();
            int amt = (int)(amount * 256);
            for (int y = 1; y < h - 1; y++)
            {
                int row = y * stride;
                for (int x = 1; x < w - 1; x++)
                {
                    int p = row + x * 4;
                    for (int c = 0; c < 3; c++)
                    {
                        int i = p + c;
                        int blur = (src[i - stride - 4] + 2 * src[i - stride] + src[i - stride + 4]
                                  + 2 * src[i - 4] + 4 * src[i] + 2 * src[i + 4]
                                  + src[i + stride - 4] + 2 * src[i + stride] + src[i + stride + 4]) >> 4;
                        int diff = src[i] - blur;
                        if (diff > -2 && diff < 2) continue; // 아주 작은 노이즈는 키우지 않음
                        int v = src[i] + ((diff * amt) >> 8);
                        buf[i] = (byte)(v < 0 ? 0 : (v > 255 ? 255 : v));
                    }
                }
            }
        }

        public static int[] LumaHistogram(Bitmap bmp, Rectangle region)
        {
            int[] hist = new int[256];
            region.Intersect(new Rectangle(0, 0, bmp.Width, bmp.Height));
            if (region.Width <= 0 || region.Height <= 0) return hist;
            // 일부 영역만 LockBits 하면 GDI+ 구현에 따라 해제할 때 엉뚱한 곳에 다시 써지는 경우가 있어 전체를 잠금
            BitmapData d = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                int stride = Math.Abs(d.Stride);
                byte[] buf = new byte[stride * bmp.Height];
                Marshal.Copy(d.Scan0, buf, 0, buf.Length);
                long count = (long)region.Width * region.Height;
                int step = count > 400000 ? 2 : 1;
                for (int y = region.Top; y < region.Bottom; y += step)
                {
                    int i = y * stride + region.Left * 4;
                    for (int x = 0; x < region.Width; x += step, i += 4 * step)
                        hist[(buf[i + 2] * 299 + buf[i + 1] * 587 + buf[i] * 114) / 1000]++;
                }
            }
            finally { bmp.UnlockBits(d); }
            return hist;
        }

        // 상하위 0.5%를 잘라낸 지점을 검정/흰색 기준으로 사용. 너무 과하게 펼치지 않도록 제한.
        public static void ComputeLevels(int[] hist, out float black, out float white)
        {
            long total = 0;
            for (int i = 0; i < 256; i++) total += hist[i];
            black = 0f; white = 1f;
            if (total == 0) return;
            long cut = Math.Max(1, total / 200);
            long acc = 0; int lo = 0;
            for (int i = 0; i < 256; i++) { acc += hist[i]; if (acc >= cut) { lo = i; break; } }
            acc = 0; int hi = 255;
            for (int i = 255; i >= 0; i--) { acc += hist[i]; if (acc >= cut) { hi = i; break; } }
            black = Math.Min(lo / 255f, 0.25f);
            white = Math.Max(hi / 255f, 0.75f);
        }
    }

    // ------------------------------------------------------------------
    // 이미지 불러오기 / 저장
    // ------------------------------------------------------------------
    static class ImageIO
    {
        public static readonly string[] Extensions =
            { ".jpg", ".jpeg", ".jfif", ".png", ".bmp", ".gif", ".tif", ".tiff", ".webp", ".heic", ".heif", ".avif" };

        public static bool IsImage(string path)
        {
            string ext = Path.GetExtension(path).ToLowerInvariant();
            return Array.IndexOf(Extensions, ext) >= 0;
        }

        public static Bitmap Load(string path)
        {
            byte[] bytes = File.ReadAllBytes(path);
            try
            {
                using (MemoryStream ms = new MemoryStream(bytes))
                using (Image img = Image.FromStream(ms))
                {
                    Bitmap bmp = new Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb);
                    using (Graphics g = Graphics.FromImage(bmp))
                    {
                        g.CompositingMode = CompositingMode.SourceCopy;
                        g.DrawImage(img, new Rectangle(0, 0, img.Width, img.Height));
                    }
                    ApplyOrientation(bmp, ReadJpegOrientation(bytes), img);
                    return bmp;
                }
            }
            catch (ArgumentException)
            {
                // GDI+가 못 여는 형식(WebP, HEIC 등)은 윈도우 이미지 코덱(WIC)으로 다시 시도
                Bitmap wic = LoadViaWic(bytes);
                if (wic != null) return wic;
                throw new Exception("이 이미지 형식은 열 수 없습니다: " + Path.GetFileName(path)
                    + "\n(JPG, PNG, BMP, GIF, TIFF는 항상 되고, WebP/HEIC는 윈도우에 해당 코덱이 있어야 합니다)");
            }
        }

        // 휴대폰 사진은 픽셀은 눕혀 저장하고 EXIF 방향값(0x0112)으로 세우라고 표시하는 경우가 많음
        static void ApplyOrientation(Bitmap bmp, int o, Image img)
        {
            if (o == 0)
            {
                try
                {
                    if (Array.IndexOf(img.PropertyIdList, 0x0112) >= 0)
                    {
                        PropertyItem p = img.GetPropertyItem(0x0112);
                        if (p.Value != null && p.Value.Length >= 2) o = BitConverter.ToUInt16(p.Value, 0);
                    }
                }
                catch { }
            }
            RotateFlipType t;
            switch (o)
            {
                case 2: t = RotateFlipType.RotateNoneFlipX; break;
                case 3: t = RotateFlipType.Rotate180FlipNone; break;
                case 4: t = RotateFlipType.RotateNoneFlipY; break;
                case 5: t = RotateFlipType.Rotate90FlipX; break;
                case 6: t = RotateFlipType.Rotate90FlipNone; break;
                case 7: t = RotateFlipType.Rotate270FlipX; break;
                case 8: t = RotateFlipType.Rotate270FlipNone; break;
                default: return;
            }
            bmp.RotateFlip(t);
        }

        // JPEG의 APP1(Exif) 세그먼트에서 IFD0의 Orientation 값을 직접 읽음. 없으면 0.
        static int ReadJpegOrientation(byte[] b)
        {
            try
            {
                if (b.Length < 4 || b[0] != 0xFF || b[1] != 0xD8) return 0;
                int pos = 2;
                while (pos + 4 <= b.Length && b[pos] == 0xFF)
                {
                    int marker = b[pos + 1];
                    int len = (b[pos + 2] << 8) | b[pos + 3];
                    if (marker == 0xDA || len < 2) break; // 이미지 데이터 시작
                    int seg = pos + 4;
                    if (marker == 0xE1 && len >= 16 && b[seg] == 'E' && b[seg + 1] == 'x' && b[seg + 2] == 'i' && b[seg + 3] == 'f')
                    {
                        int tiff = seg + 6;
                        bool le = b[tiff] == 'I';
                        Func<int, int> u16 = delegate(int i) { return le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]; };
                        Func<int, int> u32 = delegate(int i) { return le ? u16(i) | (u16(i + 2) << 16) : (u16(i) << 16) | u16(i + 2); };
                        int ifd = tiff + u32(tiff + 4);
                        int count = u16(ifd);
                        for (int n = 0; n < count; n++)
                        {
                            int e = ifd + 2 + n * 12;
                            if (e + 12 > b.Length) break;
                            if (u16(e) == 0x0112) return u16(e + 8);
                        }
                        return 0;
                    }
                    pos += 2 + len;
                }
            }
            catch { }
            return 0;
        }

        // WPF(PresentationCore)를 리플렉션으로 불러와서 WIC 디코더를 사용. 실패하면 null.
        static Bitmap LoadViaWic(byte[] bytes)
        {
            try
            {
                const string suffix = ", Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35";
                Assembly core = Assembly.Load("PresentationCore" + suffix);
                Type decT = core.GetType("System.Windows.Media.Imaging.BitmapDecoder", true);
                Type createOpt = core.GetType("System.Windows.Media.Imaging.BitmapCreateOptions", true);
                Type cacheOpt = core.GetType("System.Windows.Media.Imaging.BitmapCacheOption", true);
                Type bsT = core.GetType("System.Windows.Media.Imaging.BitmapSource", true);
                Type fcbT = core.GetType("System.Windows.Media.Imaging.FormatConvertedBitmap", true);
                Type paletteT = core.GetType("System.Windows.Media.Imaging.BitmapPalette", true);
                Type pfT = core.GetType("System.Windows.Media.PixelFormat", true);
                Type pfsT = core.GetType("System.Windows.Media.PixelFormats", true);

                using (MemoryStream ms = new MemoryStream(bytes))
                {
                    MethodInfo create = decT.GetMethod("Create", new Type[] { typeof(Stream), createOpt, cacheOpt });
                    object dec = create.Invoke(null, new object[] {
                        ms, Enum.Parse(createOpt, "None"), Enum.Parse(cacheOpt, "OnLoad") });
                    System.Collections.IList frames = (System.Collections.IList)decT.GetProperty("Frames").GetValue(dec, null);
                    object frame = frames[0];
                    object bgra = pfsT.GetProperty("Bgra32").GetValue(null, null);
                    ConstructorInfo ctor = fcbT.GetConstructor(new Type[] { bsT, pfT, paletteT, typeof(double) });
                    object conv = ctor.Invoke(new object[] { frame, bgra, null, 0.0 });
                    int w = (int)bsT.GetProperty("PixelWidth").GetValue(conv, null);
                    int h = (int)bsT.GetProperty("PixelHeight").GetValue(conv, null);
                    int stride = w * 4;
                    byte[] buf = new byte[stride * h];
                    MethodInfo copy = bsT.GetMethod("CopyPixels", new Type[] { typeof(Array), typeof(int), typeof(int) });
                    copy.Invoke(conv, new object[] { buf, stride, 0 });

                    Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
                    BitmapData d = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                    try
                    {
                        for (int y = 0; y < h; y++)
                            Marshal.Copy(buf, y * stride, IntPtr.Add(d.Scan0, y * d.Stride), stride);
                    }
                    finally { bmp.UnlockBits(d); }
                    return bmp;
                }
            }
            catch
            {
                return null;
            }
        }

        public static void Save(Bitmap bmp, string path, bool jpeg, int quality)
        {
            if (jpeg)
            {
                // JPG는 투명도를 못 가지므로 흰 배경 위에 합성
                using (Bitmap flat = new Bitmap(bmp.Width, bmp.Height, PixelFormat.Format24bppRgb))
                {
                    using (Graphics g = Graphics.FromImage(flat))
                    {
                        g.Clear(Color.White);
                        g.DrawImage(bmp, new Rectangle(0, 0, bmp.Width, bmp.Height));
                    }
                    ImageCodecInfo codec = null;
                    foreach (ImageCodecInfo c in ImageCodecInfo.GetImageEncoders())
                        if (c.FormatID == ImageFormat.Jpeg.Guid) codec = c;
                    using (EncoderParameters ps = new EncoderParameters(1))
                    {
                        ps.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, (long)quality);
                        flat.Save(path, codec, ps);
                    }
                }
            }
            else
            {
                bmp.Save(path, ImageFormat.Png);
            }
        }
    }

    // ------------------------------------------------------------------
    // 그림판 (자르기 영역을 그리는 곳)
    // ------------------------------------------------------------------
    class Canvas : Panel
    {
        public Canvas()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                   | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            TabStop = true;
        }

        protected override bool IsInputKey(Keys keyData)
        {
            Keys k = keyData & Keys.KeyCode;
            if (k == Keys.Left || k == Keys.Right || k == Keys.Up || k == Keys.Down) return true;
            return base.IsInputKey(keyData);
        }
    }

    enum Hit { None, Move, NW, N, NE, E, SE, S, SW, W, New }

    // ------------------------------------------------------------------
    // 메인 창
    // ------------------------------------------------------------------
    class EditorForm : Form
    {
        static readonly string[] RatioLabels = { "1:1", "16:9", "4:3", "3:4", "9:16", "자유" };
        static readonly float[] RatioValues = { 1f, 16f / 9f, 4f / 3f, 3f / 4f, 9f / 16f, 0f };
        static readonly int[] SizeValues = { 0, 1920, 1280, 1080, 720, 512, 320 };

        readonly Color BgDark = Color.FromArgb(30, 30, 32);
        readonly Color PanelBg = Color.FromArgb(245, 245, 247);

        // 상태
        List<string> files = new List<string>();
        int fileIndex = -1;
        Bitmap source;
        RectangleF sel;          // 원본 픽셀 좌표 기준 자르기 영역
        float ratio = 1f;        // 0 = 자유
        Adjust adj = new Adjust();
        bool comparing;
        string lastSaved;

        // 화면 표시용
        Bitmap baseView, fxView;   // 화면 크기로 줄인 원본 / 보정 적용본
        Rectangle viewRect;        // 이미지가 그려지는 위치(캔버스 좌표)
        bool fxDirty;
        float dpi = 1f;

        // 마우스 드래그
        Hit drag = Hit.None;
        PointF dragStartImg, anchor;
        RectangleF dragStartSel;
        Point downScreen;
        bool newMoved;

        // 컨트롤
        Canvas canvas;
        Label infoLabel, fileLabel, outputLabel, counterLabel;
        LinkLabel statusLink;
        Button prevBtn, nextBtn;
        Control navRow;
        RadioButton[] ratioButtons;
        ComboBox sizeCombo, formatCombo;
        CheckBox autoLevelsCheck;
        List<TrackBar> sliders = new List<TrackBar>();
        TrackBar brightness, contrast, shadows, saturation, warmth, sharpness;
        bool suppressEvents;
        Timer fxTimer, viewTimer;
        ToolTip tips = new ToolTip();

        public EditorForm(string[] args)
        {
            Text = "썸네일 크롭";
            using (Graphics g = CreateGraphics()) dpi = g.DpiX / 96f;
            Font = new Font("Malgun Gothic", 9f);
            StartPosition = FormStartPosition.CenterScreen;
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            Size = new Size(Math.Min(S(1280), wa.Width - 40), Math.Min(S(820), wa.Height - 40));
            MinimumSize = new Size(S(820), S(560));
            KeyPreview = true;
            AllowDrop = true;
            Icon = MakeIcon();

            BuildUi();
            LoadSettings();

            fxTimer = new Timer();
            fxTimer.Interval = 30;
            fxTimer.Tick += delegate { if (fxDirty) RebuildFx(); };
            fxTimer.Start();
            viewTimer = new Timer();
            viewTimer.Interval = 150;
            viewTimer.Tick += delegate { viewTimer.Stop(); RebuildBase(); };

            DragEnter += OnDragEnter;
            DragDrop += OnDragDrop;

            List<string> initial = ExpandPaths(args);
            if (initial.Count > 0)
            {
                files = initial;
                Shown += delegate { OpenIndex(0); };
            }
            UpdateNav();
        }

        int S(int px) { return (int)Math.Round(px * dpi); }

        // ---------------- UI 구성 ----------------
        void BuildUi()
        {
            SuspendLayout();

            Panel side = new Panel();
            side.Dock = DockStyle.Right;
            side.Width = S(322); // 세로 스크롤바가 생겨도 내용이 잘리지 않도록 여유
            side.BackColor = PanelBg;
            side.AutoScroll = true;
            side.Padding = new Padding(S(14), S(10), S(14), S(10));

            FlowLayoutPanel flow = new FlowLayoutPanel();
            flow.FlowDirection = FlowDirection.TopDown;
            flow.WrapContents = false;
            flow.AutoSize = true;
            flow.Dock = DockStyle.Top;
            side.Controls.Add(flow);
            int W = S(262);

            // 파일
            Button openBtn = MakeButton("이미지 열기...", W);
            openBtn.Click += delegate { OpenDialog(); };
            flow.Controls.Add(openBtn);

            fileLabel = new Label();
            fileLabel.AutoSize = false;
            fileLabel.Width = W;
            fileLabel.Height = S(36);
            fileLabel.ForeColor = Color.FromArgb(90, 90, 96);
            fileLabel.Text = "열린 이미지 없음";
            fileLabel.Margin = new Padding(0, S(4), 0, 0);
            flow.Controls.Add(fileLabel);

            FlowLayoutPanel nav = MakeRow(W);
            prevBtn = MakeButton("◀ 이전", S(80));
            prevBtn.Click += delegate { OpenIndex(fileIndex - 1); };
            nextBtn = MakeButton("다음 ▶", S(80));
            nextBtn.Click += delegate { OpenIndex(fileIndex + 1); };
            counterLabel = new Label();
            counterLabel.AutoSize = false;
            counterLabel.Size = new Size(S(90), S(28));
            counterLabel.TextAlign = ContentAlignment.MiddleCenter;
            nav.Controls.Add(prevBtn);
            nav.Controls.Add(counterLabel);
            nav.Controls.Add(nextBtn);
            flow.Controls.Add(nav);
            navRow = nav;

            // 자르기
            flow.Controls.Add(MakeHeader("자르기 비율", W));
            FlowLayoutPanel ratios = MakeRow(W);
            ratioButtons = new RadioButton[RatioLabels.Length];
            for (int i = 0; i < RatioLabels.Length; i++)
            {
                RadioButton rb = new RadioButton();
                rb.Appearance = Appearance.Button;
                rb.Text = RatioLabels[i];
                rb.TextAlign = ContentAlignment.MiddleCenter;
                rb.Size = new Size(S(40), S(28));
                rb.Margin = new Padding(0, 0, S(3), 0);
                rb.FlatStyle = FlatStyle.Flat;
                rb.BackColor = Color.White;
                int idx = i;
                rb.CheckedChanged += delegate
                {
                    rb.BackColor = rb.Checked ? Color.FromArgb(0, 120, 215) : Color.White;
                    rb.ForeColor = rb.Checked ? Color.White : Color.Black;
                    if (rb.Checked && !suppressEvents) SetRatio(RatioValues[idx]);
                };
                ratioButtons[i] = rb;
                ratios.Controls.Add(rb);
            }
            flow.Controls.Add(ratios);

            FlowLayoutPanel rot = MakeRow(W);
            rot.Margin = new Padding(0, S(6), 0, 0);
            Button rotL = MakeButton("↺ 왼쪽 90°", S(84));
            rotL.Click += delegate { Rotate(RotateFlipType.Rotate270FlipNone); };
            Button rotR = MakeButton("↻ 오른쪽 90°", S(90));
            rotR.Click += delegate { Rotate(RotateFlipType.Rotate90FlipNone); };
            Button maxBtn = MakeButton("최대 크기", S(80));
            maxBtn.Click += delegate { if (source != null) { sel = MaxSel(Center(sel)); SelChanged(); } canvas.Focus(); };
            tips.SetToolTip(maxBtn, "선택 영역을 비율에 맞는 가장 큰 크기로 (더블클릭과 같음)");
            rot.Controls.Add(rotL); rot.Controls.Add(rotR); rot.Controls.Add(maxBtn);
            flow.Controls.Add(rot);

            // 보정
            flow.Controls.Add(MakeHeader("보정", W));
            brightness = AddSlider(flow, "밝기", -100, 100, W);
            contrast = AddSlider(flow, "대비", -100, 100, W);
            shadows = AddSlider(flow, "어두운 부분 살리기", 0, 100, W);
            saturation = AddSlider(flow, "채도 (색 진하게)", -100, 100, W);
            warmth = AddSlider(flow, "색온도 (차갑게 ↔ 따뜻하게)", -100, 100, W);
            sharpness = AddSlider(flow, "선명하게", 0, 100, W);

            autoLevelsCheck = new CheckBox();
            autoLevelsCheck.Text = "자동 레벨 (흐릿한 사진의 명암 펼치기)";
            autoLevelsCheck.AutoSize = true;
            autoLevelsCheck.Margin = new Padding(0, S(2), 0, S(4));
            autoLevelsCheck.CheckedChanged += delegate
            {
                if (suppressEvents) return;
                adj.AutoLevels = autoLevelsCheck.Checked;
                fxDirty = true;
            };
            flow.Controls.Add(autoLevelsCheck);

            FlowLayoutPanel fxRow = MakeRow(W);
            Button autoBtn = MakeButton("✨ 자동 보정", S(100));
            autoBtn.Click += delegate { AutoEnhance(); };
            tips.SetToolTip(autoBtn, "선택 영역을 분석해서 썸네일용으로 밝고 또렷하게 맞춰줍니다");
            Button resetBtn = MakeButton("초기화", S(70));
            resetBtn.Click += delegate { ResetAdjust(); };
            Button compareBtn = MakeButton("원본 비교", S(84));
            tips.SetToolTip(compareBtn, "누르고 있는 동안 보정 전 원본을 보여줍니다 (캔버스에서 오른쪽 버튼을 눌러도 됨)");
            compareBtn.MouseDown += delegate { comparing = true; canvas.Invalidate(); };
            compareBtn.MouseUp += delegate { comparing = false; canvas.Invalidate(); };
            fxRow.Controls.Add(autoBtn); fxRow.Controls.Add(resetBtn); fxRow.Controls.Add(compareBtn);
            flow.Controls.Add(fxRow);

            // 저장
            flow.Controls.Add(MakeHeader("저장", W));
            sizeCombo = new ComboBox();
            sizeCombo.DropDownStyle = ComboBoxStyle.DropDownList;
            sizeCombo.Width = W;
            foreach (int s in SizeValues)
                sizeCombo.Items.Add(s == 0 ? "원본 해상도 그대로" : string.Format("긴 변 {0}px로 맞추기", s));
            sizeCombo.SelectedIndex = 0;
            sizeCombo.SelectedIndexChanged += delegate { UpdateInfo(); SaveSettings(); };
            flow.Controls.Add(sizeCombo);

            formatCombo = new ComboBox();
            formatCombo.DropDownStyle = ComboBoxStyle.DropDownList;
            formatCombo.Width = W;
            formatCombo.Items.Add("JPG (고화질 95%)");
            formatCombo.Items.Add("PNG (무손실)");
            formatCombo.SelectedIndex = 0;
            formatCombo.Margin = new Padding(0, S(4), 0, 0);
            formatCombo.SelectedIndexChanged += delegate { SaveSettings(); };
            flow.Controls.Add(formatCombo);

            outputLabel = new Label();
            outputLabel.AutoSize = false;
            outputLabel.Size = new Size(W, S(22));
            outputLabel.TextAlign = ContentAlignment.MiddleLeft;
            outputLabel.ForeColor = Color.FromArgb(60, 60, 66);
            flow.Controls.Add(outputLabel);

            FlowLayoutPanel saveRow = MakeRow(W);
            Button saveBtn = MakeButton("저장  (Ctrl+S)", W - S(96));
            saveBtn.Height = S(40);
            saveBtn.BackColor = Color.FromArgb(0, 120, 215);
            saveBtn.ForeColor = Color.White;
            saveBtn.FlatStyle = FlatStyle.Flat;
            saveBtn.FlatAppearance.BorderSize = 0;
            saveBtn.Font = new Font(Font.FontFamily, 10f, FontStyle.Bold);
            saveBtn.Click += delegate { Save(false); };
            tips.SetToolTip(saveBtn, "원본과 같은 폴더에 '파일이름_thumb'로 저장합니다");
            Button saveAsBtn = MakeButton("다른 이름...", S(92));
            saveAsBtn.Height = S(40);
            saveAsBtn.Margin = new Padding(0);
            saveAsBtn.Click += delegate { Save(true); };
            tips.SetToolTip(saveAsBtn, "저장할 위치와 이름을 직접 고르기 (Ctrl+Shift+S)");
            saveRow.Controls.Add(saveBtn);
            saveRow.Controls.Add(saveAsBtn);
            flow.Controls.Add(saveRow);

            statusLink = new LinkLabel();
            statusLink.AutoSize = false;
            statusLink.Size = new Size(W, S(40));
            statusLink.Margin = new Padding(0, S(6), 0, 0);
            statusLink.LinkClicked += delegate
            {
                if (lastSaved != null && File.Exists(lastSaved))
                    Process.Start("explorer.exe", "/select,\"" + lastSaved + "\"");
            };
            flow.Controls.Add(statusLink);


            // 캔버스
            canvas = new Canvas();
            canvas.Dock = DockStyle.Fill;
            canvas.BackColor = BgDark;
            canvas.AllowDrop = true;
            canvas.Paint += OnCanvasPaint;
            canvas.MouseDown += OnCanvasMouseDown;
            canvas.MouseMove += OnCanvasMouseMove;
            canvas.MouseUp += OnCanvasMouseUp;
            canvas.MouseDoubleClick += OnCanvasDoubleClick;
            canvas.MouseWheel += OnCanvasWheel;
            canvas.MouseEnter += delegate { if (ActiveForm == this && !(ActiveControl is ComboBox)) canvas.Focus(); };
            canvas.Resize += delegate { if (source != null) { UpdateViewRect(); viewTimer.Stop(); viewTimer.Start(); } };
            canvas.DragEnter += OnDragEnter;
            canvas.DragDrop += OnDragDrop;

            Panel bar = new Panel();
            bar.Dock = DockStyle.Bottom;
            bar.Height = S(26);
            bar.BackColor = Color.FromArgb(22, 22, 24);
            infoLabel = new Label();
            infoLabel.Dock = DockStyle.Fill;
            infoLabel.ForeColor = Color.FromArgb(200, 200, 205);
            infoLabel.TextAlign = ContentAlignment.MiddleLeft;
            infoLabel.Padding = new Padding(S(8), 0, 0, 0);
            Label hint = new Label();
            hint.Dock = DockStyle.Right;
            hint.AutoSize = true;
            hint.ForeColor = Color.FromArgb(130, 130, 138);
            hint.Padding = new Padding(0, S(6), S(8), 0);
            hint.Text = "휠: 크기 · 방향키: 미세 이동 · 더블클릭: 최대 · 우클릭: 원본 비교";
            bar.Controls.Add(infoLabel);
            bar.Controls.Add(hint);

            Controls.Add(canvas);
            Controls.Add(bar);
            Controls.Add(side);
            ResumeLayout(false);
            PerformLayout();
        }

        Button MakeButton(string text, int width)
        {
            Button b = new Button();
            b.Text = text;
            b.Size = new Size(width, S(28));
            b.Margin = new Padding(0, 0, S(4), 0);
            b.UseVisualStyleBackColor = true;
            return b;
        }

        FlowLayoutPanel MakeRow(int width)
        {
            FlowLayoutPanel p = new FlowLayoutPanel();
            p.FlowDirection = FlowDirection.LeftToRight;
            p.WrapContents = false;
            p.AutoSize = true;
            p.Width = width;
            p.Margin = new Padding(0);
            return p;
        }

        Label MakeHeader(string text, int width)
        {
            Label l = new Label();
            l.Text = text;
            l.AutoSize = false;
            l.Size = new Size(width, S(26));
            l.TextAlign = ContentAlignment.BottomLeft;
            l.Font = new Font(Font.FontFamily, 10f, FontStyle.Bold);
            l.Margin = new Padding(0, S(8), 0, S(2));
            return l;
        }

        TrackBar AddSlider(FlowLayoutPanel flow, string name, int min, int max, int width)
        {
            Panel row = new Panel();
            row.Size = new Size(width, S(18));
            row.Margin = new Padding(0);
            Label n = new Label();
            n.Text = name;
            n.AutoSize = true;
            n.Location = new Point(0, 0);
            Label v = new Label();
            v.Text = "0";
            v.AutoSize = false;
            v.TextAlign = ContentAlignment.TopRight;
            v.Size = new Size(S(50), S(18));
            v.Location = new Point(width - S(50), 0);
            v.Cursor = Cursors.Hand;
            row.Controls.Add(n);
            row.Controls.Add(v);
            flow.Controls.Add(row);

            TrackBar t = new TrackBar();
            t.Minimum = min;
            t.Maximum = max;
            t.Value = 0;
            t.TickStyle = TickStyle.None;
            t.SmallChange = 1;
            t.LargeChange = 10;
            t.AutoSize = false;
            t.Size = new Size(width, S(26));
            t.Margin = new Padding(0, 0, 0, S(2));
            t.BackColor = PanelBg;
            t.ValueChanged += delegate
            {
                v.Text = t.Value > 0 && min < 0 ? "+" + t.Value : t.Value.ToString();
                v.ForeColor = t.Value == 0 ? Color.FromArgb(120, 120, 128) : Color.FromArgb(0, 100, 200);
                if (suppressEvents) return;
                ReadSliders();
                fxDirty = true;
            };
            v.Click += delegate { t.Value = 0; };
            tips.SetToolTip(v, "클릭하면 0으로");
            v.ForeColor = Color.FromArgb(120, 120, 128);
            flow.Controls.Add(t);
            sliders.Add(t);
            return t;
        }

        Icon MakeIcon()
        {
            try
            {
                using (Bitmap b = new Bitmap(32, 32))
                {
                    using (Graphics g = Graphics.FromImage(b))
                    {
                        g.SmoothingMode = SmoothingMode.AntiAlias;
                        g.Clear(Color.Transparent);
                        using (SolidBrush bg = new SolidBrush(Color.FromArgb(0, 120, 215)))
                            g.FillRectangle(bg, 2, 2, 28, 28);
                        using (Pen p = new Pen(Color.White, 3f))
                        {
                            g.DrawLines(p, new Point[] { new Point(9, 4), new Point(9, 23), new Point(28, 23) });
                            g.DrawLines(p, new Point[] { new Point(4, 9), new Point(23, 9), new Point(23, 28) });
                        }
                    }
                    return Icon.FromHandle(b.GetHicon());
                }
            }
            catch { return null; }
        }

        // ---------------- 파일 ----------------
        static List<string> ExpandPaths(IEnumerable<string> paths)
        {
            List<string> result = new List<string>();
            foreach (string p in paths)
            {
                if (string.IsNullOrEmpty(p)) continue;
                if (Directory.Exists(p))
                {
                    List<string> inDir = new List<string>();
                    foreach (string f in Directory.GetFiles(p))
                        if (ImageIO.IsImage(f)) inDir.Add(f);
                    inDir.Sort(StringComparer.OrdinalIgnoreCase);
                    result.AddRange(inDir);
                }
                else if (File.Exists(p) && ImageIO.IsImage(p))
                {
                    result.Add(Path.GetFullPath(p));
                }
            }
            return result;
        }

        void OpenDialog()
        {
            using (OpenFileDialog d = new OpenFileDialog())
            {
                d.Title = "이미지 열기";
                d.Multiselect = true;
                string pattern = "*" + string.Join(";*", ImageIO.Extensions);
                d.Filter = "이미지 (" + pattern + ")|" + pattern + "|모든 파일 (*.*)|*.*";
                if (fileIndex >= 0) d.InitialDirectory = Path.GetDirectoryName(files[fileIndex]);
                if (d.ShowDialog(this) != DialogResult.OK) return;
                List<string> list = ExpandPaths(d.FileNames);
                if (list.Count == 0) return;
                files = list;
                OpenIndex(0);
            }
        }

        void OnDragEnter(object sender, DragEventArgs e)
        {
            e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        }

        void OnDragDrop(object sender, DragEventArgs e)
        {
            string[] dropped = e.Data.GetData(DataFormats.FileDrop) as string[];
            if (dropped == null) return;
            List<string> list = ExpandPaths(dropped);
            if (list.Count == 0)
            {
                MessageBox.Show(this, "이미지 파일이 아닙니다.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            files = list;
            OpenIndex(0);
        }

        void OpenIndex(int index)
        {
            if (index < 0 || index >= files.Count) return;
            Bitmap loaded;
            try
            {
                Cursor = Cursors.WaitCursor;
                loaded = ImageIO.Load(files[index]);
            }
            catch (Exception ex)
            {
                Cursor = Cursors.Default;
                MessageBox.Show(this, ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            Cursor = Cursors.Default;
            if (source != null) source.Dispose();
            source = loaded;
            fileIndex = index;
            sel = MaxSel(new PointF(source.Width / 2f, source.Height / 2f));
            statusLink.Text = "";
            lastSaved = null;
            UpdateViewRect();
            RebuildBase();
            UpdateNav();
            UpdateInfo();
            canvas.Focus();
        }

        void UpdateNav()
        {
            bool many = files.Count > 1;
            navRow.Visible = many;
            prevBtn.Enabled = many && fileIndex > 0;
            nextBtn.Enabled = many && fileIndex < files.Count - 1;
            counterLabel.Text = files.Count > 0 && fileIndex >= 0 ? string.Format("{0} / {1}", fileIndex + 1, files.Count) : "";
            if (fileIndex >= 0)
            {
                string name = Path.GetFileName(files[fileIndex]);
                fileLabel.Text = string.Format("{0}\n{1} × {2} px", name, source.Width, source.Height);
                Text = "썸네일 크롭 - " + name;
            }
        }

        void Rotate(RotateFlipType t)
        {
            if (source == null) return;
            source.RotateFlip(t);
            sel = MaxSel(new PointF(source.Width / 2f, source.Height / 2f));
            UpdateViewRect();
            RebuildBase();
            UpdateNav();
            UpdateInfo();
            canvas.Focus();
        }

        // ---------------- 화면용 이미지 ----------------
        void UpdateViewRect()
        {
            if (source == null) return;
            int pad = S(16);
            int cw = Math.Max(1, canvas.ClientSize.Width - 2 * pad);
            int ch = Math.Max(1, canvas.ClientSize.Height - 2 * pad);
            float scale = Math.Min((float)cw / source.Width, (float)ch / source.Height);
            scale = Math.Min(scale, 8f);
            int w = Math.Max(1, (int)Math.Round(source.Width * scale));
            int h = Math.Max(1, (int)Math.Round(source.Height * scale));
            viewRect = new Rectangle((canvas.ClientSize.Width - w) / 2, (canvas.ClientSize.Height - h) / 2, w, h);
            canvas.Invalidate();
        }

        void RebuildBase()
        {
            if (source == null) return;
            UpdateViewRect();
            Bitmap b = new Bitmap(viewRect.Width, viewRect.Height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(b))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingMode = CompositingMode.SourceCopy;
                using (ImageAttributes ia = new ImageAttributes())
                {
                    ia.SetWrapMode(WrapMode.TileFlipXY);
                    g.DrawImage(source, new Rectangle(0, 0, b.Width, b.Height), 0, 0, source.Width, source.Height, GraphicsUnit.Pixel, ia);
                }
            }
            if (baseView != null) baseView.Dispose();
            baseView = b;
            RebuildFx();
        }

        void UpdateLevels()
        {
            if (!adj.AutoLevels || baseView == null) return;
            int[] hist = Filters.LumaHistogram(baseView, Rectangle.Round(ImgToView(sel)));
            Filters.ComputeLevels(hist, out adj.Black, out adj.White);
        }

        void RebuildFx()
        {
            fxDirty = false;
            if (baseView == null) return;
            UpdateLevels();
            Bitmap f = null;
            if (!adj.IsIdentity)
            {
                f = new Bitmap(baseView);
                Filters.Apply(f, adj);
            }
            if (fxView != null) fxView.Dispose();
            fxView = f;
            canvas.Invalidate();
        }

        // 원본 좌표 → baseView 비트맵 좌표
        RectangleF ImgToView(RectangleF r)
        {
            float s = (float)viewRect.Width / source.Width;
            return new RectangleF(r.X * s, r.Y * s, r.Width * s, r.Height * s);
        }

        RectangleF ImgToScreen(RectangleF r)
        {
            RectangleF v = ImgToView(r);
            v.Offset(viewRect.X, viewRect.Y);
            return v;
        }

        PointF ScreenToImg(Point p, bool clamp)
        {
            float s = (float)viewRect.Width / source.Width;
            float x = (p.X - viewRect.X) / s, y = (p.Y - viewRect.Y) / s;
            if (clamp)
            {
                x = Math.Max(0, Math.Min(source.Width, x));
                y = Math.Max(0, Math.Min(source.Height, y));
            }
            return new PointF(x, y);
        }

        // ---------------- 그리기 ----------------
        void OnCanvasPaint(object sender, PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            if (source == null || baseView == null)
            {
                using (Brush b = new SolidBrush(Color.FromArgb(150, 150, 158)))
                using (Font f = new Font(Font.FontFamily, 13f))
                using (StringFormat sf = new StringFormat())
                {
                    sf.Alignment = StringAlignment.Center;
                    sf.LineAlignment = StringAlignment.Center;
                    g.DrawString("이미지를 여기로 끌어다 놓거나\n오른쪽 [이미지 열기...]를 누르세요\n\n(여러 장을 한 번에 놓으면 PageUp / PageDown으로 넘기며 작업)", f, b, canvas.ClientRectangle, sf);
                }
                return;
            }

            Bitmap show = comparing || fxView == null ? baseView : fxView;
            bool exact = show.Width == viewRect.Width && show.Height == viewRect.Height;
            g.InterpolationMode = exact ? InterpolationMode.NearestNeighbor : InterpolationMode.Bilinear;
            g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(show, viewRect);
            g.PixelOffsetMode = PixelOffsetMode.Default;

            RectangleF s = ImgToScreen(sel);
            using (Region outside = new Region(viewRect))
            using (Brush shade = new SolidBrush(Color.FromArgb(160, 0, 0, 0)))
            {
                outside.Exclude(s);
                g.FillRegion(shade, outside);
            }

            using (Pen grid = new Pen(Color.FromArgb(90, 255, 255, 255), 1f))
            {
                for (int i = 1; i <= 2; i++)
                {
                    float x = s.X + s.Width * i / 3f, y = s.Y + s.Height * i / 3f;
                    g.DrawLine(grid, x, s.Top, x, s.Bottom);
                    g.DrawLine(grid, s.Left, y, s.Right, y);
                }
            }
            using (Pen border = new Pen(Color.White, Math.Max(1f, dpi)))
                g.DrawRectangle(border, s.X, s.Y, s.Width, s.Height);

            float hs = S(9);
            using (Brush hb = new SolidBrush(Color.White))
            using (Pen hp = new Pen(Color.FromArgb(40, 40, 40), 1f))
            {
                foreach (PointF p in HandlePoints(s))
                {
                    if (p.IsEmpty) continue;
                    g.FillRectangle(hb, p.X - hs / 2, p.Y - hs / 2, hs, hs);
                    g.DrawRectangle(hp, p.X - hs / 2, p.Y - hs / 2, hs, hs);
                }
            }

            Rectangle crop = CropRect();
            string sizeText = string.Format("{0} × {1}", crop.Width, crop.Height);
            DrawBadge(g, sizeText, new PointF(s.X + S(6), s.Y + S(6)));
            if (comparing) DrawBadge(g, "원본 (보정 전)", new PointF(S(10), S(10)));
        }

        void DrawBadge(Graphics g, string text, PointF at)
        {
            SizeF sz = g.MeasureString(text, Font);
            using (Brush bg = new SolidBrush(Color.FromArgb(170, 0, 0, 0)))
                g.FillRectangle(bg, at.X, at.Y, sz.Width + S(6), sz.Height + S(2));
            using (Brush fg = new SolidBrush(Color.White))
                g.DrawString(text, Font, fg, at.X + S(3), at.Y + S(1));
        }

        // 순서: NW, N, NE, E, SE, S, SW, W (변 핸들은 영역이 작으면 생략)
        PointF[] HandlePoints(RectangleF s)
        {
            float mx = s.X + s.Width / 2, my = s.Y + s.Height / 2;
            bool edges = s.Width > S(60) && s.Height > S(60);
            return new PointF[] {
                new PointF(s.Left, s.Top), edges ? new PointF(mx, s.Top) : PointF.Empty,
                new PointF(s.Right, s.Top), edges ? new PointF(s.Right, my) : PointF.Empty,
                new PointF(s.Right, s.Bottom), edges ? new PointF(mx, s.Bottom) : PointF.Empty,
                new PointF(s.Left, s.Bottom), edges ? new PointF(s.Left, my) : PointF.Empty };
        }

        // ---------------- 마우스 ----------------
        Hit HitTest(Point p)
        {
            RectangleF s = ImgToScreen(sel);
            float tol = S(9);
            Hit[] order = { Hit.NW, Hit.N, Hit.NE, Hit.E, Hit.SE, Hit.S, Hit.SW, Hit.W };
            PointF[] pts = HandlePoints(s);
            // 모서리 우선
            for (int i = 0; i < 8; i += 2)
                if (Math.Abs(p.X - pts[i].X) <= tol && Math.Abs(p.Y - pts[i].Y) <= tol) return order[i];
            bool inY = p.Y > s.Top + tol && p.Y < s.Bottom - tol;
            bool inX = p.X > s.Left + tol && p.X < s.Right - tol;
            if (inY && Math.Abs(p.X - s.Left) <= tol) return Hit.W;
            if (inY && Math.Abs(p.X - s.Right) <= tol) return Hit.E;
            if (inX && Math.Abs(p.Y - s.Top) <= tol) return Hit.N;
            if (inX && Math.Abs(p.Y - s.Bottom) <= tol) return Hit.S;
            if (s.Contains(p)) return Hit.Move;
            return Hit.None;
        }

        static Cursor CursorFor(Hit h)
        {
            switch (h)
            {
                case Hit.NW: case Hit.SE: return Cursors.SizeNWSE;
                case Hit.NE: case Hit.SW: return Cursors.SizeNESW;
                case Hit.N: case Hit.S: return Cursors.SizeNS;
                case Hit.E: case Hit.W: return Cursors.SizeWE;
                case Hit.Move: return Cursors.SizeAll;
                default: return Cursors.Cross;
            }
        }

        void OnCanvasMouseDown(object sender, MouseEventArgs e)
        {
            canvas.Focus();
            if (source == null) return;
            if (e.Button == MouseButtons.Right)
            {
                comparing = true;
                canvas.Invalidate();
                return;
            }
            if (e.Button != MouseButtons.Left) return;

            Hit h = HitTest(e.Location);
            downScreen = e.Location;
            dragStartSel = sel;
            dragStartImg = ScreenToImg(e.Location, false);
            switch (h)
            {
                case Hit.NW: anchor = new PointF(sel.Right, sel.Bottom); break;
                case Hit.NE: anchor = new PointF(sel.Left, sel.Bottom); break;
                case Hit.SE: anchor = new PointF(sel.Left, sel.Top); break;
                case Hit.SW: anchor = new PointF(sel.Right, sel.Top); break;
                case Hit.None:
                    h = Hit.New;
                    anchor = ScreenToImg(e.Location, true);
                    newMoved = false;
                    break;
            }
            drag = h;
        }

        void OnCanvasMouseMove(object sender, MouseEventArgs e)
        {
            if (source == null) return;
            if (drag == Hit.None)
            {
                canvas.Cursor = CursorFor(HitTest(e.Location));
                return;
            }
            PointF p = ScreenToImg(e.Location, true);
            switch (drag)
            {
                case Hit.Move:
                    PointF raw = ScreenToImg(e.Location, false);
                    float x = dragStartSel.X + raw.X - dragStartImg.X;
                    float y = dragStartSel.Y + raw.Y - dragStartImg.Y;
                    sel = new RectangleF(ClampPos(x, sel.Width, source.Width), ClampPos(y, sel.Height, source.Height), sel.Width, sel.Height);
                    break;
                case Hit.NW: case Hit.NE: case Hit.SE: case Hit.SW:
                    sel = ResizeFromAnchor(anchor, p);
                    break;
                case Hit.New:
                    if (!newMoved && Math.Abs(e.X - downScreen.X) + Math.Abs(e.Y - downScreen.Y) < S(5)) return;
                    newMoved = true;
                    sel = ResizeFromAnchor(anchor, p);
                    break;
                default:
                    sel = ResizeEdge(drag, p);
                    break;
            }
            SelChanged();
        }

        void OnCanvasMouseUp(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right && comparing)
            {
                comparing = false;
                canvas.Invalidate();
            }
            if (e.Button == MouseButtons.Left) drag = Hit.None;
        }

        void OnCanvasDoubleClick(object sender, MouseEventArgs e)
        {
            if (source == null || e.Button != MouseButtons.Left) return;
            sel = MaxSel(Center(sel));
            SelChanged();
        }

        void OnCanvasWheel(object sender, MouseEventArgs e)
        {
            if (source == null) return;
            float f = e.Delta > 0 ? 1.06f : 1f / 1.06f;
            PointF c = Center(sel);
            float w = sel.Width * f, h = sel.Height * f;
            float fit = Math.Min(1f, Math.Min(source.Width / w, source.Height / h));
            if (ratio > 0) { w *= fit; h *= fit; }
            else { w = Math.Min(w, source.Width); h = Math.Min(h, source.Height); }
            EnforceMin(ref w, ref h);
            sel = Place(c, w, h);
            SelChanged();
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            Keys key = keyData & Keys.KeyCode;
            bool ctrl = (keyData & Keys.Control) != 0, shift = (keyData & Keys.Shift) != 0;
            if (ctrl && key == Keys.S) { Save(shift); return true; }
            if (ctrl && key == Keys.O) { OpenDialog(); return true; }
            if (key == Keys.PageDown) { OpenIndex(fileIndex + 1); return true; }
            if (key == Keys.PageUp) { OpenIndex(fileIndex - 1); return true; }
            if (source != null && ActiveControl == canvas
                && (key == Keys.Left || key == Keys.Right || key == Keys.Up || key == Keys.Down))
            {
                float step = shift ? 10f : 1f;
                float dx = key == Keys.Left ? -step : key == Keys.Right ? step : 0;
                float dy = key == Keys.Up ? -step : key == Keys.Down ? step : 0;
                sel = new RectangleF(ClampPos(sel.X + dx, sel.Width, source.Width),
                                     ClampPos(sel.Y + dy, sel.Height, source.Height), sel.Width, sel.Height);
                SelChanged();
                return true;
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        // ---------------- 영역 계산 (원본 픽셀 좌표) ----------------
        float MinSize { get { return Math.Min(16f, Math.Min(source.Width, source.Height)); } }

        static PointF Center(RectangleF r) { return new PointF(r.X + r.Width / 2, r.Y + r.Height / 2); }

        static float ClampPos(float pos, float size, float total)
        {
            return Math.Max(0, Math.Min(total - size, pos));
        }

        void EnforceMin(ref float w, ref float h)
        {
            float m = MinSize;
            if (ratio > 0)
            {
                if (w < m) { w = m; h = w / ratio; }
                if (h < m) { h = m; w = h * ratio; }
            }
            else { w = Math.Max(w, m); h = Math.Max(h, m); }
        }

        RectangleF Place(PointF center, float w, float h)
        {
            w = Math.Min(w, source.Width);
            h = Math.Min(h, source.Height);
            return new RectangleF(ClampPos(center.X - w / 2, w, source.Width),
                                  ClampPos(center.Y - h / 2, h, source.Height), w, h);
        }

        RectangleF MaxSel(PointF center)
        {
            float W = source.Width, H = source.Height, w, h;
            if (ratio > 0)
            {
                if (W / H > ratio) { h = H; w = H * ratio; } else { w = W; h = W / ratio; }
            }
            else { w = W; h = H; }
            return Place(center, w, h);
        }

        // 고정점(anchor)에서 마우스(p)까지 - 모서리 드래그 / 새로 그리기
        RectangleF ResizeFromAnchor(PointF a, PointF p)
        {
            float dx = p.X - a.X, dy = p.Y - a.Y;
            bool right = dx >= 0, down = dy >= 0;
            float w = Math.Abs(dx), h = Math.Abs(dy);
            float maxW = right ? source.Width - a.X : a.X;
            float maxH = down ? source.Height - a.Y : a.Y;
            if (ratio > 0)
            {
                if (w / ratio > h) h = w / ratio; else w = h * ratio;
                if (w > maxW) { w = maxW; h = w / ratio; }
                if (h > maxH) { h = maxH; w = h * ratio; }
            }
            else { w = Math.Min(w, maxW); h = Math.Min(h, maxH); }
            EnforceMin(ref w, ref h);
            float x = right ? a.X : a.X - w;
            float y = down ? a.Y : a.Y - h;
            return new RectangleF(ClampPos(x, w, source.Width), ClampPos(y, h, source.Height), w, h);
        }

        // 변 드래그. 비율이 고정이면 반대쪽 축은 가운데를 기준으로 같이 늘어남
        RectangleF ResizeEdge(Hit edge, PointF p)
        {
            RectangleF s = dragStartSel;
            float W = source.Width, H = source.Height, m = MinSize;
            PointF c = Center(s);
            if (edge == Hit.E || edge == Hit.W)
            {
                float w = edge == Hit.E ? p.X - s.Left : s.Right - p.X;
                w = Math.Max(m, Math.Min(edge == Hit.E ? W - s.Left : s.Right, w));
                float x = edge == Hit.E ? s.Left : s.Right - w;
                if (ratio <= 0) return new RectangleF(x, s.Y, w, s.Height);
                float h = w / ratio;
                if (h > H) { h = H; w = h * ratio; x = edge == Hit.E ? s.Left : s.Right - w; }
                if (h < m) { h = m; w = h * ratio; x = edge == Hit.E ? s.Left : s.Right - w; }
                return new RectangleF(x, ClampPos(c.Y - h / 2, h, H), w, h);
            }
            else
            {
                float h = edge == Hit.S ? p.Y - s.Top : s.Bottom - p.Y;
                h = Math.Max(m, Math.Min(edge == Hit.S ? H - s.Top : s.Bottom, h));
                float y = edge == Hit.S ? s.Top : s.Bottom - h;
                if (ratio <= 0) return new RectangleF(s.X, y, s.Width, h);
                float w = h * ratio;
                if (w > W) { w = W; h = w / ratio; y = edge == Hit.S ? s.Top : s.Bottom - h; }
                if (w < m) { w = m; h = w / ratio; y = edge == Hit.S ? s.Top : s.Bottom - h; }
                return new RectangleF(ClampPos(c.X - w / 2, w, W), y, w, h);
            }
        }

        void SetRatio(float r)
        {
            ratio = r;
            if (source != null && r > 0)
            {
                // 넓이를 비슷하게 유지하면서 새 비율로
                float area = sel.Width * sel.Height;
                float w = (float)Math.Sqrt(area * r), h = w / r;
                float fit = Math.Min(1f, Math.Min(source.Width / w, source.Height / h));
                w *= fit; h *= fit;
                EnforceMin(ref w, ref h);
                sel = Place(Center(sel), w, h);
            }
            SelChanged();
            SaveSettings();
            canvas.Focus();
        }

        void SelChanged()
        {
            if (adj.AutoLevels) fxDirty = true;
            UpdateInfo();
            canvas.Invalidate();
        }

        // ---------------- 출력 ----------------
        Rectangle CropRect()
        {
            int x = (int)Math.Round(sel.X), y = (int)Math.Round(sel.Y);
            int w = (int)Math.Round(sel.Width), h = (int)Math.Round(sel.Height);
            w = Math.Max(1, Math.Min(w, source.Width - x));
            h = Math.Max(1, Math.Min(h, source.Height - y));
            return new Rectangle(x, y, w, h);
        }

        Size OutputSize(Rectangle crop)
        {
            int target = SizeValues[Math.Max(0, sizeCombo.SelectedIndex)];
            if (target == 0)
            {
                if (ratio > 0) return new Size(crop.Width, Math.Max(1, (int)Math.Round(crop.Width / ratio)));
                return crop.Size;
            }
            float r = ratio > 0 ? ratio : (float)crop.Width / crop.Height;
            if (r >= 1) return new Size(target, Math.Max(1, (int)Math.Round(target / r)));
            return new Size(Math.Max(1, (int)Math.Round(target * r)), target);
        }

        void UpdateInfo()
        {
            if (source == null) { infoLabel.Text = ""; outputLabel.Text = ""; return; }
            Rectangle c = CropRect();
            Size o = OutputSize(c);
            infoLabel.Text = string.Format("원본 {0} × {1}    ·    선택 {2} × {3}  (x {4}, y {5})",
                source.Width, source.Height, c.Width, c.Height, c.X, c.Y);
            string warn = o.Width > c.Width * 1.01 ? "  ⚠ 확대됨" : "";
            outputLabel.Text = string.Format("→ 저장 크기 {0} × {1} px{2}", o.Width, o.Height, warn);
            outputLabel.ForeColor = warn.Length > 0 ? Color.FromArgb(200, 110, 0) : Color.FromArgb(60, 60, 66);
        }

        public Bitmap RenderOutput()
        {
            Rectangle c = CropRect();
            Size o = OutputSize(c);
            Bitmap dst = new Bitmap(o.Width, o.Height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(dst))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingMode = CompositingMode.SourceCopy;
                g.CompositingQuality = CompositingQuality.HighQuality;
                using (ImageAttributes ia = new ImageAttributes())
                {
                    ia.SetWrapMode(WrapMode.TileFlipXY);
                    g.DrawImage(source, new Rectangle(0, 0, o.Width, o.Height), c.X, c.Y, c.Width, c.Height, GraphicsUnit.Pixel, ia);
                }
            }
            if (adj.AutoLevels) UpdateLevels();
            Filters.Apply(dst, adj);
            return dst;
        }

        void Save(bool askPath)
        {
            if (source == null) return;
            bool jpeg = formatCombo.SelectedIndex == 0;
            string ext = jpeg ? ".jpg" : ".png";
            string srcPath = files[fileIndex];
            string dir = Path.GetDirectoryName(srcPath);
            string baseName = Path.GetFileNameWithoutExtension(srcPath) + "_thumb";
            string path = Path.Combine(dir, baseName + ext);
            for (int n = 2; File.Exists(path); n++) path = Path.Combine(dir, baseName + n + ext);

            if (askPath)
            {
                using (SaveFileDialog d = new SaveFileDialog())
                {
                    d.Title = "다른 이름으로 저장";
                    d.InitialDirectory = dir;
                    d.FileName = Path.GetFileName(path);
                    d.Filter = jpeg ? "JPG 이미지 (*.jpg)|*.jpg" : "PNG 이미지 (*.png)|*.png";
                    if (d.ShowDialog(this) != DialogResult.OK) return;
                    path = d.FileName;
                }
            }

            try
            {
                Cursor = Cursors.WaitCursor;
                using (Bitmap outBmp = RenderOutput())
                {
                    ImageIO.Save(outBmp, path, jpeg, 95);
                    lastSaved = path;
                    statusLink.Text = string.Format("✔ 저장됨: {0} ({1}×{2})  폴더 열기", Path.GetFileName(path), outBmp.Width, outBmp.Height);
                    int linkStart = statusLink.Text.Length - "폴더 열기".Length;
                    statusLink.LinkArea = new LinkArea(linkStart, "폴더 열기".Length);
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "저장하지 못했습니다:\n" + ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally { Cursor = Cursors.Default; }
        }

        // ---------------- 보정 ----------------
        void ReadSliders()
        {
            adj.Brightness = brightness.Value;
            adj.Contrast = contrast.Value;
            adj.Shadows = shadows.Value;
            adj.Saturation = saturation.Value;
            adj.Warmth = warmth.Value;
            adj.Sharpness = sharpness.Value;
        }

        void SetSliders(int b, int c, int sh, int sat, int warm, int sharp, bool levels)
        {
            suppressEvents = true;
            brightness.Value = b; contrast.Value = c; shadows.Value = sh;
            saturation.Value = sat; warmth.Value = warm; sharpness.Value = sharp;
            autoLevelsCheck.Checked = levels;
            suppressEvents = false;
            ReadSliders();
            adj.AutoLevels = levels;
            fxDirty = true;
        }

        void ResetAdjust()
        {
            SetSliders(0, 0, 0, 0, 0, 0, false);
            canvas.Focus();
        }

        // 선택 영역의 밝기 분포를 보고 썸네일용 기본값을 정함
        void AutoEnhance()
        {
            if (baseView == null) return;
            int[] hist = Filters.LumaHistogram(baseView, Rectangle.Round(ImgToView(sel)));
            float black, white;
            Filters.ComputeLevels(hist, out black, out white);

            long total = 0; double sum = 0; long dark = 0;
            for (int i = 0; i < 256; i++)
            {
                double v = (i / 255.0 - black) / (white - black);
                v = Math.Max(0, Math.Min(1, v));
                total += hist[i];
                sum += v * hist[i];
                if (v < 0.25) dark += hist[i];
            }
            double mean = total > 0 ? sum / total : 0.5;
            mean = Math.Max(0.05, Math.Min(0.95, mean));
            // pow(mean, gamma) ≈ 0.52 가 되도록, gamma = 2^(-b/100)
            double gamma = Math.Log(0.52) / Math.Log(mean);
            int b = (int)Math.Round(-100 * Math.Log(gamma, 2));
            b = Math.Max(-25, Math.Min(55, b));
            int sh = total > 0 && dark > total / 4 ? 30 : 12;

            SetSliders(b, 12, sh, 18, 0, 35, true);
            canvas.Focus();
        }

        // ---------------- 설정 저장 ----------------
        static string SettingsPath
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ThumbCrop", "settings.txt"); }
        }

        void LoadSettings()
        {
            int ratioIdx = 0, sizeIdx = 0, fmt = 0;
            try
            {
                if (File.Exists(SettingsPath))
                {
                    foreach (string line in File.ReadAllLines(SettingsPath))
                    {
                        string[] kv = line.Split('=');
                        if (kv.Length != 2) continue;
                        int v;
                        if (!int.TryParse(kv[1].Trim(), out v)) continue;
                        switch (kv[0].Trim())
                        {
                            case "ratio": ratioIdx = v; break;
                            case "size": sizeIdx = v; break;
                            case "format": fmt = v; break;
                        }
                    }
                }
            }
            catch { }
            suppressEvents = true;
            if (ratioIdx < 0 || ratioIdx >= RatioValues.Length) ratioIdx = 0;
            ratioButtons[ratioIdx].Checked = true;
            ratio = RatioValues[ratioIdx];
            if (sizeIdx >= 0 && sizeIdx < sizeCombo.Items.Count) sizeCombo.SelectedIndex = sizeIdx;
            if (fmt >= 0 && fmt < formatCombo.Items.Count) formatCombo.SelectedIndex = fmt;
            suppressEvents = false;
        }

        void SaveSettings()
        {
            if (suppressEvents || ratioButtons == null) return;
            try
            {
                int ratioIdx = 0;
                for (int i = 0; i < ratioButtons.Length; i++) if (ratioButtons[i].Checked) ratioIdx = i;
                Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath));
                File.WriteAllLines(SettingsPath, new string[] {
                    "ratio=" + ratioIdx, "size=" + sizeCombo.SelectedIndex, "format=" + formatCombo.SelectedIndex });
            }
            catch { }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            fxTimer.Stop();
            base.OnFormClosed(e);
        }
    }
}
