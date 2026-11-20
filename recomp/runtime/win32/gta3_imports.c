/* Win32 functions Grand Theft Auto III calls that the earlier ports never did (generic; built for every edition). */
#include "w32.h"
#include <sys/statvfs.h>
#include <unistd.h>

extern char w32_cwd[1024], w32_drive_c[];
int w32_wait_one(Ctx *c, uint32_t h, uint32_t ms);

/* GetDiskFreeSpaceA(root, sectors per cluster *, bytes per sector *, free clusters *, total clusters *): the data
 * folder's volume, in 4 KB clusters, capped below 2 GB as Windows 9x-era callers expect from this call */
IMPL(kernel32, GetDiskFreeSpaceA)
{
    struct statvfs v; uint64_t free_b = 1ull << 30, total_b = 1ull << 31;
    if (!statvfs(w32_drive_c, &v)) { free_b = (uint64_t)v.f_bavail * v.f_frsize; total_b = (uint64_t)v.f_blocks * v.f_frsize; }
    uint64_t cap = 0x7fff0000ull; if (free_b > cap) free_b = cap; if (total_b > cap) total_b = cap;
    if (ARG(1)) rt_w32(G_MEM, ARG(1), 8); if (ARG(2)) rt_w32(G_MEM, ARG(2), 512);
    if (ARG(3)) rt_w32(G_MEM, ARG(3), (uint32_t)(free_b / 4096)); if (ARG(4)) rt_w32(G_MEM, ARG(4), (uint32_t)(total_b / 4096));
    RET(1, 5);
}
/* SetCurrentDirectoryA(path): relative paths are taken from here (files.c) */
IMPL(kernel32, SetCurrentDirectoryA)
{
    const char *p = GS(ARG(0)); char full[1024];
    if (((p[0] | 32) >= 'a' && (p[0] | 32) <= 'z') && p[1] == ':') snprintf(full, sizeof full, "%s", p);
    else if (p[0] == '\\' || p[0] == '/') snprintf(full, sizeof full, "C:%s", p);
    else snprintf(full, sizeof full, "%s\\%s", w32_cwd, p);
    size_t n = strlen(full); while (n > 3 && (full[n - 1] == '\\' || full[n - 1] == '/')) full[--n] = 0;
    snprintf(w32_cwd, sizeof w32_cwd, "%s", full);
    RET(1, 1);
}
IMPL(kernel32, GetSystemDefaultLCID) { RET(0x409, 0); }              /* English (United States) */
IMPL(kernel32, WaitForSingleObjectEx)                                   /* (handle, ms, alertable): no APCs here */
{
    int r = w32_wait_one(c, ARG(0), ARG(1));
    if (r < 0) { w32_set_last_error(c, 6); RET(0xffffffffu, 3); }
    RET((uint32_t)r, 3);
}
/* GetOverlappedResult(file, OVERLAPPED *, bytes *, wait): file reads here complete at once, so the count is the
 * OVERLAPPED's InternalHigh (set when the read was made) */
IMPL(kernel32, GetOverlappedResult)
{
    uint32_t o = ARG(1); if (ARG(2)) rt_w32(G_MEM, ARG(2), o ? rt_r32(G_MEM, o + 4) : 0);
    RET(1, 4);
}
IMPL(user32, ClipCursor) { RET(1, 1); }                                 /* the host keeps the pointer in the window */
/* GetWindowPlacement(hwnd, WINDOWPLACEMENT *): shown normally, at the window's rectangle */
IMPL(user32, GetWindowPlacement)
{
    uint32_t p = ARG(1); if (!p) RET(0, 2);
    extern int w32_screen_w, w32_screen_h;
    uint32_t v[11] = {44, 0, 1 /* SW_SHOWNORMAL */, 0xffffffffu, 0xffffffffu, 0xffffffffu, 0xffffffffu, 0, 0, (uint32_t)w32_screen_w, (uint32_t)w32_screen_h};
    memcpy(GP(p), v, 44); RET(1, 2);
}
IMPL(user32, WaitMessage) { usleep(1000); RET(1, 0); }
