#include "display.h"
#include "event.h"
#include "window.h"
#include "element.h"
#include <Cocoa/Cocoa.h>
#include <stdio.h>

#define internal static
#define CGSDefaultConnection _CGSDefaultConnection()

typedef int CGSConnectionID;
extern "C" CGSConnectionID _CGSDefaultConnection(void);
extern "C" CGSSpaceType CGSSpaceGetType(CGSConnectionID CID, CGSSpaceID SID);
extern "C" CFArrayRef CGSCopyManagedDisplaySpaces(const CGSConnectionID CID);
extern "C" CFArrayRef CGSCopySpacesForWindows(CGSConnectionID CID, CGSSpaceSelector Type, CFArrayRef Windows);
extern "C" bool CGSManagedDisplayIsAnimating(CGSConnectionID CID, CFStringRef DisplayIdentifier);

extern "C" void CGSHideSpaces(CGSConnectionID CID, CFArrayRef Spaces);
extern "C" void CGSShowSpaces(CGSConnectionID CID, CFArrayRef Spaces);
extern "C" void CGSManagedDisplaySetIsAnimating(CGSConnectionID CID, CFStringRef Display, bool Animating);
extern "C" void CGSManagedDisplaySetCurrentSpace(CGSConnectionID CID, CFStringRef Display, CGSSpaceID SpaceID);

extern "C" void CGSRemoveWindowsFromSpaces(CGSConnectionID CID, CFArrayRef Windows, CFArrayRef Spaces);
extern "C" void CGSAddWindowsToSpaces(CGSConnectionID CID, CFArrayRef Windows, CFArrayRef Spaces);

internal std::map<CGDirectDisplayID, ax_display> *Displays;
internal unsigned int MaxDisplayCount = 5;
internal unsigned int ActiveDisplayCount = 0;

/* NOTE(koekeishiya): If the display UUID is stored, return the corresponding
                      CGDirectDisplayID. Otherwise we return 0 */
internal CGDirectDisplayID
AXLibContainsDisplay(CFStringRef DisplayIdentifier)
{
    if(DisplayIdentifier)
    {
        std::map<CGDirectDisplayID, ax_display>::iterator It;
        for(It = Displays->begin(); It != Displays->end(); ++It)
        {
            CFStringRef ActiveIdentifier = It->second.Identifier;
            if(CFStringCompare(DisplayIdentifier, ActiveIdentifier, 0) == kCFCompareEqualTo)
                return It->first;
        }
    }

    return 0;
}

/* NOTE(koekeishiya): If the display UUID is stored, return the corresponding
                      ax_display. Otherwise we return NULL */
internal ax_display *
AXLibDisplay(CFStringRef DisplayIdentifier)
{
    if(DisplayIdentifier)
    {
        std::map<CGDirectDisplayID, ax_display>::iterator It;
        for(It = Displays->begin(); It != Displays->end(); ++It)
        {
            CFStringRef ActiveIdentifier = It->second.Identifier;
            if(CFStringCompare(DisplayIdentifier, ActiveIdentifier, 0) == kCFCompareEqualTo)
                return &It->second;
        }
    }

    return NULL;
}

/* NOTE(koekeishiya): Find the UUID for a given CGDirectDisplayID. */
internal CFStringRef
AXLibGetDisplayIdentifier(CGDirectDisplayID DisplayID)
{
    CFUUIDRef DisplayUUID = CGDisplayCreateUUIDFromDisplayID(DisplayID);
    if(DisplayUUID)
    {
        CFStringRef Identifier = CFUUIDCreateString(NULL, DisplayUUID);
        CFRelease(DisplayUUID);
        return Identifier;
    }

    return NULL;
}

internal inline bool
AXLibDisplayHasSpace(ax_display *Display, CGSSpaceID SpaceID)
{
    bool Result = Display->Spaces.find(SpaceID) != Display->Spaces.end();
    return Result;
}

