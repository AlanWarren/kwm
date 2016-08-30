#ifndef AXLIB_WINDOW_H
#define AXLIB_WINDOW_H

#include <Carbon/Carbon.h>

enum ax_window_flags
{
    AXWindow_Movable = (1 << 0),
    AXWindow_Resizable = (1 << 1),
    AXWindow_Floating = (1 << 2),
    AXWindow_Minimized = (1 << 3),

    AXWindow_MoveIntrinsic = (1 << 4),
    AXWindow_SizeIntrinsic = (1 << 5),
};

struct ax_window_role
{
    CFTypeRef Role;
    CFTypeRef Subrole;
    CFTypeRef CustomRole;
};

struct ax_application;
struct ax_window
{
    ax_application *Application;
    AXUIElementRef Ref;
    uint32_t ID;

    uint32_t Flags;
    ax_window_role Type;

    CGSize Size;
    CGPoint Position;
    char *Name;
};

inline bool
AXLibHasFlags(ax_window *Window, uint32_t Flag)
{
    bool Result = Window->Flags & Flag;
    return Result;
}

inline void
AXLibAddFlags(ax_window *Window, uint32_t Flag)
{
    Window->Flags |= Flag;
}

inline void
AXLibClearFlags(ax_window *Window, uint32_t Flag)
{
    Window->Flags &= ~Flag;
}

ax_window *AXLibConstructWindow(ax_application *Application, AXUIElementRef WindowRef);
void AXLibDestroyWindow(ax_window *Window);

bool AXLibIsWindowStandard(ax_window *Window);
bool AXLibIsWindowCustom(ax_window *Window);

bool AXLibWindowHasRole(ax_window *Window, CFTypeRef Role);
bool AXLibWindowHasCustomRole(ax_window *Window, CFTypeRef Role);

#endif
