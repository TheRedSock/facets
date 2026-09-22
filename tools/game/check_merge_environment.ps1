param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$Output,
    [ValidateSet('cpu','native','characterization','closeout')][string]$Mode = 'native',
    [int]$Seeds = 100, [int]$Repetitions = 3,
    [int]$GpuIndex = 0,
    [int]$MaxFps = -1,
    [switch]$AlwaysOnTop,
    [int]$Width = 1280, [int]$Height = 720,
    [int]$Multiplier = 1,
    [switch]$AllowIdle
)
# Process-scoped diagnostic only. No power-plan, driver, lock or user-input change.
$ErrorActionPreference='Stop'
$outputPath=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $outputPath){throw 'Environment report must be fresh'}
New-Item -ItemType Directory -Path $outputPath|Out-Null
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class FacetsEnvironmentProbe {
    [StructLayout(LayoutKind.Sequential)] struct LastInput { public uint size; public uint time; }
    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LastInput info);
    [DllImport("user32.dll",SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool GetUserObjectInformation(IntPtr obj,int index,StringBuilder value,int size,out int needed);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr window,int index);
    [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action,uint parameter,out bool value,uint flags);
    public sealed class Sample {
        public string utc; public long monotonic_ms; public uint idle_ms;
        public bool input_read_ok; public bool desktop_available; public bool default_desktop;
        public bool foreground_facets; public bool screensaver; public bool screensaver_read_ok;
        public bool foreground_read_available;
        public int facets_windows; public int visible_facets_windows; public int minimized_facets_windows; public int topmost_facets_windows;
    }
    static Thread worker; static volatile bool stop; static bool keepAwake;
    public static bool awake_request_succeeded; public static bool awake_request_released;
    public static List<Sample> samples = new List<Sample>();
    public static void Start(bool awake) {
        keepAwake=awake; stop=false; samples.Clear();
        awake_request_succeeded=false; awake_request_released=false;
        worker=new Thread(Run); worker.IsBackground=true; worker.Start();
    }
    static void Run() {
        uint prior=0;
        try {
            if(keepAwake) { prior=SetThreadExecutionState(0x80000003); awake_request_succeeded=prior!=0; }
            while(!stop) {
                var s=new Sample(); s.utc=DateTime.UtcNow.ToString("O"); s.monotonic_ms=Environment.TickCount64;
                var li=new LastInput(); li.size=(uint)Marshal.SizeOf<LastInput>();
                s.input_read_ok=GetLastInputInfo(ref li); s.idle_ms=unchecked((uint)Environment.TickCount-li.time);
                var desktop=OpenInputDesktop(0,false,1); s.desktop_available=desktop!=IntPtr.Zero;
                if(desktop!=IntPtr.Zero) {
                    try { var name=new StringBuilder(256); int needed; s.default_desktop=GetUserObjectInformation(desktop,2,name,512,out needed)&&name.ToString()=="Default"; }
                    finally { CloseDesktop(desktop); }
                }
                s.screensaver_read_ok=SystemParametersInfo(0x0072,0,out s.screensaver,0);
                var foreground=GetForegroundWindow(); s.foreground_read_available=foreground!=IntPtr.Zero;
                uint pid; GetWindowThreadProcessId(foreground,out pid);
                try { using(var process=Process.GetProcessById((int)pid)) s.foreground_facets=process.ProcessName=="Facets"; } catch {}
                foreach(var process in Process.GetProcessesByName("Facets")) {
                    using(process) { try {
                        var window=process.MainWindowHandle;
                        if(window==IntPtr.Zero) continue;
                        s.facets_windows++;
                        if(IsWindowVisible(window)) s.visible_facets_windows++;
                        if(IsIconic(window)) s.minimized_facets_windows++;
                        if((GetWindowLongPtr(window,-20).ToInt64()&8)!=0) s.topmost_facets_windows++;
                    } catch {} }
                }
                samples.Add(s); Thread.Sleep(100);
            }
        } finally { if(keepAwake&&prior!=0) awake_request_released=SetThreadExecutionState(prior)!=0; }
    }
    public static void Stop() { stop=true; if(worker!=null&&!worker.Join(2000)) throw new TimeoutException("Environment observer did not stop"); }
}
'@
$began=Get-Date
[FacetsEnvironmentProbe]::Start(-not $AllowIdle)
try {
    if($Mode -eq 'closeout') {
        & (Join-Path $PSScriptRoot 'verify_closeout_release.ps1') -Package $Package -OutputRoot (Join-Path $outputPath 'release') -GpuIndex $GpuIndex -AlwaysOnTop:$AlwaysOnTop
    } else {
    & (Join-Path $PSScriptRoot '../check_merge_release.ps1') -Package $Package -Output (Join-Path $outputPath 'release') -Mode $Mode -Seeds $Seeds -Repetitions $Repetitions -GpuIndex $GpuIndex -MaxFps $MaxFps -AlwaysOnTop:$AlwaysOnTop -Width $Width -Height $Height -Multiplier $Multiplier
    }
} finally {
    [FacetsEnvironmentProbe]::Stop()
    [FacetsEnvironmentProbe]::samples|ConvertTo-Json -Depth 4|Set-Content (Join-Path $outputPath 'environment-samples.json') -Encoding utf8
    [ordered]@{schema=1;started=$began.ToString('o');finished=(Get-Date).ToString('o');keep_awake=(-not $AllowIdle);awake_request_succeeded=[FacetsEnvironmentProbe]::awake_request_succeeded;awake_request_released=[FacetsEnvironmentProbe]::awake_request_released;samples=[FacetsEnvironmentProbe]::samples.Count;note='100ms observations; input-desktop availability is a lock/desktop indicator, not a security audit. No input is synthesized; screenshots/windows titles are not collected. Sleep/display request cannot prevent manual lock/lid close.'}|ConvertTo-Json|Set-Content (Join-Path $outputPath 'environment.json') -Encoding utf8
}
$resultFile=if($Mode -eq 'closeout'){'release/release.json'}else{'release/run.json'}
$result=Get-Content (Join-Path $outputPath $resultFile) -Raw|ConvertFrom-Json
if(-not $AllowIdle -and (-not [FacetsEnvironmentProbe]::awake_request_succeeded -or -not [FacetsEnvironmentProbe]::awake_request_released)){throw 'Temporary keep-awake request did not acquire/release successfully'}
if($Mode -eq 'closeout') {if($result.status -ne 'passed'){exit 1}}
elseif(-not $result.passed){exit 1}