/* NOTE(koekeishiya): Find the UUID of the active space for a given ax_display. */
internal CFStringRef
AXLibGetActiveSpaceIdentifier(ax_display *Display)
{
    CFStringRef ActiveSpace = NULL;
    NSString *CurrentIdentifier = (__bridge NSString *)Display->Identifier;

    CFArrayRef DisplayDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *DisplayDictionary in (__bridge NSArray *)DisplayDictionaries)
    {
        NSString *DisplayIdentifier = DisplayDictionary[@"Display Identifier"];
        if([DisplayIdentifier isEqualToString:CurrentIdentifier])
        {
            ActiveSpace = (__bridge CFStringRef) [[NSString alloc] initWithString:DisplayDictionary[@"Current Space"][@"uuid"]];
            break;
        }
    }

    CFRelease(DisplayDictionaries);
    return ActiveSpace;
}

/* NOTE(koekeishiya): Find the CGSSpaceID of the active space for a given ax_display. */
internal CGSSpaceID
AXLibGetActiveSpaceID(ax_display *Display)
{
    CGSSpaceID ActiveSpace = 0;
    NSString *CurrentIdentifier = (__bridge NSString *)Display->Identifier;

    CFArrayRef DisplayDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *DisplayDictionary in (__bridge NSArray *)DisplayDictionaries)
    {
        NSString *DisplayIdentifier = DisplayDictionary[@"Display Identifier"];
        if([DisplayIdentifier isEqualToString:CurrentIdentifier])
        {
            ActiveSpace = [DisplayDictionary[@"Current Space"][@"id64"] intValue];
            break;
        }
    }

    CFRelease(DisplayDictionaries);
    return ActiveSpace;
}

internal ax_space
AXLibConstructSpace(CFStringRef Identifier, CGSSpaceID SpaceID, CGSSpaceType SpaceType)
{
    ax_space Space;

    char *IdentifierC = CopyCFStringToC(Identifier, true);
    if(!IdentifierC)
        IdentifierC = CopyCFStringToC(Identifier, false);

    if(IdentifierC)
    {
        Space.Identifier = std::string(IdentifierC);
        free(IdentifierC);
    }

    Space.ID = SpaceID;
    Space.Type = SpaceType;

    return Space;
}

/* NOTE(koekeishiya): Find the active ax_space for a given ax_display. */
ax_space *AXLibGetActiveSpace(ax_display *Display)
{
    CGSSpaceID SpaceID = AXLibGetActiveSpaceID(Display);

    /* NOTE(koekeishiya): This is the first time we see this space. It was most likely created after
                          AXLib was initialized. Create ax_space struct and add to the displays space list. */
    if(!AXLibDisplayHasSpace(Display, SpaceID))
    {
        CFStringRef SpaceUUID = AXLibGetActiveSpaceIdentifier(Display);
        CGSSpaceType SpaceType = CGSSpaceGetType(CGSDefaultConnection, SpaceID);
        Display->Spaces[SpaceID] = AXLibConstructSpace(SpaceUUID, SpaceID, SpaceType);
        CFRelease(SpaceUUID);
    }

    return &Display->Spaces[SpaceID];
}

/* NOTE(koekeishiya): Constructs ax_space structs for every space of a given ax_display. */
internal void
AXLibConstructSpacesForDisplay(ax_display *Display)
{
    NSString *CurrentIdentifier = (__bridge NSString *)Display->Identifier;
    CFArrayRef DisplayDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *DisplayDictionary in (__bridge NSArray *)DisplayDictionaries)
    {
        NSString *DisplayIdentifier = DisplayDictionary[@"Display Identifier"];
        if([DisplayIdentifier isEqualToString:CurrentIdentifier])
        {
            NSDictionary *SpaceDictionaries = DisplayDictionary[@"Spaces"];
            for(NSDictionary *SpaceDictionary in (__bridge NSArray *)SpaceDictionaries)
            {
                CGSSpaceID SpaceID = [SpaceDictionary[@"id64"] intValue];
                CGSSpaceType SpaceType = [SpaceDictionary[@"type"] intValue];
                CFStringRef SpaceUUID = (__bridge CFStringRef) [[NSString alloc] initWithString:SpaceDictionary[@"uuid"]];
                Display->Spaces[SpaceID] = AXLibConstructSpace(SpaceUUID, SpaceID, SpaceType);
                CFRelease(SpaceUUID);
            }
            break;
        }
    }

    CFRelease(DisplayDictionaries);
}

