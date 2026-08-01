[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [uint32]$ProcessId
)

$ErrorActionPreference = "Stop"

if (-not ("CatDesk.ConsoleInput" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace CatDesk {
    public static class ConsoleInput {
        private const int STD_INPUT_HANDLE = -10;
        private const ushort KEY_EVENT = 0x0001;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool FreeConsole();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AttachConsole(uint dwProcessId);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetStdHandle(int nStdHandle);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "WriteConsoleInputW")]
        private static extern bool WriteConsoleInput(
            IntPtr hConsoleInput,
            INPUT_RECORD[] lpBuffer,
            uint nLength,
            out uint lpNumberOfEventsWritten
        );

        [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)]
        public struct KEY_EVENT_RECORD {
            [FieldOffset(0), MarshalAs(UnmanagedType.Bool)]
            public bool bKeyDown;
            [FieldOffset(4)]
            public ushort wRepeatCount;
            [FieldOffset(6)]
            public ushort wVirtualKeyCode;
            [FieldOffset(8)]
            public ushort wVirtualScanCode;
            [FieldOffset(10)]
            public char UnicodeChar;
            [FieldOffset(12)]
            public uint dwControlKeyState;
        }

        [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)]
        public struct INPUT_RECORD {
            [FieldOffset(0)]
            public ushort EventType;
            [FieldOffset(4)]
            public KEY_EVENT_RECORD KeyEvent;
        }

        public static void SendOne(uint processId) {
            FreeConsole();
            if (!AttachConsole(processId)) {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "AttachConsole failed");
            }
            try {
                IntPtr input = GetStdHandle(STD_INPUT_HANDLE);
                if (input == IntPtr.Zero || input == new IntPtr(-1)) {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "GetStdHandle failed");
                }
                var down = new INPUT_RECORD {
                    EventType = KEY_EVENT,
                    KeyEvent = new KEY_EVENT_RECORD {
                        bKeyDown = true,
                        wRepeatCount = 1,
                        wVirtualKeyCode = 0x31,
                        wVirtualScanCode = 0x02,
                        UnicodeChar = '1',
                        dwControlKeyState = 0
                    }
                };
                var up = down;
                up.KeyEvent.bKeyDown = false;
                uint written;
                if (!WriteConsoleInput(input, new [] { down, up }, 2, out written) || written != 2) {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "WriteConsoleInput failed");
                }
            }
            finally {
                FreeConsole();
            }
        }
    }
}
'@
}

[CatDesk.ConsoleInput]::SendOne($ProcessId)