/* NOTE(koekeishiya): CGDirectDisplayID of a display can change when swapping GPUs, but the
                      UUID remain the same. This function performs the CGDirectDisplayID update
                      and repopulates the list of spaces. */
internal inline void
AXLibChangeDisplayID(CGDirectDisplayID OldDisplayID, CGDirectDisplayID NewDisplayID)
{
    if(OldDisplayID == NewDisplayID)
        return;

    ax_display OldDisplay = (*Displays)[OldDisplayID];
    (*Displays)[NewDisplayID] = OldDisplay;
    Displays->erase(OldDisplayID);

    ax_display *Display = &(*Displays)[NewDisplayID];
    Display->ID = NewDisplayID;
    Display->Spaces.clear();
    AXLibConstructSpacesForDisplay(Display);
    Display->Space = AXLibGetActiveSpace(Display);
    Display->PrevSpace = Display->Space;
}

/* NOTE(koekeishiya): Initializes an ax_display for a given CGDirectDisplayID. Also populates the list of spaces. */
internal ax_display
AXLibConstructDisplay(CGDirectDisplayID DisplayID, unsigned int ArrangementID)
{
    ax_display Display = {};

    Display.ID = DisplayID;
    Display.ArrangementID = ArrangementID;
    Display.Identifier = AXLibGetDisplayIdentifier(DisplayID);
    Display.Frame = CGDisplayBounds(DisplayID);
    AXLibConstructSpacesForDisplay(&Display);
    Display.Space = AXLibGetActiveSpace(&Display);
    Display.PrevSpace = Display.Space;

    return Display;
}

/* NOTE(koekeishiya): Updates an ax_display for a given CGDirectDisplayID. */
internal void
AXLibRefreshDisplay(ax_display *Display, CGDirectDisplayID DisplayID, unsigned int ArrangementID)
{
    Display->ArrangementID = ArrangementID;
    Display->Frame = CGDisplayBounds(DisplayID);
}

/* NOTE(koekeishiya): Repopulate map with information about all connected displays. */
internal void
AXLibRefreshDisplays()
{
    CGDirectDisplayID *CGDirectDisplayList = (CGDirectDisplayID *) malloc(sizeof(CGDirectDisplayID) * MaxDisplayCount);
    CGGetActiveDisplayList(MaxDisplayCount, CGDirectDisplayList, &ActiveDisplayCount);

    for(std::size_t Index = 0; Index < ActiveDisplayCount; ++Index)
    {
        CGDirectDisplayID ID = CGDirectDisplayList[Index];
        if(Displays->find(ID) == Displays->end())
        {
            (*Displays)[ID] = AXLibConstructDisplay(ID, Index);
        }
        else
        {
            AXLibRefreshDisplay(&(*Displays)[ID], ID, Index);
        }
    }

    free(CGDirectDisplayList);
}

internal inline void
AXLibAddDisplay(CGDirectDisplayID DisplayID)
{
    CFStringRef DisplayIdentifier = AXLibGetDisplayIdentifier(DisplayID);
    CGDirectDisplayID StoredDisplayID = AXLibContainsDisplay(DisplayIdentifier);
    if(DisplayIdentifier)
        CFRelease(DisplayIdentifier);

    if(!StoredDisplayID)
    {
        /* NOTE(koekeishiya): New display detected. */
    }
    else if(StoredDisplayID != DisplayID)
    {
        /* NOTE(koekeishiya): Display already exists, but the associated CGDirectDisplayID was invalidated.
                              Does this also cause the associated CGSSpaceIDs to reset and is it necessary
                              to reassign these based on the space UUIDS (?) */
        AXLibChangeDisplayID(StoredDisplayID, DisplayID);
    }
    else
    {
        /* NOTE(koekeishiya): For some reason OSX added a display with a CGDirectDisplayID that
                              is still in use by the same display we added earlier (?) */
        return;
    }

    /* NOTE(koekeishiya): Refresh map of connected displays and update exisitng frame bounds. */
    AXLibRefreshDisplays();

    /* TODO(koekeishiya): Should probably pass an identifier for the added display. */
    AXLibConstructEvent(AXEvent_DisplayAdded, NULL, false);
}

internal inline void
AXLibRemoveDisplay(CGDirectDisplayID DisplayID)
{
    CFStringRef DisplayIdentifier = AXLibGetDisplayIdentifier(DisplayID);
    CGDirectDisplayID StoredDisplayID = AXLibContainsDisplay(DisplayIdentifier);
    if(DisplayIdentifier)
        CFRelease(DisplayIdentifier);

    if(StoredDisplayID)
    {
        /* NOTE(koekeishiya): This code-path is not taken (on my machine) when a display is disconnected.
        The call to AXLibGetDisplayIdentifier(..) results in a 'display not found' error, and we end up returning NULL
        causing our StoredDisplayID to be zero.

        This is only non-zero when a fake 'GPU display' is removed, and so we do nothing. */
    }
    else if(Displays->find(DisplayID) != Displays->end())
    {
        if((*Displays)[DisplayID].Identifier)
            CFRelease((*Displays)[DisplayID].Identifier);

        Displays->erase(DisplayID);
    }

    /* NOTE(koekeishiya): Refresh all displays for now. */
    AXLibRefreshDisplays();

    /* TODO(koekeishiya): Should probably pass an identifier for the removed display. */
    AXLibConstructEvent(AXEvent_DisplayRemoved, NULL, false);
}

internal inline void
AXLibResizeDisplay(CGDirectDisplayID DisplayID)
{
    /* NOTE(koekeishiya): Display frames consists of both an origin and size dimension. When a display
                          is resized, we need to refresh the boundary information for all other displays. */
    if(!CGDisplayIsAsleep(DisplayID))
    {
        CFStringRef DisplayIdentifier = AXLibGetDisplayIdentifier(DisplayID);
        AXLibRefreshDisplays();

        ax_display *Display = AXLibDisplay(DisplayIdentifier);
        if(Display)
            AXLibConstructEvent(AXEvent_DisplayResized, Display, false);

        if(DisplayIdentifier)
            CFRelease(DisplayIdentifier);
    }
}

/* NOTE(koekeishiya): Caused by a change in monitor arrangements (?) */
internal inline void
AXLibMoveDisplay(CGDirectDisplayID DisplayID)
{
    /* NOTE(koekeishiya): Display frames consists of both an origin and size dimension. When a display
                          is moved, we need to refresh the boundary information for all other displays. */
    if(!CGDisplayIsAsleep(DisplayID))
    {
        CFStringRef DisplayIdentifier = AXLibGetDisplayIdentifier(DisplayID);
        AXLibRefreshDisplays();

        ax_display *Display = AXLibDisplay(DisplayIdentifier);
        if(Display)
            AXLibConstructEvent(AXEvent_DisplayMoved, Display, false);

        if(DisplayIdentifier)
            CFRelease(DisplayIdentifier);
    }
}


/* NOTE(koekeishiya): Get notified about display changes. */
internal void
AXDisplayReconfigurationCallBack(CGDirectDisplayID DisplayID, CGDisplayChangeSummaryFlags Flags, void *UserInfo)
{
    AXLibPauseEventLoop();

#ifdef DEBUG_BUILD
    static int DisplayCallbackCount = 0;
    printf("%d: Begin Display Callback\n", ++DisplayCallbackCount);
#endif

    if(Flags & kCGDisplayAddFlag)
    {
#ifdef DEBUG_BUILD
        printf("%d: Display detected\n", DisplayID);
#endif
        AXLibAddDisplay(DisplayID);
    }

    if(Flags & kCGDisplayRemoveFlag)
    {
#ifdef DEBUG_BUILD
        printf("%d: Display removed\n", DisplayID);
#endif
        AXLibRemoveDisplay(DisplayID);
    }

    if(Flags & kCGDisplayDesktopShapeChangedFlag)
    {
#ifdef DEBUG_BUILD
        printf("%d: Display resolution changed\n", DisplayID);
#endif
        AXLibResizeDisplay(DisplayID);
    }

    if(Flags & kCGDisplayMovedFlag)
    {
#ifdef DEBUG_BUILD
        printf("%d: Display moved\n", DisplayID);
#endif
        AXLibMoveDisplay(DisplayID);
    }

#ifdef DEBUG_BUILD
    if(Flags & kCGDisplaySetMainFlag)
    {
       printf("%d: Display became main\n", DisplayID);
    }

    if(Flags & kCGDisplaySetModeFlag)
    {
       printf("%d: Display changed mode\n", DisplayID);
    }

    if(Flags & kCGDisplayEnabledFlag)
    {
       printf("%d: Display enabled\n", DisplayID);
    }

    if(Flags & kCGDisplayDisabledFlag)
    {
        printf("%d: Display disabled\n", DisplayID);
    }

    printf("%d: End Display Callback\n", DisplayCallbackCount);
#endif

    AXLibResumeEventLoop();
}

/* NOTE(koekeishiya): Populate map with information about all connected displays. */
internal void
AXLibActiveDisplays()
{
    CGDirectDisplayID *CGDirectDisplayList = (CGDirectDisplayID *) malloc(sizeof(CGDirectDisplayID) * MaxDisplayCount);
    CGGetActiveDisplayList(MaxDisplayCount, CGDirectDisplayList, &ActiveDisplayCount);

    for(std::size_t Index = 0; Index < ActiveDisplayCount; ++Index)
    {
        CGDirectDisplayID ID = CGDirectDisplayList[Index];
        (*Displays)[ID] = AXLibConstructDisplay(ID, Index);
    }

    free(CGDirectDisplayList);
    CGDisplayRegisterReconfigurationCallback(AXDisplayReconfigurationCallBack, NULL);
}

/* NOTE(koekeishiya): The main display is the display which currently holds the window that accepts key-input. */
ax_display *AXLibMainDisplay()
{
    NSDictionary *ScreenDictionary = [[NSScreen mainScreen] deviceDescription];
    NSNumber *ScreenID = [ScreenDictionary objectForKey:@"NSScreenNumber"];
    CGDirectDisplayID MainDisplay = [ScreenID unsignedIntValue];
    if(Displays->find(MainDisplay) == Displays->end())
        AXLibAddDisplay(MainDisplay);

    return &(*Displays)[MainDisplay];
}

/* NOTE(koekeishiya): The display that holds the cursor. */
ax_display *AXLibCursorDisplay()
{
    CGEventRef Event = CGEventCreate(NULL);
    CGPoint Cursor = CGEventGetLocation(Event);
    CFRelease(Event);

    ax_display *Result = NULL;
    std::map<CGDirectDisplayID, ax_display>::iterator It;
    for(It = Displays->begin(); It != Displays->end(); ++It)
    {
        ax_display *Display = &It->second;
        if(CGRectContainsPoint(Display->Frame, Cursor))
        {
            Result = Display;
            break;
        }
    }

    return Result;
}

/* NOTE(koekeishiya): The display that holds the largest portion of the given window. */
ax_display *AXLibWindowDisplay(ax_window *Window)
{
    CGRect Frame = { Window->Position, Window->Size };
    CGFloat HighestVolume = 0;
    ax_display *BestDisplay = NULL;

    std::map<CGDirectDisplayID, ax_display>::iterator It;
    for(It = Displays->begin(); It != Displays->end(); ++It)
    {
        ax_display *Display = &It->second;
        CGRect Intersection = CGRectIntersection(Frame, Display->Frame);
        CGFloat Volume = Intersection.size.width * Intersection.size.height;

        if(Volume > HighestVolume)
        {
            HighestVolume = Volume;
            BestDisplay = Display;
        }
    }

    return BestDisplay ? BestDisplay : AXLibMainDisplay();
}


ax_display *AXLibNextDisplay(ax_display *Display)
{
    unsigned int NextDisplayID = Display->ArrangementID + 1 >= ActiveDisplayCount ? 0 : Display->ArrangementID + 1;
    std::map<CGDirectDisplayID, ax_display>::iterator DisplayIt;
    for(DisplayIt = Displays->begin(); DisplayIt != Displays->end(); ++DisplayIt)
    {
        ax_display *CurrentDisplay = &DisplayIt->second;
        if(CurrentDisplay->ArrangementID == NextDisplayID)
            return CurrentDisplay;
    }

    return NULL;
}

ax_display *AXLibPreviousDisplay(ax_display *Display)
{
    unsigned int PrevDisplayID = Display->ArrangementID == 0 ? ActiveDisplayCount - 1 : Display->ArrangementID - 1;
    std::map<CGDirectDisplayID, ax_display>::iterator DisplayIt;
    for(DisplayIt = Displays->begin(); DisplayIt != Displays->end(); ++DisplayIt)
    {
        ax_display *CurrentDisplay = &DisplayIt->second;
        if(CurrentDisplay->ArrangementID == PrevDisplayID)
            return CurrentDisplay;
    }

    return NULL;
}

ax_display *AXLibArrangementDisplay(unsigned int ArrangementID)
{
    std::map<CGDirectDisplayID, ax_display>::iterator DisplayIt;
    for(DisplayIt = Displays->begin(); DisplayIt != Displays->end(); ++DisplayIt)
    {
        ax_display *Display = &DisplayIt->second;
        if(Display->ArrangementID == ArrangementID)
            return Display;
    }

    return NULL;
}

unsigned int AXLibDesktopIDFromCGSSpaceID(ax_display *Display, CGSSpaceID SpaceID)
{
    unsigned int Result = 0;
    NSString *CurrentIdentifier = (__bridge NSString *)Display->Identifier;

    CFArrayRef ScreenDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *ScreenDictionary in (__bridge NSArray *)ScreenDictionaries)
    {
        int SpaceIndex = 1;
        NSString *ScreenIdentifier = ScreenDictionary[@"Display Identifier"];
        if([ScreenIdentifier isEqualToString:CurrentIdentifier])
        {
            NSArray *SpaceDictionaries = ScreenDictionary[@"Spaces"];
            for(NSDictionary *SpaceDictionary in (__bridge NSArray *)SpaceDictionaries)
            {
                if(SpaceID == [SpaceDictionary[@"id64"] intValue])
                {
                    Result = SpaceIndex;
                    break;
                }

                ++SpaceIndex;
            }
            break;
        }
    }

    CFRelease(ScreenDictionaries);
    return Result;
}

CGSSpaceID AXLibCGSSpaceIDFromDesktopID(ax_display *Display, unsigned int DesktopID)
{
    CGSSpaceID Result = 0;
    NSString *CurrentIdentifier = (__bridge NSString *)Display->Identifier;

    CFArrayRef ScreenDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *ScreenDictionary in (__bridge NSArray *)ScreenDictionaries)
    {
        int SpaceIndex = 1;
        NSString *ScreenIdentifier = ScreenDictionary[@"Display Identifier"];
        if([ScreenIdentifier isEqualToString:CurrentIdentifier])
        {
            NSArray *SpaceDictionaries = ScreenDictionary[@"Spaces"];
            for(NSDictionary *SpaceDictionary in (__bridge NSArray *)SpaceDictionaries)
            {
                if(SpaceIndex == DesktopID)
                {
                    Result = [SpaceDictionary[@"id64"] intValue];
                    break;
                }
                ++SpaceIndex;
            }
            break;
        }
    }

    CFRelease(ScreenDictionaries);
    return Result;
}

unsigned int AXLibDisplaySpacesCount(ax_display *Display)
{
    unsigned int Result = 0;
    NSString *CurrentIdentifier = (__bridge NSString *)Display->Identifier;

    CFArrayRef ScreenDictionaries = CGSCopyManagedDisplaySpaces(CGSDefaultConnection);
    for(NSDictionary *ScreenDictionary in (__bridge NSArray *)ScreenDictionaries)
    {
        NSString *ScreenIdentifier = ScreenDictionary[@"Display Identifier"];
        if ([ScreenIdentifier isEqualToString:CurrentIdentifier])
        {
            NSArray *Spaces = ScreenDictionary[@"Spaces"];
            Result = CFArrayGetCount((__bridge CFArrayRef)Spaces);
        }
    }

    CFRelease(ScreenDictionaries);
    return Result;
}

/* NOTE(koekeishiya): Given an abitrary CGSSpaceID, return the ax_display it belongs to. */
ax_display * AXLibSpaceDisplay(CGSSpaceID SpaceID)
{
    ax_display *Result = NULL;

    std::map<CGDirectDisplayID, ax_display>::iterator It;
    for(It = Displays->begin(); It != Displays->end(); ++It)
    {
        ax_display *Display = &It->second;
        if(Display->Spaces.find(SpaceID) != Display->Spaces.end())
        {
            Result = Display;
            break;
        }
    }

    return Result;
}

bool AXLibIsSpaceTransitionInProgress()
{
    bool Result = false;

    std::map<CGDirectDisplayID, ax_display>::iterator It;
    for(It = Displays->begin(); It != Displays->end(); ++It)
    {
        ax_display *Display = &It->second;
        Result = Result || CGSManagedDisplayIsAnimating(CGSDefaultConnection, Display->Identifier);
    }

    return Result;
}

/* NOTE(koekeishiya): Performs a space transition without the animation. */
void AXLibSpaceTransition(ax_display *Display, CGSSpaceID SpaceID)
{
    NSArray *NSArraySourceSpace = @[ @(Display->Space->ID) ];
    NSArray *NSArrayDestinationSpace = @[ @(SpaceID) ];
    CGSManagedDisplaySetIsAnimating(CGSDefaultConnection, Display->Identifier, true);

    CGSShowSpaces(CGSDefaultConnection, (__bridge CFArrayRef)NSArrayDestinationSpace);
    CGSHideSpaces(CGSDefaultConnection, (__bridge CFArrayRef)NSArraySourceSpace);
    [NSArraySourceSpace release];
    [NSArrayDestinationSpace release];

    CGSManagedDisplaySetCurrentSpace(CGSDefaultConnection, Display->Identifier, SpaceID);
    CGSManagedDisplaySetIsAnimating(CGSDefaultConnection, Display->Identifier, false);
}

void AXLibSpaceAddWindow(CGSSpaceID SpaceID, uint32_t WindowID)
{
    NSArray *NSArrayWindow = @[ @(WindowID) ];
    NSArray *NSArrayDestinationSpace = @[ @(SpaceID) ];
    CGSAddWindowsToSpaces(CGSDefaultConnection, (__bridge CFArrayRef)NSArrayWindow, (__bridge CFArrayRef)NSArrayDestinationSpace);
    [NSArrayWindow release];
    [NSArrayDestinationSpace release];
}

void AXLibSpaceRemoveWindow(CGSSpaceID SpaceID, uint32_t WindowID)
{
    NSArray *NSArrayWindow = @[ @(WindowID) ];
    NSArray *NSArraySourceSpace = @[ @(SpaceID) ];
    CGSRemoveWindowsFromSpaces(CGSDefaultConnection, (__bridge CFArrayRef)NSArrayWindow, (__bridge CFArrayRef)NSArraySourceSpace);
    [NSArrayWindow release];
    [NSArraySourceSpace release];
}

bool AXLibSpaceHasWindow(ax_window *Window, CGSSpaceID SpaceID)
{
    bool Result = false;
    NSArray *NSArrayWindow = @[ @(Window->ID) ];
    CFArrayRef Spaces = CGSCopySpacesForWindows(CGSDefaultConnection, kCGSSpaceAll, (__bridge CFArrayRef)NSArrayWindow);
    int NumberOfSpaces = CFArrayGetCount(Spaces);
    for(int Index = 0; Index < NumberOfSpaces; ++Index)
    {
        NSNumber *ID = (__bridge NSNumber *)CFArrayGetValueAtIndex(Spaces, Index);
        if(SpaceID == [ID intValue])
        {
            Result = true;
            break;
        }
    }

    CFRelease(Spaces);
    [NSArrayWindow release];
    return Result;
}

bool AXLibStickyWindow(ax_window *Window)
{
    bool Result = false;
    NSArray *NSArrayWindow = @[ @(Window->ID) ];
    CFArrayRef Spaces = CGSCopySpacesForWindows(CGSDefaultConnection, kCGSSpaceAll, (__bridge CFArrayRef)NSArrayWindow);
    int NumberOfSpaces = CFArrayGetCount(Spaces);
    Result = NumberOfSpaces > 1;

    CFRelease(Spaces);
    [NSArrayWindow release];
    return Result;
}

bool AXLibDisplayHasSeparateSpaces()
{
    return [NSScreen screensHaveSeparateSpaces];
}

void AXLibInitializeDisplays(std::map<CGDirectDisplayID, ax_display> *AXDisplays)
{
    Displays = AXDisplays;
    AXLibActiveDisplays();
}
